function ok=testSharedPUSCHCSIReceiveObligation()
% Configured receiver schema only; no invented CSI measurement or RF proof.
setup6GRSimToolkit('Verbose',false);
s=sixgr.lls6g.config.loadScenarioConfig( ...
    'simulator/configs/scenarios/lls_pusch_shared_queue_fdd_fixture.yaml');
cfg=sixgr.lls6g.buildInternalConfig(s,tempname);
saved=load(fullfile('docs','lls','evidence_20260913','scheduled_ul_dai_03', ...
    'scheduled_ul_dai_0.mat'),'fixed');
grant=saved.fixed;
% Declare the calendar alignment as fixture input, independent of UE data.
cfg.phy.csi.reportCSI=true;
cfg.phy.csi.reportTrigger='periodic';
cfg.phy.csi.reportPeriodicitySlots=5;
cfg.phy.csi.reportOffsetSlots=mod(grant.TimingDecision.DataAbsoluteSlot,5);
cfg.phy.rsla.measurement_gaps=struct('enabled',false);
[obligation,report,calendar]=sixgr.truth.buildSharedPUSCHCSIReceiveObligation(cfg,grant);
assert(height(calendar)==1 && calendar.ULResourceAvailable && ...
    report.UCIChannel=="PUSCH" && obligation.ReportConfigID==report.ReportConfigID && ...
    obligation.ConfigurationEpoch==report.Epoch);
installed=sixgr.phy.mimo.CSIReportConfiguration( ...
    cfg.phy.csi.reportConfiguration,cfg.phy.csi.reportConfigurationEpoch);
assert(report.ConfiguredUCIChannel==installed.ConfiguredUCIChannel && ...
    isequal(report.Part1Fields,installed.Part1Fields) && ...
    isequal(report.Part1Widths,installed.Part1Widths) && ...
    isequal(report.Part2Widths,installed.Part2Widths), ...
    'An overlapping PUSCH does not reconfigure the installed CSI report format.');
% A configuration-only schema does not prove an executed CSI reference.
% Runtime selection must omit CSI when the actual TX ledger is empty,
% regardless of fabricated UE measurement or pending-report metadata.
state=struct('SharedDataTXLedger',{{}},'ControlTrials',struct('CSIRS',"poisoned"), ...
    'PendingCSITable',"poisoned");
[none,absent,configured,proof]=sixgr.truth.resolveSharedPUSCHCSIReceiveObligation(state,cfg,grant);
assert(none.ReportConfigID=="" && isnan(none.ConfigurationEpoch) && ...
    isempty(absent) && isequaln(configured,calendar) && isempty(proof));
d=struct('ObservationID',"declared_CSI_obligation",'ConfigurationEpoch',0, ...
    'AssignmentDigest',"declared_UL_assignment",'HARQMappingDigest',"", ...
    'HARQACKBitCount',0,'ConfiguredGrantUCIBitCount',0, ...
    'CSIReportConfigID',obligation.ReportConfigID, ...
    'CSIConfigurationEpoch',obligation.ConfigurationEpoch);
context=sixgr.phy.ul.pusch.PUSCHUCIReceiveContext(d);
budget=context.bitBudget(report);
assert(budget.OACK==0 && budget.OCSI1==report.part1BitCount() && budget.OCSI2==0);
% TX report presence, rank, value and counts never determine the RX schema.
poison=grant; poison.ExpectedUCIBits=ones(99,1,'int8');
poison.ExpectedUCIPayload=struct('CSIPart1',ones(99,1),'CSIPart2',ones(101,1));
poison.UCIOnPUSCHCSIReportIdentity="wrong_report";
[same,sameReport,sameCalendar]=sixgr.truth.buildSharedPUSCHCSIReceiveObligation(cfg,poison);
assert(isequaln(same,obligation) && isequaln(sameReport,report) && isequaln(sameCalendar,calendar));
disabled=cfg; disabled.phy.csi.reportCSI=false;
localAbsent(disabled,grant,0);
nonoccasion=cfg;
nonoccasion.phy.csi.reportOffsetSlots=mod(cfg.phy.csi.reportOffsetSlots+1,5);
localAbsent(nonoccasion,grant,0);
gap=cfg; gap.phy.rsla.measurement_gaps=struct('enabled',true,'period_slots',5, ...
    'offset_slots',cfg.phy.csi.reportOffsetSlots,'length_slots',1);
localAbsent(gap,grant,1);
% A nonoverlapping symbol interval is a declared timing-contract fixture,
% not a new PHY grant. Keep its redundant canonical fields consistent.
nonoverlap=grant;
assert(calendar.StartSymbol>0,'Fixture requires a CSI resource after symbol zero.');
nonoverlap.SymbolAllocation=[0 1];
nonoverlap.TimingDecision.DataDecision.TargetStartSymbol=0;
nonoverlap.TimingDecision.DataDecision.TargetNumSymbols=1;
localAbsent(cfg,nonoverlap,1);
bad=cfg; bad.phy.csi.reportTrigger='aperiodic';
localReject(@()sixgr.truth.buildSharedPUSCHCSIReceiveObligation(bad,grant), ...
    'sixgr:truth:UnsupportedScheduledPUSCHCSITrigger');
bad=cfg; bad.phy.frame.DefaultIdentity.ULBWPID=cfg.phy.frame.DefaultIdentity.ULBWPID+1;
localReject(@()sixgr.truth.buildSharedPUSCHCSIReceiveObligation(bad,grant), ...
    'sixgr:truth:ScheduledPUSCHCSIBWPMismatch');
for value={NaN,.5,[true false],"true"}
    bad=cfg; bad.phy.csi.reportCSI=value{1};
    localReject(@()sixgr.truth.buildSharedPUSCHCSIReceiveObligation(bad,grant), ...
        'sixgr:truth:InvalidScheduledPUSCHCSIConfiguration');
end
localReject(@()sixgr.truth.buildSharedPUSCHCSIReceiveObligation(cfg,struct()), ...
    'sixgr:truth:MissingScheduledPUSCHCSIGrant');
fprintf('SHARED_PUSCH_CSI_RECEIVE_OBLIGATION_PASS independent_config_calendar no_RF_claim\n');
ok=true;
end

function localAbsent(cfg,grant,calendarRows)
[obligation,report,calendar]=sixgr.truth.buildSharedPUSCHCSIReceiveObligation(cfg,grant);
assert(obligation.ReportConfigID=="" && isnan(obligation.ConfigurationEpoch) && ...
    isempty(report) && height(calendar)==calendarRows);
end

function localReject(fn,id)
try, fn(); catch err
    assert(strcmp(err.identifier,id),'Expected %s; got %s: %s',id,err.identifier,err.message);
    return;
end
error('test:ExpectedRejection','Expected %s',id);
end
