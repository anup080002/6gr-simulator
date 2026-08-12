function result=run1083Validation(configPath,options)
%RUN1083VALIDATION Execute the complete versioned 10.8.3 validation chain.
%
% Stage 1 fails closed before comparative work. Later stages reuse the same
% configuration and output root. Screening evidence remains screening; this
% function never promotes it to publication evidence merely because all
% configured points executed.
arguments
    configPath (1,1) string = "configs/isac/joint_isac_tdoc_master.yaml"
    options.OutputRoot (1,1) string = ""
    options.RunId (1,1) string = ""
end
[cfg,sourcePath]=sixgr.isac.loadJointConfig(configPath);
if options.OutputRoot=="", outputRoot=string(fullfile(localRepoRoot(),"results"));
else, outputRoot=options.OutputRoot; end
if options.RunId==""
    runId="isac_10_8_3_validation_"+string(datetime("now","Format","yyyyMMdd_HHmmss"));
else, runId=options.RunId; end
runFolder=string(fullfile(outputRoot,runId)); localLayout(runFolder);
started=datetime("now","TimeZone","UTC");

stage1=sixgr.isac.run1083Stage1(sourcePath,"OutputRoot",outputRoot,"RunId",runId);
if ~stage1.Passed
    error("sixgr:isac:Stage1PhysicalGateFailed", ...
        "10.8.3 comparative stages cannot run because Stage 1 failed.");
end
comparative=sixgr.isac.run1083Comparative(sourcePath,"OutputRoot",outputRoot,"RunId",runId);
intrinsic=sixgr.isac.run1083Intrinsic(sourcePath,"OutputRoot",outputRoot,"RunId",runId);
stress=sixgr.isac.run1083Stress(sourcePath,"OutputRoot",outputRoot,"RunId",runId);
lineage=sixgr.isac.verify1083Artifacts(runFolder);

status=localStatus(cfg,stage1,comparative,intrinsic,stress,lineage);
writetable(status,fullfile(runFolder,"aggregate","validation_status.csv"));
classification=localClassification(cfg,status);
writetable(classification,fullfile(runFolder,"aggregate","result_classification.csv"));
[questions,decision]=localDecision(cfg,comparative,stress);
writetable(questions,fullfile(runFolder,"aggregate","w3_decision_questions.csv"));
localReport(runFolder,cfg,stage1,comparative,intrinsic,stress,status,questions,decision);
[sourceLineage,sourcePatchHash]=localSourceSnapshot(runFolder);

copyfile(sourcePath,fullfile(runFolder,"config_source.yaml"));
save(fullfile(runFolder,"config_snapshot.mat"),"cfg","-v7.3");
sixgr.util.jsonWrite(fullfile(runFolder,"config_snapshot.json"),cfg);
[~,gitCommit]=system("git rev-parse HEAD"); [~,gitStatus]=system("git status --porcelain");
gitCommit=strtrim(string(gitCommit)); gitDirty=strlength(strtrim(string(gitStatus)))>0;
localWrite(fullfile(runFolder,"git_commit.txt"),gitCommit+newline);
finished=datetime("now","TimeZone","UTC");
publicationQualified=comparative.PublicationQualified&&intrinsic.PublicationQualified&& ...
    stress.PublicationQualified&&all(status.Pass(status.RequiredForActiveClass));
manifest=struct("SchemaVersion","sixgr.isac.10_8_3.validation.v1", ...
    "RunId",char(runId),"RunFolder",char(runFolder), ...
    "ConfigSource",char(sourcePath),"ConfigSHA256",cfg.provenance.SourceSHA256, ...
    "GitCommit",char(gitCommit),"GitWorktreeDirty",gitDirty, ...
    "MATLABRelease",version("-release"),"MATLABVersion",version, ...
    "ActiveRunMode",char(cfg.run.activeMode), ...
    "StartedUTC",char(started),"FinishedUTC",char(finished), ...
    "ActiveComparativeClass",char(comparative.Class), ...
    "ActiveIntrinsicClass",char(intrinsic.Class),"ActiveStressClass",char(stress.Class), ...
    "Stage1Passed",stage1.Passed,"RequiredArtifactFiles",height(lineage), ...
    "RequiredArtifactFilesPassed",nnz(lineage.Pass), ...
    "ComparativeTargetTrials",height(comparative.Trials), ...
    "ComparativeH0Trials",sum(comparative.Thresholds.TrialCount), ...
    "PDSCHTransportBlocks",height(stress.Data.PDSCHTrials), ...
    "PublicationQualified",publicationQualified, ...
    "Decision",char(decision),"StatusSHA256",char(localHash( ...
    fullfile(runFolder,"aggregate","validation_status.csv"))), ...
    "FigureLineageSHA256",char(localHash(fullfile(runFolder,"aggregate", ...
    "validation_figure_lineage.csv"))), ...
    "SourceLineageRows",height(sourceLineage), ...
    "SourceLineageSHA256",char(localHash(fullfile(runFolder,"audit","source_lineage.csv"))), ...
    "TrackedWorktreePatchSHA256",char(sourcePatchHash));
sixgr.util.jsonWrite(fullfile(runFolder,"run_manifest.json"),manifest);
result=struct("RunFolder",runFolder,"Stage1",stage1,"Comparative",comparative, ...
    "Intrinsic",intrinsic,"Stress",stress,"ArtifactLineage",lineage, ...
    "Status",status,"DecisionQuestions",questions,"Decision",decision, ...
    "PublicationQualified",publicationQualified);
fprintf("10.8.3 validation complete: %s\n",runFolder);
fprintf("Stage-1=%d, artifacts=%d/%d, publication-qualified=%d\n", ...
    stage1.Passed,nnz(lineage.Pass),height(lineage),publicationQualified);
end

function [lineage,patchHash]=localSourceSnapshot(folder)
repo=localRepoRoot(); snapshot=fullfile(folder,"audit","source_snapshot");
isacFiles=dir(fullfile(repo,"+sixgr","+isac","*.m"));
paths=string(fullfile({isacFiles.folder},{isacFiles.name})).';
extra=[string(fullfile(repo,"+sixgr","+lls","runPDSCHTransportBlock.m")); ...
    string(fullfile(repo,"+sixgr","+phy","+dl","PDSCH_Tx.m")); ...
    string(fullfile(repo,"configs","isac","joint_isac_tdoc_master.yaml")); ...
    string(fullfile(repo,"runISAC1083Validation.m"))];
paths=unique([paths;string(extra)],"stable");
relative=strings(numel(paths),1); hash=strings(numel(paths),1); bytes=zeros(numel(paths),1);
for i=1:numel(paths)
    relative(i)=erase(paths(i),string(repo)+filesep);
    target=fullfile(snapshot,relative(i)); parent=fileparts(target);
    if exist(parent,"dir")~=7, mkdir(parent); end
    copyfile(paths(i),target);
    info=dir(paths(i)); bytes(i)=info.bytes; hash(i)=localHash(paths(i));
end
lineage=table(relative,bytes,hash,'VariableNames',{'RelativePath','Bytes','SHA256'});
writetable(lineage,fullfile(folder,"audit","source_lineage.csv"));
patchPath=fullfile(folder,"audit","tracked_worktree.patch");
command=sprintf('git diff --binary -- "+sixgr/+isac" "+sixgr/+lls/runPDSCHTransportBlock.m" "+sixgr/+phy/+dl/PDSCH_Tx.m" "configs/isac/joint_isac_tdoc_master.yaml" > "%s"',patchPath);
status=system(command);
if status~=0, error("sixgr:isac:SourcePatchFailed","Unable to save tracked worktree patch."); end
patchHash=localHash(patchPath);
end

function out=localStatus(cfg,stage1,comparative,intrinsic,stress,lineage)
campaign=cfg.validation.comparative.(comparative.Class);
intrinsicCfg=cfg.validation.intrinsic.(intrinsic.Class);
stressCfg=cfg.validation.stress.(stress.Class);
if stress.Class=="screening"
    pdschCountPass=all(stress.Data.PDSCH.TransportBlocks>= ...
        double(stressCfg.pdschTransportBlocksPerPoint));
else
    pdschCountPass=all(stress.Data.PDSCH.PublicationStoppingRuleSatisfied);
end
item=[stage1.GateTable.Gate;"COMPARATIVE_H0_COUNT";"COMPARATIVE_TARGET_COUNT"; ...
    "INTRINSIC_PAPR_COUNT";"INTRINSIC_CROSS_CORRELATION_COUNT"; ...
    "COMPARATIVE_METRIC_CONDITIONING"; ...
    "STRESS_PDSCH_COUNT";"FIGURE_ARTIFACT_CONTRACT";"PUBLICATION_STATISTICS"];
pass=[stage1.GateTable.Pass; ...
    all(comparative.Thresholds.TrialCount>=double(campaign.h0TrialsPerReceiver)); ...
    all(comparative.Metrics.Trials>=double(campaign.targetTrialsPerOperatingPoint)); ...
    all(intrinsic.PAPR.OFDMSymbolSamples>=double(intrinsicCfg.paprOFDMSymbolsPerProfile)); ...
    all(intrinsic.CrossCorrelation.PairCount>=double(intrinsicCfg.crossCorrelationPairsPerClass)); ...
    all(comparative.Metrics.EstimatorSampleCount<=comparative.Metrics.Trials) && ...
        all(comparative.Metrics.EstimatorMetricCondition=="conditioned_on_correct_detection"); ...
    pdschCountPass; ...
    all(lineage.Pass); ...
    comparative.PublicationQualified&&intrinsic.PublicationQualified&&stress.PublicationQualified];
required=[true(height(stage1.GateTable),1);true(7,1);false];
details=[stage1.GateTable.Details; ...
    "executed="+sum(comparative.Thresholds.TrialCount)+" configured="+ ...
        4*double(campaign.h0TrialsPerReceiver); ...
    "minimum_per_operating_point="+min(comparative.Metrics.Trials); ...
    "minimum_symbols_per_profile="+min(intrinsic.PAPR.OFDMSymbolSamples); ...
    "minimum_pairs_per_class="+min(intrinsic.CrossCorrelation.PairCount); ...
    "RMSE conditioned on correct detections; zero-count rows="+ ...
        nnz(comparative.Metrics.EstimatorSampleCount==0); ...
    "transport_blocks="+height(stress.Data.PDSCHTrials); ...
    "files="+nnz(lineage.Pass)+"/"+height(lineage); ...
    "active classes="+comparative.Class+"/"+intrinsic.Class+"/"+stress.Class];
classification=repmat("PASS — physical/unit sanity",numel(item),1);
classification(6:end-1)="RESULT — comparative performance";
classification(end)="INCONCLUSIVE — more simulation required";
classification(~pass&required)="FAIL — implementation issue";
out=table(item,pass,required,classification,details, ...
    'VariableNames',{'Gate','Pass','RequiredForActiveClass','ResultClass','Details'});
end

function out=localClassification(cfg,status)
contract=sixgr.isac.validationFigureContract();
resultClass=repmat("RESULT — comparative performance",height(contract),1);
resultClass(1:3)="PASS — physical/unit sanity";
notes=repmat("Executed from saved runtime rows under the active YAML class.",height(contract),1);
if lower(string(cfg.validation.comparative.activeClass))~="publication"
    notes(4:end)="Screening evidence; publication trial-count and confidence gates remain open.";
end
out=[contract table(resultClass,notes)];
gateRows=table("gate:"+status.Gate,repmat("not_applicable",height(status),1), ...
    status.ResultClass,status.Details,'VariableNames',out.Properties.VariableNames);
out=[out;gateRows];
end

function [out,decision]=localDecision(cfg,comparative,stress)
regions=["delay_below_cp";"delay_around_cp";"delay_above_cp";"multi_target"; ...
    "punctured_resources";"tdd_gapped_resources";"relocation"; ...
    "shared_pdsch";"asynchronous_intercell_interference"];
status=repmat("INCONCLUSIVE — more simulation required",numel(regions),1);
evidence=strings(numel(regions),1);
m=comparative.Incremental;
evidence(1)=localDelta(m,m.DelayOverCP<1);
evidence(2)=localDelta(m,m.DelayOverCP>=.9&m.DelayOverCP<=1.1);
evidence(3)=localDelta(m,m.DelayOverCP>1);
multi=comparative.Metrics(comparative.Metrics.ScenarioClass=="two_target_clutter",:);
evidence(4)=sprintf("executed_rows=%d minimum_trials_per_row=%g",height(multi),min(multi.Trials));
evidence(5)=sprintf("rows=%d correct_and_negative_counter=%d", ...
    height(stress.Data.Puncture),numel(unique(stress.Data.Puncture.ReceiverW3StateRule))==2);
    tddRows=stress.Data.Puncture.PunctureProfile=="tdd_driven_missing_occasions";
    evidence(6)=sprintf("executed_rows=%d ratios=%s state_rules=%s",nnz(tddRows), ...
        mat2str(unique(stress.Data.Puncture.CollisionRatioPercent(tddRows)).'), ...
        join(unique(stress.Data.Puncture.ReceiverW3StateRule(tddRows)),"|"));
evidence(7)=sprintf("rows=%d classes=%s",height(stress.Data.Relocation), ...
    join(unique(stress.Data.Relocation.RelocationClass),"|"));
evidence(8)=sprintf("coded_transport_blocks=%d profiles=%d", ...
    height(stress.Data.PDSCHTrials),numel(unique(stress.Data.PDSCH.WaveformProfile)));
evidence(9)=sprintf("rows=%d relative_power_range=[%g,%g] dB", ...
    height(stress.Data.Intercell),min(stress.Data.Intercell.RelativeInterfererPowerDb), ...
    max(stress.Data.Intercell.RelativeInterfererPowerDb));
out=table(regions,status,evidence,'VariableNames',{'QuestionARegion','Status','Evidence'});
if comparative.PublicationQualified&&stress.PublicationQualified
    decision="Publication statistics complete; inspect signed C0-minus-B1 table without forcing benefit.";
else
    decision="The evaluated transmitter-side W3 profile is not justified by the current performance evidence.";
end
end

function text=localDelta(m,rows)
slice=m(rows,:);
if isempty(slice), text="no rows"; return; end
text=sprintf("rows=%d mean_delta_PD=%g mean_delta_range_RMSE_m=%g mean_delta_doppler_RMSE_Hz=%g", ...
    height(slice),mean(slice.DeltaDetectionProbability_C0MinusB1,"omitnan"), ...
    mean(slice.DeltaRangeRMSEM_B1MinusC0,"omitnan"), ...
    mean(slice.DeltaDopplerRMSEHz_B1MinusC0,"omitnan"));
end

function localReport(folder,cfg,stage1,comparative,intrinsic,stress,status,questions,decision)
report=fullfile(folder,"report","10_8_3_validation_report.md");
fid=fopen(report,"w","n","UTF-8");
if fid<0, error("sixgr:isac:ReportOpenFailed","Cannot write %s.",report); end
cleanup=onCleanup(@()fclose(fid)); %#ok<NASGU>
fprintf(fid,"# SixGR ISAC agenda item 10.8.3 validation report\n\n");
fprintf(fid,"> Evidence class: `%s`; not publication-qualified unless the manifest says true.\n\n", ...
    comparative.Class);
sections={ ...
"1. Simulation configuration","2. Waveform definitions W0–W3", ...
"3. Receiver definitions B0–C0","4. CP-safe W0 validation", ...
"5. Linear-convolution long-delay validation","6. Beyond-CP sensing results", ...
"7. B1 versus C0 incremental benefit","8. PAPR", ...
"9. PSD/OOBE/ACLR","10. Autocorrelation and 2D ambiguity", ...
"11. Cross-correlation","12. Inter-cell sensing interference", ...
"13. Residual self-interference","14. Shared PDSCH BLER/goodput", ...
"15. Puncturing","16. Relocation","17. Randomization/coherence tradeoff", ...
"18. Buffer/latency/complexity","19. 10.8.2/10.8.3 interaction", ...
"20. Technical conclusions","21. Potential specification impact","22. Open issues"};
body=cell(22,1);
body{1}=sprintf("Carrier profile `%s`; seed %g; PFA %g; YAML SHA-256 `%s`.", ...
    string(cfg.carrier.activeProfile),double(cfg.run.masterSeed), ...
    double(cfg.validation.comparative.(comparative.Class).probabilityFalseAlarm), ...
    string(cfg.provenance.SourceSHA256));
body{2}="W0 ordinary communication CP-OFDM; W1-A per-occasion randomized; W1-B reset-aligned randomized; W2 repeated base sequence; W3 repeated sequence with absolute-subcarrier cumulative physical-CP phase.";
body{3}="B0 conventional per-symbol FFT; B1 capable whole-observation W0 correlation; B2 repeated-W2 receiver; C0 independently derives W3 absolute-symbol state. C0 receives no target oracle.";
body{4}=sprintf("%d/%d Stage-1 gates pass. Maximum CP-safe EVM RMS %.4g.",nnz(stage1.GateTable.Pass),height(stage1.GateTable),max(stage1.CPSafe.EVMRMS));
body{5}=sprintf("WFig17 uses true zero-extended time-domain delay. Maximum above-CP previous-symbol ISI ratio %.4g; maximum residual EVM %.4g.",max(stage1.LinearConvolution.PreviousSymbolISIPowerRatio(stage1.LinearConvolution.DelayOverCP>1)),max(stage1.LinearConvolution.ResidualEVMRMS));
body{6}=sprintf("%d paired target-present trials executed: four receivers, four target-echo SNRs, nine delay/CP points, two scenario classes and two trials/point. Metrics contain %d aggregate rows. Fixed-PFA PD and wrong-peak rows use 95%% Wilson intervals; range/Doppler RMSE is conditioned on correct detection and exports its contributing sample count.",height(comparative.Trials),height(comparative.Metrics));
body{7}="Signed deltas are in `tables/c0_minus_b1_incremental_benefit.csv`; positive values are not imposed. Conditional RMSE differences are NaN where either receiver has no correct detection. Two trials/point is screening and cannot establish material benefit.";
body{8}=sprintf("%d PAPR symbol samples/profile; empirical 1e-2 and 1e-3 CCDF quantiles, mean and standard deviation are in `tables/papr_ccdf_numeric.csv`. This distribution evidence has no parametric confidence claim.",min(intrinsic.PAPR.OFDMSymbolSamples));
body{9}=sprintf("WFig26 reports measured in-band, lower-adjacent and upper-adjacent power, asymmetric ACLR and OOBE from one deterministic oversampled runtime waveform/profile at %.4g MHz sample rate; it is numeric waveform evidence, not a statistical spectral mask claim.",intrinsic.Spectrum.SampleRateHz(1)/1e6);
ambiguityCells=sum(double(intrinsic.Ambiguity.DelayBins).*double(intrinsic.Ambiguity.DopplerBins));
body{10}=sprintf("WFig27 contains %d measured delay-Doppler cells over %d waveform profiles, with cuts, PSLR/ISLR, mainlobe widths and strongest ghost. The saved table also contains %d aperiodic/circular autocorrelation rows.",ambiguityCells,height(intrinsic.Ambiguity),height(intrinsic.Autocorrelation));
body{11}=sprintf("%d profile-pair classes were evaluated with minimum %d independent pairs/class.",height(intrinsic.CrossCorrelation),min(intrinsic.CrossCorrelation.PairCount));
body{12}=sprintf("%d aggregate inter-cell rows execute an asynchronous interferer in the same received sample vector, with %d target trials/row and an independently recalibrated H0 threshold at every power/profile point. Probability intervals are Wilson; conditional estimator counts are exported.",height(stress.Data.Intercell),min(stress.Data.Intercell.Trials));
body{13}=sprintf("%d residual-SI operating points execute leaked transmit waveform energy in the same received sample vector, with %d target trials/point and a separately recalibrated H0 threshold per SI level. No cancellation requirement is inferred from screening counts.",height(stress.Data.SelfInterference),min(stress.Data.SelfInterference.Trials));
pdschTrials=stress.Data.PDSCHTrials;
gridSNRError=max(abs(pdschTrials.MeasuredSNRdB-pdschTrials.TargetSNRdB));
evmImpliedSINR=-20*log10(pdschTrials.EqualizedSymbolEVMRMS);
postEqEVMDelta=max(abs(pdschTrials.PostEqSINRdB-evmImpliedSINR));
body{14}=sprintf("Production DL-SCH/PDSCH executed %d transport blocks over %d profile/SNR points. Transmit-grid Es/N0 agrees with the requested value within %.4g dB. Post-equalization SINR includes the declared 16-element gNB / 4-element UE channel-and-MMSE gain and agrees with independent equalized-symbol EVM within %.4g dB; it is not the transmit-grid Es/N0. Publication stopping-rule pass rows: %d/%d. Paired comparisons with statistically significant degradation: %d/%d.",height(pdschTrials),height(stress.Data.PDSCH),gridSNRError,postEqEVMDelta,nnz(stress.Data.PDSCH.PublicationStoppingRuleSatisfied),height(stress.Data.PDSCH),nnz(stress.Data.PDSCHComparison.CommunicationDegradationStatisticallySignificant),height(stress.Data.PDSCHComparison));
body{15}=sprintf("%d W3 puncture rows include correct absolute physical-symbol and deliberately wrong transmitted-counter receivers.",height(stress.Data.Puncture));
body{16}=sprintf("%d relocation rows cover R0 unknown, R1 exact and R2 bounded residual phase cases.",height(stress.Data.Relocation));
body{17}=sprintf("WFig19 and WFig35 separate W1-A and W1-B, reporting sequence cross-correlation and cross-symbol coherency costs rather than raw sample jumps; each randomization aggregate uses %d target trials.",min(stress.Data.Randomization.Trials));
body{18}=sprintf("%d B0/B1/B2/C0 rows separately report complex-sample buffer, bytes, median/p90 runtime, FFT count and complex-multiply estimate from %d repetitions/receiver on this MATLAB host. Runtime is not a hardware-independent complexity claim.",height(stress.Data.Complexity),min(stress.Data.Complexity.RuntimeRepetitions));
body{19}="Puncture and relocation state retains the 10.8.2 relation class and coherent-segment semantics. A missing occasion does not reset W3 q(l).";
body{20}="Question A rows are in `aggregate/w3_decision_questions.csv`. Question B: any reproducible W3 gain must arise from its declared cumulative-CP phase relation, not extra receiver knowledge. Question C remains open until publication counts establish separation from B1.";
body{21}=decision+" If future evidence supports W3, the required transmitter artifact is an explicit RS sequence/phase rule, absolute physical-symbol/reset anchor, CP recurrence, and receiver-visible continuity relation.";
body{22}=sprintf("Publication remains open unless the manifest is qualified: H0=%d and target=%d in this run; requested final operating point is PFA=1e-3 with 1e5 H0 and 5000 target trials per important point. Full PDSCH points require 100 errors or 10000 TBs.",sum(comparative.Thresholds.TrialCount),height(comparative.Trials));
for i=1:numel(sections)
    fprintf(fid,"## %s\n\n%s\n\n",sections{i},body{i});
end
fprintf(fid,"## Gate summary\n\n| Gate | Pass | Required | Classification | Details |\n|---|---:|---:|---|---|\n");
for i=1:height(status)
    fprintf(fid,"| %s | %d | %d | %s | %s |\n",status.Gate(i),status.Pass(i), ...
        status.RequiredForActiveClass(i),status.ResultClass(i),strrep(status.Details(i),"|","/"));
end
fprintf(fid,"\n## W3 Question-A status\n\n| Region | Status | Evidence |\n|---|---|---|\n");
for i=1:height(questions)
    fprintf(fid,"| %s | %s | %s |\n",questions.QuestionARegion(i),questions.Status(i), ...
        strrep(questions.Evidence(i),"|","/"));
end
end

function localLayout(folder)
for name=["audit","logs","raw","aggregate","tables","figures","report"]
    path=fullfile(folder,name); if exist(path,"dir")~=7, mkdir(path); end
end
end

function root=localRepoRoot()
root=fileparts(fileparts(fileparts(mfilename("fullpath"))));
end

function hash=localHash(path)
fid=fopen(path,"rb"); if fid<0, error("sixgr:isac:ArtifactReadFailed","Cannot read %s.",path); end
cleanup=onCleanup(@()fclose(fid)); %#ok<NASGU>
hash=string(sixgr.util.sha256Hex(fread(fid,Inf,"*uint8")));
end

function localWrite(path,text)
fid=fopen(path,"w","n","UTF-8"); if fid<0, error("sixgr:isac:WriteFailed","Cannot write %s.",path); end
cleanup=onCleanup(@()fclose(fid)); %#ok<NASGU>
fprintf(fid,"%s",text);
end
