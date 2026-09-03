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

ok = true;
fprintf('testObservedREAllocationDeduplication passed.\n');
end
