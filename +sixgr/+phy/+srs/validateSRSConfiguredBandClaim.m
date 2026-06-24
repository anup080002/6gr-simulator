function tf = validateSRSConfiguredBandClaim(coverage, srsCfg)
%VALIDATESRSCONFIGUREDBANDCLAIM Validate configured-band/full/partial rules.

req = lower(string(srsCfg.CoverageRequirement));
switch req
    case "full_carrier"
        tf = logical(coverage.FullCarrierClaimValid);
    case "configured_band"
        targetRB = min(double(srsCfg.ExpectedNumRB), double(coverage.CarrierPRBCount));
        targetPct = double(sixgr.util.structGet(srsCfg, "ExpectedBandwidthCoveragePercent", ...
            100 * targetRB / max(double(coverage.CarrierPRBCount), 1)));
        rbOk = double(coverage.OccupiedPRBCount) >= targetRB;
        pctOk = double(coverage.CoveragePercent) + 1e-9 >= targetPct;
        tf = rbOk && pctOk && targetRB > 0;
    case "partial_band_allowed"
        tf = double(coverage.OccupiedPRBCount) > 0;
    otherwise
        tf = false;
end
end
