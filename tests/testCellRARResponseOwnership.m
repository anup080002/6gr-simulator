function ok=testCellRARResponseOwnership()
% Actual alternate-preamble reception through the core continuation API.
% This bounded unit-channel test is not an integrated two-UE attach run.
setup6GRSimToolkit('Verbose',false);
cfg=raStrictAnchorConfig(); cfg.phy.duplex.mode='TDD';
cfg.lls6g.userContext.RuntimeServingCell=2;
cfg.random_access.temporary_crnti_pool=[6200 6205];
[prepared,checkpoint]=sixgr.phy.ra.runFourStepRA(cfg,'WriteArtifacts',false, ...
    'RuntimeIntegrationMode','provided_observation_unit_channel_test', ...
    'RequireRuntimeStageWaveforms',true,'UseRuntimeChannel',false, ...
    'AllowRuntimeStageWaveformComposition',false,'StageAction','prepare_next_stage');
observed=mod(checkpoint.RAConfig.PreambleIndex+1,64);
alternate=sixgr.rach.generatePRACHWaveform(checkpoint.Msg1Tx.PRACHRuntimeConfig, ...
    'Occasion',checkpoint.PreparedContext.Occasion,'PreambleIndex',observed);
t=prepared.PreparedTransmission; first=round(t.StartTime_s*t.SampleRate_Hz);
b=sixgr.phy.waveform.WaveformObservationBuffer(first,first+size(alternate.Waveform,1), ...
    t.SampleRate_Hz,size(alternate.Waveform,2));
b.append(sixgr.phy.waveform.WaveformChunk(alternate.Waveform,first),t.SampleRate_Hz);
[received,checkpoint]=sixgr.phy.ra.runFourStepRA(cfg,'Continuation',checkpoint, ...
    'RuntimeStageWaveforms',struct('Msg1RxWaveform',b),'StopAfterStage','Msg1');
assert(received.PreambleDetected && received.PreambleIndexDetected==observed);
assert(checkpoint.RAConfig.NCellID==17 && checkpoint.RAConfig.ServingCell==2);
state=struct('RadioIdentityBindings',struct('ServingCell',2,'RNTI',6200));
[state,firstResponse,frozen]=sixgr.truth.prepareCellRARResponse(state,cfg,checkpoint);
assert(firstResponse.PreparedTransmission.StageName=="Msg2");
assert(frozen.Msg2Tx.RAR.TemporaryCRNTI==6201 && frozen.Msg2Tx.RAR.RAPID==observed);
assert(frozen.RAConfig.TempCRNTI==6201 && checkpoint.RAConfig.TempCRNTI~=6201);
assignment=state.GNBTemporaryCRNTIAllocator.Allocations(1);
localReject(@()sixgr.phy.ra.runFourStepRA(cfg,'Continuation',frozen, ...
    'StageAction','prepare_next_stage','GNBIdentityAssignment',assignment), ...
    'sixgr:phy:ra:MissingRAContinuationOutput');
localReject(@()localChangeFrozen(cfg,frozen,assignment),'sixgr:phy:ra:FrozenRARIdentity');
[state,duplicate,waiting]=sixgr.truth.prepareCellRARResponse(state,cfg,checkpoint);
assert(isempty(fieldnames(duplicate.PreparedTransmission)) && ...
    waiting.Result.GNBResponseOwnedByCell && isscalar(state.GNBTemporaryCRNTIAllocator.Allocations), ...
    'Repeated completion must not create a second physical RAR producer.');
% The duplicate disposition is a gNB decision only; it must not manufacture
% a received RAR, connected identity, or decoded grant for the waiting UE.
assert(waiting.NextStage==2 && isempty(fieldnames(waiting.RARRx)) && ...
    waiting.RAConfig.TempCRNTI==checkpoint.RAConfig.TempCRNTI);
% Declared negative boundary, not a second claimed physical detection.
different=checkpoint; different.Detection.DetectedPreambleIndex=mod(observed+1,64);
localReject(@()sixgr.truth.prepareCellRARResponse(state,cfg,different), ...
    'sixgr:truth:RARMultiResponseMultiplexingRequired');
ok=true; disp('CELL_RAR_RESPONSE_OWNERSHIP_PASS: received RAPID, allocated coded RAR, single producer, independent UE state.');
end
function localChangeFrozen(cfg,cp,assignment)
[~,~]=sixgr.phy.ra.runFourStepRA(cfg,'Continuation',cp, ...
    'StageAction','prepare_next_stage','GNBIdentityAssignment',assignment);
end
function localReject(f,id)
try, f(); catch e, assert(string(e.identifier)==id,e.message); return; end
error('test:MissingExpectedRejection','Expected %s.',id);
end
