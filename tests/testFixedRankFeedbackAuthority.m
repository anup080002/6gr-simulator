function ok=testFixedRankFeedbackAuthority()
% Rank-control and delivered-feedback boundary test, not waveform proof.
setup6GRSimToolkit('Verbose',false,'RunToolboxChecks',false);
source=sixgr.lls6g.config.loadScenarioConfig( ...
    'simulator/configs/fixtures/lls_fixed_rank4_connected_config.yaml');
installed=sixgr.lls6g.buildInternalConfig(source,tempname);
assert(installed.phy.nTxAnt==64 && installed.phy.nRxAnt==4 && ...
    installed.phy.pdsch.numLayers==4 && installed.phy.pusch.numLayers==4);
assert(isequal(installed.phy.csi.rankDomain,4) && ...
    isequal(installed.phy.csi.reportConfiguration.AllowedRanks,4));
request=installed.phy.csi.reportConfiguration;
wire=sixgr.phy.mimo.CSIReportConfiguration(request,request.Epoch);
wire.assertQualifiedWireLayout();
aliases=["fixed","fixed_rank","fixed-rank-anchor","configured_fixed", ...
    "fixed_configured_rank","anchor","no_adaptation","disabled","none","off","false"];
for direction=["DL","UL"]
    cfg=sixgr.config.defaultConfig();
    cfg.phy.linkAdaptation.mode='closed_loop';
    cfg.phy.linkAdaptation.dlPolicy='baseline';
    cfg.phy.linkAdaptation.ulPolicy='baseline';
    cfg.phy.linkAdaptation.domain='cqi';
    cfg.phy.linkAdaptation.beamPolicy='adaptive';
    cfg.phy.nTxAnt=4; cfg.phy.nRxAnt=4;
    for signal=["pdsch","pusch"]
        cfg.phy.(signal).numLayers=4; cfg.phy.(signal).nLayers=4;
        cfg.phy.(signal).numAntennaPorts=4; cfg.phy.(signal).NumAntennaPorts=4;
        cfg.phy.(signal).maxLayers=4;
        cfg.phy.(signal).precoding.matrix=[];
    end
    for alias=aliases
        cfg.phy.linkAdaptation.rankPolicy=alias;
        rank=sixgr.mimo.resolveRankExecutionPolicy(cfg,direction,4);
        assert(rank.FixedRankAnchor && ~rank.AdaptiveRank && rank.EffectiveRank==4);
        good=struct('CQI',10,'RI',4,'PMI',0,'CRI',0);
        [accepted,prior]=sixgr.link.computeLinkAdaptationDecision(cfg,direction,good);
        assert(accepted.Valid && accepted.NumLayers==4 && ~accepted.RankUpdated);
        bad=good; bad.RI=1; bad.CQI=15;
        [held,after]=sixgr.link.computeLinkAdaptationDecision( ...
            cfg,direction,bad,'AdaptationState',prior);
        assert(~held.Valid && ~held.RankUpdated && ~held.PMIUpdated && ...
            ~held.CRIUpdated && held.NumLayers==4 && held.RI==1 && held.CQI==15);
        assert(string(held.RankUpdateStatus)=="held_fixed_rank_feedback_mismatch");
        assert(isequaln(prior,after),'Rejected rank-specific CSI must not change ILLA/OLLA.');
        assert(isequaln(cfg,sixgr.link.applyLinkAdaptationDecision(cfg,direction,held)));
    end
    % Installed runtime authority must win over a conflicting legacy field.
    cfg.runtime.link_adaptation.RankPolicy='fixed_rank';
    cfg.phy.linkAdaptation.rankPolicy='adaptive';
    decision=sixgr.link.computeLinkAdaptationDecision(cfg,direction,bad);
    assert(decision.NumLayers==4 && ~decision.Valid && decision.RankPolicy=="fixed_rank");
    % Exercise the shared-runtime adaptation handoff with labelled input
    % values. This is not a claim of physical CSI/SRS or UCI reception.
    state=struct('CfgMobility',cfg,'NumUsers',1,'DLSchedulers',{{}}, ...
        'ULSchedulers',{{}},'DLLinkAdaptationState',{{struct()}}, ...
        'ULLinkAdaptationState',{{struct()}},'SlotDuration_s',.001);
    report=struct('CQI',10,'RI',4,'PMI',0,'CRI',0,'SINR_dB',NaN, ...
        'SourceSlot',9,'DueSlot',10,'DeliveredSlot',10,'ServingCell',1);
    [state,report]=sixgr.truth.CoupledTruthRuntime.applyDeliveredCSIAdaptationRuntime( ...
        state,report,1,direction,struct());
    assert(~report.SchedulerSpatialDecisionDeferred);
    report.RI=1; report.CQI=15; report.SourceSlot=14;
    report.DueSlot=15; report.DeliveredSlot=15;
    [~,rejected]=sixgr.truth.CoupledTruthRuntime.applyDeliveredCSIAdaptationRuntime( ...
        state,report,1,direction,struct());
    assert(rejected.RI==1 && rejected.SchedulerSpatialDecisionDeferred && ...
        isnan(rejected.SchedulerResolvedCQI) && isnan(rejected.MCSIndex));
    if direction=="DL", assert(rejected.SchedulerAcceptedRank==4); end

    % Check the independent grant-consumer boundary as well. The inputs
    % below are explicit test feedback, not decoded over-the-air evidence.
    feedback=struct('Valid',true,'CQI',10,'RI',4,'PMI',0, ...
        'SourceSlot',3,'DeliveredSlot',4);
    future=struct('Slot',5,'RNTI',4101,'MCSIndex',0,'MCS',0, ...
        'PRBSet',0:24,'SymbolAllocation',[2 12]);
    acceptedGrant=sixgr.truth.CoupledTruthRuntime.applyMeasuredFeedbackAMCToGrantRuntime( ...
        future,feedback,[],installed,direction);
    assert(acceptedGrant.NumLayers==4 && acceptedGrant.RIUsed==4 && ...
        acceptedGrant.RankAuthority=="configured_fixed_rank_anchor");
    feedback.RI=1;
    try
        sixgr.truth.CoupledTruthRuntime.applyMeasuredFeedbackAMCToGrantRuntime( ...
            future,feedback,[],installed,direction);
        error('test:MissingFixedRankRejection','Mismatched feedback reached a fixed-rank grant.');
    catch cause
        assert(string(cause.identifier)=="sixgr:truth:FixedRankFeedbackMismatch",cause.message);
    end
    frozen=acceptedGrant; frozen.ExactPHYFeasibilityChecked=true;
    frozen.PrecodingMatrix=eye(4)/2;
    retained=sixgr.truth.CoupledTruthRuntime.applyMeasuredFeedbackAMCToGrantRuntime( ...
        frozen,feedback,[],installed,direction);
    assert(retained.NumLayers==4 && retained.PMI==frozen.PMI && ...
        isequal(retained.PrecodingMatrix,frozen.PrecodingMatrix) && ...
        retained.RankAuthority=="finalized_grant_spatial_contract");
end
fprintf('FIXED_RANK_FEEDBACK_AUTHORITY_PASS aliases=%d directions=2 rank=4 raw_RI_retained=1 temporal_state_unchanged=1\n',numel(aliases));
ok=true;
end
