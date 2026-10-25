function ok=testPDCCHReceivedFrequencyCorrection()
% Original coded PDCCH preparation -> actual received buffer -> core decoder.
% Installed connected DCI contexts, with a declared received-clock boundary.
% This is not an end-to-end SSB acquisition or scheduler qualification.
setup6GRSimToolkit('Verbose',false);
s=sixgr.lls6g.config.loadScenarioConfig(fullfile('simulator','configs', ...
    'scenarios','lls_tdd_n40_20mhz_64txru_4rx_cdlc100_impaired.yaml'));
data=s.toStruct();
data.impairments.cfo_estimation_method='cyclic_prefix';
data.impairments.cfo_cp_observation_policy='received_coherence_window';
data.impairments.cfo_cp_window_fraction=0.5;
data.impairments.cfo_cp_false_alarm_probability=0.001;
s=sixgr.lls6g.config.ScenarioConfig(data);
cfg=sixgr.lls6g.buildInternalConfig(s,tempname);
cfg=sixgr.phy.grid.applyRuntimeCarrierTimeline(cfg,11);
carrier=sixgr.phy.grid.makeCarrier(cfg);
cfg=sixgr.util.structSet(cfg,'lls6g.userContext.RuntimeSlotStartTime_s', ...
    10e-3/double(carrier.SlotsPerSubframe));
cfg.phy.rx.cfoCorrectionEnabled=true;
context=sixgr.phy.pdcch.DCIContextFactory.fromRuntimeConfig(cfg,'1_1');
schema=sixgr.phy.pdcch.DCISchemaEngine.resolve(context);
fields=struct();
for def=schema.Definitions(:).', fields.(def.Name)=def.ValueMin; end
fields.mcs=10; fields.ndi=1;
packed=sixgr.phy.pdcch.DCIPacker.pack(fields,context); bits=packed.Bits;
p=sixgr.link.preparePDCCHTransmission(cfg,'DCIBits',bits,'RNTI',context.Data.RNTIValue);
reference=struct('Source',"received_SSB_timing_and_decoded_BCH", ...
    'SampleRateHz',p.SampleRateHz,'AvailableAtSample',0, ...
    'DLPhaseOffsetSamples',3,'NCellID',p.Tx.Carrier.NCellID, ...
    'ImplementationFilterDelay_samples',0,'SearchGuardSamples',32);
p.ReceivedTimingAlignment=sixgr.phy.frame.pdcchReceivedClockAlignment( ...
    reference,p.Tx.Carrier,p.RuntimeStartSample,p.SampleRateHz,0);
first=p.ReceivedTimingAlignment.ReceiveStartSample;
for hz=[-2000 430 2000]
    input=p.TransmitSamples.*exp(2i*pi*hz/p.SampleRateHz*(0:p.NumSamples-1).');
    b=sixgr.phy.waveform.WaveformObservationBuffer(first, ...
        first+p.NumSamples,p.SampleRateHz,size(input,2));
    b.append(sixgr.phy.waveform.WaveformChunk(input,first),p.SampleRateHz);
    [rx,info]=sixgr.link.completePDCCHReception(p,b);
    assert(rx.Ok&&isequal(rx.DCIBits,bits)&&rx.CFOCorrectionApplied);
    assert(info.ReceiverConfiguredMonitoring && rx.AppliedTimingCorrection_samples==0 && ...
        rx.RawTimingEstimate_samples==3, ...
        'Received capture timing must not be applied a second time.');
    assert(abs(rx.EstimatedCFO_Hz-hz)<15 && ...
        isequaln(rx.ReceiveFrequency,info.ReceiveFrequency));
    assert(rx.ReceiveFrequency.CorrectionSampleCount==info.DemodulatedReceiveSamples && ...
        rx.ReceiveFrequency.CFOObservation.NumSymbolsUsed<=numel(info.ReceiveExtent.MonitoredSymbols0Based));
    modified=p;
    modified.ReceiverConfig.phy.impairments.cfoHz=12345;
    modified.ReceiverConfig.phy.impairments.timingOffsetSamples=77;
    [again,~]=sixgr.link.completePDCCHReception(modified,b);
    assert(isequaln(rx,again),'Hidden injected values changed actual receiver behavior.');
    modified.ReceiverConfig.phy.rx.cfoCorrectionEnabled=false;
    [off,~]=sixgr.link.completePDCCHReception(modified,b);
    assert(~off.CFOCorrectionApplied && off.ReceiveFrequency.Status=="disabled_by_receiver_configuration");
end
fprintf('PDCCH_RECEIVED_FREQUENCY_CORRECTION_PASS coded_cases=3 disabled_cases=3\n');
ok=true;
end
