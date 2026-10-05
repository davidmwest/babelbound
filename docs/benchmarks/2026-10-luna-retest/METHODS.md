# Luna retest methods

This follow-up keeps the September benchmark intact. It asks two narrower questions: how Luna performs on a fresh run of the same captures, and whether supplying Japanese text improves Medium's translation quality.

## Screenshot retest

- Same 12 PNG files and exact translation prompt as the original benchmark; source and prompt hashes are checked.
- Five reasoning settings: Low, Medium, High, Xhigh, and Max. There are 60 fresh translations, each in an isolated, ephemeral Codex CLI session.
- Original and fresh translations are reviewed together, anonymously, by Astra High and Sol High. Each old/new pair stays in the same review packet. Each capture has packets containing three pairs and two pairs, with independent candidate ordering for each judge.
- Scores weight accuracy 50%, completeness 25%, names/numbers 15%, and fluency 10%. “Usable” requires both judges to consider the translation usable without major correction.
- Historical scores remain separate from freshly regraded scores. Paired bootstrap intervals resample the 12 captures, with 10,000 replicates and seed 20261004. They describe this sample, not translation quality across books.

The September 25 image-encoding fix motivated this retest, but this is not a causal test of that fix. The model, CLI, and judges can change, and the precise deployment time relative to the original requests is unknown.

## Text-only Medium control

All nine prose captures are included. Astra High transcribes the Japanese, then Sol High checks and corrects that transcription against the original image. Luna Medium receives the resulting Japanese text, with no image attached, in a separate ephemeral session. No previous English translations or review comments are supplied to it.

Astra High and Sol High independently compare anonymous text-input and screenshot-input translations against the original image. Each packet contains just those two candidates. These grades therefore form their own paired comparison; they should not be substituted into the larger screenshot retest's review batches.

The text prompt adapts the original translation requirements to Japanese text and explains parenthetical ruby readings. That wrapper differs from the screenshot prompt, so the intervention includes both transcription and input formatting. Transcriptions are AI-verified, not human ground truth. The same model families prepare and evaluate the text in independent sessions, which may introduce shared biases. Remaining transcription errors can affect the final English.

## Cost and scope

Prices are standard API-equivalent estimates from recorded CLI token usage, not actual bills or Babelbound charges. They include CLI context and recorded reasoning output. Grading costs are excluded. Text-only translation cost and the cost of preparing the Japanese transcription are reported separately: clean text does not require that preparation, but a workflow starting with screenshots does.

This is a small sample from one novel series, reviewed by AI judges. Some captures contain two printed pages. It is not a human-validated quality ranking or an estimate for every Japanese book.

Only scores, usage, hashes, and methods are published. Source scans, Japanese transcriptions, English translations, review excerpts, and account details remain private.
