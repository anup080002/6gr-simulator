function ok=testInitialSpatialAcquisitionPolicy()
% Declared receiver-delivery boundaries, not new PHY/RF or a campaign.
setup6GRSimToolkit('Verbose',false);
s=sixgr.lls6g.config.loadScenarioConfig( ...
    'simulator/configs/scenarios/lls_tdd_n40_20mhz_64txru_4rx_cdlc100_reference_snr_sweep.yaml');
cfg=sixgr.lls6g.buildInternalConfig(s,tempname);
assert(cfg.phy.linkAdaptation.initialSpatialConfirmationReports==1 && ...
    cfg.phy.linkAdaptation.rankIncreaseConfirmationReports==2 && ...
    cfg.phy.csi.reportPeriodicitySlots==5 && cfg.phy.csi.reportOffsetSlots==3);
for direction=["DL","UL"]
    st=localState(cfg);
    [st,r]=localDeliver(st,direction,2,1,10);
    assert(~r.SchedulerSpatialDecisionDeferred && r.HasAcceptedSpatialDecision && ...
        r.SpatialConfirmationPhase=="initial_measured_spatial_acquisition" && ...
        r.SpatialConfirmationRequiredCount==1 && r.SchedulerAcceptedRank==2, ...
        'First %s acquisition failed: %s',direction,jsonencode(r));
    before=st;
    [again,duplicate]=localDeliver(st,direction,2,1,10);
    assert(isequaln(again,before) && duplicate.SchedulerSpatialDecisionDeferred);
    [st,down]=localDeliver(st,direction,1,2,10);
    assert(~down.SchedulerSpatialDecisionDeferred && down.SchedulerAcceptedRank==1 && down.HasAcceptedSpatialDecision);
    [st,pending]=localDeliver(st,direction,2,3,10);
    assert(pending.SchedulerSpatialDecisionDeferred && pending.SchedulerAcceptedRank==1 && ...
        pending.SpatialConfirmationRequiredCount==2 && pending.HasAcceptedSpatialDecision);
    [st,up]=localDeliver(st,direction,2,4,10);
    assert(~up.SchedulerSpatialDecisionDeferred && up.SchedulerAcceptedRank==2);
    % Quality reset is not loss of acquired spatial authority.
    acquired=st.(direction+'LinkAdaptationState'){1};
    assert(acquired.HasAcceptedSpatialDecision);
    same=localState(cfg); [same,first]=localDeliver(same,direction,1,1,10);
    assert(first.HasAcceptedSpatialDecision && ~first.SchedulerSpatialDecisionDeferred);
    [~,later]=localDeliver(same,direction,2,2,10);
    assert(later.SchedulerSpatialDecisionDeferred && later.SpatialConfirmationRequiredCount==2);
    % Explicit two-report initial acquisition also applies to same rank.
    two=cfg; two.phy.linkAdaptation.initialSpatialConfirmationReports=2;
    twoState=localState(two); [twoState,held]=localDeliver(twoState,direction,1,1,10);
    assert(held.SchedulerSpatialDecisionDeferred && ~held.HasAcceptedSpatialDecision && ...
        held.RankUpdateStatus=="pending_initial_spatial_confirmation");
    [~,ready]=localDeliver(twoState,direction,1,2,10);
    assert(ready.HasAcceptedSpatialDecision && ~ready.SchedulerSpatialDecisionDeferred);
    % Measured outage cannot acquire; it is not bootstrap quality.
    outage=localState(cfg); [~,bad]=localDeliver(outage,direction,2,1,0);
    assert(~bad.HasAcceptedSpatialDecision);
end
% Spatial-only UL can acquire with every quality field still unavailable.
st=localState(cfg); [st,spatial]=localDeliver(st,"UL",4,1,NaN);
assert(spatial.HasAcceptedSpatialDecision && ~spatial.SchedulerSpatialDecisionDeferred && ...
    isnan(spatial.MCSIndex) && isnan(st.ULLinkAdaptationState{1}.SmoothedCQI) && ...
    ~st.ULLinkAdaptationState{1}.Initialized);
% A new DL report epoch must not reset UL SRS acquisition.
prior=st.ULLinkAdaptationState{1}; changed=cfg;
changed.phy.csi.reportConfigurationEpoch=cfg.phy.csi.reportConfigurationEpoch+1;
metric=struct('CQI',10,'RI',4,'PMI',0,'SpatialUpdateAllowed',false);
[~,unchanged]=sixgr.link.computeLinkAdaptationDecision(changed,"UL",metric,'AdaptationState',prior);
assert(unchanged.HasAcceptedSpatialDecision);
changed.rf.configurationEpoch=cfg.rf.configurationEpoch+1;
[~,reset]=sixgr.link.computeLinkAdaptationDecision(changed,"UL",metric,'AdaptationState',prior);
assert(~reset.HasAcceptedSpatialDecision);
% State survives native MAT serialization without quality-derived inference.
path=[tempname '.mat']; save(path,'prior'); saved=load(path,'prior'); delete(path);
assert(isequaln(saved.prior,prior));
ok=true; disp('INITIAL_SPATIAL_ACQUISITION_POLICY_PASS initial1_steady2_DL_UL_no_RF');
end

function state=localState(cfg)
state=struct('CfgMobility',cfg,'NumUsers',1,'DLSchedulers',{{}},'ULSchedulers',{{}}, ...
    'DLLinkAdaptationState',{{struct()}},'ULLinkAdaptationState',{{struct()}}, ...
    'SlotDuration_s',sixgr.time.slotDurationSec(cfg));
end

function [state,r]=localDeliver(state,direction,rank,sequence,cqi)
source=26+5*(sequence-1); delivered=44+5*(sequence-1);
if direction=="UL", source=45+5*(sequence-1); delivered=source+1; end
signal="CSI-RS"; if direction=="UL", signal="SRS"; end
r=struct('CQI',cqi,'RI',rank,'PMI',0,'CRI',0,'SINR_dB',NaN, ...
    'SourceSlot',source,'DueSlot',delivered,'DeliveredSlot',delivered, ...
    'ServingCell',1,'SourceSignal',signal,'SpatialOnly',direction=="UL" && isnan(cqi), ...
    'ReportIdentity',"declared_initial_"+direction+"_"+sequence);
[state,r]=sixgr.truth.CoupledTruthRuntime.applyDeliveredCSIAdaptationRuntime(state,r,1,direction,struct());
end
