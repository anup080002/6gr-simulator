function ok = testChannelComplianceTruth()
%TESTCHANNELCOMPLIANCETRUTH Verify large-scale channel compliance metadata stays honest.

setup6GRSimToolkit("Verbose", false);

cfgNorm = sixgr.config.defaultConfig();
cfgNorm.run.strictMode = true;
cfgNorm = sixgr.config.normalizeConfig(cfgNorm);
assert(strcmpi(char(string(sixgr.util.structGet(cfgNorm, "channel.complianceMode", ""))), "strict_38901"), ...
    "normalizeConfig must promote run.strictMode into channel.complianceMode when no explicit mode is supplied.");

cfgApprox = sixgr.config.defaultConfig();
cfgApprox.channel.model = "TR38901";
cfgApprox.channel.pathlossModel = "ABG";
cfgApprox.channel.pathloss.model = "ABG";
cfgApprox.channel.complianceMode = "approximate_38901_plus";
cfgApprox.channel.shadowFadingEnabled = false;
cfgApprox.channel.shadowSigma_dB = 0;
cfgApprox.channel.losEnabled = true;
cfgApprox.channel.pathlossEnabled = true;
cfgApprox.channel.o2i.model = "low";
cfgApprox.channel.propagationScenario = "UMa";

pl = sixgr.channel.TR38901Plus(cfgApprox, "Scenario", "UMa", "Seed", 11);
assert(strcmpi(char(string(pl.ChannelComplianceMode)), "approximate_38901_plus"), ...
    "TR38901Plus must retain the configured channel compliance mode.");
assert(strcmpi(char(string(pl.PathlossModelSource)), "configured_abg_large_scale_model") && ...
    strcmpi(char(string(pl.PathlossComplianceStatus)), "configured_abg_not_strict_38901") && ...
    ~logical(pl.FallbackUsedForPathloss), ...
    "ABG pathloss must stay labeled as approximate rather than strict or fallback.");

[pl_dB, los, ex] = pl.pathloss([0; 0; 25], [50; 0; 1.5], ...
    "Scenario", "UMa", "IndoorRx", true, "IndoorDistance_m", 8);
assert(isfinite(double(pl_dB)) && islogical(logical(los)), ...
    "Approximate pathloss evaluation must still produce usable outputs.");
assert(strcmpi(char(string(ex.pathlossModelSource)), "configured_abg_large_scale_model") && ...
    strcmpi(char(string(ex.pathlossComplianceStatus)), "configured_abg_not_strict_38901"), ...
    "Pathloss metadata must survive the runtime pathloss call.");
assert(strcmpi(char(string(ex.o2iModelSource)), "tr38901_table_7_4_3_1_low_loss_building") && ...
    strcmpi(char(string(ex.o2iComplianceStatus)), "strict_38901_o2i_model"), ...
    "Low-loss O2I metadata must identify the TR 38.901 Table 7.4.3-1 model.");
assert(strcmpi(char(string(ex.losProbabilitySource)), "tr38901_uma_closed_form_los_probability") && ...
    strcmpi(char(string(ex.losComplianceStatus)), "scenario_specific_tr38901_curve"), ...
    "Known LOS scenarios must report the scenario-specific closed-form source.");

cfgStrictABG = cfgApprox;
cfgStrictABG.channel.complianceMode = "strict_38901";
localAssertThrows(@() sixgr.channel.TR38901Plus(cfgStrictABG, "Scenario", "UMa", "Seed", 13), ...
    "TR38901Plus:StrictPathlossModel");

[~, losStatusUnknown] = sixgr.channel.LOSProbability("mysteryScenario", 100);
assert(strcmpi(char(string(losStatusUnknown.Source)), "generic_exponential_fallback") && ...
    strcmpi(char(string(losStatusUnknown.ComplianceStatus)), "generic_fallback_not_strict_38901"), ...
    "Unknown LOS scenarios must disclose the generic fallback explicitly.");

[~, losStatusInf] = sixgr.channel.LOSProbability("InF", 100);
assert(strcmpi(char(string(losStatusInf.Source)), "approximate_inf_factory_proxy_los_probability") && ...
    strcmpi(char(string(losStatusInf.ComplianceStatus)), "approximate_factory_proxy_not_strict_38901") && ...
    ~logical(losStatusInf.StrictSupported), ...
    "InF LOS must remain labeled as an approximate factory proxy unless a stricter model exists.");

[pInH5, losStatusInH] = sixgr.channel.LOSProbability("InH", 5);
expectedInH5 = exp(-(5 - 1.2) / 4.7);
assert(abs(double(pInH5) - expectedInH5) < 1e-12 && logical(losStatusInH.StrictSupported), ...
    "InH LOS probability must use the TR 38.901 Table 7.4.2-1 piecewise curve.");

[pUmaHigh, losStatusUmaHigh] = sixgr.channel.LOSProbability("UMa", 100, "HUT_m", 23);
[pUmaLow, ~] = sixgr.channel.LOSProbability("UMa", 100, "HUT_m", 1.5);
assert(double(pUmaHigh) > double(pUmaLow) && logical(losStatusUmaHigh.StrictSupported), ...
    "UMa LOS probability must apply the hUT-dependent C' correction above 13 m.");

[o2iLow, o2iStatus] = sixgr.channel.O2ILoss(3.5e9, "low", ...
    "IndoorDistance_m", 5, "RandomComponentEnabled", false);
fGHz = 3.5;
lGlass = 2 + 0.2 * fGHz;
lConcrete = 5 + 4 * fGHz;
expectedLow = 5 - 10 * log10(0.3 * 10^(-lGlass/10) + 0.7 * 10^(-lConcrete/10)) + 0.5 * 5;
assert(abs(double(o2iLow) - expectedLow) < 1e-12 && ...
    strcmpi(char(string(o2iStatus.ModelSource)), "tr38901_table_7_4_3_1_low_loss_building") && ...
    strcmpi(char(string(o2iStatus.ComplianceStatus)), "strict_38901_o2i_model") && ...
    logical(o2iStatus.StrictSupported), ...
    "O2I helper must implement the low-loss TR 38.901 building penetration formula.");

layout = struct( ...
    "bs", struct( ...
        "pos_m", [0 0 25], ...
        "txPower_dBm", 43, ...
        "siteId", 1, ...
        "sectorId", 1), ...
    "wraparoundEnabled", false, ...
    "wraparoundMode", "disabled", ...
    "area_m", [200 200], ...
    "isd_m", NaN);
ue = struct("pos_m", [40 0 1.5], "K", 1, "indoor", true);
state = sixgr.system.buildLargeScaleStateCache(cfgApprox, layout, ue, 1, 0, pl, "NumRB", 1);
assert(strcmpi(char(string(state.ChannelComplianceMode)), "approximate_38901_plus") && ...
    strcmpi(char(string(state.PathlossModelSource)), "configured_abg_large_scale_model") && ...
    strcmpi(char(string(state.O2IModelSource)), "tr38901_table_7_4_3_1_low_loss_building") && ...
    strcmpi(char(string(state.LOSProbabilitySource)), "tr38901_uma_closed_form_los_probability"), ...
    "Large-scale state cache must retain the pathloss, O2I, and LOS compliance provenance.");

cfgFR3 = sixgr.config.defaultConfig();
cfgFR3.channel.model = "TR38901";
cfgFR3.channel.pathlossModel = "nrPathLoss";
cfgFR3.channel.pathloss.model = "nrPathLoss";
cfgFR3.channel.complianceMode = "strict_38901";
cfgFR3.channel.shadowFadingEnabled = false;
cfgFR3.channel.shadowSigma_dB = 0;
cfgFR3.channel.o2i.model = "none";
cfgFR3.channel.propagationScenario = "UMa";
cfgFR3.phy.fc_Hz = 12e9;
plFR3 = sixgr.channel.TR38901Plus(cfgFR3, "Scenario", "UMa", "Fc_Hz", 12e9, "Seed", 15);
[plFR3dB, ~, exFR3] = plFR3.pathloss([0; 0; 25], [250; 0; 1.5], "LOS", true);
expectedFR3 = 28.0 + 22.0 * log10(sqrt(250^2 + 23.5^2)) + 20.0 * log10(12.0);
assert(abs(double(plFR3dB) - expectedFR3) < 1e-9 && ...
    strcmpi(char(string(exFR3.pathlossExecutionBackend)), "tr38901_closed_form_runtime_backend") && ...
    strcmpi(char(string(exFR3.pathlossComplianceStatus)), "tr38901_closed_form_7p125_to_24p25ghz_gap") && ...
    ~logical(exFR3.fallbackUsedForPathloss), ...
    "FR3/gap pathloss must use standards-backed TR 38.901 closed-form equations, not an FSPL fallback.");

haveNrPathLoss = exist("nrPathLossConfig", "class") == 8 && exist("nrPathLoss", "file") == 2;
if haveNrPathLoss
    cfgStrictNR = sixgr.config.defaultConfig();
    cfgStrictNR.channel.model = "TR38901";
    cfgStrictNR.channel.pathlossModel = "nrPathLoss";
    cfgStrictNR.channel.pathloss.model = "nrPathLoss";
    cfgStrictNR.channel.complianceMode = "strict_38901";
    cfgStrictNR.channel.shadowFadingEnabled = false;
    cfgStrictNR.channel.shadowSigma_dB = 0;
    cfgStrictNR.channel.o2i.model = "none";
    cfgStrictNR.channel.propagationScenario = "mysteryScenario";

    strictLOS = sixgr.channel.TR38901Plus(cfgStrictNR, "Scenario", "mysteryScenario", "Seed", 17);
    localAssertThrows(@() strictLOS.pathloss([0; 0; 25], [50; 0; 1.5]), ...
        "TR38901Plus:StrictLOSUnsupported");
end

ok = true;
end

function localAssertThrows(fh, expectedId)
caught = false;
try
    fh();
catch ME
    caught = strcmp(ME.identifier, expectedId);
end
assert(caught, "Expected error '%s'.", expectedId);
end
