import unittest
from pricing import estimate, value_comparison


def usage(i=1000, c=0, w=0, o=100, r=80):
    return dict(input_tokens=i,cached_input_tokens=c,cache_write_input_tokens=w,output_tokens=o,reasoning_output_tokens=r)


class CostTests(unittest.TestCase):
    def test_disjoint_input_buckets_and_reasoning_already_in_output(self):
        cost = estimate('gpt-6-astra', usage(1000, 200, 100, 100, 80))
        self.assertAlmostEqual(cost['usd'], .007 + .0002 + .00125 + .005)
        self.assertAlmostEqual(cost['no_cache_usd'], .015)
        self.assertEqual(cost['status'], 'estimated')
        self.assertEqual(cost['usd'], estimate('gpt-6-astra', usage(1000, 200, 100, 100, 0))['usd'])

    def test_missing_invalid_or_unknown_is_not_zero(self):
        for tokens in ({}, usage(-1), usage(c=1001), usage(i=True)):
            self.assertIsNone(estimate('gpt-6-sol', tokens)['usd'])
        self.assertIsNone(estimate('unknown', usage())['usd'])

    def test_delegation_and_missing_retry_usage_are_lower_bounds(self):
        for kwargs in ({'delegated': True}, {'incomplete_attempt_usage': True}):
            result = estimate('gpt-6-luna', usage(), **kwargs)
            self.assertEqual(result['status'], 'lower_bound')
            self.assertIsNone(result['upper_usd'])
            self.assertGreater(result['usd'], 0)

    def test_aggregate_does_not_prove_long_context(self):
        at = estimate('gpt-6-sol', usage(272000))
        above = estimate('gpt-6-sol', usage(272001))
        self.assertEqual(at['status'], 'estimated')
        self.assertEqual(above['status'], 'lower_bound')
        self.assertAlmostEqual(above['upper_usd'], .272001 * 4 + .0001 * 15)

    def test_actual_saved_example(self):
        result = estimate('gpt-6-sol', usage(14885,9344,0,6253,5741))
        self.assertAlmostEqual(result['usd'], .0754808)

    def test_value_uses_common_captures_and_excludes_bad_or_unknown_costs(self):
        configs = [{'id': x} for x in ('a','b','c')]
        sources = [{'id': x} for x in ('one','two')]
        runs = []
        for config in configs:
            for source in sources:
                cid, sid = config['id'], source['id']
                runs.append(dict(configuration_id=cid,source_id=sid,status='completed',
                    scores={'overall': 9} if sid=='one' or cid=='a' else None,
                    cost={'usd': {'a': .2,'b': .01,'c': .02}[cid], 'no_cache_usd': .3,
                        'status': 'lower_bound' if cid=='b' else 'estimated'},
                    reviews=[{'usable': True},{'usable': cid!='c'}]))
        comparison = value_comparison(configs,sources,runs)
        self.assertEqual(comparison['common_source_ids'], ['one'])
        self.assertEqual(next(r for r in comparison['rows'] if r['configuration_id']=='b')['eligible'], False)
        rejected = next(r for r in comparison['rows'] if r['configuration_id']=='c')
        self.assertTrue(rejected['cost_eligible'])
        self.assertFalse(rejected['eligible'])
        self.assertFalse(rejected['frontier'])
        self.assertEqual(next(r for r in comparison['recommendations'] if r['minimum_score']==9)['configuration_id'], 'a')
        self.assertIsNone(next(r for r in comparison['recommendations'] if r['minimum_score']==9.5)['configuration_id'])

if __name__ == '__main__':
    unittest.main()
