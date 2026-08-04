function ok = testLinkAdaptationAtomicRankPrecoderDecision()
%TESTLINKADAPTATIONATOMICRANKPRECODERDECISION Require RI+PMI coherence.

setup6GRSimToolkit("Verbose", false, "RunToolboxChecks", false);
cfg = sixgr.config.defaultConfig();
cfg.phy.linkAdaptation.mode = "closed_loop";
cfg.phy.linkAdaptation.dlPolicy = "fixed";
cfg.phy.linkAdaptation.rankPolicy = "adaptive";
cfg.phy.linkAdaptation.beamPolicy = "adaptive";
cfg.phy.pdsch.numLayers = 2;
cfg.phy.pdsch.nLayers = 2;
cfg.phy.pdsch.numPorts = 2;
cfg.phy.pdsch.nPorts = 2;
cfg.phy.pdsch.precoding.matrix = eye(2);

[held, ~] = sixgr.link.computeLinkAdaptationDecision( ...
    cfg, "DL", struct("RI", 1, "PMI", NaN));
assert(~logical(held.RankUpdated) && held.NumLayers == 2, ...
    "An RI-only decision must not detach rank from its frozen explicit precoder.");
assert(string(held.RankUpdateStatus) == "held_missing_atomic_pmi" && ...
    string(held.RankUpdateBlockedReason) == ...
    "explicit_precoder_rank_transition_requires_simultaneous_finite_pmi", ...
    "Blocked rank transition must carry an explicit audit reason.");

[atomic, ~] = sixgr.link.computeLinkAdaptationDecision( ...
    cfg, "DL", struct("RI", 1, "PMI", 0));
assert(logical(atomic.RankUpdated) && logical(atomic.PMIUpdated) && ...
    atomic.NumLayers == 1 && atomic.PMI == 0 && ...
    string(atomic.RankUpdateStatus) == "ready_to_apply", ...
    "A coherent RI+PMI decision must remain applicable atomically.");
ok = true;
end
