# Methods

This package omits the licensed source images, full translations, and quoted reviewer evidence. Source IDs and hashes identify the frozen private corpus; they do not supply access to it.

## Sample

Purposive sample: nine prose captures and three illustrated/typographic captures from volumes 6, 7, and 10 of one light-novel series. Captures may contain two printed pages. Five overlap a prior Gemini study.

## Cohorts

Two separately graded cohorts share the same twelve source PNGs and translation prompt: 23 Codex CLI configurations (276 outputs) and six Gemini web configurations (72 responses). Gemini candidates were graded in batches of six after the original OpenAI reviews, with no shared calibration controls. Cross-cohort reviewer drift was not measured. Cross-provider quality comparisons are exploratory; pooled ordering is descriptive, not a controlled provider comparison. Gemini token usage and API-equivalent costs are unknown, so Gemini is excluded from all dollar-value recommendations. A third cohort adds DeepSeek V4.1 Flash via native Ollama cloud requests: Instant (think:false) and Light (think:low), 24 responses on the same 12 source PNGs. These candidates were reviewed in separate two-candidate batches, without common calibration controls. Cross-cohort comparisons remain exploratory. A later native Ollama cohort adds DeepSeek V4.1 Flash High and Gemma 4 31B Instant and Thinking: 36 attempted translations on the same 12 source PNGs. The prior 31 configurations and 372 responses remain frozen, yielding 34 configurations and 408 attempts. The new candidates use separate review batches without common calibration controls. Cross-cohort comparisons remain exploratory.

## Conditions

Identical original PNG bytes and user prompt; fresh ephemeral Codex CLI session per capture/configuration. No supplied glossary or prior translations. Codex model-specific system instructions and the default installed-skill catalogue remain part of the client environment. A tool audit flags additional observable file/context reads; generic skill-document reads are disclosed separately from external book context. Some delegated child tool histories are not exposed, so their context cannot be fully audited. Tests the Codex vision-plus-translation workflow, not an isolated raw-model API. Collection crossed an account usage boundary. New dispatch paused proactively with three translation attempts in flight; those attempts retained their existing deadlines. Collection resumed after an account usage reset, preserving prior outputs and requested model/reasoning settings. No quota error was recorded at the pause, and the service still reported ordinary usage allowed. Actual serving-model routing is not observable, so this event does not establish model substitution. A later user-requested pause interrupted only Luna/max and Terra/ultra on V10-S090. The user explicitly resumed them in fresh second attempts, preserving the interrupted logs and all 274 already completed outputs. During that pause, the desktop client updated from codex-cli 0.155.0-alpha.9.2 to codex-cli 0.155.0-alpha.16.3. Only those two translation replacements use the newer build; source bytes, prompts and requested model/reasoning settings remain unchanged. Remaining review calls also use the newer client. This environment boundary is disclosed rather than treated as a quality retry. Gemini collection uses a fresh conversation in the signed-in web interface for each source/configuration with the same source PNG and prompt. Model selection and extended-thinking switch state are observed in the UI; actual backend identity and API equivalence are unverified. Standard and extended indicate the extended-thinking switch off and on; off does not mean zero intrinsic reasoning. Error messages returned instead of translations are retained and scored as delivered, without quality retries. Service errors measure delivery reliability in the observed Gemini browser session and selected configuration; they do not establish the model's intrinsic translation ability or its API behavior. DeepSeek receives the identical source PNG bytes and user prompt in a fresh single-message native Ollama /api/chat request, with no supplied system message, tools, prior output, glossary or context. Sampling parameters use provider defaults. The requested and returned model labels are recorded; they do not independently establish backend weights. No quality retries are allowed. A transient transport error before any model output may be retried once, preserving both attempts. The added Ollama configurations receive the identical source PNG bytes and user prompt in fresh single-message native /api/chat requests, with no supplied system message, tools, prior output, glossary or context. Sampling parameters use provider defaults. Requested and returned model labels are recorded; they do not independently establish backend weights. No quality retries are allowed. A transient transport error before any model output may be retried once, preserving both attempts. Collection uses at most two concurrent requests and finishes all three settings for one source before starting the next. The original collection setup used a 300-second socket-inactivity timeout and no total wall-time deadline or output-token cap override. After a Gemma Thinking request streamed reasoning for over twenty minutes without delivering translation content, an operational amendment added a 30-minute wall-time deadline for remaining in-flight and future requests. The amendment was recorded after the triggering request had already finished; a preserved addendum corrects the stale live-stream observation. This limit was introduced after observing that run, not preregistered. The triggering request ultimately ended naturally after 1,254.447 seconds with no visible translation; no administrative interruption was needed for that request. An interrupted attempt is retained without retry, with received content assessed by both judges and no invented final usage or cost. Sampling and output-token limits otherwise remain provider defaults. A final receipt with no translation content remains in the evaluation as a delivery failure, without a quality rerun.

## Scoring

Two attribution-blind AI reviewers, GPT-6 Astra/high and GPT-6 Sol/high; independently shuffled batches of at most eight candidates. Accuracy 50%, completeness 25%, names/numbers 15%, fluency 10%. Each capture receives equal weight. Gemini uses the same amended source-alone anchors and rubric with six anonymous candidates per source and two independent judge orders. Gemini review files use cohort-local version 1; original OpenAI review files retain version 2. Critical issues and large judge disagreements require source audits, without candidate-specific score changes. An anonymous content audit separately classifies delivery as an English translation, service error, non-English transcription or other failure. The primary score includes every delivered response. Conditional English-translation means exclude delivery failures, use differing subsets, and must not replace the primary ranking. DeepSeek uses the same amended source-alone anchors, dimensions, weights and Astra/high and Sol/high reviewers. Each judge receives two anonymous candidates per source in an independently shuffled order. DeepSeek review version 1 is cohort-local. Critical issues and large disagreements require source audits; no candidate-specific score changes are made. The added Ollama cohort uses the same amended source-alone anchors, dimensions, weights and Astra/high and Sol/high reviewers. Each judge receives a pair and a singleton of anonymous candidates per source, with independently shuffled placement and order. This differs from the earlier DeepSeek two-candidate batches. Ollama review version 1 is cohort-local. Critical issues and large disagreements require source audits; no candidate-specific score changes are made.

## Amendment

Review v2: all 23 illustrated-card translations were blindly re-scored after reviewers penalized a literal character designation using an unprovided canonical name. The source-alone ambiguity rule accepts defensible readings without ruby or a glossary; other captures had not yet been graded. Source clarification v3: both judges regrade all 23 profile-layout translations after a source audit found repeated misreading of a city-name glyph and erroneous penalties for a defensible reading. Both amendments preserve original reviews and unchanged translations; no candidate-specific score overrides are used.

## Limitations

One series, twelve purposively selected captures, one generation per setting/capture, and AI judgments without a human-validated gold translation. Reviewers may favor particular writing styles even when candidate identities are hidden. Tenths of a point are not strong evidence of a real difference. Partial means are not a fair full comparison until all paired cells are scored. The later Gemini cohort has a different transport, collection period and reviewer batch composition. No cross-cohort drift controls were run. UI model labels do not establish the serving API model. Thirteen original runs retain an explicit limitation: delegated child context and usage were not fully observable. The publication acknowledges only those exact runs and frozen findings; it does not clear their audit flags or claim complete child histories or total spend. Their lower-bound costs and affected configurations remain excluded from dollar-value recommendations. The DeepSeek cohort was collected later through a native API, unlike the Codex CLI and Gemini web cohorts. System context, provider preprocessing and reviewer batch composition differ. No cross-cohort calibration or repeated-generation controls were added. The original Codex dollar-value selector is preserved; DeepSeek quality and tariff estimates are shown separately for descriptive comparison. The Gemma 4 and DeepSeek High additions were collected later through a native API. System context, provider preprocessing, collection time and reviewer batch composition differ across cohorts. No cross-cohort calibration or repeated-generation controls were added. The original Codex dollar-value selector and earlier numeric records remain frozen; the added quality and no-cache tariff estimates appear separately for descriptive comparison. The post-hoc wall-time limit can censor slow responses; interrupted requests have unknown final token cost and prevent a complete-cost comparison for that configuration.

## Intervals

95% percentile bootstrap over observed capture scores (4,000 resamples); descriptive sample uncertainty, not a population guarantee or model run-to-run uncertainty. Gemini confidence intervals are not estimated in this publication. No confidence intervals are estimated for the DeepSeek addition. No confidence intervals are estimated for the added Ollama cohort.

## Timing

End-to-end CLI launch-to-completion under concurrent execution; includes overhead and retries. Not pure model latency. API-equivalent estimates separately apply published Standard rates to observed usage; delegated usage may not be separately observable. Resumed cells sum active elapsed time across both attempts, excluding the time the job was paused. Interrupted attempts did not emit complete usage, so those two cells have lower-bound costs and do not qualify for value recommendations. Gemini elapsed times run from observed UI submission to observed completion and include polling, collection and interleaved audit gaps. They are browser-observed elapsed time, not model inference latency, and are not directly comparable with concurrent CLI timing. No cross-provider speed ranking is made. DeepSeek timing covers native request start through the final streamed receipt. It includes transport and provider processing under two concurrent requests and is not directly comparable to browser polling or CLI timing. Added Ollama timing covers native request start through the final streamed receipt, including transport and provider processing under the recorded concurrency. It is not directly comparable to Gemini browser polling or Codex CLI timing. Administrative interruptions report observed elapsed time as a censored lower bound to completion, separately from completed median, mean and maximum latency. A complete study includes all assessed attempts, including delivery failures; it does not imply every request finished normally.

## Ultra

Ultra is maximum reasoning plus automatic delegation. Requested settings are recorded; internal routing is not independently observable from the emitted CLI events.

## Deepseek

Instant maps to native think:false and Light maps to think:low on deepseek-v4.1-flash:cloud. Both requests use original source images. Published Ollama pricing is reported separately from original OpenAI Standard API equivalents and unknown Gemini web costs. Native eval_count reports total generated output; no separate thinking-token counter is exposed. The estimate applies the output tariff once to that count.

## Ollama expanded

DeepSeek V4.1 Flash High requests native think:high on deepseek-v4.1-flash:cloud. Gemma 4 31B Instant and Thinking request native think:false and think:true on gemma4:31b-cloud. All use original source images. Native eval_count reports total generated output; the receipts do not expose a separate thinking-token count. The estimate applies the output tariff once to that count. Ollama tariffs are distinct from the original OpenAI Standard API-equivalent estimates and unknown Gemini web costs.

## Native controls

Ollama model metadata lists DeepSeek V4.1 Flash thinking values false, low, high and max, with high as default. Medium is not supported; Ollama documents that unsupported names fall back to the model default, so no separate Medium condition is included. Gemma 4 31B lists boolean false and true, with false as default. These are model-specific native controls, not universal reasoning levels. Sources: https://docs.ollama.com/capabilities/thinking and each model's public /api/show metadata, verified 2026-09-25.

## Grading batches

The expanded Ollama cohort uses a pair plus a singleton per source and reviewer. Earlier OpenAI, Gemini and DeepSeek cohorts retain their own original batch composition and numeric judgments. Differences across those batches can reflect reviewer context as well as model behavior.

## Cli versions

DeepSeek reviewers use codex-cli 0.155.0-alpha.16.4; earlier cohorts retain their recorded versions. The expanded Ollama reviewers use codex-cli 0.155.0-alpha.16.4; earlier cohorts retain their recorded versions.

## Ollama tariff estimates

Rates per million tokens, checked 2026-09-25: peak input $0.30, cached input $0.006, output $1.20; off-peak input $0.15, cached input $0.003, output $0.60.

Peak weekdays 12:00–18:00 UTC; all other hours off-peak.

Published Ollama tariff applied to native token receipts with all input charged at the uncached rate. Cache-hit counts and account billing terms are unavailable; this is a no-cache estimate, not an observed account charge. Review costs, taxes and subscription charges are excluded.

Source: [Ollama pricing](https://ollama.com/pricing).

## deepseek-v4.1-flash:cloud tariff estimate

USD per million tokens, checked 2026-09-25: peak input 0.3, cached input 0.006, output 1.2; off-peak input 0.15, cached input 0.003, output 0.6.

Peak weekdays 12:00–18:00 UTC; all other hours off-peak.

Published Ollama tariff applied to native token receipts with all input charged at the uncached rate. Cache-hit counts and account billing terms are unavailable; this is a no-cache estimate, not an observed account charge. Total output includes thinking where present and is charged once. Review costs, taxes and subscription charges are excluded.

Source: [Published Ollama tariff](https://ollama.com/pricing).

## gemma4:31b-cloud tariff estimate

USD per million tokens, checked 2026-09-25: peak input 0.14, cached input 0.05, output 0.4; off-peak input 0.14, cached input 0.05, output 0.4.

A single all-hours rate is published for Gemma 4; no separate off-peak rate is listed. Peak and off-peak fields repeat that same tariff. The exact gemma4:31b-cloud model page also lists these rates: https://ollama.com/library/gemma4:31b-cloud.

Published Ollama Gemma 4 tariff, also shown on the exact gemma4:31b-cloud page, applied to native token receipts with all input charged at the uncached rate. Cache-hit counts and account billing terms are unavailable; this is a no-cache estimate, not an observed account charge. Total output includes thinking where present and is charged once. Review costs, taxes and subscription charges are excluded.

Source: [Published Ollama tariff](https://ollama.com/pricing).

## Cost estimates

Apply published Standard USD rates per million tokens to the observed CLI usage across all attempts. Ordinary input = total input minus cached reads minus cache writes. Output already includes reasoning; image input is already included in input usage. Neither is charged twice. No-cache sensitivity prices all input as ordinary input with caching disabled.

Counterfactual API-equivalent token cost, not an API bill or a Codex subscription charge. Includes Codex instructions and tool-loop context; a lean API translator may cost less. Excludes grading, local compute, taxes, regional uplifts and separately charged hosted tools. Requested model rates are used because backend routing is not independently observable. Missing delegated usage or request-level long-context detail is labeled as a lower bound and excluded from value recommendations. Cache reuse in production can differ. Captures may contain two printed pages; cost per 100 captures is an extrapolation, not per 100 printed pages.

Rates: [2026-09-24 Standard API pricing](https://developers.openai.com/api/docs/pricing).

## Reproduce the report

Run `python3 render_publication.py --results results.json --output report.html`. Python 3.10 or newer is sufficient; the report needs no network requests or third-party JavaScript.

The included prompt, rubric, cost calculations and schema document the experiment. Exact translation replication requires lawful access to the same private corpus and matching service/runtime conditions. Backend model routing and unexposed child usage cannot be independently reconstructed from this package.
