function ok=testTRSReceivedCommonFrequency(mode)
% Actual NR IFFT/CP waveform with analytic frequency impairment for unit scoring.
setup6GRSimToolkit('Verbose',false);
if nargin<1, mode="TDD"; end
file='lls_causal_access_to_data_wiring_tdd.yaml';
if string(mode)=="FDD", file='lls_causal_access_to_data_wiring.yaml'; end
s=sixgr.lls6g.config.loadScenarioConfig(fullfile('simulator','configs','scenarios',file));
cfg=sixgr.lls6g.buildInternalConfig(s,tempname);
runtimeSlot=double(cfg.phy.trs.slotNumbers(1))+1;
p=sixgr.link.prepareTRSTransmission(cfg,12,'RuntimeSlot',runtimeSlot);
tx=p.Tx; strict=p.StrictConfig;
wave=tx.Waveform;
rx=struct('Waveform',[wave -wave], 'NoiseVariance',0, ...
    'InjectedTimingOffset_samples',0,'InjectedCFO_Hz',0);
% A retained timing measurement from the same receiver precedes CFO tracking.
timing=sixgr.phy.trs.estimateTRSTiming(rx,strict,tx);
assert(all(timing.Table.TRSTimingEstimateAvailable));
for offset=[-1000 -250 0 250 1000]
    rotation=exp(1i*2*pi*offset*(0:size(wave,1)-1).'/tx.SampleRateHz);
    rx.Waveform=[wave.*rotation -wave.*rotation];
    rx.FrequencyReferenceForScoring_Hz=offset;
    rx.FrequencyReferenceForScoringSource="analytic_scalar_rotation_unit_scoring_only";
    det=sixgr.phy.trs.detectTRSResources(rx,strict,tx,'Timing',timing);
    assert(det.DetectionSuccess);
    f=sixgr.phy.trs.estimateTRSFrequencyOffset(det,strict,tx,rx);
    assert(f.EstimateAvailable && abs(f.EstimatedCommonFrequency_Hz-offset)<10, ...
        'Measured %g Hz, expected %g Hz.',f.EstimatedCommonFrequency_Hz,offset);
    assert(isnan(f.EstimatedOscillatorCFO_Hz) && isnan(f.PhysicalDoppler_Hz));
    assert(all(f.Table.NumReceiveAntennas==2) && all(f.Table.UnambiguousHalfRange_Hz>1000));
    assert(all(f.Table.FromSymbol0Based==4 & f.Table.ToSymbol0Based==8));
    assert(all(f.Table.FromSlot==f.Table.ToSlot));
    changed=rx;
    changed.InjectedCFO_Hz=123456;
    changed.PhysicalDoppler_Hz=-932;
    changed.InjectedDoppler_Hz=741;
    changed.RuntimeSignedDoppler_Hz=29;
    changed.InjectedScalarDoppler_Hz=512;
    repeated=sixgr.phy.trs.estimateTRSFrequencyOffset(det,strict,tx,changed);
    assert(isequaln(f,repeated),'Injected/oracle fields changed a measured frequency result.');
    absent=sixgr.phy.trs.estimateTRSFrequencyOffset(det,strict,tx,struct());
    assert(absent.EstimatedCommonFrequency_Hz==f.EstimatedCommonFrequency_Hz && ...
        absent.EstimateAvailable && isnan(absent.FrequencyError_Hz));
    % An unsuccessful resource pair remains unavailable despite another pass.
    partial=det; partial.SlotDetections(2).Detected=false;
    one=sixgr.phy.trs.estimateTRSFrequencyOffset(partial,strict,tx,rx);
    assert(one.EstimateAvailable && one.Table.TRSCFOEstimateAvailable(1));
    assert(~one.Table.TRSCFOEstimateAvailable(2) && isnan(one.Table.EstimatedCFO_Hz(2)));
    assert(one.Table.EstimatedCFO_Hz(1)==f.Table.EstimatedCFO_Hz(1));
    partial.SlotDetections(1).ReferenceSymbols=partial.SlotDetections(1).ReferenceSymbols(1:end-1);
    none=sixgr.phy.trs.estimateTRSFrequencyOffset(partial,strict,tx,rx);
    assert(~none.EstimateAvailable && all(~none.Table.TRSCFOEstimateAvailable));
    assert(contains(none.Table.Status(1),'FrequencyReferenceIdentity'));
    fprintf('TRS common frequency %s: injected=%g measured=%g Hz; both RX branches.\n', ...
        mode,offset,f.EstimatedCommonFrequency_Hz);
end
ok=true;
end
