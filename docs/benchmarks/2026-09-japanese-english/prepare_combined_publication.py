#!/usr/bin/env python3
"""Stage the expanded numeric-only study; never publish or contact a service.

Final staging requires the original 276 cells plus all 72 Gemini cells, current
integrity receipts, two distinct reviews per cell, resolved source audits, and
the bounded CLI pause/resume amendment. --preview always produces a draft.
"""
from __future__ import annotations
import argparse
import copy
import hashlib
import json
from pathlib import Path
import re
import statistics
import prepare_publication as core

BASE = Path(__file__).resolve().parent
GEMINI_MODELS = {'gemini-3.5-flash-lite', 'gemini-3.8-flash', 'gemini-3.1-pro'}
GEMINI_EFFORTS = {'standard', 'extended'}
OLD_CLI = 'codex-cli 0.155.0-alpha.9.2'
NEW_CLI = 'codex-cli 0.155.0-alpha.16.3'
RESUMED = {('gpt-6-luna--max', 'V10-S090', 2), ('gpt-5.6-terra--ultra', 'V10-S090', 2)}
SUCCESS = {'completed', 'complete', 'success'}
DELIVERY = {'english_translation', 'service_error', 'non_english_transcription', 'other_failure'}
CONTEXT_LIMITATION = 'delegated_child_context_not_fully_observable'
CONTEXT_GATE = 'Every context audit must be explicitly complete with no unresolved findings.'


def context_limitation_binding(raw):
    """Bind exact private findings without including their prose in the package."""
    findings = [{'run_id': r['configuration_id'] + '/' + r['source_id'],
        'findings': r.get('context_policy_review_required')} for r in raw['runs']
        if r.get('context_policy_review_required')]
    return core.canonical_hash(sorted(findings, key=lambda r: r['run_id']))


def context_limitation_ready(raw, audit, curation):
    """Acknowledge only the reviewed, frozen 13-row observability limitation.

    This does not resolve child context or usage and never changes the raw flags.
    A new finding, missing flag, changed result or value-eligible cost fails closed.
    """
    acknowledgment = curation.get('context_limitation_acknowledgment') or {}
    expected = acknowledgment.get('run_ids', [])
    flagged = []
    for r in raw['runs']:
        flags = r.get('context_policy_review_required')
        if flags is False or flags == []:
            continue
        if not (isinstance(flags, list) and len(flags) == 1
            and isinstance(flags[0], dict) and flags[0].get('category') == CONTEXT_LIMITATION
            and (r.get('cost') or {}).get('status') == 'lower_bound'):
            return False
        flagged.append(r['configuration_id'] + '/' + r['source_id'])
    affected_configs = {r.split('/')[0] for r in flagged}
    values = [r for r in raw.get('value_comparison', {}).get('rows', [])
        if r.get('configuration_id') in affected_configs]
    return (acknowledgment.get('category') == CONTEXT_LIMITATION
        and len(expected) == len(set(expected)) == len(flagged) == 13 and set(expected) == set(flagged)
        and acknowledgment.get('openai_numeric_sha256') == audit.get('results_numeric_sha256') == core.integrity_binding(raw)
        and acknowledgment.get('findings_sha256') == context_limitation_binding(raw)
        and len(values) == len(affected_configs)
        and all(r.get('cost_status') == 'lower_bound' and r.get('cost_eligible') is False
            and r.get('eligible') is False and r.get('frontier') is False for r in values)
        and not any(r.get('configuration_id') in affected_configs
            for r in raw.get('value_comparison', {}).get('recommendations', [])))


def complete_reviews(run, version):
    reviews, statuses = run['reviews'], run['review_statuses']
    return (len(reviews) == 2 and {r['judge'] for r in reviews} == core.JUDGES
        and all(r['review_version'] == version and r['usable'] is not None
            and all(r[k] is not None for k in core.SCORES) for r in reviews)
        and len(statuses) == 2 and {s['judge'] for s in statuses} == core.JUDGES
        and all(s['status'] in SUCCESS for s in statuses))


def cli_amendment_ready(raw, audit, amendment, curation):
    affected = amendment.get('affected_attempts', [])
    expected = {(a.get('configuration_id'), a.get('source_id'), a.get('attempt')) for a in affected}
    if not (core.canonical_hash(amendment) == curation.get('cli_amendment_sha256')
        and audit.get('cli_resume_amendment') == amendment
        and amendment.get('schema_version') == 1
        and amendment.get('old_cli_version') == OLD_CLI and amendment.get('new_cli_version') == NEW_CLI
        and len(affected) == 2 and expected == RESUMED):
        return False
    observed = set()
    for r in raw['runs']:
        key = (r['configuration_id'], r['source_id'], r.get('attempt_count'))
        resumed = key in RESUMED
        if resumed:
            observed.add(key)
            if not (r.get('cli_version') == NEW_CLI and r.get('resumed_after_user_interruption') is True
                and (r.get('cost') or {}).get('status') == 'lower_bound'):
                return False
        elif r.get('cli_version') != OLD_CLI or r.get('resumed_after_user_interruption') is True:
            return False
    resumed_configs = {c for c, _, _ in RESUMED}
    value_rows = [r for r in raw.get('value_comparison', {}).get('rows', [])
        if r.get('configuration_id') in resumed_configs]
    return (observed == RESUMED and len(value_rows) == 2
        and all(r.get('cost_status') == 'lower_bound' and r.get('cost_eligible') is False
            and r.get('eligible') is False and r.get('frontier') is False for r in value_rows))


def source_audits_ready(rows, source_ids):
    return (len(rows) == len(source_ids) and {s.get('source_id') for s in rows} == source_ids
        and all(s.get('status') in {'resolved', 'not_needed'} for s in rows))


def delivery_audits_ready(rows, source_ids):
    return (source_audits_ready(rows, source_ids)
        and all(s.get('status') == 'resolved' and s.get('audited_candidates') == 6
            and isinstance(s.get('packet_sha256'), str) and re.fullmatch(r'[0-9a-f]{64}', s['packet_sha256']) is not None for s in rows))


def gemini_audit_ready(raw, raw_bytes, audit, sources):
    if json.loads(raw_bytes) != raw:
        raise ValueError('Gemini snapshot bytes and parsed results differ')
    hashes = {s['id']: s['sha256'] for s in sources}
    checks = audit.get('source_hash_checks', [])
    return (audit.get('passed') is True and audit.get('complete') is True
        and audit.get('planned_cells') == 72 and audit.get('completed_responses') == 72
        and audit.get('double_reviewed_cells') == 72
        and audit.get('original_openai_study_modified') is False
        and audit.get('results_sha256') == hashlib.sha256(raw_bytes).hexdigest()
        and len(checks) == 12 and {s.get('source_id') for s in checks} == set(hashes)
        and all(s.get('matched') is True and s.get('expected_sha256') == hashes[s['source_id']]
            and s.get('actual_sha256') == hashes[s['source_id']] for s in checks)
        and source_audits_ready(audit.get('source_audit_checks', []), set(hashes))
        and delivery_audits_ready(audit.get('delivery_audit_checks', []), set(hashes))
        and {r.get('source_id'): r.get('packet_sha256') for r in audit.get('delivery_audit_checks', [])}
            == {r.get('source_id'): r.get('packet_sha256') for r in raw.get('delivery_audits', [])})


def gemini_run(r, config_ids, source_ids, pricing):
    cid = core.enum(r.get('configuration_id'), config_ids)
    sid = core.enum(r.get('source_id'), source_ids)
    # Browser subscriptions do not emit API token counts. Reject fabricated zero
    # costs as firmly as positive estimates; neither can support a value ranking.
    if r.get('usage') is not None or r.get('cost_usd') is not None or r.get('cost') is not None:
        raise ValueError('Gemini web usage and API-equivalent costs must remain unknown')
    a = r.get('adjudication') or {}
    outcome = r.get('delivery_outcome') or {}
    return {'id': cid + '/' + sid, 'configuration_id': cid, 'source_id': sid,
        'cohort': 'gemini-web', 'status': core.enum(r.get('status'), core.STATES),
        'scores': core.scores(r.get('scores')), 'elapsed_seconds': core.numeric(r.get('elapsed_seconds')),
        'usage': core.numbers({}, core.USAGE), 'cost': core.safe_cost(None, pricing),
        'reviews': [core.review(v) for v in r.get('reviews', [])],
        'review_statuses': [{'judge': core.enum(v.get('judge'), core.JUDGES),
            'status': core.enum(v.get('status'), core.STATES)} for v in r.get('review_statuses', [])],
        'judge_disagreement': core.numeric(r.get('judge_disagreement'), 0, 9),
        'needs_adjudication': core.boolean(r.get('needs_adjudication')),
        'adjudication_resolved': core.boolean(r.get('adjudication_resolved')),
        'adjudication_recorded': bool(a),
        'adjudication_verdict': core.enum(a.get('verdict'), {'supported', 'partly_supported', 'unsupported', 'uncertain'}, nullable=True),
        'score_override_recommended': core.boolean(a.get('score_override_recommended')),
        'delivery_outcome': core.enum(outcome.get('classification'), DELIVERY, nullable=True)}


def gemini_summary(cid, runs, sources):
    rows = [r for r in runs if r['configuration_id'] == cid]
    graded = [r for r in rows if r['scores'] and r['scores']['overall'] is not None]
    prose = {s['id'] for s in sources if s['is_prose']}
    def mean(rs):
        return statistics.mean(r['scores']['overall'] for r in rs) if rs else None
    elapsed = [r['elapsed_seconds'] for r in rows if r['elapsed_seconds'] is not None]
    return {'configuration_id': cid, 'cohort': 'gemini-web', 'n': len(graded), 'total': 12,
        'completed': sum(r['status'] == 'completed' for r in rows), 'mean': mean(graded),
        'prose_mean': mean([r for r in graded if r['source_id'] in prose]),
        'layout_mean': mean([r for r in graded if r['source_id'] not in prose]),
        'median_seconds': statistics.median(elapsed) if elapsed else None,
        'unusable': sum(len(r['reviews']) == 2 and all(v['usable'] is False for v in r['reviews']) for r in graded),
        'review_disagreements': sum((r['judge_disagreement'] or 0) >= 1.5 for r in graded),
        'failed': sum(r['status'] not in {'completed', 'pending', 'running'} for r in rows),
        'ci_low': None, 'ci_high': None, 'cost_n': 0, 'cost_mean_usd': None,
        'cost_mean_no_cache_usd': None, 'cost_total_usd': None, 'cost_status': 'unavailable',
        'delivery_counts': {key: sum(r['delivery_outcome'] == key for r in rows) for key in sorted(DELIVERY)},
        'english_translation_n': sum(r['delivery_outcome'] == 'english_translation' for r in graded),
        'english_translation_mean': mean([r for r in graded if r['delivery_outcome'] == 'english_translation'])}


def sanitize(openai, gemini, *, openai_curation, curation, openai_audit, gemini_audit, gemini_bytes, cli_amendment):
    data = copy.deepcopy(core.sanitize(openai, openai_curation, openai_audit))
    if core.canonical_hash(gemini.get('methodology')) != curation.get('gemini_methodology_sha256'):
        raise ValueError('Gemini methodology changed since curation')
    if core.canonical_hash(gemini.get('pricing_policy')) != curation.get('gemini_pricing_policy_sha256'):
        raise ValueError('Gemini pricing policy changed since curation')
    source_ids = {s['id'] for s in data['sources']}
    gem_sources = [{'id': s.get('id'), 'category': s.get('category'), 'is_prose': s.get('prose'), 'sha256': s.get('sha256')} for s in gemini.get('sources', [])]
    if sorted(gem_sources, key=lambda s: s['id']) != sorted(data['sources'], key=lambda s: s['id']):
        raise ValueError('Gemini must retain the same twelve source captures and hashes')
    configs = []
    for c in gemini.get('configurations', []):
        model = core.enum(c.get('model'), GEMINI_MODELS)
        effort = core.enum(c.get('effort'), GEMINI_EFFORTS)
        cid = model + '--' + effort
        if c.get('id') != cid or c.get('provider') != 'gemini-web' or c.get('extended_thinking') is not (effort == 'extended'):
            raise ValueError('Unexpected Gemini UI configuration identity')
        configs.append({'id': cid, 'model': model, 'effort': effort, 'cohort': 'gemini-web',
            'extended_thinking': effort == 'extended'})
    config_ids = {c['id'] for c in configs}
    if len(configs) != 6 or config_ids != {m + '--' + e for m in GEMINI_MODELS for e in GEMINI_EFFORTS}:
        raise ValueError('Publication must retain all six Gemini configurations')
    runs = [gemini_run(r, config_ids, source_ids, data['pricing']) for r in gemini.get('runs', [])]
    pairs = {(r['configuration_id'], r['source_id']) for r in runs}
    if len(runs) != 72 or pairs != {(c, s) for c in config_ids for s in source_ids}:
        raise ValueError('Publication must retain all 72 Gemini cells exactly once')
    reasons = data['publication']['gate_reasons']
    if CONTEXT_GATE in reasons and context_limitation_ready(openai, openai_audit, curation):
        reasons.remove(CONTEXT_GATE)
        acknowledgment = curation['context_limitation_acknowledgment']
        data['context_limitation_acknowledgment'] = {
            'status': 'acknowledged_reporting_limitation', 'category': CONTEXT_LIMITATION,
            'run_ids': sorted(acknowledgment['run_ids']), 'count': 13,
            'openai_numeric_sha256': acknowledgment['openai_numeric_sha256'],
            'findings_sha256': acknowledgment['findings_sha256'],
            'complete_child_context': False, 'complete_child_usage': False}
        for r in data['runs']:
            r['context_limitation_acknowledged'] = r['id'] in acknowledgment['run_ids']
            if r['context_limitation_acknowledged']:
                r['context_limitation_category'] = CONTEXT_LIMITATION
    if any(not complete_reviews(r, openai_curation['review_version']) for r in data['runs']):
        reasons.append('OpenAI requires exactly two distinct completed review statuses per cell.')
    if not cli_amendment_ready(openai, openai_audit, cli_amendment, curation):
        reasons.append('The bounded two-cell CLI pause/resume amendment must match current results and integrity receipt.')
    if gemini.get('status') != 'complete' or any(r['status'] != 'completed' or not r['scores'] or any(v is None for v in r['scores'].values()) for r in runs):
        reasons.append('All 72 Gemini responses need complete dimensional scores.')
    if any(not complete_reviews(r, curation['gemini_review_version']) for r in runs):
        reasons.append('Gemini requires both distinct completed reviews at the curated protocol version for every response.')
    if any(core.adjudication_needed(r) and not core.adjudication_valid(r) for r in runs) or any(r['score_override_recommended'] is True for r in runs):
        reasons.append('Gemini source adjudications or score overrides remain unresolved.')
    if not source_audits_ready(gemini.get('source_audits', []), source_ids):
        reasons.append('All twelve Gemini source audits must be resolved or explicitly not needed.')
    delivery_packets = {a.get('source_id'): a.get('packet_sha256') for a in gemini.get('delivery_audits', [])}
    if (not delivery_audits_ready(gemini.get('delivery_audits', []), source_ids)
        or any(not (r.get('delivery_outcome') and r['delivery_outcome'].get('audited') is True
            and r['delivery_outcome'].get('classification') in DELIVERY
            and r['delivery_outcome'].get('source_id') == r['source_id']
            and r['delivery_outcome'].get('packet_sha256') == delivery_packets.get(r['source_id'])) for r in gemini['runs'])):
        reasons.append('Every Gemini delivery outcome needs a resolved anonymous content audit bound to its source packet.')
    if any(r.get('provenance_problems') or r.get('quota_warning') for r in gemini['runs']):
        reasons.append('Gemini collection provenance or quota warnings require resolution.')
    if not gemini_audit_ready(gemini, gemini_bytes, gemini_audit, data['sources']):
        reasons.append('A complete passing Gemini integrity receipt must bind these exact results bytes and source hashes.')
    for row in (*data['configurations'], *data['runs'], *data['summary']):
        row['cohort'] = 'codex-cli'
    for c in configs:
        summary = gemini_summary(c['id'], runs, data['sources'])
        data['summary'].append(summary)
        data['value_comparison']['rows'].append({'configuration_id': c['id'], 'n': summary['n'],
            'mean': summary['mean'], 'cost_mean_usd': None, 'cost_mean_no_cache_usd': None,
            'unusable': sum(any(v['usable'] is False for v in r['reviews']) for r in runs if r['configuration_id'] == c['id']),
            'cost_status': 'unavailable', 'cost_eligible': False, 'eligible': False, 'frontier': False})
    data['configurations'].extend(configs)
    data['runs'].extend(runs)
    data['methodology'] = copy.deepcopy(curation['methodology'])
    data['schema_version'] = 2
    data.pop('review_version', None)
    data['review_versions'] = {'codex-cli': openai_curation['review_version'], 'gemini-web': curation['gemini_review_version']}
    data['status'] = 'partial' if reasons else 'complete'
    data['generated_at'] = core.pattern(gemini.get('generated_at'), r'\d{4}-\d{2}-\d{2}T[0-9:.+Z-]+')
    data['publication'].update(ready=not reasons, status='draft' if reasons else 'final',
        input_bindings={'openai_numeric_sha256': core.integrity_binding(openai),
            'gemini_results_sha256': hashlib.sha256(gemini_bytes).hexdigest(),
            'cli_amendment_sha256': core.canonical_hash(cli_amendment)})
    data['cli_resume_amendment'] = {'old_cli_version': OLD_CLI, 'new_cli_version': NEW_CLI,
        'affected_attempts': [{'configuration_id': c, 'source_id': s, 'attempt': a} for c, s, a in sorted(RESUMED)],
        'cost_status': 'lower_bound', 'completed_original_outputs_preserved': 274}
    data['value_comparison']['scope'] = 'codex-cli only; Gemini web costs are unknown and excluded from dollar-value recommendations'
    data['value_comparison']['method'] += ' Gemini web configurations cannot enter API dollar-value rankings because their token usage and API equivalence are unknown.'
    core.privacy_check(json.dumps(data, ensure_ascii=False))
    return data


SCHEMA = '''# Expanded result schema

The package retains 12 source captures, 29 configurations, and 348 cells: 276 Codex CLI and 72 Gemini web responses. Null means unknown, never free or zero. Source text, images, translations, reviewer quotations and private paths are excluded.

Each configuration, run and summary has a `cohort`: `codex-cli` or `gemini-web`. Reviews use protocol version 2 and 1 respectively, both with the amended source-alone grading anchors. Two distinct judges assess every response. Numeric issue-severity counts remain; reviewer prose does not.

The cohorts share frozen source hashes and scoring dimensions, but were graded in separate batches with no calibration controls. Cross-cohort grading drift was not measured. Treat pooled score ordering as descriptive, not a controlled provider comparison. Gemini standard/extended means the web UI extended-thinking switch off/on, not zero versus nonzero internal reasoning. Selected UI model names do not verify backend identity.

`summary` reports cohort scores and timing. Gemini delivery counts distinguish English translations, service errors, non-English transcriptions and other failures using anonymous content audits. The primary mean retains all twelve responses; `english_translation_mean` is conditional on delivery and has a potentially different subset, so it is not a replacement ranking. Codex intervals are descriptive bootstrap estimates; Gemini intervals are unavailable. Unusable counts in summary require both judges; value eligibility excludes any capture either judge marked unusable.

`cost` holds observed-token Standard API equivalents for Codex. Gemini costs and usage remain null with unavailable status; Gemini configurations are never value eligible and never receive dollar recommendations. Missing usage from two interrupted Codex attempts makes their costs lower bounds and excludes them from value recommendations. `cli_resume_amendment` records exactly those two replacement attempts and their client version boundary.

`publication.input_bindings` binds the OpenAI numeric integrity snapshot, the exact Gemini results bytes, and the reviewed CLI amendment. Final staging requires 348 completed doubly graded cells, resolved source adjudications, no unresolved score overrides, current source-hash checks, and both passing integrity receipts. A narrowly pinned `context_limitation_acknowledgment` retains the exact 13 original runs with unavailable delegated child histories: their `context_policy_review_required` flags remain true, child context and usage are not claimed complete, and affected lower-bound costs cannot enter dollar-value recommendations. The acknowledgment binds exact run IDs, finding payload hashes, and the frozen numerical receipt. Any new or changed context finding blocks staging. This is a reporting limitation, not a passed child-context audit. Any incomplete gate permits only an explicit draft preview. Existing directories cannot be overwritten. The staging tools never publish or make network requests.

Run `python3 -m unittest test_publication test_pricing test_combined_publication` for synthetic privacy and readiness regressions. Run `python3 render_publication.py --results results.json --output report.html` to reproduce the standalone report. Private input collection and source review are not included in this sanitized package.
'''


def write_package(data, output, *, preview=False):
    return core.write_package(data, output, preview=preview, schema=SCHEMA,
        extra_source_files=('prepare_combined_publication.py', 'publication-combined-methodology.json', 'test_combined_publication.py'))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ('openai-results', 'gemini-results', 'openai-integrity', 'gemini-integrity', 'cli-amendment', 'output'):
        parser.add_argument('--' + name, type=Path, required=True)
    parser.add_argument('--openai-curation', type=Path, default=BASE / 'publication-methodology.json')
    parser.add_argument('--curation', type=Path, default=BASE / 'publication-combined-methodology.json')
    parser.add_argument('--preview', action='store_true')
    args = parser.parse_args()
    read = lambda path: json.loads(path.read_text())
    try:
        gemini_bytes = args.gemini_results.read_bytes()
        data = sanitize(read(args.openai_results), json.loads(gemini_bytes), openai_curation=read(args.openai_curation),
            curation=read(args.curation), openai_audit=read(args.openai_integrity), gemini_audit=read(args.gemini_integrity),
            gemini_bytes=gemini_bytes, cli_amendment=read(args.cli_amendment))
        print(write_package(data, args.output, preview=args.preview))
    except (OSError, ValueError, KeyError, TypeError) as error:
        parser.exit(1, f'Expanded publication staging failed: {error}\n')


if __name__ == '__main__':
    main()
