# Changelog

## 1.6.0 — 2026-09-25

- Replaced the flat BT menu with four groups: Read translation, Books, Setup, and Advanced.
- Added a primary action that follows the actual job state: start, pause, resume, review a problem or page position, or translate more after a completed batch.
- Added a passive summary of the loaded book, provider, last observed model, and screen target. Opening the menu does not query the browser or pause work.
- Kept export errors separate from translation activity, and added Rebuild EPUB for repair from saved work.
- Made actions that open another window explicitly pause active automation and cancel pending resume checks or scheduled resume before changing focus.
- Guarded book changes, provider changes, and calibration during translation, recovery checks, or scheduled resume; rename also waits for background writers.
- Clarified recovery labels and shortcut behavior. S follows the primary action; P cannot bypass a warning or start another batch.

This release implements the menu cleanup in the [menu and whole-book design](docs/menu-and-whole-book-design.md). Jobs still use a fixed screen count. Continuous translation scopes, coverage tracking, and end-of-book review remain planned.

## 1.5.0 — 2026-09-24

- Added an experimental provider for the official ChatGPT Chrome side panel, using direct prompts and the existing save/turn workflow.
- Added a provider menu, separate calibration and latest-job settings, and provider metadata on pending requests and saved pages.
- Bound ChatGPT interactions to the extension’s accessible web area; mismatched jobs and pending requests stop before input or collection.
- Preserved older Gemini jobs, prepared drafts, and the existing optional Gemini skill flow.
- Verified one authorized Japanese capture through the official extension with 6 Astra Medium: two visible Copy operations, a validated response, HTML and EPUB output, and provider/model provenance.
- Added bounded, read-only source checks when Chrome's temporary debugging banner shifts the reader, with a diagnostic capture if the fingerprint differs.
- Cleared unfinished calibration state when restoring a job from another provider.

A two-capture local reader test saved both translations and an EPUB with one
verified forward turn. It exposed a temporary banner interruption; a fresh run
with the fix completed automatically after the original source returned.
BOOKWALKER pagination with ChatGPT remains unverified because the live reader
requires a new sign-in after its session expired. Support remains experimental.

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
