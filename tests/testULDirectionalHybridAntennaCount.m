function ok = testULDirectionalHybridAntennaCount()
%TESTULDIRECTIONALHYBRIDANTENNACOUNT Keep UL UE-Tx/gNB-Rx physical domains distinct.

cfg = struct();
cfg.lls6g.userContext.RuntimeUEAntennaMeta = struct( ...
    "NumPorts", 2, "NumElements", 4, "NumWaveformColumns", 4, ...
    "WaveformDomain", "element", "HybridBeamformingEnabled", true);
cfg.lls6g.userContext.RuntimeServingBSAntennaMeta = struct( ...
    "NumPorts", 4, "NumElements", 64, "NumWaveformColumns", 64, ...
    "WaveformDomain", "element", "HybridBeamformingEnabled", true);

txCount = sixgr.phy.ul.resolveULDirectionalAntennaCount(cfg, "tx", 1);
rxCount = sixgr.phy.ul.resolveULDirectionalAntennaCount(cfg, "rx", 1);
assert(txCount == 4, ...
    "UL hybrid transmission must use the four UE element-domain columns.");
assert(rxCount == 64, ...
    "UL hybrid reception must use the 64 physical gNB channel branches, not four logical ports.");

logicalCfg = cfg;
logicalCfg.lls6g.userContext.RuntimeServingBSAntennaMeta.WaveformDomain = "logical_port";
logicalCfg.lls6g.userContext.RuntimeServingBSAntennaMeta.HybridBeamformingEnabled = false;
logicalCount = sixgr.phy.ul.resolveULDirectionalAntennaCount(logicalCfg, "rx", 1);
assert(logicalCount == 4, ...
    "A declared logical-port runtime must continue to use its logical channel-port count.");

ok = true;
end
