# Architecture and contributing

## Runtime

Hammerspoon owns the menu, hotkeys, timers, accessibility queries, window/focus checks, mouse delivery, clipboard collection, and job checkpoints. Chrome renders BOOKWALKER and Gemini. BT does not use a Gemini API client or inject a hidden browser crawler.

A normal screen follows this sequence:

1. Verify the calibrated Chrome window and a stable source capture.
2. Create a pending request with a unique ID and source fingerprint; persist it before submission.
3. Verify the composer, populate the prompt, read back the full draft, and submit once.
4. Poll for a complete response, then collect the matching block through verified Copy controls.
5. Validate request ID, protocol markers, source anchors, and response completeness.
6. Save the response and accepted translation, commit the record, and refresh derived reading copies.
7. If work remains, persist turn state, deliver one forward click, and verify a stable changed screen.

Timeouts and uncertainty produce warnings, not successful completion. A pending request survives interruption. A reply that was already submitted is collected before considering another submission. Source review updates a navigation reference only after explicit matching evidence; original source captures remain unchanged.

Lightweight readiness polling targets three starts per second, while bounded accessibility scans and independent page-stability checks still take the time they require. Increasing CPU speed does not eliminate network generation time or the need to verify a page turn.

## Modules

| Module | Responsibility |
| --- | --- |
| `gemini_book.lua` | Main state machine, UI, capture/save flow, and integration |
| `gemini_book_core.lua` | Prompt/response protocol and Markdown/HTML rendering |
| `gemini_book_ax.lua` | Scoped accessibility traversal |
| `gemini_book_focus.lua` | Book focus and page-turn delivery checks |
| `gemini_book_skill.lua` | Optional Gemini skill-selection flow |
| `gemini_book_limits.lua` | Usage-limit text recognition and notice classification |
| `gemini_book_resume.lua` | Model/reset-notice parsing and resume policy helpers |
| `gemini_book_prior_reply.lua` | Matching an earlier pending reply after a retry |
| `gemini_book_source.lua` | Reviewed navigation-reference policy |
| `gemini_book_jobs.lua` | Saved-job validation and discovery |
| `gemini_book_names.lua` | Title normalization, folder selection, and path rewriting |
| `gemini_book_rename.lua` | Journaled rename transaction and rollback |
| `gemini_book_move.py` | macOS atomic rename with no replacement of an existing destination |
| `gemini_book_status.lua` | Pure status/title/progress presentation |
| `gemini_book_illustrations.py` | Conservative artwork extraction from committed screenshots |
| `gemini_book_portable.py` | Confined image optimization and verified derivative cache |
| `gemini_book_epub.lua` | Asynchronous EPUB queue and result validation |
| `gemini_book_epub.py` | EPUB packaging, composed layouts, and reading-flow cleanup |

The main module’s public functions support the menu and a few Console workflows. They are not a versioned remote API. In particular, diagnostic and review actions can pause automation; a function that looks like a status action is not necessarily free of desktop effects. `uiState()` is a pure presentation snapshot.

## Saved and derived data

`checkpoint.json` records the committed translation order and outstanding work. `sources/`, `responses/`, and `pages/` preserve evidence and accepted output. `page-metadata.json` indexes model observations.

HTML is derived from checkpoint records and the illustration manifest. Illustration overrides and reviewed layouts are tied to source checksums. EPUB export reads the selected HTML as its authority, so exporting a separately reviewed HTML copy preserves that copy’s corrections.

EPUB requests are coalesced and wait for active/queued illustration writers. Worker callbacks validate successful exit, JSON output, the requested output path, and a sufficient saved-screen count. A stale or duplicate callback must not start a competing writer or report a blocked export as successful.

The portable image cache includes both source and generated-JPEG hashes. Source art is retained. The exporter rejects remote image resources and paths outside the permitted illustration directory. Publishing the ZIP is atomic, and the EPUB `mimetype` entry is first and uncompressed.

Job renames run only while relevant writers are idle. The transaction rebases operational paths, preserves record/request identity, refuses destination replacement, and keeps a rollback journal. These behaviors matter more than the cosmetic folder name.

## Run offline tests

From the repository root, with Python 3.10+, Pillow, and Lua 5.4:

```sh
python3 -m pip install "Pillow>=10.1,<13"
python3 -m unittest discover -s tests -p 'test_*.py' -v
for file in tests/test_*.lua; do lua "$file" || exit; done
```

Use `lua5.4` if that is your interpreter’s executable name. Prefer a Python virtual environment for development. [The test guide](../tests/README.md) describes the coverage and environment.

Fixtures contain generated images, invented text, temporary directories, and in-memory Hammerspoon stand-ins. They do not read a developer’s real book folders or control Chrome. CI runs the portable suites; it cannot prove that a current Gemini sidebar exposes the expected controls on macOS.

## Change and review expectations

Keep desktop operations behind checks for the intended window, source, and phase. Avoid changes that resend a sent request, advance from an uncertain position, accept an incomplete response, or write a checkpoint after a cancelled callback.

Use synthetic fixtures for regressions. Cover interrupted operations and failure paths when changing persistence, request handling, or file publication. A parser fix should preserve complete book text and reject ambiguous protocol blocks rather than silently repair missing content.

Changes to source geometry, focus, Send/Copy control identification, or accessibility traversal need a short manual macOS test with authorized material. Start with a one-screen or three-screen batch. Verify pause/stop behavior and the saved request/source association. Do not use a contributor’s real book archive as a test fixture.

For export changes, inspect both package structure and rendered pages. Test a portrait illustration, a reviewed cover, text-only captures, an empty capture, model metadata, unusual punctuation, and paragraph continuity. Browser rendering is useful, but native Apple Books remains a separate compatibility check.

## Known boundaries

- Chrome/Gemini UI labels and accessibility trees can change independently of this repository.
- The selected model observation does not reveal Gemini’s internal serving model.
- Artwork detection is heuristic, and translated page typography requires reviewed layout metadata.
- A batch target is not automatic end-of-book detection.
- EPUB cleanup removes known export scaffolding; it does not repair translation omissions or join uncertain sentence fragments.
- The rename helper uses macOS `renamex_np` and is not a cross-platform filesystem utility.
