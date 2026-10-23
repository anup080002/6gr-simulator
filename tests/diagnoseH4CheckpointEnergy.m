function report=diagnoseH4CheckpointEnergy(checkpointFolder,outputFolder,recoveryReceipt)
% Re-export only the committed small-table prefix into a fresh diagnostic
% folder. Do not load the native runtime, rewrite the run, or invent missing
% historical signal resource/power evidence.
arguments
    checkpointFolder (1,1) string
    outputFolder (1,1) string
    recoveryReceipt (1,1) string=""
end
setup6GRSimToolkit('Verbose',false);
assert(~isfolder(outputFolder),'test:DiagnosticFolderExists');
record=jsondecode(fileread(fullfile(checkpointFolder,'checkpoint.json')));
assert(record.Status=="complete" && any(record.SchemaVersion==[1 2]));
files=record.Files;
paths=replace(string({files.Path}),'\','/');
configuration=source("meta/scenario_config_resolved.json");
identity=jsondecode(fileread(source("meta/scenario_config_identity.json")));
assert(sixgr.util.sha256File(configuration)==string(identity.ResolvedJSONSHA256));
s=jsondecode(fileread(configuration));
cfg=sixgr.lls6g.buildInternalConfig(s,outputFolder);
domains=["DL","UL","PBCH","PRACH","PDCCH","PUCCH","SRS","CSIRS","TRS"];
names=["dl_pdsch","ul_pusch","pbch","prach","pdcch","pucch","srs","csi_rs","trs"];
raw=struct();
inputs=table('Size',[0 4],'VariableTypes',{'string','string','double','string'}, ...
    'VariableNames',{'Domain','CheckpointPath','Rows','SHA256'});
for k=1:numel(domains)
    relative="air_interface/csv/"+names(k)+"_trials.csv";
    if ~any(paths==relative), continue; end
    path=source(relative);
    info=dir(path);
    if info.bytes<3, T=table();
    else, T=sixgr.util.csvReadTable(path,'TextType','string'); end
    if ismember("UniqueDeliveredTBBits",string(T.Properties.VariableNames)) && ~isempty(T)
        % The committed snapshot is the authority for this diagnostic
        % migration. Preserve old files/credit; bind the corrected key only
        % in the separately versioned derived model, just as publication.
        [~,logicalRun]=fileparts(record.RunFolder);
        executions=unique(string(T.ExecutionID));
        assert(isscalar(executions)&&~ismissing(executions)&&strlength(executions)>0);
        T=sixgr.kpi.bindTransportGoodputPublicationScope(T, ...
            struct('RunID',string(logicalRun),'ExecutionID',executions, ...
            'ConfigHash',string(identity.ConfigHash)));
    end
    raw.(domains(k))=T;
    inputRecord=files(paths==relative);
    inputs(end+1,:)={domains(k),relative,height(T),string(inputRecord.SHA256)}; %#ok<AGROW>
end
relative="control/csv/ra_runtime_stage_waveforms.csv";
if any(paths==relative)
    raw.RAEvidenceTables.ra_runtime_stage_waveforms=sixgr.util.csvReadTable(source(relative),'TextType','string');
    entry=files(paths==relative);
    inputs(end+1,:)={"RA_stage_waveforms",relative,height(raw.RAEvidenceTables.ra_runtime_stage_waveforms),string(entry.SHA256)};
end
mkdir(fullfile(outputFolder,'air_interface'));
raw.CoupledRuntime=struct('CompletedCanonicalSlots',record.CompletedSlotOneBased);
evidence=[];
if strlength(recoveryReceipt)>0
    recovered=jsondecode(fileread(recoveryReceipt));
    assert(replace(string(recovered.CheckpointFolder),'\','/')==replace(checkpointFolder,'\','/') && ...
        string(recovered.ConfigHash)==string(identity.ConfigHash), ...
        'test:ResourceRecoveryScope','Resource recovery belongs to another checkpoint.');
    retained=source("components/frame_grid/csv/observed_re_allocation.csv");
    assert(sixgr.util.sha256File(retained)==string(recovered.ResourceSourceSHA256) && ...
        sixgr.util.sha256File(recovered.RecoveredCSV)==string(recovered.RecoveredCSVSHA256), ...
        'test:ResourceRecoveryIntegrity','Recovered or original resource evidence changed.');
    evidence=struct('Intervals',sixgr.util.csvReadTable(recovered.RecoveredCSV,'TextType','string'), ...
        'ConfigHash',string(identity.ConfigHash),'SourceSHA256',string(recovered.ResourceSourceSHA256));
    nativePath="components/frame_grid/csv/observed_prach_native_allocation.csv";
    if any(paths==nativePath)
        nativeFile=source(nativePath);
        evidence.NativePRACH=sixgr.util.csvReadTable(nativeFile,'TextType','string');
        entry=files(paths==nativePath); evidence.NativeSourceSHA256=string(entry.SHA256);
    end
end
result=sixgr.truth.exportLLSEnergyDiagnostics(cfg, ...
    fullfile(outputFolder,'air_interface'),raw,evidence);
report=struct('CheckpointFolder',checkpointFolder, ...
    'CompletedSlot',record.CompletedSlotOneBased, ...
    'SourceSHA256',sixgr.runtime.SlotCheckpoint.sourceIdentity().SHA256, ...
    'ModelAvailable',result.ModelAvailable, ...
    'EndpointTotalsAvailable',result.EndpointTotalsAvailable, ...
    'FailureReason',result.FailureReason,'PrimaryStudyEligible',false, ...
    'Scope',"separately_versioned_energy_model_audit_of_hash_verified_checkpoint_tables_not_hardware_power");
if ~isempty(evidence)
    report.ResourceRecoveryReceipt=recoveryReceipt;
    report.BoundReceiverRows=sum(result.ResourceBindingTable.BoundIntervalCount>0);
    report.UnboundOFDMIntervalCount=height(result.UnboundResourceTable);
    report.BoundCommonSignalObservations=height(result.CommonResourceBindingTable);
    report.BoundCommonOFDMIntervals=sum(result.CommonResourceBindingTable.BoundIntervalCount);
    report.ResourceCoverageComplete=result.ResourceCoverageComplete;
    report.CompleteRunEnergyAvailable=result.CompleteRunEnergyAvailable;
    if isfield(result,'NativeResourceBindingTable')
        report.BoundNativePRACHRows=sum(result.NativeResourceBindingTable.NativeRows>0);
    end
end
sixgr.util.csvWriteTable(fullfile(outputFolder,'input_hashes.csv'),inputs);
sixgr.util.jsonWrite(fullfile(outputFolder,'receipt.json'),report);
fprintf('CHECKPOINT_ENERGY_AUDIT completed_slot=%d model_available=%d endpoint_totals_available=%d\n', ...
    report.CompletedSlot,report.ModelAvailable,report.EndpointTotalsAvailable);

    function path=source(relative)
        match=files(paths==relative);
        assert(isscalar(match),'test:MissingCheckpointInput','Missing %s.',relative);
        snapshot=string(match.Snapshot);
        assert(strlength(snapshot)>0,'test:MutableCheckpointInput', ...
            'This diagnostic only reads immutable small-table snapshots.');
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
