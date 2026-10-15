function T=diagnoseRetainedRARFObservations(captureFiles,outputFolder)
% Re-publish actual retained RF metadata as a separate offline audit. Never
% rerun RF/channel/decoder, change original results, or infer message success.
setup6GRSimToolkit('Verbose',false);
T=table();
for file=reshape(string(captureFiles),1,[])
    assert(isfile(file),'Retained physical capture is missing: %s',file);
    hash=string(sixgr.util.sha256File(file));
    loaded=load(file,'capture'); c=loaded.capture;
    assert(startsWith(string(c.Source),'actual_shared_physical_'));
    replay=c.ExecutionReplay;
    tx=string(replay.TransmitterID); rx=string(replay.ReceiverID);
    if startsWith(tx,'gnb_')
        cellIndex=str2double(extractAfter(tx,'gnb_'));
        ueIndex=str2double(extractBefore(extractAfter(rx,'ue_'),'_rx'));
    else
        ueIndex=str2double(extractAfter(tx,'ue_'));
        cellIndex=str2double(extractBefore(extractAfter(rx,'gnb_'),'_rx'));
    end
    segments=replay.ReceiveStreamExecutionSegments;
    planes=[localPlane(c.TXAfterRF,tx+":tx",c,segments), ...
        localPlane(c.RXBeforeRF,rx+":pre_rf",c,segments), ...
        localPlane(c.RXAfterRF,rx+":post_rf",c,segments)];
    item=struct('ID',"offline_capture_"+hash,'UE',ueIndex,'Planes',planes);
    if isfield(c,'Prepared')
        assert(string(c.Source)=="actual_shared_physical_RA_stage_observation");
        item.Kind="RA"; item.Context=struct('Prepared',c.Prepared);
        ra=c.ReceiverContinuation.RAConfig;
    else
        if string(c.Source)=="actual_shared_physical_RAR_monitoring", item.Kind="RAR";
        elseif string(c.Source)=="actual_shared_physical_Contention_monitoring", item.Kind="Contention";
        else, error('test:UnknownCapture','Unknown retained physical observation source.'); end
        item.Context=c.Context;
        r=c.ReceiverObservation;
        assert(height(r)==1,'One retained receive-window result is required.');
        ra=struct('RunId',r.RunId,'UEId',r.UEId,'AttemptId',r.AttemptId);
    end
    configured=nan(numel(segments),1);
    for k=1:numel(segments)
        endpoints=segments{k}.Execution.RX;
        endpoint=endpoints(string({endpoints.ID})==rx);
        assert(isscalar(endpoint));
        configured(k)=endpoint.Replay.RequestedAWGNReferenceSNR_dB;
    end
    assert(all(isfinite(configured)) && all(configured==configured(1)), ...
        'Do not infer a fixed reference-SNR point from a filename or waveform power.');
    row=sixgr.truth.buildRAReceiverRFObservation(item,ra,cellIndex,configured(1),c.EndSampleExclusive);
    row.AuditMode="offline_republication_of_retained_RF_execution_no_new_RF_or_PHY";
    row.SourceCapturePath=file; row.SourceCaptureSHA256=hash;
    row.CurrentSourceIntegratedAcceptance=false;
    T=[T;row]; %#ok<AGROW>
    fprintf('RETAINED_RA_RF stage=%s direction=%s TX=%s RX=%s DAC=%g IQ=%g ADC=%g\n', ...
        row.StageName,row.Direction,row.TransmitterID,row.ReceiverID, ...
        row.DACFullScale,row.IQImbalanceApplied,row.ADCBits);
    clear loaded c replay planes segments
end
sixgr.util.ensureFolder(outputFolder);
sixgr.util.csvWriteTable(fullfile(outputFolder,'retained_ra_receiver_rf_observations.csv'), ...
    T,'PreserveSchema',true);
fprintf('RETAINED_RA_RF_AUDIT_COMPLETE rows=%d output=%s\n',height(T),outputFolder);
end
function plane=localPlane(wave,id,c,segments)
assert(size(wave,1)==c.EndSampleExclusive-c.StartSample);
o=sixgr.phy.waveform.WaveformObservationBuffer(c.StartSample,c.EndSampleExclusive,c.SampleRateHz,size(wave,2));
o.append(sixgr.phy.waveform.WaveformChunk(wave,c.StartSample),c.SampleRateHz);
plane=struct('ReceiverID',id,'Observation',o,'Segments',{segments});
end
