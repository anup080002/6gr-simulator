function ok=testPUCCHReceiverOnlyAssignment()
% Replay actual retained no-signal IQ through the canonical receiver.
% This is API/detector equivalence, not an independent conformance campaign.
setup6GRSimToolkit('Verbose',false);
root=fullfile('docs','lls','evidence_20260913','pucch_baseline_noise_rf_01');
x=load(fullfile(root,'configuration.mat'));
rows=readtable(fullfile(root,'noise_trials.csv'),'TextType','string');
iqPath=fullfile(root,'noise_observations.mat');
assert(all(rows.IQSHA256==string(sixgr.util.sha256File(iqPath))));
iq=matfile(iqPath);
ue=struct('UEID',1,'RNTI',1,'ServingCell',1,'PUCCHCell',1, ...
    'ComponentCarrier',x.cfg.phy.frame.DefaultIdentity.ScheduledCCID, ...
    'ActiveULBWP',x.cfg.phy.frame.DefaultIdentity.ULBWPID);
rrc=sixgr.phy.pucch.PUCCHConfigBuilder.receiverConfiguration(x.cfg,ue);
% Cover absent detections and actual false alarms for both payload lengths.
selected=[1;2];
for bits=[1 2]
    selected=[selected;find(rows.HARQBits==bits & rows.Detected,1)]; %#ok<AGROW>
end
for index=unique(selected).'
    row=rows(index,:);
    carrier=sixgr.phy.grid.makeCarrier(x.cfg);
    carrier.NFrame=floor(row.AbsoluteSlot0/carrier.SlotsPerFrame);
    carrier.NSlot=mod(row.AbsoluteSlot0,carrier.SlotsPerFrame);
    context=sixgr.phy.pucch.UCIReportContext(struct( ...
        'ReportID',"noise-observation-"+string(row.Occasion), ...
        'ConfigurationEpoch',rrc.ConfigurationEpoch, ...
        'Sequence1Length',row.HARQBits,'Sequence2Length',0, ...
        'HARQACKBits',row.HARQBits,'SRBits',0,'CSIPart1Bits',0, ...
        'CSIPart2Bits',0,'PriorityIndex',0));
    data=struct('ObservationID',context.ReportID,'ResourceID',x.resource.id, ...
        'RNTI',ue.RNTI,'AbsoluteSlot0',row.AbsoluteSlot0, ...
        'Source','retained_noise_receiver_component_fixture', ...
        'TimingSource','prescribed_slot_window_not_acquired_sync');
    assignment=sixgr.phy.pucch.PUCCHReceptionAssignment(data,rrc,context);
    assert(~isprop(assignment,'PowerControlState') && ~isprop(assignment,'SpatialRelationState'));
    waveform=iq.IQ(row.IQFirstRow:row.IQFirstRow+row.IQRowCount-1,1:row.ReceiveBranches);
    [threshold,~]=sixgr.phy.pucch.resolveDetectionThreshold( ...
        assignment,x.cfg.phy.pucch.receiverDetectionThresholds);
    assert(threshold==row.DetectionThreshold);
    result=sixgr.phy.pucch.PUCCHReceiver.receive(waveform,carrier,assignment,context, ...
        'NoiseVariance',NaN,'NoiseVarianceMode','noncoherent_correlation', ...
        'ChannelProfile','AWGN','DetectionThreshold',threshold);
    [bits,~,metric]=nrPUCCHDecode(carrier,x.pucch,row.HARQBits, ...
        nrExtractResources(nrPUCCHIndices(carrier,x.pucch), ...
        sixgr.phy.waveform.ofdmDemodulate(carrier,waveform)), ...
        'DetectionThreshold',threshold);
    assert(abs(double(metric)-row.DetectionMetric)<1e-12);
    assert(abs(result.DetectionMetric-double(metric))<1e-12);
    assert(result.DTX==~logical(row.Detected));
    assert(isequal(int8(bits{1}(:)),result.DecodedSequence1));
    assert(result.ReceiverOnlyAssignment && ~result.OraclePayloadBitsUsed);
    assert(isempty(result.ChannelEstimate) && isnan(result.DecodeNoiseInterferenceVariance));
    assert(result.ReceiverAssignmentSource==string(data.Source));
end
bad=data; bad.TransmittedPayloadBits=int8([1;0]);
localReject(@()sixgr.phy.pucch.PUCCHReceptionAssignment(bad,rrc,context), ...
    'sixgr:phy:pucch:OracleInputForbidden');
bad=data; bad.RNTI=ue.RNTI+1;
localReject(@()sixgr.phy.pucch.PUCCHReceptionAssignment(bad,rrc,context), ...
    'sixgr:phy:pucch:WrongRNTI');
bad=data; bad.ResourceID=max(arrayfun(@(r)r.ID,rrc.Resources))+1;
localReject(@()sixgr.phy.pucch.PUCCHReceptionAssignment(bad,rrc,context), ...
    'sixgr:phy:pucch:InvalidResourceIndicator');
hidden=context.Data; hidden.ExpectedBits=int8([1;0]);
hidden=sixgr.phy.pucch.UCIReportContext(hidden);
localReject(@()sixgr.phy.pucch.PUCCHReceptionAssignment(data,rrc,hidden), ...
    'sixgr:phy:pucch:OracleInputForbidden');
bad=data; bad.PowerControlState=struct('AppliedPowerdBm',0);
localReject(@()sixgr.phy.pucch.PUCCHReceptionAssignment(bad,rrc,context), ...
    'sixgr:phy:pucch:OracleInputForbidden');
changed=context.Data; changed.ConfigurationEpoch=changed.ConfigurationEpoch+1;
stale=sixgr.phy.pucch.UCIReportContext(changed);
localReject(@()sixgr.phy.pucch.PUCCHReceptionAssignment(data,rrc,stale), ...
    'sixgr:phy:pucch:StaleConfiguration');
changed=context.Data; changed.PriorityIndex=changed.PriorityIndex+1;
different=sixgr.phy.pucch.UCIReportContext(changed);
localReject(@()sixgr.phy.pucch.PUCCHReceiver.receive(waveform,carrier,assignment,different), ...
    'sixgr:phy:pucch:StaleConfiguration');
wrongCarrier=carrier; wrongCarrier.NSlot=mod(carrier.NSlot+1,carrier.SlotsPerFrame);
localReject(@()sixgr.phy.pucch.PUCCHReceiver.receive(waveform,wrongCarrier,assignment,context), ...
    'sixgr:phy:pucch:WrongReceiveSlot');
fprintf('PUCCH_RECEIVER_ONLY_ASSIGNMENT_PASS retained absent/false-alarm IQ and identity guards\n');
ok=true;
end

function localReject(fn,id)
try, fn(); catch cause
    assert(strcmp(cause.identifier,id),'Expected %s; got %s: %s',id,cause.identifier,cause.message);
    return;
end
error('test:MissingRejection','Expected %s',id);
end
