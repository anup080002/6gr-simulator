function ok=testConnectedResearchPUSCH(widths)
% Blind PDCCH -> UE HARQ buffer -> experimental waveform -> independent gNB.
% Bounded allocations, not the coupled scheduler/access/feedback calendar.
setup6GRSimToolkit('Verbose',false); old=rng; cleanup=onCleanup(@()rng(old)); %#ok<NASGU>
rng(3821220,'twister'); if nargin<1, widths=[25 264]; end
s=sixgr.lls6g.config.loadScenarioConfig( ...
    'simulator/configs/scenarios/lls_four_port_connected_research_ul_fixture.yaml');
base=sixgr.lls6g.buildInternalConfig(s,tempname);
assert(~startsWith(string(base.phy.pdsch.mcsTable),'experimental_'));
definition=base.phy.pusch.experimentalMCSTable;
for row=definition.Rows.'
    p=sixgr.phy.pdcch.resolveConnectedMCS(base.phy.pusch,row(1));
    assert(p.Valid && ~p.StandardNR && p.Qm==row(2) && p.TargetCodeRate==row(3));
end
for index=setdiff(0:31,definition.Rows(:,1))
    localReject(@()sixgr.phy.pdcch.resolveConnectedMCS(base.phy.pusch,index), ...
        'sixgr:phy:pdcch:field_out_of_range');
end
bad=base; bad.phy.pusch.experimentalMCSTable.Rows(5,3)=.9;
localReject(@()sixgr.phy.pdcch.DCIContextFactory.fromRuntimeConfig(bad,'0_1'), ...
    'sixgr:research:MCSTableContextMismatch');
for width=widths
 for rank=[2 4]
    cfg=base; scs=15; if width==264, scs=120; end
    cfg.phy.carrier.NSizeGrid=width; cfg.phy.carrier.SubcarrierSpacing=scs;
    cfg.phy.carrier.SubcarrierSpacing_kHz=scs;
    for side={'dl','ul'}
        cfg.phy.bwp.(side{1}).NSizeBWP=width;
    end
    cfg.phy.bwp.configuredDL(1).NSizeBWP=width;
    cfg.phy.bwp.configuredUL(1).NSizeBWP=width;
    entity=sixgr.link.ReceivedULHARQState(cfg);
    bits=[]; priorSoft=[]; priorLayout=struct(); owner=[];
    for attempt=1:2
        slot=31+10*(attempt-1); rv=2*(attempt-1);
        controlCfg=sixgr.phy.grid.applyRuntimeCarrierTimeline(cfg,slot);
        context=sixgr.phy.pdcch.DCIContextFactory.fromRuntimeConfig(controlCfg,'0_1');
        schema=sixgr.phy.pdcch.DCISchemaEngine.resolve(context); fields=struct();
        for def=schema.Definitions(:).', fields.(def.Name)=def.ValueMin; end
        fields.frequency_resource_assignment=sixgr.phy.pdcch.rivEncode(0,width,width);
        fields.mcs=4; fields.ndi=1; fields.rv=rv; fields.dmrs_sequence_initialization=1;
        fields.precoding_information_and_number_of_layers= ...
            sixgr.phy.pdcch.ULPrecodingField.encode(context.Data,rank,0);
        fields.antenna_ports=sixgr.phy.pdcch.ULReferenceSignaling.encodeAntenna( ...
            context.Data,rank,0:rank-1,2,1);
        packed=sixgr.phy.pdcch.DCIPacker.pack(fields,context);
        p=sixgr.link.preparePDCCHTransmission(controlCfg,'DCIBits',packed.Bits,'RNTI',cfg.phy.pusch.RNTI);
        [control,info]=sixgr.phy.dl.PDCCH_Rx(p.TransmitSamples,controlCfg,'SampleRate_Hz',p.SampleRateHz);
        a=sixgr.phy.pdcch.materializeConnectedDCI(control,info,controlCfg);
        assert(~a.StandardNR && a.Modulation=="1024QAM" && a.TargetCodeRate==.5 && ...
            control.DecodedDCI.StandardProfile=="experimental_mcs_with_nr_dci_layout");
        allocation=sixgr.phy.pdcch.connectedDataAllocation(controlCfg,a);
        fresh=[];
        if attempt==1, bits=int8(randi([0 1],allocation.NominalTBSBits,1)); fresh=bits; end
        payload=sixgr.phy.ul.pusch.PUSCHUCIPayload('HARQACK',int8([1;0;1;0;1]));
        [tx,txInfo,entity]=entity.transmit(controlCfg,a,fresh,payload);
        assert(tx.UEHARQAttempt==attempt && tx.UEHARQIsRetransmission==(attempt==2) && ...
            tx.Modulation=="1024QAM" && ~tx.StandardNR && size(tx.Waveform,2)==4 && ...
            tx.TransportBlockSize==numel(bits) && tx.G==allocation.RateMatchedCapacityBits);
        % Rebuild the gNB allocation solely from its schedule and installed
        % policy. Do NOT copy allocation.Config, a, tx.PUSCH, TBS or UCI.
        rows=context.Data.ULTimeDomainAllocations;
        row=rows(rows(:,1)==fields.time_resource_assignment,:);
        gnb=sixgr.phy.grid.applyRuntimeCarrierTimeline(cfg,slot+row(4));
        gnb.phy.pusch.prbSet=0:width-1; gnb.phy.pusch.symbolAllocation=row(2:3);
        gnb.phy.pusch.mcsIndex=4; gnb.phy.pusch.modulation='1024QAM'; gnb.phy.pusch.codeRate=.5;
        gnb.phy.pusch.numLayers=rank; gnb.phy.pusch.nLayers=rank;
        gnb.phy.pusch.TPMI=0; gnb.phy.pusch.PMI=0; gnb.phy.pusch.rv=rv;
        gnb.phy.pusch.dmrs.NSCID=1; gnb.phy.pusch.dmrs.scheduledPortSet=0:rank-1;
        gnb.phy.pusch.dmrs.portSet=0:rank-1; gnb.phy.pusch.dmrs.numCDMGroupsWithoutData=2;
        carrier=sixgr.phy.grid.makeCarrier(gnb);
        expected=sixgr.phy.research.configuredPUSCHTransport(gnb,carrier);
        [~,indInfo]=nrPUSCHIndices(carrier,expected.Geometry);
        tbs=nrTBS('1024QAM',rank,width,indInfo.NREPerPRB,.5,gnb.phy.pusch.xOverhead);
        receive=sixgr.phy.ul.pusch.PUSCHUCIReceiveContext(struct( ...
            'ObservationID',"scheduled_control_fixture",'ConfigurationEpoch',1, ...
            'AssignmentDigest',"independent_gnb_schedule",'HARQMappingDigest',"five_scheduled_DL_TBs", ...
            'HARQACKBitCount',5,'ConfiguredGrantUCIBitCount',0, ...
            'CSIReportConfigID',"",'CSIConfigurationEpoch',NaN));
        % Production physical owner: fixed configured noise once/RX, retained
        % clock and independent noise samples through the inter-attempt gap.
        first=sixgr.phy.frame.slotStartSample(carrier,slot+row(4)-1,tx.OFDM.SampleRate);
        if attempt==1
            state=sixgr.channel.ChannelFactory.createRuntimeChannelState(gnb,'UL', ...
                'UEIndex',1,'ServingCell',1,'AbsoluteSampleIndex',first);
            state.TargetUEIndex=1; state.TargetServingCell=1;
            state=sixgr.channel.ChannelFactory.materializeRuntimeChannelState( ...
                state,gnb,tx.Waveform,txInfo,'NumTxAnt',4,'NumRxAnt',4);
            owner=sixgr.truth.SharedWaveformPhysicalRuntime(tx.OFDM.SampleRate,first,1);
            owner.addTransmitter('ue',gnb,'UL',4,false);
            owner.addReceiver('gnb',gnb,'UL',4,false);
            owner.addLink('identity','ue','gnb',state,gnb);
        end
        if owner.NextSampleIndex<first
            gap=complex(zeros(first-owner.NextSampleIndex,4));
            input=struct('ID',"ue",'Chunk',sixgr.phy.waveform.WaveformChunk(gap,owner.NextSampleIndex));
            owner.process(input,owner.NextSampleIndex,first,[]);
        end
        input=struct('ID',"ue",'Chunk',sixgr.phy.waveform.WaveformChunk(tx.Waveform,first));
        [outputs,physical]=owner.process(input,first,first+size(tx.Waveform,1),[]);
        capture=outputs(string({outputs.ID})=="gnb:post_rf");
        assert(isscalar(capture) && physical.RX.Replay.GridNoiseVariance==.00025);
        dispatcher=sixgr.phy.waveform.WaveformReceiveDispatcher(tx.OFDM.SampleRate,4,first);
        dispatcher.register('pusch',first,capture.Chunk.EndSample+1);
        complete=dispatcher.dispatch(capture.Chunk,tx.OFDM.SampleRate);
        segment=struct('StartSample',first,'EndSampleExclusive',capture.Chunk.EndSample+1, ...
            'Execution',physical);
        [observation,gain]=sixgr.phy.rx.compensateReceivedAGC(complete.Observation,{segment},'gnb');
        wave=observation.readComplete();
        assert(~gain.ClippingReconstructed && ~gain.QuantizationRemoved);
        fprintf('CONNECTED_SHARED_RECEIVE_PLANE applied_AGC_compensation=%d gain_dB=[%g,%g] fixed_grid_noise=%g\n', ...
            gain.Applied,gain.AppliedGainMin_dB,gain.AppliedGainMax_dB,physical.RX.Replay.GridNoiseVariance);
        rx=sixgr.phy.ul.PUSCH_Rx(wave,gnb,'UCIReceiveContext',receive, ...
            'TransportBlockSize',tbs,'TargetCodeRate',.5,'RV',rv,'InitialIMCSPerCodeword',4, ...
            'HARQSoftBufferLLR',priorSoft,'HARQSoftBufferLayout',priorLayout);
        fprintf('CONNECTED_RESEARCH_RX_DIAGNOSTIC rank=%d attempt=%d ok=%d crc_error=%d tb_match=%d ACK=%s nvar=%g timing=%g soft_combining=%d\n', ...
            rank,attempt,rx.Ok,rx.CRCError,isequal(rx.TransportBlock,bits), ...
            mat2str(rx.DecodedHARQACKBits.'),rx.NoiseVar,rx.TimingOffset,rx.HARQSoftCombiningApplied);
        assert(rx.Ok && ~rx.CRCError && isequal(rx.TransportBlock,bits) && ...
            isequal(rx.DecodedHARQACKBits,payload.HARQACK) && ~rx.UCIReferenceScoringAvailable && ...
            ~rx.StandardNR && rx.Modulation=="1024QAM");
        assert(rx.HARQSoftCombiningApplied==(attempt==2));
        priorSoft=rx.HARQSoftBuffer; priorLayout=rx.CodingLayout;
        fprintf('CONNECTED_RESEARCH_PUSCH_PASS PRB=%d SCS=%d rank=%d attempt=%d RV=%d TBS=%d Qm=10 ACK=5 CRC=1 rate=0.5 reference_SNR=30\n', ...
            width,scs,rank,attempt,rv,tbs);
    end
 end
end
ok=true;
end

function localReject(fn,id)
try, fn(); catch ME, assert(strcmp(ME.identifier,id),'Expected %s, got %s: %s',id,ME.identifier,ME.message); return; end
error('test:MissingRejection','Expected %s.',id);
end
