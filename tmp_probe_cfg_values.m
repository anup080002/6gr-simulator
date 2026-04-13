setup6GRSimToolkit('Verbose',false,'RunToolboxChecks',false);
scfg = sixgr.lls6g.config.loadScenarioConfig('simulator/configs/scenarios/lls_700mhz_20mhz_2x2_rank2_beam_truth.yaml');
cfg = sixgr.lls6g.buildInternalConfig(scfg,pwd);
cfg = sixgr.config.normalizeConfig(cfg);
disp(struct('dlMod',string(cfg.phy.pdsch.modulation),'dlMCS',cfg.phy.pdsch.mcsIndex,'dlCodeRate',cfg.phy.pdsch.codeRate,'ulMod',string(cfg.phy.pusch.modulation),'ulMCS',cfg.phy.pusch.mcsIndex,'ulCodeRate',cfg.phy.pusch.codeRate,'mcsTable',string(sixgr.util.structGet(cfg,'phy.pdsch.mcsTable',''))));
