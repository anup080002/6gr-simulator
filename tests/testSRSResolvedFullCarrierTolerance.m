function ok = testSRSResolvedFullCarrierTolerance()
setup6GRSimToolkit("Verbose", false);

fullCfg = struct();
fullCfg.CoverageRequirement = "full_carrier";
fullCfg.FullCarrierSoundingRequired = true;
fullCfg.ExpectedNumRB = 273;
fullCfg.FullCarrierCoverageToleranceRB = 1;

fullCoverage = struct();
fullCoverage.OccupiedPRBCount = 272;
fullCoverage.CarrierPRBCount = 273;
fullCoverage.CoveragePercent = 100 * 272 / 273;
fullCoverage.BandwidthCoverageStatus = "within_configured_carrier_edge_tolerance";
fullCoverage.FullCarrierCoverageToleranceRB = 1;
fullCoverage.FullCarrierEffectiveTargetRB = 272;
fullCoverage.FullCarrierClaimValid = true;
assert(sixgr.phy.srs.validateSRSFullCarrierClaim(fullCoverage, fullCfg), ...
    "A 273-RB full-carrier SRS request resolved to 272 RB must pass the declared one-RB tolerance.");
mislabel=fullCoverage; mislabel.BandwidthCoverageStatus="full_carrier";
assert(~sixgr.phy.srs.validateSRSFullCarrierClaim(mislabel,fullCfg), ...
    '272/273 must never be labelled literal full-carrier coverage.');
carrier=nrCarrierConfig('NSizeGrid',273); srs=nrSRSConfig;
coverage=sixgr.phy.srs.computeSRSCoverage(carrier,srs,(1:12:272*12).',fullCfg);
assert(coverage.OccupiedPRBCount==272 && coverage.CoverageGapRB==1 && ...
    ~coverage.LiteralFullCarrierCoverage && coverage.FullCarrierClaimValid && ...
    coverage.BandwidthCoverageStatus=="within_configured_carrier_edge_tolerance");
coverage=sixgr.phy.srs.computeSRSCoverage(carrier,srs,(1:12:273*12).',fullCfg);
assert(coverage.LiteralFullCarrierCoverage && coverage.BandwidthCoverageStatus=="full_carrier");
assert(sixgr.phy.srs.validateSRSConfiguredBandClaim(fullCoverage, fullCfg), ...
    "Full-carrier coverage must also satisfy the configured-band gate.");

badCoverage = fullCoverage;
badCoverage.OccupiedPRBCount = 271;
badCoverage.CoveragePercent = 100 * 271 / 273;
badCoverage.BandwidthCoverageStatus = "partial_band";
assert(~sixgr.phy.srs.validateSRSFullCarrierClaim(badCoverage, fullCfg), ...
    "The tolerance must not hide coverage gaps larger than one RB.");

configuredCfg = fullCfg;
configuredCfg.CoverageRequirement = "configured_band";
configuredCfg.FullCarrierSoundingRequired = false;
configuredCoverage = fullCoverage;
configuredCoverage.BandwidthCoverageStatus = "partial_band";
configuredCoverage.FullCarrierEffectiveTargetRB = 273;
assert(~sixgr.phy.srs.validateSRSFullCarrierClaim(configuredCoverage, configuredCfg), ...
    "Configured-band SRS must not be relabeled as a full-carrier claim.");
assert(sixgr.phy.srs.validateSRSConfiguredBandClaim(configuredCoverage, configuredCfg), ...
    "Configured-band validation must accept the resolved 272-RB SRS span for a 273-RB BWP request.");

ok = true;
end
