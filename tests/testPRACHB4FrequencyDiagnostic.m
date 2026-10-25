function [ok,result]=testPRACHB4FrequencyDiagnostic()
% Native B4 and blind 64-preamble detection; frequency is diagnostic only.
% Unit channel, declared CFO and absolute sample scale, no fading/RF/RA
% qualification and no SSB-derived frequency supplied to the receiver.
setup6GRSimToolkit('Verbose',false,'RunToolboxChecks',false);
saved=rng; cleanup=onCleanup(@()rng(saved)); %#ok<NASGU>
rng(251025,'twister');
folder=tempname(fullfile(pwd,'results','validation'));
sixgr.util.ensureFolder(folder);
scenario=sixgr.lls6g.config.loadScenarioConfig(fullfile(pwd,'simulator', ...
    'configs','scenarios','lls_tdd_n40_20mhz_64txru_4rx_cdlc100_reference_snr_sweep.yaml'));
cfg=sixgr.lls6g.buildInternalConfig(scenario,fullfile(folder,'config'));
assert(cfg.random_access.enable_frequency_estimation_metric && ...
    cfg.prach_lls.EnableFrequencyEstimationMetric);
prach=sixgr.rach.PRACHConfig(cfg,'NumPRACHOccasions',1,'NumTrials',1, ...
    'NumTxAntennas',1,'NumRxAntennas',2);
assert(string(prach.ResolvedPRACHFormat)=="B4" && prach.CarrierSCSkHz==30);
occasion=sixgr.rach.mapPRACHToOccasion(prach,'OccasionIndex',1);
tx=sixgr.rach.generatePRACHWaveform(prach,'Occasion',occasion,'PreambleIndex',17);
assert(string(tx.Format)=="B4" && size(tx.Waveform,2)==1);
receiver=prach;
if isfield(receiver,'PreambleIndex'), receiver=rmfield(receiver,'PreambleIndex'); end
time=(0:size(tx.Waveform,1)-1).'/tx.SampleRate_Hz;
unit=tx.Waveform/sqrt(mean(abs(tx.Waveform).^2));
rows=cell(6,1); k=0;
% Native detector has its own additive-eps normalization floor. Do not
% silently add pre-AGC or weaken its threshold to claim unlimited range.
% 1e-6 sqrt(mW) is -120 dBm mean per branch for this unit-RMS waveform.
for amplitude=[1 1e-6]
    for frequency=[-400 0 400]
        x=amplitude*unit.*exp(1i*2*pi*frequency*time);
        received=[x -x]; % Exact opposite phases must not cancel at RX.
        before=received;
        det=sixgr.phy.ra.detectConfiguredPRACH(received,cfg,receiver,occasion);
        save(fullfile(folder,sprintf('original_detection_%02d.mat',k+1)), ...
            'det','received','tx','receiver','occasion','frequency','amplitude');
        fprintf('B4_FREQUENCY_DETECTION amplitude=%g CFO=%g detected=%d preamble=%g peak=%g threshold=%g candidates=%d evidence=%s\n', ...
            amplitude,frequency,det.Detected,det.DetectedPreambleIndex, ...
            det.PeakMetric,det.Threshold,det.CandidateCount,folder);
        assert(det.Detected && det.DetectedPreambleIndex==17 && ...
            isequal(det.CandidatePreambles,(0:63).') && det.CandidateCount==64);
        e=det.FrequencyEstimate;
        assert(det.FrequencyEstimationEnabled && e.Valid && ...
            e.Estimator=="prach_repetition_phase" && ...
            abs(e.EstimateHz-frequency)<1e-3 && e.AmbiguityRange_Hz>400, ...
            'Native B4 CFO=%g, amplitude=%g: estimate=%g valid=%d.', ...
            frequency,amplitude,e.EstimateHz,e.Valid);
        assert(isequal(before,received), ...
            'Diagnostic must not rotate or otherwise modify original samples.');
        k=k+1; rows{k}=struct('CFOInjectedHz',frequency,'Amplitude',amplitude, ...
            'DetectedPreamble',det.DetectedPreambleIndex, ...
            'EstimatedHz',e.EstimateHz,'AmbiguityHalfWidthHz',e.AmbiguityRange_Hz, ...
            'CandidateCount',det.CandidateCount,'RxBranches',2);
    end
end
% Separately exercise the diagnostic's numerical scale invariance below
% the native detector's supported numerical range. Identity/timing here
% are declared component inputs, NOT a claimed native detection at 1e-12.
for frequency=[-400 0 400]
    x=1e-12*unit.*exp(1i*2*pi*frequency*time);
    e=sixgr.rach.estimateFrequencyOffset([x -x],unit,tx.SampleRate_Hz);
    assert(e.Valid && abs(e.EstimateHz-frequency)<1e-3);
end
disabled=cfg; disabled.random_access.enable_frequency_estimation_metric=false;
d=sixgr.phy.ra.detectConfiguredPRACH([unit -unit],disabled,receiver,occasion);
assert(d.Detected && ~d.FrequencyEstimationEnabled && ...
    ~d.FrequencyEstimate.Valid && isnan(d.FrequencyEstimate.EstimateHz) && ...
    d.FrequencyEstimate.Estimator=="disabled");
empty=sixgr.phy.ra.detectConfiguredPRACH(zeros(size(unit,1),2),cfg,receiver,occasion);
assert(~empty.Detected && empty.FrequencyEstimationEnabled && ...
    ~empty.FrequencyEstimate.Valid && isnan(empty.FrequencyEstimate.EstimateHz) && ...
    empty.FrequencyEstimate.Estimator=="unavailable_without_prach_detection");
% Standalone numerical validity: not a confidence or detection test.
for invalid={zeros(size(unit)),nan(size(unit)),inf(size(unit))}
    e=sixgr.rach.estimateFrequencyOffset(invalid{1},unit,tx.SampleRate_Hz);
    assert(~e.Valid && isnan(e.EstimateHz));
end
result=struct('Rows',struct2table(vertcat(rows{:})), ...
    'Scope',"native_B4_unit_channel_diagnostic_not_frequency_control_or_statistics", ...
    'NativeDetectorAmplitudeRangeTested',[1e-6 1], ...
    'DiagnosticOnlyAmplitudeBelowNativeRange',1e-12, ...
    'NativeDetectorUnboundedScaleQualification',false, ...
    'EvidenceFolder',string(folder));
save(fullfile(folder,'frequency_diagnostic.mat'),'result','tx','occasion');
writetable(result.Rows,fullfile(folder,'frequency_diagnostic.csv'));
ok=true;
fprintf('PRACH_B4_FREQUENCY_DIAGNOSTIC_PASS %s\n',folder);
end
