function ok = testYAMLDuplexAuthorityIsolation()
%TESTYAMLDUPLEXAUTHORITYISOLATION Prove duplex is singular and YAML-owned.

setup6GRSimToolkit("Verbose", false, "RunToolboxChecks", false);
root = fileparts(fileparts(mfilename("fullpath")));
fddPath = fullfile(root, "simulator", "configs", "scenarios", ...
    "lls_causal_access_to_data_wiring.yaml");
fddScenario = sixgr.lls6g.config.loadScenarioConfig(fddPath);
fddRaw = fddScenario.toStruct();
assert(string(fddRaw.frequency.duplex_mode) == "FDD");
assert(string(fddRaw.global_radio_scope.duplex_mode) == "FDD");
assert(~isfield(fddRaw.frame, "tdd_common") && ...
    ~isfield(fddRaw.frame_timing, "tdd_common") && ...
    ~isfield(fddRaw, "tdd_timing"));
assert(isfield(fddRaw, "scheduling_timing"));

fddCfg = sixgr.lls6g.buildInternalConfig(fddRaw, string(tempname));
assert(string(fddCfg.phy.duplex.mode) == "FDD");
assert(isfield(fddCfg.phy.duplex, "fdd") && ...
    ~isfield(fddCfg.phy.duplex, "tddCommon") && ...
    ~isfield(fddCfg.phy, "tddTiming") && ...
    isfield(fddCfg.phy, "schedulingTiming"));
fddFrame = sixgr.phy.FrameStructureEngine(fddCfg, ...
    "FrameCoreOnly", true);
assert(fddFrame.DuplexMode == "FDD" && ...
    fddFrame.TDDPattern == "not_applicable" && ...
    isempty(fddFrame.SlotState) && ~isempty(fddFrame.FDDContexts));
assert(fddFrame.IsDLSlot(0) && fddFrame.IsULSlot(0));
assert(fddCfg.phy.duplex.fdd.dlCenterFrequencyHz ~= ...
    fddCfg.phy.duplex.fdd.ulCenterFrequencyHz);

bad = fddRaw;
bad.global_radio_scope.duplex_mode = "TDD";
localMustThrow(@() sixgr.lls6g.buildInternalConfig(bad, string(tempname)), ...
    "sixgr:phy:frame:DuplexAuthorityMismatch");

bad = fddRaw;
bad.frame.tdd_common = localTDDCommon();
localMustThrow(@() sixgr.lls6g.buildInternalConfig(bad, string(tempname)), ...
    "sixgr:lls6g:TDDPatternPresentForFDD");

tddPath = fullfile(root, "simulator", "configs", "scenarios", ...
    "dl_4ghz_baseline.yaml");
tddScenario = sixgr.lls6g.config.loadScenarioConfig(tddPath);
tddRaw = tddScenario.toStruct();
% Keep the duplex regression focused while satisfying the unrelated strict
% reference-signal schedule contract of this legacy TDD fixture.
tddRaw.random_access.enabled = false;
tddRaw.reference_signals.csi_rs_periodicity_slots = 4;
tddRaw.reference_signals.csi_rs_offset_slots = 1;
tddRaw.tdd_timing.k1_selection_policy = "first_valid_configured";
tddCfg = sixgr.lls6g.buildInternalConfig(tddRaw, string(tempname));
assert(string(tddCfg.phy.duplex.mode) == "TDD");
assert(isfield(tddCfg.phy.duplex, "tddCommon") && ...
    ~isfield(tddCfg.phy.duplex, "fdd") && ...
    isfield(tddCfg.phy, "schedulingTiming"));
tddFrame = sixgr.phy.FrameStructureEngine(tddCfg, ...
    "FrameCoreOnly", true);
assert(tddFrame.DuplexMode == "TDD" && ...
    ~isempty(tddFrame.SlotState) && isempty(tddFrame.FDDContexts));

bad = tddRaw;
bad.frequency.dl_center_frequency_hz = bad.frequency.center_frequency_hz;
bad.frequency.ul_center_frequency_hz = ...
    bad.frequency.center_frequency_hz - 1e6;
localMustThrow(@() sixgr.lls6g.buildInternalConfig(bad, string(tempname)), ...
    "sixgr:lls6g:FDDFieldsPresentForTDD");

bad = fddRaw;
bad.scheduling_timing.ul_grant_k2 = ...
    bad.scheduling_timing.pdcch_to_pusch_k2 + 1;
localMustThrow(@() sixgr.lls6g.buildInternalConfig(bad, string(tempname)), ...
    "sixgr:lls6g:ConflictingK2Authority");

ok = true;
fprintf("[PASS] testYAMLDuplexAuthorityIsolation\n");
end

function value = localTDDCommon()
value = struct( ...
    "ReferenceSubcarrierSpacingKHz", 15, ...
    "Pattern1", struct( ...
        "PeriodicityMilliseconds", 5, ...
        "NumDownlinkSlots", 3, ...
        "NumDownlinkSymbols", 4, ...
        "NumUplinkSlots", 1, ...
        "NumUplinkSymbols", 2));
end

function localMustThrow(fcn, identifier)
threw = false;
try
    fcn();
catch ME
    threw = true;
    assert(string(ME.identifier) == string(identifier), ...
        "Expected %s, received %s: %s", ...
        identifier, ME.identifier, ME.message);
end
assert(threw, "Expected typed failure %s.", identifier);
end
