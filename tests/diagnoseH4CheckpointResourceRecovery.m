function receipt=diagnoseH4CheckpointResourceRecovery(checkpointFolder,outputFolder)
% Recover actual retained occupancy; do not restore/run the physical runtime.
arguments
    checkpointFolder (1,1) string
    outputFolder (1,1) string
end
setup6GRSimToolkit('Verbose',false);
assert(~isfolder(outputFolder),'test:DiagnosticFolderExists','Use a new derived-evidence folder.');
record=jsondecode(fileread(fullfile(checkpointFolder,'checkpoint.json')));
assert(string(record.Status)=="complete" && any(record.SchemaVersion==[1 2]));
files=record.Files; paths=replace(string({files.Path}),'\','/');
[configuration,~]=source("meta/scenario_config_resolved.json");
[identityPath,~]=source("meta/scenario_config_identity.json");
identity=jsondecode(fileread(identityPath));
assert(sixgr.util.sha256File(configuration)==string(identity.ResolvedJSONSHA256));
s=jsondecode(fileread(configuration));
cfg=sixgr.lls6g.buildInternalConfig(s,outputFolder);
carrier=nrCarrierConfig('NSizeGrid',cfg.phy.carrier.NSizeGrid, ...
    'SubcarrierSpacing',cfg.phy.carrier.SubcarrierSpacing, ...
    'CyclicPrefix',char(cfg.phy.carrier.CyclicPrefix));
[path,dependency]=source("components/frame_grid/csv/observed_re_allocation.csv");
timer=tic;
[intervals,audit]=sixgr.truth.readObservedOFDMResourceIntervals( ...
    path,string(dependency.SHA256),carrier,32768);
for k=1:height(intervals)
    scope=jsondecode(intervals.PopulationScopeJSON(k));
    assert(isfield(scope,'ConfigHash') && string(scope.ConfigHash)==string(identity.ConfigHash), ...
        'test:RecoveredResourceConfigMismatch','Recovered resources must belong to the saved configuration.');
end
mkdir(outputFolder);
csvPath=fullfile(outputFolder,'recovered_ofdm_resource_intervals.csv');
sixgr.util.csvWriteTable(csvPath,intervals);
receipt=struct('CheckpointFolder',checkpointFolder, ...
    'CompletedSlot',record.CompletedSlotOneBased,'ConfigHash',string(identity.ConfigHash), ...
    'SourceSHA256',sixgr.runtime.SlotCheckpoint.sourceIdentity().SHA256, ...
    'ResourceSourceSHA256',string(dependency.SHA256),'ResourceSourceBytes',dependency.Bytes, ...
    'RecoveredCSV',csvPath,'RecoveredCSVSHA256',sixgr.util.sha256File(csvPath), ...
    'Audit',audit,'Seconds',toc(timer),'PhysicalReplayExecuted',false, ...
    'ReceiverTrialsModified',false,'EndpointEnergyQualified',false,'PrimaryStudyEligible',false);
sixgr.util.jsonWrite(fullfile(outputFolder,'receipt.json'),receipt);
fprintf('CHECKPOINT_RESOURCE_RECOVERY rows=%d intervals=%d seconds=%.3f\n', ...
    audit.SourceRows,audit.IntervalRows,receipt.Seconds);

    function [path,match]=source(relative)
        match=files(paths==relative);
        assert(isscalar(match),'test:MissingCheckpointInput','Missing %s.',relative);
        snapshot=string(match.Snapshot);
        assert(strlength(snapshot)>0,'test:MutableCheckpointInput','Require an immutable saved dependency.');
        if startsWith(snapshot,"@objects/")
            path=sixgr.runtime.CheckpointFileStore.resolve(fileparts(checkpointFolder),snapshot);
        else
            path=fullfile(checkpointFolder,snapshot);
        end
        info=dir(path);
        assert(isscalar(info) && info.bytes==match.Bytes && ...
            sixgr.util.sha256File(path)==string(match.SHA256), ...
            'test:CheckpointInputIntegrity','Changed checkpoint dependency %s.',relative);
    end
end
