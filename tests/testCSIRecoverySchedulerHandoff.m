function ok=testCSIRecoverySchedulerHandoff()
% Delivered-value fixture through the actual ILLA/report adapter and MAC.
% This is not a physical CSI decoding/low-SNR qualification campaign.
setup6GRSimToolkit('Verbose',false);
cfg=sixgr.config.defaultConfig();
cfg.phy.linkAdaptation.mode='amc';
cfg.phy.linkAdaptation.dlPolicy='baseline';
cfg.phy.linkAdaptation.rankPolicy='baseline';
cfg.phy.linkAdaptation.beamPolicy='baseline';
cfg.phy.linkAdaptation.domain='cqi';
cfg.phy.linkAdaptation.innerLoopFlag=true;
cfg.phy.linkAdaptation.cqiSmoothingMode='fixed';
cfg.phy.linkAdaptation.cqiSmoothingAlpha=.5;
cfg.phy.linkAdaptation.outageRecoveryPositiveCQIReports=2;
cfg.phy.linkAdaptation.outageRecoveryCQITolerance=1;
cfg.phy.linkAdaptation.outageRecoveryMaxGapSlots=5;
% The target scenario permits pre-feedback bootstrap. That permission must
% not reopen bootstrap after a real outage/recovery decision was received.
cfg.phy.linkAdaptation.bootstrapCQIMode='conservative';
scheduler=sixgr.l2.mac.SchedulerPF(cfg,'Direction','DL');
[~,~,~,bootstrap]=scheduler.selectAMC(struct('RNTI',1,'CQI',NaN, ...
    'RI',1,'CausalFeedbackUsable',false,'CausalFeedbackStatus','missing_runtime_cqi'));
assert(isfinite(bootstrap.MCSIndex) && ...
    string(bootstrap.Mode)=="bootstrap_cqi_conservative", ...
    'The repair must preserve explicitly configured pre-feedback bootstrap.');
state=struct('CfgMobility',cfg,'NumUsers',1,'DLSchedulers',{{scheduler}}, ...
    'ULSchedulers',{{}},'DLLinkAdaptationState',{{struct()}}, ...
    'ULLinkAdaptationState',{{struct()}},'SlotDuration_s',.001);
for event=1:4
    cqis=[0 10 13 13]; slots=[24 29 44 49];
    report=struct('CQI',cqis(event),'RI',1,'PMI',0,'CRI',0,'SINR_dB',NaN, ...
        'SourceSlot',slots(event)-1,'DueSlot',slots(event),'DeliveredSlot',slots(event), ...
        'ServingCell',1,'SINRSource','not_reported_in_CSI_payload', ...
        'SINRValueRole','unavailable_not_a_received_SINR_measurement', ...
        'SINRValueStatus','NA_not_reported');
    [state,adapted]=sixgr.truth.CoupledTruthRuntime.applyDeliveredCSIAdaptationRuntime( ...
        state,report,1,'DL',struct());
    assert(adapted.CQI==cqis(event),'Raw received CQI must not be rewritten.');
    ue=struct('RNTI',1,'CQI',adapted.SchedulerResolvedCQI, ...
        'RI',1,'CausalFeedbackUsable',~adapted.CQIOutageRecoveryPending, ...
        'CausalFeedbackStatus',adapted.LinkAdaptationDecisionReason,'CSIAgeSlots',1);
    [~,~,~,amc]=scheduler.selectAMC(ue);
    if event==1
        assert(adapted.SchedulerResolvedCQI==0 && ~isfinite(amc.MCSIndex));
    elseif event<4
        assert(adapted.CQIOutageRecoveryPending && ...
            adapted.CQIOutageRecoveryResolvedCQI>0 && isnan(adapted.SchedulerResolvedCQI), ...
            'Pending recovery CQI is diagnostic, not scheduler authority.');
        assert(~isfinite(amc.MCSIndex),'The scheduler must not bypass pending CSI recovery.');
        for age=[1 1000]
            rejectedUE=ue;
            rejectedUE.CSIAgeSlots=age;
            rejectedUE.CQI=13; % A diagnostic/raw value cannot override admission.
            rejectedUE.CausalFeedbackUsable=true;
            plan=scheduler.buildNewDataGrantPlan(rejectedUE,0:23,[2 12],4000);
            assert(~plan.Valid && plan.TBSBits==0 && ...
                string(plan.GrantBlocker)=="blocked_cqi_outage_recovery_filter", ...
                'Recovery admission must survive raw-CQI and age handling.');
        end
    else
        assert(~adapted.CQIOutageRecoveryPending && isfinite(adapted.SchedulerResolvedCQI) && ...
            isfinite(amc.MCSIndex),'A timely consistent recovery pair must permit scheduling.');
    end
end
[rejected,~]=sixgr.link.computeLinkAdaptationDecision(cfg,'DL', ...
    struct('CQI',10,'RI',2,'PMI',1,'CRI',0,'CausalFeedbackUsable',false));
assert(~rejected.Valid && ~rejected.PMIUpdated && ~rejected.CRIUpdated && ~rejected.RankUpdated, ...
    'Spatial updates must not turn unusable feedback into a valid operating point.');
fprintf('CSI_RECOVERY_SCHEDULER_HANDOFF_PASS events=4 blocked_isolated_and_gap=1 recovered_pair=1\n');
ok=true;
end
