function result=consumeAcceptedSRSSpatialDecision(state,decision,ueIndex,rnti,ri,tpmi,cfg)
% Check accepted-source age/availability separately from newest raw SRS.
consumerSlot=double(state.CurrentSlot);
knowledgeSlot=consumerSlot;
if string(sixgr.util.structGet(state,'RuntimeViewMode',"execution"))=="future_ul_grant_planning"
    knowledgeSlot=double(state.PlanningDecisionSlot);
end
maxAge=double(state.ControlGating.SRSMaxAgeSlots);
if nargin<7, cfg=state.CfgMobility; end
assert(isstruct(decision) && isscalar(decision), ...
    'sixgr:truth:AcceptedSRSSpatialIdentityMismatch','Retain one accepted-source capsule.');
if isempty(fieldnames(decision))
    result=sixgr.phy.refsig.causalMeasurementState(table(),consumerSlot, ...
        'KnownAtSlot',knowledgeSlot,'MaxAgeSlots',maxAge);
    result.Status="accepted_srs_spatial_identity_unavailable";
    return;
end
assert(string(decision.Version)=="accepted_srs_spatial_decision/v1" && ...
    decision.TargetId==ueIndex && decision.RNTI==rnti && ...
    decision.ServingCell==state.CurrentServingIdx(ueIndex) && ...
    decision.RI==ri && decision.PMI==tpmi, ...
    'sixgr:truth:AcceptedSRSSpatialIdentityMismatch', ...
    'Accepted SRS identity, serving cell and RI/TPMI must remain one decision.');
sixgr.truth.validateAcceptedSRSConfiguration(cfg,decision);
T=struct2table(decision,'AsArray',true);
if decision.ProducerSlot<double(sixgr.util.structGet(state,'SweepPointStartSlot',1))
    T=T([],:);
end
clockArgs=sixgr.truth.referenceMeasurementClockArguments(state,T,"SRS","UE",ueIndex,knowledgeSlot);
result=sixgr.phy.refsig.causalMeasurementState(T,consumerSlot, ...
    'SignalType',"SRS",'TargetType',"UE",'TargetId',ueIndex, ...
    'KnownAtSlot',knowledgeSlot,'MaxAgeSlots',maxAge,clockArgs{:});
end
