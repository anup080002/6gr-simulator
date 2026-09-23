function diagnoseCSIReceiveReferenceAuthority(scenarioPath,sourceRun,outputRoot)
% Dependency diagnostic on copied real rows, not a new physical CSI episode.
assert(~isfolder(outputRoot),'test:EvidenceExists','Preserve prior diagnostics.');
s=sixgr.lls6g.config.loadScenarioConfig(scenarioPath);
cfg=sixgr.lls6g.buildInternalConfig(s,outputRoot);
path=fullfile(sourceRun,'air_interface','csv','csi_rs_trials.csv');
hash=sixgr.util.sha256File(path);
T=readtable(path,'TextType','string','VariableNamingRule','preserve');
assert(~isempty(T) && sixgr.util.sha256File(path)==hash);
row=T(1,:);
ue=double(row.UEIndex); cellID=double(row.ServingCell);
target=double(row.ObservationDeliverySlot)+10;
calendar=table(double(row.Slot),'VariableNames',{'CSIReferenceSlot'});
state=struct('ControlTrials',struct('CSIRS',row),'SweepPointStartSlot',1);
[before,~]=sixgr.truth.resolveCSIReceiveReferenceEvidence(state,cfg,ue,cellID,calendar,target);
assert(isscalar(before) && before,'test:MissingPositiveCSIReference','Require the real completed positive CSI observation.');
fields=["Observed","Consumed","ResourceExtractionAvailable", ...
    "ChannelEstimateAvailable","CSIMeasurementAvailable"];
results=table();
for field=fields
    altered=state;
    altered.ControlTrials.CSIRS.(field)(1)=false;
    [after,~]=sixgr.truth.resolveCSIReceiveReferenceEvidence(altered,cfg,ue,cellID,calendar,target);
    assert(altered.ControlTrials.CSIRS.Transmitted==row.Transmitted && ...
        altered.ControlTrials.CSIRS.Slot==row.Slot);
    result=table(field,logical(before),logical(after),logical(before==after), ...
        'VariableNames',{'ChangedUEReceiverFlag','OriginalGNBEligibility', ...
        'AlteredGNBEligibility','IndependentOfUEReceiverOutcome'});
    results=[results;result]; %#ok<AGROW>
end
sixgr.util.csvWriteTable(fullfile(outputRoot,'authority_dependency.csv'),results);
sixgr.util.jsonWrite(fullfile(outputRoot,'receipt.json'),struct( ...
    'Scope',"copied_receiver_outcome_dependency_diagnostic_not_PHY_reexecution", ...
    'SourcePath',string(path),'SourceSHA256',hash,'SourceSlot',double(row.Slot), ...
    'TransmittedFlagUnchanged',true,'PayloadBitsConsulted',false, ...
    'IndependentGNBTransmissionLedgerPresent',false, ...
    'IndependentOfUEReceiverOutcome',all(results.IndependentOfUEReceiverOutcome)));
disp(results);
assert(all(results.IndependentOfUEReceiverOutcome), ...
    'test:CSIReceiveLayoutUsesUEOutcome', ...
    'The gNB schema currently depends on UE receiver outcomes; bind an independent executed CSI-RS transmission obligation.');
end
