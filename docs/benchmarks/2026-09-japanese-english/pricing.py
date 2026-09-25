"""Standard API-equivalent estimates from observed CLI usage, never actual bills."""
from __future__ import annotations
from statistics import mean

PRICING_DATE = '2026-09-24'
SOURCE_URL = 'https://developers.openai.com/api/docs/pricing'
RATES = {
    'gpt-6-astra': dict(input=10.0, cached_input=1.0, cache_write=12.5, output=50.0),
    'gpt-6-sol': dict(input=2.0, cached_input=.2, cache_write=2.5, output=10.0),
    'gpt-5.6-terra': dict(input=2.0, cached_input=.2, cache_write=2.5, output=12.0),
    'gpt-6-luna': dict(input=.1, cached_input=.01, cache_write=.125, output=.5),
}
PRICING = {
    'date': PRICING_DATE, 'currency': 'USD', 'tier': 'Standard',
    'rates': RATES, 'source_url': SOURCE_URL,
    'sources': [SOURCE_URL,
        'https://developers.openai.com/api/docs/models/gpt-5.6-terra',
        'https://developers.openai.com/api/docs/models/gpt-6-astra',
        'https://developers.openai.com/api/docs/guides/prompt-caching',
        'https://developers.openai.com/api/docs/guides/agents-api/observability'],
    'method': 'Apply published Standard USD rates per million tokens to the observed CLI usage across all attempts. Ordinary input = total input minus cached reads minus cache writes. Output already includes reasoning; image input is already included in input usage. Neither is charged twice. No-cache sensitivity prices all input as ordinary input with caching disabled.',
    'limitations': 'Counterfactual API-equivalent token cost, not an API bill or a Codex subscription charge. Includes Codex instructions and tool-loop context; a lean API translator may cost less. Excludes grading, local compute, taxes, regional uplifts and separately charged hosted tools. Requested model rates are used because backend routing is not independently observable. Missing delegated usage or request-level long-context detail is labeled as a lower bound and excluded from value recommendations. Cache reuse in production can differ. Captures may contain two printed pages; cost per 100 captures is an extrapolation, not per 100 printed pages.',
    'long_context_threshold_input_tokens': 272000,
    'long_context_multipliers': {'input': 2, 'cached_input': 2, 'cache_write': 2, 'output': 1.5},
}

def estimate(model, usage, *, delegated=False, incomplete_attempt_usage=False):
    base = {'status': 'unavailable', 'usd': None, 'upper_usd': None,
            'no_cache_usd': None, 'notes': [], 'pricing_date': PRICING_DATE,
            'source_url': SOURCE_URL, 'rates_per_million': RATES.get(model)}
    if model not in RATES:
        base['notes'].append('No verified Standard rate for this requested model.')
        return base
    fields = ('input_tokens', 'cached_input_tokens', 'cache_write_input_tokens', 'output_tokens')
    if any(k not in usage for k in fields):
        base['notes'].append('Complete token usage, including cache reads and writes, is not available.')
        return base
    if any(isinstance(usage[k], bool) or not isinstance(usage[k], int) or usage[k] < 0 for k in fields):
        base['notes'].append('Token usage is invalid; no cost is inferred.')
        return base
    total, cached, writes, output = (usage[k] for k in fields)
    ordinary = total - cached - writes
    if ordinary < 0:
        base['notes'].append('Cache token counts exceed total input; no cost is inferred.')
        return base
    rates = RATES[model]
    components = {
        'uncached_input_usd': ordinary * rates['input'] / 1e6,
        'cached_input_usd': cached * rates['cached_input'] / 1e6,
        'cache_write_usd': writes * rates['cache_write'] / 1e6,
        'output_usd': output * rates['output'] / 1e6,
    }
    base.update(components)
    base.update(status='estimated', usd=sum(components.values()),
                no_cache_usd=(total * rates['input'] + output * rates['output']) / 1e6,
                ordinary_input_tokens=ordinary)
    if total > PRICING['long_context_threshold_input_tokens']:
        # CLI totals can span multiple requests; total > threshold does not
        # establish that any individual request exceeded the threshold.
        base['status'] = 'lower_bound'
        base['upper_usd'] = 2 * sum(v for k, v in components.items() if k != 'output_usd') + 1.5 * components['output_usd']
        base['notes'].append('Aggregate input exceeds 272K, but request-level lengths are unavailable. Short-context cost is the lower bound; upper bound applies long-context rates to all observed usage.')
    if delegated or incomplete_attempt_usage:
        base['status'] = 'lower_bound'
        base['upper_usd'] = None
        if delegated:
            base['notes'].append('Delegation occurred; separate child-model usage is not fully exposed. This prices only observed usage and is not eligible for value recommendations.')
        if incomplete_attempt_usage:
            base['notes'].append('At least one attempt lacks complete usage; unreported tokens cannot be priced.')
    return base

def summarize_cost(cells):
    observed = [r for r in cells if r['cost']['usd'] is not None]
    complete = [r for r in observed if r['status'] == 'completed']
    scored = [r for r in complete if r['scores']]
    return {
        'cost_n': len(complete),
        'cost_total_usd': sum(r['cost']['usd'] for r in observed) if observed else None,
        'cost_mean_usd': mean(r['cost']['usd'] for r in complete) if complete else None,
        'cost_mean_no_cache_usd': mean(r['cost']['no_cache_usd'] for r in complete) if complete else None,
        'scored_cost_mean_usd': mean(r['cost']['usd'] for r in scored) if scored else None,
        'cost_incomplete_count': sum(r['cost']['status'] != 'estimated' for r in cells if r['status'] not in ('pending', 'running')),
    }

def value_comparison(configs, sources, runs):
    by_config = {c['id']: {r['source_id']: r for r in runs if r['configuration_id'] == c['id']} for c in configs}
    common = sorted(s['id'] for s in sources if all(
        by_config[c['id']][s['id']]['status'] == 'completed' and by_config[c['id']][s['id']]['scores']
        for c in configs))
    rows = []
    for c in configs:
        cells = [by_config[c['id']][sid] for sid in common]
        cost_ok = bool(cells) and all(r['cost']['status'] == 'estimated' for r in cells)
        any_cost = bool(cells) and all(r['cost']['usd'] is not None for r in cells)
        unusable = sum(not all(v['usable'] for v in r['reviews']) for r in cells)
        rows.append({
            'configuration_id': c['id'], 'n': len(cells),
            'mean': mean(r['scores']['overall'] for r in cells) if cells else None,
            'cost_mean_usd': mean(r['cost']['usd'] for r in cells) if any_cost else None,
            'cost_mean_no_cache_usd': mean(r['cost']['no_cache_usd'] for r in cells) if any_cost else None,
            'unusable': unusable,
            'cost_status': 'estimated' if cost_ok else 'lower_bound' if any_cost else 'unavailable',
            'cost_eligible': cost_ok, 'eligible': cost_ok and not unusable, 'frontier': False,
        })
    eligible = [r for r in rows if r['eligible']]
    for row in eligible:
        row['frontier'] = not any(other['mean'] >= row['mean'] and other['cost_mean_usd'] <= row['cost_mean_usd']
            and (other['mean'] > row['mean'] or other['cost_mean_usd'] < row['cost_mean_usd']) for other in eligible)
    recommendations = []
    for threshold in (7, 8, 8.5, 9, 9.5):
        qualified = [r for r in eligible if r['mean'] >= threshold and not r['unusable']]
        best = min(qualified, key=lambda r: r['cost_mean_usd']) if qualified else None
        recommendations.append({'minimum_score': threshold, **({k: best[k] for k in ('configuration_id', 'mean', 'cost_mean_usd')} if best else {'configuration_id': None})})
    return {'common_source_ids': common, 'n': len(common), 'total': len(sources),
            'provisional': len(common) != len(sources), 'rows': rows, 'recommendations': recommendations,
            'method': 'Compare the same doubly graded captures across every configuration. Value suggestions require the selected average quality and both judges marking every included capture usable; incomplete cost estimates are excluded. Scores are AI judgments, not human-validated accuracy. Partial comparisons remain provisional.'}
