function tf = validateSRSConfiguredBandClaim(coverage, srsCfg)
%VALIDATESRSCONFIGUREDBANDCLAIM Validate configured-band/full/partial rules.

req = lower(string(srsCfg.CoverageRequirement));
switch req
    case "full_carrier"
        tf = logical(coverage.FullCarrierClaimValid);
    case "configured_band"
        tf = double(coverage.OccupiedPRBCount) >= min(double(srsCfg.ExpectedNumRB), double(coverage.CarrierPRBCount));
    case "partial_band_allowed"
        tf = double(coverage.OccupiedPRBCount) > 0;
    otherwise
        tf = false;
end
end
