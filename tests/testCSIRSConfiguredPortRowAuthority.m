function ok = testCSIRSConfiguredPortRowAuthority()
%TESTCSIRSCONFIGUREDPORTROWAUTHORITY Enforce YAML CSI-RS port/row truth.

setup6GRSimToolkit("Verbose", false);
scenario = sixgr.lls6g.config.loadScenarioConfig(fullfile(pwd, ...
    "simulator", "configs", "scenarios", ...
    "webgui_sinr_sweep_64x4_mu_mimo_repair_slice.yaml"));
cfg = sixgr.lls6g.buildInternalConfig(scenario, tempdir);
carrier = sixgr.phy.grid.makeCarrier(cfg);

[indices, symbols, info] = sixgr.phy.refsig.csirs(carrier, cfg);
assert(double(cfg.phy.csirs.nPorts) == 4 && ...
    double(cfg.phy.csi.reportConfiguration.Ports) == 4, ...
    "The resolved YAML must retain four-port CSI measurement authority.");
assert(numel(info.Resources) == 8 && ...
    all(double([info.Resources.NumPorts]) == 4) && ...
    all(double([info.Resources.RowNumber]) == 4), ...
    "Every transmitted NZP CSI-RS resource must use row 4 and four ports.");
assert(~isempty(indices) && numel(indices) == numel(symbols), ...
    "The configured four-port CSI-RS resource set must materialize real REs.");

bad = cfg;
bad.phy.csirs.rowNumbers(1) = 3;
threw = false;
try
    sixgr.phy.refsig.csirs(carrier, bad);
catch ME
    threw = strcmp(ME.identifier, ...
        "sixgr:phy:csirs:ConfiguredPortRowMismatch");
end
assert(threw, ...
    "A two-port CSI-RS row under four-port YAML authority must fail closed.");
ok = true;
end
