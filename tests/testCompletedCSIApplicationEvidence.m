function ok=testCompletedCSIApplicationEvidence(varargin)
% Default: negative owner boundaries plus declared matrix arithmetic only;
% never launch a waveform or fabricate a successful receiver/physical owner.
% Positive use after an actual shared application completion:
%   testCompletedCSIApplicationEvidence(state,item,control,res)
% Use the live returned owner and original saved completion operands. For
% the CSI-continuation harness, item is in received_csi_later_pdsch_receiver.mat;
% res is the final out in received_csi_later_application.mat. Do not substitute
% the earlier pre-commit out. No fixture-authored successful receiver is used.
setup6GRSimToolkit('Verbose',false);
call=@sixgr.truth.buildCompletedCSIApplicationEvidence;
localReject(@()call(struct(),struct(),struct(),struct()), ...
    'sixgr:truth:CompletedCSIOwnerRequired');
localReject(@()call(struct('SharedWaveformStream',struct( ...
    'WaveformApplicationVerified',true,'CompletedAtSample',100)),struct(),struct(),struct()), ...
    'sixgr:truth:CompletedCSIOwnerRequired');
localReject(@()sixgr.truth.bindCompletedCSIApplicationEvidence(table(),struct()), ...
    'sixgr:truth:CompletedCSIProjectionInput');
localDeclaredMappingChecks();
if nargin==0
    fprintf('COMPLETED_CSI_APPLICATION_NEGATIVE_BOUNDARIES_PASS declared_mapping_checks=1 positive_waveform_checks_executed=0\n');
    ok=true; return;
end
assert(nargin==4,'test:CompletedCSIActualInputs', ...
    'Supply the original live state, completed item, received control and final result together.');
state=varargin{1}; item=varargin{2}; control=varargin{3}; res=varargin{4};
owner=state.SharedWaveformStream;
clockBefore=owner.Events.NextSampleIndex;
transmissionsBefore=owner.DataTransmissions;
reportsBefore=state.SharedGNBCSIReportTable;
e=call(state,item,control,res);
assert(e.WaveformApplicationVerified && ~e.FrozenApplication.WaveformApplicationVerified && ...
    ~e.FullScenarioQualified && e.AdditionalPHYExecutions==0 && ...
    ~e.ReceivedControl.RawDecoderReplayRetained && ...
    e.ReceivedControl.Source=="retained_receiver_owned_control_record_and_binding_not_decoder_replay" && ...
    e.AppliedMatrices.ReferencePlane=="physical_element_data_grid_before_node_rf" && ...
    ~e.AppliedMatrices.SelectedIsOptimalClaimed && ~e.AppliedMatrices.RadiatedPowerClaimed && ...
    isequal(e.ReceiverOutcome.CRCPass,logical(res.TrialTable.CRCPass)));
assert(e.EvidenceSHA256==localSHA(e.EvidenceJSON) && ...
    e.AdmittedCSISHA256==localSHA(e.AdmittedCSIJSON) && ...
    e.ReceivedControl.AssignmentJSONSHA256==localSHA(e.ReceivedControl.AssignmentJSON));
prepared=item.Context.Prepared;
assert(e.LogicalGrantContextID==string(prepared.RequestBinding.Grant.GrantContextId));
assert(isequaln(e.PreparedConfiguration.PreparedRandomSeed, ...
        double(sixgr.util.structGet(prepared.InputConfig,'run.seed',NaN))) && ...
    isequaln(e.PreparedConfiguration.PreparedChannelSeed, ...
        double(sixgr.util.structGet(prepared.InputConfig,'channel.seed',NaN))) && ...
    isequaln(e.PreparedPopulation.ConfiguredSNR_dB, ...
        double(sixgr.util.structGet(prepared.RequestBinding,'SNR_dB',NaN))), ...
    'Do not relabel the prepared UE seed as the global report seed or discard the retained configured request SNR.');
source=sixgr.util.structGet(prepared.InputConfig,'lls6g.runtime.PreparedDataPopulation',struct());
if ~isempty(fieldnames(source))
    assert(isequaln(e.PreparedSourcePopulation,source) && ...
        e.PreparedSourcePopulationJSON==string(jsonencode(sixgr.util.jsonSafeValue(source))) && ...
        e.PreparedSourcePopulationSHA256==localSHA(e.PreparedSourcePopulationJSON) && ...
        isequaln(e.PreparedPopulation.RandomSeed,double(source.SourceRandomSeed)) && ...
        isequaln(e.PreparedPopulation.ChannelSeed,double(source.SourceChannelSeed)) && ...
        isequaln(e.PreparedPopulation.SweepPointIndex,double(source.SweepPointIndex)), ...
        'Global source and derived prepared seeds must retain their separate original namespaces.');
else
    assert(isnan(e.PreparedPopulation.RandomSeed) && isnan(e.PreparedPopulation.ChannelSeed) && ...
        isnan(e.PreparedPopulation.SweepPointIndex) && ~e.PopulationScopeComplete && ...
        e.PreparedSourcePopulationJSON=="" && e.PreparedSourcePopulationSHA256=="", ...
        'An old preparation cannot borrow source seeds or sweep index from a received report.');
end
decoded=jsondecode(e.EvidenceJSON);
assert(decoded.WaveformApplicationVerified && ~decoded.FrozenApplication.WaveformApplicationVerified && ...
    string(decoded.TransmissionIdentity.TransmissionID)==e.TransmissionIdentity.TransmissionID);
again=call(state,item,control,res);
assert(isequaln(e,again) && owner.Events.NextSampleIndex==clockBefore && ...
    isequaln(owner.DataTransmissions,transmissionsBefore) && ...
    isequaln(state.SharedGNBCSIReportTable,reportsBefore), ...
    'Publication cannot consume another sample, update feedback or mutate an owner receipt.');
bound=sixgr.truth.bindCompletedCSIApplicationEvidence(res.TrialTable,e);
assert(isequaln(bound(:,res.TrialTable.Properties.VariableNames),res.TrialTable) && ...
    bound.CompletedCSIApplicationVerified && ...
    bound.CompletedCSIApplicationLogicalGrantContextID==e.LogicalGrantContextID && ...
    bound.CompletedCSIApplicationEvidenceJSON==e.EvidenceJSON && ...
    bound.CompletedCSIApplicationEvidenceSHA256==e.EvidenceSHA256 && ...
    bound.CompletedCSIApplicationAdmittedCSIJSON==e.AdmittedCSIJSON && ...
    bound.CompletedCSIApplicationPreparedPopulationJSON==e.PreparedSourcePopulationJSON && ...
    bound.CompletedCSIApplicationPreparedPopulationSHA256==e.PreparedSourcePopulationSHA256 && ...
    isequal(bound.CompletedCSIApplicationPopulationScopeComplete,e.PopulationScopeComplete) && ...
    isequaln(sixgr.truth.bindCompletedCSIApplicationEvidence(bound,e),bound));
csvPath=string(tempname)+"_completed_csi_application.csv";
sixgr.util.csvWriteTable(csvPath,bound,'PreserveSchema',true);
persisted=sixgr.util.csvReadTable(csvPath,'TextType','string');
assert(persisted.CompletedCSIApplicationEvidenceJSON==e.EvidenceJSON && ...
    persisted.CompletedCSIApplicationEvidenceSHA256==localSHA(persisted.CompletedCSIApplicationEvidenceJSON) && ...
    persisted.CompletedCSIApplicationAdmittedCSIJSON==e.AdmittedCSIJSON && ...
    persisted.CompletedCSIApplicationAdmittedCSISHA256==localSHA(persisted.CompletedCSIApplicationAdmittedCSIJSON), ...
    'CSV persistence must preserve the exact lossless evidence and admitted-capsule tokens.');
if strlength(e.PreparedSourcePopulationJSON)>0
    assert(persisted.CompletedCSIApplicationPreparedPopulationJSON==e.PreparedSourcePopulationJSON && ...
        persisted.CompletedCSIApplicationPreparedPopulationSHA256==localSHA(e.PreparedSourcePopulationJSON));
end
public=sixgr.truth.buildLLSPublicOutputTables(struct('pdsch_table',persisted), ...
    sixgr.truth.llsOutputContract(),struct('logical_run_id',e.ReceivedReportPopulation.RunID,'run_id',NaN));
published=public.pdsch_runtime_event_table;
for name=string(persisted.Properties.VariableNames)
    if startsWith(name,"CompletedCSIApplication") || ismember(name,[ ...
            "FrozenGrantContextId","GrantContextId","ReceiverObservationSHA256", ...
            "ObservationStartSample","ObservationEndSampleExclusive","ObservationSampleRateHz"])
        assert(ismember(name,string(published.Properties.VariableNames)) && ...
            isequaln(published.(name),persisted.(name)), ...
            'Public PDSCH must preserve the original completion field %s.',name);
    end
end
publicPath=string(tempname)+"_completed_csi_application_public.csv";
sixgr.util.csvWriteTable(publicPath,published,'PreserveSchema',true);
reloaded=sixgr.util.csvReadTable(publicPath,'TextType','string');
assert(reloaded.CompletedCSIApplicationEvidenceJSON==e.EvidenceJSON && ...
    reloaded.CompletedCSIApplicationEvidenceSHA256==localSHA(reloaded.CompletedCSIApplicationEvidenceJSON));
changed=e; changed.EvidenceSHA256="corrupt";
localReject(@()sixgr.truth.bindCompletedCSIApplicationEvidence(res.TrialTable,changed), ...
    'sixgr:truth:CompletedCSIProjectionHash');
changed=e; changed.EvidenceJSON=changed.EvidenceJSON+" "; changed.EvidenceSHA256=localSHA(changed.EvidenceJSON);
localReject(@()sixgr.truth.bindCompletedCSIApplicationEvidence(res.TrialTable,changed), ...
    'sixgr:truth:CompletedCSIProjectionHash');
wrongRow=res.TrialTable; wrongRow.ReceiverObservationSHA256="transplanted";
localReject(@()sixgr.truth.bindCompletedCSIApplicationEvidence(wrongRow,e), ...
    'sixgr:truth:CompletedCSIProjectionRow');
wrongRow=res.TrialTable; wrongRow.GrantContextId="transplanted_logical_grant";
localReject(@()sixgr.truth.bindCompletedCSIApplicationEvidence(wrongRow,e), ...
    'sixgr:truth:CompletedCSIProjectionRow');
wrongRow=bound; wrongRow.CompletedCSIApplicationTransmissionID="transplanted";
localReject(@()sixgr.truth.bindCompletedCSIApplicationEvidence(wrongRow,e), ...
    'sixgr:truth:CompletedCSIProjectionConflict');

% Mutations below are negative/unit branches only. They are never written
% as primary measurements or used to create a received control/capture.
bad=state; bad.SharedDataTXLedger={};
localReject(@()call(bad,item,control,res),'sixgr:truth:CompletedCSITXReceiptRequired');
bad=state;
hit=find(cellfun(@(r)r.Identity.TransmissionID==e.TransmissionIdentity.TransmissionID,bad.SharedDataTXLedger));
bad.SharedDataTXLedger{hit}.Grant.GrantContextId="transplanted_logical_grant";
localReject(@()call(bad,item,control,res),'sixgr:truth:CompletedCSITXBindingMismatch');
bad=state; bad.SharedDataTXLedger{end+1}=bad.SharedDataTXLedger{find(cellfun( ...
    @(r)r.Identity.TransmissionID==e.TransmissionIdentity.TransmissionID,bad.SharedDataTXLedger),1)};
localReject(@()call(bad,item,control,res),'sixgr:truth:CompletedCSITXReceiptRequired');
bad=state; bad.SharedDataRXCommittedIDs=bad.SharedDataRXCommittedIDs( ...
    bad.SharedDataRXCommittedIDs~=e.TransmissionIdentity.TransmissionID);
localReject(@()call(bad,item,control,res),'sixgr:truth:CompletedCSIRXCommitRequired');
bad=state; bad.SharedDataRXCommittedIDs(end+1)=e.TransmissionIdentity.TransmissionID;
localReject(@()call(bad,item,control,res),'sixgr:truth:CompletedCSIRXCommitRequired');
bad=item; bad.Context.TransmissionIdentity.TransmissionID="transplanted";
localReject(@()call(state,bad,control,res),'sixgr:truth:CompletedCSIIdentityMismatch');
bad=item; bad.Context.WaveformToElementMatrix(1)=bad.Context.WaveformToElementMatrix(1)+1;
localReject(@()call(state,bad,control,res),'sixgr:truth:CompletedCSITXBindingMismatch');
bad=item; bad.ID=string(bad.ID)+"_transplanted_window";
localReject(@()call(state,bad,control,res),'sixgr:truth:CompletedCSIEmissionRequired');

tx=find(endsWith(string({item.Planes.ReceiverID}),':tx'));
original=item.Planes(tx).Observation;
bad=item;
bad.Planes(tx).Observation=sixgr.phy.waveform.WaveformObservationBuffer( ...
    original.StartSample,original.EndSampleExclusive,original.SampleRateHz,original.NumReceiveAntennas);
localReject(@()call(state,bad,control,res),'WAVEFORM:IncompleteObservation');
bad=item; bad.Planes(tx).Segments=bad.Planes(tx).Segments(1:end-1);
localReject(@()call(state,bad,control,res),'sixgr:truth:CompletedCSIEmissionRequired');
bad=item;
s=bad.Planes(tx).Segments{1};
s.Execution.ExecutedContributors(1).CommittedThroughSample=s.Execution.ExecutedContributors(1).CommittedThroughSample+1;
bad.Planes(tx).Segments{1}=s;
localReject(@()call(state,bad,control,res),'sixgr:truth:CompletedCSIExecutionMismatch');

bad=state; bad.SharedReceivedGrantControls={};
localReject(@()call(bad,item,control,res),'sixgr:truth:CompletedCSIControlRequired');
wrong=control; wrong.Key=string(wrong.Key)+"_transplanted";
localReject(@()call(state,item,wrong,res),'sixgr:truth:CompletedCSIControlRequired');
bad=state; wrong=control; wrong.ReceivedAssignment.MCS=wrong.ReceivedAssignment.MCS+1;
hit=find(cellfun(@(x)isequaln(x,control),bad.SharedReceivedGrantControls));
bad.SharedReceivedGrantControls{hit}=wrong;
localReject(@()call(bad,item,wrong,res),'sixgr:truth:CompletedCSIControlMismatch');
bad=state;
hit=find(string(bad.SharedGNBCSIReportTable.ReportIdentity)==string(e.AdmittedCSI.ReportIdentity) & ...
    string(bad.SharedGNBCSIReportTable.ObservationID)==string(e.AdmittedCSI.ObservationID));
bad.SharedGNBCSIReportTable.RI(hit)=bad.SharedGNBCSIReportTable.RI(hit)+1;
localReject(@()call(bad,item,control,res),'sixgr:truth:CompletedCSIAdmissionMismatch');
bad=state; bad.SharedGNBCSIReportTable.ExecutionID(hit)="transplanted_execution";
localReject(@()call(bad,item,control,res),'sixgr:truth:CompletedCSIAdmissionMismatch');

bad=res; bad.HARQ.SharedTransmissionID="transplanted";
localReject(@()call(state,item,control,bad),'sixgr:truth:CompletedCSIResultRequired');
bad=res; bad.HARQ.ReceivedAssignmentDigest="transplanted";
localReject(@()call(state,item,control,bad),'sixgr:truth:CompletedCSIResultRequired');
bad=res; bad.TrialTable.FrozenGrantContextId="transplanted";
localReject(@()call(state,item,control,bad),'sixgr:truth:CompletedCSIReceiverOutcome');
bad=res; bad.TrialTable.ReceiverObservationSHA256="transplanted";
localReject(@()call(state,item,control,bad),'sixgr:truth:CompletedCSIRowMismatch');
bad=res; bad.TrialTable=removevars(bad.TrialTable,'ReceiverObservationSHA256');
localReject(@()call(state,item,control,bad),'sixgr:truth:CompletedCSIReceiverOutcome');
bad=res; bad.TrialTable.CRCPass=NaN;
localReject(@()call(state,item,control,bad),'sixgr:truth:CompletedCSIReceiverOutcome');
bad=res; bad.TrialTable.Crash=true;
localReject(@()call(state,item,control,bad),'sixgr:truth:CompletedCSIReceiverOutcome');
bad=res; bad.TrialTable.DLSCHDecodeAttempted=false;
localReject(@()call(state,item,control,bad),'sixgr:truth:CompletedCSIReceiverOutcome');
if ~isempty(fieldnames(source))
    % Only corrupted copies of the real retained preparation are made.
    % They are rejection probes, never replacement physical evidence.
    changedCfg=prepared.InputConfig;
    changedCfg.lls6g.runtime.PreparedDataPopulation.LogicalGrantContextID="transplanted_logical_grant";
    changedCfg=localSealPreparedPopulation(changedCfg);
    bad=localCopyPreparedInput(item,changedCfg);
    localReject(@()call(state,bad,control,res),'sixgr:truth:CompletedCSIPreparedPopulationMismatch');
    changedCfg=prepared.InputConfig;
    changedCfg.lls6g.runtime.PreparedDataPopulation.SweepPointIndex=localDifferentNumber(source.SweepPointIndex);
    bad=localCopyPreparedInput(item,changedCfg);
    localReject(@()call(state,bad,control,res),'sixgr:truth:CompletedCSIPreparedPopulationHash');
    changedCfg=prepared.InputConfig;
    changedCfg.lls6g.runtime.PreparedDataPopulation.PreparedRandomSeed=localDifferentNumber(source.PreparedRandomSeed);
    changedCfg=localSealPreparedPopulation(changedCfg);
    bad=localCopyPreparedInput(item,changedCfg);
    localReject(@()call(state,bad,control,res),'sixgr:truth:CompletedCSIPreparedPopulationMismatch');
    changedCfg=prepared.InputConfig;
    changedCfg.lls6g.runtime.PreparedDataPopulation.GrantContextID=string(source.GrantContextID)+"_transplanted";
    changedCfg=localSealPreparedPopulation(changedCfg);
    bad=localCopyPreparedInput(item,changedCfg);
    localReject(@()call(state,bad,control,res),'sixgr:truth:CompletedCSIPreparedPopulationMismatch');
    changedCfg=prepared.InputConfig;
    changedCfg.lls6g.runtime.PreparedDataPopulation.ConfiguredSNR_dB=source.ConfiguredSNR_dB+1;
    changedCfg=localSealPreparedPopulation(changedCfg);
    bad=localCopyPreparedInput(item,changedCfg);
    localReject(@()call(state,bad,control,res),'sixgr:truth:CompletedCSIPreparedPopulationMismatch');
end
% Branch test only: both measured CRC outcomes preserve identical physical
% application evidence; no mutated outcome is exported or called measured.
failed=res; failed.TrialTable.CRCPass=0;
passed=res; passed.TrialTable.CRCPass=1;
f=call(state,item,control,failed); p=call(state,item,control,passed);
assert(f.WaveformApplicationVerified && p.WaveformApplicationVerified && ...
    ~f.ReceiverOutcome.CRCPass && p.ReceiverOutcome.CRCPass && ...
    isequaln(f.AppliedMatrices,p.AppliedMatrices) && ...
    isequaln(f.ExecutedComponentReceipts,p.ExecutedComponentReceipts));
fprintf('COMPLETED_CSI_APPLICATION_ACTUAL_INPUTS_PASS positive_waveform_checks_executed=1 additional_waveform_runs=0\n');
ok=true;
end

function localReject(call,id)
try, call(); catch cause
    assert(strcmp(cause.identifier,id),'Expected %s, got %s: %s',id,cause.identifier,cause.message);
    return;
end
error('test:ExpectedCompletedCSIRejection','Expected %s.',id);
end

function sha=localSHA(token)
sha=string(sixgr.util.sha256Hex(uint8(unicode2native(char(token),'UTF-8'))));
end

function item=localCopyPreparedInput(item,cfg)
original=item.Context.Prepared;
item.Context.Prepared=sixgr.link.PreparedDataTransmission(original.Direction,cfg, ...
    original.RequestBinding,original.Tx,original.TxInfo,original.ReceiverConfig, ...
    original.SampleRateHz,original.PreparationComputeTime_ms);
end

function cfg=localSealPreparedPopulation(cfg)
cfg.lls6g.runtime.PreparedDataPopulationSHA256=localSHA( ...
    string(jsonencode(sixgr.util.jsonSafeValue(cfg.lls6g.runtime.PreparedDataPopulation))));
end

function value=localDifferentNumber(original)
if isfinite(original), value=double(original)+1; else, value=0; end
end

function localDeclaredMappingChecks()
% Authored numerical vectors test the pure arithmetic contract, not an RF
% outcome. No successful owner, decoded DCI, CRC or execution is authored.
carrier=struct('NSizeGrid',2,'SymbolsPerSlot',14);
matrix=[1 1i;0.5 -0.25];
spec=struct('Mode',"prg_symbol_selective",'NPorts',2,'NLayers',2, ...
    'NPRG',2,'NSymbolGroups',2,'PRGSize',1,'PRBSet',[0 1], ...
    'ScheduledSymbols',[2 3],'SymbolGroupMap',[0 1], ...
    'W',repmat(matrix,1,1,2,2),'MatrixSource',"declared_arithmetic_fixture_not_waveform", ...
    'CodebookIdentifier',"",'NormalizationConvention',"explicit_no_normalization");
bundle=sixgr.pdsch.PDSCHPrecoderBundle(spec);
subcarrier=[1;13;2;14]; symbol=[3;3;4;4];
indices=subcarrier+(symbol-1)*24+(0:1)*(24*14);
layers=[1+1i 2;3 -1i;2-1i 0.5;-0.5 1i];
[ports,trace]=bundle.apply(layers.',floor((subcarrier-1)/12),symbol-1,'Domain','data');
tx=struct('PrecoderBundle',bundle,'Carrier',carrier,'PDSCHLayerSymbols',layers, ...
    'PDSCHPortSymbols',ports.','PDSCHLayerIndices',indices,'PDSCHPortIndices',indices, ...
    'LayerSymbolOrder',sixgr.phy.resource.buildSymbolOrderingMap(carrier,indices,"layer"), ...
    'PortSymbolOrder',sixgr.phy.resource.buildSymbolOrderingMap(carrier,indices,"port"), ...
    'DataPrecoderTrace',trace);
projection=[2 0;0 0.5;1i -1]; % Nonunit, non-square actual physical mapping.
frozen=struct('WidebandOnly',true,'MatrixPhysicalPorts',projection*matrix);
call=@sixgr.truth.collectCompletedCSIDataMapping;
e=call(tx,projection,frozen);
assert(~e.ExecutionProof && e.AdditionalPHYExecutions==0 && ...
    isequal(e.AppliedMatrixShape,[3 2 2 2]) && ...
    isequal(e.DataResourcesPerSlice,ones(2)) && ...
    isequal(e.PRGIndex0,[0;1;0;1]) && isequal(e.SymbolGroupIndex0,[0;0;1;1]) && ...
    isequal(e.SubcarrierIndex0,subcarrier-1) && ...
    isequal(e.AppliedMatrixPages,repmat(projection*matrix,1,1,2,2)), ...
    'Multiple native pages must be checked without collapsing their coordinates or normalizing their power.');
permutation=[3 1 4 2]; moved=tx;
moved.PDSCHLayerSymbols=layers(permutation,:); moved.PDSCHPortSymbols=ports(:,permutation).';
moved.PDSCHLayerIndices=indices(permutation,:); moved.PDSCHPortIndices=indices(permutation,:);
moved.LayerSymbolOrder=sixgr.phy.resource.buildSymbolOrderingMap(carrier,moved.PDSCHLayerIndices,"layer");
moved.PortSymbolOrder=sixgr.phy.resource.buildSymbolOrderingMap(carrier,moved.PDSCHPortIndices,"port");
[~,moved.DataPrecoderTrace]=bundle.apply(moved.PDSCHLayerSymbols.', ...
    floor((subcarrier(permutation)-1)/12),symbol(permutation)-1,'Domain','data');
permuted=call(moved,projection,frozen);
assert(isequal(permuted.SubcarrierIndex0,e.SubcarrierIndex0(permutation)) && ...
    isequal(permuted.DataResourcesPerSlice,e.DataResourcesPerSlice), ...
    'Native indices, not assumed contiguous order, select the pages.');
bad=tx; bad.PDSCHPortSymbols(2,1)=bad.PDSCHPortSymbols(2,1)+0.25;
localReject(@()call(bad,projection,frozen),'sixgr:truth:CompletedCSIMatrixMismatch');
bad=tx; bad.PDSCHPortIndices=indices(permutation,:);
bad.PortSymbolOrder=sixgr.phy.resource.buildSymbolOrderingMap(carrier,bad.PDSCHPortIndices,"port");
localReject(@()call(bad,projection,frozen),'sixgr:truth:CompletedCSIResourceMismatch');
bad=tx; bad.LayerSymbolOrder.OFDMSymbolIndex(1)=14;
localReject(@()call(bad,projection,frozen),'sixgr:truth:CompletedCSIResourceMismatch');
bad=tx; bad.DataPrecoderTrace.PRG(1)=1;
localReject(@()call(bad,projection,frozen),'sixgr:truth:CompletedCSIResourceMismatch');
badFrozen=frozen; badFrozen.MatrixPhysicalPorts(1)=badFrozen.MatrixPhysicalPorts(1)+0.25;
localReject(@()call(tx,projection,badFrozen),'sixgr:truth:CompletedCSIMatrixMismatch');
% Even self-consistent unequal producer pages cannot be called application
% of the retained single frozen matrix. A per-page frozen grant is missing.
unequal=spec; unequal.W(:,:,2,2)=2*matrix;
bad=tx; bad.PrecoderBundle=sixgr.pdsch.PDSCHPrecoderBundle(unequal);
[changed,changedTrace]=bad.PrecoderBundle.apply(layers.', ...
    floor((subcarrier-1)/12),symbol-1,'Domain','data');
bad.PDSCHPortSymbols=changed.'; bad.DataPrecoderTrace=changedTrace;
localReject(@()call(bad,projection,frozen),'sixgr:truth:CompletedCSIMatrixMismatch');
badFrozen=frozen; badFrozen.WidebandOnly=false;
localReject(@()call(tx,projection,badFrozen),'sixgr:truth:CompletedCSIFrozenPageContractRequired');
end
