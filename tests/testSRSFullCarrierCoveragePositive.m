function ok = testSRSFullCarrierCoveragePositive()
setup6GRSimToolkit("Verbose", false);
cov = srsStrictAnchorResult().Result.ArtifactTables.srs_coverage;
assert(any(logical(cov.FullCarrierClaimValid)), "Strict SRS full-carrier coverage claim must be valid for the positive anchor.");
assert(all(ismember(string(cov.BandwidthCoverageStatus),["full_carrier","within_configured_carrier_edge_tolerance"])), ...
    "Configured full-band policy must preserve exact versus tolerated-edge coverage.");
assert(all((string(cov.BandwidthCoverageStatus)=="full_carrier") == ...
    (cov.OccupiedPRBCount==cov.CarrierPRBCount)),"Literal full coverage requires every PRB.");
ok = true;
end
