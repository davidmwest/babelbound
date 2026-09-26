# Japanese → English translation benchmark

How much translation quality does more reasoning buy—and which settings are worth the cost? This study compares model settings on a selected set of Japanese light-novel captures.

**Final numeric publication.** 408 / 408 planned translation attempts assessed across 34 configurations and 12 captures; two source-based AI reviews per assessed attempt.

[Interactive report](report.html) · [Numeric results](results.json) · [Full methods and limitations](METHODS.md)

## Practical takeaways

Within the OpenAI cohort, on the same 12 captures, using recorded cache usage and complete Standard API cost estimates:

- **gpt-6-sol / high** was the cheapest eligible setting with mean quality ≥ 9.5/10: **9.67/10 at $0.064151 per capture**.

These thresholds apply to the unrounded mean, not every page. Eligibility requires both judges to mark every matched output usable. Lower-bound and unknown costs are excluded; the interactive report also offers a no-cache scenario.

Within the Gemini cohort, **gemini-3.8-flash / standard** delivered English for **12/12 captures**, with the highest observed mean among settings that delivered English every time: **8.76/10**. Both reviewers marked **7/12 outputs usable**; delivering English does not by itself establish an acceptable translation. Delivery failures and English-only quality are shown separately below; this is a small comparison of the observed browser workflow.

## OpenAI quality and estimated cost

Scores are 1–10. Cost is estimated API-equivalent USD per capture, excluding grading and subscription charges. ≥ marks a lower bound; — means unknown. Captures can contain multiple printed pages.

| Model | Effort | Overall | Prose | Layout | Graded | Avg. USD | Cost status |
|---|---|---:|---:|---:|---:|---:|---|
| gpt-6-astra | low | 9.58 | 9.55 | 9.66 | 12/12 | $0.147380 | estimated |
| gpt-6-astra | medium | 9.27 | 9.21 | 9.45 | 12/12 | $0.132265 | estimated |
| gpt-6-astra | high | 9.79 | 9.74 | 9.94 | 12/12 | $0.204753 | estimated |
| gpt-6-astra | xhigh | 9.79 | 9.76 | 9.87 | 12/12 | $0.361184 | estimated |
| gpt-6-astra | max | 9.74 | 9.68 | 9.92 | 12/12 | $0.627312 | estimated |
| gpt-6-astra | ultra | 9.93 | 9.91 | 9.98 | 12/12 | ≥ $0.287943 | lower_bound |
| gpt-6-sol | low | 6.78 | 6.16 | 8.63 | 12/12 | $0.037143 | estimated |
| gpt-6-sol | medium | 9.42 | 9.35 | 9.61 | 12/12 | $0.049737 | estimated |
| gpt-6-sol | high | 9.67 | 9.68 | 9.64 | 12/12 | $0.064151 | estimated |
| gpt-6-sol | xhigh | 9.56 | 9.52 | 9.68 | 12/12 | $0.090150 | estimated |
| gpt-6-sol | max | 9.69 | 9.74 | 9.53 | 12/12 | $0.121051 | estimated |
| gpt-6-sol | ultra | 9.78 | 9.81 | 9.70 | 12/12 | ≥ $0.150536 | lower_bound |
| gpt-5.6-terra | low | 8.51 | 8.22 | 9.40 | 12/12 | $0.037110 | estimated |
| gpt-5.6-terra | medium | 8.71 | 8.68 | 8.79 | 12/12 | $0.042068 | estimated |
| gpt-5.6-terra | high | 8.79 | 8.68 | 9.12 | 12/12 | $0.048360 | estimated |
| gpt-5.6-terra | xhigh | 9.01 | 9.08 | 8.81 | 12/12 | $0.112820 | estimated |
| gpt-5.6-terra | max | 9.08 | 8.97 | 9.41 | 12/12 | ≥ $0.300342 | lower_bound |
| gpt-5.6-terra | ultra | 9.06 | 8.98 | 9.30 | 12/12 | ≥ $0.349688 | lower_bound |
| gpt-6-luna | low | 1.84 | 1.59 | 2.61 | 12/12 | $0.001188 | estimated |
| gpt-6-luna | medium | 3.69 | 3.01 | 5.73 | 12/12 | $0.001277 | estimated |
| gpt-6-luna | high | 7.38 | 7.10 | 8.22 | 12/12 | $0.003518 | estimated |
| gpt-6-luna | xhigh | 7.82 | 7.36 | 9.22 | 12/12 | $0.009815 | estimated |
| gpt-6-luna | max | 7.74 | 7.45 | 8.62 | 12/12 | ≥ $0.012698 | lower_bound |

The value comparison uses 12/12 identical doubly reviewed captures. [Open the interactive report](report.html) for dimensions, coverage, both reviewers’ scores, cost assumptions and eligibility details.

## Gemini delivery and conditional quality

The primary mean includes every response. Conditional mean uses only delivered English translations: its captures can differ across settings, so it is not a replacement ranking. Gemini browser token usage and equivalent API costs are unknown.

| Model / setting | English / planned | Service errors | Non-English | Other failures | Primary mean | Conditional mean | Conditional n |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| gemini-3.5-flash-lite / standard | 10/12 | 0 | 2 | 0 | 5.28 | 6.14 | 10 |
| gemini-3.5-flash-lite / extended | 12/12 | 0 | 0 | 0 | 8.44 | 8.44 | 12 |
| gemini-3.8-flash / standard | 12/12 | 0 | 0 | 0 | 8.76 | 8.76 | 12 |
| gemini-3.8-flash / extended | 1/12 | 9 | 0 | 2 | 2.26 | 8.68 | 1 |
| gemini-3.1-pro / standard | 8/12 | 3 | 0 | 1 | 7.13 | 9.83 | 8 |
| gemini-3.1-pro / extended | 7/12 | 5 | 0 | 0 | 6.27 | 9.57 | 7 |

`standard` and `extended` mean the browser’s extended-thinking switch was off or on. Off does not guarantee zero backend reasoning. Service errors describe this observed browser session/configuration, not intrinsic translation ability or API behavior.

## DeepSeek on Ollama Cloud

Instant requests disable thinking (`think: false`); Light requests use low thinking (`think: "low"`). Native Ollama requests form a separate two-candidate grading batch. The original OpenAI value comparison remains separate.

Within this two-setting batch, **DeepSeek V4.1 Flash / light** had the highest observed mean: **6.59/10**. DeepSeek V4.1 Flash / instant: **1/12 usable by both reviewers**; DeepSeek V4.1 Flash / light: **5/12 usable by both reviewers**. English delivery does not by itself establish an acceptable translation. One generation per capture; small differences are weak evidence.

Primary means retain all responses; conditional means use delivered English translations only. Usable counts require both reviewers to mark the output usable; an English response can still contain serious translation errors. No-cache tariff estimates use recorded usage and request-time Ollama rates. These are estimates, not invoices; — means unknown.

| Model / setting | Think | Primary mean | Prose | Layout | English / planned | Usable by both / planned | Service errors | Non-English | Other failures | Conditional mean | Graded | Median seconds | No-cache USD / capture | Priced | Cost status |
|---|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---|
| DeepSeek V4.1 Flash / instant | false | 3.81 | 2.81 | 6.82 | 12/12 | 1/12 | 0 | 0 | 0 | 3.81 | 12/12 | 5.0 | $0.000704 | 12 | estimated |
| DeepSeek V4.1 Flash / light | low | 6.59 | 6.57 | 6.64 | 12/12 | 5/12 | 0 | 0 | 0 | 6.59 | 12/12 | 10.6 | $0.003607 | 12 | estimated |

DeepSeek tariff estimates and OpenAI API-equivalent estimates can be compared descriptively. Separate transports and grading batches do not establish a controlled best-value ranking. Gemini browser cost remains unknown.

Ollama pricing snapshot: 2026-09-25 · [Official Ollama pricing](https://ollama.com/pricing).

Peak, USD per million tokens: $0.300000 input; $0.006000 cached input; $1.200000 output.

Off-peak, USD per million tokens: $0.150000 input; $0.003000 cached input; $0.600000 output.

Peak weekdays 12:00–18:00 UTC; all other hours off-peak.

Published Ollama tariff applied to native token receipts with all input charged at the uncached rate. Cache-hit counts and account billing terms are unavailable; this is a no-cache estimate, not an observed account charge. Review costs, taxes and subscription charges are excluded.

DeepSeek reviewers use codex-cli 0.155.0-alpha.16.4; earlier cohorts retain their recorded versions. The expanded Ollama reviewers use codex-cli 0.155.0-alpha.16.4; earlier cohorts retain their recorded versions.

## Gemma 4 and DeepSeek High on Ollama Cloud

This later cohort uses supported model-specific native thinking controls. Each reviewer grades a pair and a singleton per source; the earlier DeepSeek Instant/Light cohort used two-candidate batches. The original 31 configurations and the OpenAI value comparison remain frozen. Cross-batch comparisons are exploratory.

Ollama model metadata lists DeepSeek V4.1 Flash thinking values false, low, high and max, with high as default. Medium is not supported; Ollama documents that unsupported names fall back to the model default, so no separate Medium condition is included. Gemma 4 31B lists boolean false and true, with false as default. These are model-specific native controls, not universal reasoning levels. Sources: https://docs.ollama.com/capabilities/thinking and each model's public /api/show metadata, verified 2026-09-25.

**DeepSeek V4.1 Flash / high** (native think: `high`): **8.15/10 mean**, **7/12 usable by both reviewers**, 12/12 delivered English; 0/12 interrupted; $0.008854 estimated no-cache USD per capture.

**Gemma 4 31B / instant** (native think: `false`): **4.00/10 mean**, **1/12 usable by both reviewers**, 12/12 delivered English; 0/12 interrupted; $0.000270 estimated no-cache USD per capture.

**Gemma 4 31B / thinking** (native think: `true`): **4.46/10 mean**, **1/12 usable by both reviewers**, 9/12 delivered English; 0/12 interrupted; $0.028200 estimated no-cache USD per capture.

English delivery does not by itself establish an acceptable translation. One generation per capture; small differences are weak evidence. These later observations do not establish a controlled improvement over the frozen earlier cohorts.

Timing summarizes completed requests with recorded elapsed durations. Interrupted attempts are counted separately; ≥ marks their observed elapsed time as a lower bound on completion time, not a completed latency. Unavailable timing remains unknown. Mean and maximum expose slow requests that a median can hide. Individual native timings appear in the interactive capture-level run status. Interrupted attempts remain in quality and delivery results. Without a final usage receipt, their costs and the configuration’s average cost are unknown; priced counts identify the known subset. Primary means retain all responses; conditional means use delivered English translations only. Usable counts require both reviewers to mark the output usable. No-cache tariff estimates use recorded input and total output counts, including thinking where present, and each exact model’s request-time rate. These are estimates, not invoices; — means unknown.

| Model / setting | Native think | Primary mean | Prose | Layout | English / planned | Usable by both / planned | Service errors | Non-English | Other failures | Conditional mean | Graded | Completed median seconds | Completed mean seconds | Completed maximum seconds | Timed completed / planned | Interrupted / planned | Longest interrupted seconds | No-cache USD / capture | Priced / planned | Cost status |
|---|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---|
| deepseek-v4.1-flash:cloud / high | high | 8.15 | 7.67 | 9.62 | 12/12 | 7/12 | 0 | 0 | 0 | 8.15 | 12/12 | 62.0 | 55.6 | 87.3 | 12/12 | 0/12 | — | $0.008854 | 12/12 | estimated |
| gemma4:31b-cloud / instant | false | 4.00 | 2.98 | 7.05 | 12/12 | 1/12 | 0 | 0 | 0 | 4.00 | 12/12 | 7.3 | 6.8 | 10.2 | 12/12 | 0/12 | — | $0.000270 | 12/12 | estimated |
| gemma4:31b-cloud / thinking | true | 4.46 | 3.16 | 8.35 | 9/12 | 1/12 | 0 | 0 | 3 | 5.62 | 12/12 | 38.1 | 355.4 | 1425.6 | 12/12 | 0/12 | — | $0.028200 | 12/12 | estimated |

Ollama tariff estimates and OpenAI API-equivalent costs can be compared descriptively. Separate transports and grading batches do not establish a controlled best-value ranking; Gemini browser cost remains unknown.

**deepseek-v4.1-flash:cloud** — Ollama pricing snapshot: 2026-09-25 · [Official Ollama pricing](https://ollama.com/pricing).

Peak, USD per million tokens: $0.300000 input; $0.006000 cached input; $1.200000 output.

Off-peak, USD per million tokens: $0.150000 input; $0.003000 cached input; $0.600000 output.

Peak weekdays 12:00–18:00 UTC; all other hours off-peak.

Published Ollama tariff applied to native token receipts with all input charged at the uncached rate. Cache-hit counts and account billing terms are unavailable; this is a no-cache estimate, not an observed account charge. Total output includes thinking where present and is charged once. Review costs, taxes and subscription charges are excluded.

**gemma4:31b-cloud** — Ollama pricing snapshot: 2026-09-25 · [Official Ollama pricing](https://ollama.com/pricing).

Peak, USD per million tokens: $0.140000 input; $0.050000 cached input; $0.400000 output.

Off-peak, USD per million tokens: $0.140000 input; $0.050000 cached input; $0.400000 output.

A single all-hours rate is published for Gemma 4; no separate off-peak rate is listed. Peak and off-peak fields repeat that same tariff. The exact gemma4:31b-cloud model page also lists these rates: https://ollama.com/library/gemma4:31b-cloud.

Published Ollama Gemma 4 tariff, also shown on the exact gemma4:31b-cloud page, applied to native token receipts with all input charged at the uncached rate. Cache-hit counts and account billing terms are unavailable; this is a no-cache estimate, not an observed account charge. Total output includes thinking where present and is charged once. Review costs, taxes and subscription charges are excluded.

## How to read the results

- This is a small, selected corpus with one generation per setting and capture. AI reviewers can share blind spots; there is no human-validated gold translation. Small score differences are weak evidence.
- Providers used separate grading batches without drift controls. Cross-provider comparisons are exploratory, not a controlled ranking.
- OpenAI costs use a Standard API pricing snapshot. Incomplete attempt or delegated usage remains a lower bound and cannot establish best value. Exact client changes, audit limitations and affected runs are disclosed in [METHODS.md](METHODS.md) and [results.json](results.json).
- Browser elapsed time includes polling, collection and audit gaps. It is not inference latency and is not ranked against CLI time.

## Explore or reproduce the report

Download `report.html` and open it locally for sorting, per-capture evidence, and the quality/cost selector. It is self-contained and makes no external requests. To rebuild it from the bundled numeric data:

```sh
python3 render_publication.py --results results.json --output report.html
```

The [full methods](METHODS.md), [prompt](translation-prompt.txt), [rubric](grading-rubric.md), [schema](SCHEMA.md) and synthetic tests document the experiment and report. Source IDs and hashes identify the private corpus; source scans, translations and reviewer quotations are excluded. This package reproduces the numeric report, not access to the corpus.

Pricing snapshot: 2026-09-24 · [Official Standard API pricing](https://developers.openai.com/api/docs/pricing).

Report renderer 1.3.2. Generated: 2026-09-26T08:01:22.235540+00:00.
