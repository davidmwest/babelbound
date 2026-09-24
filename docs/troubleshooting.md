# Troubleshooting

Start with **BT → Show last pause/error** and note the loaded book title. A warning is a request for review; clicking Retry repeatedly can obscure which request or page needs attention.

## BT does not appear

Open Hammerspoon’s Console and inspect the load error. Confirm the `gemini_book*.lua` files are in the Hammerspoon configuration directory and `init.lua` loads the module once. After changing files, choose **Reload Config**.

The installer does not start or restart Hammerspoon. If the modules loaded but a shortcut does nothing, check for conflicts with other Hammerspoon bindings or macOS shortcuts.

## New job will not start

Bring the calibrated Chrome window to the front. Ensure the book and Gemini sidebar are visible, the input is empty, and there is no open picker or dialog. Complete calibration, then inspect **Preview source crop**.

Check Hammerspoon’s Accessibility and Screen Recording permissions. A changed window frame or invalid crop is intentionally rejected. Do not create another job just to recover an existing job: choose the saved job instead.

## Typing, Send, or Copy cannot be verified

BT uses Chrome’s accessibility tree to identify the actual composer and controls. A Chrome/Gemini update, localized label, expanded editor, or a very long conversation can change those details.

Pause, close temporary menus, leave a clean editor, and try the relevant recovery action. **Accessibility diagnostics** writes a local diagnostic report; it also pauses active work so its overlays do not affect captures. The default `inputPlaceholders` list is configurable, but adding a label does not by itself guarantee correct focus behavior.

Do not replace verification with blind Return presses or unrestricted clicks when debugging. Request IDs, source checks, and readback are what keep a response associated with the right capture.

## Gemini finished, but nothing was saved

Look for a pending request and inspect the error. A visible response may be incomplete, use the wrong request ID, lack the required END marker, contain an error block, or fail source-anchor checks.

Use **Collect existing pending reply only (test one)** when the complete reply already exists. It avoids a new submission. Review the full response before using **Accept reviewed clipboard**. Merely reaching a timeout never marks the screen complete.

## A page turn failed or the source changed

BT pauses when it cannot establish a single, stable next screen. Verify the book position against the saved image before continuing. A changed zoom level, crop, sidebar width, or layout can also change the screenshot fingerprint.

Use **Set forward click only** if the target is wrong. Use **Review last saved source** when the content matches the last saved page but its appearance changed. If the turn is uncertain, follow the explicit review/retry workflow instead of turning another page yourself and guessing which capture it represents.

## BT says finished too early

**Finished** refers to the requested batch, not the entire source book. Use Start / resume to add more screens. The percentage target is saved screens plus the current requested remainder; it does not use the reader’s total printed-page count.

## Gemini reached a limit

A selected fallback model can still be used when Gemini makes it available. Close the model picker before resuming. The displayed model tag is diagnostic, not a Pro-only requirement.

Recognized account-limit errors still pause the job. Either resume manually when available or explicitly choose **Schedule auto-resume from reset notice**. Scheduling cannot overcome a service limit or a lost login/session.

## Illustrations or EPUB failed

Confirm that the configured Python interpreter exists and can import Pillow. The installed default is `<Hammerspoon config directory>/.bt-venv/bin/python3`.

```sh
"$HOME/.hammerspoon/.bt-venv/bin/python3" -c 'from PIL import Image; print(Image.__version__)'
```

For a custom configuration directory, adjust that path. If needed, rerun the installer with the desired `--python` interpreter. Set custom runtime paths in `GeminiBookConfig` before loading the module, then reload while paused.

**Rebuild illustrated reading copy (all saved screens)** recreates the manifest from committed captures. A missing or mismatched source image should be investigated before rebuilding. EPUB work waits for the illustrated HTML to be ready; an illustration failure can therefore block the export while leaving saved translations intact.

## Images disappear after copying HTML to iPad

The HTML references its adjacent `illustrations` directory. Use `translation.epub` for a single portable file. The EPUB contains its image resources and does not need the Mac’s folder paths.

## Excess blank pages or visible `[continues]` in Books

Regenerate the EPUB with the current exporter and reimport the new file. The current exporter uses one continuous reading document, removes generated capture furniture and continuation markers, and fits artwork to the page. An old Books import can still contain the earlier layout even after the disk file is rebuilt.

## A job cannot be renamed

Pause translation, cancel any scheduled auto-resume, and wait for illustration/EPUB saves to finish. Rename checks the saved checkpoint against the loaded job and refuses conflicting state.

If a rename reports that recovery is required, retain the `.job-renames` journal and both affected folder locations. The engine stops using uncertain paths. Resolve that transaction before resuming; do not delete the journal as a routine cleanup.

## Report a reproducible problem

Include the BT version, macOS/Chrome/Hammerspoon versions, the exact menu action, the error text, and whether the job had a sent pending request or uncertain turn. A short synthetic reproduction is preferable.

Local diagnostics can contain book text, screenshots, titles, and file paths. Review and redact them before attaching an issue. Do not include session tokens, account credentials, or full book archives. See [architecture and contributing](architecture.md) for offline tests and manual validation boundaries.
