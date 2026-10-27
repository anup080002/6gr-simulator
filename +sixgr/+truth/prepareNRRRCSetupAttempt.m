function [state,cfg]=prepareNRRRCSetupAttempt(state,cfg,ue)
% Main-run initial RRC initiation, before the first MAC preamble attempt.
policy=sixgr.lls6g.config.resolveNRAccessPolicy(sixgr.util.structGet(cfg,'initial_access.rrc',struct()));
if ~policy.Enabled,return;end
id='sixgr:truth:NRRRCInitialAttempt';
assert(isfield(state,'SharedWaveformStream') && ...
    isa(state.SharedWaveformStream,'sixgr.truth.CoupledWaveformStream'),id, ...
    'The NR access profile requires original shared receiver/time owners.');
owner=state.SharedWaveformStream;
if ~isfield(state,'NRRRCSetupAttemptsByUE'),state.NRRRCSetupAttemptsByUE=cell(state.NumUsers,1);end
if ~isfield(state,'NRRRCAttemptCounterByUE'),state.NRRRCAttemptCounterByUE=zeros(state.NumUsers,1);end
attempt=state.NRRRCSetupAttemptsByUE{ue};
if isempty(attempt)
    assert(isfield(state,'DecodedSIB1RecoveryByUE') && numel(state.DecodedSIB1RecoveryByUE)>=ue && ...
        isfield(state,'UECommonCellConfigurationByUE')&&numel(state.UECommonCellConfigurationByUE)>=ue, ...
        id,'Essential SI must be received before initial RRC establishment.');
    state.NRRRCAttemptCounterByUE(ue)=state.NRRRCAttemptCounterByUE(ue)+1;
    counter=state.NRRRCAttemptCounterByUE(ue);
    key="cell_"+state.CurrentServingIdx(ue)+"_ue_"+ue;
    seed=sixgr.lls.deterministicSeed(cfg.run.seed,key,counter,1,"RRC_RANDOM_IDENTITY");
    stream=RandStream('mt19937ar','Seed',seed);
    context=struct('RunID',string(cfg.run.runTag),'UEIndex',ue, ...
        'ServingCell',state.CurrentServingIdx(ue),'ConfigurationEpoch',owner.Physical.ConfigurationEpoch, ...
        'SampleRateHz',owner.SampleRateHz,'StartSample',owner.Events.NextSampleIndex);
    attempt=sixgr.mac.ra.NRRRCSetupAttemptState(policy,state.UECommonCellConfigurationByUE{ue}, ...
        state.DecodedSIB1RecoveryByUE{ue},context,stream);
    owner.armRRCSetupTimer(ue,attempt);
elseif attempt.Status~="waiting_setup"
    error(id,'A completed/expired RRC attempt requires an explicit upper-layer restart; do not silently start another one.');
end
assert(attempt.Context.ServingCell==state.CurrentServingIdx(ue)&& ...
    attempt.Context.ConfigurationEpoch==owner.Physical.ConfigurationEpoch&& ...
    owner.Events.NextSampleIndex<attempt.ExpirySampleExclusive,id, ...
    'MAC retry cannot retarget or outlive its original RRC attempt.');
state.NRRRCSetupAttemptsByUE{ue}=attempt;
cfg.NRInitialAccessRequest=struct('Context',attempt.Context,'Request',attempt.Request, ...
    'T300ExpirySample',attempt.ExpirySampleExclusive);
end
