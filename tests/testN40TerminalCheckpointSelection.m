function ok=testN40TerminalCheckpointSelection()
% Authored byte/receipt fixture only; no native state or PHY execution claim.
folder=tempname; root=fullfile(folder,'child'); mkdir(fullfile(root,'meta'));
base=sixgr.runtime.SlotCheckpoint.storageRoot(root);
repo=fileparts(fileparts(mfilename('fullpath')));
sourcePath='+sixgr/+validation/evaluateN40IntegrationGate.m';
source=struct('SHA256','declared_fixture_inventory', ...
    'Files',struct('Path',sourcePath,'SHA256',sixgr.util.sha256File(fullfile(repo,sourcePath))));
prefix=checkpoint(55,'original');
original=checkpoint(60,'original');
resumed=checkpoint(60,'resumed');
point(original,60); verify(true);
point(resumed,60); verify(true);
point(original,55); verify(false);
point(prefix,60); verify(false);
point(fullfile(folder,'foreign','state.mat'),60); verify(false);
point(original,60);
recordPath=fullfile(fileparts(original),'checkpoint.json');
record=jsondecode(fileread(recordPath)); saved=record;
record.RunFolder=fullfile(folder,'other_child'); sixgr.util.jsonWrite(recordPath,record); verify(false);
sixgr.util.jsonWrite(recordPath,saved);
sixgr.util.writeTextFile(original,'changed payload'); verify(false);
fprintf('N40_TERMINAL_CHECKPOINT_SELECTION_PASS prefix=55 terminal=60 duplicate_endpoints=2 physical_execution=0\n');
ok=true;

    function path=checkpoint(slot,label)
        dirPath=fullfile(base,sprintf('after_slot_%06d_%s',slot,label)); mkdir(dirPath);
        path=string(fullfile(dirPath,'state.mat'));
        scientific=fullfile(dirPath,'scientific_scenario.mat');
        sixgr.util.writeTextFile(path,"declared non-native payload "+label+slot);
        sixgr.util.writeTextFile(scientific,'declared non-native config');
        receipt=struct('CompletedSlotOneBased',slot,'NextSlotOneBased',slot+1, ...
            'Status','complete','RunFolder',string(sixgr.util.canonicalPath(root)), ...
            'StateSHA256',sixgr.util.sha256File(path), ...
            'ScientificScenarioFile','scientific_scenario.mat', ...
            'ScientificScenarioSHA256',sixgr.util.sha256File(scientific),'Source',source);
        sixgr.util.jsonWrite(fullfile(dirPath,'checkpoint.json'),receipt);
    end
    function point(path,slot)
        sixgr.util.jsonWrite(fullfile(root,'meta','latest_slot_checkpoint.json'), ...
            struct('Checkpoint',path,'CompletedSlotOneBased',slot,'NextSlotOneBased',slot+1));
    end
    function verify(expected)
        out=sixgr.validation.evaluateN40IntegrationGate(root,'RequireContinuation',false);
        hit=out.Checks.CheckID=="checkpoint60";
        assert(nnz(hit)==1 && out.Checks.Passed(hit)==expected,'%s',out.Checks.Detail(hit));
        assert(~out.Ok && ~out.FinalAccepted,'Receipt fixture is not full-run acceptance.');
    end
end
