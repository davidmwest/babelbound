# Japanese → English translation benchmark

How much translation quality does more reasoning buy—and which settings are worth the cost? This study compares model settings on a selected set of Japanese light-novel captures.

**Final numeric publication.** 348 / 348 planned translations graded across 29 configurations and 12 captures; two source-based AI reviews per completed translation.

[Interactive report](report.html) · [Numeric results](results.json) · [Full methods and limitations](METHODS.md)

## Practical takeaways

On the same 12 captures, using recorded cache usage and complete Standard API cost estimates:

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

## How to read the results

- This is a small, selected corpus with one generation per setting and capture. AI reviewers can share blind spots; there is no human-validated gold translation. Small score differences are weak evidence.
- OpenAI and Gemini used separate grading batches without drift controls. Cross-provider comparisons are exploratory, not a controlled ranking.
- Costs use a Standard API pricing snapshot. Incomplete attempt or delegated usage remains a lower bound and cannot establish best value. Exact client changes, audit limitations and affected runs are disclosed in [METHODS.md](METHODS.md) and [results.json](results.json).
- Browser elapsed time includes polling, collection and audit gaps. It is not inference latency and is not ranked against CLI time.

## Explore or reproduce the report

Download `report.html` and open it locally for sorting, per-capture evidence, and the quality/cost selector. It is self-contained and makes no external requests. To rebuild it from the bundled numeric data:

```sh
python3 render_publication.py --results results.json --output report.html
```

The [full methods](METHODS.md), [prompt](translation-prompt.txt), [rubric](grading-rubric.md), [schema](SCHEMA.md) and synthetic tests document the experiment and report. Source IDs and hashes identify the private corpus; source scans, translations and reviewer quotations are excluded. This package reproduces the numeric report, not access to the corpus.

Pricing snapshot: 2026-09-24 · [Official Standard API pricing](https://developers.openai.com/api/docs/pricing).

Report renderer 1.1.2. Generated: 2026-09-25T06:58:40.346504+00:00.
