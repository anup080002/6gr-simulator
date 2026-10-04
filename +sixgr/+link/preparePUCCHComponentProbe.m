function [probe,carrier,evidence] = preparePUCCHComponentProbe(cfg,trialIndex)
% Configured isolated coding probe; never a causal connected CSI report.
arguments
    cfg (1,1) struct
    trialIndex (1,1) double {mustBeInteger,mustBePositive}
end
p = sixgr.util.structGet(cfg,'validation.pucch_resources.component_probe',struct());
fields = {'evidence_scope','ue_id','rnti','serving_cell','first_slot_zero_based', ...
    'period_slots','csi_part1_bit_count','csi_part2_bit_count'};
assert(isstruct(p) && isscalar(p) && all(isfield(p,fields)), ...
    'sixgr:link:MissingPUCCHComponentProbe', ...
    'Standalone PUCCH trials require explicit pucch_resources.component_probe configuration.');
assert(isfield(p,'enabled') && islogical(p.enabled) && isscalar(p.enabled), ...
    'sixgr:link:InvalidPUCCHComponentProbe','Configure component_probe.enabled explicitly.');
assert(p.enabled,'sixgr:link:DisabledPUCCHComponentProbe', ...
    'An isolated PUCCH coding probe must be explicitly enabled; connected feedback is a separate runtime path.');
assert(isequal(string(p.evidence_scope),"isolated_known_payload_not_causal_feedback"), ...
    'sixgr:link:InvalidPUCCHComponentProbe','Known payload probes cannot claim connected CSI reception.');
minimum = [1 1 0 0 1 1 0]; maximum = [flintmax 65519 flintmax flintmax flintmax flintmax flintmax];
for k=2:numel(fields)
    value=p.(fields{k});
    assert(isnumeric(value) && isscalar(value) && isreal(value) && isfinite(value) && ...
        value==fix(value) && value>=minimum(k-1) && value<=maximum(k-1), ...
        'sixgr:link:InvalidPUCCHComponentProbe','Invalid component-probe field %s.',fields{k});
end
identity = sixgr.util.structGet(cfg,'phy.frame.DefaultIdentity',struct());
assert(all(isfield(identity,{'ScheduledCCID','ULBWPID'})), ...
    'sixgr:link:MissingPUCCHComponentIdentity','Use the installed carrier and UL BWP identity.');
ue = struct('UEID',p.ue_id,'RNTI',p.rnti,'ServingCell',p.serving_cell, ...
    'PUCCHCell',p.serving_cell,'ComponentCarrier',identity.ScheduledCCID,'ActiveULBWP',identity.ULBWPID);
slot0 = p.first_slot_zero_based+(trialIndex-1)*p.period_slots;
assert(isfinite(slot0) && slot0<flintmax,'sixgr:link:InvalidPUCCHComponentProbe','Probe slot overflow.');
[~,~,~,partition] = sixgr.truth.CoupledTruthRuntime.resolveSlotPartition(cfg,slot0+1);
ownership = repmat('D',1,partition.SymbolsPerSlot);
ul = partition.ULSymbolAllocation;
ownership(ul(1)+(1:ul(2))) = 'U';
% All other symbols remain unavailable for UL; never resolve flexible/guard
% symbols as uplink merely to make a requested component resource fit.
frame = struct('K1',0,'K1Source',"configured_component_occasion", ...
    'PDSCHEndSlot',slot0+1,'TargetSlot',slot0+1, ...
    'SlotSymbolOwnership',string(ownership),'FlexibleResolutionProvided',false);
seed = sixgr.util.structGet(cfg,'run.seed',NaN);
assert(isnumeric(seed) && isscalar(seed) && isfinite(seed) && seed>=0 && seed==fix(seed), ...
    'sixgr:link:InvalidPUCCHComponentSeed','Retain the configured integer seed.');
seed = mod(double(seed)+trialIndex-1,2^32);
stream = RandStream('mt19937ar','Seed',seed);
part1 = int8(randi(stream,[0 1],p.csi_part1_bit_count,1));
part2 = int8(randi(stream,[0 1],p.csi_part2_bit_count,1));
probe = sixgr.phy.pucch.PUCCHConfigBuilder.connectedCSI(cfg,ue,part1,part2,frame);
% Reuse exact configured resource/coding/power validation, but explicitly
% disqualify this planned known-payload trial from connected-mode evidence.
a = probe.Assignment;
data = a.Data;
data.AssignmentSource = "calibration";
data.ConnectedModeEvidenceEligible = false;
data.CollisionResolution = "calibration_isolated";
probe.Assignment = sixgr.phy.pucch.PUCCHTransmissionAssignment( ...
    data,a.Resource,a.PowerControlState,a.SpatialRelationState);
probe.RuntimeConfig = sixgr.truth.attachFixedLinkRuntimeAntennaContext(cfg,1,1);
probe.RuntimeConfig.lls6g.userContext.UEIndex = p.ue_id;
probe.RuntimeConfig.lls6g.userContext.RNTI = p.rnti;
probe.RuntimeConfig.run.seed = seed;
carrier = sixgr.phy.grid.makeCarrier(cfg);
carrier.NSlot = mod(slot0,carrier.SlotsPerFrame);
carrier.NFrame = mod(floor(slot0/carrier.SlotsPerFrame),1024);
evidence = struct('EvidenceScope',string(p.evidence_scope),'Seed',seed, ...
    'SlotOneBased',slot0+1,'AbsoluteSlotZeroBased',slot0,'UEID',p.ue_id,'RNTI',p.rnti, ...
    'ExpectedBitCount',p.csi_part1_bit_count+p.csi_part2_bit_count);
end
