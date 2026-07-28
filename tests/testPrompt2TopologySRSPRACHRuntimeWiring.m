function ok = testPrompt2TopologySRSPRACHRuntimeWiring()
%TESTPROMPT2TOPOLOGYSRSPRACHRUNTIMEWIRING Guard topology, SRS and PRACH runtime wiring.

setup6GRSimToolkit("Verbose", false, "RunToolboxChecks", false);

masterPath = fullfile(pwd, "simulator", "configs", "scenarios", "master_geometry_based.yaml");
assert(exist(masterPath, "file") == 2, "Missing master_geometry_based.yaml.");

scfg = sixgr.lls6g.config.loadScenarioConfig(masterPath);
resolved = scfg.toStruct();
expectedSpeedKmh = double(sixgr.util.structGet(resolved, ...
    "random_access.speed_kmh", NaN));
expectedDopplerHz = (expectedSpeedKmh / 3.6) * 4.0e9 / 299792458;

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

multiUser = struct( ...
    "Enabled", true, ...
    "NumUsers", 2, ...
    "RNTIStart", 1, ...
    "SeedStride", 17, ...
    "ExecutionModel", "slot_coupled_truth");
state = sixgr.truth.CoupledTruthRuntime.initialize(cfg, fullfile(tmp, "runtime"), multiUser, struct(), 1);
state = sixgr.truth.CoupledTruthRuntime.advanceFrame(state, cfg, multiUser, 1, 18);
state.CurrentServingIdx(:) = [1; 2];
[cfgCell1, state] = sixgr.truth.CoupledTruthRuntime.applyUserContext(cfg, state, 1, "DL");
[cfgCell2, state] = sixgr.truth.CoupledTruthRuntime.applyUserContext(cfg, state, 2, "DL");
localAssertRuntimeCellIdentity(cfgCell1, 1, "UE1/Cell1 DL runtime");
localAssertRuntimeCellIdentity(cfgCell2, 2, "UE2/Cell2 DL runtime");
assert(double(sixgr.util.structGet(cfgCell1, "phy.carrier.NCellID", NaN)) ~= ...
    double(sixgr.util.structGet(cfgCell2, "phy.carrier.NCellID", NaN)), ...
    "Two-cell coupled runtime must not reuse one global PHY NCellID for both cells.");
state = localPrepareBootstrapSchedulingState(state);
[state, grantsSlot11] = sixgr.truth.CoupledTruthRuntime.scheduleDirection(state, cfg, "DL");
assert(numel(grantsSlot11) == 1 && double(grantsSlot11(1).ServingCell) == 1, ...
    "First conservative-bootstrap full-reuse DL slot must allow only the selected clean cell.");
% Use the next DL control slot whose configured K1=4 feedback lands in the
% full UL slot of the five-slot TDD period.
state.CurrentSlot = 16;
state = localMarkControlSuccessAtCurrentSlot(state);
state.DLDecodeSuccessCountByUE(1) = 1;
[state, grantsSlot12] = sixgr.truth.CoupledTruthRuntime.scheduleDirection(state, cfg, "DL");
assert(numel(grantsSlot12) == 1 && double(grantsSlot12(1).ServingCell) == 2, ...
    "Second conservative-bootstrap full-reuse DL slot must protect the other cell's first decode. Got %s. State %s.", ...
    localGrantSummary(grantsSlot12), localStateSummary(state));
state.CurrentSlot = 21;
state = localMarkControlSuccessAtCurrentSlot(state);
state.DLDecodeSuccessCountByUE(:) = 1;
[~, grantsSlot13] = sixgr.truth.CoupledTruthRuntime.scheduleDirection(state, cfg, "DL");
assert(numel(grantsSlot13) == 2, ...
    "After both UEs have successful DL decode history, normal two-cell reuse must be allowed. Got %s.", ...
    localGrantSummary(grantsSlot13));

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
localAssertPRACHRuntimeConfig(prachCfg, expectedSpeedKmh, ...
    expectedDopplerHz, "PRACH runtime config");

prachStrict = sixgr.phy.prach.PRACHConfigStrict(cfg, ...
    "RunFolder", tmp, "ScenarioName", "prompt2_topology_srs_prach_runtime_wiring");
localAssertPRACHRuntimeConfig(prachStrict, expectedSpeedKmh, ...
    expectedDopplerHz, "Strict PRACH config");
assert(logical(prachStrict.StrictValidation.StrictValid), ...
    "Strict PRACH validation must pass for the resolved 4 GHz UMa/CDL-C configuration.");

ok = true;
end

function state = localPrepareBootstrapSchedulingState(state)
state.CurrentSlot = 11;
state.CurrentFrame = 1;
state.CurrentSlotDLAllowed = true;
state.CurrentSlotULAllowed = true;
state.CfgMobility = sixgr.util.structSet(state.CfgMobility, "mac.scheduler.coverageOutageGuardEnabled", false);
state.CfgMobility = sixgr.util.structSet(state.CfgMobility, "system.scheduler.coverageOutageGuardEnabled", false);
state.CurrentServingIdx(:) = [1; 2];
state.DLQueueBits(:) = 2e6;
state.ControlEligibility(:) = true;
state.SchedulingEligibility(:) = true;
state.CellAcquisitionState(:) = "acquired";
state.AccessState(:) = "succeeded";
state.SRSValidityState(:) = "valid";
state.CSIValidityState(:) = "bootstrap_csi_unavailable";
state = localMarkControlSuccessAtCurrentSlot(state);
state.CSIValidityState(:) = "bootstrap_csi_unavailable";
if isfield(state, "SRSValidityState")
    state.SRSValidityState(:) = "valid";
end
if isfield(state, "CellAcquisitionState")
    state.CellAcquisitionState(:) = "acquired";
end
if isfield(state, "AccessState")
    state.AccessState(:) = "succeeded";
end
if isfield(state, "ControlEligibility")
    state.ControlEligibility(:) = true;
end
if isfield(state, "SchedulingEligibility")
    state.SchedulingEligibility(:) = true;
end
if isfield(state, "CoverageEligibility")
    state.CoverageEligibility(:) = true;
end
if isfield(state, "CoverageOutageState")
    state.CoverageOutageState(:) = "eligible";
end
if isfield(state, "SchedulingOpportunitiesBlockedByGatingCount")
    state.SchedulingOpportunitiesBlockedByGatingCount(:) = 0;
end
if isfield(state, "GrantsBlockedByGatingCount")
    state.GrantsBlockedByGatingCount(:) = 0;
end
if isfield(state, "LatestDLFeedback")
    for i = 1:numel(state.LatestDLFeedback)
        state.LatestDLFeedback(i).Valid = false;
        state.LatestDLFeedback(i).CQI = NaN;
        state.LatestDLFeedback(i).BootstrapCQIUsableForScheduling = false;
        state.LatestDLFeedback(i).BootstrapCQISource = "";
        state.LatestDLFeedback(i).MCSIndex = NaN;
        state.LatestDLFeedback(i).SINR_dB = NaN;
    end
end
end

function state = localMarkControlSuccessAtCurrentSlot(state)
slot = double(state.CurrentSlot);
state.LastSuccessfulPBCHSlotByUE(:) = slot;
state.LastSuccessfulPRACHSlotByUE(:) = slot;
state.LastSuccessfulSRSSlotByUE(:) = slot;
if isfield(state, "TRSValidityStateByCell")
    state.TRSValidityStateByCell(:) = "valid";
end
if isfield(state, "TrackingEligibilityByCell")
    state.TrackingEligibilityByCell(:) = true;
end
if isfield(state, "LastSuccessfulTRSSlotByCell")
    state.LastSuccessfulTRSSlotByCell(:) = slot;
end
if isfield(state, "LastSRSObservedSlotByUE")
    state.LastSRSObservedSlotByUE(:) = slot;
end
if isfield(state, "LastTRSObservedSlotByCell")
    state.LastTRSObservedSlotByCell(:) = slot;
end
if isfield(state, "DLDecodeSuccessCountByUE")
    state.DLDecodeSuccessCountByUE(:) = 0;
end
end

function summary = localGrantSummary(grants)
if isempty(grants)
    summary = "no grants";
    return;
end
cells = nan(numel(grants), 1);
ues = nan(numel(grants), 1);
for i = 1:numel(grants)
    cells(i) = double(sixgr.util.structGet(grants(i), "ServingCell", NaN));
    ues(i) = double(sixgr.util.structGet(grants(i), "UEIndex", NaN));
end
summary = sprintf("count=%d cells=%s ues=%s", numel(grants), mat2str(cells.'), mat2str(ues.'));
end

function summary = localStateSummary(state)
valid = false(1, numel(state.LatestDLFeedback));
for i = 1:numel(state.LatestDLFeedback)
    valid(i) = logical(sixgr.util.structGet(state.LatestDLFeedback(i), "Valid", false));
end
summary = sprintf("slot=%g dlAllowed=%d queue=%s serving=%s schedElig=%s ctrlElig=%s success=%s feedbackValid=%s schedBlocked=%s grantBlocked=%s", ...
    double(sixgr.util.structGet(state, "CurrentSlot", NaN)), ...
    logical(sixgr.util.structGet(state, "CurrentSlotDLAllowed", false)), ...
    mat2str(double(sixgr.util.structGet(state, "DLQueueBits", [])).'), ...
    mat2str(double(sixgr.util.structGet(state, "CurrentServingIdx", [])).'), ...
    mat2str(logical(sixgr.util.structGet(state, "SchedulingEligibility", [])).'), ...
    mat2str(logical(sixgr.util.structGet(state, "ControlEligibility", [])).'), ...
    mat2str(double(sixgr.util.structGet(state, "DLDecodeSuccessCountByUE", [])).'), ...
    mat2str(valid), ...
    mat2str(double(sixgr.util.structGet(state, "SchedulingOpportunitiesBlockedByGatingCount", [])).'), ...
    mat2str(double(sixgr.util.structGet(state, "GrantsBlockedByGatingCount", [])).'));
end

function localAssertPRACHRuntimeConfig(prachCfg, expectedSpeedKmh, ...
        expectedDopplerHz, label)
assert(abs(double(prachCfg.CarrierFrequencyHz) - 4.0e9) < 1e-3, ...
    "%s must inherit the 4 GHz carrier frequency.", label);
assert(strcmpi(char(string(prachCfg.ChannelModel)), "CDL-C"), ...
    "%s must use CDL-C, not AWGN or CDL-D.", label);
assert(abs(double(prachCfg.DelaySpread_ns) - 93) < 1e-12, ...
    "%s must use the 93 ns UMa delay spread.", label);
assert(abs(double(prachCfg.Speed_kmh) - expectedSpeedKmh) < 1e-12, ...
    "%s must use the configured %.15g km/h mobility.", ...
    label, expectedSpeedKmh);
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

function localAssertRuntimeCellIdentity(cfg, expectedNCellID, label)
paths = [ ...
    "phy.carrier.NCellID", ...
    "phy.NCellID", ...
    "phy.pdsch.NID", ...
    "phy.pusch.NID", ...
    "phy.pdcch.dmrsScramblingID", ...
    "phy.pdcch.coreset.shiftIndex", ...
    "reference_signals.csi_rs_scrambling_id", ...
    "random_access.n_cell_id", ...
    "prach_lls.NCellID", ...
    "lls6g.userContext.RuntimeServingNCellID"];
for i = 1:numel(paths)
    actual = double(sixgr.util.structGet(cfg, paths(i), NaN));
    assert(actual == double(expectedNCellID), ...
        "%s must resolve %s to NCellID %d, got %.15g.", ...
        label, paths(i), double(expectedNCellID), actual);
end
end

function localCleanupTempFolder(tmp)
if isfolder(tmp)
    rmdir(tmp, "s");
end
end
