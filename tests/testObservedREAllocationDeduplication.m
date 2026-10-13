function ok = testObservedREAllocationDeduplication()
%TESTOBSERVEDREALLOCATIONDEDUPLICATION Exact replay is not physical occupancy.

base = table(0, 1, 0, 0, 12, "DL", "PDSCH", "alloc_a", ...
    'VariableNames', {'absolute_slot','symbol_index','port_index', ...
    'subcarrier_start','subcarrier_count','direction','channel','allocation_id'});
base.optional_measurement = NaN;
differentAllocation = base;
differentAllocation.allocation_id(:) = "alloc_b";
differentPort = base;
differentPort.port_index(:) = 1;
metadataRefresh = base;
metadataRefresh.optional_measurement(:) = 17;

[deduped, removed] = sixgr.truth.deduplicateObservedREAllocation( ...
    [base; base; metadataRefresh; differentAllocation; differentPort]);
assert(removed == 2, ...
    'Repeated physical RE observations must be removed despite NaN or refreshed metadata.');
assert(height(deduped) == 3, ...
    'Distinct allocation and port observations must not be collapsed.');
assert(isequaln(deduped(1, :), base), ...
    'Stable de-duplication must preserve first-observation ordering.');
assert(any(deduped.allocation_id == "alloc_b"), ...
    'A distinct overlapping allocation must remain auditable.');
assert(any(deduped.port_index == 1), ...
    'A distinct physical port must remain auditable.');

% Declared validator inputs, not a physical capture. Independent local
% clocks must retain SNR/seed/trial/user identity through de-duplication.
base.cell_id=1; base.ue_id=1; base.ObservationUEIndex=1;
base.ConfiguredSNR_dB=18; base.Seed=42; base.TrialIndex=1;
bound=sixgr.truth.bindIndependentREObservation(base);
other=base; other.ConfiguredSNR_dB=30;
other=sixgr.truth.bindIndependentREObservation(other);
[joint,n]=sixgr.truth.deduplicateObservedREAllocation([bound;bound;other]);
assert(height(joint)==2 && n==1 && numel(unique(joint.ObservationID))==2);
cellRS=base; cellRS.channel="CSI-RS"; cellRS.ue_id=NaN;
cellRS=sixgr.truth.bindIndependentREObservation(cellRS);
assert(cellRS.ObservationID==bound.ObservationID && isnan(cellRS.ue_id));
bad=bound; bad.ConfiguredSNR_dB=19;
localReject(@()sixgr.truth.bindIndependentREObservation(bad),'sixgr:truth:IndependentREIdentityMismatch');
localReject(@()sixgr.truth.bindIndependentREObservation(removevars(base,'Seed')), ...
    'sixgr:truth:MissingIndependentREIdentity');
for invalid={NaN,Inf,-1,0,0.5}
    bad=base; bad.TrialIndex=invalid{1};
    localReject(@()sixgr.truth.bindIndependentREObservation(bad),'sixgr:truth:InvalidIndependentREIdentity');
end

ok = true;
fprintf('testObservedREAllocationDeduplication passed.\n');
end

function localReject(fn,id)
try, fn(); catch cause
    assert(strcmp(cause.identifier,id),'Expected %s, got %s.',id,cause.identifier); return;
end
error('test:MissingIndependentRERejection','Invalid observation identity was accepted.');
end
