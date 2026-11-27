# Changelog

All notable changes to Citadel. Versions follow [semantic versioning](https://semver.org): major.minor.patch.

## 1.4.0 - 2026-11-27

What Citadel 1.4.0 for Windows brought, where it applies on the Mac.

### Added

- **Japanese interface**: Citadel speaks Japanese too (日本語 in the globe button and the Language menu), with the texts
  of Citadel for Windows where both have the same one. The installer pages are in Japanese on a Mac in Japanese.
- On the first start the interface follows the Mac when it is in Spanish or Japanese, and is in English otherwise.
- The dates of the conversation list and the labels of an exported conversation follow the interface language.
- Buttons that show only an icon (new conversation, export, send, stop, Show in Finder and Delete of a memory, refresh)
  have a name that VoiceOver reads.
- README, PDF manual and pictures in Japanese; every picture of the manuals made again with this version.

### Changed

- An attachment can be at most 2 MB; a larger file is refused with a message. The text of an attachment is read in its
  own encoding (byte order mark, UTF-8, or one macOS recognises, such as Shift_JIS or Windows-1252), so a file that is
  not UTF-8 no longer shows broken characters.
- `--screenshot` shows the paths of the folder given with `--data-folder` as `~/Library/Application Support/Citadel`, so
  the pictures of the manuals show the real path.
- Asking for an update check while one is under way says so instead of doing nothing.

### Fixed

- Changing the language with Settings open discarded rules being edited and not yet saved.
- A `<think>` tag that arrived split between two pieces of an answer was shown as text and the reasoning was mixed
  with the answer.
- Deleting the conversation that was answering, while another one was selected, let its answer go on.
- With Ollama or the SSH computer unreachable, the status checks could pile up; a check that comes while another one
  runs now waits for it.
- An answer from Ollama that cannot be read (for example from another program on its port) now gives the message
  "Ollama returned an answer that cannot be read." instead of a technical error.
- The search in the messages shows at most 200 results, as intended (it could show 201).

## 1.3.2 - 2026-11-27

The same number as Citadel 1.3.2 for Windows.

### Changed

- **A new icon**: a castle with its keep and two towers, and a speech bubble for a pennant, drawn as a flat picture,
  cream with a black outline on the chosen colour; it still follows the colour chosen in the settings, in all twelve
  colours. The drawing is `icono/icono.svg`, which `icono/render.sh` and `icono/render-accents.sh` turn into the icons.
- The release carries `release.sig`, the author's signature of its `SHA256SUMS.txt`, like the Windows apps. Citadel
  for Mac already accepts an update only when the downloaded app is signed as the installed one.

## 1.3.0 - 2026-11-20

What Citadel 1.3.0 for Windows brought, on the Mac.

### Added

- Updates that install themselves: once a day, and from Citadel → Check for Updates, Citadel looks for a newer
  release on GitHub and asks once: Update now, What's new or Later. Update now downloads the package, checks it
  against the release's `SHA256SUMS.txt` (a file that does not match is deleted and never opened) and the app
  inside it for the same identifier, version and signature, waits for or stops an answer in progress as the user
  chooses, quits, puts the new app in place of the old one and opens it with the text being typed and the open
  conversation.
- Search in the text of every saved conversation, ignoring case, accents and line breaks: the results show the
  conversation, the date and the words around the match, highlighted, and a click opens the conversation at that
  message. ⌘F goes to the search field.
- Export a conversation to Markdown, from the header or from the sidebar menu: title, date, model and each turn
  under its own heading, with code blocks intact; "Open after exporting" opens the file with the app macOS uses
  for `.md` files.
- `--self-test` checks the search, the export and the update checks first, without Ollama;
  `--self-test --offline` runs only those.

### Changed

- The search field, which only looked at titles, also lists the matches in the messages.

## 1.2.0 - 2026-11-10

### Added

- Theme and colour, as in Wyrmhold and Gryphmark: Settings → Appearance chooses as macOS, light or dark (the
  default), and one of twelve colours for the buttons, the selection and the icon in the Dock (green is the
  original). Every colour that was fixed for the dark window now follows the appearance.

## 1.1.0 - 2026-11-09

### Added

- Installer package, `Citadel-<version>.pkg`, in English and Spanish, built by `scripts/paquete.sh`.
- Globe button at the top right, next to the model menu, that shows and switches the interface
  language.
- Ollama on another computer through SSH: Settings → Ollama opens a tunnel with `/usr/bin/ssh` to
  port 11434 of that computer and closes it on quit.
- Models that cannot reason are marked "(no Reason)" in the model menu, and the Reason button is
  dimmed while one of them is selected.

### Changed

- The menus that macOS adds to every app (Edit, View, Window, Help) follow the interface language
  from the next launch.

### Removed

- The Translate menu.

## 1.0.1 - 2026-11-09

### Fixed

- Spotlight and Launchpad listed Citadel twice after installing: `scripts/instalar.sh` now deletes the copy
  left in `build/` and removes it from the macOS app register.

## 1.0.0 - 2026-11-09

First release.

### Added

- Chat with the models installed in Ollama, streamed as they are written and rendered as Markdown, with
  Copy buttons for each answer and each code block.
- Reason button: the model thinks before answering and its reasoning is shown in a folded block. Answers
  are capped at 8,000 tokens with Reason on and 3,000 with it off.
- Stop button (⌘.), which closes the connection so that Ollama stops generating.
- Status line: whether Ollama answers, whether the model is loaded, what it is doing, elapsed seconds and
  the speed of the last answer.
- Conversations in a sidebar, saved as JSON files, with search by title, rename and delete.
- Rules file sent at the start of every request, editable in Settings.
- Memories: `/mem <topic>` loads a saved memory into the conversation; `/save` drafts one with the model,
  shows it for review and writes it, with its index line, only after confirmation, checking both on disk.
- Attachments of `.txt` and `.md` files by drag and drop, and a Translate menu.
- English and Spanish interface, chosen from the Language menu.
- Stable self-signed code signature, so macOS keeps recognizing the app across updates.
- `--self-test` and `--screenshot` modes for maintenance and for the images of the manual.
- README and PDF manual in English and Spanish.
