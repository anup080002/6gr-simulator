function ok = testExactDLULAllocationPreflight()
%TESTEXACTDLULALLOCATIONPREFLIGHT Guard fail-closed YAML-to-RE resolution.

setup6GRSimToolkit("Verbose", false);
root = fileparts(fileparts(mfilename("fullpath")));
scenarioPath = fullfile(root, "simulator", "configs", "scenarios", ...
    "lls_causal_access_to_data_wiring.yaml");
scenario = sixgr.lls6g.config.loadScenarioConfig(scenarioPath);
cfg = sixgr.lls6g.buildInternalConfig(scenario, fullfile(tempdir, ...
    "sixgr_exact_dl_ul_allocation_preflight"));

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
