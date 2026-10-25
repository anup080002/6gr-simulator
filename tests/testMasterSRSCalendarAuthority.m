function ok = testMasterSRSCalendarAuthority()
% Real YAML/native RE calendars and runtime selection, not received evidence.
setup6GRSimToolkit('Verbose',false,'RunToolboxChecks',false);
names=["master_sinr_sweep", "master_geometry_based", ...
    "webgui_sinr_sweep_64x4_mu_mimo_full"];
failures=strings(0,1);
for name=names
    try
        localCheck(name);
    catch cause
        failures(end+1,1)=name+": "+string(cause.identifier)+" "+string(cause.message); %#ok<AGROW>
        fprintf(2,'MASTER_SRS_CALENDAR_FAIL %s\n',failures(end));
    end
end
assert(isempty(failures),'test:MasterSRSCalendarFailed', ...
    '%d/%d independent configurations failed:\n%s', ...
    numel(failures),numel(names),char(strjoin(failures,newline)));
ok=true;
end

function localCheck(name)
    scenario=sixgr.lls6g.config.loadScenarioConfig(fullfile( ...
        'simulator','configs','scenarios',name+".yaml"));
    original=scenario.toStruct();
    cfg=sixgr.lls6g.buildInternalConfig(scenario,tempname);
    assert(original.reference_signals.srs_periodicity_ms==10 && ...
        isequal(double(original.reference_signals.srs_slot_within_period(:).'),5));
    assert(cfg.phy.srs.period_slots==20 && cfg.phy.srs.period_offset==4 && ...
        isequal(double(cfg.phy.srs.slotWithinPeriod1Based(:).'),5));
    % No enable, period, offset, symbol or resource-policy override is made.
    % Even disabled master resources have a valid inheritable native calendar.
    strict=sixgr.phy.srs.buildSRSConfigFromScenario(cfg);
    assert(strict.SubcarrierSpacingKHz==30 && ...
        isequal(strict.ToolboxSRS.SRSPeriod,[20 4]));
    frame=sixgr.phy.FrameStructureEngine(cfg,'FrameCoreOnly',true);
    % Removing only the redundant optional selector must leave every native
    % frequency/symbol/port coordinate unchanged, including empty occasions.
    nativeOnly=cfg;
    nativeOnly.phy.srs.slotWithinPeriod1Based=[];
    reference=sixgr.phy.srs.buildSRSConfigFromScenario(nativeOnly);
    emitted=false(1,40);
    for slot0=0:39
        carrier=strict.ToolboxCarrier; carrier.NSlot=slot0;
        referenceCarrier=reference.ToolboxCarrier; referenceCarrier.NSlot=slot0;
        indices=nrSRSIndices(carrier,strict.ToolboxSRS);
        referenceIndices=nrSRSIndices(referenceCarrier,reference.ToolboxSRS);
        assert(isequal(indices,referenceIndices), ...
            'Optional selection changed original native SRS RE coordinates.');
        emitted(slot0+1)=~isempty(indices);
        assert(emitted(slot0+1)==ismember(slot0,[4 24]));
        % Multiple users may share one configured occasion. Multiplexing
        % never creates additional phases within this resource period.
        for ue=1:4
            due=sixgr.truth.coupledSRSResourceOpportunity(cfg, ...
                slot0+1,ue,4,20,'multiplex_due_users',4);
            assert(due==emitted(slot0+1));
        end
        if emitted(slot0+1)
            assert(frame.IsULAllocation(slot0, ...
                [strict.SymbolStart strict.NumSRSSymbols]), ...
                'Native SRS occasion overlaps a non-UL symbol.');
            coordinates=nrSRSIndices(carrier,strict.ToolboxSRS,'IndexStyle','subscript');
            assert(isequal(sort(unique(double(coordinates(:,2))-1)).', ...
                sort(strict.ExpectedSymbolSet(:).')));
        end
    end
    assert(isequal(find(emitted),[5 25]));
    malformed=cfg; malformed.phy.srs.slotWithinPeriod1Based=[5 10 15 20];
    localReject(@()sixgr.phy.srs.buildSRSConfigFromScenario(malformed));
    localReject(@()sixgr.truth.coupledSRSResourceOpportunity( ...
        malformed,10,1,4,20,'multiplex_due_users',4));
    fprintf('MASTER_SRS_CALENDAR_PASS %s native_period=20 offset=4 slots=5,25 unchanged_REs=40 TDD_valid=2 receiver_trials=0\n',name);
end

function localReject(operation)
try
    operation();
catch cause
    assert(strcmp(cause.identifier,'sixgr:phy:srs:ScheduleAuthorityMismatch'), ...
        'test:WrongMasterSRSGuard','Unexpected error %s: %s',cause.identifier,cause.message);
    return;
end
error('test:MissingMasterSRSGuard','Contradictory resource phases were not rejected.');
end
