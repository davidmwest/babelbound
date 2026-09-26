"""Synthetic regression coverage for the separate DeepSeek publication cohort."""
import json
import re
import unittest

import render_publication as renderer


def fixture():
    configurations = [
        {'id': 'openai', 'model': 'gpt-6-sol', 'effort': 'low', 'cohort': 'codex-cli'},
        {'id': 'gemini', 'model': 'gemini-3-pro', 'effort': 'standard', 'cohort': 'gemini-web'},
        {'id': 'instant', 'model': 'deepseek-v4.1-flash:cloud', 'model_display': 'DeepSeek V4.1 Flash',
         'effort': 'instant', 'cohort': 'ollama-cloud', 'requested_think': False},
        {'id': 'light', 'model': 'deepseek-v4.1-flash:cloud', 'model_display': 'DeepSeek V4.1 Flash',
         'effort': 'light', 'cohort': 'ollama-cloud', 'requested_think': 'low'},
    ]
    data = {
        'configurations': configurations,
        'sources': [{'id': 's01', 'is_prose': True, 'category': 'prose', 'sha256': '0' * 64}],
        'runs': [], 'summary': [],
        'publication': {'ready': True},
        'methodology': {'planned_translations': 4,
            'deepseek': 'Native Ollama API with the frozen prompt.',
            'grading_batches': 'Separate two-candidate grading batch.',
            'transports': 'CLI, browser and native Ollama requests.',
            'cli_versions': 'DeepSeek grading used codex-cli 0.155.0-alpha.16.4.'},
        'pricing': {'date': '2026-09-25', 'tier': 'Standard'},
        'deepseek_pricing': {'date': '2026-09-25', 'source_url': 'https://ollama.com/pricing',
            'peak': {'input': .3, 'cached_input': .006, 'output': 1.2},
            'off_peak': {'input': .15, 'cached_input': .003, 'output': .6},
            'schedule': 'Peak weekdays 12:00–18:00 UTC; off-peak otherwise.',
            'limitations': 'Provider-reported token counts; actual billing not verified.'},
        'value_comparison': {'n': 1, 'total': 1, 'provisional': False, 'rows': []},
    }
    for c, score, cost in zip(configurations, (9.5, 8.5, 9.8, 9.9), (.05, None, .0008, .0012)):
        scores = dict.fromkeys(renderer.DIMENSIONS, score)
        data['runs'].append({'source_id': 's01', 'configuration_id': c['id'], 'status': 'completed',
            'scores': scores, 'elapsed_seconds': 5,
            'reviews': [dict(scores, judge=j, usable=True, coverage_percent=100) for j in ('judge-a', 'judge-b')],
            'cost': {'status': 'estimated' if cost is not None else 'unavailable', 'usd': cost, 'no_cache_usd': cost}})
        summary = {'configuration_id': c['id'], 'mean': score, 'prose_mean': score, 'layout_mean': None,
            'n': 1, 'total': 1, 'unusable': 0, 'failed': 0, 'median_seconds': 5,
            'cost_mean_usd': cost, 'cost_mean_no_cache_usd': cost, 'cost_n': 0 if cost is None else 1,
            'cost_status': 'estimated' if cost is not None else 'unavailable'}
        if c['cohort'] != 'codex-cli':
            summary.update(delivery_counts={'english_translation': 1, 'service_error': 0,
                'non_english_transcription': 0, 'other_failure': 0},
                english_translation_n=1, english_translation_mean=score)
        data['summary'].append(summary)
        # Deliberately include all cohorts to prove the selector stays OpenAI-only.
        data['value_comparison']['rows'].append(dict(summary, eligible=True, cost_eligible=True))
    return data


class DeepSeekRendererTests(unittest.TestCase):
    def test_explicit_and_legacy_cohorts_preserve_native_settings(self):
        data = fixture()
        for c in data['configurations']:
            c.pop('cohort')
        prepared = renderer.prepare(data)
        self.assertEqual([c['cohort'] for c in prepared['configurations']],
            ['codex-cli', 'gemini-web', 'ollama-cloud', 'ollama-cloud'])
        self.assertIs(prepared['configurations'][2]['requested_think'], False)
        self.assertEqual(prepared['configurations'][3]['requested_think'], 'low')
        self.assertEqual(prepared['rows'][2]['model_display'], 'DeepSeek V4.1 Flash')

    def test_cheaper_deepseek_does_not_enter_original_value_ranking(self):
        prepared = renderer.prepare(fixture())
        self.assertTrue(prepared['final'])
        self.assertEqual([r['configuration_id'] for r in prepared['value']['rows']], ['openai'])
        self.assertEqual({r['configuration_id'] for _, r in renderer.value_choices(prepared)}, {'openai'})

    def test_delivery_counts_do_not_mislabel_deepseek_as_gemini(self):
        overview = renderer.readme(fixture())
        gemini = overview.split('## Gemini delivery and conditional quality', 1)[1].split('## DeepSeek', 1)[0]
        deepseek = overview.split('## DeepSeek on Ollama Cloud', 1)[1].split('## How to read', 1)[0]
        self.assertIn('gemini-3-pro / standard', gemini)
        self.assertNotIn('DeepSeek V4.1 Flash', gemini)
        self.assertNotIn('gemini-3-pro / standard', deepseek)
        self.assertIn('DeepSeek V4.1 Flash / light', deepseek)
        self.assertIn('false', deepseek)
        self.assertIn('$0.000800', deepseek)
        self.assertIn('$0.001200', deepseek)
        self.assertIn('9.90/10', deepseek)
        self.assertIn('separate two-candidate grading batch', deepseek)
        self.assertIn('compared descriptively', deepseek)
        self.assertIn('0.155.0-alpha.16.4', deepseek)

    def test_incomplete_publication_withholds_deepseek_takeaway(self):
        data = fixture()
        data['publication']['ready'] = False
        overview = renderer.readme(data)
        self.assertIn('within-batch takeaway is withheld', overview)
        self.assertNotIn('highest observed mean', overview)
        self.assertNotIn('cheapest eligible setting', overview)

    def test_english_delivery_is_distinct_from_unanimous_usability(self):
        data = fixture()
        # The response remains English and the aggregate unusable count remains
        # zero, but a negative judgment from either reviewer prevents unanimity.
        data['runs'][2]['reviews'][0]['usable'] = False
        prepared = renderer.prepare(data)
        self.assertEqual(prepared['rows'][2]['delivery_counts']['english_translation'], 1)
        self.assertEqual(prepared['rows'][2]['both_reviewers_usable'], 0)
        self.assertEqual(prepared['rows'][3]['both_reviewers_usable'], 1)
        overview = renderer.readme(data)
        self.assertIn('DeepSeek V4.1 Flash / instant: **0/1 usable by both reviewers**', overview)
        self.assertIn('DeepSeek V4.1 Flash / light: **1/1 usable by both reviewers**', overview)
        self.assertIn('Usable by both / planned', overview)
        row = next(line for line in overview.splitlines() if line.startswith('| DeepSeek V4.1 Flash / instant'))
        self.assertEqual([cell.strip() for cell in row.split('|')][6:8], ['1/1', '0/1'])
        report = renderer.render(data)
        self.assertIn('<th>Usable by both / planned</th>', report)
        self.assertIn('English delivery does not by itself establish an acceptable translation', report)

    def test_no_cost_is_invented_and_zero_remains_a_recorded_number(self):
        data = fixture()
        data['summary'][2]['cost_mean_no_cache_usd'] = None
        data['summary'][2]['cost_status'] = 'unavailable'
        data['summary'][3]['cost_mean_no_cache_usd'] = 0
        prepared = renderer.prepare(data)
        self.assertIsNone(prepared['rows'][2]['cost_mean_no_cache_usd'])
        self.assertEqual(prepared['rows'][3]['cost_mean_no_cache_usd'], 0)
        overview = renderer.readme(data)
        instant = next(line for line in overview.splitlines() if line.startswith('| DeepSeek V4.1 Flash / instant'))
        light = next(line for line in overview.splitlines() if line.startswith('| DeepSeek V4.1 Flash / light'))
        self.assertIn('| — | 1 | unavailable |', instant)
        self.assertIn('$0.000000', light)

    def test_pricing_and_methodology_allowlists_exclude_raw_payloads(self):
        data = fixture()
        data['configurations'][2]['request_body'] = 'DO_NOT_PUBLISH_CONFIG'
        data['deepseek_pricing']['raw_response'] = 'DO_NOT_PUBLISH_PRICING'
        data['deepseek_pricing']['peak']['credentials'] = 'DO_NOT_PUBLISH_RATE'
        data['deepseek_pricing']['source_url'] = 'https://example.invalid/private'
        data['runs'][2]['translation'] = 'DO_NOT_PUBLISH_TRANSLATION'
        data['runs'][2]['reviews'][0]['quote'] = 'DO_NOT_PUBLISH_QUOTE'
        prepared = renderer.prepare(data)
        self.assertNotIn('DO_NOT_PUBLISH', json.dumps(prepared))
        self.assertNotIn('source_url', prepared['deepseek_pricing'])
        self.assertEqual(prepared['deepseek_pricing']['peak']['output'], 1.2)
        self.assertEqual(prepared['methodology']['cli_versions'], data['methodology']['cli_versions'])

    def test_html_data_escapes_script_end_and_contains_separate_cost_section(self):
        data = fixture()
        data['configurations'][2]['model_display'] = '</script><script>alert(1)</script>'
        report = renderer.render(data)
        payload = re.search(r'<script id="data" type="application/json">(.*?)</script>', report, re.S).group(1)
        prepared = json.loads(payload)
        self.assertEqual(prepared['configurations'][2]['model_display'], data['configurations'][2]['model_display'])
        self.assertNotIn('</script>', payload)
        self.assertIn('id="deepseek-body"', report)
        self.assertIn('No-cache USD / capture', report)
        self.assertIn("r.cohort==='gemini-web'&&r.delivery_counts", report)
        self.assertIn("r.cohort==='ollama-cloud'", report)

    def test_original_openai_only_report_keeps_legacy_behavior(self):
        data = fixture()
        data['configurations'] = data['configurations'][:1]
        data['configurations'][0].pop('cohort')
        data['runs'] = data['runs'][:1]
        data['summary'] = data['summary'][:1]
        data['methodology']['planned_translations'] = 1
        data.pop('deepseek_pricing')
        overview = renderer.readme(data)
        self.assertIn('## Quality and estimated cost', overview)
        self.assertNotIn('## DeepSeek', overview)
        self.assertNotIn('## Gemini', overview)
        self.assertTrue(renderer.prepare(data)['final'])


if __name__ == '__main__':
    unittest.main()
