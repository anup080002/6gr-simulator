function calibration = calibrateGlobalFalseAlarm(bundle,cfg,varargin)
%CALIBRATEGLOBALFALSEALARM Calibrate the complete cell-with-PCI declaration.
% Receiver exceptions fail closed: they are never counted as benign
% no-declaration outcomes. Optional checkpoints expose exact progress and
% allow deterministic continuation without reusing or skipping a window.
p=inputParser;
p.addParameter("CheckpointPath","",@(x)ischar(x)||isstring(x));
p.addParameter("ProgressCSVPath","",@(x)ischar(x)||isstring(x));
p.parse(varargin{:});
checkpointPath=string(p.Results.CheckpointPath);
progressPath=string(p.Results.ProgressCSVPath);
nTrials=double(cfg.false_alarm.calibration_trials);
nRx=double(cfg.mimo.num_rx_antennas);
guard=double(cfg.search.timing_uncertainty_samples);
nSamples=size(bundle.Waveform,1)+2*guard;
seed0=double(cfg.run.seed_set_calibration);
seeds=seed0+(1:nTrials)';
searchHash=string(sixgr.util.sha256Hex(uint8( ...
    unicode2native(jsonencode(cfg.search),"UTF-8"))));
[pssMetrics,jointMetrics,sssMetrics,completed]=localRestore( ...
    checkpointPath,nTrials,seed0,searchHash);
progressEvery=double(cfg.false_alarm.progress_interval);
checkpointEvery=double(cfg.false_alarm.checkpoint_interval);
started=tic;
old=rng;
cleanup=onCleanup(@()rng(old)); %#ok<NASGU>
for trial=completed+1:nTrials
    rng(seeds(trial),"twister");
    noise=(randn(nSamples,nRx)+1j*randn(nSamples,nRx))/sqrt(2);
    try
        [~,sync]=sixgr.phy.dl.SSB_Rx(noise, ...
            localPHYConfig(cfg,bundle.SampleRateHz), ...
            "SampleRate_Hz",bundle.SampleRateHz);
        d=sixgr.phy.ia.c0.receiver.declarationMetrics(sync,cfg, ...
            struct("PSSStageThreshold",-Inf, ...
            "GlobalDeclarationThreshold",-Inf));
    catch ME
        localCheckpoint(checkpointPath,pssMetrics,jointMetrics,sssMetrics, ...
            trial-1,nTrials,seed0,searchHash);
        localProgress(progressPath,"CALIBRATION","FAILED",trial-1,nTrials, ...
            seed0,seeds(max(trial-1,1)),toc(started),1,NaN,ME.identifier);
        failure=MException("sixgr:phy:ia:c0:falseAlarm:CalibrationReceiverFailure", ...
            "Complete blind receiver failed at calibration window %d (seed %.0f): %s | %s", ...
            trial,seeds(trial),ME.identifier,ME.message);
        failure=addCause(failure,ME);
        throw(failure);
    end
    pssMetrics(trial)=d.PSSMetric;
    sssMetrics(trial)=d.SSSNormalizedMetric;
    jointMetrics(trial)=d.JointDeclarationStatistic;
    if mod(trial,progressEvery)==0 || trial==nTrials
        localProgress(progressPath,"CALIBRATION","RUNNING",trial,nTrials, ...
            seed0,seeds(trial),toc(started),0,NaN,"");
        fprintf('[C0][%s][FA_CALIBRATION] completed=%d/%d (%.3f%%) seed=%.0f exceptions=0\n', ...
            upper(string(cfg.run.mode)),trial,nTrials,100*trial/nTrials,seeds(trial));
    end
    if mod(trial,checkpointEvery)==0 || trial==nTrials
        localCheckpoint(checkpointPath,pssMetrics,jointMetrics,sssMetrics, ...
            trial,nTrials,seed0,searchHash);
    end
end
[pssThreshold,pssOrderIndex]=localOrderThreshold( ...
    pssMetrics,double(cfg.false_alarm.pss_stage_target_probability));
finalStatistics=jointMetrics;
finalStatistics(pssMetrics<pssThreshold)=-Inf;
[globalThreshold,globalOrderIndex]=localOrderThreshold( ...
    finalStatistics,double(cfg.false_alarm.target_probability));
thresholds=struct("PSSStageThreshold",double(pssThreshold), ...
    "GlobalDeclarationThreshold",double(globalThreshold));
localProgress(progressPath,"CALIBRATION","COMPLETE",nTrials,nTrials, ...
    seed0,seeds(end),toc(started),0,nnz(finalStatistics>=globalThreshold),"");
calibration=struct("Threshold",double(globalThreshold), ...
    "Thresholds",thresholds,"PSSStageThreshold",double(pssThreshold), ...
    "Metrics",finalStatistics,"PSSMetrics",pssMetrics, ...
    "SSSMetrics",sssMetrics,"JointMetricsBeforePSSStage",jointMetrics, ...
    "Seeds",seeds,"SeedFirst",seeds(1),"SeedLast",seeds(end), ...
    "TargetPFA",double(cfg.false_alarm.target_probability), ...
    "PSSStageTargetPFA",double(cfg.false_alarm.pss_stage_target_probability), ...
    "TrialCount",nTrials,"ReceiverExceptionCount",0, ...
    "ExceedanceCount",nnz(finalStatistics>=globalThreshold), ...
    "PSSStageExceedanceCount",nnz(pssMetrics>=pssThreshold), ...
    "ThresholdOrderStatisticIndex",double(globalOrderIndex), ...
    "PSSStageThresholdOrderStatisticIndex",double(pssOrderIndex), ...
    "SeedBase",seed0,"Statistic",string(cfg.search.declaration_statistic), ...
    "DeclarationPath","blind_pss_timing_cfo_nid2_then_all_pci_sss_confirmation", ...
    "SearchConfigurationHash",searchHash);
end

function [pss,joint,sss,completed]=localRestore(path,nTrials,seedBase,searchHash)
pss=-inf(nTrials,1); joint=-inf(nTrials,1); sss=nan(nTrials,1); completed=0;
if strlength(path)==0 || ~isfile(path), return; end
saved=load(path,"checkpoint");
if ~isfield(saved,"checkpoint") || ...
        saved.checkpoint.TotalTrials~=nTrials || ...
        saved.checkpoint.SeedBase~=seedBase || ...
        string(saved.checkpoint.SearchHash)~=searchHash
    error("sixgr:phy:ia:c0:falseAlarm:CheckpointMismatch", ...
        "Calibration checkpoint does not match the resolved trial count, seed partition, or search configuration.");
end
checkpoint=saved.checkpoint;
completed=double(checkpoint.CompletedTrials);
pss=checkpoint.PSSMetrics; joint=checkpoint.JointMetrics;
sss=checkpoint.SSSMetrics;
end

function localCheckpoint(path,pss,joint,sss,completed,total,seedBase,searchHash)
if strlength(path)==0, return; end
checkpoint=struct("Stage","CALIBRATION","CompletedTrials",completed, ...
    "TotalTrials",total,"SeedBase",seedBase,"SearchHash",searchHash, ...
    "PSSMetrics",pss,"JointMetrics",joint,"SSSMetrics",sss); %#ok<NASGU>
save(path,"checkpoint","-v7.3");
end

function localProgress(path,stage,status,completed,total,seedBase,lastSeed,elapsed,exceptions,alarms,errorID)
if strlength(path)==0, return; end
progress=table(string(stage),string(status),completed,total,100*completed/total, ...
    seedBase+1,lastSeed,elapsed,exceptions,alarms,string(errorID), ...
    string(datetime("now","TimeZone","UTC","Format","yyyy-MM-dd'T'HH:mm:ss.SSSXXX")), ...
    'VariableNames',{'Stage','Status','CompletedTrials','TotalTrials','Percent', ...
    'FirstSeed','LastCompletedSeed','InvocationElapsedSeconds', ...
    'ReceiverExceptions','FalseAlarmsSoFar','ErrorIdentifier','UpdatedUTC'});
writetable(progress,path);
end

function [threshold,index]=localOrderThreshold(values,targetPFA)
values=sort(double(values(:))); n=numel(values);
allowed=floor(double(targetPFA)*n);
if allowed<1
    index=n; threshold=values(end)+max(eps(values(end)),1e-12); return;
end
index=n-allowed;
if index<1
    threshold=-Inf;
elseif index==n
    threshold=values(n)+max(eps(values(n)),1e-12);
else
    threshold=0.5*(values(index)+values(index+1));
end
end

function cfgPHY=localPHYConfig(cfg,sampleRate)
cfgPHY=sixgr.phy.ia.c0.config.toPHYConfig(cfg);
cfgPHY.phy.sampleRate_Hz=double(sampleRate);
end
