function folder=diagnoseTRSPilotPowerReplay(capturePath)
% Received-grid replay, never a new scenario execution or PHY success claim.
% Only acquired pilot samples enter estimation. Replay metadata establishes
% the executed flat/white-noise model, not its gains or injected variance.
setup6GRSimToolkit('Verbose',false);
before=sixgr.phy.waveform.WaveformHash.file(capturePath);
saved=load(capturePath,'det','replay');
eligibility=sixgr.phy.rx.assertFlatStaticAWGNObservation(saved.replay);
rows=struct([]);
for k=1:numel(saved.det.SlotDetections)
    d=saved.det.SlotDetections(k);
    assert(d.Detected && ~isempty(d.RxGrid), ...
        'TRS power replay requires actual acquisition; do not substitute true timing.');
    samples=reshape(d.RxGrid,[],size(d.RxGrid,3));
    samples=samples(double(d.ReferenceIndices(:)),:);
    ref=d.ReferenceSymbols(:);
    old=sixgr.phy.rx.estimateFlatAWGNPilotChannel(samples,ref);
    joint=sixgr.phy.rx.estimateFlatAWGNMultiportChannel(samples,ref);
    assert(max(abs(old.GainPerReceiveBranch-joint.GainPerPortReceiveBranch))<1e-12);
    assert(max(abs(old.NoiseVariancePerReceiveBranch-joint.NoiseVariancePerReceiveBranch))<1e-12);
    m=joint.ReferencePowerMeasurement;
    for r=1:size(samples,2)
        signed=m.SignedReferenceSNRLinearPerReceiveBranch(r);
        snrDB=NaN; status="signed_linear_nonpositive_logarithm_unavailable";
        if signed>0, snrDB=10*log10(signed); status="positive_signed_linear_estimate"; end
        row=struct('Slot',d.Slot,'ReceiveBranch',r,'PilotCount',m.PilotCount, ...
            'RawFittedPower',m.RawReconstructedPowerPerReceiveBranch(r), ...
            'EstimatedNoiseBias',m.EstimatedNoiseBiasPerReceiveBranch(r), ...
            'SignedDesiredPower',m.SignedSignalPowerPerReceiveBranch(r), ...
            'MeasuredNoisePower',m.NoisePowerPerReceiveBranch(r), ...
            'SignedLinearSNR',signed,'PilotSNREstimate_dB',snrDB,'Status',status, ...
            'PowerUnit',"retained_received_pilot_grid_amplitude_squared", ...
            'Source',m.Source,'ClippedToNonnegative',m.ClippedToNonnegative, ...
            'ScoringReferenceUsed',false,'Scope',"retained_TRS_grid_replay_not_new_PHY_execution");
        if isempty(rows), rows=row; else, rows(end+1)=row; end %#ok<AGROW>
    end
end
assert(~isempty(rows));
folder=fullfile(pwd,'results','lls','trs_pilot_power_replay', ...
    char(datetime('now','Format','yyyyMMdd_HHmmss_SSS')));
mkdir(folder); writetable(struct2table(rows),fullfile(folder,'received_pilot_power.csv'));
assert(sixgr.phy.waveform.WaveformHash.file(capturePath)==before);
sixgr.util.jsonWrite(fullfile(folder,'replay_manifest.json'),struct( ...
    'Scope',"retained_acquired_TRS_pilots_no_new_PHY",'CapturePath',string(capturePath), ...
    'CaptureSHA256',before,'OriginalCaptureUnchanged',true,'NewPHYExecutions',0, ...
    'ModelEligibility',eligibility,'ProductionTRSReportingFixed',false));
disp(struct2table(rows));
fprintf('TRS_PILOT_POWER_REPLAY rows=%d source_unchanged=1 production_reporting_fixed=0 output=%s\n',numel(rows),folder);
end
