function ok=testLegacyWidebandTRSCalendar()
% Native reference-symbol production/reservations, not physical reception.
% TS 38.214 V18.8.0 5.1.6.1.1: retain 273 RBs and use 20 ms.
setup6GRSimToolkit('Verbose',false,'RunToolboxChecks',false);
for name=["master_sinr_sweep","master_geometry_based"]
    scenario=sixgr.lls6g.config.loadScenarioConfig(fullfile( ...
        'simulator','configs','scenarios',name+".yaml"));
    s=scenario.toStruct();
    assert(s.reference_signals.trs_periodicity_ms==20 && ...
        s.reference_signals.trs.num_rb==273 && ...
        s.reference_signals.trs.period_offset==1 && ...
        s.reference_signals.trs.burst_length_slots==2 && ...
        isequal(double(s.reference_signals.trs.symbol_locations(:).'),[4 8]));
    fprintf('LEGACY_TRS_DECLARATION_PASS %s period_ms=20 width_RB=273 full_build_not_claimed\n',name);
end
% Geometry's unsupported Type-II/subband CSI remains rejected by its actual
% full builder. Do not disable it to manufacture a TRS integration pass.
% The enabled inheriting WebGUI configuration exercises native production
% and the real reservation owner; n40 separately proves its own 10-ms policy.
names=["webgui_sinr_sweep_64x4_mu_mimo_full", ...
    "lls_tdd_n40_20mhz_64txru_4rx_cdlc100_reference_snr_sweep"];
periods=[40 20]; widths=[273 51]; offsets=[1 6];
failures=strings(0,1);
for k=1:numel(names)
    try
        localCheck(names(k),periods(k),widths(k),offsets(k));
    catch cause
        failures(end+1,1)=names(k)+": "+string(cause.identifier)+" "+string(cause.message); %#ok<AGROW>
        fprintf(2,'LEGACY_TRS_NATIVE_FAIL %s\n',failures(end));
    end
end
assert(isempty(failures),'test:LegacyTRSCalendarFailed', ...
    '%d/%d native calendar checks failed:\n%s', ...
    numel(failures),numel(names),char(strjoin(failures,newline)));
ok=true;
end

function localCheck(name,period,width,offset)
scenario=sixgr.lls6g.config.loadScenarioConfig(fullfile( ...
    'simulator','configs','scenarios',name+".yaml"));
cfg=sixgr.lls6g.buildInternalConfig(scenario,tempname);
assert(cfg.phy.trs.enable && cfg.phy.trs.period_slots==period && ...
    cfg.phy.trs.period_offset==offset);
frame=sixgr.phy.FrameStructureEngine(cfg,'FrameCoreOnly',true);
plan=sixgr.phy.frame.CommonDLResourcePlan(cfg);
for start0=offset+[0 period]
    strict=sixgr.phy.trs.buildTRSConfigFromScenario(cfg,'RuntimeSlot',start0+1);
    assert(strict.NumRB==width && strict.PeriodicityValidation.Valid && ...
        strict.PeriodicityValidation.PeriodSlots==period && ...
        strict.PeriodicityValidation.PeriodMilliseconds==period/2 && ...
        isequal(strict.SlotNumbers,start0+[0 1]));
    assert(all(cellfun(@(resource)resource.NumRB==width,strict.ToolboxResources)));
    emitted=sixgr.phy.trs.generateTRSSymbolsAndIndices(strict);
    assert(numel(emitted.SlotResources)==2);
    for ordinal=1:2
        actual=emitted.SlotResources(ordinal);
        assert(actual.Slot==start0+ordinal-1 && ~isempty(actual.Indices) && ...
            numel(actual.Symbols)==numel(actual.Indices) && all(isfinite(actual.Symbols)));
        prepared=plan.prepareSlot(actual.Slot);
        assert(isequal(sort(unique(double(actual.Indices(:))-1)), ...
            sort(prepared.PreparedTRSRE0(:))), ...
            'Real emitted TRS REs and common-channel reservations disagree.');
        [~,symbols]=ind2sub([actual.K actual.L],double(actual.Indices));
        symbols=unique(double(symbols)-1);
        assert(isequal(sort(symbols(:)),sort(double(strict.SymbolLocation(:)))));
        for symbol=symbols(:).'
            assert(frame.IsDLAllocation(actual.Slot,[symbol 1]), ...
                'TRS native mapping overlaps a non-DL symbol.');
        end
        assert(sixgr.truth.isActiveTRSOccasion(cfg,actual.Slot+1));
    end
end
% No resource remains at the removed half-period. This is a calendar test,
% not a relaxation of the separate tracking-reference freshness policy.
for slot0=offset+period/2+[0 1]
    prepared=plan.prepareSlot(slot0);
    assert(isempty(prepared.PreparedTRSRE0) && ...
        ~sixgr.truth.isActiveTRSOccasion(cfg,slot0+1));
end
fprintf('LEGACY_TRS_NATIVE_PASS %s period_slots=%d width_RB=%d producer_reservation_TDD=4 receiver_trials=0\n', ...
    name,period,width);
end
