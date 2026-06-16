function ok = testMIMOConfigStrictValidation()
%TESTMIMOCONFIGSTRICTVALIDATION Strict MIMO config validation must fail closed.

setup6GRSimToolkit("Verbose", false);

cfg = localCfg(2, 20, "256QAM");
cfg.scenario.ue.nTxAnt = 2;
cfg.scenario.bs.nRxAnt = 4;
cfgT = sixgr.mimo.buildMIMOConfigFromScenario(cfg, "RunId", "mimo_cfg", "ScenarioName", "unit");
audit = sixgr.mimo.validateMIMOConfigStrict(cfgT);
assert(all(logical(audit.Pass)), "Valid 64T/4R DL and supported UL rank-2 config must pass strict validation.");

bad = cfg;
bad.scenario.ue.nTxAnt = 1;
bad.phy.pusch.numLayers = 2;
bad.phy.pusch.nLayers = 2;
badT = sixgr.mimo.buildMIMOConfigFromScenario(bad);
badAudit = sixgr.mimo.validateMIMOConfigStrict(badT);
ulFail = badAudit(strcmp(string(badAudit.Direction), "UL") & strcmp(string(badAudit.ValidationRule), "configured_rank_supported_by_ports"), :);
assert(height(ulFail) == 1 && ~logical(ulFail.Pass(1)), ...
    "UL rank-2 must fail when the UE has only one configured Tx antenna/port.");

unsupported = cfgT;
unsupported.CodebookType(:) = "typeII";
unsupportedAudit = sixgr.mimo.validateMIMOConfigStrict(unsupported);
assert(any(~logical(unsupportedAudit.Pass) & strcmp(string(unsupportedAudit.ValidationRule), "unsupported_codebook_modes_fail_closed")), ...
    "Unsupported Type-II/multi-panel codebook modes must fail closed.");

ok = true;
end

function cfg = localCfg(layers, mcs, modulation)
cfg = struct();
cfg.scenario.bs.nTxAnt = 64;
cfg.scenario.ue.nRxAnt = 4;
cfg.scenario.ue.nTxAnt = 2;
cfg.scenario.bs.nRxAnt = 4;
cfg.channel.nTxAnt = 64;
cfg.channel.nRxAnt = 4;
cfg.phy.pdsch.numLayers = layers;
cfg.phy.pdsch.nLayers = layers;
cfg.phy.pdsch.mcsIndex = mcs;
cfg.phy.pdsch.modulation = modulation;
cfg.phy.pdsch.NumAntennaPorts = 4;
cfg.phy.pusch.numLayers = layers;
cfg.phy.pusch.nLayers = layers;
cfg.phy.pusch.mcsIndex = mcs;
cfg.phy.pusch.modulation = modulation;
cfg.phy.pusch.NumAntennaPorts = layers;
cfg.link_adaptation.fixed_or_amc = "fixed";
cfg.mimo.rank_adaptation_policy = "fixed";
end
