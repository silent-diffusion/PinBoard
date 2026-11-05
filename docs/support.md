---
title: PinBoard Support
permalink: /support
---

# PinBoard Support

PinBoard is a private inspiration library for iPhone and iPad. Save pictures, videos, GIFs, notes, quotes and links as pins, gather them on boards, and find anything again by what it shows or says. There's no account, no ads and no tracking, and the AI that tags and sorts your pins runs on your device.

PinBoard is free and open source (MIT licence): [github.com/silent-diffusion/PinBoard](https://github.com/silent-diffusion/PinBoard).

## Get help or report a problem

PinBoard is made by one person and has no email support. Questions, bug reports and ideas all go to the project's GitHub Issues page:

**→ [github.com/silent-diffusion/PinBoard/issues](https://github.com/silent-diffusion/PinBoard/issues)**

1. Search the existing issues first: your question may already be answered.
2. To open a new one, tap **New issue**. Posting needs a free GitHub account; reading doesn't.
3. Say which device and iOS (or macOS) version you use, and what you did just before the problem. For sync problems, paste the Sync log (see below).

**Issues are public.** Don't post pictures, link addresses, API keys or anything else from your library that you want to keep private. Remove anything personal from a Sync log before pasting it.

New to PinBoard? The [user guide](user-guide.md) walks through everything.

---

## Frequently asked questions

### Do I need an account?
No. PinBoard has no account and no server. If you turn on iCloud sync, it uses the iCloud account already on your device.

### How do I sync between my iPhone and iPad?
On each device, open **Settings › iCloud & storage** and turn on **Sync with iCloud Drive**. Both devices must be signed in to the same Apple Account with iCloud Drive on. The first sync on a new device brings your pins in batches, and the count climbs as they arrive ("Syncing with iCloud… 200 of 2,500"). Large libraries can take a while; keep PinBoard open for the first sync if you can.

Each profile syncs on its own. Profiles pair up across devices by name: "My library" on your iPhone syncs with "My library" on your iPad. To sync another profile, make one with exactly the same name on the other device.

### Sync seems stuck. What can I do?
1. Check that iCloud Drive is on and that the device has space in iCloud.
2. Look at **Settings › iCloud & storage › Sync log**. It lists what each sync did and how long each step took. A line such as "files from this device are still being sent to iCloud" means the *other* device hasn't finished uploading yet; open PinBoard there and give it time.
3. Tap **Sync now**. You can also pull down on any grid to sync.
4. Still stuck? Use **Copy** on the Sync log page and paste it into a new issue (see the top of this page). The log stays on your device unless you share it, and it lists counts and timings, not your pins.

### What is "Optimize device storage"?
An optional setting under **iCloud & storage**. Full-size pictures and videos you haven't opened for 30 days are kept only in iCloud; their thumbnails stay on the device, so your grids and search still work. A file comes back when you open it.

### How does the Hidden side work?
Hidden is a private part of your library, reached from **Boards › ⋯ › Hidden…**. To hide something, touch and hold a board and choose **Hide board**, or choose **Hide pin** on a pin. Hidden pins never appear in your feed, search, suggestions, widgets or the share sheet. Opening Hidden asks for Face ID, Touch ID or your passcode, and it locks again when you leave the app. You can turn the lock off in **Settings › Privacy & Hidden**.

### Why don't my hidden pins have AI tags?
On purpose. By default the AI leaves the Hidden side completely alone: no tagging, AI titles, transcripts, Apple Intelligence or Cloud AI. Hidden pins can still be found by their titles, notes and your own tags, and duplicates are still spotted. If you'd like the AI to work on them too, turn on **Include hidden pins in AI** in Settings.

### I can't use Face ID. Can I still open Hidden?
Yes. If Face ID or Touch ID fails or isn't set up, iOS asks for your device passcode instead.

### How do I back up my library?
- **Export:** **Settings › Library › Export all pins and boards…** makes a folder per board (or a zip) with every pin's title, tags and notes written into the pictures. Save it to Files, a computer or a drive.
- **Import:** **Import a folder…** brings an export back exactly, or turns any folder of pictures into boards.
- **iCloud sync** keeps a copy in your iCloud, and your device backups include PinBoard's data.
- PinBoard also keeps two safety copies of the library file: **Settings › Library › Recover library**.

PinBoard reminds you to export after you've added 50 new pins.

### I deleted something by mistake.
Deleted pins wait 30 days in **Settings › Library › Recently Deleted**, where you can restore them.

### What are profiles?
Completely separate libraries on one device, for example "Personal" and "Work". Each has its own pins, boards, Hidden side, settings and iCloud choice. Make and switch profiles in **Settings › Library › Profiles**.

### How do I save things from other apps?
Tap the Share button in Photos, Safari, Files, Messages or another app and choose **PinBoard**. If you don't see it, scroll the row of apps to the end, tap **More**, and switch PinBoard on. In the sheet you can choose a profile and a board (suggested boards and your last-used one are at the top), make a new board and add a note. PinBoard adds what you shared the next time you open it.

Prefer one tap? Turn off **Choose a board when sharing** in **Settings › Pins & boards**, and sharing saves straight to Unsorted.

### How do I add a widget?
Touch and hold your Home Screen, tap **Edit › Add Widget**, and search for PinBoard. Choose Photo, Photo Grid or Quote and a size. Then touch and hold the widget, choose **Edit Widget** and pick a board. The widget shows something new every hour; tap it to open that pin. Hidden pins are never shown in widgets.

Two widgets on the same board? Give each a different **Pick** (1st, 2nd…) so they don't show the same picture.

### What is Cloud AI, and do I need it?
You don't need it. PinBoard's AI runs on your device. Cloud AI is an optional extra that sends a small copy of each new picture to Claude (Anthropic) or OpenAI, using **your own** API key, for more specific tags and titles. PinBoard names the company, shows exactly what is sent and asks before turning it on. Hidden pins are never sent unless you turn on **Include hidden pins in AI**. See the [privacy policy](privacy.md).

### Does PinBoard work offline?
Yes. Everything except web searches, link reading, Cloud AI and iCloud sync works without a connection. **Offline mode** in Settings switches all of those off at once.

### Can I find a setting quickly?
Yes: type in the search field at the top of Settings.

### Does PinBoard work on a Mac or Apple Vision Pro?
Yes. On a Mac with Apple silicon (M1 or later) and on Apple Vision Pro, you can install PinBoard from the App Store; it runs as the iPad app. Your library on each device is separate unless you turn on iCloud sync. Some things that are part of iPhone and iPad, such as Home Screen widgets and Face ID, work differently there: on a Mac, Hidden opens with Touch ID or your Mac's password, and on Vision Pro with Optic ID or your passcode. If something doesn't work on your Mac or Vision Pro, please open an issue.

---

[Privacy policy](privacy.md)
