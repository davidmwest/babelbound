# Installation and configuration

## Requirements

- macOS with [Hammerspoon](https://www.hammerspoon.org/) installed and running.
- Google Chrome, using the standard `com.google.Chrome` application bundle by default.
- Access to Gemini’s Chrome sidebar or the official ChatGPT extension, and a BOOKWALKER tab the chosen provider can read. [ChatGPT setup](chatgpt.md) is experimental.
- Python 3.10 or newer, with Pillow available to the interpreter used by the helpers.
- Accessibility and Screen Recording permission for Hammerspoon.

The illustration extractor uses image analysis, not OCR. The EPUB exporter renders reviewed text layouts with local fonts and Pillow. Neither helper calls a model or downloads book content.

## Install the files

From the repository directory:

```sh
./scripts/install.sh
```

The installer copies the Lua modules and Python helpers into `~/.hammerspoon`, creates `~/.hammerspoon/.bt-venv`, and installs `Pillow>=10.1,<13` in that environment. It backs up replaced files and `init.lua` under `bt-backups/<timestamp>` inside the configuration directory.

An existing customized prompt is retained; the bundled default is written as a `.dist` file for comparison. The installer appends the following line to `init.lua` only if it is absent:

```lua
GeminiBook = require("gemini_book")
```

If that file already contains other automation, retain it and add the module load once. A Hammerspoon configuration is Lua code; do not replace an existing configuration blindly. Choose **Reload Config** from Hammerspoon’s menu after making changes. Babelbound’s menu appears as **BT**, short for **Book Translator**.

Hammerspoon’s [official setup guide](https://www.hammerspoon.org/go/) covers installation, Accessibility access, and configuration reloads.

Installer options:

| Option | Purpose |
| --- | --- |
| `--config-dir PATH` | Install into a different Hammerspoon configuration directory |
| `--python PATH` | Choose the Python 3.10+ interpreter that creates the helper environment |
| `--no-init` | Copy files without adding the load line to `init.lua` |
| `--skip-deps` | Reuse an existing working `.bt-venv` without installing dependencies |
| `--dry-run` | Show planned installation work without making changes |

If `init.lua` ends with a top-level `return`, the installer stops before changing application files. Use `--no-init`, then add the Babelbound load line before that return yourself.

The installer does not restart Hammerspoon or change macOS permissions. A custom `--config-dir` must match the directory Hammerspoon actually uses; the flag does not reconfigure Hammerspoon itself.

## Permissions and Chrome setup

Enable Hammerspoon in macOS **System Settings → Privacy & Security → Accessibility**. Also allow screen recording when Babelbound requests it; the exact setting label varies between macOS versions. Restart Hammerspoon if macOS asks you to do so.

Open the BOOKWALKER reader and Gemini sidebar in the same Chrome window. Share the book tab with Gemini. Confirm manually that Gemini can access the visible page before attempting automation. Keep the editor empty and close any model picker or modal dialog before starting.

For ChatGPT, choose **BT → Provider → ChatGPT extension**, open the official extension’s side panel, and follow [its setup guide](chatgpt.md). Calibrate each provider separately. Restoring a saved job selects its recorded provider and stays paused.

Babelbound relies on accessibility roles, control labels, window geometry, and calibrated coordinates. Different Chrome builds, UI languages, and account features can expose different controls. A successful installation does not guarantee that every Gemini interface variant is supported.

## Configuration

The defaults are defined in `hammerspoon/gemini_book.lua`. Relevant options include:

| Option | Default behavior |
| --- | --- |
| `provider` | `gemini` on first use; subsequent menu choices are remembered |
| `defaultRequestMode` | `inline`: send the translation prompt directly |
| `skill` | `/ln`, used only for the explicit skill workflow |
| `defaultBatch` | Three screens or spreads |
| `outputRoot` | `~/Documents/GeminiBookTranslations` |
| `chromeBundle` | Standard Google Chrome |
| `promptFile` | `gemini_book_prompt.txt` in the Hammerspoon config directory |
| `illustrationsEnabled` | Build illustrated HTML from saved captures |
| `epubEnabled` | Queue an EPUB after a completed batch |
| `illustrationPython` | Python interpreter for illustration, EPUB, and job-move helpers |
| `pollSeconds` | Readiness checks target three starts per second |
| `pageStableSeconds` | Require two seconds of continuous image stability |
| `offerAutoResume` | Off; reset-time scheduling is explicitly chosen from the **BT** menu |

Set overrides in the global `GeminiBookConfig` table **before** requiring the module. For example, in `init.lua`:

```lua
GeminiBookConfig = {
    defaultBatch = 5,
    outputRoot = os.getenv("HOME") .. "/Documents/BookTranslations",
}
GeminiBook = require("gemini_book")
```

The default helper interpreter is `<Hammerspoon config directory>/.bt-venv/bin/python3`. To use another environment, set `illustrationPython` to its absolute Python path in the same pre-load table. That interpreter must have Pillow.

Some workers capture configuration when the module loads. Changing a field in the Console later does not reliably reconfigure every worker. Pause and reload after changing startup configuration.

The prompt file is plain text. You can customize translation tone or terminology, but retain the request-ID markers, source anchors, `[[TEXT]]` separator, and error/completion rules. The parser rejects malformed or mismatched responses.

## Manual helper use

The Python helpers can run independently of Hammerspoon. Use an interpreter with Pillow installed. These commands operate on saved files and do not turn pages or contact Gemini:

```sh
python3 hammerspoon/gemini_book_illustrations.py \
  --job "/path/to/Book-The Lantern Archive - Vol. 01"

python3 hammerspoon/gemini_book_epub.py \
  --html "/path/to/Book-The Lantern Archive - Vol. 01/translation.html" \
  --output "/path/to/Book-The Lantern Archive - Vol. 01/translation.epub" \
  --title "The Lantern Archive - Vol. 01"
```

The illustration command updates the illustration manifest and crops. In normal use, Hammerspoon also regenerates HTML from that manifest; running the extractor alone does not rewrite `translation.html`. The EPUB command treats the supplied HTML as the authoritative reading copy.

## Upgrading from Gemini Book Translator

Babelbound is the project’s name from version 1.4.3. The existing `gemini_book*` filenames, `GeminiBook` load line, `GeminiBookConfig` overrides, and `.bt-venv` helper environment keep their names. The default output folder remains `~/Documents/GeminiBookTranslations`. Existing saved jobs, calibration, and settings do not need a migration.

Use the normal update procedure below with the same Hammerspoon configuration directory. There is no need to rename job folders, create replacement jobs, or translate saved screens again.

## Updates and removal

Pause translation and wait for illustration/EPUB work to finish before updating installed files. Keep a backup of customized prompts, configuration, and saved job folders. After updating, reload Hammerspoon and restore the desired saved job; a reload does not automatically resume it.

To disable Babelbound, remove or comment out its load line in `init.lua`, then reload Hammerspoon. Saved jobs remain in the output directory. Removing the installed `gemini_book*` modules and helper environment is a separate manual cleanup; do not remove saved jobs unless you intend to delete that work.
