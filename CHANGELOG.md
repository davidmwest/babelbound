# Changelog

## 1.4.3 — 2026-09-23

- Renamed the project to **Babelbound**, with updated documentation, installer messages, menu heading, and diagnostic labels.
- Made the independent-project notice visible near the README introduction.
- Kept **BT** (Book Translator) as the compact macOS menu label.
- Preserved configuration names, module paths, settings, saved-job locations, request IDs, and EPUB identifiers. Existing installations and books need no migration.

This release changes the project name and presentation; translation and recovery behavior are unchanged. Earlier releases retain their original names and files.

## 1.4.2 — 2026-09-23

- Added an MIT license for original code, documentation, fixtures, and demo content, with explicit third-party screenshot exceptions.
- Added an offline synthetic demo of the illustrated HTML-to-EPUB export path.
- Made the project easier to review: engineering evidence, a workflow diagram, contributor instructions, and a concise PR template.
- Expanded CI to Linux/Python 3.10 and macOS/Python 3.14 with Lua 5.4, using pinned current GitHub Actions.
- Included the calibration compatibility guide, redacted workflow images, and Gemini plan/model recommendations added since the first package.

Live translation behavior is unchanged in this release. The offline demo does not test Gemini access or native reader interaction.

## 1.4.1 — 2026-09-23

First packaged repository release of the existing desktop translator.

- Added a portable installer with an isolated Python environment, backups, and customized-prompt preservation.
- Removed the dependency on a particular Codex runtime installation.
- Added startup configuration overrides that reach background helpers before initialization.
- Documented setup, recovery, model provenance, illustrations, EPUB export, and the state machine.
- Packaged synthetic regression tests and an offline GitHub Actions workflow.

This release includes the existing translator features: named resumable jobs, selected-model translation, status and progress reporting, source-page checks, illustration extraction, and automatic EPUB export. EPUB reading copies keep artwork and model provenance while removing generated continuation markers and unnecessary capture-by-capture page breaks.

Native UI compatibility still depends on the local Chrome, Gemini, BOOKWALKER, and Hammerspoon setup. See the troubleshooting guide before resending a pending request.
