# Changelog

All notable changes to Citadel. Versions follow [semantic versioning](https://semver.org): major.minor.patch.

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
