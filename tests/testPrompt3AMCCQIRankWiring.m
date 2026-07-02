function ok = testPrompt3AMCCQIRankWiring()
%TESTPROMPT3AMCCQIRANKWIRING Guard AMC/CQI/rank adaptation Prompt-3 fixes.

setup6GRSimToolkit("Verbose", false, "RunToolboxChecks", false);

scenarioPath = fullfile(pwd, "simulator", "configs", "scenarios", ...
    "master_scenaio_all_file.yaml");
assert(exist(scenarioPath, "file") == 2, "Missing master_scenaio_all_file.yaml.");

tmp = tempname;
mkdir(tmp);
cleanup = onCleanup(@() localCleanupTempFolder(tmp)); %#ok<NASGU>

scfg = sixgr.lls6g.config.loadScenarioConfig(scenarioPath);
resolved = scfg.toStruct();
cfg = sixgr.lls6g.buildInternalConfig(scfg, fullfile(tmp, "run"));

assert(strcmpi(char(string(sixgr.util.structGet(resolved, "link_adaptation.cqi_table", ""))), "table2"), ...
    "Master scenario must explicitly resolve link_adaptation.cqi_table=table2 for qam256_table2 operation.");
assert(strcmpi(char(string(sixgr.util.structGet(cfg, "phy.csi.cqiTable", ""))), "table2"), ...
    "buildInternalConfig must wire CQI table2 into the runtime CSI config.");
assert(strcmpi(char(string(sixgr.util.structGet(cfg, "phy.pdsch.mcsTable", ""))), "qam256_table2") && ...
    strcmpi(char(string(sixgr.util.structGet(cfg, "phy.pusch.mcsTable", ""))), "qam256_table2"), ...
    "DL and UL runtime MCS tables must remain qam256_table2.");
assert(strcmpi(char(string(sixgr.util.structGet(cfg, "phy.linkAdaptation.bootstrapCQIMode", ""))), "estimated"), ...
    "Prompt-3 master config must use estimated bootstrap CQI rather than conservative-only CQI 0.");
assert(abs(double(sixgr.util.structGet(cfg, "phy.linkAdaptation.rankThreshold", NaN)) - 0.5) < 1e-12 && ...
    abs(double(sixgr.util.structGet(cfg, "phy.linkAdaptation.minSINRForRank2_dB", NaN)) - 12.0) < 1e-12 && ...
    double(sixgr.util.structGet(cfg, "phy.linkAdaptation.dlBootstrapMinCQIForScheduling", NaN)) == 2, ...
    "Rank adaptation thresholds must be runtime-configurable and wired into link adaptation.");
assert(abs(double(sixgr.util.structGet(cfg, "phy.linkAdaptation.deltaMCSMin", NaN)) + 5) < 1e-12 && ...
    abs(double(sixgr.util.structGet(cfg, "phy.linkAdaptation.deltaMCSMax", NaN)) - 5) < 1e-12, ...
    "OLLA delta bounds must resolve to [-5,+5] MCS.");

cfgDecision = sixgr.config.defaultConfig();
cfgDecision = sixgr.util.structSet(cfgDecision, "phy.linkAdaptation.mode", "amc");
cfgDecision = sixgr.util.structSet(cfgDecision, "phy.linkAdaptation.dlPolicy", "baseline");
cfgDecision = sixgr.util.structSet(cfgDecision, "phy.linkAdaptation.domain", "cqi");
cfgDecision = sixgr.util.structSet(cfgDecision, "phy.linkAdaptation.outerLoopFlag", true);
cfgDecision = sixgr.util.structSet(cfgDecision, "phy.linkAdaptation.deltaMCSPolicy", "olla");
cfgDecision = sixgr.util.structSet(cfgDecision, "phy.linkAdaptation.ollaStepUp", 5);
cfgDecision = sixgr.util.structSet(cfgDecision, "phy.linkAdaptation.deltaMCSMax", 5);
cfgDecision = sixgr.util.structSet(cfgDecision, "phy.csi.cqiTable", "table2");
cfgDecision = sixgr.util.structSet(cfgDecision, "phy.pdsch.mcsTable", "qam256_table2");
metrics = struct("CQI", 12, "RI", 1, "CombinedDecodeOK", true);
[decision, ~] = sixgr.link.computeLinkAdaptationDecision(cfgDecision, "DL", metrics);
assert(logical(decision.Valid), "CQI-domain link adaptation decision must be valid for finite CQI.");
assert(double(decision.MCSIndex) == double(decision.InstantaneousCQIMCS), ...
    "Positive OLLA must not select an MCS above the CQI-derived maximum.");
assert(strcmpi(char(string(decision.MCSValueStatus)), "clamped_to_cqi_max"), ...
    "Link adaptation must disclose when OLLA is clamped to the CQI-derived MCS ceiling.");

cfgSched = cfgDecision;
scheduler = sixgr.l2.mac.SchedulerPF(cfgSched, "Direction", "DL");
scheduler.updateAfterRx(struct("RNTI", 9301, "TBSBits", 1024, ...
    "Ack", true, "IsRetransmission", false, "RV", 0));
[~, ~, ~, amc] = scheduler.selectAMC(struct("RNTI", 9301, "CQI", 12, "RI", 1));
assert(double(amc.MCSIndex) == double(amc.RawCQIDerivedMCS), ...
    "Scheduler AMC must clamp positive OLLA to the CQI-derived MCS ceiling.");
assert(strcmpi(char(string(amc.MCSValueStatus)), "clamped_to_cqi_max"), ...
    "Scheduler AMC must label CQI-ceiling clamping explicitly.");

cfgRank = sixgr.config.defaultConfig();
cfgRank.phy.nTxAnt = 2;
cfgRank.phy.nRxAnt = 2;
cfgRank = sixgr.util.structSet(cfgRank, "phy.csi.maxRank", 2);
cfgRank = sixgr.util.structSet(cfgRank, "phy.csi.pmiCodebookMode", "noncodebook");
cfgRank = sixgr.util.structSet(cfgRank, "phy.linkAdaptation.rankThreshold", 0.25);
cfgRank = sixgr.util.structSet(cfgRank, "phy.linkAdaptation.minSINRForRank2_dB", 5);
csiFullRank = sixgr.phy.dl.CSI_Feedback(eye(2), 0.01, cfgRank, "MaxRank", 2);
assert(double(csiFullRank.RI) == 2, ...
    "A well-conditioned 2x2 channel must be allowed to report RI=2.");
csiWeakRank = sixgr.phy.dl.CSI_Feedback(diag([1 0.1]), 0.01, cfgRank, "MaxRank", 2);
assert(double(csiWeakRank.RI) == 1, ...
    "Rank-2 candidates below the configured singular-value threshold must be rejected.");

cfgBoot = cfg;
cfgBoot = sixgr.util.structSet(cfgBoot, "phy.linkAdaptation.mode", "amc");
cfgBoot = sixgr.util.structSet(cfgBoot, "phy.linkAdaptation.dlPolicy", "baseline");
cfgBoot = sixgr.util.structSet(cfgBoot, "phy.linkAdaptation.bootstrapCQIMode", "estimated");
cfgBoot = sixgr.util.structSet(cfgBoot, "phy.pdsch.nLayers", 2);
cfgBoot = sixgr.util.structSet(cfgBoot, "phy.pdsch.numLayers", 2);
multiUser = struct("Enabled", true, "NumUsers", 2, "RNTIStart", 401, ...
    "SeedStride", 17, "ExecutionModel", "slot_coupled_truth");
state = sixgr.truth.CoupledTruthRuntime.initialize(cfgBoot, fullfile(tmp, "boot"), multiUser, struct(), 1);
state.CurrentServingIdx(:) = 1;
state.LargeScaleState.RxPower_dBm(1, :) = -140;
state.LargeScaleState.RxPower_dBm(1, 1) = -60;
fb = sixgr.truth.CoupledTruthRuntime.latestFeedbackForDirectionRuntime(state, 1, "DL");
assert(~logical(fb.Valid) && logical(sixgr.util.structGet(fb, "BootstrapCQIUsableForScheduling", false)), ...
    "Estimated bootstrap CQI must be scheduler-usable while remaining distinct from measured CSI.");
assert(double(fb.CQI) > 0 && double(fb.MCSIndex) > 0, ...
    "Estimated bootstrap must not collapse to conservative CQI 0/MCS 0 when runtime SINR preview is available.");
assert(strcmpi(char(string(fb.BootstrapCQISource)), "bootstrap_estimated_runtime_preview_cqi"), ...
    "Estimated bootstrap CQI must disclose runtime-preview provenance.");
minRank2SINR = double(sixgr.util.structGet(cfgBoot, "phy.linkAdaptation.minSINRForRank2_dB", 5));
adjustedPreviewSINR = double(sixgr.util.structGet(fb, "AdjustedPreviewSINR_dB", NaN));
if isfinite(adjustedPreviewSINR) && adjustedPreviewSINR >= minRank2SINR
    assert(double(fb.RI) == 2 && logical(sixgr.util.structGet(fb, "BootstrapRankUsableForScheduling", false)), ...
        "Estimated bootstrap must preserve configured rank hint when preview SINR meets the rank-2 floor.");
else
    assert(double(fb.RI) == 1 && ~logical(sixgr.util.structGet(fb, "BootstrapRankUsableForScheduling", true)), ...
        "Estimated bootstrap must keep rank-1 when preview SINR is below the rank-2 floor.");
end

cfgBootGate = sixgr.util.structSet(cfgBoot, "phy.linkAdaptation.dlBootstrapMinCQIForScheduling", 15);
stateGate = sixgr.truth.CoupledTruthRuntime.initialize(cfgBootGate, fullfile(tmp, "boot_gate"), multiUser, struct(), 1);
stateGate.CurrentServingIdx(:) = 1;
for pwr = -40:-5:-150
    stateGate.LargeScaleState.RxPower_dBm(1, :) = -140;
    stateGate.LargeScaleState.RxPower_dBm(1, 1) = pwr;
    fbGate = sixgr.truth.CoupledTruthRuntime.latestFeedbackForDirectionRuntime(stateGate, 1, "DL");
    previewCQI = double(sixgr.util.structGet(fbGate, "PreviewCQI", NaN));
    if isfinite(previewCQI) && previewCQI > 0 && previewCQI < 15
        break;
    end
end
assert(isfinite(previewCQI) && previewCQI > 0 && previewCQI < 15, ...
    "Low-preview bootstrap test must create a finite positive CQI below the admission floor.");
assert(~logical(sixgr.util.structGet(fbGate, "BootstrapCQIUsableForScheduling", true)) && ...
    strcmpi(char(string(sixgr.util.structGet(fbGate, "BootstrapCQIAdmissionStatus", ""))), ...
    "rejected_below_min_cqi_for_scheduling"), ...
    "Bootstrap CQI below the configured floor must remain diagnostic-only and not schedule data.");
assert(double(fbGate.CQI) == 0 && isfinite(double(fbGate.PreviewCQI)) && double(fbGate.PreviewCQI) > 0, ...
    "Rejected bootstrap must keep PreviewCQI but clear scheduler-facing CQI.");
gateScheduler = sixgr.l2.mac.SchedulerPF(cfgBootGate, "Direction", "DL");
[~, ~, ~, amcGate] = gateScheduler.selectAMC(struct( ...
    "RNTI", 9302, ...
    "CQI", double(fbGate.CQI), ...
    "RI", double(fbGate.RI), ...
    "FeedbackValid", logical(fbGate.Valid), ...
    "CausalFeedbackUsable", false, ...
    "CausalFeedbackStatus", char(string(fbGate.BootstrapCQIAdmissionStatus))));
assert(strcmpi(char(string(amcGate.Mode)), "cqi_required_no_runtime_feedback") && ...
    strcmpi(char(string(amcGate.MCSSelectionSource)), "blocked_bootstrap_cqi_below_configured_floor"), ...
    "Scheduler AMC must block, not conservative-bootstrap, when preview CQI is below the configured floor.");

ok = true;
end

function localCleanupTempFolder(tmp)
if isfolder(tmp)
    rmdir(tmp, "s");
end
end
