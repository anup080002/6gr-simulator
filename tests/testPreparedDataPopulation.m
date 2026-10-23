function ok=testPreparedDataPopulation()
% Original configuration/clock provenance only. No waveform or decode claim.
setup6GRSimToolkit('Verbose',false,'RunToolboxChecks',false);
s=sixgr.lls6g.config.loadScenarioConfig(fullfile('simulator','configs', ...
    'scenarios','lls_pdcch_shared_queue_fixture.yaml'));
cfg=sixgr.lls6g.buildInternalConfig(s,tempname);
multi=struct('Enabled',true,'NumUsers',1,'RNTIStart',1,'ExecutionModel','slot_coupled_truth');
state=sixgr.truth.CoupledTruthRuntime.initialize(cfg,tempname,multi,struct(),20);
state.CurrentSlot=1; state.CurrentCanonicalSlot=1; state.CurrentFrame=1;
state.CurrentServingIdx(:)=1; state.CurrentSweepPointIndex=3;
[state,owner]=sixgr.truth.CoupledWaveformStream.initialize(state,cfg,{cfg});
state.CfgMobility.run.seed=127; state.CfgMobility.channel.seed=256;
cfg.run.seed=1127; cfg.channel.seed=1256;
cfg.run.runTag='declared_population_unit'; cfg.run.executionID='declared_execution_unit';
cfg.run.scenarioID='declared_component'; cfg.meta.configHash=repmat('a',1,64);
% This frozen-identity shell is a metadata boundary fixture, not a real grant.
grant=struct('UEIndex',1,'Direction',"DL",'PHYGrant', ...
    struct('IsFrozen',true,'Direction',"DL",'ChannelStateKey',struct('UEIndex',1), ...
    'GrantContextId',"declared_metadata_boundary"));
before=owner.Events.NextSampleIndex;
bound=sixgr.truth.bindPreparedDataPopulation(cfg,state,grant,1,'DL',-10);
p=bound.lls6g.runtime.PreparedDataPopulation;
assert(p.Version=="prepared_data_population/v1" && p.SourceRandomSeed==127 && ...
    p.PreparedRandomSeed==1127 && p.SourceChannelSeed==256 && p.PreparedChannelSeed==1256 && ...
    p.SweepPointIndex==3 && p.ConfiguredSNR_dB==-10 && p.CapturedAtSample==before && ...
    p.ReceiverClockEpoch==owner.Physical.ConfigurationEpoch && ...
    p.GrantContextID==grant.PHYGrant.GrantContextId && owner.Events.NextSampleIndex==before);
token=jsonencode(sixgr.util.jsonSafeValue(p));
assert(bound.lls6g.runtime.PreparedDataPopulationSHA256== ...
    string(sixgr.util.sha256Hex(uint8(unicode2native(token,'UTF-8')))));
assert(isequaln(bound,sixgr.truth.bindPreparedDataPopulation(bound,state,grant,1,'DL',-10)));
state.CurrentSweepPointIndex=4;
localReject(@()sixgr.truth.bindPreparedDataPopulation(bound,state,grant,1,'DL',0), ...
    'sixgr:truth:PreparedPopulationConflict');
next=sixgr.truth.bindPreparedDataPopulation(cfg,state,grant,1,'DL',0);
assert(next.lls6g.runtime.PreparedDataPopulation.SweepPointIndex==4 && ...
    next.lls6g.runtime.PreparedDataPopulation.ConfiguredSNR_dB==0 && ...
    next.lls6g.runtime.PreparedDataPopulationSHA256~=bound.lls6g.runtime.PreparedDataPopulationSHA256);
missing=rmfield(state,'CfgMobility');
unknown=sixgr.truth.bindPreparedDataPopulation(cfg,missing,grant,1,'DL',-10);
assert(isnan(unknown.lls6g.runtime.PreparedDataPopulation.SourceRandomSeed) && ...
    isnan(unknown.lls6g.runtime.PreparedDataPopulation.SourceChannelSeed), ...
    'Do not substitute prepared UE seeds for absent original source seeds.');
localReject(@()sixgr.truth.bindPreparedDataPopulation(cfg,struct(),grant,1,'DL',0), ...
    'sixgr:truth:PreparedPopulationOwnerRequired');
localReject(@()sixgr.truth.bindPreparedDataPopulation(cfg,state,grant,2,'DL',0), ...
    'sixgr:truth:PreparedPopulationGrantMismatch');
localReject(@()sixgr.truth.bindPreparedDataPopulation(cfg,state,grant,1,'UL',0), ...
    'sixgr:truth:PreparedPopulationGrantMismatch');
bad=grant; bad.PHYGrant.ChannelStateKey.UEIndex=2;
localReject(@()sixgr.truth.bindPreparedDataPopulation(cfg,state,bad,1,'DL',0), ...
    'sixgr:truth:PreparedPopulationGrantMismatch');
bad=grant; bad.PHYGrant.Direction="UL";
localReject(@()sixgr.truth.bindPreparedDataPopulation(cfg,state,bad,1,'DL',0), ...
    'sixgr:truth:PreparedPopulationGrantMismatch');
% Logical scheduler and frozen PHY identities intentionally have distinct
% domains. Retain the former verbatim; reject a false alias of the latter.
logicalGrant=grant; logicalGrant.GrantContextId="declared_logical_scheduler_context";
logicalBound=sixgr.truth.bindPreparedDataPopulation(cfg,state,logicalGrant,1,'DL',0);
assert(logicalBound.lls6g.runtime.PreparedDataPopulation.LogicalGrantContextID== ...
    logicalGrant.GrantContextId && logicalBound.lls6g.runtime.PreparedDataPopulation.GrantContextID== ...
    grant.PHYGrant.GrantContextId);
changedLogical=logicalGrant; changedLogical.GrantContextId="another_logical_context";
localReject(@()sixgr.truth.bindPreparedDataPopulation(logicalBound,state,changedLogical,1,'DL',0), ...
    'sixgr:truth:PreparedPopulationConflict');
bad=grant; bad.GrantContextId=["ambiguous","logical_context"];
localReject(@()sixgr.truth.bindPreparedDataPopulation(cfg,state,bad,1,'DL',0), ...
    'sixgr:truth:PreparedPopulationGrantMismatch');
for name="PHYGrantContextId"
    bad=grant; bad.(name)="other_grant";
    localReject(@()sixgr.truth.bindPreparedDataPopulation(cfg,state,bad,1,'DL',0), ...
        'sixgr:truth:PreparedPopulationGrantMismatch');
end
bad=cfg; bad.lls6g.runtime.PreparedDataPopulationSHA256="unpaired_hash";
localReject(@()sixgr.truth.bindPreparedDataPopulation(bad,state,grant,1,'DL',0), ...
    'sixgr:truth:PreparedPopulationConflict');
grant.PHYGrant.IsFrozen=false;
localReject(@()sixgr.truth.bindPreparedDataPopulation(cfg,state,grant,1,'DL',0), ...
    'sixgr:truth:PreparedPopulationGrantRequired');
fprintf('PREPARED_DATA_POPULATION_PASS metadata_only=1 waveform_executed=0\n');
ok=true;
end

function localReject(fn,id)
try, fn(); catch err, assert(strcmp(err.identifier,id),'Expected %s, got %s',id,err.identifier); return; end
error('test:ExpectedRejection','Expected %s.',id);
end
