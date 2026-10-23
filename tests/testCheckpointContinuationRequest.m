function ok=testCheckpointContinuationRequest()
% Metadata/storage fixtures, not measured PHY or qualification evidence.
setup6GRSimToolkit('Verbose',false);
root=fullfile(pwd,'logs','lls_repairs',"saved_configuration_"+string(java.util.UUID.randomUUID));
mkdir(root); mkdir(fullfile(root,'meta'));
scenario=struct('run_control',struct('runtime_checkpoint_keep',3,'total_slots',100), ...
    'meta',struct('scenario_id','saved_request_fixture'), ...
    'scenario',struct('runner_profile','waveform_bundle'), ...
    'output',struct('backend','filesystem'),'seed',57,'NativeString',"keep_native_type");
scenario.users.execution_model='slot_coupled_truth';
% Deliberately lacks modern defaults and has an old reporting-policy pair.
% Restoring a native checkpoint must not normalize it into new science.
scenario.energy_efficiency.sleep_state_model='micro_sleep';
scenario.energy_and_complexity.sleep_state_model='none';
configHash=string(repmat('a',1,64));
jsonPath=fullfile(root,'meta','scenario_config_resolved.json');
sixgr.util.jsonWrite(jsonPath,scenario);
identity=struct('SchemaVersion','sixgr_resolved_config_identity/v1', ...
    'ScenarioID',scenario.meta.scenario_id,'ConfigHash',configHash, ...
    'ResolvedJSONSHA256',sixgr.util.sha256File(jsonPath));
sixgr.util.jsonWrite(fullfile(root,'meta','scenario_config_identity.json'),identity);
probe=MatSaveLoadProbe(complex(1:16,16:-1:1));
payload=struct('RuntimeState',struct('CurrentSlot',1,'Probe',probe,'Alias',probe), ...
    'CompletedSlot',1,'RNG',rng,'ConfigHash',configHash, ...
    'FramesPerPoint',100,'FrameLocal',1,'SweepIndex',1,'SNRGrid',40);
path=sixgr.runtime.SlotCheckpoint.write(root,payload,scenario,sixgr.runtime.SlotCheckpoint.sourceIdentity());
receiptPath=fullfile(fileparts(path),'checkpoint.json');
receipt=sixgr.util.jsonRead(receiptPath);
requestPath=fullfile(fileparts(path),'request.yaml');
raw.checkpoint_continuation=struct('contract','sixgr_checkpoint_continuation/v1', ...
    'checkpoint',char(path),'state_sha256',receipt.StateSHA256,'config_hash',configHash, ...
    'repair_reason','explicit same-source continuation fixture, not a study result');
raw.checkpoint_continuation.finish_after_slot=60;
raw.checkpoint_continuation.operational_settings=struct( ...
    'run_control',struct('runtime_checkpoint_enable',true,'checkpoint_every_slots',3,'checkpoint_first_slot',49), ...
    'output',struct('live_csv_png_interval_slots',5));
sixgr.util.jsonWrite(requestPath,raw);
MatSaveLoadProbe.loadCount("reset");
beforeRNG=rng;
r=sixgr.runtime.CheckpointContinuationRequest.fromFile(requestPath);
preview=r.preview();
assert(MatSaveLoadProbe.loadCount("get")==0&&preview.ConfigHash==configHash);
assert(preview.Kind=="checkpoint_continuation");
assert(preview.get('seed')==57 && preview.get('run_control.checkpoint_every_slots')==3);
assert(preview.get('run_control.total_slots')==100 && ...
    r.ExecutionHorizon.FinishAfterSlot==60 && r.ExecutionHorizon.ResumedAfterSlot==1);
assert(isequaln(beforeRNG,rng));
% Mutable run outputs are not configuration authority.
sixgr.util.writeTextFile(jsonPath,'changed after checkpoint, not configuration input');
r.verifiedMetadata();
[restoredRoot,lineage,lease]=sixgr.runtime.SlotCheckpoint.prepareResume(path,r,r.RepairReason);
assert(MatSaveLoadProbe.loadCount("get")==1&&isequaln(beforeRNG,rng));
assert(isequaln(lineage.CanonicalScenario,scenario)&&lineage.CanonicalConfigHash==configHash);
assert(lineage.ExecutionHorizon.FinishAfterSlot==60 && ...
    lineage.ExecutionHorizon.OriginalConfigHash==configHash);
assert(~lineage.PrimaryStudyEligible && ...
    lineage.ConfigurationSource=="immutable_checkpoint_native_scenario_no_current_defaults_or_inheritance");
nativeRequested=r.applyOperational(lineage.CanonicalScenario);
[restored,~]=lease.take(path,nativeRequested,r.RepairReason);
assert(MatSaveLoadProbe.loadCount("get")==1 && ...
    restored.RuntimeState.Probe==restored.RuntimeState.Alias && ...
    isequaln(restored.RuntimeState.Probe.Samples,probe.Samples) && ...
    isstring(restored.FullScenario.NativeString));
assert(strcmp(restoredRoot,root)&&isfolder(lineage.PreservedFailedAttempt));
assert(contains(fileread(fullfile(lineage.PreservedFailedAttempt,'meta','scenario_config_resolved.json')),'changed after checkpoint'));
assert(string(sixgr.util.sha256File(jsonPath))==string(identity.ResolvedJSONSHA256));

bad=raw; bad.seed=58;
rejectRaw(bad,requestPath,'sixgr:checkpoint:RequestScienceOverride');
bad=raw; bad.checkpoint_continuation.operational_settings.run_control.total_slots=100;
rejectRaw(bad,requestPath,'sixgr:checkpoint:InvalidOperationalSettings');
bad=raw; bad.checkpoint_continuation.operational_settings.output.save_channel=false;
rejectRaw(bad,requestPath,'sixgr:checkpoint:InvalidOperationalSettings');
bad=raw; bad.checkpoint_continuation.state_sha256=repmat('0',1,64);
rejectRaw(bad,requestPath,'sixgr:checkpoint:SavedIdentityMismatch');
bad=raw; bad.checkpoint_continuation.config_hash=repmat('0',1,64);
rejectRaw(bad,requestPath,'sixgr:checkpoint:SavedIdentityMismatch');
bad=raw; bad.checkpoint_continuation.repair_reason='';
rejectRaw(bad,requestPath,'sixgr:checkpoint:InvalidContinuationRequest');
bad=raw; bad.checkpoint_continuation.finish_after_slot=1;
rejectRaw(bad,requestPath,'sixgr:checkpoint:InvalidExecutionHorizon');
bad=raw; bad.checkpoint_continuation.finish_after_slot=101;
rejectRaw(bad,requestPath,'sixgr:checkpoint:InvalidExecutionHorizon');
sixgr.util.jsonWrite(requestPath,raw);
r=sixgr.runtime.CheckpointContinuationRequest.fromFile(requestPath);
requestText=fileread(requestPath);
sixgr.util.writeTextFile(requestPath,string(requestText)+newline);
reject(@()r.preview(),'sixgr:checkpoint:ContinuationRequestChanged');
sixgr.util.writeTextFile(requestPath,requestText);

% Corrupt immutable metadata: reject without native reconstruction.
[~,meta]=r.verifiedMetadata(); metadataText=fileread(meta.ResolvedSource);
sixgr.util.writeTextFile(meta.ResolvedSource,'corrupt immutable metadata fixture');
loads=MatSaveLoadProbe.loadCount("get");
reject(@()r.preview(),'sixgr:checkpoint:SavedMetadataIntegrity');
assert(MatSaveLoadProbe.loadCount("get")==loads);
sixgr.util.writeTextFile(meta.ResolvedSource,metadataText);

mirror=fullfile(fileparts(path),'scientific_scenario.mat');
mirrorBackup=fullfile(fileparts(path),'mirror_backup_fixture.mat'); copyfile(mirror,mirrorBackup);
fid=fopen(mirror,'a'); assert(fid>=0); fwrite(fid,uint8(13),'uint8'); fclose(fid);
reject(@()sixgr.runtime.SlotCheckpoint.readSavedContinuation(r),'sixgr:checkpoint:ScenarioPreflightIntegrity');
copyfile(mirrorBackup,mirror,'f');

% Front-door guards reject combined modes and environmental changes before
% native state loading or run-folder restoration.
loads=MatSaveLoadProbe.loadCount("get");
reject(@()sixgr.lls6g.runners.runSingle(requestPath,root,'not_executed', ...
    struct('ResumeCompletedRuntimeFinalization',true)),'sixgr:checkpoint:InvalidContinuationRequest');
previous=getenv('SIXGR_OUTPUT_BACKEND_OVERRIDE');
envCleanup=onCleanup(@()setenv('SIXGR_OUTPUT_BACKEND_OVERRIDE',previous)); %#ok<NASGU>
setenv('SIXGR_OUTPUT_BACKEND_OVERRIDE','mysql_web');
reject(@()sixgr.lls6g.runners.runSingle(requestPath,root,'not_executed'), ...
    'sixgr:checkpoint:RequestScienceOverride');
setenv('SIXGR_OUTPUT_BACKEND_OVERRIDE',previous);
assert(MatSaveLoadProbe.loadCount("get")==loads);

% Even a rewritten state and updated state hash cannot change science
% relative to the still-pinned saved JSON/config identity.
originalState=fullfile(fileparts(path),'original_state_fixture.mat'); copyfile(path,originalState);
mutated=restored;
mutated.FullScenario.seed=58; mutated.Scenario.seed=58;
sixgr.util.matSave(path,struct('payload',mutated),'UseArtifactStore',false,'ForceV73',true);
changedReceipt=receipt; changedReceipt.StateSHA256=sixgr.util.sha256File(path);
sixgr.util.jsonWrite(receiptPath,changedReceipt);
changedRequest=raw; changedRequest.checkpoint_continuation.state_sha256=changedReceipt.StateSHA256;
sixgr.util.jsonWrite(requestPath,changedRequest);
r=sixgr.runtime.CheckpointContinuationRequest.fromFile(requestPath);
reject(@()sixgr.runtime.SlotCheckpoint.readSavedContinuation(r),'sixgr:checkpoint:SavedScenarioMismatch');
copyfile(originalState,path,'f'); sixgr.util.jsonWrite(receiptPath,receipt);
sixgr.util.jsonWrite(requestPath,raw);
% Current-schema normal resumes still reject different science.
changed=scenario; changed.seed=58;
reject(@()sixgr.runtime.SlotCheckpoint.read(path,changed,""),'sixgr:checkpoint:ScenarioChanged');
ok=true; disp('SAVED_CHECKPOINT_REQUEST_PASS');
end

function rejectRaw(raw,path,id)
sixgr.util.jsonWrite(path,raw);
reject(@()sixgr.runtime.CheckpointContinuationRequest.fromFile(path),id);
end
function reject(call,id)
try
    call();
catch cause
    assert(string(cause.identifier)==id,'Expected %s; got %s: %s',id,cause.identifier,cause.message);
    return;
end
error('test:ExpectedFailure','Expected %s.',id);
end
