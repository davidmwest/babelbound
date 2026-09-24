# Gemini Book Translator

I wanted to read a book in English without constantly moving between the reader, Gemini, and a saved document. The routine was getting ridiculous: translate a page, copy the response, save it, turn the page, repeat. If something got stuck, figure out which of those steps had actually happened.

Gemini Book Translator handles that loop from a **BT** menu in macOS. It translates the visible BOOKWALKER page through Gemini in Chrome, keeps resumable jobs, and produces illustrated HTML and EPUB reading copies.

**Version 1.4.1 · macOS · Hammerspoon · Lua + Python**

I developed this with Codex, using the running desktop workflow to find problems and drive the next changes. The implementation and regression tests were AI-assisted. You don't need Codex or a Gemini API key to run it; BT uses your existing Gemini sidebar and selected model.

## What it does

- Translates batches of visible screens or spreads, saving each accepted response before turning the page.
- Resumes saved jobs with checks for the correct source page and any pending response.
- Shows the loaded book title in **Start / resume** and progress such as **BT translating (42%)**.
- Distinguishes deliberate pauses, warnings, active work, and finished batches.
- Stores jobs in named folders such as `Book-The Lantern Archive - Vol. 01`.
- Records the model observed in Gemini’s interface for each translation.
- Extracts illustrations from saved captures and inserts them in reading order.
- Exports a self-contained EPUB for Apple Books, including artwork and any reviewed English cover layouts.

## The tricky part

Keeping a page, a request, and a saved translation in agreement gets surprisingly involved when any one of them stalls.

| Problem encountered | What changed |
| --- | --- |
| Gemini finished, but Copy failed | Persist the pending request and collect the existing reply before considering a resend |
| A page-turn click did nothing | Record turn state first, deliver one click, and verify a stable image change |
| Every idle state looked like “paused” | Separate warnings, deliberate pauses, finished batches, and active work |
| Faster polling could still read a moving page | Check readiness roughly three times a second while retaining an independent two-second stability check |
| Moving HTML to an iPad lost the images | Package text and artwork together in EPUB |
| One EPUB chapter per capture created blank spreads | Use one continuous reading document with screen anchors for navigation |

The [design notes](docs/design-notes.md) explain those choices. This is still desktop UI automation: Chrome, Gemini, the reader layout, and accessibility permissions have to cooperate. Try a short batch first, and review the translation.

## Install

You need macOS, Google Chrome with a working Gemini sidebar, [Hammerspoon](https://www.hammerspoon.org/), and [Python 3.10 or newer](https://www.python.org/downloads/macos/). The illustration and EPUB helpers use Pillow.

Download or clone this repository, then run from its directory:

```sh
./scripts/install.sh
```

The installer creates a helper environment, copies the modules, backs up files it replaces, and adds the load line to your Hammerspoon configuration if absent:

```lua
GeminiBook = require("gemini_book")
```

Use Hammerspoon’s **Reload Config** after installation. Grant Hammerspoon Accessibility and Screen Recording access when prompted. See [installation and configuration](docs/installation.md) for the full setup, updates, and custom paths. Hammerspoon’s [Getting Started guide](https://www.hammerspoon.org/go/) explains its configuration and reload controls.

## First translation

1. Open a book you have permission to translate in BOOKWALKER’s Chrome reader.
2. Open Gemini in the sidebar of that same Chrome window. Share the book tab with Gemini and select the model you want to use. Leave the input empty.
3. Keep the book on the left and Gemini on the right, with the window on one display.
4. Choose **BT → Calibrate**, then follow the five hover prompts using **Control–Option–Command–C**. No clicking is needed to record the points.
5. Choose **Preview source crop**. Check that it contains the whole visible book page or spread, without browser controls or the Gemini pane.
6. Choose **New job on current screen** and start with three screens. The current visible screen is the first one. A screen may contain more than one printed page.
7. Let the automation use that Chrome window. **Control–Option–Command–P** pauses it; **Control–Option–Command–X** stops it while retaining saved work.

The normal request mode sends the bundled translation prompt directly. Creating a Gemini `/ln` skill is optional.

When the requested batch completes, BT leaves the last translated screen visible and builds the reading copy. **BT → Open EPUB in Books** opens the saved ebook on the Mac. Transfer `translation.epub` to your iPad and open it in Books; the illustrations travel inside the file.

## Continue a book

Use **Start / resume — [book title]** to continue the loaded job. After a reload, use **Restore latest saved job** or **Choose saved job…**, review the book’s position, then resume. Restoring does not start translation.

If the previous batch is finished, Start / resume asks how many additional screens to translate. **Finished means the requested batch is complete, not that BT has independently detected the end of the book.**

Read [usage and recovery](docs/usage.md) before retrying a pending request or an uncertain page turn.

## Saved output

The default output root is `~/Documents/GeminiBookTranslations`. Each job contains its checkpoint, source captures, individual translations, model metadata, and reading copies:

```text
GeminiBookTranslations/
└── Book-The Lantern Archive - Vol. 01/
    ├── checkpoint.json
    ├── page-metadata.json
    ├── translation.md
    ├── translation.html
    ├── translation.epub
    ├── sources/
    ├── pages/
    ├── responses/
    └── illustrations/
```

Use **Rename current job…** to change a title while the job is paused and background saves have finished. BT updates the job’s paths without changing its request IDs or translated text.

## Documentation

- [Installation and configuration](docs/installation.md)
- [Usage, shortcuts, statuses, and recovery](docs/usage.md)
- [Illustrations, HTML, EPUB, and model metadata](docs/reading-copies.md)
- [Troubleshooting](docs/troubleshooting.md)
- [Design notes](docs/design-notes.md)
- [Architecture and contributing](docs/architecture.md)

## Testing and limits

The repository includes synthetic Python and Lua regression suites for response parsing, duplicate-submit prevention, source review, renames, status, illustration assets, and EPUB output. [Run them locally](tests/README.md); CI runs the portable suites. Native Chrome interaction and Apple Books pagination also need manual macOS testing. A passing parser test can't tell you that Google moved a button.

The current integration targets macOS, the standard Chrome application, BOOKWALKER’s visible reader, and Gemini’s sidebar. English UI labels are the default. It is not a headless browser crawler and cannot translate unseen pages without turning to them. It does not automatically change models or assess their translation quality.

BT stores screenshots, translations, and diagnostic traces locally. Gemini processes the shared page through your existing Chrome session. The source repository contains no books, saved jobs, credentials, or personal browser state.
