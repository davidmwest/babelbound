# A simpler BT menu and whole-book translation

**Design and rollout plan · September 25, 2026 · Menu cleanup shipped in Babelbound 1.6.0**

**Stage 1 is implemented:** the grouped menu, state-dependent primary action, passive status summary, guarded actions, and separate EPUB repair work with existing fixed-count jobs. See [Usage](usage.md) for the shipped menu and shortcuts.

**Whole-book mode remains planned.** Continuous scopes, beginning/coverage evidence, endpoint review, and a reader-position adapter below describe later stages. Version 1.6.0 has no scope chooser or end-of-book confirmation; **Translate more** still asks for another screen count.

## The decision

Put the loaded book and its next useful action at the top. Keep four stable groups below it: **Read translation**, **Books**, **Setup**, and **Advanced**. Everyday use should not require choosing among several kinds of retry.

Add three explicit translation scopes: **Entire book**, **From here to the end**, and **A set number of screens**. The first two continue across internal work batches without asking for another count. They retain the existing save-before-turn and interruption checks.

Start with continuous translation and a reviewed endpoint. Add unattended end detection only for readers whose position and terminal controls have been inspected and tested. A missed click must never become a successfully finished book.

## What prompted the redesign

The 1.5.0 menu exposed calibration, daily use, recovery experiments, scheduling, and diagnostics together. Some labels described implementation history—“test one”—instead of what would happen.

Several actions also hid important differences:

- **Start / resume** could restore a job without starting, resume unfinished work, or ask for another batch.
- **Finished** means the requested screen count was saved. It does not establish that the book ended.
- **Pause** and **STOP** both retain saved work and pending requests. They do not cancel a response already generating in the provider.
- **Status** and **Show last pause/error** paused automation to display their dialogs without saying so in their labels.
- An EPUB failure could override the displayed status while translation was still running. A status label alone could not determine whether Resume was safe.

The menu should answer: **Which book? What is happening? What can I do next?** Detailed repair tools belong one level deeper.

## Menu direction

The four groups and primary-action rules are implemented for fixed-count jobs. The example below includes the planned whole-book progress display; scope and endpoint entries are not in version 1.6.0.

Example with a paused book and an unknown endpoint:

```text
BT paused
┌─────────────────────────────────────────────────┐
│ The Lantern Archive — Vol. 01                    │
│ Gemini · Flash                                  │
│ Paused · 42 screens saved · Entire book           │
│ Total length not available                       │
├─────────────────────────────────────────────────┤
│ Resume — The Lantern Archive — Vol. 01           │
├─────────────────────────────────────────────────┤
│ Read translation                              ▸ │
│ Books                                         ▸ │
│ Setup                                         ▸ │
│ Advanced                                      ▸ │
└─────────────────────────────────────────────────┘
```

The title may be visually shortened, but the tooltip and start dialog show the full name. The primary command always identifies the loaded book. The model is the last observed selection, labeled as such if stale; opening the menu does not query the browser or infer an unseen model.

```text
Read translation
  Open reading copy
  Open EPUB in Books
  Open output folder

Books
  Start a new book…
  Open saved book…
  Open most recent book
  Rename this book…
  Change translation scope…
  Review end of book…                [to-end jobs only]

Setup
  Translation provider             ▸ Gemini / ChatGPT extension (experimental)
  Calibrate…
  Adjust forward-click target…
  Preview source crop

Advanced
  Recovery                         ▸
  Resume after usage reset…         [supported providers only]
  Cancel scheduled resume           [only when armed]
  Rebuild reading copy
  Rebuild EPUB
  Diagnostics                      ▸
  Stop automation
```

Recovery contains **Collect existing reply and pause**, **Resend pending request…**, **Recover earlier reply…**, **Use direct prompt for this screen…**, **Continue with selected Gemini skill**, **Save reviewed clipboard…**, and **Review saved source…**. Unavailable entries remain disabled with a short reason. The optional Gemini skill stays an advanced compatibility feature; it is not a setup requirement.

Diagnostics contains **Pause and show details…**, **Pause and inspect browser controls…**, **Show last message…**, **Dismiss message**, and the version. Any dialog that still pauses work must say so in its active-state label. The summary at the top is passive: opening the menu never pauses, moves focus, captures a page, sends a prompt, or starts a job.

Keep shortcuts C/N/S/P/X/M/D. S dispatches the displayed Start/Resume/Translate more command and cannot bypass a required review. P pauses active translation or resumes a normally paused job; it does not dismiss a warning or silently start another batch. X remains an immediate stop/cancel for local automation, recovery, and scheduled resume, without deleting work or cancelling a provider response. Do not introduce a separate “stopped job” lifecycle just to justify a second button.

## One primary action, chosen from actual state

These rules use execution flags, pending state, navigation state, and scope—not just the display label. Where more than one rule applies, ongoing work and required review take precedence.

| Situation | Primary action | Result |
| --- | --- | --- |
| Actively translating, turning, or saving a reply | **Pause — [title]** | Stop local continuation; retain any sent request. |
| Resume checks or recovery in progress | **Checking — [title]…** (disabled) | Show **Stop automation** immediately below, not buried in Advanced. |
| Resume scheduled | **Resume now — [title]** | Cancel the timer and perform ordinary guarded resume checks. Show **Cancel scheduled resume** below. |
| Suspected endpoint | **Review end of book — [title]…** | Inspect the candidate and last saved content; never infer completion from the label. |
| Page position uncertain | **Review page position — [title]…** | Inspect the saved turn evidence before another turn or request. For a to-end job, this same review also offers endpoint confirmation when supported by the evidence. |
| Other blocking warning | **Review problem — [title]…** | Explain the failure and offer the applicable recovery action. |
| No usable calibration for the chosen provider | **Set up translator…** | Calibrate that provider; do not create or resume a job. |
| No loaded job | **Start translating…** | Open new-book setup. Opening a saved book is a separate command. |
| Paused, valid sent pending request | **Resume — [title]** | Collect the existing reply first. A detail line says “A reply is pending; it will not be sent again.” |
| Normally paused | **Resume — [title]** | Verify the book and continue its saved scope. |
| Fixed-count batch complete | **Translate more — [title]…** | Choose another count or continue to the end. |
| Endpoint confirmed, export unfinished | **Open reading copy — [title]**, if available | Show EPUB generation or failure separately, with **Retry EPUB export** on failure. If no readable output exists, offer **Rebuild reading copy** instead. |
| Endpoint confirmed, EPUB ready | **Open EPUB — [title]** | Open the finished ebook. New work is an explicit scope change. |

An export failure during active translation does not replace Pause with Resume. Show both facts: “Translating · EPUB needs attention.” Any foreground-opening action—HTML, Books, or the output folder—must first pause local automation and cancel active resume/recovery checks; label it **Pause and open…** while running. It also cancels a scheduled resume before changing focus.

Disable new/open book, provider changes, calibration, and scope changes during execution or resume/recovery checks. Rename also waits for illustration/export writers. Switching jobs, renaming, or changing scope while a timer is armed requires cancelling that timer first. Opening a saved job selects its saved provider and remains paused.

Enforce these gates again inside the action handlers. The menu can become stale between opening and clicking.

## Planned scope selection

Use a short native chooser/dialog flow, not a new settings application:

1. **Book:** suggest the reader's title, allow an edit, and show provider plus observed model. Keep the existing named output folder rules.
2. **Scope:** choose Entire book, From here to the end, or A set number of screens. The last option exposes a count; one screen is simply a count of 1. Remember the last scope for convenience, but always show it before starting. For a new calibration, suggest a three-screen check without forcing it.
3. **Starting position:** preview the crop. Entire book asks the user to move to the beginning and confirm that the visible content is the first reader page/spread. Other scopes start at the current verified position.
4. **Start — [title]:** a final explicit start action, with the chosen scope beside it. Cancelling setup leaves no empty job behind.

“Entire book” means all content in reader order, including covers, front matter, illustrations, and back matter. It does not stop at the end of the story. A screen can contain one page or a spread; “Screen 0001” is an archive index, not proof of book page 1.

Do not automatically rewind in the first release. A forward target calibrated by the user does not provide a verified route to the beginning. Starting at the beginning is user-confirmed unless a tested reader adapter can independently establish it.

For an existing job, **Change translation scope…** preserves saved records and IDs. Moving to a to-end scope does not retranslate earlier screens. A legacy job with no beginning evidence keeps **Beginning unknown**; a job started in the middle keeps **From here to the end**. Reaching the end cannot retroactively prove complete coverage.

Pausing is temporary. There is no “finish book” shortcut that discards an unresolved request. A user who wants to end a run early can change it to a fixed target of the already saved screens after resolving pending/turn state; label the result **Selected range complete**, with partial coverage.

## Whole-book behavior and tradeoffs

The current runtime verifies a calibrated Chrome window, a source-image fingerprint, response anchors, and a single forward-click attempt. It has **no reader adapter for book position, total length, first page, or last page**. Gemini and ChatGPT are translation-provider adapters; neither supplies a trustworthy book endpoint through its answer.

| Choice | Benefit | Cost or failure mode | Decision |
| --- | --- | --- | --- |
| Ask for a very large count | Small change | Still stops early or runs into the end; the percentage is fictional as book progress. | Reject as the whole-book feature. |
| Keep translating until pixels stop changing | Usually reaches somewhere near the end | A missed click, focus problem, or repeated illustration looks identical to completion. | Reject as automatic completion. |
| Continue with checkpoints; review ambiguous endpoint | Works with the existing calibrated workflow | User may need to confirm the end and resolve interruptions. | First release. |
| Read verified reader position and terminal controls | Can establish coverage and finish unattended | Requires a source-reader adapter, native investigation, and ongoing compatibility tests. | Add by demonstrated capability. |
| Jump to the beginning automatically | Fewer setup steps | No verified navigation contract exists today; a wrong jump can omit content. | Defer. |

The first release is **continuous translation to a reviewed end**, not a promise of unattended completion. Keep the Mac awake and unlocked with the calibrated reader and provider visible. Switching tabs, layout changes, quotas, and uncertain turns can still pause the run.

### End detection

Reader inspection must be bounded and confined to the calibrated book surface. A future source-reader adapter may return book identity, logical position/span, total positions, and a terminal signal, each with its evidence. Unknown information stays unknown. Do not scrape unseen book text or ask the translator to guess where the book ends.

Inspect actual BOOKWALKER controls before choosing the adapter contract. A disabled arrow alone is insufficient: it might reflect loading or unavailable focus. A rounded “100%” alone does not establish the last content item either.

| Observation | Action |
| --- | --- |
| Verified final content position, tied to this book and stable source | Translate and commit that content, then confirm the endpoint without another forward click. |
| Verified end overlay reached after the final saved content | Do not translate the overlay. Confirm only if continuity to the last saved source is established. |
| Unverified end-looking screen or an unchanged turn | Pause for review. It may be the end, a dropped click, or a reader problem. |
| User reviews the reader end and the matching last saved content | Record **End confirmed by user**, with no unresolved pending request. The review may resolve an unchanged terminal turn and confirm the endpoint together. |
| `[NO TEXT]`, repeated anchors, identical pixels, chapter ending, “The End,” or response `END` marker | Insufficient evidence of book completion. |
| Quota, timeout, internal work-window boundary, or resource limit | Preserve state; pause or continue as appropriate. Never label the book finished. |

Check reader signals before preparing a new source request so a known end overlay is not translated. When final-position evidence refers to actual book content, that content must still be saved before completion. Revalidate evidence after a layout or book identity change.

Without a reader adapter, a changed terminal overlay can be captured or submitted before it is recognized. The first release must include an explicit **This is reader UI, not a book page** resolution inside endpoint review. Compare it with the preceding saved content and preserve the candidate source, request ID, sent state, and any available reply in a terminal-review record. Only after that record is durable may the active pending request be marked resolved as reviewed non-content. Do not resend it, count it as translated book content, or silently discard its evidence. A provider reply may still finish afterward; the retained request receipt explains what was sent.

Reserve archived request IDs and retain their artifacts under immutable, unique paths. The current request/source naming derives from the saved-screen count; a non-content resolution must not allow a later scope change to reuse that ID or overwrite its source. Keep request identity separate from reading-copy numbering when adding this path.

If the overlay was already committed, retain its original record and numbering but mark it as reviewed reader UI, excluded from the reading copy and coverage count. The confirmed endpoint refers to the preceding actual book content. This is an explicit correction, never an automatic exclusion of blank pages or illustrations. Regenerate reading copies from that reviewed revision. Overlay prevention is capability-dependent; recovery cannot depend on having prevented it.

Use one position/end review flow. It shows the last saved source and current reader, then offers **This is the end of the book**, **The next page is visible**, **Retry one forward click**, or **Keep paused** only when their prerequisites hold. A to-end job with an unchanged turn must be able to reach endpoint review even without an automatic endpoint candidate.

Confirming the end requires a complete last saved response, no unresolved pending request, and evidence connecting the visible endpoint to that response. For an unchanged terminal turn, one checkpoint records the user's confirmation, marks the saved turn trace as **reviewed terminal**, clears `turnUncertain`, and confirms the endpoint. It performs no extra click and creates no synthetic translated screen. This resolves the uncertainty through review; it does not require the user to retry the failed turn first. A changed source or terminal overlay needs its own matching continuity evidence.

### Coverage and repeated pages

Track beginning evidence, navigation continuity, and endpoint evidence separately. “User confirmed” and “reader verified” are different claims. Even a verified coverage sequence does not certify translation accuracy.

The existing duplicate-anchor check also rejects successive textless pages because both use `[NO TEXT]`. Whole-book work must handle this deliberately. Permit repeated anchors/images automatically only when independently verified, consecutive reader positions establish that these are distinct content items. Without that signal, keep a specific review path. Do not remove duplicate detection globally to get past an illustration.

If a reliable reader position moves backwards, skips content, or belongs to another book, pause and show the discrepancy. A changed hash alone does not prove the correct next page. Preserve that limitation in the coverage record for generic calibrated readers.

### Progress and completion

Keep the compact activity names: checking, translating, turning, and saving. Add a percentage in parentheses when its denominator is meaningful:

| Mode | Example | Meaning |
| --- | --- | --- |
| Fixed count | `BT translating (42%)` | Saved screens against the selected job target; menu explicitly says **Screen target**. Extending the target may lower this percentage. |
| To end, verified logical range | `BT turning (42%)` | Committed reader positions in the requested range, counting a spread's positions once. |
| To end, unknown total | `BT translating (42 saved)` | Honest saved-screen count; detail says **Total length unknown**. |
| Endpoint confirmed, EPUB running | `BT exporting` | Translation is complete; ebook generation is still running. No invented export percentage. |

Do not divide screenshot count by printed-page count. If the reader cannot supply compatible position/range units, show its position separately and keep saved-count progress. Stay below 100% until endpoint and coverage checks for the requested scope finish.

Use **Batch complete** for fixed counts and **Book finished** only with beginning evidence, accepted continuity, and a confirmed endpoint. Otherwise use **Translated to end — partial book** or **Translated to end — beginning unknown**. Details identify whether coverage/end were reviewed by a person or verified through a reader adapter. A manual pause remains **Paused**; an unresolved error remains **Warning**.

### Quotas, provider choice, and speed

Continue using the selected provider and model; record observed provenance on every screen. Do not switch to Flash-Lite or another provider to keep a run alive. If the provider changes its serving model itself, retain the observed evidence and existing limit handling rather than claiming the previous model did the work.

Default to a resumable pause on a blocking limit. Preserve the optional one-shot reset-time resume where supported, using an actual reset notice or an explicitly entered time. No assumed five-hour interval, repeated quota polling, or automatic new conversation. ChatGPT reset scheduling must stay unavailable until its signals and resume policy are implemented and tested separately.

An already-sent reply is collected before any new request. Optional resume checks must revalidate the original job, source, provider, model selection, empty composer, and absence of a blocking notice. Stop, manual resume, job changes, or reload cancel the scheduled attempt as they do today.

Retain readiness checks around three starts per second and the independent source-stability check. An entire-book run adds no sleep between successful screens. Check reader position at source/turn boundaries, not by traversing all browser controls every menu refresh. Do not remove stability checks just because a longer job makes their cost more visible.

### Files and EPUB

Every accepted screen remains durable before the next click. Illustration processing stays incremental and coalesced. Completion queues the final EPUB automatically; there is no required manual export action. A failed EPUB retries from saved work, without another translation or page turn.

Persist translation completion separately from export readiness. A restart after the final save should finish the export, not send the final page again. An export must identify the saved-record revision it contains so an older success cannot be mistaken for the final book.

Do not build an EPUB after every page by default. Keep partial HTML available and allow **Rebuild EPUB** on demand. Measure full-list checkpoint/HTML/metadata rewrites on long jobs before adding export snapshots or changing the storage format: the current implementation rewrites these growing lists repeatedly, so cumulative work grows with book length.

## Implementation outline

Introduce a pure menu/action policy, a pure run-scope policy, and eventually a separate reader-position adapter. Keep browser I/O and existing recovery handlers in the runtime. Translation provider and source reader are independent choices.

An illustrative checkpoint extension:

```lua
run = {
  mode = "until-end", -- or "fixed-count"
  scope = "from-beginning", -- or "from-current" / "selected-count"
  startEvidence = {
    method = "user-confirmed", -- or "reader-verified" / "unknown"
    sourceHash = "…", sourcePath = "…", confirmedAt = "…",
  },
  coverage = {continuity = "capture-verified"},
  completion = {state = "open"}, -- candidate / confirmed
  -- Confirmed completion includes method, time, last saved ID/hash,
  -- and any reader identity/position evidence supporting the decision.
}
```

Preserve legacy request IDs, sources, models, provider choice, and pending state. Jobs without `run` retain fixed-count semantics. Validate new modes explicitly and back up checkpoints before migration. Document that older runtimes do not understand until-end jobs; do not claim new-mode checkpoints are safe to resume after a downgrade.

For an incremental implementation, `remaining` can stay a finite internal work-window counter in until-end mode. Refill it durably when that window ends, under the original to-end authorization; never prompt again, start another job, export a “finished book,” or reset numbering merely because it reached zero. An optional resource/session ceiling pauses with a reason and remains separate from that internal counter.

Centralize `hasMoreWork`, `needsEndpointReview`, `scopeComplete`, and `canPerform(action)` decisions. Audit every current `remaining == 0`/`remaining > 0` use: resume, save, restore, one-screen recovery, quota scheduling, status, and export triggers must agree. Do not implement until-end mode as a sentinel count or infinity.

The menu policy returns labels, enabled states, and reasons from a snapshot. It does not call the browser. Handler guards remain authoritative. Preserve existing public Lua entry points and hotkeys where possible so installed configurations keep loading.

### Existing commands have a home

| Current command(s) | Proposed home / behavior |
| --- | --- |
| Provider; Calibrate; Set forward click only; Preview source crop | **Setup**; provider-specific calibration retained. |
| New job on current screen | **Books → Start a new book…**, with explicit scope and start action. |
| Start / resume; Pause / resume | State-dependent primary command; separate opening, starting, and continuing. |
| STOP | **Advanced → Stop automation**, plus immediately visible while checking/scheduled; X always available. |
| Restore latest saved job; Choose saved job; Rename current job | **Books → Open most recent / Open saved / Rename this book**. Opening stays paused. |
| Retry pending screen | **Advanced → Recovery → Resend pending request…**; clearly says it sends another request. |
| Direct prompt recovery; manually selected ln skill | **Advanced → Recovery**; valid unsent pending request required; Gemini skill only on Gemini. |
| Collect existing reply; collect earlier reply | **Advanced → Recovery**; keep these distinct from resend and each other. |
| Accept reviewed clipboard | **Advanced → Recovery → Save reviewed clipboard…**; retain response/source validation. |
| Review last saved source | **Advanced → Recovery → Review saved source…** for same-page appearance changes only. Uncertain turns use the guarded position-review flow instead. |
| Schedule / cancel auto-resume | **Advanced**, with cancellation and scheduled time also visible at the top when armed. |
| Open illustrated reading copy; Open EPUB; Open output folder | **Read translation**. Enable only when the corresponding output exists; report stale exports. |
| Rebuild illustrated reading copy | **Advanced → Rebuild reading copy**. Add **Rebuild EPUB** for export-only repair. |
| Accessibility diagnostics; Status; last pause/error; dismiss | **Advanced → Diagnostics**, with explicit pause labels where applicable; passive summary above. |

## Rollout and acceptance

**1. Menu cleanup — shipped in 1.6.0.** The pure menu policy and grouped commands operate on current fixed-count jobs. The menu shows a passive book/provider/model/progress summary, directs warnings to review, and exposes repair tools under Advanced. S dispatches the primary action; P only pauses or resumes ordinary work. Opening an output or diagnostic dialog cancels active continuation and scheduled resume before changing focus. Handler guards repeat menu restrictions. Existing jobs need no migration, and the [usage guide](usage.md) describes the installed labels.

**2. Continuous scope and reviewed endpoints.** Add durable run scope, coverage evidence, endpoint review, reviewed non-content resolution, mode-aware recovery, and final export. Clearly state that an endpoint review may be required. Test on a short synthetic reader before a real book.

**3. Verified BOOKWALKER position/end support.** Inspect native controls and capture fixtures for first/last content, loading, spreads, and terminal overlays. If reliable signals are unavailable, keep reviewed endpoints and unknown-length progress. Do not hold menu cleanup hostage to a capability the reader might not expose.

Acceptance checks:

- Menu snapshots cover no job, missing calibration, running, paused, pending reply, uncertain turn, quota, scheduled resume, batch complete, endpoint confirmed, and export failure during both active and idle translation.
- Opening the menu has no side effects. A stale menu selection still hits handler guards. Every current command and shortcut remains accounted for.
- Legacy fixed batches still stop at the requested count. Until-end work crosses internal boundaries once, without duplicate saves, new IDs for the same request, or false completion.
- Pause/reload around submission, collection, pre-click checkpoint, post-click settling, work-window refill, and final export does not duplicate a request or navigation click.
- Dropped click and same-image endpoint remain ambiguous; loading, repeated/textless pages, end overlays, and rounded 100% cannot falsely finish a book.
- A user-confirmed unchanged endpoint resolves the turn and completion together, with no extra click, lost trace, synthetic screen, or unresolved pending request. Cancelling review leaves the uncertainty intact.
- A terminal overlay captured before detection can be reviewed before send, after send, or after commit. Each path retains its evidence, excludes only explicitly reviewed reader UI, and attaches completion to the preceding book content. Reload during that resolution cannot lose the request or silently exclude a real page. Later continuation cannot reuse its request ID or overwrite its source.
- Starting in the middle or restoring an unknown legacy beginning cannot produce a complete-book coverage claim.
- Quotas before send, during generation, after the final reply, and at a window boundary preserve pending work and endpoint evidence.
- Illustration/export failure does not erase translation completion. A final EPUB contains the final committed revision and model metadata, with illustrations in order.
- Synthetic archives beyond 1,000 screens verify ordering, bounded memory, numbering, and measured save/render/export costs. Record timings before deciding whether storage needs redesign.
- Native macOS checks verify actual focus, direction, first/last positions, spreads, and endpoint signals. Test Gemini and ChatGPT separately; the latter remains experimental until its BOOKWALKER workflow passes.

No new provider API, automatic model switching, automatic rewind, or image editing is required for this design. The aim is a readable menu and a run that can reach the end without losing track of how it got there.
