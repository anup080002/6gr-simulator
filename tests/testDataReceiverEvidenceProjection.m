function ok = testDataReceiverEvidenceProjection()
% Declared receiver/replay boundary fixtures, not waveform qualification.
% No channel, RF, TX, RX or decoder is executed by this test.
for direction=["DL","UL"]
    rx=struct('ReceiverUsable',false,'DecodeAttempted',false,'CRCPass',true, ...
        'TBSBits',1000,'CQI',12,'NoiseVar',1,'ChannelEstimate',ones(2), ...
        'PostEqSINR_dB',30,'PostEqSINRAvailable',false, ...
        'PostEqSINRReceiverDerived',false);
    original=rx;
    row=sixgr.link.summarizeDataReceiverStages(rx,direction);
    assert(isequaln(original,rx) && ~isfield(row,'ReceiverUsable') && ...
        row.DetectionApplicable==0 && row.DetectionAttempted==0 && ...
        row.DetectionUsable==0 && contains(row.DetectionStatus,'not_applicable') && ...
        row.MeasurementUsable==0 && isnan(row.MeasurementAttempted) && ...
        ~row.MeasurementAttemptKnown && isnan(row.MeasurementValue_dB));
    rx.PostEqSINRAvailable=true; rx.PostEqSINRReceiverDerived=true;
    rx.PostEqSINRSource="canonical_post_equalization_sinr";
    rx.PostEqSINRValueRole="measured_post_equalization_scheduling_input";
    rx.PostEqSINRValueStatus="OK";
    rx.SINRComputationMethod="native_equalizer_noise_enhancement";
    rx.CRCError=true;
    row=sixgr.link.summarizeDataReceiverStages(rx,direction);
    assert(row.MeasurementUsable==1 && row.MeasurementAttempted==1 && ...
        row.MeasurementAttemptKnown && row.MeasurementValue_dB==30 && ...
        row.DetectionUsable==0 && contains(row.MeasurementDefinition,'SINR_only'));
    for flag=["PostEqSINRAvailable","PostEqSINRReceiverDerived"]
        bad=rx; bad.(flag)=false;
        row=sixgr.link.summarizeDataReceiverStages(bad,direction);
        assert(row.MeasurementUsable==0 && isnan(row.MeasurementValue_dB));
        bad.(flag)=NaN;
        row=sixgr.link.summarizeDataReceiverStages(bad,direction);
        assert(row.MeasurementUsable==0);
    end
    bad=rx; bad.PostEqSINRSource="configured_post_equalization_sinr";
    row=sixgr.link.summarizeDataReceiverStages(bad,direction);
    assert(row.MeasurementUsable==0 && isnan(row.MeasurementValue_dB));
    bad=rx; bad.PostEqSINR_dB=NaN;
    row=sixgr.link.summarizeDataReceiverStages(bad,direction);
    assert(row.MeasurementUsable==0);
    rx.DetectionApplicable=true; rx.DetectionAttempted=true; rx.DetectionUsable=false;
    rx.DetectionSuccess=false;
    rx.DetectionStatus="declared_receiver_detector_rejected";
    rx.DetectionSource="declared_boundary_detector";
    rx.MeasurementApplicable=true; rx.MeasurementAttempted=false; rx.MeasurementUsable=false;
    rx.MeasurementStatus="declared_receiver_measurement_not_attempted";
    rx.MeasurementSource="declared_boundary_measurement";
    row=sixgr.link.summarizeDataReceiverStages(rx,direction);
    for name=["DetectionApplicable","DetectionAttempted","DetectionSuccess","DetectionUsable", ...
            "DetectionStatus","DetectionSource","MeasurementApplicable", ...
            "MeasurementAttempted","MeasurementUsable","MeasurementStatus","MeasurementSource"]
        assert(isequal(row.(name),rx.(name)) || isequal(row.(name),double(rx.(name))));
    end
    assert(row.MeasurementAttemptKnown && isnan(row.MeasurementValue_dB));
end
empty=sixgr.link.summarizeDataReceiverStages();
assert(isnan(empty.DetectionApplicable) && isnan(empty.MeasurementUsable));
localChannelCases();
% Structural integration guard: the real runners bind their returned rx and
% original replay, and their shared runtime template reaches raw/empty CSVs.
for runner=["runDLPDSCHThroughput","runULPUSCHThroughput"]
    source=fileread(which("sixgr.link."+runner));
    assert(contains(source,'chState, replay, rx);') && ...
        contains(source,'sixgr.link.summarizeDataReceiverStages(rx, direction)') && ...
        contains(source,'sixgr.link.collectDataChannelExecutionEvidence(replay)') && ...
        contains(source,'sixgr.link.summarizeDataReceiverStages();') && ...
        contains(source,'sixgr.link.collectDataChannelExecutionEvidence();') && ...
        contains(source,'T.CountsTowardCoverage = sixgr.util.linkTrialDecodeCoverage(T);') && ...
        ~contains(source,'activeRuntimeMask = ~logical(localOptionalColumn(T, "Crash", false))'));
end
ok=true;
fprintf('testDataReceiverEvidenceProjection PASS (declared boundary fixtures; waveform executions=0)\n');
end

function localChannelCases()
replay=struct('ChannelModelApplied',"AWGN",'ChannelFadingApplied',false, ...
    'ChannelFadingExecutionStatus',"runtime_channel_state_awgn_or_not_materialized");
row=sixgr.link.collectDataChannelExecutionEvidence(replay);
assert(row.ChannelExecutionEvidenceAvailable && row.ChannelFadingApplied==0 && ...
    row.ChannelModelApplied=="AWGN" && strlength(row.ChannelExecutionTransmitterID)==0);
replay.ChannelModelApplied="TDL-C"; replay.ChannelFadingApplied=true;
replay.ChannelFadingExecutionStatus="applied_persistent_runtime_channel_object";
row=sixgr.link.collectDataChannelExecutionEvidence(replay);
assert(row.ChannelExecutionEvidenceAvailable && row.ChannelFadingApplied==1);
replay=rmfield(replay,'ChannelModelApplied');
row=sixgr.link.collectDataChannelExecutionEvidence(replay);
assert(~row.ChannelExecutionEvidenceAvailable && row.ChannelModelApplied=="" && ...
    row.ChannelFadingApplied==1);
row=sixgr.link.collectDataChannelExecutionEvidence(struct( ...
    'ChannelModel',"TDL-C",'ChannelObjectClass',"nrTDLChannel", ...
    'ChannelObjectSource',"constructed_runtime_object"));
assert(~row.ChannelExecutionEvidenceAvailable && isnan(row.ChannelFadingApplied) && row.ChannelModelApplied=="");
shared=localShared();
row=sixgr.link.collectDataChannelExecutionEvidence(shared);
assert(row.ChannelExecutionEvidenceAvailable && row.ChannelFadingApplied==0 && ...
    row.ChannelModelApplied=="AWGN" && row.ChannelExecutionTransmitterID=="desired_tx" && ...
    row.ChannelExecutionReceiverID=="receiver" && row.ChannelExecutionSegmentCount==2 && ...
    row.ChannelExecutionDesiredSegmentCount==2 && row.ChannelExecutionStartSample==2 && ...
    row.ChannelExecutionEndSampleExclusive==18 && row.ChannelExecutionSampleRateHz==30720000);
bad=shared; bad.TransmitterID="not_executed"; localUnavailable(bad);
bad=shared; bad.ReceiverID="not_executed"; localUnavailable(bad);
bad=shared; bad.ReceiveStreamExecutionSegments{2}.Execution.Links(1).TX="different_tx"; localUnavailable(bad);
bad=shared; bad.ReceiveStreamExecutionSegments{2}.Execution.Links(1).RX="different_rx"; localUnavailable(bad);
bad=shared; bad.ReceiveStreamExecutionSegments{2}.Execution.Links(1).Replay.ChannelFadingApplied=true; localUnavailable(bad);
bad=shared; bad.ReceiveStreamExecutionSegments{2}.Execution.Links(1).Replay.ChannelModelApplied="TDL-C"; localUnavailable(bad);
bad=shared; bad.ReceiveStreamExecutionSegments{2}.Execution.SampleRateHz=15360000; localUnavailable(bad);
bad=shared; bad.ReceiveStreamExecutionSegments{2}.Execution.ConfigurationEpoch="epoch2"; localUnavailable(bad);
bad=shared; bad.ReceiveStreamExecutionSegments{2}.Execution.Links(1).Replay.RuntimeChannelStartSample=11; localUnavailable(bad);
bad=shared; bad.ReceiveStreamExecutionSegments{2}.StartSample=11; localUnavailable(bad);
bad=shared; bad.ReceiveStreamExecutionSegments=bad.ReceiveStreamExecutionSegments(1); localUnavailable(bad);
bad=shared; bad.ReceiveStreamExecutionSegments{2}.Execution.Links(end+1)=bad.ReceiveStreamExecutionSegments{2}.Execution.Links(1); localUnavailable(bad);
bad=shared; bad.ReceiveStreamExecutionSegments{2}.Execution.ApproximationMode="fast_proxy"; localUnavailable(bad);
bad=shared; bad.ReceiveStreamExecutionSegments{2}.Execution=rmfield(bad.ReceiveStreamExecutionSegments{2}.Execution,'TX'); localUnavailable(bad);
row=sixgr.link.collectDataChannelExecutionEvidence();
assert(~row.ChannelExecutionEvidenceAvailable && isnan(row.ChannelFadingApplied));
end

function localUnavailable(replay)
row=sixgr.link.collectDataChannelExecutionEvidence(replay);
assert(~row.ChannelExecutionEvidenceAvailable && isnan(row.ChannelFadingApplied) && ...
    strlength(row.ChannelModelApplied)==0 && strlength(row.ChannelExecutionEvidenceStatus)>0);
end

function replay=localShared()
segments=cell(2,1);
for k=1:2
    first=10*(k-1); stop=10*k;
    desired=struct('ChannelModelApplied',"AWGN",'ChannelFadingApplied',false, ...
        'ChannelFadingExecutionStatus',"runtime_channel_state_awgn_or_not_materialized", ...
        'RuntimeChannelStartSample',first,'RuntimeChannelEndSample',stop);
    interferer=desired; interferer.ChannelModelApplied="TDL-C";
    interferer.ChannelFadingApplied=true;
    interferer.ChannelFadingExecutionStatus="applied_persistent_runtime_channel_object";
    links=[struct('ID',"desired",'TX',"desired_tx",'RX',"receiver",'Replay',desired), ...
        struct('ID',"interfering",'TX',"interferer_tx",'RX',"receiver",'Replay',interferer)];
    e=struct('Source',"composed_tx_retained_rf_per_link_channel_sum_receiver_noise_rf", ...
        'ApproximationMode',"none",'StartSample',first,'EndSampleExclusive',stop, ...
        'TX',struct('ID',{"desired_tx","interferer_tx"}), ...
        'RX',struct('ID',"receiver"),'Links',links,'SampleRateHz',30720000, ...
        'ConfigurationEpoch',"epoch1");
    segments{k}=struct('StartSample',first,'EndSampleExclusive',stop,'Execution',e);
end
replay=struct('TransmitterID',"desired_tx",'ReceiverID',"receiver", ...
    'RuntimeChannelStartSample',2,'RuntimeChannelEndSample',18, ...
    'ChannelFadingApplied',true,'ReceiveStreamExecutionSegments',{segments});
end
