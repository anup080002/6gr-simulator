function ok = testConfiguredDCITimingOffsets()
% Shipped constant-offset profiles must encode their scheduler K0/K2 in DCI.
% This does not require all possible scenarios to use a constant-offset table.
profiles = ["master_geometry_based", "master_sinr_sweep", ...
    "webgui_sinr_sweep_64x4_mu_mimo_full"];
for profile = profiles
    scenario = sixgr.lls6g.config.loadScenarioConfig(fullfile(pwd, ...
        "simulator", "configs", "scenarios", profile + ".yaml"));
    cfg = sixgr.lls6g.buildInternalConfig(scenario, tempname);
    for direction = ["DL", "UL"]
        if direction == "DL"
            format = "1_1"; offsetName = "K0";
            tableName = "DLTimeDomainAllocations";
            timingPath = "phy.schedulingTiming.pdcchToPDSCHK0";
        else
            format = "0_1"; offsetName = "K2";
            tableName = "ULTimeDomainAllocations";
            timingPath = "phy.schedulingTiming.pdcchToPUSCHK2";
        end
        context = sixgr.phy.pdcch.DCIContextFactory.fromRuntimeConfig(cfg, format);
        rows = double(context.value(tableName));
        expected = double(sixgr.util.structGet(cfg, timingPath, NaN));
        assert(isfinite(expected) && size(rows,2) == 4 && ...
            all(rows(:,4) == expected), ...
            '%s: %s TDRA offsets must match its configured scheduler timing.', ...
            profile, direction);
        for row = 1:size(rows,1)
            grant = struct('Direction', direction, 'RNTI', 1, ...
                'SymbolAllocation', rows(row,2:3));
            grant.(offsetName) = expected;
            [bound, index, source] = ...
                sixgr.phy.pdcch.DCIContextFactory.fromScheduledGrant(cfg, grant, format);
            assert(index == rows(row,1) && source == "operator_rrc_dci_context");
            assert(isequal(bound.value(tableName), rows), ...
                'Grant binding must not rewrite the configured TDRA table.');
        end
        % A scheduler/configuration disagreement must still fail closed.
        grant.(offsetName) = expected + 1;
        try
            sixgr.phy.pdcch.DCIContextFactory.fromScheduledGrant(cfg, grant, format);
            error('test:MissingTimingRejection', 'Mismatched offset was accepted.');
        catch cause
            assert(strcmp(cause.identifier, ...
                'sixgr:phy:pdcch:grant_tdra_timing_mismatch'), cause.message);
        end
    end
end
ok = true;
disp('CONFIGURED_DCI_TIMING_PASS: 96 DL/UL allocation bindings; mismatches rejected.');
end
