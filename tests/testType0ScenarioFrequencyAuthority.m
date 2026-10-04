function ok = testType0ScenarioFrequencyAuthority()
% Exact target YAMLs must fit their SSB-relative common-control references.
% Configuration/resource qualification only, not decoded access acceptance.
setup6GRSimToolkit('Verbose',false);
names = ["lls_tdd_5mhz_rank2_shared_awgn_20db.yaml", ...
    "h4_100_cdlc100_connected_impaired_40db_gate.yaml"];
starts = [0 126];
indices = [1 0];
slots = [2 0];
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
    assert(slot == slots(k));
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
