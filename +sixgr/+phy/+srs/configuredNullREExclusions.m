function [occupied,evidence]=configuredNullREExclusions(cfg,carrier)
% Receiver-known SRS resources that cannot be assumed to be null REs.
% This is configured resource knowledge, NOT actual emission/activity truth.
% No received samples, transmitted values or injected noise are inputs.
occupied=false(12*carrier.NSizeGrid,carrier.SymbolsPerSlot);
evidence=struct('Source',"installed_same_cell_SRS_resource_configuration", ...
    'ConfiguredResourcesExamined',0,'ResourcesDue',0,'ExcludedRECount',0, ...
    'ActualTransmissionsInferred',false,'ReceiverCellID',NaN);
rows=sixgr.util.structGet(cfg,'phy.srs.ueResourceBindings',[]);
scenario=sixgr.util.structGet(cfg,'lls6g.reference_signals.srs.ue_resource_bindings',[]);
if isempty(rows), rows=scenario; end
if isempty(rows), return; end
owner=sixgr.util.structGet(cfg,'phy.srs.UEFrequencyResourceBinding',struct());
assert(isstruct(owner) && isscalar(owner) && all(isfield(owner, ...
    {'UEIndex','RNTI','ServingCellID','SHA256'})), ...
    'sixgr:srs:NullREReceiverIdentity','Configured null exclusions need the actual receiver resource binding.');
% Rebind independently: a mutated receiver identity cannot select a more
% convenient noise population or silently change the desired resource.
[~,expected]=sixgr.phy.srs.bindConfiguredUEFrequencyResource( ...
    cfg,owner.UEIndex,owner.RNTI,owner.ServingCellID);
assert(isequaln(owner,expected),'sixgr:srs:NullREReceiverIdentity', ...
    'The retained UE resource binding differs from installed configuration.');
evidence.ReceiverCellID=owner.ServingCellID;
for k=1:numel(rows)
    row=rows(k);
    if row.serving_cell_id~=owner.ServingCellID, continue; end
    userCfg=sixgr.phy.srs.bindConfiguredUEFrequencyResource( ...
        cfg,row.ue_index,row.rnti,row.serving_cell_id);
    strict=sixgr.phy.srs.buildSRSConfigFromScenario(userCfg);
    indices=nrSRSIndices(carrier,strict.ToolboxSRS);
    evidence.ConfiguredResourcesExamined=evidence.ConfiguredResourcesExamined+1;
    if isempty(indices), continue; end
    [sc,symbol,~]=ind2sub([size(occupied) strict.NumSRSPorts],double(indices(:)));
    occupied(sub2ind(size(occupied),sc,symbol))=true;
    evidence.ResourcesDue=evidence.ResourcesDue+1;
end
evidence.ExcludedRECount=nnz(occupied);
end
