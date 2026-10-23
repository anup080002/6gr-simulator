function ok=testReceivedCSIProvenanceClockDomains()
% Declared receiver/decision-clock contracts, not a waveform qualification.
% Exercise the production binder with both legacy caller Slot conventions.
setup6GRSimToolkit('Verbose',false);
[cfg,report,clock,ue,grant]=localFixture();
original=ue.CSIReportProvenance;
g0=sixgr.l2.mac.bindReceivedCSIProvenance(grant,ue,cfg);
oneBased=grant; oneBased.Slot=grant.Slot+1;
g1=sixgr.l2.mac.bindReceivedCSIProvenance(oneBased,ue,cfg);
assert(isequaln(rmfield(g0,'Slot'),rmfield(g1,'Slot')) && ...
    isequaln(g0.CSIReportProvenance,original) && ...
    isequaln(g0.CSIReportDecisionContext,clock), ...
    'Caller-defined Slot must not change the explicit control-decision result.');
assert(g0.CSIReportProvenance.ReceiverObservationBound && ...
    report.DeliveredSlot==grant.ControlAbsoluteSlot+1 && ...
    report.AvailableAtSample==clock.AtSample, ...
    'A completed report at this runtime decision boundary is causal.');
withoutLegacy=rmfield(grant,'Slot');
g=sixgr.l2.mac.bindReceivedCSIProvenance(withoutLegacy,ue,cfg);
assert(isequaln(g.CSIReportProvenance,original));
% Numeric storage class is not a slot origin. Preserve supplied report
% values while applying the same explicit conversion for single/uint data.
for numericClass=["single","uint32"]
    typedUE=ue; typedGrant=grant;
    for field=["SourceSlot","DueSlot","DeliveredSlot"]
        typedUE.CSIReportProvenance.(field)=cast(report.(field),numericClass);
    end
    typedGrant.ControlAbsoluteSlot=cast(grant.ControlAbsoluteSlot,numericClass);
    for callerSlot=[grant.Slot grant.Slot+1]
        typedGrant.Slot=cast(callerSlot,numericClass);
        g=sixgr.l2.mac.bindReceivedCSIProvenance(typedGrant,typedUE,cfg);
        assert(isequaln(g.CSIReportProvenance,typedUE.CSIReportProvenance));
    end
end

% A valid canonical timing record corroborates the explicit control slot.
withTiming=grant;
withTiming.TimingDecision=struct('Valid',true, ...
    'ControlAbsoluteSlot',grant.ControlAbsoluteSlot,'DataAbsoluteSlot',9);
g=sixgr.l2.mac.bindReceivedCSIProvenance(withTiming,ue,cfg);
assert(isequaln(g.CSIReportProvenance,original));
% Neither past nor future data slots serve as a decision clock.
for dataSlot0=[0 9 999]
    dataGrant=grant; dataGrant.ScheduledAbsoluteSlot=dataSlot0;
    g=sixgr.l2.mac.bindReceivedCSIProvenance(dataGrant,ue,cfg);
    assert(isequaln(g.CSIReportProvenance,original));
end

future=ue;
future.CSIReportDecisionContext.AtSample=report.AvailableAtSample-1;
mustFail(@()sixgr.l2.mac.bindReceivedCSIProvenance(grant,future,cfg), ...
    'sixgr:truth:FutureCSIProvenance');
future=ue; future.CSIReportProvenance.DeliveredSlot=report.DeliveredSlot+1;
lateData=grant; lateData.Slot=999; lateData.ScheduledAbsoluteSlot=999;
mustFail(@()sixgr.l2.mac.bindReceivedCSIProvenance(lateData,future,cfg), ...
    'sixgr:mac:FutureCSIProvenance');
earlyControl=grant; earlyControl.ControlAbsoluteSlot=grant.ControlAbsoluteSlot-1;
mustFail(@()sixgr.l2.mac.bindReceivedCSIProvenance(earlyControl,ue,cfg), ...
    'sixgr:mac:FutureCSIProvenance');
for field=["SourceSlot","DueSlot"]
    unordered=ue; unordered.CSIReportProvenance.(field)=report.DeliveredSlot+1;
    mustFail(@()sixgr.l2.mac.bindReceivedCSIProvenance(grant,unordered,cfg), ...
        'sixgr:mac:FutureCSIProvenance');
end
for field=["SourceSlot","DueSlot","DeliveredSlot"]
    for value={0,-1,NaN,Inf,2.5,[1 2],"5"}
        bad=ue; bad.CSIReportProvenance.(field)=value{1};
        mustFail(@()sixgr.l2.mac.bindReceivedCSIProvenance(grant,bad,cfg), ...
            'sixgr:mac:InvalidCSIProvenanceReportClock');
    end
end

missing=rmfield(grant,'ControlAbsoluteSlot');
missing.ScheduledAbsoluteSlot=999;
mustFail(@()sixgr.l2.mac.bindReceivedCSIProvenance(missing,ue,cfg), ...
    'sixgr:mac:MissingCSIProvenanceControlClock');
missing.TimingDecision=withTiming.TimingDecision;
mustFail(@()sixgr.l2.mac.bindReceivedCSIProvenance(missing,ue,cfg), ...
    'sixgr:mac:MissingCSIProvenanceControlClock');
for value={[],NaN,Inf,-1,4.5,[4 5],"4"}
    bad=grant; bad.ControlAbsoluteSlot=value{1};
    mustFail(@()sixgr.l2.mac.bindReceivedCSIProvenance(bad,ue,cfg), ...
        'sixgr:mac:InvalidCSIProvenanceControlClock');
end
bad=withTiming; bad.TimingDecision.ControlAbsoluteSlot=grant.ControlAbsoluteSlot+1;
mustFail(@()sixgr.l2.mac.bindReceivedCSIProvenance(bad,ue,cfg), ...
    'sixgr:mac:InvalidCSIProvenanceControlClock');
bad=withTiming; bad.TimingDecision.Valid=false;
mustFail(@()sixgr.l2.mac.bindReceivedCSIProvenance(bad,ue,cfg), ...
    'sixgr:mac:InvalidCSIProvenanceControlClock');
for value={[],struct([]),"",struct('Valid',true)}
    bad=grant; bad.TimingDecision=value{1};
    mustFail(@()sixgr.l2.mac.bindReceivedCSIProvenance(bad,ue,cfg), ...
        'sixgr:mac:InvalidCSIProvenanceControlClock');
end
% An absent or empty scalar record means timing is not yet resolved at the
% attachment boundary; neither substitutes for explicit ControlAbsoluteSlot.
pendingTiming=grant; pendingTiming.TimingDecision=struct();
g=sixgr.l2.mac.bindReceivedCSIProvenance(pendingTiming,ue,cfg);
assert(isequaln(g.CSIReportProvenance,original));

missing=rmfield(ue,'CSIReportDecisionContext');
mustFail(@()sixgr.l2.mac.bindReceivedCSIProvenance(grant,missing,cfg), ...
    'sixgr:mac:MissingCSIProvenanceDecisionClock');
for value={[],NaN,-1,4.5,[4000 4001]}
    bad=ue; bad.CSIReportDecisionContext.AtSample=value{1};
    mustFail(@()sixgr.l2.mac.bindReceivedCSIProvenance(grant,bad,cfg), ...
        'sixgr:mac:InvalidCSIProvenanceDecisionClock');
end
bad=ue; bad.CSIReportDecisionContext=rmfield(clock,'ClockDomain');
mustFail(@()sixgr.l2.mac.bindReceivedCSIProvenance(grant,bad,cfg), ...
    'sixgr:mac:InvalidCSIProvenanceDecisionClock');
for field=["ClockDomain","ClockEpoch","SampleRateHz"]
    bad=ue;
    if field=="ClockDomain", bad.CSIReportDecisionContext.(field)="another_owner_clock";
    else, bad.CSIReportDecisionContext.(field)=clock.(field)+1; end
    mustFail(@()sixgr.l2.mac.bindReceivedCSIProvenance(grant,bad,cfg), ...
        'sixgr:truth:CSIProvenanceClockMismatch');
end
bad=ue; bad.CSIReportProvenance.AvailableAtSample=NaN;
mustFail(@()sixgr.l2.mac.bindReceivedCSIProvenance(grant,bad,cfg), ...
    'sixgr:mac:InvalidCSIProvenanceDecisionClock');

% Preserve historical unbound records; a later clock cannot upgrade them.
historical=ue;
historical.CSIReportProvenance=sixgr.truth.captureReceivedCSIProvenance(report);
g=sixgr.l2.mac.bindReceivedCSIProvenance(grant,historical,cfg);
assert(~g.CSIReportProvenance.ReceiverObservationBound);
historical=rmfield(historical,'CSIReportDecisionContext');
g=sixgr.l2.mac.bindReceivedCSIProvenance(grant,historical,cfg);
assert(~g.CSIReportProvenance.ReceiverObservationBound);

% Existing replay/freeze boundaries return unchanged before any rebind.
% Deliberately remove new-decision evidence and poison latest feedback.
replay=rmfield(g0,'ControlAbsoluteSlot');
replay.HARQ=struct('IsRetransmission',true);
badUE=struct('CSIReportProvenance',struct('Version',"poison_latest"));
assert(isequaln(sixgr.l2.mac.bindReceivedCSIProvenance(replay,badUE,cfg),replay));
frozen=rmfield(g0,'ControlAbsoluteSlot'); frozen.PHYGrant=struct('IsFrozen',true);
assert(isequaln(sixgr.l2.mac.bindReceivedCSIProvenance(frozen,badUE,cfg),frozen));
ul=rmfield(grant,'ControlAbsoluteSlot'); ul.Direction="UL";
assert(isequaln(sixgr.l2.mac.bindReceivedCSIProvenance(ul,badUE,cfg),ul));
noReport=rmfield(grant,'ControlAbsoluteSlot');
assert(isequaln(sixgr.l2.mac.bindReceivedCSIProvenance(noReport,struct(),cfg),noReport));
fprintf('RECEIVED_CSI_PROVENANCE_CLOCK_DOMAINS_PASS explicit_control0=1 caller_slot_invariant=1 physical_qualification=0\n');
ok=true;
end

function [cfg,report,clock,ue,grant]=localFixture()
cfg=struct();
cfg.phy.csi.reportConfiguration=struct('ReportConfigID',"declared_clock_contract");
cfg.phy.csi.reportConfigurationEpoch=7;
report=struct('Direction',"DL",'UEIndex',1,'RNTI',701,'ServingCell',1, ...
    'SourceSlot',3,'DueSlot',4,'DeliveredSlot',5,'CSIReferenceSlot',3, ...
    'ReportIdentity',"declared_received_report", ...
    'CSIReportConfigID',"declared_clock_contract",'CSIConfigurationEpoch',7, ...
    'SourceSignal',"received_CSI_UCI",'CSIUCIDecodeOk',true, ...
    'ObservationID',"declared_receiver_window",'ReceiverContextDigest',"declared_schema", ...
    'ReceiverClockDomain',"shared_receiver_sample_clock/v1",'ReceiverClockEpoch',7, ...
    'ObservationStartSample',3900,'ObservationEndSampleExclusive',4000, ...
    'ObservationSampleRateHz',1e6,'AvailableAtSample',4000, ...
    'CQI',10,'RI',1,'PMI',0,'CRI',0);
clock=struct('ClockDomain',report.ReceiverClockDomain,'ClockEpoch',7, ...
    'SampleRateHz',1e6,'AtSample',4000);
ue=struct('RNTI',701,'UEIndex',1,'ServingCell',1, ...
    'CSIReportProvenance',sixgr.truth.captureReceivedCSIProvenance(report,clock), ...
    'CSIReportDecisionContext',clock);
grant=struct('Direction',"DL",'Slot',4,'ControlAbsoluteSlot',4,'RNTI',701);
end

function mustFail(f,id)
try, f(); catch e
    assert(strcmp(e.identifier,id),'Expected %s, got %s: %s',id,e.identifier,e.message);
    return;
end
error('sixgr:test:ExpectedFailure','Expected %s.',id);
end
