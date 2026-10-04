function ok = testExactDLULAllocationPreflight()
%TESTEXACTDLULALLOCATIONPREFLIGHT Guard fail-closed YAML-to-RE resolution.

setup6GRSimToolkit("Verbose", false);
root = fileparts(fileparts(mfilename("fullpath")));
scenarioPath = fullfile(root, "simulator", "configs", "scenarios", ...
    "lls_causal_access_to_data_wiring.yaml");
scenario = sixgr.lls6g.config.loadScenarioConfig(scenarioPath);
cfg = sixgr.lls6g.buildInternalConfig(scenario, fullfile(tempdir, ...
    "sixgr_exact_dl_ul_allocation_preflight"));

% Retain the original invalid CORESET0 geometry as a negative regression.
outside = cfg;
outside.phy.mib.pdcchConfigSIB1 = 2;
[~, outsideChecks] = sixgr.truth.buildPlannedREAllocation(outside, ...
    "TargetChannels", "TYPE0_PDCCH");
type0Check = outsideChecks(outsideChecks.feature == "TYPE0_PDCCH", :);
assert(type0Check.enabled && ~type0Check.resolved && ...
    type0Check.error_id == "sixgr:phy:pdcch:type0_context_not_supported");
localExpectError(@() sixgr.truth.assertAllocationPreflight(outsideChecks), ...
    "sixgr:truth:EnabledAllocationUnresolved");

[allocations, checks] = sixgr.truth.buildPlannedREAllocation(cfg);
sixgr.truth.assertAllocationPreflight(checks);
required = ["FRAME","SSB_PBCH","TYPE0_PDCCH","SIB1_PDSCH", ...
    "PDCCH","PDSCH","CSI_RS","TRS","PRACH","PUCCH","PUSCH","SRS"];
assert(all(ismember(required, string(checks.feature))));
enabled = logical(checks.enabled);
assert(all(checks.resolved(enabled)) && all(checks.status(enabled) == "PASS"));
assert(all(checks.exact_re_count(enabled) > 0));

assert(~isempty(allocations));
assert(all(isfinite(allocations.absolute_slot)));
assert(all(isfinite(allocations.sfn)));
assert(all(isfinite(allocations.slot_within_frame)));
assert(all(isfinite(allocations.subcarrier_start)));
assert(all(isfinite(allocations.subcarrier_count)));
assert(all(isfinite(allocations.symbol_index)));
assert(all(isfinite(allocations.port_index)));
assert(all(allocations.subcarrier_start >= 0));
assert(all(allocations.subcarrier_start + allocations.subcarrier_count <= ...
    allocations.grid_subcarrier_count));
assert(all(allocations.symbol_index >= 0 & allocations.symbol_index < allocations.grid_symbol_count));
[carrierAllocations,nativePRACH]=sixgr.truth.splitREAllocationDomains(allocations);
assert(all(carrierAllocations.grid_domain=="carrier_cp_ofdm") && ...
    ~any(carrierAllocations.channel=="PRACH") && ~isempty(nativePRACH) && ...
    all(nativePRACH.grid_domain=="prach_native_ofdm") && ...
    all(nativePRACH.grid_subcarrier_spacing_hz==1000*cfg.phy.prach.subcarrierSpacing_kHz));
assert(all(ismember(["DL","UL"], unique(string(allocations.direction)))));

% Selecting an output must not disable its configured broadcast dependencies.
for channel = ["TYPE0_PDCCH", "SIB1_PDSCH"]
    [selected, selectedChecks] = sixgr.truth.buildPlannedREAllocation( ...
        cfg, "TargetChannels", channel);
    sixgr.truth.assertAllocationPreflight(selectedChecks);
    expected = allocations(allocations.channel == channel, :);
    assert(~isempty(expected) && isequaln(selected, expected), ...
        "Selected %s allocation must match the full plan exactly.", channel);
end

% Disabled SIB1 must not create a Type-0 obligation, even when SSB is on
% and legacy raw configuration disagrees with the normalized runtime flag.
noSI = cfg;
noSI.phy.sib1.enable = false;
noSI.initial_access.sib1.enable = true;
noSI.phy.mib.pdcchConfigSIB1 = NaN;
broadcast = ["SSB_PBCH", "TYPE0_PDCCH", "SIB1_PDSCH"];
[ssbOnly, disabledChecks] = sixgr.truth.buildPlannedREAllocation( ...
    noSI, "TargetChannels", broadcast);
sixgr.truth.assertAllocationPreflight(disabledChecks);
assert(~isempty(ssbOnly) && all(ssbOnly.channel == "SSB_PBCH"));
siChecks = disabledChecks(ismember(disabledChecks.feature, broadcast(2:3)), :);
assert(all(~siChecks.enabled & siChecks.status == "DISABLED") && ...
    all(siChecks.exact_re_count == 0));

% Re-enabling the same malformed dependency must still fail, for both
% joint and SIB1-only requests. Missing SSB/MIB is not silently disabled.
badSI = noSI;
badSI.phy.sib1.enable = true;
localExpectBroadcastFailure(badSI, broadcast(2:3));
localExpectBroadcastFailure(badSI, "SIB1_PDSCH");
badSI = cfg;
badSI.phy.ssb.enable = false;
localExpectBroadcastFailure(badSI, broadcast(2:3));
badSI = cfg;
badSI.phy.mib.enable = false;
localExpectBroadcastFailure(badSI, "SIB1_PDSCH");

frame = sixgr.phy.FrameStructureEngine(cfg);
assert(string(frame.DuplexMode) == "FDD");
for slot0 = 0:(double(cfg.run.totalSlots)-1)
    assert(frame.IsDLSlot(slot0) && frame.IsULSlot(slot0));
    assert(frame.IsDLAllocation(slot0, [0 14]));
    assert(frame.IsULAllocation(slot0, [0 14]));
end

% A stale wideband bitmap must fail at the shared config boundary instead
% of reaching nrPDCCHConfig or being silently truncated.
bad = scenario.toStruct();
bad.control.coreset_frequency_resource_policy = "explicit_bitmap";
bad.control.coreset_frequency_resources = ones(1, 12);
localExpectError(@() sixgr.lls6g.buildInternalConfig(bad, ...
    fullfile(tempdir, "sixgr_bad_coreset_preflight")), ...
    "sixgr:lls6g:CORESETBitmapOutsideBWP");

ok = true;
fprintf("[PASS] testExactDLULAllocationPreflight rows=%d exactRE=%d\n", ...
    height(allocations), sum(allocations.re_count));
end

function localExpectBroadcastFailure(cfg, channels)
[~, checks] = sixgr.truth.buildPlannedREAllocation(cfg, "TargetChannels", channels);
selected = checks(ismember(checks.feature, channels), :);
assert(all(selected.enabled & ~selected.resolved & selected.status == "FAIL"));
assert(all(selected.error_id == "sixgr:truth:MissingMIBControlAuthority"));
localExpectError(@() sixgr.truth.assertAllocationPreflight(checks), ...
    "sixgr:truth:EnabledAllocationUnresolved");
end

function localExpectError(fn, expectedIdentifier)
thrown = false;
try
    fn();
catch cause
    thrown = true;
    assert(string(cause.identifier) == string(expectedIdentifier), ...
        "Expected %s, received %s: %s", expectedIdentifier, ...
        cause.identifier, cause.message);
end
assert(thrown, "Expected typed failure %s.", expectedIdentifier);
end
