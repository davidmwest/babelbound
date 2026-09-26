#!/usr/bin/env python3
"""Render a standalone, numeric-only publication report from sanitized results."""
from __future__ import annotations
import argparse
import html
import json
import math
import statistics
from pathlib import Path

VERSION = '1.3.2'
DIMENSIONS = ('accuracy', 'completeness', 'names_numbers', 'fluency', 'overall')
DELIVERY = ('english_translation', 'service_error', 'non_english_transcription', 'other_failure')
OLLAMA_MODELS = ('deepseek-v4.1-flash:cloud', 'gemma4:31b-cloud', 'gemma4:cloud')


def numeric(value):
    return value if isinstance(value, (int, float)) and not isinstance(value, bool) and math.isfinite(value) else None


def mean(values):
    values = [v for v in values if numeric(v) is not None]
    return sum(values) / len(values) if values else None


def records(value):
    return [v for v in value if isinstance(v, dict)] if isinstance(value, list) else []


def metric_fields(item, fields):
    return {key: numeric(item.get(key)) for key in fields}


def ollama_pricing(value):
    """Keep only public tariff fields, including a single-rate model's schedule."""
    value = value if isinstance(value, dict) else {}
    result = {k: value[k] for k in ('date', 'schedule', 'limitations') if isinstance(value.get(k), str)}
    if value.get('source_url') == 'https://ollama.com/pricing':
        result['source_url'] = value['source_url']
    for period in ('peak', 'off_peak'):
        if isinstance(value.get(period), dict):
            result[period] = metric_fields(value[period], ('input', 'cached_input', 'output'))
    return result


def cohort(configuration):
    """Use transport metadata, with model-name fallback for older publications."""
    explicit = configuration.get('cohort')
    if isinstance(explicit, str) and explicit:
        return explicit
    model = str(configuration.get('model', '')).lower()
    return 'ollama-cloud' if model.startswith('deepseek-') else 'ollama-cloud-expanded' if model.startswith('gemma4') else 'gemini-web' if model.startswith('gemini-') else 'codex-cli'


def prepare(data):
    """Project only report fields; never embed arbitrary input records or review prose."""
    configs = []
    for c in records(data.get('configurations')):
        config = {key: str(c.get(key, '')) for key in ('id', 'model', 'effort', 'model_display')}
        config['cohort'] = cohort(c)
        if isinstance(c.get('requested_think'), (bool, str)):
            config['requested_think'] = c['requested_think']
        configs.append(config)
    sources = [{key: s.get(key) for key in ('id', 'category', 'is_prose', 'sha256')} for s in records(data.get('sources'))]
    expanded_ids = {c['id'] for c in configs if c['cohort'] == 'ollama-cloud-expanded'}
    runs = []
    for r in records(data.get('runs')):
        reviews = [{**metric_fields(v, (*DIMENSIONS, 'coverage_percent')), 'judge': str(v.get('judge', '')), 'usable': v.get('usable') if isinstance(v.get('usable'), bool) else None} for v in records(r.get('reviews'))]
        cost = r.get('cost') if isinstance(r.get('cost'), dict) else {}
        if r.get('configuration_id') in expanded_ids and r.get('status') == 'interrupted':
            cost = {}  # An interrupted native stream has no final usage receipt.
        runs.append({'source_id': r.get('source_id'), 'configuration_id': r.get('configuration_id'), 'status': str(r.get('status', 'pending')), 'scores': metric_fields(r.get('scores') or {}, DIMENSIONS), 'reviews': reviews, 'review_statuses': [{'judge': str(v.get('judge', '')), 'status': str(v.get('status', 'pending'))} for v in records(r.get('review_statuses'))], 'elapsed_seconds': numeric(r.get('elapsed_seconds')), 'cost': {**metric_fields(cost, ('usd', 'no_cache_usd')), 'status': str(cost.get('status', 'unavailable'))}})
    summaries = {s.get('configuration_id'): s for s in records(data.get('summary'))}
    rows = []
    for c in configs:
        s = summaries.get(c['id'], {})
        rr = [r for r in runs if r['configuration_id'] == c['id']]
        graded = [r for r in rr if r['scores']['overall'] is not None]
        coverage = [mean(v.get('coverage_percent') for v in r['reviews']) for r in graded]
        priced = [r for r in rr if r['cost']['usd'] is not None]
        costs = {r['cost']['status'] for r in priced}
        cost_status = s.get('cost_status') or ('lower_bound' if 'lower_bound' in costs else 'incomplete' if priced and (len(priced) < len([r for r in rr if r['status'] == 'completed'])) else 'estimated' if costs == {'estimated'} else 'unavailable')
        row = {**c, **metric_fields(s, ('mean', 'prose_mean', 'layout_mean', 'median_seconds', 'cost_mean_usd', 'cost_mean_no_cache_usd', 'ci_low', 'ci_high')), 'n': numeric(s.get('n')) if numeric(s.get('n')) is not None else len(graded), 'total': numeric(s.get('total')) if numeric(s.get('total')) is not None else len(sources), 'unusable': numeric(s.get('unusable')), 'failed': numeric(s.get('failed')), 'cost_n': numeric(s.get('cost_n')), 'cost_status': str(cost_status), 'coverage_percent': mean(coverage), 'coverage_n': sum(v is not None for v in coverage)}
        row.update({key: mean(r['scores'][key] for r in graded) for key in DIMENSIONS[:-1]})
        row['both_reviewers_usable'] = sum(len(r['reviews']) == 2
            and len({v['judge'] for v in r['reviews']}) == 2
            and all(v['usable'] is True for v in r['reviews']) for r in graded)
        if c['cohort'] == 'ollama-cloud-expanded':
            timings = [r['elapsed_seconds'] for r in rr if r['status'] == 'completed'
                and numeric(r['elapsed_seconds']) is not None and r['elapsed_seconds'] >= 0]
            interrupted = [r for r in rr if r['status'] == 'interrupted']
            censored = [r['elapsed_seconds'] for r in interrupted
                if numeric(r['elapsed_seconds']) is not None and r['elapsed_seconds'] >= 0]
            row.update(median_seconds=statistics.median(timings) if timings else None,
                mean_seconds=mean(timings), max_seconds=max(timings) if timings else None,
                timing_n=len(timings), interrupted=len(interrupted),
                interrupted_elapsed_seconds_max=max(censored) if censored else None)
            if interrupted:
                row.update(cost_mean_usd=None, cost_mean_no_cache_usd=None,
                    cost_n=len(priced), cost_status='unavailable')
        if isinstance(s.get('delivery_counts'), dict):
            row['delivery_counts'] = metric_fields(s['delivery_counts'], DELIVERY)
            row.update(metric_fields(s, ('english_translation_n', 'english_translation_mean')))
        rows.append(row)
    value = data.get('value_comparison') if isinstance(data.get('value_comparison'), dict) else {}
    value_rows = [{**metric_fields(v, ('n', 'mean', 'cost_mean_usd', 'cost_mean_no_cache_usd', 'unusable')), 'configuration_id': v.get('configuration_id'), 'cost_status': str(v.get('cost_status', 'unavailable')), 'eligible': v.get('eligible') is True, 'cost_eligible': v.get('cost_eligible') is True} for v in records(value.get('rows'))]
    methodology = data.get('methodology') if isinstance(data.get('methodology'), dict) else {}
    methods = {key: value for key, value in methodology.items() if key in ('direction', 'sample', 'cohorts', 'conditions', 'scoring', 'amendment', 'limitations', 'intervals', 'timing', 'ultra', 'deepseek', 'ollama_expanded', 'native_controls', 'grading_batches', 'transports', 'cli_versions', 'weights', 'judges', 'planned_captures', 'planned_configurations', 'planned_translations', 'prompt_sha256')}
    expected = len(configs) * len(sources)
    pairs = {(r['source_id'], r['configuration_id']): r for r in runs}
    valid = lambda r: (r['status'] == 'completed' or (r['status'] == 'interrupted' and r['configuration_id'] in expanded_ids)) and all(numeric(r['scores'].get(k)) is not None and 1 <= r['scores'][k] <= 10 for k in DIMENSIONS) and len(r['reviews']) == 2 and len({v['judge'] for v in r['reviews']}) == 2 and all(all(numeric(v.get(k)) is not None and 1 <= v[k] <= 10 for k in DIMENSIONS) for v in r['reviews']) and all(v['status'] in ('completed', 'complete', 'success') for v in r['review_statuses'])
    matrix_complete = expected > 0 and all((s['id'], c['id']) in pairs and valid(pairs[(s['id'], c['id'])]) for s in sources for c in configs)
    publication = data.get('publication') if isinstance(data.get('publication'), dict) else {}
    final = publication.get('ready') is True and matrix_complete and expected == methodology.get('planned_translations', expected)
    pricing = data.get('pricing') if isinstance(data.get('pricing'), dict) else {}
    deepseek_pricing = ollama_pricing(data.get('deepseek_pricing'))
    ep = data.get('ollama_expanded_pricing') if isinstance(data.get('ollama_expanded_pricing'), dict) else {}
    expanded_models = {c['model'] for c in configs if c['cohort'] == 'ollama-cloud-expanded'}
    expanded_pricing = {model: ollama_pricing(ep[model]) for model in OLLAMA_MODELS
        if model in expanded_models and isinstance(ep.get(model), dict)}
    openai_ids = {c['id'] for c in configs if c['cohort'] == 'codex-cli'}
    value_rows = [r for r in value_rows if r['configuration_id'] in openai_ids]
    return {'version': VERSION, 'final': final, 'gate_reasons': [v for v in publication.get('gate_reasons', []) if isinstance(v, str)], 'generated_at': str(data.get('generated_at', '')), 'status': str(data.get('status', 'unknown')), 'configurations': configs, 'sources': sources, 'runs': runs, 'rows': rows, 'methodology': methods, 'value': {'n': numeric(value.get('n')), 'total': numeric(value.get('total')), 'provisional': value.get('provisional') is not False, 'rows': value_rows}, 'pricing': {k: pricing.get(k) for k in ('date', 'currency', 'tier', 'method', 'limitations', 'rates')}, 'deepseek_pricing': deepseek_pricing, 'ollama_expanded_pricing': expanded_pricing, 'expected': expected, 'graded': sum(r['scores']['overall'] is not None for r in pairs.values())}


HTML = r'''<!doctype html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><meta name="color-scheme" content="light"><title>Japanese → English · Model benchmark</title>
<style>
:root{--paper:#f4f4ef;--ink:#202c35;--muted:#63716c;--line:#d8dfda;--accent:#17695c;--soft:#e6f1eb;--mono:ui-monospace,SFMono-Regular,Consolas,monospace}*{box-sizing:border-box}[hidden]{display:none!important}body{margin:0;background:var(--paper);color:var(--ink);font:15px/1.55 -apple-system,BlinkMacSystemFont,"Segoe UI",sans-serif}main{max-width:1480px;margin:auto;padding:38px 32px 60px}h1,h2{font-family:Georgia,serif;font-weight:500;letter-spacing:-.02em}h1{font-size:clamp(32px,4.5vw,52px);line-height:1.12;margin:20px 0}h2{font-size:27px;margin:0 0 8px}h3{font-size:15px}p{max-width:1000px}a{color:var(--accent);text-underline-offset:3px}.eyebrow{color:var(--accent);font:11px var(--mono);letter-spacing:.12em;text-transform:uppercase}.intro{font-size:17px;color:var(--muted);max-width:820px}.nav{display:flex;flex-wrap:wrap;gap:20px;font-size:13px;margin:24px 0}.banner{border:1px solid #ddc58d;background:#fff6e3;border-radius:8px;padding:15px 18px}.banner.final{background:var(--soft);border-color:#adcebc}.stats{display:grid;grid-template-columns:repeat(4,1fr);border:1px solid var(--line);border-radius:9px;overflow:hidden;margin:22px 0 36px;background:white}.stat{padding:20px;border-right:1px solid var(--line)}.stat:last-child{border:0}.stat b{display:block;font:30px Georgia,serif}.stat span,.small{font-size:12px;color:var(--muted)}section{margin-top:38px}.card{background:white;border:1px solid var(--line);border-radius:9px;overflow:hidden}.controls{display:flex;align-items:flex-end;flex-wrap:wrap;gap:15px;padding:18px;border-bottom:1px solid var(--line)}label{display:flex;flex-direction:column;gap:5px;font-size:11px;color:var(--muted);font-weight:600}input,select,button{font:inherit;color:var(--ink)}input,select{border:1px solid var(--line);border-radius:6px;padding:9px 11px;background:white;max-width:100%;font-size:13px}input[type=number]{width:100px}button{cursor:pointer}a:focus-visible,button:focus-visible,input:focus-visible,select:focus-visible,summary:focus-visible{outline:3px solid #85b4a2;outline-offset:3px}.table-wrap{overflow:auto}table{width:100%;border-collapse:collapse;font-variant-numeric:tabular-nums;font-size:12px;min-width:1100px}th,td{padding:12px;text-align:right;border-bottom:1px solid #e7ece8;white-space:nowrap}th{text-transform:none;background:#f5f8f4;font-size:11px}th:first-child,td:first-child{text-align:left}th button{border:0;padding:0;background:none;font:inherit}th[aria-sort=ascending] button:after{content:" ↑"}th[aria-sort=descending] button:after{content:" ↓"}tbody tr:hover{background:#f8faf7}.name{font:11px var(--mono);font-weight:600}.sub{display:block;margin-top:4px;font-size:10px;color:var(--muted)}.score{font-weight:700}.note{padding:13px 18px;font-size:12px;color:var(--muted);border-top:1px solid var(--line)}.recommend{padding:18px;background:var(--soft);border-bottom:1px solid var(--line)}.recommend p{margin:5px 0;font-size:13px}.plot-wrap{padding:20px 18px}.plot{width:100%;height:auto;min-height:220px;display:block}.plot text{fill:var(--muted);font:11px -apple-system,sans-serif}.legend{display:flex;flex-wrap:wrap;gap:16px;font-size:11px;color:var(--muted)}.legend i{display:inline-block;width:9px;height:9px;border-radius:50%;margin-right:6px}details>summary{cursor:pointer;padding:17px 18px;font-size:13px;color:var(--accent)}details .table-wrap{border-top:1px solid var(--line)}.empty{padding:24px;color:var(--muted);font-size:13px}.methods{padding:20px 24px;display:grid;grid-template-columns:1fr 1fr;gap:5px 26px}.methods p{font-size:13px;color:var(--muted);margin-top:5px;white-space:pre-wrap;overflow-wrap:anywhere}.methods h3{margin-bottom:5px}footer{margin-top:30px;border-top:1px solid var(--line);padding-top:18px;font-size:12px;color:var(--muted)}.sr{position:absolute;width:1px;height:1px;overflow:hidden;clip:rect(0,0,0,0)}.highlight{background:#eaf3eb}.nowrap{white-space:nowrap}@media(max-width:700px){main{padding:24px 15px 45px}.stats{grid-template-columns:1fr 1fr}.stat:nth-child(2){border-right:0}.stat:nth-child(-n+2){border-bottom:1px solid var(--line)}.methods{grid-template-columns:1fr}.plot-wrap{padding:14px 8px}}@media print{body{background:white}main{padding:0}.controls,.nav{display:none}.table-wrap{overflow:visible}table{min-width:0;font-size:8px}th,td{padding:5px}.card{break-inside:avoid}}
</style></head><body><main>
<div class="eyebrow">Japanese → English · Numeric research report</div><h1>Translation quality,<br>reasoning effort, and cost.</h1><p class="intro">A source-based comparison of model configurations on one selected light-novel corpus. Scores describe this workflow and sample; they are not a universal model ranking.</p><p id="cohort-note" class="banner" hidden></p>
<nav class="nav" aria-label="Report sections"><a href="#results">All configurations</a><a href="#value">Quality & cost</a><a href="#captures">Capture-level metrics</a><a href="#methods">Method & limitations</a><a href="results.json">Sanitized JSON</a></nav>
<div id="banner" class="banner" role="status"></div><div id="stats" class="stats"></div>
<section id="results"><h2>All configurations</h2><p class="small">Click a column heading to sort. Missing values remain unknown. Quality, coverage, and priced sample counts may differ in a draft.</p><div class="card"><div class="controls"><label>Find model or effort<input id="search" type="search" placeholder="All configurations"></label><span class="small" id="row-count"></span></div><div class="table-wrap"><table><caption class="sr">Sortable model scores, coverage, elapsed time, and estimated cost.</caption><thead><tr id="summary-head"></tr></thead><tbody id="summary-body"></tbody></table></div><div class="note">Scores: 1–10. Unusable counts require both judges to mark the translation unusable. Value recommendations below exclude a configuration if either judge marks any matched translation unusable. Coverage is the mean reviewer estimate, averaged within each graded capture, then across captures with recorded coverage. Cost averages use priced captures; they are not necessarily the quality sample. ≥ denotes a lower bound. OpenAI costs are estimated API-equivalent USD; Ollama costs are estimated no-cache provider tariffs. Both exclude grading and are not subscription charges or invoices. The value comparison below retains the OpenAI cohort on identical captures.</div></div></section>
<section id="value"><h2>OpenAI quality for your budget</h2><p class="small" id="matched-note"></p><div class="card"><div class="controls"><label>Minimum mean quality / 10<input id="minimum" type="number" min="1" max="10" step="0.1" value="8.5"></label><label>Cost assumption<select id="basis"><option value="cost_mean_usd">Recorded cache usage</option><option value="cost_mean_no_cache_usd">No cache discounts</option></select></label></div><div id="recommendation" class="recommend" aria-live="polite"></div><div class="plot-wrap"><svg id="plot" class="plot" viewBox="0 0 1000 340" role="img" aria-label="Mean quality against estimated API-equivalent cost per capture"></svg><p id="plot-note" class="small"></p><div id="legend" class="legend"></div></div><details><summary>Matched configurations and eligibility</summary><div class="table-wrap"><table style="min-width:700px"><thead><tr><th>Model / effort</th><th>Mean / 10</th><th>USD / capture</th><th>USD / 100 captures</th><th>Cost status</th><th>Value eligibility</th></tr></thead><tbody id="value-body"></tbody></table></div></details><div class="note">Value eligibility requires complete estimated costs and both judges marking every matched capture usable. A negative usability judgment from either judge excludes that configuration, even when the other judge disagrees. Missing costs and lower bounds also exclude a configuration from recommendations. A threshold applies to the unrounded mean; it does not guarantee every capture meets that score. Captures can contain multiple printed pages. The 100-capture figure extrapolates this mix.</div></div></section>
<section id="captures"><h2>Capture-level metrics</h2><p class="small">Numeric evidence only. Source images, translations, reviewer quotations, local paths, and tool commands are not published.</p><details class="card"><summary>Expand recorded runs and both reviewers’ scores</summary><div class="controls"><label>Configuration<select id="capture-config"><option value="">All configurations</option></select></label><label>Source capture<select id="capture-source"><option value="">All captures</option></select></label><span class="small" id="capture-count"></span></div><div class="table-wrap"><table><caption class="sr">Per-capture dimensions, cost, completion state, and each reviewer's numeric metrics.</caption><thead><tr><th>Model / effort</th><th>Capture</th><th>Run status</th><th>Mean / 10</th><th>Accuracy</th><th>Complete</th><th>Names / numbers</th><th>Fluency</th><th>Coverage</th><th>Cost USD</th><th>Cost status</th><th>Reviewer metrics</th></tr></thead><tbody id="capture-body"></tbody></table></div></details></section>
<section id="delivery" hidden><h2>Gemini delivery and conditional quality</h2><p class="small">Anonymous content audits distinguish English translations from service errors and other delivery failures. The primary score retains every response. Conditional quality uses only delivered English translations, so its sample can differ across configurations and it is not a replacement ranking. Service errors describe reliability in the observed Gemini browser session and selected configuration; they do not establish intrinsic translation ability or API behavior.</p><div class="card table-wrap"><table style="min-width:850px"><thead><tr><th>Model / effort</th><th>English / planned</th><th>Service errors</th><th>Non-English</th><th>Other failures</th><th>Primary mean</th><th>Conditional mean</th><th>Conditional n</th></tr></thead><tbody id="delivery-body"></tbody></table></div></section>
<section id="deepseek" hidden><h2>DeepSeek on Ollama Cloud</h2><p class="small" id="deepseek-method">Instant requests disable thinking; Light requests use low thinking. These native Ollama requests form a separate two-candidate grading batch. OpenAI CLI, Gemini browser and Ollama transports differ; cross-cohort comparisons are exploratory. The quality and cost selector retains the original OpenAI cohort.</p><div class="card"><div id="deepseek-takeaway" class="recommend"></div><div class="table-wrap"><table style="min-width:1200px"><thead><tr><th>Model / setting</th><th>Requested think</th><th>Primary mean</th><th>Prose</th><th>Layout</th><th>English / planned</th><th>Usable by both / planned</th><th>Service errors</th><th>Non-English</th><th>Other failures</th><th>Conditional mean</th><th>Graded</th><th>Median seconds</th><th>No-cache USD / capture</th><th>Priced</th><th>Cost status</th></tr></thead><tbody id="deepseek-body"></tbody></table></div><div class="note">DeepSeek amounts are estimated no-cache Ollama tariff costs using recorded token counts and request-time rates, excluding grading. They are not invoices; — means unknown. OpenAI amounts are API-equivalent estimates for a separate CLI workflow. Displayed costs can be compared descriptively, but separate grading batches do not establish a controlled best-value ranking. Primary means retain all responses; conditional means use delivered English translations only. Usable counts require both reviewers to mark the output usable; an English response can still contain serious translation errors.<p id="deepseek-pricing"></p><p id="deepseek-pricing-limitations"></p><a href="https://ollama.com/pricing" rel="noopener" target="_blank">Official Ollama pricing</a></div></div></section>
<section id="ollama-expanded" hidden><h2>Gemma 4 and DeepSeek High on Ollama Cloud</h2><p class="small">This later native-API cohort uses supported model-specific thinking controls. Each reviewer grades a pair and a singleton per source; the earlier DeepSeek Instant/Light cohort used two-candidate batches. Comparisons across collection and grading batches are exploratory. The original OpenAI value comparison remains unchanged.</p><p class="small" id="ollama-expanded-controls"></p><div class="card"><div id="ollama-expanded-takeaway" class="recommend"></div><div class="table-wrap"><table style="min-width:1200px"><thead><tr><th>Model / setting</th><th>Native think</th><th>Primary mean</th><th>Prose</th><th>Layout</th><th>English / planned</th><th>Usable by both / planned</th><th>Service errors</th><th>Non-English</th><th>Other failures</th><th>Conditional mean</th><th>Graded</th><th>Completed median seconds</th><th>Completed mean seconds</th><th>Completed maximum seconds</th><th>Timed completed / planned</th><th>Interrupted / planned</th><th>Longest interrupted seconds</th><th>No-cache USD / capture</th><th>Priced / planned</th><th>Cost status</th></tr></thead><tbody id="ollama-expanded-body"></tbody></table></div><div class="note">Timing summarizes completed requests with recorded elapsed durations. Interrupted attempts are counted separately; ≥ marks their observed elapsed time as a lower bound on completion time, not a completed latency. Unavailable timing remains unknown. Mean and maximum expose slow requests that a median can hide. Individual native timings appear in the capture-level run status. Interrupted attempts remain in quality and delivery results. Without a final usage receipt, their costs and the configuration’s average cost are unknown; priced counts identify the known subset. Primary means retain all responses; conditional means use delivered English translations only. English delivery does not by itself establish an acceptable translation. Usable counts require both reviewers to mark the output usable. No-cache costs apply each exact model's published Ollama tariff to recorded input and total output counts, including thinking where present. These are estimates, not invoices; — means unknown. Displayed costs can be compared descriptively; separate transports and grading batches do not establish a controlled best-value ranking.<div id="ollama-expanded-pricing"></div><a href="https://ollama.com/pricing" rel="noopener" target="_blank">Official Ollama pricing</a></div></div></section>
<section id="methods"><h2>Method & limitations</h2><div class="card"><div id="methods-body" class="methods"></div><div class="note">Reviewers can share blind spots. One generation per configuration and capture does not measure run-to-run variance. Small differences on this selected corpus are weak evidence. No human-validated gold translation is provided.</div><div class="note"><a href="METHODS.md">Full methods</a> · <a href="results.json">Sanitized numeric data</a> · <a href="https://developers.openai.com/api/docs/pricing" rel="noopener" target="_blank">Official pricing</a><p id="pricing-note"></p><p id="pricing-limitations"></p></div></div></section>
<footer id="footer"></footer></main><noscript>This report uses local JavaScript for sorting and charts. Read README.md or results.json for the numeric results. No network request is needed.</noscript>
<script id="data" type="application/json">__DATA__</script><script>
'use strict';const D=JSON.parse(document.getElementById('data').textContent),$=id=>document.getElementById(id),num=v=>typeof v==='number'&&Number.isFinite(v)?v:null,fmt=(v,d=2)=>num(v)===null?'—':v.toLocaleString('en-US',{minimumFractionDigits:d,maximumFractionDigits:d}),usd=v=>num(v)===null?'—':'$'+v.toLocaleString('en-US',{minimumFractionDigits:v===0||v>=1?2:4,maximumFractionDigits:v<.001?6:4}),name=c=>c?(c.model_display||c.model)+' / '+c.effort:'Unknown configuration',el=(tag,cls,text)=>{const n=document.createElement(tag);if(cls)n.className=cls;if(text!==undefined)n.textContent=String(text);return n},configs=new Map(D.configurations.map(c=>[c.id,c])),sourceMap=new Map(D.sources.map(s=>[s.id,s])),ns='http://www.w3.org/2000/svg',svg=(tag,attrs,text)=>{const n=document.createElementNS(ns,tag);for(const[k,v]of Object.entries(attrs))n.setAttribute(k,String(v));if(text!==undefined)n.textContent=String(text);return n};
$('banner').classList.toggle('final',D.final);$('banner').textContent=(D.final?'Final numeric publication · ':'Draft · ')+D.graded+' / '+D.expected+' captures × configurations graded. '+(D.final?'The publication completion gate passed.':'The complete-publication gate has not passed. Coverage is incomplete or not approved for final publication; rankings can change.')+(!D.final&&D.gate_reasons.length?' Gate: '+D.gate_reasons.join('; ')+'.':'');
for(const[value,label]of[[D.configurations.length,'Configurations'],[D.sources.length,'Source captures'],[D.graded+' / '+D.expected,D.configurations.some(c=>c.cohort==='ollama-cloud-expanded')?'Assessed translation attempts':'Graded translations'],[D.sources.filter(s=>s.is_prose===true).length+' / '+D.sources.filter(s=>s.is_prose===false).length,'Prose / layout captures']]){const n=el('div','stat');n.append(el('b','',value),el('span','',label));$('stats').append(n)}
let sort='mean',direction=-1;const columns=[['model','Model / effort'],['mean','Overall'],['accuracy','Accuracy'],['completeness','Complete'],['names_numbers','Names / numbers'],['fluency','Fluency'],['coverage_percent','Coverage'],['prose_mean','Prose'],['layout_mean','Layout'],['n','Graded'],['unusable','Unusable (both judges)'],['failed','Failed'],['median_seconds','Median seconds'],['cost_mean_usd','Avg. USD'],['cost_n','Priced'],['cost_status','Cost status']];
for(const[k,label]of columns){const th=el('th');th.scope='col';th.dataset.key=k;const b=el('button','',label);b.type='button';b.onclick=()=>{direction=sort===k?-direction:k==='model'||k==='cost_status'?1:-1;sort=k;renderSummary()};th.append(b);$('summary-head').append(th)}
function renderSummary(){const q=$('search').value.trim().toLowerCase(),rr=D.rows.filter(r=>name(r).toLowerCase().includes(q));rr.sort((a,b)=>{const x=a[sort],y=b[sort];if(x===null||x===undefined)return y===null||y===undefined?0:1;if(y===null||y===undefined)return-1;return direction*(typeof x==='string'?x.localeCompare(String(y)):x-y)});$('summary-body').replaceChildren();for(const r of rr){const tr=el('tr');for(const[k]of columns){let value=r[k];if(k==='model')value=name(r);else if(k==='coverage_percent')value=fmt(value,1)+(num(value)===null?'':'%');else if(k==='n')value=fmt(value,0)+' / '+fmt(r.total,0);else if(k==='cost_mean_usd')value=(r.cost_status==='lower_bound'?'≥ ':'')+usd(value);else if(k!=='cost_status')value=fmt(value,['n','unusable','failed','cost_n'].includes(k)?0:k==='median_seconds'?1:2);const td=el('td',k==='model'?'name':k==='mean'?'score':'',value);if(k==='mean'&&num(r.ci_low)!==null&&num(r.ci_high)!==null)td.title='95% bootstrap interval '+fmt(r.ci_low)+'–'+fmt(r.ci_high);if(k==='coverage_percent')td.title='Coverage recorded for '+r.coverage_n+' graded captures';tr.append(td)}$('summary-body').append(tr)}$('row-count').textContent=rr.length+' / '+D.rows.length+' configurations';for(const th of $('summary-head').children)th.setAttribute('aria-sort',th.dataset.key===sort?(direction===1?'ascending':'descending'):'none')}
const colors=['#17695c','#4d69a3','#b77731','#925d84'];const modelColors=new Map([...new Set(D.value.rows.map(r=>configs.get(r.configuration_id)?.model).filter(Boolean))].map((m,i)=>[m,colors[i%colors.length]]));
function valueEligible(r,basis){return r.eligible===true&&r.cost_eligible===true&&r.cost_status==='estimated'&&r.unusable===0&&num(r.mean)!==null&&num(r[basis])!==null&&r[basis]>=0&&r.n>0&&r.n===D.value.n}
function drawPlot(rows,basis,minimum){const p=$('plot');p.replaceChildren();const points=rows.filter(r=>r.cost_status==='estimated'&&num(r[basis])!==null&&r[basis]>=0&&num(r.mean)!==null&&r.n>0);if(!points.length){p.setAttribute('hidden','');$('plot-note').textContent='No matched quality and complete cost estimates are available yet.';return}p.removeAttribute('hidden');const vals=points.map(r=>r[basis]),lo=Math.min(...vals),hi=Math.max(...vals),log=lo>0&&hi/lo>8,xmin=log?Math.log10(lo)-.12:0,xmax=log?Math.log10(hi)+.12:Math.max(hi*1.1,.001),x=v=>70+((log?Math.log10(v):v)-xmin)/(xmax-xmin)*885,y=v=>285-(v-1)/9*250;for(const tick of[1,4,7,10]){p.append(svg('line',{x1:70,x2:955,y1:y(tick),y2:y(tick),stroke:'#e0e6e1'}),svg('text',{x:57,y:y(tick)+4,'text-anchor':'end'},tick))}for(let i=0;i<=4;i++){const n=xmin+(xmax-xmin)*i/4,v=log?10**n:n;p.append(svg('text',{x:70+i*885/4,y:307,'text-anchor':'middle'},usd(v)))}p.append(svg('text',{x:510,y:335,'text-anchor':'middle'},'Estimated USD / capture'+(log?' · logarithmic cost axis':'')),svg('text',{x:70,y:17},'Mean quality / 10'));if(num(minimum)!==null)p.append(svg('line',{x1:70,x2:955,y1:y(minimum),y2:y(minimum),stroke:'#17695c','stroke-dasharray':'5 5'}));for(const r of points){const c=configs.get(r.configuration_id),eligible=valueEligible(r,basis),circle=svg('circle',{cx:x(r[basis]),cy:y(r.mean),r:eligible?6:5,fill:eligible?modelColors.get(c?.model)||'#63716c':'white',stroke:modelColors.get(c?.model)||'#63716c','stroke-width':2,tabindex:0});circle.append(svg('title',{},name(c)+' · '+fmt(r.mean)+' / 10 · '+usd(r[basis])+' · '+(eligible?'value eligible':'excluded from recommendation')));p.append(circle)}$('plot-note').textContent='Dashed line: minimum mean quality. Hollow points: complete cost estimate, but excluded from value recommendations. Lower bounds and missing costs are not plotted. Hover or focus a point for its configuration.'}
function renderValue(){const basis=$('basis').value,entered=$('minimum').value,min=entered===''?null:Number(entered),valid=num(min)!==null&&min>=1&&min<=10,eligible=D.value.rows.filter(r=>valueEligible(r,basis)&&valid&&r.mean>=min).sort((a,b)=>a[basis]-b[basis]||b.mean-a.mean),winner=eligible[0];$('matched-note').textContent=(D.value.provisional||!D.final?'Provisional matched comparison · ':'Matched comparison · ')+fmt(D.value.n,0)+' / '+fmt(D.value.total,0)+' identical doubly reviewed captures per configuration.';$('recommendation').replaceChildren(el('strong','',!valid?'Enter a minimum between 1 and 10.':winner?'Cheapest eligible configuration: '+name(configs.get(winner.configuration_id)):'No eligible configuration meets this threshold.'));if(winner)$('recommendation').append(el('p','',fmt(winner.mean)+' / 10 mean · '+usd(winner[basis])+' per capture · '+usd(winner[basis]*100)+' per 100 captures.'),el('p','small',(D.value.provisional||!D.final?'Provisional suggestion on the currently matched sample. ':'')+'Uses complete estimates only; unavailable or lower-bound costs cannot establish the cheapest option.'));$('value-body').replaceChildren();for(const r of D.value.rows){const tr=el('tr',winner===r?'highlight':'');const why=valueEligible(r,basis)?'Eligible':r.cost_status!=='estimated'?'Excluded: '+r.cost_status:r.unusable>0?'Excluded: at least one judge marked a matched capture unusable':'Excluded: incomplete or unverified';for(const v of[name(configs.get(r.configuration_id)),fmt(r.mean),(r.cost_status==='lower_bound'?'≥ ':'')+usd(r[basis]),(r.cost_status==='lower_bound'?'≥ ':'')+usd(num(r[basis])===null?null:r[basis]*100),r.cost_status,why])tr.append(el('td','',v));$('value-body').append(tr)}drawPlot(D.value.rows,basis,valid?min:null)}
for(const[model,color]of modelColors){const n=el('span'),i=el('i');i.style.backgroundColor=color;n.append(i,document.createTextNode(model));$('legend').append(n)}
for(const c of D.configurations){const o=el('option','',name(c));o.value=c.id;$('capture-config').append(o)}for(const s of D.sources){const o=el('option','',s.id+' · '+(s.category||'uncategorized'));o.value=s.id;$('capture-source').append(o)}
function renderCaptures(){const cc=$('capture-config').value,ss=$('capture-source').value,rr=D.runs.filter(r=>(!cc||r.configuration_id===cc)&&(!ss||r.source_id===ss));$('capture-body').replaceChildren();for(const r of rr){const tr=el('tr'),coverage=r.reviews.map(v=>v.coverage_percent).filter(v=>num(v)!==null),cv=coverage.length?coverage.reduce((a,b)=>a+b,0)/coverage.length:null;for(const[i,v]of[name(configs.get(r.configuration_id)),r.source_id,r.status,fmt(r.scores.overall),fmt(r.scores.accuracy),fmt(r.scores.completeness),fmt(r.scores.names_numbers),fmt(r.scores.fluency),fmt(cv,1)+(cv===null?'':'%'),(r.cost.status==='lower_bound'?'≥ ':'')+usd(r.cost.usd),r.cost.status].entries()){const td=el('td','',v);if(i===2&&configs.get(r.configuration_id)?.cohort==='ollama-cloud-expanded')td.append(el('span','sub',r.status==='interrupted'?'Completion time: '+(num(r.elapsed_seconds)!==null&&r.elapsed_seconds>=0?'≥ '+fmt(r.elapsed_seconds,1)+' seconds':'unknown')+' (interrupted)':'Native elapsed: '+(r.status==='completed'&&num(r.elapsed_seconds)!==null&&r.elapsed_seconds>=0?fmt(r.elapsed_seconds,1)+' seconds':'unknown')));tr.append(td)}const cell=el('td'),details=el('details'),summary=el('summary','',r.reviews.length+' recorded reviewers');details.append(summary);for(const v of r.reviews)details.append(el('p','small',v.judge+' · overall '+fmt(v.overall)+' · accuracy '+fmt(v.accuracy)+' · completeness '+fmt(v.completeness)+' · names/numbers '+fmt(v.names_numbers)+' · fluency '+fmt(v.fluency)+' · coverage '+fmt(v.coverage_percent,1)+(num(v.coverage_percent)===null?'':'%')+' · usable '+(v.usable===null?'unknown':v.usable?'yes':'no')));for(const v of r.review_statuses)details.append(el('p','small',v.judge+' · '+v.status));cell.append(details);tr.append(cell);$('capture-body').append(tr)}$('capture-count').textContent=rr.length+' recorded runs'}
if(D.methodology.cohorts){$('cohort-note').hidden=false;$('cohort-note').textContent=D.methodology.cohorts;}
for(const r of D.rows.filter(r=>r.cohort==='gemini-web'&&r.delivery_counts)){const c=r.delivery_counts,tr=el('tr');$('delivery').hidden=false;for(const v of[name(r),fmt(c.english_translation,0)+' / '+fmt(r.total,0),fmt(c.service_error,0),fmt(c.non_english_transcription,0),fmt(c.other_failure,0),fmt(r.mean),fmt(r.english_translation_mean),fmt(r.english_translation_n,0)])tr.append(el('td','',v));$('delivery-body').append(tr)}
const deepseekRows=D.rows.filter(r=>r.cohort==='ollama-cloud');
if(deepseekRows.length){$('deepseek').hidden=false;const nav=el('a','','DeepSeek');nav.href='#deepseek';document.querySelector('nav').append(nav);for(const r of deepseekRows){const c=r.delivery_counts||{},tr=el('tr');for(const v of[name(r),r.requested_think===false?'false':r.requested_think||'unknown',fmt(r.mean),fmt(r.prose_mean),fmt(r.layout_mean),fmt(c.english_translation,0)+' / '+fmt(r.total,0),fmt(r.both_reviewers_usable,0)+' / '+fmt(r.total,0),fmt(c.service_error,0),fmt(c.non_english_transcription,0),fmt(c.other_failure,0),fmt(r.english_translation_mean),fmt(r.n,0)+' / '+fmt(r.total,0),fmt(r.median_seconds,1),(r.cost_status==='lower_bound'?'≥ ':'')+usd(r.cost_mean_no_cache_usd),fmt(r.cost_n,0),r.cost_status])tr.append(el('td','',v));$('deepseek-body').append(tr)}const complete=deepseekRows.filter(r=>r.n===r.total&&r.total>0&&num(r.mean)!==null).sort((a,b)=>b.mean-a.mean);$('deepseek-takeaway').textContent=D.final&&complete.length===deepseekRows.length?'Within this two-setting batch, '+name(complete[0])+' had the highest observed mean ('+fmt(complete[0].mean)+'/10). '+complete.map(r=>name(r)+': '+fmt(r.delivery_counts?.english_translation,0)+'/'+fmt(r.total,0)+' English translations; '+fmt(r.both_reviewers_usable,0)+'/'+fmt(r.total,0)+' usable by both reviewers; '+usd(r.cost_mean_no_cache_usd)+' estimated no-cache USD/capture').join('. ')+'. English delivery does not by itself establish an acceptable translation. One generation per capture; small differences are weak evidence.':'DeepSeek collection or publication checks are incomplete; a within-batch takeaway is withheld.';const p=D.deepseek_pricing,rate=v=>num(v)===null?'unknown':'$'+String(v),parts=[];for(const[k,label]of[['peak','Peak'],['off_peak','Off-peak']])if(p[k])parts.push(label+': '+rate(p[k].input)+' input / '+rate(p[k].cached_input)+' cached input / '+rate(p[k].output)+' output per million tokens');$('deepseek-pricing').textContent='Ollama pricing snapshot: '+(p.date||'not recorded')+'. '+parts.join('; ')+'. '+(p.schedule||'Rate schedule not recorded.');$('deepseek-pricing-limitations').textContent=p.limitations||'';}
const expandedRows=D.rows.filter(r=>r.cohort==='ollama-cloud-expanded');
const nativeThink=v=>typeof v==='boolean'?String(v):typeof v==='string'&&v?v:'unknown';
if(expandedRows.length){
  $('ollama-expanded').hidden=false;const nav=el('a','','Gemma 4 & DeepSeek High');nav.href='#ollama-expanded';document.querySelector('nav').append(nav);
  $('ollama-expanded-controls').textContent=D.methodology.native_controls||'Use the exact model and native think value recorded in each row. Thinking labels are model-specific.';
  for(const r of expandedRows){const c=r.delivery_counts||{},tr=el('tr');for(const v of[r.model+' / '+r.effort,nativeThink(r.requested_think),fmt(r.mean),fmt(r.prose_mean),fmt(r.layout_mean),fmt(c.english_translation,0)+' / '+fmt(r.total,0),fmt(r.both_reviewers_usable,0)+' / '+fmt(r.total,0),fmt(c.service_error,0),fmt(c.non_english_transcription,0),fmt(c.other_failure,0),fmt(r.english_translation_mean),fmt(r.n,0)+' / '+fmt(r.total,0),fmt(r.median_seconds,1),fmt(r.mean_seconds,1),fmt(r.max_seconds,1),fmt(r.timing_n,0)+' / '+fmt(r.total,0),fmt(r.interrupted,0)+' / '+fmt(r.total,0),num(r.interrupted_elapsed_seconds_max)===null?'—':'≥ '+fmt(r.interrupted_elapsed_seconds_max,1),(r.cost_status==='lower_bound'?'≥ ':'')+usd(r.cost_mean_no_cache_usd),fmt(r.cost_n,0)+' / '+fmt(r.total,0),r.cost_status])tr.append(el('td','',v));$('ollama-expanded-body').append(tr)}
  const complete=expandedRows.filter(r=>r.n===r.total&&r.total>0&&num(r.mean)!==null);
  if(D.final&&complete.length===expandedRows.length){for(const r of complete)$('ollama-expanded-takeaway').append(el('p','',name(r)+' (native think:'+nativeThink(r.requested_think)+'): '+fmt(r.mean)+'/10 mean; '+fmt(r.both_reviewers_usable,0)+'/'+fmt(r.total,0)+' usable by both reviewers; '+fmt(r.delivery_counts?.english_translation,0)+'/'+fmt(r.total,0)+' English translations; '+fmt(r.interrupted,0)+'/'+fmt(r.total,0)+' interrupted'+(num(r.interrupted_elapsed_seconds_max)===null?'':' (longest observed ≥ '+fmt(r.interrupted_elapsed_seconds_max,1)+' seconds)')+'; '+(r.cost_status==='unavailable'?'average no-cache cost unknown ('+fmt(r.cost_n,0)+'/'+fmt(r.total,0)+' priced)':usd(r.cost_mean_no_cache_usd)+' estimated no-cache USD/capture')+'.'));$('ollama-expanded-takeaway').append(el('p','small','One generation per capture; small differences are weak evidence. These later observations do not establish a controlled improvement over the frozen earlier cohorts.'));}else $('ollama-expanded-takeaway').textContent='Expanded Ollama collection or publication checks are incomplete; a within-cohort takeaway is withheld.';
  for(const model of new Set(expandedRows.map(r=>r.model))){const p=D.ollama_expanded_pricing[model]||{},rate=v=>num(v)===null?'unknown':'$'+String(v),parts=[];for(const[k,label]of[['peak','Peak'],['off_peak','Off-peak']])if(p[k])parts.push(label+': '+rate(p[k].input)+' input / '+rate(p[k].cached_input)+' cached input / '+rate(p[k].output)+' output per million tokens');$('ollama-expanded-pricing').append(el('p','',model+' — pricing snapshot '+(p.date||'not recorded')+'. '+parts.join('; ')+'. '+(p.schedule||'Rate schedule not recorded.')),el('p','',p.limitations||''));}
}
const methodNames={cohorts:'Separate cohorts',sample:'Source selection',conditions:'Comparable requests',scoring:'Scoring',amendment:'Review amendment',limitations:'Limitations',intervals:'Intervals',timing:'Timing',ultra:'Ultra workflow',deepseek:'DeepSeek protocol',ollama_expanded:'Expanded Ollama protocol',native_controls:'Native thinking controls',grading_batches:'Grading batches',transports:'Generation transports',cli_versions:'CLI versions'};for(const[k,title]of Object.entries(methodNames))if(typeof D.methodology[k]==='string'){const a=el('article');a.append(el('h3','',title),el('p','',D.methodology[k]));$('methods-body').append(a)}$('pricing-note').textContent='Pricing snapshot: '+(D.pricing.date||'not recorded')+' · '+(D.pricing.tier||'unspecified tier')+' · '+(D.pricing.method||'No pricing method recorded.');$('pricing-limitations').textContent=D.pricing.limitations||'';$('footer').textContent='Self-contained numeric report · renderer '+D.version+' · generated '+(D.generated_at||'date not recorded')+'. No images, fonts, analytics, or other resources are fetched. External pricing links open only when clicked.';
$('search').addEventListener('input',renderSummary);$('minimum').addEventListener('input',renderValue);$('basis').addEventListener('change',renderValue);$('capture-config').addEventListener('change',renderCaptures);$('capture-source').addEventListener('change',renderCaptures);renderSummary();renderValue();renderCaptures();
</script></body></html>'''


def render(data: dict) -> str:
    payload = json.dumps(prepare(data), ensure_ascii=False, allow_nan=False, separators=(',', ':'))
    payload = payload.replace('&', '\\u0026').replace('<', '\\u003c').replace('>', '\\u003e').replace('\u2028', '\\u2028').replace('\u2029', '\\u2029')
    return HTML.replace('__DATA__', payload)


def value_choices(d, thresholds=(9.0, 9.5)):
    """Final-only choices on the fully matched sample and complete costs."""
    value = d['value']
    count = len(d['sources'])
    if not d['final'] or value['provisional'] or count == 0 or value['n'] != count or value['total'] != count:
        return []
    eligible = [r for r in value['rows'] if r['eligible'] and r['cost_eligible']
        and r['cost_status'] == 'estimated' and r['unusable'] == 0 and r['n'] == count
        and numeric(r['mean']) is not None and 1 <= r['mean'] <= 10
        and numeric(r['cost_mean_usd']) is not None and r['cost_mean_usd'] >= 0]
    choices = []
    for threshold in thresholds:
        candidates = [r for r in eligible if r['mean'] >= threshold]
        if candidates:
            choices.append((threshold, min(candidates, key=lambda r: (r['cost_mean_usd'], -r['mean'], r['configuration_id']))))
    return choices


def readme(data: dict) -> str:
    d = prepare(data)
    def safe(value):
        return html.escape(str(value), quote=False).replace('|', '&#124;').replace('\n', ' ').replace('\r', ' ')
    def n(value, digits=2):
        return '—' if numeric(value) is None else f'{value:.{digits}f}'
    def money(value):
        return '—' if numeric(value) is None else f'${value:.6f}'
    def name(r):
        return safe((r.get('model_display') or r['model']) + ' / ' + r['effort'])
    configs = {c['id']: c for c in d['configurations']}
    delivery_rows = [r for r in d['rows'] if r['cohort'] == 'gemini-web' and 'delivery_counts' in r]
    deepseek_rows = [r for r in d['rows'] if r['cohort'] == 'ollama-cloud']
    expanded_rows = [r for r in d['rows'] if r['cohort'] == 'ollama-cloud-expanded']
    other_rows = [r for r in d['rows'] if r['cohort'] == 'codex-cli']
    out = ['# Japanese → English translation benchmark', '',
        'How much translation quality does more reasoning buy—and which settings are worth the cost? This study compares model settings on a selected set of Japanese light-novel captures.', '',
        f"**{'Final numeric publication' if d['final'] else 'DRAFT — incomplete or awaiting publication gate'}.** {d['graded']} / {d['expected']} planned {'translation attempts assessed' if expanded_rows else 'translations graded'} across {len(d['configurations'])} configurations and {len(d['sources'])} captures; two source-based AI reviews per {'assessed attempt' if expanded_rows else 'completed translation'}.", '',
        '[Interactive report](report.html) · [Numeric results](results.json) · [Full methods and limitations](METHODS.md)', '']
    if not d['final']:
        out += ['Collection or publication checks are still incomplete. Draft means can cover different captures; practical recommendations are withheld until the final gate passes.', '']
    choices = value_choices(d)
    if choices:
        out += ['## Practical takeaways', '', f"Within the OpenAI cohort, on the same {len(d['sources'])} captures, using recorded cache usage and complete Standard API cost estimates:", '']
        distinct_choices = {r['configuration_id']: (threshold, r) for threshold, r in choices}
        for threshold, r in distinct_choices.values():
            out.append(f"- **{name(configs[r['configuration_id']])}** was the cheapest eligible setting with mean quality ≥ {threshold:g}/10: **{n(r['mean'])}/10 at {money(r['cost_mean_usd'])} per capture**.")
        out += ['', 'These thresholds apply to the unrounded mean, not every page. Eligibility requires both judges to mark every matched output usable. Lower-bound and unknown costs are excluded; the interactive report also offers a no-cache scenario.', '']
    if d['final'] and delivery_rows:
        complete = [r for r in delivery_rows if numeric(r['total']) is not None and r['total'] > 0
            and r['delivery_counts'].get('english_translation') == r['total']
            and r['english_translation_n'] == r['total'] and numeric(r['mean']) is not None]
        if complete:
            r = max(complete, key=lambda r: r['mean'])
            out += [f"Within the Gemini cohort, **{name(r)}** delivered English for **{n(r['total'], 0)}/{n(r['total'], 0)} captures**, with the highest observed mean among settings that delivered English every time: **{n(r['mean'])}/10**. Both reviewers marked **{n(r['both_reviewers_usable'], 0)}/{n(r['total'], 0)} outputs usable**; delivering English does not by itself establish an acceptable translation. Delivery failures and English-only quality are shown separately below; this is a small comparison of the observed browser workflow.", '']
    if other_rows:
        out += ['## ' + ('OpenAI quality and estimated cost' if delivery_rows or deepseek_rows or expanded_rows else 'Quality and estimated cost'), '',
            'Scores are 1–10. Cost is estimated API-equivalent USD per capture, excluding grading and subscription charges. ≥ marks a lower bound; — means unknown. Captures can contain multiple printed pages.', '',
            '| Model | Effort | Overall | Prose | Layout | Graded | Avg. USD | Cost status |',
            '|---|---|---:|---:|---:|---:|---:|---|']
        for r in other_rows:
            cost = ('≥ ' if r['cost_status'] == 'lower_bound' else '') + money(r['cost_mean_usd'])
            out.append('| ' + ' | '.join(map(safe, (r.get('model_display') or r['model'], r['effort'], n(r['mean']), n(r['prose_mean']), n(r['layout_mean']), f"{n(r['n'],0)}/{n(r['total'],0)}", cost, r['cost_status']))) + ' |')
        out += ['', f"The value comparison uses {n(d['value']['n'],0)}/{n(d['value']['total'],0)} identical doubly reviewed captures. [Open the interactive report](report.html) for dimensions, coverage, both reviewers’ scores, cost assumptions and eligibility details.", '']
    if delivery_rows:
        out += ['## Gemini delivery and conditional quality', '',
            'The primary mean includes every response. Conditional mean uses only delivered English translations: its captures can differ across settings, so it is not a replacement ranking. Gemini browser token usage and equivalent API costs are unknown.', '',
            '| Model / setting | English / planned | Service errors | Non-English | Other failures | Primary mean | Conditional mean | Conditional n |',
            '|---|---:|---:|---:|---:|---:|---:|---:|---:|']
        for r in delivery_rows:
            c = r['delivery_counts']
            out.append('| ' + ' | '.join(map(safe, (r['model']+' / '+r['effort'], f"{n(c['english_translation'],0)}/{n(r['total'],0)}", n(c['service_error'],0), n(c['non_english_transcription'],0), n(c['other_failure'],0), n(r['mean']), n(r['english_translation_mean']), n(r['english_translation_n'],0)))) + ' |')
        out += ['', '`standard` and `extended` mean the browser’s extended-thinking switch was off or on. Off does not guarantee zero backend reasoning. Service errors describe this observed browser session/configuration, not intrinsic translation ability or API behavior.', '']
    if deepseek_rows:
        out += ['## DeepSeek on Ollama Cloud', '',
            'Instant requests disable thinking (`think: false`); Light requests use low thinking (`think: "low"`). Native Ollama requests form a separate two-candidate grading batch. The original OpenAI value comparison remains separate.', '']
        complete = [r for r in deepseek_rows if numeric(r['mean']) is not None
            and numeric(r['total']) is not None and r['total'] > 0 and r['n'] == r['total']]
        if d['final'] and len(complete) == len(deepseek_rows):
            r = max(complete, key=lambda r: r['mean'])
            usability = '; '.join(f"{name(r)}: **{n(r['both_reviewers_usable'],0)}/{n(r['total'],0)} usable by both reviewers**" for r in complete)
            out += [f"Within this two-setting batch, **{name(r)}** had the highest observed mean: **{n(r['mean'])}/10**. {usability}. English delivery does not by itself establish an acceptable translation. One generation per capture; small differences are weak evidence.", '']
        else:
            out += ['DeepSeek collection or publication checks are incomplete; a within-batch takeaway is withheld.', '']
        out += ['Primary means retain all responses; conditional means use delivered English translations only. Usable counts require both reviewers to mark the output usable; an English response can still contain serious translation errors. No-cache tariff estimates use recorded usage and request-time Ollama rates. These are estimates, not invoices; — means unknown.', '',
            '| Model / setting | Think | Primary mean | Prose | Layout | English / planned | Usable by both / planned | Service errors | Non-English | Other failures | Conditional mean | Graded | Median seconds | No-cache USD / capture | Priced | Cost status |',
            '|---|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---|']
        for r in deepseek_rows:
            c = r.get('delivery_counts') or {}
            think = str(r['requested_think']).lower() if isinstance(r.get('requested_think'), bool) else r.get('requested_think', 'unknown')
            cost = ('≥ ' if r['cost_status'] == 'lower_bound' else '') + money(r['cost_mean_no_cache_usd'])
            values = (name(r), safe(think), n(r['mean']), n(r['prose_mean']), n(r['layout_mean']),
                f"{n(c.get('english_translation'),0)}/{n(r['total'],0)}",
                f"{n(r['both_reviewers_usable'],0)}/{n(r['total'],0)}", n(c.get('service_error'),0),
                n(c.get('non_english_transcription'),0), n(c.get('other_failure'),0),
                n(r.get('english_translation_mean')), f"{n(r['n'],0)}/{n(r['total'],0)}",
                n(r['median_seconds'],1), cost, n(r['cost_n'],0), safe(r['cost_status']))
            out.append('| ' + ' | '.join(values) + ' |')
        out += ['', 'DeepSeek tariff estimates and OpenAI API-equivalent estimates can be compared descriptively. Separate transports and grading batches do not establish a controlled best-value ranking. Gemini browser cost remains unknown.', '']
        p = d['deepseek_pricing']
        out += [f"Ollama pricing snapshot: {safe(p.get('date') or 'not recorded')} · [Official Ollama pricing](https://ollama.com/pricing).", '']
        for key, label in (('peak', 'Peak'), ('off_peak', 'Off-peak')):
            if key in p:
                rates = p[key]
                out += [f"{label}, USD per million tokens: {money(rates.get('input'))} input; {money(rates.get('cached_input'))} cached input; {money(rates.get('output'))} output.", '']
        for key in ('schedule', 'limitations'):
            if p.get(key):
                out += [safe(p[key]), '']
        if d['methodology'].get('cli_versions'):
            out += [safe(d['methodology']['cli_versions']), '']
    if expanded_rows:
        out += ['## Gemma 4 and DeepSeek High on Ollama Cloud', '',
            'This later cohort uses supported model-specific native thinking controls. Each reviewer grades a pair and a singleton per source; the earlier DeepSeek Instant/Light cohort used two-candidate batches. The original 31 configurations and the OpenAI value comparison remain frozen. Cross-batch comparisons are exploratory.', '']
        if d['methodology'].get('native_controls'):
            out += [safe(d['methodology']['native_controls']), '']
        complete = [r for r in expanded_rows if numeric(r['mean']) is not None
            and numeric(r['total']) is not None and r['total'] > 0 and r['n'] == r['total']]
        if d['final'] and len(complete) == len(expanded_rows):
            for r in complete:
                think = str(r['requested_think']).lower() if isinstance(r.get('requested_think'), bool) else r.get('requested_think', 'unknown')
                cost = (f"average no-cache cost unknown ({n(r['cost_n'],0)}/{n(r['total'],0)} priced)"
                    if r['cost_status'] == 'unavailable'
                    else f"{money(r['cost_mean_no_cache_usd'])} estimated no-cache USD per capture")
                interrupted = f"{n(r['interrupted'],0)}/{n(r['total'],0)} interrupted"
                if r['interrupted_elapsed_seconds_max'] is not None:
                    interrupted += f" (longest observed ≥ {n(r['interrupted_elapsed_seconds_max'],1)} seconds)"
                out += [f"**{name(r)}** (native think: `{safe(think)}`): **{n(r['mean'])}/10 mean**, **{n(r['both_reviewers_usable'],0)}/{n(r['total'],0)} usable by both reviewers**, {n((r.get('delivery_counts') or {}).get('english_translation'),0)}/{n(r['total'],0)} delivered English; {interrupted}; {cost}.", '']
            out += ['English delivery does not by itself establish an acceptable translation. One generation per capture; small differences are weak evidence. These later observations do not establish a controlled improvement over the frozen earlier cohorts.', '']
        else:
            out += ['Expanded Ollama collection or publication checks are incomplete; a within-cohort takeaway is withheld.', '']
        out += ['Timing summarizes completed requests with recorded elapsed durations. Interrupted attempts are counted separately; ≥ marks their observed elapsed time as a lower bound on completion time, not a completed latency. Unavailable timing remains unknown. Mean and maximum expose slow requests that a median can hide. Individual native timings appear in the interactive capture-level run status. Interrupted attempts remain in quality and delivery results. Without a final usage receipt, their costs and the configuration’s average cost are unknown; priced counts identify the known subset. Primary means retain all responses; conditional means use delivered English translations only. Usable counts require both reviewers to mark the output usable. No-cache tariff estimates use recorded input and total output counts, including thinking where present, and each exact model’s request-time rate. These are estimates, not invoices; — means unknown.', '',
            '| Model / setting | Native think | Primary mean | Prose | Layout | English / planned | Usable by both / planned | Service errors | Non-English | Other failures | Conditional mean | Graded | Completed median seconds | Completed mean seconds | Completed maximum seconds | Timed completed / planned | Interrupted / planned | Longest interrupted seconds | No-cache USD / capture | Priced / planned | Cost status |',
            '|---|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---|']
        for r in expanded_rows:
            c = r.get('delivery_counts') or {}
            think = str(r['requested_think']).lower() if isinstance(r.get('requested_think'), bool) else r.get('requested_think', 'unknown')
            cost = ('≥ ' if r['cost_status'] == 'lower_bound' else '') + money(r['cost_mean_no_cache_usd'])
            values = (safe(r['model'] + ' / ' + r['effort']), safe(think), n(r['mean']), n(r['prose_mean']), n(r['layout_mean']),
                f"{n(c.get('english_translation'),0)}/{n(r['total'],0)}",
                f"{n(r['both_reviewers_usable'],0)}/{n(r['total'],0)}", n(c.get('service_error'),0),
                n(c.get('non_english_transcription'),0), n(c.get('other_failure'),0),
                n(r.get('english_translation_mean')), f"{n(r['n'],0)}/{n(r['total'],0)}",
                n(r['median_seconds'],1), n(r['mean_seconds'],1), n(r['max_seconds'],1),
                f"{n(r['timing_n'],0)}/{n(r['total'],0)}", f"{n(r['interrupted'],0)}/{n(r['total'],0)}",
                "—" if r['interrupted_elapsed_seconds_max'] is None else f"≥ {n(r['interrupted_elapsed_seconds_max'],1)}",
                cost, f"{n(r['cost_n'],0)}/{n(r['total'],0)}", safe(r['cost_status']))
            out.append('| ' + ' | '.join(values) + ' |')
        out += ['', 'Ollama tariff estimates and OpenAI API-equivalent costs can be compared descriptively. Separate transports and grading batches do not establish a controlled best-value ranking; Gemini browser cost remains unknown.', '']
        for model in dict.fromkeys(r['model'] for r in expanded_rows):
            p = d['ollama_expanded_pricing'].get(model, {})
            out += [f"**{safe(model)}** — Ollama pricing snapshot: {safe(p.get('date') or 'not recorded')} · [Official Ollama pricing](https://ollama.com/pricing).", '']
            for key, label in (('peak', 'Peak'), ('off_peak', 'Off-peak')):
                if key in p:
                    rates = p[key]
                    out += [f"{label}, USD per million tokens: {money(rates.get('input'))} input; {money(rates.get('cached_input'))} cached input; {money(rates.get('output'))} output.", '']
            for key in ('schedule', 'limitations'):
                if p.get(key):
                    out += [safe(p[key]), '']
    out += ['## How to read the results', '',
        '- This is a small, selected corpus with one generation per setting and capture. AI reviewers can share blind spots; there is no human-validated gold translation. Small score differences are weak evidence.']
    if delivery_rows or deepseek_rows or expanded_rows:
        out += ['- Providers used separate grading batches without drift controls. Cross-provider comparisons are exploratory, not a controlled ranking.']
    out += ['- OpenAI costs use a Standard API pricing snapshot. Incomplete attempt or delegated usage remains a lower bound and cannot establish best value. Exact client changes, audit limitations and affected runs are disclosed in [METHODS.md](METHODS.md) and [results.json](results.json).']
    if delivery_rows:
        out += ['- Browser elapsed time includes polling, collection and audit gaps. It is not inference latency and is not ranked against CLI time.']
    out += ['', '## Explore or reproduce the report', '',
        'Download `report.html` and open it locally for sorting, per-capture evidence, and the quality/cost selector. It is self-contained and makes no external requests. To rebuild it from the bundled numeric data:', '',
        '```sh', 'python3 render_publication.py --results results.json --output report.html', '```', '',
        'The [full methods](METHODS.md), [prompt](translation-prompt.txt), [rubric](grading-rubric.md), [schema](SCHEMA.md) and synthetic tests document the experiment and report. Source IDs and hashes identify the private corpus; source scans, translations and reviewer quotations are excluded. This package reproduces the numeric report, not access to the corpus.', '',
        f"Pricing snapshot: {safe(d['pricing'].get('date') or 'not recorded')} · [Official Standard API pricing](https://developers.openai.com/api/docs/pricing).", '',
        f"Report renderer {VERSION}. Generated: {safe(d['generated_at'] or 'not recorded')}.", '']
    return '\n'.join(out)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--results', type=Path, required=True)
    parser.add_argument('--output', type=Path)
    args = parser.parse_args()
    data = json.loads(args.results.read_text(encoding='utf-8'))
    if not isinstance(data, dict):
        parser.error('Results must contain a JSON object')
    destination = args.output or args.results.with_name('report.html')
    destination.parent.mkdir(parents=True, exist_ok=True)
    destination.write_text(readme(data) if destination.suffix.lower() == '.md' else render(data), encoding='utf-8')
    print(destination)


if __name__ == '__main__':
    main()
