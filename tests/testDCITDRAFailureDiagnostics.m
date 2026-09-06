function ok = testDCITDRAFailureDiagnostics()
cfg = struct(); cfg.phy.carrier.NSizeGrid = 24;
cfg.phy.pdsch.timeDomainAllocations = [0 2 10 0];
cfg.phy.pusch.timeDomainAllocations = [0 0 10 1];
for direction = ["DL","UL"]
    if direction == "DL", fmt = "1_0"; allocation = [2 10];
    else, fmt = "0_0"; allocation = [0 10]; end
    grant = struct('Direction',direction,'RNTI',1,'SymbolAllocation',allocation);
    [~,index] = sixgr.phy.pdcch.DCIContextFactory.fromScheduledGrant(cfg,grant,fmt);
    assert(index == 0);
    missing = grant; missing.SymbolAllocation = [0 1];
    localReject(@()sixgr.phy.pdcch.DCIContextFactory.fromScheduledGrant(cfg,missing,fmt), ...
        'sixgr:phy:pdcch:grant_tdra_not_configured');
    wrong = grant; wrong.TDRAIndex = 1;
    localReject(@()sixgr.phy.pdcch.DCIContextFactory.fromScheduledGrant(cfg,wrong,fmt), ...
        'sixgr:phy:pdcch:grant_tdra_index_mismatch');
end
ok = true;
fprintf('PASS testDCITDRAFailureDiagnostics: typed errors for invalid DL/UL allocations.\n');
end
function localReject(call,identifier)
try
    call();
catch exception
    assert(strcmp(exception.identifier,identifier), ...
        'Expected %s, received %s: %s.',identifier,exception.identifier,exception.message);
    return;
end
error('testDCITDRAFailureDiagnostics:MissingRejection','Expected %s.',identifier);
end
