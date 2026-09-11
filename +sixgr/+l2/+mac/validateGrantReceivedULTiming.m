function evidence=validateGrantReceivedULTiming(cfg,grant,decision)
% Check received TAG applicability at the frozen actual UL occasion.
% This validates scheduling only; it neither transmits IQ nor asserts that
% the UE decoded this grant. The waveform preparation rechecks its binding.
evidence=struct();
context=sixgr.util.structGet(grant,'SharedULTimingContext',struct());
if isempty(fieldnames(context)), return; end
assert(decision.Valid,'sixgr:l2:mac:InvalidReceivedULTimingDecision', ...
    'Resolve the exact scheduling relation before validating its TAG lifetime.');
if upper(string(grant.Direction))=="UL"
    relation=decision.DataDecision;
elseif decision.HARQACKRequired
    relation=decision.HARQACKDecision;
else
    return; % No uplink occasion belongs to this HARQ-disabled DL grant.
end
assert(15*2^relation.TargetMu==context.ReceivedRARTiming.FirstULSCSkHz, ...
    'sixgr:l2:mac:ReceivedULTimingBWPChanged', ...
    'A different UL numerology requires received dedicated-BWP timing authority.');
fs=context.DLReference.SampleRateHz;
ticksPerSecond=double(sixgr.phy.frame.AbsoluteTime.TicksPerSecond);
nominal=double(relation.TargetSlotTick)/ticksPerSecond;
slotSamples=fs*1e-3/2^relation.TargetMu;
cfg.SharedULTimingContext=context;
evidence=sixgr.link.resolveConnectedULTransmissionTiming(cfg,nominal,fs,slotSamples);
assert(relation.TimingAdvanceTicks==evidence.TotalAdvanceTicks && ...
    grant.TimingAdvanceTicks==evidence.TotalAdvanceTicks && ...
    grant.TimingAdvanceOwnerRNTI==grant.RNTI, ...
    'sixgr:l2:mac:ReceivedULTimingDecisionMismatch', ...
    'The frozen timing relation and received per-UE TAG must agree.');
evidence.Procedure=relation.Procedure;
evidence.ScheduledULAbsoluteSlot=relation.TargetAbsoluteSlot;
evidence.Scope="validated_full_slot_contribution_not_transmitted_or_received";
end
