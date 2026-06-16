function ok = testTRSGridGeneration()
setup6GRSimToolkit("Verbose", false);
b = trsStrictAnchorResult();
mapped = sixgr.phy.trs.generateTRSGrid(b.Config);
assert(~isempty(mapped.GridSlots) && height(mapped.ResourceMappingTable) > 0, ...
    "Strict TRS grid generation must produce resource mappings.");
assert(all(string(mapped.ResourceMappingTable.TruthStatus) == "real_lls_evidence"), ...
    "TRS resource mappings must be real evidence rows.");
ok = true;
end
