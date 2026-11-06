# PinBoard — the complete feature and design list

*What the app is, screen by screen, so that someone who has never seen it could build it again almost exactly. It describes what the user sees and what happens; it says nothing about how the code is organised.*

*Last updated for build 16 (4 November 2026): the App Review safety changes — videos from TikTok, Instagram, Reddit, X, Pinterest and web pages are no longer saved, YouTube is read only through its own services, the Cloud AI consent names the company, Unsplash credits and download reports, add-only Photos access, and the Swift Playgrounds leftovers (the built-in keyboard, the "capability" texts) removed.*

**How to read it.** Every section is a screen or a theme, in the order a user meets them: the library's rules, the design conventions, the four tabs, the pin page, Quick Look and the player, boards, Hidden, smart boards, Search, Explore, the AI, every Settings row, storage and data. Text in "quotes" is the app's exact wording (titles, menu items, buttons, toasts, footers). Names in `code type` are the system symbol (SF Symbols) names of icons. Numbers in brackets such as (10.3) point to the section that holds the detail; ‹angle marks› stand for a value filled in at the time, such as a board's name. **†** marks what was added in the latest round: built and checked, but not yet run on a device. Section 24 lists what was asked for but not built; 25 the questions still open; 26 the quirks a recreation may want to fix rather than copy.

## Contents

- 1. What PinBoard is
- 2. The library: what things are and the rules between them
- 3. Design conventions that hold everywhere
- 4. The app frame
- 5. The Pins tab
- 6. The grid and the cards
- 7. The pin menus
- 8. Adding pins
- 9. Links
- 10. The pin page
- 11. Quick Look
- 12. The video player
- 13. The Boards tab
- 14. A board's page
- 15. Board commands and AI sorting
- 16. The Hidden section
- 17. Smart boards
- 18. The Search tab
- 19. The Explore tab
- 20. The AI
- 21. Settings
- 22. Storage
- 23. Your data
- 24. Asked for but not built, or not possible
- 25. Open questions for the owner
- 26. Known quirks

## 1. What PinBoard is

PinBoard is a personal Pinterest-style library of pictures, videos, text and links for iPad and iPhone. You save things as pins, arrange them on boards and find them again by what they show or say. Everything is stored on the device, with no account and nothing posted for anyone else to see. The AI that tags, titles, searches and suggests boards also runs on the device and cannot be switched off. Apple Intelligence adds more natural titles and search words on devices that have it (it only ever sees words, never pictures), and a cloud vision model exists only if you add your own key and agree to it. Nothing else leaves the device unless you switch it on or start a web search yourself (3.5). It is for one person who wants a private reference or inspiration library that organises itself, with a locked Hidden section, back-up reminders and a full export.

**† = added in the latest round; built and checked, but not yet run on a device.** The mark follows the heading or item it applies to.

## 2. The library: what things are and the rules between them

One library per profile (2.8) holds pins, boards (which hold sub-boards), smart boards and a memory of what was erased. It has two sides that never mix, the normal side and Hidden (2.6).

### 2.1 Pins — the four kinds and what each holds (what the user can see of it)

- **Picture ("Photos", icon `photo`).** One picture kept as a JPEG of at most 2,048 px on its long side (quality 0.9, turned upright) plus a grid copy of at most 700 px. The Photos app is never changed; a full-size original can be kept in a Files folder (22.2). The pin remembers what the photo file holds (date taken, camera, keywords, caption, a title of its own, and whether it had a location, shown only as "Has location data (kept for export only, never sent)") and, for a saved web result, its page address and a credit such as "Photo by … · Pexels". It can be cropped, rotated and flipped (7.2).
- **Text ("Text", `text.alignleft`).** An optional title and a text, no picture. The card is a small page of text styled in Settings › Appearance › Text pins (21.3); the words change only with "Edit text" on its page (10.3). A **quote pin** † is a text pin made from a highlighted passage of an article, titled after the article and filed with it (9.3).
- **Video ("Videos", `play.rectangle`).** A video file with a poster picture (its thumbnail, used by the grid, the AI and search), a length (badge "m:ss", or "Video" until known), a sound-track flag and what is said in it †. The stored copy is converted to the chosen quality (22.1; default "1080p").
- **Link ("Links", `link`).** An address (tracking removed while "Clean links" is on, default on), a title (the site's name, such as "example.com", until the page's own arrives), a description and an optional preview picture, possibly a stand-in † (6.2). Read fully ("Read links fully", default on), it also holds an article's text, writer and date, the site name, the linked page, a video's views and length, a YouTube video's top comments (needs a key) and your highlights †. Its link details name what it turned out to be: "Web page", "Article", "YouTube video", "Pinterest pin", "Picture from the web" or "Video from the web" (9.2). A link to a picture file becomes a Photos pin, one to a video file (.mp4, .mov) a Videos pin, and a Pinterest picture pin its own picture; a video on TikTok, Instagram, Reddit, X, Pinterest or inside a web page stays a link pin with its picture † (9.2). Addresses that differ only in tracking, capitals, "http" versus "https" or a trailing "/" are the same page (8.4).

Every pin also has a title and its author (2.2), a note and tags (2.3), boards (2.4), a source address and credit line (the address can be edited †, 7.3), and a **date added**. The date added orders "Newest first" / "Oldest first" and the date filters; editing never changes it, and it is not the date a photo was taken. Flags you can see: hidden (2.6), kept out of All (2.7), "Tagging…" until the AI has looked at it, and "Duplicate?" on the newer of two look-alike pictures (20.8).

### 2.2 Titles and who wrote them (you / imported from a page or file / the AI; protection rules)

Every title has an author, and the author decides whether the AI may replace it.

| Author | Where the title comes from | May the AI replace it? |
|---|---|---|
| You | Typed or chosen by you: "Edit title", a text pin's title field, "Edit link", the title kept when two duplicates merge | Never by itself; only "Rename with AI" and "Rename all with AI…" do |
| Imported | A tidied file name (underscores and hyphens become spaces; camera-style names such as "IMG_1234" are dropped), a title stored inside a photo file, a page's own title, a web result's title (cut to 60 characters), an article's title on a quote † | Not by itself; a newer page title may replace a link's when the page is read again, unless you typed one |
| The AI | The pin has no title, or still has exactly the title the AI last wrote; the page shows "Written by AI" | Yes, while nobody has edited it |

- A title you type while the AI is still working on the pin stays.
- A new link starts with the site's name as the AI's placeholder until the page's own title arrives; a cleared link title returns to the site's name.
- When the AI replaced an earlier title and the pin still carries the AI's, the page offers **Undo** and the line "was “‹previous title›”"; Undo restores the old title with its author. The first title of an untitled pin cannot be undone; a name you wrote is never lost. A whole run is undone with "Undo last AI naming" (15.2).
- Settings › AI › "Write titles for untitled pins" (default on) switches automatic naming (21.7); how a title is made: 20.2. A pin may have no title; its card then shows no title line.

### 2.3 Tags: yours, the AI's, colours, words read in the picture; notes

| Kind | Comes from | Listed under | Chip |
|---|---|---|---|
| Your tags | You typed them, or tapped an AI chip to keep it | "Your tags"; Search; smart boards; the tag manager (23.4) | Accent text on a 14 % accent tint, trailing `xmark`; tap removes. VoiceOver "Remove tag ‹tag›" |
| AI tags | The on-device recogniser (and the cloud model, if on) | "AI tags" | Secondary background, trailing `plus`, text "‹label› NN%" (confidence cut down, so 0.876 reads "87%"); tap keeps it as yours. VoiceOver "Add tag ‹text›" |
| Colour tags | The picture's dominant colours | "AI tags", no percentage | Like an AI tag |
| Words read in the picture | Key words of text found in the picture | "Text in this image" | Like an AI tag with a leading `text.quote` |

- Chips are capsules with 12 pt side and 7 pt vertical padding and one line of subheadline text (cut with "…"); they flow left to right, wrap, and sit 8 pt apart.
- A tag is one phrase, trimmed and lower-cased, never added twice to a pin; commas do not split it. A tag you keep leaves the AI list.
- While you type a tag, up to 12 suggestions appear, yours first (`person`) then the AI's (`sparkles`, only tags it is at least 30 % sure of), taken only from pins on the same side of the hidden line.
- Tags are edited on the pin's page ("Add a tag", "Add") and for several pins with "Edit tags…" (14.5).

**Notes.** A note is free text under the title ("Add a note" in grey when empty; sheet "Note", hint "Anything you want to remember about this pin."). The AI never writes or edits it, except that a video's spoken words † are added after your text (20.10). Notes count in search and are written into exported pictures; they are never sent to the cloud model.

### 2.4 Boards, sub-boards, Unsorted; the nesting rule; counts; covers; favourites; order; dates

- **Boards.** A named collection; a pin may be on several or none. Boards hold sub-boards to any depth; a path reads "Travel › Beaches". Names are trimmed, an empty name is refused, two boards may share a name.
- **Unsorted.** Pins on no board of their side: after their last board is removed, or deleted with "Delete board, keep its pins", or when dropped on the Pins tab.
- **The nesting rule.** A pin is never on a board and on a board inside it; only the deepest is kept. A pin on a sub-board counts as on every board above it: their counts include it and their page lists it while that page includes sub-board pins (Settings › Pins & boards › "Board pages include sub-board pins", default on; each page has an "Include pins from sub-boards" switch, 14.1), never twice. Adding a pin to a board has four outcomes: already there, nothing changes; on one of its sub-boards, it stays there; on a board this one sits inside, it moves down onto this one; otherwise it is added besides its other boards. The rule is re-applied after every load, sync, board move, merge and unhide. Toast wording: 7.2.
- **Counts.** A board's pin count includes its sub-boards' pins, each once; its sub-board count is its direct sub-boards. A normal board never counts or lists hidden pins.
- **Covers.** A tile's first, large picture is the cover: the one you chose while its pin is still on the board or a sub-board, otherwise the newest pin. Set with "Change cover…" on a board or "Use as board cover" on a pin (7.2); cleared when its pin is deleted, erased or hidden.
- **Favourites.** "Add to favorites" / "Remove from favorites" puts a yellow star on a board. Favourites come first in every board list whatever the sort (the Boards tab lists those of any depth, a sub-board adding "in ‹parent›"). Favouriting is not an edit.
- **Order.** "Sort boards": "Custom order" (default; a new board goes to the end of its siblings), "Name (A–Z)", "Recently edited", "Recently added to" — one choice for every board list on both sides. "Reorder boards" moves a board among its siblings and switches the sort to "Custom order" (13.1).
- **Dates.** A board keeps Created, Edited, Last added and Opened N× (this device only), showing the latest of itself and its same-side sub-boards. What counts as an edit: 13.1; how the dates read: 13.2, 14.1.

### 2.5 Smart boards (what they are; detail in 17)

A smart board is a saved search (words, filters, sort) that holds no pins and never changes one; its contents follow the library. It has a name, its rule, the pins you removed from it ("Bring back removed pins" restores them), a hidden flag and a place in its own manual order. A normal smart board searches normal pins only, a hidden one hidden pins only. A normal one is never limited to a hidden board: hiding, merging away or deleting the board it was limited to takes the limit off ("Any board"). They are listed under "Smart" on the Boards tab (13.1) and made from Search or the Boards tab (17.1).

### 2.6 Hidden pins and boards — every rule (what hidden things never do)

Hidden is a second, private side of the library, reached only through Boards › ⋯ › Hidden… and locked behind Face ID, Touch ID or the passcode (16.1).

**What counts as hidden**

- A board is hidden when you hid it or when it sits inside a hidden board, to any depth.
- A pin is hidden when you hid it ("Hide pin") or when it is on any hidden board. Hidden wins: a pin on a hidden and a normal board is hidden, stays filed on the normal board out of sight, and that board never lists or counts it.
- A hidden pin never falls into the normal library by itself; only "Unhide pin(s)", "Unhide board(s)" and moving a board out of a hidden board do that.

**How things cross the line**

- "Hide pin" remembers the normal boards the pin was on and leaves them (hidden boards stay); a normal board that used it as cover reverts to automatic. "Unhide pin(s)" puts it back on those remembered boards that still exist and are normal, leaves its hidden boards, and with none left makes it Unsorted. Toasts: 7.2.
- "Hide board" hides everything inside it. "Unhide board" brings back the sub-boards hidden only through it; one hidden on its own stays hidden, and a board hidden only through its parent cannot be unhidden alone. Moving a board into or out of a hidden board changes its side with everything inside it.
- Adding a pin hidden on its own to a normal board makes it normal again; adding a pin on a hidden board to a normal board leaves it hidden. Removing a pin from its last hidden board, deleting a hidden board, and deleting or restoring a hidden pin all leave it hidden. Deleting a normal board that holds a hidden one moves that board to the top of Hidden. New pins saved from Hidden land in Hidden.

**What hidden things never do**

- Appear, count, be searched, suggested or named on a normal screen: the Pins tab and its counts, boards, Search, smart boards, "More like this", board suggestions, "Sort into boards", Start here's proposals, duplicates, tag lists, Settings' counts, the back-up reminder and the status pill.
- Appear by name in a message: toasts, questions and alerts say "a hidden board", "Hidden" or "Delete this board?"; an article's title is never told across the line.
- Mix with the normal side: a hidden pin is compared only with hidden pins (look-alikes, "More like this", suggestions; an import into Hidden says "Already in Hidden"), is offered only hidden boards, and the same address on the other side is a different pin.
- Reach the AI by name: hidden pins are looked at only after all normal pins, and hidden boards' names never reach titles, Apple Intelligence or the cloud model With "Include hidden pins in AI" off (the default, build 17 †) no AI of any kind looks at a hidden pin; only the fixed checks do (20.11).
- Stay visible when the app is not in front: hidden screens and sheets are covered at once (4.3), and Hidden closes and locks when the app goes to the background, the profile changes or you choose "Lock now" (16.1). Settings › Privacy & Hidden › "Ask for Face ID, Touch ID or passcode" (default on) controls the lock; a device with no passcode opens Hidden without asking.
- Be kept out of All (hidden pins are never in All).

Hidden has its own AI sorting, order of pins, Recently Deleted, duplicates and tags in its ⋯ menu (16.2). An export asks "Include hidden boards in the export?" and what it then holds is unprotected; iCloud sync carries hidden things like everything else (23.2, 23.3).

### 2.7 Kept out of All — every rule

- "Keep out of All" takes pins off the Pins tab's "All" feed without hiding them. They stay on their boards, in Unsorted (when on no board), in Search, smart boards and "More like this", are counted as usual, and are listed under "Kept out (N)" (5.1).
- A pin is kept out when it was kept out on its own, or sits on, or inside, a board that keeps its pins out; a board's setting covers all its sub-boards and one such board is enough.
- Normal side only. The pin commands are "Keep out of All", "Show in All" and the dimmed note "Kept out by its board" (7.2); board commands: 15.1. "Show in All" on a pin clears only the pin's own setting. Setting it on a board is not an edit of the board. A quote pin † is kept out when its article is.

### 2.8 Profiles (separate libraries); what is saved; back-ups (detail in 23)

- **Profiles.** A profile is a completely separate library: its own pins, boards, smart boards, tags, Hidden section, Recently Deleted, duplicate answers, "Undo last AI naming" memory and files. Each profile also has its own settings (23.1): iCloud sync on or off, Offline mode, look, API keys, originals folder and the rest. The first profile is "My library". Profiles are made, renamed, switched and deleted only in Settings › Library › Profiles (23.1). Switching saves first, locks Hidden, sends every tab back to its root screen, reshuffles every feed (6.1) and stops all work for the old library (AI, conversions, transcription †, imports, sync).
- **Saving.** Changes are saved on the device about 0.4 s after the last one (3 s after quiet background results), but never more than about 2 s (or those 3 s) after the oldest unsaved change, so a stream of changes (the AI tagging pin after pin) can't keep putting the save off. Bulk changes save at once and the import waits for the write before saying it's done: an import of any kind ("Import a folder…", the share-sheet inbox, every "+" import), a restore from a backup, a sync's merge, and "Remove AI tags from hidden pins". A switch of profile saves the old library first. A save still waiting starts when the app becomes inactive (closing it from the App Switcher may never reach the background), and the app also saves at once, finished before it goes on, when it goes to the background (build 18). Two safety copies are kept, one about ten minutes old and one from the day before; an unreadable library file is never overwritten but set aside (23.4).
- **Deleting is not erasing.** A deleted pin waits 30 days in Recently Deleted, then is erased (23.4); erased things are remembered so other devices erase them too.
- **Back-ups.** The only copy outside the device is one you make: "Export all pins and boards…" (a zip or folders, one per board, with each pin's title, tags and notes written into the picture's metadata, plus a file for exact re-import) and "Import a folder…", which re-creates a PinBoard export whole, every field of every pin as it was †, or reads a plain folder whose sub-folders become boards (23.3). After 50 new normal pins without an export the back-up reminder appears (4.2). Optional iCloud sync ("Sync with iCloud Drive", default off) keeps a copy per profile in the app's iCloud Drive folder, the newest change winning (23.2).

## 3. Design conventions that hold everywhere

### 3.1 Platforms, windows and sizes (iPad, iPhone, size classes, wide vs narrow; Mac not targeted)

- PinBoard is one app for iPad and iPhone; nothing exists on only one of them. Layouts follow the width of the window, not the device, so a narrow iPad window behaves like an iPhone. There is no Mac layout, menu bar or pointer styling; a secondary click opens the long-press menu.
- **Wide window** (full-screen iPad, wide split) versus **narrow** (iPhone, narrow split, slide-over) changes: where the tab bar sits (4.1); the grid's columns (6.1) and board tiles' (13.2); one pin-page column or two (10.1); how the selection bar, back-up reminder and the crop screen's shape picker re-flow (6.5, 4.2, 7.5).
- **Sheets** ask for "medium and large" (half height, pulled up to full) or "large"; iPad presents them its own way, usually as a centred form sheet. The "Original" viewer, the link reader, the "YouTube" player and the private browser are page-sized on iPad (iOS 18 and later). A **question** is an action sheet with "Cancel" on iPhone, and on iPad a popover beside the control, without "Cancel" (tap outside).
- **Segmented switches †** (Pins "Filter", Boards / Smart, Hidden's five sections, a pin page's "More like this" / "From the web") never cut a label short with "…" (`FittingSegmentedPicker`). They try in turn: equal segments at the usual 13 pt (footnote, following the text size); segments sized by their words; 12 pt, then 11 pt; at a larger text size that is not an accessibility size, 11 pt whatever the text size (the system control never grows with it either); only at the accessibility text sizes, when nothing fits, one full-width menu button with the chosen section's name and `chevron.up.chevron.down`, listing all sections with the same words (VoiceOver: the switch's name and the chosen section). On a 375-pt iPhone Hidden's five sections fit at 12–11 pt; from 402 pt (iPhone 17, the iPhone Duo's outer screen at 466 pt, iPad) at the usual size. Settings' Appearance switch and the crop screen's shape row keep their own (short labels; the crop row already turns into a menu).
- Two iPad windows share the library and profile; each has its own tab, pages, Settings sheet and questions.
- On iOS 26 and later toolbar buttons are plain `plus` and `ellipsis` on their own glass circles and toasts are Liquid Glass; before it they are `plus.circle.fill` (title2) and `ellipsis.circle`, and toasts a regular material with a soft shadow. The app runs on iOS 17 and later; the newer looks and behaviours named here switch on where the system has them.

### 3.2 Appearance: accent themes, dark mode, Increase Contrast, Dynamic Type

- **Theme** (Settings › Appearance › "Theme"): "System" (default), "Light", "Dark", for every screen and sheet, Settings included. Always dark whatever the theme: Quick Look, the crop screen, the "Original" viewer, the "YouTube" sheet. Palette pictures are always white. A sheet or field takes the look of the screen it opened from.
- **Accent colour** ("Accent color": 34-pt circles in 44-pt targets): Red #E60024 (default), Coral #FF665C, Orange #FF8C1A, Gold #D9A61A, Green #33A85C, Teal #1A9EA8, Blue #1F7AF2, Indigo #5957D6, Purple #9E4DD9, Pink #F24D9E, Graphite #595961, or "Any other color" (system picker, no opacity, starting at #E6002B). It tints buttons, selection, toggles, links, chips, the pill's sparkles, toast symbols and drop outlines.
- **Adaptation**, for themes and a picked colour alike. Dark mode: brightness raised 35 % of the way to full, saturation × 0.9, then, if still under 3 : 1 against #2C2C2E, lightened in 3 % steps until it reaches that. Increase Contrast: darkened (light mode) or lightened (dark mode) in 3 % steps until text in it reaches 4.5 : 1 against the grey background (#F2F2F7 light, #2C2C2E dark).
- **Other colours.** Yellow only for the favourite star, green only for "saved" checks and "Photos added", red for destructive buttons.
- **Dynamic Type.** All text follows the iOS text size; layouts re-flow rather than cut (selection bar, back-up reminder, "Looks familiar" bulk buttons, toasts), while strictly one-line items are cut with "…". Empty-state symbols stay 44 pt; text pins scale like body text (their sizes in Settings are for the standard size).
- **Shapes.** All corners are continuous. Radius 16: cards, board tiles, the Start here card; 20: toasts; 14: status pill, back-up reminder, colour swatches; 12: text fields and sheet boxes; 24: a board's big title. Dashed drop outline: 20 (page), 16 (tile). Grid margins and gaps 12 pt. Surfaces: system background; secondary system background for cards, fields, banners; regular material for the selection bar; ultra-thin material for small badges. Every icon is a system symbol.

### 3.3 Touch targets, menus, long-press = ⋯, submenus, selection, Select all

- **Touch targets** are at least 44 × 44 pt; a smaller symbol or word gets a 44-pt area. Exception: the "Restore" / "Erase" buttons under a Recently Deleted card (about 32 pt).
- **⋯ and +.** Every screen's menu button is ⋯ (VoiceOver "More"); adding is + (VoiceOver "Add").
- **Long-press = ⋯.** Touch and hold on a card, tile or row opens the same commands as that screen's ⋯. A command that cannot be used right now is left out of a long-press menu and dimmed in a ⋯ menu or bar.
- **Menu grammar.** An item ending in "…" asks something more before it acts; "Delete" has none because it only asks "are you sure". "Select" comes first, then a divider; destructive items are red and last, after a divider. A submenu that would hold one entry shows that entry directly (7.1).
- **Selection** is one pattern for pins, boards and tags. Start with "Select" (long-press; that item starts chosen) or "Select pins" / "Select boards" in ⋯, which reads "Done selecting" meanwhile. Each item shows a ring at its top right, a white check on the accent colour once chosen; chosen items have a 3 pt accent border, unchosen ones dim to 75 %. A bottom bar shows "N selected", "Select all" / "Deselect all" and "Done" above bordered buttons; tab swiping is off. "Select all" chooses every item of the list shown, not only those on screen. Pins: 6.5; boards: 13.3.
- **Text fields.** The Return key reads "Done" and puts the keyboard away while doing the field's action. Sentences are capitalised and autocorrected, except in tag, address, key and search fields. The system's clear (×) button shows while editing (not in the search bar). Fields take the light or dark look of their screen. Fields in sheets ask for the keyboard 0.35 s after the sheet appears. With Settings › Pins & boards › "Use PinBoard's own keyboard" on (default off) a simple built-in keyboard shows under the field instead (21.10).
- **The one-line text sheet** (board, profile and tag names, titles, notes, descriptions): medium or large; inline title; "Cancel" at left, "Save" at right; "Save" is dimmed while a required text is empty; Return saves; text is trimmed. A multi-line sheet has a box 120 to 200 pt tall with the hint as a caption under it. Once the text differs from how the sheet opened, swiping down is blocked; "Cancel" discards without asking.

### 3.4 How the app talks: toasts (when, where, how long, wording style), alerts (only when they explain what to do next), the status pill, empty states, "why" footers

- **Toasts** confirm something done or noted and never ask anything. A rounded rectangle (radius 20; padding 16 sideways, 10 vertically) holding an accent-coloured symbol, an 8 pt gap and footnote medium text, up to three lines. In this document ✓ marks a toast with `checkmark.circle` (done), ⓘ with `info.circle` (a note, nothing was done) and ✗ with `exclamationmark.triangle` (a failure or partial result); other symbols: `stop.circle` (a run stopped), `doc.on.clipboard`, `photo.badge.checkmark`, `quote.opening` ("Saved as a pin" †), `doc.on.doc` ("Copied").
  - *Where:* centred, 24 pt side margins, 12 pt above the bottom of the area the tab uses (tab bar, home indicator or keyboard), 96 pt above it over Quick Look and the private browser. They show over every tab and page, Settings, the "Colors" sheet and the link reader.
  - *How:* slides up while fading in over 0.25 s ease-in-out (only fades with Reduce Motion); on screen 3.5 s in all; a newer toast replaces it at once; taps pass through; all are cleared when the app goes to the background; VoiceOver reads one 0.5 s after it appears.
- **Alerts** appear only when a message says what to do next or must not be missed: the sentence is the title with a single "OK", shown about 0.45 s after the menu or sheet that began it has closed. Plain good news is a toast; anything unreadable, lost, left out or needing a next step is an alert; a folder import is always an alert (8.5).
- **Questions** come before something one tap cannot undo: the title is the question, the destructive answer is red, "Cancel" is last (7.2 "Delete", 15.2, 8.4).
- **The status pill** shows work in progress at the top of the Pins tab, normal side only (4.2).
- **Empty states** share one look: a stack 10 pt apart of a 44-pt symbol in secondary colour, a title in title3 semibold and a message in subheadline, secondary, centred (absent when a screen has none), at most 420 pt wide with 16 pt padding, centred across the area. In a pin grid it sits 40 pt under the header (60 pt on "Recently Deleted" and "Possible duplicates", 30 pt on "Colors"). A grid with no words says "Nothing here". Each screen's texts are quoted where it is described.
- **"Why" lines.** The app says why: a pin the AI put on a board shows "Auto-sort: ‹the matching words, or the reason›" or "Start here: tagged “‹tag›”" under its boards (10.3); an AI title shows "Written by AI"; every Settings switch has a footer saying what it changes and what leaves the device (21).
- **Wording style.** English only. Counts read "1 pin" / "N pins" (likewise boards, videos, links, files), with thousands separators in progress words. Items that open something or ask end with "…". Names and settings sit in curly quotation marks (“Hidden”); messages use an em dash with spaces ( — ) and the single character "…". Dates in captions are an abbreviated date with a short time ("Oct 1, 2026 at 9:41 PM").

### 3.5 Privacy promises (hidden content never on the normal side; nothing leaves the device unless a switch says so; what each switch sends)

- Hidden content never shows, counts or is named on the normal side (2.6).
- Nothing leaves the device unless a switch or your own action says so. **"Offline mode"** (Settings › Privacy & Hidden, default off) is the master switch: it turns off Explore, web feeds, link previews, Cloud AI, iCloud sync and the speech recogniser's language download †; on-device AI keeps working. The ten lines of the Privacy section are in 21.8. What each thing sends:
  - *Nothing, ever:* tagging, text reading, search, suggestions, Apple Intelligence (words only) and writing down speech †. A photo's location is kept for export only.
  - *"Fetch link previews" and "Read links fully"* (both on): the saved page is fetched once.
  - *Web searches* (Explore; "From the web" and "Keep exploring", which wait for you unless "Automatically load web suggestions" is on): only the search words, to the image source you chose (default "Wikimedia Commons"), over a throwaway connection that keeps no cookies, stored data or tracking identifiers, HTTPS only. Keys stay on the device and go only to their own service. Saving an Unsplash photo also tells Unsplash that it was downloaded (one request with your key, as Unsplash asks; nothing else is sent) † (19.2).
  - *"Find a picture for links without one"* (default off) †: a link's title becomes search words; never for links in Hidden.
  - *"Use a cloud vision model"* (default off; your own key and a consent sheet that names the company the pictures go to, Anthropic or OpenAI, agreed to per provider †): each new image shrunk to at most 1,024 px with all metadata removed, the names of its boards (never hidden boards') and your tags; for a link, up to 1,500 characters of page text and its preview picture. Never notes, location or other images, and nothing of a hidden pin unless "Include hidden pins in AI" is on (default off, build 17 †) (20.4, 20.11).
  - *"Sync with iCloud Drive"* (default off): the whole library, hidden things and pictures included, goes to the app's iCloud Drive folder; settings, keys and the profile list do not.
  - *The Photos library and the camera* † (nothing leaves the device): PinBoard reads only the photos and videos picked in the system picker, and asks iOS only for add-only access to save into Photos (7.8), so it never sees the rest of the library and never changes or deletes anything there. The camera takes photos only (no video, so the microphone is never asked for). The words iOS shows when asking are in 25.2.
  - *Searching a picture on the web* †: the app uploads nothing; it hands you the picture (clipboard for two minutes, Files or Photos) and you upload it; a hidden pin's picture goes by the clipboard only (7.4).

### 3.6 Accessibility (VoiceOver labels pattern, keyboard shortcuts summary, Reduce Motion where relevant)

- Every symbol-only button has a spoken name ("More", "Add", "Dismiss", "Remove tag ‹tag›", "Actions for ‹name›"). A grid card is one element whose label joins, with ", ": its kind ("Photo", "Video", "Text", "Link"); what a link was read as ("Article", "YouTube video", "Pinterest pin", "Picture from the web", "Video from the web"); a video's length; its title; a text pin's first 160 characters; a link's site; the caption. While selecting it is a button that says "Selected" when chosen. A video with sound offers "Turn sound on" / "Turn sound off".
- Announcements: a toast 0.5 s after it appears; "N selected. Tap pins to select or deselect them. Touch and hold one for Quick look." when the selection bar comes up and "N selected" after each change; a pill's text; "Hidden pins are covered" for the privacy cover. With Larger Text on, a symbol-only bar button shows its name large when touched and held.
- Keyboard (iPad): no shortcuts for tabs, menus, grids, Search or Explore. Return does a field's action; Escape cancels in the crop screen (where Return crops), the "Add link" / "Edit link" sheet † and "This pin is gone" (Close), and closes the "Original" viewer. Quick Look has its own keys (11.5).
- Reduce Motion: toasts only fade and a board's colourful title stands still. The app plays no sounds of its own; the only haptic is one medium-strength tap when the 2× hold in Quick Look locks or unlocks (11.4).

## 4. The app frame

### 4.1 The four tabs and swiping between them

- Tabs, left to right: "Pins" (`square.grid.2x2`), "Boards" (`folder`), "Explore" (`globe`), "Search" (`magnifyingglass`). The app opens on Pins. All four are always present; in Offline mode Explore stays and says why it is empty. The bar is at the bottom on iPhone and in a narrow window, at the top in a wide one.
- Each tab keeps its own stack of pages and place. Root screens have large titles that shrink to a small centred title on scroll: "PinBoard" (Pins), "Boards", "Explore", "Search". Top-right buttons: Pins "+" then ⋯; Boards "+" (Boards segment only) then ⋯; Explore the source menu then ⋯; Search ⋯.
- "Show info" on a video in Quick Look closes it and, about 0.45 s later, pushes the video's page onto the visible tab (when that page is already open underneath, Quick Look simply closes).
- **Swiping.** A quick sideways swipe on a tab's root screen goes to the neighbouring tab — right to left to the next (Pins → Boards → Explore → Search), left to right to the previous — with no wrap and no custom animation. It counts when the finger travels at least 30 pt to start, ends at least 80 pt sideways and more than 2.2 times as far sideways as vertically, and is quick: under 0.6 s, or predicted to end at least 220 pt sideways. It runs alongside scrolling, taps and long-presses. It does nothing on a pushed page (board, pin, smart board, Hidden), while selecting, or in Search inside Hidden, and is ignored if the drag touched the Pins tab's "Filter" control, a filter-chip row or the Boards tab's segmented switch in the half second before it began.
- Setting: Settings › Pins & boards › Getting around › "Swipe between tabs" (default on). Footer: "Swipe left or right on Pins, Boards, Explore or Search to move to the next tab. Inside a board or a pin, swiping works as usual."

### 4.2 The status pill and banners (back-up reminder)

- **Status pill.** At the top of the Pins tab's scrolling content (it scrolls away with the grid), showing normal-side work only. One line at a time, by priority: (1) an import's or other job's words (the list: 8.5; "Transcribing N of M…" † only for the run started from Settings and only while the pill is free); (2) "Syncing with iCloud…"; (3) "AI is tagging pins… N of M" (N = the pin being looked at now); (4) "AI is renaming pins… N of M". Every line with a count ("Importing 3 of 40…", "Syncing with iCloud… 2,100 of 2,500", "Converting 2 of 5 (45%)") carries a thin progress bar under the text †, read from its own numbers (`WorkProgress`); only a line without one ("Fetching the link…") has a small spinner. The same goes for the long-work rows in Settings and the Hidden section, and an export's bar fills to 90% as pins are written and the rest while the zip is made (estimated by the clock at about 40 MB a second). Look: `sparkles` in the accent colour, 10 pt gap, footnote medium text; padding 14 sideways and 10 vertically; radius 14 on the secondary system background.
- **Back-up reminder**, under the pill. It appears once 50 or more new normal pins have been added since the last real export or the last "Later" (per profile; pins added into Hidden, restored from Recently Deleted or skipped as look-alikes do not count). Title "Time for a back-up?" (subheadline semibold); caption "N pins added and never exported. An export is the only copy outside this device." or, after an export, "N pins added since your last export.". Buttons: "Export now" (small, prominent), which opens Settings on Library and starts the export about 0.9 s later (with hidden content it first asks "Include hidden boards in the export?": "Include hidden boards", "Leave them out", "Cancel"), and "Later" (caption, plain), which resets the count to 0. Only an export really shared or saved counts. Look: `externaldrive.badge.timemachine` (title3, secondary), 12 pt gap, the words, then the two buttons stacked 6 pt apart at the right; with large text or a narrow window (under about 170 pt left for the words) the buttons go under the words side by side, 16 pt apart. Radius 14, padding 12, secondary system background, full width.

### 4.3 Going to the background and coming back; the privacy cover

- **Leaving.** The library is saved at once; toasts are cleared; an import question for Hidden is dropped with its import; Hidden closes (the Boards tab returns to where Hidden was opened, even if another tab shows) and locks.
- **Returning** from the background (not from Control Center or a notification): the Pins tab's "All" grid reshuffles only under the rule in 6.1; an iCloud sync is scheduled 2 s later (3 s after launch); videos whose transcript was waiting for the speech files restart 2 s after Offline mode is switched off †.
- **The privacy cover** hides whatever shows hidden things the instant the app steps out of the front (App Switcher, Control Center, a system question) and stays on through the background until the app is active again. It covers the Boards tab while Hidden is open (only while that tab shows), hidden pins' pages and Quick Look, and every sheet or question about hidden things (imports into Hidden, editors adding to it, hidden boards' and smart boards' sheets, the private browser, pickers). It is not drawn while Hidden's own Face ID or passcode prompt is up. Look: fully opaque, the plain system background with a 44-pt `lock.fill` in secondary colour in the middle; VoiceOver "Hidden pins are covered".

### 4.4 Settings' doorway; iPad windows

- Settings is a sheet over the tabs, opened by "Settings…" (`gearshape`) in the ⋯ menu of every tab, board, smart board, Hidden and pin page (left out of a page that was itself opened from inside Settings) and by the reminder's "Export now". It carries the app's theme and accent. "Done" closes it (dimmed, and swipe-down blocked, while an export runs). Opening it silences a grid card that was playing sound. Toasts, "Looks familiar" questions and result alerts show over it. Rows: 21.1.
- Choosing another profile there sends every tab back to its root; the Boards tab is blank for a moment; an import question or batch of the old profile is dropped with "Import cancelled: another profile was opened."; the Start here card returns (5.4).
- On iPad two windows share the library and profile but not tabs, pages, sheets or questions (3.1); a toast shows in the window where the work began.

## 5. The Pins tab

### 5.1 Layout top to bottom; the segments "All" / "Unsorted" / "Kept out (N)" and their empty states

- Tab label "Pins" (`square.grid.2x2`); screen title "PinBoard". Top right: the "+" menu (5.2), then ⋯ (5.3); on iOS 26 each sits on its own glass circle.
- Everything under the bar scrolls together; nothing is pinned. Side padding 12 pt, 10 pt between header items, and an item with nothing to say takes no room. Top to bottom: the status pill and the back-up reminder (4.2), the "Start here" card (5.4), a segmented control named "Filter", then the grid (6) or an empty state, then 24 pt of space. While selecting, the selection bar (6.5) sits at the bottom.
- **Segments** (counts live; e.g. "All (120)", "Unsorted (3)", "Kept out (5)"):
  - "All (N)": normal pins not kept out of All (2.7). Its order is chosen in ⋯ (default Shuffled; 6.1).
  - "Unsorted (N)": normal pins on no board, newest first. A pin on no board that is also kept out shows in both "Unsorted" and "Kept out".
  - "Kept out (N)": normal pins kept out of All, newest first. It exists only while at least one pin is kept out (otherwise the control has two segments); when the last such pin leaves while it is chosen, the control jumps back to "All".
- Pulling the grid down on "All" reshuffles a Shuffled feed (6.1); "Unsorted" and "Kept out" don't shuffle. Every pull also starts an iCloud sync † when this profile syncs (6.1).
- **Empty states** (icon `photo.on.rectangle.angled`; look and position 3.4):

| Shown when | Title | Message |
|---|---|---|
| "All" is chosen, or any segment while the library has no normal pins (also "All" when every pin is kept out) | "No pins yet" | "Tap + to add photos, take one, or drag pictures, text and links in from another app. The on-device AI tags them automatically." |
| "Unsorted" is chosen and pins exist | "Nothing unsorted" | "Every pin is on a board. Nice work!" |
| "Kept out" is chosen | "Nothing kept out of All" | "“Keep out of All” (in a pin's or a board's menu) takes pins off this tab's All feed without hiding them; they show here and stay on their boards." |

### 5.2 The "+" menu (the list; detail of each in 8)

- The button is `plus` on iOS 26 and later, `plus.circle.fill` (title2) before; VoiceOver "Add". While any import works (this menu, a drop, a board's "+", Explore) a small spinner takes its place and VoiceOver adds "Importing". The same menu is on every board page and in Hidden (what is added lands there; 8.3).

| Item | Icon | Opens |
|---|---|---|
| "Photos…" | `photo.on.rectangle` | the system photo picker: pictures and videos, up to 100 |
| "Camera" | `camera` | a full-screen camera for one photo; always listed (8.2) |
| "Files… (pictures, videos, text)" | `folder` | the system file picker, several files |
| "Clipboard (picture, text or link)" | `doc.on.clipboard` | imports what is on the clipboard |
| *(divider)* | | |
| "Text pin" | `text.alignleft` | the "New text pin" editor (8.7) |
| "Link pin" | `link` | the "New link pin" sheet (8.7) |

- From this tab, new pins land in Unsorted, at the front. The look-alike question, pill texts, toasts and alerts of every door: 8.4, 8.5.

### 5.3 The ⋯ menu

Icon `ellipsis` (iOS 26 and later) or `ellipsis.circle`; VoiceOver "More". Items, top to bottom:

| Item | Icon | Notes |
|---|---|---|
| "Select pins" / "Done selecting" | `checkmark.circle` | toggles selection (5.5); dimmed when the segment shown has no pins and you are not selecting |
| *(divider)* | | |
| "Shuffled", "Newest first", "Oldest first" | `shuffle`, `arrow.down`, `arrow.up` | the order of All; a checkmark marks the one in force; choosing one first shows "All" (6.1) |
| "Shuffle again" | `arrow.clockwise` | only while "Shuffled" is in force; shows "All" and reshuffles |
| *(divider)* | | |
| "AI sorting" ▸ | `wand.and.stars` | acts on every normal pin; items in 7.2, wording in 15.2; dimmed with no normal pins (hidden pins have their own in Hidden's ⋯) |
| *(divider)* | | |
| "Settings…" | `gearshape` | opens Settings (4.4) |

### 5.4 The "Start here" card

- Sits in the header under the banners: padding 14, radius 16, secondary system background, rows 10 pt apart. Shown while the library has no boards at all (a hidden board counts as a board) until dismissed with the small `xmark.circle.fill` at the right (VoiceOver "Dismiss"); the dismissal is not remembered: the card returns after a relaunch or when another profile is opened, as long as no board exists.
- Title "Start here" with `sparkles` (headline). The body follows what the library holds:

| State | Body |
|---|---|
| No pins at all | Three steps with `1.circle`, `2.circle`, `3.circle` (secondary): "Tap + to add a few photos (or drag them in).", "The AI tags them on this device.", "Come back here to create boards from what it found." |
| Pins exist, any still waiting for the AI | Green `checkmark.circle.fill` "Photos added." then a small spinner and "Tagging your photos — board ideas appear when it's done." |
| All tagged, no board idea | Green check "Photos added and tagged." then, secondary, "Add a few more photos, or create a board yourself in the Boards tab." |
| Ideas found | "Based on your photos, these boards would sort N of them straight away:" (N = the sum of the chips' counts, so a pin matching two ideas counts twice), wrapping bordered chips 8 pt apart, "‹Name› · ‹count›", each with `checkmark.circle.fill` (accent) when on or `circle` (grey) when off, all starting on, a tap toggles (VoiceOver "selected" when on); then a prominent button `folder.badge.plus` "Create N board(s)" ("Create 1 board", "Create 3 boards"), dimmed when no chip is on. |

- Creating makes each chosen board with its pins on it; each pin keeps the reason "Start here: tagged “‹tag›”" (10.3). The card then disappears because boards exist. Which words become ideas: 20.7.

### 5.5 Selection mode on this tab; drops onto the tab

- Start with ⋯ › "Select pins" (nothing chosen) or a card's "Select" (that pin chosen); leave with "Done" or ⋯ › "Done selecting". On this tab tab-swiping is off while selecting, and "Select all" chooses every pin of the segment shown. The bar and all other rules: 6.5.
- **Drops.** The whole page, header and grid alike, is a drop zone, also while selecting and whichever segment shows. Pictures, videos, web addresses and text dropped anywhere become pins in Unsorted (what each becomes, several items at once and the reports: 8.2, 8.5). A card of the app's own, dropped here (also one dragged within this tab), only shows the ⓘ toast "Drop pins onto a board to put them there.".
- **The outline** shows only while something the zone can take is held over it: a dashed accent line, 3 pt, radius 20, dashes 10 pt with 6 pt gaps, inset 8 pt, drawn over the cards, never taking taps. A drag carrying nothing droppable gets no outline and the system's "not allowed"; a droppable one gets the system's copy badge. It goes away when the drag leaves, when something is dropped, or 3.5 s after the last movement over the zone. Board tiles use the tile style: radius 16, dashes 8 pt with 5 pt gaps, no inset (13.2). Search, Explore, a pin's page, Quick Look, Settings and every sheet are not drop zones.

## 6. The grid and the cards

### 6.1 Masonry layout, columns (setting), spacing, radii

- **Where.** One grid is used on the Pins tab, in Hidden, on board and smart-board pages and for Search results (each card with a caption line). The same cards and column rule fill "More like this" on a pin page and the two picture-choosing sheets ("Choose a picture", the board-cover chooser).
- **Layout.** Cards go one after another into whichever column is shortest (the leftmost on a tie); columns are equal; the grid fills the width of its area with 12 pt side margins and 12 pt gaps across and down, and 24 pt under the last row or footer. It scrolls vertically, under the translucent bars. A card's height is known before its picture loads, so nothing jumps.
- **Columns.** Settings › Appearance › Grid › "Images per row": "Automatic" (default), 2, 3, 4, 5, 6, 7, 8; footer "Large numbers only take effect on wide screens; columns never get narrower than about 88 points." Automatic follows the width of the area, not the screen: 2 columns up to 640 pt, 3 above 640, 4 above 1,000, 5 above 1,400. A chosen number is never below 2 and never so large that a column is under about 88 pt (area width ÷ 88; a 6 on a 390-pt iPhone gives 4).
- **Card height.** Picture, video, link with a preview: width ÷ the picture's shape (to whole points) plus the lines under it; a very tall picture is cut to fill a 1:5 shape. Text pin: as tall as its text. Link without a preview: at least 88 pt. All grow with the text size.
- **Radii.** Cards 16 (continuous corners everywhere); other radii: 3.2.
- **Feed order.** The Pins tab's "All", Hidden's "All" and every board page (one shared choice) show an order the person chooses: "Shuffled" (default; a random arrangement that stays until something asks for a new one), "Newest first" or "Oldest first" (by the date the pin was added, never changed by edits; equal dates keep a fixed order). Unsorted, Kept out and Hidden's Unsorted are always newest first; Search and smart boards have their own sort (18.1, 17.1); board tiles have theirs (13.1).
  - *Where chosen:* Pins ⋯ (5.3), Hidden ⋯ (16.2), and a board page's ⋯ › "Order of pins" ▸ with the same entries. Choosing the order already in force changes nothing; choosing "Shuffled" after a date order shuffles. Three choices are remembered between launches (Pins All, Hidden All, all boards), for every profile and window, outside the library and exports; the shuffle itself is not.
  - *Adding, removing, hiding or moving* a pin never reshuffles the rest: in a shuffled feed a new pin lands at a random place, in "Newest first" at the front, in "Oldest first" at the end.
  - *A shuffled feed gets a fresh order* on: "Shuffle again"; choosing "Shuffled" after a date order; pulling the grid down (the spinner stays about 0.35 s; a date-ordered feed keeps its order; a pull on any pin grid — Pins tab, board pages, Hidden — also starts an iCloud sync † (about 0.7 s after the spinner has gone, so the "Syncing…" pill never comes or goes while the spinner slides away — on iPhone that could leave an empty gap at the top of the grid; build 15) when this profile's sync is on, Offline mode is off, iCloud is there and no sync is running: the usual sync with its quick "nothing changed" look, not the full one of "Sync now"; the spinner doesn't wait for it and it shows in its usual pill; the Sync log notes "Sync started by pull to refresh"; build 12); every visit to a board page and every opening of Hidden (it then keeps that order while pins are opened from it); returning to the Pins tab from another tab only when "All" shows with nothing open over it and it was scrolled less than 60 pt from the top when left (the new order is in place before anything draws); returning from the background under the same rule and with nothing shown over the tabs in any window (sheet, cover, Settings, alert, question); a board page starting or stopping to include sub-board pins; every launch; switching profile. Opening a pin or Quick Look and coming back, scrolling, selecting, changing segments, changing "Images per row" and tapping the Pins tab while on it change nothing. On iPad two windows share the Pins order.

### 6.2 Cards by kind: picture, video, text, link (badges, titles, captions, what shows under a card)

A card is a box with up to three text lines under it, 6 pt apart. A card is one VoiceOver element (3.6); the selection look is in 6.5.

- **Picture card.** The box has the picture's own shape (never taller than 1:5); a grey (secondary system fill) box with a spinner until the picture loads; scaled to fill and clipped to radius 16. A turned, flipped or cropped picture shows its new shape at once. Badges bottom left; the title under it when it has one.
- **Video card.** A picture card using the poster frame (picked when the video is added; 12.5), the video's own shape, with the length badge, a speaker button at the bottom right (6.3) and, when auto-play is on, the video playing on the card (6.3).
- **Text card.** A secondary-system-background box, radius 16, padding 14, items 6 pt apart: the title (only with "Show the title on the card" on, default on, and a title present; semibold, 1.12 × the board text size, at most 2 lines), then the text, at most N lines ("Lines shown on boards", default 6, cut with "…"). Typeface "Standard" (default), "Serif", "Rounded" or "Monospaced"; size on boards 15 pt, scaled with the text size. Colour: the custom text colour if set, otherwise the accent colour while "Use the accent color for text" is on (default off), otherwise the normal text colour. Height: 28 pt of padding plus the title's lines (up to 2) plus 6 pt plus the text's lines (at least one; a pin with no text shows one blank line). No badges and no line under it. The rows are in 21.3; on a board tile a text pin's words appear as small grey type (13.2).
- **Link card with a preview picture.** A picture card plus a kind badge at the top left (8 pt in; a circle in the ultra-thin material with a caption-size semibold symbol, 6 pt padding): `newspaper` for an article, `play.rectangle` for a YouTube video, `link` for everything else. Under it: the title line (when titled) and the site line. No bottom-left badges. A stand-in picture found for a link looks the same; nothing marks it †.
- **Link card without a preview picture.** A compact box (secondary system background, radius 16, padding 12) with the same kind symbol at the left (title3, secondary) and the title (subheadline semibold, at most 2 lines) — the address when untitled, the word "Link" when it has no address. 88 pt tall (two title lines plus 24 pt at larger text sizes); nothing under it.
- **Badges** (picture and video cards): capsules in the ultra-thin material, caption2 semibold, padding 8 × 4 (icon-only 6), bottom left, 8 pt in, 6 pt apart (4 when compact), in this order: (1) the video's length, `play.fill` "m:ss" (minutes are not rolled into hours: "75:00"; "Video" while the length is unknown); (2) "Tagging…" `sparkles`, until the on-device AI has looked at the pin; (3) "Duplicate?" `square.on.square`, on the newer of two look-alike pictures on the same side (a normal card never hints at a hidden twin); (4) "N boards" `folder` (e.g. "2 boards"), when the pin is on more than one board shown on this side (hidden boards are never counted). When they do not all fit, every badge shrinks to its icon; beside a speaker button they stop 56 pt from the card's right edge.
- **Under a card.** The title line: footnote semibold, one line, "…" when cut (picture, video, link with a preview; never a text pin or a preview-less link, which hold their title inside). The site line (link with a preview): the address's host without "www.", caption2, secondary, one line. The caption line (caption2, secondary, one line) only where a screen supplies one: Search results show up to three matched words joined with " · " ("beach · sunset"), or "N% match" ("63% match") when sorted by "Best match" and no word matched (18.2). Each line takes room only when it exists.

### 6.3 Video previews on cards: which play, the middle-of-screen rule, sound, the one-sound rule, posters, no grey flash

- **The switch.** Settings › Videos › "Auto-play videos in grids" (default off; footer in 21.5). Off: a video card is a still poster. On: video cards on screen play silently and loop, at most six at a time, the six nearest the middle of what is visible. One card at a time can be given sound by its speaker button, and that card plays even with auto-play off. Cards carry no other controls; a tap opens Quick Look (6.4).
- **Which cards play.** A card wants a player when it is a video, within about 100 pt of the visible area (so videos just about to scroll in are ready), Quick Look is not covering the screen, and auto-play is on — or it has sound. Of those, the card with sound is served first, then the cards nearest the middle of the visible area (distance from the middle to the card's centre; while the grid is at its very top, from the top edge, so a page starts playing from the top). A playing card keeps its player unless a waiting card is closer by more than about 120 pt. The choice is made again at most every 0.4 s, after a 0.05 s pause that lets a new screen's cards report in; the card with sound is chosen at once. A card leaving the screen gives up its place. Quick Look stops every card player under it; they start again when it closes.
- **Posters, no grey flash.** The poster stays underneath, so a card is never an empty grey box. The video is invisible until its first picture is ready, then fades in over the poster in 0.15 s (once per start; looping never hides it); if the first picture is not ready after 2 s it shows anyway. It fills the card. A preview carries on where the video was last left in any player (preview, pin page, Quick Look) when that was more than 0.5 s in and more than 0.5 s before the end, otherwise it starts from the beginning; it waits until ready, jumps there and only then shows, so it never visibly jumps. A preview remembers where it stopped if it played at least 0.3 s. Places are remembered only until the app is closed.
- **The speaker button.** Only on a video known to have a sound track (older videos are checked once in the background; one with no sound track never shows it) and not while selecting. Bottom right, 5 pt in: a 42-pt black circle at 45 % opacity with a white `speaker.slash.fill` (off) or `speaker.wave.2.fill` (on), title3 semibold; touch area a 44-pt circle. A tap makes this card the one with sound and turns the app's sound switch on; a big player (pin page, Quick Look) that was sounding goes quiet. A second tap turns sound off.
- **The one-sound rule.** Only one grid card has sound at a time. Once sound is on, every video opened large (pin page, Quick Look) plays with sound, from page to page and tab to tab, until turned off. When the card with sound leaves the screen it goes quiet for good, though the switch stays on for videos opened large. VoiceOver: the speaker is hidden; the card offers "Turn sound on" / "Turn sound off".
- **What you hear.** Silent previews mix with other apps' audio and never interrupt it. Once something plays with sound the app takes over like a video app: it plays even with the silent switch on, may pause other apps' audio, and keeps the screen awake.

### 6.4 Tapping and long-pressing a card, by kind

| Kind | Tap | Touch and hold | Drag out (not while selecting) |
|---|---|---|---|
| Picture, text, link | opens the pin's page (10.1), which pages through the grid's neighbouring pins in the order shown | the pin menu, "Select" first (7.1) | picture: a JPEG file (the library copy, never a kept original); text: its text (its title when it has no text); link: only the app's own reference, not its web address |
| Video | opens Quick Look at once on that video, paging through the grid's pins in the order shown (its ⋯ › "Show info" goes on to the pin's page; 11.4) | the pin menu | a movie file |

- In "More like this" a video opens its page, not Quick Look (10.4). A secondary click (mouse, trackpad) does what touch and hold does.
- Every dragged card also carries a reference only PinBoard understands: dropped on a board tile or board page it files the pin on that board (13.2, 14.2); on the Pins tab it only shows the hint of 5.5. One card is dragged at a time. "More like this" cards, web results and Quick Look cannot be dragged.
- While selecting, a tap toggles the card and touch and hold offers only "Quick look" (`arrow.up.left.and.arrow.down.right`).

### 6.5 Selection mode and the selection bar (every button, "Select all", counts, More ▸)

- **Start and end.** Start with a card's "Select" (that pin is chosen) or the screen's ⋯ › "Select pins" (nothing chosen; it reads "Done selecting" meanwhile and is dimmed when the grid has no pins) on the Pins tab, Hidden, a board's page, a smart board's page and the Search tab. On a board page, pin selection and sub-board selection exclude each other. End with "Done", ⋯ › "Done selecting", or an action started from the bar finishing; the chosen set is forgotten, and pins that vanish drop out of the count.
- **The cards.** A check circle sits at the top right (title2, 10 pt padding): an empty white ring, or a white check on an accent disc (`checkmark.circle.fill`) when chosen. A tap anywhere on a card, a video card too, toggles it. Chosen cards have a 3 pt accent border; the others dim to 75 %. Drags and speaker buttons are off (the common pattern: 3.3).
- **The bar.** At the bottom above the home indicator, on the regular material, padding 12, rows 8 pt apart: the header line, the buttons, the hint. The grid's visible area ends above it.
  - *Header:* "N selected" (subheadline semibold; a small spinner beside it while a job runs), then "Select all" (it reads "Deselect all" when every pin of the grid is chosen) and "Done" (semibold), 12 pt apart, each at least 44 pt tall. When the three do not fit, the count moves above and the two buttons sit right-aligned beneath; at the largest sizes each takes a line. "Select all" chooses every pin of the list the grid shows, not only those on screen: the whole feed, a board page including its sub-board pins when included, the whole Search result list.
  - *Six bordered buttons* in one row, 6 pt apart, equal width, each an icon over a caption2 name:

| Button | Icon | Does |
|---|---|---|
| "Edit tags…" | `tag` | the "Tags" sheet for all chosen pins (14.5) |
| "Add to board…" | `folder.badge.plus` | the board picker (7.2) |
| "Move to board…" | `arrow.turn.up.right` | the board picker (7.2); only while at least one chosen pin is on a board † |
| "AI sorting" | `wand.and.stars` | a menu with the AI sorting items for the chosen pins (7.2) |
| "More" | `ellipsis.circle` | the other shared commands (7.1) |
| "Delete" | `trash` | red; asks "Delete N pins?" (7.2) |

  - Names show only when every name fits whole; otherwise the buttons show icons only (touch and hold shows the name large in the middle of the screen with Larger Text on), and at the largest sizes they form two rows of three (Edit tags, Add to board, Move to board / AI sorting, More, Delete). All six are dimmed when nothing is chosen or a job runs. **†** "Move to board…" is left out while no chosen pin is on a board (nothing chosen, or only pins on no board); the other five then share the row (two rows: Edit tags, Add to board / AI sorting, More, Delete).
  - *Hint* (caption2, secondary): "Tap pins to select or deselect them. Touch and hold one for Quick look."
- **When selection ends.** Cancelling a question or sheet ends nothing. Otherwise, command by command:
  - at once: Open link, Hide pins / Unhide pins, Keep out of All / Show in All, Remove from this board / from board ▸, Remove from this smart board, Use as board cover;
  - once a board is chosen: Add to board…, Move to board…; once confirmed: Delete; once saved: Edit link… / Add link… (also "Remove link");
  - after the job, whatever its outcome: Rotate left, Rotate right, Flip horizontally, Pick another frame, Save to Photos (even "Nothing could be saved to Photos."), "Put on a suggested board" / "Sort into boards" (only when something moved; otherwise an alert explains and the selection stays); after a successful crop (a failed one keeps it); after the thumbnail is set (Choose from Photos…, Use a picture pin…; a failure keeps it); after the page has opened or the picture could not be read (Search this picture on the web ▸; Cancel in the Files folder picker ends nothing);
  - as soon as chosen, before any question: AI sorting › "Re-run AI tags", "Name with AI (keeps your names)", "Rename all with AI…" / "Rename with AI";
  - never: Edit tags… (the sheet's "Done" just closes it), Share…, Generate colors, "Undo last AI naming", "Stop renaming".

## 7. The pin menus — every command (one table; it is the same list in all five places)

### 7.1 The five places and what differs in each (card long-press, selection bar, Quick Look ⋯, pin page ⋯, "More like this")

| # | Place | Opened by | Acts on | What is special |
|---|---|---|---|---|
| 1 | Grid card menu | touch and hold a card in any grid (a secondary click does the same) | the one pin | The only place with "Select" (first, then a divider). On a board's page it adds "Remove from this board", on a smart board's page "Remove from this smart board". While selecting it shows only "Quick look". |
| 2 | Selection bar | choose pins first (6.5) | all chosen pins | "Edit tags…", "Add to board…", "Move to board…", "AI sorting" and "Delete" are buttons of their own; "More" holds the rest. No "Select", no "Quick look". |
| 3 | Quick Look ⋯ | the viewer's ⋯; touch and hold on a picture too | the pin on screen | Quick Look's own items first (11.4), then the shared list; no "Quick look". |
| 4 | Pin page ⋯ | ⋯ (VoiceOver "More") at the top right | the page's pin | The shared list without "Delete", a divider, the page's own items (10.2), a divider, "Settings…", a divider, then "Delete" alone. |
| 5 | "More like this" card | touch and hold a card in that section | the one pin | The shared list without "Select" and without board context. |

- **Dividers** in the shared list: after "Select" (place 1), after "Generate colors", and before "Delete" (only where "Delete" is in the menu). A command that is not offered leaves no gap.
- **What the place decides.** "Quick look": one pin, places 1, 4, 5 only. "Remove from this board" / "…smart board": places 1 and 2 on those pages only; elsewhere the pin's own boards are listed under "Remove from board ▸". The dimmed note "Kept out by its board": places 2, 3, 4 only (a long-press menu shows only what you can do). Hidden side: "Unhide pin(s)" replaces "Hide pin(s)" and the keep-out items are never offered. In the bar's "More", one-pin commands (Quick look, Open link, Remove from board ▸, Use as board cover, Crop…, Search this picture on the web ▸, Edit link… / Add link…, Choose from Photos…, Use a picture pin…) need exactly one pin chosen.
- **Submenus** are "Boards", "Edit picture", "Thumbnail", "Search this picture on the web" and "AI sorting". A submenu that would hold one entry shows that entry directly: with several videos "Thumbnail ▸" becomes "Pick another frame"; in the bar's "More", "Boards ▸" may shrink to just "Remove from this board", "Remove from board ▸" or the cover item. "Remove from board ▸" reads "Remove from another board" beside "Remove from this board"; its buttons show each board's full path ("Travel › Beaches"; "Board" if the path cannot be found).
- **Busy.** While a turn or flip, a save to Photos, a fetch of originals for Share, a thumbnail pick or an AI sort runs, "Edit picture ▸", "Thumbnail ▸" and "Save to Photos" are dimmed, the bar's buttons are dimmed with a spinner, and asking again does nothing. "Share…", "Generate colors" and "Delete" are never dimmed.
- A sheet or question a command opens takes the look of the screen it came from, is covered in the App Switcher for a hidden pin, and over Quick Look switches its Space and arrow keys off.

### 7.2 The table: command · icon · when offered · what it does · what it asks · toast

✓ ⓘ ✗ are the toast kinds of 3.4; N counts pins ("1 pin" / "N pins"). Rows follow the menu order.

| Command | Icon | Offered when | What it does | Asks | Message |
|---|---|---|---|---|---|
| "Select" | `checkmark.circle` | place 1 | starts selection with this pin chosen (6.5) | — | — |
| "Quick look" | `arrow.up.left.and.arrow.down.right` | one pin; places 1, 4, 5 | opens the always-dark viewer; from a grid it pages through the grid's pins in the order shown (11.1) | — | — |
| "Open link" | `safari` | one link pin whose address starts "http://" or "https://" and has a host | opens it in the default browser app (never PinBoard's private browser), a hidden pin's too | — | none |
| "Add to board…" | `folder.badge.plus` | always | puts the pins on the chosen board besides their boards; nesting rule 2.4 | the picker "Add N pin(s) to…" (14.5) | ✓ "Added N pin(s) to ‹Board›." then, when they apply, " It moved down from a board this one is in." / " N moved down from boards this one is in." and " 1 was already on a sub-board, so it stays there." / " N were already on sub-boards, so they stay there." Nothing changed (still ✓): "It's already on a sub-board of ‹Board›, so it stays there." · "They're already on ‹Board› or its sub-boards." · "It's already on ‹Board›." · "They're already on ‹Board›." Hidden side: "Added 2 pins to a hidden board." |
| "Move to board…" | `arrow.turn.up.right` | when at least one of the pins is on a board of its side † (a pin on no board has nothing to be moved from: it gets only "Add to board…") | replaces all board memberships; "No board (Unsorted)" means none; in Hidden only hidden boards are replaced; clears the AI's "why" note | the picker "Move N pin(s) to…" | ✓ "Moved N pin(s) to ‹Board›." ("Unsorted" for none; hidden side "a hidden board") |
| "Remove from this board" | `folder.badge.minus` | on a board's page, a pin directly on it | takes the pins off that board; they stay on others (none left: Unsorted); a hidden pin stays hidden | — | ✓ "Removed N pin(s) from ‹Board›." (only pins really on it; none: no message; hidden side "a hidden board") |
| "Remove from board ▸" | `folder.badge.minus` | one pin on at least one board shown on this side | one button per board, by full path; same effect | — | same toast |
| "Use as cover of “‹board path›”" / "Use as board cover ▸" | `photo.on.rectangle` | one pin with a picture file (picture, video poster, link preview) | the picture becomes the cover of a board it is on or inside (its boards plus their parents, outermost first, same side only); one candidate: a button naming it; several: a submenu of full paths | — | none (the tile shows it) |
| "Remove from this smart board" | `minus.circle` | on a smart board's page | leaves the pins out of it from now on; "Bring back removed pins" in its ⋯ undoes that (17.2) | — | ✓ "Removed N pin(s) from ‹name›." (hidden: "…from a hidden smart board."; gone: "…from the smart board.") |
| "Crop…" (in "Edit picture ▸", `crop.rotate`) | `crop` | exactly one picture pin | the crop screen (7.5) | — | ✓ "Cropped." · ✗ "The picture couldn't be cropped." |
| "Rotate left", "Rotate right", "Flip horizontally" | `rotate.left`, `rotate.right`, `arrow.left.and.right.righttriangle.left.righttriangle.right` | at least one picture pin (other kinds are left alone) | turns a quarter anticlockwise / clockwise, mirrors left to right, every picture among the pins; rewrites the library picture (at most 2,048 px, JPEG 0.9); the pin counts as new for the AI ("Tagging…") and loses any "Duplicate?" mark; a kept original is untouched (7.8) | — | none on success (the card turns); ✗ "Nothing could be turned." · "N of M pictures couldn't be turned." |
| "Pick another frame", "Choose from Photos…", "Use a picture pin…" (in "Thumbnail ▸", `photo`) | `shuffle`, `photo.on.rectangle`, `pin` | every pin is a video; the last two for one video | 7.7 | the photo picker / "Choose a picture" | 7.7 |
| "Search this picture on the web ▸" | `magnifyingglass` | one pin with a picture file | "Google Lens", "Bing", "TinEye", "Yandex" (each `magnifyingglass`) hand the picture over and open the site (7.4) | — | 7.4 |
| "Edit link…" / "Add link…" | `pencil` / `link.badge.plus` | one pin: "Edit link…" for a link pin, or † for a picture, video or text pin that has a source link; "Add link…" † for a pin with none | 7.3 | the link editor (link pins) or the address sheet † | 7.3 |
| "Edit tags…" | `tag` | always | tags the chosen pins; saved as they change, no Save; "Done" closes; selection stays | the "Tags" sheet (14.5) | none |
| "Generate colors" | `paintpalette` | a pin has a picture file | the "Colors" sheet for exactly these pins (7.6); selection stays | — | 7.6 |
| *divider* | | | | | |
| "Save to Photos" | `square.and.arrow.down` | a pin is a picture or video or has a picture | 7.8 | — | 7.8 |
| "Share…" | `square.and.arrow.up` | always | 7.8 | the system share sheet | 7.8 |
| "AI sorting ▸" | `wand.and.stars` | always (a button in the bar) | block below | 15.2 | 15.2 |
| "Hide pin" / "Hide pins" | `eye.slash` | normal side | the pins leave their normal boards (remembered for Unhide) and go to Hidden (2.6); a page moves on to the next pin, Quick Look drops the pin from its strip | — | ✓ "Hid 1 pin. It's in Boards › ⋯ › Hidden." · "Hid N pins. They're in Boards › ⋯ › Hidden." |
| "Unhide pin" / "Unhide pins" | `eye` | hidden side | returns the pins to their remembered boards that still exist, else Unsorted (2.6) | — | ✓ "Unhid 1 pin." · "Unhid N pins." |
| "Keep out of All" | `rectangle.stack.badge.minus` | normal side; a pin currently shows in All | sets the pins' own setting (2.7) | — | ✓ "Kept 1 pin out of All. It's in Pins › Kept out." · "Kept N pins out of All. They're in Pins › Kept out." (N: pins that were showing; none: no toast) |
| "Show in All" | `rectangle.stack.badge.plus` | normal side; a pin's own setting keeps it out (a mixed choice offers both) | clears that setting | — | ✓ "1 pin shows in All again." · "N pins show in All again." plus " 1 is still kept out by its board." · " N are still kept out by their boards." (none: no toast) |
| "Kept out by its board" (dimmed) | `rectangle.stack.badge.minus` | normal side; only boards keep the pins out; places 2, 3, 4 | a note, not a command | — | ⓘ if chosen anyway: "A board keeps this pin out of All. Change it on the board: ⋯ › Show in All." |
| *divider* | | | | | |
| "Delete" (red) | `trash` | always | the pins go to Recently Deleted for 30 days (23.4) and vanish everywhere; a cover that was the pin goes back to automatic; a pin's page moves on to the next pin | the question "Delete this pin?" / "Delete N pins?", message "It stays in Recently Deleted for 30 days." / "They stay in Recently Deleted for 30 days.", buttons "Delete" (red), "Cancel" | none |

**"AI sorting ▸"** (`wand.and.stars`; no dividers) acts on the pin or pins of the menu. Questions, alerts and toasts: 15.2; how boards are chosen: 20.7. In the bar, "Re-run AI tags" and the naming items end selection when chosen, and a sort only when something moved (6.5).

| Item | Icon | Offered / dimmed |
|---|---|---|
| "Put on a suggested board" (one pin) / "Sort into boards" (several) | `tray.and.arrow.down` | dimmed while a sort runs |
| "Re-run AI tags" | `tag` | never dimmed; tags, colours, picture text and AI-written names again; "Tagging…" on cards, pill "AI is tagging pins… N of M" |
| "Name with AI (keeps your names)" | `character.cursor.ibeam` | dimmed during a naming run; never replaces a name you wrote |
| "Rename with AI" (one) / "Rename all with AI…" (several) | `text.cursor` | dimmed during a naming run; replaces every name |
| "Undo last AI naming (N)" | `arrow.uturn.backward` | after a naming run on this side that changed names, when none runs |
| "Renaming… X of Y" (plain text), "Stop renaming" | `stop.circle` | only while a naming run goes on this side |

### 7.3 "Edit link…" / "Add link…": the link editor (link pins) and the address sheet (other pins) †

A single pin gets one of the two. It has a link when it is a link pin or has a source link (the page a picture, video or text came from; a blank address counts as none).

**The link editor** (link pins; sheet, medium and large, inline title "Edit link") is the "New link pin" sheet (8.7) with a title field added. Top to bottom, 10 pt apart: the address field (placeholder "https://…", filled in, keyboard up, Return saves); "Will be saved as: ‹cleaned address›" when "Clean links" would change it; "Use the link on the clipboard" when the clipboard holds something address-like; the title field (placeholder "Title (empty: the page's own)", filled in); the footnote "Another page's address fetches its title and preview picture again. A title you type stays." — or, with previews off: "Link previews are off, so the card shows the address only. A title you type stays." "Cancel" / "Save"; "Save" is dimmed until the address is a web address (http or https, a host, one line, under 2,048 characters); once anything has changed, swiping down is blocked.
- Save closes the sheet at once; the toast does not wait for the page: ✓ "Link updated." when anything changed, ⓘ "Link unchanged." when address (after cleaning) and title are as before.
- The *same page* (judged by the address without tracking, ignoring capitals, a trailing "/" and http versus https) keeps everything the pin knows; only the stored address changes. *Another page* drops what the old page was: preview picture, description and all that reading found (article text, kind, writer, date, site name, comments, views, length). The compact address card shows until the new page is read like a new link (9.6), and the title becomes the site's name (for example "example.com") until the page's own arrives — unless you typed one.
- A title you type becomes yours (the AI never replaces it). Clearing it brings back the site's name as the AI's title and, with previews allowed, refetches the page so its own title replaces it.

**The address sheet** (picture, video and text pins) † names the page the pin came from or any page about it. A sheet, medium and large; inline title "Edit link" when the pin had a link, "Add link" when not (fixed when it opens). The address field (placeholder "https://…", VoiceOver "Web address", Return reads "Done" and saves), the caption "The page this pin came from, or any page about it.", and, when there was a link, a small bordered red "Remove link" that removes it at once (the pin stays), closes the sheet and says "Link removed.". "Cancel" (also Escape) and "Save", dimmed unless the text is a web address (or empty while there is a link to remove); swiping down is blocked once the text differs from how it opened. After Save: ✓ "Link added." (had none) · ✓ "Link changed." · ✓ "Link removed." · ⓘ "Link unchanged." (same address, or nothing to remove) · ✗ "That isn't a web address." (Save normally prevents it).
- With "Clean links" on, tracking is removed from the saved address. An address on another site (different host) clears the pin's credit line ("Photo by … · Pexels"); the same site keeps it. Nothing is fetched.
- The pin page's ⋯ also offers "Open source page" (`safari`) for a pin with a source link, and the "Link" section of a stored picture, video or text pin has "Add link" (no link yet), or a round pencil (VoiceOver "Edit link") that opens this sheet and a round `xmark` (VoiceOver "Remove link") † (10.3). Quick Look's info panel has "Edit link…" only for link pins; for the others it is in Quick Look's ⋯.
- If the pin is deleted while this sheet or the crop screen is open, it becomes a centred note with `pin.slash`, "This pin is gone" and a bordered "Close" (Escape closes it).

### 7.4 Reverse image search and the picture hand-off (clipboard / Files / Photos; hidden pins) †

- **The submenu** "Search this picture on the web" has four entries, each `magnifyingglass`: "Google Lens", "Bing", "TinEye", "Yandex". It is offered for one pin with a picture: a picture pin, a video (its poster is searched) or a link (its preview picture). Web results in Explore and Quick Look have the same submenu but hand the site the result's own address (19.2).
- **What a choice does.** A picture that lives only in the library has no web address, so the app hands you the picture and opens the site's upload page for you to paste or upload it into: Google Lens `https://lens.google.com/`, Bing `https://www.bing.com/visualsearch`, TinEye `https://tineye.com/`, Yandex `https://yandex.com/images/`. The page opens in PinBoard's private browser (9.7) or the default browser, as Settings › Links › "Open web searches in" says: "PinBoard (private)" (default) or "Default browser" †.
- **"Hand the picture over by"** † (Settings › Explore & web search, "Search on the web" section with the row above; dimmed in Offline mode; footers in 21.8): "Copying it to the clipboard" (default), "Saving it to Files", "Saving it to Photos". **A hidden pin's picture always goes to the clipboard**, whatever is chosen: a copy in Photos (which may sync) or in Files would outlive the hidden side, while the clipboard copy stays on the device and clears itself.
- A picture that cannot be read (still in iCloud, or gone): ✗ "Couldn't read this picture." and nothing opens.
- **Clipboard:** two minutes, on this device only (not shared with other devices); the page opens; toast (`doc.on.clipboard`) "The picture is on your clipboard for two minutes, on this device only — paste or upload it on the page."
- **Photos** † asks iOS for add-only access ("Add Photos Only"; iOS asks the first time, 7.8). The picture is saved (the newest in Recents), the page opens, and the toast (`photo.badge.checkmark`) says "Saved to Photos (the newest in Recents) — upload it on the page."; if access was refused: ✗ "PinBoard isn't allowed to add to Photos. You can allow it in the Settings app › Apps › PinBoard › Photos." and no page opens; if Photos fails otherwise: ✗ "Photos didn't take the picture." and no page opens. There is no fall-back to the clipboard any more (before build 16, an app without the Photos permission text used the clipboard and said so).
- **Files:** the system folder picker opens. The file is named from the pin's title plus ".jpg" (characters a file name cannot hold — / \ : * ? " < > | and line breaks — become "-", spaces and dots at the ends go, the title is cut at 80 characters, "Untitled.jpg" if nothing is left), or "PinBoard picture.jpg" for an untitled pin. After a folder is chosen the picker closes, about 0.35 s later the page opens, and the toast (`checkmark.circle`) says "Saved — upload it on the page." "Cancel" in the picker: nothing opens, no message, selection kept. No room to write the file: ✗ "The picture couldn't be saved to Files." and no page. The temporary file is removed 5 s after the picker closes.
- Toasts show over the private browser, 96 pt above the bottom.

### 7.5 The crop screen

- **Opened by** "Edit picture ▸ › Crop…" for one picture pin from any of the five places. A full-screen cover, always dark (iPad too), with dark bars; nothing swipes it away: only "Cancel" or "Crop" closes it. A keyboard left up beneath is put away; a hidden pin's crop screen is covered in the App Switcher.
- **Bars.** Inline title "Crop picture". "Cancel" top left (Escape; dimmed while cropping). "Crop" top right (Return), dimmed while the picture loads or failed, while the rectangle covers (nearly) the whole picture (within half a percent on every side) and while cropping, when it becomes a small spinner (VoiceOver "Cropping"). Bottom bar (side padding 16, 10 above and below, 12 between): the shape picker at the left, "Reset" at the right (shape back to "Free", rectangle back to the whole picture; dimmed when it already is); the bar is dimmed while loading or cropping.
- **Canvas.** Black; the library's picture (at most 2,048 px, never the kept original) as large as fits, centred, 24 pt margin; a white spinner while loading, "This picture couldn't be loaded." (white at 80 %) on failure. It starts with the rectangle on the whole picture and the shape "Free". The picture never moves, zooms or pans.
- **The rectangle.** Outside it everything is dimmed under 55 % black; border white, 1.5 pt; white grips with a soft shadow (black 45 %, blur 2): a 16-pt circle on each corner and, on sides at least 120 pt long on screen, a capsule 26 × 6 pt (top, bottom) or 6 × 26 pt (left, right) in the middle. Thirds lines (two each way, white 50 %, 0.5 pt) show only while a drag holding the rectangle or a grip is going on.
- **Dragging** takes hold the moment the finger touches. Within 30 pt of a grip's centre (also just outside the rectangle) it resizes by that grip (nearest wins, a corner wins a tie; in a small rectangle the reach into it is a quarter of its shorter side, at most 30 pt). Inside the rectangle, away from the grips, it moves the rectangle, which keeps its size and stops at the picture's edges. Anywhere else, nothing.
- **Resizing.** Never beyond the picture, never below 10 % of its width and height. "Free": a corner moves its two sides, a side moves that side. A fixed shape is always kept: a corner slides along the diagonal with the opposite corner fixed (in shrinks, out grows, no jumps; a purely sideways or vertical move pulls about half as strongly as the same distance diagonally); a side moves with the finger while the rectangle grows or shrinks evenly on the other axis around its middle.
- **The shape picker.** Seven shapes in this order: "Free", "Square", "4:3", "3:4", "16:9", "9:16", "Original" (the picture's own shape). A segmented row (VoiceOver "Aspect ratio") when all seven fit (iPad, wide windows), otherwise a menu button showing the current name with `aspectratio` and the list with the current one ticked. A new shape keeps about the same area, centred where the rectangle was, kept on the picture and at least the minimum; "Free" keeps the rectangle as it is.
- **Crop** replaces the library picture with the cut (at most 2,048 px, JPEG 0.9) and remakes its small thumbnail; the card changes shape; the pin counts as new for the AI ("Tagging…") and loses every "Duplicate?" mark; a kept original is untouched (7.8). The screen closes first, then the toast shows beneath (7.2).
- **VoiceOver.** The canvas is one element, "Crop area", value such as "80% of the width, 60% of the height, 10% from the left, 20% from the top", hint "Swipe up or down to make it larger or smaller." (up: 15 % larger; down: ÷ 1.15; around its middle, shape kept). Actions: "Move left", "Move right", "Move up", "Move down" (a tenth of the picture each), "Bigger", "Smaller"; each announces the new value.

### 7.6 "Generate colors" (the palette sheet; copying; the board title surprise)

- **Where.** The pin command of 7.2 (for the pins the menu was opened for) and, on a board page, its own ⋯ › "Generate colors" (`paintpalette`, after a divider and "AI sorting"), which uses every pin of the board, sub-boards included, and names the sheet with the board's name (14.1).
- **The sheet.** Medium and large; inline title "Colors"; top right a ⋯ "More" (dimmed while there are no colours) and "Done"; content scrolls (16 pt padding); it takes the look of the screen it came from, is covered in the App Switcher for hidden pins or boards, and lets toasts show over it. In turn it shows a spinner with "Looking at the pictures…" (footnote, grey); or, when no pin has a readable picture, `paintpalette`, "No pictures to take colors from" and "Colors come from pictures, videos and link previews. Text pins have none."; or the colours.
- **The colours.** A caption (footnote, grey) "N color(s) from “‹name›”. Tap a color to copy its hex code; touch and hold it to share or save it." (‹name›: "1 pin" / "N pins", or the board's name); then swatches in columns at least 130 pt wide, 12 pt apart across and 14 pt down, the most prominent first. A swatch is a filled rounded rectangle (radius 14), 1.3 times as wide as high, with a 1 pt border (primary text colour at 10 %) and, below it, its hex code in monospaced body type ("#3A7BD5"); VoiceOver "Color #3A7BD5", hint "Copies the hex code".
- **Copying.** A tap copies the code and shows the note "Copied #3A7BD5." Touch and hold offers "Copy #3A7BD5" (`doc.on.doc`), "Share…" (`square.and.arrow.up`: the code as text with a 600 × 600 px picture of the colour), "Save palette to Photos" (`photo.badge.arrow.down`) and "Save palette as a pin" (`pin`). The ⋯ menu offers "Copy all hex codes" (`doc.on.doc`; one per line; note "Copied N hex codes." — also "Copied 1 hex codes."), "Share palette…" (`square.and.arrow.up`: the palette picture and the codes on one line), "Save palette image to Photos" (`photo.badge.arrow.down`) and "Save as pin" (`pin`).
- **The "Copied" note** is a capsule at the bottom centre of the sheet (footnote semibold, regular material, ignoring touches): in over 0.15 s, read by VoiceOver after 0.5 s, out over 0.3 s after about 1.8 s. A newer note replaces an older one and removes any toast; a toast that appears removes a note still showing.
- **Saving to Photos** † asks for add-only access as in 7.8 (iOS asks the first time; no alert of PinBoard's own). Toasts over the sheet: ✓ "Saved the palette to Photos." · ✗ "Photos didn't take the palette picture." (or, when access was refused, ✗ "PinBoard isn't allowed to add to Photos. You can allow it in the Settings app › Apps › PinBoard › Photos.") · ✗ "The palette picture couldn't be made."
- **"Save as pin"** closes the sheet, then imports the palette picture as a new picture pin, like a camera photo: onto the board whose page the command came from (the board's ⋯, or the pin menus on its page), otherwise Unsorted; on the hidden side onto the page's hidden board or into Hidden. The usual confirmation shows beneath ("Added 1 pin to ‹Board›." / "Added 1 pin." / "Added 1 pin to Hidden." / "Added 1 pin to a hidden board."), and the "Looks familiar" question if an identical picture is a pin already. Failures: ✗ "The palette picture couldn't be made." and the alert "The photo couldn't be saved.".
- **How colours are chosen.** Up to 8, written "#RRGGBB" in capitals, the most prominent first (equal shares: the lighter first); fewer when the pictures have fewer clearly different colours. With more than eight candidates strong colours are favoured over greys. Each picture counts the same, whatever its size; at most 120 pictures are used (more are taken evenly from newest to oldest, a board's cover first); the same pictures always give the same colours. A picture is a picture pin, a video's poster or a link's preview; text pins and preview-less links give nothing. When the pins are exactly a board's whole content (sub-boards included) the palette is kept on the board and shown at once next time while the board is unchanged.
- **The palette picture** (Photos, "Share palette…", "Save as pin"): 1,600 × 1,000 px on white; the name ("N pins" or the board's name) in rounded bold 46 pt black above a row of tall rounded swatches with their codes under them (monospaced semibold 30 pt). A picture made from hidden pins or boards carries no name, so nothing hidden is written into Photos or onto a shared picture.
- **The board title surprise.** Tapping a board's name in its page's navigation bar (VoiceOver reads the name) fades the name in over 0.25 s as big letters filled with the board's colours at the top of the page; a tap on it or on the name again hides it. Its look and motion: 14.1. Its colours are the board's remembered palette when up to date, otherwise worked out in the background; meanwhile, and for a board without pictures, the accent colour and a paler (45 %) shade of it. On a locked hidden board the bar title says "Hidden" and a tap does nothing.

### 7.7 Thumbnails for videos (four ways; where the thumbnail lives)

A video's thumbnail is its poster: the still on its card and wherever the video's picture appears (12.5), kept in the library as a picture of at most 2,048 px (JPEG) with its own small copy. Every change remakes both and makes the AI look at the pin again ("Tagging…"). The first poster is picked when the video is added (12.5). Four ways to change it:

1. **"Pick another frame"** (`shuffle`; any number of videos). For each in turn the app takes a frame from a random spot in the middle that is not black, not a plain colour and not the picture shown now, and also writes it into the video file as its artwork (what Files, QuickTime Player and VLC show as its icon) in the background, for .mov, .mp4 and .m4v files only (a video being converted waits until it is done). Pill on the Pins tab, normal side only: "Picking a new thumbnail…" / "Picking new thumbnails N of M…". Toasts: ✓ "Changed N thumbnail(s)." ("Changed 1 thumbnail.", "Changed 5 thumbnails."); ✗ "Changed M of N thumbnails."; ✗ "The thumbnail couldn't be changed." (one video asked) or "No thumbnail could be changed." (several). A video whose file is missing or that has no other usable frame is skipped.
2. **"Choose from Photos…"** (`photo.on.rectangle`; one video). The system photo picker (pictures only, one); the picture becomes the poster, a picture of another shape being cut to the video's shape from its middle. ✓ "Thumbnail changed." or ✗ "The thumbnail couldn't be changed."; cancelling does nothing.
3. **"Use a picture pin…"** (`pin`; one video). A large sheet "Choose a picture" ("Cancel" at the top left) with a grid of this side's picture pins, newest first (the main grid's cards, spacing and column rule, at least 2 columns, no captions); a tap applies it as in 2, with the same toasts. Empty: `photo`, "No picture pins yet".
4. **"Use this frame as thumbnail"** (while the player is paused on a frame: Quick Look ⋯, the pin page; 10.1, 11.4): the exact frame; toasts "Thumbnail changed" / "Couldn't change the thumbnail" (no full stop; ✓ / ✗).

Ways 1–3 are the pin menu's "Thumbnail ▸" (dimmed while a thumbnail job runs, 7.1).

### 7.8 Save to Photos and Share (originals first; messages)

- **Kept originals.** With Settings › iCloud & storage › "Keep originals in a folder" (22.2), each picture's and video's full-size original is kept in a Files folder while the library holds a smaller copy. A pin has a kept original when it is a picture or video added while the setting was on; links, text, poster frames, items restored from an export and anything added straight into Hidden never have one (hidden pins' originals are never copied to the folder, so for them both commands use the library copy and say nothing; a pin hidden later keeps the one it has). Both commands hand out the original when there is one.
- **Fetching.** The folder may be in iCloud Drive or offline, so the original is fetched first: the Pins tab's pill reads "Fetching the original…" or "Fetching originals 2 of 5…" (the one being fetched, of those needed), and in the bar a spinner shows and the buttons dim. On the hidden side, and from Quick Look or a pin page, nothing shows. The first original is waited for up to 45 s; once one has not come, the rest are taken only if already on the device. One that cannot be had is replaced by the library copy, and the message says so. Crop, Rotate and Flip never touch a kept original, so afterwards both commands still hand out the unedited original.
- **"Save to Photos"** (`square.and.arrow.down`). Text pins and preview-less links are skipped silently. † PinBoard asks only for add-only access to Photos ("Add Photos Only": it can add new items but never sees, changes or deletes the rest of the library); iOS asks the first time, with the words "PinBoard adds a pin's picture or video to Photos only when you choose Save to Photos." (the old alert "Saving to Photos needs one setting" is gone). Pins are saved one at a time, in no particular order: a kept original as the file exactly as kept (HEIC, PNG, JPEG or the video, all details intact); a picture as the library holds it; a video as its file; a link with a preview as its preview picture. Toasts: ✓ "Saved N item(s) to Photos." ("Saved 1 item to Photos.", "Saved 3 items to Photos."); ✗ "Saved the copy on this device; the original wasn't reachable." (one item, a copy); ✗ "Saved N items to Photos. 1 original wasn't reachable, so its copy on this device was saved."; ✗ "Saved N items to Photos. K originals weren't reachable, so their copies on this device were saved." (K ≥ 2); ✗ "Nothing could be saved to Photos." (Photos refused or the files were unreadable); when access to Photos was refused (now or earlier, in the Settings app) the last one reads instead ✗ "PinBoard isn't allowed to add to Photos. You can allow it in the Settings app › Apps › PinBoard › Photos." †
- **"Share…"** (`square.and.arrow.up`). The system share sheet opens inside a regular sheet (medium and large, never a popover, on iPad and iPhone alike) in the look of the screen it came from, and closes by itself when sharing ends or is cancelled. Shared, newest pin first, in one sheet: a text pin as its text (its title when it has none); a link pin as its web address (failing that its title, else the address text); a video as its file; a picture as the library's JPEG file (each the kept original when there is one), so "Save Image", Messages and AirDrop work as for any picture. With no kept originals it opens at once; otherwise they are fetched first and, when some could not be, copies are shared and a toast says so as the sheet opens: ✗ "Sharing the copy on this device; the original wasn't reachable." (one) or "N originals weren't reachable: their copies on this device are shared instead." (several). Selection stays. If originals must be fetched while a job runs, choosing it does nothing. The same sheet serves the Colors sheet (7.6), a web result's address (19.2), "Share board…" (14.3) and an export (23.3).


## 8. Adding pins

Pins come in through the "+" menu, by dragging, from the clipboard, by saving web results and through a few other doors. Every door runs one flow: read everything, ask about look-alikes (8.4), save, report (8.5), then work in the background (8.6).

### 8.1 The "+" menu, item by item

The "+" sits at the right end of the navigation bar, before "⋯" (More), on exactly three screens: the Pins tab, every board page (board or sub-board, normal or hidden) and the Hidden page. On iOS 26 and later it is a plain `plus` on a round glass button; earlier, an accent `plus.circle.fill`. While an import works a small spinner replaces it (the menu still opens); Hidden has no status pill, so there the spinner is the only sign of progress. Empty pages say in words how pins come in (5.1, 14.1, 16.2).

| Item | Icon | Does |
|---|---|---|
| "Photos…" | `photo.on.rectangle` | System Photos picker, pictures and videos, up to 100 at once; imports when you confirm |
| "Camera" | `camera` | System camera, one photo |
| "Files… (pictures, videos, text)" | `folder` | System Files picker, several files |
| "Clipboard (picture, text or link)" | `doc.on.clipboard` | Imports what is on the clipboard now |
| *divider* | | |
| "Text pin" | `text.alignleft` | The "New text pin" editor (8.7) |
| "Link pin" | `link` | The "New link pin" sheet (8.7) |

### 8.2 Every way a pin comes in (Photos, Files, camera, clipboard, text, link, web results, drag-and-drop, folder) and what each kind becomes

- **Photos…** Pill "Reading N of M…", then "Importing N of M…". A video is copied as it is (made smaller later, 8.6; poster, 12.5). A picture is kept as a JPEG of at most 2,048 px on the long side plus a grid thumbnail; the photo's date taken, camera, location, keywords and caption stay with the pin (10.3; location is never sent anywhere); a title stored in the photo becomes the pin's title, otherwise it has none (the AI may write one).
- **Camera.** One photo per use in the full-screen system camera (permission asked the first time) → a picture pin (JPEG at 92%), not also saved to Photos, stored without the camera's date and place. Photos only: the camera never films, so PinBoard never asks for the microphone †. iOS's question the first time: "PinBoard uses the camera only to take a photo when you choose Camera from the + menu." † Always in the menu; on a device with no camera an alert says so (8.5).
- **Files…** A picture file → picture pin; a video file → video pin; a text file (read as UTF-8) → text pin, its contents as the text. File names become titles, tidied: underscores and hyphens turn into spaces ("golden-retriever_beach" → "golden retriever beach"); a camera-like name (fewer than 4 letters, or more digits than letters: "IMG_2041", "DSC00012") is dropped, leaving no title.
- **Animated GIFs †** (from Photos, Files, the clipboard, a drop, a link, web results or a folder) come in as videos: each frame keeps its timing (a frame asking for under 0.02 s gets 0.1 s), transparent parts are filled white, the longest side is at most 1,280 px, and from then on the pin is a silent video pin that plays, loops and remembers its place like any other (12.4). A GIF with one frame stays a picture.
- **Clipboard** (iOS may ask "Allow Paste"). In order: an animated GIF (as above); pictures (all, one pin each, JPEG at 95%; pill "Reading the clipboard…"); a link; text. One web address alone becomes a link pin (read fully if Settings says so, 9.2); any other text a text pin with no title.
- **Dragging in** (iPad; iPhone where the system allows dragging between apps). *Drop zones:* the Pins tab's page (Unsorted); a board's page (that board; a sub-board's page: the sub-board); a board tile (Boards tab, a sub-board row, Hidden's boards; not while boards are selected); the Hidden page (Hidden, unsorted). *Accepted:* pictures, videos, web addresses, text and PinBoard's own cards. A picture → picture pin (one dragged out of Safari that also carries its address is imported as the picture); a video file → video pin; an address → link pin; text → text pin unless it is one web address. Several items are read in the order dropped, one pin each. A zone that can take the content shows a dashed accent outline (gone after 3.5 s without movement or on cancel); otherwise the "not allowed" cursor. PinBoard's own cards dropped back are put on the board, not imported again (toasts, 8.5); on the Pins tab's page nothing moves; on the Hidden page they are hidden. *Dragging out:* a card carries its picture (a JPEG file), its video (a movie file) or a text pin's text; a link card only PinBoard's own reference.
- **Web results** (Explore, a board's "Keep exploring", a pin's "From the web", Quick Look over results). A round "+" on the card saves it onto the feed's boards (none: Unsorted; a Hidden feed: Hidden); the cards and their menu are in 19.2. A result whose source page is already a saved pin is not downloaded again: that pin is put on the chosen boards. The saved pin gets the result's title (cut to 60 characters), credit ("Photo by Name · Pexels", "Photo by Name on Unsplash" †) and source page; saving an Unsplash photo also reports the download to Unsplash † (19.2). *Explore only:* its ⋯ menu has "Save all N results…" ("Save 1 result…" with one left, "Save all results…" with none; dimmed before a search, offline, and when everything loaded is saved), which asks "Save N results to your library?" / "Each one becomes a pin in Unsorted. Results you saved already are left out." with "Save N results" and "Cancel"; pill "Downloading N of M…".
- **The share sheet †** (other apps: Photos, Safari, Files…; TestFlight build only). "PinBoard" in their share sheet saves pictures (several at once), GIFs, videos, web links and text onto a board you pick; PinBoard takes them in the next time it opens, as if they had been added from Files or as a link (23.7).
- **Other doors.** "Generate colors" › "Save as pin" (7.6) adds the palette picture to the board the colours were made for, else Unsorted (Hidden on the hidden side). "Save as pin" on an article passage makes a text pin (9.3). **Folders:** Settings › Library › "Import a folder…" turns a folder's pictures, videos, ".txt" files and ".url" shortcuts into pins and its sub-folders into boards, always on the normal side; a PinBoard export is re-created whole (file types and rules: 23.3). Its questions are 8.4's and its result is always an alert (8.5).

### 8.3 Where new pins land (board, Unsorted, Hidden); the hidden rules on import

| Started from | Pins land |
|---|---|
| "+" or a drop on the Pins tab | In Unsorted (no board); they show in All and in the Unsorted filter |
| "+" on a board page (sub-boards too); a drop on a board page or tile | On that board only, not Unsorted; on a hidden board they are hidden |
| "+" or a drop on Hidden | In Hidden, on no board |
| Web result saved in Explore | In Unsorted, or on the board chosen with "Save to board…" |
| Web result from a board's "Keep exploring" | On that board |
| Web result from a pin's "From the web" | On the boards that pin is on (a hidden pin's: Hidden) |
| "Generate colors" › "Save as pin" | On the board the colours were made for, else Unsorted |
| "Import a folder…" | On boards named after its sub-folders (made if missing); an export keeps its own |
| The share sheet in another app † | On the board picked there (never a hidden one), else Unsorted (23.7) |

- A pin put on a sub-board is filed on that sub-board only, never on a parent board as well; the boards above it count it, and list it while their page includes sub-board pins (the nesting rule, 2.4).
- Any chosen hidden board puts the whole batch on the hidden side. When a batch goes onto several boards only the deepest are kept; a pin is Unsorted only when no board was chosen.
- A board that keeps its pins out of All keeps new pins out of All too (they still show on the board, in search and under Pins › Kept out). Otherwise a new import is never "kept out".
- **Hidden rules on import:** look-alikes are looked for only on the side imported into; hidden work shows no pill, no board name and no count toward the back-up reminder; a hidden board is called "a hidden board" in messages; the sheets of a hidden import are covered in the App Switcher, and a question waiting about one is cancelled with its import when the app goes to the background; a folder import never goes into Hidden; a pin you already had is only put on the chosen boards, never moved into Hidden; a hidden pin's original is never copied to a folder (22.2); a hidden link's title is never sent to an image search (9.5).

### 8.4 "Looks familiar": the look-alike questions (exact wording, options, what each does)

**When it asks.** After everything is read and before anything is saved, each item is compared with the pins already on the same side (never across the hidden line). If nothing looks familiar, everything is saved at once, unasked.
- *Picture:* the same as a pin already here, even resized, re-saved or lightly edited. Two pictures are look-alikes when their 64-step light-and-dark signatures differ in **at most 6 steps** and their shapes are close (width ÷ height within 0.85 to 1.18 times: 20.8). The closest is shown. Imports ask again even about pairs once marked "Keep both" (10.6).
- *Video:* its poster is compared the same way. *Text:* the same text as a text pin, ignoring capitals and blank space at the ends (titles are not compared). *Link:* the same page as a link pin; addresses differing only in tracking, "http" versus "https", capitals or a trailing "/" are the same page. A link that is read and turned into a picture or video (a Pinterest picture pin, a picture or video file, a picture post, a page that is only a photo) is compared as that picture or video; a video post or a page with a video stays a link and is compared as a link †.
- *Never asked* (the pin you have is put on the chosen boards; the report says "was already in your library"): a picture that is byte-for-byte one of your own pins' files (a card dragged back in, or a picture saved from PinBoard and added again unchanged); a web result whose source page is already a saved pin's; a link to a picture or video whose page (a Pinterest pin's own address, a file's address, a post's address) is already a saved pin's source page (a Pinterest link showing the pin's number is recognised before anything is fetched).
- One question per look-alike item, in order. **Nothing is saved until the last is answered:** "Cancel import" saves nothing from the batch, new items included.

**The sheet.** It appears about half a second after what started the import closes: full height, inline title "Looks familiar", "Cancel import" at the left, cannot be swiped away; dark over Quick Look. Top to bottom:
1. Heading: "This picture looks like one you already have" · "This video looks like one you already have" · "This text is already a pin" · "This link is already in your library".
2. With several questions: "Question N of M".
3. Two equal columns: **"New"** (the new item at its own proportions; a video has a capsule with a play symbol and its length, or "Video"; a link a box with a link symbol and its address) and **"Already in your library"** (Hidden: "Already in Hidden"): the existing pin's card and, if it is on boards, "On: Board A, Board B".
4. Full-width answers: **"Save as a new pin"** (prominent); **"Add the existing pin to this board"** / **"Add the existing pin to these boards"** (only when the item would land on a board; if the existing pin is on all of them, the grey line "The existing pin is already on this board." replaces it); **"Skip this one"**.
5. With more than one question left, three small buttons: **"Save all N as new"**, **"Add all N existing"** (only when every remaining question has a board), **"Skip all N"** (N counts this one).
6. Footnote: "The other 1 item is new and will be added." / "The other N items are new and will be added."; with none: "Skipped items are not added. A pin you already have only changes if you add it to a board here."

An item saved as new may later appear under Possible duplicates (23.4). Opening another profile while a question waits drops the batch: toast "Import cancelled: another profile was opened." (normal side only).

### 8.5 What you are told: the pill texts, toasts, alerts (patterns)

**The status pill** (Pins tab, normal side only; 4.2) shows one line at a time, by priority: the import line, "Syncing with iCloud…", "AI is tagging pins… N of M", "AI is renaming pins… N of M" (the AI lines with a progress bar, the others a spinner).
- Import lines: "Reading N of M…" (items being read) · "Reading the clipboard…" · "Downloading N of M…" (several web results; not for one) · "Importing N of M…" (saving; "Importing N of M — converting video P%…" while a video converts) · "Reading the folder…" · "Reading the link…" · "Downloading the video…" (only for a link that is itself a video file, .mp4 or .mov †) · "Fetching the link…" (a plain link's title and picture) · "Reading link N of M…" ("Read existing links", 9.6).
- Lines from elsewhere ("Sorting N of M…", "Picking a new thumbnail…" / "Picking new thumbnails N of M…", "Converting video N of M (P%)…", "Transcribing N of M…" †, "Fetching the original…" / "Fetching originals N of M…") never take the pill from other work.

**The report after an import** is one line made of these parts in order, joined by spaces (X = board names joined with ", "; "pin(s)" is "pin" for 1):
1. "Added N pin(s) to X." — no board: "Added N pin(s)."; Hidden's "+": "Added N pin(s) to Hidden."; a hidden board: "Added N pin(s) to a hidden board."
2. "Put N existing pin(s) on X." ("on the board." without a name)
3. "1 was already in your library (now on X too)." / "N were already in your library (now on X too)." (no bracket without a board)
4. "Skipped N duplicate(s)."
5. Only when pins were added: "The video file couldn't be downloaded, so its link was saved instead." / "N videos couldn't be downloaded, so their links were saved instead." Since build 16 † this can only happen to a link that is itself a video file (9.2), which then becomes a plain link.
6. "N couldn't be read."
7. If none applies: "Nothing was added."

It is a **toast** when something was added, put on a board, already there or skipped by your choice, and nothing was unreadable and no video lost (checkmark if something was added or put on a board, else the info symbol); otherwise an **alert** with "OK", because a toast is gone after 3.5 seconds (3.4). A **folder import always ends in an alert**, built from the same parts plus "created M board(s)" (wording, and the toast "Folder import cancelled. Nothing was changed.": 23.3).

**Other toasts:** "Already hidden." · "Hid N pin(s)." · "Drop pins onto a board to put them there." (info) · "Those pins are no longer in your library." · "Everything shown is already in your library." (info). PinBoard's own cards dropped on a board report as in 14.2.

**Alerts** (one "OK", about half a second after what started the import closes):

| Door | Text |
|---|---|
| Photos | "Those items couldn't be read." |
| Files | "Those files couldn't be read as pictures, videos or text." (a failing picker: the system's own text) |
| Clipboard | "Nothing usable on the clipboard (a picture, text or a link)." |
| Drop | "Nothing droppable was found — try an image, a video, text or a link." |
| Web results | "This image couldn't be downloaded." / "None of those images could be downloaded." |
| Camera | "The photo couldn't be saved." · no camera: "This device has no camera." † |
| Link | "That doesn't look like a web address." · "That link couldn't be added." |

### 8.6 What happens afterwards in the background (AI, conversion, transcripts †, originals) and what you see of it

The pin is usable at once; then, in the background:
1. **Boards tidied:** a pin put on a board and on one inside it keeps only the inner one.
2. **Back-up count:** only normal-side pins count; after 50 since the last export (or "Later") the Pins tab shows the back-up reminder (4.2).
3. **The AI looks at each new pin** on the device (and with the cloud model if on, 20.4): tags, a title if none (never over one you typed), text in pictures, colours; pill "AI is tagging pins… N of M" (20.1). A link with a preview picture is worked from the page's text first; one with **no preview picture** is tagged from its text alone and never named by the AI ("Suggest a title" then answers "There's nothing for the AI to go on: this link has no preview picture.").
4. **Videos,** one at a time: a second look about 2 seconds after the batch (waiting while the AI works) fills in an unknown length and sound and swaps a black poster for a lighter frame (12.5); **made smaller** when larger than Settings › Videos (or iCloud & storage) › "Video quality" (Original, 4K, 1080p, 720p; default 1080p; Original converts nothing), oldest first, pill "Converting video N of M (P%)…" (a hidden video is not converted while "Keep originals in a folder" is on); **speech written down** † once the AI and any conversion are done, on the device, into the pin's note (10.3), when Settings › Videos › "Transcribe speech in videos" is on (default on); its progress, "Transcribing N of M…", shows in Settings › Videos (20.10).
5. **Originals:** with Settings › iCloud & storage › "Keep originals in a folder" on (default off) each new picture's untouched original is copied there, never a hidden pin's; a minute later originals iCloud holds in full may leave the device (22.2).
6. **Links:** the page is read or its preview fetched (9.1–9.2). **Look-alike marks:** new pins are re-checked and may appear under Possible duplicates.
7. Leaving the app meanwhile only pauses the work. While an import or iCloud sync runs, Profiles will not switch or create (23.1).

### 8.7 The text-pin editor and the link-pin editor sheets

**"New text pin"** (the same editor, headed "Edit text", rewrites a text pin from its page, 10.1). Full height (an ordinary form sheet on iPad), top to bottom:
1. A title field, placeholder **"Title (optional — the AI can write one)"**; Return only puts the keyboard away.
2. A multi-line text area (160 to 320 pt tall, ordinary body type, not the text-pin typeface); the keyboard rises in it by itself.
3. Caption: "The text becomes a pin: it sits in the grid, can go on boards, and is searched like everything else."
4. "Cancel" and "Save"; Save is dimmed until there is a title or text (blank space does not count); both are trimmed. Once anything differs from how it opened, swiping down does nothing: only Cancel or Save closes it. For a hidden destination both this sheet and the link sheet are covered in the App Switcher.

*Save, new:* the pin is added as the newest, through the look-alike question ("This text is already a pin"), with the toast "Added 1 pin to ‹Board›." / "Added 1 pin." / "Added 1 pin to Hidden." / "Added 1 pin to a hidden board." A typed title is yours for good. With no title, and Settings › AI › "Write titles for untitled pins" on (default), the AI writes one a moment later: the first non-empty line, cut at a word to about 50 characters with "…" (or a short written title where Apple Intelligence is used); tags come from the key words of text and title. *Save, existing ("Edit text"):* only changes are saved; a changed title becomes yours; a changed text makes the AI look again (new tags, and a new title if the pin's is empty or still the AI's); an emptied title makes the pin untitled; the text may be emptied if the title is not; no toast.

**"New link pin"** — a sheet at medium height (can be pulled to large), inline title "New link pin". (Edit mode, titled "Edit link" with a title field, and the address sheet of other pins: 7.3.)
- "Cancel" / "Save". Save is dimmed until the whole text (blank ends ignored) is one line under 2,048 characters that reads as an address starting "http://" or "https://" (any capitals) with a host; a word, a phone number, "mailto:…" or a sentence containing a link leaves it dimmed. Swiping down does nothing once the field is not empty.
- The **address field** (placeholder "https://…", no automatic capitals or correction, Return saves, keyboard up at once). **"Will be saved as: ‹address›"** (up to 3 lines, selectable) only while "Clean links" would change what you typed (9.1). **"Use the link on the clipboard"** (small bordered, `doc.on.clipboard`) when the clipboard holds text (decided without reading it, so no "Allow Paste" appears from opening the sheet); tapping it fills the field if it is a web address, otherwise the button disappears. A footnote:
  - links read fully †: "The page is read once and kept in your library: its title and picture, an article's text, a video's details. A link to a Pinterest picture, a picture file or a video file (.mp4, .mov) becomes that picture or video; a video on TikTok, Instagram or another site stays a link with its picture."
  - previews on, reading fully off: "The page's title and preview picture are fetched once and kept in your library."
  - previews off or Offline mode: "Link previews are off, so the card shows the address only."
- *Save:* the sheet closes and the link goes through the usual steps (look-alike question "This link is already in your library", pill, report). A non-address gives the alert "That doesn't look like a web address."; a failure "That link couldn't be added."

## 9. Links

### 9.1 A link pin: preview, title, Clean links, the link panel (Open link, Refresh preview / Read link again)

**What it keeps.** An address, a title, a preview picture when one was found, a short description (up to 300 characters) and, when links are read fully (9.2), its *kind* with writer, date, site name, text, comments, view count and length. Kinds: **"Web page"** (icon `link`), **"Article"** (`newspaper`: a readable article, a Reddit text post or an X post) and **"YouTube video"** (`play.rectangle`). "Pinterest pin", "Picture from the web" and "Video from the web" label pins that came out of a link (9.2). In filters a link is a "Links" pin.

**A new link** appears at the top of the grid at once, titled with the site's name (the address without "www." and anything after the host) and with no picture; within 25 seconds at most the card fills in with the page's title, preview picture and kind icon, then the AI tags it (8.6).

**The card** (grid rules: 6.2). *With a preview picture:* the picture at its own proportions (taller than 1 : 5 is cut to 1 : 5), a round translucent badge with the kind's icon at the top-left, the title under it (one line) and the site (host without "www."). *Without one* (none found, previews off, offline, not read yet): a compact card, at least 88 pt tall, the kind's icon at the left and the title (up to two lines; with no title the address, else "Link"); no site line.

**Titles.** A title you type (the pencil beside the title, or the link sheet's field) is yours for good: reading again, refreshing and pointing the link elsewhere never replace it. Otherwise the page's own title (up to 120 characters) replaces the site's name when the page arrives and counts as imported, so automatic naming leaves it alone. The site-name stand-in counts as written by the AI (the page shows "Written by AI"), and the AI may replace it when a page has no title; a link with no preview picture is never named by the AI (8.6). Clearing a title brings back the site's name and, when previews are allowed, re-reads the page for its own. Reading again never swaps a good result for a poorer one.

**Plain previews** (Settings › Links › "Fetch link previews", default on) serve links that are not read fully (reading off, or nothing could be read) and ".url" shortcuts. Off, or in Offline mode, the page is never contacted: no picture, the title stays the site's name, no refresh button. On, the page is fetched once right after saving (pill "Fetching the link…"): HTTPS only (an "http" address is asked for as "https"), no cookies, an ordinary web page only (not a PDF or picture), the first 2 MB, giving up after 15 seconds. Title: the page's sharing headline, else its title, else its Twitter-card title (tidied, ≤120); description (≤300): the sharing description, else the page's; picture: the sharing picture (checked to be a real picture), else a stand-in † (9.5). A login or "are you a robot?" wall is not kept (9.2). If nothing can be read nothing changes. A link added offline is previewed later only on request: "Fetch preview", "Read link again" or "Read existing links" (9.6).

**Clean links** (Settings › Links › "Clean links", default on). Every http or https address saved — typed, pasted, dropped, from a ".url" file or an export, chosen in "Edit link", the source page of a picture, video or text, the address a read link is saved with — loses its tracking; the page is the same.
1. *Wrappers* are unwrapped, up to three deep: Google's "…/url?q=…" (any country), "l.facebook.com/l.php?u=…", "lm.facebook.com/l.php?u=…", "l.instagram.com/?u=…", "href.li/?…".
2. Scheme and host go lower-case; the path stays.
3. An Amazon product page (any Amazon site) becomes "/dp/‹product number›" or "/gp/product/‹product number›" (ten letters and digits): the name, "ref=…" and every parameter go.
4. *Tracking parameters* go, all others stay: fbclid, gclid, gclsrc, dclid, gbraid, wbraid, msclkid, yclid, twclid, ttclid, li_fat_id, mc_cid, mc_eid, igshid, igsh, ig_rid, ref_src, ref_url, spm, sr_share, srsltid, _ga, _gl, sscid, epik, mkt_tok, trk, trkcampaign, ncid, cmpid, rb_clickid, ito, xtor, share_id, gad_source, ref_; hsa_acc, hsa_cam, hsa_grp, hsa_ad, hsa_src, hsa_tgt, hsa_kw, hsa_mt, hsa_net, hsa_ver, hsctatracking, _hsenc, _hsmi, _hsfp, __hssc, __hstc, __hsfp; pk_campaign, pk_kwd, pk_source, pk_medium, pk_content; at_medium, at_campaign, at_source, at_custom1–4; anything starting utm_, mtm_, oly_ or vero_ (capitals ignored). On certain sites only: "s" and "t" on x.com and twitter.com; "si" and "feature" on YouTube; "si" on Spotify; "ref" on Amazon. Meaningful ones stay (YouTube's v, t and list, a search's q).
5. A text-highlight mark ("#:~:text=…") goes; any other "#…" stays; a dangling "?" or "&" goes.

"Clean existing links" (Settings › Links, normal side) cleans every saved link pin (only real changes; titles and previews stay; the source pages of pictures, videos and texts are left alone): toast "Cleaned N link(s)." ("Cleaned 1 link.") or "Your links had no tracking to take out." With "Clean links" off a link is saved as given, though two addresses differing only in tracking still count as the same page.

**The link panel** (on a stored link pin's page, 10.3): a box with 16-pt corners on the secondary background, holding the site (`globe` + host), the address (up to three lines, selectable) and small buttons: **"Open link"** (`safari`, prominent; default browser outside PinBoard; only for an http or https address; bordered when a YouTube "Play" is shown, which is then the prominent one) and **"Read link again"** (links read fully) or **"Refresh preview"** / **"Fetch preview"** (`arrow.clockwise`, bordered), offered only when the web is allowed and "Fetch link previews" is on; it says nothing when done, the card and page just update. A round "Edit link" pencil beside the panel opens the link editor (7.3).

### 9.2 "Read links fully": what each kind becomes — article, YouTube, Pinterest, Reddit, TikTok, Instagram, X, a picture/video file, a generic page, a login wall; limits (sizes, time); no videos from sites or pages †

**When.** Settings › Links › "Read links fully" (default on) makes saving a link read the page and keep what is worth keeping. It needs "Read links fully" on, "Fetch link previews" on and Offline mode off; otherwise the plain preview (9.1) is used. *Read:* links typed in the sheet, from the clipboard, dropped, pointed at another page with "Edit link", "Read link again", "Read existing links" (9.6). *Not read:* ".url" files of a folder import, links re-created from an export, "Add link…" / "Edit link…" on pictures, videos and texts, web results. Nothing is posted, no account used, nobody logged into: only what a visitor sees.

**No videos from sites or pages †** (build 16, App Review guideline 5.2.3: an app may not download media from other services without their permission). A video on TikTok, Instagram, Reddit, X or Pinterest, and a video inside any web page (one the page declares with its sharing tags or video data), is **never downloaded**: the link becomes an ordinary link pin ("Web page") with the post's or page's picture (a TikTok cover, a Reddit video's first frame, an Instagram reel's picture, a Pinterest video pin's picture, a page's sharing picture) as its preview, and its title, caption and creator. Picture posts are unchanged: a Pinterest picture pin and a picture post on Reddit, TikTok or Instagram still become picture pins. Only a link that **is itself a video file** (an .mp4 or .mov address, or one whose server says it is a video) is still downloaded, as a browser's download would be. The pin's page tells you once how to get such a video in anyway (10.3). Before build 16 these videos were saved as video pins (24).

**While it works:** pill "Reading the link…" (or "Downloading the video…" for a link that is itself a video file †). The whole reading takes at most 25 seconds, then the link counts as unread and is saved the plain way. Only HTTPS is contacted: the link's own site and the services it names (YouTube's oEmbed service and, with a key, its Data API †; Reddit's public data; TikTok's and X's sharing services). No cookies are sent or kept †; pages are asked for as Safari on an iPad does. (YouTube's watch page, with its cookie question, and TikTok's cookie for its video files are no longer used †.)

**Recognised in this order:** YouTube (by address); Pinterest (by address); a picture or video file (by the ending of its address: jpg, jpeg, png, gif, webp, heic, heif, avif; mp4, mov, m4v); a post on Reddit, TikTok, Instagram or X; any other address, fetched and tried as: a login wall → plain link; an article → article; an ordinary page → page details, or for a photo page the picture (a page whose point is a video is an ordinary page too †). A link whose server says it is a picture or video is treated as one.

**Short links** from these services are saved as the address they lead to: t.co, bit.ly, buff.ly, ow.ly, tinyurl.com, goo.gl, lnkd.in, trib.al, dlvr.it, ift.tt, amzn.to, amzn.eu, a.co, fb.me, is.gd, rebrand.ly, cutt.ly, shorturl.at, tiny.cc, bl.ink, flip.it, wp.me, apple.co, spoti.fi, nyti.ms, wapo.st, bbc.in, cnn.it, reut.rs, econ.st, bloom.bg, g.co, hubs.ly, hubs.la, mailchi.mp, on.ft.com. Any other link is saved as given, even if it redirects, unless it ends on a post or video of YouTube, Pinterest, Reddit, TikTok, Instagram or X, when the address it led to is saved. A short link to a picture or video file stays as is; one that leads to a login wall becomes a plain link carrying the sign-in address.

| Link | Becomes | What is kept |
|---|---|---|
| **Ordinary page** | Link pin, "Web page" | Title, description, site name, writer, date; picture: the page's sharing picture, else a stand-in † (9.5). The page shows the description and, when known, a grey line "By Jane Doe · Jan 2, 2024". |
| **Page with a video** † (says it is a video, or shows one in its sharing tags or video data) | Link pin, "Web page" (or "Article" if it reads as one); the video is never downloaded | As an ordinary page: title, description, site name, the page's picture (or its oEmbed thumbnail). |
| **Photo page** (says it is a photo or image, and its main picture is at least 600 px on the longer side) | Picture pin; title ≤60; source page = the page | |
| **Article** | Link pin, "Article" | 9.3 |
| **YouTube** | Link pin, "YouTube video" | 9.4 |
| **Pinterest pin** (pinterest.com and country sites, pin.it; a board or profile is an ordinary page) | Picture pin (largest size); a video pin † → link pin ("Web page") with the pin's picture as preview, its video never downloaded | Title = the pin's, without " \| Pinterest" (generic "Pin on …" stand-ins ignored; ≤60); source page = "https://www.pinterest.com/pin/‹number›/" whatever short link or site it came from; creator as writer, date, the destination link (never a Pinterest address), site "Pinterest". |
| **Reddit post** (reddit.com sub-domains, redd.it, "/r/x/s/…" share links, v.redd.it) | Video post † → link pin ("Web page") to the post with the video's first frame as preview, nothing of the video downloaded; picture or gallery → picture pin (first picture); text post → "Article" whose text is the post (headings "## ", lists "• ", quotes "> "); link post → ordinary link to the post | Title ≤120, site "r/subreddit", writer "u/name", date; a media post's source page is the post. "[removed]" or "[deleted]" with no picture or video stays a plain link. |
| **TikTok** (tiktok.com, short links) | Video † → link pin ("Web page") with its cover picture, the video never downloaded; photo post → picture pin; else a plain link keeping the caption | Title = caption (≤80) or "TikTok by ‹name›"; writer "@username"; date; views; site "TikTok". |
| **Instagram** (/p/, /reel/, /reels/, /tv/) | Reel or video † → link pin ("Web page") with its picture, the video never downloaded; picture post → picture pin; with only a caption a plain link; its login page is never kept | Title = caption (≤80) else "Instagram post by ‹name›"; writer; date; site "Instagram"; source page "https://www.instagram.com/p/‹code›/". |
| **X post** (twitter.com, x.com, "…/status/‹number›") | Link pin, "Article": title = the post's text (≤80), text = the whole post; pictures and videos of the post are not fetched | Site "X", writer "Jane Doe (@jane)", date; byline "By Jane Doe (@jane) · X · Jan 2, 2024 · 1 min read". |
| **Picture file** | Picture pin (≤30 MB, must open); title = file name tidied (≤60) or the page's | Source page = the picture's address. |
| **Video file** (an address ending .mp4, .mov or .m4v, or one whose server says it is a video) | Video pin: mp4, mov, m4v or 3GPP only (saved as mp4), ≤500 MB, downloaded with "Downloading the video…"; playlists, streams and text pages refused; title = file name tidied. The only kind of link whose video is downloaded † | If it cannot be had: a link pin of kind "Video from the web", and the lost-video line (8.5). |
| **Login or "are you a robot?" wall** | Plain link, title = the site's name, nothing else kept | A wall is: a redirect that ends at a sign-in address (a host starting login., accounts., auth., sso., signin. or consent.; or a path segment such as login, sign-in, signup, authwall, checkpoint, sso or oauth, which counts only with a query like "?next=…", a page with under 600 characters of text or a password field: an address you typed yourself is never a wall by its address, so "…/wiki/OAuth" is fine); a title that is exactly "Log in", "Login", "Sign in", "Sign up", "Instagram" or "Facebook"; a title containing "Log in or sign up", "Login • Instagram", "Log in to Facebook" or "Sign in to continue" on a page with under 600 characters of text or a password field; a title of at most 70 characters starting (as a whole word) with one of 25 phrases such as "Log in", "Please sign in", "Just a moment", "Attention required", "Access denied", "Verify you are human", "Are you a robot" or "Captcha", on a page with under 600 characters of text; or a page that is only a password form (no picture of its own, little text). |

**Dates** a page gives as a day alone ("2024-01-02", "2 Jan 2024") show as that same day wherever the device is; a date with a time shows as the day it falls on in the device's time zone; a date written any other way is left out. Lines are built from "By ‹writer›", the site's name, the date in the medium style ("Jan 2, 2024"), "N min read" and "N views", leaving out what is unknown and joining the rest with " · ".

**"From ‹site›"** appears on a picture or video a link became, and on pins of kind Pinterest pin, Picture from the web or Video from the web: `globe` + "From Pinterest" / "From images.example.com" (the site's name, else the host); "By Jane Baker · Nov 12, 2019" (as known); "Open linked page (bakery.com)" (`arrow.up.right.square`, default browser, only for a web address); and, on picture and video pins only, the pin's description when it adds something to the line under the title.

**What a link becomes in the library.** *Video* (only a link that is itself a video file †): "Downloading the video…", then a video pin stored like one chosen in Files (poster, length, sound; smaller copy and transcript per Settings). *Video lost* (too big, not playable, refused, cut off): the file address becomes a "Video from the web" link and the report adds the lost-video line (8.5, so an alert). A video on a site or inside a page is never downloaded, so it is never "lost": it is a link with its picture from the start †. *Picture:* a picture pin; the untouched picture also goes to the originals folder when kept, never for a hidden pin. *Link:* a link pin filled with what was read. *Nothing could be read* (offline, no answer in time): a plain link, preview fetched afterwards, no message. Look-alikes are asked about as in 8.4. **Reading never erases:** reading again writes only what it finds; an article never becomes a plain page again (a teaser or cookie page leaves its byline, "Read article", text, description and picture); a typed title is never replaced.

**Limits.** Whole reading 25 s, then unread; stand-in picture look ≤10 s of what is left; one request 15 s, one fetch 30 s (a video: 30 s without data, 10 min in all); a page: first 3 MB; a small service answer 2 MB; a picture 30 MB; a video 500 MB; a page's pictures tried: 3 (YouTube and Pinterest thumbnails 4); titles 120 characters (80 for TikTok, Instagram and X captions; 60 for picture and video pins); short description 300; article text and video description 40,000; YouTube comments 5 × 2,000; reading time at 230 words a minute (rounded, at least 1); title sent to a picture search 100.

### 9.3 Articles: byline, "Read article" sheet, highlights (make, remove, save as pin, the lists) †

**What counts.** A page with at least 600 characters of reading that says it is an article or blog post, keeps its text in an article block, or has 1,500 or more characters. **What is kept:** the text, up to 40,000 characters (cut at a paragraph end if one lies in the last quarter, else at a word, with "…"): the article's own paragraphs, without menus, headers, footers, share buttons, sidebars, related lists, promos, newsletter and cookie boxes, ads, breadcrumbs, pop-ups, readers' comments, forms, pictures, captions and videos; paragraphs under 20 characters and big headings that repeat the title are dropped; smaller headings become "## " lines, list items "• ", quotations "> ". Title: the structured headline, else the sharing title, page title or first heading, without the site's name tacked on (" | ", " - ", " — "…), ≤120. Writer: from the page's data (up to three names, joined ", ") or a byline ("By", "Written by", "Posted by" removed; ≤60; never an address, "@handle" or date). Also date, site name (publisher, else site name, else host), description (the page's, else the first plain paragraph, ≤300) and a lead picture (the article's data picture, else the sharing picture, else the first large one in it, ≥200 px wide; else a stand-in †).

**On the page:** the byline **"By Jane Doe · The Verge · Jan 2, 2024 · 5 min read"** (whatever is known, joined with " · ") and, when text was kept, **"Read article"** (large bordered button, `doc.plaintext`), then the highlights list. "Read article" exists only on the page, not in Quick Look, grids or menus.

**The reader sheet.** Full height (page-sized on iPad), inline title = the site's name or "Article", "Done" at the right; covered in the App Switcher for a hidden pin; toasts ("Saved as a pin", "Copied") float over it. A centred column at most 700 pt wide: the title (bold, selectable; "Article" if none), the byline, a divider, the text and "Highlights (N)" with every highlight. The text is saved with the link (opens at once, works offline) and is one selectable piece: a selection runs across paragraphs. It follows Dynamic Type: headings bold, list items with a hanging "• ", quotations italic grey and indented; addresses, phone numbers and dates are not turned into links; light or dark follows the app.

**Highlights †**
- *Make one:* select words. The edit menu lists PinBoard's items first, then the system's (Copy, Look Up, Translate, Share…): **"Highlight"** (`highlighter`; not offered when the selection already lies inside one highlight), **"Remove highlight"** (`highlighter`, red; when the selection touches a highlight, even by a letter; removes every one touched), **"Save as pin"** (`quote.opening`; any selection with words). A selection of only spaces or line breaks offers neither "Highlight" nor "Save as pin".
- *What is kept:* the selected words, trimmed at both ends. Highlights never overlap: one that overlaps or touches another merges with it. They are drawn as the accent colour at 28% behind the words; tapping a highlighted passage selects all of it (best effort). They belong to the article: saved with it, there each time it opens, carried to other devices.
- *If the article is read again* and its text changed, each highlight is found again by its words (spaces and line breaks ignored; the nearest to the old place if the words repeat); one whose words are gone is not drawn but stays in the list, last, tagged "Text changed". Pointing the link at another page removes all highlights.
- *The list* (on the page under "Read article", the first five; in the sheet, all): header `highlighter` + "Highlights (N)"; one row per highlight in reading order: a thin accent bar, the quote (italic, secondary, up to 8 lines), a "⋯" button (VoiceOver "Highlight options"), and the same menu on long-press: **"Save as pin"** (`quote.opening`), **"Copy"** (`doc.on.doc`; toast "Copied"), **"Remove highlight"** (red; nothing is asked). Beyond five rows the page shows "Show all N", then "Show fewer".
- **"Save as pin"** creates a text pin at once, without a look-alike question: text = the quote exactly; title = the article's (none: untitled, and the AI may title it); on the article's boards; hidden or kept out of All as the article is; source page = the article's address; credit "Read on ‹site name›" ("Open the article" without one); the AI tags it. Toast **"Saved as a pin"** (`quote.opening`; it names no board). Saving the same passage twice makes two pins. The pin's page carries the "From the article …" row (10.3). Exports keep no pointer to an article outside the export, nor to a hidden one.

### 9.4 YouTube: what is shown; Play (embedded player, no downloading); comments with a key

- **Recognised** by address: youtube.com/watch?v=…, youtu.be/…, and /shorts/, /embed/, /live/, /v/, /e/ on youtube.com (also m. and music.) and youtube-nocookie.com. A channel, playlist or other site is no video. The result is always a link pin of kind "YouTube video"; **nothing of the video is ever downloaded** (24).
- **Only YouTube's own services for apps are used †** (its terms allow nothing else): its oEmbed service and, with a key, the YouTube Data API. **The watch page is never read** (before build 16 it filled in the description, date, length and views without a key).
- **Kept without a key †:** title (≤120), channel (as writer), site name "YouTube" and the thumbnail as preview picture (largest size first; 4 tries) — from oEmbed. No length, description, date or views: the details line then shows only the channel.
- **Kept with a key** (Settings › Links › "YouTube API key", placeholder "Optional"; sent only to YouTube, under YouTube's Terms of Service and Google's Privacy Policy, linked under the key, 21.6 †): the Data API is used first and adds the date, length, views, the whole description (line breaks kept, ≤40,000; its first lines, ≤300, are the short description) and the **top 5 comments** (writer, text ≤2,000, likes, date); oEmbed fills in what it lacks. A wrong key, no quota or disabled comments just leave those out. When neither service answers, the link is saved plain.
- **The card:** thumbnail, the `play.rectangle` badge, the title and the host of the saved address ("youtube.com", "youtu.be", never the word "YouTube"). On the page the thumbnail tops it (tap → Quick Look; no play button on it).
- **On the page,** under the link panel: **"Play"** (large prominent button, `play.fill`; shown only when the address names the video and the web is allowed; "Open link" then turns bordered); the details line **"Rick Astley · Oct 24, 2009 · 3:33 · 1.6B views"** (channel, date, length "4:13" or "1:02:03", views as 999, 1.2K, 12K, 3.4M, 1.1B — one decimal under 10 of a unit, rounded down — always "views", even for one); the description (four lines, selectable, with **"More"** / **"Less"** when over 280 characters or four lines); **"Top comments"** (`text.bubble`) with up to five: writer, text, likes ("♡ 1.2K"; VoiceOver reads each comment as one item, "@fan: Still a classic. 1200 likes").
- **The player.** "Play" opens a sheet titled "YouTube" with "Done": always dark, 16 : 9 centred on black, page-sized on iPad, YouTube's own embedded player in its privacy-enhanced form (no cookies until you play), starting at once. Its full-screen button and picture-in-picture work, except for a **hidden** pin (neither; the sheet is covered in the App Switcher). Links tapped inside open outside PinBoard. "Done" stops the sound at once; nothing it stored is kept. No "Play" in Offline mode.

### 9.5 A picture for every link: the page's own pictures, the web-search fallback and its setting †

When an ordinary page or article names no preview picture that can be had, PinBoard looks for a stand-in; the first that works wins:
1. **One of the page's own pictures,** ranked by declared size (width × height; one side only counts as square; none counts as 640 × 360; ties keep page order): at most 12 listed, the first 3 tried. Skipped: under 120 in either declared side, pictures written into the page, drawings (SVG) and animations (GIF), addresses naming a logo, sprite, spinner, tracking pixel, emoji or favicon, pictures the page labels logo, icon, sprite, avatar, badge or emoji, repeats, and pictures in a menu or footer. It must open and be ≥120 px on its short side.
2. **A web search,** only with Settings › Links › **"Find a picture for links without one"** on (default off; footer "It may not be a picture from that site."), the web allowed and Explore's picture source ready (Wikimedia Commons by default; it and Openverse need no key, while Pexels, Pixabay and Unsplash count only once their key is entered): the first picture that source finds for the link's title (tidied, ≤100 characters; no search for an empty title or just the address or site name). It may not be from that site.

At most 10 seconds within the 25. Nothing is said when nothing works, and the search leaves no notes in Explore's "Details". **Never** for a hidden link's title (its page's own pictures are still tried), nor for sites with their own reader or a login wall (a page with a video counts as an ordinary page since build 16 †, so it may get one); "Read link again" never replaces an existing picture by a stand-in.

### 9.6 "Read link again" and "Read existing links (N)"; "Edit link" to another page

**"Read link again"** (link panel and the page's ⋯, when links are read fully; otherwise "Refresh preview" / "Fetch preview"): pill "Reading the link…", no message at the end. It keeps what it finds (9.2); a page that now names a picture replaces the old one. A link that turns out to be a picture (Pinterest picture pin, picture file, photo page, picture post) **becomes a picture pin in place**: same pin, boards, tags, note and typed title; source page = the pin's own address (Pinterest) or the link's; a page-derived title cut to 60; original kept per Settings; the AI looks at it as a new picture. A link to a video (a video file, a video post, a page with a video) stays a link and gets the video's picture; nothing is downloaded. A hidden link works the same, minus the stand-in web search and the pill.

**"Read existing links"** (Settings › Links, normal side; hidden in Offline mode) reads, one at a time with 0.3 s between, links saved before reading-fully existed, while it was off or offline, or whose reading failed, and looks for a picture for pages with none. *Taken:* link pins never read fully (including ".url" and export links) and † ordinary pages and articles still without a preview picture. *Not taken:* YouTube, Pinterest pins, pictures and videos from the web, any link with a picture. The button reads **"Read existing links (N)"** (N counted live) or "Read existing links" when none; it is dimmed when none waits or reading is not in effect. Unlike "Read link again" an unreadable link is left exactly as it was, and the pill counts: **"Reading link N of M…"**.
- While it runs the row shows a spinner, "Reading 3 of 12…" ("Reading…" until the count is known, "Stopping…" after Stop) and a borderless **"Stop"**. One run for the whole app: it continues when Settings closes, a second cannot start, profile switching waits. Stop gives up on the link being read (it keeps what it had and is not counted as unread); links not reached stay as they were; one deleted, hidden or no longer needing it is skipped. The run also ends with "Stopped." if another profile is opened some other way.
- **When it ends** a toast (checkmark if at least one link was read, else info): "Your links have all been read already." (none waiting); otherwise the sentences that apply — "Stopped." · "Read N link(s)." · "N couldn't be read." (if none was read and it wasn't stopped: "None of your links could be read.") — or "No links were read." A login page counts as read; a link whose page has no picture stays in the list, so N may never reach zero.

**"Edit link" to another page** (sheet and toasts: 7.3). If the cleaned address leads to another page, everything about the old page goes — preview picture (the card shows the site's name until the new one arrives), description, article text, kind, writer, date, site name, linked page, comments, views, length and the **highlights †** — and the new page is read like a new link; a reading of the old page still under way is thrown away. The same page under another spelling (tracking, capitals, http/https, trailing "/"): only the address changes.

### 9.7 PinBoard's private browser (what it keeps, bar, buttons, address rules) and "Open in browser"

PinBoard has one browser of its own, used only for "Search this picture on the web" (7.4) when Settings › Explore & web search › "Open web searches in" is **"PinBoard (private)"** (default; the other choice, **"Default browser"** †, hands the address to the device). Everything else that opens a page — "Open link", "Open source page", "Open linked page", a link tapped in the YouTube player — opens the default browser outside PinBoard.
- **Sheet:** large only (page-sized on iPad); covered in the App Switcher for a hidden pin or feed. A viewer: no address field, tabs, bookmarks or history. Navigation bar: the page's title; until it has one the host being opened ("lens.google.com"); "Web search" if there is no host; "Done" at the right.
- **Address strip** under it: an icon and the host without "www." of the page you are on, centred; a filled padlock (`lock.fill`) for an encrypted page, a warning triangle (`exclamationmark.triangle`) otherwise (also before loading); a thin progress line runs along its bottom while loading. VoiceOver reads the strip as "Secure page, example.com" or "Page, example.com".
- **Note bar** (only when needed; an info icon and one line; gone on the next page): "PinBoard's browser opens only web addresses (https or http)." · "PinBoard's browser can't show this kind of file. “Open in browser” can." · "The page didn't load. ‹the system's reason›" (nothing for a load you stopped or replaced).
- **The page:** asked for as Safari on an iPad; nothing plays by itself; a link wanting a new window opens in the same view; swiping from the left or right edge goes back or forward; it reloads itself if the system drops it for memory. Only http and https load.
- **Bottom bar,** four evenly spaced icons: Back (`chevron.backward`, dimmed with nothing to go back to), Forward (`chevron.forward`), Reload (`arrow.clockwise`, turning into "Stop loading", `xmark`, while loading) and **"Open in browser"** † (`safari`; hands the page you are on — or, if that is not a web address, the one the sheet started with — to the default browser).
- **Keeps nothing:** a private session with no cookies, history, cache, saved page data or logins; closing empties the page (its sound stops) and wipes everything. Confirmations float 96 pt above the bottom edge, clear of the bar.

## 10. The pin page

One pin shown big, with everything about it. A web result not yet in the library gets a page that looks the same (a "draft", 10.5).

### 10.1 Reaching it; one column or two (the exact rule); the media box and its height (one/two columns) †

**Ways in.** Tap a picture, text or link card in a grid, or any card in the page's own "More like this": that pin's page, with the list as its swipe neighbours. A **video** card opens Quick Look instead (11.1); its ⋯ › "Show info" reaches the page (11.4). A web result opens a draft page (10.5); a quote pin's quote row opens the article's page (10.3). Pages opened from Settings › Library › "Possible duplicates" sit inside Settings (their ⋯ has no "Settings…").

The page is a pushed screen with the system back button and a small centred title; all of it scrolls. It belongs to one side of the library, fixed when it opens, and lists neighbours of that side only. A hidden pin's page asks to unlock first (16.1) and its sheets are covered in the App Switcher (3.5).

**One column or two.** The page decides by its own width, never by device: an iPad in a narrow Split View gets one column, a large iPhone turned sideways may get two. **Two columns only when all three are true:** the window is regular width; the page is at least 768 pt wide (the details column needs 320 pt, which is 45% of the room left after two 16-pt paddings and the 24-pt gap); the text size is not an accessibility size. Resizing across 768 pt switches the arrangement without restarting a playing video or losing the neighbour you are on.
- *One column:* 16-pt padding; content at most 900 pt wide, centred; media and details full width, 18 pt apart.
- *Two columns:* at most 1,280 pt wide, centred; media on the left, 55% of (page − 32 − 24); 24-pt gap; details on the right, the rest (at 768 pt: 391 and 321); both start at the top; 18 pt between the details' sections. The two feeds (10.4) run below both columns at full width.

**The media box** (on top, or left) has 16-pt corners on a light-grey fill; a picture is shown whole and centred.

| Kind | In the box |
|---|---|
| Picture | Tap → Quick Look. A corner mark `arrow.up.left.and.arrow.down.right` says so: bottom-right in one column, top-right in two. Links with a preview picture too; videos and text no. |
| Video | The player (12) with its expand button. Plays by itself only with Settings › Videos › "Auto-play on a pin's page" (default off) and only while at least 30% of the box is on screen (a box much taller than the window: while at least half the window shows it); scrolling away pauses it (even a video you started), as does Quick Look or Settings over the page. Paused on a frame, a capsule "Use as thumbnail" (`photo.badge.checkmark`) at the top-right makes that frame the thumbnail (7.7). |
| Text | The whole text in a panel in the Settings › Appearance › Text pins style; empty: "No text yet — tap “Edit text” to write some." A small bordered "Edit text" button (`pencil`) under it opens the editor (8.7). |
| Link | With a picture: tap → Quick Look. Without: the *link hero*, a big `link` symbol over the host ("Link" if none), exactly 180 pt tall; "Open link" is in the link panel only (9.1). |
| Draft | The picture on grey (the feed's thumbnail stays while the full image downloads); tap → Quick Look over all results (11.5). |

**Height, one column:** the pin's own height at full width (a shape taller than 1 : 5 counts as 1 : 5), at least 180 pt (a link without a picture: exactly 180) and at most 560 pt; on a short screen (under 700 pt from page top to window bottom) or an iPhone in landscape at most 80% of the visible height, never under 120. It is measured as if the keyboard were down. A text pin takes its panel's natural height within the same bounds; longer text scrolls inside it. **Height, two columns †:** the media fills its column and is as tall as its shape asks for that width, with no screen cap (the page scrolls); never under 180 pt, never over 2.5 × the column width (a taller picture is shown whole, a little narrower, centred). Videos too: as tall as their shape asks, even taller than the window. Height changes animate, ease-in-out, 0.2 s.

### 10.2 Swiping between neighbours; the toolbar and its ⋯ menu

**Neighbours.** Swiping the media box sideways moves to the previous or next item of the list the page came from (no wrap-around). When the list has more than one item a hint capsule says "Swipe for next" (`arrow.left.arrow.right`), on the last item "Swipe back": bottom-left of the box (two columns: top-left of a picture or link; under the player for a video). A landing swipe replaces everything below the media; a half-typed tag is cleared; the tabs return to "More like this". If the pin on the page is deleted, hidden or unhidden, the page moves to the next item, else the previous, else goes back; a pin gone altogether shows `pin.slash` "This pin was deleted". A grid card playing with sound goes quiet while the page is up.

**Toolbar.** Title: the pin's title; none: "Photo", "Video", "Text" or "Link"; a draft: "From the web". At the right one ⋯ (`ellipsis` on iOS 26 and later, `ellipsis.circle` before). A draft shows "Save" (`plus`, small, prominent; a spinner while saving; dimmed while the image downloads or is analysed) before the ⋯.

**⋯ of a stored pin:** the shared pin menu (7.2) in its usual order, "Quick look" first, without "Select" and "Delete"; "Remove from board" has no "this board". Then the page's own items:
1. "Open source page" (`safari`), when the pin has a source address.
2. "Use this frame as thumbnail" (`photo.badge.checkmark`), for a video paused on a frame.
3. For a link pin: "Read link again" (`arrow.clockwise`; "Read links fully" and previews on, online), else "Refresh link preview" / "Fetch link preview".
4. "Settings…" (`gearshape`), not inside Settings.
5. "Delete" (`trash`, red) → "Delete this pin?" / "It stays in Recently Deleted for 30 days." with "Delete" and "Cancel"; afterwards the page moves on.

A running picture-changing or saving job dims Crop, Rotate, Flip, Thumbnail and "Save to Photos". **⋯ of a draft:** "Save to board…" (`folder.badge.plus`; dimmed until the image is ready; picker "Save to…"), "Save to Photos" (dimmed until downloaded), "Share…" (once downloaded; shares the picture), "Open source page", "Settings…"; no "Delete".

### 10.3 The sections in order: title, quote row †, note, link panel, the video note †, link details, original row, boards, your tags, AI tags, text in this image, details, source row (with Edit link pencil †), delete

A section that does not apply is absent. Sections are 18 pt apart.

**Title block.** The title (large, bold; grey "Add a title" when empty). Under it: "Written by AI" (`sparkles`) when the AI wrote the title or an AI rename can be undone; "Undo" (`arrow.uturn.backward`) and "was “‹earlier title›”" only when the AI replaced an earlier title; the pin's description when it has one (a link's is the page's own, up to 300 characters; a picture's is the cloud model's one sentence). Two round buttons at its right:
- "Suggest a title" (`sparkles`; stored pins): the AI writes a fresh title that differs from the current one, whoever wrote it, yours included, and "Undo" appears. Toast "No different title was found." or, for a link with no preview picture, "There's nothing for the AI to go on: this link has no preview picture."
- "Edit title" (`pencil`) → sheet "Title": one field (placeholder "Title"), "Cancel" / "Save"; once changed only those close it. A title you type is yours: the AI never replaces it by itself; saving it empty lets the AI write one again (2.2).

**Quote row †** (quote pins: text pins made by "Save as pin" on an article highlight, 9.3), above the note: `quote.opening` + "From the article “‹article title›”" ("From the article" without a title). When the article is still in the library on the same side of the hidden line, the row is a button with a `chevron.right` that opens the article's page (hint "Opens the article's page."); otherwise plain grey text that never names the article.

**Note.** The note, or grey "Add a note", and a round pencil → sheet "Note": a multi-line box with the caption "Anything you want to remember about this pin."; "Cancel" / "Save". A video's transcript † is written into the note, under your own text and a line "Transcript:" (20.10); words that arrive while the sheet is open are kept by "Save".

**Link panel and link details** (link pins; also under a picture or video a link became): 9.1 and 9.2–9.4. Between the two, on a stored link pin only (never a draft), may sit the video note.

**The video note †** (build 16; how to get a video PinBoard no longer downloads, 9.2). Shown once: on a link pin kept as an ordinary web page whose address is on TikTok, Instagram (a post or reel address), X (a post address), Pinterest, or Reddit (only when the post doesn't link on to another page), right under the link panel, until "Got it" is tapped; after that it never shows again on any pin. A box with 12-pt corners on the secondary colour at 10 %, 12 pt inside: `info.circle` and, in subheadline, "Most apps let you download a video inside the app itself. If you'd like the video in PinBoard, download it there, then save it to PinBoard (from Photos or with the share sheet)."; under it a bordered "Got it". "Seen" is remembered on this device for all profiles (not per profile, not synced). The same words are in Settings › Links (21.6).

**Original row** (a stored picture or video whose original is kept): "Original kept in ‹folder› · ‹size›" with "Show original" (22.3).

**Boards** (header `folder` "Boards"; draft: "Save to a board").
- Chips, wrapping: `folder.fill` (`lock.fill` for a hidden board) + the full path ("Travel › Beaches"); a tap opens the board. Only boards of the pin's own side show. None: "Not on a board yet" (draft: "Choose a board when saving, or save without one."). A draft that starts on its feed's boards says "Save puts it on this board — or choose another." / "Save puts it on these boards — or choose another."
- Under the chips, when the AI sorted it: `wand.and.stars` + "Auto-sort: cats, kittens" or "Start here: tagged “cats”".
- A small bordered "Choose" (no boards) or "Add" opens the board picker (14.5): "Add 1 pin to…" for a stored pin, "Save to…" for a draft (first row "No board (Unsorted)"; saves at once); in Hidden: "Hidden boards", "New hidden board".
- Notes: a hidden pin: `eye.slash` "Hidden pin — it shows only in Boards › ⋯ › Hidden."; before the AI has looked: "The AI is still looking at this pin…"; a small "Suggest other boards" when the pin is on a board and nothing was asked; nothing to suggest: "Create a board and the AI will start suggesting where pins belong." or "No board stands out for this pin yet."
- Suggestions: "AI suggestions — tap to add" (draft: "… tap to save there too" with boards shown, "… tap to save there" without) and up to three buttons `sparkles` + board + "NN%" with "because: a, b" (up to four tags or phrases). A tap adds the pin at once, silently, and remembers the board as last used; on a draft it saves the result onto its boards plus that one. Only boards of the pin's side that it is not on and that score at least 20% (20.7).

**Your tags** (`tag`). Capsules in the accent colour with a small `xmark`; a tap removes the tag. Field "Add a tag" (no auto-capitals) and a prominent "Add" (Return adds too); tags are saved lower-case without duplicates. While you type, up to 12 suggestion chips: your own tags containing the text first (`person`), then tags the AI or the file's keywords used (`sparkles`); tags the pin has are left out.

**AI tags** (`sparkles`; "Re-run", `arrow.clockwise`, at the right of stored pins, dimmed while analysing). While working: a spinner and "Analyzing on this device…" ("Analyzing on this device and in the cloud…"). Nothing found: "The AI couldn't find anything it recognizes here. Add your own tags above." All kept: "You have kept every tag the AI found." Otherwise capsules "dog 92%" with `plus`, then colour names ("blue", "black and white"), and "Tap an AI tag to keep it as one of your own tags." A tap moves it to Your tags.

**Text in this image** (not text pins; only when words were read; `text.viewfinder`): key-word chips (a tap keeps one as your tag) and the full text (up to 8 lines, selectable).

**Details** (only with something to say; `info.circle`): a duplicate — on a stored pin "Looks like a duplicate" and the pair card (10.6); on a draft `square.on.square` + "Looks like a duplicate of “‹title›” in your library" ("another pin" if untitled; opens that pin) and a small "Ignore" — only a look-alike on the same side counts; "Taken October 1, 2026 at 3:45 PM" (`calendar`); the camera model (`camera`); "Has location data (kept for export only, never sent)" (`location`); "Keywords in the file: a, b" (`tag`); the photo's caption.

**"Link" section †** (picture, video and text pins; a link pin's own address is in its link panel under the title, so none here). Heading "Link" (`link`, headline, like "Boards"). It does what the ⋯ menu's "Add link…" / "Edit link…" do (the same sheet, the same save, the same short messages, 7.3), so the page and the menu always agree.
- *No link* (stored pins only): grey "No link yet." and, at the right, a small bordered "Add link" (`link.badge.plus`) opening the address sheet "Add link".
- *A link:* the source row below, with the address itself under the link (caption2, grey, one line, shortened in the middle, selectable); at its right, on stored pins, the round pencil "Edit link" and a round `xmark` "Remove link", which opens a one-item menu "Remove link" (`trash`, red), so one slip never removes it; choosing it takes the address away at once (the pin stays) with the toast "Link removed.".
- *A web result not saved yet:* the section shows only when it came from a page, with no buttons.

**Source row** (pins from a web page): `safari` + a link in the credit's words ("Photo by Jane on Unsplash", the wording of Unsplash pins saved from build 16 † — older ones read "Photo by Jane · Unsplash"; a quote pin "Read on The Verge" or "Open the article") or "Open source page"; opens the default browser. At its right, on stored picture, video and text pins (not link pins, which have their pencil beside the link panel; not drafts), a round "Edit link" pencil † opens the address sheet (7.3).

**Delete.** A full-width bordered "Delete pin" (`trash`, red) at the very bottom (stored pins), asking "Delete this pin?" as the ⋯ menu does.

**VoiceOver.** The media box reads "Photo 3 of 12. Swipe left or right for the others." ("Video", "Text" or "Link" for the kind; the kind alone when there is no list). The round buttons say "Suggest a title", "Edit title", "Edit note" and "Edit link", the toolbar's ⋯ "More"; the title's "Undo" has the hint "Puts back the title from before the AI renamed this pin."; a tag says "Remove tag cats", an AI tag "Add tag dog 92%". Marks that only decorate (a link's big symbol, the quote mark and chevron) are hidden.

### 10.4 "More like this" and "From the web"

Below both columns, full width, after a thin divider.

**Tabs.** A two-segment control: "More like this" and "From the web" (the second only when Offline mode is off). The first shows a count once there are results: "More like this (12)", "More like this (40+)" when the list is full. A tap scrolls to the section (0.3 s) and the first tap on "From the web" also starts the search; scrolling by hand moves the highlight; when the tabs scroll off the top a floating copy sticks there.

**"More like this"** (`sparkles`). Pins of this page's side that look like this one or share its subject: 60% how alike the pictures look, 40% shared tags; best first; only scores of at least 12%; never Recently Deleted. A draft compares its downloaded picture with the library. Empty: "Similar pins appear here once the AI has looked at this pin." or "Nothing similar in your library yet." Otherwise the normal grid with the grids' column count (6.1); a tap opens that pin's page (videos too) with this list as neighbours; a long-press gives the shared pin menu without "Select" (7.1). 40 pins first, then a full-width "Show more" (`chevron.down`) adds 40 each time. Pins turned, renamed, hidden or deleted meanwhile update in place (a deleted or hidden one vanishes at once).

**"From the web"** (`globe`) contacts the web only after "Continue from the web" or a tap on its tab. Its texts, how the (at most two) search words are chosen, and the results grid and its messages are in 19.3 and 19.2. On this page: a result's round "+" saves it onto the same boards as this pin (a hidden pin's results go into Hidden); a tap opens its draft page (10.5); a result already saved on this side shows "Saved"; results stay when you return, only a new search reloads.

### 10.5 Web-result pages (drafts) and Save

A draft looks exactly like a pin's page but is not saved; it is downloaded and analysed on the device as a new pin would be.
- **Before the page:** a spinner and "Fetching this image…" under the title "From the web". On failure: `wifi.exclamationmark`, "Couldn't load", "This image couldn't be downloaded." and "Try again".
- **Banner** across the top (`globe`): "From the web — not saved yet" and, under it, "Downloading…", then "Looking at the image…", then "Edit the title or tags if you like, then tap Save."
- **The page has** the media box, title block (no "Suggest a title"), note, "Save to a board", Your tags, AI tags (no "Re-run"), Text in this image, Details, source row (no pencil) and both feeds; no "Delete", original row or link panel.
- **Its title** is the web page's own, cut to 60 characters, and counts as imported; the AI titles a result only when it arrives untitled; a title you type is never replaced.
- **Save:** the toolbar's "Save", or "Save to board…" / "Choose" (picker "Save to…", first row "No board (Unsorted)"), or a suggestion chip. Plain "Save" goes onto the boards the feed saves to (a pin's feed: the pin's boards; a board's feed: that board; Explore: none); a chosen board replaces them; a suggestion adds to them. On the Hidden side a result lands in Hidden or on the chosen hidden board; boards deleted, hidden or unhidden since the feed was shown are left out, so a save never crosses the hidden line. If the same web page was saved meanwhile, "Save" just puts that pin on the boards. Swiping to another result while a save runs does not mix them up: each result keeps its own state.
- **After saving** the page turns into the stored pin's page in place and a toast says where: "Saved to your library.", "Saved to Travel, Beaches.", and on the Hidden side, which never names a board, "Saved to a hidden board." or "Saved to Hidden."; failure: "Sorry — the image couldn't be saved." Saving an Unsplash result reports the download to Unsplash † (19.2). "Save to Photos" there (add-only access, 7.8 †) says "Saved to Photos." or "Photos didn't take the picture." (access refused: "PinBoard isn't allowed to add to Photos. You can allow it in the Settings app › Apps › PinBoard › Photos." †)

### 10.6 Duplicate pairs (card, Keep both, Delete, "Keep which?" merge sheet)

Shown under Details of a pin that "Looks like a duplicate" and in Settings › Library › "Possible duplicates" (23.4). Look-alikes are found as 8.4 and 20.8 say; only the newer of a pair is marked, and a pair never crosses the hidden line.

**The pair card:** "Newer" at the left, "Older" at the right, each headed "Newer · Oct 1, 2026" / "Older · Sep 2, 2026" (date added), with the pin's normal card (a tap opens its page), the names of its boards, and three small buttons: "Delete newer" (red), "Delete older" (red), "Keep both". Footnote: "Deleting one moves it to Recently Deleted; its boards and tags go to the other. “Keep both” hides the pair from future checks."
- **"Delete newer" / "Delete older"** asks "Delete the newer copy?" (or "older") — "Its boards and tags move to the copy you keep." — with "Delete and merge" (red) and "Cancel". While it is up the cards preview the result: the copy that goes turns grey, fades to 45% and carries a white `trash.fill`; the copy that stays grows 4% and gets a 3-pt accent frame (VoiceOver "Will be deleted" / "Will be kept"). Tapping outside the question counts as "Cancel" and the cards go back to normal.
- After "Delete and merge", if both copies have different titles, or different notes, the sheet **"Keep which?"** asks; otherwise the merge happens at once. The kept pin gets all boards and tags of both; the other goes to Recently Deleted; a kept copy with no title or note takes the other's (a title keeps its "Written by AI" mark if it had one); a video's transcript is not duplicated †.
- **"Keep which?"** (medium/large): "Which title?" and/or "Which note?", each listing both texts in full as radio rows (the kept copy's first and chosen), the footnote "Boards and tags from both copies are combined either way." and "Cancel" / "Merge".
- **"Keep both"** remembers the two are different, removes the mark and skips the pair in later checks (resettable: 23.4).

## 11. Quick Look

The full-screen viewer: one pin (or web result) fills the screen on black and you move through a feed of them by swiping up and down. It has no title bar or bottom bar: a round ✕ at the top-left, a round ⋯ at the top-right and, on a video page, the player's controls (12).

### 11.1 How it opens from each place and which pins it pages through (the 1,000-pin window)

**Ways in**
1. **Tap a video card** in a grid (in select mode a tap selects). A video card never opens the pin's page; "Show info" does (11.4).
2. **Long-press any card → "Quick look"** (`arrow.up.left.and.arrow.down.right`; in select mode a long-press offers only this item). Both open on the pins of that grid in the grid's order (all kinds mixed), the tapped pin in its place, and never look for "more like this".
3. **On a pin's page:** tap the picture (or a link's preview), the corner mark or the player's expand button, or ⋯ › "Quick look". It opens on that pin with no list: the pin, then pins like it of the same kind (below). The page stays underneath.
4. **Long-press a "More like this" card → "Quick look"** (a tap opens that pin's page): as 3.
5. **Web results** (Explore, a board's or a pin's "From the web"): long-press a result → "Quick look", or tap the picture on a draft's page. It pages through the results (11.5); a Hidden feed opens a Hidden-side Quick Look. After a result is saved, a tap on its picture opens the stored pin (no list).
6. **Inside Settings** (a duplicate pair's page): the same, except a video's "Show info" shows the panel (11.4).

While it is up the page beneath stops its previews, page videos pause and a grid card that had sound goes quiet.

**The feed.** Swipe up for the next, down for the previous: one item per swipe, no wrap-around.
- **The window:** a feed built from a grid holds at most 1,000 pins on each side of the opened pin (2,001 pages).
- **A feed with no list** starts with the pin and fills with pins like it of the same kind (pictures with pictures, videos with videos, text with text, links with links; "like" as in 10.4), 40 at a time: when the page in front is within 6 of the end, the next 40 are fetched (the request grows 40, 80, 120…; pins already shown are skipped); nothing new means the end.
- **Its own side only:** normal pins with normal pins, hidden with hidden. A pin deleted, hidden or unhidden while Quick Look is open leaves the feed; if it was in front, the page now in its place comes forward (the next pin, else the previous); with none left Quick Look closes. Changed pictures (turned, flipped, cropped) show at once.
- **States:** empty feed `photo` "Nothing to show". The page in front and one on each side load the full picture, the one two away a thumbnail; a waiting page shows a large white spinner; a picture that cannot load shows "Couldn't load this image" (a stored picture shows its thumbnail first, so this is rare; one kept in iCloud only: see 22.5 Optimize device storage, "Coming back").

### 11.2 Gestures: paging, closing, zoom, double-tap; the look (always dark)

**The look.** Always dark, whatever the appearance, and so are its menus, sheets, questions and text fields. ✕: a 44 × 44 circle of ultra-thin material with a white `xmark`, 16 pt from the left edge, 8 pt below the top safe area. ⋯: the same circle with `ellipsis` at the top-right; while the pin's original is being fetched (11.4) a small white spinner replaces it, and it is hidden while the info panel is open. Both fade while the feed is pulled right to close it, when the black also dims (to 25% opaque at 375 pt of pull). Toasts float 96 pt above the bottom edge here (12 pt elsewhere); "Looks familiar" questions (8.4) and result alerts appear over it, dark. Player controls stay inside the safe area and beside the info panel; the top 64 pt of a video page stay free.

| Kind | Page |
|---|---|
| Picture | Whole, centred on black, zoomable; a thumbnail stands in while it loads. |
| Video | The player (12) with the picture fitted on black. Only the video in front plays; the ones just before and after have their player ready, paused at the first frame † (the video Quick Look opened on keeps its place: 12.4); further ones show only their poster, never playing. |
| Text | Only the text, white on black, no scrolling (swiping always pages): the title, if any, bold at 1.3 × the text size, then the text at 1.1 ×, in the Settings › Appearance › Text pins font; a left-aligned column at most 720 pt wide, centred, 24-pt margins, below ✕ and ⋯. |
| Link, no picture | Centred: a big `link` symbol, the title, the address and, for a real web address, a prominent "Open link" (`safari`). |
| Link, picture | The picture like a picture, with a prominent "Open link" over its bottom (none for a non-web address such as "mailto:"). |
| Web result | The picture, zoomable: the feed's thumbnail first, then the full picture (fitted within 2,048 px); failing with no thumbnail: "Couldn't load this image". |

**Gestures.** Every Quick Look swipe needs the finger to move at least 24 pt.

| You do | What happens |
|---|---|
| Swipe up / down | Next / previous item. |
| Swipe left → right (panel closed) | The feed follows the finger; ✕ and ⋯ fade, the black dims. Let go after more than 120 pt, or with a flick that would carry it past 320 pt: Quick Look closes; otherwise it eases back in 0.2 s. |
| Swipe in from the right edge (a leftward drag starting within 32 pt of it) | The info panel (11.3) is pulled in; let go after more than 80 pt or a flick past 200 pt and it stays (0.25 s), else it slides back. On iPad this edge swipe belongs to Quick Look. Works for every item, videos included. A leftward drag that starts elsewhere does nothing. |
| Swipe left → right (panel open) | Pushes the panel out (80 pt / flick 200 pt); does not close Quick Look. |
| Tap | Closes an open panel; on a video also shows or hides the controls (12.2). Otherwise nothing. |
| Double-tap a picture | Zoom to about 2.5× around the tap; again returns to 1×. (On a video it skips: 12.2.) |
| Pinch a picture | 1× to 6×; one finger pans when zoomed, never off the picture's edges. |
| Touch and hold a picture, text or link | The ⋯ menu as a pop-up. |
| Touch and hold a video | Not a menu: after one second it plays at 2× (11.4). |
| Tap or drag on a scrub bar | A tap jumps there; a drag only scrubs (12.1): never pages, closes or opens the panel. |

The close and panel swipes are off while a picture is zoomed (the drag pans; zoom resets on every page change), for a drag starting on a scrub bar or following a hold on a video, and while a finger holds a video for 2×. A drag counts as vertical unless its horizontal travel is at least 1.3 × the vertical. With Reduce Motion the panel fades instead of sliding.

### 11.3 The info panel: everything in it

A full-height column from the right edge on regular material (the picture keeps showing, a video keeps playing): 85% of the width on screens under 600 pt, otherwise 36% clamped to 300–380 pt. A picture is not moved; a text page moves beside the panel only when at least 320 pt are left (so on an iPhone in portrait it covers the text); a video's controls move beside it. It opens by the edge swipe or ⋯ › "Show info", and closes with its `xmark.circle.fill` button, a swipe right, a tap on the picture or Esc (panel first, then Quick Look). It always shows the item in front. Header "Info"; below, a scrolling column of sections with small grey headings and small bordered buttons (side-by-side ones wrap onto two lines when narrow).

**A stored pin, top to bottom**
1. **Title:** the title, or grey "No title"; "Written by AI" (`sparkles`) when the AI wrote it; "Edit title" (`pencil`), or "Add a title" when empty → the "Title" sheet (10.3).
2. **Note:** the note, or grey "No note yet."; "Edit note", or "Add a note" when empty (`square.and.pencil`) → the "Note" sheet.
3. **Your tags:** grey "No tags yet.", or small capsules (not tappable); "Edit tags…" (`tag`).
4. **Boards:** grey "Not on a board yet.", or one line per board `folder` + full path (only this side's boards); "Add to board…" (`folder.badge.plus`) and "Move to board…" (`arrow.turn.up.right`; only when the pin is on a board †).
5. **Video** (videos): `timer` + the length ("3:33", "1:02:03") or "Length not known yet"; `speaker.wave.2` "With sound", `speaker.slash` "Without sound" or `speaker.wave.2` "Sound not checked yet".
6. **Link** (link pins): the address (up to three lines); "Open link" (`safari`; real web addresses only) and "Edit link…" (`pencil`).
7. **Storage** (only when the original is kept): `externaldrive` + "Original · 48 MB · iCloud Drive › PinBoard Originals" (size left out when unknown; "your originals folder" when the folder has no name).
8. **Added:** "Oct 1, 2026 at 9:41 AM".

A text pin has the same panel; its words are edited on its page. **A web result:** the title (or "No title") with its credit (an Unsplash result's † reads "Photo by ‹name› on Unsplash" with two links, the name to the photographer's Unsplash page and "Unsplash" to unsplash.com, both tagged "utm_source=PinBoard&utm_medium=referral", 19.2); the source (`safari` + the site's host, or "Open source page"); "Save to library" (`plus`, prominent) or dimmed "Saved" (`checkmark`) once on the side this feed saves to; "Save to board…" (`folder.badge.plus`) → "Save to…".

### 11.4 The ⋯ menu per kind; Show info; Show original; Speed ▸; hold for 2× and the lock

The ⋯ menu and the touch-and-hold pop-up of a picture, text or link page are the same list.
- **A stored picture, text or link:** "Show info" (`info.circle`); "Show original" (`arrow.up.left.and.arrow.down.right`; only when the original is kept; while it is fetched it reads "Fetching the original…", dimmed; 22.3); then the shared pin menu (7.2) without "Select" and "Quick look" — "Remove from board" lists each board of the pin, and the dimmed "Kept out by its board" note shows here, unlike on a card.
- **A stored video** (⋯ only): "Show info"; "Speed ▸" (`speedometer`); "Use this frame as thumbnail" (`photo`; only while paused and loaded; toasts "Thumbnail changed" / "Couldn't change the thumbnail", 7.7); "Show original"; then the shared menu, with "Thumbnail ▸" and "Search this picture on the web ▸" but no "Edit picture ▸".
- **A web result:** "Show info"; "Save to library" (`plus`) or dimmed "Saved"; "Save to board…" (`folder.badge.plus`; picker "Save to…"); "Share…" (`square.and.arrow.up`; shares the result's page address); "Search this picture on the web ▸" (`magnifyingglass`; searches by the picture's own address, so nothing is handed over; it opens where 7.4 says); "Open source page" (`safari`).

**"Show info"** opens the panel (0.25 s) for a picture, text, link or web result. For a **video** the info is its own page: Quick Look closes and, about 0.45 s later, the pin's page opens in the showing tab with the pins Quick Look has so far as swipe neighbours; if that page is already right under Quick Look it just closes; inside Settings it opens the panel instead.

**Speed ▸** (Quick Look only; a page's player always plays at 1×): the nine speeds of 12.3 † with a checkmark on the chosen one. It carries on from one video to the next while Quick Look stays open, keeps the pitch, and switches a 2× lock off.
- **Hold for 2×:** rest a finger on the playing video in front for 1 second without moving more than 10 pt: it plays at 2× while the finger stays down and returns to the chosen speed on lifting. A held touch never pages or closes. On a paused video the touch behaves normally.
- **The lock:** while holding, slide the finger down 40 pt (once per hold): 2× stays on after you let go (a light tap of feedback). Hold and slide down again to turn it off (the chosen speed returns at once, even with the finger still down).
- **The speed pill:** while the speed is not 1×, a capsule of ultra-thin material with the speed ("2×", "0.5×") sits at the top-centre, level with ✕ and ⋯, taking no touches.
- Everything returns to 1× when Quick Look closes.

### 11.5 Keyboard shortcuts; sound; web results in Quick Look; hidden pins

- **Keys:** ↑ previous · ↓ next (stops at the ends) · Esc closes the info panel, then Quick Look · Space plays or pauses the video in front · ← / → skip it back / forward by "Skip buttons jump" (12.1); Space and the arrows do nothing on a page that is not a video; no key for the 2× hold. All keys are off while anything covers Quick Look (a Title or Note sheet, the web-search browser, a pin-action sheet, a question, an alert).
- **Sound:** a grid card playing with sound goes quiet the moment Quick Look, a page or Settings comes up; the app's sound switch is unchanged, and a video opened here has sound if you turned it on anywhere (12.1).
- **Web results:** it pages through the results the screen had, from the chosen one; within 6 of the last it asks the feed for more (the feed underneath grows; shown results are skipped; nothing new means the end). Opened from the picture on a draft's page it pages only through the results already loaded and cannot load more. "Save to library" and "Save to board…" put the result where the feed saves (a board's feed: that board; a pin's feed: the pin's boards; Explore: Unsorted; a Hidden feed: Hidden) through the normal import: the same pill, "Looks familiar" question and toast, and, if the picture cannot be downloaded, the alert "This image couldn't be downloaded." The item then reads "Saved".
- **Hidden pins:** Quick Look on hidden pins or a Hidden feed, every sheet it opens, and the questions and toasts above it are covered whenever the app leaves the front (4.3).
- **VoiceOver:** ✕ says "Close", ⋯ says "More" (with the value "Fetching the original" while it fetches), the panel's button "Close info". Each page is one element: "Photo, Sunset, 3 of 20", "Video, ‹title›, 3 of 20", "Text, …", "Link, …", "Web image, …", with ", couldn't be loaded" added when a picture failed; the title part is left out when there is none, and a text page reads its text as its value. The player's own words are in 12.1.

## 12. The video player

Wherever a video is shown large, PinBoard plays it in its own player: always on black, with white controls, whatever the appearance. (In grids a video card is a small silent looping preview with a speaker button: 6.3.)

### 12.1 Where it appears (grid previews vs the player); the bar, centre play/skip, scrub bar, time, sound, expand

| Place | Differences |
|---|---|
| A pin's page (10.1) | Has the expand button. Starts by itself only with "Auto-play on a pin's page" (default off); pauses when scrolled away. Always 1×. Hears the volume going up † (12.3). |
| Quick Look (11) | No expand button. The video in front always plays by itself and pauses when you swipe away. Speeds, hold for 2×, keyboard (11.4, 11.5). Hears the volume going up †. |
| The "Original" viewer (12.5) | Plays at once at 1×. No expand, speeds or volume-up. |

**The picture** is shown whole, centred on black. Until the video has loaded the area is plain black (no poster underneath; the picture appears when ready); meanwhile the scrub bar takes no touches and the skip buttons are dimmed. A video that cannot be read shows a centred `exclamationmark.triangle` over "This video can't be played."; no bar, no centre buttons. The top 64 pt of a player never carry controls, so Quick Look's ✕ and ⋯ stay free.

**The bar** lies along the bottom on a shade rising from clear to 70% black and fades in and out in 0.25 s.
- *Wide player* (520 pt or more, not counting safe areas or the info panel): one row of 44-pt targets: Play/Pause (`play.fill` / `pause.fill`) · time played · the scrub bar (taking the rest) · time left · speaker (`speaker.slash.fill` muted / `speaker.wave.2.fill` on) · expand (page only; `arrow.up.left.and.arrow.down.right`).
- *Narrow player* (under 520 pt: iPhone upright, a narrow window, Quick Look with the panel open on a small screen): two rows: time played · scrub bar · time left above; Play/Pause at the left and speaker and expand at the right below.
- *Time text:* "0:07", "12:05", "1:02:03"; played time rounded down, time left rounded up with a minus ("-1:05"); never shortened.

**The scrub bar †:** a thin track, the played part in the accent colour, a white knob (12 pt, 20 pt while scrubbing). It works like Apple's own player (a mouse or trackpad on a Mac the same way): a finger landing does nothing yet. Lifting without having moved more than 8 pt is a tap: the video jumps exactly to the tapped spot, playing on or staying paused. Moving further makes it a scrub, which is relative: the video pauses where it is and the playhead moves from there by the distance the finger travels (the bar's full width = the whole video); it never jumps to where the finger landed, and lifting does not jump either. While scrubbing, the further the finger is above or below the bar the slower it goes: full speed up to 50 pt off the bar, half up to 100 pt, a quarter up to 150 pt, then fine (a tenth), with a small label just above the bar, "Half-speed scrubbing", "Quarter-speed scrubbing" or "Fine scrubbing" (caption semibold, white on a 60% black capsule; none at full speed). Changing speed never makes the playhead jump. No haptics. The video follows approximately while moving, settles exactly on release and plays on if it was playing. It takes no touches until the video is ready and the controls are showing (a touch there is then only a tap on the picture), and a drag on it never pages, closes or opens the panel.

**The centre buttons:** skip back · play/pause · skip forward at the exact middle, shown and hidden with the bar. Skip buttons jump by Settings › Videos › "Skip buttons jump" ("5 seconds", "10 seconds", "15 seconds", "20 seconds", "30 seconds"; default "10 seconds"): glyph `gobackward.10` / `goforward.10` (also 5, 15, 30; for 20 the plain `gobackward` / `goforward` with "20" over it). A skip never goes before 0:00 or closer than 0.1 s to the end and keeps playing or paused as it was. Large group (72-pt play circle on 45% black, 56-pt skip targets) or compact (48 / 44 pt): the largest that fits between the free top strip and the bar; if neither fits only the bar's play button remains (on a page's video box: large from about 208 pt tall, compact from about 184, 256 and 232 in a narrow player).

**Sound.** The app has one sound switch, **off at every launch** (not remembered); the one-sound rule and what you hear are in 6.3. The player's speaker flips it: once on, every video opened large has sound until it is turned off, and turning it on also starts a paused video. A big player turning sound on silences the grid card, and so does opening Quick Look, a page or Settings.

**Expand** (page only) opens the video in Quick Look; sound and place carry over.

**VoiceOver.** Bar: "Play" / "Pause", the scrub bar "Playback position" (value "0:07 of 3:33"; swiping up or down moves a tenth of the video, 1 to 10 seconds), "Turn sound on" / "Turn sound off", "Open in Quick Look" (page only). Centre: "Skip back 10 seconds" / "Skip forward 10 seconds" (the chosen number). The speed pill says "Playing at 2 times speed", "Playing at 0.5 times speed". The centre play button, the two time labels and the skip numbers are skipped; the bar never hides while VoiceOver runs.

### 12.2 Controls auto-hide; single tap vs double tap †; the skip label †

- **Hiding.** The bar and centre buttons show when a video appears and whenever it is paused, scrubbed, skipped by buttons or keys, or its sound is switched; while it plays they fade 3 seconds after the last touch. A single tap shows or hides them (paused, they stay unless tapped away). With VoiceOver they never hide.
- **What wins a touch:** the buttons and scrub bar; then a 1-second hold (Quick Look, 11.4); then a double-tap; then a single tap, which answers 0.3 s late because the player first waits for a possible second tap (in Quick Look it also closes the info panel).
- **Double-tap skips †** (page, Quick Look, Original viewer; a double-click on a Mac): two taps, the second within 0.3 s of the first, skip by the "Skip buttons jump" step in the direction of the zone the second tap lands in. The picture is split into a left and a right half (the exact middle counts as right), and each half into its upper two-thirds and its bottom third (so the middle of the screen is "upper"); beside the info panel the zones are of what is left, inside the player's insets:

  | Zone | Double-tap |
  |---|---|
  | Upper left (top two-thirds) | Skip back |
  | Bottom left (bottom third) | Skip forward |
  | Upper right (top two-thirds) | Skip forward |
  | Bottom right (bottom third) | Skip back |

  After a double-tap every further tap within 0.5 s of the previous one skips again, by its own zone; the run ends 0.5 s after the last tap. While the controls show, the bar along the bottom and its shade take their own touches, so a tap there is never part of a double-tap (the bottom zones then work above the shade, and fully while the controls are hidden — a double-tap does not bring them up). It does not bring the bar up (a bar already showing stays and gets its three seconds again), and does nothing while the video loads or fails. (A double-tap on a picture in Quick Look zooms.)
- **The skip label †:** a big "+10", "+20", "+30"… ("−10"… backward) in 44-pt white bold rounded type with a soft shadow in the middle of the tapped zone; it adds up while taps keep skipping the same way and restarts when a tap skips the other way; it fades over 0.3 s after the run ends and takes no touches.

### 12.3 Speeds (list) †; volume-up unmutes †

- **Speeds †** (Quick Look's ⋯ › "Speed ▸", 11.4): "0.25×", "0.5×", "0.75×", "1×", "1.25×", "1.5×", "2×", "3×", "5×"; default 1×.
- **Volume-up unmutes †** (page and Quick Look; not the Original viewer): while the video in front plays muted, turning the volume up (side buttons or Control Center) turns its sound on as if the speaker had been pressed (the switch is set, the icon changes, the bar shows a moment). A paused video stays paused; only a rise counts, for the video in front only. System limits: at top volume there is nothing to rise; a paused video may not hear it; a rise within one second of the audio output changing (AirPods, AirPlay) is ignored.

### 12.4 Playback position memory across the app; controls hidden until tapped †

- Every video remembers where it stopped, for every player (grid preview, page, Quick Look), until the app is closed; a fresh launch starts every video from the beginning. Within 0.5 s of the start or end nothing is remembered: a video left at the end starts from 0:00. While a grid preview plays, a big player opening the same video starts from its live time.
- **One big video plays at a time.** Starting one stops any other (saving its place); if it was the same video (Quick Look closing over the page) the new player carries on from exactly there, with no jump back and no double sound. A video you paused yourself, or left by leaving the app, keeps a waiting player of the same video paused.
- A video starts over when it ends; pressing play within 0.1 s of the end starts from 0:00.
- **It pauses by itself** when the app goes to the background (and does not resume by itself; a hidden video never restarts on its own), another screen covers it, the page scrolls it away or Quick Look or Settings comes over it, or another app's sound or a call takes over. One covered or scrolled away resumes when it may play; not after the app went to the background, you paused it, or a call or other sound stopped it. A file swapped for a smaller copy or given new artwork is reopened by any player showing it, which carries on from the same place.
- **No exceptions †:** a video you swipe to in Quick Look carries on from where it was left, like everywhere else (the earlier rule that a swiped-to video started from 0:00 is gone).
- **Controls start hidden †** on a pin's page and in Quick Look, so a video you scroll to plays undisturbed; one tap shows them. They come up by themselves only when you pause the video yourself, or for a video in front that won't play by itself (auto-play off on a pin's page), so its play button can be seen. A pause because the page scrolled away leaves them hidden for the way back.

### 12.5 Posters/thumbnails and the "black thumbnail" repair; originals ("Show original", the Original viewer)

- **The poster** is a video's one thumbnail: its card picture in every grid (the card keeps the video's shape), the picture of neighbours on a page and of Quick Look pages two or more away (with a white `play.circle.fill` on a page), its board-tile picture (with a small white play mark), the picture "Search this picture on the web ▸" sends and the one the AI looks at. It is not shown under the big player. Changing it: 7.7.
- **Picked at adding:** the frame 0.5 s in (halfway for a very short video), then at 50%, 40%, 60%, 30%, 70%, 20%, 80% of the length: the first not mostly black (more than 70% very dark counts as black), else the least dark.
- **The "black thumbnail" repair** runs by itself in the background (schedule: 20.9): a nearly black or unreadable thumbnail is replaced by a frame picked as above if that one is less dark, and the AI looks at the pin again. A fine one is left alone, and a video once checked is never checked again. The same pass learns a video's length and whether it has sound, then starts the transcripts † (20.10).
- **The "Original" viewer.** "Show original" (the original row on a page, or Quick Look's ⋯; fetching, Cancel and patience: 22.3) opens a sheet titled "Original" with "Done" at the right (Esc too): always dark, page-sized on iPad with iOS 18 or later, covered in the App Switcher for a hidden pin. A picture is shown whole on black and zooms as in Quick Look (1× to 6×, double-tap about 2.5×, pan), decoded at no more than 4,096 px on its long side; if it cannot be opened: "The original couldn't be opened." A video plays at once in the player, at 1×, with the bar, centre buttons and double-tap skipping †; an unreadable one says "This video can't be played."


## 13. The Boards tab

### 13.1 Layout; the segments; sorting menu; favourites; the "New board" tile

Top to bottom: the large title "Boards", a switch with "Boards" and "Smart" ("Smart (N)" while N ≥ 1 normal smart boards exist), the content, and, while boards are selected, the batch bar (13.3). Changing segment ends selecting. Toolbar, trailing: "+" (new board; Boards segment only) and ⋯; from iOS 26 they are a plain `plus` and `ellipsis` on round glass buttons, before that `plus.circle.fill` and `ellipsis.circle`.

The Boards segment lists every favourite board at any depth, lifted to the top level (its detail line ends "in Parent"), then every other top-level board, each group in the board sort. Hidden boards never appear or count. Other sub-boards are reached through their parents.

| Segment | ⋯ menu, in order |
|---|---|
| Boards | "Select boards" (`checkmark.circle`; "Done selecting" while selecting; dimmed with no board and nothing selected) · "Sort boards" (`line.3.horizontal.decrease.circle`) · "Reorder boards" (`arrow.up.arrow.down`; dimmed with fewer than 2 top-level boards) · divider · "Hidden…" (`lock`; always offered; ends selecting; 16.1) · "Settings…" (`gearshape`) |
| Smart | "Hidden…" · "Settings…" |

**"Sort boards"** is a one-choice list (check on the current one). It is one setting for every board list on both sides (Boards tab, Hidden › Boards, sub-board grids, pickers, the board menus of Search and the smart-board editor), kept on the device. Favourites stay on top in every choice and are ordered among themselves by it.

- "Custom order" (`hand.point.up.left`; default): the manual order from "Reorder boards". Boards start in creation order; a new or moved board, and the sub-boards of a merged board, go to the end of their siblings; ties by name.
- "Name (A–Z)" (`textformat`): ignoring case and accents; numbers in natural order ("Board 2" before "Board 10").
- "Recently edited" (`pencil`): newest edit first. Edits: rename, move, new cover or description, hide or unhide, a new sub-board, a pin put on, taken off, hidden, deleted or restored, a merge into it; a sub-board's edit counts for every parent. Not edits: AI tagging or naming, favouriting, "Keep out of All", reordering, opening the page, making colours.
- "Recently added to" (`tray.and.arrow.down`): the board that most recently had a pin put on it (or on a sub-board) first; never-added-to boards last; ties by name.

**Favourites.** "Add to favorites" / "Remove from favorites" (15.1) adds a yellow star badge to the tile and moves the board into or out of the favourites group at once, at any depth. No toast; not an edit.

**Empty state** (no board): icon `folder.badge.plus` (44 pt), "No boards yet" (title3, semibold), "Boards keep pins organized. You can nest boards inside boards to make categories, e.g. Travel › Beaches. Drag a pin onto a board to put it there." (subheadline, centred).

**Unsorted footer,** centred under the grid or empty state while any normal pin is on no board: "N unsorted pins — to put them on suggested boards, choose Pins › ⋯ › AI sorting › Sort Unsorted pins into boards." ("1 unsorted pin — …"; hidden pins are never counted; the last words are the item of 15.2).

**The "New board" tile.** The Boards segment has no dashed tile: "+" opens a medium/large sheet, inline title "New board", with one field (placeholder "Board name", keyboard up at once), "Cancel" and "Save" (dimmed until there is non-blank text; Return also saves). The name is trimmed; once text is typed a swipe down cannot close the sheet. The board is added at the end of the custom order, top level, empty, with no cover (a folder symbol). The dashed tile (1.35 : 1, radius 16, 2 pt dashes at 50 % secondary, a large `plus`, a headline-weight title) belongs to "New sub-board" (14.1), "New hidden board" (16.2) and "New smart board" / "New hidden smart board" (17.2). Every one-field sheet here ("Rename board", "New sub-board in “Name”") behaves like this one.

### 13.2 Board tiles: collage/cover, counts, badges, long-press menu

Tiles serve the Boards tab, Hidden › Boards and sub-board grids. Columns = width ÷ 230 pt, rounded down, minimum 2, maximum 4; 14 pt gutters and margins; tiles in a row align at their tops.

| Part | Design and rule |
|---|---|
| Cover area | 1.35 : 1, radius 16, secondary fill. Empty board: icon `folder` (34 pt). |
| Collage | One picture fills it; two or more: a big picture on the left (62 % of the width) and a right column (38 %) of up to 3 stacked; 2 pt gaps; at most 4 pictures. |
| Which pins | The cover first (a chosen cover while its pin is still on the board or a sub-board, else the newest pin added to the app), then the other pins with a picture (pictures; videos by poster; links with a stored preview), newest first; sub-board pins count. |
| In a cell | A text pin shows its own words (caption2, 4 lines, top-left); a link without picture shows `link`; a video a small white `play.fill`. |
| Badges | Ultra-thin-material circle, 8 pt from the corner: top-left a favourite's yellow `star.fill`; top-right, Hidden only, `lock.fill`. |
| Name | Headline, at most two lines. |
| Detail line | Caption, one line, joined with " • ": "N pins" ("1 pin"; the board and its sub-boards, each pin once; never hidden pins on the normal side) · "N sub-boards" ("1 sub-board"; direct; only when some) · the age · "in Name" (favourite sub-boards on the Boards page). Example: "134 pins • 15 sub-boards • 1mo". |
| Age | Time since a pin was last added to the board or a sub-board: "now" (under a minute), "5m", "3h", "3d" (1–6 days), "2w" (whole weeks, 7–29 days), "1mo" (whole 30-day months, 30–364 days), "1y". Left out if never. |
| While selecting | Top-right becomes the selection mark (13.3); a selected cover gets a 3 pt accent border; unselected tiles are at 75 % opacity. |

A tap opens the board's page (14). Pictures, videos, text, links or the app's own pin cards dropped on a tile go onto that board (14.2); while something droppable hovers, a dashed accent outline (3 pt, radius 16) surrounds the tile and clears when the drag leaves or after about 3.5 s without movement. Tiles are not drop targets while selecting.

**The long-press menu** leaves out any command that cannot be used now: "Select" (only where boards can be selected), divider, "Rename…", "Description…", "New sub-board…", "Change cover…", "Move into…", "Add to favorites" / "Remove from favorites", "Share board…", "Hide board" / "Unhide board", "Keep out of All" / "Show in All" (normal side), divider, "Delete…" (red). Titles and behaviour: 15.1. There is no "Merge…" and no "Select pins".

**Covers.** The cover is the picture at the front of the collage; automatic (default) is the newest pin. A normal board never keeps a hidden pin as cover (hiding it resets the cover). A cover change counts as an edit.

- "Change cover…" (only when the board or a sub-board has a pin with a picture) opens a full-height sheet, inline title "Board cover", "Cancel" top-left. A full-width bordered "Automatic (the newest pin)" (`sparkles`) resets and closes. Below, a masonry grid of the board's pins with a picture (sub-boards included); the current cover has the accent selection border; a tap sets it and closes. Empty: icon `photo`, "No pictures on this board yet".
- A pin's "Use as board cover" (`photo.on.rectangle`; one pin with a picture; boards of the pin's own side) offers every board the pin is on and all their parents: one candidate gives the button "Use as cover of “Travel › Beaches”" (full path), several a submenu "Use as board cover" with one path entry each. No toast.

A video's Thumbnail › "From a picture pin…" (7.7) uses the same kind of grid: full-height sheet "Choose a picture", this side's picture pins newest first; empty: `photo`, "No picture pins yet".

### 13.3 Selecting boards: Select, Select all, the batch bar and its commands; Merge boards sheet; Reorder sheet

**Starting and ending.** ⋯ › "Select boards", or a tile's long-press › "Select" (that tile starts chosen). It ends with "Done" in the bar, ⋯ › "Done selecting", switching to Smart, opening Hidden, or running any bar command. The same selecting works in Hidden › Boards and on a board's sub-board grid (14.1). While selecting, a tap toggles a tile (it does not open it); the top-right mark is an empty white ring `circle` or `checkmark.circle.fill` (white check on an accent disc); there is no long-press menu, drop or tab swipe.

**The bar** (regular material above the home indicator):

1. Header: "N selected" (semibold), "Select all" (reads "Deselect all" once every listed board is chosen; it chooses the segment's favourites and top-level boards; "Deselect all" empties the selection but stays in selecting) and "Done".
2. Five equal bordered buttons, icon over a one-word caption: Move, Hide / Unhide, Keep out / Show, Merge, Delete (red). Captions show only while all fit whole, else icons only. A button is dimmed when its command cannot be used on the selection (titles, icons, rules: 15.1). The hidden side has four (no "Keep out").
3. Hint (caption2): "Tap boards to select them." — or, while Merge is dimmed because a chosen board sits inside another chosen board, "A board can't be merged with a board inside it."

Moves from the bar stay on the same side. A chosen board that has vanished (for example through sync) is skipped silently.

**"Merge boards" sheet:** medium/large, inline title "Merge boards"; the line "Merging: Name1, Name2, Name3"; a focused field, placeholder "Name of the merged board", pre-filled with the first board's name; the caption "All their pins and sub-boards end up in one board; the others are removed."; "Cancel" and "Merge" (dimmed while blank; Return merges; swipe-down blocked once the name was edited). The first chosen board in custom order stays and takes the typed name; every pin of the others goes onto it without duplicates (nesting rule, 2.4); their sub-boards become its sub-boards at the end; the others are removed; it counts as edited and as "added to". A board that holds the first board, or sits inside it, is left out with a toast (15.1). Selecting ends only if something merged. Smart boards limited to a removed board go back to "Any board" (17.1).

**"Reorder" sheet** (⋯ › "Reorder boards"; on a board's page "Reorder sub-boards"): medium/large, inline title "Reorder", "Done" top-right, a list with drag handles always showing. Rows: `folder.fill` (`lock.fill` if hidden), the name, a small `star.fill` for a favourite, the pin count. It lists, in manual order, the top-level normal boards, the page's sub-boards, or Hidden's top-level boards; a board moves among its siblings only. Every move is kept at once and switches the board sort to "Custom order" for every list. Footer: "Favorites always stay on top." while the sort is "Custom order"; otherwise "Moving a board switches every board list to “Custom order”. Favorites always stay on top."

## 14. A board's page

A tile, a sub-board tile or a board chip on a pin's page opens it on top of the tab, with a back button. A hidden board's page is behind the Hidden gate (16.1).

### 14.1 Top to bottom: info line, description, sub-boards row, grid, "Include pins from sub-boards"

**Navigation bar.** Inline title: the board's name (a still-locked hidden board reads "Hidden"); tapping it shows or hides the big coloured title. Trailing: "+" (14.2; a small spinner replaces it while an import runs) and ⋯ (below). A board that no longer exists shows icon `folder` and "This board was deleted".

**The page, in order:**

1. The big coloured title, when on: a full-width near-black block (radius 24, hairline white 8 % border) with the name in black-weight serif, 76 pt, one line, shrinking to 20 % for long names. The letters are windows onto a gradient of the board's colours gliding sideways, one colour every 2.5 s (each solid for 70 % of its stretch, 30 % blends, seamless loop); still, spread across the word, with Reduce Motion or fewer than two colours. It fades in and out in 0.25 s. Colours: the saved palette while up to date, else worked out in the background (meanwhile the accent and a paler accent). The Colors sheet: 7.6.
2. Location line "In: Travel › Beaches" (not for a top-level board); a hidden board also shows `lock.fill` and "Hidden".
3. Info line (caption, up to 3 lines), joined with " · ": "N pins" (including sub-boards) · "N sub-boards" (direct; only when some) · "Created 3 Mar 2025" (device's abbreviated date) · "Edited 2d ago" / "Edited just now" (the board or a sub-board) · "Last added 5h ago" / "Last added just now" (as the tile's age; left out if never) · "Opened 12×" (visits on this device; left out at 0; a hidden board counts once unlocked) · its files' size on disk including sub-boards, such as "48 MB" (left out at 0). Ages read 5m, 3h, 3d, 2w, 1mo, 1y followed by " ago".
4. Description: with none, a button "Add a description" (`text.alignleft`, subheadline); otherwise the text (subheadline) and a pencil button. Both open "Description…" (15.1).
5. Sub-boards: with none, a button "Add a sub-board" (`folder.badge.plus`, subheadline) opening "New sub-board in “Name”". With some: the heading "Sub-boards" (headline); a grid of sub-board tiles (13.2: same menu including "Select", same drops, board sort, favourites first) ending with a dashed "New sub-board" tile (hidden while selecting sub-boards); a switch row "Include pins from sub-boards"; a divider; the heading "Pins (including sub-boards)" (switch on) or "Pins" (off). A board without sub-boards shows none of these headings.
6. The pins: a staggered grid with the cards, columns (Settings "Images per row", 21.3), taps, menus, selection and drag-out of the Pins tab (6).
7. At the very end, "Keep exploring" (14.4).

**"Include pins from sub-boards."** On: the page lists the pins of the board and all its sub-boards together, each once; off: only pins directly on the board. Each visit starts from Settings › Pins & boards › "Board pages include sub-board pins" (default on; 21.4); flipping it applies to this visit only and gives the pins a new mixed order. Counts on tiles and in the info line always include sub-boards. "AI sorting" and "Select all" follow what the page lists; "Generate colors" always uses the board and all its sub-boards.

**The pins.** Shuffled by default: each visit starts a fresh shuffle that stays while pins are opened and closed; pulling down reshuffles (a date order is untouched); changed in ⋯ › "Order of pins". Empty board: icon `pin`, "No pins on this board", "Add with +, drag pins or pictures here, open a pin and choose this board, or scroll down for ideas from the web." (the last words drop with the web block off). The pin menus carry the board commands of 7.2; a board's page adds "Remove from this board" (`folder.badge.minus`; when a chosen pin is directly on it; toast "Removed 1 pin from Name." / "Removed 3 pins from Name.") and, for one pin, a submenu listing the pin's other boards by full path ("Remove from board"; "Remove from another board" when "Remove from this board" is offered too).

**Selecting sub-boards:** ⋯ › "Select sub-boards", or a sub-board tile's long-press › "Select". Same bar and hint as 13.3 ("Select all" chooses this page's sub-boards); the dashed tile hides; selecting pins ends it and the other way round; a hidden board's bar has no "Keep out".

**The ⋯ menu** dims a command that cannot be used now. In order:

1. "Select pins" (`checkmark.circle`; "Done selecting" while selecting): the pin selection bar (6.5). "Select sub-boards" (same icon; only with sub-boards).
2. Divider; "Rename…" (`pencil`), "Description…" (`text.alignleft`), "New sub-board…" (`folder.badge.plus`), "Change cover…" (`photo.on.rectangle`; dimmed with no picture), "Move into…" (`arrow.turn.down.right`), "Add to favorites" (`star`) / "Remove from favorites" (`star.slash`), "Share board…" (`square.and.arrow.up`), "Hide board" (`lock`) / "Unhide board" (`lock.open`; dimmed "Unhide board (hidden with its parent)"), "Keep out of All" (`rectangle.stack.badge.minus`) / "Show in All" (`rectangle.stack.badge.plus`; dimmed "Show in All (kept out with its parent)"; absent on a hidden board).
3. Divider; "Reorder sub-boards" (`arrow.up.arrow.down`; dimmed with fewer than 2), "Sort boards" (13.1), "Order of pins" (`shuffle`; a one-choice submenu: "Shuffled" `shuffle`, "Newest first" `arrow.down`, "Oldest first" `arrow.up`, and while shuffled "Shuffle again" `arrow.clockwise`; one setting for every board page, default Shuffled; the Pins tab and Hidden keep their own).
4. Divider; "AI sorting" (`wand.and.stars`; 15.2; the pins the page lists; dimmed when none), "Generate colors" (`paintpalette`; 7.6).
5. Divider; "Settings…" (`gearshape`; not shown when the page was opened from inside Settings).
6. Divider; "Delete…" (`trash`, red).

After "Delete…" or "Hide board" the page closes without a lock or Face ID prompt; "Unhide board" keeps it open.

### 14.2 The "+" menu and drops onto a board

Everything added here lands on this board (on the hidden side for a hidden board). The menu (each item: 8.1): "Photos…" (`photo.on.rectangle`; up to 100), "Camera" (`camera`), "Files… (pictures, videos, text)" (`folder`), "Clipboard (picture, text or link)" (`doc.on.clipboard`), divider, "Text pin" (`text.alignleft`; sheet "New text pin"), "Link pin" (`link`).

**Drops.** While something droppable hovers, a dashed accent outline surrounds the page (3 pt, radius 20, inset 8 pt). Pictures, videos, text and links dropped anywhere become new pins on this board (look-alike questions first, 8.4; reported as in 8.5, a hidden board being "a hidden board"); the app's own pin cards are put on the board without copying. Dropped on a sub-board tile they go to that tile.

The nesting rule (2.4) decides each pin card: already on this board, nothing changes; on a sub-board of it, nothing is added and it stays there; on a board this one sits in, it moves down; otherwise it is put on, in addition to its other boards. The toast:

- "Put 3 pins on Name." ("Put 1 pin on Name."; N counts pins now on the board because of the drop; several boards: "Put 3 pins on Travel, Beaches."; a hidden target: "a hidden board"), then where they apply " It moved down from a board this one is in." (one) / " 2 moved down from boards this one is in." and " 1 was already on a sub-board, so it stays there." / " 2 were already on sub-boards, so they stay there."
- Nothing changed (info icon): "It's already on Name." / "They're already on Name." / "It's already on a sub-board of Name, so it stays there." / "They're already on Name or its sub-boards."
- "Those pins are no longer in your library." (info). "Add to board…" in a pin menu says "Added 3 pins to Name." with the same endings (7.2). Dropping a card on the Pins tab: 5.5; on Hidden: 16.2.

When a dropped item raises a look-alike question, its second answer reads "Add the existing pin to this board" ("…to these boards"; 8.4). A quote saved from an article's passage (9.3) is a text pin placed on the same boards as the article, which count it as newly added and edited; a hidden article's quote is hidden, and a pin kept out of All keeps its quote out. †

### 14.3 Sharing a board (sheet, what it makes)

"Share board…" opens a medium/large sheet, inline title "Share board", "Cancel" top-left, a form: a row with `folder.fill`, the board's name and "N pins" (following the switch); a switch "Include sub-boards (N)" (only with sub-boards; all nested sub-boards of its side; default on; locked while exporting); the footer "One zip with the pictures, videos, notes and tags. Unzip it in Files, then in PinBoard choose Settings › Library › Import a folder… to bring the board back exactly." (a hidden board adds " The copy is not hidden: whoever opens it sees everything in it."); importing the folder gives every pin back everything attached to it when exported (23.3) †; a "Share" button (`square.and.arrow.up`), replaced while exporting by "Preparing export… 120 of 1,040" (device number format), then "Making the zip…", with a progress bar; errors "This board no longer exists." / "The board couldn't be exported: ‹reason›". When the zip is ready the system share sheet opens at once and this sheet closes. Smart boards are never included.

### 14.4 "Keep exploring": the web ideas footer and auto-load

The block ends a board's page, below the pins, only when Settings › Explore & web search › "Offer web ideas at the end of boards" is on (default on) and Offline mode is off (21.8). The web is contacted only after the user scrolls to it and, by default, taps. A divider, then a header row: "Keep exploring" (`globe`, headline) and at the right "Different ideas" (`arrow.clockwise`, subheadline), shown once a search exists and dimmed while words are being chosen, which picks another search without repeating the last.

1. **Before asking:** "Find images related to this board on Wikimedia Commons. Anything you save lands on this board." (the chosen image source, 19.1) and a prominent "Show ideas from the web" (`globe`). With Settings › "Automatically load web suggestions" on (default off) it starts without the tap, never for a hidden board, which always waits.
2. **Choosing:** a spinner with "Apple Intelligence is composing a search…" or "Choosing a search…". Words: 19.3.
3. **Searching:** `sparkles` (written by Apple Intelligence) or `tag` (built from tags), "Searching for “query”" and a small "Change" opening the sheet "Search the web for" (field "Search words", pre-filled; "Cancel" / "Save"; empty text does nothing; own words switch the icon to `tag`).
4. **Results:** the web-result grid of 19.2. Saved results land on this board: the card's "+" and "Save to library" say "Added 1 pin to Name." ("Added 1 pin to a hidden board."; a look-alike already in the library: "1 was already in your library (now on Name too)."); a draft page's Save says "Saved to Name." ("Saved to Name, Name."; "Saved to a hidden board."; 10.5). Results stay when you come back; a new search reloads.

### 14.5 The board picker sheet (Last used, Suggested, search, new board) and the batch tag editor

**The board picker** is used wherever a board is chosen. Titles: "Add 3 pins to…" and "Move 3 pins to…" ("Add 1 pin to…"), "Save to…" (web results, Quick Look), "Move “Name” into…" / "Move N boards into…" (15.1). Medium/large, inline title, "Cancel" top-left; it lists one side's boards only; the list is a tree.
- **Background †:** solid at every height, the system's grouped background (light grey in light mode, dark grey in dark mode), the same whether the sheet is still, dragged up or scrolled. (On iOS 26 a half-height sheet is otherwise see-through Liquid Glass that only turns solid once you drag or scroll it; that was hard to read.)
- **Search †:** a field pinned under the title that stays put while the list scrolls: `magnifyingglass`, placeholder "Search boards", no automatic capitals or corrections, Return closes the keyboard; once something is typed an `xmark.circle.fill` button ("Clear search") empties it.

Top to bottom:

1. **Top rows,** only those that apply:
   - the "none" row (`tray`): "No board (Unsorted)" in "Move" and "Save to…" pickers; "Top level (no parent)" / "Top of Hidden (no parent)" when moving boards; none in "Add … to…".
   - **Suggested,** only in "Add N pins to…" and "Move N pins to…": `sparkles` in accent, the board's full path, the caption "Suggested · board name matches its tags" / "… looks like pins already here" / "… shares tags with pins already here" (plus " · Last used" when it is also the last used board), the pin count, the row tinted accent at 14 %. It appears a moment after the sheet opens, and only when the average fit over up to 12 of the pins (spread evenly over the newest-first list) is at least 0.25, ignoring boards every pin is already on (scoring: 20.7). Nothing happens until it is tapped.
   - **Last used:** `clock.arrow.circlepath` in accent, the path, the caption "Last used", the pin count; only if that board still exists on this side and is not excluded; merged into Suggested when it is the same board.
   - While searching †, only the "none" row stays here; Suggested and Last used are left out.
2. **"Boards"** ("Hidden boards" in Hidden): every board of the side as an indented tree in Boards-page order (favourites first, then the sort, at every level). A row: a chevron (`chevron.right` / `chevron.down`) for boards with sub-boards, `folder.fill` in accent (top level), grey `folder` (sub-board) or `lock.fill` (hidden), the name, a small "last used" tag, "N sub", the pin count; the last used row is tinted accent at 14 %. Sub-boards start collapsed except the way to the last used board. A `plus.circle` button (`minus.circle` while open) opens a row beneath with a field (placeholder "New sub-board in “Name”") and "Create" (dimmed while blank), which makes the sub-board and chooses it at once. Boards being moved and everything inside them are dimmed and cannot be chosen. Empty: "No boards yet — create one below." / "No hidden boards yet — create one below."
   **While searching †** this section is "Matching boards" ("Matching hidden boards" in Hidden): every board of the side whose name contains the typed words, ignoring capitals and accents ("cafe" finds "Café", "ZURICH" finds "Zürich"), sub-boards included even when their parent is collapsed, in the same order, as a flat list. A row: the icon as above, the name, and for a sub-board the caption "in Travel › Europe" (its parents, outermost first), then the pin count; a tap chooses it. A hidden picker searches only the hidden boards it lists, and its captions never name a normal board. Boards being moved stay dimmed. Nothing found: "No boards match".
3. **"New board"** ("New hidden board" in Hidden): field "Board name" and "Create" (dimmed while blank; Return also creates), which makes a top-level board on this side and chooses it at once. It stays below the results while searching.
   **Filled from the search †:** while the person hasn't typed in "Board name" themselves, it copies the search words as they are typed (spaces at the ends trimmed), so a board can be made from a search with just "Create". Once they type in it, the search never changes it again, and typing in it never changes the search. Emptying it hands it back to the search from the next change of the search words. When the search words are exactly the name of a board of this side (capitals and accents aside: "zurich" is "Zürich"), the name stays empty and a grey line under it says "“Zürich” already exists — tap it above to choose it." (a name typed by hand is still allowed, as before). Creating a board, or closing the picker, starts it all afresh.

Choosing any board makes it the **last used board**: one memory for every picker, Quick Look and the pin page, kept on the device, forgotten for a side where it no longer exists; the next picker opens with its path expanded.

**The batch tag editor** ("Edit tags…" on several pins): a medium/large sheet, inline title "Tags", "Done" top-right; changes apply at once.

- Section "Add a tag to 3 pins" ("Add a tag to 1 pin"): a field (placeholder "New tag", no automatic capitals, keyboard up at once) and "Add" (dimmed while blank; Return also adds), adding the tag to every selected pin and clearing the field. While typing, matching existing tags of the same side appear as bordered chips, the user's own first (`person`, accent-tinted), then the AI's (`sparkles`, grey), leaving out tags every selected pin already has; a tap adds it to all.
- Section "Tags on the selected pins": "No tags yet.", or a row per tag: `tag`, the tag, "2/3" (selected pins carrying it) and an `xmark.circle.fill` button removing it from every selected pin. Most-shared first, then alphabetical; only the pins' own tags.

## 15. Board commands and AI sorting

### 15.1 The command table: command · icon · where (tile long-press / ⋯ / batch bar) · asks first? · what it does · toast

Every board command has one title, one icon and one set of rules. It is offered on the tile's long-press menu (a command that cannot be used now is left out), on the board page's ⋯ menu (dimmed; 14.1) and on the batch bar (13.3; only commands that work on several boards; unavailable ones dimmed). "…" in a title means a sheet or a question comes first; other commands act at once. A command touches only the side it runs on.

| Command | Icon | Where | What it asks and does | Toast |
|---|---|---|---|---|
| "Select" | `checkmark.circle` | Tile only, where boards can be selected | Starts selecting with this board chosen (13.3). | none |
| "Rename…" | `pencil` | Tile, page; one board | Sheet "Rename board": field "Board name" (pre-filled), "Cancel" / "Save" (dimmed while blank); the name is trimmed. | none |
| "Description…" | `text.alignleft` | Tile, page; one board | Sheet "Description": a multi-line box (120–200 pt tall, 12 pt corners, secondary fill), pre-filled, with the hint "What is this board about?" under it; "Cancel" / "Save"; empty text removes the description. | none |
| "New sub-board…" | `folder.badge.plus` | Tile, page; one board | Sheet "New sub-board in “Name”": field "Sub-board name", "Cancel" / "Save" (dimmed while blank). Adds an empty board at the end of this board's sub-boards (hidden when the parent is). | none |
| "Change cover…" | `photo.on.rectangle` | Tile, page; one board with a picture on it or a sub-board | The "Board cover" sheet (13.2). | none |
| "Move into…" | `arrow.turn.down.right` | Tile, page, bar ("Move"); one or more boards | Picker "Move “Name” into…" / "Move 3 boards into…" (14.5): first row "Top level (no parent)" ("Top of Hidden (no parent)"), then the side's boards except the moved ones and everything inside them. Each moved board goes to the end of the new parent's order, on its own side. A pin now on a board and on an inner board keeps only the inner one (2.4). Selecting ends. | none |
| "Add to favorites" / "Remove from favorites" | `star` / `star.slash` | Tile, page; one board | At once (13.1). | none |
| "Share board…" | `square.and.arrow.up` | Tile, page; one board | Sheet "Share board" (14.3). | none |
| "Hide board" / "Hide boards" · "Unhide board" / "Unhide boards" · dimmed "Unhide board (hidden with its parent)" ("Unhide boards (hidden with their parents)") | `lock` / `lock.open` | Tile (not for a board hidden with its parent), page, bar ("Hide" / "Unhide"). Hide needs a chosen board that is not hidden; Unhide a board hidden by itself | No question. The boards and everything inside them go to Hidden (2.6, 16.3) or come back; a board hidden only through its parent returns with that parent. Hiding from a board's own page closes it. A normal smart board limited to the board goes back to "Any board" (17.1). | "Hid the board. It's in Boards › ⋯ › Hidden." / "Hid 3 boards. They're in Boards › ⋯ › Hidden."; "Unhid the board." / "Unhid 3 boards." (check) |
| "Keep out of All" / "Show in All" · dimmed "Show in All (kept out with its parent)" ("… with their parents") | `rectangle.stack.badge.minus` / `rectangle.stack.badge.plus` | Tile, page, bar ("Keep out" / "Show"); normal side only (never offered for a hidden board, not on Hidden's bar). Show needs a board whose own setting keeps pins out | No question; covers the pins of the board and its sub-boards (2.7). | "Pins on this board stay out of All now. They're in Pins › Kept out." / "Pins on 3 boards stay out of All now. They're in Pins › Kept out."; "Pins on this board show in All again." / "Pins on 3 boards show in All again." plus " A board they are in still keeps them out." when so (check) |
| "Merge…" | `arrow.triangle.merge` | Bar only ("Merge"); two or more boards, none inside another chosen one | Sheet "Merge boards" (13.3). | only for boards left out (below) |
| "Delete…" | `trash`, red | Tile, page, bar ("Delete"); last, after a divider | The question below. | none |

**Merge left boards out** (a board that holds the one that stays, or sits inside it; info toast). Normal side, one board: "“Japan” is inside “Travel”, so it wasn't merged." (the left-out board is inside the one that stays) or "“Travel” is inside “Japan”, so “Japan” wasn't merged."; several: "3 boards are inside “Travel” or hold it, so they weren't merged." Hidden side, no names: "One board is inside another, so it wasn't merged." / "3 boards are inside another or hold one, so they weren't merged."

**"Delete…"** asks a confirmation dialog (buttons at the bottom on iPhone, a popover on iPad):

- Title: "Delete “Name”?" or "Delete 3 boards?"; hidden side, never named: "Delete this board?".
- Message, normal: "Sub-boards inside it are deleted as well. Pins that are also on other boards stay there." ("… inside them …"). Hidden: "Sub-boards inside it are deleted as well. Its pins stay hidden: kept ones go to Unsorted in Hidden, deleted ones to Recently Deleted in Hidden's ⋯ menu." ("… inside them … Their pins stay hidden: …").
- Buttons: "Delete board, keep its pins" ("Delete boards, keep their pins"): the boards and their sub-boards go; pins stay on other boards or in Unsorted (Unsorted in Hidden on the hidden side). "Delete board and move its pins to Recently Deleted" ("Delete boards and move their pins to Recently Deleted"; red): pins on no other board go to Recently Deleted and can be restored. "Cancel".
- A hidden board inside a deleted normal board moves to Hidden's top level with its contents. Smart boards limited to a deleted board go back to the whole library (17.1). Deleting from a board's page closes it; from the bar, selecting ends.

### 15.2 "AI sorting ▸": every item and its dialog wording (Sort into boards, Name with AI, Tag…, Undo last AI naming…)

The submenu "AI sorting" (icon `wand.and.stars`) acts on a set of pins and stays on its own side:

| Place | Works on |
|---|---|
| Pins tab › ⋯ | Every normal pin; the submenu is dimmed with no pins. |
| Selection bar's "AI sorting" button (Pins tab, board pages) | The selected pins; its "Sort into boards" shows progress. |
| A pin's long-press menu | That pin, or the selection. |
| Board page › ⋯ | The pins the page lists; dimmed when none. |
| Hidden › ⋯ | Every hidden pin; dimmed when none. |
| Settings › AI, last section "AI sorting" (21.7) | Every normal pin. Footer: "Sorts every pin into boards, gives them tags and names them. Hidden pins have their own in Hidden's ⋯ menu." During a naming run a line shows under it: a spinner, "Renaming… X of Y", a borderless "Stop". |

| Item | Icon | Notes |
|---|---|---|
| "Sort Unsorted pins into boards" (whole library; Unsorted pins only) · "Sort into boards" (several pins) · "Put on a suggested board" (one pin) | `tray.and.arrow.down` | Dimmed while another sort runs. |
| "Re-run AI tags" | `tag` | Looks at the pins again: tags, colours, text found in pictures, AI-written names. Pill: "AI is tagging pins… N of M". |
| "Name with AI (keeps your names)" | `character.cursor.ibeam` | Dimmed during a naming run. |
| "Rename all with AI…" (one pin: "Rename with AI") | `text.cursor` | Dimmed during a naming run. |
| "Undo last AI naming (N)" | `arrow.uturn.backward` | Only when no run is going on and this side's last run changed names that can be put back; N = names changed (a first name given to an untitled pin is not counted). |
| During a run: the plain line "Renaming… X of Y" and "Stop renaming" | `stop.circle` | Stopping keeps every name given so far. |

A video whose speech has been written down is treated like a link with text: what is said comes first, the poster second. The first part of the speech (small words and "um"s left out) supplies the video's lead tags and its AI name, and is what "Sort … into boards" sees. The speech stays on the device: the cloud model sees only the poster; a video named from its speech keeps that name. †

**"Sort … into boards."** Puts each chosen pin on its best board in addition to those it is on, only when the fit is at least 0.4 (scoring and the "why" line: 20.7); a hidden pin gets only hidden boards; the nesting rule (2.4) applies. One sort runs at a time; the Pins tab's pill reads "Sorting X of Y…" (normal side only). Result:

- Whole-library version with no Unsorted pins: alert "There are no Unsorted pins to sort." / "OK".
- Something moved: check toast "Put 1 pin on a suggested board." (one of one), "Put 5 pins on suggested boards." or "Put 3 of 5 pins on suggested boards."
- Nothing moved: alert / "OK": "No confident matches. Try adding more pins to your boards, or move a few by hand to teach it." (boards exist) or "Create a board or two first, then the AI can suggest where pins belong." (none).

**"Name with AI" and "Rename all with AI…".** "Name with AI" never changes a name the user typed; "Rename all with AI…" replaces every name.

- Several pins ask first. Title "Rename 12 pins with AI?" ("Rename 1 pin with AI?"), or "No names to change" when nothing is eligible. Message, names kept: "Only names the AI wrote (and pins without a name) change, never one you wrote. You can undo the whole run in this menu."; rename all: "Every one of them gets a new name from the AI — names you wrote too. You can put them all back with “Undo last AI naming” in this menu." Both add " When the AI finds nothing better, a pin keeps its name." and, with the cloud model on and pictures to be read, " The cloud model looks at each picture again (4 requests)." ("1 request"). Nothing eligible, names kept: "Every name here was written by you (or belongs to a link without a preview picture), so there is nothing the AI may rename. “Rename all with AI” replaces your names too."; rename all: "These pins are links without a preview picture, so the AI has nothing to name them from." Buttons: "Rename 12 pins" ("Rename 1 pin"; only when N > 0), "Cancel".
- One pin is renamed at once. With nothing to go on, an alert: "You wrote this pin's name, so the AI leaves it. Choose “Rename with AI” to replace it." (names kept, user-written name) or "There's nothing for the AI to go on: this link has no preview picture."
- Progress (normal side only): the pill "AI is renaming pins… X of Y" with a bar, and the menu's "Renaming… X of Y" with "Stop renaming".
- End: all renamed gives a check toast "Renamed 12 pins." ("Renamed 1 pin."). Otherwise an alert / "OK": "Renamed 12 pins. 1 kept its name — nothing better was found." / "Renamed 12 pins. 3 kept their names — nothing better was found." / "1 pin kept its name — nothing better was found." / "3 pins kept their names — nothing better was found." / "No names were changed."; one pin: "This pin kept its name — nothing better was found." While another dialog is showing the text comes as an info toast. A run on hidden pins is told only in an alert on the hidden screen. A first name given to an untitled pin counts as renamed.

**"Undo last AI naming (N)."** Dialog "Undo the last AI naming?", message "Puts back the 12 names the AI changed on Oct 1, 2026 at 3:14 PM. Names changed since then stay as they are." ("1 name"; abbreviated device date and time), buttons "Put back the names" / "Cancel". Then an alert / "OK": "Put back 12 names." ("Put back 1 name.") or "No names were put back: they had all been changed since." The last run stays undoable until another run replaces it; a single-pin run does not (its Undo is on the pin's page, 20.2).

## 16. The Hidden section

### 16.1 The gate (Face ID / Touch ID / passcode), the locked view, when it relocks

Hidden is a separate side of the library for pins and boards kept out of sight (rules: 2.6). It opens from the Boards tab's ⋯ › "Hidden…" in either segment, on top of the tab like a board's page; its back button leaves it.

- **The gate.** With Settings › Privacy & Hidden › "Ask for Face ID, Touch ID or passcode" on (default on; 21.9), Hidden and every hidden board's page show a locked view until unlocked: icon `lock.fill` (40 pt, secondary), the title "Hidden pins and boards are locked" (title3, semibold), the footnote "Unlock with Face ID, Touch ID or your passcode. You can turn this off in Settings › Safety › Hidden pins and boards.", and a prominent "Unlock" button. The system prompt appears by itself as the page appears, reason "Show your hidden pins and boards"; "Unlock" asks again. A device with no passcode goes straight through. While locked there is no toolbar and no content on any Hidden page (boards, smart boards, Duplicates, Recently Deleted, Tags), and a hidden board's page is titled "Hidden" instead of its name.
- **Switch off:** Hidden opens without asking; a hidden board's page shows its name at once.
- **Relocking.** Once unlocked, Hidden stays unlocked while the app is in use until the app goes to the background (or is swiped away in the App Switcher), "Lock now" is chosen (it locks and closes Hidden), or the profile is switched (23.1).
- **To the background.** The Boards tab returns to the screen Hidden was opened from (even if another tab was showing), Hidden locks, a pending import question into Hidden is dropped and a toast on screen is cleared. While Hidden is open and the app is not in front, an opaque privacy cover hides the screen (4.3).

### 16.2 Inside: segments, what is listed, hidden boards, the ⋯ menu, convert videos row/question

Inline title "Hidden". Toolbar: "+" (the menu of 14.2; everything added goes into Hidden; a spinner while an import runs) and ⋯.

**Segments** (14 pt side margins): "All (N)" (every hidden pin), "Unsorted (N)" (hidden pins on no hidden board), "Boards", "Smart", "Search". Changing segment ends selecting that does not belong to it.

- **All:** the Pins grid (same cards, selection and menus; "Unhide pin(s)" replaces "Hide pin(s)"; pickers list hidden boards only) in Hidden's own "Order of pins" (default Shuffled; separate from the Pins tab's and the boards'; each opening starts a fresh shuffle). **Unsorted:** always newest first.
- Empty All (and Unsorted with no hidden pin at all): icon `eye.slash`, "No hidden pins yet", "Hidden pins stay out of Pins, Search, suggestions and “More like this”. Hide a pin from its ⋯ menu (or touch and hold it), add one here with +, or drag pictures here." Empty Unsorted while hidden pins exist: "Nothing unsorted here", "Every hidden pin is on a hidden board."
- **Boards:** tiles as 13.2 (lock badge; same menu and bar but no "Keep out of All"): every favourite hidden board at any depth, then the top-level hidden boards (a hidden board's normal parent is not shown), each group in the board sort, then a dashed "New hidden board" tile (hidden while selecting). With no hidden board a footnote sits above: "Everything on a hidden board is hidden too. Make one here, or touch and hold a board on the Boards tab and choose “Hide board”."
- **Smart:** 17.2. **Search:** 18.3.

**Drops** (dashed outline as 14.2): pictures, videos, text and links go to Hidden › Unsorted; the app's own pin cards are hidden, toast "Hid 3 pins." / "Hid 1 pin.", or the info toast "Already hidden."

**Converting row.** Only while hidden videos convert, under the switch: a small spinner, "Converting 2 of 5 (45%)" ("Finishing up…" after the last) and a "Stop" button (44 × 44 pt) at the right.

**The ⋯ menu**, in order:

1. "Select pins" (`checkmark.circle`; "Done selecting"): switches to All first unless All or Unsorted shows; dimmed with no hidden pins unless selecting.
2. "Select boards" (`checkmark.circle`; "Done selecting"): switches to Boards first; dimmed with no hidden boards unless selecting.
3. "New hidden board" (`folder.badge.plus`): sheet "New hidden board" (field "Board name", "Cancel" / "Save"); a hidden top-level board at the end of the custom order.
4. "Sort boards" (13.1) · "Reorder boards" (`arrow.up.arrow.down`; dimmed with fewer than 2 hidden top-level boards).
5. Divider; on All and Unsorted only, the "Order of pins" choices placed directly in the menu: "Shuffled" (`shuffle`), "Newest first" (`arrow.down`), "Oldest first" (`arrow.up`), and while shuffled "Shuffle again" (`arrow.clockwise`); choosing one switches to All first. Divider.
6. "Duplicates" (`square.on.square`) · "Recently Deleted" (`trash`) · "Tags" (`tag`): hidden-side versions of the screens of 23.4, behind the gate (wording: 16.3).
7. "AI sorting" (15.2).
8. "Convert videos to 1080p…" (`arrow.down.right.and.arrow.up.left`; only when it applies, below).
9. Divider, "Lock now" (`lock`; locks and returns to the Boards tab), "Settings…" (`gearshape`).

**"Convert videos to ‹quality›…"** converts hidden videos only (Settings' conversion, 22.1, handles normal ones; nothing here shows in Settings or on the normal pill). ‹quality› is Settings › Videos (or iCloud & storage) › "Video quality" (Original, 4K, 1080p default, 720p). Offered only while "Keep originals in a folder" is off (default off; hidden pins' originals are never copied there), the quality is not "Original" and some hidden video is bigger; dimmed during an import, a sync or Settings' conversion. It asks:

- Title: "Convert 4 videos to 1080p?" ("Convert 1 video to 1080p?"; "Convert videos to 1080p?" when none is left; N counts only videos that would change).
- Message: "Hidden videos larger than 1080p are replaced by smaller copies, and the larger versions are not kept. You can stop at any time."
- Buttons: "Convert" (red; the larger version is gone for good) and "Cancel". The dialog closes by itself when the app leaves the front.

While it runs the item reads "Stop converting" (`stop.circle`) and the row above shows progress. At the end, a toast only if Hidden is still on screen in this window (check; `stop.circle` when stopped): "Converted 3 videos." / "Converted 1 video." / "No video needed converting." / "Stopped. Converted 1 video." / "Stopped." It never names a board.

### 16.3 Everything hidden does differently, collected (toasts, pills, counts, exports, AI, web, Quick Look, sheets)

Hidden things never leak onto the normal side through a count, a message, a suggestion or a picture (2.6):

| Area | What differs |
|---|---|
| Wording | Messages never name a hidden board: "a hidden board" ("Put 2 pins on a hidden board.", "Removed 1 pin from a hidden board.", "Added 1 pin to a hidden board.", "Saved to a hidden board."), "a hidden smart board". Hide, unhide and keep-out toasts name no board. Delete questions say "Delete this board?" / "Delete this smart board?" and sit above the privacy cover. |
| Counts and lists | Never include hidden things: a normal board's counts, sub-board count, "Last added", size; pickers; "Move into…" lists; sub-board lists; the Pins segments "All (N)", "Unsorted (N)", "Kept out (N)"; the Boards footer "N unsorted pins"; "Smart (N)"; Settings' counts; the back-up reminder (pins added into Hidden are not counted). |
| Pill | The Pins tab's pill ("Sorting X of Y…", "AI is tagging pins… N of M", "AI is renaming pins… X of Y", import progress, "Transcribing N of M…" †) never shows work on hidden pins. The convert result shows only in Hidden. |
| Search and AI | Each side sees only its own pins: Search, Explore's library ideas, "More like this", "Start here", the picker's "Suggested" row, "Sort … into boards", look-alike questions (a look-alike link between a hidden and a normal pin is dropped). No AI looks at hidden pins — on-device tagging and text reading, AI titles, Apple Intelligence, search by meaning, transcripts, the cloud model — unless "Include hidden pins in AI" (Settings › Privacy & Hidden, also on AI) is on †; even then never the names of hidden boards (20.11). Hidden's ⋯ menu shows "AI sorting" only with it on. |
| Transcripts † | Hidden videos are listened to silently, after every normal video; no status line counts or mentions them. |
| The web | A hidden board's "Keep exploring" never loads by itself, even with "Automatically load web suggestions" on (14.4). Results saved from a hidden pin's or board's feed go into Hidden. Each feed keeps its own "Details" notes †. A link added to Hidden is never searched for a picture on the web † (9.5). A hidden pin's picture reaches a web search page only by the clipboard, whatever "Hand the picture over by" says † (7.4). |
| Sheets and screens | Covered whenever the app is not in front (4.3): Hidden itself, Quick Look of hidden pins, a hidden pin's page and its sheets, board commands on hidden boards, "New hidden board", Reorder, Colors, a hidden board's "Search the web for" sheet, adding a text or link pin into Hidden, import questions about hidden pins, Hidden › Search, a hidden smart board's editor, reorder sheet and page, hidden web results, Duplicates. |
| Exports | Whenever something hidden exists, an export first asks "Include hidden boards in the export?", message "Hidden pins (hidden on their own, or on a hidden board) are left out too.", buttons "Include hidden boards", "Leave them out", "Cancel". "Leave them out" writes no hidden board, pin or smart board (nor a smart board limited to a hidden board), no mention of hidden boards on normal pins, and drops links between a kept and a left-out pin (23.3). A shared hidden board carries the warning of 14.3; the palette picture of hidden pins carries no name. |
| Smart boards | Hidden ones live only in Hidden › Smart and never count in "Smart (N)" (17.2). |

**Hidden-side wording of the three ⋯ screens** (23.4; they list hidden pins only; normal wording in brackets):

| Screen | Hidden-side wording |
|---|---|
| "Possible duplicates" | Empty: "No duplicates found" — "Each new hidden image is compared with your other hidden pins as it is tagged." (“Each new image is compared with the library as it is tagged.”) |
| "Recently Deleted" | Empty: "Nothing here" — "Deleted hidden pins stay for 30 days so you can change your mind." (“Deleted pins stay for 30 days so you can change your mind.”). Footnote: "Deleted hidden pins. Restored pins stay hidden. They are erased for good after 30 days." (“Pins are erased for good after 30 days.”). "Erase all now…" asks "Erase every deleted hidden pin?" (“Erase everything in Recently Deleted?”). |
| "Tags of hidden pins" ("Your tags") | Footer: "Only the tags of hidden pins are listed. The number is how many hidden pins carry the tag. Renaming or merging changes it on every hidden pin." (“The number is how many pins carry the tag. Renaming or merging changes it on every pin.”). Empty: "No tags on hidden pins yet. Add tags on a pin's page." (“No tags of your own yet. Add tags on a pin's page.”). Delete question: "Delete this tag from every hidden pin?" (“Delete “beach” from every pin?”); a hidden pin's tag is never named. |

## 17. Smart boards

### 17.1 Making one (from Search, from the Boards tab), its rules (words, kinds, boards, colours, dates…), editing

A smart board is a saved search that fills itself: optional words, optional filters and a sort. It shows the pins that match now and keeps up as the library grows. It never holds pins: nothing can be put or dragged on it, it is in no board picker, and its only hand control is removing a pin from its list (17.2). It has no sub-boards, star, cover, description, "Keep out of All", hide, merge, share or multi-select; only a name, a rule, a place in the list and a removed-pins list. Normal smart boards (Boards › Smart) search normal pins; hidden ones (Hidden › Smart) search hidden pins; the two never mix.

**Where one is made.** The dashed "New smart board" tile (Boards › Smart) or "New hidden smart board" tile (Hidden › Smart); on Search, ⋯ › "Save as smart board…" (`sparkles`; dimmed with no words and no filter) and the small bordered "Save as smart board" button (`sparkles`, caption) at the right of the result line (same on Hidden › Search). From Search the editor opens with the current words, filters and sort filled in and the name empty; the user stays on Search after saving.

**The editor sheet.** Full height; inline title "New smart board" (Boards › Smart, Search), "New hidden smart board" (Hidden) or "Edit smart board" (keeps its side). "Cancel" (closes without asking) and "Save" (dimmed until the name is not blank and there is at least one word or one filter; a sort alone does not count). The content scrolls:

1. "Name" (caption, semibold, secondary) over a field, placeholder "e.g. Beach days" (rounded fields, radius 12; first letter capitalised).
2. "Search words (optional)" over a field, placeholder "e.g. sunset beach" (no automatic capitals).
3. "Filters" and the filter bar of 18.1 with its Sort chip; its board chip lists this side's boards only.
4. A divider, then a status line (footnote, secondary): "Add search words or a filter." (nothing set), "Nothing matches right now — the board fills up as pins arrive." (a rule, no match), or "Matches now: 1 pin" / "Matches now: 12 pins" (every match, removed pins included).
5. With matches, a sideways strip of up to 12 pin cards (110 pt wide, 8 pt apart, no scroll indicator).

The status line and strip update 0.3 s after the last key or filter change. Saving trims the name and words; a new smart board goes to the end of its side's list, an edited one keeps its removed pins; no toast. Once the name, words or a filter differs from how the sheet opened, a swipe down is blocked.

**The rule line:** the parts that apply, joined with " · ", in this order: the words in curly quotes (“sunset beach”) · the kinds joined with "/" in the fixed order "Photos/Links/Text/Videos" · "in Name" (the limiting board's own name; left out when it is gone; a normal smart board never names a hidden board) · "Unsorted" · "Untagged" · "With text" · "Duplicates" · the date "Past week" / "Past month" / "Past year" · the length "Under 10 s" / "10–30 s" / "30–60 s" / "1–5 min" / "5+ min" · "With sound" / "Without sound" · the sort when not "Best match": "Newest first" / "Oldest first". Nothing applies: "Every pin". Example: “sunset” · Photos · in Travel · Past year. A rule holds the filters of 18.1 except a colour filter, which does not exist: colour names typed as words match colour tags like any word.

**Which pins it shows.** The words are matched as Search matches them (18.2: tags, title, text in the picture, notes, link text, colour names, names of the pin's boards) but without Apple Intelligence's related words, so it can show fewer pins than the same search in Search. Every filter must pass too. Order: best match with words, newest first with only filters, or as sorted. Pins on the removed list are left out. A board limit includes that board's sub-boards of the same side. The list follows every change to the library (added, tagged, renamed, moved, hidden, deleted pins). A rule with neither words nor filters (only possible from old data) shows every pin of its side, newest first.

**When the limiting board changes.** Deleted or merged away: the limit goes back to "Any board" (it does not follow the merge). Hidden, or moved into a hidden board: normal smart boards limited to it or to a board inside it go back to "Any board", and unhiding does not restore the limit. Renamed: the rule line shows the new name. Hidden smart boards change only when their board is deleted or merged away.

### 17.2 How they show (segment, tiles, counts), deleting, hidden smart boards

**The Smart segment** has no "+" in the toolbar; ⋯ holds only "Hidden…" and "Settings…":

1. A footnote: "A smart board is a saved search that fills itself as your library grows. Make one here, or from the Search tab with “Save as smart board”." (Hidden › Smart: "A smart board here is a saved search over your hidden pins that fills itself. Make one here, or from Search with “Save as smart board”.")
2. A grid of tiles (columns, gutters, alignment as 13.2) in the user's own order, oldest first until reordered; the last cell is the dashed "New smart board" tile ("New hidden smart board" in Hidden).
3. Only with two or more on the side: "Reorder smart boards" (`arrow.up.arrow.down`, subheadline, accent) under the grid, opening a medium/large sheet "Reorder" ("Done"; rows `sparkles` and the name; drag handles always showing; every move saved at once).

There is no empty state: with none, the footnote and the dashed tile show. "Smart (N)" on the switch counts normal smart boards only.

**A tile.** Cover area 1.35 : 1, radius 16: the 62 % / 38 % collage of 13.2 from the first four current matches with a picture (text pins skipped); with none yet, or while counting, the neutral fill with `folder` (34 pt). Top-right on every smart tile (also in Hidden; no lock badge): `sparkles` (caption, semibold) in an ultra-thin-material circle, 8 pt in; no star, no selection mark. Name (headline, two lines). Detail line (caption, secondary, one line, cut with "…"): the rule line alone while the first count is made, then e.g. "12 pins · “sunset” · Photos · Past year", "1 pin · Unsorted", "0 pins · “zebra”". A tap opens the page; there is no "Select", drop target or favourite. The count and collage refresh when the tile first appears, at once when the rule changes or "Bring back" is used, and about 0.8 s after the library last changed (never interrupting a running search; it runs once more when that ends).

**The tile menu** (unusable commands left out): "Edit rule…" (`pencil`; sheet "Edit smart board"), "Bring back removed pins" (`arrow.counterclockwise`; only when some pin was removed; at once, no toast), divider, "Delete…" (`trash`, red). Delete asks: title "Delete “Name”?" (Hidden: "Delete this smart board?"), message "Only the rule is deleted; the pins it showed are not touched.", buttons "Delete smart board" (red) and "Cancel". No toast.

**A smart board's page.** Inline title: the name ("Hidden" for a hidden one while locked); trailing ⋯ only. Deleted meanwhile: icon `sparkles`, "This smart board was deleted".

- Header above the grid: `sparkles` and the rule line (subheadline, secondary, wraps) with a small bordered "Edit" at the right. When pins were removed: "1 pin removed from this smart board." / "3 pins removed from this smart board." (caption, secondary) with a small text button "Bring back".
- The pins: the Pins grid (cards, columns, taps, menus, selecting, drag-out; 6) in the rule's order: relevance with words and sort "Best match", newest first with only filters, else as the sort says. No shuffle, no "Order of pins" menu; pulling down does not reorder.
- Empty: icon `sparkles`; "Looking…" (no message) during the first search, then "Nothing matches yet" — "Pins that match the rule appear here automatically. Edit the rule from the ⋯ menu."
- ⋯ menu: "Select pins" (`checkmark.circle`; "Done selecting"; dimmed when nothing is listed), "Edit rule…" (`pencil`), "Bring back removed pins" (`arrow.counterclockwise`; dimmed when none), divider, "Settings…" (`gearshape`; not when the page was opened from Settings), divider, "Delete…" (`trash`, red). The page's delete question has only "Delete smart board" (the system's tap-away closes it); afterwards the page closes.
- Removing: on this page a pin's long-press menu and the selection bar's More carry "Remove from this smart board" (`minus.circle`), for one pin or several. Toast: "Removed 2 pins from Beach days." ("Removed 1 pin from Beach days."; hidden: "Removed 2 pins from a hidden smart board."). The pins vanish at once, stay in the library and on their boards, and return with "Bring back" (header button or menu item; no question, no toast).
- Searched again when the page opens, at once when the rule changes or "Bring back" is used, and about 0.8 s after library changes; a pin removed, deleted, hidden or unhidden disappears at once.

**Hidden smart boards** live in Hidden › Smart: the Hidden footnote, the "New hidden smart board" tile, "Reorder smart boards" and tiles identical to normal ones. Their editor is "New hidden smart board", its board chip lists hidden boards only, and Save makes one at the end of Hidden's list. The delete question never names the board, the removal toast says "a hidden smart board", the editor, reorder sheet and page are covered when the app is not in front (16.3), and they never count in "Smart (N)".

**In the data.** Each profile has its own smart boards (23.1). A full export carries them with rules and removed lists, and importing adds those not already present; hidden ones, and ones limited to a hidden board, are left out when hidden content is (23.3). iCloud keeps the newest change of each; a deletion on one device wins unless the other copy changed later (23.2). "Clear this profile's library…" removes them (23.4); "Share board…" never includes them.

## 18. The Search tab

### 18.1 Layout; the search bar; the filter chips (every filter and its choices); "Save as smart board"

The fourth tab, label "Search" (`magnifyingglass`), large title "Search": it searches the whole normal library by meaning, with optional filters. It is not a drop target. Leaving and coming back keeps the words, filters and results. The toolbar ⋯ holds "Select pins" (`checkmark.circle`; "Done selecting"; dimmed with no results unless selecting), "Save as smart board…" (`sparkles`; dimmed until there is a word or a filter; 17.1), divider, "Settings…" (`gearshape`).

Everything under the title scrolls together (nothing is pinned): search bar, chip row, top tags or result line, then the grid or an empty state. While selecting, the pin selection bar (6.5) appears. A sideways swipe switches tab, except on the chip row and while selecting.

**The search bar:** a rounded bar (radius 14, secondary fill):

1. `magnifyingglass` (secondary).
2. The field, placeholder "What are you looking for?" (Hidden: "Search hidden pins"); return key "Search"; no automatic capitals or corrections; the keyboard does not rise by itself when the tab opens.
3. While there is text, `xmark.circle.fill`: empties the field and the results.
4. A small prominent "Search" button (subheadline, semibold; dimmed while blank): puts the keyboard away and searches at once.

**The filter chips** are one sideways-scrolling row (sliding along it never changes tab). Every filter works without words, and all active ones must pass together:

| Chip | Icon | Choices |
|---|---|---|
| Kinds (toggles, any combination; none on = every kind) | `photo`, `text.alignleft`, `play.rectangle`, `link` | "Photos", "Text", "Videos", "Links" |
| Board menu | `folder` | "Any board", "Unsorted only", divider, then the side's boards in Boards-page order (favourites first, then the sort), a sub-board indented two spaces per level. The chip reads "Any board", the board's name or "Unsorted". A board includes its sub-boards; a hidden board chosen earlier is ignored ("Any board"). |
| Date menu | `calendar` | "Any time", "Past week", "Past month", "Past year" (7, 31 and 366 days; from the day a picture was taken when known, else from when it was added) |
| Length menu | `timer` | "Any length", "Under 10 s", "10–30 s", "30–60 s", "1–5 min", "5+ min" (0 to under 10 s; 10–30; 30–60; 60–300; 300 and more) |
| Sound menu | `speaker.wave.2` | "Any sound", "With sound", "Without sound". A length or sound choice shows videos only; a video whose length or sound is not yet known is left out until the background check finds it. |
| "Untagged" | `tag.slash` | Pins with no tags of your own |
| "With text" | `text.viewfinder` | Pins with text read in the picture, and text pins |
| "Duplicates" | `square.on.square` | Pins marked as looking like another pin |
| Sort menu | `arrow.up.arrow.down` | "Best match" (default), "Newest first", "Oldest first" (by date added, not date taken) |
| "Clear" | `xmark` | Shown when a filter is on or the sort is not "Best match"; clears every filter and the sort, not the words |

Chip look: capsule, caption size, one line. Off: secondary fill, primary text. On (a toggle on, a menu on a non-default choice, a chosen board): accent at 18 % fill with accent text. A sort alone is not a search: with no words and no filter the screen stays on "Search by meaning". The same row, with Sort, serves the smart-board editor (17.1); "Save as smart board" (menu item and result-line button) opens that editor with the current words, filters and sort.

### 18.2 Before a search; results; what a search matches (words, tags, colours, text in pictures, notes, transcripts †)

**Before any word or filter**

- If the library has tags: the caption "Try one of your library's top tags" (secondary) and up to 14 small bordered buttons wrapping over several lines; a tap puts the tag in the field and searches (0.3 s). The tags are the side's most-used: a pin's own tag gives 3 points, an AI tag 1 point (only above 50 % confidence), a word once per pin; colours and read words never count; ties alphabetical.
- Empty state: icon `text.magnifyingglass`, "Search by meaning", "Describe what you're looking for in plain words — “puppies at the beach”, “food”, “screenshots with text”. The on-device AI matches meaning, not just exact tags. Filters work on their own too."

**With words or filters**

- Under the chips: "12 results — best matches first" (caption, secondary; "1 result"; the dash part only while the sort is "Best match"; nothing with no results) and, at the right, the small bordered "Save as smart board" button (`sparkles`, caption). When Apple Intelligence found related words: "Apple Intelligence also looked for: word1, word2" (`sparkles`, caption, secondary).
- Under each card (caption2, one line): up to three matched words joined with " · " ("dog · beach"; an exact phrase match shows the phrase first), or, when no word matched and the sort is "Best match", "72% match". A filters-only search lists newest first and shows "100% match" under "Best match" (nothing under another sort).
- A tap opens the pin as on the Pins tab: a picture, text or link opens its page, where swiping moves through up to 400 results around it in the order shown; a video opens Quick Look. A long-press gives the card's menu ("Select" starts selecting).
- Live: a deleted pin, or one moved across the hidden line, leaves at once. Pins in Recently Deleted never show; pins kept out of All do.
- Empty: "Searching…" with icon `questionmark.circle` (no message) while nothing has arrived yet; no match, `questionmark.circle`, "No matches", "Try different words or fewer filters, or add your own tags to pins so they're easier to find." Old results stay until new ones arrive.
- Timing: typing or changing a filter or the sort searches 0.3 s after the last change; Return or "Search" search at once. Clearing the field and filters empties the results and brings the tags back at once. After a library change the results refresh about 1.5 s later without interrupting a running search (it runs once more 1 s after it ends). Switching Settings › AI › "Use Apple Intelligence" reruns the search at once. A newer search replaces an older one.

**What a search matches**

1. **The words.** The text is lower-cased and split at spaces and punctuation; one-letter words are ignored; filler words are dropped: a, an, the, of, with, and, or, in, on, at, to, for, from, by, my, me, i, show, find, search, photos, photo, pictures, picture, pics, pic, images, image, that, this, some, any, all, where, which, have, has, is, are, it, its, like, look, looks, looking, featuring, containing, contains, something, things, thing, want, see, get, near, about, kind, type, pins, pin, one, ones, very, really, please, you, your, our, we, was, were, be, been, not, but, if, so, as, can, will, just, than, then, there, here, what, when, who, how, http, https, www, com (if every word is a filler, all are used). Each word is reduced to its base form ("puppies" → "puppy", "running" → "run"; for an unknown word a final "s" is dropped when the word is longer than 3 letters, except "ss"). A word typed twice counts once.
2. **Two words compared** give a similarity: the same word 1.0; the shorter (at least 3 letters) starts the longer and the longer has at most 2 extra letters ("dog"/"dogs", "doggy"; not "car"/"carpet") 0.85; the shorter (at least 5 letters) lies inside the longer 0.6; otherwise, when spelling gives under 0.7, the device's English word meanings are compared: 0.4 to 0.85 ("puppy"/"dog", "coast"/"beach"). Colour names, a link's site name and the full text read in a picture match by spelling only.
3. **Where a pin's words come from,** each similarity multiplied by a weight:

| Source on the pin | Weight |
|---|---|
| Own tags (whole tag) | 1.0 (single words of a multi-word tag 0.95) |
| Title words | 0.95 |
| Keywords stored in the picture file; a link's website name | 0.9 |
| Key words of the text read in the picture; a note's words; a text pin's body; a link's article text (first 4,000 characters) | 0.85 |
| A video's spoken-word transcript kept in its note (first 4,000 characters, word by word) † | 0.85 |
| The AI's description; names of the pin's boards (the searched side's only) | 0.8 |
| Every word read in the picture; colour names | 0.7 |
| AI tags | 0.5 + 0.5 × the AI's confidence (single words of a multi-word AI tag: 0.9 of that) |

4. **Scoring.** A typed word counts when the pin's best match for it is at least 0.3; the score is the sum divided by the number of typed words (a pin missing one of two words scores at most half). Pins at 0.3 or more are shown. The whole typed text (at least 3 characters) found in the title, note, text, picture text, description, link address or own tags lifts the score to at least 0.95. Order: score ("Best match"), or date added for the other sorts. With no words: the pins that pass the filters, newest first.
5. **Apple Intelligence's second pass.** After the first results show, with words, Settings › AI › "Use Apple Intelligence" on and available: the on-device model suggests up to 6 related single words (20 letters or fewer; "puppy" → dog, retriever, pet). A pin whose best related match is at least 0.6 gets a score of at least 0.55 × that match: it can add or lift pins, never lower one. Nothing leaves the device. Smart boards never use it.
6. **Sides.** A normal search ignores hidden pins and hidden boards entirely (their names never count as words).

### 18.3 Inside Hidden

Hidden › Search (16.2) is the same screen for hidden pins only, with no title, ⋯ menu or tab swipe of its own ("Select" is on a card's long-press menu). Differences: placeholder "Search hidden pins"; tags caption "Try one of the top tags of your hidden pins" (hidden pins' tags only); empty state "Search hidden pins" — "Only your hidden pins are searched here. Describe what you're looking for in plain words, or use the filters."; the board menu lists hidden boards, a chosen one including its sub-boards' pins; "Unsorted only" means on no hidden board (a hidden pin filed only on normal boards, out of sight, counts as unsorted); board names count as words only for hidden boards; "Save as smart board" (the result-line button only) makes a hidden smart board, editor "New hidden smart board". The segment and the editor are covered when the app is not in front (16.3).

## 19. The Explore tab

### 19.1 Sources (names, which need keys, where to get a key), choosing a source, recent searches

The third tab, label "Explore" (`globe`), large title "Explore": it searches openly licensed picture sources on the web and saves results into the library with one tap. Nothing is fetched until the user searches (Return, the "Search" button, or a tap on a recent-search or idea chip), except at the end of a board's page when "Automatically load web suggestions" is on (14.4). Web pictures are held only while looked at; nothing is written to the device until saved.

Layout: toolbar (source menu and ⋯, below) and a scrolling area with the search bar, then the suggestions or the results. A sideways swipe switches tab, also on the Offline page. Pull-to-refresh does nothing. A profile switch clears the words and results.

**The five sources**

| Source | Key | Settings rows | Link row (opens) | Page size |
|---|---|---|---|---|
| "Wikimedia Commons" (default) | none; no practical limit | Note: "Wikimedia Commons needs no key and has no practical limit. Results are openly licensed but mixed in quality." | "About Wikimedia Commons" (commons.wikimedia.org/wiki/Commons:Welcome) | 30 |
| "Openverse" | none; optional credentials | "Client ID", "Client secret"; note: "Without credentials Openverse allows only about 5 searches per hour. Registering is free: it emails you a client ID and secret." | "About Openverse" (api.openverse.org/v1/#tag/auth/operation/register) | 20 (50 with credentials) |
| "Pexels" | key | "Pexels API key" | "Get a free key from Pexels" (www.pexels.com/api/) | 30 |
| "Pixabay" | key | "Pixabay API key" | "Get a free key from Pixabay" (pixabay.com/api/docs/) | 30; 500 results at most |
| "Unsplash" | access key | "Unsplash access key" | "Get a free key from Unsplash" (unsplash.com/developers) | 30 |

A key row has its title at the left and a right-aligned field, placeholder "Paste here", no automatic capitals or corrections, shown as dots unless the switch "Show keys" is on (not offered for Wikimedia Commons; off each time the page opens).

**Explore's rows in Settings** › Explore & web search › "Image source" and "Web suggestions" (21.8; dimmed, not hidden, while Offline mode is on):

| Row | Choices | Default |
|---|---|---|
| "Image source" | "Wikimedia Commons", "Openverse", "Pexels", "Pixabay", "Unsplash" | "Wikimedia Commons" |
| Key rows of the chosen source, "Show keys", link row | as the table above | no key saved |
| "Automatically load web suggestions" | on / off | off |
| "Offer web ideas at the end of boards" | on / off | on |
| "Clear recent Explore searches" (button, only while there are recent searches; no confirmation) | | |

Footer: "Board pages and pin pages fetch web results only when you ask, unless “Automatically load” is on; the Explore tab searches when you tap Search. Keys are stored in the iOS Keychain and sent only to the service they belong to, over HTTPS." When the system refuses to store keys: "…The Keychain refused to store keys in this environment, so they are kept in the app's preferences instead. They are still sent only to the service they belong to, over HTTPS."

**Choosing a source.** The toolbar button shows the source's name with a `globe` (subheadline) and opens a menu with a picker "Source" (check on the chosen one). It is the same setting as "Image source" (each changes the other; kept between launches). Changing it reloads the current search from the new source.

**The ⋯ menu:** "Save all N results…" (`square.and.arrow.down.on.square`; 19.2), divider, "Settings…" (`gearshape`).

**The suggestions screen** (before a search):

1. The key notice, only when the chosen source needs a key and none is saved: icon `key` and "Pexels needs an API key — add it in Settings or pick another source." (footnote, secondary; the source's name; never for Wikimedia Commons or Openverse).
2. **Recent searches** (only when there are some): a header row with "Recent searches" (caption, secondary) and a "Clear" button (caption) that empties the list; below, wrapping chips (8 pt apart): small bordered buttons with `clock` and the words, which fill the field and search at once. At most 10, newest first; the same words again (ignoring capitals) move to the top; every search is remembered, trimmed; the list belongs to the profile in use, is shared by all sources and kept between launches.
3. **The ideas line** (caption, secondary): with no tags in the library, "Search for ideas — “mid-century living room”, “sourdough”, “mountain cabins” — then tap Search. Tap + on anything to keep it."; otherwise "Ideas from your library" and up to 12 small bordered chips (lower-case tag words, no icon) that fill the field and search. The ideas are the normal side's most-used tags (hidden pins never count): own tag 3 per pin, AI tag above 50 % confidence 1 per pin; highest first, ties alphabetical.

**The Offline page.** With Offline mode on (Settings › Privacy & Hidden › "Offline mode", default off; 21.9) everything below the toolbar becomes the system's "content unavailable" look: icon `wifi.slash`, title "Explore is off in Offline mode", text "Nothing leaves this device while Offline mode is on, so there are no web images to search.", and a prominent "Turn Offline mode off". Nothing on it touches the network. The button turns Offline mode off, the earlier search comes back and loads again, and videos waiting for a transcript restart about 2 s later †.

### 19.2 Searching and results (cards, credit, Save, Save to board, Quick Look, reverse search, Details)

**Starting a search.** The search bar of 18.1 with the placeholder "Search ‹source›…" ("Search Wikimedia Commons…"). A search starts only on Return, "Search" or a chip tap, never while typing; the text is trimmed and empty text does nothing. Clearing the field clears the results and returns to the suggestions; editing the text after a search leaves the results alone until the next one. The bar is not shown in Offline mode.

**The results.** A masonry grid of result cards (columns as 6.1). Pages of 30 (Openverse 20, or 50 with credentials) load as you scroll: when the last card appears the next page is requested, one at a time; a page with nothing new or usable makes the next load by itself, up to 3 in a row. Results stay when you leave and return; only a new query, a source change or a changed key reloads; a result is never added twice. Under the grid, centred, one of: a spinner while a page loads (the first page's sits under the search bar); an error: icon `wifi.exclamationmark` (title2, secondary), the message (footnote, secondary), a small bordered "Try again" (from the first page) and "Details" (a failed later page leaves the results shown); nothing found: "No web results for “query”." (footnote, secondary) and "Details"; the end: "That's everything for “query”." (footnote, secondary).

**A result card**

- The picture in its true shape, never narrower than 1 : 5 (taller ones are cropped), radius 16, on a secondary-fill placeholder; a spinner while it loads, a grey `photo` if it cannot load.
- The "+" button at the picture's bottom-right: a 34 pt accent circle with a white `plus` (headline weight) and a soft shadow (radius 3), 8 pt from the corner, 44 × 44 pt tap area; a white spinner while that result saves, then a green circle with a white `checkmark` (disabled). It saves onto the feed's boards (Unsorted in Explore).
- 6 pt under the picture, the title (footnote, semibold, one line), 6 pt lower the credit (caption2, secondary, one line); each only when the source gave one.
- "Saved" means a pin made from that very source page already exists on this side of the library (a page saved as a hidden pin never shows as saved in a normal feed).
- A tap opens a draft pin page (10.5), or the saved pin's own page if already saved. A long-press opens the menu below. Cards cannot be dragged.

**The long-press menu:** "Save to library" / "Saved" (`plus` / `checkmark`; dimmed once saved or while saving); "Save to board…" (`folder.badge.plus`; the picker "Save to…" of 14.5; allowed for a saved result, which it then only puts on the board, saying "1 was already in your library (now on X too)."; "No board (Unsorted)" changes nothing for it; dimmed while that result saves); "Quick look" (`arrow.up.left.and.arrow.down.right`); "Search this picture on the web" (`magnifyingglass`; submenu "Google Lens", "Bing", "TinEye", "Yandex"); "Open source page" (`safari`; the page the picture came from, in the system's default browser, whatever "Open web searches in" says).

**Saving a result**

- Saved: the full-size picture when it can be fetched (sizes per source below), else the preview. HTTPS only; a file over 30 MB is refused. The pin's title is the result's title cut to 60 characters; the page address and credit stay with the pin (its page shows "Open source page" and the credit line).
- **Unsplash †** (build 16, as Unsplash's API guidelines ask). Each Unsplash photo saved (the card's "+", "Save to library", "Save to board…", "Save all", a draft page's Save) is reported to Unsplash: once the picture has been downloaded for saving (so also when the look-alike question then cancels it; on a draft page, once it is saved), one request goes to the photo's own "download location" with your access key; nothing waits for it, a failure changes nothing, and nothing is sent in Offline mode or without a key. A result already in the library is not downloaded again and not reported. The credit reads "Photo by ‹name› on Unsplash"; the saved pin's source page is the photo's Unsplash page with "utm_source=PinBoard&utm_medium=referral" added, and in Quick Look's info panel the name and "Unsplash" are links to the photographer's page and unsplash.com with the same tags (11.3). (Unsplash pins saved before build 16 keep "Photo by ‹name› · Unsplash" and an untagged source page.)
- A result already in the library (same source page, same side) is not downloaded again, only put on the chosen boards.
- It lands in Unsorted (Explore, or a feed with no board), on the feed's boards (14.4, 19.3), or in Hidden for a hidden feed with no board (a hidden board hides it itself).
- While it saves the card's "+" spins; with several at once the pill reads "Downloading N of M…"; a picture that looks like one already in the library raises "Looks familiar" (8.4). Afterwards the import wording of 8.5: "Added 1 pin." / "Added 1 pin to X." / "Added N pins." / "1 was already in your library (now on X too)." as a toast, or, when something failed, an alert: "This image couldn't be downloaded." (one) / "None of those images could be downloaded." (several).

**Save all.** ⋯ › "Save all N results…" saves every loaded result not yet saved (all scrolled through, not just those on screen). The item reads "Save all results…" (0), "Save 1 result…", "Save all 57 results…"; dimmed when nothing is searched, in Offline mode, or when every loaded result is saved or saving. Dialog: title "Save 57 results to your library?" ("Save 1 result to your library?"), message "Each one becomes a pin in Unsorted. Results you saved already are left out.", buttons "Save 57 results" ("Save 1 result") and "Cancel". Results whose own "+" is still saving are left out. Nothing left at confirmation: info toast "Everything shown is already in your library."

**Quick Look from results.** "Quick look" opens a full-screen feed of the loaded results from the chosen one; swiping pages through them, and when the picture shown is among the last 6 more are fetched (seen results are skipped). Its ⋯ menu, also the long-press menu on the picture: "Show info" (`info.circle`), "Save to library" / "Saved", "Save to board…" (`folder.badge.plus`), "Share…" (`square.and.arrow.up`; a medium/large share sheet with the result's page address, not the picture), "Search this picture on the web", "Open source page" (`safari`). The info panel ("Show info", or a swipe in from the right edge) has headings in caption, semibold, secondary: "Title" (title3, semibold, or "No title"; the credit under it, footnote, secondary; for Unsplash † with the photographer's name and "Unsplash" as links), "Source" (a link with `safari` and the site's address, such as "commons.wikimedia.org", or "Open source page" when none) and "Save" (a small prominent "Save to library" / "Saved" and a small bordered "Save to board…"). Saves land where the feed's saves land; a hidden feed's Quick Look is covered when the app is not in front; toasts show 96 pt above the bottom.

**Reverse search.** The search site is given the picture's own web address (nothing is copied or saved): Google Lens `lens.google.com/uploadbyurl?url=…`, Bing `www.bing.com/images/search?view=detailv2&iss=sbi&form=SBIVSP&sbisrc=UrlPaste&q=imgurl:…`, TinEye `tineye.com/search?url=…`, Yandex `yandex.com/images/search?rpt=imageview&url=…`. It opens as Settings › Links › "Open web searches in" says: "PinBoard (private)" (default; the private browser, 9.7) or "Default browser" †. A picture that lives only in the library has no address and uses the hand-over of 7.4 (Settings › Links › "Hand the picture over by"; 21.5) †.

**"Details".** A small "Details" disclosure (caption, secondary; up to 600 pt wide) under an error or "No web results". Opened: selectable monospaced text (caption2, secondary) and a "Copy details" button (caption). The text is what the feed's latest request did, the last 12 lines at most, any key of 4 or more characters shown as "•••"; each page request starts the notes afresh. Lines: "Source: ‹source name› · query “…” · page N · offset N"; "Request: ‹web address›"; "Reply: HTTP ‹status›, N bytes: <the first 500 characters of the reply, line breaks as spaces>"; "Pages in reply: N" (Commons); "Nothing with the photo filter; retrying without it."; "Usable results: N · more available: true" (or false); "Error: ‹message›"; "Reply could not be decoded: ‹details›"; "Openverse: could not get a token with the saved credentials; searching anonymously." Each web feed (Explore, a board's, a pin's, a hidden one) keeps its own notes, so words searched in a hidden feed never show under the normal side's "Details" or "Copy details" †.

**Error wordings** (the feed stops after one; "Try again" starts over):

- "‹Source› needs an API key. Add one in Settings, or switch to Wikimedia Commons." (a keyed source without a key, or a key the service refused with HTTP 401/403); a keyless source that still refuses: "‹Source› refused the request (not authorized)."
- Openverse's limit: "Openverse's free limit was reached (about 5 searches per hour without credentials). Add credentials in Settings or switch source."; other sources (HTTP 429): "‹Source› says too many requests. Try again in a little while."
- "The image service replied with an error (N)." (any other HTTP error) · "That image is too large to download." (over 30 MB) · "The image service returned an address that isn't HTTPS, so it was skipped." · "Offline mode is on (Settings), so nothing is fetched from the web." · "The reply from ‹source› had an unexpected format." · "Wikimedia Commons: ‹the service's own message›".
- Other network trouble shows the system's own description (for example a time-out, after 25 s).

**What each source does.** All requests: HTTPS only; 25 s time-out; no cookies, nothing kept between searches; the app identifies itself as "PinBoard/1.0 (iPhone and iPad app)" † (before build 16 "PinBoard/2.1 (personal iPad app built with Swift Playgrounds; SwiftUI)"; a contact address is still to be added, 25.2); keys go only to their own service and are hidden in "Details"; a result whose pictures are not served over HTTPS is skipped, and results in an unexpected shape are skipped one by one.

| Source | Search and pictures | Title | Credit |
|---|---|---|---|
| Wikimedia Commons | Files only; asks for photos first (JPEG, PNG, WebP; other kinds skipped), retrying without that filter when the first page is empty and filtering itself; 800 px previews; saves the original, or a 1600 px version when the original is wider than 1800 px; page = the file's description page | The file name without "File:" and its extension, underscores as spaces | "Artist (cut to 40 characters) · License · Wikimedia Commons" (the parts that exist; markup stripped) |
| Openverse | 20 per page without credentials, 50 with them (a token is fetched first; if that fails it searches anonymously and says so in "Details"); mature content excluded; preview = the provider's thumbnail; saves the original; page = the provider's own page | As given (none if missing) | "Creator (cut to 40) · LICENSE (capitals) · Provider (title case; "Openverse" when unknown)" |
| Pexels | Preview "medium"; saves "large 2×", else "large", else the original | The picture's description (alt text); none if empty | "Photo by ‹name› · Pexels" ("unknown" without a name) |
| Pixabay | Photos only, safe search on, 500 results at most; preview = the web-format picture; saves the large image | The picture's tags cut to 60 characters, commas shown as " ·" | "Image by ‹user› · Pixabay" |
| Unsplash | Content filter "high"; preview "small"; saves "regular"; page = the photo's Unsplash page with Unsplash's referral tags †; each save reported to its download location † | The description, else the alternative description, cut to 60; none if empty | "Photo by ‹name› on Unsplash" † (was "Photo by ‹name› · Unsplash"); in Quick Look the name and "Unsplash" are tagged links |

### 19.3 The web feeds elsewhere ("From the web" on a pin page, "Keep exploring" on a board) and "Automatically load"

Both feeds use Explore's result cards, long-press menu, paging, error lines, "Details" and saving rules (19.2), and the same image source and keys.

**Where saves go.** A board's "Keep exploring": onto that board. A pin's "From the web": onto the boards shown on the pin's page; a hidden pin's results go into Hidden (or its hidden boards), a normal pin's never do. A draft page: onto the boards of the feed the result came from. A board deleted, hidden or unhidden since the feed was shown is left out, so a save never crosses the hidden line.

**How the search words are chosen.** At most 2 words are ever sent ("golden retriever puppy beach" becomes "golden retriever"). Only the search words leave the device, never notes, tags or images (unless Cloud AI is on; 20.4).

- **Board:** its name first (and the boards around it), then its most common tags (up to 10) and some titles (up to 6) of its pins, sub-boards included. With Apple Intelligence on, the on-device model writes the words; otherwise the board's name (two meaningful words at most) or, on "Different ideas", a name word plus a tag from its pictures (not a vague one). A board with no usable name falls back to "inspiration".
- **Pin:** what the person wrote comes first, in this order of weight: the boards it is on (most important), its own tags (very important), a title they wrote, a note they wrote (first 300 characters); then what the file and the software found: keywords and caption stored in the photo file, the AI's description, an AI-written title, the AI's top 10 recognised objects with confidence, dominant colours, text in the picture (first 200 characters), camera, date taken. With Apple Intelligence on, the model writes the words from that (a hint the cloud model left for the picture is used first, on the first ask). Without it: a board name or own tag plus one machine word (a word of an own title, a file keyword, or an AI tag that is not vague); "Different ideas" cycles through the alternatives without repeating the last; last resort: the pin's title, or "inspiration".

**On a board** (14.4 has the block in full): "Keep exploring" with "Show ideas from the web", "Different ideas", "Searching for “query”" and "Change".

**On a pin's page.** The page's segmented control (10.4) has "More like this" and, only with Offline mode off, "From the web". The section header is "From the web" (`globe`, headline) with, once a search exists and no new words are being chosen, "Different ideas" (`arrow.clockwise`, caption) at the right, which makes another search from the same pin.

1. Before asking: "Search Wikimedia Commons for images like this one. Anything you save goes on the same boards as this pin." (footnote, secondary, centred; the chosen source's name) and a prominent "Continue from the web" (`globe`).
2. The first tap on the "From the web" tab scrolls to the section and starts the search, as the button does; scrolling to the section by hand only moves the tab highlight and leaves the ask.
3. Choosing the words: a small spinner with "Apple Intelligence is composing a search from this pin…" (Apple Intelligence on) or "Choosing a search from this pin's tags…" (caption, secondary).
4. Searching: `sparkles` (written by Apple Intelligence) or `tag`, "Searching for “query”" (caption, one line) and "Change", opening the sheet "Search the web for" (field placeholder "Search words", pre-filled; empty text does nothing; own words switch the icon to `tag`), then the feed.

**"Automatically load web suggestions"** (default off) makes only a board's "Keep exploring" start without the "Show ideas from the web" tap, and never for a hidden board. A pin's "From the web" never loads by itself. With Offline mode on, neither feed exists: no "Keep exploring" block, no "From the web" tab.


## 20. The AI

Three layers work on a pin. The **on-device AI** is always on, needs no account and has no switch (20.1). **Apple Intelligence**, the device's own language model, is optional and sees only words (20.3). A **cloud vision model** stays off until the person adds their own key and agrees; it is the only thing that ever sends a picture anywhere (20.4). None of them changes what the person wrote, and none files a pin on a board unless asked (20.7).

### 20.1 On the device: what every new pin gets (tags, colours, text in pictures, a title), the order of work, the pill texts, what makes the AI look again, what it never does

A new pin appears at once; nothing waits for the AI. Then, one pin at a time at low priority (also in Offline mode), the on-device AI looks at it.

**While a pin waits.** Photo and video cards carry a "Tagging…" badge (icon `sparkles`, 6.2); text and link cards show nothing. The pin page says "The AI is still looking at this pin…" under the board chips, "AI tags" shows a spinner with "Analyzing on this device…" ("Analyzing on this device and in the cloud…" when the cloud model is in use), and "More like this" says "Similar pins appear here once the AI has looked at this pin."

**Order of work.** The newest waiting pin first; every normal pin before any hidden one; Recently Deleted pins never. A link waits for its page to be read (at once, from its text alone, when "Fetch link previews" is off or in Offline mode). Video upkeep (20.9) and transcription (20.10) wait while the AI is busy. The queue starts at launch and after anything that adds or changes pins: an import, paste or drop; a restored copy or an iCloud sync; a changed picture (turn, flip, crop, new thumbnail, a link pointed at another page); an edited text pin; a video's words written down †.

**The pill** (4.2) reads "AI is tagging pins… N of M" (N = done + 1; M only grows) with a progress bar. It counts normal pins only: hidden pins never show a pill or a number. One message at a time, by priority: import messages ("Sorting N of M…", "Fetching the link…", "Transcribing N of M…" †) → "Syncing with iCloud…" → "AI is tagging pins… N of M" → "AI is renaming pins… N of M".

**What the look finds** (in a photo, a video's poster or a link's preview picture)
1. **AI tags:** the labels the built-in recogniser is sure of, topped up to 6 with the most confident others (each above 20%); at most 15, lower-case; a chip reads "label NN%".
2. **People counted, never identified:** one face adds "portrait" (90%) and "person" (85%); two to four "people"; five or more "crowd". "cat" or "dog" when over 50% sure.
3. **Colours:** up to three of red, orange, brown, yellow, green, teal, blue, purple, pink, each covering at least 18% of the picture (the most common one if none does); "black and white" first when over 92% is colourless. No percentage; searched by spelling only.
4. **Text in the picture,** read with language correction (Settings › AI › "Accurate text reading (slower)" picks the slower reader, 21.7). Up to 8 key words are kept: 3–24 letters, no digits, no filler, seen twice or known to the dictionary.
5. **A visual fingerprint and a 64-point signature,** never sent, behind "More like this", board suggestions and look-alikes (20.8).
6. **A title,** only when the AI may write it (20.2).

If the file cannot be read: "The AI couldn't find anything it recognizes here. Add your own tags above."

| Pin | Named and tagged from |
|---|---|
| Photo | the picture |
| Video | its poster; with a transcript †, the spoken words first, then the poster |
| Link | its page text first (the first 4,000 characters of the article, video description or short description), then the preview picture's labels; with a picture but no text, the picture plus the words of the page title (at 55%) |
| Text pin; link without a picture | its text only |

Tags made from text are its key words (up to 8), at 60%; for a link or video with text of its own, at 80% and ahead of the picture's labels, none twice. A stand-in picture found for a link whose page has none (9.5) † becomes its preview picture and is looked at like any other. On the pin page "AI tags" and "Text in this image" (10.3) show the results; the caption "Tap an AI tag to keep it as one of your own tags." means a tapped chip moves, lower-cased, into "Your tags" (all kept: "You have kept every tag the AI found.").

**Looking again.** "Re-run" in "AI tags"; "AI sorting ▸ Re-run AI tags" (15.2) for a pin, a selection, a board's pins or a whole side; Settings › AI › "Re-run the cloud model on all pins". A re-run replaces the AI's tags, colours and read text and may rewrite titles the AI wrote; no question, no message.

**What it never does.** Change the person's tags, notes, boards, covers, favourites or hiding (its one addition to a note is a transcript †, 20.10); work out who is in a picture; send anything off the device by itself; look at, count, compare or name hidden pins from the normal side, or the reverse; replace a title the person typed or one imported from a page or file, except through "Rename with AI" / "Rename all with AI…".

### 20.2 Titles: the three authors and the protection rules; how an on-device title is made; "Written by AI", Undo, "Suggest a title"; links are named from their text first; videos from their transcript first †

Who wrote a title (you, imported, the AI) and its protection rules: 2.2. The AI may replace a title only while it is empty or exactly what the AI last wrote; a title you typed changes only through "Rename with AI", "Rename all with AI…" (20.5) or "Suggest a title".

**First titles by origin**
- Camera, paste, drop, share, and videos from Photos: none; the AI writes one.
- A file from Files: its name with "_" and "-" as spaces (imported); a camera-style name (fewer than 4 letters, or more digits than letters: "IMG_1234") is dropped. A photo file's embedded title is used when the pin has none.
- A saved web image: its title cut to 60 characters at a word, with "…".
- Text: a text pin's title as typed (yours); pasted, dropped or shared text has none and the AI uses its first line; a text file takes its file name.
- A new link: the site's name ("example.com", the AI's placeholder), then the page's own title once read (imported). A saved quote †: the article's title.

**When the AI names a pin by itself.** After the look, if the title is the AI's to write, "Write titles for untitled pins" (21.7) is on, and the pin is not a link with neither text nor picture. Each step replaces the last: (1) a title made on the device, at once; (2) Apple Intelligence's (20.3); (3) the cloud model's (20.4), never for a video named from its words †. A title that only repeats the person's own words (every meaningful word is among their tags, board names and photo-file keywords) is never written automatically. Text pins and links with text are named from their first lines, then by Apple Intelligence from the text; a video with words † from its best-scoring tags (never a line of speech: the first line of a talk is a greeting), then by Apple Intelligence from the spoken words. A pass keeps one Undo; a title typed meanwhile stays.

**The on-device title** needs neither Apple Intelligence nor the internet. A text-heavy picture (a label such as text, document, screenshot, menu, sign or receipt above 30%, or 12 or more words read) is named by its first read line (3+ characters, cut at a word to about 50 characters, with "…"). Otherwise by up to two recognised labels, capitalised and joined with " · " ("Golden Retriever · Beach"), skipping vague labels (outdoor, indoor, object, person, people, photo, image, portrait, gray, black…) and the person's own words; the second joins only at 40% or more. With nothing recognised, the person's tags, keywords and first board name stand in. Text pins and links take the first of their first five non-empty lines that does not only repeat the person's words (Markdown marks, "[words](address)" and bare addresses are cleaned out). Apple Intelligence and cloud titles are 2–6 words without quotes, a "Title:" label or a final full stop; over 80 characters or several lines is refused. A hidden pin's hidden board names are never part of a title or sent anywhere.

**"Written by AI" and Undo** (pin page, 10.3). Under the title, the caption "Written by AI" with icon `sparkles` whenever the AI wrote it; if it replaced an earlier title and the pin still has exactly that title, an **Undo** button (icon `arrow.uturn.backward`) and the grey caption was “‹previous title›”. Undo restores the previous title with its author; editing the title removes it; an untitled pin's first title cannot be undone.

**"Suggest a title"** is a round `sparkles` button beside the title's pencil (44 × 44 pt, grey circle; not on an unsaved web result). A spinner replaces the icon; the AI looks first if it has not (waiting up to 10 seconds when the queue is looking now; the cloud model is asked too when on); it writes a title different from the current one, whoever wrote it, and offers Undo. If nothing differs: the toast "No different title was found." (info icon), or for a link with no preview picture "There's nothing for the AI to go on: this link has no preview picture."

### 20.3 Apple Intelligence (when used, what it is told)

The device's own language model: it runs on the device (also in Offline mode), sees **words only** and never changes tags, notes, boards or a title the person wrote. It is available on iOS 26 or later when supported, switched on in the system and downloaded; only then does Settings show "Use Apple Intelligence" (21.7). Without it the app does the same jobs plainly. Turning the switch while a search shows re-runs the search.

**Job 1: titles** (new pins, naming runs, "Suggest a title"). It is asked for a natural title of 2–6 words that describes this item: use the person's words to understand it but never repeat them, trust the person over software, name from the item's own text first and the picture's labels second. A usable reply is one line of at most 80 characters; otherwise it is asked once more ("Reply with just the title, on one line, in 2 to 6 words."); a repeat of the current title or of the person's words is kept only as a last resort. It is told, as text: "Tags the person gave it: …", "Boards the person filed it under: …" (normal boards only), "The person's note: …", "Keywords stored in the file: …", "Caption stored in the file: …", "Detected by software: …", "Text visible in the picture: …"; for a link or video with text of its own, "The item's own text (the main thing to name it from): …" (the first 800 characters; a transcript † is cut to 1,500 and 800 shown); and, for another name, "Its title now is “…”. Write a different title."

**Job 2: related words for a search** (20.6): up to 6 single English words; the grey line "Apple Intelligence also looked for: word, word, word" (icon `sparkles`) then shows.

**Job 3: composing a web image search** (a pin page's "From the web", 10.4; a board's "Keep exploring", 14.4): one or two words, trusting board names ("most important") and the person's tags ("very important") far above recognised objects, colours, read text and camera data; the order of evidence and the fallback without it are in 19.3. The line shows icon `sparkles` when Apple Intelligence wrote the words and icon `tag` otherwise. Only these search words leave the device.

### 20.4 The cloud model (optional): consent sheet wording, keys, models, exactly what is sent and what comes back, hidden pins

A **cloud vision model** (Claude by Anthropic, or an OpenAI model) looks at the picture itself and returns much more specific tags, a real title, a one-line description and a short web-search hint. PinBoard has no account or server of its own; the person's own key pays the provider. The rows are in 21.7.

**Really used only when** Offline mode is off, "Use a cloud vision model" is on, the consent sheet was agreed to **for the chosen provider** † and a key is filled in (switch on with no key: nothing is sent, no error). Offline mode removes the "Cloud AI (optional)" section; the choices return when it goes off. The key lives in the device's secure keychain, never in the library, an export or a back-up, and goes only to its provider.

**The consent sheet †** (build 16, App Review guideline 5.1.2(i): say by name where pictures go, and ask first). It names one company, the provider being agreed to. It opens when the switch is turned on without consent for the chosen provider, and when the other provider is picked under "Provider" while the switch is on; a full-height sheet with inline title "Cloud AI", and nothing changes until "I understand — turn it on" is tapped. Texts below for Anthropic; for OpenAI "Anthropic" reads "OpenAI", "the company behind Claude" reads "the company behind ChatGPT" and the address is "api.openai.com":
- A cloud icon and the heading "Send pictures to Anthropic?" / "Send pictures to OpenAI?" (title3, semibold); then "With this on, every new image (and any you re-run) is sent to Anthropic (the company behind Claude), at api.anthropic.com, using your own API key. That is the trade for much better tags and titles."
- Six bullets with small filled dots:
  1. "Sent: a copy of the image, shrunk to at most 1024 pixels, with all metadata (location, camera, dates) removed."
  2. "Sent: the names of the boards the image is on and the tags you gave it, so the title and the suggested web search fit your own words."
  3. "Sent: for a link, the text read from its page (up to 1,500 characters), together with its preview picture, so the title and tags fit what the page says."
  4. "Hidden pins are not sent, unless you turn on “Include hidden pins in AI” — and even then the names of hidden boards never are." (build 17 †)
  5. "Never sent: your notes, your location, other images."
  6. "The provider bills your key per image — usually a fraction of a cent. PinBoard has no account of its own and receives nothing."
- In subheadline: "What Anthropic does with what it receives is governed by its privacy policy, not by PinBoard." and under it the link "Read Anthropic's privacy policy" (https://www.anthropic.com/legal/privacy; for OpenAI "Read OpenAI's privacy policy", https://openai.com/policies/privacy-policy/).
- Small grey line "You can turn this off at any time; images already tagged keep their tags. Choosing the other provider later asks you again."; a large prominent button "I understand — turn it on" and a plain "Not now" (closes; nothing changes).
- **Agreeing** records consent for that provider only and by name, makes it the chosen provider and turns the switch on. The consent is stored per profile, as the provider's name (setting "cloudConsentProvider"; like the other Cloud AI settings it stays on this device and does not travel with iCloud settings sync). **Changing provider:** picking the other one under "Provider" while it has no consent opens the sheet for it; the choice changes only when it is agreed to ("Not now" leaves the old provider). Going back to a provider agreed to earlier needs no sheet only while that is still the stored one: only one provider's consent is kept at a time, so switching back and forth asks each time.
- **After the update to build 16:** the old yes/no consent ("cloudConsentGiven", which named no company) is not carried over. Anyone who had Cloud AI on sees the switch Off (Settings search says "Off" too) and nothing is sent until they turn it on again and agree to the new sheet; their key, provider and model are kept.

**When a request is made.** Once for every pin with a picture, right after its on-device look (40 new photos make 40 requests), and not again until the AI looks again (20.1); once more for each picture in a naming run (20.5); in "Suggest a title" only for a pin not yet looked at; for an unsaved web result, the picture only (no boards, no tags). Never for text pins, links without a preview picture, or pins looked at before the switch was turned on.

**What is sent** is what the sheet lists: the picture as a plain JPEG at most 1,024 px on its long side, the names of the pin's boards (never a hidden board's), the person's tags and, for a link, the first 1,500 characters of its page text on one line, presented as the page's words, not as instructions. **Hidden pins (build 17 †):** by default nothing of a hidden pin — picture, title, tags, page text — is sent (20.11). With "Include hidden pins in AI" on, hidden pins go like any other pin's (never a hidden board's name). One check (`LibraryStore.cloudMaySee` = Cloud AI active and `aiMaySee`) is asked at the moment of sending, with the pin as it is then, on every path: the AI queue's tagging and naming, "Name with AI"/"Rename all" runs (the question's request count leaves hidden pins out), naming a single pin, Hidden's "Re-run AI tags", and a web result from a hidden feed. So a pin hidden after it was queued is not sent. Never sent: notes, location, other pictures, a photo file's keywords and caption, text read on the device, the title, and anything said in a video † (a video sends its poster only).

**What comes back and what the app does with it:** 8–15 specific lower-case tags (one to three words, confidence 0–1, the person's tags included, never contradicted), a 2–6-word title, a one-sentence description (at most 25 words) and a one-or-two-word web search.
- Tags come first, then the device's tags the cloud did not mention at 80% of their confidence (24 at most); they replace the old AI tags, never the person's.
- The title is used only in a naming pass for a title the AI may write, after the on-device and Apple Intelligence ones (it replaces them); never when it only repeats the person's words, never for a video named from its words †.
- The description is kept for pictures and videos (small grey text under the title; searchable, 20.6), never for a link. The search hint becomes the pin's first "From the web" search (20.3).

**When it fails.** The pin keeps its on-device tags and title, and a grey error line (icon `exclamationmark.triangle`, footnote) in Settings › AI stays until a later request succeeds: "Offline mode is on, so the cloud model wasn't contacted." · "No API key for the cloud model. Add one in Settings." · "The cloud model replied with an error (CODE). TEXT" (the first 300 characters of the reply, the key shown as "•••") · "The cloud model's reply could not be read." · "The image could not be prepared for the cloud model." A request waits at most 60 seconds. After 5 failures in a row the queue stops asking for that run and the line gains " — paused until the next run."; a naming run finishes the rest on the device and its line ends " — the rest of this renaming is done on this device."

### 20.5 Naming runs ("AI sorting → Name…") and "Undo last AI naming"

The menu, its items and every dialog and end-of-run message are in 15.2; these are the rules behind them.
1. **Two kinds.** "Name with AI (keeps your names)" renames the pins whose title the AI may write (empty, or exactly what the AI last wrote; 2.2). "Rename all with AI…" renames every pin, the person's titles too. A link with no preview picture is never renamed: there is nothing to go on. One pin (its own menu, a selection of one, a board page showing one pin) is named at once with no question, and is not recorded as a run (its Undo is on its page, 20.2).
2. **The question** (several pins) says how many pins will change, that a pin keeps its name when nothing better is found, and, with the cloud model in use, how many pictures it will look at again ("N request(s)"). With nothing to rename only "Cancel" is offered, with the reason. A links-only or all-yours selection is the usual cause.
3. **While it runs.** One run at a time, one pin at a time in the background; the app stays usable and both naming items are dimmed on both sides. Each pin is looked at first if needed; with the cloud model and a picture it is asked again for a title; it then gets the best title that differs from its own, in this order: the cloud's, Apple Intelligence's, the on-device alternatives, a title that only repeats the person's words last; else it keeps its name. A pin the person renames meanwhile (unless "Rename all"), deletes or moves to the other side is left alone.
4. **What shows.** Normal side: the pill "AI is renaming pins… N of M" (lowest priority), the menu line "Renaming… N of M" with "Stop renaming" (icon `stop.circle`), and in Settings › AI a row with a spinner, "Renaming… N of M" and a borderless "Stop". A run on hidden pins shows progress only in Hidden's own menu and ends with an alert there. "Stop renaming" keeps the names given (one undoable run) and shows no message; changing profile stops the run.
5. **Undo.** Each side of each profile remembers its last run that renamed something (kept across launches, forgotten when the library is cleared; a run that only gave first names to untitled pins is not kept). "Undo last AI naming (N)" puts back every name that is still exactly what the run wrote — Recently Deleted pins too — with its previous title and author, leaves names changed since, says how many were put back (or that none were) and forgets the run.

### 20.6 Search by meaning: what a query matches and in what order

The Search tab is 18; how a typed query is split into words, compared with a pin's words, weighted by field (title, tags, note, text read in the picture…), scored and sorted is stated in 18.2. What the AI adds to it:
- **Meaning, not only spelling.** When two words do not match by spelling, the device's English word meanings compare them and give 0.85 (very close), about 0.7 (fairly close) or about 0.4 (loosely related): "puppy" finds a pin tagged "dog". Colour tags, a link's site name and the full text read in a picture match by spelling only.
- **What the AI wrote is searchable:** an AI tag counts 0.50 + 0.50 × its confidence (a 90% tag 0.95, a 40% tag 0.70; each word of a multi-word AI tag 90% of that), the cloud model's description 0.80, key words read in the picture 0.85, a video's transcript † (in its note, first 4,000 characters) 0.85. AI tags never count for the exact-phrase boost.
- **Related words** (Apple Intelligence, 20.3). The typed words are searched first and shown at once; then up to 6 related words are added and the list is replaced. A pin whose best related match reaches 0.60 scores 0.55 × that match when that beats its own score (about 0.47 at most) and the word joins its "why it matched" caption; related words never push a strong match down. Smart boards never use them.

### 20.7 Board suggestions, "Sort into boards" (how boards are chosen, "why" on the pin page), "Start here"

The AI never files a pin by itself: it suggests, and files only when asked ("Sort into boards", a tapped suggestion, "Create N boards"). Each side (normal, hidden) looks only at its own pins and boards.

**How a board is scored for a pin** (0–1, shown as a percent): 0.55 × name fit + 0.25 × tag fit + 0.35 × look-alike fit, capped at 1.
- **Name fit:** the board's name words (those of the boards it sits in count 60%) against the pin's words by the word similarity of 18.2 (item 2). The pin's words weigh: your tags 1.0, photo-file keywords 0.8, AI tags 0.5 + 0.5 × confidence, words read in the picture 0.6, a title the AI did not write 0.9 (an AI-written title cannot vouch for itself). It works for an empty board.
- **Tag fit:** how much the pin's eight strongest words appear among the pins already on the board (not its sub-boards' pins): a word on two thirds of them counts fully, on a third half.
- **Look-alike fit:** the average similarity of its three closest look-alikes on the board, measured against the whole library; none for a pin without a fingerprint.
- The reason follows the largest weighted part: "board name matches its tags", "looks like pins already here" or "shares tags with pins already here"; the evidence is up to four words, or "N look-alike pin(s)".

**On a pin's page** (10.3). Suggestions need a score of 0.20 or more and leave out boards the pin is directly on. Under the caption "AI suggestions — tap to add" (unsaved web result: "AI suggestions — tap to save there" / "… tap to save there too") sit at most three buttons, best first: icon `sparkles`, the board's name, its score in grey ("Beach 62%") and "because: beach, sea" beneath. Tapping one files the pin there and makes that board "Last used". A pin already on boards shows a plain button "Suggest other boards" first. Without suggestions the page says "The AI is still looking at this pin…", "Create a board and the AI will start suggesting where pins belong." (no board on that side) or "No board stands out for this pin yet."

**The reason line.** Under its board chips a pin the AI filed shows icon `wand.and.stars` and "Auto-sort: beach, sea" / "Auto-sort: 2 look-alike pins" or, with no words, "Auto-sort: board name matches its tags" / "Auto-sort: looks like pins already here" / "Auto-sort: shares tags with pins already here"; "Start here" writes "Start here: tagged “beach”". It goes when the pin is filed by hand (Add, Move, a tapped suggestion) or leaves its last board.

**"Sort into boards"** (menu: 15.2)
1. Each pin goes to its single best board on its own side that it is not already on, only at a score of 0.40 or more (twice the page's bar), in addition to its other boards, with the reason line; the nesting rule of 2.4 applies.
2. The whole-side item takes only Unsorted pins (hidden side: hidden pins on no hidden board); a board's page, a selection or a pin's menu take every pin given.
3. One sort at a time; the pill reads "Sorting N of M…" (no pill and no count when any pin is hidden); changing profile ends it quietly.
4. Result: when something moved, a floating note (checkmark, about 3.5 seconds) "Put N pins on suggested boards." (or "Put N of M pins on suggested boards."); when nothing moved, an alert with "OK" saying why (no confident match, no board yet, no Unsorted pin). Exact texts: 15.2. While pins are Unsorted the Boards tab says how to sort them (13.1).

**The board picker's "Suggested" row** (14.5) uses the same score: up to twelve of the pins being added (spread over the newest-first list) are scored, boards all of them are on are ignored, and the best board is offered at an average of 0.25 or more, with the same reason texts as the caption.

**"More like this"** (10.4) ranks the same side's pins by 0.6 × look-alike + 0.4 × shared tags (your tags 1.0, AI tags 0.4 + 0.6 × confidence, photo-file keywords 0.8, picture words 0.5); a pin shows at 0.12 or more; 40 at first, "Show more" adds 40.

**"Start here" ideas** (the card: 5.4). Only normal pins count; each offers its own tags and its AI tags that are at least 45% sure and not vague. A tag becomes a proposal when at least 3 pins carry it and no board already has that name; most pins first, then alphabetical, four at most; each board is named in title case ("golden retriever" → "Golden Retriever") and made top-level. Creating files each pin with "Start here: tagged “beach”".

### 20.8 Duplicates: how look-alikes are found; the questions; the Possible duplicates screen (summary; detail 23.4)

A picture that looks the same as another pin's marks the newer copy; nothing is deleted, hidden or merged without asking (the answers: 10.6; the screen: 23.4).
- **Which pins:** anything with a picture the AI looked at (photos, a video's poster, a link's preview picture); never text pins or links without a picture. A turned, flipped or cropped picture, a new thumbnail, or a link pointed at another page loses its mark and is compared afresh.
- **A look-alike:** the 64-point signatures differ in at most 6 points and the width-to-height ratios are alike (one between 0.85 and 1.18 times the other); a resized, recompressed or lightly edited copy matches, another picture of the same scene does not. The closest is the twin. Only the newer copy (by date added) is marked; the older stays clean.
- **Sides:** a pair never crosses the hidden line; hiding or unhiding re-checks each side 0.3 seconds later. "Keep both" is remembered per pair.
- **Where it shows:** a "Duplicate?" badge (icon `square.on.square`; icon alone on narrow cards) after "Tagging…" on the newer photo or video card; on the newer pin's page under "Details", "Looks like a duplicate" with the pair card; on an unsaved web result, "Looks like a duplicate of “‹title›” in your library" ("another pin" without a title) with an "Ignore" button; the Search "Duplicates" chip (18.1); the Possible duplicates screen.
- **Re-checks** also run after a folder import, after pins return from Recently Deleted and after "Reset and re-check everything", in small batches; not after a restore or an iCloud sync (marks travel with the copy). Signatures never leave the device.

### 20.9 Video upkeep: length, sound, black thumbnails replaced

A quiet background job fills in what an older video does not know yet (a video added today arrives with its length, its sound answer and a poster that is not black); it also serves videos arriving in a restored copy or from iCloud. It runs 8 seconds after launch, after a profile switch, a restore or a sync that brought something, and 2 seconds after an import; it waits while the AI is busy and does one video at a time.
- **Length:** the card's badge reads "m:ss" instead of "Video". **Sound:** the speaker button appears when the video has sound (a card also checks its own sound when it first shows). Search's length and sound filters then find the video. None of this is an edit: the change date does not move.
- **Black poster, checked once.** A poster with more than 70% very dark pixels (or one that cannot be read) is replaced by the first of several test frames (at 0.5 seconds, then 50%, 40%, 60%, 30%, 70%, 20% and 80% of the length) that is not mostly black, else the least dark; the new poster is made full size (at most 2,048 px) and kept only if it is less dark than the old one. The AI then looks again ("Tagging…") and the pin's fingerprint, tags and duplicate mark are dropped. The pin menu's "Thumbnail ▸" choices (7.7) are the person's own and separate.

### 20.10 Transcripts †: when a video is listened to, where the words go (the note), status lines, the first-time download, Offline mode, "Transcribe existing videos", what the AI does with the words, limits

PinBoard listens to a video's sound on the device and writes down the words, by itself, in the background, one video at a time at low priority. The words go into the pin's note and the AI then names and tags the video from them as it does a link from its text. Nothing is sent anywhere. The rows: 21.4.

**What the person sees.** No badge, toast or button for a finished transcript: the note holds the words (pin page; Quick Look's "Note"); the video gets new tags and, when the AI may write its title, a new name ("Tagging…" shows again); Search finds words said in it; Settings › Videos › "Transcripts" shows progress and why a run stopped. A video with no sound track is never listened to; one whose speech is too short, or in a language the device cannot read, stays as it was.

**Which videos, and when.** A video not in Recently Deleted, with a sound track found by the check of 20.9, no words yet, its file present and no conversion going. Hidden videos come only after every normal one and silently (no line, pill, count or closing line). A video that gave no words, failed, ran out of time or was in an unsupported language is retried only by "Transcribe existing videos". A run starts 12 seconds after launch, an import, a found sound track, an iCloud sync or a restore; 5 seconds after a conversion run or video upkeep; 2 seconds after the switch or Offline mode is turned on; at once from the button. It waits while the AI works or a video converts, rests a quarter-second between videos, takes normal videos newest first, and gives each video 4 × its length (at least 15 minutes, plus 30 while language files may download, at most 12 hours of running time). It ends when nothing is left, when the switch goes off (after the video in hand) or when another profile opens or the library is cleared. Only the device's own language is used.

**The line under the switch** (footnote, grey): "Transcribing 2 of 5…" (done + 1 of done + waiting normal videos); "Preparing the speech recogniser…" while the language files download (first time only); "No videos are waiting to be written down." for about 4 seconds after the button finds nothing; or, after a run that ended for a reason, a closing line that stays until the next run:

| Outcome | The video | Line left | The run |
|---|---|---|---|
| Words (at least 3, with letters) | into the note; change date moves; AI looks again | none | goes on |
| No speech | marked listened to; nothing written | none | goes on |
| Language not supported | marked | "Speech in English isn't supported on this iPad." ("iPhone" on an iPhone; the device language's name) | goes on; one run marks every waiting video |
| Speech files missing, Offline mode on | waits | "The speech files for English have to be downloaded first. Turn off Offline mode to let that happen." | stops; Offline mode off restarts it |
| Speech files could not be downloaded | waits | "The speech files for English could not be downloaded. Check the internet connection and try again." | stops |
| Not allowed (iOS older than 26) | waits | "Speech recognition isn't available to PinBoard on this iPad. Allow it in Settings › Privacy & Security › Speech Recognition." | stops until the next launch |
| Needs a newer system | waits | "Writing down speech needs iOS 26 or later on this iPad." | stops until the next launch |
| Could not be listened to | marked | at the run's end: "1 video couldn't be listened to — Transcribe existing videos tries again." / "3 videos couldn't be listened to — …" | goes on |

A reason line wins over the count; a hidden video leaves no line. Only a run the button started (or took over) shows "Transcribing 2 of 5…" on the Pins tab pill (icon `sparkles`, a small spinner), and only while the pill is free.

**The words in the note.** Pieces are joined and white space collapsed; fewer than 3 words (counted by the language's own rules) or no letter: nothing is written. A paragraph ends at the first sentence end (". ", "! ", "? ", "… ", "。", "！", "？") after 600 characters, paragraphs are separated by a blank line, and a stretch over 1,200 characters without a sentence end is cut at a space about every 600. The longest transcript is 20,000 characters, cut at a word end with "…". An empty note becomes the words; a note with the person's text keeps it, then a blank line, a line "Transcript:" and the words; the words are never added twice. There is no separate transcript view or hide switch, and cards never show a note. The change date moves, so the words travel with iCloud.

**The person's edits.** The words may be edited, shortened or deleted like any note text. The AI treats the text before and after the "Transcript:" block as the person's own words; if the spoken words are changed by hand, the whole note counts as theirs. Cutting the words out undoes nothing: they stay with the video (the AI keeps using them), nothing puts them back, the video is not listened to again and Search no longer finds them. Words that arrive while the "Note" sheet is open do not change it under the person's hands: on Save the person's text stays first and the words are added under "Transcript:", unless they are already in the note. A merged duplicate (10.6) does not write the words twice.

**What the AI does with them.** The key words of speech (80% each, up to 8, none twice, from the first 4,000 characters, with small words and speech fillers such as "um", "gonna", "you know", "okay", "subscribe" dropped; English only) lead the AI tags. Title: 20.2; Apple Intelligence is shown the first 800 of the first 1,500 characters; the person's own words are tags, board names, file keywords and the note without the transcript block. The cloud model never gets the words and its title is never used for such a video (20.4). "Re-run AI tags" rebuilds the tags from the words and the poster; the words stay.

**Elsewhere.** Search: the first 4,000 characters word by word at 0.85; the exact-phrase check sees all (18.2). Export: library data keeps every word, a video's poster file carries the note cut at 8,000 characters; a re-import brings the words back. iCloud: a video with words travels, the "listened to" mark does not, so a video arriving without words is listened to on this device 12 seconds after the sync. Each profile has its own words; opening another stops the run at once.

**Privacy.** The sound is read from the library's own file; nothing is uploaded. The only internet use is the first download of the speech files (iOS 26 or later), which Offline mode switches off. iOS 26 or later asks for no permission; an older iOS asks once, through the system's own question.

### 20.11 Hidden pins and the AI † (build 17)

The switch "Include hidden pins in AI" (Settings › Privacy & Hidden, and the same value on AI › On-device AI; off by default; per profile, not synced) decides whether any AI looks at hidden pins. One check, `LibraryStore.aiMaySee(pin)`, is asked at the moment the AI would look, with the pin as it is then.

**Off — what a hidden pin does not get:**
- Vision's recognition: no tags for things and scenes, no reading of text in the picture (OCR), no people count, no cats and dogs.
- Key words of a text pin's or link's text as tags (they need the language model's word list).
- AI titles: the quick on-device title from tags, Apple Intelligence's title, "Suggest a title" (the sparkles button is not shown), "Name with AI"/"Rename all" (hidden pins are left out; Hidden's ⋯ menu shows "AI sorting" only with the switch on).
- Apple Intelligence's web search words for a hidden pin's or hidden board's "From the web", and its extra search words in Hidden's search.
- Search by meaning inside Hidden, and meaning-matching in board suggestions for a hidden pin: words match as written and by their dictionary form only (the word map is a language model).
- Speech transcripts of hidden videos (speech recognition is a model too); a video hidden while it is listened to keeps no words and waits.
- The cloud model (20.4).
- A web result opened from a hidden feed gets the same treatment.

**Kept regardless (fixed, rule-based code):** colours, the perceptual hash, the duplicate and look-alike check, the board scoring's rules, text search over what the person typed (titles, notes, own tags, link text), link reading, video upkeep (length, poster, sound check), and the picture's fingerprint. *Owner's decision:* the fingerprint (`VNGenerateImageFeaturePrintRequest`) is made by one of Vision's models; it is kept for hidden pins because the duplicate check and "More like this" need it — hidden pictures are still compared on the device, and the footer says so. Also flagged: turning words into their dictionary form uses Apple's language tagger (`NLTagger`), kept as part of plain text search.

**Already-made AI results stay** until the person removes them: tags, text and titles the AI made before a pin was hidden (or before the switch existed) are kept. Settings › Privacy & Hidden › "Remove AI tags from hidden pins" (21.9) takes them out in one go, after asking.

**How it works:** a hidden pin waiting for the AI gets only the fixed checks; it is then marked `aiSkipped` (stored with the pin, so it survives a restart and travels with sync). Whenever the AI queue starts, and after every save, pins marked so that the AI may see now — un-hidden by any path, or the switch turned on — wait for the AI's look again (`wakePinsTheAIMaySeeNow`); a video among them may be listened to. A pin hidden while it is queued or being looked at drops out: what the AI found is thrown away before it is written, and no naming or cloud request follows.

## 21. Settings — every page, row by row (label · choices · default · footer)

Everything saves the moment it changes; there is no Save or Cancel. Footers are quoted exactly. Every row's name, its page and section, the section footers and the search's other words come from one list, `SettingsCatalog.swift` (21.2); the "Settings › …" paths the app writes elsewhere are made from it too. Build 15 regrouped the pages (owner's request: easier to find things; every setting the app has is now also in Settings) — nothing stored changed, only where it is shown. Settings belongs to the normal side: its counts, lists and commands never include hidden pins.

### 21.1 The Settings list (search, rows, icons, order, Done)

- A sheet that slides up over the current tab; inline title "Settings"; "Done" (top right) closes it and exists on the list only, every page has a Back button. While an export is being made Done is dimmed and swiping the sheet down is off.
- Opened from the ⋯ menu's "Settings…" (icon `gearshape`) on every tab (Pins, Boards, Explore, Search), on pin, board and smart-board pages (left out of a page opened from inside Settings), and from Hidden's ⋯ menu ("Settings…", last, under "Lock now"; 4.4). Some screens open it straight on a page: the back-up reminder's "Export now" lands on Library and the export starts about 0.9 seconds later; Back then goes to Library, then to the list. A screen can also open it at a single row (`SettingsView(row:)`), which works like a search result (21.2).
- Import questions and results, the AI-sorting dialogs, the export's share sheet, the "Save the folder to Files" picker and the Cloud AI consent sheet appear over Settings, not over the tabs behind it.
- At the top, pinned above the list: the search field "Search settings" (21.2).

| Group | Row | Icon | Right-hand text |
|---|---|---|---|
| 1 | "Appearance" | `paintbrush` | |
| 1 | "Pins & boards" | `square.grid.2x2` | |
| 1 | "Videos" | `play.rectangle` | |
| 1 | "Links" | `link` | |
| 2 | "AI" | `sparkles` | |
| 2 | "Explore & web search" | `globe` | |
| 3 | "Privacy & Hidden" | `lock.shield` | "Offline" while Offline mode is on |
| 3 | "iCloud & storage" | `icloud` | |
| 4 | "Library" | `books.vertical` | the profile in use (nothing if its name is empty) |
| 4 | "About" | `info.circle` | |

Inside Library: "Profiles" (`person.2`), "Recently Deleted" (`trash`), "Possible duplicates" (`square.on.square`), "Your tags" (`tag`), "Recover library" (`clock.arrow.circlepath`).

**Before build 15** the list was Appearance, Pins & boards, Videos, Links · AI, Storage, Network & privacy · Library, Typing, Safety · About. Where things went: Network & privacy's "Explore the web" and Links' "Web searches" → Explore & web search; Offline mode, the Privacy lines and Safety → Privacy & Hidden; the iCloud group and Storage → iCloud & storage; "Images per row" → Appearance; Typing → Pins & boards › Getting around; "Show key" (Links) is now "Show keys", like the other two. New in Settings: "Sort boards" and the "Order of pins" choices (also in the ⋯ menus, the same settings), a Widgets note, and "Video quality" on Videos too (the same setting as on iCloud & storage).

**Offline mode never hides a row any more.** Rows that need the internet (Links' previews and reading, Cloud AI, the Explore & web search page, iCloud sync) are dimmed, and the first group of each such page starts with the grey line "Off while Offline mode is on (Settings › Privacy & Hidden › Network)." (icon `wifi.slash`). Clean links works offline and is never dimmed.

### 21.2 Settings search

- **The field:** a rounded box (12 pt continuous corners, the grouped-row background) pinned at the top of the list, 16 pt from the sides: `magnifyingglass`, the field "Search settings" (no auto-capitals or correction, return key "Search"; VoiceOver "Search settings"), and an `xmark.circle.fill` "Clear search" while something is typed.
- **While something is typed** the groups of pages are replaced by one group of results. Each result: the row's name; under it, grey footnote, where it is ("iCloud & storage › iCloud"; the page alone when the section has no header or is named like the page); for a row shown only sometimes, a caption saying when ("Shown when “Use a cloud vision model” is on", "Shown when Image source is Pexels", "Shown while “Sync with iCloud Drive” is on", "Shown while there are recent searches"); and at the right, grey, the value now — "On"/"Off" for a switch, the choice for a menu ("Shuffled", "1080p", "Custom order", "Red", "15 pt"…). Nothing found: "No settings match “xyz”." and, grey, "Try another word, like “sync” or “colour”."
- **A result opens its page** (the list's stack is replaced by that page) and the page scrolls the row to its middle, then lights it: the row's background gets the accent colour at 18 % for about 1.6 seconds, then fades out over 0.8 s. A row that is only shown sometimes opens at the row that shows it (the Cloud AI switch, Image source, Sync with iCloud Drive, Automatically load web suggestions). Two entries say there is no setting and open where it is explained: "Sound" ("No setting: tap the speaker on a video. Sound stays on until you turn it off or close PinBoard.", opens Videos) and "Playback speed" ("No setting: in Quick Look, ⋯ › Speed, or touch and hold a video for 2×.", opens Player). A third † (build 16), "Videos from TikTok, Instagram and others" (Links › Reading links), says "Kept as a link with its picture. Most apps let you download a video inside the app itself. If you'd like the video in PinBoard, download it there, then save it to PinBoard (from Photos or with the share sheet)." and opens Links at "Read links fully"; its other words are "video", "download", "save video", "reel", "reels", "tiktok", "instagram", "reddit", "pinterest", "x", "twitter".
- The Cloud AI switch's value reads "On" only with consent for the chosen provider (20.4) †; right after the update to build 16 it reads "Off".
- **What matches** (`SettingsCatalog.search`): capitals and accents don't count; every word typed must be found — as the start of a word — in the row's name, its other words, its page and section, or its section's footer. Order: the name starts with what was typed; then every word is a whole word of the name; the start of a word of the name; one of its other words; its page or section; ties keep the order of the pages. Rows found only through a footer are shown only when nothing else matched. Nothing at all: one wrong letter is forgiven in words of five letters or more, in names and other words only ("transcibe", "apple inteligence").
- **Other words** (lower case, a few per row) cover other ways of saying it and speech-to-text spellings, e.g. "sync", "sink", "sinc", "synch", "i cloud" → the iCloud rows; "dark", "night" → Theme; "colour", "tint" → the colour rows; "columns" → Images per row; "face id", "password", "lock" → the Hidden lock; "airplane", "wifi", "internet" → Offline mode; "key", "api", "token" → every key row; "shuffle", "random", "sort" → the order rows; "trash", "bin" → Recently Deleted; "chatgpt", "openai", "claude" → Cloud AI; "captions", "subtitles" → Transcribe speech in videos; "tiktok", "reels", "save video" → Videos from TikTok, Instagram and others †. ("keyboard", "typing", "playgrounds" found "Use PinBoard's own keyboard", which is gone since build 16.)
- Settings search looks only through Settings' own rows: never pins, boards or anything hidden.

### 21.3 Appearance

**Group "Appearance"**

| Row | Choices | Default |
|---|---|---|
| "Theme" | segmented "System" · "Light" · "Dark" (Light and Dark apply to the whole app, sheets included; Quick Look, the picture editor, the "Show original" viewer and the YouTube player sheet are always dark) | System |
| "Accent color" | a heading, then a horizontally scrolling row (no indicator) of 11 circles, 34 pt in 44 × 44 pt targets, 2 pt apart: Red, Coral, Orange, Gold, Green, Teal, Blue, Indigo, Purple, Pink, Graphite; the chosen one shows a bold check; VoiceOver says the colour name | Red |
| "Any other color" | the system colour picker, no opacity slider; picking saves and selects it, and a filled check-circle in the accent colour shows at the row's right; the first custom colour is #E6002B | none |

The accent tints the whole app at once. Colours as chosen in light mode: Red #E60024, Coral #FF665C, Orange #FF8C1A, Gold #D9A61A, Green #33A85C, Teal #1A9EA8, Blue #1F7AF2, Indigo #5957D6, Purple #9E4DD9, Pink #F24D9E, Graphite #595961. Dark mode brightens a colour 35% of the way to full brightness, keeps 90% of its saturation and never lets it fall under 3 : 1 against #2C2C2E. With Increase Contrast, a colour is darkened (light mode) or lightened (dark mode) until text in it reaches 4.5 : 1 against #F2F2F7 or #2C2C2E. The picker always shows the colour exactly as picked.

**Group without a header: "App icon"** †

| Row | Choices | Default |
|---|---|---|
| "App icon" | a heading, then a horizontally scrolling row (no indicator) of 8 icons, 62 pt with continuous corners of radius 14, each with its name in caption2 under it: "Mood board", "Four kinds", "Pinned photo", "Push-pin", "Folded note", "Card stack", "Pin P", "Snapshot". The one in use has a 2.5 pt ring in the accent colour, and its name is in the primary colour, not grey. VoiceOver says the name, and "selected" for the one in use. A tap changes the Home Screen icon at once, and iOS shows its own short alert saying so. If it fails, the red footnote "The icon couldn't be changed: ‹reason›" appears. A build without the other icons (Swift Playgrounds) shows "This copy of PinBoard has only its main icon. The App Store version lets you choose another." instead of the icons | Mood board |

Footer: "The icon on this device's Home Screen. iOS shows its light, dark or tinted look to match the Home Screen. The choice belongs to this iPhone or iPad: it stays the same in every profile and isn't synced to your other devices." iOS keeps the choice itself (`setAlternateIconName`), so nothing is saved in the settings or the profile. Every icon has a light, a dark and a tinted look, plus iOS 26's clear look, made from an Icon Composer file. Search finds the row by "icon", "logo", "home screen" and the like. The icons are drawn by `AppStore/icon/options.swift`.

**Group "Grid"** (moved here from Pins & boards in build 15)

| Row | Choices | Default |
|---|---|---|
| "Images per row" | menu: Automatic, 2, 3, 4, 5, 6, 7, 8 (stays on this device; doesn't travel with settings sync) | Automatic |

Footer: "Large numbers only take effect on wide screens; columns never get narrower than about 88 points." Automatic means 5 columns over 1,400 pt of width, 4 over 1,000, 3 over 640, otherwise 2; a fixed number gives way to the width (never below 2 columns).

**Group "Text pins"**

| Row | Choices | Default |
|---|---|---|
| "Typeface" | menu: Standard · Serif · Rounded · Monospaced | Standard |
| "Size on boards: 15 pt" (the number is in the label) | stepper 11–28 pt, step 1 | 15 |
| "Size on the pin's page: 20 pt" | stepper 13–40 pt | 20 |
| "Lines shown on boards: 6" | stepper 2–30 | 6 |
| "Show the title on the card" | switch | on |
| "Use the accent color for text" | switch | off |
| "Custom text color" | colour picker, no opacity; once set, a small bordered "Reset" beside it returns to the normal text colour | none |

Colour precedence: custom colour, else the accent (when its switch is on), else the normal text colour. A live preview card (at most 320 pt wide) follows the rows: title "A note to self", text "Text pins look like this. The typeface, size, colour and how many lines a card shows are all yours to change here." Footer: "Text pins sit in the grid like any other pin. Add one from the + menu on the Pins tab or on a board. The sizes are for the standard text size: text pins grow and shrink with the text size chosen in the Settings app." (A card's title is drawn at 1.12 × the text size.)
### 21.4 Pins & boards

| Group | Row | Choices | Default |
|---|---|---|---|
| "Order" | "Sort boards" | menu: Custom order · Name (A–Z) · Recently edited · Recently added to (13.1; the same setting as ⋯ › "Sort boards") | Custom order |
| "Order" | "Order of pins on the Pins tab" | menu: Shuffled · Newest first · Oldest first (the same setting as the Pins ⋯ menu, 5.3) | Shuffled |
| "Order" | "Order of pins on board pages" | the same menu (one order for every board; the same setting as a board page's ⋯ › "Order of pins") | Shuffled |
| "Boards" | "Board pages include sub-board pins" | switch | on |
| "Sharing" † | "Choose a board when sharing" | switch (per profile; travels with iCloud settings sync) | on |
| "Widgets" | "Edit a widget on the Home Screen" (icon `rectangle.3.group`, grey; information only) | | |
| "Getting around" | "Swipe between tabs" | switch | on |

- "Order" footer: "The same choices as in the ⋯ menus: Sort boards on the Boards tab, in Hidden and on a board's page; Order of pins on the Pins tab and on a board's page (one order for every board). Changing one changes the other. Favorites always stay on top. A shuffled list is shuffled again when you pull it down." Choosing an order here goes through the same rule as the menus (choosing Shuffled after a date order shuffles afresh; 5.3). The pin orders stay on this device (they don't travel with settings sync; the owner chose to keep it so); Sort boards travels.
- "Boards" footer: "A board's page also shows the pins of its sub-boards, as if they were on the board itself. A pin you move into a sub-board counts as being on the boards above it already, and is never listed twice. Each board page can still switch this on or off for itself." (This is only the starting value of each page's own "Include pins from sub-boards" switch.)
- "Sharing" footer †: "When you share pictures, videos, links or text to PinBoard from another app, you choose the board and profile in the share sheet. Off: it saves straight away, to no board in the profile open here, and closes by itself. A picture or video that looks like one you already have is still asked about, so nothing is saved twice; the same link or text already in PinBoard is never saved again." (Quick save, 23.7. The share sheet is part of the Xcode/TestFlight build, Xcode/PinBoardShare.)
- "Widgets" footer: "PinBoard's widgets (Photo, Photo Grid and Quote) each show one board, or all of them. Choose the board on the widget itself: touch and hold it on the Home Screen and choose Edit Widget. For two widgets on the same board, give each its own Pick so they never show the same photo. Widgets never show hidden pins." On a Mac it adds: "On a Mac, add them from the widget gallery under PinBoard (this Mac's app), not under “From iPhone”: the iPhone's copies can't show your photos on a Mac. On the desktop, Control-click a widget and choose Edit to pick its board." and the row reads "Edit a widget on the desktop".
- "Getting around" footer †: "Swipe left or right on Pins, Boards, Explore or Search to move to the next tab. Inside a board or a pin, swiping works as usual."

**Gone in build 16 †:** the switch "Use PinBoard's own keyboard" (off by default) and the simple built-in keyboard it drew under text fields. It existed only because the iPad keyboard never appeared when the app ran inside Swift Playgrounds; in the real app the system keyboard always works. Every field now uses the system keyboard; the "Typing into" switches, the "Show keyboard" buttons and the `keyboard` buttons in search fields are gone with it. The stored setting is simply no longer read.

### 21.5 Videos

Four groups: "Videos", "Player", "Video quality", "Transcripts" †.

| Group | Row | Choices | Default |
|---|---|---|---|
| "Videos" | "Auto-play videos in grids" | switch | off |
| "Videos" | "Auto-play on a pin's page" | switch | off |
| "Player" | "Skip buttons jump" | menu: 5 seconds · 10 seconds · 15 seconds · 20 seconds · 30 seconds | 10 seconds |
| "Video quality" | "Video quality" | menu: Original · 4K · 1080p · 720p — the same setting as iCloud & storage › Video quality (21.10); name, choices and footer are the same in both places | 1080p |
| "Transcripts" † | "Transcribe speech in videos" | switch | on |
| "Transcripts" † | status line (see below) | | |
| "Transcripts" † | "Transcribe existing videos" | button | |

- "Videos" footer: "In grids, videos on screen play silently (a few at a time; the rest show a still frame); tap a card's speaker for sound. On a pin's page and in Quick Look, PinBoard's own player has a play button in the middle with skip buttons on either side, and along the bottom the time bar, sound, and on a pin's page a button that opens Quick Look (tap the video to show or hide them). Videos start over when they reach the end. Once you turn sound on it stays on for every video you open, until you turn it off. A video carries on where it stopped, wherever you open it next, until the app is closed. Auto-play on a pin's page: the video starts by itself and pauses when you scroll away. Off: press play."
- "Player" footer: "How far the buttons on either side of play jump back or forward. In Quick Look, touch and hold a video for a second to play it at double speed for as long as you hold; slide down while holding to keep 2× on, and do the same again to turn it off. The ⋯ menu there has other speeds." The skip buttons show the matching arrow for the chosen number.
- † The slow speeds in that ⋯ menu are new (list: 12.3); the rest of the two footers is not.
- "Video quality" footer (the same on iCloud & storage): "A video is added exactly as it is, at once; afterwards, in the background, those larger than the chosen size are converted so they take less room, and smaller ones are kept as they are. “Convert existing videos…” (iCloud & storage) does the videos already in your library."
- "Transcripts" † footer: "Words spoken in a video are written down on this device after the video is added, and put in the pin's note. Nothing is sent anywhere. The first time, the speech recogniser's language files are downloaded."
- The switch: turning it on starts waiting videos within about 2 seconds; turning it off stops automatic runs (a running one stops after its current video) and keeps the words already written. The status line (footnote, grey, one at a time, only when there is something to say) and the button's behaviour are in 20.10; "Transcribe existing videos" is dimmed only while a run's progress line shows.
### 21.6 Links

Groups top to bottom. With Offline mode on, the "Links" and "Reading links" groups are dimmed (not hidden) and the first starts with the offline line (21.1).

| Group | Row | Choices | Default |
|---|---|---|---|
| "Links" | "Fetch link previews" | switch | on |
| "Links" † | "Find a picture for links without one" | switch (dimmed with Offline mode or previews off) | off |
| "Reading links" | "Read links fully" | switch (dimmed while "Fetch link previews" is off) | on |
| | "YouTube API key" | secret field, placeholder "Optional" (VoiceOver says "YouTube API key"), no auto-capitals or correction, kept in the keychain | empty |
| | "Show keys" (was "Show key") | switch, shown only once a key exists | off |
| | "YouTube Terms of Service" and "Google Privacy Policy" † | one row of two links (footnote size, the first at the left, the second at the right), opening https://www.youtube.com/t/terms and https://policies.google.com/privacy; YouTube's developer policies ask an app using its Data API to link to both | |
| | "Read existing links (N)" | button; "Read existing links" when none wait | |
| "Clean links" | "Clean links" | switch | on |
| | "Clean existing links" | button | |

Footers
- "Links" (followed by the "Find a picture…" words in the same footer): "When a link is saved, its page is fetched once for the title and a preview picture, which are kept in your library. Off: the card shows the address only."
- "Find a picture…" †: "When a page has no picture of its own, PinBoard uses the first picture Explore's source finds for the link's title. It may not be a picture from that site. Links in Hidden are never searched for." With previews off it adds " Turn on “Fetch link previews” to use this."
- "Read links fully" †: "When you add a link, PinBoard reads the page: an article's text, writer and date; a Pinterest pin's picture and the page it links to; a YouTube video's title, channel and thumbnail from YouTube's own service — and its length, description and top comments with a YouTube Data API key (free from Google Cloud: enable “YouTube Data API v3”, then create an API key). YouTube videos play in YouTube's own player; nothing is downloaded from YouTube. A link straight to a picture or a video file (.mp4, .mov) becomes a picture or video pin. Posts on Reddit, TikTok, Instagram and X are read as far as each site shows them to a visitor without an account: the caption, who posted it and its picture. A video on these sites, on Pinterest or inside any other web page is kept as a link with its picture and title; PinBoard doesn't download it. Pages behind a login (Facebook, private accounts) can't be read: such a link is added as a plain link, never as the login page. Most apps let you download a video inside the app itself. If you'd like the video in PinBoard, download it there, then save it to PinBoard (from Photos or with the share sheet). The key is sent only to YouTube's own service, under YouTube's Terms of Service and Google's Privacy Policy (the links above). “Read existing links” reads the links you saved before, one at a time, and looks for a picture for those that have none (a link whose page has no picture to find stays in the list); links to a Pinterest picture pin or a picture file become picture pins." With previews off it adds "Reading links needs “Fetch link previews” (above)." (Before build 16 it promised Pinterest videos and said "Reddit videos are saved without sound" and that TikTok's video file "needs a cookie its own page hands out"; all gone with the video saving, 9.2.) Settings search matches against a shorter version of this footer: "When you add a link, PinBoard reads the page: an article's text, writer and date; a Pinterest pin's picture; a YouTube video's details from YouTube's own service and, with a YouTube Data API key, its top comments. Posts on Reddit, TikTok, Instagram and X are read as far as each site shows them to a visitor. A video on those sites or inside a web page is kept as a link with its picture: download it in its own app, then save it to PinBoard." †
- "Clean links": "Takes the tracking out of links you add — the “?utm_…”, “fbclid” and such that only tell a site who shared it. The page you get is the same."

Behaviour
- A link whose page names no picture first tries another picture of its own page, then the web image search for its title with the "Image source" of 21.8; a link kept in Hidden is never searched for. Reading needs "Read links fully" on, "Fetch link previews" on and Offline mode off.
- "Read existing links (N)": N = normal links never read fully, or read as an ordinary page or article and still without a picture; dimmed unless reading is in effect and one waits. While it runs the row becomes a spinner, "Reading 3 of 12…" ("Reading…", "Stopping…") and a borderless "Stop"; the pill says "Reading link 3 of 12…"; it ends with a toast (9.6).
- "Clean existing links" cleans every normal link in place (page, title and preview unchanged) and ends with the toast "Cleaned 3 links." / "Cleaned 1 link." / "Your links had no tracking to take out." What cleaning removes: 9.1.
### 21.7 AI

Page title "AI". Groups: "On-device AI", "Cloud AI (optional)" (dimmed, not hidden, in Offline mode, with the offline line first), "AI sorting".

**Group "On-device AI"**

| Row | Default |
|---|---|
| "Write titles for untitled pins" (switch; 20.2) | on |
| "Accurate text reading (slower)" (switch; 20.1) | on |
| "Use Apple Intelligence" (switch; 20.3) — shown only where Apple Intelligence is available; elsewhere a plain row "Apple Intelligence" with "Not available on this device" at the right | on |
| "Include hidden pins in AI" † | switch (build 17), the same value as on Privacy & Hidden (21.9): off, no AI looks at hidden pins (20.11) | off |

Footer, available: "Apple Intelligence writes more natural titles, adds related words to searches and composes web searches from everything known about an image — trusting your board names and tags first. It only ever sees text, never the picture, and runs on this device. Apple offers no cloud version to apps." Not available: "Tags (objects, scenes, colours, people count, cats and dogs), text reading, search and suggestions work on every device using the built-in Vision and Natural Language frameworks."

**Group "Cloud AI (optional)"** (behaviour, consent sheet and errors: 20.4). Only the first row shows while the switch is off; the other rows follow while it is on.

| Row | Choices | Default |
|---|---|---|
| "Use a cloud vision model" | switch; shows on only with consent for the chosen provider †; turning it on without that opens the consent sheet naming the company, and it stays off until "I understand — turn it on" (20.4) | off |
| "Provider" | menu: "Claude (Anthropic)" · "OpenAI"; picking the provider not agreed to opens the consent sheet for it, and the choice changes only once it is agreed to † | Claude (Anthropic) |
| "API key" | secret field at the right, no capitals or auto-correct; placeholder "sk-ant-…" (Claude) or "sk-…" (OpenAI); kept in the keychain | empty |
| "Model" | text field; placeholder is the provider's default, "claude-haiku-4-5-20251001" or "gpt-4o-mini"; blank uses it | empty |
| "Show keys" | switch; forgotten on leaving the page | off |
| "Get a key from Claude (Anthropic)" / "Get a key from OpenAI" | link to console.anthropic.com / platform.openai.com/api-keys | |
| error line | grey, icon `exclamationmark.triangle`, shown after a failed request | |

| "Re-run the cloud model on all pins" | button, dimmed unless the cloud model is really in use and a normal pin exists; normal pins only (Hidden has its own "Re-run AI tags") | |

Footer, switch off: "Apple doesn't let apps use its cloud models, so this is the one way to get a model that actually looks at the picture: far more specific tags, real titles and better searches. Needs your own API key and sends each image to that provider once, with its boards, your tags and, for a link, the text read from its page." Switch on † (for Anthropic; OpenAI reads "OpenAI (api.openai.com)", "OpenAI's privacy policy", "You pay OpenAI"): "Each new image is sent once, downscaled and stripped of all metadata, together with the names of its boards and your tags for it. For a link, the text read from its page (up to 1,500 characters) is sent with its preview picture. Everything goes to Anthropic (api.anthropic.com), under Anthropic's privacy policy. Hidden pins are never sent (“Include hidden pins in AI” is off). You pay Anthropic per image (usually a fraction of a cent). Your notes, your location and your other images are not sent." With "Include hidden pins in AI" on †, the hidden sentence reads instead: "Hidden pins are included: their pictures, titles, tags and text go to Anthropic too (never the names of hidden boards)."

**Group "AI sorting"**: a menu button "AI sorting" (icon `wand.and.stars`) that works on every normal pin (dimmed with none; items: 15.2); while a naming run goes, a row with a small spinner, "Renaming… 3 of 12" and a borderless "Stop". Footer: "Sorts every pin into boards, gives them tags and names them. Hidden pins have their own in Hidden's ⋯ menu."
### 21.8 Explore & web search

Page title "Explore & web search" (new in build 15: "Explore the web" from Network & privacy and "Web searches" from Links). Groups: "Image source", "Web suggestions", "Search on the web". In Offline mode all three are dimmed and the first starts with the offline line (21.1).

**Group "Image source"**

| Row | Choices | Default |
|---|---|---|
| "Image source" (also used by "Find a picture for links without one" †) | menu: Wikimedia Commons · Openverse · Pexels · Pixabay · Unsplash | Wikimedia Commons |
| key rows | secret fields at the right of a title, placeholder "Paste here", no auto-capitals or correction, kept in the keychain: Openverse "Client ID" and "Client secret"; "Pexels API key"; "Pixabay API key"; "Unsplash access key"; Wikimedia Commons none | empty |
| "Show keys" | switch, for every source but Commons; forgotten on leaving | off |
| link row | "Get a free key from Pexels" / "…from Pixabay" / "…from Unsplash" (pexels.com/api, pixabay.com/api/docs, unsplash.com/developers); "About Wikimedia Commons" / "About Openverse" | |

Footnotes under the key rows: Commons, "Wikimedia Commons needs no key and has no practical limit. Results are openly licensed but mixed in quality."; Openverse, "Without credentials Openverse allows only about 5 searches per hour. Registering is free: it emails you a client ID and secret." Footer: "The source Explore, board pages and pin pages search, and “Find a picture for links without one” (Links) uses." followed by "Keys are stored in the iOS Keychain and sent only to the service they belong to, over HTTPS." or, when the keychain refused, "The Keychain refused to store keys in this environment, so they are kept in the app's preferences instead. They are still sent only to the service they belong to, over HTTPS."

**Group "Web suggestions"**

| Row | Choices | Default |
|---|---|---|
| "Automatically load web suggestions" | switch | off |
| "Offer web ideas at the end of boards" | switch | on |
| "Clear recent Explore searches" | button, only while there are recent searches (10 kept, newest first) | |

Footer: "Board pages and pin pages fetch web results only when you ask, unless “Automatically load” is on; the Explore tab searches when you tap Search."

**Group "Search on the web"** (was "Web searches" on Links)

| Group | Row | Choices | Default |
|---|---|---|---|
| "Search on the web" | "Open web searches in" | menu: "PinBoard (private)" · "Default browser" († the second choice read "Safari" before; it now opens whatever browser is the device's default) | PinBoard (private) |
| "Search on the web" | "Hand the picture over by" † | menu: "Copying it to the clipboard" · "Saving it to Files" · "Saving it to Photos" | Copying it to the clipboard |

Footer: "PinBoard's browser keeps nothing: no cookies, no history, no cache. Your default browser opens the search in that app instead. A picture that lives only in your library has no web address, so PinBoard hands it to you for the page: copied to the clipboard for two minutes (on this device only), saved to a folder you choose in Files, or saved to Photos (the newest picture in Recents). The first time, iOS asks whether PinBoard may add to Photos. A hidden pin's picture always goes to the clipboard, whatever you chose here. Then upload it on the search page." († "The first time, iOS asks…" replaced the sentence about the "Photo Library Additions capability" and the clipboard fall-back.)

"Open web searches in" and "Hand the picture over by" govern "Search on the web ▸" (7.4).

### 21.9 Privacy & Hidden

Page title "Privacy & Hidden". Groups: "Network" (Offline mode), "Hidden pins and boards", "Privacy".

**Group "Network"** — "Offline mode" (switch, default off). Footer on: "Nothing leaves the device: Explore, web feeds, link previews, Cloud AI, iCloud sync and the speech recogniser's language download are off. On-device AI keeps working." Footer off: "Turn this on to switch off everything that uses the internet: Explore, web feeds, link previews, Cloud AI, iCloud sync and the speech recogniser's language download." (The speech clause is †.) Offline mode:
- shows "Offline" on the list's "Privacy & Hidden" row; dims (never hides) the rows that need the internet on Links, AI, Explore & web search and iCloud & storage, each page's first such group starting with the offline line (21.1);
- stops link previews, link reading, iCloud sync, the cloud model (error line "Offline mode is on, so the cloud model wasn't contacted.") and the speech language download †; web searches say "Offline mode is on (Settings), so nothing is fetched from the web.";
- leaves on-device AI working. Turning it off again (here, or by Explore's button) lets videos waiting for the speech files be listened to within about 2 seconds †.

**Group "Hidden pins and boards"** (was the Safety page)

| Row | Choices | Default |
|---|---|---|
| "Ask for Face ID, Touch ID or passcode" | switch (stays on this device) | on |
| "Include hidden pins in AI" † | switch (build 17); the same value as the row on AI › On-device AI (21.7). Off: no AI looks at hidden pins (20.11); on: they get the AI like any other pin, Cloud AI included. Turning it on starts the AI's look at the hidden pins that were left out. Per profile, kept on this device (not synced). Search words: hidden, ai, cloud, private, tags, secret, privacy, apple intelligence, transcribe | off |
| "Remove AI tags from hidden pins" † | red button (build 17), dimmed when no hidden pin of this profile holds anything the AI made. Asks first: alert "Remove AI tags from 42 hidden pins?" (one: "…1 hidden pin?"), message "Your own tags, titles and notes stay.", buttons "Remove" (red) and "Cancel". Takes out of every hidden pin the AI's tags, the text read in the picture (and its key words), the cloud description and search hint, and a title only the AI wrote: it goes back to the title from before the AI's rename when there was one, else the pin is untitled. Titles the person typed or that came from a file or page, their own tags and notes stay. Instant (no progress line); toast "Removed AI tags from 42 hidden pins." (names no board). The pins are marked to get the AI's look again only once the AI may see them (20.11). Search words: hidden, ai, tags, remove, clear, delete, private, text, titles | |
| "Order of pins in Hidden" | menu: Shuffled · Newest first · Oldest first — the same setting as Hidden's ⋯ menu (16.2); it says nothing about what is hidden | Shuffled |

Footer: "Hidden pins and boards live in Boards › ⋯ › Hidden. Touch and hold a board and choose “Hide board”, or choose “Hide pin” on a pin. Hidden pins stay out of every other screen. Once unlocked, Hidden stays open until PinBoard goes to the background, you switch profiles or you choose “Lock now” in its ⋯ menu. “Order of pins in Hidden” is the same choice as in Hidden's ⋯ menu. Include hidden pins in AI: off, no AI looks at hidden pins — no tags, no reading of text in pictures, no AI titles, no Apple Intelligence, no speech transcripts and no Cloud AI. Only PinBoard's fixed checks run on them: colours, finding duplicates (pictures are still compared on this device), and searching the words you typed. Tags and titles the AI made before stay; “Remove AI tags from hidden pins” takes them out. On, hidden pins get the AI like any other pin — with Cloud AI on, their pictures go to its company too." († build 17: the last part, from "Include hidden pins in AI". The sentence about the “Face ID” capability in Swift Playgrounds is gone.)
- On: opening Hidden asks for Face ID, Touch ID or the device passcode (reason line "Show your hidden pins and boards"); until then the screen shows a locked panel: icon `lock.fill` (40 pt), "Hidden pins and boards are locked", "Unlock with Face ID, Touch ID or your passcode. You can turn this off in Settings › Privacy & Hidden › Hidden pins and boards." and a prominent "Unlock" button; the prompt also appears by itself. It re-locks only when the app goes to the background, on "Lock now", or on a profile switch. Off, or on a device with no passcode: Hidden opens without asking.

**Group "Privacy"** — ten grey footnote lines in one row (6 pt apart), each with icon `checkmark.shield`:
1. "Tagging, text reading, search and suggestions run on this device."
2. "Speech in videos is written down on this device; nothing is sent anywhere." †
3. "Web searches use a throwaway connection: no cookies, no cache, no tracking identifiers, HTTPS only."
4. "Only the search words leave the device — never your notes, tags or images (unless Cloud AI is on)."
5. "With “Find a picture for links without one” on, a link's title is one of those search words: it goes to the image source you chose. Links in Hidden are never searched for." †
6. "Keys stay in the Keychain and go only to their own service."
7. "Location data in photos is kept for export only and never sent anywhere."
8. "Offline mode switches every network feature off."
9. "A picture searched on the web opens in PinBoard's own browser, which keeps no cookies, history or cache, unless you chose your default browser." †
10. "A picture that lives only in your library reaches the search page by the clipboard (gone after two minutes, on this device only) or, if you chose that, as a copy saved to Files or Photos, which stays there until you delete it. A hidden pin's picture only ever goes by the clipboard." †

### 21.10 iCloud & storage

Page title "iCloud & storage" (new in build 15: the iCloud group from Network & privacy and the Storage page). Groups: "iCloud", "Device storage", "Video quality", "Originals and size". Texts say "this device", never "this iPad". Rules behind the rows: 22, 23.2.

**Group "iCloud"** (rules: 23.2; dimmed, not hidden, in Offline mode, with the offline line first)

| Row | Choices | Default |
|---|---|---|
| "Sync with iCloud Drive" | switch | off |
| "Last sync" (while on and iCloud is available) | the date and time in short form, or "Not yet" | |
| "Sync now" | button; while a sync runs, its line instead ("Syncing with iCloud… 580 of 2,500", with the bar) and a "Stop" button † (the sync ends at its next step; what came stays) | |
| "Bringing full pictures and videos: 120 of 900" † | a progress line with its bar, only while the full files of pins that came with a sync are coming (after the "Syncing" line is gone). Build 11. | |
| "Sync log" † | opens a page (inline title "Sync log") with the last syncs' diary, newest first, small monospaced lines, selectable; "Copy" and "Clear" top right; empty: "Nothing yet. Each sync writes a few lines here." It refreshes every 3 seconds while open. Kept on this device only (never synced, never sent), last 400 lines. Each sync logs how long each step took: listing iCloud's files, finding the profile's folder, reading iCloud's library, comparing and sending, writing, pins and thumbnails arriving, the full files, and the total; or "Nothing changed on either side (checked in 0.3 s)". Build 11. | |
| error line | grey, icon `exclamationmark.triangle`, after a failed sync | |

Footer, iCloud available: "This profile's library is kept in this app's iCloud Drive folder and merged with your other devices, and its settings follow along. It syncs with the profile of the same name on your other devices. Each profile decides for itself: one with sync off stays on this device only. Columns, Offline mode, the originals folder, the Hidden lock and API keys stay on this device." Otherwise †: "iCloud isn't available. Check that this device is signed in to iCloud with iCloud Drive on, and that PinBoard is allowed to use it (Settings › your name › iCloud › iCloud Drive)." plus, when the switch is on, " The switch stays on and starts working once iCloud is there." (Build 16 dropped the sentence "In Swift Playgrounds it is never available: the app needs to be built with the iCloud capability.") Settings search matches the shorter "Your library is kept in this app's iCloud Drive folder and merged with your other devices."

**Group "Device storage"**: "Optimize device storage" (switch, default off, stays on this device; 22.5) — dimmed unless "Sync with iCloud Drive" is on and Offline mode is off; under it a grey line: "Needs “Sync with iCloud Drive” (above)." / "Not while Offline mode is on." / "Full-size pictures and videos you haven't added or opened in 30 days are kept in iCloud only. Thumbnails stay, so browsing and search work offline; opening one gets it from iCloud."; then, while files are kept in iCloud only, "In iCloud only" with the count and size and "Download everything" (22.5).

**Group "Video quality"**: "Video quality", menu Original · 4K · 1080p · 720p, default 1080p — the same row, name, choices and footer as on Videos (21.5).

**Group "Originals and size"**

| Row | Choices · what it shows | Default |
|---|---|---|
| "Keep originals in a folder" | switch; turning it on before a folder was chosen opens the Files folder picker (cancelling leaves it off); an unusable folder shows the grey line "That folder can't be used. Choose another one (in iCloud Drive, say)." | off |
| folder row (once chosen) | "Folder: iCloud Drive › PinBoard Originals" with a caption "Checking…" → "Reachable" / "Not reachable now", and a borderless "Change…" | none |
| "Library size" | "Measuring…", then for example "1.3 GB on this device — videos 1 GB · pictures 300 MB" (" · other Z" only at 10 MB or more) | |
| "Originals in the folder" | the size, "48 MB"; only while the normal side has originals kept | |
| "Convert existing videos…" | button (22.1; converts to the Video quality above); during a run a spinner, "Converting 3 of 12 (45%)" ("Finishing up…") and "Stop" | |
| "Pins" | the number of normal pins at the right | |

- "Change…" with originals already kept asks "Use another folder?": "The originals already kept stay in “iCloud Drive › PinBoard Originals”. To keep them reachable, move its folders into the new one in the Files app." with "Choose a folder…" and "Cancel"; with none kept the picker opens at once. Choosing a folder also turns the switch on.
- "Library size" is measured when Settings opens and again after a conversion, a folder import or a clear; it counts everything this profile keeps on the device, hidden pins and Recently Deleted included. The folder is named by its last two parts ("iCloud Drive › PinBoard Originals"; "On this device" for the device's own storage; "the chosen folder" when no readable part is left).
- Footer: "A video is added exactly as it is, at once; afterwards, in the background, those larger than the chosen size are converted so they take less room, and smaller ones are kept as they are. Originals: full-size pictures and videos are copied to the folder you choose — pick one in iCloud Drive to keep them off this device. PinBoard keeps its own smaller copy and fetches the original when you ask for it: “Show original” on a pin's page, Save to Photos and Share. Hidden pins' originals are never copied to the folder; while originals are kept, hidden videos stay as they are. Converting runs while PinBoard is open; a video interrupted by leaving the app is tried again at the end of the run, and “Convert existing videos…” catches anything left."

### 21.11 Library

Page title "Library" (inline); five groups. The screens behind the rows: 23.

1. **Profiles** (no header): the row "Profiles" (icon `person.2`, the profile in use in grey). Footer: "Each profile is a completely separate library, with its own settings (iCloud sync included). Switching happens only here."
2. **The three lists** (no header), each with a grey count of the normal side: "Recently Deleted" (icon `trash`; pins waiting), "Possible duplicates" (icon `square.on.square`; the newer pin of each pair), "Your tags" (icon `tag`; how many different tags you gave). Footer: "Rename, merge or delete the tags you gave to pins."
3. **Header "Your data"**
   - "Export all pins and boards…" (icon `square.and.arrow.up`): dimmed only when the profile has no live pins and no boards at all (hidden ones count). While an export is made it becomes the grey line "Preparing export… 120 of 1,040" with a progress bar, then "Making the zip…", and a button "Stop export" (icon `stop.circle`).
   - After an export, a grey footnote "Ready: 12 pins in 14 files." plus "1 pin was left out: its file is missing." / "2 pins were left out: their files are missing.", or "Export failed: " and the reason (a stopped export leaves no message).
   - "Share the zip (AirDrop, Files…)" (icon `doc.zipper`) and "Save the folder to Files…" (icon `folder.badge.plus`; dimmed if the folder is gone), shown once an export is ready.
   - "Import a folder…" (icon `square.and.arrow.down`), which opens the Files folder picker (one folder); while any import runs it is replaced by a spinner and "Importing… Reading 12 of 300…" (the normal side's words; never a hidden import's); a picker error shows an alert with the system's text and "OK".
   - Footer: "The export is a folder per board (sub-boards nested), with every pin's title, tags and notes written into the JPEG's metadata, plus a library.json for an exact re-import. Zips can't be opened by the app itself — unzip them in Files first, then import the folder. “Import a folder…” takes an export or any folder of pictures, videos and text files (its sub-folders become boards); anything that looks like a pin you already have is asked about, like any import." After a real export: " Last export: 1 Oct 2026 at 9:30 PM." While pins were added since: " 12 pins added since." ("1 pin added since.")
4. **Header "Backups"**: "Recover library" (icon `clock.arrow.circlepath`; "3 missing" in grey only when pins lost their files). Footer: "PinBoard keeps a copy of the library file from a few minutes ago and one from the previous day, so a bad save is never the only version."
5. A red "Clear this profile's library…", dimmed when the profile has no pins and no boards at all (hidden pins and Recently Deleted count).
### 21.12 About

One section, header "About", one small grey paragraph, and nothing else (no version number, link, licence or contact line): "PinBoard keeps everything on this device. Image tagging, text reading, writing down speech, search and board suggestions run locally; the only network use is the web image search you start yourself, link previews and reading the links you add (and a web image search for a link that has no picture, if you turn that on), the speech recogniser's language files the first time, the cloud model if you turn it on, and iCloud sync if you turn that on."
- † Three phrases of it belong to the latest round: "writing down speech", "(and a web image search for a link that has no picture, if you turn that on)" and "the speech recogniser's language files the first time".

## 22. Storage

The rows are in 21.10 (iCloud & storage; "Video quality" is on Videos too, 21.5); this section holds the rules.

### 22.1 Video quality tiers and what is converted when; converting existing videos (normal side) and Hidden's own

| Quality | Longest side | Data-rate limit | Converted to |
|---|---|---|---|
| Original | none | none | nothing is converted |
| 4K | 3840 px | 30 Mbit/s | HEVC 3840 × 2160 |
| 1080p (default) | 1920 px | 12 Mbit/s | HEVC 1920 × 1080 |
| 720p | 1280 px | 6 Mbit/s | H.264 1280 × 720 |

1. A video is only ever made smaller: it is converted when its longest side or its data rate is above the tier's, otherwise it is kept as it is. A converted copy is kept only if it is at least 15% smaller. It keeps its kind of file (.mov, .mp4, .m4v) and name.
2. A new video is first copied exactly as it is, at once, so its pin appears immediately; converting follows in the background, one video at a time, after everything imported is in. (A file kind that cannot keep its name, such as .3gp, becomes an .mp4 at import.)
3. With "Keep originals in a folder" on, each original is copied to the folder first and then replaced by the smaller copy under the same name; if the original cannot be kept, that video is not converted and the run stops with a note. Without originals the larger version is gone for good.
4. A failed conversion is tried once more at the end of the run, once the app is on screen again (up to 10 minutes). Stop ends the video in hand, leaves nothing half-made and keeps what is done.
5. The Pins tab pill, when free, says "Converting video 3 of 12 (45%)…" (during an import of an odd file kind "Importing 3 of 10 — converting video 45%…"). A run holds the library like an import: switching profile waits. When it ends, transcription starts (20.10).

**"Convert existing videos…"** is dimmed while the library is busy (an import, a folder import, an iCloud sync, a link-reading run, a conversion), when the quality is Original, or when no video waits. It asks "Convert 12 videos to 1080p?" ("Convert 1 video to 1080p?"; "Convert videos to 1080p?" when none): with originals kept, "Videos larger than 1080p are converted to take less room. Each original is copied to your originals folder first. You can stop at any time."; without, "Videos larger than 1080p are replaced by smaller copies. The larger versions are not kept — turn on “Keep originals in a folder” first if you want them. You can stop at any time." Buttons "Convert" (red when no originals are kept) and "Cancel". After a run stopped early, a grey note stays under the button: "Stopped: the originals folder couldn't be reached, and each original is copied there before its video is converted." or "Stopped: the original couldn't be copied (is there room?), and each original is copied before its video is converted."

**Hidden videos** never get an original in the folder, so while originals are kept a hidden video is never converted. Hidden's ⋯ menu has its own "Convert videos to 1080p…" (the chosen tier), offered only while originals are not kept, the tier is not Original and a hidden video is not yet at it; its question, progress row and closing toast are in 16.2. It uses the same tier rules and the larger version is gone for good; nothing about it shows in Settings or on the pill.

### 22.2 Keep originals in a folder: what goes there, names, iCloud eviction, hidden pins never

- The folder is chosen in the Files picker (iCloud Drive is the intended place) and remembered. With the switch on, each picture or video added to the normal library (and a link that becomes a picture pin) is also copied untouched to it, a picture as imported (HEIC, PNG, JPEG…). The library keeps its own smaller copy: a picture at most 2,048 px on its long side as JPEG, a video as converted.
- Each profile has a subfolder of its own; an original is named after its pin ("‹pin id›.‹extension›"); the app only writes, removes or evicts files it named, and a file appears only once complete. An unreachable folder breaks nothing; the row says "Not reachable now".
- To keep the device light, shortly after launch and after every import, conversion and fetch, originals iCloud already has in full are taken off the device (they come back when opened) — never one not yet uploaded, opened in the last 10 minutes, or on screen. Originals of pins erased for good are removed.
- Hidden pins' originals are never copied; a pin hidden later keeps the one it has. "Clear this profile's library…", "Delete profile" and "Erase all now…" say in their questions that originals go too.

### 22.3 "Show original" (row, viewer, fetch and Cancel, patience); Save to Photos / Share with originals

For a stored picture or video whose original was kept, the pin page has a row between the link details and "Boards" (10.3): a rounded panel (secondary background, 16 pt corners, 14 pt padding) with
- the title, icon `externaldrive` and "Original kept in iCloud Drive › PinBoard Originals · 48 MB" ("Original kept in your originals folder" when the name is unknown; size and "·" left out when unknown);
- a status line (caption, grey): "Checking…" → "On this device" / "In iCloud — fetched when you open it" / "Not reachable now";
- after a failed try, icon `exclamationmark.triangle` and "The original couldn't be fetched (the folder may be offline).";
- a bordered large button "Show original" (icon `arrow.up.left.and.arrow.down.right`), which while fetching — also when Share or Save to Photos is fetching — becomes a spinner, "Fetching the original…" and a borderless "Cancel" (44 pt tall).

Fetching waits up to 10 minutes for iCloud and gives up at once if iCloud reports a problem. "Cancel" stops every fetch of that original (Share and Save to Photos then use the copy on the device); leaving the page stops it too. In Quick Look the command is "Show original" in ⋯ (no Cancel; while fetching it is dimmed and reads "Fetching the original…"; swiping away stops it; failure toast "The original couldn't be fetched (the folder may be offline)."), and the info panel shows "Original · 48 MB · iCloud Drive › PinBoard Originals".

**The viewer:** a sheet with inline title "Original" and "Done" at the top right (Esc too), black and always dark, page-sized on iPad. A picture is shown whole and zooms like Quick Look (pinch 1× to 6×, double-tap about 2.5×), decoded at up to 4,096 px on its long side; one that cannot be opened shows "The original couldn't be opened." (VoiceOver: the title, or "Original picture"). A video plays at once in PinBoard's own player with its bar, middle play and skip buttons and double-tap skipping †, but no expand button and no speed controls; one it cannot read says "This video can't be played." While the viewer is open, and for 10 minutes after, the original is never taken off the device.

**Save to Photos and Share** use the original when one was kept: the pill reads "Fetching the original…" or "Fetching originals 2 of 5…"; the first original is waited for up to 45 seconds and, once one fails, the rest are taken only if already on the device; copies stand in and the toast says so (7.8).

### 22.4 The library size read-out

"Library size" (21.10) is measured each time Settings opens and again after a conversion, a folder import or a clear. Pictures = pictures and their small copies (a video's poster too); videos = the video files; other = fingerprints, photo details, the library file and its safety copies (shown from 10 MB). It counts everything the profile keeps on the device, hidden pins and Recently Deleted included, without saying which is which; "Originals in the folder" and "Pins" count the normal side only.

### 22.5 Optimize device storage †

Settings › iCloud & storage › "Optimize device storage" (default off; only with "Sync with iCloud Drive" on and Offline mode off; this device only, never synced). Under it: "In iCloud only  312 · 4.1 GB" and "Download everything" (progress "Downloading 12 of 312…" with Stop) whenever anything is offloaded. Offloading.swift. "In iCloud only" also counts pins that just came with a sync whose full file is still on its way † (23.2, "Full files later").
- **What leaves.** After each sync, a picture pin's full picture or a video pin's video — never a link preview, text, thumbnail, poster, fingerprint or photo details file — when iCloud holds it in full, it was added more than 30 days ago and not opened on this device in the last 30 days, and its work is done (a picture the AI has looked at and whose thumbnail is here; a video with its length, sound and poster known and its words written down or not wanted). Hidden pins too: they are in iCloud already while sync is on. Which pins are offloaded, with their sizes and when each was last opened here, is kept in "offloaded.json" in the library's folder.
- **Coming back.** Opening a picture (pin page, Quick Look, crop) or a video (pin page, Quick Look: the poster shows with "Getting the video from iCloud… 40%" †, or "Couldn't get this video from iCloud. Check your connection." with "Try again" †) brings the file back from the library's iCloud folder (a minute's wait for a picture, ten for a video) and it stays another 30 days. In Quick Look a picture's thumbnail shows at once with a pill at the bottom, "Getting the picture from iCloud… 40%" † (the percentage once iCloud says; a spinner before); when it can't come, the thumbnail stays with "Couldn't get the full picture from iCloud. Showing a smaller copy." and "Try again" † (the pin page also keeps the thumbnail). The request to iCloud is repeated every 15 seconds while waiting. (Build 9 never noticed the file had arrived, for the same reason as the slow sync below, so Quick Look spun for a minute and then showed "Couldn't load this image".) Share, Save to Photos, search the web, turn, flip, crop, a new poster, video conversion, Export and Share board, the AI queue and the cloud model bring it back first; when it can't come: "Couldn't get it from iCloud. Check your connection." A grid card of an offloaded video shows its poster without playing. Transcription skips offloaded videos (the Settings button brings them back). Dragging an offloaded pin out carries no file.
- **Never called missing.** The missing-files check and "Remove pins whose files are missing" leave offloaded pins alone, and a sync does not fetch them back.

## 23. Your data

### 23.1 Profiles (create, rename, switch, delete, what each holds; the Profiles screen)

- A profile is a completely separate library: its own pins, boards, smart boards, Recently Deleted, hidden pins and boards, tags, duplicate decisions, "Undo last AI naming" history, back-up copies, "Last export" date and reminder count, kept originals (a subfolder of its own) and, with iCloud sync, its own iCloud folder. It also has its own settings, kept in a preferences file of its own (ProfileSettings.swift): every Settings value (iCloud sync, Offline mode, Optimize storage, look, text, videos, links, AI, the Hidden lock…), its own API keys in the Keychain, its own originals-folder choice, recent Explore searches, last board and feed orders. So one profile can sync with iCloud while another stays on this device only. Switching shows the other profile's settings at once (its sync starts or stops with it); a new profile starts with the default settings; deleting one deletes its settings and keys. Updating from a version where settings were shared gives every existing profile a copy of them, so nothing changes until changed. Shared by every profile: only the list of profiles.
- A fresh install has one profile, "My library" (an older single library becomes it). A name is trimmed and cannot be empty; there is no length limit and duplicates are allowed. Profiles keep the order they were made in.
- Switching happens only on the Profiles screen. The library in use is saved at once and the other loaded; Hidden locks again; shuffled feeds get a new order; every tab is rebuilt (the Pins tab on All); a running export stops and its share rows go; a pending import question is dropped with the toast "Import cancelled: another profile was opened." (normal side only); background work of the old library stops. Switching waits while an import, a folder import, an iCloud sync, "Read existing links" or "Convert existing videos…" runs: the other rows and "New profile…" are dimmed and the footer adds "Switching waits until the import or sync that is running has finished."

**The Profiles screen** (Library › "Profiles", inline title "Profiles"). Section "Profiles": one row per profile, the whole row switching to it — a filled `checkmark.circle.fill` in the accent colour for the profile in use and an empty grey circle for the others, the name (with "1 shared item waiting" / "3 shared items waiting" in small grey type under it when things shared from other apps wait for that profile, 23.7 †), the caption "Current", and a ⋯ button (44 pt; VoiceOver "Actions for ‹name›") with "Rename…" (icon `pencil`) and "Delete…" (icon `trash`, red; dimmed for the profile in use and when only one exists). Touch and hold gives the same menu ("Delete…" only for another profile). Footer, sentences joined in this order: "Now using “‹name›”." (after a switch made here), "Switching waits until the import or sync that is running has finished." (while blocked), "Tap a profile to switch to it. Each one is kept completely apart: its own pins, boards, smart boards and Recently Deleted, and its own settings — iCloud sync, Offline mode, look, API keys and the rest. A new profile starts with the default settings. Rename or delete a profile with its ⋯ button (or touch and hold it). The profile in use can't be deleted." A second section holds "New profile…" (icon `plus`; dimmed while blocked).
- "New profile" sheet (inline title): placeholder "Name (e.g. Work, Kids)", "Cancel" and "Save" (dimmed until the name is not blank; Return saves); saving creates the profile and switches to it, empty. "Rename profile": placeholder "Name", starting with the current name; renaming never switches. Once text is typed, swiping a sheet down no longer closes it.
- "Delete…" asks "Delete “‹name›” and everything in it?" — "All of that profile's pins and boards are removed from this device. This cannot be undone." (with an originals folder: "…removed from this device, and its full-size originals from “iCloud Drive › PinBoard Originals”. This cannot be undone.") — "Delete profile" (red) and "Cancel". It removes the library files and the originals the app named, nothing in iCloud Drive; the profile in use and the last profile can never be deleted.

### 23.2 iCloud sync (when, what merges, status texts, limits)

The switch "Sync with iCloud Drive" (21.10) keeps each profile in its own folder of the app's iCloud Drive container and merges it with other devices. Settings travel too †, through iCloud's key-value store (SettingsSync.swift): appearance, accent, text-pin style, video, link, board and AI preferences, Explore's source and the web-search choices. Each profile's settings travel apart, only to the same profile on the other devices, and only from a profile whose own sync is on (starting after its library's first sync, once its iCloud folder is known). The newest change wins; a device turning sync on takes the settings already in iCloud first. These stay on each device: the number of columns, Offline mode, the originals folder, the Hidden lock, recent searches, the last board, the sync switch, every API key and the cloud model settings.
- **Which folder** †. iCloud keeps a list of profiles (Documents/PinBoard/profiles.json, ids and names; CloudProfiles.swift). A profile syncs with the folder it used before, else the entry with its own id, else an entry with the same name (spaces at the ends and capitals don't count) that no other profile on this device uses; with none of those it adds itself. So every device's first profile, "My library", shares one library, and a profile made on a second device joins the one of the same name. The choice is remembered per profile on the device. A profile made on one device does not appear on the others by itself: make one with the same name there. Before reading, the app has iCloud list the folder's files (up to 15 s) so a new device sees what the others wrote; a library or list iCloud has but couldn't bring within 30 s stops the sync with an error instead of being treated as missing. Whether iCloud is there is checked again at every sync, so switching iCloud Drive on later needs no relaunch.
- **When it runs** (switch on, Offline mode off, iCloud available): about 1 second after the switch is turned on; 3 seconds after launch; 20 seconds after every save (more saves restart the wait) — but not after a save that only holds what a sync just brought, and not during a sync † (changes made during one are sent right after it); about 3 seconds after iCloud reports that another device wrote this profile's library † (iCloud tells the app while it is open; the app's own write doesn't count); 2 seconds after returning from the background; 5 seconds after a sync during which something changed; 2 minutes after a sync that failed or ended with pins still to come † (not after Stop); at once with "Sync now" (always the full sync); at once with a pull to refresh on any pin grid † (the quick look first; not while a sync runs; build 12). A sync holds the library like an import (switching profile waits) and the pill says "Syncing with iCloud…" with a spinner.
- **Nothing changed** † (build 11): after each full sync that left nothing to do, the app keeps a marker — a fingerprint of this device's library and the date and size of iCloud's library file. The next sync looks at both first; when neither changed it ends in about a second and logs "Nothing changed on either side". "Sync now" in Settings always does the full sync. Any edit here, or a newer library file from another device, means a full sync. The full list of iCloud's files is fetched once per launch (it can take up to 15 seconds), again only after a sync found pins whose files weren't in iCloud yet.
- **What merges.** Every pin, board and smart board has a change date; the newer change wins (a tie keeps this device's). Exception: a pin's picture details (the picture, turn or crop, a refreshed link preview, a new video poster) come from the device with the newer picture, so a crop on one device and a tag edit on the other both survive. Deletions are remembered for 90 days as erase marks; an erase beats a record last changed at or before it, not a later one (a re-import). A board whose parent vanished moves to the top level; hidden boards stay hidden with their pins; a pin loses a board erased elsewhere; a board's open count, "last edited" and "last added" keep the higher or later value and its colour palette the newer.
- **Files** are copied whole both ways: a new pin's files (a video included) when it first reaches the other side; a picture again whenever it changed, newer to older. A video is not copied again, so a later conversion stays on the device that made it. This device's new pins go to iCloud during the merge. iCloud's new pins come afterwards through a rolling window † (CloudArrivals.swift, build 10): the files of up to 200 pins are asked for at once, a pin joins the library as soon as its thumbnail is here † (build 11; a link's preview, or a photo without a thumbnail in iCloud, waits for the picture itself), and each pin that arrives makes room for the next, so one slow file never holds up the rest; every 3 seconds the pins that came join the grid and the pill reads "Syncing with iCloud… 2,100 of 2,500" — the pins here out of the whole library, so it only counts up, also across syncs †; a thumbnail, fingerprint or photo details file gets 5 seconds more and is otherwise left out (a missing fingerprint is made again here). A file iCloud doesn't have yet (still on its way from the other device) is skipped at once; a pin still waiting after 90 seconds (15 minutes for a video), or whose file iCloud reports an error for, is set aside so the window takes others †; set-aside pins get one more try at the end of the run. The pill adds " · waiting for iCloud" when nothing has come for 30 seconds †. When nothing at all has come for 5 minutes the run stops †, and while the app is open the next sync starts 2 minutes later and carries on †. Time the app spends away from the screen doesn't count as waiting. Build 10 could stall for 20 minutes or for good: pins that never came kept their place in the window, a waiting video stretched the patience to 10 minutes twice over, a run that gave up wasn't started again until something changed, and reading the library file could wait for iCloud with no end (now 30 seconds, then the sync stops and tries again). Leaving the app mid-sync gives the running round about half a minute to finish and save; iCloud keeps bringing what was asked for, and the sync carries on when the app is back (pins already here are not asked for again, files already copied count as here at once). Build 9 waited for files by asking the same file address over and over, which keeps its first answer ("not downloaded"), so nearly every file waited out the full minute (ten with a video) before being skipped: that was the slow sync. Either way the next sync tries again, and it also fetches the picture or video of any pin here whose file is missing. The library file waits up to 30 seconds.
- **Full files later** † (build 11, CloudChanges.swift): a photo's full picture and a video's video don't hold the pill. Until they come the pin counts as "in iCloud only" (as with Optimize device storage, 22.5): the grid and search work from the thumbnail, Quick Look shows "Getting the picture from iCloud… 40%", and Settings › iCloud & storage counts it under "In iCloud only". Right after the sync they come quietly, eight at a time, with "Bringing full pictures and videos: N of M" in Settings › iCloud; a file that doesn't come (90 seconds, 15 minutes for a video) comes after the next sync or when opened. With Optimize device storage on, pins not added or opened here in the last 30 days are not downloaded at all: they stay in iCloud only until opened. Letting go of this device's copies in the iCloud folder (once iCloud has them) never makes a later sync think a file is missing: the check looks at the library's own folder. That tidy-up runs in the background after a sync that sent files (or that left nothing to come), without holding the pill.
- **Storage** †. Each file copied into the library is let go from the iCloud folder on this device (it stays in iCloud), and after every sync so is each of this device's files that iCloud has in full, so a synced device doesn't keep every picture twice. The library lists stay.
- **iCloud not there** (signed out, iCloud Drive off, or PinBoard not allowed to use it): nothing syncs and Settings › iCloud & storage says "iCloud isn't available. Check that this device is signed in to iCloud with iCloud Drive on, and that PinBoard is allowed to use it (Settings › your name › iCloud › iCloud Drive)." († build 16: without the old Swift Playgrounds sentence; 21.10).
- Deleting a profile removes nothing from iCloud Drive; "Clear this profile's library…" marks everything erased so other devices drop it, but picture files already in the iCloud folder stay. A restore is not protected: the next sync merges the restored list with the cloud copy record by record. Hidden pins and boards, with their pictures, sync like everything else.

### 23.3 Export (what the zip/folder holds, board folders, metadata in pictures, the hidden-boards question, progress, Share / Save to Files) and import a folder (PinBoard exports re-created whole †, plain folders, questions)

**Export** (Library › "Your data"; rows and messages: 21.11). Nothing in it is a key, a setting or the profile list.
1. When the library has any hidden board, hidden pin or hidden smart board, a dialog asks "Include hidden boards in the export?" — "Hidden pins (hidden on their own, or on a hidden board) are left out too." — "Include hidden boards", "Leave them out", "Cancel". Include: everything goes in (hidden boards become ordinary folders under their names, a pin hidden on its own goes to "Unsorted"; library.json records what is hidden, so a re-import brings it back hidden); the files are not protected. Leave out: the normal side only, every hidden mark and id stripped. With no hidden content there is no question.
2. While it runs Done is dimmed and swiping Settings down is off. "Stop export" removes everything made so far, with no message. When the zip is ready the share sheet opens by itself, or, when something else is open over Settings, the toast "Your export is ready — tap Share the zip." appears. It counts as a back-up ("Last export"; the 50-pin reminder of 4.2 starts over) only when the zip was really shared or the folder really saved, and only for the profile it was made from. An export that is neither shared nor saved does not stay on the device: leftovers are removed at every launch.
3. **The folder** "PinBoard Export 2026-10-01 21.30" (year-month-day, then hours and minutes with a dot, 24-hour clock; the zip adds ".zip"; a board share is "‹board name› (PinBoard)") holds one folder per board (every board, empty ones too; sub-boards nested; equal names get " 2", " 3"), "Unsorted" for pins on no board, a copy of a pin in every board it is on, and:

| Pin | Files |
|---|---|
| Picture | "‹name›.jpg": the library's copy (not the kept original), details written inside |
| Video | "‹name›.poster.jpg" (carries the details) and "‹name›.mov" (or .mp4, .m4v) |
| Link | "‹name›.url" (an internet shortcut) and, with a preview, "‹name›.preview.jpg" |
| Text pin | "‹name›.txt": the title, a blank line, the text |

**File names.** A name is the title made safe (`/ \ : * ? " < > |`, line breaks and control characters become "-"; spaces and dots at the ends trimmed; 80 characters; nothing left: "Untitled") or, with no title, "Pin " plus the first 8 characters of the id in capitals; clashes add " 2", " 3". Not exported: Recently Deleted, kept originals, settings, keys, the profile list. "Ready: 12 pins in 14 files." counts every copy written (a pin on three boards is three files; a video is two; a link with a preview two).

4. **Details inside every JPEG:** IPTC title and TIFF description; IPTC keywords (your tags, AI tags at 50% or more, photo-file keywords, colour tags, each once); IPTC caption (the note, cut at 8,000 characters at a word end with "…" †; the AI's description when there is no note); credit; software "PinBoard"; orientation upright; a JSON record in the EXIF User Comment (id, title, note, tags, AI tags with confidence, colour tags, key words, text read, description, boards, created, source, credit); the pin's location as GPS when the original details held none; the original camera details where they existed. If writing them fails the picture is copied without them.
5. **library.json** holds every live pin with every field it has (kind, id and dates; title and who wrote it; note, tags, AI tags, colour tags, read text, description and search hint; a text pin's text; a link's address, kind, text, writer, date, site, comments, highlights † and the article a quote came from; a video's length, sound, quality and transcript †; a picture's size, fingerprint, photo details, source and kept-original name; boards, hidden status, "Keep out of All", look-alike marks), plus all boards and smart boards (with their settings and dates). **files.json** maps each pin to its file; a **_pinboard** folder holds fingerprints and original photo details so a re-import needs no new AI look; **README.txt** reads: "PinBoard export" · "Folders match your boards (sub-boards are nested folders); "Unsorted" holds pins that were on no board." · "A pin on several boards appears in each of them." · "Each JPEG carries its title (IPTC Object Name), tags (IPTC Keywords), note (IPTC Caption) and a full JSON record in the EXIF User Comment. Camera EXIF from the original photo is kept where it existed." · "Text pins are .txt files (title, blank line, text). Videos sit next to a ".poster.jpg" still that carries their metadata." · "Links are .url shortcut files, with a ".preview.jpg" picture when one was fetched." · "library.json, files.json and the _pinboard folder let PinBoard re-import everything exactly."

**Share board…** (14.3) makes the same files for one board and, optionally, its sub-boards: a zip holding the folder "‹board name› (PinBoard)" with the board's own folder at the top, every pin on the shared boards (each listing only those), no smart boards, nothing hidden (a shared hidden board comes out ordinary), open counts reset to 0. It is not a back-up.

**Import a folder…** reads one folder from Files, never changes it, does not open zips (unzip in Files first) and works on the normal side only; it is library work (switching profile waits).
- **A plain folder:** pictures (jpg, jpeg, png, heic, heif, webp, gif, tif, tiff), videos (mov, mp4, m4v), text files (.txt) and shortcuts (.url) at any depth in natural name order; dotfiles, README.txt, "*.preview.jpg" and "_pinboard" are ignored. Sub-folders are boards (matched ignoring capitals with an existing normal board at that level, else created); files in the chosen folder itself or in a top-level "Unsorted" go on no board. Titles: 20.2; a text file whose first paragraph is one line of at most 80 characters takes it as the title, otherwise the whole file is the text; a shortcut needs an http or https "URL=" line (cleaned if "Clean links" is on).
- **A PinBoard export** (library.json and files.json present) †: boards not yet in the library are re-created with their own ids and settings, parents first, and smart boards too; pins are taken one by one — already live: left alone; in Recently Deleted: restored; otherwise re-created from the files with every field of the record (title and author, notes, tags, AI tags, read text, hidden and kept-out marks, transcript, highlights and the rest), boards narrowed to those that exist, its own id when free and its own change date; hidden records return hidden and are never compared with the normal library.
- **Questions and result.** Anything that looks like a pin already there is asked in "Looks familiar" (8.4): a picture or video still within the signature rule of 20.8, text equal ignoring capitals, a link with the same cleaned address (a byte-identical picture asks nothing). The result is always an alert with "OK": "Nothing to import in that folder." (+ " 1 was already in your library." / " N were already in your library." + " N couldn't be read."), or in order "Added 12 pins, created 3 boards." / "Added 12 pins." / "Created 3 boards."; "Put 2 existing pins on their boards."; "1 was already in your library." / "N were already in your library."; "Skipped 2 duplicates."; "N couldn't be read."; or "Nothing was added." Cancelling at a question gives the toast "Folder import cancelled. Nothing was changed."

### 23.4 Recently Deleted (retention, restore, erase), Possible duplicates screen, Your tags (tag manager), Recover library (daily/previous back-ups, restore), "Clear this profile's library"

Hidden's ⋯ menu opens the first three for hidden pins only ("Recently Deleted", "Duplicates", "Tags", titled "Tags of hidden pins"), with the hidden-side wording of 16.3.

**Recently Deleted** (Library › "Recently Deleted", count at the right). Deleting a pin (question: 7.2) moves it here for 30 days with everything it had, a hidden pin staying hidden; it leaves every grid, board, count, search, suggestion and smart board, is no longer looked at and no longer covers a board.
- The screen (inline title): the footnote "Pins are erased for good after 30 days.", then the pins as cards in the Pins tab's grid (newest deleted first, the Settings column count; tapping a card does nothing), each with two small bordered buttons "Restore" and "Erase" (red), icon-only on narrow cards (`arrow.uturn.backward`, `trash`; VoiceOver keeps the words). A ⋯ menu (VoiceOver "More"; dimmed when empty): "Restore all" and "Erase all now…" (red). Empty: icon `trash` (44 pt), "Nothing here", "Deleted pins stay for 30 days so you can change your mind."
- "Restore" and "Restore all" act at once without a question or message: a pin returns to the boards it was on that still exist (else Unsorted), those boards count as edited and duplicates are re-checked; a cover or duplicate mark cleared at deletion does not return.
- "Erase" asks "Erase this pin for good?" ("Erase" red, "Cancel"). "Erase all now…" asks "Erase everything in Recently Deleted?" — "This cannot be undone." or, with an originals folder, "Their originals in “iCloud Drive › PinBoard Originals” go too. This cannot be undone." — "Erase all" (red). Erasing removes the pin's picture, small copy, fingerprint, photo details, video and kept original and records a 90-day erase mark so other devices drop it too.
- A pin more than 30 days here is erased for good, but the check runs only when a library is loaded (launch, switching profile), never while the app stays open.

**Possible duplicates** (Library › "Possible duplicates"). A toolbar button (icon `arrow.clockwise`, VoiceOver "Re-check", a spinner while checking) opens "Re-check (skips pairs you kept)" and "Reset and re-check everything" (icon `arrow.counterclockwise`; forgets every "Keep both" first). The body is the footnote "Delete either copy — its boards and tags move to the one you keep — or keep both." and one pair card (10.6) per newer copy with a live twin on the same side, 16 pt apart; in a window wider than 900 pt the cards sit in one centred panel up to 700 pt wide (system background, 24 pt corners, 20 pt padding, soft shadow). Empty: icon `square.on.square` (44 pt), "No duplicates found", "Each new image is compared with the library as it is tagged."

**Your tags** (Library › "Your tags"). It lists the tags the person typed or accepted (never AI tags, colours or read words; always lower case), each with how many pins carry it (Recently Deleted not counted), most used first, ties alphabetical.
- Top to bottom: a "Find a tag" field, only with more than 8 tags (matches tags containing the typed words); the header "12 tags" / "1 tag" / "0 tags" (all tags, whatever the filter) and footer "The number is how many pins carry the tag. Renaming or merging changes it on every pin."; rows with icon `tag`, the tag, its count and a ⋯ button (VoiceOver "Actions for ‹tag›") offering "Rename…" (icon `pencil`), "Merge into another tag…" (icon `arrow.triangle.merge`) and "Delete…" (icon `trash`, red). Empty: "No tags of your own yet. Add tags on a pin's page."; no match: "No tag matches."
- "Select" (dimmed under 2 tags) turns rows into selection circles and shows "Select all" / "Deselect all" and "Done"; a bottom bar (regular material) shows "3 selected" and a small prominent button "Merge into one…" (icon `arrow.triangle.merge`; icon alone when narrow), dimmed under 2 chosen.
- One-line sheets: "Rename “‹tag›”" (placeholder "New name"; a name another tag has merges the two), "Merge “‹tag›” into…" and "Merge 3 tags into…" (placeholder "Name of the tag to keep"). A merge swaps every chosen tag for the typed name (lower-cased) on every pin of that side, Recently Deleted included, keeping it once per pin. "Delete…" asks "Delete “‹tag›” from every pin?" with "Delete tag" (red) and "Cancel".

**Recover library** (Library › Backups; normal side only). The list of pins and boards (not pictures or videos) is saved about 0.4 seconds after each change and when the app goes to the background. Per profile it keeps copies: "Earlier today" (renewed at the next save once more than 10 minutes old), "Daily copy" (more than 24 hours), "Before the last restore" (made at every restore) and "Set aside (unreadable at the time)" (a library file that cannot be read at launch is set aside, never overwritten, and the newest readable copy loads silently).
- Section "Earlier copies of the library": one row per copy, newest first — the name, the caption "1 Oct 2026 at 9:30 PM · 12 pins" ("1 pin"; live normal pins) and "Restore" at the right. Empty: "No earlier copies yet. One is kept after the first few minutes of use." Footer: "Restoring replaces the list of pins and boards with the copy. Pictures and videos on disk are kept."
- Restoring asks "Restore “Earlier today” from 1 Oct 2026 at 9:30 PM?" — "The current list of pins and boards is replaced. A copy of it is kept as “Before the last restore”, so this can be undone." — "Restore this copy" (red) and "Cancel". The current list is kept first (if that fails nothing is restored; restoring "Before the last restore" swaps the two). An alert says "Restored. The AI will look at anything that still needs it." or "Nothing was changed: that copy couldn't be read, or the current list couldn't be kept first." The AI, the missing-file check, video upkeep, transcription † and duplicates then run again; pictures and videos on disk are never touched, so pins added after the copy stay out of the list until a newer copy or an export brings them back.
- Section "Missing files": "Pins in your library with missing files" with the count (live normal pins whose picture or video file is gone — pictures, videos, links with a preview picture; they show an empty card); "Check for missing files" (a spinner meanwhile; alert "Every pin in your library has its file." / "1 pin in your library is missing its file." / "N pins in your library are missing a file."); and the red "Move pins with missing files to Recently Deleted…" (dimmed at 0), which asks "Move 1 pin to Recently Deleted?" / "Move N pins to Recently Deleted?" — "It stays in Recently Deleted for 30 days." / "They stay in Recently Deleted for 30 days." — "Move to Recently Deleted" (red). Footer: "A pin whose picture or video file has disappeared shows an empty card. Pins moved to Recently Deleted stay there for 30 days." The check also runs at launch, on opening a profile and after a restore.

**"Clear this profile's library…"** (red row; 21.11) asks "Delete every pin and board in “‹profile›”?" — "This removes all pins from this profile, including Recently Deleted. Your Photos app is not affected. This cannot be undone." (with an originals folder: "…including Recently Deleted. The full-size originals kept for them in “iCloud Drive › PinBoard Originals” are deleted too. Your Photos app is not affected. This cannot be undone.") — "Delete everything" (red) and "Cancel" (a popover without Cancel on iPad). It erases every pin, board and smart board, hidden ones too (the message does not say so), with Recently Deleted, pictures, videos and kept originals; stops the AI, naming runs, video upkeep and transcription †; forgets the "Undo last AI naming" history; leaves erase marks so iCloud copies follow; and saves the empty library at once. Other profiles, this profile's settings and its keys stay.

### 23.6 Widgets †

Only in the build made from Xcode/PinBoard.xcodeproj (TestFlight): a widget extension can't be part of a Swift Playgrounds app, where none of this exists (the snapshot below is simply never written). PinBoardWidgets/PinBoardWidgets.swift; the shared part is WidgetShared.swift, the writing WidgetSnapshotWriter.swift.
- **Three widgets**, each resizable (touch and hold › the size buttons) and set to one board or all boards (Edit Widget › Board, empty = all): **Photo** (one photo filling the widget; on medium and up its title on a soft dark band at the bottom; small, medium, large, extra large), **Photo Grid** (2 × 2 small, 4 × 2 medium, 3 × 3 large, 6 × 3 extra large; each photo opens its own pin, a small one the first), **Quote** (a text pin in serif type under a red quote mark, with its title — or the board's name — below on medium and large; small, medium, large).
- **Changing.** A new photo (grid, quote) every hour: each hour has its own order of the board's items, the same for every widget.
- **Pick** (Edit Widget › Pick, 1st–12th, default 1st). Widgets on the same board with different picks never show the same photo or quote at the same time: pick n takes the n-th share of that hour's order. iOS gives a widget no identity of its own and draws widgets with identical settings from one timeline, so two widgets on one board with the same pick always match; the descriptions say "For two on the same board, give each its own Pick."
- **The snapshot** (App Group group.com.silentdiffusion.pinboard2, folder Widgets): the normal library's boards (never a hidden board or one inside it), up to 30 photos from each board and 90 from the whole library — a fresh random sample each time, as JPEGs of at most 640 px made from the thumbnails (so offloaded pictures are included) — and up to 1,000 text pins, newest first. Written 30 seconds after the library is saved (each save restarts the wait), 5 seconds after launch, 3 seconds after another profile is opened; the widgets are then told to look again. Nothing from the Hidden section, ever.
- **Tapping** a widget opens the pin's page on the Pins tab ("pinboard://pin/<id>"; Settings closes first). A pin that is gone or hidden opens nothing.
- **Empty.** "Open PinBoard to fill this widget." before the first snapshot; "No photos on “Travel” yet." / "No text pins yet." when the board has none.
- **Waiting.** While a Photo or Photo Grid widget waits for its first photos (WidgetKit's placeholder), it shows the red pin mark (60 %) on the widget's grey background — not a plain grey box, which looked broken.
- **On a Mac** (build 20 on; found in build 18). Use the Mac's own widgets: the widget gallery's "PinBoard" entry, which comes from the PinBoard app installed on the Mac, and works like on an iPad (it reads the Mac's own snapshot). The iPhone's copies that macOS can borrow (System Settings › Desktop & Dock › "Use iPhone widgets", the gallery's "From iPhone") are marked `.disfavoredLocations([.iPhoneWidgetsOnMac])`, so macOS stops offering them: the Mac can't run them, only show pictures the iPhone sends now and then, and each new iPhone build throws those pictures away. On the owner's Mac three of them sat as grey placeholders that could not be removed. Settings › Widgets on a Mac says "Edit a widget on the desktop" and adds the "From iPhone" note. Widgets already placed are not changed by this; remove a stuck one with Control-click › Remove Widget, or right-click the desktop › Edit Widgets and the "–" badge, or by turning "Use iPhone widgets" off.

### 23.7 The share sheet †

Only in the build made from Xcode/PinBoard.xcodeproj (TestFlight): Swift Playgrounds can't make a share extension. The extension is PinBoardShare/ (ShareViewController, ShareView, ShareModel, ShareLoader, ShareBoardPicker, ShareSuggester, ShareFamiliarCheck, ShareFamiliarViews); what it and the app share is ShareShared.swift; the app's side is ShareInbox.swift and ShareFamiliar.swift.
- **Where it shows.** "PinBoard" (the app's icon) in the share sheet of other apps whenever what is shared holds at least one picture (any kind: JPEG, HEIC, PNG, GIF, a Live Photo — kept as its still picture), video, web link or piece of text: Photos (one or several photos, videos, Live Photos, or a mix), Safari, Files, Messages, Notes and the like. There is no upper count; anything else in the same share (a PDF, a contact) is left out with the "Nothing to save" note only when nothing usable is there. A file's own address (a PDF shared from Files) doesn't count as a link. (After build 15 the rule was changed from a list of counts — at most 100 pictures, 20 videos, 1 link — to "at least one usable thing", after PinBoard was missing from the Photos share sheet on the owner's iPhone.) In the share sheet's row of apps, iOS puts apps used less at the end: if PinBoard isn't in view, scroll that row to the end and tap "More", where it can also be moved to the front (Favorites).
- **The sheet.** Title "Save to PinBoard" (inline), "Cancel" at the top left, "Save" (bold) at the top right, dimmed until everything is read.
  - While reading: a spinner with "Getting ready…", or "Getting 2 of 5…" when several things are shared. Each file is copied, never held in memory (the share sheet runs inside the other app with very little memory).
  - Section 1, the preview: pictures, GIFs and videos as 84-pt squares with 10-pt corners in a row that scrolls sideways (a video has a small `play.fill` badge, a GIF a "GIF" badge; a grey square with a spinner until its picture is made); below them each link (icon `link`, the site's name in bold, the address in small grey type, 2 lines) and each text (icon `text.quote`, 4 lines), at most 5, then "and 3 more". Footer: what is shared — "1 picture", "3 pictures and 1 video", "1 link", "2 texts", "1 GIF".
  - **"Looks familiar"** (between the preview and the board; ShareFamiliarCheck.swift, ShareFamiliarViews.swift): each shared thing is compared with the normal library by the app's own import rules (8.4), from a small copy, one at a time:
    - *The same link* (the common kinds of tracking — utm_…, fbclid, gclid, Instagram's igsh, YouTube's and Spotify's si, a text highlight — taken out first; the app's full cleaning still runs on take-in) or *the same text* (capitals and blank space at the ends don't count): today's rule — the pin you have goes on the chosen board, nothing is saved twice — and one grey line with `checkmark.circle` says so: "Already in PinBoard: it'll be added to Travel." / "Already in PinBoard, on Travel." (it is on that board already) / "Already in PinBoard: it won't be saved twice." (no board) / "3 are already in PinBoard: they'll be added to Travel." / "3 are already in PinBoard: they won't be saved twice."
    - *A look-alike picture* (a GIF, or a video by its first frame): signatures at most 6 steps apart and shapes close (0.85–1.18), the closest pin. A section per look-alike, headed "This picture looks like one you already have" / "This video looks like one you already have" (with several: " (1 of 2)"): two columns, "New" (the shared picture) and "Already in your library" (the pin's tiny picture, 88-pt square, and "On: Outdoors, Travel" when it is on boards), then the app's answers as rows with a red checkmark on the chosen one: **"Save as a new pin"** (chosen to begin with), **"Add the existing pin to this board"** (only once a board is chosen; before that the grey line "Choose a board to add the existing pin to it instead."; if the pin you have is on that board already, the grey line "The existing pin is already on this board." instead), **"Skip this one"**. Changing the board back to "No board" turns "Add the existing pin" back into "Save as a new pin". With more than one look-alike, a last section with three small buttons: "Save all N as new", "Add all N existing" (only with a board), "Skip all N".
    - The answer is saved with the item (the pin it looks like, and the answer); PinBoard carries it out when it takes the item in, without reading the item: **Skip** → nothing is added; **Add the existing pin** → that pin is put on the board (the app's own `addPins`, as its import does), unless it has been deleted or hidden since — then the item is saved as new after all; **Save as a new pin** → saved as new, a link or text too. The confirmation adds "Put 1 existing pin on Travel." / "Skipped 1 duplicate.".
    - **What the check compares with** (App Group, each profile's own "Share/<profile>/familiar.json", written with that profile's board list, at the same times): every normal pin's picture signature and shape (pictures, video posters, link previews), each link pin's page, a fingerprint of each text pin's words (never the words themselves), each pin's kind, title (60 characters), boards; and in "Share/<profile>/thumbs" a tiny picture (120 px, JPEG) per normal pin with a picture, made in the background only when missing and removed when no longer needed. Nothing of a hidden pin is ever in either, so the sheet can never show or point at one. The check uses the chosen profile's index (another profile chosen: checked again against that one).
  - Section 2, where it goes. **"Profile"** (only with two or more profiles; above the board): the profile's name at the right; it opens a list titled "Profile" — header "Profiles", each profile as in Settings › Profiles (a filled circle `checkmark.circle.fill` in red on the chosen one, an empty `circle` on the others, "Current" at the right of the one open in PinBoard), footer "Each profile is a library of its own, with its own boards. What you save goes to the profile chosen here; for a profile that isn't open in PinBoard, it waits until you open that profile." It starts on the profile open in PinBoard. Choosing another swaps everything that depends on the library: its boards (its order, its hidden boards never listed), Suggested, the "Looks familiar" check, boards made in the share sheet — and the board goes back to "No board". **"Board"**: the choice at the right — "No board" or the board with its parents, "Travel › Japan". **Every share starts on "No board"** (the board the last share went to is remembered only for the board list's "Last used" row, never as the default). Footer: "It's added to PinBoard the next time you open it." / another profile: "It's added to “Work” the next time you open that profile in PinBoard."; a profile PinBoard hasn't written boards for yet (not open since this update) adds " Open “Work” in PinBoard once to see its boards here."; no profile list at all (PinBoard not opened since the update): "Open PinBoard once to see your boards here. What you save now is added without a board."
  - **The board list** (tapping the row; title "Board", inline) looks and works like the app's board picker (14.5; BoardPicker.swift), with the share sheet's differences said here. Top to bottom: a search field pinned on top (`magnifyingglass`, "Search boards", an `xmark.circle.fill` "Clear search" button while it holds words; a white rounded field on the grey). Then one section: **"No board (Unsorted)"** (`tray`); when nothing is being searched, the **suggested** boards (below), then **"Last used"** — the board this profile's last share went to (a red `clock.arrow.circlepath`, the board with its parents, "Last used" under it in small grey type, its pin count), left out when there is none (or it is gone) and when it is already one of the suggestions (that row's caption then ends " · Last used"). Suggested rows are highlighted in the accent at 14%, as is the row of the board chosen now; in "Boards" the last-used board has "last used" in small grey type after its name. The last board is kept per profile in the App Group ("Share/<profile>/last-board.txt"), written when a share is saved onto a board; when PinBoard makes a board the share sheet made, it puts the real board in its place. Then **"Boards"**: every board in the app's order (below), top-level boards with a red `folder.fill`, sub-boards with a grey `folder`, indented 18 pt per level; a board with sub-boards has a chevron (`chevron.right` / `chevron.down`, "Expand" / "Collapse") and "2 sub" in small grey type, and sub-boards start collapsed (the way to the chosen board opens by itself); at the right the board's pin count (as the app counts it; a board made in the share sheet and not made by PinBoard yet says "new") and a `plus.circle` ("New sub-board inside Travel") that opens a field "New sub-board in “Travel”" with "Create" under the row (`minus.circle` closes it). No boards: "No boards yet — create one below." While searching, "Boards" gives way to **"Matching boards"**: every board whose name holds the words (capitals and accents don't matter: "cafe" finds "Café"), sub-boards whether or not their parent is open, each with "in Travel › Europe" under it; none: "No boards match". Last, **"New board"**: a field "Board name" with "Create". Its name follows the search words until the person types in it (then search changes don't touch it; emptying it gives it back to the search); it is left empty when a board of that name already exists, with "“Travel” already exists — tap it above to choose it." under it — so no board is offered twice. Tapping a board (or creating one) chooses it and goes back. Unlike the app's picker: the board chosen to begin with is always "No board" ("Last used" is only a shortcut row), up to 3 suggestions instead of one, and it is a page inside the sheet rather than a sheet of its own.
  - **New boards from the share sheet** ("Create" in "New board", or a sub-board's "Create"): the extension can't change the library, so the board is listed and chosen at once with a stand-in id, and the share records it (its name, and the board it goes inside, also a new one) when saved. Saved shares' new boards are also kept for the next shares (App Group "Share/<profile>/new-boards.json"), so they are listed there before PinBoard has opened. PinBoard makes them when it takes the share in, outermost first: a normal board with the same name in the same place (capitals and accents don't count) is used instead, so a board two shares made is made once ("Reading" and "READING" → one board). Never a hidden board: one whose parent is hidden (or gone) by then is made at the top level. Once PinBoard has taken in every share of that profile, the kept list is cleared (the boards are real now). A board made in a sheet that is then cancelled is never made.
  - **Order.** The app writes the boards already in its order — the one its board pickers use: favorites first at every level, then the sort chosen on the Boards page (your own order, Name, Recently edited, Recently added), the same for sub-boards under each parent — and the share sheet keeps it as given. It is written again a few seconds after any change to the library (a board moved, renamed, made a favorite…) and at once when the sort is changed, when PinBoard comes to the front and when another profile is opened.
  - **Suggested** (up to 3 boards, best first; each row as the app's "Suggested" row: a red `sparkles`, the board with its parents, under it in small grey type "Suggested · pins from swift.org are here" / "Suggested · its name matches “outdoor”" / "Suggested · like the pins already here", and its pin count at the right. The same rules as the app's board suggestions (20.7; the board picker's "Suggested", 14.5), worked out in the share sheet from the **first** shared thing only (with many, the first is usually like the rest, and looking at each would cost memory): the board's name and its parents' names (parents count 0.6) against the item's words or tags — 55%; the item's main tags against the tags common on the board's pins — 25%; and, in place of the app's look-alike check (the share sheet can't compare pictures with the library), a link from a site the board's pins come from — 35%. A board scoring under 0.2 is never suggested; nothing fits: no Suggested section. What is compared: a link's site, the words of its address and the page title the other app gives (Safari does); a text's most frequent words; a picture's, GIF's or video's tags from Apple's on-device picture classifier on a small copy (360 px; a video's first frame), plus the keywords and title stored in the file (as the app reads them; a camera's name like "DSC_0001" is skipped). Words match by spelling ("beach"/"beaches", "cake" in "cupcakes"), not by meaning as in the app. Nothing leaves the device. A hidden board is never suggested (it is never in the list), and nothing of a hidden pin goes into what the app writes. In the simulator Apple's classifier only runs on the processor and gives poor tags; on a phone it is the same as the app's AI tags. A red checkmark marks the choice; tapping anywhere on a row chooses it and goes back. Typing narrows the list by name as you type, ignoring big or small letters and accents ("CAFE" finds "Café"); a matching sub-board shows its parents ("Travel › Café"). Nothing fits: a grey "No boards match" under "No board". No boards at all: "You have no boards yet."
  - **Look.** A steady, solid background (the system's grouped grey, darker than the see-through glass iOS would show) behind the sheet, the list and the title bar, from the first frame, not changing as the list scrolls. Buttons and checkmarks use PinBoard's red (the share sheet can't read the accent chosen in Settings); board names are in the normal text colour.
  - **Hidden boards are never listed** — neither a hidden board nor a board inside the Hidden section. The share sheet runs inside other apps and the Hidden side is locked there, so it never learns their names. The sheet doesn't say that anything is left out.
  - Section 3: a text field "Add a note (optional)" (1–5 lines). The note goes on every new pin of the share.
  - Nothing usable (a PDF, a contact): icon `questionmark.square.dashed`, "Nothing to save", "PinBoard keeps pictures, GIFs, videos, links and text. None of these could be read." The shared folder can't be written: icon `exclamationmark.triangle`, "Couldn't save", "PinBoard's shared folder couldn't be written. Open PinBoard once, then try again."
- **Quick save** (Settings › Pins & boards › "Choose a board when sharing" off, 21.4; the app writes the open profile's value into "Share/<profile>/settings.json"): no board picker. The sheet reads what is shared ("Getting 2 of 5…", then a spinner with "Saving…" while it checks for look-alikes), saves to no board in the profile open in PinBoard, shows `checkmark.circle` "Saved to PinBoard" for a moment (no Cancel or Save then) and closes by itself. The same link or text already in PinBoard is handled silently as always (the pin you have stays; nothing is saved twice). A *look-alike* picture or video still stops it: the sheet shows the preview and the "Looks familiar" question with "Save as a new pin" (chosen to begin with) and "Skip this one" (no board, so no "Add the existing pin"), and the footer "Saves to no board in “My library”. To choose a board when sharing, turn on “Choose a board when sharing” in PinBoard's Settings › Pins & boards."; no Profile or Board row and no note. Save → "Saved to PinBoard", then it closes.
- **What is kept.** Each shared thing in its own pin. A GIF from Photos or Files stays a GIF (so it comes in animated, as a video pin, 8.2). A picture shared only as an image (no file) is kept as a JPEG at 92%. A file shared from Files by its address is read by its type (picture, GIF, video, or a text file of at most 1 MB). A web address shared both as a link and as text, or as two links that differ only by capitals, "http"/"https" or a "/" at the end (Safari does both), is kept once. A video's or Files picture's file name becomes its title, tidied as in 8.2 ("FullSizeRender", Photos' name for an edited picture, is dropped).
- **Saving** closes the sheet at once — for a profile that isn't open in PinBoard, after a moment showing `checkmark.circle`, "Saved", "It'll appear in “Work” the next time you open that profile in PinBoard." (no Cancel or Save then). Nothing is sent anywhere: the files and a small description (the kinds, the address or text, the profile, the board and any new boards, the look-alike answers, the note, the date) wait in the App Group's "Share Inbox" folder until PinBoard takes them in.
- **Taking in** (the app): at launch, every time PinBoard comes to the front, when another profile is opened, and at once when the share sheet saves while PinBoard is open (iPad side by side). Oldest share first, item by item, through the same reading and saving as every other import: links are read fully when Settings › Links says so and get their preview, the AI tags the new pins, videos are made smaller (8.6), and iCloud sync takes them along. The pill counts "Adding 3 of 12 shared items…" (a link's "Reading the link…" shows while it is read). No look-alike questions: a byte-for-byte copy of a picture already here, or a link or text already a pin, puts that pin on the board instead of saving it twice; a picture that only looks similar is saved as a new pin. A toast at the end: "Added 3 shared items to Travel." (several boards or no board: "Added 3 shared items."), with " 1 was already in your library." / " 2 couldn't be read." when so (`info.circle` when nothing new was added).
- **Profiles.** A share belongs to the profile chosen in the sheet and is taken in only while that profile is open; until then it waits in the inbox. It is not added to a profile that isn't open: that would take a second copy of the library store with the open profile's settings (reading and cleaning links, the AI, video conversion), which could mix two libraries. Instead PinBoard says so: once for each new count, a toast `tray.full` "1 shared item is waiting for “Work”. Open that profile to add it." / "3 shared items are waiting for “Work”. Open that profile to add them." (after the take-in's own confirmation), and in Settings › Profiles that profile's row shows "1 shared item waiting" / "3 shared items waiting" in small grey type under its name. A share made before PinBoard wrote its profile list, or for a profile deleted since, goes to the profile open now, without a board. A board deleted since: Unsorted. Each item is crossed off as soon as it is in, so a take-in cut short (another profile, the app closed) never adds anything twice.
- **A board hidden since** the share was made: the pins still go onto it (so they are hidden too), and no toast mentions them.
- **The files** (App Group, folder "Share"): "profiles.json" — the profiles (id and name, as in Settings › Profiles) and which one is open, written at launch, when PinBoard comes to the front, and whenever a profile is made, renamed, deleted or opened; and a folder per profile ("Share/<profile id>", each kept apart) with "boards.json" — that profile's normal boards in the app's order (id, name, parent, depth, pin count), each with what Suggested needs: its name's words in their base form, the 40 tags most common on its normal pins (the AI's fairly sure tags, your own tags, words read in pictures, file keywords) with the share of pins carrying each, and the sites its link pins and web pictures come from with their share — plus "familiar.json" and "thumbs" (above) and the share sheet's "new-boards.json". A profile's folder is written only while that profile is open: at launch, 5 seconds after the library's last save (only when it changed), at once when the board sort changes, when PinBoard comes to the front and when that profile is opened; other profiles keep what was written when they were last open (a profile not open since this update has none yet). A deleted profile's folder goes; nothing of a hidden pin or board is ever in any of them.
- An unfinished share (the system closed the sheet halfway) is cleared from the inbox after a day.

## 24. Asked for but not built, or not possible

| Asked for | Status | What the app does instead |
|---|---|---|
| Downloading YouTube videos | refused: YouTube's terms of service | A YouTube link shows title, channel and thumbnail (from YouTube's oEmbed service); with an optional free key also length, description, date, views and top comments; "Play" uses YouTube's embedded player. Since build 16 † the watch page is never read either, so without a key there is less to see. "Nothing is downloaded from YouTube." (9.4) |
| Saving videos from TikTok, Instagram, Reddit, X, Pinterest and from inside web pages | built, then removed for build 16 † | It worked until build 15: a TikTok, Reddit or Pinterest video, an Instagram reel or a web page's video was downloaded and became a video pin. App Review guideline 5.2.3 forbids an app to download media from other services without their permission, so build 16 took it out. Such a link now becomes a link pin with the post's picture, title and caption (9.2), and a friendly note, shown once on the pin's page and kept in Settings › Links, says: "Most apps let you download a video inside the app itself. If you'd like the video in PinBoard, download it there, then save it to PinBoard (from Photos or with the share sheet)." (10.3, 21.6). A link that is itself a video file (.mp4, .mov) is still downloaded. Videos saved by earlier builds stay video pins. |
| PinBoard's own keyboard | removed for build 16 † | The setting "Use PinBoard's own keyboard" and its simple built-in keyboard existed only because the system keyboard never appeared when the app ran inside Swift Playgrounds. The real app always has the system keyboard, so both are gone (21.4). |
| iPhone Duo features (fold-aware layouts, reserved regions) | not possible yet: needs the iOS 27.1 SDK; Swift Playgrounds has 27.0 | Layouts follow window width and size class only (3.1) |
| A converted video travelling to other iCloud devices | not built | A video's file travels when its pin first reaches a device; a later conversion stays on the device that made it (23.2) |
| A per-pin "remove from this device" | not built | Originals are taken off the device automatically once iCloud has them (22.2); the library's own copy always stays |
| HEIC re-encoding of pictures | not built | The library keeps its own copy as JPEG, at most 2,048 px on the long side; HEIC survives only as the original in the originals folder |
| Exports with originals | not built | An export holds the library's copy of each picture and video (23.3) |
| A crop screen for custom thumbnails of another shape | not built | A thumbnail from Photos or a picture pin is centre-cropped to the video's shape (7.7) |
| Facebook and other login-walled pages | cannot be read, by decision | The link is added as a plain link, never as the login page; posts on X keep no pictures or videos (9.2) |
| Apple's own cloud models for apps | not available to apps | The optional cloud vision model needs the person's own key (20.4) |
| Opening zips inside the app | not built | Unzip in Files, then "Import a folder…" (23.3) |
| Choosing the language for speech in videos | not built | The device's own language is always used (20.10) |


## 25. Open questions for the owner

The sections above describe what the app does today. These are the places where a recreation needs the owner's decision: either the app's behaviour and its own wording disagree, or a behaviour may be an accident rather than a design. Until answered, "as it is today" is the rule.

**A. Building it as an ordinary app**

1. **Swift Playgrounds texts and work-arounds** — answered in build 16 †: dropped. The "Use PinBoard's own keyboard" switch and the built-in keyboard (21.4), the Hidden footer's "Face ID" capability sentence (21.9), the Playgrounds wording of the camera alert (now "This device has no camera.", 8.5), the "Saving to Photos needs one setting" alerts with the fall-back to the clipboard (7.4, 7.6, 7.8) and the iCloud footer's Swift Playgrounds sentence (21.10) are all gone. Still open: the image services see the app as "PinBoard/1.0 (iPhone and iPad app)"; Wikimedia asks apps to add a contact address there — which address? And if the app is registered at unsplash.com/developers under another name than "PinBoard", the Unsplash links' "utm_source" should carry that name (19.2).
2. **Permission prompts** — answered in build 16 †. The words iOS shows (PinBoard-Info.plist): Photos (reading what you pick) "PinBoard reads only the photos and videos you pick to pin. It never changes or deletes anything in your library; saving to Photos only adds new items, and only when you ask."; adding to Photos "PinBoard adds a pin's picture or video to Photos only when you choose Save to Photos."; camera "PinBoard uses the camera only to take a photo when you choose Camera from the + menu."; speech recognition "PinBoard listens to your videos on this device to write their transcripts. Nothing is sent anywhere."; Face ID "PinBoard uses Face ID to unlock your Hidden section." The microphone is no longer asked for (the camera takes photos only). Save to Photos asks only for add-only access (7.8).
3. **iCloud sync** (23.2): profiles now pair up across devices by name (a second device's "My library" joins the first one's). Should hidden pins and their pictures sync (today they do)? And a restore from "Recover library" is merged with the cloud copy about 20 seconds later, so newer cloud records can come back — should a restore win?

**B. The hidden side**

4. **Silence as the rule.** Hidden shows no status pill while importing (only its "+" turns into a spinner), a naming run on hidden pins is reported only by an alert on the hidden screen, and no toast ever names a hidden board. Deliberate, or should Hidden show its own progress?
5. **Hidden things and the outside world.** *Answered for the AI (build 17 †, the owner: "The only thing that should see hidden pins is the hard-coded algorithms that already exist"): no AI of any kind looks at hidden pins unless the person turns on Settings › Privacy & Hidden › "Include hidden pins in AI" (off by default); see 20.11.* Still open: an export that includes hidden boards writes ordinary, unprotected files; "Clear this profile's library…" erases hidden content without saying so; a pin hidden after it got a kept original leaves that original in the Files-visible originals folder; "Open link" on a hidden pin opens the outside default browser, whose history keeps the address. Which of these are meant?
6. **"Start here"** (5.4) counts hidden pins and hidden boards: a library of only hidden pins reads "Photos added", and a hidden board makes the card vanish, so the normal side hints at hidden content. Its dismissal is not remembered (the card returns after a relaunch or a profile switch while no board exists). Intended?

**C. Behaviour to confirm**

7. **Dragging between apps** (6.4, 8.2). A dragged link card carries only PinBoard's own reference, not its web address; a hidden picture can be dragged out to other apps; a dragged picture is the library copy, never the kept original. Is dragging between apps meant on iPhone as well as iPad? (What other apps hand over when dropped onto PinBoard depends on those apps and needs checking on real devices.)
8. **Reading limits and per-site gaps** (9.2): 25 s per page, 3 MB of page text, 30 MB per picture, 500 MB per video file, only mp4, mov, m4v and 3GPP video files; X posts keep no pictures or videos, Instagram and Facebook login walls stay plain links. Final, or "not yet"? (Videos from TikTok, Instagram, Reddit, X, Pinterest and web pages are no longer saved at all since build 16 †, by App Review's rule, not by choice: 24.)
9. **Two-column pin pages** (10.1) let a video be as tall as its shape asks, even taller than the window; a one-line rule would keep videos inside it. Keep the uncapped height?
10. **The sound switch** (12.1) is off at every launch, while the Videos footer says that once sound is on it "stays on for every video you open, until you turn it off". Should it be remembered across launches, or should the footer say "until you turn it off or close the app"?
11. **"Write titles for untitled pins" off, cloud model on** (20.2, 20.4): the cloud model's title is still written. Should the switch stop it?
12. **Camera photos** (8.2) are stored without their capture date and place. Keep that metadata?
13. **Text files through two doors** (8.2, 23.3). A .txt chosen with "Files…" becomes a text pin holding the whole file; the same file inside an imported folder gives its first line (up to 80 characters) as the title. PinBoard's own exported text files start with the title, so importing one through "Files…" repeats it. Make both doors alike?
14. **A board named "Unsorted"** (23.3) shares its export folder with the pins on no board; imported back as a plain folder, everything in it lands on no board. Rename such a folder on export ("Unsorted 2")?
15. **Highlights** (9.3) are always the accent colour at 28%. Is a choice of colours, or a note on a highlight, planned?
16. **Tuning numbers.** This document gives every number the app uses (six grid video players, the 100 pt reach and 120 pt swap margin, 0.4 s re-rank, toast and fade timings, score thresholds…). Must a recreation match them exactly, or are they starting points?

**D. Wording that disagrees with behaviour** (fix the words or the behaviour?)

17. **"Automatically load web suggestions"** (14.4, 19.3): the Explore & web search footer ("Web suggestions") names board pages and pin pages, but only a board's "Keep exploring" ever loads by itself; a pin's "From the web" always waits for a tap.
18. **"Board pages include sub-board pins"** (14.1, 21.4): the footer says each board page "can still switch this on or off for itself", but a page's own switch is forgotten when the page is left; every visit starts from the Settings value. Per visit, or remembered per board?
19. **Imported titles** (2.2, 15.2) — a title taken from a web page or a file name — are protected like the person's own, yet the "Name with AI" question calls every protected name "written by you". Change the wording or the protection?

## 26. Known quirks — what the app does today that a recreation may want to fix

Each of these is how the app behaves now. None was asked for; they came out of the code review. They are listed so that a recreation knows whether it is reproducing a design or an accident. The hidden-side items above (25.4–25.6) are not repeated here.

**Pins tab, grid and adding**

1. "Unsorted (N)" includes pins kept out of All, and the "All" empty state says "No pins yet" even when every pin is only kept out (5.1).
2. A video card opens Quick Look in a grid but its page in "More like this" (6.4).
3. Two iPad windows share one Pins-tab shuffle (3.1, 6.1).
4. A dropped address that is not a web address becomes a plain link pin, although the link sheet would refuse it (8.2).
5. A dropped video's title comes from a temporary file name: about six in ten get none, the rest a code like "dropped 3F2A1B4C …" (8.2, 20.2).

**Pin commands**

6. After Crop, Rotate or Flip, "Save to Photos" and "Share…" still hand out the unedited kept original; each edit re-saves the library picture as a JPEG of at most 2,048 px (7.5, 7.8).
7. "Share…" is never dimmed, yet while a job runs and kept originals must be fetched, choosing it silently does nothing; the fetch's progress shows only on the Pins tab's pill; "Save to Photos" saves several pins in no particular order (7.8).
8. Offline mode dims the "Search on the web" settings (Explore & web search), yet "Search this picture on the web ▸" stays in every menu and the search page still loads: Offline mode governs only the app's own fetches (7.4, 21.8).
9. Wording slips: the hide toast says "It's in Boards › ⋯ › Hidden." while the menu item reads "Hidden…" (7.2, 16.2); "Copied 1 hex codes." has no singular (7.6); a YouTube card's details line says "1 views" for one view (9.4).
10. Fixed in build 16 †: the texts that spoke in developer terms ("Swift Playgrounds", "Capabilities") — the camera alert (8.5), "Saving to Photos needs one setting" (7.8), and the "Getting around" (21.4), Hidden lock (21.9) and iCloud (21.10) footers — are gone (25.1). The number is kept so later references stay right.

**Links**

11. A new link is first titled with the site's name, which its page labels "Written by AI"; the AI may replace it (9.1, 20.2).
12. With previews off, the link sheet says "the card shows the address only", but the card shows the site's name (8.7).
13. "Read existing links (N)" never reaches zero while pages without any picture, and login pages, stay in the list (9.6, 21.6).
14. "Clean existing links" leaves the source pages of picture, video and text pins alone, while "Edit link…" on them cleans the address (9.1).

**Pin page, Quick Look and the player**

15. The sound switch starts off at every launch, while the Videos footer says that once sound is on it stays on "until you turn it off" (12.1; question 25.10).
16. The big player is plain black until the video is ready, with no poster underneath, so the change from a neighbour's poster may flash black (12.1).
17. A draft's page opened from its own picture cannot load more results in Quick Look; opened from the feed it can (11.5).
18. Quick Look's "Share…" on a web result shares the result's page address, while a draft page's "Share…" shares the picture (10.2, 19.2).

**Boards**

19. Two boards may share a name; merging keeps the first chosen board in custom order without saying which; Rename, Description, Change cover, favouriting and Delete give no toast while Hide, Keep out of All and drops do (13, 15.1).
20. While boards are selected, an unselected tile shows only a plain white ring, hard to see on a pale cover (13.3).
21. Dropping a pin card on the page of the board it is already on lights the drop outline and then reports "It's already on Name." (14.2).
22. A board page's "Include pins from sub-boards" is forgotten when the page is left (14.1; question 25.18).
23. The "Order of pins" choices and "Sort boards" are kept per device, not per profile, and are not exported or synced (5.3, 13.1).

**Smart boards and Search**

24. "Matches now" in the smart-board editor counts pins removed from that smart board, so it can exceed what the board lists (17.1).
25. The delete question on a smart board's own page has only "Delete smart board" (no "Cancel"; tapping away closes it); the tile's has both (17.2).
26. A hidden smart board limited to a hidden board that is later unhidden keeps "in Name" in its rule line but shows nothing; a normal one would have gone back to "Any board" (17.1).
27. A filters-only search shows "100% match" under every card while the sort is "Best match" (18.2).

**Explore and the web feeds**

28. The "Web suggestions" footer (Explore & web search) says board and pin pages fetch "only when you ask, unless “Automatically load” is on", but only a board's "Keep exploring" ever loads by itself (19.3; question 25.17).
29. A web feed's "Details" notes restart at every page request, so the first page's notes are gone once the second page loads (19.2).

**The AI**

30. "Sort into boards" counts a pin as "put on a suggested board" even when it was already on a sub-board of that board and stays where it is; the longer message "Put N of M pins on suggested boards. Each pin's page shows why." is never shown (20.7).
31. Duplicates: only the newer copy is marked, so with several copies usually only the newest is listed; two copies with the same date are each the newer of the other and listed twice; only photo and video cards show the badge; "Save as a new pin" is not remembered, so the pair may reappear in Possible duplicates (8.4, 20.8).
32. The black-poster check can replace a poster the person chose on an older, never-checked video (20.9); a poster label above 80% can outrank speech key words in a video's name (20.2).
33. Transcripts †: words cut out of a note stay stored, keep feeding tags and names, and can no longer be found by search; a device language the recogniser lacks makes one run mark every waiting video as listened to; the status line keeps "Transcribing N of M…" while the run waits between videos (20.10).

**Your data**

34. Recently Deleted: "Restore" and "Restore all" ask nothing and say nothing; a tapped card does nothing; the 30-day clean-up runs only when a library is loaded, never while the app stays open (23.4).

**Build 16 changes †**

35. YouTube links saved without a key now show less than before: title, channel and thumbnail only — no length, description, date or views — because the watch page is no longer read (9.4). Links saved by earlier builds keep what they had until "Read link again", which can only find the smaller set.
36. The video note on a link pin's page (10.3) is remembered as "seen" per device, not per profile: tapping "Got it" in one profile hides it in every profile on that device, and another device shows it once more. Its "Settings › Links" copy and the search entry stay.
37. Everyone who had Cloud AI on before build 16 finds it Off after the update and must agree to the new consent sheet once (20.4); nothing is sent meanwhile. Only one provider's consent is kept, so switching provider back and forth asks every time.
38. Unsplash pins saved before build 16 have an untagged source page (without "utm_source=PinBoard&utm_medium=referral") and the old credit "Photo by ‹name› · Unsplash"; saving the same Unsplash photo again is compared by its now-tagged source page, so it may not be recognised as already in the library and only the look-alike question (8.4) may catch it (19.2).
39. (Fixed in build 16: the lost-video line now says only the link was saved, 8.5.)
