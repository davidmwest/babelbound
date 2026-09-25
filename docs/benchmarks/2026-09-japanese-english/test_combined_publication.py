"""Synthetic expanded-study gates; no source pages or service calls."""
import copy
import hashlib
import json
from pathlib import Path
import tempfile
import unittest
import prepare_publication as core
import prepare_combined_publication as combined
from test_publication import fixture as openai_fixture


def fixture():
    original, oc, oa = openai_fixture()
    original = json.loads(json.dumps(original).replace('V99-S012', 'V10-S090'))
    oa = json.loads(json.dumps(oa).replace('V99-S012', 'V10-S090'))
    amendment = {'schema_version': 1, 'old_cli_version': combined.OLD_CLI, 'new_cli_version': combined.NEW_CLI,
        'affected_attempts': [{'configuration_id': c, 'source_id': s, 'attempt': a} for c, s, a in sorted(combined.RESUMED)]}
    for r in original['runs']:
        resumed = (r['configuration_id'], r['source_id'], 2) in combined.RESUMED
        r.update(cli_version=combined.NEW_CLI if resumed else combined.OLD_CLI,
            attempt_count=2 if resumed else 1, resumed_after_user_interruption=resumed)
        if resumed:
            r['cost']['status'] = 'lower_bound'
    for r in original['value_comparison']['rows']:
        if r['configuration_id'] in {c for c, _, _ in combined.RESUMED}:
            r.update(cost_status='lower_bound', cost_eligible=False, eligible=False, frontier=False)
    oa['results_numeric_sha256'] = core.integrity_binding(original)
    oa['cli_resume_amendment'] = amendment
    configs = [{'id': m + '--' + e, 'model': m, 'effort': e, 'extended_thinking': e == 'extended',
        'provider': 'gemini-web'} for m in sorted(combined.GEMINI_MODELS) for e in sorted(combined.GEMINI_EFFORTS)]
    sources = [{'id': s['id'], 'category': s['category'], 'prose': s['is_prose'], 'sha256': s['sha256']} for s in original['sources']]
    runs = []
    for c in configs:
        for s in sources:
            r = copy.deepcopy(original['runs'][0])
            r.update(id=c['id']+'/'+s['id'], configuration_id=c['id'], source_id=s['id'], usage=None, cost_usd=None,
                provenance_problems=[], quota_warning=None, adjudication=None, adjudication_resolved=False)
            r['delivery_outcome'] = {'audited': True, 'classification': 'english_translation', 'source_id': s['id'], 'packet_sha256': s['sha256']}
            r.pop('cost')
            for v in r['reviews']:
                v['review_version'] = 1
            runs.append(r)
    sa = [{'source_id': s['id'], 'status': 'resolved', 'flagged_candidates': 0} for s in sources]
    da = [{'source_id': s['id'], 'status': 'resolved', 'audited_candidates': 6, 'packet_sha256': s['sha256']} for s in sources]
    gemini = {'status': 'complete', 'generated_at': original['generated_at'], 'methodology': {'separate_cohort': True},
        'pricing_policy': 'Synthetic unknown costs.', 'sources': sources, 'configurations': configs, 'runs': runs, 'source_audits': sa, 'delivery_audits': da}
    curation = {'gemini_review_version': 1, 'gemini_methodology_sha256': core.canonical_hash(gemini['methodology']),
        'gemini_pricing_policy_sha256': core.canonical_hash(gemini['pricing_policy']),
        'cli_amendment_sha256': core.canonical_hash(amendment),
        'methodology': {**oc['methodology'], 'planned_captures': 12, 'planned_configurations': 29,
            'planned_translations': 348, 'cohorts': 'Synthetic separate cohorts. Gemini cost unknown.'}}
    ga = {'passed': True, 'complete': True, 'planned_cells': 72, 'completed_responses': 72, 'double_reviewed_cells': 72,
        'original_openai_study_modified': False, 'source_audit_checks': copy.deepcopy(sa), 'delivery_audit_checks': copy.deepcopy(da),
        'source_hash_checks': [{'source_id': s['id'], 'expected_sha256': s['sha256'], 'actual_sha256': s['sha256'], 'matched': True} for s in sources]}
    bs = json.dumps(gemini).encode()
    ga['results_sha256'] = hashlib.sha256(bs).hexdigest()
    return original, gemini, dict(openai_curation=oc, curation=curation, openai_audit=oa,
        gemini_audit=ga, gemini_bytes=bs, cli_amendment=amendment)


class CombinedTests(unittest.TestCase):
    def setUp(self):
        self.op, self.ge, self.kw = fixture()

    def clean(self, refresh=True):
        if refresh:
            self.kw['gemini_bytes'] = json.dumps(self.ge).encode()
            self.kw['gemini_audit']['results_sha256'] = hashlib.sha256(self.kw['gemini_bytes']).hexdigest()
            self.kw['openai_audit']['results_numeric_sha256'] = core.integrity_binding(self.op)
        return combined.sanitize(self.op, self.ge, **self.kw)

    def acknowledge_context_limitation(self):
        selected = self.op['runs'][:13]
        for r in selected:
            r['context_policy_review_required'] = [{'category': combined.CONTEXT_LIMITATION,
                'assessment': 'PRIVATE_CHILD_CONTEXT_CANARY: unavailable child history.'}]
            r['cost']['status'] = 'lower_bound'
        affected = {r['configuration_id'] for r in selected}
        for r in self.op['value_comparison']['rows']:
            if r['configuration_id'] in affected:
                r.update(cost_status='lower_bound', cost_eligible=False, eligible=False, frontier=False)
        self.op['value_comparison']['recommendations'] = [r for r in self.op['value_comparison'].get('recommendations', [])
            if r.get('configuration_id') not in affected]
        self.kw['openai_audit']['results_numeric_sha256'] = core.integrity_binding(self.op)
        self.kw['curation']['context_limitation_acknowledgment'] = {
            'category': combined.CONTEXT_LIMITATION,
            'run_ids': [r['configuration_id']+'/'+r['source_id'] for r in selected],
            'openai_numeric_sha256': core.integrity_binding(self.op),
            'findings_sha256': combined.context_limitation_binding(self.op)}

    def test_exact_context_limitation_acknowledged_without_clearing_flags(self):
        self.acknowledge_context_limitation()
        original = copy.deepcopy(self.op)
        d = self.clean()
        self.assertTrue(d['publication']['ready'], d['publication']['gate_reasons'])
        flagged = [r for r in d['runs'] if r.get('context_limitation_acknowledged')]
        self.assertEqual(len(flagged), 13)
        self.assertTrue(all(r['context_policy_review_required'] is True for r in flagged))
        self.assertFalse(d['context_limitation_acknowledgment']['complete_child_context'])
        self.assertFalse(d['context_limitation_acknowledgment']['complete_child_usage'])
        self.assertNotIn('PRIVATE_CHILD_CONTEXT_CANARY', json.dumps(d))
        self.assertEqual(self.op, original)
        # The original generic gate remains strict; only this curated expanded
        # publication acknowledges the bound limitation.
        self.assertFalse(core.sanitize(self.op, self.kw['openai_curation'], self.kw['openai_audit'])['publication']['ready'])

    def test_context_acknowledgment_rejects_missing_new_or_changed_findings(self):
        self.acknowledge_context_limitation()
        original = copy.deepcopy(self.op)
        for mutation in ('missing', 'new_run', 'new_category', 'changed_payload', 'unknown_flag', 'missing_flag'):
            with self.subTest(mutation=mutation):
                self.op = copy.deepcopy(original)
                if mutation == 'missing': self.op['runs'][0]['context_policy_review_required'] = []
                if mutation == 'new_run': self.op['runs'][13]['context_policy_review_required'] = copy.deepcopy(self.op['runs'][0]['context_policy_review_required'])
                if mutation == 'new_category': self.op['runs'][0]['context_policy_review_required'][0]['category'] = 'unknown_tool_call'
                if mutation == 'changed_payload': self.op['runs'][0]['context_policy_review_required'][0]['assessment'] = 'Different unreviewed finding'
                if mutation == 'unknown_flag': self.op['runs'][13]['context_policy_review_required'] = True
                if mutation == 'missing_flag': self.op['runs'][13].pop('context_policy_review_required')
                self.assertFalse(self.clean()['publication']['ready'])

    def test_context_acknowledgment_pinned_to_exact_snapshot_and_receipt(self):
        self.acknowledge_context_limitation()
        self.op['runs'][20]['scores']['accuracy'] = 8.5
        self.assertFalse(self.clean()['publication']['ready'])
        self.op, self.ge, self.kw = fixture()
        self.acknowledge_context_limitation()
        self.kw['openai_audit']['results_numeric_sha256'] = 'f'*64
        self.assertFalse(self.clean(False)['publication']['ready'])

    def test_context_acknowledgment_cannot_make_incomplete_costs_eligible(self):
        self.acknowledge_context_limitation()
        original = copy.deepcopy(self.op)
        for mutation in ('estimated_run', 'eligible_value', 'recommended_value'):
            with self.subTest(mutation=mutation):
                self.op = copy.deepcopy(original)
                affected = self.op['runs'][0]['configuration_id']
                if mutation == 'estimated_run': self.op['runs'][0]['cost']['status'] = 'estimated'
                if mutation == 'eligible_value':
                    next(r for r in self.op['value_comparison']['rows'] if r['configuration_id'] == affected)['eligible'] = True
                if mutation == 'recommended_value':
                    self.op['value_comparison']['recommendations'].append({'configuration_id': affected,
                        'minimum_score': 8, 'mean': 9, 'cost_mean_usd': 0.01})
                # Even a new numeric pin cannot bypass the required cost boundary.
                self.kw['curation']['context_limitation_acknowledgment']['openai_numeric_sha256'] = core.integrity_binding(self.op)
                self.assertFalse(self.clean()['publication']['ready'])

    def test_exact_final_matrix(self):
        d = self.clean()
        self.assertTrue(d['publication']['ready'], d['publication']['gate_reasons'])
        self.assertEqual(len(d['runs']), 348)
        self.assertEqual(len(d['configurations']), 29)
        self.assertEqual(sum(len(r['reviews']) for r in d['runs']), 696)
        self.assertEqual(d['review_versions'], {'codex-cli': 2, 'gemini-web': 1})

    def test_no_gemini_value_or_imputed_cost(self):
        d = self.clean()
        for r in d['value_comparison']['rows']:
            if r['configuration_id'].startswith('gemini-'):
                self.assertIsNone(r['cost_mean_usd'])
                self.assertFalse(r['cost_eligible'])
                self.assertFalse(r['eligible'])
                self.assertFalse(r['frontier'])
        for r in d['runs'][276:]:
            self.assertTrue(all(v is None for v in r['usage'].values()))
            self.assertIsNone(r['cost']['usd'])
        for field, value in [('cost_usd', 0), ('cost_usd', 1), ('usage', {}), ('cost', {'usd': 0})]:
            with self.subTest(field=field, value=value):
                r = self.ge['runs'][0];old = copy.deepcopy(r)
                r[field] = value
                with self.assertRaisesRegex(ValueError, 'must remain unknown'):
                    self.clean()
                r.clear();r.update(old)

    def test_single_pending_cell_blocks_final_without_files(self):
        self.ge['runs'][0].update(status='pending', reviews=[], scores=None)
        d = self.clean()
        self.assertFalse(d['publication']['ready'])
        with tempfile.TemporaryDirectory() as root:
            p=Path(root)/'no-output'
            with self.assertRaisesRegex(ValueError, 'Final package refused'):
                combined.write_package(d,p)
            self.assertFalse(p.exists())

    def test_missing_or_duplicate_matrix_cell_rejected(self):
        self.ge['runs'][-1] = copy.deepcopy(self.ge['runs'][0])
        with self.assertRaisesRegex(ValueError, 'exactly once'):
            self.clean()
        self.ge['runs'].pop()
        with self.assertRaises(ValueError):
            self.clean()

    def test_sources_must_match_original_frozen_corpus(self):
        self.ge['sources'][0]['sha256'] = 'f'*64
        with self.assertRaisesRegex(ValueError, 'same twelve'):
            self.clean()

    def test_stale_exact_gemini_bytes_block(self):
        self.kw['gemini_bytes'] += b'\n'
        self.assertFalse(self.clean(False)['publication']['ready'])
        self.kw['gemini_bytes'] = b'{}'
        with self.assertRaisesRegex(ValueError, 'snapshot bytes'):
            self.clean(False)

    def test_stale_openai_numeric_snapshot_blocks(self):
        self.op['runs'][0]['scores']['accuracy'] = 8.5
        self.assertFalse(self.clean(False)['publication']['ready'])

    def test_each_review_version_and_two_distinct_judges(self):
        r=self.ge['runs'][0]
        for mutation in ('wrong_version','duplicate_judge','missing_status','duplicate_status','missing_score','missing_usability'):
            with self.subTest(mutation=mutation):
                old=copy.deepcopy(r)
                if mutation=='wrong_version': r['reviews'][0]['review_version']=2
                elif mutation=='duplicate_judge': r['reviews'][1]['judge']=r['reviews'][0]['judge']
                elif mutation=='missing_status': r['review_statuses'].pop()
                elif mutation=='duplicate_status': r['review_statuses'][1]['judge']=r['review_statuses'][0]['judge']
                elif mutation=='missing_score': r['reviews'][0]['overall']=None
                else: r['reviews'][0]['usable']=None
                self.assertFalse(self.clean()['publication']['ready'])
                r.clear();r.update(old)

    def test_openai_review_status_must_be_present(self):
        self.op['runs'][0]['review_statuses']=[]
        self.assertFalse(self.clean()['publication']['ready'])

    def test_critical_flag_derived_and_supported_audit_required(self):
        r=self.ge['runs'][0]
        r['reviews'][0]['issues']=[{'severity':'critical'}]
        self.assertFalse(self.clean()['publication']['ready'])
        r['adjudication_resolved']=True
        self.assertFalse(self.clean()['publication']['ready'])
        r['adjudication']={'verdict':'supported','score_override_recommended':False}
        self.assertTrue(self.clean()['publication']['ready'])
        r['adjudication']['score_override_recommended']=True
        self.assertFalse(self.clean()['publication']['ready'])

    def test_both_source_audit_sets_must_be_resolved(self):
        for key in ('source_audits','source_audit_checks'):
            rows=self.ge[key] if key=='source_audits' else self.kw['gemini_audit'][key]
            old=copy.deepcopy(rows)
            rows[0]['status']='awaiting_source_audit'
            self.assertFalse(self.clean()['publication']['ready'])
            rows[:]=old
            rows.pop()
            self.assertFalse(self.clean()['publication']['ready'])
            rows[:]=old

    def test_gemini_integrity_flags_and_sources(self):
        ga=self.kw['gemini_audit']
        for key,value in [('passed',False),('complete',False),('completed_responses',71),('double_reviewed_cells',71),('original_openai_study_modified',True)]:
            with self.subTest(key=key):
                old=ga[key];ga[key]=value
                self.assertFalse(self.clean()['publication']['ready'])
                ga[key]=old
        ga['source_hash_checks'][0]['actual_sha256']='f'*64
        self.assertFalse(self.clean()['publication']['ready'])

    def test_provenance_warning_blocks(self):
        r=self.ge['runs'][0]
        r['provenance_problems']=['PRIVATE_CANARY']
        d=self.clean();self.assertFalse(d['publication']['ready'])
        self.assertNotIn('PRIVATE_CANARY',json.dumps(d))
        r['provenance_problems']=[];r['quota_warning']='PRIVATE_CANARY'
        self.assertFalse(self.clean()['publication']['ready'])

    def test_cli_amendment_bound_to_exact_two_replacements(self):
        r=next(r for r in self.op['runs'] if r['resumed_after_user_interruption'])
        old=copy.deepcopy(r)
        for key,value in [('cli_version',combined.OLD_CLI),('attempt_count',3),('resumed_after_user_interruption',False)]:
            with self.subTest(key=key):
                r[key]=value
                self.assertFalse(self.clean()['publication']['ready'])
                r.clear();r.update(copy.deepcopy(old))
        r['cost']['status']='estimated'
        self.assertFalse(self.clean()['publication']['ready'])

    def test_unlisted_cli_change_or_unpinned_amendment_blocks(self):
        self.op['runs'][0]['cli_version']=combined.NEW_CLI
        self.assertFalse(self.clean()['publication']['ready'])
        self.op['runs'][0]['cli_version']=combined.OLD_CLI
        self.kw['cli_amendment']['extra']='unreviewed'
        self.assertFalse(self.clean()['publication']['ready'])

    def test_lower_bound_resumed_costs_cannot_be_value_eligible(self):
        r=next(r for r in self.op['value_comparison']['rows'] if r['cost_status']=='lower_bound')
        r.update(cost_eligible=True, eligible=True, frontier=True)
        self.assertFalse(self.clean()['publication']['ready'])

    def test_methodology_requires_reviewed_pin(self):
        self.ge['methodology']['controls']=1
        with self.assertRaisesRegex(ValueError,'methodology changed'):
            self.clean()

    def test_nested_private_payloads_excluded(self):
        secret='PRIVATE_CANARY ' + '/'+'Users/HiddenPerson/file.txt ' + '\u672c\u6587' + ' private'+'@'+'example.invalid'
        self.ge['account']=secret
        self.ge['sources'][0]['image_path']=secret
        r=self.ge['runs'][0]
        r.update(translation=secret,translation_path=secret,attempts=[{'command':secret}],metadata_path=secret,arbitrary=secret)
        r['reviews'][0].update(issues=[{'severity':'minor','translation_excerpt':secret,'source_japanese':secret,'explanation':secret}],strength=secret)
        r['review_statuses'][0]['error']=secret
        d=self.clean()
        self.assertTrue(d['publication']['ready'])
        self.assertNotIn('PRIVATE_CANARY',json.dumps(d))
        self.assertNotIn('HiddenPerson',json.dumps(d))
        self.assertEqual(d['runs'][276]['reviews'][0]['severity_counts']['minor'],1)

    def test_delivery_audit_is_bound_and_primary_score_retains_failures(self):
        r=self.ge['runs'][0]
        r['delivery_outcome']['classification']='service_error'
        r['scores']={key:1 for key in core.SCORES}
        d=self.clean()
        self.assertTrue(d['publication']['ready'])
        summary=next(s for s in d['summary'] if s['configuration_id']==r['configuration_id'])
        self.assertEqual(summary['n'],12)
        self.assertEqual(summary['english_translation_n'],11)
        self.assertEqual(summary['english_translation_mean'],9)
        self.assertLess(summary['mean'],9)
        self.assertEqual(summary['delivery_counts']['service_error'],1)
        from render_publication import prepare, readme
        public_row=next(s for s in prepare(d)['rows'] if s['id']==r['configuration_id'])
        self.assertEqual(public_row['english_translation_n'],11)
        self.assertEqual(public_row['delivery_counts']['service_error'],1)
        self.assertIn('Conditional mean',readme(d))
        self.assertIn('not a replacement ranking',readme(d))
        r['delivery_outcome']['audited']=False
        self.assertFalse(self.clean()['publication']['ready'])
        r['delivery_outcome']['audited']=True
        r['delivery_outcome']['packet_sha256']='f'*64
        self.assertFalse(self.clean()['publication']['ready'])

    def test_missing_delivery_audit_receipt_blocks(self):
        self.kw['gemini_audit'].pop('delivery_audit_checks')
        self.assertFalse(self.clean()['publication']['ready'])

    def test_delivery_packet_receipt_must_match_snapshot(self):
        self.kw['gemini_audit']['delivery_audit_checks'][0]['packet_sha256']='f'*64
        self.assertFalse(self.clean()['publication']['ready'])
        # Even mutually matching packet fields must be valid lowercase SHA-256.
        for invalid_hash in ('g'*64, 'F'*64, 'a'*63, ''):
            with self.subTest(invalid_hash=invalid_hash):
                self.op, self.ge, self.kw = fixture()
                sid=self.ge['sources'][0]['id']
                self.ge['delivery_audits'][0]['packet_sha256']=invalid_hash
                self.kw['gemini_audit']['delivery_audit_checks'][0]['packet_sha256']=invalid_hash
                for r in self.ge['runs']:
                    if r['source_id']==sid:r['delivery_outcome']['packet_sha256']=invalid_hash
                self.assertFalse(self.clean()['publication']['ready'])

    def test_package_is_portable_text_only_and_manifest_bound(self):
        with tempfile.TemporaryDirectory() as root:
            dest=combined.write_package(self.clean(),Path(root)/'final')
            manifest=json.loads((dest/'MANIFEST.json').read_text())
            self.assertEqual(manifest['publication_status'],'final')
            self.assertIn('prepare_combined_publication.py',manifest['files'])
            self.assertIn('test_combined_publication.py',manifest['files'])
            for name,digest in manifest['files'].items():
                content=(dest/name).read_text()
                core.privacy_check(content)
                self.assertEqual(hashlib.sha256(content.encode()).hexdigest(),digest)
            self.assertIn('348',(dest/'SCHEMA.md').read_text())
            self.assertIn('Synthetic separate cohorts',(dest/'report.html').read_text())
            with self.assertRaisesRegex(ValueError,'never overwritten'):
                combined.write_package(self.clean(),dest)

    def test_readme_overview_keeps_full_history_in_methods(self):
        from render_publication import readme
        d = self.clean()
        keys = ('sample', 'cohorts', 'conditions', 'scoring', 'amendment', 'limitations', 'intervals', 'timing', 'ultra')
        for key in keys:
            d['methodology'][key] = 'FULL_METHOD_DETAIL_' + key
        overview = readme(d)
        methods = core.methods_markdown(d)
        for key in keys:
            self.assertNotIn('FULL_METHOD_DETAIL_' + key, overview)
            self.assertIn('FULL_METHOD_DETAIL_' + key, methods)
        self.assertIn('METHODS.md', overview)
        self.assertIn('separate grading batches', overview)
        self.assertIn('not intrinsic translation ability', overview)
        self.assertIn('Off does not guarantee zero backend reasoning', overview)
        # The aggregate unusable flag is not unanimous reviewer agreement.
        # Count the two individual booleans instead of subtracting that flag.
        selected = next(r for r in d['summary'] if 'delivery_counts' in r)
        selected.update(mean=10, unusable=0)
        runs = [r for r in d['runs'] if r['configuration_id'] == selected['configuration_id']]
        for r in runs:
            for review in r['reviews']:
                review['usable'] = True
        for r in runs[:5]:
            r['reviews'][0]['usable'] = False
        self.assertIn('Both reviewers marked **7/12 outputs usable**', readme(d))

    def test_practical_takeaways_require_final_fully_matched_data(self):
        from render_publication import prepare, readme, value_choices
        d = self.clean()
        self.assertTrue(value_choices(prepare(d)))
        d['publication']['ready'] = False
        self.assertEqual(value_choices(prepare(d)), [])
        self.assertNotIn('cheapest eligible setting', readme(d))
        self.assertNotIn('highest observed mean', readme(d))
        for field, value in (('n', 11), ('total', 13), ('provisional', True)):
            with self.subTest(field=field):
                d = self.clean()
                d['value_comparison'][field] = value
                self.assertEqual(value_choices(prepare(d)), [])

    def test_value_takeaways_exclude_unknown_lower_bound_or_unusable(self):
        from render_publication import prepare, value_choices
        base = prepare(self.clean())
        row = next(r for r in base['value']['rows'] if r['eligible'])
        base['value']['rows'] = [row]
        self.assertTrue(value_choices(base))
        for field, value in (('cost_status', 'lower_bound'), ('cost_status', 'unavailable'),
                ('cost_mean_usd', None), ('cost_mean_usd', -1), ('eligible', False),
                ('cost_eligible', False), ('unusable', 1), ('n', 11)):
            with self.subTest(field=field, value=value):
                d = copy.deepcopy(base)
                d['value']['rows'][0][field] = value
                self.assertEqual(value_choices(d), [])

    def test_value_takeaways_apply_unrounded_threshold_and_eligible_minimum(self):
        from render_publication import prepare, value_choices
        d = prepare(self.clean())
        template = next(r for r in d['value']['rows'] if r['eligible'])
        cheap = dict(template, configuration_id='cheap', mean=9.499, cost_mean_usd=.01)
        winner = dict(template, configuration_id='winner', mean=9.51, cost_mean_usd=.02)
        excluded = dict(template, configuration_id='incomplete', mean=10, cost_mean_usd=.001, cost_status='lower_bound')
        d['value']['rows'] = [cheap, winner, excluded]
        self.assertEqual(value_choices(d, (9.5,))[0][1]['configuration_id'], 'winner')

    def test_preview_never_looks_final(self):
        with tempfile.TemporaryDirectory() as root:
            dest=combined.write_package(self.clean(),Path(root)/'draft',preview=True)
            data=json.loads((dest/'results.json').read_text())
            self.assertFalse(data['publication']['ready'])
            self.assertEqual(data['publication']['status'],'draft')
            self.assertIn('DRAFT',(dest/'README.md').read_text())


if __name__=='__main__':
    unittest.main()
