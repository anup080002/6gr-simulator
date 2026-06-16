function ok = testSRSFrequencyHoppingCoverage()
setup6GRSimToolkit("Verbose", false);
b = srsStrictAnchorResult();
hop = sixgr.phy.srs.validateSRSFrequencyHoppingCoverage(b.Config);
assert(~logical(hop.FrequencyHoppingRequested) && logical(hop.Ok), "Non-hopping SRS anchor must explicitly mark hopping not configured.");
bad = b.Config;
bad.FrequencyHopping = "intraSlot";
bad.CoverageRequirement = "full_carrier";
bad.FullCarrierSoundingRequired = true;
bad.C_SRS = 0;
bad.B_SRS = 0;
bad.ToolboxSRS.CSRS = 0;
bad.ToolboxSRS.BSRS = 0;
hopBad = sixgr.phy.srs.validateSRSFrequencyHoppingCoverage(bad);
assert(logical(hopBad.FrequencyHoppingRequested) && ~logical(hopBad.Ok), "Incomplete hopping coverage must fail full-carrier claim.");
ok = true;
end
