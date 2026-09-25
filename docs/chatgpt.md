# ChatGPT in the Chrome side panel

ChatGPT is an experimental second provider for Babelbound. It uses the official
ChatGPT extension and your signed-in account. The workflow is the same: verify
the visible page, paste a direct translation prompt, collect the matching reply,
save it, then turn once. No translation skill, API key, or extension modification
is required.

## Set up

1. Install and connect the official extension using [OpenAI’s Chrome extension guide](https://learn.chatgpt.com/docs/chrome-extension).
2. Open your authorized book in Chrome. Open ChatGPT’s side panel on the right,
   and make sure the extension can use this tab. Keep the reader visible on the left.
3. Choose the model and reasoning level in the panel. Babelbound leaves that
   selection to you; availability and limits depend on your account.
4. Pause any active Babelbound job and cancel any scheduled resume, then choose **BT → Setup → Translation provider → ChatGPT extension**.
5. Use **Setup → Calibrate…** for the empty ChatGPT input, the book’s forward target, the source
   rectangle, and the panel’s top-left corner. Preview the crop.
6. Use **Books → Start a new book…** for a separate one-screen job first. Check its saved source and translation
   before starting a longer batch.

Gemini and ChatGPT keep separate calibrations and remembered jobs. Restoring a
job selects its recorded provider, but does not open a panel or send a request.
Older jobs without provider metadata belong to Gemini. To translate a book with
another provider, create a separate job; a pending reply is never transferred
between providers.

## What it verifies

The integration targets the official extension’s English interface: the
**Do anything** input, **Send**, generation controls, reply **Copy**, and the
composer’s model picker. It checks the extension’s accessible web-area URL before
interacting with a calibrated ChatGPT panel. Third-party ChatGPT sidebars and
chatgpt.com in a separate window are not interchangeable with this adapter.

Each saved screen includes its provider and observed model selection, including
the reasoning level when the picker exposes it. These are UI observations;
they do not prove which backend served a response.

The same full-draft readback, request IDs, source fingerprints, completion
markers, duplicate checks, and write-before-send checkpointing apply to both
providers. A refusal, source-access failure, incomplete reply, or usage limit
does not authorize a page turn. A single-page request is not a guarantee of
acceptance; the provider still applies its normal rules.

Chrome can show a debugging banner while the extension reads the tab, shifting
the book image. Before Copy, Babelbound checks about three times per second for
the original fingerprint to return and remain identical for one second, then
reacquires the controls. This check stops after 30 seconds; it never adopts a
changed page or sends another translation request. A mismatch image is saved
in the job's `collection` folder for diagnosis.

## Live checks — September 24, 2026

One authorized Japanese source capture was translated through the official
extension with **6 Astra Medium** selected. Babelbound collected the response
twice using visible **Copy** controls, validated the matching request, and saved
HTML, EPUB, and provider/model provenance.

A separate two-capture local reader test saved both translations and built an
EPUB. It issued exactly one calibrated forward click and verified that the
source changed and settled before sending the second request. That test exposed
the debugging-banner interruption; the pending replies were collected by
resuming, without sending either request again.

A fresh one-capture run with the banner fix completed automatically. The
original source returned after about 5.5 seconds of checking; Babelbound then
collected two identical replies and saved the HTML, EPUB, and model metadata.

End-to-end ChatGPT pagination in BOOKWALKER remains unverified. The live reader
currently shows an expired-session sign-in error, so the local fixture results
do not establish compatibility with that reader's full pagination flow.

## Current limits

ChatGPT support is experimental. Its extension and accessibility labels can
change independently of Babelbound. Start with a small batch after an update.
Only visible, accessible page content can be translated; sign-in errors,
expired reader sessions, and unreadable captures need to be fixed first.

The local screenshots are used for verification and reading-copy artwork.
This adapter asks ChatGPT to read the current tab; it does not silently upload
the saved screenshot or access a book’s unseen pages.
