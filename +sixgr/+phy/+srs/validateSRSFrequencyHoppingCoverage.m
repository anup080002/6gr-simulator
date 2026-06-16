function result = validateSRSFrequencyHoppingCoverage(srsCfg)
%VALIDATESRSFREQUENCYHOPPINGCOVERAGE Validate cumulative SRS RB coverage.

mapping = sixgr.phy.srs.generateSRSSymbolsAndIndices(srsCfg);
coverage = mapping.Coverage;
requested = lower(strtrim(string(srsCfg.FrequencyHopping))) ~= "neither" || double(srsCfg.BHop) > 0;
if requested
    ok = logical(coverage.FullCarrierClaimValid) || string(srsCfg.CoverageRequirement) ~= "full_carrier";
    status = string(sixgr.phy.srs.localTernary(ok, ...
        "frequency_hopping_cumulative_coverage_valid", ...
        "frequency_hopping_cumulative_coverage_incomplete"));
else
    ok = true;
    status = "frequency_hopping_not_configured";
end
result = struct();
result.FrequencyHoppingRequested = logical(requested);
result.CoveragePercent = double(coverage.CoveragePercent);
result.OccupiedPRBCount = double(coverage.OccupiedPRBCount);
result.CarrierPRBCount = double(coverage.CarrierPRBCount);
result.FullCarrierClaimValid = logical(coverage.FullCarrierClaimValid);
result.Ok = logical(ok);
result.Status = string(status);
result.ConfigHash = string(srsCfg.ConfigHash);
end
