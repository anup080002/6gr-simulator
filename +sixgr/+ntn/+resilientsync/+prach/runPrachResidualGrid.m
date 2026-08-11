function result = runPrachResidualGrid(scenario,runDirectory)
%RUNPRACHRESIDUALGRID Calibrate and execute the canonical PRACH receiver.

capabilities=sixgr.ntn.resilientsync.prach.discoverPrachCapabilities();
source=string(scenario.physical_layer.prach_scenario_config);
resolved=sixgr.lls6g.config.loadScenarioConfig(source);
base=resolved.toStruct();
nTrials=double(scenario.physical_layer.prach_trials_min);
target=double(scenario.physical_layer.pfa_total);
batch=min(1000,nTrials);
looks=ceil(nTrials/batch);
% The canonical strict PRACH receiver requires an enabled statistical
% design even for a quick wiring run.  The run-mode distinction is the
% YAML-owned trial budget, not a hidden bypass of the qualification path.
% A quick result remains labelled quick and cannot satisfy the TDoc budget
% gate; its finite-sample confidence interval is exported without being
% promoted to publication evidence.
base.random_access.statistical_qualification.enabled=true;
base.random_access.statistical_qualification.target_false_alarm_probability=target;
base.random_access.statistical_qualification.confidence_level=double(scenario.physical_layer.confidence_level);
base.random_access.statistical_qualification.minimum_trials=nTrials;
base.random_access.statistical_qualification.maximum_trials=nTrials;
base.random_access.statistical_qualification.batch_size_trials=batch;
base.random_access.statistical_qualification.minimum_false_alarm_events=0;
base.random_access.statistical_qualification.ci_width_target=max(target,1/nTrials);
base.random_access.statistical_qualification.planned_looks=looks;
base.random_access.statistical_qualification.target_missed_detection_probability=0.01;
base.random_access.statistical_qualification.required_detection_snr_db=double(base.random_access.snr_sweep_db(end));
base.random_access.statistical_qualification.minimum_detection_trials=nTrials;
base.random_access.statistical_qualification.maximum_detection_trials=nTrials;
base.random_access.statistical_qualification.batch_size_detection_trials=batch;
base.random_access.statistical_qualification.minimum_missed_detection_events=0;
base.random_access.statistical_qualification.detection_ci_width_target=max(0.01,1/nTrials);
base.random_access.statistical_qualification.detection_planned_looks=looks;
base.random_access.statistical_qualification.deterministic_seeds=double(scenario.seed)+(1:4);
tmp=sixgr.phy.prach.buildPRACHConfigFromScenario(base, ...
    "RunFolder",fullfile(char(runDirectory),'raw','campaign_c_prach'), ...
    "ScenarioName",string(scenario.campaign_name));
frequencyHypotheses=double(scenario.residual_grid.frequency_error_khz(:))*1e3;
calibration=sixgr.ntn.resilientsync.prach.calibrateFalseAlarmThreshold( ...
    tmp,target,nTrials,frequencyHypotheses, ...
    double(scenario.seed)+7000);
base.random_access.detection_threshold_mode='fixed';
base.random_access.detection_threshold=double(calibration.Threshold);
folder=fullfile(char(runDirectory),'raw','campaign_c_prach');
if exist(folder,'dir')~=7,mkdir(folder);end
strict=sixgr.phy.prach.runStrictPRACHValidation(base,"RunFolder",folder, ...
    "RunId",string(scenario.RunId)+"_prach", ...
    "ScenarioName",string(scenario.campaign_name),"WriteArtifacts",true);
if ~logical(strict.StrictOk)
    error("sixgr:ntn:resilientsync:PRACHStrictValidationFailed", ...
        "Canonical PRACH validation failed after global-threshold calibration.");
end
residual=localResidualGrid(tmp,calibration.Threshold,scenario,runDirectory,frequencyHypotheses);
tables=struct("prach_capabilities",capabilities, ...
    "prach_false_alarm_calibration",calibration.SummaryTable, ...
    "prach_false_alarm_calibration_trials",calibration.TrialTable, ...
    "prach_residual_summary",residual.SummaryTable, ...
    "prach_residual_trial_file_index",residual.FileIndex);
names=fieldnames(strict.ArtifactTables);
for index=1:numel(names)
    tables.(names{index})=strict.ArtifactTables.(names{index});
end
artifactNames=string(fieldnames(tables));
evidence=table(artifactNames,repmat("CALIBRATED_LLS",numel(artifactNames),1), ...
    true(numel(artifactNames),1),repmat("PRODUCED",numel(artifactNames),1), ...
    'VariableNames',{'Artifact','EvidenceClass','Measured','Status'});
result=struct("Campaign","C","Status","COMPLETE","Tables",tables, ...
    "Evidence",evidence,"StrictResult",strict);
end

function result=localResidualGrid(cfg,threshold,scenario,runDirectory,frequencyHypotheses)
occasion=sixgr.rach.mapPRACHToOccasion(cfg,"OccasionIndex",1);
preamble=double(cfg.PreambleIndex(1));
tx=sixgr.phy.prach.generatePRACHWaveform(cfg,"Occasion",occasion,"PreambleIndex",preamble);
timingS=double(scenario.residual_grid.timing_error_us(:))*1e-6;
timingSamples=round(timingS*double(tx.SampleRate_Hz));
frequency=double(scenario.residual_grid.frequency_error_khz(:))*1e3;
snrValues=double(scenario.physical_layer.residual_snr_db(:));
pointCount=numel(timingS)*numel(frequency)*numel(snrValues);
if string(scenario.run_mode)=="quick"
    trialsPerPoint=max(2,ceil(double(scenario.physical_layer.prach_trials_min)/pointCount));
else
    trialsPerPoint=double(scenario.physical_layer.prach_trials_min);
end
candidatePreambles=0:min(63,double(cfg.NumPreambles)-1);
summaryRows=cell(pointCount,1);indexRows=cell(pointCount,1);point=0;
folder=fullfile(char(runDirectory),'raw','campaign_c_prach_residual');
if exist(folder,'dir')~=7,mkdir(folder);end
t=(0:size(tx.Waveform,1)-1).'./double(tx.SampleRate_Hz);
signalPower=mean(abs(tx.Waveform(:)).^2);
for ti=1:numel(timingS)
    shifted=localShift(tx.Waveform,timingSamples(ti));
    for fi=1:numel(frequency)
        impaired=shifted.*exp(1i*2*pi*frequency(fi).*t);
        for si=1:numel(snrValues)
            point=point+1;stream=RandStream('mt19937ar','Seed', ...
                double(scenario.seed)+800000+point);
            rows=cell(trialsPerPoint,1);
            noiseVariance=signalPower/10^(snrValues(si)/10);
            for trial=1:trialsPerPoint
                noise=sqrt(noiseVariance/2)*(randn(stream,size(impaired))+ ...
                    1i*randn(stream,size(impaired)));
                rx=impaired+noise;best=[];bestMetric=-Inf;bestHypothesis=NaN;
                for hypothesis=double(frequencyHypotheses(:)).'
                    corrected=rx.*exp(-1i*2*pi*hypothesis.*t);
                    det=sixgr.phy.prach.detectPRACHWaveform(corrected,cfg, ...
                        "Occasion",occasion,"CandidatePreambles",candidatePreambles, ...
                        "DetectionThreshold",threshold,"DetectorBackend","toolbox_peak");
                    if double(det.PeakMetric)>bestMetric
                        best=det;bestMetric=double(det.PeakMetric);bestHypothesis=hypothesis;
                    end
                end
                detected=bestMetric>=threshold && ...
                    double(best.DetectedPreambleIndex)==preamble;
                estimatedTiming=double(sixgr.util.structGet(best,'TimingOffsetSamples',NaN));
                rows{trial}=struct('Trial',trial,'TimingError_s',timingS(ti), ...
                    'TimingError_samples',timingSamples(ti),'FrequencyError_Hz',frequency(fi), ...
                    'SNR_dB',snrValues(si),'Detected',detected, ...
                    'DetectedPreambleIndex',double(best.DetectedPreambleIndex), ...
                    'PeakMetric',bestMetric,'Threshold',threshold, ...
                    'EstimatedTiming_samples',estimatedTiming, ...
                    'TimingEstimateError_samples',estimatedTiming-timingSamples(ti), ...
                    'SelectedFrequencyHypothesis_Hz',bestHypothesis, ...
                    'PostSearchFrequencyResidual_Hz',frequency(fi)-bestHypothesis, ...
                    'ReceiverOracleUsed',false,'ExecutionBackend','waveform_truth', ...
                    'ApproximationMode','none','Provenance','CALIBRATED_LLS');
            end
            trials=struct2table(vertcat(rows{:}));
            detections=sum(trials.Detected);misses=trialsPerPoint-detections;
            [lo,hi]=sixgr.lls.stats.wilsonInterval(detections,trialsPerPoint, ...
                double(scenario.physical_layer.confidence_level));
            finiteTiming=trials.TimingEstimateError_samples(isfinite(trials.TimingEstimateError_samples));
            if isempty(finiteTiming),timingBias=NaN;timingRMSE=NaN;else
                timingBias=mean(finiteTiming);timingRMSE=sqrt(mean(finiteTiming.^2));end
            summaryRows{point}={timingS(ti),timingSamples(ti),frequency(fi),snrValues(si), ...
                trialsPerPoint,detections,misses,detections/trialsPerPoint,lo,hi, ...
                timingBias,timingRMSE,mean(abs(trials.PostSearchFrequencyResidual_Hz)), ...
                threshold,"CALIBRATED_LLS"};
            file=sprintf('prach_t%+gus_f%+gkhz_snr%+gdb.csv', ...
                timingS(ti)*1e6,frequency(fi)/1e3,snrValues(si));
            file=regexprep(file,'[^A-Za-z0-9_.-]','_');path=fullfile(folder,file);
            writetable(trials,path);
            indexRows{point}={replace(string(path),string(runDirectory)+filesep,""), ...
                height(trials),detections,misses,localFileHash(path), ...
                timingS(ti),frequency(fi),snrValues(si),"CALIBRATED_LLS"};
        end
    end
end
summary=cell2table(vertcat(summaryRows{:}),'VariableNames', ...
    {'ResidualTimingError_s','ResidualTimingError_samples','ResidualFrequencyError_Hz', ...
    'SNR_dB','NumTrials','NumDetections','NumMisses','DetectionProbability', ...
    'WilsonLower','WilsonUpper','TimingBias_samples','TimingRMSE_samples', ...
    'MeanAbsolutePostSearchFrequencyResidual_Hz','DetectionThreshold','Provenance'});
summary.Properties.VariableUnits={'s','sample','Hz','dB','','','','1','1','1', ...
    'sample','sample','Hz','',''};
indexTable=cell2table(vertcat(indexRows{:}),'VariableNames', ...
    {'RelativePath','Rows','Detections','Misses','SHA256','ResidualTimingError_s', ...
    'ResidualFrequencyError_Hz','SNR_dB','Provenance'});
indexTable.Properties.VariableUnits={'','','','','','s','Hz','dB',''};
result=struct('SummaryTable',summary,'FileIndex',indexTable);
end

function shifted=localShift(waveform,offset)
n=size(waveform,1);shifted=zeros(size(waveform),'like',waveform);
if offset>=0
    if offset<n,shifted(offset+1:end,:)=waveform(1:end-offset,:);end
else
    advance=-offset;if advance<n,shifted(1:end-advance,:)=waveform(advance+1:end,:);end
end
end

function digest=localFileHash(path)
fid=fopen(path,'rb');if fid<0,error('sixgr:ntn:resilientsync:ArtifactReadFailed','Cannot hash %s.',path);end
cleanup=onCleanup(@()fclose(fid)); %#ok<NASGU>
digest=sixgr.util.sha256Hex(fread(fid,Inf,'*uint8'));
end
