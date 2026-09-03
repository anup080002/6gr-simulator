function ok = testDLPDSCHCSIDimensionsDoNotOverrideRuntime()
%TESTDLPDSCHCSIDIMENSIONSDONOTOVERRIDERUNTIME Guard CSI/PDSCH axes.
% A CSI-RS state is a reporting input.  Its resource/snapshot axes must not
% be exported as physical PDSCH receive branches or transmit ports.

setup6GRSimToolkit("Verbose", false);
scenario = sixgr.lls6g.config.loadScenarioConfig(fullfile(pwd, ...
    "simulator", "configs", "scenarios", ...
    "lls_causal_access_to_data_wiring.yaml"));
tmp = tempname;
mkdir(tmp);
cleanup = onCleanup(@() rmdir(tmp, "s")); %#ok<NASGU>
cfg = sixgr.lls6g.buildInternalConfig(scenario, tmp);
cfg.run.shortRun = true;
cfg.outputs.saveCSV = false;
cfg.outputs.saveMAT = false;
cfg.outputs.saveFigures = false;
cfg.phy.pdsch.executionProfile = "phy_calibration";
cfg.run.pdschExecutionProfile = "phy_calibration";
cfg.phy.csirs.period_slots = 1;
cfg.phy.csirs.offset_slots = 0;

result = sixgr.link.runDLPDSCHThroughput(cfg, "NumFrames", 1, ...
    "SNR_dB", 30, "ExecutionProfile", "phy_calibration");
assert(istable(result.TrialTable) && ~isempty(result.TrialTable), ...
    "The focused 2x2 PDSCH/CSI-RS chain did not produce runtime trials.");
fprintf("PDSCH runtime dimensions Rx=%s Tx=%s\n", ...
    mat2str(double(result.TrialTable.NumRxAntennas).'), ...
    mat2str(double(result.TrialTable.NumTxPorts).'));
assert(all(double(result.TrialTable.NumRxAntennas) == 2) && ...
    all(double(result.TrialTable.NumTxPorts) == 2), ...
    "CSI reporting tensors must not overwrite the executed 2x2 PDSCH waveform dimensions.");
assert(istable(result.CSIRSTrialTable) && ~isempty(result.CSIRSTrialTable) && ...
    all(double(result.CSIRSTrialTable.HestRxPorts) == 2) && ...
    all(double(result.CSIRSTrialTable.HestTxPorts) == 2), ...
    "CSI-RS evidence must independently retain its exact 2x2 channel axes.");
ok = true;
fprintf("testDLPDSCHCSIDimensionsDoNotOverrideRuntime: PASS\n");
end
