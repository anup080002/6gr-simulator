function ok = testSystemAllocationFailureVisibility()
% An invalid enabled TRS cannot silently suppress all primary DL grants.
setup6GRSimToolkit('Verbose',false);
scfg=sixgr.lls6g.config.loadScenarioConfig(fullfile('simulator','configs', ...
    'scenarios','master_geometry_based.yaml'));
root=tempname;
mkdir(root);
cleanup=onCleanup(@() rmdir(root,'s')); %#ok<NASGU>
ok=localExercise(scfg,root);
end

function ok=localExercise(scfg,root)
cfg=sixgr.lls6g.buildInternalConfig(scfg,root);
trs=sixgr.phy.trs.buildTRSConfigFromScenario(cfg);
assert(trs.RowNumber==1 && trs.NumCSIRSPortsRequested==1 && ...
    isequal(reshape(trs.SymbolLocation,1,[]),[4 8]) && trs.SlotAuthority=="periodic_offset", ...
    'Unexpected resolved TRS authority: %s',jsonencode(struct( ...
    'Row',trs.RowNumber,'Ports',trs.NumCSIRSPortsRequested, ...
    'Symbols',trs.SymbolLocation,'Authority',trs.SlotAuthority,'Slots',trs.SlotNumbers)));
assert(isequal(reshape(trs.SlotNumbers,1,[]),[1 2]), ...
    'Unexpected resolved TRS slots: %s',jsonencode(trs.SlotNumbers));
assert(trs.PeriodOffset==1 && trs.BurstLengthSlots==2);
nextWindow=sixgr.truth.resolveTRSObservationWindow(cfg,22);
assert(nextWindow.ObservationStarts && ...
    isequal(nextWindow.AbsoluteSlotNumbers,[21 22]));
% Explicit invalid input reproduces the historical operator configuration.
cfg.phy.trs.csirsRowNumber=2;
cfg.phy.trs.symbolLocation=4;
ctx=sixgr.core.SimContext(cfg,'RunFolder',root);
closeLog=onCleanup(@() ctx.Logger.close()); %#ok<NASGU>
ctx.Logger.EchoToConsole=false;
try
    sixgr.system.SystemLevelRunner.run(ctx,struct( ...
        'PHYBackend','waveform','NumTTI',1));
catch ME
    assert(strcmp(ME.identifier,'sixgr:phy:grid:allocREsPDSCH:TRSReservationFailed'), ...
        'An invalid enabled TRS must surface its original allocation failure.');
    ok=true;
    return;
end
error('test:ExpectedAllocationFailure', ...
    'The scheduler hid an invalid enabled TRS as an empty successful run.');
end
