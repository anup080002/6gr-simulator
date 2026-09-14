"""Analytical development candidate only; reads no RF samples or trial outcomes."""
import argparse
import hashlib
import json
import math
from pathlib import Path

import yaml


def derive(policy):
    expected = {'schema_version', 'research_class', 'scope', 'null_model',
                'resource_elements_per_block', 'symbol_count', 'receive_branch_count',
                'maximum_hypothesis_count', 'target_model_false_detection_bound',
                'threshold_decimal_places'}
    if set(policy) != expected:
        raise ValueError('Unexpected or missing analytical design policy fields')
    if (policy['schema_version'] != 1 or
            policy['research_class'] != 'optional_research_experiment' or
            policy['scope'] != 'analytical_candidate_design_not_rf_qualification' or
            policy['null_model'] != 'circular_white_complex_gaussian_within_each_block'):
        raise ValueError('Unsupported scope or null model')
    for key in ('resource_elements_per_block', 'symbol_count', 'receive_branch_count',
                'maximum_hypothesis_count', 'threshold_decimal_places'):
        if type(policy[key]) is not int or policy[key] < 1:
            raise ValueError(f'{key} must be a positive integer')
    length = policy['resource_elements_per_block']
    if length <= 1 or policy['threshold_decimal_places'] > 12:
        raise ValueError('Block length must exceed one; decimal places must be 1..12')
    target = policy['target_model_false_detection_bound']
    if type(target) not in (float, int) or not math.isfinite(target) or not 0 < target < 1:
        raise ValueError('Model probability target must be finite and strictly between zero and one')
    blocks = policy['symbol_count'] * policy['receive_branch_count']
    comparisons = blocks * policy['maximum_hypothesis_count']
    # If an average of positive correlations exceeds t, at least one block
    # exceeds t. Union bound needs no independence across blocks/hypotheses.
    raw = math.sqrt(-math.expm1(math.log(target / comparisons) / (length - 1)))
    scale = 10 ** policy['threshold_decimal_places']
    candidate = math.ceil(raw * scale) / scale
    bound = min(1.0, comparisons * (1 - candidate * candidate) ** (length - 1))
    if not raw <= candidate <= 1 or bound > target * (1 + 1e-12):
        raise ValueError('Numerical candidate does not satisfy its declared model bound')
    return dict(Source='analytical_union_bound_not_physical_measurement',
                DetectorQualified=False, PhysicalEpisodes=0,
                UnroundedThreshold=raw, CandidateThreshold=candidate,
                ModelFalseDetectionUpperBound=bound, TargetModelBound=target,
                CorrelationBlocks=blocks, Hypotheses=policy['maximum_hypothesis_count'],
                RequiresIIDWithinBlock=True, RequiresIndependentBlocks=False,
                RequiresIndependentHypotheses=False,
                SignalPresentPerformanceEstablished=False)


def self_test(policy):
    r = derive(policy)
    for key in ('symbol_count', 'receive_branch_count', 'maximum_hypothesis_count'):
        more = dict(policy); more[key] *= 2
        if derive(more)['UnroundedThreshold'] <= r['UnroundedThreshold']:
            raise AssertionError('More comparisons must require a stricter bound')
    malformed = [('target_model_false_detection_bound', float('nan')),
                 ('target_model_false_detection_bound', 0),
                 ('receive_branch_count', True), ('resource_elements_per_block', 1),
                 ('threshold_decimal_places', 13), ('scope', 'truth')]
    for key, value in malformed:
        bad = dict(policy); bad[key] = value
        try:
            derive(bad)
        except ValueError:
            continue
        raise AssertionError(f'Invalid policy accepted: {key}')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('config', type=Path)
    parser.add_argument('output', type=Path)
    args = parser.parse_args()
    data = args.config.read_bytes()
    policy = yaml.safe_load(data)
    self_test(policy)
    receipt = derive(policy)
    receipt.update(Configuration=policy, SelfTestsPassed=True,
                   ConfigSHA256=hashlib.sha256(data).hexdigest(),
                   ScriptSHA256=hashlib.sha256(Path(__file__).read_bytes()).hexdigest())
    args.output.mkdir(parents=True, exist_ok=False)
    (args.output / 'analytical_design.json').write_text(json.dumps(receipt, indent=2) + '\n', encoding='utf-8')
    print(json.dumps(receipt, indent=2))


if __name__ == '__main__':
    main()
