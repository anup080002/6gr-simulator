function receipt=runPUCCHDetectorCampaign(configPath,outputRoot)
% Resumable, preregistered physical campaign. No automatic qualification.
% Call again with the same config/root to execute the next declared batch.
% Started attempts are never replaced; missing/corrupt evidence fails closed.
v=sixgr.lls6g.config.readConfigFile(configPath);
p=sixgr.lls6g.config.readConfigFile(v.episode_policy_path);
seeds=validatePUCCHDetectorCampaignPolicy(v,p);
scenario=sixgr.lls6g.config.loadScenarioConfig(p.scenario_path);
[code,revision]=system('git rev-parse HEAD'); assert(code==0);
[code,dirty]=system('git status --porcelain');
assert(code==0 && isempty(strtrim(dirty)),'test:CampaignSource','Freeze a clean source revision first.');
root=char(java.io.File(outputRoot).getCanonicalPath());
logs=char(java.io.File(fullfile(pwd,'logs')).getCanonicalPath());
assert(startsWith(lower(string(root)),lower(string(logs))+filesep), ...
    'test:CampaignOutput','Campaign output must be a child of this checkout''s logs folder.');
identity=struct('SchemaVersion',1,'GitRevision',strtrim(revision), ...
    'PolicySHA256',sixgr.util.sha256File(configPath), ...
    'EpisodePolicySHA256',sixgr.util.sha256File(v.episode_policy_path), ...
    'ResolvedScenarioSHA256',sixgr.util.sha256Hex(jsonencode(scenario.toStruct())), ...
    'MATLABVersion',version,'Platform',computer,'Seeds',seeds, ...
    'Policy',v,'EpisodePolicy',p);
manifest=fullfile(root,'registration.mat');
if ~isfolder(root), mkdir(root); end
lockPath=fullfile(root,'campaign.lock');
assert(java.io.File(lockPath).mkdir(),'test:CampaignLocked', ...
    'An active or interrupted owner has locked %s; do not launch a second owner.',root);
lockCleanup=onCleanup(@()rmdir(lockPath)); %#ok<NASGU> % Only this newly created empty lock.
if isfile(manifest)
    old=load(manifest,'identity');
    assert(isequaln(identity,old.identity),'test:CampaignFreeze', ...
        'Source, MATLAB, seeds, config or resolved scenario changed after registration.');
else
    contents=dir(root); names=string({contents.name});
    assert(all(ismember(names,[".","..","campaign.lock"])), ...
        'test:CampaignRegistration','Refusing unregistered existing evidence.');
    save(manifest,'identity');
    sixgr.util.jsonWrite(fullfile(root,'registration.json'),identity);
    copyfile(configPath,fullfile(root,'input_campaign.yaml'));
    copyfile(v.episode_policy_path,fullfile(root,'input_episode_policy.yaml'));
    sixgr.util.jsonWrite(fullfile(root,'resolved_scenario.json'),scenario.toStruct());
end
sixgr.util.jsonWrite(fullfile(root,'run_status.json'),struct('Status','running', ...
    'GitRevision',strtrim(revision),'DetectorQualified',false));
rows=table(); launched=0; incomplete=[];
for n=1:v.episodes
    folder=fullfile(root,sprintf('attempt_%06d',n));
    ep=p; ep.stage='held_out_campaign_episode'; ep.episodes=1; ep.seed_base=seeds(n);
    if ~isfolder(folder) && launched<v.execution_batch_episodes
        [canStillPass,~]=localCanStillPass(v,p,rows,incomplete);
        if ~canStillPass
            break; % A registered failed/missing attempt is never replaced.
        end
        localSourceCheck(revision);
        mkdir(folder); % Durable attempt marker BEFORE executing RF.
        episodePath=fullfile(folder,'episode_policy.json');
        sixgr.util.jsonWrite(episodePath,ep);
        launched=launched+1;
        try
            runPUCCHDetectorEpisodes(episodePath,fullfile(folder,'physical'));
        catch err
            [message,diagnostic]=sixgr.util.formatExceptionDiagnostic(err);
            sixgr.util.jsonWrite(fullfile(folder,'execution_failure.json'),diagnostic);
            fprintf('CAMPAIGN_ATTEMPT_FAILED episode=%d %s\n',n,message);
        end
    end
    if ~isfolder(folder), continue; end
    episodePath=fullfile(folder,'episode_policy.json');
    assert(isfile(episodePath) && isequaln( ...
        sixgr.lls6g.config.readConfigFile(episodePath),ep), ...
        'test:CampaignFreeze','Attempt %d policy does not match registration.',n);
    physical=fullfile(folder,'physical');
    csvPath=fullfile(physical,'physical_trials.csv');
    if ~isfile(csvPath)
        incomplete(end+1)=n; %#ok<AGROW>
        continue; % Missing observations are never replaced with fabricated rows.
    end
    part=localAuditEpisode(physical,ep,scenario,revision);
    part.CampaignEpisode=repmat(n,height(part),1);
    if isempty(rows), rows=part; else, rows=[rows;part]; end %#ok<AGROW>
    if height(part)~=numel(p.cases), incomplete(end+1)=n; end %#ok<AGROW>
end
localSourceCheck(revision);
summary=summarizePUCCHDetectorCampaign(v,p,rows);
[canStillPass,terminalReason]=localCanStillPass(v,p,rows,incomplete);
if ~isempty(rows)
    sixgr.util.csvWriteTable(fullfile(root,'physical_trials.csv'),rows,'PreserveSchema',true);
end
sixgr.util.csvWriteTable(fullfile(root,'case_summary.csv'),summary,'PreserveSchema',true);
receipt=struct('Status','partial','GitRevision',strtrim(revision), ...
    'RegistrationSHA256',sixgr.util.sha256File(manifest), ...
    'PhysicalRows',height(rows),'PlannedEpisodesPerCase',v.episodes, ...
    'NewAttemptsThisInvocation',launched,'IncompleteAttempts',incomplete, ...
    'AllPhysicalCasesPresent',all(summary.UnavailableEpisodes==0), ...
    'AllConfidenceGatesPassed',all(summary.ConfidenceGatePassed), ...
    'QualificationStillPossible',logical(canStillPass), ...
    'TerminalFailureReason',string(terminalReason), ...
    'DevelopmentHistoryDeclaredComplete',v.development_history_complete, ...
    'IndependentEvidenceReviewComplete',false,'DetectorQualified',false, ...
    'Scope','registered_campaign_evidence_pending_independent_review_not_12db_acceptance');
if receipt.AllPhysicalCasesPresent, receipt.Status='physical_campaign_complete_pending_review'; end
if ~isempty(incomplete), receipt.Status='incomplete_attempts_preserved'; end
if ~canStillPass
    receipt.Status='candidate_rejected_terminal';
    receipt.Scope='registered_campaign_candidate_rejected_not_detector_qualification';
end
sixgr.util.jsonWrite(fullfile(root,'run_status.json'),receipt);
fprintf('DETECTOR_CAMPAIGN_BATCH rows=%d new_attempts=%d qualified=0\n',height(rows),launched);
end

function [possible,reason]=localCanStillPass(v,p,rows,incomplete)
% Best-case bound: assume every not-yet-started episode is error-free.  A
% started incomplete attempt is permanently unavailable by campaign design.
if ~isempty(incomplete)
    possible=false;
    reason="started_attempt_missing_required_physical_cases";
    return;
end
possible=true; reason="";
caseCount=numel(p.cases);
for k=1:caseCount
    errors=0;
    if ~isempty(rows)
        errors=sum(rows.EventError(rows.CaseID==string(p.cases(k).id)));
    end
    if errors>=v.episodes
        possible=false;
        reason="observed_event_count_exhausted_campaign:"+string(p.cases(k).id);
        return;
    end
    bestCaseUpper=betaincinv(1-v.family_alpha/caseCount, ...
        errors+1,v.episodes-errors);
    if bestCaseUpper>v.event_error_limit
        possible=false;
        reason="best_case_confidence_bound_exceeds_event_error_limit:"+ ...
            string(p.cases(k).id);
        return;
    end
end
end

function localSourceCheck(revision)
[code,current]=system('git rev-parse HEAD');
assert(code==0 && strcmp(current,revision),'test:CampaignSource','Source revision changed.');
[code,dirty]=system('git status --porcelain');
assert(code==0 && isempty(strtrim(dirty)),'test:CampaignSource','Source became dirty.');
end

function rows=localAuditEpisode(root,policy,scenario,revision)
environment=sixgr.lls6g.config.readConfigFile(fullfile(root,'meta','environment.json'));
assert(strcmp(environment.GitRevision,strtrim(revision)) && ...
    strcmp(environment.MATLABVersion,version) && ...
    startsWith(string(environment.Scope),'held_out_campaign_episode;'), ...
    'test:CampaignEvidence','Episode environment/source/scope mismatch.');
rows=readtable(fullfile(root,'physical_trials.csv'),'TextType','string');
configuration=load(fullfile(root,'episode_000001','configuration.mat'),'cfg','v','seed');
assert(isequaln(configuration.v,policy) && configuration.seed==policy.seed_base && ...
    configuration.cfg.run.seed==policy.seed_base && configuration.cfg.channel.seed==policy.seed_base, ...
    'test:CampaignEvidence','Retained runtime configuration/seed differs from registration.');
assert(height(rows)<=numel(policy.cases) && numel(unique(rows.CaseID))==height(rows) && ...
    all(rows.Episode==1 & rows.Seed==policy.seed_base), ...
    'test:CampaignEvidence','Duplicate, excess or incorrectly seeded episode rows.');
for k=1:height(rows)
    selected=find(string({policy.cases.id})==rows.CaseID(k));
    assert(isscalar(selected),'test:CampaignEvidence','Unknown physical case.');
    c=policy.cases(selected);
    expected=fullfile(root,'episode_000001',char(rows.CaseID(k)+".mat"));
    assert(strcmp(char(java.io.File(char(rows.EvidencePath(k))).getCanonicalPath()), ...
        char(java.io.File(expected).getCanonicalPath())) && ...
        string(sixgr.util.sha256File(expected))==rows.EvidenceSHA256(k), ...
        'test:CampaignEvidence','Evidence path/hash mismatch.');
    saved=load(expected);
    assert(isequaln(saved.testCase,c),'test:CampaignEvidence','Declared case mismatch.');
    rx=saved.out;
    [samples,postStart,postEnd,postRate]=localSavedObservation(saved,"post");
    [txSamples,~,~,~]=localSavedObservation(saved,"tx");
    assert(~isempty(samples) && all(isfinite(samples),'all') && ...
        rx.IndependentReceiverAssignment && ~rx.PreparedTransmitterConsumed && ...
        ~rx.OraclePayloadBitsUsed && ~rx.InjectedNoiseVarianceConsumed && ...
        ~rx.InjectedInterferenceCovarianceConsumed && ~rx.ReceiveTiming.OracleTimingUsed && ...
        ~rx.ReceiveTiming.ReceiverZeroPaddingUsed,'test:CampaignEvidence','Nonphysical or oracle-aided RX evidence.');
    decoded=jsondecode(rows.DecodedPayloadJSON(k));
    declared=jsondecode(rows.DeclaredPayloadJSON(k));
    assert(rx.DetectionThreshold==scenario.Data.pucch.detection_threshold_format0_two_symbols && ...
        rows.DetectionThreshold(k)==rx.DetectionThreshold && ...
        isfinite(rx.DetectionMetric) && ...
        abs(rows.DetectionMetric(k)-rx.DetectionMetric)<=8*eps(max(1,abs(rx.DetectionMetric))) && ...
        rows.Slot(k)==c.slot && rows.HARQBits(k)==c.harq_bits && ...
        rows.SignalPresent(k)==c.signal_present && rows.DTX(k)==rx.DTX && ...
        rows.ObservationStartSample(k)==postStart && ...
        rows.ObservationEndSampleExclusive(k)==postEnd && ...
        rows.SampleRateHz(k)==postRate && ...
        isequal(double(decoded(:)),double(rx.DecodedSequence1(:))) && ...
        isequal(double(declared(:)),double(c.payload(:))), ...
        'test:CampaignEvidence','RX policy/payload/CSV mismatch.');
    if ~c.signal_present
        assert(~any(txSamples~=0,'all'),'test:CampaignEvidence','Noise case contains TX samples.');
    end
    counts=countPUCCHDetectorPilotErrors(c,rx.DecodedSequence1,rx.ReceiverUsable,rx.DTX);
    for field=string(fieldnames(counts)).'
        assert(rows.(field)(k)==double(counts.(field)), ...
            'test:CampaignEvidence','Physical CSV error count differs from retained receiver output.');
    end
end
end

function [samples,startSample,endSample,sampleRate]=localSavedObservation(saved,name)
compactName=char(name+"Evidence");
legacyName=char(name);
if isfield(saved,compactName)
    evidence=saved.(compactName);
    assert(evidence.Complete,'test:CampaignEvidence','Saved observation is incomplete.');
    samples=evidence.Samples;
    startSample=evidence.StartSample;
    endSample=evidence.EndSampleExclusive;
    sampleRate=evidence.SampleRateHz;
else
    observation=saved.(legacyName); % Audit retained schema-v1 evidence.
    samples=observation.readComplete();
    startSample=observation.StartSample;
    endSample=observation.EndSampleExclusive;
    sampleRate=observation.SampleRateHz;
end
end
