function ok = testPrompt2TopologySRSPRACHRuntimeWiring()
%TESTPROMPT2TOPOLOGYSRSPRACHRUNTIMEWIRING Guard topology, SRS and PRACH runtime wiring.

setup6GRSimToolkit("Verbose", false, "RunToolboxChecks", false);

masterPath = fullfile(pwd, "simulator", "configs", "scenarios", "master_scenaio_all_file.yaml");
assert(exist(masterPath, "file") == 2, "Missing master_scenaio_all_file.yaml.");

scfg = sixgr.lls6g.config.loadScenarioConfig(masterPath);
resolved = scfg.toStruct();
expectedDopplerHz = (100 / 3.6) * 4.0e9 / 299792458;

assert(double(sixgr.util.structGet(resolved, "random_access.num_rx_antennas", NaN)) == 64, ...
    "Resolved PRACH must use the configured gNB receive antenna count.");
assert(double(sixgr.util.structGet(resolved, "random_access.num_tx_antennas", NaN)) == 4, ...
    "Resolved PRACH must use the configured UE transmit antenna count.");
assert(abs(double(sixgr.util.structGet(resolved, "random_access.delay_spread_ns", NaN)) - 93) < 1e-12, ...
    "Resolved PRACH must carry the 93 ns UMa delay spread.");
assert(abs(double(sixgr.util.structGet(resolved, "random_access.timing_tolerance_us", NaN)) - 0.5) < 1e-12, ...
    "Resolved PRACH timing tolerance must not fall back to the old 0.25 us default.");

tmp = tempname;
mkdir(tmp);
cleanup = onCleanup(@() localCleanupTempFolder(tmp)); %#ok<NASGU>
cfg = sixgr.lls6g.buildInternalConfig(scfg, fullfile(tmp, "run"));

layout = sixgr.scenario.generateLayout(cfg, cfg.scenario.name);
assert(isequal(double(layout.bs.cellId(:).'), [1 2]), ...
    "Two-cell topology must expose unique cell IDs [1 2].");
assert(isequal(double(layout.bs.pci(:).'), [1 2]), ...
    "Two-cell topology must expose unique PCI values [1 2].");
assert(isequal(double(layout.bs.nCellId(:).'), [1 2]), ...
    "Two-cell topology must expose unique NCellID values [1 2].");

rng(double(sixgr.util.structGet(cfg, "run.seed", 1)), "twister");
ue = sixgr.scenario.dropUEs(cfg, layout, cfg.scenario.name);
assert(isequal(double(ue.drop_cell_id(:).'), [1 2]), ...
    "Configured two-UE topology must attach UE1 to Cell1 and UE2 to Cell2.");

srsCfg = sixgr.phy.srs.buildSRSConfigFromScenario(cfg);
srsMapping = sixgr.phy.srs.generateSRSSymbolsAndIndices(srsCfg);
assert(abs(double(srsCfg.CarrierFrequencyHz) - 4.0e9) < 1e-3, ...
    "SRS strict config must inherit the 4 GHz carrier frequency.");
assert(abs(double(srsCfg.PowerControlAlpha) - 0.8) < 1e-12, ...
    "SRS strict config must inherit alpha power-control from the scenario.");
assert(abs(double(srsCfg.P0) - (-80)) < 1e-12, ...
    "SRS strict config must inherit P0 from the scenario.");
assert(double(srsCfg.ExpectedRECount) == height(srsMapping.ResourceMappingTable), ...
    "SRS ExpectedRECount must equal the generated mapping rows.");
assert(logical(srsCfg.StrictValidation.StrictValid), ...
    "SRS strict validation must pass with finite carrier, power-control and RE-count fields.");

prachCfg = sixgr.rach.PRACHConfig(cfg);
localAssertPRACHRuntimeConfig(prachCfg, expectedDopplerHz, "PRACH runtime config");

prachStrict = sixgr.phy.prach.PRACHConfigStrict(cfg, ...
    "RunFolder", tmp, "ScenarioName", "prompt2_topology_srs_prach_runtime_wiring");
localAssertPRACHRuntimeConfig(prachStrict, expectedDopplerHz, "Strict PRACH config");
assert(logical(prachStrict.StrictValidation.StrictValid), ...
    "Strict PRACH validation must pass for the resolved 4 GHz UMa/CDL-C configuration.");

ok = true;
end

function localAssertPRACHRuntimeConfig(prachCfg, expectedDopplerHz, label)
assert(abs(double(prachCfg.CarrierFrequencyHz) - 4.0e9) < 1e-3, ...
    "%s must inherit the 4 GHz carrier frequency.", label);
assert(strcmpi(char(string(prachCfg.ChannelModel)), "CDL-C"), ...
    "%s must use CDL-C, not AWGN or CDL-D.", label);
assert(abs(double(prachCfg.DelaySpread_ns) - 93) < 1e-12, ...
    "%s must use the 93 ns UMa delay spread.", label);
assert(abs(double(prachCfg.Speed_kmh) - 100) < 1e-12, ...
    "%s must use 100 km/h mobility.", label);
assert(abs(double(prachCfg.MaxDopplerHz) - expectedDopplerHz) < 1e-6, ...
    "%s must derive Doppler from speed and carrier frequency.", label);
assert(double(prachCfg.NumRxAntennas) == 64, ...
    "%s must use the gNB receive antenna count.", label);
assert(double(prachCfg.NumTxAntennas) == 4, ...
    "%s must use the UE transmit antenna count.", label);
assert(abs(double(prachCfg.DetectionThreshold) - 0.35) < 1e-12, ...
    "%s must use the configured detection threshold.", label);
assert(abs(double(prachCfg.TimingTolerance_us) - 0.5) < 1e-12, ...
    "%s must use the configured timing tolerance.", label);
end

function localCleanupTempFolder(tmp)
if isfolder(tmp)
    rmdir(tmp, "s");
end
end
