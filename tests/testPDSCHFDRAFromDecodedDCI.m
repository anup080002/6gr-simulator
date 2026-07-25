function ok = testPDSCHFDRAFromDecodedDCI()
%TESTPDSCHFDRAFROMDECODEDDCI Exact type-0/type-1 allocation materialization.

setup6GRSimToolkit("Verbose", false, "RunToolboxChecks", false);
base = struct("PhysicalCarrierID", 0, "SingleCarrierOnly", true);

cfg0 = base;
cfg0.FDRAType = "type0_bitmap";
cfg0.RBBitmap = [1 0 1 0 1 0];
cfg0.GranularityRB = 4;
a0 = sixgr.pdsch.FDRAAllocator(cfg0, 24);
assert(isequal(a0.PRBSet, [0:3 8:11 16:19]));
assert(a0.RBStart == 0 && a0.NumRB == 12);

cfg1 = base;
cfg1.FDRAType = "type1_riv";
cfg1.RIV = 52 * (10 - 1) + 5;
a1 = sixgr.pdsch.FDRAAllocator(cfg1, 52);
assert(isequal(a1.PRBSet, 5:14));

dynamic = cfg0;
dynamic.FDRAType = "dynamic";
aDyn = sixgr.pdsch.FDRAAllocator(dynamic, 24, ...
    "DecodedFDRAType", "type0_bitmap", ...
    "ExecutionProfile", "connected_strict");
assert(isequal(aDyn.PRBSet, a0.PRBSet));

localAssertError(@() sixgr.pdsch.FDRAAllocator(dynamic, 24), ...
    "sixgr:pdsch:MissingDecodedFDRAType");
badBitmap = cfg0; badBitmap.RBBitmap = [1 2 0 0 0 0];
localAssertError(@() sixgr.pdsch.FDRAAllocator(badBitmap, 24), ...
    "sixgr:pdsch:InvalidRBGField");
badLength = cfg0; badLength.RBBitmap = [1 0];
localAssertError(@() sixgr.pdsch.FDRAAllocator(badLength, 24), ...
    "sixgr:pdsch:InvalidRBGField");
badRIV = cfg1; badRIV.RIV = 99999;
localAssertError(@() sixgr.pdsch.FDRAAllocator(badRIV, 52), ...
    "sixgr:pdsch:InvalidRIV");
fprintf("PDSCH FDRA: type-0, type-1, dynamic decode and four negatives passed.\\n");
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
error("testPDSCHFDRAFromDecodedDCI:MissingError", ...
    "Expected error %s was not thrown.", id);
end
