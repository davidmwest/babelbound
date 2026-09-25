# Blind review rubric

This is the generic rubric used by the study, with source-specific interpretation notes and book examples omitted. Those private notes supported image checks; they are not a gold translation.

Two AI judges independently review each unchanged candidate against the original image. Candidate IDs and order are independently shuffled; judges do not see the generating model, reasoning effort, cost, runtime or the other judge's scores. The judges are GPT-6 Astra/high and GPT-6 Sol/high. Attribution blindness reduces one source of bias; it does not remove shared errors or stylistic preferences.

| Dimension | Weight | What to check |
| --- | ---: | --- |
| Accuracy | 50% | Meaning, agency, negation, causality, viewpoint, tone and register; no invented events |
| Completeness | 25% | All visible book text in reading order, without substantive omissions or repetition |
| Names and numbers | 15% | Entity consistency, defensible name readings, measurements, counts, symbols and relationships |
| English fluency | 10% | Clear, idiomatic prose and dialogue faithful to the source voice |

Use a 1–10 scale, allowing half-points. Ten means an excellent faithful reading copy; eight means good with local errors; six means useful but noticeably flawed; four means frequent major errors; two means mostly unreliable; one means missing, unrelated or effectively untranslated. Fluent invented content must still score poorly for accuracy and completeness.

Preserve an incomplete fragment at a capture boundary. Do not reward completion of unseen text. Reader controls and progress indicators are not narrative text. Text in contents, captions and artwork is in scope; descriptions of the artwork are not. A stylistic preference alone is not a mistranslation.

Each judge records dimensional scores, coverage percentage, usability, confidence, and up to four substantive issues with severity. The full private review includes source and translation quotations. This package retains only the scores, flags and severity counts.

The capture score averages the two weighted reviews. Configuration means weight captures equally; prose and layout means are separate. Large disagreement or serious alleged errors receives an additional source-based review. Keep the original reviews and mark the adjudication instead of silently revising evidence.

The documented version-2 amendment accepts defensible literal or name readings where the image provides no pronunciation or glossary. All 23 candidates for the affected illustrated capture were blindly rescored under the same rule, without regenerating translations. The original reviews are retained privately. See [METHODS](METHODS.md) for the amendment, client-context limitations and uncertainty calculation.

These are AI judgments of one purposive sample. There is no human-validated gold reference and only one translation generation per setting/capture. Small mean differences may reflect judges or the sample rather than a reliable model advantage.
