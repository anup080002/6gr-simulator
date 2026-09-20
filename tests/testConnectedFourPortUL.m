function ok=testConnectedFourPortUL()
% Actual blind PDCCH -> received UL rank/ports -> coded PUSCH.
% Bounded native-modulation component test; no SRS capture or coordinator claim.
setup6GRSimToolkit('Verbose',false); old=rng; cleanup=onCleanup(@()rng(old)); %#ok<NASGU>
rng(3821218,'twister');
s=sixgr.lls6g.config.loadScenarioConfig( ...
    'simulator/configs/scenarios/lls_four_port_connected_ul_fixture.yaml');
base=sixgr.lls6g.buildInternalConfig(s,tempname);
base=sixgr.phy.grid.applyRuntimeCarrierTimeline(base,31);
assert(base.phy.pusch.NumAntennaPorts==4 && base.phy.srs.nPorts==4 && ...
    ~base.phy.pusch.enablePTRS && base.phy.pdcch.operatorControl.ul_precoding.max_rank==4 && ...
    base.phy.pusch.maxLayers==4 && base.phy.pusch.maxRankDefault==4 && ...
    base.phy.pusch.numLayers==1);
context=sixgr.phy.pdcch.DCIContextFactory.fromRuntimeConfig(base,'0_1');
rankPolicy=sixgr.mimo.resolveRankExecutionPolicy(base,'UL',4);
assert(context.Data.LayerCapability==4 && rankPolicy.MaxSupportedLayers==4 && ...
    rankPolicy.EffectiveRank==4, 'Bootstrap rank one must not cap a future UL rank-four decision.');
for rank=[2 4]
    schema=sixgr.phy.pdcch.DCISchemaEngine.resolve(context); fields=struct();
    for def=schema.Definitions(:).', fields.(def.Name)=def.ValueMin; end
    fields.frequency_resource_assignment=25*5+3;
    fields.mcs=4; fields.ndi=1; fields.dmrs_sequence_initialization=1;
    fields.precoding_information_and_number_of_layers= ...
        sixgr.phy.pdcch.ULPrecodingField.encode(context.Data,rank,0);
    fields.antenna_ports=sixgr.phy.pdcch.ULReferenceSignaling.encodeAntenna( ...
        context.Data,rank,0:rank-1,2,1);
    dci=sixgr.phy.pdcch.DCIPacker.pack(fields,context);
    p=sixgr.link.preparePDCCHTransmission(base,'DCIBits',dci.Bits,'RNTI',base.phy.pusch.RNTI);
    [control,info]=sixgr.phy.dl.PDCCH_Rx(p.TransmitSamples,base,'SampleRate_Hz',p.SampleRateHz);
    received=sixgr.phy.pdcch.materializeConnectedDCI(control,info,base);
    assert(received.NumLayers==rank && received.TPMI==0 && isequal(received.DMRSPortSet,0:rank-1));
    % The same CRC-accepted bits must not be reinterpreted after either
    % member of the installed paired MCS-table context has changed.
    for direction={'pdsch','pusch'}
        stale=base; name=direction{1};
        replacement="qam256_table2";
        if string(stale.phy.(name).mcsTable)==replacement, replacement="qam64_table1"; end
        stale.phy.(name).mcsTable=char(replacement);
        localRejectStale(@()sixgr.phy.pdcch.materializeConnectedDCI(control,info,stale));
        localRejectStale(@()sixgr.phy.pdcch.connectedDataAllocation(stale,received));
    end
    allocation=sixgr.phy.pdcch.connectedDataAllocation(base,received);
    bits=int8(randi([0 1],allocation.NominalTBSBits,1));
    tx=sixgr.link.transmitReceivedPUSCH(base,received,bits,[]);
    assert(size(tx.Waveform,2)==4 && tx.PrecodeInfo.AuthoritativeDCIDecisionUsed);
    % gNB expectation is independently scheduled; no TX object/received UE
    % assignment/TBS/coding plan is passed to its data decoder.
    rows=context.Data.ULTimeDomainAllocations;
    row=rows(rows(:,1)==fields.time_resource_assignment,:);
    gnb=sixgr.phy.grid.applyRuntimeCarrierTimeline(base,31+row(4));
    profile=sixgr.link.resolveMCSProfile(gnb.phy.pusch.mcsTable,fields.mcs);
    gnb.phy.pusch.prbSet=3:8; gnb.phy.pusch.symbolAllocation=row(2:3);
    gnb.phy.pusch.mcsIndex=fields.mcs; gnb.phy.pusch.modulation=char(profile.Modulation);
    gnb.phy.pusch.codeRate=profile.TargetCodeRate;
    gnb.phy.pusch.numLayers=rank; gnb.phy.pusch.nLayers=rank;
    gnb.phy.pusch.TPMI=0; gnb.phy.pusch.PMI=0; gnb.phy.pusch.rv=0;
    gnb.phy.pusch.dmrs.NSCID=1; gnb.phy.pusch.dmrs.scheduledPortSet=0:rank-1;
    gnb.phy.pusch.dmrs.portSet=0:rank-1; gnb.phy.pusch.dmrs.numCDMGroupsWithoutData=2;
    noise=1e-4/nrOFDMInfo(allocation.Carrier).Nfft;
    wave=tx.Waveform+sqrt(noise/2)*complex(randn(size(tx.Waveform)),randn(size(tx.Waveform)));
    rx=sixgr.phy.ul.PUSCH_Rx(wave,gnb,'NoiseVar',noise,'NoiseVarDomain','time');
    assert(rx.Ok && isequal(rx.TransportBlock,bits));
    fprintf('CONNECTED_FOUR_PORT_UL_PASS rank=%d DCIbits=%d TBS=%d actual_ports=%d\n', ...
        rank,numel(dci.Bits),numel(bits),size(tx.Waveform,2));
end
bad=base; bad.phy.pusch.enablePTRS=true;
try
    sixgr.phy.pdcch.DCIContextFactory.fromRuntimeConfig(bad,'0_1');
    error('test:MissingRejection','Multilayer PTRS was silently accepted.');
catch ME
    assert(string(ME.identifier)=="sixgr:phy:pdcch:ULPrecodingContextMismatch");
end
ok=true;
end

function localRejectStale(fn)
try
    fn();
catch ME
    assert(strcmp(ME.identifier,'sixgr:phy:pdcch:stale_bwp_context'), ...
        'Expected stale control context, got %s: %s',ME.identifier,ME.message);
    return;
end
error('test:MissingRejection','Changed installed MCS table reinterpreted retained DCI.');
end
