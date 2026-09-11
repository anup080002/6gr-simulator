function ok=testConnectedSSBPowerAuthority()
% Explicit received-power/codec fixture; not main-run waveform evidence.
for fixture=["lls_pdcch_shared_queue_fixture.yaml","lls_pusch_shared_queue_fdd_fixture.yaml"]
    s=sixgr.lls6g.config.loadScenarioConfig(fullfile('simulator','configs','scenarios',fixture));
    cfg=sixgr.lls6g.buildInternalConfig(s,tempname);
    multi=struct('Enabled',true,'NumUsers',1,'RNTIStart',1,'ExecutionModel','slot_coupled_truth');
    state=sixgr.truth.CoupledTruthRuntime.initialize(cfg,tempname,multi,struct(),10);
    state.CurrentSlot=1; state.CurrentServingIdx(:)=1;
    state.UECommonCellConfigurationByUE={decodedSSBPowerCodecFixture(cfg,5,1,1)};
    measurement=table(0,110,"SSB-0","explicit_physical_diagnostic_fixture", ...
        1,-90,20,'VariableNames',{'ReferenceSignalId','MeasuredReferenceSignalPathloss_dB', ...
        'PathlossReferenceRS','MeasuredReferenceSignalPathlossSource','ServingCell', ...
        'SS_RSRP_dBm','ReferenceSignalTxEPRE_dBm'});
    state=sixgr.truth.CoupledTruthRuntime.publishReferenceSignalMeasurementRuntime( ...
        state,'SSB','UE',1,measurement,'ProducerSlot',1,'AvailableSlot',1,'Valid',true, ...
        'Direction','DL','SourceSignal','SSB','MeasurementSource','explicit_selector_fixture');
    state.CurrentSlot=5;
    [bound,state]=sixgr.truth.CoupledTruthRuntime.applyUserContext(cfg,state,1,'UL');
    meta=bound.lls6g.userContext;
    assert(meta.RuntimeServingPathloss_dB==95, ...
        'Connected UL must use decoded power (5) minus UE filtered RSRP (-90), not physical diagnostic loss (110).');
    assert(string(meta.RuntimeServingPathlossSource)=="ue_decoded_sib1_power_minus_filtered_ssb_rsrp");
    assert(meta.RuntimePropagationPathloss_dB==state.LargeScaleState.Pathloss_dB(1,1));
    altered=state;
    altered.ReferenceSignalMeasurementTable.Pathloss_dB(:)=777;
    altered.ReferenceSignalMeasurementTable.ReferenceSignalTxEPRE_dBm(:)=999;
    altered.ReferenceSignalMeasurementTable.RSRP_dBm(:)=-140;
    [bound,~]=sixgr.truth.CoupledTruthRuntime.applyUserContext(cfg,altered,1,'UL');
    assert(bound.lls6g.userContext.RuntimeServingPathloss_dB==95);
    % A future transmission slot is not a future-information entitlement.
    future=state; future.RuntimeViewMode="future_ul_grant_planning";
    future.PlanningDecisionSlot=5; future.CurrentSlot=9;
    future.UECommonCellConfigurationByUE{1}.AvailableSlot=7;
    [bound,~]=sixgr.truth.CoupledTruthRuntime.applyUserContext(cfg,future,1,'UL');
    assert(isnan(bound.lls6g.userContext.RuntimeServingPathloss_dB), ...
        'SIB1 delivered after the planning decision must not affect a queued grant.');
    future.UECommonCellConfigurationByUE{1}.AvailableSlot=1;
    future.ReferenceSignalMeasurementTable.AvailableSlot(:)=7;
    [bound,~]=sixgr.truth.CoupledTruthRuntime.applyUserContext(cfg,future,1,'UL');
    assert(isnan(bound.lls6g.userContext.RuntimeServingPathloss_dB));
    missing=state; missing.UECommonCellConfigurationByUE={struct()};
    [bound,~]=sixgr.truth.CoupledTruthRuntime.applyUserContext(cfg,missing,1,'UL');
    assert(isnan(bound.lls6g.userContext.RuntimeServingPathloss_dB), ...
        'Missing decoded authority must clear the estimate, not reuse model pathloss.');
end
ok=true; disp('CONNECTED_SSB_POWER_AUTHORITY_PASS: TDD/FDD decoded power, filtered RSRP, physical separation and planning knowledge guards.');
end
