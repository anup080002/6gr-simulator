function ok=testPUCCHTrialIndependentReceive(outputRoot)
% Actual codec/connector observations, not scheduled missing-DCI qualification.
setup6GRSimToolkit('Verbose',false);
if nargin<1
    logsRoot=fullfile(pwd,'logs');
    if ~isfolder(logsRoot), mkdir(logsRoot); end
    outputRoot=tempname(logsRoot);
end
assert(~isfolder(outputRoot),'test:EvidenceExists','Preserve earlier evidence.');
mkdir(outputRoot);
source=sixgr.lls6g.config.loadScenarioConfig(fullfile('simulator','configs', ...
    'scenarios','lls_causal_access_to_data_wiring_tdd.yaml'));
cfg=sixgr.lls6g.buildInternalConfig(source,tempname);
cfg.channel.model='AWGN'; cfg.channel.awgnOnly=true;
cfg.channel.fading.enabled=false; cfg.channel.fading.type='AWGN';
cfg.run.noiseOperatingMode='standalone_awgn_snr_argument';
cfg=sixgr.phy.grid.applyRuntimeCarrierTimeline(cfg,5,1);
cfg.lls6g.userContext.RuntimeSlotStartTime_s=4e-3;
cfg.lls6g.userContext.RuntimeServingPathloss_dB=77;
cfg.lls6g.userContext.RuntimeServingPathlossSource='unit_fixture_analytic_reference_not_field_measurement';
cfg.lls6g.userContext.RuntimeServingPathlossReferenceRS='SSB-0';
cfg.lls6g.userContext.RuntimeServingPathlossMeasurementId='unit_fixture_not_measured_access';
cfg.lls6g.userContext.RuntimeServingPathlossMeasurementSlot=1;
cfg.lls6g.userContext.RuntimeServingPathlossReferenceSignalType='SSB';
cfg.lls6g.userContext.RuntimeServingPathlossReferenceSignalId=0;
identity=cfg.phy.frame.DefaultIdentity;
ue=struct('UEID',1,'RNTI',cfg.phy.pusch.RNTI,'ServingCell',1,'PUCCHCell',1, ...
    'ComponentCarrier',identity.ScheduledCCID,'ActiveULBWP',identity.ULBWPID);
rrc=sixgr.phy.pucch.PUCCHConfigBuilder.receiverConfiguration(cfg,ue);
frame=struct('K1',4,'K1Source','decoded_dci','PDSCHEndSlot',1,'TargetSlot',5, ...
    'DecodedPRI',0,'PRIFieldWidth',3,'PRIProvenance','unit_fixture', ...
    'FirstCCE',0,'NumCCE',4,'SlotSymbolOwnership','UUUUUUUUUUUUUU', ...
    'FlexibleResolutionProvided',false,'TriggeringEventID','unit_fixture');
% Receiver contexts are constructed before any UE payload or transmitter.
hypotheses=cell(2,1);
for i=1:2
    count=[3 12]; count=count(i);
    harq=count; sr=0; csi=0;
    if count==12, harq=2; sr=1; csi=9; end
    context=sixgr.phy.pucch.UCIReportContext(struct('ReportID',"gnb-declared-"+count, ...
        'ConfigurationEpoch',rrc.ConfigurationEpoch,'Sequence1Length',count,'Sequence2Length',0, ...
        'HARQACKBits',harq,'SRBits',sr,'CSIPart1Bits',csi,'CSIPart2Bits',0,'PriorityIndex',0));
    set=sixgr.phy.pucch.PUCCHResourceSetResolver.resolveBitCount(count,rrc,rrc.ConfigurationEpoch);
    assignment=sixgr.phy.pucch.PUCCHReceptionAssignment(struct( ...
        'ObservationID',context.ReportID,'ResourceID',set.ResourceIDs(1),'RNTI',ue.RNTI, ...
        'AbsoluteSlot0',4,'Source','declared_gNB_component_not_scheduled_feedback', ...
        'TimingSource','received_DMRS', ...
        'ResourceSelectionProcedure',localProcedure(csi)),rrc,context);
    hypotheses{i}=struct('Assignment',assignment,'Context',context);
end
audit=table();
for txCount=[3 12]
    bits=int8(mod((1:txCount).',2));
    connected=sixgr.phy.pucch.PUCCHConfigBuilder.connectedHARQ(cfg,ue,bits,frame);
    if txCount==12
        data=connected.Report.Data;
        data.HARQACKReport=struct('Bits',bits(1:2));
        data.SchedulingRequestReports=struct('Bits',bits(3));
        data.CSIReports=struct('Part1Bits',bits(4:12),'Part2Bits',int8([]),'Priority',0,'ReportID',1);
        connected.Report=sixgr.phy.pucch.UCIReport(data);
        connected.Assignment=sixgr.phy.pucch.PUCCHTransmissionAssignment.fromCombinedUCI( ...
            connected.Report,connected.UEContext,frame);
    end
    args={'Assignment',connected.Assignment,'Report',connected.Report, ...
        'Carrier',sixgr.phy.grid.makeCarrier(cfg),'ChannelProfile','AWGN', ...
        'SNR_dB',34,'TimingAdvanceSamples',0};
    pending=sixgr.link.runPUCCHWaveformTrial(cfg,args{:},'PrepareOnly',true);
    p=pending.PreparedTransmission;
    array=sixgr.rf.AntennaArrayFactory.build(cfg,'ue','signal','pucch','numPorts',size(p.Tx.Waveform,2));
    x=p.Tx.Waveform*cast(array.PortToElementMatrix.','like',p.Tx.Waveform);
    desired=x*cast(eye(size(x,2),p.NumReceiveAntennas)*10^(-77/20),'like',x);
    [energy,~]=sixgr.phy.waveform.measureReceivedOccupiedREEnergy( ...
        p.Tx.Carrier,desired,p.Tx.PUCCHIndices,'SignalFamily','PUCCH');
    rng(34000+txCount,'twister');
    [y,noise]=sixgr.phy.waveform.addOccupiedREAWGN(desired,p.Tx.Carrier,34,'SignalEnergyPerOccupiedRE',energy);
    replay=struct('SampleNoiseVariance',noise.SampleNoiseVariance, ...
        'SampleNoiseVarianceDomain','receiver_sample_waveform_post_composite_front_end', ...
        'NoiseVarianceSource','explicit_isolated_occupied_re_awgn', ...
        'NoiseOperatingMode','standalone_awgn_snr_argument','AppliedAWGNSNR_dB',34,'ApproximationMode','none');
    input=struct('Prepared',p,'Observation',buffer(p,y),'PhysicalMeasurementObservation',buffer(p,y), ...
        'TransmitterObservation',buffer(p,x),'DesiredReferenceObservation',buffer(p,desired), ...
        'Replay',replay,'ChannelState',struct('UnitConnectorConsumedSamples',size(x,1)), ...
        'Channel',struct('Profile','AWGN','Source','unit_analytic_attenuating_connector'));
    for i=1:2
        h=hypotheses{i}; rxCount=h.Context.Sequence1Length;
        input.GNBReception=h;
        before=rng;
        trial=sixgr.link.runPUCCHWaveformTrial(cfg,args{:},'ReceivedContext',input);
        assert(isequal(before,rng),'Completion must not regenerate random RF/noise/TX.');
        direct=sixgr.link.receivePUCCHObservation(p.ReceiverConfig,h.Assignment,h.Context,input.Observation);
        names=string(fieldnames(direct)); latency=cellstr(names(endsWith(names,'Latency_ms')));
        assert(isequaln(rmfield(trial.Rx,latency),rmfield(direct,latency)), ...
            'Trial wrapper must reproduce the receiver-only API exactly.');
        assert(trial.IndependentReceiverAssignment && trial.ReceiverExpectedBitCount==rxCount && ...
            trial.ExpectedBitCount==txCount && trial.CRCApplicable==(rxCount>=12) && ...
            trial.TransmitterUCICRCApplicable==(txCount>=12));
        assert(isequaln(trial.ReceiverFields,direct.DecodedFields));
        if rxCount<12, assert(isnan(trial.CRCPass)); else, assert(trial.CRCPass==direct.CRCPassed); end
        if txCount==rxCount
            assert(~trial.DTXFlag && trial.UCIContentMatch && trial.Ok);
            if txCount==12
                assert(isequal(trial.ReceiverFields.HARQACK,bits(1:2)) && ...
                    isequal(trial.ReceiverFields.SR,bits(3)) && isequal(trial.ReceiverFields.CSIPart1,bits(4:12)));
            end
        end
        changed=input; changed.Replay.SampleNoiseVariance=12345;
        changed.Replay.InterferenceCovariance=1e6*eye(p.NumReceiveAntennas);
        counterfactual=sixgr.link.runPUCCHWaveformTrial(cfg,args{:},'ReceivedContext',changed);
        assert(isequaln(rmfield(trial.Rx,latency),rmfield(counterfactual.Rx,latency)));
        bad=input; bad.GNBReception.Assignment=connected.Assignment;
        reject(@()sixgr.link.runPUCCHWaveformTrial(cfg,args{:},'ReceivedContext',bad), ...
            'sixgr:link:InvalidGNBUCIReceiveHypothesis');
        bad=input; bad.GNBReception.ExpectedBits=bits;
        reject(@()sixgr.link.runPUCCHWaveformTrial(cfg,args{:},'ReceivedContext',bad), ...
            'sixgr:link:InvalidGNBUCIReceiveHypothesis');
        save(fullfile(outputRoot,sprintf('tx_%d_rx_%d.mat',txCount,rxCount)), ...
            'cfg','h','input','trial','direct','txCount','rxCount');
        audit=[audit;table(txCount,rxCount,trial.CRCApplicable,trial.TransmitterUCICRCApplicable, ...
            trial.CRCPass,trial.DTXFlag,true,'VariableNames', ...
            {'TXBits','RXExpectedBits','ReceiverCRCApplicable','TransmitterCRCApplicable','ReceiverCRCPass','DTX','DirectRXEqual'})]; %#ok<AGROW>
    end
end
writetable(audit,fullfile(outputRoot,'receiver_authority_audit.csv'));
fprintf('PUCCH_TRIAL_INDEPENDENT_PASS cases=4 combined_fields=1 differing_CRC_lengths=2 no_injected_metadata_consumed=1 evidence=component\n');
ok=true;
end
function b=buffer(p,x)
b=sixgr.phy.waveform.WaveformObservationBuffer(p.StartSample,p.StartSample+size(x,1),p.SampleRateHz,size(x,2));
b.append(sixgr.phy.waveform.WaveformChunk(x,p.StartSample),p.SampleRateHz);
end
function value=localProcedure(csiBits)
value="dynamic_harq";
if csiBits>0, value="dynamic_harq_csi"; end
end
function reject(fn,id)
try, fn(); catch cause
    assert(strcmp(cause.identifier,id),'Expected %s; got %s: %s',id,cause.identifier,cause.message); return;
end
error('test:MissingRejection','Expected %s.',id);
end
