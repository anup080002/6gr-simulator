function ok=testContinuousSharedTxIQCapture()
%TESTCONTINUOUSSHAREDTXIQCAPTURE Production shared-clock integration gate.

setup6GRSimToolkit('Verbose',false);
root=string(tempname)+"_shared_continuous_iq";
cleanup=onCleanup(@()localCleanup(root)); %#ok<NASGU>
scenario=sixgr.lls6g.config.loadScenarioConfig(fullfile('simulator','configs', ...
    'scenarios','lls_causal_access_to_data_wiring_tdd_short_continuous_iq.yaml'));
cfg=sixgr.lls6g.buildInternalConfig(scenario,root);
cfg=sixgr.util.structSet(cfg,'run.rootRunFolder',root);
assert(cfg.outputs.continuousRawIQCaptureEnabled);

multiUser=struct('Enabled',true,'NumUsers',1,'RNTIStart',1, ...
    'ExecutionModel','slot_coupled_truth');
state=sixgr.truth.CoupledTruthRuntime.initialize( ...
    cfg,root,multiUser,struct(),1);
state.CurrentSlot=1;
state.CurrentServingIdx(:)=1;
[state,stream]=sixgr.truth.CoupledWaveformStream.initialize( ...
    state,cfg,{cfg});
[dl,~]=sixgr.truth.CoupledTruthRuntime.applyUserContext(cfg,state,1,'DL');
prototype=sixgr.link.runCellSearch_MIB_SIB1(dl,'PrepareOnly',true, ...
    'UseRuntimeChannel',true,'RuntimeSlot',0);
assert(isfield(prototype,'PreparedBroadcast'),'%s',prototype.FailureReason);
context=struct('Config',dl,'Slot',1,'Frame',1,'RNTI',1, ...
    'ServingCell',1,'SNR',12);
stream.queueDownlink('PBCH',1,prototype.PreparedBroadcast,context);
[state,~]=stream.advanceSlot(state,cfg); %#ok<ASGLU>
carrier=sixgr.phy.grid.makeCarrier(cfg);
expectedEnd=sixgr.phy.frame.slotStartSample( ...
    carrier,1,stream.SampleRateHz);
capture=stream.finalizeContinuousTxIQCapture(expectedEnd,1);
manifest=capture.ManifestTable;
assert(capture.Ok && height(manifest)==2 && ...
    all(manifest.SampleCountPerPort==expectedEnd) && ...
    all(manifest.ContinuousCoverage) && ...
    all(manifest.CaptureStatus=="PASS"));
gnb=manifest(manifest.EndpointID=="gnb_1",:);
ue=manifest(manifest.EndpointID=="ue_1",:);
assert(height(gnb)==1 && height(ue)==1 && ...
    gnb.ActiveSampleCount>0 && ue.ActiveSampleCount==0, ...
    'The first TDD slot must retain active gNB broadcast IQ and intentional UE silence.');

fprintf(['Continuous shared Tx-IQ: exact post-TX-RF gNB/UE streams sealed ' ...
    'over one complete scheduler slot.\n']);
ok=true;
end

function localCleanup(pathValue)
if isfolder(pathValue)
    rmdir(pathValue,'s');
end
end
