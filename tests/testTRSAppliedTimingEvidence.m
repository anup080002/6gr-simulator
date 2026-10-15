function ok=testTRSAppliedTimingEvidence()
% Actual NR TRS loopback plus explicitly labelled malformed evidence tests.
scenario=sixgr.lls6g.config.loadScenarioConfig( ...
    'simulator/configs/scenarios/lls_causal_access_to_data_wiring_tdd.yaml');
cfg=sixgr.lls6g.buildInternalConfig(scenario,tempname);
p=sixgr.link.prepareTRSTransmission(cfg,30,'RuntimeSlot',double(cfg.phy.trs.slotNumbers(1))+1);
tx=p.Tx;
rx=struct('Waveform',tx.Waveform,'InjectedTimingOffset_samples',NaN, ...
    'InjectedCFO_Hz',NaN,'NoiseVariance',NaN,'AppliedAWGNSNR_dB',NaN);
timing=sixgr.phy.trs.estimateTRSTiming(rx,p.StrictConfig,tx);
det=sixgr.phy.trs.detectTRSResources(rx,p.StrictConfig,tx,'Timing',timing);
out=sixgr.phy.trs.summarizeAppliedTiming(det.Table);
assert(out.TimingEstimateUsed && out.TRSAppliedTimingResourceCount==height(det.Table));
assert(out.TRSExpectedTimingResourceCount==height(det.Table));
assert(all(det.Table.EstimatedTimingOffset_samples==out.AppliedTimingCorrection_samples));
assert(out.TimingEstimateStatus=="available_applied_at_received_window_origins");
assert(~out.TimingEstimateWasClipped && contains(out.TimingEstimateApplicationPolicy,'no_second_correction'));
saved=jsondecode(out.TRSAppliedTimingEvidenceJSON);
assert(numel(saved)==height(det.Table) && ...
    all([saved.EstimatedTimingOffset_samples].'==det.Table.EstimatedTimingOffset_samples));

% Exercise the production receive-completion adapter on these same samples.
% No propagation, RF or statistical qualification is claimed by loopback.
observation=sixgr.phy.waveform.WaveformObservationBuffer( ...
    0,size(rx.Waveform,1),tx.SampleRateHz,size(rx.Waveform,2));
observation.append(sixgr.phy.waveform.WaveformChunk(rx.Waveform,0),tx.SampleRateHz);
completed=sixgr.link.completeTRSReception(p,observation,struct(),struct());
assert(~completed.Crash, '%s',string(completed.FailureIdentifier));
assert(completed.TimingEstimateUsed && ...
    completed.AppliedTimingCorrection_samples==out.AppliedTimingCorrection_samples && ...
    completed.TRSAppliedTimingResourceCount==out.TRSAppliedTimingResourceCount && ...
    completed.TRSAppliedTimingEvidenceJSON==out.TRSAppliedTimingEvidenceJSON);

% Distinct actual per-resource shifts must not be replaced by their mean.
fixture=det.Table; fixture.EstimatedTimingOffset_samples(end)=2;
different=sixgr.phy.trs.summarizeAppliedTiming(fixture);
assert(different.TimingEstimateUsed && isnan(different.AppliedTimingCorrection_samples));
assert(contains(different.TimingEstimateStatus,'per_resource_shifts'));
for name=["ReceiveStartSample1Based","ReceiveEndSample1Based", ...
        "ReceivedSymbolCount","EstimatedTimingOffset_samples"]
    fixture.(name)(end)=NaN;
end
fixture.ReceiveWindowSource(end)="";
partial=sixgr.phy.trs.summarizeAppliedTiming(fixture);
assert(partial.TRSAppliedTimingResourceCount==height(fixture)-1 && ...
    startsWith(partial.TimingEstimateStatus,'partial_'));
bad=det.Table; bad.ReceiveEndSample1Based(1)=NaN;
try
    sixgr.phy.trs.summarizeAppliedTiming(bad);
    error('test:GuardBypassed','Expected incomplete execution evidence rejection.');
catch err
    assert(strcmp(err.identifier,'sixgr:phy:trs:InvalidAppliedTimingEvidence'));
end
empty=sixgr.phy.trs.summarizeAppliedTiming();
assert(~empty.TimingEstimateUsed && isnan(empty.AppliedTimingCorrection_samples));
% The real ledger must retain these fields without turning score into input.
state=struct('CurrentSlot',9);
state=sixgr.truth.CoupledTruthRuntime.publishReferenceSignalMeasurementRuntime( ...
    state,'TRS','Cell',1,struct2table(out),'ProducerSlot',7,'AvailableSlot',9,'Valid',true);
ledger=state.ReferenceSignalMeasurementTable;
assert(ledger.TimingEstimateUsed && ledger.TRSAppliedTimingResourceCount==height(det.Table) && ...
    ledger.TRSAppliedTimingEvidenceJSON==out.TRSAppliedTimingEvidenceJSON && isnan(ledger.SINR_dB));
ok=true; fprintf('TRS_APPLIED_TIMING_EVIDENCE_PASS\n');
end
