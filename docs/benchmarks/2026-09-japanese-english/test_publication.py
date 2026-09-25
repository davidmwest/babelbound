"""Synthetic-only publication privacy and readiness regressions."""
import copy
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest

BASE = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location('prepare_publication', BASE / 'prepare_publication.py')
publication = importlib.util.module_from_spec(spec)
spec.loader.exec_module(publication)


def fixture():
    configs = [{'id': model + '--' + effort, 'model': model, 'effort': effort}
        for model in sorted(publication.MODELS) for effort in ('low', 'medium', 'high', 'xhigh', 'max', 'ultra')
        if not (model == 'gpt-6-luna' and effort == 'ultra')]
    categories = sorted(publication.CATEGORIES)
    sources = [{'id': f'V99-S{i + 1:03}', 'category': categories[i], 'is_prose': i < 9, 'sha256': f'{i:064x}'} for i in range(12)]
    dims = {key: 9.0 for key in publication.SCORES}
    rates = {'input': 1, 'cached_input': .1, 'cache_write': 1.25, 'output': 2}
    pricing = {'date': '2026-09-24', 'source_url': 'https://developers.openai.com/api/docs/pricing',
        'method': 'SYNTHETIC PUBLICATION TEST ONLY.', 'limitations': 'Synthetic values are not benchmark results.',
        'currency': 'USD', 'tier': 'Synthetic', 'rates': {c['model']: rates for c in configs}}
    methods = {'sample': 'SYNTHETIC PUBLICATION TEST ONLY.', 'conditions': 'No service was called.', 'weights': {'accuracy': .5, 'completeness': .25, 'names_numbers': .15, 'fluency': .1}}
    runs = []
    for c in configs:
        for s in sources:
            runs.append({'configuration_id': c['id'], 'source_id': s['id'], 'status': 'completed',
                'scores': dict(dims), 'elapsed_seconds': 1,
                'usage': {'input_tokens': 10, 'output_tokens': 5, 'cached_input_tokens': 0, 'cache_write_input_tokens': 0, 'reasoning_output_tokens': 2},
                'cost': {'status': 'estimated', 'usd': 0.00002, 'no_cache_usd': 0.00002, 'rates_per_million': dict(rates)},
                'reviews': [{'judge': judge, **dims, 'usable': True, 'coverage_percent': 100, 'confidence': 'high', 'review_version': 2, 'issues': []} for judge in sorted(publication.JUDGES)],
                'review_statuses': [{'judge': judge, 'status': 'completed'} for judge in sorted(publication.JUDGES)],
                'needs_adjudication': False, 'context_policy_review_required': [], 'delegation_observed': False})
    summary = [{'configuration_id': c['id'], 'n': 12, 'total': 12, 'completed': 12, 'mean': 9.0, 'cost_n': 12, 'cost_mean_usd': .00002, 'cost_incomplete_count': 0} for c in configs]
    raw = {'status': 'complete', 'review_version': 2, 'generated_at': '2026-09-24T12:00:00Z',
        'methodology': methods, 'pricing': pricing, 'configurations': configs, 'sources': sources,
        'runs': runs, 'summary': summary, 'value_comparison': {'n': 12, 'total': 12, 'provisional': False,
            'common_source_ids': [s['id'] for s in sources], 'rows': [{'configuration_id': c['id'], 'n': 12,
            'mean': 9, 'cost_mean_usd': .00002, 'cost_mean_no_cache_usd': .00002, 'unusable': 0,
            'cost_status': 'estimated', 'cost_eligible': True, 'eligible': True, 'frontier': True} for c in configs]}}
    curation = {'review_version': 2, 'methodology_input_sha256': publication.canonical_hash(methods),
        'pricing_input_sha256': publication.canonical_hash(pricing), 'methodology': methods, 'pricing': pricing}
    audit = {'ok': True, 'complete': True, 'expected_runs': 276, 'pending_count': 0,
        'status_counts': {'completed': 276}, 'errors': [], 'incomplete_runs': [],
        'results_numeric_sha256': publication.integrity_binding(raw),
        'source_hash_checks': [{'id': s['id'], 'sha256': s['sha256'], 'original_sha256': s['sha256'],
            'frozen_sha256': s['sha256'], 'original_unchanged': True, 'frozen_unchanged': True} for s in sources]}
    return raw, curation, audit


class PublicationTests(unittest.TestCase):
    def setUp(self):
        self.raw, self.curation, self.audit = fixture()

    def clean(self, refresh_binding=True):
        audit = copy.deepcopy(self.audit)
        if refresh_binding:
            # Simulate a fresh integrity check after a synthetic fixture edit.
            # Gate regressions must fail for their own reason, not a stale hash.
            audit['results_numeric_sha256'] = publication.integrity_binding(self.raw)
        return publication.sanitize(self.raw, self.curation, audit)

    def test_complete_matrix_and_dimensional_evidence_preserved(self):
        out = self.clean()
        self.assertTrue(out['publication']['ready'])
        self.assertEqual(len(out['configurations']), 23)
        self.assertEqual(len(out['runs']), 276)
        self.assertEqual(out['sources'], self.raw['sources'])
        self.assertEqual(out['runs'][0]['scores'], self.raw['runs'][0]['scores'])
        self.assertEqual(out['runs'][0]['reviews'][0]['coverage_percent'], 100)

    def test_nested_private_payloads_are_never_copied(self):
        secret = 'PRIVATE_CANARY ' + ('/' + 'Users/' + 'SecretPerson/book.txt') + ' source' + '@' + 'example.invalid ' + '\u672c\u6587'
        r = self.raw['runs'][0]
        r.update(translation=secret, translation_text=secret, translation_path=secret, metadata_path=secret, error=secret,
            unique_tool_calls=[{'command': secret}], allowed_source_inspection=[secret], unknown_payload={'text': secret})
        r['reviews'][0].update(strength=secret, source_uncertainties=secret, review_path=secret,
            issues=[{'severity': 'critical', 'source_japanese': secret, 'translation_excerpt': secret, 'explanation': secret}])
        r['cost']['notes'] = [secret]
        r['review_statuses'][0].update(error=secret, metadata_path=secret)
        self.raw['sources'][0].update(image_path=secret, source_path=secret, description=secret)
        self.raw['account'] = {'token': secret}
        out = self.clean()
        self.assertNotIn('PRIVATE_CANARY', json.dumps(out))
        self.assertNotIn('SecretPerson', json.dumps(out))
        self.assertEqual(out['runs'][0]['reviews'][0]['severity_counts']['critical'], 1)

    def test_partial_matrix_refuses_final_without_writes(self):
        self.raw['status'] = 'partial'
        self.raw['runs'][0].update(status='pending', scores=None, reviews=[])
        out = self.clean()
        self.assertFalse(out['publication']['ready'])
        with tempfile.TemporaryDirectory() as root:
            path = Path(root) / 'must-not-exist'
            with self.assertRaisesRegex(ValueError, 'Final package refused'):
                publication.write_package(out, path)
            self.assertFalse(path.exists())

    def test_integrity_audit_must_be_complete_and_pass(self):
        for key, value in [('complete', False), ('ok', False), ('pending_count', 1), ('errors', ['synthetic error'])]:
            with self.subTest(key=key):
                audit = copy.deepcopy(self.audit)
                audit[key] = value
                self.assertFalse(publication.sanitize(self.raw, self.curation, audit)['publication']['ready'])

    def test_unresolved_adjudication_or_context_blocks_final(self):
        r = self.raw['runs'][0]
        r['needs_adjudication'] = True
        self.assertFalse(self.clean()['publication']['ready'])
        r['adjudication_resolved'] = True
        self.assertFalse(self.clean()['publication']['ready'])
        r['adjudication'] = {'verdict': 'supported', 'score_override_recommended': False}
        self.assertTrue(self.clean()['publication']['ready'])
        r['context_policy_review_required'] = [{'command': 'PRIVATE_CANARY'}]
        out = self.clean()
        self.assertFalse(out['publication']['ready'])
        self.assertNotIn('PRIVATE_CANARY', json.dumps(out))

    def test_context_audits_must_be_explicitly_complete(self):
        run = self.raw['runs'][0]
        for flag in (None, [{'category': 'synthetic_unresolved'}], True):
            with self.subTest(flag=flag):
                run['context_policy_review_required'] = flag
                out = self.clean()
                self.assertFalse(out['publication']['ready'])
                self.assertTrue(any('Every context audit' in reason for reason in out['publication']['gate_reasons']))
        run.pop('context_policy_review_required')
        self.assertFalse(self.clean()['publication']['ready'])
        for flag in (False, []):
            run['context_policy_review_required'] = flag
            self.assertTrue(self.clean()['publication']['ready'])

    def test_every_review_must_match_curated_protocol(self):
        review = self.raw['runs'][0]['reviews'][0]
        for version in (None, 1, 1.5, 3):
            with self.subTest(version=version):
                review['review_version'] = version
                out = self.clean()
                self.assertFalse(out['publication']['ready'])
                self.assertIn('Every review must use the curated review protocol version.', out['publication']['gate_reasons'])
        review['review_version'] = 2
        self.assertTrue(self.clean()['publication']['ready'])

    def test_critical_and_disagreement_flags_are_derived(self):
        run = self.raw['runs'][0]
        run.pop('needs_adjudication')
        run['reviews'][0]['issues'] = [{'severity': 'critical'}]
        self.assertIn('Flagged adjudications remain unresolved.', self.clean()['publication']['gate_reasons'])
        run['reviews'][0]['issues'] = []
        run['needs_adjudication'] = False
        run['reviews'][0]['overall'] = 7.5
        self.assertIn('Flagged adjudications remain unresolved.', self.clean()['publication']['gate_reasons'])
        run['reviews'][0]['overall'] = 7.5001
        self.assertTrue(self.clean()['publication']['ready'])

    def test_resolution_needs_supported_evidence_and_no_override(self):
        run = self.raw['runs'][0]
        run['reviews'][0]['issues'] = [{'severity': 'critical'}]
        run['adjudication_resolved'] = True
        for evidence in ({}, {'verdict': 'supported'}, {'verdict': 'unsupported', 'score_override_recommended': False},
                         {'verdict': 'supported', 'score_override_recommended': True}):
            with self.subTest(evidence=evidence):
                run['adjudication'] = evidence
                self.assertFalse(self.clean()['publication']['ready'])
        for verdict in ('supported', 'partly_supported'):
            run['adjudication'] = {'verdict': verdict, 'score_override_recommended': False}
            self.assertTrue(self.clean()['publication']['ready'])
        run['reviews'][0]['issues'] = []
        run['needs_adjudication'] = False
        run['adjudication']['score_override_recommended'] = True
        self.assertIn('Recommended score overrides remain unresolved.', self.clean()['publication']['gate_reasons'])

    def test_integrity_report_must_bind_current_numeric_snapshot(self):
        for edit in ('score', 'cost', 'review', 'flag', 'summary', 'value'):
            with self.subTest(edit=edit):
                raw = copy.deepcopy(self.raw)
                if edit == 'score': raw['runs'][0]['scores']['accuracy'] = 8.9
                elif edit == 'cost': raw['runs'][0]['cost']['usd'] = .002
                elif edit == 'review': raw['runs'][0]['reviews'][0]['overall'] = 8.9
                elif edit == 'flag': raw['runs'][0]['context_policy_review_required'] = False
                elif edit == 'summary': raw['summary'][0]['mean'] = 8.9
                else: raw['value_comparison']['rows'][0]['mean'] = 8.9
                out = publication.sanitize(raw, self.curation, self.audit)
                self.assertFalse(out['publication']['ready'])
                self.assertTrue(any('bound to this numeric snapshot' in reason for reason in out['publication']['gate_reasons']))
        self.audit.pop('results_numeric_sha256')
        self.assertFalse(self.clean(refresh_binding=False)['publication']['ready'])

    def test_integrity_report_must_bind_each_actual_source_hash(self):
        for field in ('sha256', 'original_sha256', 'frozen_sha256'):
            with self.subTest(field=field):
                audit = copy.deepcopy(self.audit)
                audit['source_hash_checks'][0][field] = 'a' * 64
                self.assertFalse(publication.sanitize(self.raw, self.curation, audit)['publication']['ready'])
        self.raw['sources'][0]['sha256'] = 'a' * 64
        self.assertFalse(self.clean()['publication']['ready'])  # Fresh numeric digest cannot bless an old source audit.

    def test_binding_ignores_timestamp_prose_paths_and_record_order(self):
        changed = copy.deepcopy(self.raw)
        changed['generated_at'] = '2030-01-01T00:00:00Z'
        changed['runs'][0].update(translation_text='PRIVATE_CANARY', translation_path='PRIVATE_CANARY', error='PRIVATE_CANARY')
        changed['runs'][0]['reviews'][0]['explanation'] = 'PRIVATE_CANARY'
        changed['runs'][0]['cost']['notes'] = ['PRIVATE_CANARY']
        changed['configurations'].reverse(); changed['sources'].reverse(); changed['runs'].reverse()
        self.assertEqual(publication.integrity_binding(changed), self.audit['results_numeric_sha256'])
        self.assertEqual(len(publication.integrity_binding(changed)), 64)
        self.assertTrue(publication.sanitize(changed, self.curation, self.audit)['publication']['ready'])

    def test_missing_or_duplicate_judge_blocks_final(self):
        self.raw['runs'][0]['reviews'][1]['judge'] = self.raw['runs'][0]['reviews'][0]['judge']
        self.assertFalse(self.clean()['publication']['ready'])

    def test_changed_methods_or_rates_require_new_curation(self):
        for key in ('methodology', 'pricing'):
            with self.subTest(key=key):
                raw = copy.deepcopy(self.raw)
                raw[key]['unreviewed_change'] = 'anything'
                with self.assertRaisesRegex(ValueError, 'changed since curation'):
                    publication.sanitize(raw, self.curation, self.audit)

    def test_invalid_numbers_rejected(self):
        for value in ['PRIVATE_CANARY', float('nan'), float('inf'), True, -1]:
            with self.subTest(value=value):
                raw = copy.deepcopy(self.raw)
                raw['runs'][0]['elapsed_seconds'] = value
                with self.assertRaises(ValueError):
                    publication.sanitize(raw, self.curation, self.audit)

    def test_missing_configuration_or_cell_rejected(self):
        for field in ('configurations', 'runs', 'summary'):
            with self.subTest(field=field):
                raw = copy.deepcopy(self.raw)
                raw[field].pop()
                with self.assertRaises(ValueError):
                    publication.sanitize(raw, self.curation, self.audit)

    def test_unknown_categories_are_not_passed_through(self):
        self.raw['sources'][0]['category'] = 'PRIVATE_CANARY book quotation'
        with self.assertRaises(ValueError):
            self.clean()

    def test_paired_identifiers_and_intervals_are_preserved(self):
        ids = [c['id'] for c in self.raw['configurations'][:2]]
        self.raw['paired_comparisons'] = [{'reference_configuration_id': ids[0], 'other_configuration_id': ids[1],
            'source_ids': [s['id'] for s in self.raw['sources']], 'n': 12, 'mean_difference': -.1, 'ci_low': -.5, 'ci_high': .2,
            'interpretation': 'PRIVATE_CANARY'}]
        pair = self.clean()['paired_comparisons'][0]
        self.assertEqual(pair['other_configuration_id'], ids[1])
        self.assertEqual(pair['mean_difference'], -.1)
        self.assertNotIn('PRIVATE_CANARY', json.dumps(pair))

    def test_cost_null_zero_and_lower_bound_remain_distinct(self):
        for status, amount in [('estimated', 0), ('unavailable', None), ('lower_bound', .01)]:
            with self.subTest(status=status):
                self.raw['runs'][0]['cost'].update(status=status, usd=amount)
                out = self.clean()['runs'][0]['cost']
                self.assertEqual(out['status'], status)
                self.assertEqual(out['usd'], amount)

    def test_preview_stays_draft_even_when_data_is_complete(self):
        out = self.clean()
        with tempfile.TemporaryDirectory() as root:
            path = Path(root) / 'preview'
            publication.write_package(out, path, preview=True)
            saved = json.loads((path / 'results.json').read_text())
            self.assertFalse(saved['publication']['ready'])
            self.assertEqual(saved['publication']['status'], 'draft')
            self.assertTrue(out['publication']['ready'])  # Caller data was not mutated.

    def test_staging_bundle_is_atomic_and_never_overwritten(self):
        self.raw['status'] = 'partial'
        out = self.clean()
        with tempfile.TemporaryDirectory() as root:
            path = Path(root) / 'preview with spaces'
            publication.write_package(out, path, preview=True)
            self.assertEqual(json.loads((path / 'results.json').read_text())['publication']['status'], 'draft')
            self.assertIn('Draft', (path / 'report.html').read_text())
            self.assertTrue((path / 'translation-prompt.txt').is_file())
            self.assertTrue((path / 'grading-rubric.md').is_file())
            self.assertTrue((path / 'MANIFEST.json').is_file())
            with self.assertRaisesRegex(ValueError, 'new staging directory'):
                publication.write_package(out, path, preview=True)


if __name__ == '__main__':
    unittest.main()
