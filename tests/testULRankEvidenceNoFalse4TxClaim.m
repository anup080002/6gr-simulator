function ok = testULRankEvidenceNoFalse4TxClaim()
%TESTULRANKEVIDENCENOFALSE4TXCLAIM UL high-rank claim must respect UE Tx ports.

setup6GRSimToolkit("Verbose", false);

cfg = struct();
cfg.scenario.bs.nTxAnt = 64;
cfg.scenario.ue.nRxAnt = 4;
cfg.scenario.ue.nTxAnt = 1;
cfg.scenario.bs.nRxAnt = 4;
cfg.phy.pdsch.numLayers = 2;
cfg.phy.pdsch.nLayers = 2;
cfg.phy.pdsch.mcsIndex = 20;
cfg.phy.pdsch.modulation = "256QAM";
cfg.phy.pdsch.NumAntennaPorts = 4;
cfg.phy.pusch.numLayers = 2;
cfg.phy.pusch.nLayers = 2;
cfg.phy.pusch.mcsIndex = 20;
cfg.phy.pusch.modulation = "256QAM";
cfg.phy.pusch.NumAntennaPorts = 1;
cfg.link_adaptation.fixed_or_amc = "fixed";

cfgT = sixgr.mimo.buildMIMOConfigFromScenario(cfg);
audit = sixgr.mimo.validateMIMOConfigStrict(cfgT);
ulAudit = audit(strcmp(string(audit.Direction), "UL"), :);
assert(any(~logical(ulAudit.Pass)), "False UL rank-2/4Tx-like claim must fail when UE Tx port support is one.");
assert(any(contains(string(ulAudit.FailureReason), "configured_rank_exceeds")), ...
    "UL validation failure must identify configured rank exceeding port support.");

ok = true;
end
