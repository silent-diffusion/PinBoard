---
title: PinBoard Privacy Policy
permalink: /privacy
---

# PinBoard Privacy Policy

*Last updated: 5 November 2026*

PinBoard is a personal library of pictures, videos, notes, quotes and links for iPhone and iPad. It is built so that what you save stays yours: on your device, and in your own iCloud account if you choose to sync.

## The short version

- **The developer collects nothing.** PinBoard has no account, no server of its own, no analytics, no advertising and no tracking. The developer never receives, stores or sees your pins, boards, searches, settings or keys.
- **You can check this.** PinBoard is free and open source (MIT licence). Its code is public at [github.com/silent-diffusion/PinBoard](https://github.com/silent-diffusion/PinBoard).
- **Your library stays on your device** unless you turn on iCloud sync, which keeps a copy in *your own* iCloud account.
- **Some features use the internet, and only when you use them:** web picture searches, reading the links you save, and the optional Cloud AI and iCloud sync, which are off until you switch them on. Each is explained below.
- **Offline mode** (in Settings) switches all of PinBoard's network features off at once. Everything else keeps working.

## What we collect

Nothing. There is nothing for us to collect into: PinBoard has no account system and no server. It contains no third-party analytics, advertising or tracking code.

## Where your library is kept

- **On your device.** Everything you save is stored in PinBoard's own storage on your iPhone or iPad. Like other apps' data, it is included in your device backups (iCloud Backup or a backup on your computer) unless you turn that off in iOS Settings.
- **Profiles** are completely separate libraries, each with its own settings. They are all kept on the device in the same way.
- **API keys** you enter (for Explore's picture sources, YouTube or Cloud AI) are kept in this device's Keychain, per profile. (If the Keychain ever refuses to store them, they are kept in PinBoard's own preferences on this device instead.) They are never put in your library, your exports or iCloud sync, and each key is sent only to the service it belongs to.
- **Location in photos.** If a photo you save contains a location, PinBoard keeps it only so it can be written back into your exports. It is never sent anywhere.

## iCloud sync (optional, off by default)

If you turn on **Sync with iCloud Drive** for a profile, that profile's library — pins, boards, pictures and videos, including the Hidden side — is stored in PinBoard's folder in **your own iCloud Drive** and merged with your other devices signed in to the same Apple Account. Most of that profile's settings travel through iCloud too, so your devices look and behave the same. API keys, the Hidden lock and a few device-only choices never travel.

- iCloud is Apple's service. Your data is stored by Apple under Apple's terms and privacy policy, not on any server of ours. The developer has no access to your iCloud account.
- If you have Advanced Data Protection turned on for iCloud, iCloud Drive data is end-to-end encrypted by Apple.
- **Optimize device storage** (optional) lets older full-size files live only in your iCloud and brings them back when you open them.
- To remove synced data, turn sync off and delete PinBoard's data in iOS Settings › your name › iCloud › Manage Account Storage. Deleting a profile in PinBoard removes it from this device only.
- PinBoard writes a short **Sync log** on your device to help you see what a sync did. It stays on the device and is never sent anywhere.

## When something leaves your device

Only when you ask for it, or after you switch a feature on.

**Searching for pictures (Explore and web ideas).** When you search, your search words are sent to the picture source you chose: Wikimedia Commons (the default), Openverse, Pexels, Pixabay or Unsplash. Web ideas on a board's or a pin's page are found the same way: their search words are made on your device from the board's name, your tags and pin titles, and only those words are sent. They wait for your tap unless you turn on "Automatically load web suggestions"; hidden boards never load them. If you added your own key for a source, the key is sent to that source. Searches use a throwaway connection that keeps no cookies or stored data.

**Links you save.** When you save a link (or share one to PinBoard), PinBoard visits that page once to read its title, picture and text, the way a web browser would, and downloads the pictures it needs. Depending on the page, it may also ask that site's own public sharing service for the details (for example for social media posts). A video on a social site or inside a web page is kept as a link with its picture; nothing of it is downloaded. Only a link that is itself a video file (such as one ending in .mp4 or .mov) is downloaded, like a browser would. The website sees an ordinary visit from your internet address. PinBoard keeps no cookies between visits. You can turn link reading and previews off in Settings › Links.

- **"Find a picture for links without one"** (off by default): when a saved page has no picture, the page's title is sent as search words to your chosen picture source. Links on the Hidden side are never searched for.
- **YouTube.** A YouTube link's title, channel and picture come from YouTube's public sharing service. If you add your own YouTube Data API key, it is sent to YouTube (Google) to fetch more details and the video's top comments. Nothing of a YouTube video is ever downloaded. "Play" uses YouTube's own embedded player in its privacy-enhanced mode, which YouTube handles under the [Google Privacy Policy](https://policies.google.com/privacy) and [YouTube's Terms of Service](https://www.youtube.com/t/terms).
- **Opening a link** opens your default browser, outside PinBoard.

**Searching the web for a picture.** If you choose to search for a picture (Google Lens, Bing, TinEye or Yandex), PinBoard uploads nothing itself. For a picture that came from the web, it passes that picture's web address to the site. For a picture that lives only in your library, it opens that site's search page and gives you the picture — on the clipboard of this device for two minutes, or, if you chose that in Settings, as a copy in Files or Photos — so that *you* can paste or upload it there. That site then handles the picture under its own privacy policy. PinBoard's own browser keeps no cookies, history or cache.

**Optional Cloud AI** (off by default). PinBoard's AI runs on your device. If you want sharper tags and titles, you can add your **own** API key for Claude (by Anthropic) or OpenAI. Before anything is sent, PinBoard shows a screen that names the company the pictures go to (Anthropic or OpenAI), lists exactly what will be sent and links that company's privacy policy. Nothing is sent until you agree, and choosing the other company later asks you again. When it is on, for each new picture PinBoard sends to the provider you chose:

- a copy of the picture, shrunk to at most 1,024 pixels, with all metadata (location, camera, dates) removed;
- the names of the boards it is on (never the names of hidden boards) and the tags you gave it;
- for a link, up to 1,500 characters of the text read from its page, with its preview picture.

Your notes, your location, the words spoken in your videos and your other pictures are never sent. Pins on the Hidden side are **not** sent unless you turn on **Include hidden pins in AI** (off by default; see below). Even then, the names of hidden boards are never sent. The provider receives your key and bills you directly; PinBoard and the developer never see what is sent or returned. Anthropic and OpenAI handle what they receive under their own privacy policies and API terms ([Anthropic](https://www.anthropic.com/legal/privacy), [OpenAI](https://openai.com/policies/privacy-policy/)). You can turn Cloud AI off at any time.

**On-device AI and Apple Intelligence.** Tagging, reading text in pictures, writing down speech in videos, search, look-alike checks and board suggestions all run on your device. On devices with Apple Intelligence, PinBoard may use Apple's on-device model to suggest titles and search words; it is given words only, never your pictures. When PinBoard first writes down speech in a video, iOS may download its speech-recognition language files from Apple. You can turn "Transcribe speech in videos" off in Settings › Videos.

**AI and the Hidden side.** Pins on the Hidden side get **no AI at all** unless you turn on **Include hidden pins in AI** (off by default). While it is off, none of the AI described here looks at them: no on-device tagging, no Apple Intelligence titles or search words, no writing down of speech and no Cloud AI. Only plain, rule-based steps still handle them: the fingerprints used to spot exact and look-alike duplicates, and word search within Hidden. If you turn it on, hidden pins are treated like the rest, except that the names of hidden boards are never sent to Cloud AI.

Each service named above handles what it receives under its own privacy policy.

## The share sheet

PinBoard's share sheet ("Save to PinBoard" in other apps) runs on your device. What you share is saved into a private folder on your device that only PinBoard and its extensions can read (an "App Group"), and PinBoard adds it to your library the next time you open it. To offer your boards, suggest a board and warn about look-alikes, PinBoard keeps a small list of your boards, tiny thumbnails and fingerprints of your pins in that same folder. Nothing from the Hidden side is ever put there. The share sheet sends nothing anywhere; a shared link is read later by the app itself, as described above.

## Widgets

PinBoard's widgets show pictures and quotes from the boards you choose. To do that, PinBoard keeps a small set of small copies of pictures and quote texts in the same private on-device folder. Hidden pins and boards are never included. Remember that widgets are visible to anyone who can see your Home Screen.

## The Hidden side

Pins and boards you hide are kept behind Face ID, Touch ID or your device passcode. PinBoard never sees your face or fingerprint data; iOS only tells it whether unlocking succeeded. Hidden content is still part of your library on the device: it is included in device backups, in iCloud sync when that is on, in an export if you choose to include it, and in the AI (on the device and Cloud AI) only if you turned on **Include hidden pins in AI**.

## Permissions PinBoard may ask for

- **Camera** — only when you choose to take a photo for a pin.
- **Photos (add only)** — to add a picture or video to your Photos library when you choose "Save to Photos". PinBoard never changes or deletes anything already there. Picking photos to import uses the system picker, which shows PinBoard only the items you pick.
- **Face ID** — to open the Hidden side.
- **Speech recognition** — to write down the words spoken in your videos, on your device.

You can change these at any time in iOS Settings › PinBoard.

## Exports and deleting your data

- An export goes wherever you choose to save or send it. If you include hidden boards, the exported files are ordinary, unprotected files.
- Deleted pins wait 30 days in Recently Deleted, then are erased.
- Deleting a profile, or deleting the app, removes that data from the device. Data in your iCloud is removed as described in the iCloud section.
- Because the developer holds none of your data, there is nothing we can look up, hand over or delete for you: you are in full control of it on your devices and in your iCloud account.

## Crash reports

If you have chosen in iOS to share analytics with app developers, Apple may pass PinBoard's crash reports to the developer. They describe what went wrong in the app, not what is in your library. You can change this in iOS Settings › Privacy & Security › Analytics & Improvements.

## Children

PinBoard is not directed at children and collects no data from anyone.

## Changes

If this policy changes, the new version will be posted at this address with a new date at the top.

## Contact

PinBoard has no email support. Questions about privacy are welcome on the project's GitHub Issues page: **[github.com/silent-diffusion/PinBoard/issues](https://github.com/silent-diffusion/PinBoard/issues)**. Issues are public, so please don't post pictures or details you want to keep private.
