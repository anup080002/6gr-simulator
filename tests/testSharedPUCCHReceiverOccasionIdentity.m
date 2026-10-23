function ok=testSharedPUCCHReceiverOccasionIdentity()
% Real typed PUCCH preparation; declared receipt/capture component fixtures.
% This is an identity regression, not executed RF or UCI reliability evidence.
setup6GRSimToolkit('Verbose',false);
[item,state,row,rx]=fixture();
[physical,key,source]=sixgr.truth.sharedPUCCHReceiverOccasionIdentity(item);
assert(physical~=key && physical==row.PhysicalPUCCHOccasionId && ...
    source=="prepared_feedback_physical_occasion_with_distinct_queue_key");
before=row;
bound=sixgr.truth.bindSharedTransmitOccupancy(row,state,item);
assert(isequaln(bound(:,before.Properties.VariableNames),before), ...
    'Binding must not relabel or overwrite an independent receiver row.');
e=jsondecode(bound.TransmitOccupancyEvidenceJSON);
assert(string(e.ReceiverBinding.SourceRowIdentity)==physical && ...
    string(e.ReceiverBinding.PhysicalOccasionID)==physical && ...
    string(e.ReceiverBinding.QueueKey)==key && ...
    string(e.ReceiverBinding.ObservationID)==item.ID && ...
    bound.TransmitOccupancyEvidenceSHA256==sixgr.util.sha256Hex(bound.TransmitOccupancyEvidenceJSON));
state.ControlTrials.PUCCH=bound;
scored=sixgr.truth.bindSharedPUCCHPresence(state,item,rx);
assert(scored.ControlTrials.PUCCH.PhysicalPUCCHOccasionId==physical && ...
    scored.ControlTrials.PUCCH.PresencePhysicalOccasionID==physical && ...
    isnan(scored.ControlTrials.PUCCH.SignalPresent));
% No execution-segment receipts were supplied by this component fixture.
% Its finite buffers cannot be promoted to measured transmission presence.
presence=jsondecode(scored.ControlTrials.PUCCH.PresenceEvidenceJSON);
assert(string(presence.PhysicalOccasionID)==physical && string(presence.QueueKey)==key);

id='sixgr:truth:PUCCHReceiverOccasionIdentity';
bad=item; bad.Context=rmfield(bad.Context,'PhysicalOccasionId');
reject(@()sixgr.truth.bindSharedTransmitOccupancy(row,state,bad),id);
bad=item; bad.Context.PhysicalOccasionId="another_physical_occasion";
reject(@()sixgr.truth.bindSharedTransmitOccupancy(row,state,bad),id);
bad=item; bad.Context.PhysicalOccasionId=key;
reject(@()sixgr.truth.bindSharedTransmitOccupancy(row,state,bad),id);
bad=item; bad.Context.Key="another_queue";
reject(@()sixgr.truth.bindSharedTransmitOccupancy(row,state,bad),id);
bad=item; bad.Context.ObservationID="another_observation";
reject(@()sixgr.truth.bindSharedTransmitOccupancy(row,state,bad),id);
bad=item; bad.Context.GNBReception.Assignment.Data.ObservationID="another_observation";
reject(@()sixgr.truth.bindSharedTransmitOccupancy(row,state,bad),id);
bad=item; bad.Context.FeedbackRows.ComponentCarrier=bad.Context.FeedbackRows.ComponentCarrier+1;
reject(@()sixgr.truth.bindSharedTransmitOccupancy(row,state,bad),id);
wrong=row; wrong.PhysicalPUCCHOccasionId=key;
reject(@()sixgr.truth.bindSharedTransmitOccupancy(wrong,state,item), ...
    'sixgr:truth:TransmitOccupancyRowIdentity');
badState=state; badState.ControlTrials.PUCCH.PhysicalPUCCHOccasionId=key;
reject(@()sixgr.truth.bindSharedPUCCHPresence(badState,item,rx), ...
    'sixgr:truth:AmbiguousPUCCHPresenceTrial');
bad=item; bad.Planes(2).ReceiverID="gnb_2_rx:post_rf";
reject(@()sixgr.truth.bindSharedTransmitOccupancy(row,state,bad), ...
    'sixgr:truth:TransmitOccupancyEndpoint');
bad=item; p=item.Context.Prepared;
bad.Planes(2).Observation=buffer(p.ReceiveStartSample, ...
    complex(zeros(p.ReceiveEndSampleExclusive-p.ReceiveStartSample,1)),p.SampleRateHz*2);
reject(@()sixgr.truth.bindSharedTransmitOccupancy(row,state,bad), ...
    'sixgr:truth:TransmitOccupancyCompletion');
badState=state; badState.SharedWaveformStream.Events.NextSampleIndex=p.StartSample+1;
reject(@()sixgr.truth.bindSharedTransmitOccupancy(row,badState,item), ...
    'sixgr:truth:TransmitOccupancyCompletion');

% Configured CSI and SR explicitly publish queue-owned receiver row IDs.
% Their completion contract is not a fallback for missing HARQ preparation.
for calendar=["CSIReportCalendar","SRReportCalendar"]
    configured=item; configured.Context=rmfield(configured.Context,'PhysicalOccasionId');
    configured.Context.GNBReception.Mapping=struct([]);
    configured.Context.GNBReception.(calendar)=table("installed_obligation", ...
        'VariableNames',{'ObligationID'});
    [actual,actualKey,origin]=sixgr.truth.sharedPUCCHReceiverOccasionIdentity(configured);
    assert(actual==key && actualKey==key && origin=="configured_CSI_SR_receiver_queue_owned_occasion");
    configuredRow=row; configuredRow.PhysicalPUCCHOccasionId=key;
    configuredBound=sixgr.truth.bindSharedTransmitOccupancy(configuredRow,state,configured);
    assert(configuredBound.PhysicalPUCCHOccasionId==key);
end
bad=item; bad.Context.GNBReception.Mapping=struct([]);
reject(@()sixgr.truth.sharedPUCCHReceiverOccasionIdentity(bad),id);
absent=item; absent.Kind="PUCCHReceiveOnly";
absent.Context=rmfield(absent.Context,{'Prepared','PhysicalOccasionId'});
[actual,~,origin]=sixgr.truth.sharedPUCCHReceiverOccasionIdentity(absent);
assert(actual==key && origin=="scheduled_HARQ_receive_only_queue_owned_occasion");
fprintf('SHARED_PUCCH_RECEIVER_OCCASION_IDENTITY_PASS distinct_namespaces=1 negative_transplants=1 component_receipts_not_RF=1\n');
ok=true;
end

function [item,state,row,rx]=fixture()
s=sixgr.lls6g.config.loadScenarioConfig( ...
    'simulator/configs/scenarios/lls_causal_tdd_connected_feedback_fixture.yaml');
cfg=sixgr.lls6g.buildInternalConfig(s,tempname);
cfg=sixgr.phy.grid.applyRuntimeCarrierTimeline(cfg,5,1);
carrier=sixgr.phy.grid.makeCarrier(cfg); ofdm=nrOFDMInfo(carrier);
cfg.lls6g.userContext.RuntimeSlotStartTime_s= ...
    sixgr.phy.frame.slotStartSample(carrier,4,ofdm.SampleRate)/ofdm.SampleRate;
ue=struct('UEID',1,'RNTI',1,'ServingCell',1,'PUCCHCell',1, ...
    'ComponentCarrier',cfg.phy.frame.DefaultIdentity.ScheduledCCID, ...
    'ActiveULBWP',cfg.phy.frame.DefaultIdentity.ULBWPID);
frame=struct('K1',4,'K1Source',"decoded_dci",'PDSCHEndSlot',1,'TargetSlot',5, ...
    'DecodedPRI',0,'PRIFieldWidth',3,'FirstCCE',0,'NumCCE',8, ...
    'PRIProvenance',"declared_component_DCI",'SlotSymbolOwnership',"UUUUUUUUUUUUUU");
planned=sixgr.phy.pucch.PUCCHConfigBuilder.planHARQ(cfg,ue,int8([1;0;1]),frame);
connected=sixgr.phy.pucch.PUCCHConfigBuilder.materialize(cfg,planned);
trial=sixgr.link.runPUCCHWaveformTrial(cfg,'Carrier',carrier, ...
    'Assignment',connected.Assignment,'Report',connected.Report, ...
    'ChannelProfile',sixgr.channel.resolveConcreteProfile(cfg), ...
    'SNR_dB',30,'TimingAdvanceSamples',0,'PrepareOnly',true);
p=trial.PreparedTransmission; observation="declared_component_observation";
identity=sixgr.truth.preparedPUCCHTransmissionIdentity(p,1,observation);
rows=struct2table(struct('ScheduledAbsoluteSlot',5,'UEIndex',1,'RNTI',1, ...
    'ServingCell',1,'ComponentCarrier',ue.ComponentCarrier,'ActiveULBWP',ue.ActiveULBWP, ...
    'FeedbackForDirection',"DL"),'AsArray',true);
key=sixgr.truth.CoupledTruthRuntime.sharedPUCCHOccasionKey(rows);
physical=string(sprintf('pucchoccasion:due=5:ue=1:rnti=1:cell=1:cc=%d:ulbwp=%d', ...
    ue.ComponentCarrier,ue.ActiveULBWP));
h=struct('UEIndex',1,'RNTI',1,'ServingCell',1,'Mapping',struct('Digest',"declared_mapping"), ...
    'Assignment',struct('Digest',"declared_receiver_assignment",'Resource',struct('Digest',"declared_resource"), ...
    'Data',struct('ObservationID',observation,'RNTI',1,'AbsoluteSlot0',4)), ...
    'Context',struct('Digest',"declared_receiver_context",'Data',struct('ReportID',observation)));
c=struct('Prepared',p,'ObservationID',observation,'Key',key,'Slot',5, ...
    'PhysicalOccasionId',physical,'FeedbackRows',rows,'GNBReception',h);
array=sixgr.rf.AntennaArrayFactory.build(p.ReceiverConfig,'ue','signal','pucch', ...
    'numPorts',size(p.Tx.Waveform,2));
x=p.Tx.Waveform*cast(array.PortToElementMatrix.','like',p.Tx.Waveform);
tx=buffer(p.StartSample,x,p.SampleRateHz);
post=buffer(p.ReceiveStartSample,complex(zeros(p.ReceiveEndSampleExclusive-p.ReceiveStartSample,1)),p.SampleRateHz);
segments={struct('Execution',struct(),'StartSample',p.StartSample,'EndSampleExclusive',p.EndSampleExclusive)};
planes=struct('ReceiverID',{'ue_1:tx','gnb_1_rx:post_rf'}, ...
    'Observation',{tx,post},'Segments',{segments,segments});
item=struct('ID',observation,'UE',1,'Kind',"PUCCH",'Context',c,'Planes',planes);
epoch=p.ReceiverConfig.rf.configurationEpoch;
occupancyID=struct('Channel',"PUCCH",'TransmissionID',identity.TransmissionID, ...
    'ObservationID',observation,'UEIndex',1,'RNTI',1,'ServingCell',1, ...
    'TransmitterID',"ue_1",'ClockDomain',"shared_physical_sample_clock/v1",'ClockEpoch',epoch);
e=sixgr.truth.captureTransmitOccupancy(x,p.StartSample,p.SampleRateHz,occupancyID);
first=e.ActiveIntervals(1,1);
receipt=struct('Identity',identity,'FirstActiveSample',first,'CommittedAtSample',first+1, ...
    'TransmitOccupancy',e,'TransmitPopulationIdentity',struct('BoundAtSample',first+1));
owner=struct('PUCCHTransmissions',receipt,'Physical',struct('ConfigurationEpoch',epoch), ...
    'Events',struct('NextSampleIndex',max(p.EndSampleExclusive,p.ReceiveEndSampleExclusive)));
row=table(1,1,1,5,physical,"declared_receiver_assignment","declared_receiver_context", ...
    post.StartSample,post.EndSampleExclusive,post.SampleRateHz,'VariableNames', ...
    {'UEIndex','RNTI','ServingCell','Slot','PhysicalPUCCHOccasionId', ...
    'ReceiverAssignmentDigest','ReceiverContextDigest','ObservationStartSample', ...
    'ObservationEndSampleExclusive','ObservationSampleRateHz'});
state=struct('SharedWaveformStream',owner,'SharedPUCCHTXLedger',{{receipt}}, ...
    'ControlTrials',struct('PUCCH',row));
rx=struct('AssignmentDigest',h.Assignment.Digest,'ReportContextDigest',h.Context.Digest, ...
    'ReceiverObservationStartSample',post.StartSample,'ReceiverObservationEndSampleExclusive',post.EndSampleExclusive, ...
    'ReceiverObservationSampleRateHz',post.SampleRateHz);
end

function b=buffer(first,x,fs)
b=sixgr.phy.waveform.WaveformObservationBuffer(first,first+size(x,1),fs,size(x,2));
b.append(sixgr.phy.waveform.WaveformChunk(x,first),fs);
end

function reject(action,id)
try, action(); catch cause
    assert(strcmp(cause.identifier,id),'Expected %s; got %s: %s',id,cause.identifier,cause.message); return;
end
error('test:ExpectedFailure','Expected %s.',id);
end
