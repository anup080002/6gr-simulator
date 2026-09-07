function result=diagnosePRACHReceiverFromCapture(captureFile,outputFolder)
% Offline receiver diagnostic. Never modifies/promotes the original run.
% Noise-only trials qualify this detector/configuration, not RF conformance.
data=load(captureFile,'capture'); c=data.capture;
tx=c.ReceiverContinuation.Msg1Tx; cfg=c.ReceiverContinuation.Config;
q=cfg.lls6g.resolvedConfig.random_access.statistical_qualification;
validateattributes(q.maximum_trials,{'numeric'},{'scalar','integer','positive'});
validateattributes(q.deterministic_seeds,{'numeric'},{'vector','integer','nonnegative','finite'});
variance=c.ExecutionReplay.InjectedNoiseVariance;
validateattributes(variance,{'numeric'},{'scalar','real','positive','finite'});
if ~isfolder(outputFolder), mkdir(outputFolder); end
rows=struct([]);
waves={tx.Waveform,c.TXAfterRF,c.RXBeforeRF,c.RXAfterDigitalGainCompensation};
labels=["tx_logical_calibration","tx_physical_after_rf_calibration","rx_before_rf","rx_gain_compensated"];
for j=1:numel(waves)
    for mode=["configured_fixed","toolbox_default"]
        args={'PreambleIndex',0:63};
        if mode=="configured_fixed", args=[args,{'DetectionThreshold',cfg.random_access.detection_threshold}]; end
        [idx,offset,info]=nrPRACHDetect(tx.Carrier,tx.PRACH,waves{j},args{:});
        row=struct('Scope',"offline_actual_captured_iq_diagnostic",'Waveform',labels(j), ...
            'Policy',mode,'PeakMetric',max(info.CorrelationPeaks),'Threshold',info.DetectionThreshold, ...
            'Detected',~isempty(idx),'DecodedPreambleIndices',string(mat2str(idx)), ...
            'TimingOffsets_samples',string(mat2str(offset)),'ReceiveColumns',size(waves{j},2));
        rows=[rows;row]; %#ok<AGROW>
    end
end
captureT=struct2table(rows); writetable(captureT,fullfile(outputFolder,'captured_receiver_decisions.csv'));
% Fixed sample size declared before seeing outcomes. Progress reports are
% not sequential stopping looks and do not select/tune the threshold.
n=double(q.maximum_trials); seeds=double(q.deterministic_seeds(:));
metrics=zeros(n,1); thresholds=zeros(n,1); detected=false(n,1); usedSeeds=zeros(n,1);
streams=cell(numel(seeds),1);
for k=1:numel(seeds), streams{k}=RandStream('mt19937ar','Seed',seeds(k)); end
for k=1:n
    seedIndex=1+mod(k-1,numel(seeds)); stream=streams{seedIndex};
    w=sqrt(variance/2)*(randn(stream,size(c.RXAfterDigitalGainCompensation))+ ...
        1i*randn(stream,size(c.RXAfterDigitalGainCompensation)));
    [idx,~,info]=nrPRACHDetect(tx.Carrier,tx.PRACH,w,'PreambleIndex',0:63);
    metrics(k)=max(info.CorrelationPeaks); thresholds(k)=info.DetectionThreshold;
    detected(k)=~isempty(idx); usedSeeds(k)=seeds(seedIndex);
    if mod(k,double(q.batch_size_trials))==0
        fprintf('PRACH_NOISE_RECEIVER_PROGRESS %d/%d false_alarms=%d\n',k,n,nnz(detected(1:k)));
    end
end
trials=table((1:n).',usedSeeds,metrics,thresholds,detected, ...
    'VariableNames',{'Trial','Seed','MeasuredMaximumCorrelation','AppliedThreshold','FalseAlarm'});
writetable(trials,fullfile(outputFolder,'noise_only_detector_trials.csv'));
errors=nnz(detected); alpha=1-double(q.confidence_level);
lower=0; upper=1;
if errors>0, lower=betaincinv(alpha/2,errors,n-errors+1); end
if errors<n, upper=betaincinv(1-alpha/2,errors+1,n-errors); end
summary=table(n,errors,errors/n,lower,upper,double(q.confidence_level), ...
    double(q.target_false_alarm_probability),upper<=q.target_false_alarm_probability, ...
    variance,size(c.RXAfterDigitalGainCompensation,1),size(c.RXAfterDigitalGainCompensation,2), ...
    "actual_nrPRACHDetect_on_generated_complex_gaussian_noise", ...
    "receiver_algorithm_only_not_main_rf_or_detection_probability_qualification", ...
    'VariableNames',{'Trials','FalseAlarms','EmpiricalPFA','ExactCILower','ExactCIUpper', ...
    'Confidence','TargetPFA','PFAUpperBoundPass','NoiseVariance_mW','SamplesPerTrial','ReceiveColumns', ...
    'Source','QualificationScope'});
writetable(summary,fullfile(outputFolder,'noise_only_detector_summary.csv'));
result=struct('CaptureDecisions',captureT,'NoiseSummary',summary,'OutputFolder',string(outputFolder));
disp(summary); fprintf('PRACH_RECEIVER_DIAGNOSTIC=%s\n',outputFolder);
end
