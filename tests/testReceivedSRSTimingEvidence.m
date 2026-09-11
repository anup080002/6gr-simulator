function ok=testReceivedSRSTimingEvidence()
setup6GRSimToolkit('Verbose',false);
carrier=nrCarrierConfig;
srs=nrSRSConfig;
indices=nrSRSIndices(carrier,srs); symbols=nrSRS(carrier,srs);
grid=nrResourceGrid(carrier); grid(indices)=symbols;
wave=sixgr.phy.waveform.ofdmModulate(carrier,grid);
% Explicit ideal-channel component with an injected seven-sample delay.
% The receiver gets the complete captured interval, not padded missing data.
capture=[zeros(7,size(wave,2));wave];
[~,timing]=sixgr.phy.sync.alignULReferenceObservation(carrier,capture,indices,symbols,[0 7]);
row=sixgr.truth.bindReceivedSRSTimingEvidence(table(),timing);
assert(timing.TimingOffsetSamples==7 && row.TimingEstimate_samples==7);
assert(row.AppliedTimingCorrection_samples==timing.AppliedTimingCorrectionSamples);
assert(row.TimingEstimateUsed && ~row.UseIdealTimingSync);
assert(row.SRSReceiveTimingOffset_samples==row.TimingEstimate_samples);
assert(~ismember('ResidualTimingError_PostCorrection_samples',row.Properties.VariableNames));
fprintf('RECEIVED_SRS_TIMING_EVIDENCE_PASS: actual reference correlation and generic/SRS aliases agree.\n');
ok=true;
end
