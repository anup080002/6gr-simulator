function ok=testReceivedULHARQState()
% Actual received C-RNTI assignments, UE TB retention, independent gNB RX.
setup6GRSimToolkit('Verbose',false); rng(90212,'twister');
s=sixgr.lls6g.config.loadScenarioConfig( ...
    'simulator/configs/scenarios/lls_causal_access_to_data_wiring_tdd_short_continuous_iq.yaml');
installed=sixgr.lls6g.buildInternalConfig(s,tempname);
entity=sixgr.link.ReceivedULHARQState(installed);
initial=sixgr.link.resolveMCSProfile(installed.phy.pusch.mcsTable,10);
bits=[]; gnbTBS=[];
uci=sixgr.phy.ul.pusch.PUSCHUCIPayload('HARQACK',int8([1;0]));
gnbContext=struct();
for k=1:3
    slot=31+10*(k-1); mcs=10; nprb=6; rv=0; ndi=1;
    if k==2, mcs=31; nprb=8; rv=2; end
    if k==3, ndi=0; end
    cfg=sixgr.phy.grid.applyRuntimeCarrierTimeline(installed,slot);
    context=sixgr.phy.pdcch.DCIContextFactory.fromRuntimeConfig(cfg,'0_1');
    defs=sixgr.phy.pdcch.DCISchemaEngine.resolve(context).Definitions;
    f=struct(); for d=defs(:).', f.(d.Name)=d.ValueMin; end
    f.frequency_resource_assignment=cfg.phy.carrier.NSizeGrid*(nprb-1)+3;
    f.mcs=mcs; f.rv=rv; f.ndi=ndi; f.harq_process=2;
    f.antenna_ports=3; f.precoding_information_and_number_of_layers=3;
    f.dmrs_sequence_initialization=1;
    packed=sixgr.phy.pdcch.DCIPacker.pack(f,context);
    controlTx=sixgr.link.preparePDCCHTransmission(cfg,'DCIBits',packed.Bits,'RNTI',cfg.phy.pdsch.RNTI);
    [control,controlInfo]=sixgr.phy.dl.PDCCH_Rx(controlTx.TransmitSamples,cfg,'SampleRate_Hz',controlTx.SampleRateHz);
    a=sixgr.phy.pdcch.materializeConnectedDCI(control,controlInfo,cfg);
    if k==2
        assert(a.RequiresHARQHistory && isnan(a.TargetCodeRate));
        localReject(@()sixgr.phy.pdcch.connectedDataAllocation(cfg,a), ...
            'sixgr:phy:pdcch:ReceivedHARQHistoryRequired');
        allocation=sixgr.phy.pdcch.connectedDataAllocation(cfg,a,initial.TargetCodeRate);
    else
        allocation=sixgr.phy.pdcch.connectedDataAllocation(cfg,a);
    end
    if k~=2, bits=int8(randi([0 1],allocation.NominalTBSBits,1)); end
    inputBits=bits; if k==2, inputBits=[]; end
    before=entity;
    [tx,info,entity]=entity.transmit(cfg,a,inputBits,uci);
    assert(tx.UEHARQIsRetransmission==(k==2) && info.UEHARQAttempt==1+(k==2));
    assert(isequal(tx.TransportBlock,bits));
    if k==2
        assert(isnan(allocation.NominalTBSBits) && tx.RV==2 && ...
            string(tx.PUSCH.Modulation)=="64QAM" && ...
            string(tx.TransmissionAuthority)=="received_dci_and_ue_harq_buffer");
        localReject(@()before.transmit(cfg,a,bits,[]),'sixgr:link:ReceivedULHARQPayloadReplacement');
        assert(isequal(before.Processes{3}.TransportBlockBits,bits) && before.Processes{3}.Attempts==1);
        missing=sixgr.link.ReceivedULHARQState(cfg);
        localReject(@()missing.transmit(cfg,a,[],[]),'sixgr:phy:pdcch:ReceivedHARQHistoryRequired');
        invalid=f; invalid.mcs=20;
        badDCI=sixgr.phy.pdcch.DCIPacker.pack(invalid,context);
        badTX=sixgr.link.preparePDCCHTransmission(cfg,'DCIBits',badDCI.Bits,'RNTI',cfg.phy.pdsch.RNTI);
        [badRX,badInfo]=sixgr.phy.dl.PDCCH_Rx(badTX.TransmitSamples,cfg,'SampleRate_Hz',badTX.SampleRateHz);
        bad=sixgr.phy.pdcch.materializeConnectedDCI(badRX,badInfo,cfg);
        localReject(@()before.transmit(cfg,bad,[],[]),'sixgr:link:ReceivedULHARQTBSChanged');
    end
    localReject(@()entity.transmit(cfg,a,[],[]),'sixgr:link:ReceivedULHARQNoncausalAssignment');
    % gNB receives from its own scheduled resource/coding values. It never
    % sees the UE entity, allocation, TX coding layout or decoded capsule.
    tdra=context.Data.ULTimeDomainAllocations;
    tdra=tdra(tdra(:,1)==0,:);
    gnb=sixgr.phy.grid.applyRuntimeCarrierTimeline(installed,slot+tdra(4));
    profile=sixgr.link.resolveMCSProfile(gnb.phy.pusch.mcsTable,mcs);
    if k==2
        assert(string(gnb.phy.pusch.mcsTable)=="qam64_table1");
        profile.Modulation='64QAM'; % Independently declared table-1 MCS 31 order.
    end
    gnb.phy.pusch.prbSet=3:(3+nprb-1);
    gnb.phy.pusch.symbolAllocation=tdra(2:3);
    gnb.phy.pusch.mcsIndex=mcs; gnb.phy.pusch.modulation=char(profile.Modulation);
    gnb.phy.pusch.codeRate=initial.TargetCodeRate; gnb.phy.pusch.rv=rv;
    gnb.phy.pusch.TPMI=3; gnb.phy.pusch.PMI=3;
    gnb.phy.pusch.dmrs.NSCID=1; gnb.phy.pusch.dmrs.scheduledPortSet=1;
    gnb.phy.pusch.dmrs.portSet=1; gnb.phy.pusch.dmrs.numCDMGroupsWithoutData=2;
    carrier=sixgr.phy.grid.makeCarrier(gnb);
    if k~=2
        [ind,ai,pusch]=sixgr.phy.grid.allocREsPUSCH(carrier,gnb);
        account=sixgr.phy.resource.computeResourceAccounting('PUSCH',carrier,pusch, ...
            'ChannelIndices',ind,'AllocationInfo',ai,'IndexBase','1based', ...
            'TargetCodeRate',initial.TargetCodeRate,'XOverhead',gnb.phy.pusch.xOverhead);
        gnbTBS=nrTBS(pusch.Modulation,pusch.NumLayers,nprb,account.NREPerPRBForTBS, ...
            initial.TargetCodeRate,gnb.phy.pusch.xOverhead);
    end
    ownGrant=struct('Direction','UL','ServingCell',1,'UEIndex',1,'RNTI',gnb.phy.pdsch.RNTI, ...
        'MCSIndex',mcs,'TargetCodeRate',initial.TargetCodeRate,'TBSBits',gnbTBS, ...
        'Modulation',profile.Modulation,'NumLayers',1,'PRBSet',gnb.phy.pusch.prbSet, ...
        'SymbolAllocation',gnb.phy.pusch.symbolAllocation,'Slot',slot, ...
        'HARQ',struct('HarqID',2,'NDI',logical(ndi),'NDIEpoch',1+(k==3)));
    if k~=2
        ownLayout=sixgr.phy.phycode.resolveCodingLayout('Direction','UL', ...
            'TransportBlockSize',gnbTBS,'TargetCodeRate',initial.TargetCodeRate, ...
            'RV',rv,'Modulation',profile.Modulation,'NumLayers',1, ...
            'RateMatchedBitCount',account.CodedBitCountG);
        gnbContext=sixgr.harq.createTBContext(struct('Direction','UL', ...
            'Grant',ownGrant,'CodingLayout',ownLayout,'IsRetransmission',false));
    end
    uciReference=sixgr.link.resolvePUSCHUCIInitialMCS(gnb,ownGrant, ...
        struct('TransportBlockContext',gnbContext),k==2,mcs);
    nfft=nrOFDMInfo(carrier).Nfft; noise=10^(-35/10)/nfft;
    wave=tx.Waveform+sqrt(noise/2)*complex(randn(size(tx.Waveform)),randn(size(tx.Waveform)));
    rx=sixgr.phy.ul.PUSCH_Rx(wave,gnb,'TransportBlockSize',gnbTBS, ...
        'InitialIMCSPerCodeword',uciReference.MCS,'ExpectedUCIPayload',uci, ...
        'NoiseVar',noise,'NoiseVarDomain','time');
    assert(rx.Ok && isequal(rx.TransportBlock,bits) && rx.HARQACKContentMatch && ...
        isequal(rx.DecodedHARQACKBits,int8([1;0])));
    fprintf('RECEIVED_UL_HARQ_PASS attempt=%d ndi=%d rv=%d mcs=%d nprb=%d tbs=%d\n', ...
        tx.UEHARQAttempt,ndi,rv,mcs,nprb,gnbTBS);
end
assert(entity.Processes{3}.NDI==0 && entity.Processes{3}.Attempts==1);
assert(isempty(entity.Processes{1}) && isempty(entity.Processes{2}));
ok=true;
end

function localReject(fn,id)
try, fn(); catch ME, assert(strcmp(ME.identifier,id),'Expected %s, got %s: %s',id,ME.identifier,ME.message); return; end
error('test:MissingRejection','Expected %s.',id);
end
