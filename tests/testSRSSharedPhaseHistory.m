function [ok,receptions]=testSRSSharedPhaseHistory()
% Two physically generated SRS occasions through the production completion
% helper. Declared aligned identity link, not acquired access/RF qualification.
setup6GRSimToolkit('Verbose',false);
source=sixgr.lls6g.config.loadScenarioConfig( ...
    'simulator/configs/scenarios/lls_tdd_5mhz_four_port_shared_awgn_12db.yaml');
folder=fullfile(pwd,'results','lls','srs_shared_phase',char(datetime('now','Format','yyyyMMdd_HHmmss_SSS')));
mkdir(folder); base=sixgr.lls6g.buildInternalConfig(source,folder);
base.phy.srs.runtimeChannelEstimator='nr_channel_estimate';
multi=struct('Enabled',true,'NumUsers',1,'RNTIStart',1,'ExecutionModel','slot_coupled_truth');
state=sixgr.truth.CoupledTruthRuntime.initialize(base,folder,multi,struct(),40);
state.SharedWaveformStream=struct('Physical',struct('ConfigurationEpoch','declared_SRS_component_epoch'));
rows=table();
receptions=cell(0,1);
for slot=[5 10]
    cfg=sixgr.phy.grid.applyRuntimeCarrierTimeline(base,slot,1);
    args={'SlotIndex',slot,'TrialIndex',1,'SNR_dB',40,'TimingAdvanceSamples',0};
    pending=sixgr.link.runSRSChannelEstimation(cfg,args{:},'PrepareOnly',true);
    p=pending.PreparedTransmission; fs=p.SampleRateHz;
    array=sixgr.rf.AntennaArrayFactory.build(p.ReceiverConfig,'ue','signal','srs','numPorts',4);
    x=p.Tx.Waveform*array.PortToElementMatrix.';
    n=p.ReceiveStartSample+(0:size(x,1)+63).';
    desired=[x;complex(zeros(64,4))].*exp(2i*pi*75*n/fs);
    energy=sixgr.phy.waveform.measureReceivedOccupiedREEnergy(p.Tx.Carrier,x, ...
        p.Tx.SRSIndices,'SignalFamily','SRS');
    [received,~]=sixgr.phy.waveform.addOccupiedREAWGN(desired,p.Tx.Carrier,40, ...
        'SignalEnergyPerOccupiedRE',energy,'Seed',174510+slot);
    endpoint=struct('InjectedTimingOffset_samples',0,'CFOApplied',false, ...
        'InjectedCFO_Hz',0,'RFEndpoint',"rx",'RFStageOrder',"rx_timing>rx_lo_cfo");
    execution=struct('ReceiverID',"declared_gnb",'TransmitterID',"declared_ue", ...
        'ReceiveStreamExecutionSegments',{{struct('StartSample',p.ReceiveStartSample, ...
        'EndSampleExclusive',p.ReceiveStartSample+size(received,1), ...
        'Execution',struct('RX',struct('ID',"declared_gnb",'Replay',endpoint)))}});
    evidence=struct('Source',"actual_executed_link_contribution", ...
        'ReceiverID',execution.ReceiverID,'TransmitterID',execution.TransmitterID, ...
        'ReceiverEstimatorInput',false,'AdditionalChannelExecutions',0, ...
        'AdditionalRFExecutions',0,'ReceiverClockExecution',execution);
    replay=execution; replay.SampleNoiseVariance=NaN;
    replay.SampleNoiseVarianceDomain="unavailable_requires_received_reference_estimation";
    replay.NoiseOperatingMode="standalone_awgn_snr_argument"; replay.ApproximationMode="none";
    input=struct('Prepared',p,'Observation',buffer(received,p.ReceiveStartSample,fs), ...
        'PhysicalMeasurementObservation',buffer(received,p.ReceiveStartSample,fs), ...
        'TransmitterObservation',buffer(x,p.StartSample,fs),'Replay',replay, ...
        'DesiredReferenceObservation',buffer(desired,p.ReceiveStartSample,fs), ...
        'DesiredReferenceEvidence',evidence,'ChannelState',struct('Source',"declared_identity_link"));
    item=struct('UE',1,'Context',struct('Config',cfg,'Arguments',{args},'ServingCell',1));
    before=state;
    [state,out]=sixgr.truth.receiveSharedSRSMeasurement(state,item,input);
    receptions{end+1,1}=struct('Config',cfg,'Output',out); %#ok<AGROW>
    assert(out.ChannelEstimateAvailable && isnan(out.EstimatedDopplerHz) && isnan(out.InjectedDoppler_Hz));
    row=struct2table(sixgr.link.srsPilotPhaseEvidence(out)); row.Slot=slot;
    if slot==5
        assert(isnan(out.PilotCommonPhaseRate_Hz) && out.PilotPhasePairCount==0);
    else
        assert(abs(out.PilotCommonPhaseRate_Hz-75)<1 && out.PilotPhasePairCount==1 && ...
            out.PilotPhaseObservationScope=="between_received_occasions");
        assert(abs(out.PilotPhaseObservationSeparation_s-.005)<2/fs);
        % Reference-scoring metadata cannot drive the measured rate.
        input.DesiredReferenceObservation=buffer(desired*1i,p.ReceiveStartSample,fs);
        [~,poisoned]=sixgr.truth.receiveSharedSRSMeasurement(before,item,input);
        assert(poisoned.PilotCommonPhaseRate_Hz==out.PilotCommonPhaseRate_Hz);
    end
    state.CurrentSlot=slot+1;
    state=sixgr.truth.CoupledTruthRuntime.publishReferenceSignalMeasurementRuntime( ...
        state,'SRS','UE',1,row,'ProducerSlot',slot,'AvailableSlot',slot+1, ...
        'Valid',true,'Direction','UL','SourceSignal','SRS','MeasurementSource','physical_component');
    for field=string(fieldnames(sixgr.link.srsPilotPhaseEvidence())).'
        assert(isequaln(state.ReferenceSignalMeasurementTable.(field)(end,:),row.(field)));
    end
    rows=[rows;row]; %#ok<AGROW>
end
sixgr.util.csvWriteTable(fullfile(folder,'srs_trials.csv'),rows,'PreserveSchema',true);
sixgr.util.csvWriteTable(fullfile(folder,'reference_measurements.csv'),state.ReferenceSignalMeasurementTable,'PreserveSchema',true);
fprintf('SRS_SHARED_PHASE_HISTORY_PASS occasions=2 common_rate=%g evidence=%s\n',out.PilotCommonPhaseRate_Hz,folder);
ok=true;
end

function b=buffer(samples,first,fs)
b=sixgr.phy.waveform.WaveformObservationBuffer(first,first+size(samples,1),fs,size(samples,2));
b.append(sixgr.phy.waveform.WaveformChunk(samples,first),fs);
end
