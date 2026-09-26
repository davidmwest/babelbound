"""Synthetic gates for appending native Ollama results to a frozen publication."""
import copy
import hashlib
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

import prepare_publication as core
import prepare_combined_publication as combined
import prepare_deepseek_publication as deepseek
from test_combined_publication import fixture as combined_fixture


def fixture():
    original, gemini, kwargs = combined_fixture()
    base = combined.sanitize(original, gemini, **kwargs)
    base_bytes = json.dumps(base).encode()
    pricing = {'date': '2026-09-25', 'source_url': 'https://ollama.com/pricing',
        'peak': {'input': .3, 'cached_input': .006, 'output': 1.2},
        'off_peak': {'input': .15, 'cached_input': .003, 'output': .6},
        'schedule': 'Peak weekdays 12:00–18:00 UTC.', 'limitations': 'Synthetic no-cache tariff estimate.'}
    curation = {'base_results_sha256': deepseek.sha(base_bytes), 'deepseek_review_version': 1,
        'pricing': pricing, 'methodology_additions': {'deepseek': 'Synthetic native requests only.',
            'cli_versions': 'Synthetic reviewers use codex-cli 0.155.0-alpha.16.4.'}}
    configs = [{'id': cid, 'model': deepseek.MODEL, 'effort': effort, 'native_think': think,
        'provider': deepseek.COHORT} for cid, (effort, think) in deepseek.CONFIGS.items()]
    sources = [{'id': s['id'], 'category': s['category'], 'prose': s['is_prose'], 'sha256': s['sha256']}
        for s in base['sources']]
    runs = []
    for c in configs:
        for s in sources:
            r = copy.deepcopy(original['runs'][0])
            r.update(configuration_id=c['id'], source_id=s['id'], model=deepseek.MODEL,
                native_think=c['native_think'], returned_model='deepseek-v4.1-flash',
                started_at='2026-09-25T12:00:00Z', attempt_count=1,
                thinking_present=c['native_think'] is not False, provenance_problems=[], quota_warning=None,
                adjudication=None, adjudication_resolved=False,
                usage={'input_tokens': 1000, 'output_tokens': 200, 'cached_input_tokens': None,
                    'cache_write_input_tokens': None, 'reasoning_output_tokens': None},
                cost={'status': 'estimated', 'usd': .00054, 'no_cache_usd': .00054,
                    'output_includes_thinking': True},
                delivery_outcome={'audited': True, 'classification': 'english_translation',
                    'source_id': s['id'], 'packet_sha256': s['sha256']})
            for v in r['reviews']:
                v['review_version'] = 1
            runs.append(r)
    sa = [{'source_id': s['id'], 'status': 'not_needed', 'flagged_candidates': 0} for s in sources]
    da = [{'source_id': s['id'], 'status': 'resolved', 'audited_candidates': 2,
        'packet_sha256': s['sha256']} for s in sources]
    raw = {'status': 'complete', 'generated_at': '2026-09-25T18:00:00Z', 'sources': sources,
        'configurations': configs, 'runs': runs, 'source_audits': sa, 'delivery_audits': da}
    audit = {'passed': True, 'complete': True, 'planned_cells': 24, 'completed_responses': 24,
        'double_reviewed_cells': 24,
        'source_hash_checks': [{'source_id': s['id'], 'expected_sha256': s['sha256'],
            'actual_sha256': s['sha256'], 'matched': True} for s in sources]}
    return base_bytes, raw, audit, curation


class DeepSeekPublicationTests(unittest.TestCase):
    def setUp(self):
        self.base_bytes, self.raw, self.audit, self.curation = fixture()

    def clean(self, refresh=True):
        raw_bytes = json.dumps(self.raw).encode()
        if refresh:
            self.audit.update(results_sha256=deepseek.sha(raw_bytes),
                source_audit_checks=copy.deepcopy(self.raw['source_audits']),
                delivery_audit_checks=copy.deepcopy(self.raw['delivery_audits']))
        return deepseek.sanitize(self.base_bytes, raw_bytes, self.audit, self.curation)

    def test_append_preserves_every_frozen_record_and_original_value_analysis(self):
        base = json.loads(self.base_bytes)
        raw_before = copy.deepcopy(self.raw)
        output = self.clean()
        self.assertTrue(output['publication']['ready'], output['publication']['gate_reasons'])
        self.assertEqual((len(output['configurations']), len(output['runs'])), (31, 372))
        self.assertEqual(sum(len(r['reviews']) for r in output['runs']), 744)
        for key in ('runs', 'configurations', 'summary'):
            self.assertEqual(output[key][:len(base[key])], base[key])
        for key in ('value_comparison', 'sources', 'paired_comparisons'):
            self.assertEqual(output.get(key), base.get(key))
        self.assertEqual(self.raw, raw_before)
        self.assertEqual(output['schema_version'], 3)
        self.assertEqual(output['methodology']['planned_translations'], 372)
        self.assertEqual(output['summary'][-1]['cost_n'], 12)
        self.assertAlmostEqual(output['summary'][-1]['cost_mean_no_cache_usd'], .00054)

    def test_base_byte_binding_and_source_identity_are_required(self):
        with self.assertRaises(ValueError):
            deepseek.sanitize(self.base_bytes + b' ', json.dumps(self.raw).encode(), self.audit, self.curation)
        for field, value in (('sha256', 'f' * 64), ('prose', False), ('category', 'Other')):
            with self.subTest(field=field):
                raw = copy.deepcopy(self.raw)
                self.raw['sources'][0][field] = value if self.raw['sources'][0].get(field) != value else True
                with self.assertRaises(ValueError):
                    self.clean()
                self.raw = raw

    def test_exact_matrix_rejects_missing_duplicate_or_wrong_configuration(self):
        original = copy.deepcopy(self.raw)
        for mutation in ('missing', 'duplicate', 'wrong_setting', 'wrong_think_type'):
            with self.subTest(mutation=mutation):
                self.raw = copy.deepcopy(original)
                if mutation == 'missing': self.raw['runs'].pop()
                elif mutation == 'duplicate': self.raw['runs'][-1] = copy.deepcopy(self.raw['runs'][0])
                elif mutation == 'wrong_setting': self.raw['runs'][0]['native_think'] = 'low'
                else: self.raw['configurations'][0]['native_think'] = 0
                with self.assertRaises(ValueError):
                    self.clean()

    def test_receipt_binds_exact_results_and_source_hashes(self):
        self.clean()
        self.raw['runs'][0]['elapsed_seconds'] = 99
        self.assertFalse(self.clean(refresh=False)['publication']['ready'])
        self.audit['source_hash_checks'][0]['actual_sha256'] = 'f' * 64
        self.assertFalse(self.clean()['publication']['ready'])

    def test_source_and_delivery_audits_cannot_be_waived(self):
        original = copy.deepcopy(self.raw)
        for mutation in ('source_pending', 'delivery_missing', 'candidate_count', 'unbound_packet', 'unaudited'):
            with self.subTest(mutation=mutation):
                self.raw = copy.deepcopy(original)
                if mutation == 'source_pending': self.raw['source_audits'][0]['status'] = 'pending'
                elif mutation == 'delivery_missing': self.raw['delivery_audits'].pop()
                elif mutation == 'candidate_count': self.raw['delivery_audits'][0]['audited_candidates'] = 6
                elif mutation == 'unbound_packet': self.raw['runs'][0]['delivery_outcome']['packet_sha256'] = 'f' * 64
                else: self.raw['runs'][0]['delivery_outcome']['audited'] = False
                self.assertFalse(self.clean()['publication']['ready'])

    def test_matching_delivery_packet_identifiers_must_be_lowercase_sha256(self):
        original = copy.deepcopy(self.raw)
        for packet in ('not-a-hash', 'A' * 64, 'f' * 63):
            with self.subTest(packet=packet):
                self.raw = copy.deepcopy(original)
                source_id = self.raw['delivery_audits'][0]['source_id']
                self.raw['delivery_audits'][0]['packet_sha256'] = packet
                for run in self.raw['runs']:
                    if run['source_id'] == source_id:
                        run['delivery_outcome']['packet_sha256'] = packet
                self.assertFalse(self.clean()['publication']['ready'])

    def test_distinct_current_reviewers_and_unchanged_weighted_scores_required(self):
        original = copy.deepcopy(self.raw)
        for mutation in ('same_judge', 'old_version', 'unfinished'):
            with self.subTest(mutation=mutation):
                self.raw = copy.deepcopy(original)
                r = self.raw['runs'][0]
                if mutation == 'same_judge': r['reviews'][1]['judge'] = r['reviews'][0]['judge']
                elif mutation == 'old_version': r['reviews'][0]['review_version'] = 2
                else: r['review_statuses'][0]['status'] = 'pending'
                self.assertFalse(self.clean()['publication']['ready'])
        self.raw = copy.deepcopy(original)
        self.raw['runs'][0]['reviews'][0]['overall'] = 8
        with self.assertRaises(ValueError):
            self.clean()

    def test_flagged_content_needs_resolved_source_adjudication(self):
        r = self.raw['runs'][0]
        r['reviews'][0]['issues'] = [{'severity': 'critical', 'explanation': 'PRIVATE_DETAIL'}]
        self.assertFalse(self.clean()['publication']['ready'])
        r.update(adjudication={'verdict': 'supported', 'score_override_recommended': False}, adjudication_resolved=True)
        self.assertTrue(self.clean()['publication']['ready'])
        r['adjudication']['score_override_recommended'] = True
        self.assertFalse(self.clean()['publication']['ready'])

    def test_peak_off_peak_and_timezone_boundaries_use_ollama_schedule(self):
        for started, period, amount in (
            ('2026-09-25T11:59:59Z', 'off_peak', .00027),
            ('2026-09-25T12:00:00Z', 'peak', .00054),
            ('2026-09-25T17:59:59Z', 'peak', .00054),
            ('2026-09-25T18:00:00Z', 'off_peak', .00027),
            ('2026-09-26T13:00:00Z', 'off_peak', .00027),
            ('2026-09-25T05:00:00-07:00', 'peak', .00054)):
            with self.subTest(started=started):
                run = copy.deepcopy(self.raw['runs'][0])
                run['started_at'] = started
                run['cost']['usd'] = amount
                usage, cost = deepseek.native_cost(run, self.curation['pricing'])
                self.assertEqual(cost['period'], period)
                self.assertAlmostEqual(cost['no_cache_usd'], amount)
                self.assertIsNone(usage['cached_input_tokens'])
                self.assertIsNone(usage['reasoning_output_tokens'])
                self.assertIsNone(cost['cached_input_usd'])
                self.assertFalse(cost['actual_account_charge_known'])

    def test_incomplete_attempt_or_thinking_usage_cannot_claim_complete_cost(self):
        for field, value in (('attempt_count', 2), ('output_includes_thinking', False),
                ('output_includes_thinking', 'false')):
            with self.subTest(field=field, value=value):
                run = copy.deepcopy(self.raw['runs'][0])
                (run['cost'] if field == 'output_includes_thinking' else run)[field] = value
                with self.assertRaises(ValueError):
                    deepseek.native_cost(run, self.curation['pricing'])
        run = copy.deepcopy(self.raw['runs'][0])
        run.update(attempt_count=2)
        run['cost']['status'] = 'lower_bound'
        _, cost = deepseek.native_cost(run, self.curation['pricing'])
        self.assertEqual(cost['status'], 'lower_bound')

    def test_missing_counts_are_unknown_and_native_cache_counts_cannot_be_invented(self):
        for field in ('cached_input_tokens', 'cache_write_input_tokens', 'reasoning_output_tokens'):
            with self.subTest(field=field):
                run = copy.deepcopy(self.raw['runs'][0])
                run['usage'][field] = 0
                with self.assertRaises(ValueError):
                    deepseek.native_cost(run, self.curation['pricing'])
        run = copy.deepcopy(self.raw['runs'][0])
        run['usage']['output_tokens'] = None
        with self.assertRaises(ValueError):
            deepseek.native_cost(run, self.curation['pricing'])
        run['cost'] = {'status': 'unavailable'}
        _, cost = deepseek.native_cost(run, self.curation['pricing'])
        self.assertIsNone(cost['usd'])

    def test_unavailable_native_cost_rejects_numeric_estimates_even_with_missing_counts(self):
        for field in core.COST_NUMBERS:
            for value in (0, 99):
                for missing_count in (False, True):
                    with self.subTest(field=field, value=value, missing_count=missing_count):
                        run = copy.deepcopy(self.raw['runs'][0])
                        run['cost'] = {'status': 'unavailable', field: value}
                        if missing_count:
                            run['usage']['output_tokens'] = None
                        with self.assertRaisesRegex(ValueError, 'Unavailable native cost'):
                            deepseek.native_cost(run, self.curation['pricing'])

    def test_unknown_sample_cost_withholds_aggregate_mean_but_retains_known_total(self):
        run = self.raw['runs'][0]
        run['usage']['output_tokens'] = None
        run['cost'] = {'status': 'unavailable'}
        result = self.clean()
        self.assertTrue(result['publication']['ready'])
        summary = next(s for s in result['summary'] if s['configuration_id'] == run['configuration_id'])
        self.assertEqual(summary['cost_status'], 'unavailable')
        self.assertEqual(summary['cost_n'], 11)
        self.assertAlmostEqual(summary['cost_total_usd'], 11 * .00054)
        self.assertIsNone(summary['cost_mean_usd'])
        self.assertIsNone(summary['cost_mean_no_cache_usd'])

    def test_fully_priced_lower_bound_still_has_a_lower_bound_mean(self):
        run = self.raw['runs'][0]
        run['attempt_count'] = 2
        run['cost']['status'] = 'lower_bound'
        result = self.clean()
        summary = next(s for s in result['summary'] if s['configuration_id'] == run['configuration_id'])
        self.assertEqual(summary['cost_status'], 'lower_bound')
        self.assertEqual(summary['cost_n'], 12)
        self.assertAlmostEqual(summary['cost_mean_usd'], .00054)
        self.assertAlmostEqual(summary['cost_mean_no_cache_usd'], .00054)

    def test_private_payloads_are_excluded_and_malformed_public_scalars_abort(self):
        secret = 'PRIVATE_NATIVE_CANARY ' + ('/' + 'Users/' + 'SecretPerson/book.txt') + '\u672c\u6587'
        r = self.raw['runs'][0]
        r.update(translation=secret, thinking=secret, request_body=secret, raw_stream=secret,
            endpoint=secret, metadata={'secret': secret})
        r['reviews'][0].update(notes=secret, issues=[{'severity': 'minor', 'explanation': secret}])
        r['cost'].update(notes=[secret], account=secret)
        self.raw['sources'][0]['image_path'] = secret
        self.raw['configurations'][0]['token'] = secret
        out = self.clean()
        self.assertNotIn('PRIVATE_NATIVE_CANARY', json.dumps(out))
        self.assertNotIn('SecretPerson', json.dumps(out))
        core.privacy_check(json.dumps(out))
        r['elapsed_seconds'] = secret
        with self.assertRaises(ValueError):
            self.clean()

    def test_portable_package_binds_files_and_rebuilds_identical_report(self):
        with tempfile.TemporaryDirectory() as directory:
            dest = deepseek.write_package(self.clean(), Path(directory) / 'public')
            manifest = json.loads((dest / 'MANIFEST.json').read_text())
            for name, digest in manifest['files'].items():
                content = (dest / name).read_text()
                core.privacy_check(content)
                self.assertEqual(hashlib.sha256(content.encode()).hexdigest(), digest)
            self.assertIn('test_deepseek_publication.py', manifest['files'])
            result = subprocess.run([sys.executable, 'render_publication.py', '--results', 'results.json',
                '--output', 'rebuilt.html'], cwd=dest, capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual((dest / 'rebuilt.html').read_bytes(), (dest / 'report.html').read_bytes())
            result = subprocess.run([sys.executable, '-m', 'unittest', 'test_deepseek_renderer'],
                cwd=dest, capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            with self.assertRaisesRegex(ValueError, 'never overwritten'):
                deepseek.write_package(self.clean(), dest)


if __name__ == '__main__':
    unittest.main()
