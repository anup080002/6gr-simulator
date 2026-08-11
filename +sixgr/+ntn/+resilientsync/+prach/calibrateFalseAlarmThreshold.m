function result = calibrateFalseAlarmThreshold(cfg, targetPfa, trials, frequencyHypothesesHz, seed)
%CALIBRATEFALSEALARMTHRESHOLD Empirical global max-statistic calibration.

arguments
    cfg (1,1) struct
    targetPfa (1,1) double {mustBePositive,mustBeLessThan(targetPfa,1)}
    trials (1,1) double {mustBeInteger,mustBePositive}
    frequencyHypothesesHz (:,1) double
    seed (1,1) double {mustBeInteger,mustBeNonnegative}
end
occasion=sixgr.rach.mapPRACHToOccasion(cfg,"OccasionIndex",1);
preamble=double(cfg.PreambleIndex(1));
tx=sixgr.phy.prach.generatePRACHWaveform(cfg,"Occasion",occasion,"PreambleIndex",preamble);
candidatePreambles=0:(min(64,double(cfg.NumPreambles))-1);
stream=RandStream("mt19937ar","Seed",seed);
metric=zeros(trials,1);
t=(0:size(tx.Waveform,1)-1).'./double(tx.SampleRate_Hz);
for trial=1:trials
    noise=(randn(stream,size(tx.Waveform))+1i*randn(stream,size(tx.Waveform)))./sqrt(2);
    globalMetric=-Inf;
    for f=double(frequencyHypothesesHz(:)).'
        corrected=noise.*exp(-1i*2*pi*f.*t);
        detection=sixgr.phy.prach.detectPRACHWaveform(corrected,cfg, ...
            "Occasion",occasion,"CandidatePreambles",candidatePreambles, ...
            "DetectionThreshold",0,"DetectorBackend","toolbox_peak");
        globalMetric=max(globalMetric,double(detection.PeakMetric));
    end
    metric(trial)=globalMetric;
end
sorted=sort(metric);
order=min(trials,max(1,ceil((1-targetPfa)*(trials+1))));
threshold=sorted(order);
exceedances=sum(metric>threshold);
[lower,upper]=sixgr.lls.stats.wilsonInterval(exceedances,trials,0.95);
trialTable=table((1:trials).',metric,metric>threshold, ...
    repmat(seed,trials,1),repmat("CALIBRATED_LLS",trials,1), ...
    'VariableNames',{'Trial','GlobalMaximumMetric','ExceedsCalibratedThreshold','Seed','Provenance'});
trialTable.Properties.VariableUnits={'','','','',''};
summaryTable=table(targetPfa,trials,threshold,exceedances,exceedances/trials,lower,upper, ...
    numel(candidatePreambles),numel(frequencyHypothesesHz), ...
    string(mat2str(double(frequencyHypothesesHz(:).'))), ...
    "complete_candidate_and_configured_frequency_hypothesis_max", ...
    "CALIBRATED_LLS", ...
    'VariableNames',{'TargetGlobalPFA','CalibrationTrials','CalibratedThreshold', ...
    'CalibrationExceedances','CalibrationPFA','WilsonLower','WilsonUpper', ...
    'PreambleHypotheses','FrequencyHypotheses','FrequencyHypothesisValues_Hz', ...
    'SearchStatistic','Provenance'});
summaryTable.Properties.VariableUnits={'1','','','', '1','1','1','','','Hz','',''};
result=struct("Threshold",threshold,"TrialTable",trialTable,"SummaryTable",summaryTable);
end
