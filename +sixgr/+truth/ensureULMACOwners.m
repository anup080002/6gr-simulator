function [state,scope]=ensureULMACOwners(state,cfg,ue,cellID)
% Lifecycle-scoped UE TX and gNB RX owners remain in coordinator checkpoints.
p=cfg.phy.mac.uplinkControl;
assert(p.Enabled,'sixgr:mac:ULMACDisabled','Explicit enabled policy required.');
assert(isfield(state,'SharedWaveformStream')&&~isempty(state.SharedWaveformStream), ...
    'sixgr:mac:SharedMACClockRequired','Received MAC state requires original shared sample clock.');
scope=struct('RunID',string(sixgr.util.structGet(cfg,'run.runTag','')), ...
    'ExecutionID',string(sixgr.util.structGet(cfg,'run.executionID',sixgr.util.structGet(cfg,'meta.executionID',''))), ...
    'ConfigHash',string(sixgr.util.structGet(cfg,'meta.configHash','')), ...
    'UEID',double(ue),'CellID',double(cellID),'RNTI',sixgr.truth.CoupledRadioIdentity.resolve(state,ue,cellID), ...
    'ConfigurationEpoch',double(sixgr.util.structGet(cfg,'protocol.configuration_epoch',NaN)), ...
    'SampleRateHz',double(state.SharedWaveformStream.SampleRateHz));
names={'SharedUEMACScopes','SharedUEPHRStates','SharedUEBSRStates','SharedGNBPHRStates','SharedGNBBufferStates'};
for k=1:numel(names)
    if ~isfield(state,names{k}), state.(names{k})={}; end
end
current=state.SharedUEMACScopes;
if numel(current)>=ue && ~isempty(current{ue}) && isequaln(current{ue},scope), return; end
if numel(current)>=ue && ~isempty(current{ue})
    archived=struct();
    for k=1:numel(names), values=state.(names{k}); archived.(names{k})=values{ue}; end
    if ~isfield(state,'ArchivedULMACOwners'), state.ArchivedULMACOwners={}; end
    state.ArchivedULMACOwners{end+1}=archived;
end
state.SharedUEMACScopes{ue}=scope;
state.SharedUEPHRStates{ue}=sixgr.l2.mac.PHRStateMachine(ue,p.PHRPeriodicSlots);
state.SharedUEPHRStates{ue}.trigger('configuration',state.CurrentSlot);
state.SharedUEBSRStates{ue}=sixgr.l2.mac.BSRStateMachine(ue,p.LCGID+1,p.BSRPeriodicSlots,p.BSRRetxSlots);
state.SharedGNBPHRStates{ue}=sixgr.l2.mac.ReceivedPHRState(scope);
state.SharedGNBBufferStates{ue}=sixgr.l2.mac.ReceivedULBufferState(scope);
end
