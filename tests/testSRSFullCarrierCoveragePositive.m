function ok = testSRSFullCarrierCoveragePositive()
setup6GRSimToolkit("Verbose", false);
cov = srsStrictAnchorResult().Result.ArtifactTables.srs_coverage;
assert(any(logical(cov.FullCarrierClaimValid)), "Strict SRS full-carrier coverage claim must be valid for the positive anchor.");
assert(any(string(cov.BandwidthCoverageStatus) == "full_carrier"), "Strict SRS coverage status must be full_carrier.");
ok = true;
end
