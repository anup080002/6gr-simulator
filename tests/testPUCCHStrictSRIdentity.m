function ok=testPUCCHStrictSRIdentity()
% A labelled SR regression must execute SR, not reuse a one-bit HARQ case.
setup6GRSimToolkit('Verbose',false);
cfg=struct('channel',struct('snr_dB',35));
result=sixgr.phy.pucch.runStrictPUCCHValidation(cfg,'WriteArtifacts',false);
rows=result.ArtifactTables.pucch_trials;
sr=rows(string(rows.TrialType)=="positive_format0_sr",:);
assert(height(sr)==1 && sr.StrictOk && sr.UCIContentMatch);
assert(sr.ExpectedHARQBitCount==0 && sr.ReceiverExpectedHARQBitCount==0 && ...
    ~sr.ExpectedAckApplicable && ~sr.AckObservedValid && ...
    isnan(sr.ExpectedAck) && isnan(sr.ObservedAck), ...
    'test:SRFixtureActuallyHARQ','The SR-labelled waveform must contain no HARQ field.');
assert(sr.ExpectedSRBitCount==1 && sr.ReceiverExpectedSRBitCount==1 && ...
    sr.DecodedSRBitCount==1 && string(sr.DecodedSRBitVector)=="1", ...
    'test:MissingSRDecodeEvidence','Retain the physically decoded SR field.');
assert(sr.HARQObservationStatus=="not_applicable_no_harq");
assert(result.StrictOk && all(rows.StrictOk));
ok=true;
end
