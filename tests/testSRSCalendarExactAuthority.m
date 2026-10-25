function ok=testSRSCalendarExactAuthority()
% Config/native mapping and scheduling authority; not receiver statistics.
setup6GRSimToolkit('Verbose',false,'RunToolboxChecks',false);
absent=struct('Periodicity',NaN,'Offset',NaN);
absentHash=sixgr.phy.srs.hashSRSConfig(absent);
assert(~ismissing(absentHash) && strlength(absentHash)==64 && ...
    absentHash==sixgr.phy.srs.hashSRSConfig(absent) && ...
    absentHash~=sixgr.phy.srs.hashSRSConfig(struct('Periodicity',1,'Offset',0)));
allowed=[1 2 4 5 8 10 16 20 32 40 64 80 160 320 640 1280 2560];
for period=allowed
    [p,o]=sixgr.phy.srs.validateSRSPeriodOffset(period,period-1);
    assert(p==period && o==period-1);
end
for bad={NaN,Inf,0,-1,2.5,3,128,true,'5',[5 10],complex(5,1)}
    localReject(@()sixgr.phy.srs.validateSRSPeriodOffset(bad{1},0), ...
        'sixgr:phy:srs:InvalidPeriodicity');
end
for bad={NaN,-1,0.5,5,true,'4',[0 1],complex(1,1)}
    localReject(@()sixgr.phy.srs.validateSRSPeriodOffset(5,bad{1}), ...
        'sixgr:phy:srs:InvalidPeriodOffset');
end
scenario=sixgr.lls6g.config.loadScenarioConfig( ...
    'simulator/configs/scenarios/lls_tdd_n40_20mhz_64txru_4rx_cdlc100_reference_snr_sweep.yaml');
s=scenario.toStruct(); cfg=sixgr.lls6g.buildInternalConfig(s,tempname);
assert(s.reference_signals.srs_periodicity_ms==2.5 && ...
    str2double(string(s.reference_signals.srs.periodicity))==2.5 && ...
    string(s.reference_signals.tracking_rs.periodicity)=="10ms");
assert(cfg.phy.srs.period_slots==5 && cfg.phy.srs.period_offset==4 && ...
    string(cfg.phy.srs.periodSource)=="reference_signals.srs_periodicity_slots");
strict=sixgr.phy.srs.buildSRSConfigFromScenario(cfg);
assert(isequal(strict.ToolboxSRS.SRSPeriod,[5 4]));
for slot0=0:9
    carrier=strict.ToolboxCarrier; carrier.NSlot=slot0;
    native=~isempty(nrSRSIndices(carrier,strict.ToolboxSRS));
    due=sixgr.truth.coupledSRSResourceOpportunity(cfg,slot0+1,1,1,5,'multiplex_due_users',1);
    assert(native==due && native==(mod(slot0,5)==4));
end
% Millisecond-only input is converted on SCS, never duration/horizon.
ms=localWithoutPeriod(s); ms.reference_signals.srs_periodicity_ms=5;
ms.reference_signals.srs.period_offset=9;
ms.reference_signals.srs_slot_within_period=10;
a=sixgr.lls6g.buildInternalConfig(ms,tempname);
assert(a.phy.srs.period_slots==10 && a.phy.srs.periodSource=="reference_signals.srs_periodicity_ms");
native=sixgr.phy.srs.buildSRSConfigFromScenario(a);
assert(isequal(native.ToolboxSRS.SRSPeriod,[10 9]));
for scs=[15 30 120]
    carrierClock=ms; carrierClock.frame.scs_khz=scs;
    carrierClock.run_control.total_slots=7; carrierClock.run_control.total_time_ms=999;
    assert(sixgr.lls6g.config.resolveCarrierPeriodSlots(carrierClock, ...
        "reference_signals.srs_periodicity_slots","reference_signals.srs_periodicity_ms")==5*scs/15);
end
bad=ms; bad.reference_signals.srs_periodicity_ms=0.3;
localReject(@()sixgr.lls6g.buildInternalConfig(bad,tempname),'sixgr:lls6g:config:NonIntegralCarrierPeriod');
bad=s; bad.reference_signals.srs_periodicity_slots=5.25;
localReject(@()sixgr.lls6g.buildInternalConfig(bad,tempname),'sixgr:lls6g:config:NonIntegralCarrierPeriod');
bad=localWithoutPeriod(s);
localReject(@()sixgr.lls6g.buildInternalConfig(bad,tempname),'sixgr:phy:srs:InvalidPeriodicity');
disabled=bad; disabled.reference_signals.srs_enabled=false;
% Connected UL signaling still requires its declared SRS codebook resource.
% Disabling SRS alone is contradictory and must not bypass that guard.
localReject(@()sixgr.lls6g.buildInternalConfig(disabled,tempname), ...
    'sixgr:lls6g:config:SRSResourceSetRuntimeMismatch');
% Isolate absent-calendar binding from connected UL signaling. This is a
% disabled component configuration, not a runnable connected-UL scenario.
anchor=sixgr.lls6g.config.loadScenarioConfig('configs/lls/lls_srs_strict_mini_anchor.yaml');
disabled=localWithoutPeriod(anchor.toStruct());
disabled.reference_signals.srs_enabled=false;
disabled.control_gating.srs_required=false;
off=sixgr.lls6g.buildInternalConfig(disabled,tempname);
assert(~isfield(off.phy.srs,'period_slots') && strlength(off.phy.srs.periodSource)==0);
% The final top-level resource-type override must own validation.
ap=bad; ap.reference_signals.srs.resource_type='periodic';
ap.reference_signals.srs_resource_type='aperiodic';
% A no-calendar AP construction must not inherit a periodic offset. Native
% per-capture generation is tested below separately from decoded DCI.
ap.reference_signals.srs=rmfield(ap.reference_signals.srs,'period_offset');
if isfield(ap.reference_signals,'srs_period_offset')
    ap.reference_signals=rmfield(ap.reference_signals,'srs_period_offset');
end
apcfg=sixgr.lls6g.buildInternalConfig(ap,tempname);
assert(strcmpi(apcfg.phy.srs.resourceType,'aperiodic') && ~isfield(apcfg.phy.srs,'period_slots'));
ap.reference_signals.srs.resource_type='aperiodic';
ap.reference_signals.srs_resource_type='periodic';
localReject(@()sixgr.lls6g.buildInternalConfig(ap,tempname),'sixgr:phy:srs:InvalidPeriodicity');
% Direct strict/native callers must not round malformed configurations.
badcfg=cfg; badcfg.phy.srs.period_slots=4.5;
localReject(@()sixgr.phy.srs.buildSRSConfigFromScenario(badcfg),'sixgr:phy:srs:InvalidPeriodicity');
badcfg=cfg; badcfg.phy.srs.period_offset=3.5;
localReject(@()sixgr.phy.srs.buildSRSConfigFromScenario(badcfg),'sixgr:phy:srs:InvalidPeriodOffset');
badcfg=cfg; badcfg.phy.srs.slotNumbers=4.5;
localReject(@()sixgr.phy.srs.buildSRSConfigFromScenario(badcfg),'sixgr:phy:srs:InvalidExplicitSlotSet');
badcfg=cfg; badcfg.phy.srs.slotWithinPeriod1Based=4.5;
localReject(@()sixgr.phy.srs.buildSRSConfigFromScenario(badcfg),'sixgr:phy:srs:InvalidSlotWithinPeriod');
localReject(@()sixgr.truth.coupledSRSResourceOpportunity(badcfg,5,1,1,5,'multiplex_due_users',1), ...
    'sixgr:phy:srs:InvalidSlotWithinPeriod');
badcfg=cfg; badcfg.phy.srs.slotWithinPeriod1Based=[4 5];
localReject(@()sixgr.phy.srs.buildSRSConfigFromScenario(badcfg),'sixgr:phy:srs:ScheduleAuthorityMismatch');
localReject(@()sixgr.truth.coupledSRSResourceOpportunity(badcfg,4,1,1,5,'multiplex_due_users',1), ...
    'sixgr:phy:srs:ScheduleAuthorityMismatch');
badcfg=cfg; badcfg.phy.srs.slotNumbers=3;
localReject(@()sixgr.phy.srs.buildSRSConfigFromScenario(badcfg),'sixgr:phy:srs:ScheduleAuthorityMismatch');
localReject(@()sixgr.truth.coupledSRSResourceOpportunity(badcfg,4,1,1,5,'multiplex_due_users',1), ...
    'sixgr:phy:srs:ScheduleAuthorityMismatch');
badcfg=cfg; badcfg.phy.srs.period_slots='P';
localReject(@()sixgr.truth.coupledSRSResourceOpportunity(badcfg,5,1,1,80,'multiplex_due_users',1), ...
    'sixgr:phy:srs:InvalidPeriodicity');
% Actual producer must not shift its native offset to make an arbitrary
% requested capture slot look scheduled. These guards execute before TX.
single=cfg; single.phy.srs.slotWithinPeriod1Based=[];
localReject(@()sixgr.link.runSRSChannelEstimation(single,'SlotIndex',4,'PrepareOnly',true), ...
    'sixgr:phy:srs:ScheduleAuthorityMismatch');
localReject(@()sixgr.link.runSRSChannelEstimation(single,'SlotIndex',4.5,'PrepareOnly',true), ...
    'sixgr:phy:srs:InvalidRuntimeSlot');
restricted=single; restricted.phy.srs.slotNumbers=9;
localReject(@()sixgr.link.runSRSChannelEstimation(restricted,'SlotIndex',5,'PrepareOnly',true), ...
    'sixgr:phy:srs:ScheduleAuthorityMismatch');
subset=cfg; subset.phy.srs.slotNumbers=9;
subsetNative=sixgr.phy.srs.buildSRSConfigFromScenario(subset);
assert(isequal(subsetNative.ExpectedSlotSet,9) && ...
    ~sixgr.truth.coupledSRSResourceOpportunity(subset,5,1,1,5,'multiplex_due_users',1) && ...
    sixgr.truth.coupledSRSResourceOpportunity(subset,10,1,1,5,'multiplex_due_users',1));
badstrict=strict; badstrict.Periodicity=4.5;
localReject(@()sixgr.phy.srs.buildSRSResourceStrict(badstrict,strict.ToolboxCarrier), ...
    'sixgr:phy:srs:InvalidPeriodicity');
localReject(@()sixgr.truth.coupledSRSResourceOpportunity(apcfg,5,1,1,5,'multiplex_due_users',1), ...
    'sixgr:truth:NonPeriodicSRSCalendar');
% Native per-capture AP context is not evidence of decoded trigger delivery.
apNative=strict; apNative.ResourceType='aperiodic';
apNative.Periodicity=NaN; apNative.Offset=NaN; apNative.DCITriggerReferenceId='';
apNative.ToolboxSRS=sixgr.phy.srs.buildSRSResourceStrict(apNative,strict.ToolboxCarrier);
assert(strcmp(apNative.ToolboxSRS.SRSPeriod,'on') && ...
    ~isempty(nrSRSIndices(strict.ToolboxCarrier,apNative.ToolboxSRS)));
validation=sixgr.phy.srs.validateSRSConfigStrict(apNative);
assert(~validation.StrictValid && any(validation.FailureReasons=="aperiodic_srs_missing_decoded_dci_trigger_reference"));
apNative.Periodicity=complex(NaN,1);
localReject(@()sixgr.phy.srs.buildSRSResourceStrict(apNative,strict.ToolboxCarrier),'sixgr:phy:srs:InvalidPeriodicity');
apNative.Periodicity=NaN; apNative.Offset=4;
localReject(@()sixgr.phy.srs.buildSRSResourceStrict(apNative,strict.ToolboxCarrier),'sixgr:phy:srs:InvalidPeriodOffset');
fprintf('SRS_CALENDAR_EXACT_AUTHORITY_PASS base_IE=17 native_runtime_occasion_identity=10 no_horizon_rounding no_missing_period_fallback\n');
ok=true;
end

function s=localWithoutPeriod(s)
for name=["srs_periodicity_slots","srs_periodicity_ms"]
    if isfield(s.reference_signals,name), s.reference_signals=rmfield(s.reference_signals,name); end
end
if isfield(s,'control_gating') && isfield(s.control_gating,'srs_period_slots')
    s.control_gating=rmfield(s.control_gating,'srs_period_slots');
end
end

function localReject(f,id)
try
    f();
catch cause
    assert(strcmp(cause.identifier,id),'test:WrongSRSCalendarGuard','Expected %s, got %s: %s',id,cause.identifier,cause.message);
    return;
end
error('test:MissingSRSCalendarGuard','Expected %s.',id);
end
