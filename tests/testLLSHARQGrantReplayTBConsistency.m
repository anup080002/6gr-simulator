function ok = testLLSHARQGrantReplayTBConsistency()
%TESTLLSHARQGRANTREPLAYTBCONSISTENCY Ensure HARQ replay preserves original TBS-driving grant.

setup6GRSimToolkit("Verbose", false);
cfg = sixgr.config.defaultConfig();
cfg.run.shortRun = true;
cfg.outputs.saveCSV = false;
cfg.outputs.saveMAT = false;
cfg.outputs.saveFigures = false;

baseDL = sixgr.link.runDLPDSCHThroughput(cfg, "NumFrames", 1, "SNR_dB", 18);
assert(~isempty(baseDL.HARQ) && isfield(baseDL.HARQ, "TransportBlockBits"), "DL base run must return HARQ transport bits.");
dlBits = int8(baseDL.HARQ.TransportBlockBits(:));
dlGrant = baseDL.HARQ.GrantSnapshot;
assert(~isempty(dlBits), "DL base run must emit a non-empty TB.");

cfgDLReplay = cfg;
cfgDLReplay.phy.pdsch.mcsIndex = 27;
cfgDLReplay.phy.pdsch.modulation = "64QAM";
cfgDLReplay.phy.pdsch.codeRate = 0.92;
cfgDLReplay.phy.pdsch.nPRB = 10;
cfgDLReplay.phy.pdsch.prbSet = 0:9;
dlReplay = sixgr.link.runDLPDSCHThroughput(cfgDLReplay, "NumFrames", 1, "SNR_dB", 18, ...
    "TransportBlockBits", dlBits, "RV", 2, ...
    "HARQContext", struct("IsRetransmission", true), "GrantSnapshot", dlGrant);
assert(~any(string(dlReplay.TrialTable.Status) == "CRASH"), "DL HARQ replay must not crash after config drift.");
assert(all(double(dlReplay.TrialTable.TBSize_bits) == numel(dlBits)), "DL HARQ replay must preserve original TB size.");
assert(all(string(dlReplay.TrialTable.Modulation) == string(sixgr.util.structGet(dlGrant, "Modulation", ""))), ...
    "DL HARQ replay must report the original modulation, not drifted config.");

baseUL = sixgr.link.runULPUSCHThroughput(cfg, "NumFrames", 1, "SNR_dB", 18);
assert(~isempty(baseUL.HARQ) && isfield(baseUL.HARQ, "TransportBlockBits"), "UL base run must return HARQ transport bits.");
ulBits = int8(baseUL.HARQ.TransportBlockBits(:));
ulGrant = baseUL.HARQ.GrantSnapshot;
assert(~isempty(ulBits), "UL base run must emit a non-empty TB.");

cfgULReplay = cfg;
cfgULReplay.phy.pusch.mcsIndex = 27;
cfgULReplay.phy.pusch.modulation = "64QAM";
cfgULReplay.phy.pusch.codeRate = 0.92;
cfgULReplay.phy.pusch.nPRB = 10;
cfgULReplay.phy.pusch.prbSet = 0:9;
ulReplay = sixgr.link.runULPUSCHThroughput(cfgULReplay, "NumFrames", 1, "SNR_dB", 18, ...
    "TransportBlockBits", ulBits, "RV", 2, ...
    "HARQContext", struct("IsRetransmission", true), "GrantSnapshot", ulGrant);
assert(~any(string(ulReplay.TrialTable.Status) == "CRASH"), "UL HARQ replay must not crash after config drift.");
assert(all(double(ulReplay.TrialTable.TBSize_bits) == numel(ulBits)), "UL HARQ replay must preserve original TB size.");
assert(all(string(ulReplay.TrialTable.Modulation) == string(sixgr.util.structGet(ulGrant, "Modulation", ""))), ...
    "UL HARQ replay must report the original modulation, not drifted config.");

ok = true;
end
