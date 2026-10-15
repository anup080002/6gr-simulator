function ok=testH4100CSIRecoveryCadence()
% Exact H4 YAML -> production report adapter. Decoded-value boundary only;
% these CQI fixtures are not waveform measurements or physical UCI results.
setup6GRSimToolkit('Verbose',false);
scenario=sixgr.lls6g.config.loadScenarioConfig( ...
    'simulator/configs/scenarios/h4_100_cdlc100_connected_impaired_40db_gate.yaml');
cfg=sixgr.lls6g.buildInternalConfig(scenario,fullfile(tempdir,'h4_csi_recovery_cadence'));
assert(cfg.phy.csi.reportPeriodicitySlots==20 && ...
    cfg.phy.linkAdaptation.outageRecoveryMaxGapSlots==20 && ...
    cfg.phy.linkAdaptation.outageRecoveryPositiveCQIReports==2);
% The late-PUCCH fixture also lengthens the inherited reporting calendar.
% It must declare a compatible gap, not bypass the production validator.
clockScenario=sixgr.lls6g.config.loadScenarioConfig( ...
    'simulator/configs/validation/lls_pucch_feedback_clock_connected.yaml');
clockCfg=sixgr.lls6g.buildInternalConfig(clockScenario,tempname);
assert(clockCfg.phy.csi.reportPeriodicitySlots==20 && ...
    clockCfg.phy.linkAdaptation.outageRecoveryMaxGapSlots==20 && ...
    clockCfg.phy.linkAdaptation.outageRecoveryPositiveCQIReports==2);
invalidClock=clockCfg; invalidClock.phy.linkAdaptation.outageRecoveryMaxGapSlots=5;
localReject(@()sixgr.link.validateCSIRecoveryCadence(invalidClock));
bad=cfg; bad.phy.linkAdaptation.outageRecoveryMaxGapSlots=5;
localReject(@()sixgr.link.validateCSIRecoveryCadence(bad));
localReject(@()sixgr.link.computeLinkAdaptationDecision(bad,'DL',struct('CQI',13)));
raw=scenario.toStruct(); raw.link_adaptation.outage_recovery_max_gap_slots=5;
invalid=sixgr.lls6g.config.ScenarioConfig(raw, ...
    'SourceFiles',scenario.SourceFiles,'ConfigPath',scenario.ConfigPath, ...
    'ConfigHash',sixgr.lls6g.config.hashResolvedScenario(raw),'Kind','scenario');
localReject(@()sixgr.lls6g.buildInternalConfig(invalid, ...
    fullfile(tempdir,'h4_invalid_csi_recovery_cadence')));
other=bad; other.phy.linkAdaptation.innerLoopFlag=false;
localReject(@()sixgr.link.validateCSIRecoveryCadence(other));
% Disabled, single-report and aperiodic policies do not inherit an unrelated
% periodic two-report constraint. Their own runtime guards remain in force.
other=bad; other.phy.csi.reportCSI=false; sixgr.link.validateCSIRecoveryCadence(other);
other=bad; other.phy.csi.reportTrigger='aperiodic'; sixgr.link.validateCSIRecoveryCadence(other);
other=bad; other.phy.linkAdaptation.outageRecoveryPositiveCQIReports=1;
sixgr.link.validateCSIRecoveryCadence(other);
for period=[5 20 40]
    current=cfg; current.phy.csi.reportPeriodicitySlots=period;
    current.phy.linkAdaptation.outageRecoveryMaxGapSlots=period;
    state=localState(current);
    for k=1:3
        cqis=[0 13 13];
        [state,report]=localDeliver(state,cqis(k),19+(k-1)*period);
        if k==1
            assert(report.SchedulerResolvedCQI==0);
        elseif k==2
            assert(report.CQIOutageRecoveryPending && ...
                report.CQIOutageRecoveryPositiveCount==1 && isnan(report.SchedulerResolvedCQI));
        else
            assert(~report.CQIOutageRecoveryPending && ...
                report.CQIOutageRecoveryPositiveCount==2 && ...
                isfinite(report.SchedulerResolvedCQI) && isfinite(report.MCSIndex));
        end
    end
end
% A duplicate is not a second observation; a missed reporting period resets
% confirmation. Do not widen the gap automatically from observed traffic.
state=localState(cfg);
[state,~]=localDeliver(state,0,19);
[state,~]=localDeliver(state,13,39);
[state,duplicate]=localDeliver(state,13,39);
assert(duplicate.CQIOutageRecoveryPending && duplicate.CQIOutageRecoveryPositiveCount==1);
[state,late]=localDeliver(state,13,79);
assert(late.CQIOutageRecoveryPending && late.CQIOutageRecoveryPositiveCount==1);
[~,accepted]=localDeliver(state,13,99);
assert(~accepted.CQIOutageRecoveryPending && isfinite(accepted.SchedulerResolvedCQI));
assert(cfg.phy.linkAdaptation.rankIncreaseConfirmationReports==2);
fprintf('H4_CSI_RECOVERY_CADENCE_PASS periods=5,20,40 duplicate_and_gap_guards=1\n');
ok=true;
end

function state=localState(cfg)
state=struct('CfgMobility',cfg,'NumUsers',1,'DLSchedulers',{{}}, ...
    'ULSchedulers',{{}},'DLLinkAdaptationState',{{struct()}}, ...
    'ULLinkAdaptationState',{{struct()}},'SlotDuration_s',.0005);
end

function [state,report]=localDeliver(state,cqi,slot)
report=struct('CQI',cqi,'RI',1,'PMI',0,'CRI',0,'SINR_dB',NaN, ...
    'SourceSlot',slot-10,'DueSlot',slot,'DeliveredSlot',slot,'ServingCell',1);
[state,report]=sixgr.truth.CoupledTruthRuntime.applyDeliveredCSIAdaptationRuntime( ...
    state,report,1,'DL',struct());
end

function localReject(fn)
try
    fn();
catch failure
    assert(strcmp(failure.identifier,'sixgr:link:CSIRecoveryCadenceConflict'),failure.message);
    return;
end
error('test:MissingCSIRecoveryCadenceGuard','Contradictory periodic recovery policy was accepted.');
end
