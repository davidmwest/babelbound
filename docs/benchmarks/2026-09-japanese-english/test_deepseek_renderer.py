"""Synthetic regression coverage for the separate DeepSeek publication cohort."""
import copy
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


def expanded_fixture():
    data = fixture()
    data['schema_version'] = 4
    settings = (
        ('high', 'deepseek-v4.1-flash:cloud', 'DeepSeek V4.1 Flash', 'high', 'high', 8.4, .002),
        ('gemma-instant', 'gemma4:31b-cloud', 'Gemma 4 31B', 'instant', False, 7.6, .0003),
        ('gemma-thinking', 'gemma4:31b-cloud', 'Gemma 4 31B', 'thinking', True, 8.1, .0009),
    )
    for cid, model, display, effort, think, score, cost in settings:
        data['configurations'].append({'id': cid, 'model': model, 'model_display': display,
            'cohort': 'ollama-cloud-expanded', 'effort': effort, 'requested_think': think})
        run = copy.deepcopy(data['runs'][2])
        run.update(configuration_id=cid, scores=dict.fromkeys(renderer.DIMENSIONS, score),
            cost={'status': 'estimated', 'usd': cost, 'no_cache_usd': cost})
        for review in run['reviews']:
            review.update(dict.fromkeys(renderer.DIMENSIONS, score))
        data['runs'].append(run)
        row = copy.deepcopy(data['summary'][2])
        row.update(configuration_id=cid, mean=score, prose_mean=score, cost_mean_usd=cost,
            cost_mean_no_cache_usd=cost, english_translation_mean=score)
        data['summary'].append(row)
        data['value_comparison']['rows'].append(dict(row, eligible=True, cost_eligible=True))
    data['methodology'].update(planned_translations=7,
        ollama_expanded='A later cohort uses a pair and a singleton per source and reviewer.',
        native_controls='Medium is not supported and falls back to default high; no separate Medium condition is included. Gemma uses boolean false and true.')
    data['ollama_expanded_pricing'] = {
        'deepseek-v4.1-flash:cloud': copy.deepcopy(data['deepseek_pricing']),
        'gemma4:31b-cloud': {'date': '2026-09-25', 'source_url': 'https://ollama.com/pricing',
            'peak': {'input': .14, 'cached_input': .05, 'output': .4},
            'off_peak': {'input': .14, 'cached_input': .05, 'output': .4},
            'schedule': 'A single all-hours rate is published; no separate off-peak rate.',
            'limitations': 'No-cache estimate, not an observed account charge.'}}
    return data


def interrupted_fixture():
    data = expanded_fixture()
    data['sources'].append(dict(data['sources'][0], id='s02'))
    data['runs'].extend(dict(copy.deepcopy(r), source_id='s02', elapsed_seconds=7)
        for r in list(data['runs']))
    for row in data['summary']:
        row.update(n=2, total=2, cost_n=2 if row['cost_n'] else 0)
        if 'delivery_counts' in row:
            row['delivery_counts']['english_translation'] = 2
            row['english_translation_n'] = 2
    run = data['runs'][6]
    run.update(status='interrupted', elapsed_seconds=1801.25,
        scores=dict.fromkeys(renderer.DIMENSIONS, 1), cost=None,
        administrative_interruption={'reason': 'DO_NOT_PUBLISH_PRIVATE_REASON',
            'deadline_seconds': 1800, 'elapsed_seconds': 1801.25})
    for review in run['reviews']:
        review.update(dict.fromkeys(renderer.DIMENSIONS, 1), usable=False)
    data['summary'][6].update(mean=4.55, prose_mean=4.55, unusable=1, failed=1,
        cost_n=1, cost_mean_usd=None, cost_mean_no_cache_usd=None, cost_status='unavailable',
        delivery_counts={'english_translation': 1, 'service_error': 0,
            'non_english_transcription': 0, 'other_failure': 1},
        english_translation_n=1)
    data['methodology']['planned_translations'] = 14
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


class ExpandedOllamaRendererTests(unittest.TestCase):
    def test_long_native_outlier_is_visible_without_changing_historical_rows(self):
        data = expanded_fixture()
        data['sources'].extend(dict(data['sources'][0], id=s) for s in ('s02', 's03'))
        template = data['runs'][6]
        template['elapsed_seconds'] = 5
        data['runs'].extend(dict(copy.deepcopy(template), source_id=s, elapsed_seconds=t)
            for s, t in (('s02', 7), ('s03', 3600)))
        data['summary'][6].update(median_seconds=999, total=3)
        original = renderer.prepare(fixture())
        prepared = renderer.prepare(data)
        row = prepared['rows'][6]
        self.assertEqual((row['median_seconds'], row['mean_seconds'], row['max_seconds'], row['timing_n']),
            (7, 1204, 3600, 3))
        self.assertEqual(prepared['rows'][:4], original['rows'])
        self.assertEqual(prepared['value'], original['value'])
        text = renderer.readme(data)
        line = next(line for line in text.splitlines() if line.startswith('| gemma4:31b-cloud / thinking'))
        self.assertIn('| 7.0 | 1204.0 | 3600.0 | 3/3 |', line)
        self.assertIn('Mean and maximum expose slow requests', text)
        html = renderer.render(data)
        section = html.split('<section id="ollama-expanded"', 1)[1].split('<section id="methods">', 1)[0]
        self.assertIn('<th>Completed mean seconds</th><th>Completed maximum seconds</th><th>Timed completed / planned</th>', section)
        self.assertIn('Native elapsed: ', html)

    def test_unavailable_or_unfinished_timing_is_not_zero(self):
        for elapsed in (None, float('nan'), True, -1):
            with self.subTest(elapsed=elapsed):
                data = expanded_fixture()
                data['runs'][6]['elapsed_seconds'] = elapsed
                row = renderer.prepare(data)['rows'][6]
                self.assertEqual(row['timing_n'], 0)
                for key in ('median_seconds', 'mean_seconds', 'max_seconds'):
                    self.assertIsNone(row[key])
                line = next(line for line in renderer.readme(data).splitlines()
                    if line.startswith('| gemma4:31b-cloud / thinking'))
                self.assertIn('| — | — | — | 0/1 |', line)
        data = expanded_fixture()
        data['runs'][6].update(status='running', elapsed_seconds=3600)
        row = renderer.prepare(data)['rows'][6]
        self.assertEqual(row['timing_n'], 0)
        self.assertIsNone(row['max_seconds'])
        data['runs'][6].update(status='completed', elapsed_seconds=0)
        row = renderer.prepare(data)['rows'][6]
        self.assertEqual((row['median_seconds'], row['mean_seconds'], row['max_seconds'], row['timing_n']),
            (0, 0, 0, 1))

    def test_frozen_rows_and_openai_value_are_preserved(self):
        old = renderer.prepare(fixture())
        new = renderer.prepare(expanded_fixture())
        self.assertTrue(new['final'])
        self.assertEqual(new['expected'], 7)
        for key in ('configurations', 'rows', 'runs'):
            self.assertEqual(old[key], new[key][:4])
        self.assertEqual(old['value'], new['value'])
        self.assertEqual(renderer.value_choices(old), renderer.value_choices(new))
        self.assertEqual(old['deepseek_pricing'], new['deepseek_pricing'])

    def test_expanded_cohort_has_separate_native_settings_and_prices(self):
        data = expanded_fixture()
        prepared = renderer.prepare(data)
        self.assertEqual([c['requested_think'] for c in prepared['configurations'][4:]], ['high', False, True])
        readme = renderer.readme(data)
        old_section, expanded = readme.split('## Gemma 4 and DeepSeek High on Ollama Cloud', 1)
        self.assertNotIn('| gemma4:31b-cloud', old_section)
        self.assertIn('| deepseek-v4.1-flash:cloud / high | high |', expanded)
        self.assertIn('| gemma4:31b-cloud / instant | false |', expanded)
        self.assertIn('| gemma4:31b-cloud / thinking | true |', expanded)
        self.assertIn('pair and a singleton', expanded)
        self.assertIn('Medium is not supported', expanded)
        self.assertIn('A single all-hours rate', expanded)
        self.assertIn('$0.140000 input; $0.050000 cached input; $0.400000 output', expanded)
        self.assertIn('$0.300000 input; $0.006000 cached input; $1.200000 output', expanded)
        self.assertIn('$0.150000 input; $0.003000 cached input; $0.600000 output', expanded)
        self.assertIn('do not establish a controlled improvement', expanded)
        report = renderer.render(data)
        self.assertIn('id="ollama-expanded-body"', report)
        self.assertIn("r.cohort==='ollama-cloud-expanded'", report)

    def test_expanded_english_delivery_does_not_hide_split_usability(self):
        data = expanded_fixture()
        data['runs'][5]['reviews'][0]['usable'] = False
        prepared = renderer.prepare(data)
        self.assertEqual(prepared['rows'][5]['delivery_counts']['english_translation'], 1)
        self.assertEqual(prepared['rows'][5]['both_reviewers_usable'], 0)
        text = renderer.readme(data).split('## Gemma 4 and DeepSeek High on Ollama Cloud', 1)[1]
        self.assertIn('**Gemma 4 31B / instant** (native think: `false`): **7.60/10 mean**, **0/1 usable by both reviewers**, 1/1 delivered English', text)

    def test_expanded_draft_and_missing_cost_remain_explicit(self):
        data = expanded_fixture()
        data['summary'][4].update(cost_mean_no_cache_usd=None, cost_status='unavailable')
        data['summary'][5]['cost_mean_no_cache_usd'] = 0
        data['publication']['ready'] = False
        text = renderer.readme(data).split('## Gemma 4 and DeepSeek High on Ollama Cloud', 1)[1]
        self.assertIn('within-cohort takeaway is withheld', text)
        self.assertNotIn('**8.40/10 mean**', text)
        row = next(line for line in text.splitlines() if line.startswith('| deepseek-v4.1-flash:cloud / high'))
        self.assertIn('| — | 1/1 | unavailable |', row)
        self.assertIn('$0.000000', text)

    def test_interrupted_attempt_is_censored_but_still_graded(self):
        data = interrupted_fixture()
        prepared = renderer.prepare(data)
        self.assertTrue(prepared['final'])
        self.assertEqual((prepared['graded'], prepared['expected']), (14, 14))
        row = prepared['rows'][6]
        self.assertEqual((row['median_seconds'], row['mean_seconds'], row['max_seconds'], row['timing_n']),
            (7, 7, 7, 1))
        self.assertEqual((row['interrupted'], row['interrupted_elapsed_seconds_max']), (1, 1801.25))
        self.assertEqual((row['n'], row['total'], row['mean'], row['both_reviewers_usable']),
            (2, 2, 4.55, 1))
        self.assertEqual(row['delivery_counts']['other_failure'], 1)
        self.assertEqual(row['cost_n'], 1)
        self.assertEqual(row['cost_status'], 'unavailable')
        self.assertIsNone(row['cost_mean_usd'])
        self.assertIsNone(row['cost_mean_no_cache_usd'])
        self.assertNotIn('DO_NOT_PUBLISH', json.dumps(prepared))
        text = renderer.readme(data)
        self.assertIn('14 / 14 planned translation attempts assessed', text)
        self.assertIn('two source-based AI reviews per assessed attempt', text)
        self.assertNotIn('per completed translation', text)
        self.assertIn('1/2 interrupted (longest observed ≥ 1801.2 seconds)', text)
        self.assertIn('average no-cache cost unknown (1/2 priced)', text)
        line = next(line for line in text.splitlines() if line.startswith('| gemma4:31b-cloud / thinking'))
        self.assertIn('| 7.0 | 7.0 | 7.0 | 1/2 | 1/2 | ≥ 1801.2 | — | 1/2 | unavailable |', line)
        self.assertIn('lower bound on completion time, not a completed latency', text)
        report = renderer.render(data)
        self.assertIn('<th>Interrupted / planned</th><th>Longest interrupted seconds</th>', report)
        self.assertIn('Completion time: ', report)

    def test_interruption_cost_and_unavailable_elapsed_never_become_zero(self):
        for elapsed in (None, float('nan'), True, -1):
            with self.subTest(elapsed=elapsed):
                data = interrupted_fixture()
                # Even stale estimates cannot become a cost for an interrupted stream.
                data['runs'][6].update(elapsed_seconds=elapsed,
                    cost={'usd': 0, 'no_cache_usd': 0, 'status': 'estimated'})
                data['summary'][6].update(cost_mean_usd=0, cost_mean_no_cache_usd=0,
                    cost_n=2, cost_status='estimated')
                prepared = renderer.prepare(data)
                row = prepared['rows'][6]
                self.assertEqual(row['interrupted'], 1)
                self.assertIsNone(row['interrupted_elapsed_seconds_max'])
                self.assertEqual(row['cost_n'], 1)
                self.assertEqual(row['cost_status'], 'unavailable')
                self.assertIsNone(row['cost_mean_usd'])
                self.assertEqual(prepared['runs'][6]['cost'],
                    {'usd': None, 'no_cache_usd': None, 'status': 'unavailable'})
                line = next(line for line in renderer.readme(data).splitlines()
                    if line.startswith('| gemma4:31b-cloud / thinking'))
                self.assertIn('| 1/2 | 1/2 | — | — | 1/2 | unavailable |', line)

    def test_interrupted_publication_still_requires_gate_and_two_reviews(self):
        data = interrupted_fixture()
        data['publication']['ready'] = False
        self.assertFalse(renderer.prepare(data)['final'])
        data['publication']['ready'] = True
        data['runs'][6]['reviews'].pop()
        self.assertFalse(renderer.prepare(data)['final'])
        historical = fixture()
        historical['runs'][2]['status'] = 'interrupted'
        self.assertFalse(renderer.prepare(historical)['final'])

    def test_new_pricing_projection_excludes_unrecognized_or_private_fields(self):
        data = expanded_fixture()
        data['ollama_expanded_pricing']['DO_NOT_PUBLISH_MODEL'] = {'raw': 'DO_NOT_PUBLISH'}
        p = data['ollama_expanded_pricing']['gemma4:31b-cloud']
        p.update(raw_response='DO_NOT_PUBLISH', limitations={'quote': 'DO_NOT_PUBLISH'},
            source_url='https://example.invalid/DO_NOT_PUBLISH')
        p['peak']['raw'] = 'DO_NOT_PUBLISH'
        p['peak']['input'] = {'raw': 'DO_NOT_PUBLISH'}
        data['configurations'][6]['requested_think'] = {'raw': 'DO_NOT_PUBLISH'}
        data['runs'][6]['translation'] = 'DO_NOT_PUBLISH'
        payload = renderer.prepare(data)
        self.assertNotIn('DO_NOT_PUBLISH', json.dumps(payload))
        p = payload['ollama_expanded_pricing']['gemma4:31b-cloud']
        self.assertIsNone(p['peak']['input'])
        self.assertEqual(p['peak']['output'], .4)
        self.assertNotIn('source_url', p)


if __name__ == '__main__':
    unittest.main()
