function ok=testHARQPUSCHMultiplexingProcessingTime()
% Independent arithmetic checks, actual NR resource maps; no PHY pass claim.
setup6GRSimToolkit('Verbose',false);
c=nrCarrierConfig('NSizeGrid',25,'SubcarrierSpacing',15);
dl=nrPDSCHConfig('PRBSet',6:24,'SymbolAllocation',[2 8],'MappingType','A');
dl.DMRS.DMRSAdditionalPosition=0;
ul=nrPUSCHConfig('PRBSet',6:24,'SymbolAllocation',[0 13],'MappingType','A');
before=rng;
b=sixgr.phy.frame.harqPUSCHMultiplexingProcessingTime(c,dl,c,ul,0,0);
tick=int64((2048+144)*64);
assert(b.N1Symbols==8 && b.D11Symbols==0 && b.PDSCHTicks==9*tick);
assert(b.N2Symbols==10 && b.D21Symbols==1 && b.PDCCHTicks==12*tick);
assert(isequal(before,rng),'Timing arithmetic must not consume receiver randomness.');
% The failed mixed-slot pair leaves roughly four symbols, not the nine
% nominal-symbol duration required even by the pos0 multiplexing budget.
assert(4*tick<b.PDSCHTicks);
dl.DMRS.DMRSAdditionalPosition=2;
b=sixgr.phy.frame.harqPUSCHMultiplexingProcessingTime(c,dl,c,ul,[0 1],0);
assert(b.N1Symbols==13 && b.PDSCHTicks==14*tick);
dl.DMRS.DMRSAdditionalPosition=0;
% Mapping-A shortened allocations and mapping-B short-block d1,1 terms.
dl.SymbolAllocation=[2 4];
b=sixgr.phy.frame.harqPUSCHMultiplexingProcessingTime(c,dl,c,ul,0,0);
assert(b.D11Symbols==2 && b.PDSCHTicks==11*tick);
dl.MappingType='B';
for length=[2 3 4 6 7 8]
    dl.SymbolAllocation=[2 length];
    for overlap=[0 1 2]
        expected=0;
        if length==2, expected=3+overlap;
        elseif length==3, expected=3+min(overlap,1);
        elseif length<=6, expected=7-length; end
        b=sixgr.phy.frame.harqPUSCHMultiplexingProcessingTime(c,dl,c,ul,0,overlap);
        assert(b.D11Symbols==expected && b.PDSCHTicks==(8+expected+1)*tick);
    end
end
% A DM-RS-only first UL symbol removes d2,1, not the +1 mux term.
ul.SymbolAllocation=[2 8]; ul.DMRS.NumCDMGroupsWithoutData=2;
b=sixgr.phy.frame.harqPUSCHMultiplexingProcessingTime(c,dl,c,ul,[2 1 0],0);
assert(b.Mu==0 && b.D21Symbols==0 && b.PDCCHTicks==11*tick);
% SCS selection includes actual data carriers as well as supplied control.
c30=nrCarrierConfig('NSizeGrid',25,'SubcarrierSpacing',30);
b=sixgr.phy.frame.harqPUSCHMultiplexingProcessingTime(c30,dl,c30,ul,[2 1],0);
assert(b.Mu==1 && b.N1Symbols==10 && b.PDSCHTicks==11*tick/2 && ...
    b.N2Symbols==12 && b.PDCCHTicks==13*tick/2);
ok=true; disp('HARQ_PUSCH_MULTIPLEXING_PROCESSING_TIME_PASS');
end
