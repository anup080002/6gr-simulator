function ok=testSlotCheckpointConfigPreflight()
% Storage/control fixture; no physical result or scientific migration.
setup6GRSimToolkit('Verbose',false);
root=tempname; mkdir(root);
scenario=struct('run_control',struct('runtime_checkpoint_keep',2),'seed',17);
scenario.values=struct('complex',complex(1,2),'logical',true,'typed',uint32(42), ...
    'empty',zeros(0,3),'column',[1;2],'text',"exact-type mirror");
source=sixgr.runtime.SlotCheckpoint.sourceIdentity();
payload=struct('RuntimeState',struct('CurrentSlot',1, ...
    'LoadProbe',MatSaveLoadProbe(1:12)),'CompletedSlot',1,'RNG',rng);
path=sixgr.runtime.SlotCheckpoint.write(root,payload,scenario,source);
MatSaveLoadProbe.loadCount("reset");
preflight=sixgr.runtime.SlotCheckpoint.preflightScenario(path,scenario);
assert(preflight.Available && ~preflight.NativeStateLoaded && ...
    MatSaveLoadProbe.loadCount("read")==0);
changed=scenario; changed.seed=18;
reject(@()sixgr.runtime.SlotCheckpoint.read(path,changed,""), ...
    'sixgr:checkpoint:ScenarioChanged');
assert(MatSaveLoadProbe.loadCount("read")==0, ...
    'Configuration mismatch must reject without loading native runtime objects.');
[saved,receipt]=sixgr.runtime.SlotCheckpoint.read(path,scenario,"");
assert(MatSaveLoadProbe.loadCount("read")==1 && ...
    isequaln(saved.Scenario,sixgr.runtime.SlotCheckpoint.scientificScenario(scenario)) && ...
    isequaln(saved.FullScenario,scenario) && receipt.ScenarioPreflight.Available, ...
    'test:CheckpointPreflightRoundTrip', ...
    'The native state must load once and retain both scientific and full configuration.');
% A changed mirror with a newly declared checksum must still disagree
% with the actual saved payload. The preflight is never an authorization.
receiptPath=fullfile(fileparts(path),'checkpoint.json');
record=jsondecode(fileread(receiptPath));
mirror=fullfile(fileparts(path),'scientific_scenario.mat');
sixgr.util.matSave(mirror,struct('ScientificScenario', ...
    sixgr.runtime.SlotCheckpoint.scientificScenario(changed)),'UseArtifactStore',false);
record.ScientificScenarioSHA256=sixgr.util.sha256File(mirror);
sixgr.util.jsonWrite(receiptPath,record);
reject(@()sixgr.runtime.SlotCheckpoint.read(path,changed,""), ...
    'sixgr:checkpoint:ScenarioChanged');
assert(MatSaveLoadProbe.loadCount("read")==2, ...
    'A matching mirror must not bypass the native scientific-state guard.');
record.ScientificScenarioSHA256=repmat('0',1,64);
sixgr.util.jsonWrite(receiptPath,record);
reject(@()sixgr.runtime.SlotCheckpoint.read(path,changed,""), ...
    'sixgr:checkpoint:ScenarioPreflightIntegrity');
record.ScientificScenarioFile='../state.mat';
sixgr.util.jsonWrite(receiptPath,record);
reject(@()sixgr.runtime.SlotCheckpoint.preflightScenario(path,changed), ...
    'sixgr:checkpoint:ScenarioPreflightIntegrity');
assert(MatSaveLoadProbe.loadCount("read")==2);
% Legacy receipts have no mirror; existing full-state validation remains.
record=rmfield(record,{'ScientificScenarioFile','ScientificScenarioSHA256'});
sixgr.util.jsonWrite(receiptPath,record);
[~,receipt]=sixgr.runtime.SlotCheckpoint.read(path,scenario,"");
assert(~receipt.ScenarioPreflight.Available && MatSaveLoadProbe.loadCount("read")==3);
ok=true;
end

function reject(call,identifier)
caught=false;
try
    call();
catch cause
    assert(strcmp(cause.identifier,identifier),'test:CheckpointWrongFailure', ...
        'Expected %s; got %s: %s',identifier,cause.identifier,cause.message);
    caught=true;
end
assert(caught,'test:CheckpointMissingGuard','Expected %s.',identifier);
end
