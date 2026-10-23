function ok = testType0ScenarioFrequencyAuthority()
% Exact target YAMLs must fit their SSB-relative common-control references.
% Configuration/resource qualification only, not decoded access acceptance.
setup6GRSimToolkit('Verbose',false);
names = ["lls_tdd_5mhz_rank2_shared_awgn_20db.yaml", ...
    "h4_100_cdlc100_connected_impaired_40db_gate.yaml"];
starts = [0 126];
indices = [1 0];
% H4 now installs SearchSpaceZero=4 (O=5,M=1): for i=0 and
% mu=1, TS 38.213 V18.8.0 13 / Table 13-11 gives n0=5*2^1=10.
% Do not retain the old SearchSpaceZero=0 expectation after the YAML change.
slots = [2 10];
for k = 1:numel(names)
    scenario = sixgr.lls6g.config.loadScenarioConfig(fullfile( ...
        'simulator','configs','scenarios',names(k)));
    cfg = sixgr.lls6g.buildInternalConfig(scenario,tempname);
    carrier = sixgr.phy.grid.makeCarrier(cfg);
    [control,~,~,resolution,slot] = ...
        sixgr.phy.broadcast.resolveSIB1ControlOccasion(carrier,cfg);
    assert(resolution.CORESET0.RBStart == starts(k));
    assert(resolution.CORESET0Index == indices(k));
    assert(control.NStartBWP == starts(k) && control.NSizeBWP == 24);
    assert(slot == slots(k),'Type-0 slot %g differs from expected %g for %s.', ...
        slot,slots(k),names(k));
    if k==2
        assert(cfg.phy.mib.pdcchConfigSIB1==4 && resolution.SearchSpaceZero==4);
    end
    ra = sixgr.mac.ra.RAConfig(cfg,'UEId',1,'AttemptId',1);
    assert(ra.Msg4DCIReference.FrequencyReferenceStart == starts(k));
    assert(ra.Msg2PDSCH.PRBStart == starts(k));
    assert(ra.Msg4PDSCH.PRBStart == starts(k));
    msg4 = sixgr.phy.ra.scheduleMsg4(ra);
    assert(isequal(msg4.PDSCH.PRBSet(:).', starts(k)+(0:23)));
    frame = sixgr.phy.FrameStructureEngine(cfg,'FrameCoreOnly',true);
    assert(frame.IsDLAllocation(ra.Msg4Slot, ...
        [ra.Msg4PDSCH.SymbolStart ra.Msg4PDSCH.NumSymbols]));
    if k == 1
        bad = cfg;
        bad.phy.mib.pdcchConfigSIB1 = 2;
        rejected = false;
        try
            sixgr.phy.broadcast.resolveSIB1ControlOccasion(carrier,bad);
        catch cause
            assert(strcmp(cause.identifier,'sixgr:phy:pdcch:type0_context_not_supported'));
            rejected = true;
        end
        assert(rejected,'The old 26-RB end on a 25-RB carrier must remain invalid.');
    end
end
ok = true;
end
