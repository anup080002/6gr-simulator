function [p,collections,identity]=loadGrantCampaign(configPath)
%LOADGRANTCAMPAIGN Expand YAML into new, independently seeded waveform work.
% Sealed manifests supply allocation/configuration templates ONLY. No prior
% CRC, decoded bits, features or measured rows enter this campaign's results.
configPath=string(java.io.File(char(configPath)).getCanonicalPath());
p=sixgr.lls6g.config.readConfigFile(configPath);
root=fileparts(fileparts(fileparts(mfilename('fullpath'))));
catalog=sixgr.lls6g.config.readConfigFile(fullfile(root, ...
    'simulator','configs','schema','grant_calibration_campaign.yaml'));
localFields(p,[string(catalog.required_fields(:));string(catalog.optional_fields(:))], ...
    'campaign',string(catalog.required_fields));
if ~isfield(p,'evidence_storage'), p.evidence_storage=catalog.evidence_storage_default; end
assert(isscalar(string(p.evidence_storage)) && ...
    ismember(string(p.evidence_storage),string(catalog.evidence_storage_modes)), ...
    'sixgr:calibration:GrantEvidenceStorage','Unsupported lossless evidence storage policy.');
assert(string(p.schema)==string(catalog.campaign_schema) && ...
    ismember(string(p.research_class),string(catalog.research_classes)) && ...
    ismember(string(p.channel_evolution),string(catalog.channel_evolution)), ...
    'sixgr:calibration:GrantCampaignSchema','Unsupported schema, research class or channel evolution.');
localName(p.campaign_id);
validateattributes(p.seed_base,{'numeric'},{'scalar','integer','nonnegative','finite','<=',2^32-1});
validateattributes(p.episodes_per_invocation,{'numeric'},{'scalar','integer','positive','finite'});
raw=p.collections;
if isstruct(raw), raw=num2cell(raw); end
assert(iscell(raw) && ~isempty(raw) && ...
    all(cellfun(@(x)isstruct(x) && isscalar(x) && isfield(x,'id'),raw)), ...
    'sixgr:calibration:GrantCampaignCollections', ...
    'Declare collections with an explicit scenario allocation or sealed template.');
ids=cellfun(@(x)string(x.id),raw);
assert(numel(unique(ids))==numel(ids),'sixgr:calibration:GrantCampaignCollections', ...
    'Collection IDs must be unique.');
collections=struct([]); nextSeed=double(p.seed_base);
roles=string(catalog.roles);
for ci=1:numel(raw)
    c=raw{ci}; localName(c.id); sourceInputs=struct('Path',{},'SHA256',{},'Text',{});
    if isfield(c,'scenario_config')
        localFields(c,string(catalog.allocation_collection_fields),'allocation collection');
        path=localPath(configPath,c.scenario_config);
        request=sixgr.config.loadSimulationRequest(path);
        assert(request.Mode=="SLS",'sixgr:calibration:GrantCampaignScenario', ...
            'Allocation templates require a validated native SLS configuration.');
        cfg=request.Config;
        % defaultConfig stamps each load, not each physical experiment.
        % Retain input texts/hashes below, but never include this load-time
        % metadata in a resumable collection's immutable physical recipe.
        if isfield(cfg,'meta') && isfield(cfg.meta,'createdUTC')
            cfg.meta=rmfield(cfg.meta,'createdUTC');
        end
        grants=sixgr.calibration.buildGrantCalibrationAllocation(cfg,c.allocation);
        sourceInputs=repmat(struct('Path',"",'SHA256',"",'Text',""),numel(request.SourceFiles),1);
        for fi=1:numel(request.SourceFiles)
            sourceInputs(fi)=struct('Path',request.SourceFiles(fi), ...
                'SHA256',sixgr.csi.studyFileSHA256(request.SourceFiles(fi)), ...
                'Text',string(fileread(request.SourceFiles(fi)))); %#ok<AGROW>
        end
        templateHash=localHash(struct('Config',cfg,'Allocation',c.allocation,'Inputs',sourceInputs));
        templateIdentity=templateHash;
        templateUsage="configured_planned_allocation_ideal_control_no_outcomes";
    else
    localFields(c,string(catalog.collection_fields),'collection');
    path=localPath(configPath,c.template_manifest);
    assert(isfile(path) && isscalar(string(c.template_manifest_sha256)) && ...
        strcmpi(string(c.template_manifest_sha256),sixgr.csi.studyFileSHA256(path)), ...
        'sixgr:calibration:GrantCampaignTemplateDigest','Missing or changed template manifest: %s',path);
    sixgr.calibration.verifyEpisodeFile(path);
    saved=load(path,'cfg','plan','sources','identity');
    assert(all(isfield(saved,{'cfg','plan','sources','identity'})), ...
        'sixgr:calibration:GrantCampaignTemplate','Template must be a sealed grant collection manifest.');
    match=find(string({saved.plan.EpisodeID})==string(c.template_episode_id));
    assert(numel(match)==1,'sixgr:calibration:GrantCampaignTemplate', ...
        'template_episode_id must identify exactly one retained allocation plan.');
    cfg=saved.cfg; grants=saved.plan(match).Grants;
    templateHash=string(c.template_manifest_sha256); templateIdentity=string(saved.identity);
    templateUsage="allocation_and_config_only_no_outcomes_reused";
    end
    n=numel(grants);
    assert(iscell(grants) && n>0,'sixgr:calibration:GrantCampaignTemplate','Missing frozen grant history.');
    for j=1:n
        sixgr.system.abstraction.scheduledDataREMap(cfg,grants{j},grants{j}.ScheduledAbsoluteSlot);
    end
    histories=double(c.snr_histories_db);
    if n==1
        histories=histories(:);
    elseif isvector(histories) && numel(histories)==n
        % JSON/YAML loaders may return a column for one history row.
        histories=reshape(histories,1,n);
    end
    assert(ismatrix(histories) && ~isempty(histories) && size(histories,2)==n && ...
        all(isfinite(histories),'all') && size(unique(histories,'rows'),1)==size(histories,1), ...
        'sixgr:calibration:GrantCampaignHistory', ...
        'snr_histories_db needs one finite column per attempt and distinct history rows.');
    nh=size(histories,1);
    counts=[localCounts(c.fit_starts_per_history,nh),localCounts(c.validation_starts_per_history,nh)];
    persistentLink=string(p.channel_evolution)=="persistent_link_absolute_slot";
    width=1+3*n+n*(~persistentLink)+double(persistentLink);
    assert(nextSeed+sum(counts,'all')*width<=2^32, ...
        'sixgr:calibration:GrantCampaignSeeds','Population exceeds disjoint uint32 seed space.');
    entries=cell(1,sum(counts,'all')); cursor=0;
    % Balanced history/role rounds, independent of invocation size. Never
    % select new starting TBs based on their eventual decoder outcome.
    for sample=1:max(counts,[],'all')
        for ri=1:numel(roles)
            for hi=1:nh
                if sample>counts(hi,ri), continue; end
                cursor=cursor+1;
                episodeID=string(p.campaign_id)+"/"+string(c.id)+"/"+roles(ri)+"/h"+hi+"/n"+sample;
                g=grants;
                for j=1:n, g{j}.TransportBlockIdentity=episodeID; end
                seq=nextSeed+(0:width-1); nextSeed=nextSeed+width;
                s=struct('Bits',seq(1),'Noise',seq(2:n+1), ...
                    'ControlNoise',seq(n+2:2*n+1),'RF',seq(2*n+2:3*n+1), ...
                    'ChannelEvolution',string(p.channel_evolution));
                if persistentLink, s.Channel=repmat(seq(end),1,n); else, s.Channel=seq(3*n+2:end); end
                sixgr.system.waveform.validateGrantCalibrationSeeds(s,n);
                entries{cursor}=struct('EpisodeID',episodeID,'Role',roles(ri), ...
                    'Grants',{g},'SNRdB',histories(hi,:),'Seeds',s);
            end
        end
    end
    item=struct('ID',string(c.id),'Config',cfg,'Plan',[entries{:}], ...
        'TemplateManifest',path,'TemplateSHA256',templateHash, ...
        'TemplateCollectionIdentity',templateIdentity,'SourceInputs',sourceInputs, ...
        'TemplateUsage',templateUsage);
    if isempty(collections), collections=item; else, collections(end+1)=item; end %#ok<AGROW>
end
science=rmfield(p,'episodes_per_invocation');
identity=localHash(struct('Campaign',science,'ResolvedTemplateHashes',string({collections.TemplateSHA256})));
end

function path=localPath(configPath,value)
path=string(value);
assert(isscalar(path),'sixgr:calibration:GrantCampaignPath','Expected one input path.');
if ~java.io.File(char(path)).isAbsolute(), path=fullfile(fileparts(configPath),path); end
path=string(java.io.File(char(path)).getCanonicalPath());
end

function hash=localHash(value)
hash=string(sixgr.util.sha256Hex(uint8(unicode2native( ...
    jsonencode(sixgr.util.jsonSafeValue(value)),'UTF-8'))));
end

function localFields(value,fields,label,required)
if nargin<4, required=fields; end
assert(isstruct(value) && isscalar(value) && ...
    all(isfield(value,cellstr(required))) && all(ismember(string(fieldnames(value)),fields)), ...
    'sixgr:calibration:GrantCampaignFields','Missing or unknown %s fields; allowed: %s',label,join(fields,', '));
end

function localName(value)
assert(isscalar(string(value)) && ~isempty(regexp(char(value),'^[A-Za-z0-9][A-Za-z0-9_-]*$','once')), ...
    'sixgr:calibration:GrantCampaignName','Use a single safe campaign/collection identifier.');
end

function counts=localCounts(value,n)
validateattributes(value,{'numeric'},{'vector','integer','positive','finite'});
counts=double(value(:));
if isscalar(counts), counts=repmat(counts,n,1); end
assert(numel(counts)==n,'sixgr:calibration:GrantCampaignPopulation', ...
    'Starting populations must be scalar or have one entry per SNR history.');
end
