# Release checklist: from "TestFlight works" to "Submit for Review"

*Written 4 November 2026. Updated 5 November 2026 with the owner's decisions, the store name and build 16's fixes. Work top to bottom; each part assumes the ones above it.*

**Marks:** ✅ done · 🧑 needs you, the owner · 🛠 needs a code change (then a new build) · 📝 a document in `AppStore/`

---

## 1. Decisions

- [x] ✅ **Price: free.** PinBoard will be free and open source (MIT).
- [x] ✅ **Contact: GitHub Issues only**, no email (`https://github.com/silent-diffusion/PinBoard/issues`).
- [x] ✅ **Product page:** the public repository's README. **Web pages:** GitHub Pages on the same repository (part 4).
- [x] ✅ **Mac and Apple Vision Pro: offered**, as the iPad app (tests in part 3).
- [x] ✅ **Hidden pins and AI:** "Include hidden pins in AI", off by default (build 17). While it's off, hidden pins get no AI at all: no on-device tagging, Apple Intelligence, transcription or Cloud AI.
- [x] ✅ **Video saving from social sites:** removed in build 16. Those videos stay links with their picture.
- [x] ✅ **Store name: "PinBoard - Pins Your Way"**, already set in App Store Connect and TestFlight. The subtitle is now "Private mood board & library" (`text/subtitle.txt`). The Home Screen name stays "PinBoard".
- [ ] 🧑 **Countries.** All is fine for a free app. In the EU, answer the trader question **"not a trader"** (a free hobby app), so no address or phone is shown publicly.

## 2. Code changes

**Done in build 16** (commits 523cfa4 to 1927871; details in `review-notes.md` Part 2):

- [x] ✅ No video downloads from TikTok, Instagram, Reddit, Pinterest or web pages; the TikTok cookie relay is removed.
- [x] ✅ The Cloud AI consent sheet names the company and links its privacy policy; consent is per provider.
- [x] ✅ Permission texts fixed (microphone removed, camera "photo"); "Save to Photos" asks for add-only access.
- [x] ✅ YouTube through oEmbed and the Data API only, with its Terms and Google's Privacy Policy linked in Settings.
- [x] ✅ Unsplash download reporting and tagged credit links.
- [x] ✅ Swift Playgrounds wording, the built-in keyboard and capability hints removed.

**Still to do:**

1. [ ] 🛠 **Build 17: "Include hidden pins in AI"**, off by default, covering all AI. The privacy policy, review notes, user guide and support page already describe it. If it slips, remove those sentences before submitting.
2. [ ] 🛠 **Web User-Agent with a contact.** "PinBoard/1.0 (https://github.com/silent-diffusion/PinBoard/issues)" (Wikimedia asks for one).
3. [ ] 🛠 *(Nice to have)* An **About** row in Settings with the version number and links to the support page, the privacy policy, the user guide and the source code. Today's About has no version or links.
4. [ ] 🛠 *(Nice to have)* "Optimize device storage" on a new device downloads old pins' full files and then offloads them straight away. Fetch only the thumbnails.
5. [ ] 🛠 *(Only if a test in part 3 fails)* Mac or Vision Pro fixes.

## 3. Finish and test the build

- [x] ✅ TestFlight uploads work (`Xcode/upload-testflight.sh <build>`).
- [x] ✅ App icon: Mood board by default, seven alternates in Settings (commit 9d380f4).
- [x] ✅ Privacy manifest checked: correct.
- [x] ✅ Encryption answer in the build (`ITSAppUsesNonExemptEncryption` = false).
- [x] ✅ Settings rework with search (commit bc7a8cb).
- [ ] 🧑 Upload the build with all of the above (build 17 or later).
- [ ] 🧑 **Test on a real iPhone and iPad.** These never ran on a device before:
  - [ ] iCloud sync between two devices: the first sync of a big library, the climbing count, the Sync log
  - [ ] Optimize device storage with real iCloud
  - [ ] Widgets on a real Home Screen (all three, a few sizes, two on one board with different Picks)
  - [ ] The share sheet from Photos, Safari, Files and Messages; quick save; a second profile
  - [ ] A TikTok or Instagram link becomes a link pin with its picture, and the one-time note appears
  - [ ] The Cloud AI consent sheet for each company
  - [ ] "Include hidden pins in AI" off: a new hidden pin gets no AI tags, title or transcript and isn't sent to Cloud AI; on: it does (build 17)
  - [ ] Per-profile settings travelling between devices
  - [ ] Choosing an alternate app icon
  - [ ] Fresh install with no data: the app is usable and explains itself (this is what the reviewer sees)
  - [ ] Hidden with Face ID off: the passcode works
  - [ ] Offline mode: nothing breaks
- [ ] 🧑 **Test on a Mac** (TestFlight, already installed) **and on Vision Pro** (or the visionOS simulator). The list is in the README under "Availability on Mac and Apple Vision Pro". The main points:
  - [ ] Hidden lock prompt (Touch ID or password; Optic ID)
  - [ ] Camera missing → "This device has no camera."
  - [ ] Import, export and Save to Files
  - [ ] iCloud sync with an iPhone
  - [ ] Share sheet and widgets: what's there, and that nothing promises what isn't
  - [ ] Narrow and wide windows, secondary click, Escape and Return
  - [ ] Vision Pro: menus, videos, Quick Look
- [ ] 🧑 **Version numbers.** `MARKETING_VERSION` is 1.0. Each upload needs a higher build number.

## 4. Going open source and the web pages

- [ ] 🧑 **Before making the repository public**, check what's in it and in its history:
  - no API keys, tokens or passwords (search the history, not just today's files);
  - nothing personal in the docs or code comments (the private development notes now live in the untracked `_dev-notes/` folder);
  - the screenshots' and demo photos' licences are fine (Unsplash License, listed in `photo-credits.txt`).
  If the history holds anything private, start the public repository from a clean copy instead.
- [x] 📝 **`LICENSE`** added (MIT, "Copyright (c) 2026 silent-diffusion"), and the README says to report issues on GitHub Issues.
- [x] 📝 Repository **README written as the product page**: what PinBoard is, screenshots, privacy in a few lines, how to build, and links to the support page, privacy policy and user guide.
- [ ] 🧑 Replace the README's TestFlight / App Store placeholder with the real link once there is one.
- [ ] 🧑 **Make the repository public** and check that **Issues** is switched on (Settings › General › Features).
- [x] 📝 **GitHub Pages files:** `docs/` holds `index.md`, `privacy.md`, `support.md`, `user-guide.md` and `_config.yml`.
- [ ] 🧑 **Turn on GitHub Pages:** Settings › Pages › "Deploy from a branch", `main`, folder `/docs`. `AppStore/README.md` explains it.
- [ ] 🧑 Open both addresses on your phone and check they load and that their links work:
  - `https://silent-diffusion.github.io/PinBoard/privacy`
  - `https://silent-diffusion.github.io/PinBoard/support`
- [x] 📝 Product page text, privacy policy, support page, user guide and review notes written and updated for build 16 and GitHub Issues.
- [ ] 📝 After build 17, re-read the privacy policy, review notes, user guide and support page against it (the switch's name and where it sits in Settings).

## 5. Screenshots

- [x] ✅ First set exists (1 November 2026): iPhone 6.3", 6.9" and iPad 13".
- [ ] 🧑 Demo content from the video session.
- [ ] Retake with the demo content, adding the share sheet, widgets, an unlocked Hidden side and Settings search. The list and order are in the README under "New shots that would sell the app".
- [ ] Shot 5 (Hidden) must be replaced: its caption "Nothing is uploaded" and its "Settings › Safety" path are out of date.
- [ ] A pin's page with AI tags, taken on your iPhone (the simulator makes no tags).
- [ ] *(Optional)* A 15–30 s App Preview video.
- [ ] *(Optional)* Mac screenshots aren't needed: a "Designed for iPad" app uses the iPad ones.

## 6. App Store Connect

- [ ] 🧑 **App Information:**
  - the name (part 1) and the subtitle;
  - category: Photo & Video (secondary Lifestyle);
  - content rights: "Yes, it contains third-party content" (Explore's openly licensed pictures), "and I have the rights";
  - age rating (README).
- [ ] 🧑 **App Privacy:** "Data Not Collected" (the README explains the Cloud AI grey area), and the Privacy Policy URL.
- [ ] 🧑 **Pricing and Availability:** Free; countries; leave **Mac** and **Apple Vision Pro** ticked.
- [ ] 🧑 **Version 1.0 page:**
  - promotional text, description, keywords;
  - Support URL (the Pages support page);
  - Marketing URL (optional: the repository);
  - screenshots;
  - copyright "2026 ‹your name›".
- [ ] 🧑 **Build:** pick the final TestFlight build.
- [ ] 🧑 **App Review Information:** sign-in **not** required; your name, phone and email (private to Apple's reviewers); the notes from `review-notes.md` Part 1.
- [ ] 🧑 **Release:** "Manually release this version" lets you choose the day after approval.

## 7. Submit

- [ ] 🧑 **Submit for Review.** Reviews usually take a day or two. If it's rejected, the message names a guideline; `review-notes.md` Part 2 has the likely ones.
- [ ] 🧑 After approval: release, then add the App Store link to the repository README and the Pages landing page, and check that the privacy and support links work from the App Store page.
