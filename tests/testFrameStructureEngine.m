function ok = testFrameStructureEngine()
%TESTFRAMESTRUCTUREENGINE Validate canonical frame/grid resolution.

setup6GRSimToolkit("Verbose", false);

cfg = struct();
cfg = sixgr.util.structSet(cfg, "frequency.range_name", "FR1");
cfg = sixgr.util.structSet(cfg, "frequency.center_frequency_hz", 4e9);
cfg = sixgr.util.structSet(cfg, "frequency.bandwidth_hz", 100e6);
cfg = sixgr.util.structSet(cfg, "frequency.n_size_grid", 66);
cfg = sixgr.util.structSet(cfg, "frequency.duplex_mode", "TDD");
cfg = sixgr.util.structSet(cfg, "frame.scs_khz", 30);
cfg = sixgr.util.structSet(cfg, "frame.cp_type", "normal");
cfg = sixgr.util.structSet(cfg, "frame.tdd_pattern", "DDDSU");
cfg = sixgr.util.structSet(cfg, "frame.special_slot_downlink_symbols", 12);
cfg = sixgr.util.structSet(cfg, "frame.ul_dl_guard_symbols", 1);
cfg = sixgr.util.structSet(cfg, "frame.special_slot_uplink_symbols", 1);
cfg = sixgr.util.structSet(cfg, "control.coreset_duration", 2);
cfg = sixgr.util.structSet(cfg, "random_access.prach_format", "B4");
cfg = sixgr.util.structSet(cfg, "random_access.configuration_index", 167);
cfg = sixgr.util.structSet(cfg, "random_access.subcarrier_spacing_khz", 30);

fs = sixgr.phy.FrameStructureEngine(cfg);
assert(double(fs.NRB) == 273, "100 MHz / 30 kHz FR1 must resolve to 273 RB.");
assert(double(fs.ConfiguredGridNumRBs) == 66, "Resolver must retain the legacy configured RB count for audit.");
assert(double(fs.FFTSize) == 4096, "100 MHz / 30 kHz FR1 must resolve to a 4096-point FFT.");
assert(double(fs.SampleRate_Hz) == 122880000, "Sample rate must follow FFT*SCS.");
assert(string(fs.ActiveGridSource) == "ts38101_5_3_2_bandwidth_scs_lookup", ...
    "Standard bandwidth/SCS pairs must be explicitly sourced to the TS 38.101 lookup.");
assert(double(fs.PDSCHStartSymbol) == 2 && double(fs.PDSCHNumSymbols) == 12, ...
    "PDSCH must start after the configured two-symbol CORESET.");

partition = fs.SlotPartition(4);
assert(string(partition.SlotLabel) == "S", "DDDSU slot 4 must be the special slot.");
assert(isequal(double(partition.DLSymbolAllocation), [0 12]), ...
    "Special-slot DL symbols must be 0..11 for the configured 12+1+1 split.");
assert(isequal(double(partition.GuardSymbolAllocation), [12 1]), ...
    "Special-slot guard symbol must be symbol 12.");
assert(isequal(double(partition.ULSymbolAllocation), [13 1]), ...
    "Special-slot UL tail must be symbol 13.");

prachSlots = double(fs.PRACHValidSlots1Based);
assert(~isempty(prachSlots), "PRACH valid slots must be resolved for the configured index.");
for slot = prachSlots
    assert(fs.TDDToken(slot) == 'U', ...
        "PRACH valid slots must be UL slots unless the configured PRACH symbols fit inside a special-slot UL tail.");
end

cfg50 = sixgr.util.structSet(cfg, "frequency.bandwidth_hz", 50e6);
fs50 = sixgr.phy.FrameStructureEngine(cfg50);
assert(double(fs50.NRB) == 133 && double(fs50.FFTSize) == 2048, ...
    "50 MHz / 30 kHz FR1 must resolve to 133 RB and 2048 FFT.");

cfg60 = sixgr.util.structSet(cfg, "frame.scs_khz", 60);
fs60 = sixgr.phy.FrameStructureEngine(cfg60);
assert(double(fs60.NRB) == 135, "100 MHz / 60 kHz FR1 must resolve to 135 RB.");

tmp = tempname;
mkdir(tmp);
c = onCleanup(@() rmdir(tmp, "s")); %#ok<NASGU>
scenarioPath = fullfile(pwd, "simulator", "configs", "scenarios", "lls_3gpp_4ghz_100mhz_longrun.yaml");
scfgObj = sixgr.lls6g.config.loadScenarioConfig(scenarioPath);
scfg = scfgObj.toStruct();
scfg.frequency.bandwidth_hz = 50e6;
scfg.frequency.n_size_grid = 273;
scfg.frame.scs_khz = 30;
scfg.control.coreset_duration = 2;
scfg.random_access.prach_format = "B4";
scfg.random_access.configuration_index = 167;
cfgI = sixgr.lls6g.buildInternalConfig(scfg, fullfile(tmp, "resolved"));
assert(double(cfgI.phy.carrier.NSizeGrid) == 133, ...
    "buildInternalConfig must apply frame-structure NRB resolution after YAML/default loading.");
assert(double(sixgr.util.structGet(cfgI, "phy.waveform.fftSize", NaN)) == 2048, ...
    "buildInternalConfig must publish the resolved FFT size.");
assert(double(sixgr.util.structGet(cfgI, "phy.pdsch.startSymbol", NaN)) >= ...
    double(sixgr.util.structGet(cfgI, "phy.pdcch.coreset.duration", NaN)), ...
    "Resolved internal PDSCH start must not overlap CORESET.");

validSlots = double(sixgr.util.structGet(cfgI, "phy.prach.validSlots1Based", []));
assert(~isempty(validSlots), "Resolved internal config must expose PRACH-valid slots.");
for slot = validSlots
    p = sixgr.util.resolveTDDSlotPartition(cfgI, slot);
    assert(logical(p.AllowUL) && ~logical(p.IsSpecialSlot), ...
        "Resolved PRACH slots for the configured PRACH index must land in UL slots for the DDDSU 12+1+1 pattern.");
end

ok = true;
end
