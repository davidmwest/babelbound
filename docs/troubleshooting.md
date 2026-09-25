# Troubleshooting

Babelbound’s compact menu-bar label is **BT**, short for **Book Translator**.

Start with the primary **Review problem…** or **Review page position…** action and note the loaded book title. **Advanced → Diagnostics → Show last message…** also shows the latest explanation. A warning is a request for review; repeatedly resending can obscure which request or page needs attention.

## The BT menu does not appear

Open Hammerspoon’s Console and inspect the load error. Confirm the `gemini_book*.lua` files are in the Hammerspoon configuration directory and `init.lua` loads the module once. After changing files, choose **Reload Config**.

The installer does not start or restart Hammerspoon. If the modules loaded but a shortcut does nothing, check for conflicts with other Hammerspoon bindings or macOS shortcuts.

## New job will not start

Bring the calibrated Chrome window to the front. Ensure the book and selected provider’s sidebar are visible, the input is empty, and there is no open picker or dialog. Complete **Setup → Calibrate…**, then inspect **Setup → Preview source crop**.

Check Hammerspoon’s Accessibility and Screen Recording permissions. A changed window frame or invalid crop is intentionally rejected. Do not create another job just to recover an existing job: use **Books → Open saved book…** instead. New/open book, provider changes, and calibration are disabled during active work or a scheduled resume; pause or cancel the scheduled action first.

## Typing, Send, or Copy cannot be verified

Babelbound uses Chrome’s accessibility tree to identify the actual composer and controls. A Chrome/Gemini update, localized label, expanded editor, or a very long conversation can change those details.

Pause, close temporary menus, leave a clean editor, and try the relevant action under **Advanced → Recovery**. **Advanced → Diagnostics → Inspect browser controls…** writes a local diagnostic report; its label includes **Pause and…** during active work because the overlay must not affect captures. The default `inputPlaceholders` list is configurable, but adding a label does not by itself guarantee correct focus behavior.

Do not replace verification with blind Return presses or unrestricted clicks when debugging. Request IDs, source checks, and readback are what keep a response associated with the right capture.

## Gemini finished, but nothing was saved

Look for a pending request and inspect the error. A visible response may be incomplete, use the wrong request ID, lack the required END marker, contain an error block, or fail source-anchor checks.

Use **Advanced → Recovery → Collect existing reply and pause** when the complete reply already exists. It avoids a new submission. Review the full response before using **Save reviewed clipboard…**. Merely reaching a timeout never marks the screen complete.

## A page turn failed or the source changed

Babelbound pauses when it cannot establish a single, stable next screen. Verify the book position against the saved image before continuing. A changed zoom level, crop, sidebar width, or layout can also change the screenshot fingerprint.

Use **Setup → Adjust forward-click target…** if the target is wrong. Use **Advanced → Recovery → Review saved source…** when the content matches the last saved page but its appearance changed. If the turn is uncertain, use the primary **Review page position…** workflow instead of turning another page yourself and guessing which capture it represents.

## BT says finished too early

**Finished** refers to the requested batch, not the entire source book. Use **Translate more — [title]…** to add more screens. The percentage target is saved screens plus the current requested remainder; it does not use the reader’s total printed-page count. Continuous whole-book translation remains planned.

## Gemini reached a limit

A selected fallback model can still be used when Gemini makes it available. Close the model picker before resuming. The displayed model tag is diagnostic, not a Pro-only requirement.

Recognized account-limit errors still pause the job. Review the problem when service is available, or explicitly choose **Advanced → Resume after usage reset…** for a supported provider. Scheduling cannot overcome a service limit or a lost login/session.

## Illustrations or EPUB failed

Confirm that the configured Python interpreter exists and can import Pillow. The installed default is `<Hammerspoon config directory>/.bt-venv/bin/python3`.

```sh
"$HOME/.hammerspoon/.bt-venv/bin/python3" -c 'from PIL import Image; print(Image.__version__)'
```

For a custom configuration directory, adjust that path. If needed, rerun the installer with the desired `--python` interpreter. Set custom runtime paths in `GeminiBookConfig` before loading the module, then reload while paused.

**Advanced → Rebuild reading copy** recreates the manifest from committed captures. A missing or mismatched source image should be investigated before rebuilding. EPUB work waits for the illustrated HTML to be ready; an illustration failure can therefore block the export while leaving saved translations intact.

If the HTML is ready and only the EPUB failed, use **Advanced → Retry EPUB export**. Otherwise this action is labeled **Rebuild EPUB**. This exports the saved reading copy without another translation request or page turn. The menu shows export errors separately from ongoing translation; an export failure does not mean the translator is paused.

## Images disappear after copying HTML to iPad

The HTML references its adjacent `illustrations` directory. Use `translation.epub` for a single portable file. The EPUB contains its image resources and does not need the Mac’s folder paths.

## Excess blank pages or visible `[continues]` in Books

Regenerate the EPUB with the current exporter and reimport the new file. The current exporter uses one continuous reading document, removes generated capture furniture and continuation markers, and fits artwork to the page. An old Books import can still contain the earlier layout even after the disk file is rebuilt.

## A job cannot be renamed

Pause translation, cancel any scheduled auto-resume, and wait for illustration/EPUB saves to finish. Rename checks the saved checkpoint against the loaded job and refuses conflicting state.

If a rename reports that recovery is required, retain the `.job-renames` journal and both affected folder locations. The engine stops using uncertain paths. Resolve that transaction before resuming; do not delete the journal as a routine cleanup.

## Report a reproducible problem

Include the Babelbound version, macOS/Chrome/Hammerspoon versions, the exact menu action, the error text, and whether the job had a sent pending request or uncertain turn. A short synthetic reproduction is preferable.

Local diagnostics can contain book text, screenshots, titles, and file paths. Review and redact them before attaching an issue. Do not include session tokens, account credentials, or full book archives. See [architecture and contributing](architecture.md) for offline tests and manual validation boundaries.
