# Methods

This package omits the licensed source images, full translations, and quoted reviewer evidence. Source IDs and hashes identify the frozen private corpus; they do not supply access to it.

## Sample

Purposive sample: nine prose captures and three illustrated/typographic captures from volumes 6, 7, and 10 of one light-novel series. Captures may contain two printed pages. Five overlap a prior Gemini study.

## Cohorts

Two separately graded cohorts share the same twelve source PNGs and translation prompt: 23 Codex CLI configurations (276 outputs) and six Gemini web configurations (72 responses). Gemini candidates were graded in batches of six after the original OpenAI reviews, with no shared calibration controls. Cross-cohort reviewer drift was not measured. Cross-provider quality comparisons are exploratory; pooled ordering is descriptive, not a controlled provider comparison. Gemini token usage and API-equivalent costs are unknown, so Gemini is excluded from all dollar-value recommendations.

## Conditions

Identical original PNG bytes and user prompt; fresh ephemeral Codex CLI session per capture/configuration. No supplied glossary or prior translations. Codex model-specific system instructions and the default installed-skill catalogue remain part of the client environment. A tool audit flags additional observable file/context reads; generic skill-document reads are disclosed separately from external book context. Some delegated child tool histories are not exposed, so their context cannot be fully audited. Tests the Codex vision-plus-translation workflow, not an isolated raw-model API. Collection crossed an account usage boundary. New dispatch paused proactively with three translation attempts in flight; those attempts retained their existing deadlines. Collection resumed after an account usage reset, preserving prior outputs and requested model/reasoning settings. No quota error was recorded at the pause, and the service still reported ordinary usage allowed. Actual serving-model routing is not observable, so this event does not establish model substitution. A later user-requested pause interrupted only Luna/max and Terra/ultra on V10-S090. The user explicitly resumed them in fresh second attempts, preserving the interrupted logs and all 274 already completed outputs. During that pause, the desktop client updated from codex-cli 0.155.0-alpha.9.2 to codex-cli 0.155.0-alpha.16.3. Only those two translation replacements use the newer build; source bytes, prompts and requested model/reasoning settings remain unchanged. Remaining review calls also use the newer client. This environment boundary is disclosed rather than treated as a quality retry. Gemini collection uses a fresh conversation in the signed-in web interface for each source/configuration with the same source PNG and prompt. Model selection and extended-thinking switch state are observed in the UI; actual backend identity and API equivalence are unverified. Standard and extended indicate the extended-thinking switch off and on; off does not mean zero intrinsic reasoning. Error messages returned instead of translations are retained and scored as delivered, without quality retries. Service errors measure delivery reliability in the observed Gemini browser session and selected configuration; they do not establish the model's intrinsic translation ability or its API behavior.

## Scoring

Two attribution-blind AI reviewers, GPT-6 Astra/high and GPT-6 Sol/high; independently shuffled batches of at most eight candidates. Accuracy 50%, completeness 25%, names/numbers 15%, fluency 10%. Each capture receives equal weight. Gemini uses the same amended source-alone anchors and rubric with six anonymous candidates per source and two independent judge orders. Gemini review files use cohort-local version 1; original OpenAI review files retain version 2. Critical issues and large judge disagreements require source audits, without candidate-specific score changes. An anonymous content audit separately classifies delivery as an English translation, service error, non-English transcription or other failure. The primary score includes every delivered response. Conditional English-translation means exclude delivery failures, use differing subsets, and must not replace the primary ranking.

## Amendment

Review v2: all 23 illustrated-card translations were blindly re-scored after reviewers penalized a literal character designation using an unprovided canonical name. The source-alone ambiguity rule accepts defensible readings without ruby or a glossary; other captures had not yet been graded. Source clarification v3: both judges regrade all 23 profile-layout translations after a source audit found repeated misreading of a city-name glyph and erroneous penalties for a defensible reading. Both amendments preserve original reviews and unchanged translations; no candidate-specific score overrides are used.

## Limitations

One series, twelve purposively selected captures, one generation per setting/capture, and AI judgments without a human-validated gold translation. Reviewers may favor particular writing styles even when candidate identities are hidden. Tenths of a point are not strong evidence of a real difference. Partial means are not a fair full comparison until all paired cells are scored. The later Gemini cohort has a different transport, collection period and reviewer batch composition. No cross-cohort drift controls were run. UI model labels do not establish the serving API model. Thirteen original runs retain an explicit limitation: delegated child context and usage were not fully observable. The publication acknowledges only those exact runs and frozen findings; it does not clear their audit flags or claim complete child histories or total spend. Their lower-bound costs and affected configurations remain excluded from dollar-value recommendations.

## Intervals

95% percentile bootstrap over observed capture scores (4,000 resamples); descriptive sample uncertainty, not a population guarantee or model run-to-run uncertainty. Gemini confidence intervals are not estimated in this publication.

## Timing

End-to-end CLI launch-to-completion under concurrent execution; includes overhead and retries. Not pure model latency. API-equivalent estimates separately apply published Standard rates to observed usage; delegated usage may not be separately observable. Resumed cells sum active elapsed time across both attempts, excluding the time the job was paused. Interrupted attempts did not emit complete usage, so those two cells have lower-bound costs and do not qualify for value recommendations. Gemini elapsed times run from observed UI submission to observed completion and include polling, collection and interleaved audit gaps. They are browser-observed elapsed time, not model inference latency, and are not directly comparable with concurrent CLI timing. No cross-provider speed ranking is made.

## Ultra

Ultra is maximum reasoning plus automatic delegation. Requested settings are recorded; internal routing is not independently observable from the emitted CLI events.

## Cost estimates

Apply published Standard USD rates per million tokens to the observed CLI usage across all attempts. Ordinary input = total input minus cached reads minus cache writes. Output already includes reasoning; image input is already included in input usage. Neither is charged twice. No-cache sensitivity prices all input as ordinary input with caching disabled.

Counterfactual API-equivalent token cost, not an API bill or a Codex subscription charge. Includes Codex instructions and tool-loop context; a lean API translator may cost less. Excludes grading, local compute, taxes, regional uplifts and separately charged hosted tools. Requested model rates are used because backend routing is not independently observable. Missing delegated usage or request-level long-context detail is labeled as a lower bound and excluded from value recommendations. Cache reuse in production can differ. Captures may contain two printed pages; cost per 100 captures is an extrapolation, not per 100 printed pages.

Rates: [2026-09-24 Standard API pricing](https://developers.openai.com/api/docs/pricing).

## Reproduce the report

Run `python3 render_publication.py --results results.json --output report.html`. Python 3.10 or newer is sufficient; the report needs no network requests or third-party JavaScript.

The included prompt, rubric, cost calculations and schema document the experiment. Exact translation replication requires lawful access to the same private corpus and matching service/runtime conditions. Backend model routing and unexposed child usage cannot be independently reconstructed from this package.
