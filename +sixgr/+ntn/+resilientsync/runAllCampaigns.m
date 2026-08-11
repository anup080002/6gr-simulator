function result = runAllCampaigns(configPath, varargin)
%RUNALLCAMPAIGNS Execute the full resilient NTN synchronization suite.

ip=inputParser;ip.FunctionName='sixgr.ntn.resilientsync.runAllCampaigns';
ip.addRequired('configPath',@(x)ischar(x)||isstring(x));
ip.addParameter('RunId','',@(x)ischar(x)||isstring(x));
ip.addParameter('Resume',false,@(x)islogical(x)&&isscalar(x));
ip.parse(configPath,varargin{:});
scenario=sixgr.ntn.resilientsync.buildScenario(string(configPath));
runId=string(ip.Results.RunId);
if strlength(strtrim(runId))==0
    runId=string(datetime('now','TimeZone','UTC','Format','yyyyMMdd_HHmmss'))+"_"+extractBefore(string(scenario.ConfigSHA256),13);
end
runId=regexprep(runId,'[^A-Za-z0-9_.-]','_');scenario.RunId=runId;
root=localRepoRoot();outputRoot=string(scenario.outputs.output_root);
if ~isfolder(fileparts(char(outputRoot))) && ~startsWith(outputRoot,root),outputRoot=fullfile(root,char(outputRoot));elseif ~startsWith(outputRoot,root),outputRoot=fullfile(root,char(outputRoot));end
runDirectory=fullfile(char(outputRoot),char(runId));
resume=logical(ip.Results.Resume);
if exist(runDirectory,'dir')==7
    if ~resume
        error('sixgr:ntn:resilientsync:OutputAlreadyExists','Run output exists: %s',runDirectory);
    end
    localValidateResume(runDirectory,scenario);
else
    localCreateLayout(runDirectory,scenario);
    localWriteConfig(runDirectory,scenario);
end
logPath=fullfile(runDirectory,'logs','campaign.log');diary(logPath);cleanupDiary=onCleanup(@() diary('off')); %#ok<NASGU>
fprintf('[%s] resilient NTN synchronization start mode=%s run=%s\n', ...
    char(datetime('now','TimeZone','UTC')),char(string(scenario.run_mode)),char(runId));

campaigns=struct();allTables=struct();evidence=table();
for id=["A","B","C","D","E","F","G"]
    checkpointPath=fullfile(runDirectory,'raw',sprintf('campaign_%s_checkpoint.mat',lower(char(id))));
    if resume && isfile(checkpointPath)
        stored=load(checkpointPath,'checkpoint');
        localValidateCheckpoint(stored.checkpoint,scenario,id,checkpointPath);
        campaign=stored.checkpoint.Campaign;
        fprintf('[%s] campaign %s resumed from exact-config checkpoint\n', ...
            char(datetime('now','TimeZone','UTC')),char(id));
    else
        fprintf('[%s] campaign %s start\n',char(datetime('now','TimeZone','UTC')),char(id));
        campaign=sixgr.ntn.resilientsync.runCampaign(scenario,id,string(runDirectory));
        checkpoint=struct('SchemaVersion',1,'ConfigSHA256',string(scenario.ConfigSHA256), ...
            'CampaignId',id,'Campaign',campaign); %#ok<NASGU>
        save(checkpointPath,'checkpoint','-v7.3');
    end
    campaigns.(char(id))=campaign;
    names=fieldnames(campaign.Tables);
    for i=1:numel(names)
        if isfield(allTables,names{i})
            error('sixgr:ntn:resilientsync:DuplicateArtifactOwner', ...
                'Campaign artifact %s has more than one owner.',names{i});
        end
        allTables.(names{i})=campaign.Tables.(names{i});
    end
    e=campaign.Evidence;e.Campaign=repmat(id,height(e),1);evidence=[evidence;e]; %#ok<AGROW>
    fprintf('[%s] campaign %s complete tables=%d\n',char(datetime('now','TimeZone','UTC')),char(id),numel(names));
end

genericRecords=table();names=fieldnames(allTables);
for i=1:numel(names)
    name=string(names{i});row=evidence(evidence.Artifact==name,:);
    if height(row)~=1,error('sixgr:ntn:resilientsync:EvidenceBindingFailure', ...
            'Artifact %s requires exactly one evidence binding.',char(name));end
    meta=struct('Campaign',string(row.Campaign),'ConfigSHA256',string(scenario.ConfigSHA256), ...
        'RunMode',string(scenario.run_mode),'Measured',logical(row.Measured));
    rec=sixgr.ntn.resilientsync.report.saveResultArtifact(string(runDirectory), ...
        "tables/"+name,allTables.(names{i}),string(row.EvidenceClass),meta);
    genericRecords=[genericRecords;rec]; %#ok<AGROW>
end
writetable(evidence,fullfile(runDirectory,'acceptance','evidence_registry.csv'));

publicFigures=sixgr.ntn.resilientsync.report.generateTdocFigures(string(runDirectory));
confidentialFigures=sixgr.ntn.resilientsync.report.generateConfidentialFigures(string(runDirectory));
traceability=sixgr.ntn.resilientsync.report.buildTraceabilityReport(string(runDirectory),scenario);
acceptance=localAcceptance(scenario,campaigns,evidence,traceability,runDirectory,publicFigures,confidentialFigures);
writetable(acceptance,fullfile(runDirectory,'acceptance','acceptance_checks.csv'));
if all(acceptance.Pass)
    if string(scenario.run_mode)=="quick",status="QUICK_COMPLETE";else,status="PASS";end
else
    status="FAIL";
end
numberedRecords=sixgr.ntn.resilientsync.report.exportTables( ...
    string(runDirectory),scenario,allTables,acceptance);
localWriteReports(runDirectory,scenario,status,acceptance,evidence);
allRecords=[genericRecords;publicFigures;confidentialFigures;numberedRecords];
fprintf('[%s] resilient NTN synchronization complete status=%s\n', ...
    char(datetime('now','TimeZone','UTC')),char(status));
% Close the active diary before hashing the run tree.  Otherwise the final
% completion line mutates campaign.log after its digest enters the manifest.
diary('off');
clear cleanupDiary
manifest=sixgr.ntn.resilientsync.report.buildManifest( ...
    string(runDirectory),scenario,status,allRecords);
result=struct('Status',status,'RunId',runId,'RunDirectory',string(runDirectory), ...
    'Scenario',scenario,'Campaigns',campaigns,'Tables',allTables, ...
    'Evidence',evidence,'Acceptance',acceptance,'Traceability',traceability, ...
    'Manifest',manifest,'FigureRecords',[publicFigures;confidentialFigures], ...
    'TableRecords',numberedRecords);
end

function localCreateLayout(root,cfg)
dirs=["config","logs","raw","tables","figures/tdoc_public", ...
    "figures/confidential_validation","figures/explanatory","traces","tests","acceptance"];
for d=dirs,path=fullfile(root,char(d));if exist(path,'dir')~=7,mkdir(path);end,end
if string(cfg.outputs.public_dir)~="figures/tdoc_public",mkdir(fullfile(root,char(cfg.outputs.public_dir)));end
if string(cfg.outputs.confidential_dir)~="figures/confidential_validation",mkdir(fullfile(root,char(cfg.outputs.confidential_dir)));end
end
function localWriteConfig(root,cfg)
copyfile(cfg.ConfigPath,fullfile(root,'config','executed_campaign.yaml'));
copyfile(cfg.StateProfilesPath,fullfile(root,'config','state_profiles.yaml'));
copyfile(fullfile(localRepoRoot(),'audit','ntn_resilient_sync','repo_audit.md'),fullfile(root,'repo_audit.md'));
localJSON(fullfile(root,'config','resolved_config.json'),cfg);
v=ver;environment=struct('MATLABVersion',string(version),'MATLABRelease',string(version('-release')), ...
    'Toolboxes',struct('Name',string({v.Name}),'Version',string({v.Version})), ...
    'Computer',string(computer),'Hostname',string(getenv('COMPUTERNAME')));
localJSON(fullfile(root,'environment.json'),environment);
end
function localValidateResume(root,cfg)
resolved=fullfile(root,'config','resolved_config.json');
if ~isfile(resolved)
    error('sixgr:ntn:resilientsync:ResumeConfigMissing', ...
        'Cannot resume %s because resolved_config.json is missing.',root);
end
saved=jsondecode(fileread(resolved));
savedHash=string(sixgr.util.structGet(saved,'ConfigSHA256',''));
if savedHash~=string(cfg.ConfigSHA256)
    error('sixgr:ntn:resilientsync:ResumeConfigMismatch', ...
        'Resume config hash %s does not match saved hash %s.', ...
        char(string(cfg.ConfigSHA256)),char(savedHash));
end
end
function localValidateCheckpoint(checkpoint,cfg,id,path)
if ~(isstruct(checkpoint)&&isscalar(checkpoint)) || ...
        double(sixgr.util.structGet(checkpoint,'SchemaVersion',NaN))~=1 || ...
        string(sixgr.util.structGet(checkpoint,'ConfigSHA256',''))~=string(cfg.ConfigSHA256) || ...
        string(sixgr.util.structGet(checkpoint,'CampaignId',''))~=id || ...
        ~isfield(checkpoint,'Campaign') || ...
        string(sixgr.util.structGet(checkpoint.Campaign,'Status',''))~="COMPLETE"
    error('sixgr:ntn:resilientsync:InvalidCampaignCheckpoint', ...
        'Checkpoint is incomplete or belongs to another config/campaign: %s',path);
end
end
function acceptance=localAcceptance(cfg,campaigns,evidence,trace,root,pub,conf)
ids=string(fieldnames(campaigns));campaignOk=true;
for i=1:numel(ids),campaignOk=campaignOk&&string(campaigns.(ids(i)).Status)=="COMPLETE";end
checks=["all_campaigns_complete";"no_proxy_or_fallback_evidence";"calibrated_evidence_present"; ...
    "public_figure_contract";"confidential_figure_contract";"traceability_complete"; ...
    "figure_traceability_complete"; ...
    "intentional_figure_gap_preserved";"geometry_budget";"prach_budget";"source_config_hashed"];
pass=false(size(checks));detail=strings(size(checks));
pass(1)=campaignOk;detail(1)=strjoin(ids,',');
pass(2)=~any(contains(lower(string(evidence.EvidenceClass)),["proxy","fallback","synthetic"]));detail(2)='evidence registry';
pass(3)=any(evidence.EvidenceClass=="CALIBRATED_LLS" & evidence.Measured);detail(3)=string(sum(evidence.EvidenceClass=="CALIBRATED_LLS"));
pass(4)=height(pub)==21;detail(4)=string(height(pub))+"/21";
pass(5)=height(conf)==15;detail(5)=string(height(conf))+"/15";
pass(6)=height(trace)==15 && all(trace.Status=="PRODUCED");detail(6)=string(sum(trace.Status=="PRODUCED"))+"/15";
figureTrace=readtable(fullfile(root,'figure_traceability_matrix.csv'),'TextType','string');
pass(7)=all(figureTrace.Status=="PRODUCED" | figureTrace.Status=="INTENTIONAL_NUMBERING_GAP");
detail(7)=string(sum(figureTrace.Status=="PRODUCED"))+" produced + "+string(sum(figureTrace.Status=="INTENTIONAL_NUMBERING_GAP"))+" gap";
pass(8)=~isfile(fullfile(root,char(cfg.outputs.public_dir),'fig_2_11.png'));detail(8)='no Figure 2-11';
if string(cfg.run_mode)=="quick",pass(9)=double(cfg.gnss_free.drops_per_point)>=10000;else,pass(9)=double(cfg.gnss_free.drops_per_point)>=300000;end
detail(9)=string(cfg.gnss_free.drops_per_point);
if string(cfg.run_mode)=="quick",pass(10)=double(cfg.physical_layer.prach_trials_min)>=100;else,pass(10)=double(cfg.physical_layer.prach_trials_min)>=10000;end
detail(10)=string(cfg.physical_layer.prach_trials_min);
pass(11)=strlength(string(cfg.ConfigSHA256))==64;detail(11)=string(cfg.ConfigSHA256);
acceptance=table(checks,pass,detail,repmat(string(cfg.run_mode),numel(checks),1), ...
    'VariableNames',{'Check','Pass','Detail','RunMode'});
end
function localWriteReports(root,cfg,status,acceptance,evidence)
fid=fopen(fullfile(root,'discrepancy_report.md'),'w','n','UTF-8');cleanup=onCleanup(@() fclose(fid));
fprintf(fid,'# Discrepancy report\n\nStatus: **%s**\n\n',char(status));
failed=acceptance(~acceptance.Pass,:);if isempty(failed),fprintf(fid,'No contract discrepancies were detected for run mode `%s`.\n',char(string(cfg.run_mode)));else,for i=1:height(failed),fprintf(fid,'- %s: %s\n',char(failed.Check(i)),char(failed.Detail(i)));end,end
clear cleanup
fid=fopen(fullfile(root,'README.md'),'w','n','UTF-8');cleanup=onCleanup(@() fclose(fid));
fprintf(fid,'# SixGR resilient NTN synchronization evidence\n\nRun: `%s`  \nMode: `%s`  \nStatus: `%s`\n\n',char(cfg.RunId),char(string(cfg.run_mode)),char(status));
fprintf(fid,'Evidence rows: %d. Proxy and fallback primary rows are prohibited. Public and confidential outputs are separated.\n',height(evidence));
clear cleanup
fid=fopen(fullfile(root,'acceptance','intentional_numbering_gaps.md'),'w','n','UTF-8');cleanup=onCleanup(@() fclose(fid));fprintf(fid,'# Intentional numbering gaps\n\nNo Figure 2-11. No Table 16 or Table 17.\n');
end
function localJSON(path,value)
fid=fopen(path,'w','n','UTF-8');if fid<0,error('sixgr:ntn:resilientsync:WriteFailed','Cannot write %s.',path);end
cleanup=onCleanup(@() fclose(fid));fprintf(fid,'%s\n',jsonencode(value,'PrettyPrint',true));
end
function root=localRepoRoot(),here=fileparts(mfilename('fullpath'));root=fileparts(fileparts(fileparts(here)));end
