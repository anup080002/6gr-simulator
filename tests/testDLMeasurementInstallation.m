function ok=testDLMeasurementInstallation()
% Actual shared clock/owner and public reducers; acquisition and CSI/TRS
% receiver values are DECLARED boundary inputs, not on-air reception proof.
% Two original idle RF/channel slots advance the clock; no RS RX runs.
setup6GRSimToolkit('Verbose',false);
prior=rng; cleanup=onCleanup(@()rng(prior)); %#ok<NASGU>
s=sixgr.lls6g.config.loadScenarioConfig( ...
    'simulator/configs/scenarios/lls_tdd_5mhz_rank2_4tx2rx_awgn_m10db.yaml');
folder=fullfile(pwd,'results','validation','dl_measurement_installation', ...
    char(java.util.UUID.randomUUID())); mkdir(folder);
cfg=sixgr.lls6g.buildInternalConfig(s,folder); cfg.run.rootRunFolder=folder;
cfg=sixgr.truth.bindStandaloneSNRPoint(cfg,-10);
cfg.outputs.continuousRawIQCaptureEnabled=false;
multi=struct('Enabled',true,'NumUsers',1,'RNTIStart',1,'ExecutionModel','slot_coupled_truth');
state=sixgr.truth.CoupledTruthRuntime.initialize(cfg,folder,multi,struct(),12);
state.ControlGating.PBCHRequired=true; % Explicit cold-acquisition test boundary.
state.CellAcquisitionState(:)="searching"; state.CurrentServingIdx(:)=1;
state=sixgr.truth.CoupledTruthRuntime.startSlot(state,cfg,'DL',1,1,1,12,-10);
[state,owner]=sixgr.truth.CoupledWaveformStream.initialize(state,cfg,{cfg});
[state,completed]=owner.advanceSlot(state,cfg);
assert(isempty(completed));
state=sixgr.truth.CoupledTruthRuntime.startSlot(state,cfg,'DL',1,1,2,12,-10);
fs=owner.SampleRateHz; n=owner.Events.NextSampleIndex;
assert(n>0 && n==fs*state.SlotDuration_s && isempty(owner.Pending));
[bound,~]=sixgr.truth.CoupledTruthRuntime.applyUserContext(cfg,state,1,'DL');
assert(sixgr.truth.DLMeasurementInstallation.required(state));
[eligible,status]=sixgr.truth.DLMeasurementInstallation.current(state,1,"CSI-RS");
assert(~eligible && status=="awaiting_received_DL_acquisition_and_configuration");

% Same original reducer APIs as the callbacks: early measured diagnostics
% are retained, but cannot publish valid scheduling/tracking evidence.
early=measurement(state,0,n,"CSI-RS");
early=sixgr.truth.DLMeasurementInstallation.stamp(state,early,bound,1,"CSI-RS");
assert(~early.DLMeasurementAuthorityEligible && early.DLMeasurementAuthorityRequired);
before=state; random=rng;
state=sixgr.truth.CoupledTruthRuntime.applyCSIRSTrial(state,1,early);
assert(isequaln(state.ControlTrials.CSIRS,early) && ...
    ~any(state.ReferenceSignalMeasurementTable.Valid) && isempty(state.PendingCSITable));
assert(isequaln(state.LatestDLFeedback,before.LatestDLFeedback) && isequal(random,rng));
earlyTRS=measurement(state,0,n,"TRS");
earlyTRS=sixgr.truth.DLMeasurementInstallation.stamp(state,earlyTRS,bound,1,"TRS");
state=deliverTRS(state,earlyTRS,bound);
assert(isequaln(state.ReceiverTrackingStateByCell,before.ReceiverTrackingStateByCell) && ...
    isequaln(state.ReceiverTrackingTraceTable,before.ReceiverTrackingTraceTable) && ...
    ~isfield(state,'TRSActiveReceiverUE') && ~any(state.ReferenceSignalMeasurementTable.Valid));
reject(@()sixgr.truth.CoupledTruthRuntime.enqueueCSIReportRuntime( ...
    state,1,'DL',table(1,'VariableNames',{'Slot'}),bound,early), ...
    'sixgr:truth:CSIReportBeforeMeasurementInstallation');
groups=1;

% Original SIB1 codec tree, with a declared received timing/acquisition
% boundary. The receipt must never claim this is decoded dedicated RRC.
tree=sixgr.rrc.asn1.buildBCCHDLSCHMessage(cfg);
decoded=sixgr.rrc.asn1.decodeSIB1UPER(sixgr.rrc.asn1.encodeSIB1UPER(tree));
decodedCommon=sixgr.mac.ra.installDecodedSIB1RACHConfig(struct(),decoded);
common=decodedCommon.UECommonCellConfiguration;
common.ServingCell=1; common.AvailableSlot=2;
common.ConfigurationEpoch=cfg.initial_access.configuration_epoch;
common.ReceivedDLTimingReference=struct('Source',"received_SSB_timing_and_decoded_BCH", ...
    'SampleRateHz',fs,'ObservationStartSample',0,'AvailableAtSample',n, ...
    'NCellID',bound.phy.carrier.NCellID,'SSBIndex',0,'ReceivedSFN',0, ...
    'ReceivedHalfFrame',0,'DLPhaseOffsetSamples',0);
state.UECommonCellConfigurationByUE={common};
reject(@()sixgr.truth.DLMeasurementInstallation.install(state,1,bound), ...
    'sixgr:truth:DLMeasurementAcquisitionRequired');
state.CellAcquisitionState(:)="acquired"; state.LastSuccessfulPBCHSlotByUE(:)=2;
tags=sixgr.util.structGet(state,'ConnectedULTimingByUE',{});
assert(isempty(tags) || all(cellfun(@isempty,tags)), ...
    'No UL timing advance is needed to install DL measurement authority.');
for defect=["future","cell","source","rate","pci"]
    bad=state;
    switch defect
        case "future", bad.UECommonCellConfigurationByUE{1}.ReceivedDLTimingReference.AvailableAtSample=n+1;
        case "cell", bad.UECommonCellConfigurationByUE{1}.ServingCell=2;
        case "source", bad.UECommonCellConfigurationByUE{1}.Source="configured_sib1";
        case "rate", bad.UECommonCellConfigurationByUE{1}.ReceivedDLTimingReference.SampleRateHz=fs/2;
        case "pci", bad.UECommonCellConfigurationByUE{1}.ReceivedDLTimingReference.NCellID=mod(bound.phy.carrier.NCellID+1,1008);
    end
    id='sixgr:truth:DLMeasurementAcquisitionRequired';
    if defect=="future", id='sixgr:truth:DLMeasurementInstallationFuture'; end
    reject(@()sixgr.truth.DLMeasurementInstallation.install(bad,1,bound),id);
end
state=sixgr.truth.DLMeasurementInstallation.install(state,1,bound);
installed=state.PreconfiguredDLMeasurementInstallationByUE{1};
assert(installed.EffectiveSample==n && installed.EffectiveSlot==2 && ...
    ~installed.DecodedDedicatedRRC && installed.Source== ...
    "preconfigured_LLS_higher_layer_after_received_DL_acquisition");
again=sixgr.truth.DLMeasurementInstallation.install(state,1,bound);
assert(isequaln(again.PreconfiguredDLMeasurementInstallationByUE, ...
    state.PreconfiguredDLMeasurementInstallationByUE));
early=sixgr.truth.DLMeasurementInstallation.stamp(state,early,bound,1,"CSI-RS");
assert(~early.DLMeasurementAuthorityEligible && early.DLMeasurementAuthorityStatus== ...
    "diagnostic_observation_started_before_configuration_installation");
groups=groups+1;

% A later original physical clock permits a later declared observation.
[state,completed]=owner.advanceSlot(state,cfg); assert(isempty(completed));
state=sixgr.truth.CoupledTruthRuntime.startSlot(state,cfg,'DL',1,1,3,12,-10);
assert(owner.Events.NextSampleIndex==2*n);
late=measurement(state,n,2*n,"CSI-RS");
late=sixgr.truth.DLMeasurementInstallation.stamp(state,late,bound,1,"CSI-RS");
assert(late.DLMeasurementAuthorityEligible && late.DLMeasurementAuthorityStatus== ...
    "post_installation_original_received_measurement");
state=sixgr.truth.CoupledTruthRuntime.applyCSIRSTrial(state,1,late);
assert(height(state.ControlTrials.CSIRS)==2 && state.ReferenceSignalMeasurementTable.Valid(end));
lateTRS=measurement(state,n,2*n,"TRS");
lateTRS=sixgr.truth.DLMeasurementInstallation.stamp(state,lateTRS,bound,1,"TRS");
state=deliverTRS(state,lateTRS,bound);
ctx=sixgr.truth.CoupledTruthRuntime.resolveTRSRuntimeContextRuntime(state,bound,1,1);
assert(ctx.TRSProcessed && ctx.TrackingEligibility && ctx.TRSCFOEstimateAvailable && ...
    ctx.TRSEstimatedCFO_Hz==23 && ~isfield(state,'TRSActiveReceiverUE'));
tracking=state.ReceiverTrackingStateByCell; trace=state.ReceiverTrackingTraceTable;
for field=["DLMeasurementConfigurationFamily","DLMeasurementConfigurationSHA256", ...
        "DLMeasurementNCellID","DLMeasurementInstallationSHA256", ...
        "DLMeasurementAuthorityRequired","DLMeasurementAuthorityEligible", ...
        "DLMeasurementAuthorityStatus","DLMeasurementAuthoritySource"]
    assert(isequal(trace.(field)(end,:),lateTRS.(field)), ...
        'test:TrackingAuthorityProjection','Tracking trace must retain original %s.',field);
end
% A delayed old diagnostic must not invalidate the latest authorized state.
state=deliverTRS(state,earlyTRS,bound);
assert(isequaln(state.ReceiverTrackingStateByCell,tracking) && ...
    isequaln(state.ReceiverTrackingTraceTable,trace));
groups=groups+1;

for defect=["missing_binding","wrong_epoch","wrong_cell","wrong_pci","changed_sequence", ...
        "changed_report","future_result","old_installation"]
    bad=late;
    switch defect
        case "missing_binding", bad(:,{'DLMeasurementInstallationSHA256'})=[];
        case "wrong_epoch", bad.MeasurementClockEpoch=bad.MeasurementClockEpoch+1;
        case "wrong_cell", bad.ServingCell=2;
        case "wrong_pci", bad.DLMeasurementNCellID=mod(bad.DLMeasurementNCellID+1,1008);
        case "changed_sequence"
            altered=bound; altered.reference_signals.csi_rs_scrambling_id=mod(bound.reference_signals.csi_rs_scrambling_id+1,1024);
            bad=sixgr.truth.DLMeasurementInstallation.stamp(state,bad,altered,1,"CSI-RS");
        case "changed_report"
            altered=bound; altered.phy.csi.reportConfigurationEpoch=altered.phy.csi.reportConfigurationEpoch+1;
            bad=sixgr.truth.DLMeasurementInstallation.stamp(state,bad,altered,1,"CSI-RS");
        case "future_result", bad.ResultAvailableAtSample=2*n+1;
        case "old_installation", bad.DLMeasurementInstallationSHA256="old-installation";
    end
    [accepted,~]=sixgr.truth.DLMeasurementInstallation.eligible(state,1,bad,"CSI-RS");
    assert(~accepted,'test:AuthorityBypass','Unexpected acceptance: %s',defect);
end
bad=late; bad.DLMeasurementNCellID=char(bound.phy.carrier.NCellID);
reject(@()sixgr.truth.DLMeasurementInstallation.eligible(state,1,bad,"CSI-RS"), ...
    'sixgr:truth:DLMeasurementIdentity');
badState=state; badState.PreconfiguredDLMeasurementInstallationByUE{1}.DecodedDedicatedRRC=0;
reject(@()sixgr.truth.DLMeasurementInstallation.current(badState,1,"CSI-RS"), ...
    'sixgr:truth:DLMeasurementInstallationIntegrity');
groups=groups+1;

% Current config and original acquisition identity, not an editable row
% Eligible flag, control reuse. A same-cell reacquisition has a new bound.
for defect=["resource","report","common_source","acquisition","cell"]
    bad=state;
    switch defect
        case "resource", bad.CfgMobility.phy.csirs.resourceIDs=bad.CfgMobility.phy.csirs.resourceIDs+1;
        case "report", bad.CfgMobility.phy.csi.reportConfigurationEpoch=bad.CfgMobility.phy.csi.reportConfigurationEpoch+1;
        case "common_source", bad.UECommonCellConfigurationByUE{1}.Source="configured_sib1";
        case "acquisition", bad.UECommonCellConfigurationByUE{1}.ReceivedDLTimingReference.ObservationStartSample=1;
        case "cell", bad.CurrentServingIdx(1)=2;
    end
    [accepted,~]=sixgr.truth.DLMeasurementInstallation.eligible(bad,1,late,"CSI-RS");
    assert(~accepted);
end
changed=state; changed.CfgMobility.phy.trs.period_slots= ...
    sixgr.util.structGet(changed.CfgMobility,'phy.trs.period_slots',1)+1;
blocked=sixgr.truth.CoupledTruthRuntime.resolveTRSRuntimeContextRuntime(changed,changed.CfgMobility,1,1);
assert(~blocked.TrackingEligibility && ~blocked.TRSCFOEstimateAvailable && ...
    ~blocked.TRSTimingEstimateAvailable && isnan(blocked.TRSEstimatedCFO_Hz) && ...
    isequaln(changed.ReceiverTrackingStateByCell,tracking));
reacquired=state;
reacquired.UECommonCellConfigurationByUE{1}.ReceivedDLTimingReference.ObservationStartSample=n;
reacquired.UECommonCellConfigurationByUE{1}.ReceivedDLTimingReference.AvailableAtSample=2*n;
reacquired.UECommonCellConfigurationByUE{1}.AvailableSlot=3;
reacquired.LastSuccessfulPBCHSlotByUE(1)=3;
reacquired=sixgr.truth.DLMeasurementInstallation.install(reacquired,1,bound);
assert(reacquired.PreconfiguredDLMeasurementInstallationByUE{1}.EffectiveSample==2*n && ...
    reacquired.PreconfiguredDLMeasurementInstallationByUE{1}.SHA256~=installed.SHA256);
[accepted,~]=sixgr.truth.DLMeasurementInstallation.eligible(reacquired,1,late,"CSI-RS");
assert(~accepted && ~sixgr.truth.DLMeasurementInstallation.trackingCurrent(reacquired,1));
% Standalone preconfigured component scope remains distinct and unchanged.
standalone=rmfield(state,'SharedWaveformStream');
[accepted,scope]=sixgr.truth.DLMeasurementInstallation.eligible(standalone,1,early,"CSI-RS");
assert(accepted && scope=="standalone_preconfigured_boundary_not_shared_acquisition");
groups=groups+1;
sixgr.util.csvWriteTable(fullfile(folder,'declared_CSI_authority_rows.csv'),state.ControlTrials.CSIRS,'PreserveSchema',true);
evidence=struct('Scope',"declared_receiver_and_acquisition_boundaries_on_actual_shared_idle_clock", ...
    'IdlePhysicalSlots',2,'CSIReceiverExecutions',0,'TRSReceiverExecutions',0, ...
    'OnAirAcquisitionQualified',false,'DecodedDedicatedRRC',false,'Groups',groups);
save(fullfile(folder,'authority_evidence.mat'),'evidence','installed','late','early','ctx');
fprintf('DL_MEASUREMENT_INSTALLATION_PASS groups=%d idle_slots=2 RS_RX=0 full_access=0 folder=%s\n',groups,folder);
ok=true;
end

function row=measurement(state,first,last,family)
owner=state.SharedWaveformStream; fs=owner.SampleRateHz;
row=table(1,1,ceil((first+1)/(fs*state.SlotDuration_s)),first,last,fs, ...
    double(owner.Physical.ConfigurationEpoch),'VariableNames', ...
    {'UEIndex','ServingCell','Slot','ObservationStartSample','ObservationEndSampleExclusive', ...
    'ObservationSampleRateHz','MeasurementClockEpoch'});
if family=="CSI-RS"
    for name=["Transmitted","Observed","Consumed","ResourceExtractionAvailable", ...
            "ChannelEstimateAvailable","CSIMeasurementAvailable"], row.(name)=true; end
    row.MeasurementSource="declared_received_boundary_for_authority_test";
    row.CQI=10; row.RI=1; row.PMI=0; row.CRI=0; row.LI=0; row.SINR_dB=12;
    row.ObservationDeliverySlot=double(state.CurrentSlot);
    row=sixgr.truth.bindDeliveredReferenceClock(state,row);
else
    row.Frame=1; row.Status="PASS"; row.EstimatedDopplerHz=0; row.NMSE_dB=-18;
    row.DetectionMetric=.99;
    for name=["DetectionAttempted","DetectionSuccess","TimingTrackingAttempted", ...
            "TRSTimingEstimateUsable","TRSTimingEstimateAvailable","FrequencyTrackingAttempted", ...
            "TRSCFOEstimateUsable","TRSCFOEstimateAvailable","ChannelEstimationAttempted", ...
            "TRSChannelEstimateAvailable","TRSRuntimeEvidenceUsable","StrictOk"], row.(name)=true; end
    row.EstimatedTimingOffset_samples=2; row.EstimatedCFO_Hz=23;
    row.EstimatedCommonFrequency_Hz=23; row.EstimatedOscillatorCFO_Hz=NaN;
    row.FrequencyEstimateDomain="received_TRS_common_phase_frequency"; row.UsedOracleFields="";
    row.ObservationCompletionTime_s=last/fs;
    row.ObservationCoverageSource="complete_contiguous_received_sample_buffer";
end
end

function state=deliverTRS(state,row,cfg)
state=sixgr.truth.TRSResultDelivery.enqueue(state,1,1,row,cfg,table());
[state,ready]=sixgr.truth.TRSResultDelivery.takeAvailable(state);
assert(isscalar(ready));
state=sixgr.truth.CoupledTruthRuntime.applyTRSTrial(state,1,ready.Trial);
end

function reject(f,id)
try, f(); catch err
    assert(strcmp(err.identifier,id),'Expected %s; got %s: %s',id,err.identifier,err.message); return;
end
error('test:MissingError','Expected %s.',id);
end
