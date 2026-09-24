# Changelog

## 1.4.1 — 2026-09-23

First packaged repository release of the existing desktop translator.

- Added a portable installer with an isolated Python environment, backups, and customized-prompt preservation.
- Removed the dependency on a particular Codex runtime installation.
- Added startup configuration overrides that reach background helpers before initialization.
- Documented setup, recovery, model provenance, illustrations, EPUB export, and the state machine.
- Packaged synthetic regression tests and an offline GitHub Actions workflow.

This release includes the existing translator features: named resumable jobs, selected-model translation, status and progress reporting, source-page checks, illustration extraction, and automatic EPUB export. EPUB reading copies keep artwork and model provenance while removing generated continuation markers and unnecessary capture-by-capture page breaks.

Native UI compatibility still depends on the local Chrome, Gemini, BOOKWALKER, and Hammerspoon setup. See the troubleshooting guide before resending a pending request.
