function ok = testSIB1DCITimeAllocation()
% Bit/semantic checks against TS 38.214 V18.7.0 default-A normal-CP rows.
% This test is not physical acquisition or BLER qualification.
setup6GRSimToolkit('Verbose',false);
cfg=sixgr.config.defaultConfig();
carrier=nrCarrierConfig('NSizeGrid',273,'SubcarrierSpacing',30);
cfg.phy.mib.dmrsTypeAPosition=2;
cfg.phy.sib1.resolvedCORESET0=struct('RBStart',126,'NumRB',24);
[tx,pdsch]=sixgr.phy.broadcast.buildSIB1DCI10(carrier,cfg, ...
    'SymbolStart',2,'NumSymbols',7,'MCSIndex',2);
[rx,recovered]=sixgr.phy.broadcast.buildSIB1DCI10(carrier,cfg,'Bits',tx.Bits);
assert(tx.TDRAIndex==3 && rx.TDRAIndex==3 && ...
    isequal(recovered.SymbolAllocation,pdsch.SymbolAllocation), ...
    'test:SIB1TDRAIgnored','SIB1 must signal and independently decode the actual TDRA row.');

starts=[2 2 2 2 2 9 4 5 5 9 12 1 1 2 4 8];
lengths=[12 10 9 7 5 4 4 7 2 2 2 13 6 4 7 4];
mapping=["A" "A" "A" "A" "A" "B" "B" "B" "B" "B" "B" "A" "A" "A" "B" "B"];
for dmrs=[2 3]
    cfg.phy.mib.dmrsTypeAPosition=dmrs;
    s=starts; l=lengths;
    if dmrs==3, s(1:5)=3; l(1:5)=l(1:5)-1; s(6:7)=[10 6]; end
    for row=1:16
        [tx,pdsch]=sixgr.phy.broadcast.buildSIB1DCI10(carrier,cfg, ...
            'SymbolStart',s(row),'NumSymbols',l(row),'MCSIndex',2,'RV',mod(row,4));
        poisoned=cfg;
        poisoned.initial_access.sib1.pdsch=struct('symbol_start',0,'num_symbols',1,'mcs',9);
        [rx,recovered]=sixgr.phy.broadcast.buildSIB1DCI10(carrier,poisoned,'Bits',tx.Bits);
        assert(tx.TDRAIndex==row-1 && rx.TDRAIndex==row-1);
        assert(isequal(recovered.SymbolAllocation,[s(row) l(row)]) && ...
            string(recovered.MappingType)==mapping(row) && ...
            recovered.DMRS.DMRSTypeAPosition==dmrs);
        assert(rx.MCSIndex==2 && rx.RV==mod(row,4) && ...
            abs(rx.TargetCodeRate-193/1024)<eps);
        assert(isequal(nrPDSCHIndices(carrier,pdsch),nrPDSCHIndices(carrier,recovered)));
    end
end
cfg.phy.mib.dmrsTypeAPosition=2;
localReject(@()sixgr.phy.broadcast.buildSIB1DCI10(carrier,cfg, ...
    'SymbolStart',2,'NumSymbols',8),'sixgr:phy:broadcast:InvalidSIB1TDRA');
for mcs=[-1 0.5 10 17 29 NaN]
    localReject(@()sixgr.phy.broadcast.buildSIB1DCI10(carrier,cfg, ...
        'MCSIndex',mcs),'sixgr:phy:broadcast:UnsupportedSIB1MCS');
end
localReject(@()sixgr.phy.broadcast.buildSIB1DCI10(carrier,cfg, ...
    'PRBStart',24,'PRBCount',2),'sixgr:phy:broadcast:SIB1AllocationOutsideBWP');
[tx,~]=sixgr.phy.broadcast.buildSIB1DCI10(carrier,cfg);
invalid=double(tx.Bits); invalid(1)=0.25;
localReject(@()sixgr.phy.broadcast.buildSIB1DCI10(carrier,cfg,'Bits',invalid), ...
    'sixgr:phy:broadcast:InvalidSIB1DCIBits');
fprintf('SIB1_DCI_TIME_ALLOCATION_PASS 32 normal-CP table rows and malformed-input guards; not waveform qualification.\n');
ok=true;
end

function localReject(action,id)
try
    action();
catch cause
    assert(strcmp(cause.identifier,id),'Expected %s; observed %s',id,cause.identifier);
    return;
end
error('test:SIB1MissingRejection','Expected rejection %s.',id);
end
