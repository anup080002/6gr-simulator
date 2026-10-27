function [plan,proposedAllocator]=buildCellRARResponsePlan(cellContext,grantPolicy,detections,receiverSampleRateHz,allocator,installedRNTIs)
%BUILDCELLRARRESPONSEPLAN Cell/received-RO owned allocation and MAC RAR plan.
% No UE ordinal, UE checkpoint, selected preamble/beam, TX waveform, or TX
% sample rate is accepted. The caller owns original detector/RO provenance
% and supplies the actual receiver clock and cell's installed grant policy.
% This value-only transaction proposes leases; the caller MUST NOT commit
% them until actual RAR waveform preparation succeeds. No PHY runs here.
% The existing aligned initial-UL-BWP RAR codec domain is retained; this
% extraction does not add arbitrary offset/narrow-BWP scheduling support.

localFields(cellContext,["ServingCell","CellId","PRACHAbsoluteSlot", ...
    "PRACHOccasionSymbol","PRACHFrequencyIndex","RARNTI"],"cellContext");
% The standalone RAConfig namespace permits zero (notably physical PCI0).
% A coupled owner's positive endpoint index remains that caller's contract.
limits=[0 flintmax;0 1007;0 flintmax;0 13;0 7;1 65535];
names=["ServingCell","CellId","PRACHAbsoluteSlot","PRACHOccasionSymbol","PRACHFrequencyIndex","RARNTI"];
for k=1:numel(names), localInteger(cellContext.(names(k)),limits(k,1),limits(k,2)); end
policyFields=["NSizeGrid","CarrierSCSkHz","CarrierCyclicPrefix","RARGrantConfig","Msg3PUSCH"];
if isfield(grantPolicy,'PUSCHCommonContext'),policyFields(end+1)="PUSCHCommonContext";end
localFields(grantPolicy,policyFields,"grantPolicy");
localFields(grantPolicy.RARGrantConfig,["field_layout","frequency_hopping","time_resource_assignment","tpc_command"],"RARGrantConfig");
localFields(grantPolicy.Msg3PUSCH,["PRBStart","NumPRB","SymbolStart","NumSymbols", ...
    "MCS","Modulation","TargetCodeRate","NLayers","RV","MCSTable","TransformPrecoding","EnablePTRS"],"Msg3PUSCH");
localInteger(grantPolicy.NSizeGrid,1,275);
% Validate original operands before arithmetic can coerce text or saturate
% integer classes. Preserve the original policy in provenance; calculate in
% double only after the numeric contract has been established.
prbStart=localInteger(grantPolicy.Msg3PUSCH.PRBStart,0,grantPolicy.NSizeGrid-1);
numPRB=localInteger(grantPolicy.Msg3PUSCH.NumPRB,1,grantPolicy.NSizeGrid);
assert(isnumeric(receiverSampleRateHz) && ~islogical(receiverSampleRateHz) && ...
    isreal(receiverSampleRateHz) && isscalar(receiverSampleRateHz) && ...
    isfinite(receiverSampleRateHz) && receiverSampleRateHz>0, ...
    'sixgr:truth:RARReceiverClockRequired','Use the actual received PRACH sample rate.');
assert(isa(allocator,'sixgr.mac.ra.RARIdentityAllocator') && isscalar(allocator), ...
    'sixgr:mac:ra:InvalidCellRARAllocator','Supply the original cell allocator value.');
validateattributes(installedRNTIs,{'numeric'},{'real','finite','integer','>=',1,'<=',65522});
assert(isstruct(detections) && (isempty(detections) || isvector(detections)), ...
    'sixgr:truth:MissingPRACHDetections','Use the complete original received candidate population.');
proposedAllocator=allocator;
plan=struct('ContractVersion',"cell_received_rar_plan/v1", ...
    'ResponseRequired',false,'Status',"no_received_preambles",'AllocatorCommitted',false, ...
    'PHYExecutionPerformed',false,'RuntimeAuthorityVerified',false, ...
    'Scope',"cell_detection_to_MAC_RAR_plan_not_waveform_or_received_RAR", ...
    'FrequencyReferenceScope',"existing_aligned_initial_UL_BWP_RAR_codec", ...
    'Source',"cell_received_preamble_set_disjoint_msg3_grants", ...
    'OriginalCellContext',cellContext,'OriginalGrantPolicy',grantPolicy, ...
    'OriginalDetections',detections,'ReceiverSampleRateHz',receiverSampleRateHz, ...
    'OriginalAllocatorAllocations',allocator.Allocations,'InstalledRNTIs',installedRNTIs, ...
    'SortedDetectionSourceIndices',zeros(0,1),'Assignments',struct([]), ...
    'TimingAdvance',struct([]),'ULGrants',struct([]),'RAR',struct());
if isempty(detections), plan.PlanSHA256=localHash(plan); return; end
rapid=zeros(numel(detections),1);
timing=cell(numel(detections),1);
for k=1:numel(detections)
    det=detections(k);
    assert(isfield(det,'Detected') && islogical(det.Detected) && isscalar(det.Detected) && det.Detected && ...
        isfield(det,'DetectedPreambleIndex'), ...
        'sixgr:mac:ra:RARUnacceptedDetection','Unknown or false detections cannot allocate a response.');
    rapid(k)=localInteger(det.DetectedPreambleIndex,0,63);
    assert(isfield(det,'PropagationTimingOffsetSamples') && ...
        localNumericScalar(det.PropagationTimingOffsetSamples) && ...
        isfinite(det.PropagationTimingOffsetSamples) && det.PropagationTimingOffsetSamples>=0, ...
        'sixgr:truth:RARMissingMeasuredTiming','Propagation timing must be an original nonnegative numeric measurement, not a cast token.');
    if isfield(det,'TimingOffsetSamples')
        assert(localNumericScalar(det.TimingOffsetSamples) && ~isinf(det.TimingOffsetSamples), ...
            'sixgr:truth:RARMissingMeasuredTiming','Raw timing must retain its original numeric scalar or unavailable NaN.');
    end
    % Preserve optional original identity/clock assertions when a receiver
    % supplies them. Their absence is not manufactured as an attestation.
    for name=names
        if isfield(det,name)
            assert(isequal(det.(name),cellContext.(name)), ...
                'sixgr:truth:RARDetectionContextMismatch','A detection belongs to another cell/received occasion.');
        end
    end
    if isfield(det,'SampleRateHz')
        assert(isequal(det.SampleRateHz,receiverSampleRateHz), ...
            'sixgr:truth:RARDetectionContextMismatch','Detection and receiver sample clocks disagree.');
    end
    timing{k}=sixgr.phy.ra.estimateTimingAdvanceFromPRACH(det,receiverSampleRateHz,grantPolicy.CarrierSCSkHz);
    assert(timing{k}.Valid,'sixgr:truth:RARMissingMeasuredTiming','RAR requires original per-preamble measured timing.');
end
assert(numel(unique(rapid))==numel(rapid),'sixgr:mac:ra:DuplicateRARRAPID', ...
    'One original detection per RAPID is required; do not silently merge duplicate measurements.');
[rapid,order]=sort(rapid); ordered=detections(order); timing=timing(order);
plan.SortedDetectionSourceIndices=order;
assignments=cell(numel(ordered),1); created=false(numel(ordered),1);
for k=1:numel(ordered)
    [proposedAllocator,assignments{k},created(k)]=proposedAllocator.reserve(cellContext,ordered(k),installedRNTIs);
end
prior=allocator.Allocations; same=false(1,numel(prior));
if ~isempty(prior)
    same=[prior.ServingCell]==cellContext.ServingCell & ...
        [prior.PRACHAbsoluteSlot]==cellContext.PRACHAbsoluteSlot & ...
        [prior.PRACHOccasionSymbol]==cellContext.PRACHOccasionSymbol & ...
        [prior.PRACHFrequencyIndex]==cellContext.PRACHFrequencyIndex;
end
if ~any(created)
    assert(isequal(sort([prior(same).RAPID]).',rapid) && ...
        all([prior(same).CellId]==cellContext.CellId) && all([prior(same).RARNTI]==cellContext.RARNTI), ...
        'sixgr:truth:RARDetectionSetChanged','A frozen received occasion must retain its complete original RAPID set.');
    plan.Status="already_reserved_received_occasion_no_duplicate_TX";
    plan.Assignments=vertcat(assignments{:}); plan.TimingAdvance=vertcat(timing{:});
    plan.PlanSHA256=localHash(plan); return;
end
assert(all(created),'sixgr:truth:RARDetectionSetChanged', ...
    'A frozen occasion response cannot acquire new RAPIDs from another callback.');
assert(~any(same),'sixgr:truth:RARMultiResponseMultiplexingRequired', ...
    'One received occasion needs one multiplexed RAR, not superposed separately prepared responses.');
responses=cell(numel(ordered),1); grants=responses;
for k=1:numel(ordered)
    assigned=grantPolicy;
    assigned.Msg3PUSCH.PRBStart=prbStart+(k-1)*numPRB;
    assigned.Msg3PUSCH.NumPRB=numPRB;
    assert(assigned.Msg3PUSCH.PRBStart+assigned.Msg3PUSCH.NumPRB<=grantPolicy.NSizeGrid, ...
        'sixgr:truth:RARMsg3CapacityExceeded','No overlapping or out-of-BWP Msg3 allocations may be issued.');
    grants{k}=sixgr.mac.ra.buildRARULGrant(assigned);
    responses{k}=sixgr.mac.ra.encodeMACRAR('RAPID',ordered(k).DetectedPreambleIndex, ...
        'TimingAdvanceCommand',timing{k}.TimingAdvanceCommand, ...
        'TemporaryCRNTI',assignments{k}.TemporaryCRNTI,'ULGrant',grants{k});
end
plan.ResponseRequired=true; plan.Status="prepared_MAC_RAR_plan_uncommitted";
plan.RAR=sixgr.mac.ra.multiplexMACRAR(vertcat(responses{:}));
plan.Assignments=vertcat(assignments{:}); plan.TimingAdvance=vertcat(timing{:});
plan.ULGrants=vertcat(grants{:}); plan.PlanSHA256=localHash(plan);
end
function localFields(value,names,label)
assert(isstruct(value) && isscalar(value) && ...
    isequal(sort(string(fieldnames(value))),sort(names(:))), ...
    'sixgr:mac:ra:InvalidCellRARPlanContext','%s must contain exactly its cell-owned operands, no UE/checkpoint fields.',label);
end
function v=localInteger(v,lo,hi)
assert(isnumeric(v) && ~islogical(v) && isreal(v) && isscalar(v) && isfinite(v) && ...
    v==fix(v) && v>=lo && v<=hi,'sixgr:mac:ra:InvalidCellRARPlanContext','Require original finite integer cell/grant operands.');
v=double(v);
end
function h=localHash(value)
h=string(sixgr.util.sha256Hex(jsonencode(sixgr.util.jsonSafeValue(value))));
end
function yes=localNumericScalar(value)
yes=isnumeric(value) && ~islogical(value) && isreal(value) && isscalar(value);
end
