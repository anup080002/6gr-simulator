function result = runSuite(mode, options)
%RUNSUITE Config-driven RAN1 10.5.2.3 UL evidence orchestrator.
% This is a thin study layer. Actual waveform evidence is generated only by
% sixgr.lls.runLLS -> existing PUSCH Tx/Rx, OFDM, channel, LLR, LDPC and CRC.

arguments
    mode (1,1) string {mustBeMember(mode,["plan","unit","quick","tdoc", ...
        "full","sls","figure_replay","audit"])} = "quick"
    options.OutputRoot (1,1) string = "results/tdoc_ul_10523"
    options.RunId (1,1) string = ""
    options.RunFolder (1,1) string = ""
    options.QuickConfigPath (1,1) string = "configs/lls/tdoc_ul_10523_quick.yaml"
    options.TDocConfigPath (1,1) string = "configs/lls/tdoc_ul_10523_bounded.yaml"
end

if any(mode==["audit","figure_replay"])
    if options.RunFolder==""
        error("sixgr:tdoc:ul10523:RunFolderRequired","RunFolder is required for %s.",mode);
    end
    if mode=="figure_replay"
        error("sixgr:tdoc:ul10523:ReplayRequiresImmutableSource", ...
            "Figure replay is intentionally blocked until a persisted source-only replay manifest is selected.");
    end
    [audit,passed,publicationPassed]=sixgr.tdoc.ul10523.ArtifactAuditor.run(options.RunFolder);
    result=struct("RunFolder",options.RunFolder,"Audit",audit,"Passed",passed, ...
        "PublicationQualified",publicationPassed); return;
end
if mode=="full"
    error("sixgr:tdoc:ul10523:FullMatrixNotAuthorized", ...
        "The full C00-C26 Cartesian campaign is not launched by the bounded TDoc entry point.");
end
if mode=="sls"
    error("sixgr:tdoc:ul10523:GenuineSLSUnavailable", ...
        "C15/C22/C24 require a genuine multi-cell scheduler, traffic, interference and PHY-coupled SLS; LLS proxy substitution is forbidden.");
end

repoRoot=localRepoRoot();
catalogPath=fullfile(repoRoot,"simulator","configs","tdoc_ul_10523", ...
    "RAN1_10_5_2_3_UL_SIMULATION_SCENARIO_CATALOG.yaml");
proposalPath=fullfile(repoRoot,"simulator","configs","tdoc_ul_10523", ...
    "RAN1_10_5_2_3_PROPOSAL_TO_CAMPAIGN_TRACEABILITY.csv");
contractPath=fullfile(repoRoot,"simulator","configs","tdoc_ul_10523", ...
    "RAN1_10_5_2_3_TDOC_FIGURE_AND_RESULT_CONTRACT.csv");
catalog=sixgr.lls6g.config.readConfigFile(catalogPath);
contract=readtable(contractPath,"Delimiter",",","VariableNamingRule","preserve");
proposal=readtable(proposalPath,"Delimiter",",","VariableNamingRule","preserve");
localValidateInputs(catalog,contract,proposal);

if options.RunId==""
    runId="ul10523_"+mode+"_"+string(datetime("now","Format","yyyyMMdd_HHmmss"));
else
    runId=options.RunId;
end
runFolder=localCanonical(fullfile(repoRoot,options.OutputRoot,runId));
if isfolder(runFolder)
    error("sixgr:tdoc:ul10523:OutputAlreadyExists", ...
        "Run folder exists and will not be overwritten: %s",runFolder);
end
localLayout(runFolder);
context=localContext(runId,[catalogPath proposalPath contractPath]);
localCopyInputs(runFolder,catalogPath,proposalPath,contractPath);
localInputManifest(runFolder,catalogPath,proposalPath,contractPath,context,mode);

deterministic=sixgr.tdoc.ul10523.DeterministicSuite.run();
sixgr.tdoc.ul10523.ResultWriter.write(fullfile(runFolder,"tables","deterministic_checks.csv"), ...
    deterministic.Checks,context);

actual=[];
if any(mode==["quick","tdoc"])
    if mode=="quick",configPath=options.QuickConfigPath;else,configPath=options.TDocConfigPath;end
    actual=localRunActualPUSCH(runFolder,configPath,context);
elseif mode=="unit"
    localWriteUnitEvidence(runFolder,context);
end

figureManifest=sixgr.tdoc.ul10523.FigurePublisher.publish( ...
    runFolder,contract,deterministic,context);
localFigureContractStatus(runFolder,contract,figureManifest,context);
localCampaignStatus(runFolder,catalog,mode,actual,context);
localProposalStatus(runFolder,proposal,context);
localLimitations(runFolder,mode,context);
localEnvironment(runFolder,context);
localArtifactManifest(runFolder,context);
[audit,passed,publicationPassed]=sixgr.tdoc.ul10523.ArtifactAuditor.run(runFolder);
sixgr.tdoc.ul10523.ResultWriter.write(fullfile(runFolder,"reports","artifact_audit.csv"),audit,context);
localSummary(runFolder,mode,actual,audit,passed,publicationPassed,context);

result=struct("RunFolder",runFolder,"Passed",passed, ...
    "PublicationQualified",publicationPassed,"Audit",audit, ...
    "FigureManifest",figureManifest,"ActualWaveform",actual);
if ~passed
    error("sixgr:tdoc:ul10523:ArtifactGateFailed", ...
        "UL 10.5.2.3 artifact integrity gate failed for %s.",runFolder);
end
fprintf("RAN1 10.5.2.3 UL %s integrity PASS: %s (%d CSV, %d PNG; publication=%d)\n", ...
    mode,runFolder,numel(dir(fullfile(runFolder,"**","*.csv"))), ...
    numel(dir(fullfile(runFolder,"**","*.png"))),publicationPassed);
end

function actual=localRunActualPUSCH(root,configPath,context)
rawRoot=fullfile(root,"raw");
wave=sixgr.lls.runLLS(configPath,"OutputRoot",rawRoot, ...
    "RunTag","c00_pusch_waveform","GeneratePlots",true);
T=wave.TrialTable; names=string(T.Properties.VariableNames);
crashed=false;
if ismember("Crash",names),crashed=any(logical(T.Crash)); ...
elseif ismember("CrashFlag",names),crashed=any(logical(T.CrashFlag));end
truth=wave.TruthContractTable;
proxyUsed=any(truth{1,["UsesBLERLookupTable","UsesSyntheticBLER", ...
    "UsesRandomPassFailModel","UsesGeometryAsLLS"]});
if wave.Status~="complete_valid" || isempty(T) || crashed || proxyUsed
    error("sixgr:tdoc:ul10523:CanonicalPUSCHUnavailable", ...
        "Bounded C00 run did not produce crash-free actual-waveform PUSCH truth.");
end
if ~all(string(T.CRCSource)=="decoded_transport_block_crc") || ...
        ~all(string(T.LLRSource)=="nrPUSCHDecode_soft_llr")
    error("sixgr:tdoc:ul10523:ReceiverLineageMismatch", ...
        "C00 rows do not terminate in the production decoder CRC/soft-LLR sources.");
end
rel=localRelative(root,wave.RunFolder);
actual=struct("RunFolder",string(wave.RunFolder),"RelativeRunFolder",rel, ...
    "TrialCount",height(T),"SNRPointCount",height(wave.SummaryTable), ...
    "SemanticSHA256",string(wave.ScientificSemanticSHA256), ...
    "Status",string(wave.Status),"PublicationEligible",false);
M=table(rel,rel+"/transport_block_trials.csv",rel+"/bler_vs_snr.csv", ...
    actual.TrialCount,actual.SNRPointCount,actual.SemanticSHA256, ...
    "waveform_truth","none","QUICK_SANITY_MODEL", ...
    "not_independent_3gpp_frc_calibrated",false,"PASS", ...
    'VariableNames',{'RelativeRunFolder','TrialCsv','SummaryCsv','ActualTransportBlocks', ...
    'SNRPointCount','ScientificSemanticSHA256','ExecutionClass','ApproximationMode', ...
    'EvidenceClass','CalibrationStatus','TDocReady','Status'});
sixgr.tdoc.ul10523.ResultWriter.write(fullfile(root,"manifests", ...
    "actual_waveform_manifest.csv"),M,context);
end

function localWriteUnitEvidence(root,context)
T=table("unit_mode_no_waveform","ANALYTICAL_DERIVATION","PASS",false, ...
    "Unit mode executes exact identities only; no link result is claimed.", ...
    'VariableNames',{'Item','EvidenceClass','Status','TDocReady','Notes'});
sixgr.tdoc.ul10523.ResultWriter.write(fullfile(root,"manifests","unit_scope.csv"),T,context);
end

function localFigureContractStatus(root,contract,observed,context)
n=height(contract); rows=repmat(struct("FigureId","","EvidenceClass","", ...
    "CampaignIds","","ExpectedPNGPath","","ObservedPNGPath","", ...
    "FileExists",false,"SourceBacked",false,"TDocReady",false, ...
    "Status","BLOCKED","StopReason",""),n,1);
for idx=1:n
    id=string(contract.FigureId(idx)); isT=startsWith(id,"TFIG-");
    obs=""; exists=false; source=false; status="BLOCKED";
    if isT
        hit=find(string(observed.FigureId)==id,1);
        if ~isempty(hit)
            obs=string(observed.PNGPath(hit)); exists=exist(fullfile(root,replace(obs,"/",filesep)),"file")==2;
            source=strlength(string(observed.SourceSHA256(hit)))>0; if exists&&source,status="PASS";end
        end
        reason="Controlling DOCX was not supplied; raster/source integrity passes but exact DOCX equivalence is unverified.";
    else
        reason="Required calibrated LLS/SLS campaign was not executed; no placeholder result image was created.";
    end
    rows(idx)=struct("FigureId",id,"EvidenceClass",string(contract.EvidenceClass(idx)), ...
        "CampaignIds",string(contract.CampaignIds(idx)), ...
        "ExpectedPNGPath",string(contract.PNGPath(idx)),"ObservedPNGPath",obs, ...
        "FileExists",exists,"SourceBacked",source,"TDocReady",false, ...
        "Status",status,"StopReason",reason);
end
sixgr.tdoc.ul10523.ResultWriter.write(fullfile(root,"manifests", ...
    "figure_contract_status.csv"),struct2table(rows,"AsArray",true),context);
end

function localCampaignStatus(root,catalog,mode,actual,context)
campaigns=localStructArray(catalog.campaigns); n=numel(campaigns);
rows=repmat(struct("CampaignId","","Name","","RequiredEvidence","", ...
    "Status","BLOCKED","CalibrationStatus","not_applicable", ...
    "ExecutedWaveformPoints",0,"ExecutedTransportBlocks",0, ...
    "TDocReady",false,"StopReason",""),n,1);
for idx=1:n
    c=campaigns(idx); id=string(c.id); status="BLOCKED"; cal="not_applicable"; points=0; tbs=0;
    reason="Mandatory calibrated LLS matrix was not launched by the bounded run.";
    if id=="C01"
        status="PASS";reason="All 22 declared conceptual/analytical raster figures regenerated from persisted CSV sources.";
    elseif id=="C00"
        cal="not_independent_3gpp_frc_calibrated";status="INCOMPLETE";
        reason="Actual PUSCH waveform anchor executed, but full PUCCH/SRS/CSI-RS/CDL/common-reference calibration gate is incomplete.";
        if ~isempty(actual),points=actual.SNRPointCount;tbs=actual.TrialCount;end
    elseif any(id==["C15","C22","C24"])
        reason="Genuine MULTICELL_SLS evidence is unavailable; single-link proxy substitution is forbidden.";
    elseif id=="C14"
        reason="No trained/versioned AI model and held-out dataset were supplied; heuristic relabeling as AI is forbidden.";
    end
    rows(idx)=struct("CampaignId",id,"Name",string(c.name), ...
        "RequiredEvidence",string(c.evidence),"Status",status, ...
        "CalibrationStatus",cal,"ExecutedWaveformPoints",points, ...
        "ExecutedTransportBlocks",tbs,"TDocReady",false,"StopReason",reason);
end
sixgr.tdoc.ul10523.ResultWriter.write(fullfile(root,"manifests", ...
    "campaign_status.csv"),struct2table(rows,"AsArray",true),context);
end

function localProposalStatus(root,proposal,context)
n=height(proposal); proposal.TerminalCampaignResult=false(n,1); ...
proposal.ClaimSupported=false(n,1); proposal.Status=repmat("BLOCKED",n,1);
proposal.StopReason=repmat("Required calibrated LLS/SLS terminal campaign evidence is unavailable in this bounded run.",n,1);
sixgr.tdoc.ul10523.ResultWriter.write(fullfile(root,"manifests", ...
    "proposal_evidence_matrix.csv"),proposal,context);
end

function localLimitations(root,mode,context)
item=["controlling_docx";"independent_3gpp_frc_calibration";"complete_c00_reference"; ...
    "calibrated_c02_c26_matrix";"genuine_multicell_sls";"trained_ai_model";"publication_statistics"];
reason=["Named controlling DOCX was not supplied"; ...
    "No independent FRC required-SNR oracle was supplied or executed"; ...
    "PUCCH/SRS/CSI-RS/CDL portions of C00 were not executed"; ...
    "Bounded mode executes only the canonical actual-PUSCH wiring anchor"; ...
    "C15/C22/C24 require real multi-cell execution"; ...
    "No model hash, training data or held-out evaluation set was supplied"; ...
    "Low transport-block counts have wide confidence intervals"];
T=table(item,repmat(string(mode),numel(item),1),repmat("BLOCKED",numel(item),1), ...
    reason,false(numel(item),1),'VariableNames',{'Item','RunMode','Status','Reason','TDocReady'});
sixgr.tdoc.ul10523.ResultWriter.write(fullfile(root,"reports","limitations.csv"),T,context);
end

function localEnvironment(root,context)
v=ver; five=find(string({v.Name})=="5G Toolbox",1); if isempty(five),fiveVer="missing";else,fiveVer=string(v(five).Version);end
T=table(string(version),fiveVer,string(computer),string(system_dependent("getos")), ...
    context.GitCommit,context.GitWorktreeDirty,datetime("now","TimeZone","UTC"), ...
    'VariableNames',{'MATLABVersion','FiveGToolboxVersion','Computer','OperatingSystem', ...
    'GitCommitObserved','GitWorktreeDirtyObserved','GeneratedUTC'});
sixgr.tdoc.ul10523.ResultWriter.write(fullfile(root,"manifests","environment_manifest.csv"),T,context);
end

function localInputManifest(root,catalog,proposal,contract,context,mode)
paths=string([catalog proposal contract]); kind=["scenario_catalog";"proposal_traceability";"figure_contract"];
hashes=strings(numel(paths),1);
for idx=1:numel(paths),hashes(idx)=sixgr.csi.fileSHA256(paths(idx));end
T=table(kind,paths(:),hashes(:),repmat(string(mode),3,1),repmat("PASS",3,1), ...
    'VariableNames',{'InputKind','SourcePath','SHA256','RunMode','Status'});
sixgr.tdoc.ul10523.ResultWriter.write(fullfile(root,"manifests","input_manifest.csv"),T,context);
end

function localCopyInputs(root,catalog,proposal,contract)
copyfile(catalog,fullfile(root,"configs","scenario_catalog.yaml"));
copyfile(proposal,fullfile(root,"configs","proposal_traceability.csv"));
copyfile(contract,fullfile(root,"configs","figure_and_result_contract.csv"));
end

function localArtifactManifest(root,context)
root=localCanonical(root); files=dir(fullfile(root,"**","*")); files=files(~[files.isdir]);
rows=repmat(struct("RelativePath","","ArtifactType","","SHA256","", ...
    "Bytes",0,"EvidenceClass","","TDocReady",false,"Status","PASS"),0,1);
for idx=1:numel(files)
    full=string(fullfile(files(idx).folder,files(idx).name)); rel=localRelative(root,full);
    if any(rel==["manifests/artifact_manifest.csv","reports/artifact_audit.csv","reports/run_summary.md"]),continue;end
    [~,~,ext]=fileparts(full); ext=lower(string(ext)); cls="MANIFEST_OR_CONFIGURATION";
    if contains(rel,"figures/tdoc"),cls="CONCEPTUAL_OR_ANALYTICAL"; ...
    elseif contains(rel,"raw/"),cls="ACTUAL_WAVEFORM_TRUTH"; ...
    elseif contains(rel,"figure_sources")||contains(rel,"deterministic"),cls="ANALYTICAL_DERIVATION";end
    rows(end+1,1)=struct("RelativePath",rel,"ArtifactType",erase(ext,"."), ... %#ok<AGROW>
        "SHA256",sixgr.csi.fileSHA256(full),"Bytes",files(idx).bytes, ...
        "EvidenceClass",cls,"TDocReady",false,"Status","PASS");
end
sixgr.tdoc.ul10523.ResultWriter.write(fullfile(root,"manifests", ...
    "artifact_manifest.csv"),struct2table(rows,"AsArray",true),context);
end

function localSummary(root,mode,actual,audit,passed,pub,context)
path=fullfile(root,"reports","run_summary.md"); fid=fopen(path,"w");
if fid<0,error("sixgr:tdoc:ul10523:SummaryWriteFailed","Cannot open %s.",path);end
cleanup=onCleanup(@()fclose(fid)); %#ok<NASGU>
fprintf(fid,"# RAN1 10.5.2.3 uplink evidence summary\n\n");
fprintf(fid,"- Run: `%s`\n- Mode: `%s`\n- Git commit observed: `%s`\n",context.RunId,mode,context.GitCommit);
fprintf(fid,"- Worktree dirty observed: `%d`\n- Artifact integrity: `%d`\n- Publication gate: `%d`\n",context.GitWorktreeDirty,passed,pub);
if ~isempty(actual),fprintf(fid,"- Actual PUSCH TBs: `%d` over `%d` SNR point(s)\n",actual.TrialCount,actual.SNRPointCount);end
fprintf(fid,"- CSV files: `%d`\n- PNG files: `%d`\n- SVG/PDF files: `0`\n\n", ...
    numel(dir(fullfile(root,"**","*.csv"))),numel(dir(fullfile(root,"**","*.png"))));
fprintf(fid,"## Scientific classification\n\nThe executed PUSCH rows are actual production waveform/decoder truth with `ApproximationMode=none`, but this bounded run is not independently 3GPP-FRC calibrated and is not publication statistics. The 22 TDoc figures are CSV-backed conceptual, analytical, or explicitly labelled quick-sanity figures. The 64 calibrated/SLS result figures remain blocked and were not replaced by placeholders.\n\n");
fprintf(fid,"## Audit\n\n");
for idx=1:height(audit),fprintf(fid,"- %s: `%d` (%s)\n",audit.Check(idx),audit.Pass(idx),audit.Details(idx));end
end

function localValidateInputs(catalog,contract,proposal)
if string(catalog.schema_version)~="1.0" || numel(localStructArray(catalog.campaigns))~=27
    error("sixgr:tdoc:ul10523:BadCatalog","Scenario catalog must contain schema 1.0 and C00-C26.");
end
ids=string(contract.FigureId); if height(contract)~=86 || nnz(startsWith(ids,"TFIG-"))~=22 || nnz(startsWith(ids,"RFIG-"))~=64
    error("sixgr:tdoc:ul10523:BadFigureContract","Expected 22 TFIG and 64 RFIG contract rows.");
end
if height(proposal)~=30,error("sixgr:tdoc:ul10523:BadProposalContract","Expected 30 proposal rows.");end
end

function a=localStructArray(value)
if ~iscell(value),value=num2cell(value);end
a=repmat(struct("id","","name","","evidence",""),numel(value),1);
for idx=1:numel(value)
    a(idx)=struct("id",string(value{idx}.id),"name",string(value{idx}.name), ...
        "evidence",strjoin(string(value{idx}.evidence(:)),"|"));
end
end
function localLayout(root)
for d=["manifests","configs","raw","aggregate","tables","tables/figure_sources", ...
        "figures/tdoc","figures/results","figures/diagnostic","figures/sls", ...
        "reports","logs","debug_samples"]
    path=fullfile(root,replace(d,"/",filesep)); if ~isfolder(path),mkdir(path);end
end
end
function c=localContext(runId,inputPaths)
[~,commit]=system("git rev-parse HEAD"); [~,dirty]=system("git status --porcelain --untracked-files=normal");
inputPaths=string(inputPaths); hashes=strings(numel(inputPaths),1);
for idx=1:numel(inputPaths),hashes(idx)=sixgr.csi.fileSHA256(inputPaths(idx));end
c=struct("RunId",string(runId),"ConfigSHA256",sixgr.util.sha256Hex(uint8(char(strjoin(hashes,"|")))), ...
    "GitCommit",strtrim(string(commit)),"GitWorktreeDirty",strlength(strtrim(string(dirty)))>0);
end
function r=localRepoRoot(),r=fileparts(fileparts(fileparts(fileparts(mfilename("fullpath")))));end
function p=localCanonical(p),p=string(java.io.File(char(string(p))).getCanonicalPath());end
function rel=localRelative(root,path)
root=localCanonical(root); path=localCanonical(path); rel=extractAfter(path,strlength(root)+1); rel=replace(rel,"\","/");
end
