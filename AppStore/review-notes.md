# App Review notes

Two parts:

- **Part 1** is ready to paste into App Store Connect › your version › **App Review Information › Notes** (limit 4,000 characters). Set **Sign-in required** to **No**: there's no account to give them.
- **Part 2** is for you, the owner: what App Review might object to, and where each stands. Build 16 already fixed the biggest risks (updated 5 November 2026).

---

## Part 1 — paste this into "Notes"

```
PinBoard is a free, open-source (MIT), private library of pictures, videos, notes and links. There is no account, no server and no sign-in: everything works right after install, on the device. Source code: https://github.com/silent-diffusion/PinBoard

HOW TO SEE THE MAIN FEATURES
1. Pins tab › + › Photos… (or Camera, Files…, Clipboard, Text pin, Link pin) to add pins. The on-device AI then tags and titles them in the background (a status pill shows progress).
2. Boards tab › New board, then add pins with a pin's menu › Add to board…
3. Search tab: search by words, tags, colors or text inside pictures.
4. Explore tab: searches openly licensed pictures on Wikimedia Commons (the default source, no key needed). Tap + to save one.
5. Link pins: Pins tab › + › Link pin, paste any article address. PinBoard reads the page's title, picture and text. Videos on social sites and inside web pages are kept as links with their picture; nothing of them is downloaded. YouTube links use YouTube's oEmbed service and embedded player only.

HIDDEN SIDE (FACE ID)
Boards tab › ⋯ › Hidden… opens a private part of the library. It asks for Face ID or Touch ID, with the device passcode as fallback (LocalAuthentication, deviceOwnerAuthentication). On a device with no passcode it opens without asking. To hide something: touch and hold a board › Hide board, or a pin's menu › Hide pin. Hidden items never appear elsewhere, in widgets or in the share sheet. By default no AI processes hidden pins at all (no on-device tagging, Apple Intelligence, transcription or Cloud AI) unless the user turns on "Include hidden pins in AI" (off by default).

SHARE EXTENSION
In Photos or Safari, tap Share › PinBoard (it may need enabling under "More" the first time). Choose a board (or none) and tap Save. The item is stored on the device and added the next time PinBoard opens. The extension sends nothing over the network.

WIDGETS
Home Screen › Edit › Add Widget › PinBoard: Photo, Photo Grid and Quote. Edit Widget › Board picks a board. Add a few photos in the app first; the widget fills within about a minute. Hidden pins are never shown.

OPTIONAL FEATURES (ALL OFF BY DEFAULT)
• iCloud sync: Settings › iCloud & storage › Sync with iCloud Drive. Uses the user's own iCloud Drive (iCloud Documents + key-value store). Not needed for any other feature.
• Cloud AI: Settings › AI › Use a cloud vision model. Needs the user's OWN API key for Anthropic or OpenAI; the developer provides no key and runs no server. Before anything is sent, a consent screen names the company ("Send pictures to Anthropic?"), lists exactly what is sent (a downscaled copy of the picture with all metadata removed, its board names and the user's tags, and for a link up to 1,500 characters of page text) and links that company's privacy policy. Nothing is sent until the user taps "I understand — turn it on"; choosing the other company asks again. Without a key, nothing is sent. The app's own AI runs on the device and needs no key.
• Offline mode (Settings) turns every network feature off at once.

PRIVACY AND SUPPORT
The app collects no data. The developer has no server and receives nothing. Network use happens only when the user searches, saves or opens a link, or turns on iCloud sync or Cloud AI. Support is through the project's public GitHub Issues page, linked from the Support URL.

Mac and Apple Vision Pro: offered as the iPad app.

Note: Vision-based tagging may produce few or no tags in the Simulator; please test on a device.
```

*(About 3,600 characters. Check two things against the submitted build: that "Videos on social sites… stay links" is in it (build 16), and the "Include hidden pins in AI" switch (planned for build 17). If the switch isn't in the build, delete the sentence "By default no AI processes hidden pins…".)*

---

## Part 2 — App Review risks (for the owner)

*First written 4 November 2026; updated 5 November 2026 after build 16. The guideline quotes come from Apple's App Review Guidelines as published on 4 November 2026.*

### Where things stand

| Risk | Guideline | Status |
|---|---|---|
| 1. Saving videos from TikTok, Instagram, Reddit, Pinterest and web pages | 5.2.3 | ✅ Fixed in build 16 |
| 2. Cloud AI consent didn't name the company; one "yes" covered both | 5.1.2(i) | ✅ Fixed in build 16. Hidden pins kept out of all AI by default: build 17 |
| 3. YouTube watch-page reading; Unsplash download reporting | 5.2.2 | ✅ Fixed in build 16 |
| 4. Swift Playgrounds texts in the app | 2.1, 2.3 | ✅ Fixed in build 16 |
| 5. Permission texts that didn't match the app | 5.1.1 | ✅ Fixed in build 16 |
| 6. GitHub Issues as the only support contact | 1.5 | ⚠️ Fine with care (below) |
| 7. Mac and Vision Pro running the iPad app | 2.1, 4.0 | ⚠️ Test before release (below) |
| 8. Age rating and web access | — | Answer honestly |

### 1. Videos from other platforms (5.2.3) — fixed in build 16

**The rule:** apps should not "include the ability to save, convert, or download media from third-party sources (such as Apple Music, YouTube, SoundCloud, Vimeo, etc.) without explicit authorization from those sources."

**Before:** "Read links fully" (on by default) downloaded the video file from TikTok (replaying a cookie from TikTok's page), Instagram reels, Reddit, Pinterest and any web page that named a video. Settings advertised it.

**Now:**
- Those videos become link pins with the post's picture, title and creator. A one-time note on the pin's page explains how to save the video from its own app and then share it to PinBoard. The TikTok cookie relay is gone.
- Picture posts still become picture pins. That's what a "save for inspiration" app is expected to do, and 5.2.3 is about audio and video.
- A link that *is itself* a video file (.mp4, .mov) is still downloaded, like a browser download. That is low risk. If App Review ever objects, it is the one thing left to switch off.
- YouTube downloads nothing. It plays in YouTube's own embedded player.

### 2. Cloud AI consent (5.1.2(i)) — fixed in build 16; hidden pins kept out of AI in build 17

**The rule:** "You must clearly disclose where personal data will be shared with third parties, including with third-party AI, and obtain explicit permission before doing so."

**Now:**
- The sheet is titled "Send pictures to Anthropic?" (or OpenAI). It says where the data goes (api.anthropic.com), lists what is sent and links the company's privacy policy.
- Consent is stored per provider; switching companies asks again.
- Build 17 adds **"Include hidden pins in AI"**, off by default. While it is off, hidden pins get no AI at all: no on-device tagging, no Apple Intelligence naming or search words, no transcription and no Cloud AI. Only rule-based code (fingerprints, the duplicate check, word search) sees them. So nothing from the Hidden side can reach Anthropic or OpenAI unless the person turns on both this switch and Cloud AI.

**One thing to keep in step:** the privacy policy, the review notes, the user guide and the support page all describe "Include hidden pins in AI". If build 17 slips, either wait for it or remove those sentences from all four before submitting.

### 3. Other sites' terms (5.2.2) — fixed in build 16

- **YouTube:** details now come only from oEmbed and, with the user's key, the Data API. The watch page isn't read. Settings links YouTube's Terms of Service and Google's Privacy Policy under the key field, and the privacy policy links both.
- **Unsplash:** each saved photo is reported through `download_location`. The credit links to the photographer and Unsplash with `utm_source`.
- **Pexels and Pixabay** ask for visible credit. The app's credit line covers that.

### 4 and 5. Playgrounds texts and permission texts — fixed in build 16

- The Swift Playgrounds wording, the built-in keyboard and the capability hints are gone.
- The microphone text is removed, and the camera and Photos texts now match the app.
- "Save to Photos" asks for add-only access.
- The web User-Agent is now "PinBoard/1.0 (iPhone and iPad app)". Wikimedia asks apps to include a contact in it; adding the Issues address would be polite: "PinBoard/1.0 (https://github.com/silent-diffusion/PinBoard/issues)".

### 6. Support through GitHub Issues only (guideline 1.5) — fine, with care

**The rule (1.5, Developer Information):** the app and its Support URL must include an easy way to contact you.

GitHub Issues meets that, and many open-source apps on the App Store use it. To keep it from being questioned:

- **Make the Support URL a real support page**, not the bare Issues list. `https://silent-diffusion.github.io/PinBoard/support` explains what PinBoard is, has the FAQ, and leads with a clear "Get help or report a problem" link to Issues. Reviewers open the Support URL; a page that answers questions and says plainly how to reach you is what they look for.
- **Posting an issue needs a free GitHub account.** The support page says so. If a reviewer pushes back, the fallback is a simple contact address on the support page. It can be an alias that forwards to you.
- **The repository must be public and Issues switched on** before you submit. A private repository's Issues page shows "404" to everyone else. That would fail 1.5 at once.
- **App Review still needs a private contact.** App Store Connect › App Review Information asks for a name, phone number and email for Apple's reviewers only. That is never shown publicly. Use your developer account's details.
- **EU trader status:** a free, open-source hobby app is normally "not a trader", so no address or phone number is shown on the EU App Store page. If you declare yourself a trader, the email and phone become public, and Issues alone won't do.
- Issues are public. The support page and privacy policy warn people not to post private pictures or details.

### 7. Mac and Apple Vision Pro (the iPad app) — test before release

App Review may try the app on a Mac. Whatever is offered there must work or degrade gracefully (2.1 completeness). The checklist has the list to try. The riskiest parts:

- **The Hidden lock:** LocalAuthentication works on a Mac with Touch ID or the password, and on Vision Pro with Optic ID or the passcode. Check that the lock prompt appears.
- **The camera:** on a Mac without one, "+ › Camera" should show "This device has no camera." rather than fail.
- **Widgets and the share sheet:** iPad apps on a Mac and on Vision Pro may not offer widgets or share extensions the same way. Check that nothing points users to a feature that isn't there. The support page only promises widgets on iPhone and iPad.
- **iCloud sync** works with the same Apple Account and the same container. Check one sync between the Mac and an iPhone.
- **Window resizing on the Mac:** PinBoard follows window width (spec 3.1), so a narrow Mac window should look like an iPhone. Check that nothing gets cut off.
- **Vision Pro:** check that hover and gaze work with the long-press menus (a secondary tap), and that videos and Quick Look play.

If something can't be fixed in time, you can switch Vision Pro (or the Mac) off in Pricing and Availability and add it later without a new review.

### 8. Age rating and web access

The in-app browser used for reverse image search can reach any site, and Explore shows open web pictures. The honest answer to "Unrestricted Web Access" is **Yes**, which gives the highest age rating. That isn't a rejection risk.

### Not a risk, but worth knowing

- **Reviewers get no demo content.** PinBoard starts empty, so the notes tell them how to add pins. Vision tagging doesn't work in the Simulator, so the notes ask them to use a device.
- **No account means no "Delete account" requirement** (5.1.1(v)).
- **Minimum functionality (4.2)** is clearly met.
- **Open source:** the MIT licence lets anyone copy the code. That is your choice and not an App Review matter. But if someone else ever ships a copy under your name, the App Store's name reservation and your trademark (if any) are what protect you, not the licence.
