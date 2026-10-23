function ok = testPDCCHReceiverObservationExport()
% Deterministic coded-waveform timing fixture, not acquisition qualification.
cfg=struct(); cfg.run.seed=9361;
cfg.frequency.duplex_mode='TDD'; cfg.phy.duplex.mode='TDD';
cfg.phy.carrier=struct('NSizeGrid',24,'NStartGrid',0, ...
    'SubcarrierSpacing',30,'NCellID',1,'NSlot',3,'NFrame',0);
cfg.phy.pdcch=struct('enable',true,'dmrs',struct('enable',true), ...
    'rnti',101,'aggregationLevel',4,'aggregationLevels',4,'blindSearch',true);
cfg.phy.pdcch.coreset=struct('id',0,'duration',2, ...
    'frequencyResources',ones(1,4),'mappingType','noninterleaved');
cfg.phy.pdcch.searchSpace=struct('id',1,'startSymbol',0, ...
    'numCandidates',[0 0 1 0 0],'slotPeriodAndOffset',[1 0],'duration',1);
cfg.lls6g.userContext.RuntimeSlotStartTime_s=.0015;
bits=int8(mod((0:31).',2));
p=sixgr.link.preparePDCCHTransmission(cfg,'DCIBits',bits);
resourceEvidence=sixgr.truth.pdcchResourceIntervalEvidence(p.Tx);
assert(resourceEvidence.PDCCHCORESETStartSymbol==0);
prbs=jsondecode(resourceEvidence.PDCCHAllocatedPRBSetJSON);
[native,~,dmrs]=nrPDCCHResources(p.Tx.Carrier,p.Tx.PDCCH);
[k,~,~]=ind2sub(size(p.Tx.Grid),double([native(:);dmrs(:)]));
assert(isequal(prbs(:),unique(floor((k(:)-1)/12))), ...
    'The exported control PRB set must come from the actual encoded candidate.');
reference=struct('Source',"received_SSB_timing_and_decoded_BCH", ...
    'SampleRateHz',p.SampleRateHz,'AvailableAtSample',0,'DLPhaseOffsetSamples',17, ...
    'NCellID',1,'ImplementationFilterDelay_samples',0,'SearchGuardSamples',32);
for phase=[-17 0 17]
    reference.DLPhaseOffsetSamples=phase;
    alignment=sixgr.phy.frame.pdcchReceivedClockAlignment(reference,p.Tx.Carrier, ...
        p.RuntimeStartSample,p.SampleRateHz,0);
    prepared=p; prepared.ReceivedTimingAlignment=alignment;
    x=p.TransmitSamples(1:p.MinimumReceiveSamples,:);
    buffer=sixgr.phy.waveform.WaveformObservationBuffer(alignment.ReceiveStartSample, ...
        alignment.ReceiveStartSample+size(x,1),p.SampleRateHz,size(x,2));
    buffer.append(sixgr.phy.waveform.WaveformChunk(x,alignment.ReceiveStartSample),p.SampleRateHz);
    [rx,info]=sixgr.link.completePDCCHReception(prepared,buffer);
    assert(rx.Ok && isequal(rx.DCIBits,bits));
    % TX-reference audit corruption must not alter receiver detection evidence.
    row=struct('InjectedTimingOffset_samples',1,'BitErrors',32,'BitsCompared',32);
    out=sixgr.truth.bindPDCCHReceiverObservation(row,rx,info);
    assert(out.RuntimeStageWaveformsUsed && out.ObservationSampleRateHz==buffer.SampleRateHz && ...
        out.ObservationStartSample==buffer.StartSample && ...
        out.ReceiverObservationSHA256==sixgr.phy.waveform.WaveformHash.runtimeArray(x) && ...
        out.ReceiverObservationHashPlane=="actual_receiver_input_before_synchronization");
    assert(out.PDCCHLLRCount==numel(rx.DecoderLLRs) && ...
        out.PDCCHLLRMeanAbs==mean(abs(double(rx.DecoderLLRs(:)))) && ...
        out.PDCCHLLRMin==min(double(rx.DecoderLLRs(:))) && ...
        out.PDCCHLLRMax==max(double(rx.DecoderLLRs(:))));
    assert(out.LLRAvailable && out.LLRFinite && ...
        all(isfinite(rx.DecoderLLRs(:))), ...
        'Generic LLR flags must describe the same actual decoder vector as the PDCCH statistics.');
    assert(out.DetectionAttempted && out.DetectionUsable && out.DetectionSuccess);
    assert(isnan(out.DetectionMetric) && contains(out.DetectionMetricStatus,'rnti_masked_crc'));
    assert(out.TimingEstimateUsed && out.TimingEstimate_samples==phase && ...
        out.AppliedTimingCorrection_samples==0 && ...
        out.TimingEstimateStatus=="available_applied_at_observation_origin");
    assert(out.InjectedTimingOffset_samples==1 && isnan(out.TrueTimingOffset_samples));
    assert(out.Modulation=="QPSK" && contains(out.DetectionPopulationScope,'hypothesis_set'));
    row.BitErrors=0;
    same=sixgr.truth.bindPDCCHReceiverObservation(row,rx,info);
    assert(same.DetectionSuccess==out.DetectionSuccess && ...
        isequaln(same.DetectionMetric,out.DetectionMetric));
end
% Explicit export-boundary fixtures, not additional waveform realizations.
% A nonfinite vector remains present, but cannot be called finite. Missing
% retained samples are unknown, even if stale summary statistics exist.
nonfinite=rx; nonfinite.DecoderLLRs(1)=NaN;
out=sixgr.truth.bindPDCCHReceiverObservation(row,nonfinite,info);
assert(out.LLRAvailable && ~out.LLRFinite);
absent=rmfield(rx,'DecoderLLRs');
out=sixgr.truth.bindPDCCHReceiverObservation(row,absent,info);
assert(isnan(out.LLRAvailable) && isnan(out.LLRFinite));
empty=rx; empty.DecoderLLRs=zeros(0,1);
out=sixgr.truth.bindPDCCHReceiverObservation(row,empty,info);
assert(~out.LLRAvailable && ~out.LLRFinite);
% Replay identical received samples with a deliberately wrong TX audit.
% The physical CRC still passes, but this must not authorize the grant.
poisoned=prepared;
poisoned.Tx.DCIBits(1)=1-poisoned.Tx.DCIBits(1);
[observed,audit]=sixgr.link.completePDCCHReception(poisoned,buffer);
assert(observed.Ok && observed.ErrFlag==0 && isequal(observed.DCIBits,bits) && ...
    ~observed.DCIPayloadMatch && ~observed.CausalGrantDecodeOk);
row.CRCApplicable=true; row.CRCPass=0; row.DCICrcPass=false; row.CRCOutcome="fail";
row.Status="FAIL"; row.StrictOk=false; row.GrantValid=false;
out=sixgr.truth.bindPDCCHReceiverObservation(row,observed,audit);
assert(out.CRCApplicable && out.CRCPass==1 && out.DCICrcPass && out.CRCOutcome=="pass", ...
    'test:PDCCHCRCAuditConflation','Actual CRC must not depend on the TX payload audit.');
assert(out.DetectionSuccess && out.Status=="FAIL" && ~out.StrictOk && ~out.GrantValid, ...
    'Publishing a CRC pass must not turn a rejected grant into success.');
% Explicit semantic-rejection fixture: CRC and context validity differ.
semantic=observed; semantic.Ok=false; semantic.CausalGrantDecodeOk=false;
out=sixgr.truth.bindPDCCHReceiverObservation(row,semantic,audit);
assert(out.CRCPass==1 && out.DCICrcPass && ~out.DetectionSuccess);
for flag=[NaN Inf -1 .5]
    unavailable=observed; unavailable.ErrFlag=flag;
    out=sixgr.truth.bindPDCCHReceiverObservation(row,unavailable,audit);
    assert(isnan(out.CRCPass) && ~out.DCICrcPass && out.CRCOutcome=="unavailable" && ...
        ~out.DetectionSuccess,'Invalid CRC evidence must not be published as a measured outcome.');
end
failed=rx; failed.Ok=false; failed.ErrFlag=1234567;
out=sixgr.truth.bindPDCCHReceiverObservation(row,failed,info);
assert(out.DetectionUsable && ~out.DetectionSuccess && out.CRCPass==0 && ...
    ~out.DCICrcPass && out.CRCOutcome=="fail");
missing=info; missing.CandidateResults=table(); missing.TimingEstimate=struct();
out=sixgr.truth.bindPDCCHReceiverObservation(row,rx,missing);
assert(~out.DetectionAttempted && ~out.DetectionUsable && ~out.DetectionSuccess && ...
    ~out.TimingEstimateUsed && isnan(out.AppliedTimingCorrection_samples) && ...
    isnan(out.CRCPass) && ~out.DCICrcPass && out.CRCOutcome=="unavailable");
% Coordinator wiring guard supplements the actual coded-IQ checks above.
source=fileread(which('sixgr.truth.runWaveformLinkBundle'));
owner=fileread(which('sixgr.truth.PDCCHControlRuntime'));
section=regexp(owner,'(?s)function \[r,receivedAssignment,channelEvidence\] = receiveTrial.*?(?=\r?\n\s*function )','match','once');
assert(contains(source, ...
    '[varargout{1:nargout}] = sixgr.truth.PDCCHControlRuntime.receiveTrial(varargin{:});'), ...
    'The coordinator must use the canonical completion writer.');
assert(contains(section,'dciCrcPass = logical(r.DCICrcPass);') && ...
    contains(section,'ok = dciCrcPass && logical(rx.Ok) && payloadMatch;') && ...
    ~contains(section,'r.CRCPass = double(ok);'), ...
    'The production completion writer must use the tested CRC binding and preserve semantic grant gates.');
ok=true; fprintf('PDCCH_RECEIVER_OBSERVATION_EXPORT_PASS\n');
end
