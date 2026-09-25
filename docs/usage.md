# Usage and recovery

Babelbound’s compact menu-bar label is **BT**, short for **Book Translator**.

## Find your next action

The top of the menu identifies the loaded book, provider, last observed model, and progress toward the requested screen count. Opening the menu is passive: it does not pause translation, inspect the browser, or move focus.

The primary action changes with the job:

| What is happening | Primary action |
| --- | --- |
| Calibration is missing | **Set up translator…** |
| No book is loaded | **Start translating…** |
| Translation is running | **Pause — [title]** |
| Resume or recovery checks are running | **Checking — [title]…**, disabled; **Stop automation** is immediately below |
| A resume is scheduled | **Resume now — [title]**; **Cancel scheduled resume** is immediately below |
| The page position needs review | **Review page position — [title]…** |
| Another warning needs attention | **Review problem — [title]…** |
| The job is normally paused | **Resume — [title]** |
| The requested batch is complete | **Translate more — [title]…** |

Four groups keep the other controls in a consistent place:

- **Read translation:** open the HTML reading copy, EPUB in Books, or output folder. While automation is active, the label says **Pause and open…**. Opening an output pauses local work and cancels resume checks or a scheduled resume before changing focus.
- **Books:** start a new book, open a saved book, or rename the loaded book.
- **Setup:** select the translation provider, calibrate, adjust the forward-click target, or preview the source crop.
- **Advanced:** recover a pending response, schedule a supported usage-reset resume, rebuild reading copies or EPUB, inspect diagnostics, or stop automation.

Book changes, provider changes, and calibration are unavailable while translation or recovery checks are active, or while a resume is scheduled. Pause or cancel the scheduled action first. Rename also waits for background saves to finish. The handlers check these conditions again if an open menu becomes stale.

## Calibrate the visible reader

Arrange the BOOKWALKER content to the left of the selected provider’s sidebar in one Chrome window, on one display. Keep that window size and position stable while running a batch.

Choose **BT → Setup → Calibrate…** or press **Control–Option–Command–C** to begin. For each prompt, hover over the requested position and press the same shortcut again:

| Step | Hover position |
| --- | --- |
| 1 | Middle of the provider’s empty input field |
| 2 | BOOKWALKER’s forward page-turn target |
| 3 | Top-left of the book-content rectangle |
| 4 | Bottom-right of the book-content rectangle |
| 5 | Just inside the chat pane’s top-left, below Chrome’s toolbar |

The book crop must be entirely left of the chat pane and include all visible book text. Check the forward direction yourself: a Japanese reader’s next-page target may differ from an English reader’s.

Use **Setup → Preview source crop** to inspect the result. If only the forward target needs adjustment, use **Adjust forward-click target…**, then hover and press **Control–Option–Command–N** again. This records a point without turning the page.

Moving/resizing the window, changing display scaling, or changing sidebar width may require recalibration. A different source book also needs a deliberate new-book or open-book choice.

## Start, pause, and resume

**Setup → Translation provider** selects Gemini or the experimental ChatGPT extension. Each keeps its own calibration and most recently used job. Switching providers unloads the paused job while retaining its checkpoint; opening that job selects its original provider. ChatGPT always uses direct prompts. [ChatGPT setup and limitations](chatgpt.md).

**Books → Start a new book…** creates a separate job beginning at screen 00001. It asks for a batch size from 1 to 1,000. The title is derived from the guarded reader window when possible; otherwise you enter it. The job starts after creation. With no book loaded, the primary **Start translating…** action opens this same setup. It does not restore a previous book.

**Resume — [book title]** continues a normally paused job after checking the source. If a sent request is pending, it collects that reply before sending anything new. Warnings lead to a review action instead of starting another request.

**Pause** stops local continuation. The provider may still finish a request already sent. **Stop automation** also cancels local resume/recovery checks and scheduled resume, while retaining all committed translations and pending-request information. Neither action deletes a job or undoes a page turn.

A completed batch leaves its last translated source screen visible. **Translate more — [title]…** asks for additional screens. This release uses fixed counts; it does not infer that reaching a requested count means the entire book is finished. Continuous scopes and end-of-book review remain in the [whole-book plan](menu-and-whole-book-design.md).

Avoid typing, changing tabs, opening dialogs, or turning the book manually while a batch is active. Babelbound uses focus, screenshot, request-ID, and clipboard checks, but it still shares your desktop input.

## Status and percentage

| Menu-bar state | Meaning |
| --- | --- |
| `BT ready` | No active work, or a new job ready to start |
| `BT checking (N%)` | Verifying focus, source, or request state |
| `BT turning (N%)` | Delivering or verifying one page turn |
| `BT translating (N%)` | Submitting or waiting for the selected provider |
| `BT saving (N%)` | Collecting a response or building reading copies |
| `BT paused` | Unfinished work was deliberately paused |
| `BT warning` | An error or uncertain state needs attention |
| `BT finished` | The requested batch completed |
| `BT scheduled` | An explicitly scheduled reset-time resume is waiting |

Percentage is `saved screens ÷ (saved screens + remaining requested screens)`, rounded down. Pending responses are not counted as saved. Adding a batch extends the target, so the percentage can decrease. This is progress toward the current job target, not a measured fraction of the physical book.

The summary keeps translation activity and export problems separate. An EPUB failure does not turn an active job’s **Pause** action into **Resume**. The model label reports the last observed selection; it is not a live query of an open picker.

Hover over **BT** for the title, saved count, remaining count, and warning reason. **Advanced → Diagnostics** contains details, browser-control inspection, and the last message. Dialog actions say **Pause and…** when they will interrupt active work; they also cancel pending checks or a scheduled resume before opening.

## Shortcuts

Every shortcut uses **Control–Option–Command** plus the listed key. Actions run when the key is released.

| Key | Action |
| --- | --- |
| C | Calibrate / record the next calibration point |
| N | Adjust the forward-click target / record its new position |
| S | Perform the primary action shown at the top of the menu |
| P | Pause active translation or resume a normally paused job; never bypass a warning or start another batch |
| X | Stop local automation, recovery checks, and scheduled resume; retain saved work |
| M | Save a manually reviewed clipboard response |
| D | Dismiss the current message |

## Saved jobs and names

**Books → Open saved book…** lists saved jobs; **Open most recent book** opens the latest saved job. Opening preserves pending requests and stays paused. It does not send a prompt or turn a page.

Use **Books → Rename this book…** to change the folder and displayed title. Babelbound adds `Book-` and handles name collisions with suffixes such as `(2)`. Pause first, cancel any scheduled resume, and let illustration/EPUB work finish. Rename is disabled while a writer could still be using the old paths.

Request IDs do not depend on the folder title. Renaming updates operational paths while preserving translations, source captures, and pending-request identity. Use Babelbound’s rename action instead of renaming an active job folder in Finder.

## Recover a pending response

Start with the primary **Review problem…** action or **Advanced → Diagnostics → Show last message…**. A request that has already been sent must not automatically be sent again merely because collection failed. Recovery commands live under **Advanced → Recovery**; unavailable commands explain what is missing.

If the provider has already produced the complete response, **Collect existing reply and pause** attempts to collect and save that reply without submitting another prompt or turning the book. **Recover earlier reply…** recovers a response associated with an earlier pending request.

**Resend pending request…** is an explicit resend workflow. Keep the book on the pending source screen and clear an unfinished input draft before using it. The tool records request history so older replies can be distinguished from the current request.

**Use direct prompt for this screen…** provides a guarded one-screen recovery path for an unsent request. **Continue with selected Gemini skill** is for the optional Gemini skill workflow when you have selected the skill yourself.

**Save reviewed clipboard…** asks you to confirm that the copied response is a complete translation of the displayed page. It can override repeated-anchor rejection after review; it does not remove the request-ID or source-image checks.

## Recover a page-position warning

A page turn is one click followed by verification. If the image does not change, changes ambiguously, or changes unexpectedly, Babelbound records the uncertainty and pauses. It does not repeatedly click until something happens.

Use **Review page position…** and compare the current reader with the saved source and turn evidence. Return to the pending source image when a pending request exists. **Advanced → Recovery → Review saved source…** supports a deliberate review when the content is the same as the last saved page but its appearance has changed. It does not clear an uncertain turn. Follow the comparison and confirmation prompts; do not assume that a changed screenshot is automatically the next page.

## Usage limits

Babelbound recognizes supported limit notices and preserves a complete reply when it can. A timeout is a warning, never evidence that a translation finished. Select the model you want in the provider, close the picker, and resume when the service is available.

Reset-time resume is off by default. **Advanced → Resume after usage reset…** is an opt-in local timer based on a recognized notice for a supported provider. It does not bypass account limits or run after an arbitrarily late wakeup. **Cancel scheduled resume**, Stop, and reload cancel that scheduled action. A scheduled job’s **Resume now** action cancels the timer before normal guarded resume checks.

## Repair a reading copy

Completed batches automatically queue an EPUB. If export fails, the committed translations remain saved. **Advanced → Rebuild EPUB** (shown as **Retry EPUB export** after a failure) retries export from the saved reading copy, without submitting a request or turning a page. **Rebuild reading copy** rescans the saved sources for illustrations and rebuilds the HTML. Background writers must finish before conflicting rebuild or rename work can start.
