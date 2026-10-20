function [cfg,assignment,context,tx]=buildConfiguredPUCCHEpisode(cfg,c)
% Build receiver obligation FIRST from installed state and declared counts.
% This is a configured independent-episode boundary, not received DCI/access.
% Valid TX/RX layout differences remain physical outcomes for the receiver.
cfg=sixgr.truth.attachFixedLinkRuntimeAntennaContext(cfg,c.ue_index,c.serving_cell);
cfg=sixgr.phy.grid.applyRuntimeCarrierTimeline(cfg,c.absolute_slot0+1);
carrier=sixgr.phy.grid.makeCarrier(cfg);
ue=struct('UEID',c.ue_index,'RNTI',c.rnti,'ServingCell',c.serving_cell, ...
    'PUCCHCell',c.serving_cell,'ComponentCarrier',cfg.phy.frame.DefaultIdentity.ScheduledCCID, ...
    'ActiveULBWP',cfg.phy.frame.DefaultIdentity.ULBWPID);
rrc=sixgr.phy.pucch.PUCCHConfigBuilder.receiverConfiguration(cfg,ue);
installed=[]; reportID=""; reportEpoch=NaN;
if c.csi_requested
    installed=sixgr.phy.mimo.CSIReportConfiguration( ...
        cfg.phy.csi.reportConfiguration,cfg.phy.csi.reportConfiguration.Epoch);
    reportID=installed.ReportConfigID; reportEpoch=installed.Epoch;
end
obligation=struct('ObservationID',string(c.id),'ConfigurationEpoch',rrc.ConfigurationEpoch, ...
    'HARQBitCount',c.harq_bit_count,'SRBitCount',c.sr_bit_count,'PriorityIndex',0, ...
    'CSIReportConfigID',reportID,'CSIConfigurationEpoch',reportEpoch);
context=sixgr.truth.buildConfiguredPUCCHReceiveContext(obligation,installed);
identity=struct('ObservationID',string(c.id),'ResourceID',c.resource_id,'RNTI',c.rnti, ...
    'AbsoluteSlot0',c.absolute_slot0,'Source',"configured_independent_episode_obligation", ...
    'TimingSource',"configured_radio_occasion", ...
    'ResourceSelectionProcedure',string(c.resource_selection_procedure));
assignment=sixgr.phy.pucch.PUCCHReceptionAssignment(identity,rrc,context);
frozen=context.Digest;
facade=sixgr.phy.FrameStructureEngine(cfg,'FrameCoreOnly',true);
assert(facade.DuplexMode=="TDD",'sixgr:pucch:UnsupportedEpisodeDuplex', ...
    'This installed campaign requires explicit TDD symbol ownership.');
part=sixgr.phy.FrameStructureEngine.SlotPartitionFromState(facade.SlotState,c.absolute_slot0);
available=sixgr.phy.frame.SlotFormatResolver.isAvailable(facade.SlotState,c.absolute_slot0, ...
    assignment.Resource.Data.StartSymbol,assignment.Resource.Data.NumSymbols,'UL');
assert(available.Available,'sixgr:pucch:IllegalEpisodeResource', ...
    'PUCCH allocation is not UL in the installed TDD calendar: %s.',available.ReasonCode);
tx=struct([]);
if ~c.signal_present, return; end % Do not construct a hidden H0 transmitter.
t=c.transmitter; csi1=int8([]); csi2=int8([]);
if ~isempty(fieldnames(t.csi))
    request=cfg.phy.csi.reportConfiguration; request.Rank=t.csi.rank;
    schema=sixgr.phy.mimo.CSIReportConfiguration(request,request.Epoch);
    [~,values]=sixgr.phy.mimo.TypeISinglePanelCodebook.matrix(request,t.csi.pmi);
    values.RI=t.csi.rank; values.CRI=t.csi.cri; values.CQI_CW0=t.csi.cqi_cw0;
    report=schema.build(values); csi1=report.Part1Bits; csi2=report.Part2Bits;
end
states=sixgr.truth.initializeConfiguredSRProcedures(cfg,ue);
requests=t.scheduling_requests;
assert(numel(requests)==numel(states),'sixgr:pucch:MissingEpisodeSRState', ...
    'Declare every installed SR procedure; absence is not an implicit pending state.');
for k=1:numel(states)
    d=states(k).Data; hit=find([requests.id]==d.SchedulingRequestID);
    assert(isscalar(hit),'sixgr:pucch:MissingEpisodeSRState','Installed SR identity missing or duplicated.');
    d.PendingPositiveSR=requests(hit).pending_positive;
    d.ProhibitTimerActive=requests(hit).prohibit_timer_active;
    d.InitializationSource="declared_independent_episode_SR_state_not_received_traffic";
    states(k)=sixgr.phy.pucch.SchedulingRequestState(d);
end
ownership=string(part.ResolvedDirection);
ownership(ownership=="DL")="D"; ownership(ownership=="UL")="U";
ownership(ownership=="GUARD")="G";
ownership(ownership=="UNRESOLVED_FLEX")="F";
assert(all(ismember(ownership,["D","U","G","F"])), ...
    'sixgr:pucch:UnresolvedEpisodeSymbols','Unknown installed symbol ownership.');
% Leave unrelated flexible symbols unresolved. The allocation itself was
% checked above and must consist exclusively of configured UL symbols.
p=t.control;
frame=struct('K1',p.k1,'K1Source',"declared_component_control_not_received", ...
    'PDSCHEndSlot',p.pdsch_end_slot,'TargetSlot',c.absolute_slot0+1, ...
    'DecodedPRI',p.decoded_pri,'PRIFieldWidth',p.pri_field_width, ...
    'PRIProvenance',"declared_component_control_not_received", ...
    'FirstCCE',p.first_cce,'NumCCE',p.num_cce, ...
    'SlotSymbolOwnership',join(ownership,""),'FlexibleResolutionProvided',false, ...
    'SchedulingRequestStates',sixgr.phy.pucch.SchedulingRequestState.atSlot(states,c.absolute_slot0));
if isempty(t.harq_bits)
    plan=sixgr.phy.pucch.PUCCHConfigBuilder.planCSI(cfg,ue,csi1,csi2,frame);
else
    plan=sixgr.phy.pucch.PUCCHConfigBuilder.planCombined(cfg,ue,int8(t.harq_bits(:)),csi1,csi2,frame);
end
materialized=sixgr.phy.pucch.PUCCHConfigBuilder.materialize(cfg,plan);
tx=sixgr.phy.pucch.PUCCHTransmitter.transmit(carrier,materialized.Assignment,plan.Report);
assert(context.Digest==frozen,'sixgr:pucch:ReceiverContextMutation','TX construction changed the receive obligation.');
end
