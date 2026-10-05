# Luna retest: screenshots and clean Japanese text

Luna's fresh screenshot results improved substantially at High and above. Medium still struggled with images; a separate paired control tests whether supplying Japanese text changes that result.

[Screenshot report](report.html) · [Numeric results](results.json) · [Methods and limitations](METHODS.md)

## Fresh screenshot translations

Same 12 captures and prompt as September. Both AI judges reviewed each original/fresh pair together. Costs are mean standard API-equivalent estimates with observed caching, excluding evaluation—not actual bills.

| Reasoning | Fresh score /10 | Usable by both judges | USD per capture |
| --- | ---: | ---: | ---: |
| low | 4.33 | 0/12 | $0.001204 |
| medium | 4.88 | 1/12 | $0.001176 |
| high | 9.18 | 12/12 | $0.002325 |
| xhigh | 9.52 | 12/12 | $0.004703 |
| max | 9.33 | 12/12 | $0.006498 |

High was the least expensive tested setting with every output usable. Xhigh had the highest sample mean; Max cost more without improving that mean. These are observations from a small sample, not guarantees for another book. The retest does not prove which model or image-processing change caused the improvement.

## Medium with clean Japanese text

On all nine prose captures, Luna Medium scored **9.53/10 from text versus 4.69/10 from screenshots**. Both judges marked **9/9 text translations usable**, versus **1/9 image translations**. Names and subtle meaning errors still need review.

Luna's text translation averaged **$0.000803 per capture (0.0803¢)**. Preparing that text with Astra High transcription and Sol High verification averaged **$0.299882 separately**. Those preparation costs cannot be omitted when starting from screenshots. This test establishes a promising result for clean text; it does not establish a cheap OCR pipeline.

The same two judges graded these anonymous pairs in separate packets from the screenshot retest. The image score therefore differs from the larger retest's prose score. Text and screenshot prompts also differ in input formatting. Transcriptions and scores are AI-reviewed, not human ground truth; the sample comes from one series.

[Text-versus-image report](text-control.html) · [Numeric text-control results](text-control.json)
