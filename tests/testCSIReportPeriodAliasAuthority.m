function ok=testCSIReportPeriodAliasAuthority()
% YAML/configured-calendar evidence only. No CSI measurement or UCI execution.
setup6GRSimToolkit('Verbose',false,'RunToolboxChecks',false);
work=tempname; mkdir(work);
cleanup=onCleanup(@()rmdir(work,'s')); %#ok<NASGU> unique test fixture folder
base=string(fullfile(pwd,'simulator/configs/scenarios/lls_tdd_n40_20mhz_64txru_4rx_cdlc100_impaired.yaml'));
checks={@()inheritance(base,work),@()orderedOffsets(base,work), ...
    @()guards(base,work),@()roundTripAndSweep(base,work), ...
    @()clockArithmetic(),@()installedCalendar(base)};
names=["authored_inheritance","ordered_period_offset_groups","conflicts_and_tampering", ...
    "resolved_reload_and_sweeps","UL_BWP_native_slot_clock","installed_report_obligations"];
passed=false(size(checks));
for k=1:numel(checks)
    try
        checks{k}(); passed(k)=true;
        fprintf('CSI_REPORT_PERIOD_AUTHORITY_PASS %s\n',names(k));
    catch cause
        fprintf(2,'CSI_REPORT_PERIOD_AUTHORITY_FAIL %s %s\n',names(k),getReport(cause,'extended','hyperlinks','off'));
    end
end
assert(all(passed),'test:CSIReportPeriodAliasAuthority','Passed %d/%d groups.',nnz(passed),numel(passed));
ok=true;
end

function inheritance(base,work)
s=read(base); check(s,10,8,30);
parent=write(work,'period_parent',base,set(struct(),periodPath(),20));
child=write(work,'period_child',parent,set(struct(),tokenPath(),'5ms'));
leaf=write(work,'period_leaf',child,struct('meta',struct('description','unrelated calendar leaf')));
s=read(leaf); check(s,10,8,30);
assert(numel(s.csi_acquisition_and_reporting.report_calendar_authority.Declarations.Period)==1);
back=write(work,'period_back',leaf,set(struct(),'reference_signals.csi_report_periodicity_slots',20));
s=read(back); check(s,20,8,30);
% Canonical controls are an authored layer too, not ignored metadata.
canonical=set(set(struct(),canonicalPeriodPath(),5),canonicalOffsetPath(),1);
file=write(work,'canonical_report_child',base,canonical);
s=read(file); check(s,5,1,30);
back=write(work,'after_canonical_child',file,set(struct(),tokenPath(),'10ms'));
check(read(back),20,1,30);
% These self-contained masters retain their pre-repair executed slot
% periods. Removing stale ms tokens must not double either calendar.
folder=fullfile(pwd,'simulator/configs/scenarios');
sinr=read(fullfile(folder,'master_sinr_sweep.yaml')); check(sinr,20,0,30);
assert(~sinr.reference_signals.csi_reporting_enabled);
geometry=read(fullfile(folder,'master_geometry_based.yaml')); check(geometry,5,1,30);
assert(geometry.reference_signals.csi_reporting_enabled);
web=read(fullfile(folder,'webgui_sinr_sweep_64x4_mu_mimo_full.yaml')); check(web,5,0,30);
end

function orderedOffsets(base,work)
a=write(work,'period_a',strings(0,1),set(struct(),periodPath(),20));
b=write(work,'period_b',strings(0,1),set(struct(),tokenPath(),'5ms'));
c=write(work,'offset_c',strings(0,1),set(struct(),'reference_signals.csi_report_offset_slots',3));
check(read(write(work,'period_ab',[base a b c],struct())),10,3,30);
check(read(write(work,'period_ba',[base b a c],struct())),20,3,30);
% Report phase is independent of the pilot phase and of a period override.
s=read(base); authored=set(struct(),'reference_signals.csi_rs_offset_slots',2);
s=sixgr.lls6g.config.normalizeScenarioAliases(sixgr.util.mergeStruct(s,authored),'Authority',authored);
assert(s.csi_acquisition_and_reporting.csi_report_offset_slots==8);
default=sixgr.lls6g.config.readConfigFile('simulator/configs/defaults/top_level_required_sections_02.yaml');
assert(default.csi_acquisition_and_reporting.csi_report_offset_slots==0);
end

function guards(base,work)
bad=set(set(struct(),periodPath(),20),tokenPath(),'5ms');
reject(@()read(write(work,'bad_period',base,bad)),'sixgr:lls6g:config:ConflictingCSIReportAliases');
bad=set(set(struct(),offsetPath(),3),'reference_signals.csi_report_offset_slots',4);
reject(@()read(write(work,'bad_offset',base,bad)),'sixgr:lls6g:config:ConflictingCSIReportAliases');
bad=set(set(struct(),periodPath(),20),canonicalPeriodPath(),5);
reject(@()read(write(work,'bad_canonical_period',base,bad)),'sixgr:lls6g:config:ConflictingCSIReportAliases');
bad=set(set(struct(),offsetPath(),3),canonicalOffsetPath(),4);
reject(@()read(write(work,'bad_canonical_offset',base,bad)),'sixgr:lls6g:config:ConflictingCSIReportAliases');
bad=set(struct(),tokenPath(),'0.6ms');
reject(@()read(write(work,'bad_integrality',base,bad)),'sixgr:lls6g:config:NonIntegralCSIReportPeriod');
for value={[],NaN,Inf,true,'20',[10 20],1+1i,-1}
    bad=set(struct(),periodPath(),value{1});
    reject(@()sixgr.lls6g.config.CSIReportPeriodAuthority.merge(struct(),bad), ...
        'sixgr:lls6g:config:InvalidCSIReportPeriod');
end
s=read(base); bad=s; bad.csi_acquisition_and_reporting.csi_report_periodicity_slots=20;
reject(@()sixgr.lls6g.buildInternalConfig(bad,tempname),'sixgr:lls6g:config:CSIReportAliasChanged');
bad=s; bad.csi_acquisition_and_reporting.report_calendar_authority.PeriodSlots=20;
reject(@()sixgr.lls6g.config.normalizeScenarioAliases(bad),'sixgr:lls6g:config:InvalidCSIReportAuthority');
bad=s; bad.csi_acquisition_and_reporting.report_calendar_authority.Clock.SCSKHz=60;
reject(@()sixgr.lls6g.config.normalizeScenarioAliases(bad),'sixgr:lls6g:config:InvalidCSIReportAuthority');
bad=s; bad.csi_acquisition_and_reporting.report_calendar_authority.SHA256=repmat('0',1,64);
reject(@()sixgr.lls6g.config.normalizeScenarioAliases(bad),'sixgr:lls6g:config:InvalidCSIReportAuthority');
% Without a capsule, contradictory direct structs are still contradictory.
bad=s; bad.csi_acquisition_and_reporting=rmfield(bad.csi_acquisition_and_reporting,'report_calendar_authority');
bad.csi_acquisition_and_reporting.report_periodicity='10ms';
reject(@()sixgr.lls6g.config.CSIReportPeriodAuthority.apply(bad),'sixgr:lls6g:config:ConflictingCSIReportAliases');
end

function roundTripAndSweep(base,work)
s=read(base);
assert(isequaln(s,sixgr.lls6g.config.normalizeScenarioAliases(s)));
for ext=["json","yaml"]
    file=fullfile(work,"resolved_report."+ext);
    if ext=="json", sixgr.util.jsonWrite(file,s); else, sixgr.lls6g.config.writeYAML(file,s); end
    restored=read(file); check(restored,10,8,30);
    assert(isequaln(restored.csi_acquisition_and_reporting.report_calendar_authority, ...
        s.csi_acquisition_and_reporting.report_calendar_authority));
    % Change only reporting BWP clock: original authored 5ms remains 5ms.
    authored=struct('bwp',struct('ul',struct('bwp_id',2,'scs_khz',60)));
    changed=sixgr.lls6g.config.normalizeScenarioAliases( ...
        sixgr.util.mergeStruct(restored,authored),'Authority',authored);
    check(changed,20,8,60);
    assert(changed.csi_acquisition_and_reporting.report_calendar_authority.Clock.BWPID==2);
    % Slot-authored periods stay in slots after the same SCS change.
    authored=set(struct(),periodPath(),20);
    fixed=sixgr.lls6g.config.normalizeScenarioAliases(sixgr.util.mergeStruct(restored,authored),'Authority',authored);
    authored=struct('bwp',struct('ul',struct('bwp_id',2,'scs_khz',60)));
    fixed=sixgr.lls6g.config.normalizeScenarioAliases(sixgr.util.mergeStruct(fixed,authored),'Authority',authored);
    check(fixed,20,8,60);
    assert(string(fixed.csi_acquisition_and_reporting.report_periodicity)=="5ms");
end
canonical=set(set(struct(),canonicalPeriodPath(),20),canonicalOffsetPath(),3);
canonical=sixgr.lls6g.config.normalizeScenarioAliases(sixgr.util.mergeStruct(s,canonical),'Authority',canonical);
check(canonical,20,3,30);
canonicalFile=write(work,'canonical_resolved',strings(0,1),canonical);
check(read(canonicalFile),20,3,30);
% Existing v1 snapshots have no mandatory canonical mirrors. Their exact
% original declarations/digest still validate, then publish the v2 mirrors.
legacy=s; legacy.canonical_control.reference_signals=rmfield( ...
    legacy.canonical_control.reference_signals,{'csi_report_periodicity_slots','csi_report_offset_slots'});
r=legacy.csi_acquisition_and_reporting.report_calendar_authority;
r.ContractVersion="sixgr.config.CSIReportCalendar/v1"; r=rmfield(r,'SHA256');
r.SHA256=sixgr.lls6g.config.hashResolvedScenario(r);
legacy.csi_acquisition_and_reporting.report_calendar_authority=r;
check(sixgr.lls6g.config.normalizeScenarioAliases(legacy),10,8,30);
s.canonical_control.runtime_overrides=struct('path',{char(periodPath()),char(periodPath())},'value',{40,20});
s=sixgr.lls6g.config.normalizeScenarioAliases(s); check(s,20,8,30);
assert(isequaln(s,sixgr.lls6g.config.normalizeScenarioAliases(s)));
s.canonical_control.runtime_overrides=struct('path',{char(periodPath()),char(tokenPath())},'value',{20,'5ms'});
reject(@()sixgr.lls6g.config.normalizeScenarioAliases(s),'sixgr:lls6g:config:ConflictingCSIReportAliases');
end

function clockArithmetic()
for spacing=[15 30 60 120]
    s=struct('frame',struct('scs_khz',15), ...
        'frame_timing',struct('slot_duration_ms',999), ...
        'bwp',struct('ul',struct('bwp_id',3,'scs_khz',spacing)), ...
        'csi_acquisition_and_reporting',struct('report_periodicity','10ms','csi_report_offset_slots',3));
    resolved=sixgr.lls6g.config.CSIReportPeriodAuthority.apply(s);
    native=nrCarrierConfig('SubcarrierSpacing',spacing);
    check(resolved,native.SlotsPerFrame,3,spacing);
    slots=(1:(2*native.SlotsPerFrame)).';
    mask=sixgr.truth.periodicCSIReportSlotMask(slots,native.SlotsPerFrame,3);
    assert(isequal(slots(mask),[4;4+native.SlotsPerFrame]));
end
% A submillisecond token can be a legal four-slot period at 120kHz.
s.csi_acquisition_and_reporting.report_periodicity='0.5ms';
resolved=sixgr.lls6g.config.CSIReportPeriodAuthority.apply(s); check(resolved,4,3,120);
% No independent report offset is supplied: a pilot offset is not authority.
s.csi_acquisition_and_reporting=rmfield(s.csi_acquisition_and_reporting,'csi_report_offset_slots');
s.reference_signals.csi_rs_offset_slots=2;
reject(@()sixgr.lls6g.config.CSIReportPeriodAuthority.apply(s),'sixgr:lls6g:config:MissingCSIReportCalendar');
end

function installedCalendar(base)
s=read(base); cfg=sixgr.lls6g.buildInternalConfig(s,tempname);
clock=sixgr.lls6g.config.CSIReportPeriodAuthority.installedClock(cfg);
assert(clock.SCSKHz==30&&clock.BWPID==cfg.phy.frame.DefaultIdentity.ULBWPID);
assert(isequaln(clock,cfg.phy.csi.reportCalendarClock));
assert(cfg.phy.csi.reportConfiguration.ReportPeriodicitySlots==10&& ...
    cfg.phy.csi.reportConfiguration.ReportOffsetSlots==8);
identity=cfg.phy.frame.DefaultIdentity;
ue=struct('UEID',1,'RNTI',1,'ServingCell',1,'PUCCHCell',1, ...
    'ComponentCarrier',identity.ScheduledCCID,'ActiveULBWP',identity.ULBWPID);
calendar=sixgr.truth.buildPeriodicCSIReportObligations(cfg,ue,1,30);
assert(isequal(calendar.ReportSlot,[9;19;29])&&all(calendar.ReportSubcarrierSpacing_kHz==30));
otherUE=ue; otherUE.ActiveULBWP=ue.ActiveULBWP+1;
reject(@()sixgr.truth.buildPeriodicCSIReportObligations(cfg,otherUE,1,30), ...
    'sixgr:truth:CSIReportingCalendarBWPMismatch');
% The connected profile supports one full-carrier BWP per direction. Test
% its configured identity with the original width/allocation, not a claim
% of partial-BWP or mixed-numerology scheduling support.
authored=struct('bwp',struct('ul',struct('bwp_id',2,'scs_khz',30, ...
    'n_start_bwp',0,'n_size_bwp',cfg.phy.carrier.NSizeGrid)));
s=sixgr.lls6g.config.normalizeScenarioAliases(sixgr.util.mergeStruct(s,authored),'Authority',authored);
configured=sixgr.lls6g.buildInternalConfig(s,tempname);
assert(configured.phy.frame.DefaultIdentity.ULBWPID==2&& ...
    configured.phy.csi.reportCalendarClock.BWPID==2);
assert(isequal(configured.phy.pusch.PRBSet,cfg.phy.pusch.PRBSet)&& ...
    isequal(configured.phy.pusch.PRBSet,0:50));
% A legal narrow allocation still cannot bypass the separate connected
% profile capability guard. This is intentionally an unsupported case.
partial=struct('bwp',struct('ul',struct('bwp_id',2,'scs_khz',30, ...
    'n_start_bwp',0,'n_size_bwp',24)), ...
    'pusch',struct('prb_start',0,'num_prb',24));
partial=sixgr.lls6g.config.normalizeScenarioAliases(sixgr.util.mergeStruct(s,partial),'Authority',partial);
reject(@()sixgr.lls6g.buildInternalConfig(partial,tempname), ...
    'sixgr:phy:pdcch:UnsupportedConnectedBWP');
% A changed installed clock cannot be passed off as the original report
% coordinate system. This negative is declared snapshot corruption, no RF.
bad=cfg; c=find([bad.phy.frame.ComponentCarriers.CCID]==identity.ScheduledCCID);
b=bad.phy.frame.ComponentCarriers(c).BWPs;
j=find([b.BWPID]==identity.ULBWPID & upper(string({b.Direction}))=="UL");
bad.phy.frame.ComponentCarriers(c).BWPs(j).SCSKHz=60;
reject(@()sixgr.lls6g.config.CSIReportPeriodAuthority.bind(bad,read(base)), ...
    'sixgr:lls6g:config:CSIReportULBWPClock');
reject(@()sixgr.truth.buildPeriodicCSIReportObligations(bad,ue,1,30), ...
    'sixgr:truth:CSIReportingCalendarClockMismatch');
end

function check(s,p,o,spacing)
r=s.csi_acquisition_and_reporting;
assert(r.csi_report_periodicity_slots==p&&s.reference_signals.csi_report_periodicity_slots==p);
assert(r.csi_report_offset_slots==o&&s.reference_signals.csi_report_offset_slots==o);
assert(s.canonical_control.reference_signals.csi_report_periodicity_slots==p&& ...
    s.canonical_control.reference_signals.csi_report_offset_slots==o);
assert(r.report_calendar_authority.Clock.SCSKHz==spacing);
assert(string(r.report_periodicity)==string(p/(spacing/15))+"ms");
end
function p=periodPath(), p="csi_acquisition_and_reporting.csi_report_periodicity_slots"; end
function p=offsetPath(), p="csi_acquisition_and_reporting.csi_report_offset_slots"; end
function p=tokenPath(), p="csi_acquisition_and_reporting.report_periodicity"; end
function p=canonicalPeriodPath(), p="canonical_control.reference_signals.csi_report_periodicity_slots"; end
function p=canonicalOffsetPath(), p="canonical_control.reference_signals.csi_report_offset_slots"; end
function out=set(s,path,value), out=sixgr.util.structSet(s,path,value); end
function s=read(file), sc=sixgr.lls6g.config.loadScenarioConfig(file); s=sc.toStruct(); end
function file=write(work,name,parents,s)
file=string(fullfile(work,name+".json"));
if ~isempty(parents), s.inherits=parents; end
sixgr.util.jsonWrite(file,s);
end
function reject(callback,id)
try, callback(); catch cause
    assert(strcmp(cause.identifier,id),'Expected %s, got %s: %s',id,cause.identifier,cause.message); return;
end
error('test:MissingCSIReportAuthorityGuard','Expected %s.',id);
end
