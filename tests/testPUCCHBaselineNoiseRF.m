function ok=testPUCCHBaselineNoiseRF(outputRoot)
% Independent receiver noise/RF observation, NOT a complete baseline run.
% No PUCCH is transmitted; no power/beam/channel/timing observation is forged.
% The actual retained physical owner supplies noise and RX RF. Only complete
% configured UL slots are scored. Slot timing is prescribed, not acquired.
if nargin<1, outputRoot=tempname; end
setup6GRSimToolkit('Verbose',false);
assert(~isfolder(outputRoot),'test:EvidenceExists','Choose a new evidence directory.');
mkdir(outputRoot);
v=sixgr.lls6g.config.readConfigFile('simulator/configs/validation/pucch_baseline_dtx.yaml');
s=sixgr.lls6g.config.loadScenarioConfig(v.scenario_path);
cfg=sixgr.lls6g.buildInternalConfig(s,outputRoot);
validateattributes(v.noise_occasions,{'numeric'},{'scalar','integer','positive','finite'});
assert(all(ismember(v.harq_bit_counts,[1 2])) && numel(unique(v.harq_bit_counts))==numel(v.harq_bit_counts));
validateattributes(v.confidence_alpha,{'numeric'},{'scalar','>',0,'<',1});
multi=struct('Enabled',true,'NumUsers',1,'RNTIStart',1,'ExecutionModel','slot_coupled_truth');
state=sixgr.truth.CoupledTruthRuntime.initialize(cfg,outputRoot,multi,struct(),1);
state.CurrentSlot=1; state.CurrentServingIdx(:)=1;
[ul,~]=sixgr.truth.CoupledTruthRuntime.applyUserContext(cfg,state,1,'UL');
% These are the same materialized endpoint element dimensions used by the
% shared owner; do not use DL-oriented phy.nRxAnt as the gNB UL count.
nt=double(ul.lls6g.userContext.RuntimeUEAntenna.NumElements);
nr=double(ul.lls6g.userContext.RuntimeServingBSAntenna.NumElements);
assert(nr==cfg.antenna.bs.numElements && nt==cfg.antenna.ue.numElements);
carrier=sixgr.phy.grid.makeCarrier(ul); info=nrOFDMInfo(carrier);
fs=double(info.SampleRate); epoch=cfg.rf.configurationEpoch;
owner=sixgr.truth.SharedWaveformPhysicalRuntime(fs,0,epoch);
owner.addTransmitter(v.transmitter_id,ul,'UL',nt,true);
owner.addReceiver(v.receiver_id,ul,'UL',nr,false);
% A receiver-only experiment has no active transmitter-to-receiver link.
% Therefore no CDL/O2I execution or signal-present ACK-miss result is claimed.
resource=cfg.phy.pucch.resources([cfg.phy.pucch.resources.id]==cfg.phy.pucch.harqACKResourceID);
assert(isscalar(resource) && resource.format==0 && resource.nrof_prbs==1);
pucch=nrPUCCH0Config('PRBSet',resource.starting_prb, ...
    'SymbolAllocation',[resource.starting_symbol resource.nrof_symbols], ...
    'InitialCyclicShift',resource.initial_cyclic_shift,'HoppingID',resource.hopping_id);
assert(~resource.intra_slot_hopping,'test:UnsupportedFixture','Extend this test before claiming hopping qualification.');
key="detection_threshold_format0_two_symbols";
if resource.nrof_symbols==1, key="detection_threshold_format0_one_symbol"; end
threshold=cfg.phy.pucch.receiverDetectionThresholds.(key);
source="yaml.pucch."+key;
ue=struct('UEID',1,'RNTI',1,'ServingCell',1,'PUCCHCell',1, ...
    'ComponentCarrier',cfg.phy.frame.DefaultIdentity.ScheduledCCID, ...
    'ActiveULBWP',cfg.phy.frame.DefaultIdentity.ULBWPID);
rrc=sixgr.phy.pucch.PUCCHConfigBuilder.receiverConfiguration(cfg,ue);
resolvedScenario=s.Data;
save(fullfile(outputRoot,'configuration.mat'),'v','resolvedScenario','cfg','resource','pucch','nt','nr','fs');
iqPath=fullfile(outputRoot,'noise_observations.mat');
scope=string(v.evidence_scope);
save(iqPath,'scope','-v7.3'); iq=matfile(iqPath,'Writable',true);
rows=cell(v.noise_occasions*numel(v.harq_bit_counts),1);
first=0; slot=0; count=0; rowIndex=0; iqFirst=1;
while count<v.noise_occasions
    carrier.NFrame=floor(slot/carrier.SlotsPerFrame);
    carrier.NSlot=mod(slot,carrier.SlotsPerFrame);
    slotInfo=nrOFDMInfo(carrier); lengthSamples=sum(double(slotInfo.SymbolLengths));
    stop=first+lengthSamples;
    input=struct('ID',string(v.transmitter_id),'Chunk', ...
        sixgr.phy.waveform.WaveformChunk(complex(zeros(lengthSamples,nt)),first));
    [outputs,execution]=owner.process(input,first,stop,[]);
    assert(owner.NextSampleIndex==stop && isempty(execution.Links));
    [dlAllowed,ulAllowed]=sixgr.truth.CoupledTruthRuntime.resolveSlotPartition(cfg,slot+1);
    if ulAllowed && ~dlAllowed
        count=count+1;
        hit=find(string({outputs.ID})==string(v.receiver_id)+":post_rf");
        assert(isscalar(hit)); waveform=outputs(hit).Chunk.Samples;
        iq.IQ(iqFirst:iqFirst+lengthSamples-1,1:nr)=waveform;
        replay=execution.RX.Replay;
        assert(replay.RequestedAWGNReferenceSNR_dB==s.Data.simulation.snr_db);
        for bits=double(v.harq_bit_counts(:).')
            context=sixgr.phy.pucch.UCIReportContext(struct( ...
                'ReportID',"noise-"+string(count)+"-"+string(bits), ...
                'ConfigurationEpoch',rrc.ConfigurationEpoch, ...
                'Sequence1Length',bits,'Sequence2Length',0,'HARQACKBits',bits, ...
                'SRBits',0,'CSIPart1Bits',0,'CSIPart2Bits',0,'PriorityIndex',0));
            assignment=sixgr.phy.pucch.PUCCHReceptionAssignment(struct( ...
                'ObservationID',context.ReportID,'ResourceID',resource.id, ...
                'RNTI',ue.RNTI,'AbsoluteSlot0',slot, ...
                'Source','physical_owner_noise_receiver_component', ...
                'TimingSource','prescribed_slot_window_not_acquired_sync'),rrc,context);
            received=sixgr.phy.pucch.PUCCHReceiver.receive(waveform,carrier,assignment,context, ...
                'NoiseVariance',NaN,'NoiseVarianceMode','noncoherent_correlation', ...
                'ChannelProfile','AWGN','DetectionThreshold',threshold);
            metric=received.DetectionMetric;
            detected=~received.DTX; ack=sum(received.DecodedSequence1==1);
            assert(detected==(metric>=threshold) && (~detected || numel(received.DecodedSequence1)==bits));
            assert(received.ReceiverOnlyAssignment && ~received.OraclePayloadBitsUsed);
            rowIndex=rowIndex+1;
            rows{rowIndex}=struct('Occasion',count,'AbsoluteSlot0',slot, ...
                'StartSample',first,'EndSampleExclusive',stop,'IQFirstRow',iqFirst, ...
                'IQRowCount',lengthSamples,'ReceiveBranches',nr,'HARQBits',bits, ...
                'SignalPresent',false,'Detected',detected,'FalseACKBits',ack, ...
                'DetectionMetric',double(metric),'DetectionThreshold',threshold, ...
                'DetectionThresholdSource',source,'NoiseStreamSeed',replay.NoiseStreamSeed, ...
                'InjectedSampleNoiseVariance',replay.InjectedNoiseVariance, ...
                'ConfiguredReferenceEsN0_dB',replay.RequestedAWGNReferenceSNR_dB, ...
                'RFAppliedStageCount',replay.RFAppliedStageCount, ...
                'TimingSource',"prescribed_slot_window_not_acquired_sync", ...
                'Source',scope,'ReceiverImplementation',"canonical_pucch_receiver", ...
                'ReceptionAssignmentDigest',assignment.Digest,'ReceiverContextDigest',context.Digest);
        end
        iqFirst=iqFirst+lengthSamples;
    end
    first=stop; slot=slot+1;
    if mod(count,64)==0 && ulAllowed && ~dlAllowed
        fprintf('PUCCH_DTX_PROGRESS occasions=%d / %d rx_branches=%d slot0=%d\n',count,v.noise_occasions,nr,slot-1);
    end
end
clear iq;
trials=struct2table(vertcat(rows{:}));
trials.IQSHA256=repmat(string(sixgr.util.sha256File(iqPath)),height(trials),1);
writetable(trials,fullfile(outputRoot,'noise_trials.csv'));
summaries=cell(numel(v.harq_bit_counts),1);
for k=1:numel(v.harq_bit_counts)
    bits=v.harq_bit_counts(k); t=trials(trials.HARQBits==bits,:); n=height(t);
    falseACK=sum(t.FalseACKBits); anyACK=sum(t.FalseACKBits>0);
    upper=1;
    if anyACK<n, upper=betaincinv(1-v.confidence_alpha,anyACK+1,n-anyACK); end
    summaries{k}=struct('HARQBits',bits,'NoiseOccasions',n,'ReceiveBranches',nr, ...
        'FalseDetections',sum(t.Detected),'FalseACKBits',falseACK,'ACKBitDenominator',n*bits, ...
        'DTXToACKBitFraction',falseACK/(n*bits),'OccasionsWithFalseACK',anyACK, ...
        'AnyACKUpperBoundUnderIIDOccasionAssumption',upper, ...
        'ConfidenceAlpha',v.confidence_alpha,'Requirement',v.dtx_to_ack_requirement, ...
        'EmpiricalFractionMeetsLimit',falseACK/(n*bits)<=v.dtx_to_ack_requirement, ...
        'QualificationStatus',"component_only_no_conformance_or_ACK_miss_qualification");
end
summary=struct2table(vertcat(summaries{:}));
writetable(summary,fullfile(outputRoot,'noise_summary.csv'));
save(fullfile(outputRoot,'terminal.mat'),'trials','summary','execution','first','slot');
disp(summary);
fprintf('PUCCH_BASELINE_NOISE_COMPONENT_COMPLETE no_signal_present_or_conformance_claim\n');
ok=true;
end
