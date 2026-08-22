function result = runRACHTDocStudyCampaign(configPath,varargin)
%RUNCAMPAIGN Execute analytical or bounded waveform RAN1 10.5.1.2 work.
%
% The campaign adapter calls the canonical SixGR PRACH and RA layers.  It
% never substitutes configured SNR values or analytical curves for measured
% waveform evidence.

p=inputParser;
p.addRequired("configPath",@(x)ischar(x)||isstring(x));
p.addParameter("OutputRoot","",@(x)ischar(x)||isstring(x));
p.addParameter("RunID","",@(x)ischar(x)||isstring(x));
p.addParameter("Resume",false,@(x)islogical(x)||isnumeric(x));
p.parse(configPath,varargin{:});

campaign=sixgr.rach.tdoc10512.buildRACHTDocStudyConfig(configPath);
cfg=campaign.Resolved; mode=campaign.Mode;
if any(mode==["core_lls","full"])
    error("sixgr:rach:tdoc10512:DecisionCampaignGate", ...
        "%s mode is intentionally gated until all requested format, Msg2, Msg3, PUCCH, multicell, and procedure task adapters are bound to calibrated runtime evidence. Run smoke or analytical first.", ...
        upper(mode));
elseif mode=="report_only"
    error("sixgr:rach:tdoc10512:ReportOnlyNeedsSource", ...
        "report_only requires an immutable completed campaign source and must be invoked through generateRachTdocArtifacts.");
end

outputRoot=string(p.Results.OutputRoot);
if strlength(strtrim(outputRoot))==0
    outputRoot=string(cfg.tdoc10512.output.root);
end
runID=string(p.Results.RunID);
if strlength(strtrim(runID))==0
    runID=campaign.CampaignID+"_"+string(datetime("now","TimeZone","UTC", ...
        "Format","yyyyMMdd_HHmmss"));
end
runFolder=fullfile(char(outputRoot),char(runID));
resume=logical(p.Results.Resume);
if (isfolder(runFolder)||isfile(runFolder))&&~resume
    error("sixgr:rach:tdoc10512:OutputExists", ...
        "Campaign output already exists and will not be overwritten: %s.",runFolder);
end
if resume
    localValidateResume(runFolder,campaign);
else
    localCreateLayout(runFolder);
    schemaReport=sixgr.rach.tdoc10512.validateRACHTDocStudyConfig(cfg);
    sixgr.util.csvWriteTable(fullfile(runFolder,"validation","schema_validation.csv"),schemaReport);
    sixgr.lls6g.config.writeYAML(fullfile(runFolder,"config","resolved_config.yaml"),cfg);
    for k=1:numel(campaign.SourceFiles)
        [~,name,ext]=fileparts(campaign.SourceFiles(k));
        copyfile(campaign.SourceFiles(k),fullfile(runFolder,"config", ...
            sprintf("source_%02d_%s%s",k,name,ext)));
    end
    localWriteProvenance(runFolder,campaign,cfg,runID);
end

% Resolve and validate the canonical production PHY configuration before
% spending time rendering analytical artifacts.  This keeps a short run
% fail-fast on inherited carrier/frame/SSB/PRACH incompatibilities.
internal=[]; strictRoot="";
if any(mode==["smoke","engineering_lls"])
    strictRoot=fullfile(runFolder,"raw","strict_prach");
    sixgr.util.ensureFolder(strictRoot);
    internal=sixgr.lls6g.buildInternalConfig(campaign.ScenarioConfig,strictRoot);
end

if resume
    analyticalArtifacts=localLoadAnalyticalArtifacts(runFolder);
    analyticalData=struct("ResumedFromPersistedArtifacts",true);
else
    [analyticalArtifacts,analyticalData]= ...
        sixgr.rach.tdoc10512.generateRACHTDocStudyAnalyticalArtifacts( ...
        runFolder,cfg,campaign.ConfigHash);
end

strict=struct(); measuredPrachArtifacts=table(); engineering=struct();
if any(mode==["smoke","engineering_lls"])
    if resume&&localStrictComplete(strictRoot)
        strict=localLoadCompletedStrict(strictRoot);
    else
        strict=sixgr.phy.prach.runStrictPRACHValidation(internal, ...
            "RunFolder",strictRoot,"RunId",runID+"_strict_prach", ...
            "ScenarioName",campaign.ScenarioID,"WriteArtifacts",true);
    end
    measuredPrachArtifacts=sixgr.rach.tdoc10512.writeRACHTDocStudyMeasuredArtifacts( ...
        runFolder,strict,campaign,localModeClassification(cfg,mode));
end
if mode=="engineering_lls"
    engineering=sixgr.rach.tdoc10512.runRACHTDocStudyEngineeringEvidence( ...
        internal,campaign,runFolder,runID);
    supplemental=sixgr.rach.tdoc10512.runRACHTDocStudySupplementalEvidence( ...
        internal,campaign,runFolder,engineering);
    engineering.Supplemental=supplemental;
    engineering.Artifacts=[engineering.Artifacts;supplemental.Artifacts];
end

taskStatus=localTaskStatus(mode,analyticalArtifacts,measuredPrachArtifacts,engineering);
sixgr.util.csvWriteTable(fullfile(runFolder,"validation","task_status.csv"),taskStatus);
readme=localREADME(campaign,mode,strict,taskStatus);
sixgr.util.writeTextFile(fullfile(runFolder,"README.md"),readme);

fileManifest=localFileManifest(runFolder);
sixgr.util.csvWriteTable(fullfile(runFolder,"manifest.csv"),fileManifest);
pass=all(taskStatus.Status(taskStatus.RequiredForSelectedMode)=="COMPLETE");
if any(mode==["smoke","engineering_lls"])
    pass=pass&&logical(strict.StrictOk);
end
manifest=struct("schema_version","sixgr.rach.tdoc10512.manifest.v1", ...
    "campaign_id",runID,"scenario_id",campaign.ScenarioID,"mode",mode, ...
    "config_hash",campaign.ConfigHash,"status",localPassText(pass), ...
    "functional_pass",logical(pass), ...
    "statistically_qualified",localStatQualified(strict), ...
    "tdoc_ready",logical(mode=="core_lls"&&pass&&localStatQualified(strict)), ...
    "result_classification",localModeClassification(cfg,mode), ...
    "git_commit",localGitCommit(),"git_worktree_dirty",localGitDirty(), ...
    "artifact_files",height(fileManifest),"task_rows",height(taskStatus), ...
    "completed_tasks",nnz(taskStatus.Status=="COMPLETE"), ...
    "blocked_or_not_executed_tasks",nnz(taskStatus.Status~="COMPLETE"), ...
    "truth_statement",localTruthStatement());
sixgr.util.jsonWrite(fullfile(runFolder,"manifest.json"),manifest);

result=struct("RunFolder",string(runFolder),"RunID",runID, ...
    "Mode",mode,"Config",cfg,"ConfigHash",campaign.ConfigHash, ...
    "AnalyticalData",analyticalData,"AnalyticalArtifacts",analyticalArtifacts, ...
    "EngineeringEvidence",engineering, ...
    "StrictPRACH",strict,"TaskStatus",taskStatus,"FileManifest",fileManifest, ...
    "Manifest",manifest,"Passed",logical(pass));
end

function localValidateResume(root,campaign)
if ~isfolder(root)
    error("sixgr:rach:tdoc10512:ResumeMissing", ...
        "Resume requested but campaign output does not exist: %s.",root);
end
if isfile(fullfile(root,"manifest.json"))
    error("sixgr:rach:tdoc10512:ResumeFinalized", ...
        "A finalized campaign cannot be resumed in place: %s.",root);
end
envPath=fullfile(root,"meta","environment_summary.json");
if ~isfile(envPath)
    error("sixgr:rach:tdoc10512:ResumeProvenanceMissing", ...
        "Resume requires the original environment summary: %s.",envPath);
end
env=jsondecode(fileread(envPath));
stored=string(sixgr.util.structGet(env,"config_hash",""));
if stored~=campaign.ConfigHash
    error("sixgr:rach:tdoc10512:ResumeConfigMismatch", ...
        "Resume config hash %s does not match stored hash %s.", ...
        campaign.ConfigHash,stored);
end
end

function artifacts=localLoadAnalyticalArtifacts(root)
figDir=fullfile(root,"figures","analytical");
files=dir(fullfile(figDir,"F*.png"));
if numel(files)~=13
    error("sixgr:rach:tdoc10512:ResumeAnalyticalIncomplete", ...
        "Resume requires all 13 analytical PNGs; found %d.",numel(files));
end
rows=cell(numel(files),1);
for k=1:numel(files)
    [~,id]=fileparts(files(k).name);
    path=fullfile(files(k).folder,files(k).name);
    source=fullfile(root,"tables","figure_sources",id+".csv");
    if ~isfile(source)||~isfile(fullfile(figDir,id+".json"))
        error("sixgr:rach:tdoc10512:ResumeAnalyticalIncomplete", ...
            "Analytical artifact %s lacks its source CSV or JSON sidecar.",id);
    end
    rows{k}=table(string(id),string(localRelative(path,root)), ...
        string(localRelative(source,root)),"ANALYTICAL_DERIVATION", ...
        "COMPLETE",localFileHash(path), ...
        'VariableNames',{'ArtifactID','RelativePath','SourceCSV', ...
        'Classification','Status','SHA256'});
end
artifacts=vertcat(rows{:});
end

function tf=localStrictComplete(root)
tf=isfile(fullfile(root,"reports","json","prach_conformance_summary.json"))&& ...
    isfile(fullfile(root,"control","csv","prach_strict_trials.csv"));
if tf
    summary=jsondecode(fileread(fullfile(root,"reports","json", ...
        "prach_conformance_summary.json")));
    tf=logical(sixgr.util.structGet(summary,"StrictOk",false));
end
end

function strict=localLoadCompletedStrict(root)
csvDir=fullfile(root,"control","csv");
names=["prach_config_strict","prach_trials","prach_detection_candidates", ...
    "prach_restricted_set_mapping","prach_root_sequence_budget", ...
    "prach_zcz_cyclic_shift_mapping","prach_missed_detection_sweep", ...
    "prach_false_alarm_sweep","prach_timing_offset_sweep", ...
    "prach_frequency_offset_sweep","prach_collision_trials", ...
    "prach_multi_occasion_trials","prach_negative_trials","prach_oracle_guard"];
files=names;files(names=="prach_trials")="prach_strict_trials";
tables=struct();
for k=1:numel(names)
    path=fullfile(csvDir,files(k)+".csv");
    if ~isfile(path)
        error("sixgr:rach:tdoc10512:ResumeStrictIncomplete", ...
            "Strict PRACH resume artifact is missing: %s.",path);
    end
    tables.(names(k))=readtable(path,"FileType","text", ...
        "Delimiter",",","ReadVariableNames",true,"TextType","string", ...
        "VariableNamingRule","preserve");
end
summary=jsondecode(fileread(fullfile(root,"reports","json", ...
    "prach_conformance_summary.json")));
strict=struct("StrictOk",logical(summary.StrictOk), ...
    "StatisticallyQualified",logical(summary.StatisticallyQualified), ...
    "StatisticalQualification",string(summary.StatisticalQualification), ...
    "DetectionSummary",summary,"ArtifactTables",tables, ...
    "ProxyUsed",false,"Skipped",false,"ToolboxMissing",false, ...
    "UsedOracleFields","","ResumedFromPersistedArtifacts",true);
end

function localCreateLayout(root)
dirs=["config","logs","raw","checkpoints","aggregated","tables", ...
    "figures","validation","debug","meta"];
for k=1:numel(dirs), sixgr.util.ensureFolder(fullfile(root,dirs(k))); end
end

function localWriteProvenance(root,campaign,cfg,runID)
v=ver; tools=repmat(struct("name","","version",""),numel(v),1);
for k=1:numel(v), tools(k).name=v(k).Name; tools(k).version=v(k).Version; end
env=struct("run_id",runID,"scenario_id",campaign.ScenarioID, ...
    "config_hash",campaign.ConfigHash,"git_commit",localGitCommit(), ...
    "git_worktree_dirty",localGitDirty(),"matlab_version",version, ...
    "computer",computer,"toolboxes",tools,"timestamp_utc",sixgr.util.utcNowISO8601());
sixgr.util.jsonWrite(fullfile(root,"meta","environment_summary.json"),env);
seeds=struct("master_seed",double(cfg.tdoc10512.master_seed), ...
    "statistical_seed_set",double(cfg.random_access.statistical_qualification.deterministic_seeds(:)'), ...
    "mapping","YAML-owned deterministic seeds; no wall-clock RNG seeding");
sixgr.util.jsonWrite(fullfile(root,"meta","seeds.json"),seeds);
end

function artifact=localWriteSmokeR01(root,strict,campaign)
T=strict.ArtifactTables.prach_missed_detection_sweep;
sourceDir=fullfile(root,"tables","figure_sources");
figDir=fullfile(root,"figures","quick_sanity");
sixgr.util.ensureFolder(sourceDir); sixgr.util.ensureFolder(figDir);
id="R01_prach_mdr_vs_snr"; source=fullfile(sourceDir,id+".csv");
sixgr.util.csvWriteTable(source,T);
sourceTable=T; %#ok<NASGU>
save(fullfile(sourceDir,id+".mat"),"sourceTable","-v7");
path=fullfile(figDir,id+".png");
fig=figure("Visible","off","Color","w","Position",[100 100 1200 720]);
clean=onCleanup(@()close(fig)); %#ok<NASGU>
[x,order]=sort(double(T.SNRdB)); y=double(T.MissedDetectionProbability(order));
lo=max(0,y-double(T.MissedDetectionCILower(order)));
hi=max(0,double(T.MissedDetectionCIUpper(order))-y);
errorbar(x,y,lo,hi,"o-","LineWidth",1.5,"MarkerFaceColor",[.1 .45 .8]);
ax=gca; set(ax,"Color","w","XColor",[.12 .15 .20],"YColor",[.12 .15 .20], ...
    "GridColor",[.55 .60 .66],"MinorGridColor",[.72 .75 .79]);
grid on; xlabel("Received SNR (dB)","Color",[.12 .15 .20]);
ylabel("Missed-detection probability","Color",[.12 .15 .20]);
upper=max(double(T.MissedDetectionCIUpper));
ylim([0 max(.06,1.15*upper)]);
if numel(x)==1, xlim(x+[-1 1]); end
title(campaign.ScenarioID+" | QUICK_SANITY_MODEL | measured PRACH MDR", ...
    "Color",[.12 .15 .20],"Interpreter","none");
legend("measured P_{MD} with exact confidence interval", ...
    "Location","best","Color","w","TextColor",[.12 .15 .20]);
sixgr.util.exportFigureArtifact(fig,path,"Resolution",double(campaign.TDoc.output.png_dpi));
meta=struct("artifact_id",id,"classification","QUICK_SANITY_MODEL", ...
    "status","COMPLETE","scenario_id",campaign.ScenarioID, ...
    "config_hash",campaign.ConfigHash,"source_csv",string(source), ...
    "source_csv_sha256",localFileHash(source), ...
    "statistically_qualified",logical(strict.StatisticallyQualified), ...
    "performance_claim",false,"producer","sixgr.rach.tdoc10512.runRACHTDocStudyCampaign");
sixgr.util.jsonWrite(fullfile(figDir,id+".json"),meta);
artifact=table(id,string(localRelative(path,root)),string(localRelative(source,root)), ...
    "QUICK_SANITY_MODEL","COMPLETE",localFileHash(path), ...
    'VariableNames',{'ArtifactID','RelativePath','SourceCSV','Classification','Status','SHA256'});
end

function T=localTaskStatus(mode,analyticalArtifacts,measuredPrachArtifacts,engineering)
ids=["F"+compose("%02d",1:13) "R"+compose("%02d",1:17)]';
n=numel(ids); status=repmat("NOT_EXECUTED",n,1); reason=repmat("not_selected_in_this_mode",n,1);
classification=repmat("",n,1); path=repmat("",n,1); required=false(n,1);
for k=1:13
    mask=startsWith(analyticalArtifacts.ArtifactID,ids(k));
    if any(mask)
        row=analyticalArtifacts(find(mask,1),:); status(k)="COMPLETE"; reason(k)="";
        classification(k)=row.Classification; path(k)=row.RelativePath; required(k)=true;
    end
end
measured=measuredPrachArtifacts;
if isstruct(engineering)&&isfield(engineering,"Artifacts")&&istable(engineering.Artifacts)
    measured=[measured;engineering.Artifacts]; %#ok<AGROW>
end
for k=14:n
    mask=startsWith(string(measured.ArtifactID),ids(k)+"_")| ...
        string(measured.ArtifactID)==ids(k);
    if any(mask)
        row=measured(find(mask,1),:);status(k)="COMPLETE";reason(k)="";
        classification(k)=row.Classification;path(k)=row.RelativePath;
    end
end
if mode=="smoke"
    required(14)=true;
    if status(14)=="COMPLETE"
        reason(14)="";
    end
    empty=status(15:end)~="COMPLETE";
    idx=find(empty)+14;
    reason(idx)="outside_short_smoke_scope_no_placeholder_evidence_created";
elseif mode=="engineering_lls"
    required(14:end)=true;
    missing=status(14:end)~="COMPLETE";
    idx=find(missing)+13;
    reason(idx)="missing_production_measurement_adapter_no_placeholder_created";
elseif mode=="analytical"
    reason(14:end)="waveform_or_procedure_task_not_selected_in_analytical_mode";
end
T=table(ids,status,classification,path,reason,required, ...
    'VariableNames',{'TaskID','Status','Classification','ArtifactPath','Reason','RequiredForSelectedMode'});
end

function text=localREADME(campaign,mode,strict,tasks)
lines=["# RAN1 10.5.1.2 PRACH/RACH evidence campaign";""; ...
    "Scenario: `"+campaign.ScenarioID+"`"; ...
    "Mode: `"+upper(mode)+"`"; ...
    "Config hash: `"+campaign.ConfigHash+"`";""];
if mode=="smoke"
    lines(end+1)="Functional strict PRACH pass: `"+string(logical(strict.StrictOk))+"`";
    lines(end+1)="Statistically qualified: `"+string(logical(strict.StatisticallyQualified))+"`";
    lines(end+1)="The 100-trial run is a QUICK_SANITY_MODEL and is not TDoc-grade statistics.";
elseif mode=="engineering_lls"
    lines(end+1)="Production waveform chains executed: `true`";
    lines(end+1)="Statistically qualified: `"+string(logical(strict.StatisticallyQualified))+"`";
    lines(end+1)="ENGINEERING_LLS artifacts are suitable for implementation review, not decision-quality probability claims.";
end
lines=[lines;"";"Completed task rows: "+nnz(tasks.Status=="COMPLETE")+"/"+height(tasks);""; ...
    "## Truth statement";"";localTruthStatement()];
text=strjoin(lines,newline);
end

function T=localFileManifest(root)
files=dir(fullfile(root,"**","*")); files=files(~[files.isdir]);
exclude=ismember(string({files.name}),["manifest.csv","manifest.json"]); files=files(~exclude);
n=numel(files); rel=strings(n,1); bytes=zeros(n,1); hash=strings(n,1); cls=strings(n,1);
for k=1:n
    path=fullfile(files(k).folder,files(k).name); rel(k)=localRelative(path,root);
    bytes(k)=files(k).bytes; hash(k)=localFileHash(path); token=lower(rel(k));
    isMeasuredRTask=~isempty(regexp(char(token), ...
        '(^|[\\/])r(0[1-9]|1[0-7])_', 'once'));
    if contains(token,"engineering_lls")||contains(token,"engineering_waveform")|| ...
            contains(token,"supplemental_engineering")||isMeasuredRTask
        cls(k)="ENGINEERING_LLS";
    elseif contains(token,"figures"+filesep+"analytical")||contains(token,"tables"+filesep)
        cls(k)="ANALYTICAL_DERIVATION";
    elseif contains(token,"strict_prach")||contains(token,"quick_sanity")
        cls(k)="QUICK_SANITY_MODEL";
    else
        cls(k)="PROVENANCE_OR_VALIDATION";
    end
end
T=table(rel,bytes,hash,cls,repmat("COMPLETE",n,1), ...
    'VariableNames',{'RelativePath','Bytes','SHA256','Classification','Status'});
end

function value=localModeClassification(cfg,mode)
value=string(sixgr.util.structGet(cfg,"tdoc10512.result_classification."+mode,""));
end

function tf=localStatQualified(strict)
tf=isstruct(strict)&&isfield(strict,"StatisticallyQualified")&&logical(strict.StatisticallyQualified);
end

function value=localPassText(pass)
if pass, value="PASS"; else, value="FAIL"; end
end

function value=localGitCommit()
[status,text]=system("git rev-parse HEAD");
if status==0, value=string(strtrim(text)); else, value="unavailable"; end
end

function tf=localGitDirty()
[status,text]=system("git status --porcelain"); tf=status~=0||strlength(strtrim(string(text)))>0;
end

function value=localRelative(path,root)
p=string(char(java.io.File(char(string(path))).getCanonicalPath()));
r=string(char(java.io.File(char(string(root))).getCanonicalPath()));
value=erase(p,r+filesep);
end

function value=localFileHash(path)
fid=fopen(path,"r");
if fid<0, error("sixgr:rach:tdoc10512:ArtifactRead","Cannot read %s.",path); end
clean=onCleanup(@()fclose(fid)); %#ok<NASGU>
value=sixgr.util.sha256Hex(fread(fid,Inf,"*uint8"));
end

function value=localTruthStatement()
value="Analytical timing, collision, payload, root-demand and SBFD-fit results are deterministic derivations under the stated assumptions. Link-level and procedure-level performance results are produced by the identified SixGR/MATLAB implementation and are not claimed to be 3GPP-conformance results unless a separate conformance-calibration record is explicitly provided. Any result classified as QUICK_SANITY_MODEL is illustrative and shall not be used as TDoc-grade or filing-grade performance evidence.";
end
