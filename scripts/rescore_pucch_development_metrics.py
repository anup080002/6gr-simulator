"""Rescore retained development metrics; no decoder/RF execution or qualification."""
import argparse
import csv
import hashlib
import json
import math
from pathlib import Path


def require(condition, message):
    if not condition:
        raise ValueError(message)


def binary(value):
    values = json.loads(value)
    if not isinstance(values, list):
        values = [values]
    require(all(type(v) is int and v in (0, 1) for v in values), 'Nonbinary payload')
    return values


def read_rows(path):
    with path.open(encoding='utf-8-sig', newline='') as stream:
        return list(csv.DictReader(stream))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('config', type=Path)
    parser.add_argument('output', type=Path)
    args = parser.parse_args()
    spec = json.loads(args.config.read_text(encoding='utf-8-sig'))
    paths = {key: Path(spec[key]) for key in ('design_receipt', 'noise_csv', 'pilot_csv', 'pilot_audit_csv')}
    hashes = {key: hashlib.sha256(path.read_bytes()).hexdigest() for key, path in paths.items()}
    design = json.loads(paths['design_receipt'].read_text(encoding='utf-8-sig'))
    require(design['Source']=='analytical_union_bound_not_physical_measurement' and
            design['DetectorQualified'] is False, 'Not the predeclared analytical candidate')
    threshold = design['CandidateThreshold']
    require(type(threshold) is float and math.isfinite(threshold) and 0 < threshold <= 1, 'Invalid candidate')
    noise = read_rows(paths['noise_csv'])
    require(len(noise)==spec['expected_noise_rows'], 'Incomplete retained noise records')
    keys, projected = set(), []
    for row in noise:
        key = (int(row['Occasion']), int(row['HARQBits']))
        require(key not in keys and key[1] in (1, 2), 'Duplicate/invalid noise hypothesis')
        keys.add(key)
        metric, old = float(row['RecomputedMetric']), float(row['Threshold'])
        require(math.isfinite(metric) and 0 <= old <= threshold, 'Only stricter-threshold rescoring supported')
        require(math.isclose(metric, float(row['OriginalMetric']), abs_tol=1e-12, rel_tol=0), 'Replay differs from original')
        bits = binary(row['WinningBitsJSON'])
        require(len(bits)==key[1], 'Winning hypothesis width mismatch')
        original = sum(bits) if metric >= old else 0
        require(original==int(row['FalseACKBits']) and int(row['Detected'])==int(metric >= old), 'Original failure accounting changed')
        projected.append(dict(Occasion=key[0], HARQBits=key[1], Metric=metric,
                              OriginalFalseACKBits=original,
                              ProjectedFalseACKBits=sum(bits) if metric >= threshold else 0))
    require({k[0] for k in keys if k[1]==1}=={k[0] for k in keys if k[1]==2}, 'Noise widths did not score the same captures')
    require(len({row['InputIQSHA256'] for row in noise})==1, 'Unexpected source IQ bundles')
    summary = []
    for width in (1, 2):
        subset = [r for r in projected if r['HARQBits']==width]
        summary.append(dict(HARQBits=width, ExistingNoiseOccasions=len(subset),
                            BitOpportunities=width*len(subset),
                            OriginalFalseACKBits=sum(r['OriginalFalseACKBits'] for r in subset),
                            ProjectedFalseACKBits=sum(r['ProjectedFalseACKBits'] for r in subset),
                            MaximumRetainedMetric=max(r['Metric'] for r in subset)))
    pilot = read_rows(paths['pilot_csv']); audit = read_rows(paths['pilot_audit_csv'])
    require(len(pilot)==spec['expected_pilot_rows'] and len(audit)==len(pilot), 'Incomplete physical pilot receipts')
    audit_keys = {(r['Episode'], r['CaseID']): r for r in audit}
    require(len(audit_keys)==len(audit), 'Duplicate pilot audit row')
    pilot_keys, signal_rows = set(), []
    for row in pilot:
        key = (row['Episode'], row['CaseID'])
        require(key not in pilot_keys and key in audit_keys, 'Invalid pilot case identity')
        pilot_keys.add(key); observed = audit_keys[key]
        require(row['EvidenceSHA256']==observed['EvidenceSHA256'], 'Different pilot evidence')
        metric, old = float(row['DetectionMetric']), float(row['DetectionThreshold'])
        require(math.isfinite(metric) and old <= threshold, 'Invalid pilot metric or threshold direction')
        flag = observed['ReceiverUsable'].lower()
        require(flag in ('true','false'), 'Invalid usability flag')
        usable = flag=='true' and metric >= threshold
        expected, decoded = binary(row['DeclaredPayloadJSON']), binary(row['DecodedPayloadJSON'])
        signal = int(row['SignalPresent'])==1
        if signal:
            require(len(expected)==int(row['HARQBits']), 'Invalid signal hypothesis')
            error = not usable or decoded!=expected
        else:
            require(not expected, 'Noise case contains transmitted payload')
            error = usable and any(decoded)
        signal_rows.append(dict(Episode=int(row['Episode']), CaseID=row['CaseID'], SignalPresent=signal,
                                Metric=metric, ProjectedReceiverUsable=usable,
                                ProjectedEventError=bool(error), EvidenceSHA256=row['EvidenceSHA256']))
    receipt = dict(Source='retained_metric_rescoring_not_candidate_receiver_execution',
                   DetectorQualified=False, NewPhysicalEpisodes=0, NewIndependentEpisodes=0,
                   CandidateThreshold=threshold, NoiseSummary=summary, PilotRows=signal_rows,
                   InputSHA256=hashes, InputPaths={k: str(v) for k,v in paths.items()},
                   SourceIQSHA256=noise[0]['InputIQSHA256'],
                   ScriptSHA256=hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
                   Limitations='No MAT/IQ replay here; reused completed independent audit receipts. No campaign confidence claim.')
    args.output.mkdir(parents=True, exist_ok=False)
    (args.output/'receipt.json').write_text(json.dumps(receipt, indent=2)+'\n', encoding='utf-8')
    print(json.dumps(receipt, indent=2))


if __name__=='__main__':
    main()
