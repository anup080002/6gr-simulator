function ok = testLinkAdaptationDomainTruth()
%TESTLINKADAPTATIONDOMAINTRUTH Guard explicit link-adaptation domain semantics.

setup6GRSimToolkit("Verbose", false);

cfg = sixgr.config.defaultConfig();
cfg = sixgr.util.structSet(cfg, "phy.linkAdaptation.mode", "amc");
cfg = sixgr.util.structSet(cfg, "phy.linkAdaptation.dlPolicy", "baseline");
cfg = sixgr.util.structSet(cfg, "phy.linkAdaptation.rankPolicy", "fixed");
cfg = sixgr.util.structSet(cfg, "phy.linkAdaptation.beamPolicy", "fixed");
cfg = sixgr.util.structSet(cfg, "phy.linkAdaptation.innerLoopFlag", true);
cfg = sixgr.util.structSet(cfg, "phy.linkAdaptation.outerLoopFlag", false);
cfg = sixgr.util.structSet(cfg, "phy.linkAdaptation.cqiSmoothingAlpha", 0.5);
cfg = sixgr.util.structSet(cfg, "phy.linkAdaptation.cqiJumpResetThreshold", 99);

[decision1, state1] = sixgr.link.computeLinkAdaptationDecision(cfg, "DL", ...
    struct("CQI", 12, "RI", 1, "CombinedDecodeOK", true));
assert(string(decision1.LinkAdaptationDomain) == "cqi", ...
    "Default AMC domain must be explicit CQI-space, not hidden legacy MCS smoothing.");
assert(string(decision1.CQISource) == "runtime_reported_cqi", ...
    "Default CQI-domain AMC must report runtime CQI provenance.");
assert(abs(double(state1.SmoothedCQI) - 12) < 1e-9, ...
    "CQI-domain AMC must persist smoothed CQI state.");

[decision2, state2] = sixgr.link.computeLinkAdaptationDecision(cfg, "DL", ...
    struct("CQI", 4, "RI", 1, "CombinedDecodeOK", true), "AdaptationState", state1);
assert(abs(double(state2.SmoothedCQI) - 8) < 1e-9, ...
    "Default inner-loop smoothing must occur in CQI-space.");
assert(string(decision2.CQISmoothingAlphaSource) == "configured_fixed_alpha", ...
    "Configured CQI smoothing alpha must carry explicit fixed-alpha provenance.");
assert(double(decision2.CQIBasedMCS) <= double(decision1.CQIBasedMCS), ...
    "Lower CQI must not increase the CQI-based operating point.");

cfgDopplerLow = sixgr.util.structSet(cfg, "phy.linkAdaptation.cqiSmoothingMode", "doppler_adaptive");
cfgDopplerLow = sixgr.util.structSet(cfgDopplerLow, "channel.doppler_Hz", 30);
cfgDopplerLow = sixgr.util.structSet(cfgDopplerLow, "phy.numerology.slotDuration_ms", 1);
cfgDopplerHigh = sixgr.util.structSet(cfgDopplerLow, "channel.doppler_Hz", 300);
[decisionDopplerLow, ~] = sixgr.link.computeLinkAdaptationDecision(cfgDopplerLow, "DL", ...
    struct("CQI", 12, "RI", 1, "CombinedDecodeOK", true));
[decisionDopplerHigh, ~] = sixgr.link.computeLinkAdaptationDecision(cfgDopplerHigh, "DL", ...
    struct("CQI", 12, "RI", 1, "CombinedDecodeOK", true));
assert(string(decisionDopplerLow.CQISmoothingAlphaSource) == "doppler_adaptive_coherence_time" && ...
    string(decisionDopplerHigh.CQISmoothingAlphaSource) == "doppler_adaptive_coherence_time", ...
    "Doppler-adaptive CQI smoothing must disclose coherence-time provenance.");
assert(double(decisionDopplerHigh.CQISmoothingAlpha) > double(decisionDopplerLow.CQISmoothingAlpha), ...
    "Higher Doppler must produce a faster CQI smoothing alpha than lower Doppler.");

cfgEff = sixgr.util.structSet(cfg, "phy.linkAdaptation.domain", "effective_sinr");
[decisionEff, ~] = sixgr.link.computeLinkAdaptationDecision(cfgEff, "DL", ...
    struct("SINR_dB", 18, "RI", 1, "CombinedDecodeOK", true));
assert(string(decisionEff.LinkAdaptationDomain) == "effective_sinr", ...
    "Effective-SINR domain must be explicit when configured.");
assert(isfinite(double(decisionEff.ResolvedCQI)) && double(decisionEff.ResolvedCQI) >= 0, ...
    "Effective-SINR domain must derive a finite CQI with provenance.");
assert(string(decisionEff.CQISource) == "runtime_effective_sinr", ...
    "Effective-SINR domain must not masquerade as direct runtime CQI.");

cfgLegacy = sixgr.util.structSet(cfg, "phy.linkAdaptation.domain", "legacy_mcs");
[decisionLegacy, stateLegacy] = sixgr.link.computeLinkAdaptationDecision(cfgLegacy, "DL", ...
    struct("CQI", 10, "RI", 1, "CombinedDecodeOK", true));
assert(string(decisionLegacy.LinkAdaptationDomain) == "legacy_mcs", ...
    "Legacy MCS smoothing must remain opt-in and explicitly labeled.");
assert(~isfinite(double(stateLegacy.SmoothedCQI)), ...
    "Legacy MCS-domain mode must not populate CQI-space smoothing state.");

pfText = fileread(fullfile(pwd, "+sixgr", "+l2", "+mac", "SchedulerPF.m"));
rrText = fileread(fullfile(pwd, "+sixgr", "+l2", "+mac", "SchedulerRR.m"));
assert(~contains(pfText, "round((double(cqi) - 1) * (27/14))"), ...
    "SchedulerPF must not keep the stale linear CQI-to-MCS helper.");
assert(~contains(rrText, "round((double(cqi) - 1) * (27/14))"), ...
    "SchedulerRR must not keep the stale linear CQI-to-MCS helper.");

ok = true;
end
