# PinBoard: App Store kit

Everything for the App Store Connect product page and the review. Each text file holds one field, ready to paste.

| File | What it is |
|---|---|
| `text/*.txt` | The product page fields (below) |
| `../docs/privacy.md` | The privacy policy. Contact: GitHub Issues. Published on GitHub Pages |
| `../docs/support.md` | The support page: GitHub Issues and an FAQ. Published on GitHub Pages; it is the Support URL |
| `../docs/user-guide.md` | "How to use PinBoard". Published on GitHub Pages |
| `review-notes.md` | Part 1: paste into "Notes for the reviewer". Part 2: App Review risks and fixes, for you |
| `RELEASE-CHECKLIST.md` | Everything left between "TestFlight works" and "Submit for Review" |
| `screenshots/`, `tools/` | Framed screenshots and the framer |
| `icon/` | The app icons (default and alternates) and the script that draws them |
| `photo-credits.txt` | Credits for the demo photos (Unsplash) |

## Text (App Store Connect › your app: App Information for the name and subtitle, the version page for the rest)

| Field | File | Length / limit |
|---|---|---|
| Name | `text/name.txt` | 24 / 30 |
| Subtitle | `text/subtitle.txt` | 28 / 30 |
| Promotional text | `text/promotional_text.txt` | 170 / 170 |
| Description | `text/description.txt` | 3,794 / 4,000 |
| Keywords | `text/keywords.txt` | 98 / 100 |
| What's New | `text/whats_new.txt` | 740 / 4,000 |

*Updated 4 November 2026 for the share sheet, widgets, iCloud sync, profiles and Settings search.*

- **Name: "PinBoard - Pins Your Way"** (24 of 30 characters). That's what the app is already called in App Store Connect and TestFlight. Keep it unless you decide otherwise. App Store Connect checks that a name is unique when you save it; this one is already saved, so it's yours.
  - It's under **App Information › Name**, with the subtitle. You can still change it before the first submission, and later with any new version.
  - On the Home Screen the app is still called "PinBoard" (`CFBundleDisplayName` in the build).
- **Subtitle: "Private mood board & library"** (28 of 30), changed on 5 November 2026 so it reads well under the name: "PinBoard - Pins Your Way" / "Private mood board & library". The old subtitle, "Your private inspiration board", repeated "Your" and "board" from the name. The subtitle carries the words the name lacks: private, mood board and library. App Store search uses both.
- **Promotional text** can be changed at any time without a new build. The other fields change only with a new version.
- **Keywords** name no other company or app (checked: moodboard, collage, scrapbook, ideas, collection, organizer, bookmarks, widget, inspiration, quotes, offline). Words already in the name or subtitle ("pins", "private", "mood", "board", "library") are left out, because Apple counts those anyway. "Inspiration" came back into the keywords when it left the subtitle.
- **Description** names the Explore picture sources (Wikimedia Commons, Openverse, Pexels, Pixabay, Unsplash), because the app really searches them. It doesn't name YouTube, TikTok or other sites whose links the app reads. Since build 16, the app keeps videos from those sites as links (see `review-notes.md`, Risk 1). It no longer says pictures are "never uploaded" either: that isn't true once Cloud AI is on.
- **Description line to check before submitting:** "Every setting is easy to find with search in Settings" is right only once the Settings rework with search is in the submitted build. Delete the line if it isn't.
- **What's New:** App Store Connect doesn't show this field for an app's very first version. Keep the text for the first update, or paste parts of it into the promotional text.

## Screenshots

| Upload slot | Folder | Size |
|---|---|---|
| iPhone 6.3" display (what App Store Connect asked for last time) | `screenshots/iphone-6.3/` | 1206 × 2622 |
| iPhone 6.9" display (if that slot is offered instead) | `screenshots/iphone-6.9/` | 1320 × 2868 |
| iPad 13" display | `screenshots/ipad-13/` | 2064 × 2752 |

Upload in file-name order. Use one iPhone set, whichever size App Store Connect's iPhone slot asks for; Apple scales it for the other iPhones.

They are real screenshots of PinBoard in the iOS 27.2 simulator, taken on 1 November 2026 (around build 7). AI tagging doesn't run in the simulator, so no shot claims AI tags; Search and Apple Intelligence's extra search words are shown because they did run. To remake the framed versions after changing a caption:

```bash
cd AppStore && swiftc -O tools/compose.swift -o /tmp/compose && /tmp/compose tools/iphone-6.3.json screenshots/raw/iphone screenshots/iphone-6.3 && /tmp/compose tools/iphone.json screenshots/raw/iphone screenshots/iphone-6.9 && /tmp/compose tools/ipad.json screenshots/raw/ipad screenshots/ipad-13
```

The demo photos are Unsplash photos (Unsplash License: free for commercial use, no credit required). Photographers are listed in `photo-credits.txt`.

### Which screenshots are out of date (4 November 2026)

Don't retake them yet: a separate session is preparing demo content.

| Shot | Status | Why |
|---|---|---|
| 1 Pins ("Everything you love, in one private place") | Probably fine | The grid looks the same. Retake with the new demo content so all shots match |
| 2 Boards ("Boards that keep themselves tidy") | Probably fine | Retake with the demo content |
| 3 Immersive ("Nothing between you and your pins") | Fine | Still shows the bars sliding away |
| 4 Search ("Find anything by what it means") | Fine | Still the best AI shot the simulator can make |
| 5 Hidden ("A Hidden section only you can open") | **Out of date** | (a) The locked screen still points to "Settings › Safety", which the Settings rework renames to "Privacy & Hidden". (b) The caption "Nothing is uploaded" isn't true once iCloud sync is on: hidden pins sync too. (c) A mostly empty locked screen sells little. Better: the Hidden side unlocked with a few pins, captioned "Locked with Face ID. Hidden everywhere else." |
| iPad 4 Board, 5 Search | Probably fine | Retake with the demo content |

**Missing: none show today's newest features.**

### New shots that would sell the app

In the order to put them (Apple shows the first three in search results):

1. **Pins grid** (keep) — "Everything you love, in one private place".
2. **The share sheet** over Safari or Photos, with the board list showing Suggested and Last used — "Save from any app" / "Pick a board right in the share sheet". This is the feature people will use most.
3. **Widgets on a Home Screen** (a large Photo widget, a Photo Grid and a Quote) — "Your boards on your Home Screen". Very visual; it stands out in search results.
4. **Search** (keep) — "Find anything by what it means".
5. **Boards** (keep) — "Boards that keep themselves tidy".
6. **A pin's page** with AI tags and "Written by AI", taken on a real iPhone (the simulator makes no tags) — "Tagged and titled on your device".
7. **Hidden, unlocked** (replaces today's shot 5).
8. **iCloud sync and Settings search**: Settings › iCloud & storage, or Settings with a search typed — "On all your devices, if you want". Only once Settings search is in the build.
9. *(Optional)* **"Looks familiar"** — the duplicate warning in the share sheet: "Never save the same picture twice."

Up to 10 screenshots are allowed per device size. The iPad set should follow the same order. An App Preview video (up to 30 s) is optional; the video session's demo content could serve it.

## App icon

PinBoard has eight icons. The default is **Mood board** (option 3): a red mood board of white and pink tiles. People can switch to one of the other seven in Settings › Appearance › App icon. That screen lists them in this order: Four kinds (8), Pinned photo (1, the old icon), Push-pin (2), Folded note (4), Card stack (5), Pin P (7) and Snapshot (9). The owner dropped options 6 and 10. `icon/options/contact-sheet.png` shows all eight.

Every icon comes in the looks iOS asks for:
- **light:** 1024 × 1024, opaque, with square corners, because iOS rounds them.
- **dark:** a dark background, with the red made brighter.
- **tinted:** greyscale on black. iOS colours it with the user's tint.

Each icon is also an Icon Composer file (`.icon`), which is what iOS 26 uses for its Liquid Glass icons. It holds the background as a gradient, with a dark version, and the picture as one glass layer. iOS 26 makes the clear and tinted looks from it, and Xcode makes the flat images older iOS versions need. This follows Apple's Human Interface Guidelines, "App icons" (checked 4 November 2026): the same shapes in every look, a subdued dark look, no shadows or glows drawn into the icon, and a dark, clear and tinted look for each alternate icon too.

`icon/options.swift` draws all of them in code:
- `icon/options/NN-name/`: `light.png`, `dark.png`, `tinted.png` and `AppIcon.icon` for each icon.
- `icon/options/contact-sheet.png`.
- `icon/AppIcon-1024.png`: the default icon's light look, the App Store's copy.
- In the Xcode build, `Xcode/App/AppIcon.icon` (the default) and `AppIcon-<Name>.icon` (the others), plus a small light and dark preview of each in `App/Assets.xcassets` (`IconPreview-<Name>`) for the picker.

`make-project.py` names the alternate icons for Xcode (`ASSETCATALOG_COMPILER_ALTERNATE_APPICON_NAMES`). `PinBoard/AppIconPicker.swift` lists the same names.

To change an icon, edit `options.swift`, then remake everything:

```bash
cd AppStore/icon && swiftc -O options.swift -o .icon-options && ./.icon-options options ../../Xcode/App && rm .icon-options
```

To change which icon is the default, change `defaultNumber` and `pickerOrder` in `options.swift`, the alternate names in `make-project.py`, and the order and `iconName` in `AppIconPicker.swift`.

## Other answers App Store Connect asks for

*Checked against the code on 4 November 2026.*

### App Privacy ("nutrition label")

**Choose "Data Not Collected".** This still holds:

- There are no third-party SDKs, analytics, ads or crash reporters in the project. Apple frameworks only.
- The developer runs no server and receives nothing.
- iCloud sync stores the library in the user's *own* iCloud (Apple's service, the user's account). The developer can't access it.
- Link reading, Explore and reverse image search contact other sites directly from the device, only to serve the request.
- **The one grey area is Cloud AI.** When the user turns it on, pictures, board names, tags and link text go to Anthropic or OpenAI. It uses the user's *own* key and account, not a service the developer contracts. Apple counts data as "collected" only when the developer or its partners can access it beyond serving the request, so "Data Not Collected" is defensible.
  - The cautious alternative: declare **Photos or Videos** and **Other User Content**, "Not linked to you", "Not used for tracking", purpose "App Functionality".
  - Whichever you choose, make `PrivacyInfo.xcprivacy` say the same (today its collected-data list is empty, which matches "Data Not Collected").
- Tracking: **No.** The app never needs App Tracking Transparency.

### Privacy policy URL and Support URL (both required): GitHub Pages

The owner's plan: PinBoard is **free and open source (MIT)** in the public repository `silent-diffusion/PinBoard`. Its README is the product page, and support is **GitHub Issues only** (no email). The web pages come from GitHub Pages on that same repository.

**The Pages folder is `docs/`** at the top of the repository (plain Markdown and a `_config.yml` with a built-in theme). In GitHub › Settings › Pages choose "Deploy from a branch", `main`, folder `/docs`. The privacy policy, support page and user guide live only there now, so edit them in `docs/`.

| File in `docs/` | What it is | Web address |
|---|---|---|
| `index.md` | A short landing page: what PinBoard is, the App Store link once live, and links to the pages below | `https://silent-diffusion.github.io/PinBoard/` |
| `privacy.md` | The privacy policy | `https://silent-diffusion.github.io/PinBoard/privacy` |
| `support.md` | The support page | `https://silent-diffusion.github.io/PinBoard/support` |
| `user-guide.md` | The user guide | `https://silent-diffusion.github.io/PinBoard/user-guide` |

- Keep the file names as they are. GitHub Pages turns the `.md` files into web pages and rewrites the links between them (`privacy.md` → `privacy`) by itself, so the links inside the pages keep working. Each page starts with a short `---` block holding its title and web address.
- The feature and design list (`docs/PinBoard-feature-and-design-list.md`) sits in the same folder but is left out of the web site (`exclude` in `_config.yml`).
- **Privacy Policy URL:** `https://silent-diffusion.github.io/PinBoard/privacy`
- **Support URL:** `https://silent-diffusion.github.io/PinBoard/support`. Use the support page, not the bare Issues list: it answers the common questions and leads with the link to Issues. `review-notes.md` Part 2, risk 6, explains why.
- **Marketing URL (optional):** the repository or the Pages landing page.
- The exact addresses follow from the repository name. If the repository is renamed, update them here and in App Store Connect.
- Before making the repository public, see the checklist: secrets, notes and licences.

**Is GitHub Issues enough for App Review?** Yes, with care. Guideline 1.5 asks for "an easy way to contact you". A support page that links a public Issues page meets that.
- The repository must be public, with Issues switched on, *before* you submit.
- Posting needs a free GitHub account. The support page says so; if a reviewer objects, add a simple forwarding address there.
- App Store Connect › **App Review Information** still asks for your name, phone and email. Those are for Apple's reviewers only and never shown publicly.
- In the EU, stay "not a trader" (free hobby app), or your contact details become public.

### Category

**Primary: Photo & Video.** Secondary: **Lifestyle** (or Productivity). App Store Connect sets the category; the build doesn't need one.

### Age rating

- Answer **Yes** to **"Unrestricted Web Access"**. The in-app browser used for reverse image search can reach any site, and Explore shows open web pictures. That gives Apple's highest age rating (18+).
- Answer "None" to the content questions (violence, gambling and so on): PinBoard has no content of its own.
- No user-generated content is shared between users, no chat, no ads, no purchases.
- **To get a lower rating**, the app would have to limit web access: open reverse image searches only in the user's default browser (Settings already has this choice), drop the in-app browser, and filter Explore with each source's safe-search option. Not worth it for a first release unless you care about younger users.

### Encryption (export compliance)

**Exempt.** `ITSAppUsesNonExemptEncryption` is already `false` in `PinBoard-Info.plist`, so App Store Connect won't ask. The app uses only HTTPS and SHA-256 fingerprints (hashing, not encryption).

### Copyright

`2026 <your name>`.

### Availability on Mac and Apple Vision Pro

**The owner's decision: offer both, as the iPad app** ("Designed for iPad" on Apple-silicon Macs, and the iPad app on Vision Pro). That's App Store Connect's default, so nothing needs switching on; just leave both ticked in **Pricing and Availability**. The owner already runs it on a Mac through TestFlight.

Before release, check these on a Mac (and on Vision Pro, or at least the visionOS simulator):

- The Hidden lock: Touch ID or the Mac password on a Mac, Optic ID or the passcode on Vision Pro.
- "+ › Camera" on a Mac without a camera says "This device has no camera."
- Photos import (the system picker), Files import, export and "Save to Files".
- iCloud sync between the Mac and an iPhone, with the same Apple Account.
- The share sheet and widgets. iPad apps may not offer these on a Mac the way they do on iPad. Check, and make sure nothing in the app promises them there.
- A narrow and a wide Mac window: the layout follows the window width.
- Keyboard and pointer: secondary click opens the long-press menus, and Escape and Return work in the sheets.
- Vision Pro: menus open with a look and pinch-and-hold, videos and Quick Look play, and the bars that slide away while scrolling behave.

If one platform isn't ready, untick it in Pricing and Availability. Availability changes don't need a new review.

## Privacy manifest and permission texts (checked 4 and 5 November 2026)

**`Xcode/App/PrivacyInfo.xcprivacy` is correct. Nothing is missing or extra:**

- **UserDefaults: CA92.1, correct.** Per-profile settings use the app's own suites, not the App Group, so 1C8F.1 isn't needed.
- **File timestamps: C617.1 and 3B52.1, correct.** 3B52.1 covers the user-chosen originals folder.
- **System boot time: 35F9.1, correct.** It is used for measuring elapsed time in the video player and transcripts.
- **Disk space: E174.1, correct.** The app checks there's room before rewriting a video.
- Tracking is false, there are no tracking domains, and the collected-data list is empty.
- **The widget and share extensions carry their own manifest** (`Xcode/PinBoardShare/PrivacyInfo.xcprivacy`, `Xcode/PinBoardWidgets/PrivacyInfo.xcprivacy`): no tracking, nothing collected, and UserDefaults with reason `1C8F.1` (defaults shared through the App Group). Their own code calls none of the required-reason APIs today; the UserDefaults line covers App Group defaults if they start using them. Add any new required-reason API to the extension's manifest too.

**`Xcode/PinBoard-Info.plist` usage texts: fixed in build 16** (checked 5 November 2026):

| Key | Text now | Status |
|---|---|---|
| `NSCameraUsageDescription` | "PinBoard uses the camera only to take a photo when you choose Camera from the + menu." | ✅ Fixed (was "photo or video") |
| `NSMicrophoneUsageDescription` | — | ✅ Removed (the app never records sound) |
| `NSPhotoLibraryUsageDescription` | — | ✅ Removed (nothing reads the photo library: imports use the system photo picker, which needs no permission) |
| `NSPhotoLibraryAddUsageDescription` | "PinBoard adds a pin's picture or video to Photos only when you choose Save to Photos." | ✅ Save to Photos now asks for add-only access first |
| `NSFaceIDUsageDescription` | "PinBoard uses Face ID to unlock your Hidden section." | OK |
| `NSSpeechRecognitionUsageDescription` | "PinBoard listens to your videos on this device to write their transcripts. Nothing is sent anywhere." | OK |

**Other things checked and fine:**

- No App Transport Security exceptions and no background modes.
- No location, contacts, tracking or local-network use.
- The entitlements match: iCloud Documents, the key-value store and the App Group in the app; the App Group only in the extensions.
- The `pinboard://` URL scheme is used by the widgets.

**Small note:** API keys live only in the Keychain (`AppSettings.swift`, `SecureStore`). If the Keychain refuses one, the App Store build stores it nowhere and Settings says "Couldn't save the key securely"; only debug builds fall back to the app's preferences. Keys an earlier build left in the preferences are moved into the Keychain. The privacy policy says the same.
