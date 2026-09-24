# Usage and recovery

## Calibrate the visible reader

Arrange the BOOKWALKER content to the left of the Gemini sidebar in one Chrome window, on one display. Keep that window size and position stable while running a batch.

Choose **BT → Calibrate** or press **Control–Option–Command–C** to begin. For each prompt, hover over the requested position and press the same shortcut again:

| Step | Hover position |
| --- | --- |
| 1 | Middle of Gemini’s empty input field |
| 2 | BOOKWALKER’s forward page-turn target |
| 3 | Top-left of the book-content rectangle |
| 4 | Bottom-right of the book-content rectangle |
| 5 | Just inside the Gemini pane’s top-left, below Chrome’s toolbar |

The book crop must be entirely left of the Gemini pane and include all visible book text. Check the forward direction yourself: a Japanese reader’s next-page target may differ from an English reader’s.

Use **Preview source crop** to inspect the result. If only the forward target needs adjustment, use **Set forward click only**, then hover and press **Control–Option–Command–N** again. This records a point without turning the page.

Moving/resizing the window, changing display scaling, or changing sidebar width may require recalibration. A different source book also needs a deliberate new-job or restore choice.

## Start, pause, and resume

**New job on current screen** creates a separate job beginning at screen 00001. It asks for a batch size from 1 to 1,000. The title is derived from the guarded reader window when possible; otherwise you enter it. The job starts after creation.

**Start / resume — [book title]** continues the loaded job. If no job is loaded, it restores the latest saved job and stays idle for review. It never silently creates a new book.

**Pause / resume** pauses local automation. Gemini may still finish a request already sent. **STOP** also retains all committed translations and pending-request information. Neither action deletes a job or undoes a page turn.

A completed batch leaves its last translated source screen visible. Start / resume then asks for additional screens. The software does not infer that reaching a requested count means the entire book is finished.

Avoid typing, changing tabs, opening dialogs, or turning the book manually while a batch is active. BT uses focus, screenshot, request-ID, and clipboard checks, but it still shares your desktop input.

## Status and percentage

| Menu-bar state | Meaning |
| --- | --- |
| `BT ready` | No active work, or a new job ready to start |
| `BT checking (N%)` | Verifying focus, source, or request state |
| `BT turning (N%)` | Delivering or verifying one page turn |
| `BT translating (N%)` | Submitting or waiting for Gemini |
| `BT saving (N%)` | Collecting a response or building reading copies |
| `BT paused` | Unfinished work was deliberately paused |
| `BT warning` | An error or uncertain state needs attention |
| `BT finished` | The requested batch completed |
| `BT scheduled` | An explicitly scheduled reset-time resume is waiting |

Percentage is `saved screens ÷ (saved screens + remaining requested screens)`, rounded down. Pending responses are not counted as saved. Adding a batch extends the target, so the percentage can decrease. This is progress toward the current job target, not a measured fraction of the physical book.

Hover over BT for the title, saved count, remaining count, and warning reason. **Status** displays more information but pauses an active run to keep the overlay out of source captures. **Show last pause/error** also stops active collection before showing its message.

## Shortcuts

Every shortcut uses **Control–Option–Command** plus the listed key. Actions run when the key is released.

| Key | Action |
| --- | --- |
| C | Calibrate / record the next calibration point |
| N | Set forward click only / record its new position |
| S | Start / resume the loaded job |
| P | Pause / resume |
| X | STOP; retain saved work |
| M | Accept a manually reviewed clipboard response |
| D | Dismiss the current message |

## Saved jobs and names

**Choose saved job…** lists saved jobs; **Restore latest saved job** restores the most recently updated valid checkpoint. Restoring preserves pending requests and does not send a prompt or turn a page.

Use **Rename current job…** to change the folder and displayed title. BT adds `Book-` and handles name collisions with suffixes such as `(2)`. Pause first, cancel any scheduled resume, and let illustration/EPUB work finish. Rename is disabled while a writer could still be using the old paths.

Request IDs do not depend on the folder title. Renaming updates operational paths while preserving translations, source captures, and pending-request identity. Use BT’s rename action instead of renaming an active job folder in Finder.

## Recover a pending response

Start with **Show last pause/error**. A request that has already been sent must not automatically be sent again merely because collection failed.

If Gemini has already produced the complete response, **Collect existing pending reply only (test one)** attempts to collect and save that reply without submitting another prompt or turning the book. **Collect earlier reply from before Retry (test one)** is for recovering a response associated with an earlier pending request.

**Retry pending screen (clear Gemini input first)** is an explicit resend workflow. Keep the book on the pending source screen and clear an unfinished input draft before using it. The tool records request history so older replies can be distinguished from the current request.

**Recover pending screen with direct prompt (test one)** provides a guarded one-screen recovery path. **Continue with manually selected ln skill** is for the optional skill workflow when you have selected the skill yourself.

**Accept reviewed clipboard** asks you to confirm that the copied response is a complete translation of the displayed page. It can override repeated-anchor rejection after review; it does not remove the request-ID or source-image checks.

## Recover a page-position warning

A page turn is one click followed by verification. If the image does not change, changes ambiguously, or changes unexpectedly, BT records the uncertainty and pauses. It does not repeatedly click until something happens.

Return to the pending source image when a pending request exists. Otherwise, compare the current book position with the last saved source. **Review last saved source** supports a deliberate review when the page is the same but its appearance has changed. Follow the comparison and confirmation prompts; do not assume that a changed screenshot is automatically the next page.

## Usage limits

BT recognizes supported limit notices and preserves a complete reply when it can. A timeout is a warning, never evidence that a translation finished. Select the model you want in Gemini, close the picker, and resume when the service is available.

Reset-time resume is off by default. **Schedule auto-resume from reset notice** is an opt-in local timer based on a recognized notice. It does not bypass account limits or run after an arbitrarily late wakeup. **Cancel auto-resume**, Stop, and reload cancel that scheduled action.
