function ok = testRARDefaultATimeAllocation()
% Check every standard row independently, including the Msg3-only delta.
normalSL = [0 14;0 12;0 10;2 10;4 10;4 8;4 6;0 14;0 12;0 10; ...
    0 14;0 12;0 10;8 6;0 14;0 10];
extendedSL = [0 8;0 12;0 10;2 10;4 4;4 8;4 6;0 8;0 12;0 10; ...
    0 6;0 12;0 10;8 4;0 8;0 10];
kOffset = [0 0 0 0 0 0 0 1 1 1 2 2 2 0 3 3];
scsValues = [15 30 60 120 480 960];
j = [1 1 2 3 11 21];
delta = [2 3 4 6 24 48];
for muIndex = 1:numel(scsValues)
    for index = 0:15
        a = sixgr.phy.frame.TimeDomainResourceAllocationCatalog.resolvePUSCHDefaultA( ...
            index, scsValues(muIndex), "normal");
        assert(isequal([a.StartSymbol a.NumSymbols],normalSL(index+1,:)));
        assert(a.K2 == j(muIndex) + kOffset(index+1));
        assert(a.Msg3AdditionalDelaySlots == delta(muIndex));
        assert(a.RowIndex == index+1 && a.TimeResourceAssignment == index);
        assert((a.MappingType == "B") == ismember(index,[3 4 5 6 13]));
    end
end
for index = 0:15
    a = sixgr.phy.frame.TimeDomainResourceAllocationCatalog.resolvePUSCHDefaultA(index,60,"extended");
    assert(isequal([a.StartSymbol a.NumSymbols],extendedSL(index+1,:)));
    assert(a.K2 == 2 + kOffset(index+1) && a.Msg3AdditionalDelaySlots == 4);
    carrier = nrCarrierConfig("SubcarrierSpacing",60,"CyclicPrefix","extended");
    pusch = nrPUSCHConfig("MappingType",char(a.MappingType), ...
        "SymbolAllocation",[a.StartSymbol a.NumSymbols],"PRBSet",0:23);
    assert(~isempty(nrPUSCHIndices(carrier,pusch)), "Every extended-CP allocation must materialize real PUSCH REs.");
end
localThrows(@() sixgr.phy.frame.TimeDomainResourceAllocationCatalog.resolvePUSCHDefaultA(0,240,"normal"), ...
    "sixgr:phy:frame:UnsupportedPUSCHDefaultANumerology");
for index = [-1 0.5 16 NaN Inf]
    localThrows(@() sixgr.phy.frame.TimeDomainResourceAllocationCatalog.resolvePUSCHDefaultA(index,15,"normal"), ...
        "sixgr:phy:frame:InvalidPUSCHDefaultATDRAIndex");
end

% Real MAC codec -> PUSCH configuration and waveform, using a non-full-slot
% mapping-B allocation. Its receiver must obey the received index even when
% the transmitter's planned index in the supplied context differs.
cfg = raStrictAnchorConfig();
cfg.phy.pusch.transformPrecoding = false;
cfg.random_access.msg3_pusch.transform_precoding = false;
cfg.random_access.rar_grant.time_resource_assignment = 3;
cfg.random_access.msg3_pusch.symbol_start = 2;
cfg.random_access.msg3_pusch.num_symbols = 10;
ra = sixgr.mac.ra.RAConfig(cfg);
g = sixgr.mac.ra.buildRARULGrant(ra);
assert(isequal(g.BitVector(16:19),int8([0;0;1;1])));
rxContext = ra;
rxContext.RARGrantConfig.time_resource_assignment = 0;
rxContext.Msg3PUSCH.SymbolStart = 0;
rxContext.Msg3PUSCH.NumSymbols = 14;
decoded = sixgr.mac.ra.RARULGrantCodec.decode(g.BitVector,rxContext);
assert(decoded.SymbolStart == 2 && decoded.NumSymbols == 10 && decoded.MappingType == "B");
assert(decoded.K2 == 1 && decoded.Msg3AdditionalDelaySlots == 3);
msg = sixgr.mac.ra.buildMsg3Payload("UEId",1);
[tx,pusch] = sixgr.phy.ra.generateMsg3PUSCHWaveform(cfg,ra,decoded,msg);
assert(string(pusch.MappingType) == "B" && isequal(pusch.SymbolAllocation,[2 10]));
[rx,parsed] = sixgr.phy.ra.recoverMsg3PUSCH(tx.Waveform,cfg,ra,decoded,tx);
assert(rx.Ok && parsed.ContentionIdentity == msg.ContentionIdentity);
bad = ra; bad.Msg3PUSCH.NumSymbols = 14;
localThrows(@() sixgr.mac.ra.buildRARULGrant(bad),"sixgr:mac:ra:RARTDRAAllocationMismatch");
badCfg = cfg;
badCfg.UECommonCellConfiguration.PUSCHConfigCommon.pusch_TimeDomainAllocationList = ...
    struct("k2",1,"mappingType","typeB","startSymbolAndLength",128);
localThrows(@() sixgr.mac.ra.RAConfig(badCfg),"sixgr:mac:ra:UnsupportedRARCommonTDRAList");
ok = true;
fprintf('PASS testRARDefaultATimeAllocation: all default-A rows, Msg3 delta and mapping-B coded waveform.\n');
end

function localThrows(f,id)
try
    f();
catch err
    assert(string(err.identifier) == id, "Expected %s, received %s: %s",id,err.identifier,err.message);
    return;
end
error("testRARDefaultATimeAllocation:MissingRejection","Expected %s.",id);
end
