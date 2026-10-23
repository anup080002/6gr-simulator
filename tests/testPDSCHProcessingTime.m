function ok=testPDSCHProcessingTime()
% Independent 38.214 5.3 arithmetic and native DM-RS coordinates.
setup6GRSimToolkit('Verbose',false);
c=nrCarrierConfig('NSizeGrid',25,'SubcarrierSpacing',15);
p=nrPDSCHConfig('PRBSet',0:24,'SymbolAllocation',[0 14],'MappingType','A');
tick=int64((2048+144)*64);
mus=[0 1 2 3 5 6]; pos0=[8 10 17 20 80 160]; other=[13 13 20 24 96 192];
for k=1:numel(mus)
    for additional=0:3
        p.DMRS.DMRSAdditionalPosition=additional;
        b=sixgr.phy.frame.pdschProcessingTime(c,p,mus(k),2);
        expected=other(k); if additional==0, expected=pos0(k); end
        assert(b.N1Symbols==expected && b.D11Symbols==0 && ...
            b.Ticks==int64(expected*(2048+144)*64/2^mus(k)));
    end
end
p.DMRS.DMRSAdditionalPosition=2;
b=sixgr.phy.frame.pdschProcessingTime(c,p,[2 0 1],0);
assert(b.Mu==0 && b.Ticks==13*tick);
p.DMRS.DMRSAdditionalPosition=0; p.SymbolAllocation=[2 4];
b=sixgr.phy.frame.pdschProcessingTime(c,p,0,0);
assert(b.D11Symbols==2 && b.Ticks==10*tick);
p.MappingType='B';
for length=[2 3 4 6 7 8]
    p.SymbolAllocation=[2 length];
    for overlap=0:2
        expected=0;
        if length==2, expected=3+overlap;
        elseif length==3, expected=3+min(overlap,1);
        elseif length<=6, expected=7-length; end
        b=sixgr.phy.frame.pdschProcessingTime(c,p,0,overlap);
        assert(b.D11Symbols==expected && b.Ticks==(8+expected)*tick);
    end
end
% Mapping-B's additional pilot at absolute symbol 12 is NOT Table 7.4.1.1.2-3 l1=12.
p.SymbolAllocation=[8 6]; p.DMRS.DMRSAdditionalPosition=1;
b=sixgr.phy.frame.pdschProcessingTime(c,p,0,0);
assert(any(b.PDSCHDMRSSymbols==12) && ~b.AdditionalDMRSStartsAt12 && b.N1Symbols==13);
% Likewise the second member of a double-symbol DM-RS pair is not l1.
p.MappingType='A'; p.SymbolAllocation=[0 14]; p.DMRS.DMRSLength=2;
b=sixgr.phy.frame.pdschProcessingTime(c,p,0,0);
assert(~b.AdditionalDMRSStartsAt12 && b.N1Symbols==13);
ok=true; disp('PDSCH_PROCESSING_TIME_PASS');
end
