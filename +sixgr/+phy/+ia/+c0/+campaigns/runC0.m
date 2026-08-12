function result = runC0(configPath,runMode,varargin)
%RUNC0 Execute Phase-1 C0 in the production initial-access namespace.
p=inputParser;
p.addParameter("OutputRoot","",@(x)ischar(x)||isstring(x));
p.addParameter("RunId","",@(x)ischar(x)||isstring(x));
p.parse(varargin{:});
[cfg,configMeta]=sixgr.phy.ia.c0.config.loadScenario( ...
    string(configPath),string(runMode));
bundle=sixgr.phy.ia.c0.waveform.buildNRAnchorA(cfg);
cfg.runtime=struct("sample_rate_hz",bundle.SampleRateHz);

outputRoot=string(p.Results.OutputRoot);
if strlength(outputRoot)==0, outputRoot=string(cfg.output.root); end
runId=string(p.Results.RunId);
if strlength(runId)==0
    runId="C0_"+string(cfg.run.mode)+"_"+string(datetime("now","Format","yyyyMMdd_HHmmss"));
end
runFolder=fullfile(char(outputRoot),char(runId));
if isfolder(runFolder) || isfile(runFolder)
    error("sixgr:phy:ia:c0:campaign:OutputExists", ...
        "Refusing to overwrite C0 output: %s.",runFolder);
end
mkdir(runFolder); mkdir(fullfile(runFolder,"figures")); mkdir(fullfile(runFolder,"logs"));
sixgr.lls6g.config.writeYAML(fullfile(runFolder,"config_resolved.yaml"),cfg);
for k=1:numel(configMeta.SourceFiles)
    copyfile(configMeta.SourceFiles(k),fullfile(runFolder,sprintf("config_source_%02d.yaml",k)));
end

fprintf('C0 %s: calibrating global false alarm with %d independent noise windows...\n', ...
    cfg.run.mode,cfg.false_alarm.calibration_trials);
calibration=sixgr.phy.ia.c0.search.calibrateGlobalFalseAlarm(bundle,cfg);
faValidation=sixgr.phy.ia.c0.search.validateGlobalFalseAlarm( ...
    bundle,cfg,calibration.Threshold);
localWriteFalseAlarm(runFolder,calibration,faValidation);

snrGrid=unique(double(cfg.snr.coarse_grid_db(:).'),"sorted");
raw=table();
for snr=snrGrid
    [raw,newRows]=localRunPoint(raw,bundle,cfg,snr,calibration.Threshold,runFolder);
    fprintf('[C0][%s][A20RB4][%s][practical][%+.2fdB] trials=%d complete_errors=%d status=SIMULATED\n', ...
        configMeta.ConfigHash,cfg.waveform.normalization,snr,height(newRows),nnz(~newRows.CompleteSSBSuccess));
end
points=localAggregate(raw,cfg);

if any(strcmpi(string(cfg.run.mode),["tdoc" "exhaustive"]))
    [raw,points]=localExtendAndRefine(raw,points,bundle,cfg,calibration.Threshold,runFolder);
end
crossings=sixgr.phy.ia.c0.metrics.buildCrossingTable(points,cfg);
writetable(raw,fullfile(runFolder,"raw_trials.csv"));
writetable(points,fullfile(runFolder,"points.csv"));
writetable(crossings,fullfile(runFolder,"target_crossings.csv"));
save(fullfile(runFolder,"raw.mat"),"raw","points","crossings","calibration","faValidation","cfg","configMeta","-v7.3");

resource=table(string(bundle.ResourceAudit.Candidate),bundle.ResourceAudit.PSSRE, ...
    bundle.ResourceAudit.SSSRE,bundle.ResourceAudit.PBCHRE,bundle.ResourceAudit.DMRSRE, ...
    bundle.ResourceAudit.ActiveRE,bundle.ResourceAudit.ReservedUnusedRE, ...
    bundle.ResourceAudit.TotalEnergy,bundle.ResourceAudit.MeanActiveREEPRE, ...
    string(cfg.waveform.normalization),bundle.ResourceAudit.Normalization.Scale, ...
    bundle.ResourceAudit.Normalization.ClosureDB,string(bundle.ResourceAudit.ResourceMapSHA256), ...
    'VariableNames',{'Candidate','PSSRE','SSSRE','PBCHRE','DMRSRE','ActiveRE', ...
    'UnusedRE','TotalEnergy','MeanActiveREEPRE','Normalization','Scale','ClosureDB','ResourceMapSHA256'});
writetable(resource,fullfile(runFolder,"resource_audit.csv"));

zeroCfg=cfg;
zeroCfg.channel.model="AWGN"; zeroCfg.channel.delay_profile="AWGN";
zeroCfg.oscillator.ue_ppm_range=[0 0]; zeroCfg.oscillator.trp_ppm_range=[0 0];
zeroCfg.search.cfo_hypotheses_hz=0; zeroCfg.search.timing_uncertainty_samples=0;
zeroAnchor=sixgr.phy.ia.c0.campaigns.runC0Trial( ...
    bundle,zeroCfg,35,999001,calibration.Threshold);
writetable(struct2table(zeroAnchor,"AsArray",true),fullfile(runFolder,"zero_impairment_anchor.csv"));

lineage=sixgr.phy.ia.c0.plots.renderC0Figures( ...
    runFolder,cfg,calibration,faValidation,raw,points,crossings);
writetable(lineage,fullfile(runFolder,"figure_lineage.csv"));
[gates,summary]=sixgr.phy.ia.c0.validation.validateC0( ...
    cfg,bundle,calibration,faValidation, ...
    raw,points,crossings,zeroAnchor,lineage);
writetable(gates,fullfile(runFolder,"truth_contract.csv"));
verification=sixgr.phy.ia.c0.util.verifyFigureLineage(runFolder,lineage);
writetable(verification,fullfile(runFolder,"artifact_verification.csv"));
manifest=sixgr.phy.ia.c0.util.buildManifest( ...
    cfg,configMeta,runFolder,height(raw),height(lineage));
manifest.SmokeOrEngineeringPass=logical(summary.SmokeOrEngineeringPass);
manifest.TDocPass=logical(summary.TDocPass);
manifest.TruthGatesPassed=double(summary.PassedApplicableGates);
manifest.TruthGatesApplicable=double(summary.ApplicableGateCount);
manifest.ArtifactVerificationPassed=all(verification.Pass);
manifest.GlobalFalseAlarmValidationPassed=logical(faValidation.Passed);
sixgr.util.writeTextFile(fullfile(runFolder,"manifest.json"), ...
    jsonencode(manifest,"PrettyPrint",true),"MimeType","application/json");
sixgr.phy.ia.c0.util.writeC0Report( ...
    runFolder,cfg,summary,faValidation,points,crossings);

result=struct("RunFolder",string(runFolder),"Config",cfg,"Bundle",bundle, ...
    "Calibration",calibration,"FalseAlarmValidation",faValidation, ...
    "RawTrials",raw,"Points",points,"Crossings",crossings,"TruthGates",gates, ...
    "ArtifactVerification",verification,"Manifest",manifest, ...
    "Passed",logical(summary.SmokeOrEngineeringPass)&&all(verification.Pass), ...
    "TDocPass",logical(summary.TDocPass)&&all(verification.Pass));
end

function [raw,newRows]=localRunPoint(raw,bundle,cfg,snr,threshold,runFolder)
maxTrials=double(cfg.run.max_trials_per_snr); minErrors=double(cfg.run.min_errors_per_snr);
rows=cell(maxTrials,1); jointErrors=0; pbchErrors=0; completeErrors=0; n=0;
for trial=1:maxTrials
    n=n+1; rows{n}=sixgr.phy.ia.c0.campaigns.runC0Trial( ...
        bundle,cfg,snr,trial,threshold);
    jointErrors=jointErrors+~(rows{n}.PSSDetected&&rows{n}.PSSIdentityCorrect&&rows{n}.SSSCorrect);
    pbchErrors=pbchErrors+(rows{n}.PBCHAttempted&&~rows{n}.PBCHOk);
    completeErrors=completeErrors+~rows{n}.CompleteSSBSuccess;
    if mod(trial,double(cfg.run.checkpoint_interval))==0
        partial=struct2table(vertcat(rows{1:n}),"AsArray",true);
        checkpoint=[raw;partial]; %#ok<NASGU>
        save(fullfile(runFolder,"checkpoint.mat"),"checkpoint","-v7.3");
    end
    if trial>=1 && jointErrors>=minErrors && pbchErrors>=minErrors && completeErrors>=minErrors
        break;
    end
end
newRows=struct2table(vertcat(rows{1:n}),"AsArray",true);
raw=[raw;newRows];
writetable(raw,fullfile(runFolder,"raw_trials_checkpoint.csv"));
end

function points=localAggregate(raw,cfg)
snrs=unique(raw.SNRDB,"sorted"); confidence=double(cfg.statistics.confidence_level);
rows=cell(numel(snrs),1);
for k=1:numel(snrs)
    T=raw(raw.SNRDB==snrs(k),:); n=height(T);
    pssErr=nnz(~(T.PSSDetected&T.PSSIdentityCorrect));
    jointErr=nnz(~(T.PSSDetected&T.PSSIdentityCorrect&T.SSSCorrect));
    cond=T.PSSDetected&T.PSSIdentityCorrect; condN=nnz(cond); condErr=nnz(cond&~T.SSSCorrect);
    pbchN=nnz(T.PBCHAttempted); pbchErr=nnz(T.PBCHAttempted&~T.PBCHOk);
    wrong=nnz(T.WrongPCI); completeErr=nnz(~T.CompleteSSBSuccess);
    oracleErr=nnz(~T.OracleCompleteSSBSuccess);
    a=sixgr.phy.ia.c0.metrics.binomialCI(pssErr,n,confidence);
    b=sixgr.phy.ia.c0.metrics.binomialCI(jointErr,n,confidence);
    c=sixgr.phy.ia.c0.metrics.binomialCI(condErr,condN,confidence);
    d=sixgr.phy.ia.c0.metrics.binomialCI(pbchErr,pbchN,confidence);
    e=sixgr.phy.ia.c0.metrics.binomialCI(wrong,n,confidence);
    f=sixgr.phy.ia.c0.metrics.binomialCI(completeErr,n,confidence);
    g=sixgr.phy.ia.c0.metrics.binomialCI(oracleErr,n,confidence);
    rows{k}=struct("SNRDB",snrs(k),"Trials",n, ...
        "PSSMissErrors",pssErr,"PSSMissProbability",a.Estimate,"PSSMissCILow",a.CILow,"PSSMissCIHigh",a.CIHigh, ...
        "JointSSErrors",jointErr,"JointSSMDR",b.Estimate,"JointSSCILow",b.CILow,"JointSSCIHigh",b.CIHigh, ...
        "ConditionalSSSTrials",condN,"ConditionalSSSErrors",condErr,"ConditionalSSSError",c.Estimate, ...
        "ConditionalSSSCILow",c.CILow,"ConditionalSSSCIHigh",c.CIHigh, ...
        "PBCHTrials",pbchN,"PBCHErrors",pbchErr,"PBCHBLER",d.Estimate,"PBCHCILow",d.CILow,"PBCHCIHigh",d.CIHigh, ...
        "WrongPCIErrors",wrong,"WrongPCIProbability",e.Estimate, ...
        "WrongPCICILow",e.CILow,"WrongPCICIHigh",e.CIHigh, ...
        "CompleteSSBErrors",completeErr,"CompleteSSBSuccessProbability",1-f.Estimate, ...
        "CompleteSSBSuccessCILow",1-f.CIHigh,"CompleteSSBSuccessCIHigh",1-f.CILow, ...
        "OracleCompleteSSBSuccessProbability",mean(T.OracleCompleteSSBSuccess), ...
        "OracleCompleteSSBSuccessCILow",1-g.CIHigh, ...
        "OracleCompleteSSBSuccessCIHigh",1-g.CILow, ...
        "MeanMeasuredInputSNRDB",mean(T.MeasuredInputSNRDB,"omitnan"), ...
        "TimingRMSESamples",sqrt(mean(T.TimingErrorSamples.^2,"omitnan")), ...
        "CFORMSEHz",sqrt(mean(T.CFOErrorHz.^2,"omitnan")), ...
        "ChannelEstimateNMSE",mean(T.ChannelEstimateNMSE,"omitnan"), ...
        "MeanSearchHypotheses",mean(T.SearchHypotheses,"omitnan"), ...
        "MeanDMRSHypotheses",mean(T.DMRSHypothesesTested,"omitnan"), ...
        "MeanPolarDecodes",mean(T.PolarDecodes,"omitnan"), ...
        "Status","SIMULATED","EvidenceClass","actual_nr_ssb_waveform_receiver_truth");
end
points=struct2table(vertcat(rows{:}),"AsArray",true);
end

function [raw,points]=localExtendAndRefine(raw,points,bundle,cfg,threshold,runFolder)
while true
    c=sixgr.phy.ia.c0.metrics.buildCrossingTable(points,cfg);
    missing=c(~c.Bracketed,:); next=[];
    for k=1:height(missing)
        values=points.(char(missing.Metric(k))); target=missing.Target(k);
        if all(values>target) && max(points.SNRDB)<double(cfg.snr.maximum_db)
            next=max(points.SNRDB)+double(cfg.snr.extension_step_db); break;
        elseif all(values<target) && min(points.SNRDB)>double(cfg.snr.minimum_db)
            next=min(points.SNRDB)-double(cfg.snr.extension_step_db); break;
        end
    end
    if isempty(next), break; end
    [raw,~]=localRunPoint(raw,bundle,cfg,next,threshold,runFolder); points=localAggregate(raw,cfg);
end
c=localCrossings(points,cfg); refined=[];
for k=1:height(c)
    if c.Bracketed(k) && c.LowerSNRDB(k)~=c.UpperSNRDB(k)
        refined=[refined c.LowerSNRDB(k):double(cfg.snr.refinement_step_db):c.UpperSNRDB(k)]; %#ok<AGROW>
    end
end
refined=setdiff(unique(refined),points.SNRDB);
for snr=refined
    [raw,~]=localRunPoint(raw,bundle,cfg,snr,threshold,runFolder);
end
points=localAggregate(raw,cfg);
end

function localWriteFalseAlarm(folder,cal,val)
T=table((1:cal.TrialCount)',cal.Metrics,repmat(cal.Threshold,cal.TrialCount,1), ...
    cal.Metrics>=cal.Threshold,'VariableNames',{'Trial','MaximumStatistic','Threshold','Exceeded'});
writetable(T,fullfile(folder,"false_alarm_calibration.csv"));
V=table((1:val.TrialCount)',val.Metrics,repmat(val.Threshold,val.TrialCount,1), ...
    val.Metrics>=val.Threshold,'VariableNames',{'Trial','MaximumStatistic','Threshold','FalseAlarm'});
writetable(V,fullfile(folder,"false_alarm_validation.csv"));
S=table(val.TrialCount,val.FalseAlarms,val.EmpiricalPFA,val.CILow,val.CIHigh,val.TargetPFA,val.Passed, ...
    'VariableNames',{'Trials','FalseAlarms','EmpiricalPFA','CILow','CIHigh','TargetPFA','Passed'});
writetable(S,fullfile(folder,"false_alarm_summary.csv"));
end
