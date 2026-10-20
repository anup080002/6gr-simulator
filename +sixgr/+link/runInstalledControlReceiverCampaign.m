function receipt=runInstalledControlReceiverCampaign(configPath,outputRoot,runTag,signal)
% YAML-driven installed-context receiver episodes with immutable resume.
% No access/shared-history claim. No detector tuning, dropped failures,
% surrogate samples, early statistical decisions or silent retries.
arguments
    configPath (1,1) string
    outputRoot (1,1) string
    runTag (1,1) string
    signal (1,1) string {mustBeMember(signal,["PUCCH","PDCCH"])}
end
id=char("sixgr:"+lower(signal)+":InstalledCampaignIntegrity");
validator=str2func("sixgr.phy."+lower(signal)+".validateInstalledReceiverCampaign");
schemaPath="simulator/configs/validation/installed_"+lower(signal)+"_campaign_schema.yaml";
assert(~isempty(regexp(char(runTag),'^[A-Za-z0-9_-]+$','once')),id,'Use a safe run tag, not a path.');
policy=sixgr.lls6g.config.readConfigFile(configPath);
schema=validator(policy);
base=sixgr.lls6g.config.loadScenarioConfig(policy.scenario_path);
root=string(java.io.File(char(fullfile(outputRoot,runTag))).getCanonicalPath());
if ~isfolder(root), mkdir(root); end
% An OS lock is released on process death. Do not delete evidence or rely on
% a stale PID file to exclude concurrent writers.
lockFile=java.io.RandomAccessFile(char(fullfile(root,'writer.lock')),'rw');
channel=lockFile.getChannel();
closeFiles=onCleanup(@()localClose(channel,lockFile)); %#ok<NASGU>
try
    lock=channel.tryLock();
catch cause
    error(id,'Cannot acquire the campaign writer lock: %s',cause.message);
end
assert(~isempty(lock),id,'Another process owns this campaign.');
% Closing the owning channel releases its lock. A second onCleanup for
% release is unsafe: cleanup objects have no guaranteed destruction order.
identity=localIdentity(configPath,policy,base,schema,signal);
fingerprint=string(sixgr.util.sha256Hex(jsonencode(identity)));
if string(policy.stage)=="frozen_qualification"
    assert(identity.GitClean,id,'Freeze and commit source before qualification; development may use hashed edits.');
end
meta=fullfile(root,'meta'); frozenPath=fullfile(meta,'frozen.mat');
sealPath=fullfile(meta,'frozen_sha256.json');
if isfolder(meta)
    assert(isfile(frozenPath)&&isfile(sealPath),id,'Incomplete campaign initialization; preserve this folder.');
    seal=jsondecode(fileread(sealPath));
    assert(string(sixgr.util.sha256File(frozenPath))==string(seal.SHA256),id,'Frozen input file changed.');
    saved=load(frozenPath,'fingerprint','inputManifest');
    assert(string(saved.fingerprint)==fingerprint,id, ...
        'Source, MATLAB environment, YAML, policy or seed schedule changed; do not mix populations.');
    localVerifyFiles(fullfile(meta,'input_configs'),saved.inputManifest,id);
else
    existing=dir(root); existing=existing(~ismember({existing.name},{'.','..','writer.lock'}));
    assert(isempty(existing),id,'A nonempty folder without frozen campaign inputs cannot be resumed.');
    mkdir(meta); mkdir(fullfile(meta,'input_configs'));
    sixgr.util.jsonWrite(fullfile(meta,'identity.json'),identity);
    sixgr.util.jsonWrite(fullfile(meta,'resolved_config.json'),base.toStruct());
    sixgr.util.jsonWrite(fullfile(meta,'campaign_policy.json'),policy);
    sixgr.util.jsonWrite(fullfile(meta,'schema_validation_report.json'), ...
        struct('Valid',true,'Schema',schema,'Scope',policy.scope));
    paths=[string(configPath);base.SourceFiles; ...
        schemaPath];
    for k=1:numel(paths)
        [~,name,ext]=fileparts(paths(k));
        destination=fullfile(meta,'input_configs',sprintf('%03d_',k)+name+ext);
        copyfile(paths(k),destination);
        assert(string(sixgr.util.sha256File(destination))==string(sixgr.util.sha256File(paths(k))), ...
            id,'Raw input copy hash mismatch.');
    end
    inputManifest=localFiles(fullfile(meta,'input_configs'));
    save(frozenPath,'identity','fingerprint','policy','schema','base','inputManifest');
    % Commit initialization only after every raw input has been retained.
    sixgr.util.jsonWrite(sealPath,struct('SHA256',sixgr.util.sha256File(frozenPath)));
end
episodeRoot=fullfile(root,'episodes');
if ~isfolder(episodeRoot), mkdir(episodeRoot); end
events=table(); nc=numel(policy.cases); total=policy.episodes_per_case*nc;
for sequence=1:total
    folder=fullfile(episodeRoot,sprintf('episode_%08d',sequence));
    if ~isfolder(folder), break; end
    record=localReadCommitted(folder,fingerprint,signal);
    events=[events;record.Events]; %#ok<AGROW>
end
% Refuse gaps, unfinished attempts and foreign folders instead of skipping.
entries=dir(episodeRoot); entries=entries(~ismember({entries.name},{'.','..'}));
assert(numel(entries)==height(events),id,'Noncontiguous/uncommitted episodes require inspection, not replacement samples.');
localSummarize(events,policy,signal);
limit=min(total,height(events)+policy.execution_batch_episodes);
for sequence=height(events)+1:limit
    timer=tic; c=policy.cases(mod(sequence-1,nc)+1);
    folder=fullfile(episodeRoot,sprintf('episode_%08d',sequence));
    assert(~isfolder(folder),id,'Do not overwrite an attempted realization.'); mkdir(folder);
    seed=policy.seed_base+(sequence-1)*policy.seed_stride;
    design=struct('EpisodeID',runTag+"_"+sprintf('%08d',sequence), ...
        'UEIndex',c.ue_index,'ServingCell',c.serving_cell,'ChannelSeed',seed, ...
        'NoiseSeed',seed+policy.noise_seed_offset,'GuardSamples',policy.guard_samples, ...
        'SignalPresent',c.signal_present);
    if signal=="PDCCH"
        design.AbsoluteSlot0=c.absolute_slot0; design.TimingBoundary=policy.timing_boundary;
    end
    save(fullfile(folder,'started.mat'),'fingerprint','design','c','sequence');
    fprintf('INSTALLED_%s_EPISODE %d/%d case=%s channel_seed=%u noise_seed=%u\n', ...
        signal,sequence,total,string(c.id),design.ChannelSeed,design.NoiseSeed);
    try
        source=sixgr.link.seedInstalledControlScenario(base,policy,seed,signal);
        cfg=sixgr.lls6g.buildInternalConfig(source,folder);
        assert(cfg.run.seed==seed && cfg.channel.seed==seed,id, ...
            'Authored seed paths did not reach run/channel ownership.');
        save(fullfile(folder,'resolved_scenario.mat'),'source');
        if signal=="PUCCH"
            [cfg,assignment,context,tx]=sixgr.link.buildConfiguredPUCCHEpisode(cfg,c);
            outcome=sixgr.link.runIndependentPUCCHReceiverEpisode( ...
                cfg,assignment,context,tx,design,fullfile(folder,'physical'));
        else
            [cfg,tx]=sixgr.link.buildConfiguredPDCCHCampaignEpisode(cfg,c);
            outcome=sixgr.link.runIndependentPDCCHReceiverEpisode( ...
                cfg,tx,design,fullfile(folder,'physical'));
        end
        row=outcome.Events;
        row.CaseID=string(c.id); row.Sequence=sequence; row.Replicate=floor((sequence-1)/nc)+1;
        row.ChannelSeed=design.ChannelSeed; row.NoiseSeed=design.NoiseSeed;
        row.ScenarioConfigSHA256=source.ConfigHash; row.CampaignIdentitySHA256=fingerprint;
        current=localIdentity(configPath,policy,base,schema,signal);
        assert(string(sixgr.util.sha256Hex(jsonencode(current)))==fingerprint,id, ...
            'Executed source/configuration changed during this episode.');
        record=struct('Events',row,'Design',design,'Case',c,'CampaignIdentity',fingerprint, ...
            'ElapsedSeconds',toc(timer),'Evidence',localFiles(folder));
        if signal=="PDCCH"
            record.ReceiverContextDigests=outcome.Execution.ReceiverContextDigests;
        end
        save(fullfile(folder,'completed.mat'),'record');
        sixgr.util.jsonWrite(fullfile(folder,'commit.json'), ...
            struct('SHA256',sixgr.util.sha256File(fullfile(folder,'completed.mat'))));
        % Reload and verify the actual persisted record before counting it.
        record=localReadCommitted(folder,fingerprint,signal);
        events=[events;record.Events]; %#ok<AGROW>
        localPublish(root,events,policy,fingerprint,identity.GitClean,signal);
        clear outcome tx cfg assignment context source
    catch cause
        failure=struct('Identifier',cause.identifier,'Message',cause.message, ...
            'Report',getReport(cause,'extended','hyperlinks','off'), ...
            'Episode',sequence,'EvidencePreserved',true,'RetryAllowed',false);
        sixgr.util.jsonWrite(fullfile(folder,'failure.json'),failure);
        rethrow(cause);
    end
end
receipt=localPublish(root,events,policy,fingerprint,identity.GitClean,signal);
end

function identity=localIdentity(configPath,policy,base,schema,signal)
% Hash content, not timestamps. Toolkit files plus authored scenario and
% validation catalogs are immutable for a resumed population.
sources=sixgr.calibration.grantSourceIdentity();
repo=fileparts(fileparts(fileparts(mfilename('fullpath'))));
catalogs=[dir(fullfile(repo,'simulator','configs','**','*.yaml')); ...
    dir(fullfile(repo,'simulator','configs','**','*.json'));dir(fullfile(repo,'*.m'))];
extra=sort([string(fullfile({catalogs.folder},{catalogs.name})).'; ...
    string(java.io.File(char(configPath)).getCanonicalPath());base.SourceFiles]);
hashes=strings(size(extra));
for k=1:numel(extra), hashes(k)=sixgr.util.sha256File(extra(k)); end
% Include ignored local accelerator binaries, not only git-tracked files.
accelerators=[dir(fullfile(repo,'*.mex*'));dir(fullfile(repo,'+sixgr','**','*.mex*')); ...
    dir(fullfile(repo,'mex','**','*.mex*'))];
binaryPaths=sort(string(fullfile({accelerators.folder},{accelerators.name})).');
binaryHashes=strings(size(binaryPaths));
for k=1:numel(binaryPaths), binaryHashes(k)=sixgr.util.sha256File(binaryPaths(k)); end
id=char("sixgr:"+lower(signal)+":MissingSourceIdentity");
[status,head]=system('git rev-parse HEAD'); assert(status==0,id);
[status,dirty]=system('git status --porcelain'); assert(status==0,id);
identity=struct('CoreSources',sources,'ConfigPaths',extra,'ConfigSHA256',hashes, ...
    'AcceleratorPaths',binaryPaths,'AcceleratorSHA256',binaryHashes, ...
    'GitHEAD',strtrim(string(head)),'GitClean',isempty(strtrim(dirty)), ...
    'GitWorkingTree',string(dirty),'Policy',policy,'Schema',schema, ...
    'ScenarioConfigSHA256',base.ConfigHash,'ResolvedScenario',base.toStruct(), ...
    'SignalFamily',signal,'ContinuousRuntimeExecuted',false,'NRConformanceQualified',false);
end

function files=localFiles(folder)
listing=dir(fullfile(folder,'**','*')); listing=listing(~[listing.isdir]);
paths=sort(string(fullfile({listing.folder},{listing.name})).');
relative=erase(paths,string(folder)+filesep); hashes=strings(size(paths));
for k=1:numel(paths), hashes(k)=sixgr.util.sha256File(paths(k)); end
files=table(relative,hashes,'VariableNames',{'Path','SHA256'});
end

function record=localReadCommitted(folder,identity,signal)
id=char("sixgr:"+lower(signal)+":InstalledCampaignIntegrity");
path=fullfile(folder,'completed.mat'); commit=fullfile(folder,'commit.json');
assert(isfile(path)&&isfile(commit),id, ...
    'An attempted episode has no complete receipt. Preserve it; do not silently retry or skip.');
seal=jsondecode(fileread(commit));
assert(string(sixgr.util.sha256File(path))==string(seal.SHA256),id,'Episode receipt checksum changed.');
loaded=load(path,'record'); record=loaded.record;
assert(string(record.CampaignIdentity)==identity && height(record.Events)==1 && ...
    record.Events.CampaignIdentitySHA256==identity,id,'Episode belongs to another campaign.');
localVerifyFiles(folder,record.Evidence,id);
physical=load(fullfile(folder,'physical','receiver_output.mat'),'execution');
e=physical.execution; d=record.Design;
assert(e.EpisodeID==d.EpisodeID && e.ChannelSeed==d.ChannelSeed && e.NoiseSeed==d.NoiseSeed && ...
    e.SignalPresent==d.SignalPresent && record.Events.EpisodeID==e.EpisodeID, ...
    id,'Physical output identity is inconsistent.');
if signal=="PUCCH"
    assert(record.Events.ReceiverAssignmentDigest==e.ReceiverAssignmentDigest && ...
        record.Events.ReceiverContextDigest==e.ReceiverContextDigest,id,'UCI context identity changed.');
else
    assert(e.AbsoluteSlot0==d.AbsoluteSlot0 && string(e.TimingBoundary)==string(d.TimingBoundary) && ...
        isequal(e.ReceiverContextDigests,record.ReceiverContextDigests) && ...
        record.Events.AbsoluteSlot0==e.AbsoluteSlot0,id,'Installed DCI context/timing identity changed.');
end
end

function localVerifyFiles(folder,files,id)
for k=1:height(files)
    relative=string(files.Path(k));
    candidate=string(java.io.File(char(fullfile(folder,relative))).getCanonicalPath());
    assert(startsWith(lower(candidate),lower(string(folder)+filesep)),id,'Evidence path escapes episode folder.');
    assert(isfile(candidate) && string(sixgr.util.sha256File(candidate))==files.SHA256(k), ...
        id,'Required episode evidence is missing or altered: %s.',relative);
end
end

function receipt=localPublish(root,events,policy,fingerprint,clean,signal)
summary=localSummarize(events,policy,signal);
csv=fullfile(root,'reports','csv'); if ~isfolder(csv), mkdir(csv); end
if height(events)>0
    sixgr.util.csvWriteTable(fullfile(csv,'receiver_episodes.csv'),events,'PreserveSchema',true);
end
sixgr.util.csvWriteTable(fullfile(csv,'qualification_status.csv'),summary,'PreserveSchema',true);
complete=height(events)==numel(policy.cases)*policy.episodes_per_case;
eligible=complete && string(policy.stage)=="frozen_qualification" && clean && policy.development_history_complete;
receipt=struct('RunFolder',root,'CompletedEpisodes',height(events), ...
    'PlannedEpisodes',numel(policy.cases)*policy.episodes_per_case,'CollectionComplete',complete, ...
    'Stage',policy.stage,'Scope',policy.scope,'SignalFamily',signal,'CampaignIdentitySHA256',fingerprint, ...
    'FixedSampleStatisticalDecisionEligible',eligible, ...
    'AllConfiguredBoundsMet',complete&&all(summary.StatisticalDecision=="BOUND_MEETS_CONFIGURED_LIMIT"), ...
    'DetectorQualified',false,'ScenarioAccepted',false,'NRConformanceQualified',false, ...
    'RemainingAcceptance',"independent_review_of_scope_seed_history_and_full_runtime_coverage");
sixgr.util.jsonWrite(fullfile(root,'receipt.json'),receipt);
fprintf('INSTALLED_%s_PROGRESS episodes=%d/%d stage=%s detector_qualified=0\n', ...
    signal,receipt.CompletedEpisodes,receipt.PlannedEpisodes,string(policy.stage));
end
function localClose(channel,file)
try, channel.close(); catch, end
try, file.close(); catch, end
end


function summary=localSummarize(events,policy,signal)
summarize=str2func("sixgr.phy."+lower(signal)+".summarizeInstalledReceiverCampaign");
summary=summarize(events,policy);
end
