function ok = testDLCSIRSPostEqCQIPrecedence()
%TESTDLCSIRSPOSTEQCQIPRECEDENCE Post-EQ SINR must drive CQI when it is scheduler-eligible.

setup6GRSimToolkit("Verbose", false);

cfg = struct();
cfg.phy.csi.reportCQI = true;
cfg.phy.csi.reportPMI = true;
cfg.phy.csi.reportRI = true;
cfg.phy.csi.maxRank = 1;
cfg.phy.pdsch.cqiTable = "table2";
cfg.phy.pdsch.mcsTable = "qam256_table2";
cfg.phy.pdsch.targetBLER = 0.1;
cfg.phy.nRxAnt = 1;
cfg.phy.nTxAnt = 1;

hEst = ones(12, 1, 1, 1);
nVar = 1e-3;
rxGrid = zeros(12, 1, 1);
rxGrid(1, 1, 1) = 0.01;
refInd = 1;
refSym = 1;

csi = sixgr.phy.dl.CSI_Feedback(hEst, nVar, cfg, ...
    "Direction", "DL", ...
    "ReceivedGrid", rxGrid, ...
    "ReferenceIndices", refInd, ...
    "ReferenceSymbols", refSym, ...
    "PostEqSINR_dB", 20, ...
    "PostEqSINRSource", "post_equalization_sinr_from_equalizer_channel_estimate", ...
    "PostEqSINRValueRole", "measured_post_equalization_scheduling_input", ...
    "PostEqSINRValueStatus", "OK");

assert(double(csi.CQI) > 1, ...
    "Scheduler-eligible post-EQ SINR must not be overridden by a finite low pilot-residual CQI.");
assert(strcmpi(char(string(csi.SINRSource)), "post_equalization_sinr_from_equalizer_channel_estimate"), ...
    "CSI feedback SINR source must disclose post-equalization scheduling input precedence.");
assert(double(csi.PostEqSINR_dB) == 20, ...
    "Post-EQ SINR must be preserved in CSI feedback metadata.");

ok = true;
end
