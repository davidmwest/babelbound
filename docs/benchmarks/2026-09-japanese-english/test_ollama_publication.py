"""Publication gates for the supported multi-model Ollama extension."""
import copy
import hashlib
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

import prepare_publication as core
import prepare_deepseek_publication as native
import prepare_ollama_publication as expanded
from test_deepseek_publication import fixture as prior_fixture


def fixture():
    previous, old, receipt, old_curation = prior_fixture()
    old_bytes = json.dumps(old).encode()
    receipt.update(results_sha256=native.sha(old_bytes),
        source_audit_checks=copy.deepcopy(old['source_audits']),
        delivery_audit_checks=copy.deepcopy(old['delivery_audits']))
    base = native.sanitize(previous, old_bytes, receipt, old_curation)
    base_bytes = json.dumps(base).encode()
    gemma_tariff = copy.deepcopy(old_curation['pricing'])
    gemma_tariff.update(peak={'input': .14, 'cached_input': .05, 'output': .4},
        off_peak={'input': .14, 'cached_input': .05, 'output': .4},
        schedule='Single all-hours tariff.')
    curation = {'base_results_sha256': native.sha(base_bytes), 'ollama_review_version': 1,
        'pricing_by_model': {expanded.DS: old_curation['pricing'], expanded.GEMMA: gemma_tariff},
        'methodology_additions': {'ollama_expanded': 'Synthetic three-configuration native cohort.',
            'native_controls': 'Medium is unsupported and is not a separate result.'}}
    raw = copy.deepcopy(old)
    raw['configurations'] = [dict(id=cid, model=model, effort=effort, native_think=think,
        provider='ollama-cloud') for cid, (model, effort, think, _) in expanded.CONFIGS.items()]
    raw['runs'] = []
    for config in raw['configurations']:
        for source in raw['sources']:
            r = copy.deepcopy(old['runs'][0])
            model = config['model']
            price = .00054 if model == expanded.DS else .00022
            r.update(configuration_id=config['id'], source_id=source['id'], model=model,
                native_think=config['native_think'],
                returned_model='deepseek-v4.1-flash' if model == expanded.DS else 'gemma4:31b',
                thinking_present=config['native_think'] is not False,
                delivery_outcome={'audited': True, 'classification': 'english_translation',
                    'source_id': source['id'], 'packet_sha256': source['sha256']})
            r['cost'].update(usd=price, no_cache_usd=price)
            raw['runs'].append(r)
    for delivery in raw['delivery_audits']:
        delivery['audited_candidates'] = 3
    receipt.update(planned_cells=36, completed_responses=36, double_reviewed_cells=36,
        interrupted_responses=0, terminal_responses=36, interruption_checks=[])
    return base_bytes, raw, receipt, curation


class ExpandedOllamaPublicationTests(unittest.TestCase):
    def setUp(self):
        self.base_bytes, self.raw, self.audit, self.curation = fixture()

    def clean(self, refresh=True):
        raw_bytes = json.dumps(self.raw).encode()
        if refresh:
            self.audit.update(results_sha256=native.sha(raw_bytes),
                source_audit_checks=copy.deepcopy(self.raw['source_audits']),
                delivery_audit_checks=copy.deepcopy(self.raw['delivery_audits']))
        return expanded.sanitize(self.base_bytes, raw_bytes, self.audit, self.curation)

    def test_prior_372_records_and_value_recommendations_are_frozen(self):
        base = json.loads(self.base_bytes)
        result = self.clean()
        self.assertTrue(result['publication']['ready'], result['publication']['gate_reasons'])
        self.assertEqual((len(result['configurations']), len(result['runs'])), (34, 408))
        self.assertEqual(sum(len(r['reviews']) for r in result['runs']), 816)
        self.assertEqual(result['schema_version'], 4)
        for key in ('runs', 'configurations', 'summary'):
            self.assertEqual(result[key][:len(base[key])], base[key])
        for key in ('sources', 'value_comparison', 'paired_comparisons', 'deepseek_pricing'):
            self.assertEqual(result[key], base[key])
        for k, v in base['publication']['input_bindings'].items():
            self.assertEqual(result['publication']['input_bindings'][k], v)

    def test_model_specific_prices_and_boolean_vs_named_controls(self):
        result = self.clean()
        rows = {r['configuration_id']: r for r in result['summary'][-3:]}
        for config in result['configurations'][-3:]:
            expected = .00054 if config['model'] == expanded.DS else .00022
            self.assertAlmostEqual(rows[config['id']]['cost_mean_usd'], expected)
            self.assertEqual(rows[config['id']]['cohort'], expanded.COHORT)
        new_runs = result['runs'][-36:]
        self.assertEqual({r['requested_model'] for r in new_runs}, {expanded.DS, expanded.GEMMA})
        self.assertTrue(all(r['cohort'] == expanded.COHORT for r in new_runs))

    def test_unsupported_medium_cannot_be_published_as_high_or_vice_versa(self):
        for scope in ('runs', 'configurations'):
            with self.subTest(scope=scope):
                old = copy.deepcopy(self.raw)
                self.raw[scope][0]['native_think'] = 'medium'
                with self.assertRaises(ValueError):
                    self.clean()
                self.raw = old
        self.raw['configurations'][0]['id'] = 'deepseek-v4.1-flash-cloud--medium'
        with self.assertRaises(ValueError):
            self.clean()

    def test_gemma_boolean_setting_cannot_be_coerced_from_number(self):
        for value in (0, 1, 'true', 'false', 'medium'):
            with self.subTest(value=value):
                old = copy.deepcopy(self.raw)
                self.raw['runs'][12]['native_think'] = value
                with self.assertRaises(ValueError):
                    self.clean()
                self.raw = old

    def test_model_identity_and_tariff_keys_are_exact(self):
        self.raw['runs'][12]['returned_model'] = 'gemma4:26b'
        with self.assertRaises(ValueError):
            self.clean()
        self.raw['runs'][12]['returned_model'] = 'gemma4:31b'
        self.curation['pricing_by_model']['gemma4:cloud'] = self.curation['pricing_by_model'].pop(expanded.GEMMA)
        with self.assertRaisesRegex(ValueError, 'exact requested model'):
            self.clean()

    def test_source_and_base_binding_require_exact_bytes(self):
        with self.assertRaisesRegex(ValueError, 'publication changed'):
            expanded.sanitize(self.base_bytes + b' ', json.dumps(self.raw).encode(), self.audit, self.curation)
        self.raw['sources'][0]['sha256'] = 'f' * 64
        with self.assertRaisesRegex(ValueError, 'identical 12'):
            self.clean()

    def test_matrix_and_review_gates_remain_complete(self):
        old = copy.deepcopy(self.raw)
        self.raw['runs'][-1] = copy.deepcopy(self.raw['runs'][0])
        with self.assertRaisesRegex(ValueError, '36 distinct'):
            self.clean()
        self.raw = old
        self.raw['runs'][0]['reviews'][1]['judge'] = self.raw['runs'][0]['reviews'][0]['judge']
        self.assertFalse(self.clean()['publication']['ready'])

    def test_three_candidate_delivery_and_integrity_binding(self):
        self.clean()
        self.raw['runs'][0]['elapsed_seconds'] = 123
        self.assertFalse(self.clean(refresh=False)['publication']['ready'])
        self.raw['delivery_audits'][0]['audited_candidates'] = 2
        self.assertFalse(self.clean()['publication']['ready'])
        self.raw['delivery_audits'][0]['audited_candidates'] = 3
        self.assertTrue(self.clean()['publication']['ready'])
        self.audit['double_reviewed_cells'] = 24
        self.assertFalse(self.clean()['publication']['ready'])

    def test_unknown_model_cost_does_not_contaminate_other_models(self):
        run = self.raw['runs'][12]
        run['usage']['output_tokens'] = None
        run['cost'] = {'status': 'unavailable'}
        result = self.clean()
        rows = {r['configuration_id']: r for r in result['summary'][-3:]}
        gemma = rows[run['configuration_id']]
        self.assertEqual(gemma['cost_n'], 11)
        self.assertIsNone(gemma['cost_mean_usd'])
        self.assertAlmostEqual(gemma['cost_total_usd'], 11 * .00022)
        self.assertAlmostEqual(rows['deepseek-v4.1-flash-cloud--high']['cost_mean_usd'], .00054)

    def test_private_native_payloads_and_audit_prose_are_omitted(self):
        secret = 'PRIVATE_EXPANDED_CANARY'
        self.raw['runs'][12].update(translation=secret, thinking=secret, endpoint=secret)
        self.raw['runs'][12]['reviews'][0]['notes'] = secret
        self.raw['source_audits'][0]['reason'] = secret
        self.raw['configurations'][1]['request'] = secret
        result = self.clean()
        self.assertNotIn(secret, json.dumps(result))
        core.privacy_check(json.dumps(result))

    def interrupt_one(self):
        run = self.raw['runs'][-1]
        run.update(status='interrupted', usage=None, cost=None, cost_usd=None,
            native_timing_ns=None, done_reason=None, elapsed_seconds=1801.25)
        run['administrative_interruption'] = dict(schema_version=1,
            run_id=run['configuration_id'] + '/' + run['source_id'],
            request_sha256='a' * 64, stream_sha256='b' * 64,
            protocol_amendment_sha256='c' * 64, translation_sha256='d' * 64,
            started_at=run['started_at'], finished_at='2026-09-26T20:00:00+00:00',
            elapsed_seconds=1801.25, deadline_seconds=1800, native_receipt_absent=True,
            reason='PRIVATE_INTERRUPTION_CANARY', termination_method='local_process_stop')
        run['delivery_outcome']['classification'] = 'other_failure'
        record = expanded.interruption_record(run)
        self.audit.update(completed_responses=35, interrupted_responses=1,
            interruption_checks=[dict(id=run['administrative_interruption']['run_id'],
                status='interrupted', administrative_interruption_verified=True,
                **{k: record[k] for k in ('request_sha256', 'stream_sha256', 'translation_sha256',
                    'protocol_amendment_sha256', 'elapsed_seconds', 'deadline_seconds', 'native_receipt_absent')})])
        return run

    def test_interrupted_attempt_is_scored_but_timing_censored_and_cost_unknown(self):
        run = self.interrupt_one()
        result = self.clean()
        self.assertTrue(result['publication']['ready'], result['publication']['gate_reasons'])
        public = result['runs'][-1]
        self.assertEqual(public['status'], 'interrupted')
        self.assertIsNone(public['cost']['usd'])
        self.assertIsNone(public['usage']['output_tokens'])
        self.assertEqual(public['administrative_interruption']['elapsed_seconds'], 1801.25)
        row = result['summary'][-1]
        self.assertEqual((row['completed'], row['interrupted'], row['cost_n']), (11, 1, 11))
        self.assertEqual(row['interrupted_elapsed_seconds_max'], 1801.25)
        self.assertEqual(row['timing_n'], 11)
        self.assertLess(row['max_seconds'], 1800)
        self.assertIsNone(row['cost_mean_usd'])
        self.assertNotIn('PRIVATE_INTERRUPTION_CANARY', json.dumps(result))
        self.audit['interruption_checks'][0]['stream_sha256'] = 'e' * 64
        self.assertFalse(self.clean()['publication']['ready'])

    def test_interrupted_attempt_cannot_invent_native_usage_or_unbound_deadline(self):
        run = self.interrupt_one()
        run['usage'] = {'input_tokens': 100, 'output_tokens': 200}
        with self.assertRaisesRegex(ValueError, 'cannot claim final usage'):
            self.clean()
        run['usage'] = None
        run['administrative_interruption']['elapsed_seconds'] = 1800
        with self.assertRaisesRegex(ValueError, 'timing must bind'):
            self.clean()
        run['administrative_interruption']['elapsed_seconds'] = 1801.25
        run['administrative_interruption']['native_receipt_absent'] = False
        with self.assertRaisesRegex(ValueError, 'absence of a native final receipt'):
            self.clean()

    def test_portable_package_rebuild_and_methodology(self):
        with tempfile.TemporaryDirectory() as directory:
            dest = expanded.write_package(self.clean(), Path(directory) / 'public')
            manifest = json.loads((dest / 'MANIFEST.json').read_text())
            for name, digest in manifest['files'].items():
                self.assertEqual(hashlib.sha256((dest / name).read_bytes()).hexdigest(), digest)
            self.assertIn('prepare_ollama_publication.py', manifest['files'])
            self.assertIn('test_ollama_publication.py', manifest['files'])
            methods = (dest / 'METHODS.md').read_text()
            self.assertIn('Medium is unsupported', methods)
            self.assertIn('gemma4:31b-cloud tariff', methods)
            process = subprocess.run([sys.executable, 'render_publication.py', '--results', 'results.json',
                '--output', 'rebuilt.html'], cwd=dest, capture_output=True, text=True)
            self.assertEqual(process.returncode, 0, process.stderr)
            self.assertEqual((dest / 'report.html').read_bytes(), (dest / 'rebuilt.html').read_bytes())


if __name__ == '__main__':
    unittest.main()
