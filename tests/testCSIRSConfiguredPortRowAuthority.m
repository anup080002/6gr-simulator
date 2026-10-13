function ok = testCSIRSConfiguredPortRowAuthority()
%TESTCSIRSCONFIGUREDPORTROWAUTHORITY Enforce YAML CSI-RS port/row truth.

setup6GRSimToolkit("Verbose", false);
scenario = sixgr.lls6g.config.loadScenarioConfig(fullfile(pwd, ...
    "simulator", "configs", "scenarios", ...
    "webgui_sinr_sweep_64x4_mu_mimo_repair_slice.yaml"));
cfg = sixgr.lls6g.buildInternalConfig(scenario, tempdir);
carrier = sixgr.phy.grid.makeCarrier(cfg);
% The configured periodic CSI-RS calendar is 5:2. Exercise its real
% scheduled occasion instead of treating enablement as an every-slot
% transmission.
carrier.NFrame = 0;
carrier.NSlot = 2;
cfg = sixgr.util.structSet(cfg, "lls6g.runtime.AbsoluteSlotIndex0", 2);

[indices, symbols, info] = sixgr.phy.refsig.csirs(carrier, cfg);
assert(double(cfg.phy.csirs.nPorts) == 2 && ...
    double(cfg.phy.csi.reportConfiguration.Ports) == 2, ...
    ["The 64-element hybrid array must retain its configured two logical " ...
     "CSI-RS ports; physical elements must not be mislabeled as NR ports."]);
assert(numel(info.Resources) == 8 && ...
    all(double([info.Resources.NumPorts]) == 2) && ...
    all(double([info.Resources.RowNumber]) == 3), ...
    "Every transmitted NZP CSI-RS resource must use configured row 3 and two ports.");
assert(~isempty(indices) && numel(indices) == numel(symbols), ...
    "The configured four-port CSI-RS resource set must materialize real REs.");

bad = cfg;
bad.phy.csirs.rowNumbers(1) = 4;
threw = false;
try
    sixgr.phy.refsig.csirs(carrier, bad);
catch ME
    threw = strcmp(ME.identifier, ...
        "sixgr:phy:csirs:ConfiguredPortRowMismatch");
end
assert(threw, ...
    "A four-port CSI-RS row under two-port YAML authority must fail closed.");
% The 100-MHz 2x2 parent previously inherited its one-layer DMRS count as
% CSI-RS port count and authored row 2, despite scheduling a two-port PMI.
% Verify the actual pilot generator now executes the declared two-port row;
% DMRS layer count remains independent of the sounded CSI port capability.
parent=sixgr.lls6g.config.loadScenarioConfig(fullfile(pwd,'simulator', ...
    'configs','scenarios','lls_100mhz_tdlc_bidirectional_truth.yaml'));
parentCfg=sixgr.lls6g.buildInternalConfig(parent,tempdir);
parentCarrier=sixgr.phy.grid.makeCarrier(parentCfg);
parentCarrier.NFrame=0; parentCarrier.NSlot=0;
parentCfg.lls6g.runtime.AbsoluteSlotIndex0=0;
[parentIndices,parentSymbols,parentInfo]=sixgr.phy.refsig.csirs(parentCarrier,parentCfg);
assert(parentCfg.phy.csirs.nPorts==2 && parentCfg.phy.pdsch.dmrs.nPorts==1 && ...
    all([parentInfo.Resources.NumPorts]==2) && all([parentInfo.Resources.RowNumber]==3) && ...
    ~isempty(parentIndices) && numel(parentIndices)==numel(parentSymbols), ...
    'The 100-MHz parent must sound two CSI ports without inventing a second data layer.');
ok = true;
end
