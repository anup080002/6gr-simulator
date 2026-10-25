function ok=testSSBPowerReferenceLifecycle()
% Declared measurement/common-power boundary fixtures, NOT SSB/SIB1 RX.
% The last group uses an actual shared owner/three idle slots only to prove
% sample-clock enforcement. No receiver or power-accuracy claim is made.
setup6GRSimToolkit('Verbose',false);
saved=rng; cleanup=onCleanup(@()rng(saved)); %#ok<NASGU>
checks={@retainedReference,@samePowerAndSynchronization,@changedPower, ...
    @identityAndClockGuards,@integratedAdmission,@sharedClock};
names=["retained_without_age_expiry","same_power_and_sync", ...
    "changed_power_and_delayed_input","identity_and_causality","PUCCH_SRS_admission", ...
    "original_shared_clock"];
failures=strings(0,1);
for k=1:numel(checks)
    try
        checks{k}(); fprintf('SSB_POWER_LIFECYCLE_PASS %s\n',names(k));
    catch ME
        failures(end+1)=names(k)+": "+string(getReport(ME,'extended','hyperlinks','off')); %#ok<AGROW>
        fprintf(2,'SSB_POWER_LIFECYCLE_FAIL %s: %s\n',names(k),ME.message);
    end
end
assert(isempty(failures),'test:SSBPowerReferenceLifecycle','%s',strjoin(failures,newline));
fprintf('SSB_POWER_LIFECYCLE_SCOPE declared_SSB_SIB1_inputs=1 actual_idle_slots=3 SSB_RX=0 SIB1_RX=0\n');
ok=true;
end

function [s,m,common]=fixture()
cfg=sixgr.config.defaultConfig();
cfg.initial_access.configuration_epoch=2;
cfg.initial_access.preconnection_rsrp_filter_coefficient_k=4;
cfg.initial_access.preconnection_rsrp_filter_reference_period_ms=20;
cfg.rf.frontend.ul_power_control.pathloss_reference_lifetime='retained_filtered_reference';
s=struct('CfgMobility',cfg,'NumUsers',1,'CurrentServingIdx',1,'CurrentSlot',3, ...
    'SweepPointStartSlot',1,'CellAcquisitionState',"acquired",'SlotDuration_s',.0005, ...
    'LastSuccessfulPBCHSlotByUE',3,'UECommonCellConfigurationByUE',{{}});
m=struct('SignalType',"SSB",'TargetType',"UE",'TargetId',1,'ServingCell',1, ...
    'ResourceId',0,'ProducerSlot',1,'AvailableSlot',3,'Valid',true, ...
    'MeasurementId',"declared_initial_capture",'RSRP_dBm',-80, ...
    'MeasurementClockDomain',"slot_only",'ReferenceConfigurationEpoch',2,'Direction',"DL", ...
    'MeasurementSource',"CoupledTruthRuntime.applyPBCHTrial.exact_sss_power_measurement");
common=struct('Source',"decoded_sib1",'TreeHash',"declared_decoded_common_boundary_1", ...
    'ServingCell',1,'ConfigurationEpoch',2,'AvailableSlot',3,'SSPBCHBlockPower_dBm',-20);
end

function [s,m,c]=observe(s,m)
[eligible,c]=sixgr.truth.SSBPowerReferenceLifecycle.filterContext(s,m);
assert(eligible,'test:LifecycleEligibility','Declared original input unexpectedly unavailable: %s.',c.Status);
[s,m]=sixgr.truth.filterUEReferenceMeasurement(s,m);
assert(string(m.SSBPowerReferenceGenerationSHA256)==c.GenerationSHA256);
end

function retainedReference()
[s,m,common]=fixture(); before=m; random=rng;
[s,m,c]=observe(s,m);
assert(c.Status=="provisional_original_acquisition_capture");
[s,r]=sixgr.truth.SSBPowerReferenceLifecycle.install(s,1,common);
s.UECommonCellConfigurationByUE={common};
assert(r.GenerationSHA256==c.GenerationSHA256 && ~r.AgeExpiryApplied);
T=struct2table(m,'AsArray',true); original=T; filters=s.UEReferenceRSRPFilters;
for slot=[3 23 42 62 81 103]
    s.CurrentSlot=slot;
    [chosen,status]=sixgr.truth.SSBPowerReferenceLifecycle.select(s,s.CfgMobility,1,0,T);
    assert(isequaln(chosen,original) && status=="retained_filtered_reference_available");
end
assert(isequaln(s.UEReferenceRSRPFilters,filters) && m.RSRP_dBm==before.RSRP_dBm && ...
    m.MeasurementId==before.MeasurementId && m.AvailableSlot==before.AvailableSlot && isequal(random,rng));
end

function samePowerAndSynchronization()
[s,m,common]=fixture(); [s,m]=observe(s,m);
[s,first]=sixgr.truth.SSBPowerReferenceLifecycle.install(s,1,common);
s.CurrentSlot=43; common.AvailableSlot=43; common.TreeHash="unrelated_SIB1_content_changed";
before=s.UEReferenceRSRPFilters;
[s,again]=sixgr.truth.SSBPowerReferenceLifecycle.install(s,1,common);
s.UECommonCellConfigurationByUE={common};
assert(isequaln(first,again) && isequaln(before,s.UEReferenceRSRPFilters));
T=struct2table(m,'AsArray',true);
s.CellAcquisitionState="failed";
[chosen,status]=sixgr.truth.SSBPowerReferenceLifecycle.select(s,s.CfgMobility,1,0,T);
assert(isempty(chosen) && status=="serving_reference_not_synchronized");
s.CellAcquisitionState="acquired"; s.LastSuccessfulPBCHSlotByUE=43;
[chosen,~]=sixgr.truth.SSBPowerReferenceLifecycle.select(s,s.CfgMobility,1,0,T);
assert(isequaln(chosen,T) && isequaln(before,s.UEReferenceRSRPFilters), ...
    'Same-cell reacquisition alone is not a reference-power/filter reset.');
end

function changedPower()
[s,m,common]=fixture(); [s,m]=observe(s,m);
[s,old]=sixgr.truth.SSBPowerReferenceLifecycle.install(s,1,common);
oldFilters=s.UEReferenceRSRPFilters; original=m;
s.CurrentSlot=50; common.AvailableSlot=50; common.SSPBCHBlockPower_dBm=-10;
[s,new]=sixgr.truth.SSBPowerReferenceLifecycle.install(s,1,common);
s.UECommonCellConfigurationByUE={common};
assert(new.GenerationSHA256~=old.GenerationSHA256 && new.MinimumObservationStart==50 && ...
    isequaln(s.UEReferenceRSRPFilters,oldFilters));
[chosen,~]=sixgr.truth.SSBPowerReferenceLifecycle.select(s,s.CfgMobility,1,0,struct2table(m,'AsArray',true));
assert(isempty(chosen));
s.CurrentSlot=51; late=m; late.ProducerSlot=49; late.AvailableSlot=51; late.MeasurementId="delayed_old_capture";
[eligible,c]=sixgr.truth.SSBPowerReferenceLifecycle.filterContext(s,late);
assert(~eligible && c.Status=="observation_precedes_reference_power_generation");
fresh=m; fresh.ProducerSlot=50; fresh.AvailableSlot=51;
fresh.MeasurementId="declared_new_power_capture"; fresh.RSRP_dBm=-67;
[s,fresh]=observe(s,fresh);
assert(fresh.UERSRPFilterUpdateCount==1 && fresh.UEFilteredRSRP_dBm==-67 && isequaln(m,original));
[chosen,~]=sixgr.truth.SSBPowerReferenceLifecycle.select(s,s.CfgMobility,1,0,struct2table(fresh,'AsArray',true));
assert(height(chosen)==1 && chosen.SSBPowerReferenceGenerationSHA256==new.GenerationSHA256);
end

function identityAndClockGuards()
[s,m,common]=fixture(); [s,m]=observe(s,m);
s=sixgr.truth.SSBPowerReferenceLifecycle.install(s,1,common); s.UECommonCellConfigurationByUE={common};
T=struct2table(m,'AsArray',true);
for kind=["cell","epoch","filter","sweep","carrier","pci"]
    bad=s;
    switch kind
        case "cell", bad.CurrentServingIdx=2;
        case "epoch", bad.CfgMobility.initial_access.configuration_epoch=3;
        case "filter", bad.CfgMobility.initial_access.preconnection_rsrp_filter_coefficient_k=0;
        case "sweep", bad.SweepPointStartSlot=2;
        case "carrier", bad.CfgMobility.phy.carrier.NSizeGrid=mod(bad.CfgMobility.phy.carrier.NSizeGrid,275)+1;
        case "pci", bad.CfgMobility.phy.carrier.NCellID=mod(bad.CfgMobility.phy.carrier.NCellID+1,1008);
    end
    [chosen,~]=sixgr.truth.SSBPowerReferenceLifecycle.select(bad,bad.CfgMobility,1,0,T);
    assert(isempty(chosen),'Changed reference context cannot relabel old filtered inputs.');
end
bad=m; bad.AvailableSlot=4;
[eligible,~]=sixgr.truth.SSBPowerReferenceLifecycle.filterContext(s,bad); assert(~eligible);
bad=m; bad.TargetId=char(1);
reject(@()sixgr.truth.SSBPowerReferenceLifecycle.filterContext(s,bad),'sixgr:truth:SSBPowerLifecycleIdentity');
badCommon=common; badCommon.SSPBCHBlockPower_dBm='0';
reject(@()sixgr.truth.SSBPowerReferenceLifecycle.install(s,1,badCommon),'sixgr:truth:SSBPowerLifecycleIdentity');
badCommon=common; badCommon.AvailableSlot=4;
reject(@()sixgr.truth.SSBPowerReferenceLifecycle.install(s,1,badCommon),'sixgr:truth:SSBPowerLifecycleCommon');
bad=s; bad.SSBPowerReferenceLifecycleByUE{1}.ReferencePower_dBm=-19;
reject(@()sixgr.truth.SSBPowerReferenceLifecycle.select(bad,bad.CfgMobility,1,0,T),'sixgr:truth:SSBPowerLifecycleIntegrity');
bad=m; bad.MeasurementClockDomain="shared_receiver_sample_clock/v1";
reject(@()sixgr.truth.SSBPowerReferenceLifecycle.filterContext(s,bad),'sixgr:truth:SSBPowerLifecycleClock');
s.CurrentSlot=70; s.RuntimeViewMode="future_ul_grant_planning"; s.PlanningDecisionSlot=2;
[chosen,~]=sixgr.truth.SSBPowerReferenceLifecycle.select(s,s.CfgMobility,1,0,T); assert(isempty(chosen));
reject(@()sixgr.truth.SSBPowerReferenceLifecycle.install(s,1,common),'sixgr:truth:SSBPowerLifecyclePlanningInstall');
end

function integratedAdmission()
scenario=sixgr.lls6g.config.loadScenarioConfig( ...
    'simulator/configs/scenarios/lls_tdd_n40_20mhz_64txru_4rx_cdlc100_impaired.yaml');
cfg=sixgr.lls6g.buildInternalConfig(scenario,tempname);
assert(sixgr.phy.refsig.pathlossReferenceLifetime(cfg)=="retained_filtered_reference");
[s,m,common]=fixture(); s.CfgMobility=cfg; s.CurrentSlot=42;
m.ReferenceConfigurationEpoch=cfg.initial_access.configuration_epoch;
m.ProducerSlot=41; m.AvailableSlot=42; m.MeasurementId="declared_received_SSB_41";
common.ConfigurationEpoch=cfg.initial_access.configuration_epoch; common.AvailableSlot=42;
[s,m]=observe(s,m); s=sixgr.truth.SSBPowerReferenceLifecycle.install(s,1,common);
s.UECommonCellConfigurationByUE={common}; s.ReferenceSignalMeasurementTable=struct2table(m,'AsArray',true);
s.CurrentSlot=82; original=s.ReferenceSignalMeasurementTable; filters=s.UEReferenceRSRPFilters; random=rng;
[pucch,srs,d]=admission(s,cfg);
assert(pucch && srs && d.ReferenceUsable && d.AgeSlots==41 && isinf(d.MaximumAgeSlots) && ...
    d.Pathloss_dB==60 && d.PathlossReferenceLifetime=="retained_filtered_reference");
assert(isequaln(original,s.ReferenceSignalMeasurementTable) && ...
    isequaln(filters,s.UEReferenceRSRPFilters) && isequal(random,rng));
% Explicit legacy study TTL still has exactly its authored semantics.
legacy=cfg; legacy.rf.frontend.ul_power_control.pathloss_reference_lifetime='configured_age_limit';
[pucch,srs,d]=admission(s,legacy); assert(~pucch && ~srs && d.Status=="stale");
s.CurrentSlot=83; common.AvailableSlot=83; common.SSPBCHBlockPower_dBm=-10;
s=sixgr.truth.SSBPowerReferenceLifecycle.install(s,1,common); s.UECommonCellConfigurationByUE={common};
[pucch,srs,d]=admission(s,cfg); assert(~pucch && ~srs && ~d.ReferenceUsable);
s.CurrentSlot=84; fresh=m; fresh.ProducerSlot=83; fresh.AvailableSlot=84;
fresh.MeasurementId="declared_received_new_power_SSB_83"; fresh.RSRP_dBm=-70;
[s,fresh]=observe(s,fresh);
assert(fresh.UERSRPFilterUpdateCount==1);
s.ReferenceSignalMeasurementTable=[s.ReferenceSignalMeasurementTable;struct2table(fresh,'AsArray',true)];
[pucch,srs,d]=admission(s,cfg);
assert(pucch && srs && d.MeasurementId==fresh.MeasurementId && d.Pathloss_dB==60);
assert(isequaln(s.ReferenceSignalMeasurementTable(1,:),original));
end

function [pucch,srs,d]=admission(s,cfg)
cfg.lls6g.userContext=struct('UEIndex',1,'RuntimeServingCell',1, ...
    'RuntimeCurrentSlot',s.CurrentSlot,'RuntimeCurrentDirection','UL');
[~,d]=sixgr.truth.bindSharedSSBPowerReference(cfg,s,1,s.CurrentSlot,0,'PUCCH');
[pucch,~,p]=sixgr.truth.resolveSharedPUCCHPowerAdmission(s,cfg,1,s.CurrentSlot);
cfg.lls6g.userContext.RuntimeSRSPowerReference=sixgr.truth.resolveSRSPowerReference(s,cfg,1,s.CurrentSlot);
[srs,q]=sixgr.truth.resolveSharedSRSPowerAdmission(s,cfg,1,s.CurrentSlot);
assert(p.MeasuredPowerReferenceRequired && q.MeasuredPowerReferenceRequired && ...
    ~q.SRSTransmissionPrepared && ~q.SRSReceiverExecuted);
end

function sharedClock()
scenario=sixgr.lls6g.config.loadScenarioConfig( ...
    'simulator/configs/scenarios/lls_tdd_5mhz_rank2_4tx2rx_awgn_m10db.yaml');
folder=fullfile(pwd,'results','validation','ssb_power_reference_lifecycle',char(java.util.UUID.randomUUID()));
mkdir(folder);
cfg=sixgr.lls6g.buildInternalConfig(scenario,folder); cfg.run.rootRunFolder=folder;
cfg=sixgr.truth.bindStandaloneSNRPoint(cfg,-10); cfg.outputs.continuousRawIQCaptureEnabled=false;
cfg.initial_access.preconnection_rsrp_filter_coefficient_k=4;
cfg.initial_access.preconnection_rsrp_filter_reference_period_ms=20;
cfg.rf.frontend.ul_power_control.pathloss_reference_lifetime='retained_filtered_reference';
multi=struct('Enabled',true,'NumUsers',1,'RNTIStart',1,'ExecutionModel','slot_coupled_truth');
s=sixgr.truth.CoupledTruthRuntime.initialize(cfg,folder,multi,struct(),5);
s.CurrentServingIdx(:)=1; % Explicit declared cell boundary; not received acquisition.
s=sixgr.truth.CoupledTruthRuntime.startSlot(s,cfg,'DL',1,1,1,5,-10);
[s,owner]=sixgr.truth.CoupledWaveformStream.initialize(s,cfg,{cfg});
[s,completed]=owner.advanceSlot(s,cfg); assert(isempty(completed));
s=sixgr.truth.CoupledTruthRuntime.startSlot(s,cfg,'DL',1,1,2,5,-10);
s.CellAcquisitionState(:)="acquired";
[~,m,common]=fixture(); m.ReferenceConfigurationEpoch=cfg.initial_access.configuration_epoch;
m.ProducerSlot=1; m.AvailableSlot=2; m.MeasurementClockDomain="shared_receiver_sample_clock/v1";
m.ObservationStartSample=0; m.ObservationEndSampleExclusive=owner.Events.NextSampleIndex;
m.ResultAvailableAtSample=owner.Events.NextSampleIndex; m.ObservationSampleRateHz=owner.SampleRateHz;
m.MeasurementClockEpoch=owner.Physical.ConfigurationEpoch;
p=sixgr.rrc.resolvePreconnectionRSRPFilter(cfg); m.SSBPowerReferenceCaptureFilterConfigHash=p.ConfigHash;
common.ConfigurationEpoch=cfg.initial_access.configuration_epoch; common.AvailableSlot=2;
common.MeasurementClockEpoch=owner.Physical.ConfigurationEpoch;
common.ReceivedDLTimingReference=struct('Source',"received_SSB_timing_and_decoded_BCH", ...
    'SampleRateHz',owner.SampleRateHz,'ObservationStartSample',0, ...
    'AvailableAtSample',owner.Events.NextSampleIndex,'NCellID',s.Layout.bs.nCellId(1));
[s,m,c]=observe(s,m); [s,r]=sixgr.truth.SSBPowerReferenceLifecycle.install(s,1,common);
s.UECommonCellConfigurationByUE={common}; assert(r.GenerationSHA256==c.GenerationSHA256);
T=struct2table(m,'AsArray',true);
[chosen,~]=sixgr.truth.SSBPowerReferenceLifecycle.select(s,cfg,1,0,T); assert(isequaln(chosen,T));
badCommon=common; badCommon.ReceivedDLTimingReference.NCellID=mod(common.ReceivedDLTimingReference.NCellID+1,1008);
reject(@()sixgr.truth.SSBPowerReferenceLifecycle.install(s,1,badCommon),'sixgr:truth:SSBPowerLifecycleCommon');
badCommon=common; badCommon.MeasurementClockEpoch=common.MeasurementClockEpoch+1;
reject(@()sixgr.truth.SSBPowerReferenceLifecycle.install(s,1,badCommon),'sixgr:truth:SSBPowerLifecycleCommon');
bad=m; bad=rmfield(bad,'SSBPowerReferenceCaptureFilterConfigHash');
[eligible,c]=sixgr.truth.SSBPowerReferenceLifecycle.filterContext(s,bad);
assert(~eligible && c.Status=="missing_original_capture_configuration");
bad=m; bad.ReferenceConfigurationEpoch=bad.ReferenceConfigurationEpoch+1;
[eligible,~]=sixgr.truth.SSBPowerReferenceLifecycle.filterContext(s,bad); assert(~eligible);
bad=m; bad.ResultAvailableAtSample=owner.Events.NextSampleIndex+1;
[eligible,~]=sixgr.truth.SSBPowerReferenceLifecycle.filterContext(s,bad); assert(~eligible);
% Actual clock progresses; no SSB, SIB1 or PUCCH is executed in this fixture.
[s,completed]=owner.advanceSlot(s,cfg); assert(isempty(completed));
s=sixgr.truth.CoupledTruthRuntime.startSlot(s,cfg,'DL',1,1,3,5,-10);
common.AvailableSlot=3; common.SSPBCHBlockPower_dBm=-10;
[s,r]=sixgr.truth.SSBPowerReferenceLifecycle.install(s,1,common);
s.UECommonCellConfigurationByUE={common}; cutoff=owner.Events.NextSampleIndex;
assert(r.MinimumObservationStart==cutoff);
[s,completed]=owner.advanceSlot(s,cfg); assert(isempty(completed));
s=sixgr.truth.CoupledTruthRuntime.startSlot(s,cfg,'DL',1,1,4,5,-10);
late=m; late.AvailableSlot=4; late.ResultAvailableAtSample=owner.Events.NextSampleIndex;
[eligible,c]=sixgr.truth.SSBPowerReferenceLifecycle.filterContext(s,late);
assert(~eligible && c.Status=="observation_precedes_reference_power_generation");
fresh=m; fresh.ObservationStartSample=cutoff; fresh.ObservationEndSampleExclusive=owner.Events.NextSampleIndex;
fresh.ResultAvailableAtSample=owner.Events.NextSampleIndex; fresh.ProducerSlot=3; fresh.AvailableSlot=4;
fresh.MeasurementId="declared_post_change_shared_capture"; fresh.RSRP_dBm=-60;
[s,fresh]=observe(s,fresh);
assert(fresh.UERSRPFilterUpdateCount==1 && fresh.UEFilteredRSRP_dBm==-60);
[chosen,~]=sixgr.truth.SSBPowerReferenceLifecycle.select(s,cfg,1,0,struct2table(fresh,'AsArray',true));
assert(height(chosen)==1);
fprintf('SSB_POWER_LIFECYCLE_RETAINED_PATH %s\n',folder);
end

function reject(f,id)
try, f(); catch ME, assert(string(ME.identifier)==id,'%s',getReport(ME,'extended','hyperlinks','off')); return; end
error('test:SSBPowerLifecycleMissingGuard','Expected %s.',id);
end
