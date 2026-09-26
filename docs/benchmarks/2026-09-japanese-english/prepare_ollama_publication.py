#!/usr/bin/env python3
"""Append supported Gemma/DeepSeek native modes to the frozen 31-setting report.

Private responses, source images and reviewer prose are never packaged. Unsupported
DeepSeek Medium is documented, not mislabeled as an independently tested mode.
"""
from __future__ import annotations
import argparse
import copy
import json
import re
from pathlib import Path
import prepare_publication as core
import prepare_combined_publication as combined
import prepare_deepseek_publication as native

BASE = Path(__file__).resolve().parent
COHORT = 'ollama-cloud-expanded'
DS = 'deepseek-v4.1-flash:cloud'
GEMMA = 'gemma4:31b-cloud'
CONFIGS = {
    'deepseek-v4.1-flash-cloud--high': (DS, 'high', 'high', {DS, 'deepseek-v4.1-flash'}),
    'gemma4-31b-cloud--instant': (GEMMA, 'instant', False, {GEMMA, 'gemma4:31b'}),
    'gemma4-31b-cloud--thinking': (GEMMA, 'thinking', True, {GEMMA, 'gemma4:31b'}),
}
DISPLAYS = {DS: 'DeepSeek V4.1 Flash', GEMMA: 'Gemma 4 31B'}
sha = native.sha
timestamp = native.timestamp


def interruption_record(raw):
    """Project bound terminal failures without publishing partial private output."""
    record = raw.get('administrative_interruption')
    if raw.get('status') != 'interrupted':
        if record:
            raise ValueError('Only interrupted attempts may contain interruption evidence')
        return None
    if not isinstance(record, dict) or record.get('native_receipt_absent') is not True:
        raise ValueError('Interrupted attempts require explicit absence of a native final receipt')
    if raw.get('usage') or raw.get('cost') or raw.get('cost_usd') is not None or raw.get('native_timing_ns') or raw.get('done_reason'):
        raise ValueError('Interrupted attempts cannot claim final usage, cost or native timing')
    if record.get('run_id') != raw['configuration_id'] + '/' + raw['source_id']:
        raise ValueError('Interruption evidence identifies a different request')
    out = {'native_receipt_absent': True}
    for key in ('request_sha256', 'stream_sha256', 'protocol_amendment_sha256', 'translation_sha256'):
        out[key] = core.pattern(record.get(key), r'[0-9a-f]{64}')
    for key in ('started_at', 'finished_at'):
        timestamp(record.get(key))
        out[key] = record[key]
    if out['started_at'] != raw['started_at'] or timestamp(out['finished_at']) < timestamp(out['started_at']):
        raise ValueError('Interruption timestamps must match the original request')
    out['deadline_seconds'] = core.numeric(record.get('deadline_seconds'), 1)
    out['elapsed_seconds'] = core.numeric(record.get('elapsed_seconds'), 0)
    if out['deadline_seconds'] != 1800 or out['elapsed_seconds'] is None or out['elapsed_seconds'] < 1800 or out['elapsed_seconds'] != raw.get('elapsed_seconds'):
        raise ValueError('Interrupted timing must bind the disclosed thirty-minute deadline')
    return out


def sanitize(base_bytes, raw_bytes, audit, curation):
    if sha(base_bytes) != curation['base_results_sha256']:
        raise ValueError('Original 31-configuration publication changed')
    base = json.loads(base_bytes)
    if not base['publication']['ready'] or base['publication']['status'] != 'final' or len(base['runs']) != 372 or len(base['configurations']) != 31:
        raise ValueError('Append requires the complete frozen publication')
    raw = json.loads(raw_bytes)
    data = copy.deepcopy(base)
    sources = {s['id']: s for s in base['sources']}
    expected = sorted((s['id'], s['category'], s['is_prose'], s['sha256']) for s in sources.values())
    observed = sorted((s['id'], s['category'], s.get('prose', s.get('is_prose')), s['sha256']) for s in raw['sources'])
    if observed != expected:
        raise ValueError('Expanded Ollama cohort must use the identical 12 source captures')
    configs = []
    for c in raw['configurations']:
        cid = core.enum(c['id'], CONFIGS)
        model, effort, think, returned = CONFIGS[cid]
        if c.get('model') != model or c.get('effort') != effort or c.get('provider') != 'ollama-cloud' or c.get('native_think') != think or type(c.get('native_think')) is not type(think):
            raise ValueError('Unexpected expanded Ollama configuration')
        configs.append({'id': cid, 'model': model, 'model_display': DISPLAYS[model],
            'effort': effort, 'requested_think': think, 'cohort': COHORT})
    if len(configs) != 3 or {c['id'] for c in configs} != set(CONFIGS):
        raise ValueError('Exactly DeepSeek High and Gemma Instant/Thinking are required')
    if set(curation['pricing_by_model']) != set(DISPLAYS):
        raise ValueError('Every exact requested model needs a reviewed tariff')
    runs = [native.public_run(r, set(sources), curation['pricing_by_model'][CONFIGS[r['configuration_id']][0]],
        config_specs=CONFIGS, cohort=COHORT) for r in raw['runs']]
    interruption_checks = []
    for original, public in zip(raw['runs'], runs):
        record = interruption_record(original)
        if record:
            public['administrative_interruption'] = record
            interruption_checks.append({'id': public['id'], 'status': 'interrupted',
                'administrative_interruption_verified': True,
                **{k: record[k] for k in ('request_sha256', 'stream_sha256', 'translation_sha256',
                    'protocol_amendment_sha256', 'elapsed_seconds', 'deadline_seconds', 'native_receipt_absent')}})
    if len(runs) != 36 or {(r['configuration_id'], r['source_id']) for r in runs} != {(c, s) for c in CONFIGS for s in sources}:
        raise ValueError('Expanded Ollama matrix must contain all 36 distinct cells')
    reasons = data['publication']['gate_reasons']
    if raw.get('status') != 'complete' or any(r['status'] not in {'completed', 'interrupted'} or not r['scores'] for r in runs):
        reasons.append('All 36 Expanded Ollama attempts must be terminal and scored.')
    if any(not combined.complete_reviews(r, curation['ollama_review_version']) for r in runs):
        reasons.append('Every Expanded Ollama response requires both distinct completed reviewers.')
    if any(core.adjudication_needed(r) and not core.adjudication_valid(r) or r['score_override_recommended'] is True for r in runs):
        reasons.append('Expanded Ollama source adjudications remain unresolved.')
    if not combined.source_audits_ready(raw.get('source_audits', []), set(sources)):
        reasons.append('Every Expanded Ollama source audit must be resolved or explicitly not needed.')
    da = raw.get('delivery_audits', [])
    packets = {v.get('source_id'): v.get('packet_sha256') for v in da}
    if (not combined.source_audits_ready(da, set(sources)) or any(v.get('status') != 'resolved' or v.get('audited_candidates') != 3
            or not re.fullmatch(r'[0-9a-f]{64}', str(v.get('packet_sha256', ''))) for v in da)
        or any(not (r.get('delivery_outcome') and r['delivery_outcome'].get('audited') is True
            and r['delivery_outcome'].get('classification') in combined.DELIVERY
            and r['delivery_outcome'].get('source_id') == r['source_id']
            and r['delivery_outcome'].get('packet_sha256') == packets.get(r['source_id'])) for r in raw['runs'])):
        reasons.append('Expanded Ollama delivery needs a bound anonymous content audit for each source set.')
    checks = audit.get('source_hash_checks', [])
    if not (audit.get('passed') is True and audit.get('complete') is True
        and audit.get('results_sha256') == sha(raw_bytes)
        and audit.get('planned_cells') == 36
        and audit.get('completed_responses') == sum(r['status'] == 'completed' for r in runs)
        and audit.get('interrupted_responses') == len(interruption_checks)
        and audit.get('terminal_responses') == 36
        and sorted(audit.get('interruption_checks', []), key=lambda v: v['id']) == sorted(interruption_checks, key=lambda v: v['id'])
        and audit.get('double_reviewed_cells') == 36
        and len(checks) == 12 and {s.get('source_id') for s in checks} == set(sources)
        and all(s.get('matched') is True and s.get('expected_sha256') == sources[s['source_id']]['sha256'] == s.get('actual_sha256') for s in checks)
        and audit.get('source_audit_checks') == raw.get('source_audits')
        and audit.get('delivery_audit_checks') == da):
        reasons.append('A passing Expanded Ollama integrity receipt must bind the exact results and audits.')
    if any(r.get('provenance_problems') or r.get('quota_warning') for r in raw['runs']):
        reasons.append('Expanded Ollama provenance or quota findings require review.')
    data['configurations'].extend(configs)
    data['runs'].extend(runs)
    data['summary'].extend(native.summarize(c['id'], runs, data['sources'], cohort=COHORT) for c in configs)
    data['ollama_expanded_pricing'] = copy.deepcopy(curation['pricing_by_model'])
    for key, value in curation['methodology_additions'].items():
        data['methodology'][key] = (data['methodology'].get(key, '') + ' ' + value).strip()
    data['methodology'].update(planned_configurations=34, planned_translations=408)
    data['review_versions'][COHORT] = curation['ollama_review_version']
    data['schema_version'] = 4
    data['generated_at'] = raw['generated_at']
    timestamp(data['generated_at'])
    data['status'] = 'partial' if reasons else 'complete'
    data['publication'].update(ready=not reasons, status='draft' if reasons else 'final')
    data['publication']['input_bindings'].update(expanded_base_publication_sha256=sha(base_bytes),
        ollama_expanded_results_sha256=sha(raw_bytes), ollama_expanded_integrity_sha256=core.canonical_hash(audit))
    # Existing cohorts, source judgments, cost rankings and recommendations are
    # frozen. The new cohort gets a separate descriptive quality/cost table.
    for key in ('runs', 'configurations', 'summary'):
        assert data[key][:len(base[key])] == base[key]
    assert data['value_comparison'] == base['value_comparison']
    core.privacy_check(json.dumps(data, ensure_ascii=False))
    return data


SCHEMA = """# Expanded result schema (schema 4)

This extension adds 36 native Ollama translation attempts and 72 blinded assessments,
bringing the package to 34 configurations, 408 attempts and 816 assessments.
All 372 earlier response records and the original value analysis remain frozen.

Cohort `ollama-cloud-expanded` contains DeepSeek V4.1 Flash High (native
`think: "high"`) and Gemma 4 31B Instant/Thinking (`think: false`/`true`).
DeepSeek Medium is unsupported and silently falls back to High, so no separate
Medium result is claimed. The new grading uses independently shuffled pairs
plus a singleton for each source/judge; older cohorts used different batch sizes.
Cross-cohort differences are exploratory, not controlled treatment effects.

`ollama_expanded_pricing` maps each exact requested model to its reviewed tariff.
Native token counts and unknown cache/reasoning splits follow schema 3 below.
No actual account charge is inferred. Inputs remain byte-bound to the frozen
31-configuration publication and to the new passing integrity receipt.

An `interrupted` attempt has no native final receipt or final token/cost estimate.
Its `administrative_interruption` records the thirty-minute deadline, observed
elapsed time, timestamps and hashes binding the request, raw stream, delivered
translation and protocol amendment. Both reviewers assess only delivered content.
Elapsed time is a censored lower bound, excluded from completion-latency averages
and shown separately. Unknown cost excludes the configuration from complete-cost
comparisons; known subset totals are partial. Final study status means the entire
attempt matrix has been audited, not that every request delivered a translation.

""" + native.SCHEMA.replace('# Expanded result schema', '## Earlier schema history', 1)


def write_package(data, output, preview=False):
    return core.write_package(data, output, preview=preview, schema=SCHEMA,
        extra_source_files=('prepare_combined_publication.py', 'publication-combined-methodology.json',
            'test_combined_publication.py', 'prepare_deepseek_publication.py',
            'publication-deepseek-methodology.json', 'test_deepseek_publication.py', 'test_deepseek_renderer.py',
            'prepare_ollama_publication.py', 'publication-ollama-expanded-methodology.json',
            'test_ollama_publication.py'))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ('base-results', 'ollama-results', 'ollama-integrity', 'output'):
        parser.add_argument('--' + name, type=Path, required=True)
    parser.add_argument('--curation', type=Path, default=BASE / 'publication-ollama-expanded-methodology.json')
    parser.add_argument('--preview', action='store_true')
    args = parser.parse_args()
    read = lambda p: json.loads(p.read_text())
    data = sanitize(args.base_results.read_bytes(), args.ollama_results.read_bytes(),
        read(args.ollama_integrity), read(args.curation))
    print(write_package(data, args.output, args.preview))


if __name__ == '__main__':
    main()
