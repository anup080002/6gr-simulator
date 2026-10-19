function ok=testCSIRankConfirmationSchedulerHandoff()
% Delivered-value boundary test, not physical CSI-channel qualification.
setup6GRSimToolkit('Verbose',false);
cfg=sixgr.config.defaultConfig();
cfg.phy.linkAdaptation.mode='amc';
cfg.phy.linkAdaptation.dlPolicy='baseline';
cfg.phy.linkAdaptation.rankPolicy='adaptive';
cfg.phy.linkAdaptation.beamPolicy='adaptive';
cfg.phy.linkAdaptation.domain='cqi';
cfg.phy.linkAdaptation.rankIncreaseConfirmationReports=2;
cfg.phy.pdsch.numLayers=1; cfg.phy.pdsch.nLayers=1;
cfg.phy.pdsch.maxLayers=2;
cfg.phy.nTxAnt=2; cfg.phy.nRxAnt=2;
cfg.phy.pdsch.precoding.matrix=[];
state=struct('CfgMobility',cfg,'NumUsers',1,'DLSchedulers',{{}}, ...
    'ULSchedulers',{{}},'DLLinkAdaptationState',{{struct()}}, ...
    'ULLinkAdaptationState',{{struct()}},'SlotDuration_s',.001);
receivedRanks=[2 2 2 1 2 2];
acceptedRanks=[1 2 2 1 1 2];
held=[true false false false true false];
for k=1:numel(receivedRanks)
    report=struct('CQI',10,'RI',receivedRanks(k),'PMI',0,'CRI',0, ...
        'SINR_dB',NaN,'SourceSlot',5*k-1,'DueSlot',5*k, ...
        'DeliveredSlot',5*k,'ServingCell',1,'ReportIdentity',"received-csi-"+k);
    inputReport=report;
    [state,report]=sixgr.truth.CoupledTruthRuntime.applyDeliveredCSIAdaptationRuntime( ...
        state,report,1,'DL',struct());
    assert(report.RI==receivedRanks(k),'Never rewrite the receiver-reported RI.');
    assert(isfield(report,'SchedulerSpatialDecisionDeferred'), ...
        'The runtime drops the core rank-confirmation admission decision.');
    assert(report.SchedulerSpatialDecisionDeferred==held(k) && ...
        report.SchedulerAcceptedRank==acceptedRanks(k), ...
        'Rank admission must use the prior accepted per-UE operating point.');
    assert(state.DLLinkAdaptationState{1}.SchedulerAcceptedRank==acceptedRanks(k));
    evidence=sixgr.truth.linkAdaptationStateEvidence(state,1);
    assert(evidence.RuntimeDLAcceptedRank==acceptedRanks(k) && ...
        evidence.RuntimeDLRankConfirmationRequired==2);
    if held(k)
        assert(report.RankUpdateStatus=="pending_increase_confirmation");
        assert(evidence.RuntimeDLPendingRankIncrease==receivedRanks(k) && ...
            evidence.RuntimeDLRankConfirmationCount==1);
    end
    if k==1
        previous=state;
        repeated=inputReport; repeated.DeliveredSlot=repeated.DeliveredSlot+1;
        [state,rejected]=sixgr.truth.CoupledTruthRuntime.applyDeliveredCSIAdaptationRuntime( ...
            state,repeated,1,'DL',struct());
        assert(isequaln(state,previous),'sixgr:test:DuplicateCSIChangedAdaptation', ...
            'Re-delivering one report must not become a second rank confirmation.');
        assert(rejected.SchedulerSpatialDecisionDeferred && ...
            rejected.AdaptationDeliveryStatus=="ignored_duplicate_feedback_delivery");
    elseif k==2
        previous=state;
        stale=inputReport; stale.SourceSlot=4; stale.DueSlot=5;
        stale.DeliveredSlot=11; stale.RI=1; stale.CQI=1;
        [state,rejected]=sixgr.truth.CoupledTruthRuntime.applyDeliveredCSIAdaptationRuntime( ...
            state,stale,1,'DL',struct());
        assert(isequaln(state,previous),'sixgr:test:StaleCSIChangedAdaptation', ...
            'An older measurement must not overwrite a newer accepted operating point.');
        assert(rejected.SchedulerSpatialDecisionDeferred && ...
            rejected.AdaptationDeliveryStatus=="ignored_stale_feedback_source");
    end
end
% Newer source data still cannot be processed backwards in delivery time.
previous=state;
invalidOrder=inputReport; invalidOrder.SourceSlot=30; invalidOrder.DueSlot=30;
invalidOrder.DeliveredSlot=30; invalidOrder.ReportIdentity="later-delivery-clock";
[advanced,~]=sixgr.truth.CoupledTruthRuntime.applyDeliveredCSIAdaptationRuntime( ...
    state,setfield(invalidOrder,'DeliveredSlot',35),1,'DL',struct()); %#ok<SFLD>
invalidOrder.SourceSlot=31; invalidOrder.DueSlot=31; invalidOrder.DeliveredSlot=31;
invalidOrder.ReportIdentity="regressed-delivery-clock";
[ignored,rejected]=sixgr.truth.CoupledTruthRuntime.applyDeliveredCSIAdaptationRuntime( ...
    advanced,invalidOrder,1,'DL',struct());
assert(isequaln(ignored,advanced) && ...
    rejected.AdaptationDeliveryStatus=="ignored_nonmonotonic_feedback_delivery");
assert(isequaln(previous,state));
assert(state.CfgMobility.phy.pdsch.numLayers==1, ...
    'Per-UE adaptation must not mutate the installed initial rank or other UEs.');
fprintf('CSI_RANK_CONFIRMATION_HANDOFF_PASS reports=6 accepted_ranks=1,2,2,1,1,2\n');
ok=true;
end
