# Reading copies and metadata

## What is saved

The checkpoint is the working record of a job. Each accepted response is saved alongside its source capture, and the reading copies are derived from committed records.

| File or directory | Purpose |
| --- | --- |
| `checkpoint.json` | Job title, records, remaining count, pending request, and recovery state |
| `page-metadata.json` | Per-screen model observations and provenance |
| `sources/` | Captured source screens |
| `responses/` | Raw Gemini responses, including protocol markers |
| `pages/` | Accepted English text for individual screens |
| `translation.md` | Combined English text with capture headings |
| `translation.html` | Illustrated local reading copy with model filters |
| `translation.epub` | Portable ebook with internally packaged artwork |
| `illustrations/manifest.json` | Illustration placements and source fingerprints |
| `illustrations/portable/` | Cached JPEG derivatives for EPUB export |
| `turns/`, `collection/`, and diagnostic files | Evidence for navigation and response-collection problems, when produced |

Capture numbers are ordering identifiers, not printed book-page numbers. One capture can be a spread.

## Illustrated HTML

Illustration extraction runs against saved source captures. It does not browse backward through a book or acquire missing pages. **Rebuild illustrated reading copy (all saved screens)** rescans the committed archive and updates the HTML.

The detector finds image regions using pixels and connected regions; it does not understand the scene. Simple line art, decorative regions, or unusual page layouts can need review. Original screenshots remain intact, and extracted art is stored separately.

The HTML uses local relative image paths. To move the HTML reading copy, keep its `illustrations` directory with it. For iPad or file sharing, use the EPUB, which packages its images inside one file.

## Reviewed cover and illustration layouts

A plain illustration is kept in the correct screen position. Recreating English typography over the original page is a separate, reviewed layout feature; it is not automatically inferred from every image.

Optional files in a job folder provide these corrections:

- `illustration-overrides.json` specifies reviewed crop boxes or excludes a false detection.
- `illustration-layouts.json` specifies a page box, text masks, positioned English blocks, and optionally a reviewed transcript.

Both files use a `screens` map keyed by capture number. Every reviewed entry includes `sourceSHA256` and is checked against the corresponding source image. A layout for a different source is rejected.

Crop boxes and `pageBox` use source pixels in `[left, top, right, bottom]` order, with right/bottom exclusive. Layout masks and text blocks use coordinates relative to the reviewed page box. Text blocks support font size, color, background, weight, alignment, line height, and horizontal or vertical placement. Consult the helper’s module docstring and `positionedPage` in `gemini_book_core.lua` for the exact schema.

The HTML keeps a plain-text transcript with a composed page. EPUB exports render reviewed layouts into JPEG artwork and keep the transcript as readable text underneath. Where a cover is identified, its packaged cover resource can be used by Books; reviewed English cover placement survives export. This does not generate new artwork or replace untranslated text without a reviewed layout.

## EPUB for Apple Books

EPUB is generated after a successful batch, once illustration and HTML writers have finished. **Open EPUB in Books** opens the existing export; if none exists, it queues an export. A paused job may have newer committed screens than its last completed-batch EPUB.

To explicitly export the current saved reading copy from the Hammerspoon Console:

```lua
GeminiBook.exportEpub()
```

Wait for saving to finish, then use **Open EPUB in Books** or find `translation.epub` through **Open output folder**. On iPad, transfer that `.epub` file and open/share it with Books. Copying the `.html` file alone does not transfer its artwork.

The EPUB has:

- Reflowable English text in one continuous reading document, avoiding forced breaks at every capture.
- A table of contents whose entries navigate to the original screen anchors.
- Embedded JPEG artwork with a maximum long edge of 2,200 pixels.
- Real paragraphs and explicit line breaks for meaningful single-line spacing.
- Per-screen model metadata in section attributes and `META-INF/bt-export.json`.

EPUB-only cleanup removes the exact `[continues]` marker, generated screen headings, model badges, and generated illustration captions from reading flow. A known empty-page placeholder becomes a zero-height navigation anchor; an illustration on that screen is retained. Other bracketed book text is preserved. Fragments from adjacent captures are not guessed, rewritten, or deduplicated.

These cleanup rules do not edit the source HTML, saved translations, checkpoints, or original artwork. The EPUB exporter reads the HTML as authoritative, including existing reviewed corrections. Export publication is atomic: a failed rebuild keeps the previous complete EPUB.

If Books keeps showing an older imported copy, check the new file’s modification time and import that file again. A file already imported into Books is a library copy; rebuilding the file on disk does not guarantee that the existing library item refreshes.

## Model provenance

Babelbound accepts the model currently selected in Gemini, including Flash-Lite, Flash, or Pro when those choices are available. It does not switch the selection for you.

Metadata distinguishes the observation at submission from the observation at collection. If the visible selection changes during generation, the record can indicate uncertainty and possible model keys. If the UI cannot be read reliably, the record may be unknown or unverified.

These are observations of Gemini’s interface, not proof of the service’s internal backend model. The HTML shows/filter these tags; the EPUB retains them as metadata without repeating badges in the novel’s reading flow. `page-metadata.json` and checkpoint records retain the fuller provenance.

The tags support later review and selecting pages for possible retranslation. There is no automatic “upgrade all translations by model” command or automatic translation-quality grader in the normal menu.

## Preserve reviewed work

Normal Babelbound HTML rebuilds derive text from checkpoint records and reviewed layout files. Hand-editing `translation.html` can therefore be overwritten by a later rebuild. Keep a separate reviewed copy if you edit HTML directly, and export that copy explicitly with the Python EPUB helper. The exporter itself preserves the input HTML.
