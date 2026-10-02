function receipt=run_link_calibration(configPath,outputRoot,runTag)
%RUN_LINK_CALIBRATION Generic resumable production-waveform DL/UL collection.
% Qualification is a separate operation; collection never installs a LUT.
if nargin<2, outputRoot='results/calibration'; end
if nargin<3, runTag=char(datetime('now','Format','yyyyMMdd_HHmmss')); end
[p,cases,identity,sources]=sixgr.calibration.loadCampaign(configPath);
assert(~isempty(regexp(char(runTag),'^[A-Za-z0-9][A-Za-z0-9_-]*$','once')), ...
    'sixgr:calibration:RunTag','Use a single safe run-tag directory.');
folder=fullfile(outputRoot,runTag); if ~isfolder(folder), mkdir(folder); end
if ~isfolder(fullfile(folder,'episodes')), mkdir(fullfile(folder,'episodes')); end
meta=fullfile(folder,'campaign.mat');
rv=double(p.rv_sequence(:).');
roles=["reference","reference_validation","fit","validation"];
histories=cell(1,4);
for k=1:4, histories{k}=sixgr.calibration.historyGrid(p,roles(k)); end
counts=sixgr.calibration.startingPopulations(p,cases);
feasibility=sixgr.calibration.auditPopulationFeasibility(p,cases);
historyCounts=cellfun(@(h)size(h,1),histories);
total=sum(cellfun(@sum,counts),'all');
assert(p.seed_base+total*(2*numel(rv)+1)<2^32, ...
    'sixgr:calibration:Seeds','Population exceeds disjoint uint32 seed space.');
if isfile(meta)
    saved=load(meta,'identity');
    assert(saved.identity==identity,'sixgr:calibration:ResumeIdentity', ...
        'Source/scientific configuration changed; use a new run tag.');
else
    environment=struct('MATLAB',version,'Toolboxes',ver);
    [~,revision]=system('git rev-parse HEAD');
    sourceText=cell(height(sources),1);
    for k=1:height(sources), sourceText{k}=fileread(sources.Path(k)); end
    save(meta,'p','cases','identity','sources','sourceText','environment','revision','histories','-v7.3');
    copyfile(configPath,fullfile(folder,'input_campaign.yaml'));
    sixgr.util.jsonWrite(fullfile(folder,'resolved_campaign.json'),sixgr.util.jsonSafeValue(p));
    writetable(sources,fullfile(folder,'sources.csv'));
    writetable(feasibility,fullfile(folder,'population_feasibility.csv'));
end
% Balanced fixed sampling across direction, role and history. Stop-on-error
% does not select TB populations. Stop-on-success applies ONLY inside HARQ.
cursor=0; committed=0; executed=0; attempts=0; budgetReached=false;
for episodeIndex=1:max(cellfun(@max,counts),[],'all')
    for ci=1:numel(cases)
        for role=1:4
            for hi=1:historyCounts(role)
                if episodeIndex>counts{ci,role}(hi), continue; end
                cursor=cursor+1;
                file=fullfile(folder,'episodes',sprintf('episode_%09d.mat',cursor));
                if isfile(file)
                    sixgr.calibration.verifyEpisodeFile(file);
                    committed=committed+1; continue;
                end
                if executed>=p.episodes_per_invocation, budgetReached=true; break; end
                cfg=cases(ci).Config;
                channel=p.target_channel;
                if role<=2, channel=p.reference_channel; end
                cfg.channel=sixgr.util.mergeStruct(cfg.channel,channel);
                seedStart=double(p.seed_base)+(cursor-1)*(2*numel(rv)+1);
                seeds=seedStart+(0:2*numel(rv));
                receipt=localReceipt(folder,identity,total,committed,executed,attempts,"running");
                receipt.CurrentCase=cases(ci).ID; receipt.CurrentRole=roles(role);
                receipt.CurrentHistory=hi; localJSON(folder,receipt);
                try
                    episode=sixgr.calibration.executeEpisode(cfg,histories{role}(hi,:),rv,seeds,identity);
                catch ME
                    receipt.Status="failed"; receipt.ErrorIdentifier=string(ME.identifier);
                    receipt.ErrorMessage=string(ME.message); localJSON(folder,receipt); rethrow(ME)
                end
                episode.CampaignIdentity=identity; episode.CaseID=cases(ci).ID;
                episode.Direction=cases(ci).Direction; episode.Role=roles(role);
                episode.EpisodeIndex=episodeIndex; episode.HistoryIndex=hi;
                episode.EpisodeID=identity+"_"+cursor;
                episode.PlannedSNRHistory_dB=histories{role}(hi,:);
                temp=string(file)+".partial.mat"; save(temp,'episode','-v7');
                checksum=struct('EpisodeID',episode.EpisodeID,'SHA256',sixgr.csi.studyFileSHA256(temp));
                % Commit checksum before the final episode filename exists.
                sixgr.util.jsonWrite(string(file)+".sha256.json",checksum);
                sixgr.calibration.commitFile(temp,file);
                executed=executed+1; committed=committed+1; attempts=attempts+numel(episode.Attempts);
                fprintf('LINK_CALIBRATION case=%s role=%s history=%d episode=%d attempts=%d committed=%d/%d\n', ...
                    cases(ci).ID,roles(role),hi,episodeIndex,numel(episode.Attempts),committed,total);
            end
            if budgetReached, break; end
        end
        if budgetReached, break; end
    end
    if budgetReached, break; end
end
status="paused_at_invocation_budget"; if committed==total, status="collection_complete_not_qualified"; end
receipt=localReceipt(folder,identity,total,committed,executed,attempts,status);
for k=2:height(sources)
    if string(sixgr.csi.studyFileSHA256(sources.Path(k)))~=string(sources.SHA256(k))
        receipt.Status="failed_source_changed"; localJSON(folder,receipt);
        error('sixgr:calibration:SourceChanged','Implementation changed during collection; retained episodes are not qualified.');
    end
end
localJSON(folder,receipt);
sixgr.calibration.fitCollection(folder);
if isfield(p,'population_planning'), sixgr.calibration.planConditionalPopulations(folder); end
end
function r=localReceipt(folder,identity,total,committed,executed,attempts,status)
r=struct('Schema',"sixgr.link_calibration_receipt/v1",'RunFolder',string(folder), ...
    'CampaignIdentity',identity,'EpisodesPlanned',total,'EpisodesCommitted',committed, ...
    'EpisodesThisInvocation',executed,'AttemptsThisInvocation',attempts, ...
    'AllEpisodesComplete',committed==total,'Status',status,'PrimaryStudyAccepted',false, ...
    'UpdatedUTC',string(datetime('now','TimeZone','UTC','Format',"yyyy-MM-dd'T'HH:mm:ss'Z'")));
end
function localJSON(folder,r)
path=fullfile(folder,'receipt.json'); temporary=string(path)+".tmp";
sixgr.util.jsonWrite(temporary,r); sixgr.calibration.commitFile(temporary,path);
end
