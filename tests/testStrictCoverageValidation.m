function ok = testStrictCoverageValidation()
%TESTSTRICTCOVERAGEVALIDATION Strict mode must reject skipped link coverage.

setup6GRSimToolkit("Verbose", false);

cfg = sixgr.config.defaultConfig();
cfg.run.strictMode = true;

cfgPBCH = cfg;
cfgPBCH.phy.ssb.enable = false;
localAssertThrows(@() sixgr.link.runCellSearch_MIB_SIB1(cfgPBCH, "NumSubframes", 10), ...
    "sixgr:link:StrictCoverageDisabled", "PBCH/SSB strict coverage");

cfgPRACH = cfg;
cfgPRACH.phy.prach.enable = false;
localAssertThrows(@() sixgr.link.runPRACHDetection(cfgPRACH, "SNR_dB", 0), ...
    "sixgr:link:StrictCoverageDisabled", "PRACH strict coverage");

cfgPDSCH = cfg;
cfgPDSCH.phy.pdsch.enable = false;
localAssertThrows(@() sixgr.link.runDLPDSCHThroughput(cfgPDSCH, "NumFrames", 1, "SNR_dB", 0), ...
    "sixgr:link:StrictCoverageDisabled", "PDSCH strict coverage");

cfgPUSCH = cfg;
cfgPUSCH.phy.pusch.enable = false;
localAssertThrows(@() sixgr.link.runULPUSCHThroughput(cfgPUSCH, "NumFrames", 1, "SNR_dB", 0), ...
    "sixgr:link:StrictCoverageDisabled", "PUSCH strict coverage");

cfgSRS = cfg;
cfgSRS.phy.srs.enable = false;
localAssertThrows(@() sixgr.link.runSRSChannelEstimation(cfgSRS, "SNR_dB", 0), ...
    "sixgr:link:StrictCoverageDisabled", "SRS strict coverage");

ok = true;
end

function localAssertThrows(fn, expectedId, label)
threw = false;
try
    fn();
catch ME
    threw = contains(string(ME.identifier), string(expectedId));
end
assert(threw, "%s must throw %s.", label, expectedId);
end
