function ok=testConnectedPDCCHBlindMonitoring()
% Actual coded control reception; receiver has no transmitted size/object.
% Unit-channel fixture, not a full-run SINR/BLER qualification.
setup6GRSimToolkit('Verbose',false);
s=sixgr.lls6g.config.loadScenarioConfig( ...
    'simulator/configs/scenarios/lls_causal_access_to_data_wiring_tdd_short_continuous_iq.yaml');
cfg=sixgr.lls6g.buildInternalConfig(s,tempname);
cfg=sixgr.phy.grid.applyRuntimeCarrierTimeline(cfg,31);
cfg.lls6g.userContext.RuntimeSlotStartTime_s=.030;
% Deliberately differ from the physical cell ID to test both data and DMRS
% scrambling. Neither receiver may accidentally inherit Toolbox defaults.
cfg.phy.pdcch.operatorControl.connected_monitoring.dmrs_scrambling_id=43;
cfg.phy.pdcch.operatorControl.connected_monitoring.cce_reg_mapping='interleaved';
cfg.phy.pdcch.operatorControl.connected_monitoring.reg_bundle_size=2;
cfg.phy.pdcch.operatorControl.connected_monitoring.interleaver_size=2;
cfg.phy.pdcch.operatorControl.connected_monitoring.shift_index=3;
for fmt=["0_1","1_1"]
    localReceive(cfg,fmt,true);
end
localReceiveBoth(cfg);

% Same-length formats must still be discriminated by received fields,
% not a transmitted format hint or the order in which contexts are tested.
same=cfg; same.phy.pdcch.operatorControl.connected_dci.tci_present=false;
same.phy.pucch.dlDataToULACK=1:4;
same.phy.pusch.timeDomainAllocations=[(0:7).' zeros(8,1) 13*ones(8,1) (1:8).'];
for fmt=["0_1","1_1"]
    c=sixgr.phy.pdcch.DCIContextFactory.fromRuntimeConfig(same,fmt);
    a=sixgr.phy.pdcch.DCISizeAlignmentEngine.resolve(c);
    assert(a.Selected.AlignedBits==39);
    localReceive(same,fmt,false);
end
bad=cfg; bad.phy.pdcch.operatorControl.connected_monitoring= ...
    rmfield(bad.phy.pdcch.operatorControl.connected_monitoring,'shift_index');
localReject(@()sixgr.phy.pdcch.ConnectedPDCCHConfiguration.build(bad, ...
    sixgr.phy.grid.makeCarrier(bad),bad.phy.pdsch.RNTI,true), ...
    'sixgr:phy:pdcch:MissingConnectedMonitoring');
ok=true;
end

function localReceive(cfg,fmt,checkNoOracle)
context=sixgr.phy.pdcch.DCIContextFactory.fromRuntimeConfig(cfg,fmt);
schema=sixgr.phy.pdcch.DCISchemaEngine.resolve(context);
fields=struct();
for def=schema.Definitions(:).'
    fields.(def.Name)=def.ValueMin;
end
fields.mcs=10; fields.ndi=1; fields.dmrs_sequence_initialization=1;
if fmt=="0_1"
    fields.precoding_information_and_number_of_layers=3;
    fields.antenna_ports=2;
end
authored=sixgr.phy.pdcch.DCIPacker.pack(fields,context);
p=sixgr.link.preparePDCCHTransmission(cfg,'DCIBits',authored.Bits,'RNTI',cfg.phy.pdsch.RNTI);
assert(string(p.Tx.PDCCH.CORESET.CCEREGMapping)=="interleaved" && ...
    p.Tx.PDCCH.CORESET.ShiftIndex==3 && string(p.Tx.PDCCH.SearchSpace.SearchSpaceType)=="ue");
start=p.RuntimeStartSample;
obs=sixgr.phy.waveform.WaveformObservationBuffer(start,start+p.NumSamples,p.SampleRateHz,size(p.TransmitSamples,2));
obs.append(sixgr.phy.waveform.WaveformChunk(p.TransmitSamples,start),p.SampleRateHz);
[rx,info]=sixgr.link.completePDCCHReception(p,obs);
assert(rx.Ok && isequal(rx.DCIBits,authored.Bits) && rx.DecodedDCI.Format==fmt);
assert(info.ReceiverConfiguredMonitoring && info.K==numel(authored.Bits) && ...
    info.NumDecodeHypothesesTried==2*info.NumCandidatesTried && rx.CausalGrantDecodeOk);
assert(info.NCellID==cfg.phy.carrier.NCellID && p.TxInfo.NCellID==cfg.phy.carrier.NCellID && ...
    info.PDCCHScramblingID==43 && p.TxInfo.PDCCHScramblingID==43);
assert(all(ismember(unique(info.CandidateResults.DCIPayloadLength),info.MonitoredPayloadSizes)));
if fmt=="0_1", assert(rx.DecodedDCI.Fields.precoding_information_and_number_of_layers_tpmi==3); end
if checkNoOracle
    % The explicitly sized codec path remains a calibration path, but must
    % still honor the configured physical scrambling identity.
    [known,knownInfo]=sixgr.phy.dl.PDCCH_Rx(p.TransmitSamples,cfg, ...
        'K',numel(authored.Bits),'PDCCH',p.Tx.PDCCH,'Carrier',p.Tx.Carrier, ...
        'RNTI',cfg.phy.pdsch.RNTI,'SampleRate_Hz',p.SampleRateHz);
    assert(known.Ok && isequal(known.DCIBits,authored.Bits) && ...
        ~knownInfo.ReceiverConfiguredMonitoring && knownInfo.PDCCHScramblingID==43);
    % Erase TX mapping/identity and corrupt every legacy size/format hint.
    % Keep actual observation samples and TX bits solely as scoring inputs.
    changed=p;
    changed.Tx=rmfield(changed.Tx,{'Carrier','PDCCH'});
    changed.TxInfo=struct();
    changed.Tx.DCIBits=int8(zeros(11,1));
    changed.ReceiverConfig.phy.pdcch.dciPayloadBits=7;
    changed.ReceiverConfig.phy.pdcch.configuredPayloadBits=9;
    changed.ReceiverConfig.phy.pdcch.dciFormat='1_0';
    changed.ReceiverConfig.phy.pdcch.dciPayloadSizesByFormat=[2 3];
    [observed,audit]=sixgr.link.completePDCCHReception(changed,obs);
    assert(observed.Ok && isequal(observed.DCIBits,rx.DCIBits) && observed.DecodedDCI.Format==fmt && ...
        ~observed.CausalGrantDecodeOk && ~observed.DCIPayloadMatch && audit.K==info.K && ...
        observed.CandidateAggregationLevel==rx.CandidateAggregationLevel && ...
        observed.CandidateIndexWithinAggregation==rx.CandidateIndexWithinAggregation);
    localReject(@()sixgr.phy.dl.PDCCH_Rx(p.TransmitSamples,cfg,'PDCCH',p.Tx.PDCCH), ...
        'sixgr:phy:pdcch:TransmitterMonitoringOverride');
    wrong=cfg; wrong.phy.pdsch.RNTI=17; wrong.phy.pusch.RNTI=17;
    wrong.phy.pdcch.rnti=17; wrong.phy.pdcch.scramblingRNTI=17;
    [noMatch,~]=sixgr.phy.dl.PDCCH_Rx(p.TransmitSamples,wrong,'SampleRate_Hz',p.SampleRateHz);
    assert(~noMatch.Ok && isempty(fieldnames(noMatch.DecodedDCI)));
    if fmt=="0_1"
        % CRC-valid but not valid for the installed data-grant profile:
        % the UL-SCH bit is zero. Do not mislabel this as a CRC failure.
        invalidBits=authored.Bits; invalidBits(end)=0;
        malformed=sixgr.link.preparePDCCHTransmission(cfg,'DCIBits',invalidBits,'RNTI',cfg.phy.pdsch.RNTI);
        [rejected,evidence]=sixgr.phy.dl.PDCCH_Rx(malformed.TransmitSamples,cfg, ...
            'SampleRate_Hz',malformed.SampleRateHz);
        assert(~rejected.Ok && evidence.ValidHypothesisCount==0 && ...
            evidence.CRCValidHypothesisCount>0 && isempty(evidence.ContextValidHypotheses));
        assert(any(evidence.CandidateResults.CRCOK & ...
            ~evidence.CandidateResults.ContextParseOK & ...
            evidence.CandidateResults.ContextParseFailure=="sixgr:phy:pdcch:field_out_of_range"));
    end
end
end

function localReject(fn,id)
try, fn(); catch ME, assert(strcmp(ME.identifier,id),'Expected %s, got %s: %s',id,ME.identifier,ME.message); return; end
error('test:MissingRejection','Expected %s.',id);
end

function localReceiveBoth(cfg)
% Two nonoverlapping same-UE commands in one actual, synchronized OFDM
% observation. This is a unit-channel component, not fading qualification.
cfg.phy.pdcch.aggregationLevel=2;
cfg.phy.pdcch.aggregationLevels=[1 2 4 8];
prepared=cell(2,1); authored=cell(2,1); occupied=zeros(0,2);
formats=["0_1","1_1"];
for k=1:2
    context=sixgr.phy.pdcch.DCIContextFactory.fromRuntimeConfig(cfg,formats(k));
    schema=sixgr.phy.pdcch.DCISchemaEngine.resolve(context);
    fields=struct();
    for def=schema.Definitions(:).', fields.(def.Name)=def.ValueMin; end
    fields.mcs=10; fields.ndi=1;
    authored{k}=sixgr.phy.pdcch.DCIPacker.pack(fields,context);
    prepared{k}=sixgr.link.preparePDCCHTransmission(cfg,'DCIBits',authored{k}.Bits, ...
        'RNTI',cfg.phy.pdsch.RNTI,'ReservedRECoordinates',occupied);
    occupied=[occupied;prepared{k}.TxInfo.AllocatedRECoordinates]; %#ok<AGROW>
end
assert(isempty(intersect(prepared{1}.TxInfo.AllocatedRECoordinates, ...
    prepared{2}.TxInfo.AllocatedRECoordinates,'rows')));
wave=prepared{1}.TransmitSamples+prepared{2}.TransmitSamples;
p=prepared{1};
obs=sixgr.phy.waveform.WaveformObservationBuffer(p.RuntimeStartSample, ...
    p.RuntimeStartSample+size(wave,1),p.SampleRateHz,size(wave,2));
obs.append(sixgr.phy.waveform.WaveformChunk(wave,p.RuntimeStartSample),p.SampleRateHz);
[scalar,allInfo]=sixgr.link.completePDCCHReception(p,obs);
assert(~scalar.Ok && scalar.AmbiguousValidHypotheses && numel(allInfo.ContextValidHypotheses)==2, ...
    'The generic scalar API must still reject arbitrary selection of two distinct valid DCIs.');
for k=1:2
    directions=["UL","DL"];
    [rx,info]=sixgr.link.selectConnectedPDCCHDirection(scalar,allInfo,directions(k));
    assert(rx.Ok && isequal(rx.DCIBits,authored{k}.Bits) && ...
        isequaln(info.ContextValidHypotheses,allInfo.ContextValidHypotheses) && ...
        info.CompositeValidHypothesisCount==2 && info.ValidHypothesisCount==1);
    assignment=sixgr.phy.pdcch.materializeConnectedDCI(rx,info,cfg);
    assert(assignment.Direction==directions(k));
    % TX bits remain scoring-only: poisoning them cannot change dispatch.
    changed=p; changed.Tx.DCIBits=int8(zeros(11,1));
    [poisoned,poisonInfo]=sixgr.link.completePDCCHReception(changed,obs);
    [independent,~]=sixgr.link.selectConnectedPDCCHDirection(poisoned,poisonInfo,directions(k));
    assert(independent.Ok && isequal(independent.DCIBits,rx.DCIBits) && ...
        ~independent.DCIPayloadMatch && ~independent.CausalGrantDecodeOk);
end
% No opposite-direction result and no same-direction conflict may be
% resolved by expected bits. These are explicit reducer-negative fixtures.
onlyUL=allInfo;
onlyUL.ContextValidHypotheses=allInfo.ContextValidHypotheses(cellfun( ...
    @(h)string(h.DecodedDCI.Direction)=="UL",allInfo.ContextValidHypotheses));
[missing,~]=sixgr.link.selectConnectedPDCCHDirection(scalar,onlyUL,"DL");
assert(~missing.Ok && isempty(fieldnames(missing.DecodedDCI)));
conflict=onlyUL; other=onlyUL.ContextValidHypotheses{1};
other.DCIBits(1)=1-other.DCIBits(1);
conflict.ContextValidHypotheses{end+1}=other;
[rejected,~]=sixgr.link.selectConnectedPDCCHDirection(scalar,conflict,"UL");
assert(~rejected.Ok && rejected.AmbiguousValidHypotheses);
fprintf('CONNECTED_MULTI_DCI_DISPATCH_PASS: both directions, no TX selector, same-direction conflict rejected.\n');
end
