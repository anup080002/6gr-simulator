function ok = testPDSCHTDRAFromDecodedDCI()
%TESTPDSCHTDRAFROMDECODEDDCI Exact symbol and slot-direction allocation.

setup6GRSimToolkit("Verbose", false, "RunToolboxChecks", false);
rowA = struct("StartSymbol", 0, "NumSymbols", 14, "MappingType", "A", ...
    "SchedulingOffsetSymbols", 0, "SchedulingOffsetSlots", 0);
a = sixgr.pdsch.TDRAAllocator(rowA, "SymbolsPerSlot", 14, ...
    "ExecutionProfile", "connected_strict", "SlotDirection", "DL");
assert(isequal(a.SymbolAllocation, [0 14]) && a.MappingType == "A");

rowB = struct("StartSymbol", 3, "NumSymbols", 7, "MappingType", "B");
b = sixgr.pdsch.TDRAAllocator(rowB, "SymbolsPerSlot", 12, ...
    "ExecutionProfile", "connected_strict", "SlotDirection", "FLEXIBLE", ...
    "DLAllowedSymbols", [false false false true(1,9)]);
assert(isequal(b.SymbolAllocation, [3 7]) && b.SymbolsPerSlot == 12);

inter = sixgr.pdsch.TDRAAllocator(rowB, "SymbolsPerSlot", 14, ...
    "RepetitionMode", "inter_slot", "RepetitionCount", 3);
assert(isequal(inter.CopyTable.SlotOffset.', [0 1 2]));
assert(inter.CrossSlotMaterializationStatus == ...
    "materialized_from_absolute_slot_offsets");

localAssertError(@() sixgr.pdsch.TDRAAllocator(rowB, ...
    "ExecutionProfile", "connected_strict"), ...
    "sixgr:pdsch:MissingFrameSymbolCount");
overflow = rowB; overflow.StartSymbol = 10; overflow.NumSymbols = 5;
localAssertError(@() sixgr.pdsch.TDRAAllocator(overflow, ...
    "SymbolsPerSlot", 14), "sixgr:pdsch:InvalidTDRA");
localAssertError(@() sixgr.pdsch.TDRAAllocator(rowB, ...
    "SymbolsPerSlot", 14, "SlotDirection", "UL"), ...
    "sixgr:pdsch:InvalidSlotDirection");
badMap = rowB; badMap.MappingType = "single_mapping_type_baseline";
localAssertError(@() sixgr.pdsch.TDRAAllocator(badMap, ...
    "SymbolsPerSlot", 14), "sixgr:pdsch:InvalidMappingType");
fprintf("PDSCH TDRA: mapping A/B, extended CP, repetition and four negatives passed.\\n");
ok = true;
end

function localAssertError(fn, id)
try
    fn();
catch ME
    assert(string(ME.identifier) == string(id), ...
        "Expected %s, got %s.", id, ME.identifier);
    return;
end
error("testPDSCHTDRAFromDecodedDCI:MissingError", ...
    "Expected error %s was not thrown.", id);
end
