function ok = testDCITDRAFailureDiagnostics()
cfg = struct(); cfg.phy.carrier.NSizeGrid = 24;
% TDRA tests still construct a real DCI context: declare its receiver clock.
% Production code must not infer PUCCH numerology from an absent UL context.
cfg.phy.carrier.SubcarrierSpacing = 30;
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
% The same symbol span can denote different data slots. Exercise both
% downlink K0 and uplink K2; an explicit TDRA index must agree too.
cfg.phy.pdsch.timeDomainAllocations = [0 2 10 0; 1 2 10 3];
cfg.phy.pusch.timeDomainAllocations = [0 0 10 1; 1 0 10 4];
for direction = ["DL","UL"]
    if direction == "DL", fmt = "1_0"; allocation = [2 10]; name = 'K0'; offset = 3;
    else, fmt = "0_0"; allocation = [0 10]; name = 'K2'; offset = 4; end
    grant = struct('Direction',direction,'RNTI',1,'SymbolAllocation',allocation);
    grant.(name) = offset;
    [context,index] = sixgr.phy.pdcch.DCIContextFactory.fromScheduledGrant(cfg,grant,fmt);
    assert(index == 1);
    if direction == "DL", rows = context.Data.DLTimeDomainAllocations;
    else, rows = context.Data.ULTimeDomainAllocations; end
    assert(rows(rows(:,1)==index,4) == offset);
    wrong = grant; wrong.TDRAIndex = 0;
    localReject(@()sixgr.phy.pdcch.DCIContextFactory.fromScheduledGrant(cfg,wrong,fmt), ...
        'sixgr:phy:pdcch:grant_tdra_index_mismatch');
    for badOffset = [-1 0.5 2 Inf]
        wrong = grant; wrong.(name) = badOffset;
        localReject(@()sixgr.phy.pdcch.DCIContextFactory.fromScheduledGrant(cfg,wrong,fmt), ...
            'sixgr:phy:pdcch:grant_tdra_timing_mismatch');
    end
    wrong = grant; wrong.TimingDecision = struct(name,offset+1);
    localReject(@()sixgr.phy.pdcch.DCIContextFactory.fromScheduledGrant(cfg,wrong,fmt), ...
        'sixgr:phy:pdcch:grant_tdra_timing_mismatch');
end
probe=struct('Direction',"DL",'RNTI',1,'SymbolAllocation',[2 10],'K0',0);
bad=cfg; bad.phy.carrier=rmfield(bad.phy.carrier,'SubcarrierSpacing');
localReject(@()sixgr.phy.pdcch.DCIContextFactory.fromScheduledGrant(bad,probe,"1_0"), ...
    'sixgr:phy:pdcch:InvalidFeedbackTimingValue');
separateUL=cfg; separateUL.phy.bwp.ul=struct('NStartBWP',0,'NSizeBWP',24,'SCSKHz',15);
[context,~]=sixgr.phy.pdcch.DCIContextFactory.fromScheduledGrant(separateUL,probe,"1_0");
assert(context.Data.PUCCHSubcarrierSpacingKHz==15, ...
    'PUCCH timing must follow the explicit UL BWP, not the 30 kHz DL carrier.');
ok = true;
fprintf('PASS testDCITDRAFailureDiagnostics: DL K0/UL K2 row selection and typed allocation/timing failures.\n');
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
