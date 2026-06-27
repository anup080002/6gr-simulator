function tf = validateSRSConfiguredBandClaim(coverage, srsCfg)
%VALIDATESRSCONFIGUREDBANDCLAIM Validate configured-band/full/partial rules.

req = lower(string(srsCfg.CoverageRequirement));
switch req
    case "full_carrier"
        tf = logical(coverage.FullCarrierClaimValid);
    case "configured_band"
        targetRB = min(double(srsCfg.ExpectedNumRB), double(coverage.CarrierPRBCount));
        if targetRB >= double(coverage.CarrierPRBCount)
            tol = double(sixgr.util.structGet(srsCfg, "FullCarrierCoverageToleranceRB", ...
                sixgr.util.structGet(coverage, "FullCarrierCoverageToleranceRB", 1)));
        else
            tol = 0;
        end
        if ~(isscalar(tol) && isfinite(tol) && tol >= 0)
            tol = 0;
        end
        effectiveTargetRB = max(1, targetRB - min(round(tol), max(0, round(targetRB) - 1)));
        effectiveTargetPct = 100 * effectiveTargetRB / max(double(coverage.CarrierPRBCount), 1);
        configuredTargetPct = double(sixgr.util.structGet(srsCfg, "ExpectedBandwidthCoveragePercent", ...
            100 * targetRB / max(double(coverage.CarrierPRBCount), 1)));
        targetPct = min(configuredTargetPct, effectiveTargetPct);
        rbOk = double(coverage.OccupiedPRBCount) >= effectiveTargetRB;
        pctOk = double(coverage.CoveragePercent) + 1e-9 >= targetPct;
        tf = rbOk && pctOk && effectiveTargetRB > 0;
    case "partial_band_allowed"
        tf = double(coverage.OccupiedPRBCount) > 0;
    otherwise
        tf = false;
end
end
