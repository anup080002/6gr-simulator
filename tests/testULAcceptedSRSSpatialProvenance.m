function ok=testULAcceptedSRSSpatialProvenance()
% Authored SRS delivery -> normal reducer -> UE state -> PF/RR freeze/TX.
% No received SRS/PDCCH, access, BLER, SRI-occasion or n40 qualification.
setup6GRSimToolkit('Verbose',false);
scenario=sixgr.lls6g.config.loadScenarioConfig( ...
    'simulator/configs/scenarios/h4_100_cdlc100_connected_impaired_40db_gate.yaml');
cfg=sixgr.lls6g.buildInternalConfig(scenario,tempname);
assert(cfg.phy.linkAdaptation.rankIncreaseConfirmationReports==2);
multi=struct('Enabled',true,'NumUsers',1,'RNTIStart',701, ...
    'ExecutionModel','slot_coupled_truth');
state=sixgr.truth.CoupledTruthRuntime.initialize(cfg,tempname,multi,struct(),8);
state.CurrentServingIdx(:)=1;
[probe,timing]=legalTiming(cfg,state.ControlGating.SRSMaxAgeSlots);
control0=double(timing.ControlAbsoluteSlot);
sourceA=control0; sourceB=control0+1;
state.CurrentSlot=sourceA; state.CurrentCanonicalSlot=sourceA;
state=sixgr.truth.CoupledTruthRuntime.applySRSTrial(state,1,declaredSRS(1,sourceA));
first=state.LatestULFeedback(1);
A=first.AcceptedSRSSpatialDecision;
assert(A.RI==1 && A.PMI==0 && A.ProducerSlot==sourceA && A.AvailableSlot==sourceA);
state.CurrentSlot=sourceB; state.CurrentCanonicalSlot=sourceB;
state=sixgr.truth.CoupledTruthRuntime.applySRSTrial(state,1,declaredSRS(2,sourceB));
assert(isequaln(state.LatestULFeedback(1),first), ...
    'Held rank B must not relabel the admitted tuple A or its clocks.');
assert(state.LastSuccessfulSRSSlotByUE(1)==sourceB);
raw=state.ReferenceSignalMeasurementTable;
B=raw(raw.SignalType=="SRS" & raw.ProducerSlot==sourceB,:);
assert(height(B)==1 && B.Valid && B.RI==2 && string(B.MeasurementId)~=string(A.MeasurementId));
plan=state;
plan.CurrentSlot=double(timing.DataAbsoluteSlot)+1;
plan.CurrentCanonicalSlot=plan.CurrentSlot;
plan.RuntimeViewMode='future_ul_grant_planning'; plan.PlanningDecisionSlot=control0+1;
[~,ue]=sixgr.truth.CoupledTruthRuntime.buildSchedulerUEStateRuntime(plan,cfg,1,'UL',1);
assert(ue.RI==1 && ue.TPMI==0 && ue.SRSCausalUsable && ue.AcceptedSRSCausalUsable && ...
    string(ue.SRSCausalMeasurementId)==string(B.MeasurementId) && ...
    isequaln(ue.AcceptedSRSSpatialDecision,A) && ...
    ue.AcceptedSRSCausalAgeSlots==plan.CurrentSlot-sourceA && ...
    ue.AcceptedSRSCausalAgeSlots==ue.SRSCausalAgeSlots+1);
% This boundary does not override initial-access/admission gates. It uses
% the real metadata attachment and exact freeze APIs on an explicit grant.
for kind=["PF","RR"]
    constructor=str2func("sixgr.l2.mac.Scheduler"+kind);
    scheduler=constructor(cfg,'Direction','UL');
    grant=probe;
    grant.RNTI=ue.RNTI; grant.UEIndex=1; grant.ServingCell=1;
    grant.PRBSet=0:11; grant.NumLayers=ue.RI; grant.RI=ue.RI;
    grant.Modulation=ue.Modulation; grant.TargetCodeRate=ue.TargetCodeRate;
    grant.MCSIndex=ue.MCSIndex; grant.MCS=ue.MCSIndex;
    grant.HARQ=struct('HarqID',0,'NDI',true,'RV',0,'IsRetransmission',false);
    grant=scheduler.attachULSRSAuthorityToGrant(grant,ue);
    g=scheduler.freezePHYGrantForGrant(grant);
    assert(g.ExactPHYFeasible && g.PHYGrant.IsFrozen);
    p=g.PHYGrant.PrecodingState;
    assert(string(p.SRSMeasurementID)==string(A.MeasurementId) && ...
        p.SRSMeasurementSlot==sourceA && p.TPMI==A.PMI && ...
        isequaln(p.AcceptedSRSSpatialDecision,A) && ...
        string(g.SRSCausalMeasurementId)==string(B.MeasurementId));
    [~,txInfo]=sixgr.phy.ul.PUSCH_Tx(cfg,'PHYGrant',g.PHYGrant,'CompactOutput',true);
    assert(string(txInfo.Precoding.SRSMeasurementID)==string(A.MeasurementId) && ...
        txInfo.Precoding.SRSMeasurementSlot==sourceA && ...
        string(txInfo.Precoding.SelectedMatrixSHA256)==string(p.SelectedMatrixSHA256));
    missing=grant; missing.AcceptedSRSSpatialDecision=struct();
    throws(@()scheduler.freezePHYGrantForGrant(missing),'sixgr:mimo:MissingAcceptedSRSState');
    missing=rmfield(grant,'AcceptedSRSSpatialDecision');
    throws(@()scheduler.freezePHYGrantForGrant(missing),'sixgr:mimo:MissingAcceptedSRSState');
    bad=grant; bad.AcceptedSRSSpatialDecision.PMI=1;
    throws(@()scheduler.freezePHYGrantForGrant(bad),'sixgr:mimo:AcceptedSRSIdentityMismatch');
    future=grant; future.AcceptedSRSDecisionContext.KnownAtSlot=control0+2;
    throws(@()scheduler.freezePHYGrantForGrant(future),'sixgr:mimo:AcceptedSRSNotCausal');
    changed=ue; changed.TPMI=1; changed.AcceptedSRSSpatialDecision=struct();
    assert(isequaln(scheduler.attachULSRSAuthorityToGrant(g,changed),g));
    replay=grant; replay.HARQ.IsRetransmission=true;
    assert(isequaln(scheduler.attachULSRSAuthorityToGrant(replay,changed),replay), ...
        'A retransmission must retain its original source, TPMI and raw admission evidence.');
    counterfactual=g;
    counterfactual.AcceptedSRSSpatialDecision.MeasurementId='metadata_only_counterfactual';
    before=scheduler.buildDCIBitfield(g); after=scheduler.buildDCIBitfield(counterfactual);
    assert(~isempty(before.Bits) && isequal(before.Bits,after.Bits), ...
        'gNB estimator provenance must not add or alter over-air DCI bits.');
end
expired=state;
expired.CurrentSlot=sourceA+state.ControlGating.SRSMaxAgeSlots+1;
expired.CurrentCanonicalSlot=expired.CurrentSlot;
[~,stale]=sixgr.truth.CoupledTruthRuntime.buildSchedulerUEStateRuntime(expired,cfg,1,'UL',1);
assert(stale.SRSCausalUsable && ~stale.AcceptedSRSCausalUsable && ...
    ~stale.Active && ~stale.SchedulingEligible && isequaln(stale.AcceptedSRSSpatialDecision,A), ...
    'New raw sounding B must not renew accepted spatial A or authorize expired new data.');
future=A; future.AvailableSlot=plan.PlanningDecisionSlot+1;
result=sixgr.truth.consumeAcceptedSRSSpatialDecision(plan,future,1,ue.RNTI,1,0,cfg);
assert(~result.Usable && contains(string(result.Status),'future'));
invalid=A; invalid.AvailableSlot=invalid.ProducerSlot-1;
throws(@()sixgr.truth.consumeAcceptedSRSSpatialDecision(plan,invalid,1,ue.RNTI,1,0,cfg), ...
    'sixgr:phy:refsig:CausalMeasurementInvalidTiming');
% A distinct second rank-two report admits C, never retroactively changes A.
state.CurrentSlot=sourceB+1; state.CurrentCanonicalSlot=state.CurrentSlot;
state=sixgr.truth.CoupledTruthRuntime.applySRSTrial(state,1,declaredSRS(2,state.CurrentSlot));
C=state.LatestULFeedback(1).AcceptedSRSSpatialDecision;
assert(C.RI==2 && C.ProducerSlot==sourceB+1 && string(C.MeasurementId)~=string(A.MeasurementId));
configurationGuards(cfg,A);
spatialOnlyN40();
fprintf('UL_ACCEPTED_SRS_SPATIAL_PROVENANCE_PASS PF_RR=2 raw_B_accepted_A=1 physical_qualification=0\n');
ok=true;
end

function [grant,timing]=legalTiming(cfg,maxAge)
grant=struct('Direction','UL','SymbolAllocation',cfg.phy.pusch.symbolAllocation, ...
    'ControlSymbolAllocation',cfg.phy.pdcch.symbolAllocation,'TimingAdvanceTicks',0);
for control0=30:80
    grant.Slot=control0; grant.ControlAbsoluteSlot=control0;
    timing=sixgr.phy.frame.TimingRelationEngine.resolveProductionGrant(cfg,grant);
    if timing.Valid && double(timing.DataAbsoluteSlot)+1-control0<=maxAge, return; end
end
error('sixgr:test:MissingULFixtureTiming','Installed timing has no fresh accepted-source boundary.');
end

function configurationGuards(cfg,A)
% Explicit config/epoch boundary values, not claimed physical reception.
strict=sixgr.phy.srs.buildSRSConfigFromScenario(cfg);
A.SRSNumPorts=double(strict.ToolboxSRS.NumSRSPorts);
A.SRSConfigurationEpoch=cfg.rf.configurationEpoch;
A.SRSConfigurationContextVersion="srs_configuration_context/v1";
A.SRSConfigurationContextID=sixgr.truth.srsConfigurationContextID( ...
    cfg,A.SRSConfigurationEpoch,A.TargetId,A.ServingCell);
sixgr.truth.validateAcceptedSRSConfiguration(cfg,A);
bad=A; bad.SRSNumPorts=A.SRSNumPorts+1;
throws(@()sixgr.truth.validateAcceptedSRSConfiguration(cfg,bad),'sixgr:truth:AcceptedSRSConfigurationMismatch');
bad=A; bad.SRSConfigurationEpoch=A.SRSConfigurationEpoch+1;
throws(@()sixgr.truth.validateAcceptedSRSConfiguration(cfg,bad),'sixgr:truth:AcceptedSRSConfigurationMismatch');
bad=A; bad.SRSConfigurationContextID=""; bad.MeasurementClockDomain="shared_receiver_sample_clock/v1";
throws(@()sixgr.truth.validateAcceptedSRSConfiguration(cfg,bad),'sixgr:truth:MissingAcceptedSRSConfiguration');
changed=cfg; changed.phy.carrier.NCellID=mod(cfg.phy.carrier.NCellID+1,1008);
throws(@()sixgr.truth.validateAcceptedSRSConfiguration(changed,A),'sixgr:truth:AcceptedSRSConfigurationMismatch');
end

function row=declaredSRS(rank,slot)
row=struct('Slot',slot,'ServingCell',1,'SINR_dB',20,'WidebandCQI',10, ...
    'RIEstimate',rank,'TPMIEstimate',0,'SRSBandwidthCoverageStatus',"full_band", ...
    'SRSBandwidthFraction',272/273,'PredictedPUSCHMinimumLayerSINR_dB',20, ...
    'PredictedPUSCHPostEqSINRSource', ...
        "receiver_measured_srs_reference_power_selected_ri_tpmi_mmse_layer_prediction", ...
    'PredictedPUSCHPostEqSINRValueRole', ...
        "power_plane_calibrated_predicted_pusch_data_channel_scheduling_input", ...
    'PredictedPUSCHPostEqSINRValueStatus',"PASS", ...
    'PredictedPUSCHPostEqSINRAnchor_dB',20, ...
    'PredictedPUSCHPostEqSINRAnchorSource',"measured_ul_srs_pilot_reconstruction_sinr", ...
    'PredictedPUSCHPostEqSINRPowerReferencePlane',"receiver_srs_resource_elements_after_ofdm_demodulation", ...
    'PredictedPUSCHReferenceSignalPower',1,'PredictedPUSCHDisturbancePower',.01, ...
    'PUSCHToSRSReferenceEnergyRatio',1,'PUSCHToSRSReferenceEnergySource', ...
        "normalized_fixed_snr_unit_grid_reference_no_device_power_scaling", ...
    'DetectionAttempted',true,'DetectionSuccess',true,'ResourceExtractionAttempted',true, ...
    'ResourceExtractionAvailable',true,'ChannelEstimateAttempted',true, ...
    'SRSChannelEstimateAvailable',true,'SRSRuntimeEvidenceUsable',true, ...
    'SRSReceiveTimingOffset_samples',NaN,'Crash',false,'ProxyUsed',false);
row=struct2table(row,'AsArray',true);
end

function throws(f,id)
try, f(); catch e
    assert(string(e.identifier)==id,'Expected %s, got %s: %s',id,e.identifier,e.message); return;
end
error('sixgr:test:ExpectedFailure','Expected %s.',id);
end

function spatialOnlyN40()
% Actual producer/reducer APIs with authored slot-only receiver operands.
% Mirrors n40 SRS45 RI4/TPMI4 with no calibrated PUSCH quality; no RF claim.
s=sixgr.lls6g.config.loadScenarioConfig( ...
    'simulator/configs/scenarios/lls_tdd_n40_20mhz_64txru_4rx_cdlc100_reference_snr_sweep.yaml');
cfg=sixgr.lls6g.buildInternalConfig(s,tempname);
multi=struct('Enabled',true,'NumUsers',1,'RNTIStart',701,'ExecutionModel','slot_coupled_truth');
state=sixgr.truth.CoupledTruthRuntime.initialize(cfg,tempname,multi,struct(),20);
state=sixgr.truth.CoupledTruthRuntime.advanceFrame(state,cfg,multi,46,20);
state=sixgr.truth.CoupledTruthRuntime.startSlot(state,cfg,'DL',1,1,46,cfg.run.totalSlots,20);
state.CurrentServingIdx(:)=1;
state.LastTrafficFrameApplied=46; state.ULQueueBits(:)=8000;
% Declared access/tracking boundary, not completed access evidence.
state.ControlGating.PBCHRequired=false; state.ControlGating.PRACHRequired=false;
state.ControlGating.TRSRequired=false; state.ControlGating.SRSRequired=true;
state.ControlGating.SRSMaxAgeSlots=5;
row=declaredSRS(4,45); row.TPMIEstimate=4;
row.WidebandCQI=NaN;
row.PredictedPUSCHMinimumLayerSINR_dB=NaN;
row.PredictedPUSCHPostEqSINRValueStatus="unavailable_power_plane_calibrated_pusch_prediction";
row.PredictedPUSCHPostEqSINRSource="rejected_unanchored_srs_spatial_prediction";
row.PredictedPUSCHPostEqSINRAnchor_dB=NaN;
row.SRSBandwidthFraction=48/51;
row.SRSBandwidthCoverageStatus="within_configured_carrier_edge_tolerance";
originalRow=row;
state=sixgr.truth.CoupledTruthRuntime.applySRSTrial(state,1,row);
stored=state.LatestULFeedback(1); A=stored.AcceptedSRSSpatialDecision;
assert(~stored.Valid && isnan(stored.CQI) && isnan(stored.MCSIndex) && ...
    A.RI==4 && A.PMI==4 && isequaln(originalRow,row), ...
    'Unavailable calibrated quality must still retain the independently observed spatial tuple.');
plan=sixgr.truth.CoupledTruthRuntime.futureULPlanningView(state,50);
[~,ue]=sixgr.truth.CoupledTruthRuntime.buildSchedulerUEStateRuntime(plan,cfg,1,'UL',1);
assert(ue.Active && ue.AcceptedSRSCausalUsable && ue.RI==4 && ue.TPMI==4 && ...
    isequaln(ue.AcceptedSRSSpatialDecision,A) && ~ue.FeedbackValid && ...
    ue.SpatialDecisionSourceSlot==stored.SpatialDecisionSourceSlot && ...
    ue.SpatialDecisionDeliveredSlot==stored.SpatialDecisionDeliveredSlot && ...
    string(ue.MCSIndexAuthority)=="bootstrap_cqi_conservative_lab_default", ...
    'Quality bootstrap must preserve original accepted spatial identity/clocks, not claim measured CQI.');
assert(isequaln(plan.LatestULFeedback(1),stored),'Consumer must not rewrite the received record.');
missing=plan; missing.LatestULFeedback(1).AcceptedSRSSpatialDecision=struct();
[~,blocked]=sixgr.truth.CoupledTruthRuntime.buildSchedulerUEStateRuntime(missing,cfg,1,'UL',1);
assert(~blocked.Active && strlength(blocked.SchedulingBlockReason)>0 && ...
    contains(blocked.SchedulingBlockReason,'accepted_srs_spatial_identity_unavailable'));
expired=plan; expired.ControlGating.SRSMaxAgeSlots=4;
[~,blocked]=sixgr.truth.CoupledTruthRuntime.buildSchedulerUEStateRuntime(expired,cfg,1,'UL',1);
assert(~blocked.Active && ~blocked.AcceptedSRSCausalUsable && strlength(blocked.SchedulingBlockReason)>0);
future=plan; future.LatestULFeedback(1).AcceptedSRSSpatialDecision.AvailableSlot=47;
[~,blocked]=sixgr.truth.CoupledTruthRuntime.buildSchedulerUEStateRuntime(future,cfg,1,'UL',1);
assert(~blocked.Active && ~blocked.AcceptedSRSCausalUsable && strlength(blocked.SchedulingBlockReason)>0);
wrong=plan; wrong.LatestULFeedback(1).AcceptedSRSSpatialDecision.RNTI=A.RNTI+1;
throws(@()sixgr.truth.CoupledTruthRuntime.buildSchedulerUEStateRuntime(wrong,cfg,1,'UL',1), ...
    'sixgr:truth:AcceptedSRSSpatialIdentityMismatch');
invalid=plan; invalid.LatestULFeedback(1).AcceptedSRSSpatialDecision.Valid=false;
[~,blocked]=sixgr.truth.CoupledTruthRuntime.buildSchedulerUEStateRuntime(invalid,cfg,1,'UL',1);
assert(~blocked.Active && ~blocked.AcceptedSRSCausalUsable && strlength(blocked.SchedulingBlockReason)>0);
fprintf('N40_SPATIAL_ONLY_SRS_HANDOFF_PASS declared_receiver_boundary=1 measured_quality_unavailable=1 rank=4 tpmi=4\n');
end
