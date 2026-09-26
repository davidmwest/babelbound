# Expanded result schema

The current schema 3 package contains 12 source captures, 31 configurations,
372 responses and 744 reviews. The original schema 2 cohorts described below
remain frozen; the DeepSeek extension follows them.

## Frozen original cohorts (schema 2)

The package retains 12 source captures, 29 configurations, and 348 cells: 276 Codex CLI and 72 Gemini web responses. Null means unknown, never free or zero. Source text, images, translations, reviewer quotations and private paths are excluded.

Each configuration, run and summary has a `cohort`: `codex-cli` or `gemini-web`. Reviews use protocol version 2 and 1 respectively, both with the amended source-alone grading anchors. Two distinct judges assess every response. Numeric issue-severity counts remain; reviewer prose does not.

The cohorts share frozen source hashes and scoring dimensions, but were graded in separate batches with no calibration controls. Cross-cohort grading drift was not measured. Treat pooled score ordering as descriptive, not a controlled provider comparison. Gemini standard/extended means the web UI extended-thinking switch off/on, not zero versus nonzero internal reasoning. Selected UI model names do not verify backend identity.

`summary` reports cohort scores and timing. Gemini delivery counts distinguish English translations, service errors, non-English transcriptions and other failures using anonymous content audits. The primary mean retains all twelve responses; `english_translation_mean` is conditional on delivery and has a potentially different subset, so it is not a replacement ranking. Codex intervals are descriptive bootstrap estimates; Gemini intervals are unavailable. Unusable counts in summary require both judges; value eligibility excludes any capture either judge marked unusable.

`cost` holds observed-token Standard API equivalents for Codex. Gemini costs and usage remain null with unavailable status; Gemini configurations are never value eligible and never receive dollar recommendations. Missing usage from two interrupted Codex attempts makes their costs lower bounds and excludes them from value recommendations. `cli_resume_amendment` records exactly those two replacement attempts and their client version boundary.

`publication.input_bindings` binds the OpenAI numeric integrity snapshot, the exact Gemini results bytes, and the reviewed CLI amendment. Final staging requires 348 completed doubly graded cells, resolved source adjudications, no unresolved score overrides, current source-hash checks, and both passing integrity receipts. A narrowly pinned `context_limitation_acknowledgment` retains the exact 13 original runs with unavailable delegated child histories: their `context_policy_review_required` flags remain true, child context and usage are not claimed complete, and affected lower-bound costs cannot enter dollar-value recommendations. The acknowledgment binds exact run IDs, finding payload hashes, and the frozen numerical receipt. Any new or changed context finding blocks staging. This is a reporting limitation, not a passed child-context audit. Any incomplete gate permits only an explicit draft preview. Existing directories cannot be overwritten. The staging tools never publish or make network requests.

Run `python3 -m unittest test_publication test_pricing test_combined_publication` for synthetic privacy and readiness regressions. Run `python3 render_publication.py --results results.json --output report.html` to reproduce the standalone report. Private input collection and source review are not included in this sanitized package.

## DeepSeek extension (schema 3)

The extension preserves all earlier run, configuration, summary and original
value-comparison records. It adds 24 native Ollama responses and 48 assessments:
31 configurations, 372 responses and 744 reviews in total. Cohort `ollama-cloud`
uses `deepseek-v4.1-flash:cloud` with Instant (`requested_think: false`) and Light
(`requested_think: "low"`). The returned service label omits the cloud routing
suffix. Neither label independently verifies backend weights.

Native usage retains unknown cache counts as null. `cost.scenario` is
`all_input_uncached`: a published Ollama tariff estimate based on UTC request
time, not an observed account charge. Complete estimates require accounting for
thinking output and all attempts. Missing accounting is unavailable or a lower
bound. The original Codex value selector is unchanged; the additional cohort's
quality and costs are displayed separately because grading batches differ.
`deepseek_pricing` records peak and off-peak rates and limitations.

The append-stage binds the exact frozen base bytes, new private results bytes,
and integrity receipt. It requires two distinct completed reviews, identical
source hashes, resolved source audits and anonymous delivery audits. Source
scans, translations, thinking text and reviewer prose remain private.
