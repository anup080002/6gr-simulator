function ok=testPeriodicPUCCHCSITimingAuthority()
% Config/schema/calendar checks only; no CSI RF delivery/accuracy claim.
setup6GRSimToolkit('Verbose',false,'RunToolboxChecks',false);
groups={@localEnums,@localInvalid,@localScope,@localProductionOwners};
names=["NR_period_and_offset_domain","malformed_period_and_offset", ...
    "configured_transport_and_inactive_scope","builder_and_obligation_owners"];
failures=strings(0,1);
for k=1:numel(groups)
    try
        groups{k}();
        fprintf('[PASS] PeriodicPUCCHCSITimingAuthority %s\n',names(k));
    catch cause
        failures(end+1,1)=names(k)+": "+string(cause.identifier)+" "+string(cause.message); %#ok<AGROW>
        fprintf(2,'[FAIL] PeriodicPUCCHCSITimingAuthority %s\n',failures(end));
    end
end
assert(isempty(failures),'testPeriodicPUCCHCSITimingAuthority:Failed', ...
    '%d/%d groups failed:\n%s',numel(failures),numel(groups),char(strjoin(failures,newline)));
ok=true;
end

function localEnums()
for period=[4 5 8 10 16 20 40 80 160 320]
    for offset=[0 period-1]
        cfg=localConfig(period,offset); original=cfg;
        assert(sixgr.phy.mimo.validatePeriodicPUCCHCSITiming(cfg));
        assert(isequaln(cfg,original),'Validation must not rewrite authored timing.');
        slots=1:2*period;
        expected=false(size(slots)); expected(offset+1:period:end)=true;
        assert(isequal(sixgr.truth.periodicCSIReportSlotMask(slots,period,offset),expected));
    end
end
end

function localInvalid()
for value={0,1,3,32,640,1.5,NaN,Inf,'10',true,1+1i,[5 10]}
    cfg=localConfig(value{1},0);
    reject(@()sixgr.phy.mimo.validatePeriodicPUCCHCSITiming(cfg), ...
        'sixgr:mimo:InvalidPeriodicPUCCHCSIPeriod');
end
for value={-1,10,0.5,NaN,Inf,'0',false,1+1i,[0 1]}
    cfg=localConfig(10,value{1});
    reject(@()sixgr.phy.mimo.validatePeriodicPUCCHCSITiming(cfg), ...
        'sixgr:mimo:InvalidPeriodicPUCCHCSIOffset');
end
end

function localScope()
for trigger={42,"bogus",["periodic","aperiodic"],char(['periodic';'periodic'])}
    bad=localConfig(10,8); bad.phy.csi.reportTrigger=trigger{1};
    reject(@()sixgr.phy.mimo.validatePeriodicPUCCHCSITiming(bad), ...
        'sixgr:mimo:InvalidCSIReportingTrigger');
end
for transport={42,["PUCCH","PUSCH"],"bogus"}
    bad=localConfig(10,8); bad.phy.csi.reportConfiguration.UCIChannel=transport{1};
    reject(@()sixgr.phy.mimo.validatePeriodicPUCCHCSITiming(bad), ...
        'sixgr:mimo:MissingCSIConfiguredTransport');
end
cfg=localConfig(10,8);
cfg.phy.csi.reportConfiguration.UCIChannel='PUSCH';
cfg.phy.csi.reportConfiguration.ConfiguredUCIChannel='PUCCH';
assert(sixgr.phy.mimo.validatePeriodicPUCCHCSITiming(cfg), ...
    'PUSCH remultiplexing must retain the original PUCCH report calendar.');
cfg.phy.csi.reportPeriodicitySlots=3;
reject(@()sixgr.phy.mimo.validatePeriodicPUCCHCSITiming(cfg), ...
    'sixgr:mimo:InvalidPeriodicPUCCHCSIPeriod');
cfg.phy.csi.reportConfiguration.ConfiguredUCIChannel='PUSCH';
assert(~sixgr.phy.mimo.validatePeriodicPUCCHCSITiming(cfg), ...
    'An independently PUSCH-configured report is outside this PUCCH validator.');
for trigger=["semi_persistent","aperiodic"]
    cfg=localConfig(NaN,NaN); cfg.phy.csi.reportTrigger=trigger;
    assert(~sixgr.phy.mimo.validatePeriodicPUCCHCSITiming(cfg));
end
cfg=localConfig(NaN,NaN); cfg.phy.csi.reportCSI=false;
cfg.phy.csi=rmfield(cfg.phy.csi,'reportConfiguration');
assert(~sixgr.phy.mimo.validatePeriodicPUCCHCSITiming(cfg));
cfg=localConfig(10,8); cfg.phy.csi=rmfield(cfg.phy.csi,'reportConfiguration');
reject(@()sixgr.phy.mimo.validatePeriodicPUCCHCSITiming(cfg), ...
    'sixgr:mimo:MissingCSIConfiguredTransport');
end

function localProductionOwners()
scenario=sixgr.lls6g.config.loadScenarioConfig(fullfile('simulator','configs','scenarios', ...
    'lls_tdd_n40_20mhz_64txru_4rx_cdlc100_impaired.yaml'));
s=scenario.toStruct();
cfg=sixgr.lls6g.buildInternalConfig(s,tempname);
assert(cfg.phy.csi.reportPeriodicitySlots==10 && cfg.phy.csi.reportOffsetSlots==8);
assert(sixgr.phy.mimo.validatePeriodicPUCCHCSITiming(cfg));
authored=struct('csi_acquisition_and_reporting',struct( ...
    'csi_report_periodicity_slots',3,'csi_report_offset_slots',0));
bad=sixgr.lls6g.config.normalizeScenarioAliases(sixgr.util.mergeStruct(s,authored),'Authority',authored);
reject(@()sixgr.lls6g.buildInternalConfig(bad,tempname), ...
    'sixgr:mimo:InvalidPeriodicPUCCHCSIPeriod');
identity=cfg.phy.frame.DefaultIdentity;
ue=struct('UEID',1,'RNTI',1,'ServingCell',1,'PUCCHCell',1, ...
    'ComponentCarrier',identity.ScheduledCCID,'ActiveULBWP',identity.ULBWPID);
calendar=sixgr.truth.buildPeriodicCSIReportObligations(cfg,ue,1,30);
assert(isequal(calendar.ReportSlot,[9;19;29]));
original=calendar;
again=sixgr.truth.buildPeriodicCSIReportObligations(cfg,ue,1,30);
assert(isequaln(original,again),'Validation must not shift or create report occasions.');
bad=cfg; bad.phy.csi.reportPeriodicitySlots=3; bad.phy.csi.reportOffsetSlots=0;
reject(@()sixgr.truth.buildPeriodicCSIReportObligations(bad,ue,1,30), ...
    'sixgr:mimo:InvalidPeriodicPUCCHCSIPeriod');
% No nominal occasion in this interval does not excuse an invalid calendar.
reject(@()sixgr.truth.buildPeriodicCSIReportObligations(bad,ue,2,2), ...
    'sixgr:mimo:InvalidPeriodicPUCCHCSIPeriod');
end

function cfg=localConfig(period,offset)
cfg=struct();
cfg.phy.csi=struct('reportCSI',true,'reportTrigger','periodic', ...
    'reportPeriodicitySlots',period,'reportOffsetSlots',offset, ...
    'reportConfiguration',struct('UCIChannel','PUCCH'));
end

function reject(callback,id)
try
    callback();
catch cause
    assert(strcmp(cause.identifier,id),'Expected %s; got %s: %s',id,cause.identifier,cause.message);
    return;
end
error('testPeriodicPUCCHCSITimingAuthority:MissingGuard','Expected %s.',id);
end
