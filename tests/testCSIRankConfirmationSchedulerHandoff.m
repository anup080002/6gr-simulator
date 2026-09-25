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
        'DeliveredSlot',5*k,'ServingCell',1);
    [state,report]=sixgr.truth.CoupledTruthRuntime.applyDeliveredCSIAdaptationRuntime( ...
        state,report,1,'DL',struct());
    assert(report.RI==receivedRanks(k),'Never rewrite the receiver-reported RI.');
    assert(isfield(report,'SchedulerSpatialDecisionDeferred'), ...
        'The runtime drops the core rank-confirmation admission decision.');
    assert(report.SchedulerSpatialDecisionDeferred==held(k) && ...
        report.SchedulerAcceptedRank==acceptedRanks(k), ...
        'Rank admission must use the prior accepted per-UE operating point.');
    assert(state.DLLinkAdaptationState{1}.SchedulerAcceptedRank==acceptedRanks(k));
    if held(k)
        assert(report.RankUpdateStatus=="pending_increase_confirmation");
    end
end
assert(state.CfgMobility.phy.pdsch.numLayers==1, ...
    'Per-UE adaptation must not mutate the installed initial rank or other UEs.');
fprintf('CSI_RANK_CONFIRMATION_HANDOFF_PASS reports=6 accepted_ranks=1,2,2,1,1,2\n');
ok=true;
end
