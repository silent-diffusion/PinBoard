//
//  VideoTranscripts.swift  —  PinBoard
//
//  What is said in a video, written down on the device (round 15). A video that has a sound track
//  is listened to once it is in place and converted: one at a time, at low priority, behind the AI
//  and the conversions. The words go into the pin's `transcript` and into its note (where the
//  person reads them), and the AI then names and tags the video from them first, the way it does
//  from a link's text. Nothing is sent anywhere: Apple's Speech framework works on the device
//  (iOS 26 and later: the new SpeechAnalyzer; iOS 17 to 25: SFSpeechRecognizer, told to stay on
//  the device).
//
//  What is in here:
//    TranscriptText        pure rules: tidying what the recogniser gave, the words a transcript
//                          offers as tags, the lines the status shows
//    TranscriptNotes       pure rules: putting a transcript into a note (never twice), and telling
//                          the person's own words from it again
//    Pin extension         `hasSpokenWords`, `spokenText(limit:)`, `personalNote`
//    SpeechTranscription   the recogniser: one video's file in, an `Outcome` out. The store calls it
//                          through `SpeechRecogniser`, which the tests replace
//    LibraryStore          the background run: which videos wait, the status, the bookkeeping
//

import Foundation
import AVFoundation
import NaturalLanguage
import Speech
import UIKit

// MARK: - The words of a transcript

/// Pure rules about the words a recogniser gives back.
enum TranscriptText {

    /// Fewer words than this is not speech worth writing down (a cough, a "hm", music the
    /// recogniser took for a word).
    nonisolated static let shortestWordCount = 3
    /// A transcript is cut here, at the end of a word, and "…" is added: a two-hour talk would
    /// otherwise fill the note with a book.
    nonisolated static let longestTranscript = 20_000
    /// A paragraph ends at the first sentence end after this many characters, so a long talk reads
    /// as paragraphs and not as one wall of words.
    nonisolated static let paragraphLength = 600
    /// How much of a transcript the AI names a video from (the first part says what it is about).
    nonisolated static let titleLimit = 1_500
    /// How much of a transcript the AI takes key words (tags) from.
    nonisolated static let tagLimit = 4_000
    /// How many characters of a note (the transcript's, too) search matches word by word. Matching
    /// every word of a long talk against every search term would make search slow; the exact-phrase
    /// check still sees all of it.
    nonisolated static let searchLimit = 4_000

    /// What the recogniser said, as one readable text: the pieces joined, spaces and line breaks
    /// squeezed, then cut into paragraphs at sentence ends. nil when there is nothing worth keeping
    /// (fewer than `shortestWordCount` words, or no letter at all): the video has no speech.
    nonisolated static func cleaned(_ pieces: [String]) -> String? {
        let squeezed = TranscriptNotes.squeezed(pieces.joined(separator: " "))
        guard squeezed.contains(where: { (character: Character) -> Bool in character.isLetter }) else { return nil }
        guard wordCount(of: squeezed, upTo: shortestWordCount) >= shortestWordCount else { return nil }
        return capped(inParagraphs(squeezed))
    }

    /// How many words a text has, by the rules of the language (Japanese and Chinese have no spaces
    /// between words, so counting spaces would call a whole sentence one word). Counting stops at
    /// `limit`: that many is all the caller wants to know about.
    nonisolated static func wordCount(of text: String, upTo limit: Int = Int.max) -> Int {
        guard !text.isEmpty else { return 0 }
        let tokenizer = NLTokenizer(unit: .word)
        tokenizer.string = text
        var count = 0
        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { (_: Range<String.Index>, _: NLTokenizer.Attributes) -> Bool in
            count += 1
            return count < limit
        }
        return count
    }

    /// `text` (one line of squeezed words) cut into paragraphs: each ends at the first sentence end
    /// after `paragraphLength` characters. A stretch with no sentence end at all (a recogniser that
    /// gave no full stops) is cut at a space instead, so it never stays one wall.
    nonisolated private static func inParagraphs(_ text: String) -> String {
        var paragraphs: [String] = []
        var current = ""
        for sentence in sentences(of: text) {
            for piece in splitIfTooLong(sentence) {
                current = current.isEmpty ? piece : current + " " + piece
                if current.count >= paragraphLength {
                    paragraphs.append(current)
                    current = ""
                }
            }
        }
        if !current.isEmpty { paragraphs.append(current) }
        return paragraphs.joined(separator: "\n\n")
    }

    /// The sentences of a text, each trimmed. A sentence ends at ". ", "! ", "? " or "… " (a full
    /// stop inside "3.5" or "e.g." does not end one) and, in Chinese and Japanese, at "。", "！", "？".
    nonisolated private static func sentences(of text: String) -> [String] {
        let characters: [Character] = Array(text)
        var result: [String] = []
        var current = ""
        for (index, character) in characters.enumerated() {
            current.append(character)
            var ends = false
            if "。！？".contains(character) {
                ends = true
            } else if ".!?…".contains(character) {
                ends = index + 1 >= characters.count || characters[index + 1].isWhitespace
            }
            if ends {
                result.append(current.trimmingCharacters(in: .whitespacesAndNewlines))
                current = ""
            }
        }
        let rest = current.trimmingCharacters(in: .whitespacesAndNewlines)
        if !rest.isEmpty { result.append(rest) }
        return result.filter { (sentence: String) -> Bool in !sentence.isEmpty }
    }

    /// A very long "sentence" (no full stops in sight) in pieces of about `paragraphLength`
    /// characters, each cut at a space where one can be found.
    nonisolated private static func splitIfTooLong(_ sentence: String) -> [String] {
        guard sentence.count > paragraphLength * 2 else { return [sentence] }
        var pieces: [String] = []
        var rest = Substring(sentence)
        while rest.count > paragraphLength * 2 {
            let limit = rest.index(rest.startIndex, offsetBy: paragraphLength)
            let space = rest[limit...].firstIndex(where: { (character: Character) -> Bool in character.isWhitespace })
            let cut = space ?? limit
            pieces.append(String(rest[..<cut]).trimmingCharacters(in: .whitespacesAndNewlines))
            rest = rest[cut...]
        }
        let last = String(rest).trimmingCharacters(in: .whitespacesAndNewlines)
        if !last.isEmpty { pieces.append(last) }
        return pieces
    }

    /// `text` cut at `longestTranscript` characters (at the end of a word when one is near) with
    /// "…" after it; shorter text stays as it is.
    nonisolated private static func capped(_ text: String) -> String {
        shortened(text, to: longestTranscript)
    }

    /// `text` cut at `limit` characters — at the end of a word when one is within 200 characters of
    /// the cut — with "…" after it; shorter text stays as it is.
    nonisolated static func shortened(_ text: String, to limit: Int) -> String {
        guard limit > 0, text.count > limit else { return text }
        let end = text.index(text.startIndex, offsetBy: limit)
        var head = text[..<end]
        let nearEnd = text.index(end, offsetBy: -min(200, limit), limitedBy: text.startIndex) ?? text.startIndex
        if let space = head[nearEnd...].lastIndex(where: { (character: Character) -> Bool in character.isWhitespace }) {
            head = head[..<space]
        }
        return String(head).trimmingCharacters(in: .whitespacesAndNewlines) + "…"
    }

    // MARK: Words for tags

    /// Words that carry no meaning in speech (small words, "um", "gonna", "you know"): taken out
    /// before key words are picked, so a talk's tags are what it is about and not how it is said.
    /// English only; in another language nothing is taken out (the words are used as they are).
    nonisolated static let fillerWords: Set<String> = [
        "a", "about", "above", "actually", "after", "again", "all", "alright", "also", "although", "always", "am", "an", "and",
        "any", "anyone", "anything", "are", "around", "as", "at", "back", "basically", "be", "because", "been", "before",
        "being", "below", "between", "bit", "both", "but", "by", "bye", "can", "come", "comes", "could", "day", "did", "do",
        "does", "doing", "done", "down", "each", "else", "even", "ever", "every", "everybody", "everyone", "everything",
        "few", "first", "for", "from", "get", "gets", "getting", "go", "goes", "going", "gonna", "gotta", "got", "guys",
        "had", "has", "have", "having", "he", "hello", "her", "here", "hey", "hi", "him", "his", "hmm", "honestly", "how",
        "if", "in", "into", "is", "it", "its", "just", "kind", "kinda", "know", "let", "lets", "like", "little", "look",
        "looking", "looks", "lot", "lots", "make", "makes", "making", "many", "may", "maybe", "me", "mean", "might", "more",
        "most", "much", "must", "my", "need", "needs", "next", "no", "nope", "not", "nothing", "now", "of", "off", "ok",
        "okay", "on", "once", "one", "only", "or", "other", "our", "out", "over", "own", "people", "pretty", "put", "really",
        "right", "said", "same", "say", "saying", "says", "see", "she", "should", "so", "some", "someone", "something",
        "sort", "sorta", "still", "stuff", "subscribe", "sure", "take", "than", "thank", "thanks", "that", "the", "their",
        "them", "then", "there", "these", "they", "thing", "things", "think", "this", "those", "though", "through", "time",
        "to", "today", "too", "totally", "two", "um", "uh", "under", "until", "up", "us", "very", "video", "videos", "want",
        "wanna", "wants", "was", "way", "we", "well", "went", "were", "what", "when", "where", "which", "while", "who",
        "why", "will", "with", "would", "yeah", "yes", "yep", "you", "your", "youre"
    ]

    /// A transcript as plain words for picking key words from (`VisionAnalyzer.keywords`): in
    /// lower case, "don't" and "that's" without their endings, and every word of `fillerWords`
    /// left out.
    nonisolated static func keywordText(of transcript: String) -> String {
        let withoutEndings = transcript.replacingOccurrences(of: "(?i)n['’]t\\b|['’](s|re|ve|ll|d|m)\\b", with: "", options: .regularExpression)
        let words: [String] = withoutEndings.lowercased().components(separatedBy: CharacterSet.alphanumerics.inverted)
        let kept: [String] = words.filter { (word: String) -> Bool in !word.isEmpty && !fillerWords.contains(word) }
        return kept.joined(separator: " ")
    }

    // MARK: Lines the status shows

    /// "Transcribing 2 of 5…" (Settings › Videos while a run goes on).
    nonisolated static func progressLine(number: Int, of total: Int) -> String {
        "Transcribing \(number) of \(max(total, number))…"
    }

    /// The first time, the language files come down before anything is written (it can take a while).
    nonisolated static let preparingLine = "Preparing the speech recogniser…"

    /// "Transcribe existing videos" when no video is waiting.
    nonisolated static let nothingWaitingLine = "No videos are waiting to be written down."

    nonisolated static func unsupportedLine(language: String, device: String) -> String {
        "Speech in \(language) isn't supported on this \(device)."
    }

    nonisolated static func notAllowedLine(device: String) -> String {
        "Speech recognition isn't available to PinBoard on this \(device). Allow it in Settings › Privacy & Security › Speech Recognition."
    }

    /// iOS 17 to 25 and the app has no "Speech Recognition" usage description: there is nothing in
    /// Settings to allow (an app that never asked has no entry there), so the line does not send the
    /// person looking for one. The new recogniser of iOS 26 asks for nothing.
    nonisolated static func needsNewerSystemLine(device: String) -> String {
        "Writing down speech needs iOS 26 or later on this \(device)."
    }

    /// What a run says at its end when some videos could not be listened to (a file the device can't
    /// read, a recogniser that never answered). Those videos are not tried again by themselves — only
    /// the Settings button tries them again, so the line says so.
    nonisolated static func failedLine(count: Int) -> String {
        let videos = count == 1 ? "1 video" : "\(count) videos"
        return "\(videos) couldn't be listened to — Transcribe existing videos tries again."
    }

    nonisolated static func needsDownloadLine(language: String) -> String {
        "The speech files for \(language) have to be downloaded first. Turn off Offline mode to let that happen."
    }

    nonisolated static func downloadFailedLine(language: String) -> String {
        "The speech files for \(language) could not be downloaded. Check the internet connection and try again."
    }

    /// The name of a locale's language, in the device's own language ("English").
    nonisolated static func languageName(of locale: Locale) -> String {
        let code = String(locale.identifier.prefix(while: { (character: Character) -> Bool in character != "_" && character != "-" }))
        return locale.localizedString(forLanguageCode: code) ?? locale.identifier
    }
}

// MARK: - The transcript in the note

/// Putting a transcript into a pin's note, and finding the person's own words in it again.
enum TranscriptNotes {

    /// The word that starts the transcript when the note has text of its own.
    nonisolated static let heading = "Transcript:"

    /// `note` with the transcript in it. An empty note becomes the transcript itself; a note with
    /// text keeps it and gets a blank line, "Transcript:" and the words after it. A note that has
    /// the words already (also with other spacing, or after "Transcript:") stays as it is — the
    /// transcript is never in a note twice.
    nonisolated static func merged(note: String, transcript: String) -> String {
        let words = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !words.isEmpty else { return note }
        let own = note.trimmingCharacters(in: .whitespacesAndNewlines)
        if own.isEmpty { return words }
        if squeezed(note).contains(squeezed(words)) { return note }
        return own + "\n\n" + heading + "\n" + words
    }

    /// The part of `note` the person wrote: the transcript block `merged` added (or a note that is
    /// only the transcript) taken out. A note whose transcript the person changed by hand cannot be
    /// told apart: it is returned as it is.
    nonisolated static func personalPart(of note: String, transcript: String?) -> String {
        guard let transcript else { return note }
        let words = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !words.isEmpty else { return note }
        if squeezed(note) == squeezed(words) { return "" }
        let block = "\n\n" + heading + "\n" + words
        if let range = note.range(of: block, options: .backwards) {
            return (String(note[..<range.lowerBound]) + String(note[range.upperBound...])).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let range = note.range(of: words) {
            return (String(note[..<range.lowerBound]) + String(note[range.upperBound...])).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return note
    }

    /// `text` with every run of spaces and line breaks made one space (to compare two texts that
    /// differ only in their spacing).
    nonisolated static func squeezed(_ text: String) -> String {
        text.split(whereSeparator: { (character: Character) -> Bool in character.isWhitespace }).joined(separator: " ")
    }
}

extension Pin {
    /// A video with a transcript: the words said in it are text the AI can name and tag it from.
    var hasSpokenWords: Bool {
        guard isVideo, let transcript else { return false }
        return !transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// The start of what was said in the video (at most `limit` characters); "" when it has no transcript.
    func spokenText(limit: Int) -> String {
        guard hasSpokenWords, let transcript else { return "" }
        return transcript.count > limit ? String(transcript.prefix(limit)) : transcript
    }

    /// The note without the transcript block: what the person wrote themselves (the AI and search
    /// treat the person's words and the recogniser's differently).
    var personalNote: String {
        TranscriptNotes.personalPart(of: note, transcript: transcript)
    }
}

// MARK: - The recogniser

/// What listens to one video: its file, the language to expect, whether the language files may be
/// downloaded now (not in Offline mode), and a call to make with true when it has to wait for that
/// download and with false when the download is over (the status says so meanwhile). The store uses
/// `SpeechTranscription.standard`; the tests put a fake in its place (the real one cannot run
/// without a device).
typealias SpeechRecogniser = @Sendable (_ file: URL, _ locale: Locale, _ mayDownload: Bool,
                                        _ preparing: @escaping @Sendable (_ isPreparing: Bool) -> Void) async -> SpeechTranscription.Outcome

/// Listens to the sound of a video with Apple's Speech framework, all on the device.
enum SpeechTranscription {

    /// How listening to one video ended.
    enum Outcome: Equatable, Sendable {
        /// The words, tidied (`TranscriptText.cleaned`).
        case text(String)
        /// There was a sound track, but no speech worth writing down.
        case noSpeech
        /// The device has no speech recogniser for the language it is set to.
        case unsupportedLanguage
        /// The language files are not on the device yet and may not be downloaded now (Offline mode).
        case needsDownload
        /// The language files had to come down and could not (no connection, no room): the run stops, the videos wait.
        case downloadFailed
        /// The person (or the system) does not let the app use speech recognition (the iOS 17 to 25 way).
        case notAllowed
        /// iOS 17 to 25 and the app has no "Speech Recognition" usage description, so nothing can be asked
        /// (asking would stop the app) and there is nothing to allow in Settings: it needs iOS 26 or later.
        case needsNewerSystem
        /// Something went wrong (the file, the recogniser, the time it took): the video is marked as listened
        /// to, so it is not tried again at every launch; only the Settings button tries it again.
        case failed
    }

    /// The real recogniser, as a value the store can hold (and tests can replace).
    nonisolated static let standard: SpeechRecogniser = {
        (file: URL, locale: Locale, mayDownload: Bool, preparing: @escaping @Sendable (Bool) -> Void) async -> Outcome in
        await SpeechTranscription.transcribe(fileURL: file, locale: locale, mayDownload: mayDownload, preparing: preparing)
    }

    /// How long one video may take before it is given up: four times its length, and at least a
    /// quarter of an hour; half an hour more when the language files may have to come down first.
    /// (A recogniser that hangs would otherwise hold every video behind it.)
    nonisolated static func timeout(forDuration seconds: Double, mayDownload: Bool) -> TimeInterval {
        let length = seconds.isFinite ? max(0, seconds) : 0
        let listening = max(900, length * 4)
        return min(listening + (mayDownload ? 1_800 : 0), 43_200)
    }

    /// Waits `seconds` of time the app spends running, in small steps. A step that came much later
    /// than it should have — the app was suspended while another app was in front, or the iPad slept —
    /// counts for only `longestGap` seconds, so a recogniser is not given up on because the person
    /// left the app for an hour in the middle of a video. False when the waiting task is stopped first.
    /// (`now` is the clock in seconds; the tests put a jumping one in its place.)
    nonisolated static func sleepWhileRunning(for seconds: TimeInterval, step: TimeInterval = 5, longestGap: TimeInterval = 10,
                                              now: @Sendable () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }) async -> Bool {
        var left = max(0, seconds)
        var last = now()
        while left > 0 {
            let pause = max(0.001, min(left, step))
            do {
                try await Task.sleep(nanoseconds: UInt64(pause * 1_000_000_000))
            } catch {
                return false
            }
            let current = now()
            left -= min(max(0, current - last), longestGap)
            last = current
        }
        return !Task.isCancelled
    }

    /// Runs `recognise` for one video with a time limit and in the background, at low priority.
    /// The first answer wins: the recogniser's, or `.failed` when `timeout` seconds of running time
    /// have gone (`sleepWhileRunning`), or when the waiting task is stopped (the recogniser is then
    /// told to stop too). Only plain values cross: the file's address, the language, flags.
    nonisolated static func listen(using recognise: @escaping SpeechRecogniser, file: URL, locale: Locale, mayDownload: Bool,
                                   timeout: TimeInterval, preparing: @escaping @Sendable (Bool) -> Void) async -> Outcome {
        let box = FirstAnswer()
        let work = Task.detached(priority: .utility) { () -> Void in
            let outcome = await recognise(file, locale, mayDownload, preparing)
            box.give(outcome)
        }
        let timer = Task.detached(priority: .utility) { () -> Void in
            guard await SpeechTranscription.sleepWhileRunning(for: timeout) else { return }
            box.give(.failed)
            work.cancel()
        }
        let outcome: Outcome = await withTaskCancellationHandler {
            await box.wait()
        } onCancel: {
            box.give(.failed)
            work.cancel()
            timer.cancel()
        }
        timer.cancel()
        return outcome
    }

    /// One video's words. `fileURL` is the video file in the library; the sound is read from it
    /// (or from a temporary copy of its sound track). `preparing` is called with true when the language
    /// files have to be downloaded first, and with false when that is over.
    nonisolated static func transcribe(fileURL: URL, locale: Locale, mayDownload: Bool,
                                       preparing: @escaping @Sendable (Bool) -> Void) async -> Outcome {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return .failed }
        if #available(iOS 26, *) {
            return await transcribeWithAnalyzer(fileURL, locale: locale, mayDownload: mayDownload, preparing: preparing)
        }
        return await transcribeWithRecognizer(fileURL, locale: locale)
    }

    // MARK: iOS 26 and later: SpeechAnalyzer

    /// Whether the language files are in place.
    private enum Preparation {
        case ready
        case needsDownload
        case downloadFailed
        case failed
    }

    /// How handing a video's sound to the analyzer ended.
    private enum Feeding {
        /// The analyzer took all of the sound and finished.
        case finished
        /// The file holds no sound to analyse at all (an empty sound track): nothing was said, which is
        /// not a failure.
        case empty
        /// The sound could not be opened, or the analyzer gave up.
        case failed
    }

    /// The new analyzer: a language model (downloaded once), the file's sound fed to it, and the
    /// finished pieces of text collected as they come. UNSURE (needs the device): that the sound of a
    /// movie file can be opened as an `AVAudioFile` (if not, `openAudio` exports its sound track first),
    /// and that the transcriber's results end once the analyzer has finished.
    @available(iOS 26, *)
    nonisolated private static func transcribeWithAnalyzer(_ video: URL, locale: Locale, mayDownload: Bool,
                                                           preparing: @escaping @Sendable (Bool) -> Void) async -> Outcome {
        // A device that cannot run the new transcriber at all is told apart first, plainly, instead of
        // making a transcriber on it and seeing what happens (it reads as "not supported on this iPad").
        guard SpeechTranscriber.isAvailable else { return .unsupportedLanguage }
        guard let supported = await SpeechTranscriber.supportedLocale(equivalentTo: locale) else { return .unsupportedLanguage }
        let transcriber = SpeechTranscriber(locale: supported, preset: .transcription)
        switch await prepareLanguage(for: transcriber, mayDownload: mayDownload, preparing: preparing) {
        case .ready: break
        case .needsDownload: return .needsDownload
        case .downloadFailed: return .downloadFailed
        case .failed: return .failed
        }
        let analyzer = SpeechAnalyzer(modules: [transcriber])
        let collector = Task { () -> [String]? in
            var pieces: [String] = []
            do {
                for try await result in transcriber.results where result.isFinal {
                    pieces.append(String(result.text.characters))
                }
            } catch {
                return nil
            }
            return pieces
        }
        // One cancellation handler around the whole job: when the time is up (or the run is stopped) the
        // collecting and the analyzer are told to stop, wherever the job is waiting.
        return await withTaskCancellationHandler {
            let fed: Feeding = await feed(video, to: analyzer)
            if fed == .empty {
                // An empty sound track: nothing was said. The collecting is stopped without waiting for it,
                // because the transcriber's results may end by throwing once the analyzer was cancelled, and
                // that would be taken for a failure (and the video tried again for ever).
                collector.cancel()
                return Outcome.noSpeech
            }
            guard fed == .finished, let pieces = await collector.value else {
                collector.cancel()
                await analyzer.cancelAndFinishNow()
                return Outcome.failed
            }
            guard let words = TranscriptText.cleaned(pieces) else { return Outcome.noSpeech }
            return Outcome.text(words)
        } onCancel: {
            collector.cancel()
            Task { await analyzer.cancelAndFinishNow() }
        }
    }

    /// Makes sure the language files for the transcriber are on the device: they come down once
    /// (`AssetInventory`), which can take a while the first time.
    @available(iOS 26, *)
    nonisolated private static func prepareLanguage(for transcriber: SpeechTranscriber, mayDownload: Bool,
                                                    preparing: @Sendable (Bool) -> Void) async -> Preparation {
        let wanted: AssetInstallationRequest?
        do {
            wanted = try await AssetInventory.assetInstallationRequest(supporting: [transcriber])
        } catch {
            return .failed
        }
        guard let request = wanted else { return .ready }
        guard mayDownload else { return .needsDownload }
        preparing(true)
        defer { preparing(false) }
        do {
            try await request.downloadAndInstall()
        } catch {
            // (A wait that was stopped or timed out is not the connection's fault: the answer is dropped then.)
            return Task.isCancelled ? .failed : .downloadFailed
        }
        return .ready
    }

    /// Opens the video's sound and hands it to the analyzer: `.finished` when the analyzer took all of
    /// it, `.empty` when there was no sound in the file to analyse, `.failed` otherwise.
    /// (The file is opened and used inside this one function: it is not safe to pass around.)
    @available(iOS 26, *)
    nonisolated private static func feed(_ video: URL, to analyzer: SpeechAnalyzer) async -> Feeding {
        guard let (audioFile, temporaryCopy) = await openAudio(of: video) else { return .failed }
        defer {
            if let temporaryCopy { try? FileManager.default.removeItem(at: temporaryCopy) }
        }
        do {
            if let last = try await analyzer.analyzeSequence(from: audioFile) {
                try await analyzer.finalizeAndFinish(through: last)
                return .finished
            }
            // Nothing came back: the file held no sound to analyse (an empty sound track).
            await analyzer.cancelAndFinishNow()
            return .empty
        } catch {
            await analyzer.cancelAndFinishNow()
            return .failed
        }
    }

    /// The sound of a video as a file the analyzer can read: the video file itself when it opens
    /// as sound, otherwise a temporary .m4a made of its sound track (`temporary`: to be removed
    /// afterwards). nil when neither works.
    nonisolated private static func openAudio(of video: URL) async -> (file: AVAudioFile, temporary: URL?)? {
        if let direct = try? AVAudioFile(forReading: video) { return (direct, nil) }
        let copy = VideoCompressor.temporaryFile(extension: "m4a")
        let exported = await VideoCompressor.export(video, to: copy, fileType: .m4a, preset: AVAssetExportPresetAppleM4A,
                                                    progress: { (_: Double) -> Void in })
        guard exported, let file = try? AVAudioFile(forReading: copy) else {
            try? FileManager.default.removeItem(at: copy)
            return nil
        }
        return (file, copy)
    }

    // MARK: iOS 17 to 25: SFSpeechRecognizer

    /// The older recogniser, kept on the device (`requiresOnDeviceRecognition`). It needs the app's
    /// "Speech Recognition" usage description (in PinBoard-Info.plist): without it the
    /// question for permission would stop the app, so nothing is asked and nothing is listened to —
    /// and the answer is `.needsNewerSystem`, not `.notAllowed`: an app that never asked has no entry
    /// in Settings › Privacy & Security › Speech Recognition for the person to switch on.
    nonisolated private static func transcribeWithRecognizer(_ video: URL, locale: Locale) async -> Outcome {
        guard Bundle.main.object(forInfoDictionaryKey: "NSSpeechRecognitionUsageDescription") != nil else { return .needsNewerSystem }
        guard await speechPermission() else { return .notAllowed }
        guard let recognizer = SFSpeechRecognizer(locale: locale), recognizer.supportsOnDeviceRecognition else { return .unsupportedLanguage }
        guard recognizer.isAvailable else { return .failed }
        let request = SFSpeechURLRecognitionRequest(url: video)
        request.requiresOnDeviceRecognition = true
        request.shouldReportPartialResults = false
        request.addsPunctuation = true
        let gate = RecognitionGate()
        let answer: RecognitionAnswer = await withTaskCancellationHandler {
            await withCheckedContinuation { (continuation: CheckedContinuation<RecognitionAnswer, Never>) -> Void in
                gate.begin(continuation)
                let task = recognizer.recognitionTask(with: request) { (result: SFSpeechRecognitionResult?, error: (any Error)?) -> Void in
                    if let result, result.isFinal {
                        gate.finish(.words(result.bestTranscription.formattedString))
                    } else if let error {
                        gate.finish(SpeechTranscription.hasNoSpeech(error) ? .noSpeech : .failed)
                    }
                }
                gate.keep(task)
            }
        } onCancel: {
            gate.cancel()
        }
        // The recogniser and its request are held until the answer is in: Apple expects the app to keep
        // the recogniser while a task of it runs, and after the task was handed over nothing else in this
        // function uses either of them (the compiler may let them go as soon as they are last used).
        withExtendedLifetime((recognizer, request)) { }
        switch answer {
        case .words(let spoken):
            guard let words = TranscriptText.cleaned([spoken]) else { return .noSpeech }
            return .text(words)
        case .noSpeech: return .noSpeech
        case .failed: return .failed
        }
    }

    /// Whether the person allows speech recognition: yes already, or yes now (asked once).
    nonisolated private static func speechPermission() async -> Bool {
        switch SFSpeechRecognizer.authorizationStatus() {
        case .authorized:
            return true
        case .notDetermined:
            return await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) -> Void in
                SFSpeechRecognizer.requestAuthorization { (status: SFSpeechRecognizerAuthorizationStatus) -> Void in
                    continuation.resume(returning: status == .authorized)
                }
            }
        default:
            return false
        }
    }

    /// The error the recogniser gives for a file with no speech in it ("No speech detected", code
    /// 1110 of kAFAssistantErrorDomain). UNSURE: the code is known from experience, not from Apple's documentation.
    nonisolated static func hasNoSpeech(_ error: any Error) -> Bool {
        let failure = error as NSError
        return failure.domain == "kAFAssistantErrorDomain" && failure.code == 1110
    }
}

/// The first answer to a question wins; later ones are ignored. Hands it to the one task waiting.
/// @unchecked: `lock` guards both fields.
private final class FirstAnswer: @unchecked Sendable {
    private let lock = NSLock()
    private var answer: SpeechTranscription.Outcome? = nil
    private var waiter: CheckedContinuation<SpeechTranscription.Outcome, Never>? = nil

    func give(_ outcome: SpeechTranscription.Outcome) {
        lock.lock()
        if answer != nil {
            lock.unlock()
            return
        }
        answer = outcome
        let waiting = waiter
        waiter = nil
        lock.unlock()
        waiting?.resume(returning: outcome)
    }

    func wait() async -> SpeechTranscription.Outcome {
        await withCheckedContinuation { (continuation: CheckedContinuation<SpeechTranscription.Outcome, Never>) -> Void in
            lock.lock()
            if let answer {
                lock.unlock()
                continuation.resume(returning: answer)
            } else {
                waiter = continuation
                lock.unlock()
            }
        }
    }
}

/// What the older recogniser's result handler (called once, on another thread) found.
private enum RecognitionAnswer: Sendable {
    case words(String)
    case noSpeech
    case failed
}

/// Carries the older recogniser's answer to the task waiting for it, once, and lets that task
/// stop the recognition. @unchecked: `lock` guards every field (the task is the framework's
/// object, only ever cancelled from here).
private final class RecognitionGate: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<RecognitionAnswer, Never>? = nil
    private var task: SFSpeechRecognitionTask? = nil
    private var answer: RecognitionAnswer? = nil
    private var cancelled = false

    func begin(_ waiting: CheckedContinuation<RecognitionAnswer, Never>) {
        lock.lock()
        if let answer {
            lock.unlock()
            waiting.resume(returning: answer)
            return
        }
        continuation = waiting
        lock.unlock()
    }

    func keep(_ running: SFSpeechRecognitionTask) {
        lock.lock()
        task = running
        let stop = cancelled
        lock.unlock()
        if stop { running.cancel() }
    }

    func finish(_ found: RecognitionAnswer) {
        lock.lock()
        if answer != nil {
            lock.unlock()
            return
        }
        answer = found
        let waiting = continuation
        continuation = nil
        lock.unlock()
        waiting?.resume(returning: found)
    }

    func cancel() {
        lock.lock()
        cancelled = true
        let running = task
        lock.unlock()
        running?.cancel()
        finish(.failed)
    }
}

// MARK: - The background run

/// How far a run has got (plain numbers: the normal side's count never includes a hidden video).
private struct TranscriptionTally {
    var visibleDone = 0
    var visibleTotal = 0
    /// What the run leaves under the switch when it ends (a language that isn't supported, say).
    var closing: String? = nil
    /// How many normal videos could not be listened to (a hidden one is never counted: nothing about
    /// it reaches the normal side).
    var failed = 0

    /// The line the run leaves: the reason it stopped when it has one, else how many videos could not
    /// be listened to; nil when all went well.
    var lineToLeave: String? {
        if let closing { return closing }
        return failed > 0 ? TranscriptText.failedLine(count: failed) : nil
    }
}

/// What waits to be listened to: the next video (a normal one while any waits, so the normal side's
/// count is done before a hidden video is looked at) and how many normal ones wait.
private struct TranscriptionQueue {
    var next: Pin? = nil
    var visibleWaiting = 0
}

extension LibraryStore {

    // MARK: Which videos wait

    /// A video that waits to be listened to: it has a sound track, no words yet, its file is here
    /// and no conversion has it. `retrying` (the Settings button): a video that was listened to
    /// before and gave no words is listened to again, and so is one the recogniser failed on (that
    /// one is marked as listened to, so nothing but this button tries it again).
    func wantsTranscript(_ pin: Pin, retrying: Bool = false) -> Bool {
        guard pin.isVideo, !pin.isDeleted, pin.hasAudio == true, pin.transcript == nil else { return false }
        guard !missingFileIDs.contains(pin.id), !videosBeingConverted.contains(pin.id) else { return false }
        // Speech recognition is AI too: a hidden video only with "Include hidden pins in AI" on.
        guard aiMaySee(pin) else { return false }
        if retrying { return true }
        if isOffloaded(pin) { return false }   // kept in iCloud only: only the Settings button brings it back for this
        return !pin.transcriptChecked
    }

    /// The AI queue or a video conversion is at work (the run waits: all of them read files and
    /// keep the processor busy).
    private var isBusyWithHeavierWork: Bool {
        isAIQueueBusy || !conversionRuns.isEmpty || !laterConversions.isEmpty
    }

    // MARK: Starting and stopping

    /// Starts the background run when a video waits and "Transcribe speech in videos" is on, `delay`
    /// seconds from now (so it never holds up launch). Nothing happens when a run is going or
    /// nothing waits. Called after launch, when a conversion run has ended, after an import, when
    /// the sound check finds a sound track, after a sync, and when the switch is turned on (Settings
    /// › Videos calls it then).
    func startTranscribingIfNeeded(delay: Double = 12) {
        guard transcriptionTask == nil, !transcriptionPaused, AppSettings.shared.transcribeVideos,
              pins.contains(where: { (pin: Pin) -> Bool in wantsTranscript(pin) }) else { return }
        transcriptionByHand = false
        launchTranscription(delay: delay)
    }

    /// "Transcribe existing videos" (Settings › Videos): every video with sound that has no
    /// transcript yet is listened to, one at a time, in the background — also those listened to
    /// before that gave no words, and those the recogniser failed on. It works with the
    /// switch off too: it was asked for. The normal side's pill and Settings show how far it has
    /// got. A run that is going already takes this on from its next video; one that still waits
    /// for its start-up delay is replaced by this one, so nothing ever starts twice.
    func startTranscribingAllVideos() {
        transcriptionPaused = false
        if transcriptionTask != nil {
            if transcriptionIsListening {
                transcriptionByHand = true
                return
            }
            transcriptionTask?.cancel()
            transcriptionTask = nil
        }
        transcriptionByHand = true
        launchTranscription(delay: 0)
    }

    /// Stops everything about transcripts (another profile is chosen, or the library is cleared:
    /// the run belongs to the old library). Its status, the line it left and its pill go with it.
    func cancelTranscription() {
        transcriptionTask?.cancel()
        transcriptionTask = nil
        transcriptionIsListening = false
        transcriptionByHand = false
        transcriptionPaused = false
        transcriptionStatus = nil
        transcriptionClosing = nil
        transcriptionLine = nil
        clearTranscriptionPill()
    }

    private func launchTranscription(delay: Double) {
        let profile = profileID
        transcriptionTask = Task { [weak self] in
            if delay > 0 { try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000)) }
            guard !Task.isCancelled, let self, self.isCurrentProfile(profile) else { return }
            await self.runTranscription(profile: profile)
        }
    }

    // MARK: The run

    /// Goes through the waiting videos one at a time: waits until the AI queue and the conversions
    /// are quiet, takes the next video (normal ones first), listens to it in the background and
    /// writes what it found. Each wait ends the run quietly when another profile is chosen.
    private func runTranscription(profile: UUID) async {
        transcriptionIsListening = true
        transcriptionClosing = nil   // (a new run replaces what the last one left under the switch)
        markSilentVideosChecked()
        var tally = TranscriptionTally()
        var tried: Set<UUID> = []
        if transcriptionByHand, transcriptionQueue(retrying: true, excluding: tried).visibleWaiting == 0 {
            await showNothingWaiting()
        }
        while !Task.isCancelled, isCurrentProfile(profile) {
            await waitUntilQuiet(profile: profile)
            guard !Task.isCancelled, isCurrentProfile(profile) else { return }
            let byHand = transcriptionByHand   // (the button may have been pressed meanwhile)
            if !byHand, !AppSettings.shared.transcribeVideos { break }
            let queue = transcriptionQueue(retrying: byHand, excluding: tried)
            guard let next = queue.next else { break }
            tried.insert(next.id)
            let hidden = isHidden(next)
            if !hidden { tally.visibleTotal = max(tally.visibleTotal, tally.visibleDone + queue.visibleWaiting) }
            showTranscriptionProgress(tally: tally, hidden: hidden, byHand: byHand)
            let outcome = await listen(to: next, hidden: hidden, profile: profile)
            guard !Task.isCancelled, isCurrentProfile(profile) else { return }
            let goOn = record(outcome, for: next, hidden: hidden, tally: &tally)
            if !hidden { tally.visibleDone += 1 }
            if !goOn { break }
            try? await Task.sleep(nanoseconds: UInt64(max(0.001, transcriptionBreathSeconds) * 1_000_000_000))
        }
        guard !Task.isCancelled, isCurrentProfile(profile) else { return }
        finishTranscriptionRun(tally: tally)
    }

    /// The end of a run: the status and the pill are cleared, a line it left on purpose goes to
    /// `transcriptionClosing`, and the library is saved. The status is never used for that line: it
    /// means "a run is at work" (Settings dims "Transcribe existing videos" while it shows), and a
    /// line that says "try again" must not dim the button that tries again. (No new run starts from
    /// here: a video that comes later starts one itself.)
    private func finishTranscriptionRun(tally: TranscriptionTally) {
        clearTranscriptionPill()
        transcriptionLine = nil
        transcriptionClosing = tally.lineToLeave
        transcriptionStatus = nil
        transcriptionIsListening = false
        transcriptionByHand = false
        transcriptionTask = nil
        scheduleSave(after: 3)
    }

    /// The Settings button found no normal video waiting: says so for a few seconds (a button that
    /// does nothing at all looks broken). A hidden video, if one waits, is done afterwards, silently.
    private func showNothingWaiting() async {
        let line = TranscriptText.nothingWaitingLine
        transcriptionStatus = line
        try? await Task.sleep(nanoseconds: UInt64(max(0.01, transcriptionNoticeSeconds) * 1_000_000_000))
        if transcriptionStatus == line { transcriptionStatus = nil }
    }

    /// Waits while the AI queue or a conversion is at work (checked every `transcriptionPollSeconds`).
    private func waitUntilQuiet(profile: UUID) async {
        while !Task.isCancelled, isCurrentProfile(profile), isBusyWithHeavierWork {
            try? await Task.sleep(nanoseconds: UInt64(max(0.01, transcriptionPollSeconds) * 1_000_000_000))
        }
    }

    /// The next video to listen to and how many normal ones wait. A normal video always comes before
    /// a hidden one, so the count the normal side shows is done before any hidden video is touched.
    private func transcriptionQueue(retrying: Bool, excluding tried: Set<UUID>) -> TranscriptionQueue {
        var queue = TranscriptionQueue()
        var firstHidden: Pin? = nil
        for pin in pins where !tried.contains(pin.id) && wantsTranscript(pin, retrying: retrying) {
            if isHidden(pin) {
                if firstHidden == nil { firstHidden = pin }
            } else {
                queue.visibleWaiting += 1
                if queue.next == nil { queue.next = pin }
            }
        }
        if queue.next == nil { queue.next = firstHidden }
        return queue
    }

    /// A video with no sound track has nothing to listen to: it is marked as listened to (not an
    /// edit: it says something about the file, so the change date stays).
    private func markSilentVideosChecked() {
        let silent: [UUID] = pins.filter { (pin: Pin) -> Bool in
            pin.isVideo && pin.hasAudio == false && !pin.transcriptChecked
        }.map { (pin: Pin) -> UUID in pin.id }
        guard !silent.isEmpty else { return }
        for id in silent { modifyKeepingDate(id) { (pin: inout Pin) -> Void in pin.transcriptChecked = true } }
        scheduleSave(after: 3)
    }

    // MARK: Showing it

    /// "Transcribing 2 of 5…" in Settings, and — for the Settings button — on the normal side's
    /// pill. Only the normal side's own count: while a hidden video is being listened to nothing
    /// is shown (and the pill is left to others).
    private func showTranscriptionProgress(tally: TranscriptionTally, hidden: Bool, byHand: Bool) {
        guard !hidden else {
            transcriptionLine = nil
            transcriptionStatus = nil
            clearTranscriptionPill()
            return
        }
        let line = TranscriptText.progressLine(number: tally.visibleDone + 1, of: tally.visibleTotal)
        transcriptionLine = line
        transcriptionStatus = line
        guard byHand else { return }
        // A background job never takes the pill from other work: only a free pill, or its own words.
        guard importStatus == nil || importStatus == transcriptionPill else { return }
        transcriptionPill = line
        setImportStatus(line, scope: .visible)
    }

    /// Takes this run's words off the pill (never somebody else's).
    private func clearTranscriptionPill() {
        if let shown = transcriptionPill, importStatus == shown { setImportStatus(nil, scope: .visible) }
        transcriptionPill = nil
    }

    /// The recogniser has to wait for the language files to come down (the first time only): the
    /// status says so, and goes back to the count when they are in place. For a normal video only.
    func speechIsPreparing(_ preparing: Bool, hidden: Bool, profile: UUID) {
        guard isCurrentProfile(profile), transcriptionIsListening, !hidden else { return }
        transcriptionStatus = preparing ? TranscriptText.preparingLine : transcriptionLine
    }

    // MARK: Listening and writing

    /// Hands one video to the recogniser (in the background, with a time limit).
    private func listen(to pin: Pin, hidden: Bool, profile: UUID) async -> SpeechTranscription.Outcome {
        guard await ensureLocal(pin) else { return .failed }   // kept in iCloud only and couldn't come back
        let allowDownload = AppSettings.shared.webAllowed
        let limit = SpeechTranscription.timeout(forDuration: pin.duration ?? 0, mayDownload: allowDownload)
        let preparing: @Sendable (Bool) -> Void = { [weak self] (now: Bool) -> Void in
            Task { @MainActor in self?.speechIsPreparing(now, hidden: hidden, profile: profile) }
        }
        return await SpeechTranscription.listen(using: speechRecogniser, file: videoFileURL(for: pin), locale: Locale.current,
                                                mayDownload: allowDownload, timeout: limit, preparing: preparing)
    }

    /// Writes down what listening found. Returns false when the run should stop (nothing more can
    /// be done now: speech isn't allowed, it needs a newer system, or the language files can't be
    /// downloaded). A line for the end of the run is left only about a normal video: nothing about a
    /// hidden one reaches the normal side.
    private func record(_ outcome: SpeechTranscription.Outcome, for pin: Pin, hidden: Bool, tally: inout TranscriptionTally) -> Bool {
        switch outcome {
        case .text(let words):
            writeTranscript(words, to: pin.id)
        case .noSpeech:
            markTranscriptChecked(pin.id)
        case .unsupportedLanguage:
            markTranscriptChecked(pin.id)
            if !hidden {
                tally.closing = TranscriptText.unsupportedLine(language: TranscriptText.languageName(of: Locale.current),
                                                               device: UIDevice.current.model)
            }
        case .needsDownload:
            if !hidden { tally.closing = TranscriptText.needsDownloadLine(language: TranscriptText.languageName(of: Locale.current)) }
            return false
        case .downloadFailed:
            if !hidden { tally.closing = TranscriptText.downloadFailedLine(language: TranscriptText.languageName(of: Locale.current)) }
            return false
        case .notAllowed:
            if !hidden { tally.closing = TranscriptText.notAllowedLine(device: UIDevice.current.model) }
            transcriptionPaused = true   // asked of the person once; no automatic start asks again this launch
            return false
        case .needsNewerSystem:
            if !hidden { tally.closing = TranscriptText.needsNewerSystemLine(device: UIDevice.current.model) }
            transcriptionPaused = true   // the answer is the same until the system is updated: no automatic start asks again this launch
            return false
        case .failed:
            // Marked as listened to, so a file that always fails is not tried again at every launch (a recogniser
            // that hangs would hold the whole queue each time). The Settings button tries it again.
            markTranscriptChecked(pin.id)
            if !hidden { tally.failed += 1 }
        }
        return true
    }

    /// Puts the words into the pin and its note (`TranscriptNotes.merged`: never twice), and has
    /// the AI look at the video again: it is named and tagged from its words first now. This is
    /// the person's note changing, so the change date moves (it travels with a sync). A video that
    /// has a transcript already (a sync brought it) only gets marked.
    private func writeTranscript(_ words: String, to id: UUID) {
        guard let current = pin(id), current.isVideo else { return }
        // Hidden while it was listened to: the words are dropped, and it waits (it is listened to
        // again once the AI may see it).
        guard aiMaySee(current) else { return }
        if current.transcript != nil {
            markTranscriptChecked(id)
            return
        }
        modify(id) { (pin: inout Pin) -> Void in
            pin.transcript = words
            pin.note = TranscriptNotes.merged(note: pin.note, transcript: words)
            pin.transcriptChecked = true
            pin.needsAnalysis = true
        }
        scheduleSave()
        startAnalysisIfNeeded()
    }

    /// Records that the sound was listened to (no words, or a language the device can't read): not
    /// an edit, so the change date stays.
    private func markTranscriptChecked(_ id: UUID) {
        guard let current = pin(id), !current.transcriptChecked else { return }
        modifyKeepingDate(id) { (pin: inout Pin) -> Void in pin.transcriptChecked = true }
        scheduleSave(after: 3)
    }
}
