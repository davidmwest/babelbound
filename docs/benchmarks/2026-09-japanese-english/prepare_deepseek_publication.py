#!/usr/bin/env python3
"""Append a validated, numeric-only DeepSeek cohort to the frozen publication.

The original 348 cells and original value analysis remain byte-value identical.
Private response/reviewer prose is structurally excluded. This script stages a
new local directory; it never contacts a service or publishes anything.
"""
from __future__ import annotations
import argparse
import copy
import datetime as dt
import hashlib
import json
import math
import re
from pathlib import Path
import statistics
import prepare_publication as core
import prepare_combined_publication as combined

BASE = Path(__file__).resolve().parent
MODEL = 'deepseek-v4.1-flash:cloud'
COHORT = 'ollama-cloud'
CONFIGS = {'deepseek-v4.1-flash-cloud--instant': ('instant', False),
           'deepseek-v4.1-flash-cloud--light': ('light', 'low')}
WEIGHTS = {'accuracy': .5, 'completeness': .25, 'names_numbers': .15, 'fluency': .1}


def sha(value):
    return hashlib.sha256(value).hexdigest()


def timestamp(value):
    core.pattern(value, r'\d{4}-\d{2}-\d{2}T[0-9:.+Z-]+')
    parsed = dt.datetime.fromisoformat(value.replace('Z', '+00:00'))
    if parsed.tzinfo is None:
        raise ValueError('Native timestamps must record a timezone')
    return parsed.astimezone(dt.timezone.utc)


def native_cost(run, pricing):
    """Recompute a no-cache tariff scenario; never invent cache counters."""
    usage = core.numbers(run.get('usage'), core.USAGE)
    if any(usage[key] is not None for key in ('cached_input_tokens', 'cache_write_input_tokens', 'reasoning_output_tokens')):
        raise ValueError('The native receipt does not expose cache counters or a reasoning token split')
    supplied = run.get('cost') or {}
    complete = supplied.get('status') == 'estimated'
    status = core.enum(supplied.get('status', 'unavailable'), core.COST_STATES)
    if status == 'unavailable' and any(supplied.get(key) is not None for key in core.COST_NUMBERS):
        raise ValueError('Unavailable native cost cannot contain numeric cost estimates')
    started = timestamp(run['started_at'])
    period = 'peak' if started.weekday() < 5 and 12 <= started.hour < 18 else 'off_peak'
    rates = pricing[period]
    if usage['input_tokens'] is None or usage['output_tokens'] is None:
        if status != 'unavailable':
            raise ValueError('Cost requires both native token counts')
        return usage, core.safe_cost(None, pricing)
    amount = (usage['input_tokens'] * rates['input'] + usage['output_tokens'] * rates['output']) / 1e6
    includes_thinking = core.boolean(supplied.get('output_includes_thinking'))
    if complete and (run.get('attempt_count') != 1 or includes_thinking is not True):
        raise ValueError('Complete estimate needs complete attempt and reasoning usage')
    if status != 'unavailable' and (supplied.get('usd') is None or not math.isclose(supplied['usd'], amount, rel_tol=1e-9, abs_tol=1e-12)):
        raise ValueError('Native tariff cost does not match recorded usage and UTC period')
    cost = core.safe_cost(supplied, pricing)
    cost.update(period=period, scenario='all_input_uncached', actual_account_charge_known=False,
        cache_usage_known=False, output_includes_thinking=includes_thinking,
        notes=[pricing['limitations']])
    if status != 'unavailable':
        cost.update(usd=amount, no_cache_usd=amount,
            uncached_input_usd=usage['input_tokens'] * rates['input'] / 1e6,
            cached_input_usd=None, output_usd=usage['output_tokens'] * rates['output'] / 1e6,
            rates_per_million={'input': rates['input'], 'cached_input': rates['cached_input'], 'cache_write': None, 'output': rates['output']})
    return usage, cost


def public_run(raw, source_ids, pricing):
    cid = core.enum(raw.get('configuration_id'), CONFIGS)
    sid = core.enum(raw.get('source_id'), source_ids)
    effort, think = CONFIGS[cid]
    if raw.get('model') != MODEL or raw.get('native_think') != think or type(raw.get('native_think')) is not type(think):
        raise ValueError('Native request identity differs from declared setting')
    returned = core.enum(raw.get('returned_model'), {MODEL, 'deepseek-v4.1-flash'}, nullable=True)
    usage, cost = native_cost(raw, pricing)
    a = raw.get('adjudication') or {}
    out = {'id': cid + '/' + sid, 'configuration_id': cid, 'source_id': sid,
        'cohort': COHORT, 'status': core.enum(raw.get('status'), core.STATES),
        'requested_model': MODEL, 'returned_model': returned, 'requested_think': think,
        'backend_identity_verified': False, 'thinking_present': core.boolean(raw.get('thinking_present')),
        'started_at': raw['started_at'], 'attempt_count': core.numeric(raw.get('attempt_count'), 1),
        'scores': core.scores(raw.get('scores')), 'usage': usage, 'cost': cost,
        'elapsed_seconds': core.numeric(raw.get('elapsed_seconds')),
        'reviews': [core.review(v) for v in raw.get('reviews', [])],
        'review_statuses': [{'judge': core.enum(v.get('judge'), core.JUDGES),
            'status': core.enum(v.get('status'), core.STATES)} for v in raw.get('review_statuses', [])],
        'judge_disagreement': core.numeric(raw.get('judge_disagreement'), 0, 9),
        'needs_adjudication': core.boolean(raw.get('needs_adjudication')),
        'adjudication_resolved': core.boolean(raw.get('adjudication_resolved')),
        'adjudication_recorded': bool(a),
        'adjudication_verdict': core.enum(a.get('verdict'), {'supported', 'partly_supported', 'unsupported', 'uncertain'}, nullable=True),
        'score_override_recommended': core.boolean(a.get('score_override_recommended')),
        'delivery_outcome': core.enum((raw.get('delivery_outcome') or {}).get('classification'), combined.DELIVERY, nullable=True)}
    if len(out['reviews']) == 2 and out['scores']:
        for review in out['reviews']:
            expected = sum(review[k] * weight for k, weight in WEIGHTS.items())
            if not math.isclose(review['overall'], expected, abs_tol=.0001):
                raise ValueError('Reviewer weighted score mismatch')
        for key in core.SCORES:
            if not math.isclose(out['scores'][key], statistics.mean(v[key] for v in out['reviews']), abs_tol=.0001):
                raise ValueError('Aggregate score differs from frozen reviews')
    return out


def summarize(cid, runs, sources):
    row = combined.gemini_summary(cid, runs, sources)
    cells = [r for r in runs if r['configuration_id'] == cid]
    costs = [r['cost']['usd'] for r in cells if r['cost']['usd'] is not None]
    states = {r['cost']['status'] for r in cells}
    all_priced = bool(cells) and len(costs) == len(cells) and states <= {'estimated', 'lower_bound'}
    status = ('estimated' if states == {'estimated'} else 'lower_bound') if all_priced else 'unavailable'
    row.update(cohort=COHORT, cost_n=len(costs), cost_status=status,
        cost_mean_usd=statistics.mean(costs) if all_priced else None,
        cost_mean_no_cache_usd=statistics.mean(costs) if all_priced else None,
        cost_total_usd=sum(costs) if costs else None)
    return row


def sanitize(base_bytes, raw_bytes, audit, curation):
    if sha(base_bytes) != curation['base_results_sha256']:
        raise ValueError('Original 29-configuration publication changed')
    base = json.loads(base_bytes)
    if not base['publication']['ready'] or base['publication']['status'] != 'final' or len(base['runs']) != 348:
        raise ValueError('Append requires the complete frozen publication')
    raw = json.loads(raw_bytes)
    data = copy.deepcopy(base)
    sources = {s['id']: s for s in base['sources']}
    expected = sorted((s['id'], s['category'], s['is_prose'], s['sha256']) for s in sources.values())
    observed = sorted((s['id'], s['category'], s.get('prose', s.get('is_prose')), s['sha256']) for s in raw['sources'])
    if observed != expected:
        raise ValueError('DeepSeek must use the identical 12 source captures')
    configs = []
    for c in raw['configurations']:
        cid = core.enum(c['id'], CONFIGS)
        effort, think = CONFIGS[cid]
        if c.get('model') != MODEL or c.get('effort') != effort or c.get('provider') != COHORT or c.get('native_think') != think or type(c.get('native_think')) is not type(think):
            raise ValueError('Unexpected DeepSeek configuration')
        configs.append({'id': cid, 'model': MODEL, 'model_display': 'DeepSeek V4.1 Flash',
            'effort': effort, 'requested_think': think, 'cohort': COHORT})
    if len(configs) != 2 or {c['id'] for c in configs} != set(CONFIGS):
        raise ValueError('Exactly Instant and Light are required')
    runs = [public_run(r, set(sources), curation['pricing']) for r in raw['runs']]
    if len(runs) != 24 or {(r['configuration_id'], r['source_id']) for r in runs} != {(c, s) for c in CONFIGS for s in sources}:
        raise ValueError('DeepSeek matrix must contain all 24 distinct cells')
    reasons = data['publication']['gate_reasons']
    if raw.get('status') != 'complete' or any(r['status'] != 'completed' or not r['scores'] for r in runs):
        reasons.append('All 24 DeepSeek responses must be complete and scored.')
    if any(not combined.complete_reviews(r, curation['deepseek_review_version']) for r in runs):
        reasons.append('Every DeepSeek response requires both distinct completed reviewers.')
    if any(core.adjudication_needed(r) and not core.adjudication_valid(r) or r['score_override_recommended'] is True for r in runs):
        reasons.append('DeepSeek source adjudications remain unresolved.')
    if not combined.source_audits_ready(raw.get('source_audits', []), set(sources)):
        reasons.append('Every DeepSeek source audit must be resolved or explicitly not needed.')
    da = raw.get('delivery_audits', [])
    packets = {v.get('source_id'): v.get('packet_sha256') for v in da}
    if (not combined.source_audits_ready(da, set(sources)) or any(v.get('status') != 'resolved' or v.get('audited_candidates') != 2
            or not re.fullmatch(r'[0-9a-f]{64}', str(v.get('packet_sha256', ''))) for v in da)
        or any(not (r.get('delivery_outcome') and r['delivery_outcome'].get('audited') is True
            and r['delivery_outcome'].get('classification') in combined.DELIVERY
            and r['delivery_outcome'].get('source_id') == r['source_id']
            and r['delivery_outcome'].get('packet_sha256') == packets.get(r['source_id'])) for r in raw['runs'])):
        reasons.append('DeepSeek delivery needs a bound anonymous content audit for each source pair.')
    checks = audit.get('source_hash_checks', [])
    if not (audit.get('passed') is True and audit.get('complete') is True
        and audit.get('results_sha256') == sha(raw_bytes)
        and audit.get('planned_cells') == 24 and audit.get('completed_responses') == 24
        and audit.get('double_reviewed_cells') == 24
        and len(checks) == 12 and {s.get('source_id') for s in checks} == set(sources)
        and all(s.get('matched') is True and s.get('expected_sha256') == sources[s['source_id']]['sha256'] == s.get('actual_sha256') for s in checks)
        and audit.get('source_audit_checks') == raw.get('source_audits')
        and audit.get('delivery_audit_checks') == da):
        reasons.append('A passing DeepSeek integrity receipt must bind the exact results and audits.')
    if any(r.get('provenance_problems') or r.get('quota_warning') for r in raw['runs']):
        reasons.append('DeepSeek provenance or quota findings require review.')
    data['configurations'].extend(configs)
    data['runs'].extend(runs)
    data['summary'].extend(summarize(c['id'], runs, data['sources']) for c in configs)
    data['deepseek_pricing'] = copy.deepcopy(curation['pricing'])
    for key, value in curation['methodology_additions'].items():
        data['methodology'][key] = (data['methodology'].get(key, '') + ' ' + value).strip()
    data['methodology'].update(planned_configurations=31, planned_translations=372)
    data['review_versions'][COHORT] = curation['deepseek_review_version']
    data['schema_version'] = 3
    data['generated_at'] = raw['generated_at']
    timestamp(data['generated_at'])
    data['status'] = 'partial' if reasons else 'complete'
    data['publication'].update(ready=not reasons, status='draft' if reasons else 'final')
    data['publication']['input_bindings'].update(base_publication_sha256=sha(base_bytes),
        deepseek_results_sha256=sha(raw_bytes), deepseek_integrity_sha256=core.canonical_hash(audit))
    # Existing cohorts, source judgments, cost rankings and recommendations are
    # frozen. The new cohort gets a separate descriptive quality/cost table.
    for key in ('runs', 'configurations', 'summary'):
        assert data[key][:len(base[key])] == base[key]
    assert data['value_comparison'] == base['value_comparison']
    core.privacy_check(json.dumps(data, ensure_ascii=False))
    return data


SCHEMA = '''# Expanded result schema

The current schema 3 package contains 12 source captures, 31 configurations,
372 responses and 744 reviews. The original schema 2 cohorts described below
remain frozen; the DeepSeek extension follows them.

''' + combined.SCHEMA.replace('# Expanded result schema', '## Frozen original cohorts (schema 2)', 1) + '''
## DeepSeek extension (schema 3)

The extension preserves all earlier run, configuration, summary and original
value-comparison records. It adds 24 native Ollama responses and 48 assessments:
31 configurations, 372 responses and 744 reviews in total. Cohort `ollama-cloud`
uses `deepseek-v4.1-flash:cloud` with Instant (`requested_think: false`) and Light
(`requested_think: "low"`). The returned service label omits the cloud routing
suffix. Neither label independently verifies backend weights.

Native usage retains unknown cache counts as null. `cost.scenario` is
`all_input_uncached`: a published Ollama tariff estimate based on UTC request
time, not an observed account charge. Complete estimates require accounting for
thinking output and all attempts. Missing accounting is unavailable or a lower
bound. The original Codex value selector is unchanged; the additional cohort's
quality and costs are displayed separately because grading batches differ.
`deepseek_pricing` records peak and off-peak rates and limitations.

The append-stage binds the exact frozen base bytes, new private results bytes,
and integrity receipt. It requires two distinct completed reviews, identical
source hashes, resolved source audits and anonymous delivery audits. Source
scans, translations, thinking text and reviewer prose remain private.
'''


def write_package(data, output, preview=False):
    return core.write_package(data, output, preview=preview, schema=SCHEMA,
        extra_source_files=('prepare_combined_publication.py', 'publication-combined-methodology.json',
            'test_combined_publication.py', 'prepare_deepseek_publication.py',
            'publication-deepseek-methodology.json', 'test_deepseek_publication.py', 'test_deepseek_renderer.py'))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ('base-results', 'deepseek-results', 'deepseek-integrity', 'output'):
        parser.add_argument('--' + name, type=Path, required=True)
    parser.add_argument('--curation', type=Path, default=BASE / 'publication-deepseek-methodology.json')
    parser.add_argument('--preview', action='store_true')
    args = parser.parse_args()
    read = lambda p: json.loads(p.read_text())
    data = sanitize(args.base_results.read_bytes(), args.deepseek_results.read_bytes(),
        read(args.deepseek_integrity), read(args.curation))
    print(write_package(data, args.output, args.preview))


if __name__ == '__main__':
    main()
