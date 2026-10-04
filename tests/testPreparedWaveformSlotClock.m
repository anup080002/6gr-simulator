function ok=testPreparedWaveformSlotClock()
% Native reference IQ exercises preparation origins and received-clock age.
% Declared TAG is a component input, NOT a physical access qualification.
% No coded-TB, decoder or complete scenario success is claimed by this test.
setup6GRSimToolkit('Verbose',false);
s=sixgr.lls6g.config.loadScenarioConfig( ...
    'simulator/configs/validation/lls_bidirectional_disjoint_ul.yaml');
base=sixgr.lls6g.buildInternalConfig(s,tempname);
cases=[15 0;30 0;60 0;120 0;240 0;60 1];
for i=1:size(cases,1)
    cfg=base; cp='normal'; if cases(i,2), cp='extended'; end
    cfg.phy.carrier.SubcarrierSpacing=cases(i,1);
    cfg.phy.carrier.CyclicPrefix=cp; cfg.phy.carrier.NSizeGrid=24;
    cfg.phy.carrier.NSlot=1; cfg.phy.carrier.NFrame=0;
    carrier=sixgr.phy.grid.makeCarrier(cfg);
    srs=nrSRSConfig('NumSRSPorts',2,'SRSPeriod',[1 0], ...
        'SymbolStart',carrier.SymbolsPerSlot-3,'NumSRSSymbols',1);
    grid=nrResourceGrid(carrier,2); indices=nrSRSIndices(carrier,srs);
    grid(indices)=nrSRS(carrier,srs);
    [waveform,ofdm]=nrOFDMModulate(carrier,grid,'Windowing',0);
    fs=double(ofdm.SampleRate); slot0=1;
    origin=sixgr.phy.frame.slotStartSample(carrier,slot0,fs);
    cfg.lls6g.userContext.RuntimeSlotStartTime_s=origin/fs;
    cfg.lls6g.runtime.AbsoluteSlotIndex0=slot0;
    cfg.lls6g.runtimePowerContext=struct('PAApplied',false,'PAEnabled',false,'PAExecutionDeferred',false);
    tx=struct('Carrier',carrier,'Waveform',waveform,'SRSIndices',indices, ...
        'PowerContext',cfg.lls6g.runtimePowerContext);
    info=struct('OFDMInfo',ofdm); options=struct('TimingAdvanceSamples',0);
    prepared=sixgr.link.PreparedUplinkControlTransmission('SRS',cfg,options,tx,info,cfg,slot0,struct());
    assert(prepared.StartSample==origin && prepared.EndSampleExclusive==origin+size(waveform,1));
    % The data preparation owner must use the SAME physical clock. This
    % uncoded reference-grid fixture checks timestamp plumbing only.
    binding=struct('PHYGrant',struct('AntennaArchitecture',struct('NumElements',2)));
    data=sixgr.link.PreparedDataTransmission('DL',cfg,binding,tx,info,cfg,fs,0);
    assert(data.StartSample==origin && data.EndSampleExclusive==prepared.EndSampleExclusive);
    if cases(i,1)>=60 && ~cases(i,2)
        bad=cfg; bad.lls6g.userContext.RuntimeSlotStartTime_s=slot0*1e-3*15/cases(i,1);
        reject(@()sixgr.link.PreparedUplinkControlTransmission('SRS',bad,options,tx,info,bad,slot0,struct()), ...
            'sixgr:link:ULControlPreparationClockMismatch');
        reject(@()sixgr.link.PreparedDataTransmission('DL',bad,binding,tx,info,bad,fs,0), ...
            'sixgr:link:DataPreparationClockMismatch');
    end
    % A pilot received at a subframe boundary is one slot old in the next slot,
    % including the longer CP-bearing first slot at 60/120/240 kHz.
    sourceSlot=2*carrier.SlotsPerSubframe;
    carrier.NSlot=sourceSlot; cfg.phy.carrier.NSlot=sourceSlot;
    grid(:)=0; indices=nrSRSIndices(carrier,srs); grid(indices)=nrSRS(carrier,srs);
    [waveform,ofdm]=nrOFDMModulate(carrier,grid,'Windowing',0);
    sourceOrigin=sixgr.phy.frame.slotStartSample(carrier,sourceSlot,fs);
    cfg.lls6g.userContext.RuntimeSlotStartTime_s=sourceOrigin/fs;
    cfg.lls6g.runtime.AbsoluteSlotIndex0=sourceSlot;
    cfg.phy.synchronization.maxReceivedULTimingAgeSlots=1;
    common=struct('Source',"decoded_sib1",'TimingAdvanceOffsetPresent',false,'TimingAdvanceOffset',"");
    cfg.SharedULTimingContext=struct('DLReference',struct('Source',"received_SSB_timing_and_decoded_BCH", ...
        'SampleRateHz',fs,'DLPhaseOffsetSamples',0,'AvailableAtSample',0), ...
        'Offset',sixgr.phy.frame.resolveULTimingAdvanceOffset(common,'FR1'), ...
        'ReceivedRARTiming',sixgr.phy.ra.resolveRARTimingAdvance(0,cases(i,1),fs), ...
        'TimingAdvanceAvailableAtSample',0,'TimingAdvanceEffectiveAtSample',0, ...
        'TimeAlignmentExpirySampleExclusive',Inf);
    tx.Carrier=carrier; tx.Waveform=waveform; tx.SRSIndices=indices; info.OFDMInfo=ofdm;
    prepared=sixgr.link.PreparedUplinkControlTransmission('SRS',cfg,options,tx,info,cfg,sourceSlot,struct());
    first=prepared.ReceiveStartSample; last=prepared.ReceiveEndSampleExclusive;
    % Explicit identity sample-channel component with actual correlation.
    offset=prepared.StartSample-first;
    y=complex(zeros(last-first,prepared.NumReceiveAntennas));
    assert(size(waveform,2)==size(y,2)); y(offset+(1:size(waveform,1)),:)=waveform;
    observed=sixgr.phy.waveform.WaveformObservationBuffer(first,last,fs,size(y,2));
    observed.append(sixgr.phy.waveform.WaveformChunk(y,first),fs);
    estimate=nrTimingEstimate(carrier,y,grid);
    assert(estimate==offset);
    timing=struct('AppliedTimingCorrectionSamples',estimate, ...
        'DemodulatedSampleCount',size(waveform,1), ...
        'TimingSource',"received_reference_correlation_bounded_search", ...
        'OracleTimingUsed',false,'ReceiverZeroPaddingUsed',false);
    reference=sixgr.phy.sync.ReceivedULTimingReference(prepared,observed,timing);
    assertBufferedPriorULTiming(reference,cfg);
end
fprintf('PREPARED_WAVEFORM_SLOT_CLOCK_PASS native_OFDM=1 physical_access_qualified=0\n');
ok=true;
end
function reject(fn,id)
try, fn(); catch ME, assert(strcmp(ME.identifier,id),'Unexpected rejection: %s',ME.identifier); return; end
error('test:MissingRejection','Expected %s.',id);
end
