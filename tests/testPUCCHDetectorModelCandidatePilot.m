function ok=testPUCCHDetectorModelCandidatePilot()
% Paired physical DEVELOPMENT gate, not independent detector qualification.
assert(testPUCCHDetectorModelCandidateConfig());
policyPath='simulator/configs/validation/pucch_tdd_detector_model_candidate_pilot.yaml';
policy=sixgr.lls6g.config.readConfigFile(policyPath);
design=sixgr.lls6g.config.readConfigFile( ...
    'simulator/configs/validation/pucch_format0_noise_design_bound.yaml');
scenario=sixgr.lls6g.config.loadScenarioConfig(policy.scenario_path);
threshold=scenario.Data.pucch.detection_threshold_format0_two_symbols;
root=tempname(fullfile(pwd,'logs'));
fprintf('DETECTOR_MODEL_CANDIDATE_ROOT=%s\n',root);
result=runPUCCHDetectorPilot(policyPath,root);
assert(result.PhysicalPilotComplete,'test:DetectorCandidateIncomplete', ...
    'Every required case must produce actual acquired-timing receive evidence; inspect %s.',root);
assert(~result.DetectorQualified && all(~result.Summary.DetectorQualified));
rows=readtable(fullfile(root,'physical_trials.csv'),'TextType','string');
assert(height(rows)==policy.episodes*numel(policy.cases));
assert(all(rows.DetectionThreshold==threshold) && all(isfinite(rows.DetectionMetric)), ...
    'test:DetectorCandidatePolicy','Actual receiver must use the candidate threshold and produce finite metrics.');
for k=1:height(rows)
    path=rows.EvidencePath(k);
    assert(string(sixgr.util.sha256File(path))==rows.EvidenceSHA256(k), ...
        'test:DetectorCandidateEvidence','Physical evidence hash mismatch.');
    saved=load(path,'out','testCase','post','hypothesis');
    samples=saved.post.readComplete();
    resource=saved.hypothesis.Assignment.Resource;
    assert(resource.Format==0 && resource.Data.NumPRBs==1 && ...
        resource.Data.NumSymbols==design.symbol_count && ...
        size(samples,2)==design.receive_branch_count && ...
        design.resource_elements_per_block==12 && ...
        2^saved.testCase.harq_bits<=design.maximum_hypothesis_count, ...
        'test:DetectorCandidateGeometry','Actual receive layout differs from the declared analytical design.');
    assert(~isempty(samples) && all(isfinite(samples),'all'));
    rx=saved.out;
    assert(rx.IndependentReceiverAssignment && ~rx.PreparedTransmitterConsumed && ...
        ~rx.OraclePayloadBitsUsed && ~rx.InjectedNoiseVarianceConsumed && ...
        ~rx.InjectedInterferenceCovarianceConsumed && ~rx.ReceiveTiming.OracleTimingUsed && ...
        ~rx.ReceiveTiming.ReceiverZeroPaddingUsed);
    decoded=jsondecode(rows.DecodedPayloadJSON(k));
    assert(isequal(int8(decoded(:)),int8(rx.DecodedSequence1(:))));
    assert(logical(rows.ReceiverUsable(k))==rx.ReceiverUsable && ...
        logical(rows.DTX(k))==rx.DTX && rows.DetectionThreshold(k)==rx.DetectionThreshold);
    counts=countPUCCHDetectorPilotErrors(saved.testCase,rx.DecodedSequence1,rx.ReceiverUsable,rx.DTX);
    for field=string(fieldnames(counts)).'
        assert(double(rows.(field)(k))==double(counts.(field)), ...
            'test:DetectorCandidateAccounting','CSV field %s differs from retained RX.',field);
    end
    clear saved samples;
end
% Requiring zero observed errors is a development gate, not a confidence
% claim. Full held-out statistical gates remain unchanged and still due.
assert(all(result.Summary.ObservedEventErrors==0) && all(rows.EventError==0), ...
    'test:DetectorCandidateErrors','Candidate produced noise ACKs or wrong/erased signal payloads; retain %s.',root);
ok=true;
fprintf('DETECTOR_MODEL_CANDIDATE_PHYSICAL_PASS rows=%d detector_qualified=0 paired_development_only=1\n',height(rows));
end
