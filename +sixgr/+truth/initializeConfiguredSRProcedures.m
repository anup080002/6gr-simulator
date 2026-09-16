function states=initializeConfiguredSRProcedures(cfg,ue)
% Explicit RRC-installation initial state: no SR has yet been triggered.
% Not a missing-state fallback, traffic inference or gNB receive obligation.
sixgr.truth.buildConfiguredSRCalendar(cfg,ue,1,1); % Validate all installed associations.
rrc=sixgr.phy.pucch.PUCCHConfigBuilder.receiverConfiguration(cfg,ue);
configs=rrc.Data.SchedulingRequestResources;
snapshots=cell(1,numel(configs));
for k=1:numel(configs)
    c=configs(k);
    data=struct('SRResourceConfigurationID',c.scheduling_request_resource_id, ...
        'SchedulingRequestID',c.scheduling_request_id,'UEIndex',ue.UEID,'RNTI',ue.RNTI, ...
        'ServingCell',ue.ServingCell,'ComponentCarrier',ue.ComponentCarrier,'ActiveULBWP',ue.ActiveULBWP, ...
        'ConfigurationEpoch',rrc.ConfigurationEpoch,'PeriodSlots',c.periodicity_slots, ...
        'OffsetSlots',c.offset_slots,'Priority',c.priority_index,'AbsoluteSlot',0, ...
        'PendingPositiveSR',false,'ProhibitTimerActive',false, ...
        'InitializationSource',"configured_SR_procedure_installation_no_trigger");
    snapshots{k}=sixgr.phy.pucch.SchedulingRequestState(data);
end
states=[snapshots{:}];
end
