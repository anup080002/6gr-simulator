function ok=testResearch1024PUSCHUCI()
% Real LDPC/CRC + Qm=10 symbols + UCI; not shared scheduler acceptance.
setup6GRSimToolkit('Verbose',false,'RunToolboxChecks',false);
prior=rng; cleanup=onCleanup(@()rng(prior)); %#ok<NASGU>
rng(20260919,'twister');
policy=sixgr.lls6g.config.readConfigFile('simulator/configs/coding/research_pusch_uci.yaml');
% All one/two-bit words, fractional final mother-code period, weak/zero LLR.
for n=1:2
 for word=0:2^n-1
    bits=int8(bitget(word,(1:n).'));
    encoded=sixgr.phy.research.encodePUSCHUCI(bits,200,'1024QAM');
    reference=encoded; reference(reference==-1)=1;
    repeat=find(reference==-2); reference(repeat)=reference(repeat-1);
    llr=10*(1-2*double(reference));
    [received,e]=sixgr.phy.ul.pusch.decodeUCIWithEvidence(llr,n,"1024QAM");
    assert(isequal(received,bits) && e.DecodeUsable && ~e.CRCApplicable && ...
        ~e.ShortConfidence.SignalPresenceQualified);
    [~,e]=sixgr.phy.ul.pusch.decodeUCIWithEvidence(zeros(size(llr)),n,"1024QAM");
    assert(~e.DecodeUsable);
    llr(encoded==-1)=Inf;
    [received,e]=sixgr.phy.ul.pusch.decodeUCIWithEvidence(llr,n,"1024QAM");
    assert(isequal(received,bits) && e.DecodeUsable);
 end
end
profiles=[25 15;264 120]; cases=0;
for profile=1:2
 for layers=[2 4]
    p=nrPUSCHConfig('NSizeBWP',profiles(profile,1),'NStartBWP',0, ...
        'PRBSet',0:profiles(profile,1)-1,'NumLayers',layers, ...
        'TransmissionScheme','nonCodebook','SymbolAllocation',[0 14]);
    p.DMRS.DMRSPortSet=0:layers-1; p.DMRS.NumCDMGroupsWithoutData=2;
    carrier=nrCarrierConfig('NSizeGrid',profiles(profile,1),'SubcarrierSpacing',profiles(profile,2));
    [~,resource]=nrPUSCHIndices(carrier,p);
    rate=.5; tbs=nrTBS('1024QAM',layers,profiles(profile,1),resource.NREPerPRB,rate);
    counts=[2 7 20];
    txPlan=sixgr.phy.research.PUSCHUCIResourceAdapter.resolve(policy,p,rate,tbs,counts,'1024QAM');
    % Receiver reconstructs independently from installed lengths, not TX map.
    rxPlan=sixgr.phy.research.PUSCHUCIResourceAdapter.resolve(policy,p,rate,tbs,counts,'1024QAM');
    layout=sixgr.phy.phycode.resolveCodingLayout('Direction','UL', ...
        'TransportBlockSize',tbs,'TargetCodeRate',rate,'RV',0, ...
        'Modulation','1024QAM','NumLayers',layers,'RateMatchedBitCount',txPlan.GULSCH);
    tb=int8(randi([0 1],tbs,1));
    crc=sixgr.phy.tb.attachCRC(tb,layout.TBCRCType);
    cb=sixgr.phy.tb.segmentLDPC(crc,double(layout.BaseGraph));
    ldpc=sixgr.phy.phycode.ldpcEncode(cb,double(layout.BaseGraph));
    data=sixgr.phy.phycode.rateMatchLDPC(ldpc,txPlan.GULSCH,0,'1024QAM',layers);
    messages={int8([1;0]),int8(randi([0 1],7,1)),int8(randi([0 1],20,1))};
    budgets=[txPlan.GACK txPlan.GCSI1 txPlan.GCSI2]; coded=cell(1,3);
    for k=1:3, coded{k}=sixgr.phy.research.encodePUSCHUCI(messages{k},budgets(k),'1024QAM'); end
    cw=sixgr.phy.research.PUSCHUCIResourceAdapter.multiplex(txPlan,data,coded{:});
    scrambled=nrPUSCHScramble(cw,17,91);
    symbols=nrSymbolModulate(scrambled,'1024QAM');
    variance=1e-4;
    actual=symbols+sqrt(variance/2)*(randn(size(symbols))+1j*randn(size(symbols)));
    llr=nrSymbolDemodulate(actual,'1024QAM',variance);
    [x,y]=sixgr.phy.research.PUSCHUCIResourceAdapter.placeholderIndices(rxPlan);
    llr=nrPUSCHDescramble(llr,17,91,x,y);
    [dataLLR,a,c1,c2]=sixgr.phy.research.PUSCHUCIResourceAdapter.demultiplex(rxPlan,llr);
    control={a,c1,c2};
    for k=1:3
        [received,e]=sixgr.phy.ul.pusch.decodeUCIWithEvidence(control{k},counts(k),"1024QAM");
        assert(isequal(received,messages{k}) && e.DecodeUsable);
    end
    recovered=sixgr.phy.phycode.rateRecoverLDPC(dataLLR,tbs,rate,0,'1024QAM',layers, ...
        double(layout.NumCodeBlocks),[],'CodingLayout',layout);
    decoded=sixgr.phy.phycode.ldpcDecode(recovered,double(layout.BaseGraph),12,'Normalized min-sum');
    [withCRC,cbError]=sixgr.phy.tb.desegmentLDPC(decoded,double(layout.BaseGraph), ...
        double(layout.TransportBlockLengthWithCRC));
    [decodedTB,pass]=sixgr.phy.tb.checkCRC(withCRC,layout.TBCRCType);
    assert(pass && ~any(cbError(:)) && isequal(int8(decodedTB),tb));
    cases=cases+1;
    fprintf('RESEARCH_1024_PUSCH_UCI_CODED_PASS PRB=%d layers=%d TB=%d G=%d GULSCH=%d control=2,7,20\n', ...
        profiles(profile,1),layers,tbs,rxPlan.G,rxPlan.GULSCH);
 end
end
ok=true; fprintf('RESEARCH_1024_PUSCH_UCI_PASS coded_cases=%d shared_clock_integration=0\n',cases);
end
