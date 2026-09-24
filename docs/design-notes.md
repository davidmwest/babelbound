# Design notes

I started with a fairly ordinary complaint: translating a book required too much back-and-forth. Getting a translation was only one step. I still had to keep track of the page, save the result, move forward, and recover when the browser stopped cooperating.

The project grew through that workflow. I used Codex to implement and test changes, then fed the failures and rough edges back into the next iteration. Some features were obvious, like showing the book title next to Start / resume. Others only became obvious after using the output—an EPUB that technically opened could still be unpleasant to read.

## A saved response has to belong to the right page

A response being visible is not enough. It might be incomplete, left over from the previous page, or associated with a request that was retried.

Each request gets an ID, a source screenshot fingerprint, and a persisted pending record. The response includes matching BEGIN/END markers and brief source anchors. A complete, matching response can become a committed screen; a timeout cannot.

That distinction also changes recovery. If Gemini already received a request, a collection failure should lead to another attempt to collect that reply. Sending the prompt again is a separate, explicit action. Otherwise a clipboard problem turns into duplicate translations and a much harder state problem.

These checks establish bookkeeping and completion, not translation accuracy. A model can produce a properly formatted answer that still needs editorial review.

## One click needs evidence

A page-turn click can be dropped. It can also land on the wrong surface if focus or geometry changed. Blindly clicking again makes it hard to know whether the reader is one page ahead or two.

BT records its turn state before delivering one forward click. Then it verifies a changed, stable source image. If the result is ambiguous, it keeps the uncertainty and pauses. Recovery starts with the saved evidence instead of assuming the click worked.

The same principle applies after a layout change. A different screenshot hash does not prove that the book advanced. The source-review path lets a person confirm that the content is the same while retaining the original capture.

## Faster should mean less unnecessary waiting

There were too many places where the initial workflow just waited. Readiness polling now targets three starts per second, with quicker focus and draft-readback checks where the state is observable.

Some waits still have a reason. A book page must remain stable for two seconds before it is trusted, accessibility traversals are bounded, and Gemini's generation time is outside the local machine's control. The useful optimization is to continue when the required state is actually ready—not to pretend that every operation will be ready after an arbitrarily short delay.

There is no claimed pages-per-minute benchmark here. Browser versions, conversation length, network latency, source density, and the selected model all affect the result.

## Status is part of correctness

“Paused” used to cover too many different outcomes. It could mean a deliberate pause, an error, or a successfully completed batch. Those states imply different next actions.

The menu now shows warnings and completion separately. Active states show a percentage, and Start / resume names the loaded book. Progress counts committed screens against the current requested target. It does not count a pending response as saved, and it does not claim to know the entire book's length.

This also explains why model metadata is kept even when it is uncertain. The observed selection is useful information; guessing an unobserved backend model would make it less useful.

## A reading copy should actually be portable

The HTML reading copy uses neighboring image files. That is convenient on the Mac but fragile when someone transfers only the HTML file to another device.

EPUB packages those resources together. It keeps searchable/reflowable text, includes the illustrations, and carries model provenance without repeating automation labels throughout the novel. Reviewed cover and character-page layouts become composed images with a readable transcript below them.

The first EPUB structure gave every capture its own reading document. Apple Books could interpret those boundaries as chapter starts and leave unnecessary space in a spread. The current exporter uses one continuous document, with a table of contents pointing to screen anchors. It also removes generated capture headings and `[continues]` markers from the ebook only.

That last point matters: export cleanup does not rewrite the underlying translation. It does not guess how fragments should join or delete repeated prose. The original HTML, checkpoint, source screenshots, and responses remain available for review.

## What I would validate before expanding this

The portable tests cover the parts that can be made deterministic: request parsing, interrupted state transitions, file transactions, image-cache freshness, EPUB structure, and text preservation. They use invented text and generated images.

The desktop boundaries need separate validation. A changed Gemini sidebar should get a short live test. A pagination change should be opened in Books. Better model comparisons would need a reviewed source set and a repeatable grading method; a model tag alone is not a quality score.

That is the direction for further work: make the uncertain parts more observable, keep recovery understandable, and improve the reading result without losing the evidence needed to debug it.
