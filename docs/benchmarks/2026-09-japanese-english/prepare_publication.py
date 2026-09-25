#!/usr/bin/env python3
"""Build a text-free, staging-only benchmark package. This tool never publishes.

Default mode requires the complete 12 x 23 matrix, both reviews, resolved audits,
and a passing final integrity report. --preview permits an explicitly marked
local draft. Output must be a new directory. The curated metadata sidecar is
reviewed separately; a methodology/pricing change invalidates that approval.
"""
from __future__ import annotations
import argparse
import collections
import hashlib
import importlib.util
import json
import math
import os
from pathlib import Path
import re
import shutil
import tempfile

BASE = Path(__file__).resolve().parent
VERSION = 1
MODELS = {'gpt-6-astra', 'gpt-6-sol', 'gpt-5.6-terra', 'gpt-6-luna'}
EFFORTS = {'low', 'medium', 'high', 'xhigh', 'max', 'ultra'}
JUDGES = {'astra-high', 'sol-high'}
SCORES = ('accuracy', 'completeness', 'names_numbers', 'fluency', 'overall')
STATES = {'pending', 'running', 'completed', 'complete', 'success', 'failed', 'error', 'timeout', 'cancelled', 'canceled', 'quota_limit', 'quota_blocked', 'configuration_or_auth_error', 'transient_transport_error', 'interrupted_unknown', 'incomplete', 'invalid_output', 'reviewer_error', 'unusable'}
CATEGORIES = {
    'Abstract exposition + dialogue + ruby names', 'Comic dialogue + physical action + idioms',
    'Contents / typographic front matter', 'Dense hazard exposition + measurements',
    'Dense introspection / rhetorical questions', 'Dense prose + embedded symbol puzzle',
    'Dialogue register / honorifics / scene shift', 'Emotional subtext + discovery + counting',
    'Ensemble dialogue / names / tactical numbers', 'Graphic exposition / white-on-dark text',
    'Illustrated character card', 'Negation + causal inference + numbers',
}
SUMMARY_NUMBERS = ('n', 'total', 'completed', 'mean', 'prose_mean', 'layout_mean', 'median_seconds', 'ci_low', 'ci_high', 'unusable', 'review_disagreements', 'failed', 'input_tokens', 'cached_input_tokens', 'output_tokens', 'reasoning_output_tokens', 'cost_n', 'cost_total_usd', 'cost_mean_usd', 'cost_mean_no_cache_usd', 'scored_cost_mean_usd', 'cost_incomplete_count')
USAGE = ('input_tokens', 'cached_input_tokens', 'cache_write_input_tokens', 'output_tokens', 'reasoning_output_tokens')
COST_NUMBERS = ('usd', 'upper_usd', 'no_cache_usd', 'uncached_input_usd', 'cached_input_usd', 'cache_write_usd', 'output_usd', 'ordinary_input_tokens')
VALUE_NUMBERS = ('n', 'mean', 'cost_mean_usd', 'cost_mean_no_cache_usd', 'unusable')
COST_STATES = {'estimated', 'lower_bound', 'unavailable'}


def canonical_hash(value):
    return hashlib.sha256(json.dumps(value, sort_keys=True, ensure_ascii=False, separators=(',', ':'), allow_nan=False).encode()).hexdigest()


def integrity_binding(raw):
    """Digest publication-relevant scalars without timestamps or private payloads.

    The integrity verifier calls this on the same results snapshot. Reordering
    records or regenerating generated_at does not invalidate an otherwise equal
    snapshot; changed scores, costs, source hashes or audit flags always do.
    This function returns only a digest, never source or reviewer prose.
    """
    def take(value, keys):
        value = value or {}
        return {key: value.get(key) for key in keys}
    def ordered(rows, keys):
        return sorted(rows, key=lambda row: tuple(str(row.get(k) or '') for k in keys))
    runs = []
    for r in raw.get('runs', []):
        item = take(r, ('configuration_id', 'source_id', 'status', 'elapsed_seconds',
            'judge_disagreement', 'needs_adjudication', 'adjudication_resolved',
            'tool_call_count', 'delegation_observed'))
        item['scores'] = take(r.get('scores'), SCORES)
        item['usage'] = take(r.get('usage'), USAGE)
        cost = r.get('cost') or {}
        item['cost'] = take(cost, (*COST_NUMBERS, 'status'))
        item['cost']['rates_per_million'] = take(cost.get('rates_per_million'), ('input', 'cached_input', 'cache_write', 'output'))
        item['reviews'] = []
        for v in r.get('reviews', []):
            judge = take(v, (*SCORES, 'judge', 'coverage_percent', 'usable', 'confidence', 'review_version'))
            judge['severity_counts'] = dict(collections.Counter(i.get('severity') for i in v.get('issues', [])))
            item['reviews'].append(judge)
        item['reviews'] = ordered(item['reviews'], ('judge',))
        item['review_statuses'] = ordered([take(v, ('judge', 'status')) for v in r.get('review_statuses', [])], ('judge', 'status'))
        context = r.get('context_policy_review_required')
        item['context_policy_review_required'] = len(context) if isinstance(context, list) else context
        item['context_audit_counts'] = dict(collections.Counter(v.get('category') for v in r.get('context_policy_deviations', [])))
        item['adjudication_recorded'] = bool(r.get('adjudication'))
        item['adjudication'] = take(r.get('adjudication'), ('verdict', 'score_override_recommended'))
        runs.append(item)
    value = raw.get('value_comparison') or {}
    projection = {
        'binding_version': 1, 'status': raw.get('status'), 'review_version': raw.get('review_version'),
        'methodology_sha256': canonical_hash(raw.get('methodology')),
        'pricing_sha256': canonical_hash(raw.get('pricing')),
        'sources': ordered([take(s, ('id', 'category', 'is_prose', 'sha256')) for s in raw.get('sources', [])], ('id',)),
        'configurations': ordered([take(c, ('id', 'model', 'effort')) for c in raw.get('configurations', [])], ('id',)),
        'runs': ordered(runs, ('configuration_id', 'source_id')),
        'summary': ordered([take(s, ('configuration_id', *SUMMARY_NUMBERS)) for s in raw.get('summary', [])], ('configuration_id',)),
        'value_comparison': {
            **take(value, ('n', 'total', 'provisional')),
            'common_source_ids': sorted(value.get('common_source_ids', [])),
            'rows': ordered([take(v, ('configuration_id', *VALUE_NUMBERS, 'cost_status', 'cost_eligible', 'eligible', 'frontier')) for v in value.get('rows', [])], ('configuration_id',)),
            'recommendations': ordered([take(v, ('configuration_id', 'minimum_score', 'mean', 'cost_mean_usd')) for v in value.get('recommendations', [])], ('minimum_score', 'configuration_id')),
        },
        'paired_comparisons': ordered([{**take(p, ('configuration_id', 'reference_configuration_id', 'other_configuration_id', 'n', 'mean_difference', 'ci_low', 'ci_high')),
            'source_ids': sorted(p.get('source_ids', []))} for p in raw.get('paired_comparisons', [])], ('configuration_id', 'reference_configuration_id', 'other_configuration_id')),
    }
    return canonical_hash(projection)


def numeric(value, low=0, high=None):
    if value is None:
        return None
    if isinstance(value, bool) or not isinstance(value, (int, float)) or not math.isfinite(value) or value < low or (high is not None and value > high):
        raise ValueError('Invalid numeric field; publication aborted')
    return value


def boolean(value):
    if value is None or isinstance(value, bool):
        return value
    raise ValueError('Invalid boolean field; publication aborted')


def enum(value, choices, nullable=False):
    if nullable and value is None:
        return None
    if not isinstance(value, str) or value not in choices:
        raise ValueError('Unreviewed enum value; publication aborted')
    return value


def pattern(value, expression):
    if not isinstance(value, str) or not re.fullmatch(expression, value):
        raise ValueError('Unexpected identifier or timestamp; publication aborted')
    return value


def numbers(obj, keys, low=0, high=None):
    obj = obj or {}
    return {key: numeric(obj.get(key), low, high) for key in keys}


def scores(obj):
    return numbers(obj, SCORES, 1, 10) if obj else None


def safe_cost(raw, pricing):
    raw = raw or {}
    status = enum(raw.get('status', 'unavailable'), COST_STATES)
    out = {'status': status, **numbers(raw, COST_NUMBERS)}
    out['rates_per_million'] = numbers(raw.get('rates_per_million'), ('input', 'cached_input', 'cache_write', 'output'))
    out['pricing_date'] = pricing['date']
    out['source_url'] = pricing['source_url']
    out['notes'] = ([] if status == 'estimated' else [
        'Incomplete usage, request-level pricing information, or delegated usage makes this a lower bound.'
        if status == 'lower_bound' else 'A matching published rate and recorded usage are required; unavailable does not mean zero.'
    ])
    return out


def review(raw):
    severity = collections.Counter()
    for issue in raw.get('issues', []):
        level = enum(issue.get('severity'), {'critical', 'major', 'minor'})
        severity[level] += 1
    return {
        'judge': enum(raw.get('judge'), JUDGES),
        **numbers(raw, SCORES, 1, 10),
        'coverage_percent': numeric(raw.get('coverage_percent'), 0, 100),
        'usable': boolean(raw.get('usable')),
        'confidence': enum(raw.get('confidence'), {'low', 'medium', 'high'}, nullable=True),
        'review_version': numeric(raw.get('review_version'), 1),
        'severity_counts': {key: severity[key] for key in ('critical', 'major', 'minor')},
    }


def adjudication_needed(run):
    reviews = run['reviews']
    critical = any(r['severity_counts']['critical'] > 0 for r in reviews)
    disagreement = (len(reviews) == 2 and all(r['overall'] is not None for r in reviews)
        and abs(reviews[0]['overall'] - reviews[1]['overall']) >= 1.5)
    return bool(run['needs_adjudication'] or critical or disagreement)


def adjudication_valid(run):
    return bool(run['adjudication_recorded'] and run['adjudication_resolved'] is True
        and run['adjudication_verdict'] in ('supported', 'partly_supported')
        and run['score_override_recommended'] is False)


def audit_ready(audit, sources, raw):
    source_hashes = {s['id']: s['sha256'] for s in sources}
    checks = {s.get('id'): s for s in audit.get('source_hash_checks', [])}
    return bool(audit.get('ok') is True and audit.get('complete') is True
        and audit.get('expected_runs') == 276 and audit.get('pending_count') == 0
        and audit.get('status_counts', {}).get('completed') == 276
        and not audit.get('errors') and not audit.get('incomplete_runs')
        and audit.get('results_numeric_sha256') == integrity_binding(raw)
        and len(audit.get('source_hash_checks', [])) == len(source_hashes) and set(checks) == set(source_hashes)
        and all(s.get('original_unchanged') is True and s.get('frozen_unchanged') is True
            and s.get('sha256') == source_hashes[sid]
            and s.get('original_sha256') == source_hashes[sid]
            and s.get('frozen_sha256') == source_hashes[sid] for sid, s in checks.items()))


def sanitize(raw, curation, audit=None):
    """Return only approved scalar data; no model-authored prose is copied."""
    if canonical_hash(raw.get('methodology')) != curation.get('methodology_input_sha256'):
        raise ValueError('Methodology changed since curation; review the publication metadata again')
    if canonical_hash(raw.get('pricing')) != curation.get('pricing_input_sha256'):
        raise ValueError('Pricing changed since curation; review the publication metadata again')
    if raw.get('review_version') != curation.get('review_version'):
        raise ValueError('Review version changed since curation')
    methods = curation['methodology']
    pricing = curation['pricing']
    configs = []
    for c in raw.get('configurations', []):
        model, effort = enum(c.get('model'), MODELS), enum(c.get('effort'), EFFORTS)
        cid = model + '--' + effort
        if c.get('id') != cid or (model == 'gpt-6-luna' and effort == 'ultra'):
            raise ValueError('Unexpected configuration identity')
        configs.append({'id': cid, 'model': model, 'effort': effort})
    config_ids = {c['id'] for c in configs}
    if len(configs) != 23 or len(config_ids) != 23:
        raise ValueError('Publication must retain all 23 configurations')
    sources = []
    for s in raw.get('sources', []):
        sources.append({'id': pattern(s.get('id'), r'V\d{2}-S\d{3}'),
            'category': enum(s.get('category'), CATEGORIES),
            'is_prose': boolean(s.get('is_prose')),
            'sha256': pattern(s.get('sha256'), r'[a-f0-9]{64}')})
    source_ids = {s['id'] for s in sources}
    if len(sources) != 12 or len(source_ids) != 12 or sum(s['is_prose'] is True for s in sources) != 9:
        raise ValueError('Publication must retain the 12 captures, including nine prose captures')
    output_runs, pairs = [], set()
    for r in raw.get('runs', []):
        cid, sid = enum(r.get('configuration_id'), config_ids), enum(r.get('source_id'), source_ids)
        if (cid, sid) in pairs:
            raise ValueError('Duplicate capture/configuration pair')
        pairs.add((cid, sid))
        out = {'id': cid + '/' + sid, 'configuration_id': cid, 'source_id': sid,
            'status': enum(r.get('status'), STATES), 'scores': scores(r.get('scores')),
            'elapsed_seconds': numeric(r.get('elapsed_seconds')),
            'usage': numbers(r.get('usage'), USAGE),
            'cost': safe_cost(r.get('cost'), pricing),
            'reviews': [review(v) for v in r.get('reviews', [])],
            'review_statuses': [{'judge': enum(v.get('judge'), JUDGES), 'status': enum(v.get('status'), STATES)} for v in r.get('review_statuses', [])],
            'judge_disagreement': numeric(r.get('judge_disagreement'), 0, 9),
            'needs_adjudication': boolean(r.get('needs_adjudication')),
            'adjudication_resolved': boolean(r.get('adjudication_resolved')),
            'context_policy_review_required': bool(r['context_policy_review_required']) if isinstance(r.get('context_policy_review_required'), list) else boolean(r.get('context_policy_review_required')),
            'tool_call_count': numeric(r.get('tool_call_count')),
            'delegation_observed': boolean(r.get('delegation_observed')),
        }
        categories = collections.Counter(enum(v.get('category'), {'generic_installed_skill_document_read'}) for v in r.get('context_policy_deviations', []))
        out['context_audit_counts'] = dict(categories)
        adjudication = r.get('adjudication') or {}
        out['adjudication_recorded'] = bool(adjudication)
        out['score_override_recommended'] = boolean(adjudication.get('score_override_recommended'))
        out['adjudication_verdict'] = enum(adjudication.get('verdict'),
            {'supported', 'partly_supported', 'unsupported', 'uncertain'}, nullable=True)
        output_runs.append(out)
    if pairs != {(c, s) for c in config_ids for s in source_ids}:
        raise ValueError('Publication must retain all 276 capture/configuration cells')
    summaries = [{'configuration_id': enum(s.get('configuration_id'), config_ids), **numbers(s, SUMMARY_NUMBERS)} for s in raw.get('summary', [])]
    if len(summaries) != 23 or {s['configuration_id'] for s in summaries} != config_ids:
        raise ValueError('Publication must retain every configuration summary')
    comparison = raw.get('value_comparison') or {}
    value = {'common_source_ids': [enum(s, source_ids) for s in comparison.get('common_source_ids', [])],
        'n': numeric(comparison.get('n')), 'total': numeric(comparison.get('total')),
        'provisional': boolean(comparison.get('provisional')), 'rows': [], 'recommendations': [],
        'method': 'Compare identical doubly graded captures. Recommendations require complete estimated costs and usable translations from both judges. Scores are AI judgments.'}
    for v in comparison.get('rows', []):
        value['rows'].append({'configuration_id': enum(v.get('configuration_id'), config_ids), **numbers(v, VALUE_NUMBERS),
            'cost_status': enum(v.get('cost_status'), COST_STATES),
            **{key: boolean(v.get(key)) for key in ('cost_eligible', 'eligible', 'frontier')}})
    for r in comparison.get('recommendations', []):
        value['recommendations'].append({'configuration_id': enum(r.get('configuration_id'), config_ids, nullable=True),
            'minimum_score': numeric(r.get('minimum_score'), 1, 10), 'mean': numeric(r.get('mean'), 1, 10),
            'cost_mean_usd': numeric(r.get('cost_mean_usd'))})
    reasons = []
    if raw.get('status') not in ('complete', 'completed', 'finished'):
        reasons.append('The source study is not marked complete.')
    if any(r['status'] != 'completed' or not r['scores'] or any(v is None for v in r['scores'].values()) for r in output_runs):
        reasons.append('All 276 translations need complete dimensional scores.')
    if any(len(r['reviews']) != 2 or {v['judge'] for v in r['reviews']} != JUDGES or any(any(v[k] is None for k in SCORES) or v['usable'] is None for v in r['reviews']) for r in output_runs):
        reasons.append('Both complete blind reviews are required for every translation.')
    if any(v['review_version'] != curation['review_version'] for r in output_runs for v in r['reviews']):
        reasons.append('Every review must use the curated review protocol version.')
    if any(any(v['status'] not in ('completed', 'complete', 'success') for v in r['review_statuses']) for r in output_runs):
        reasons.append('Some judge review statuses are incomplete or failed.')
    if any(adjudication_needed(r) and not adjudication_valid(r) for r in output_runs):
        reasons.append('Flagged adjudications remain unresolved.')
    if any(r['score_override_recommended'] is True for r in output_runs):
        reasons.append('Recommended score overrides remain unresolved.')
    if any(r['context_policy_review_required'] is not False for r in output_runs):
        reasons.append('Every context audit must be explicitly complete with no unresolved findings.')
    if not audit_ready(audit or {}, sources, raw):
        reasons.append('A complete passing integrity audit bound to this numeric snapshot and source hashes is required.')
    data = {'schema_version': VERSION, 'review_version': curation['review_version'],
        'status': 'complete' if not reasons else 'partial',
        'generated_at': pattern(raw.get('generated_at'), r'\d{4}-\d{2}-\d{2}T[0-9:.+Z-]+'),
        'publication': {'ready': not reasons, 'status': 'final' if not reasons else 'draft',
            'gate_reasons': reasons, 'content_policy': 'Numeric results and reviewed methodology only; source scans, translations, review quotations, commands, logs, local paths and account data are omitted.',
            'private_input_sha256': canonical_hash(raw)},
        'methodology': methods, 'sources': sources, 'configurations': configs,
        'runs': output_runs, 'summary': summaries, 'pricing': pricing, 'value_comparison': value}
    # Paired analysis is optional until the final matrix is complete. Keys are
    # explicitly selected below rather than copying arbitrary analyst payloads.
    data['paired_comparisons'] = []
    for pair in raw.get('paired_comparisons', []):
        safe = {}
        for key in ('configuration_id', 'reference_configuration_id', 'other_configuration_id'):
            if key in pair:
                safe[key] = enum(pair[key], config_ids)
        for key in ('n', 'mean_difference', 'ci_low', 'ci_high'):
            if key in pair:
                safe[key] = numeric(pair[key], -10 if key != 'n' else 0, 10 if key != 'n' else None)
        safe['source_ids'] = [enum(sid, source_ids) for sid in pair.get('source_ids', [])]
        safe['interpretation'] = 'Exploratory paired capture bootstrap; reference selected after observing this sample, with no multiplicity adjustment.'
        data['paired_comparisons'].append(safe)
    privacy_check(json.dumps(data, ensure_ascii=False))
    return data


def privacy_check(text):
    """Defense in depth after structural allowlisting, not a prose sanitizer."""
    patterns = (r'/(?:Users|home)/[^\s/]+/', r'file://[/A-Za-z]', r'[A-Za-z]:\\Users\\',
        r'(?<![\w.-])[\w.+-]+@[\w.-]+\.[A-Za-z]{2,}', r'\bsk-[A-Za-z0-9_-]{16,}',
        r'[\u3040-\u30ff\u3400-\u9fff]', r'data:image/[a-z0-9.+-]+;base64,')
    if any(re.search(p, text) for p in patterns):
        raise ValueError('Private-content pattern found; no package was written')


def write_package(data, destination, *, preview=False, schema=None, extra_source_files=()):
    if not data['publication']['ready'] and not preview:
        raise ValueError('Final package refused: ' + ' '.join(data['publication']['gate_reasons']))
    if preview:
        data = json.loads(json.dumps(data))
        data['publication'].update(ready=False, status='draft')
        data['publication']['gate_reasons'].append('Local preview; a final publication package has not been requested.')
    destination = Path(destination).absolute()
    if destination.exists() or destination.is_symlink():
        raise ValueError('Choose a new staging directory; existing output is never overwritten')
    assets = {}
    for public_name, work_name in [('translation-prompt.txt', 'publication-translation-prompt.txt'), ('grading-rubric.md', 'publication-grading-rubric.md')]:
        assets[public_name] = next((p for p in (BASE / work_name, BASE / public_name) if p.is_file()), None)
    for name in ('render_publication.py', 'pricing.py', 'publication-methodology.json', 'test_publication.py', 'test_pricing.py'):
        if not (BASE / name).is_file():
            raise ValueError('A required publication source file is missing')
    if any(p is None for p in assets.values()):
        raise ValueError('A required prompt or rubric file is missing')
    spec = importlib.util.spec_from_file_location('publication_report', BASE / 'render_publication.py')
    renderer = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(renderer)
    files = {'results.json': json.dumps(data, indent=2, ensure_ascii=False, allow_nan=False) + '\n',
        'report.html': renderer.render(data), 'README.md': renderer.readme(data),
        'METHODS.md': methods_markdown(data), 'SCHEMA.md': schema or SCHEMA}
    for name in ('prepare_publication.py', 'render_publication.py', 'pricing.py', 'publication-methodology.json', 'test_publication.py', 'test_pricing.py', *extra_source_files):
        files[name] = (BASE / name).read_text()
    for name, path in assets.items():
        files[name] = path.read_text()
    for name, contents in files.items():
        privacy_check(contents)
    files['MANIFEST.json'] = json.dumps({'schema_version': 1, 'publication_status': data['publication']['status'],
        'files': {name: hashlib.sha256(text.encode()).hexdigest() for name, text in files.items()}}, indent=2) + '\n'
    destination.parent.mkdir(parents=True, exist_ok=True)
    temp = Path(tempfile.mkdtemp(prefix='.publication-', dir=destination.parent))
    try:
        for name, text in files.items():
            (temp / name).write_text(text)
        os.rename(temp, destination)
    finally:
        if temp.exists():
            shutil.rmtree(temp)
    return destination


def methods_markdown(data):
    blocks = ['# Methods', '', 'This package omits the licensed source images, full translations, and quoted reviewer evidence. Source IDs and hashes identify the frozen private corpus; they do not supply access to it.', '']
    for key in ('sample', 'cohorts', 'conditions', 'scoring', 'amendment', 'limitations', 'intervals', 'timing', 'ultra'):
        blocks.extend(['## ' + key.replace('_', ' ').capitalize(), '', str(data['methodology'].get(key, 'Not recorded.')), ''])
    blocks += ['## Cost estimates', '', data['pricing']['method'], '', data['pricing']['limitations'], '',
        'Rates: [' + data['pricing']['date'] + ' Standard API pricing](' + data['pricing']['source_url'] + ').', '',
        '## Reproduce the report', '', 'Run `python3 render_publication.py --results results.json --output report.html`. Python 3.10 or newer is sufficient; the report needs no network requests or third-party JavaScript.', '',
        'The included prompt, rubric, cost calculations and schema document the experiment. Exact translation replication requires lawful access to the same private corpus and matching service/runtime conditions. Backend model routing and unexposed child usage cannot be independently reconstructed from this package.', '']
    return '\n'.join(blocks)


SCHEMA = '''# Published result schema

`results.json` retains all 23 model/effort configurations and all 276 capture/configuration cells. Null means unavailable, never zero.

- `publication`: final-readiness flag and fixed gate reasons. Draft output cannot be presented as a completed benchmark.
- `sources`: opaque IDs, generic capture categories, prose/layout flags, and frozen source SHA-256 hashes. No source bytes or text.
- `runs`: dimensional scores, two reviewers' numerical ratings, coverage, usability, confidence and issue-severity counts; observable tool/delegation flags; token usage; API-equivalent cost status and components. Reviewer prose and commands are excluded.
- `summary`: supplied aggregate means, intervals, capture counts, timings, token totals and estimated costs. `summary.unusable` counts captures that BOTH reviewers marked unusable.
- `pricing`: curated published USD rates, snapshot date, method and limitations. Reasoning is already included in output tokens. Missing delegated usage can make an estimate a lower bound.
- `value_comparison`: the common doubly graded capture set, costs, eligibility and recommendations. `value_comparison.rows[].unusable` counts matched captures that EITHER reviewer marked unusable, a stricter eligibility criterion than `summary.unusable`. Lower bounds and unusable translations do not qualify for a cheapest-option recommendation.

The bundled `pricing.py` exposes `estimate(model, usage, *, delegated=False, incomplete_attempt_usage=False)`, `summarize_cost(cells)` and `value_comparison(configs, sources, runs)`. Read each function signature before applying it to another schema. It does not contact a provider. The report renderer consumes this published schema directly.

`prepare_publication.py` is a packaging tool, not a network publisher. Its default final gate requires the full scored matrix, both reviews at the curated protocol version, explicit completed context audits, and supported adjudication evidence for critical issues or judge disagreement of at least 1.5 points. Outstanding score overrides block completion. The integrity report must match both the actual source hashes and `integrity_binding(raw_results)`, a canonical digest of publication-relevant numeric, enum and hash fields that excludes generation timestamps and private prose. A reviewed metadata sidecar pins the method and pricing descriptions; changed metadata must be reviewed again. `--preview` only creates a marked local draft. Existing directories are never overwritten.
'''


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--results', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--curation', type=Path, default=BASE / 'publication-methodology.json')
    parser.add_argument('--integrity-audit', type=Path)
    parser.add_argument('--preview', action='store_true')
    args = parser.parse_args()
    try:
        data = sanitize(json.loads(args.results.read_text()), json.loads(args.curation.read_text()),
            json.loads(args.integrity_audit.read_text()) if args.integrity_audit else None)
        print(write_package(data, args.output, preview=args.preview))
    except (OSError, ValueError, KeyError, TypeError) as error:
        parser.exit(1, f'Publication staging failed: {error}\n')


if __name__ == '__main__':
    main()
