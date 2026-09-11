function T=bindSharedRFExecutionEvidence(T,planes)
% Post-decode export of actual retained RF executions and captured IQ.
% Segment manifest hashes and waveform-content hashes have separate fields.
assert(istable(T) && height(T)==1,'sixgr:truth:RFTrialScope', ...
    'Bind one completed shared PHY attempt at a time.');
ids=string({planes.ReceiverID});
itx=find(endsWith(ids,':tx')); ipre=find(endsWith(ids,':pre_rf')); ipost=find(endsWith(ids,':post_rf'));
assert(isscalar(itx) && isscalar(ipre) && isscalar(ipost), ...
    'sixgr:truth:RFObservationPlanes','One physical TX, pre-RF RX and post-RF RX capture are required.');
tx=planes(itx).Observation; pre=planes(ipre).Observation; post=planes(ipost).Observation;
assert(tx.isComplete() && pre.isComplete() && post.isComplete() && ...
    pre.StartSample==post.StartSample && pre.EndSampleExclusive==post.EndSampleExclusive && ...
    pre.SampleRateHz==post.SampleRateHz && tx.SampleRateHz==post.SampleRateHz, ...
    'sixgr:truth:RFObservationClock','RX before/after RF must share the actual capture clock.');
txRecords=localRecords(planes(itx),extractBefore(ids(itx),':tx'),'TX');
rxRecords=localRecords(planes(ipost),extractBefore(ids(ipost),':post_rf'),'RX');
T.RxRFInputWaveformSHA256=string(sixgr.rf.waveformSHA256(pre.readComplete()));
T.RxRFOutputWaveformSHA256=string(sixgr.rf.waveformSHA256(post.readComplete()));
T.TxRFOutputWaveformSHA256=string(sixgr.rf.waveformSHA256(tx.readComplete()));
txEvidence=struct('NodeID',extractBefore(ids(itx),':tx'), ...
    'CaptureStartSample',tx.StartSample,'CaptureEndSampleExclusive',tx.EndSampleExclusive, ...
    'OutputWaveformSHA256',T.TxRFOutputWaveformSHA256,'ExecutedSegments',txRecords);
rxEvidence=struct('NodeID',extractBefore(ids(ipost),':post_rf'), ...
    'CaptureStartSample',post.StartSample,'CaptureEndSampleExclusive',post.EndSampleExclusive, ...
    'InputWaveformSHA256',T.RxRFInputWaveformSHA256, ...
    'OutputWaveformSHA256',T.RxRFOutputWaveformSHA256,'ExecutedSegments',rxRecords);
manifest=struct('Contract',"actual_shared_rf_observation/v1", ...
    'SampleRateHz',post.SampleRateHz,'TX',txEvidence,'RX',rxEvidence);
T.RFExecutionManifestJSON=string(jsonencode(manifest));
T.RFExecutionManifestSHA256=localHash(T.RFExecutionManifestJSON);
T.RFImpairmentChainId="rfpath_"+T.RFExecutionManifestSHA256;
T.RxRFImpairmentChainId="rfobs_"+localHash(jsonencode(rxEvidence));
T.RFStrictOk=all([txRecords.RFStrictOk]) && all([rxRecords.RFStrictOk]);
T.RFExecutionEvidenceSource="actual_captured_IQ_and_ordered_retained_RF_execution_segments";
T.RxRFStreamStartSample=post.StartSample;
T.RxRFStreamEndSampleExclusive=post.EndSampleExclusive;
T.TxRFStreamStartSample=tx.StartSample;
T.TxRFStreamEndSampleExclusive=tx.EndSampleExclusive;
for endpoint=["Tx","Rx"]
    if endpoint=="Tx", records=txRecords; else, records=rxRecords; end
    for field=["RFStageOrder","RFConfiguredStageCount","RFExecutedStageCount"]
        values={records.(field)};
        assert(all(cellfun(@(v)isequaln(v,values{1}),values)), ...
            'sixgr:truth:RFConfigurationChangedWithinCapture', ...
            'Do not flatten different RF configuration epochs within one capture.');
        T.(endpoint+field)=values{1};
    end
    changedCounts=[records.RFAppliedStageCount];
    T.(endpoint+"RFAppliedStageCount")=NaN;
    T.(endpoint+"RFAppliedStageCountStatus")="time_varying_per_execution_segment";
    if all(changedCounts==changedCounts(1))
        T.(endpoint+"RFAppliedStageCount")=changedCounts(1);
        T.(endpoint+"RFAppliedStageCountStatus")="stationary_per_execution_segment";
    end
end
end

function records=localRecords(plane,nodeID,endpoint)
segments=plane.Segments; observation=plane.Observation;
assert(~isempty(segments),'sixgr:truth:MissingRFExecution','RF execution segments are required.');
records=struct([]); intervals=zeros(numel(segments),2);
fields={'RFStreamStartSample','RFStreamEndSampleExclusive','RFConfigurationEpoch', ...
    'RFProcessingMode','RFImpairmentChainId','RFInputWaveformSHA256','RFOutputWaveformSHA256', ...
    'RFStageOrder','RFConfiguredStageCount','RFAppliedStageCount','RFExecutedStageCount','RFStrictOk','RFFailureReason'};
for k=1:numel(segments)
    e=segments{k}.Execution; nodes=e.(endpoint);
    node=nodes(string({nodes.ID})==nodeID);
    assert(isscalar(node) && all(isfield(node.Replay,fields)), ...
        'sixgr:truth:MissingRFExecution','Each interval must retain the actual endpoint RF result.');
    r=struct();
    for f=fields, r.(f{1})=node.Replay.(f{1}); end
    assert(string(r.RFProcessingMode)=="retained_sample_stream" && ...
        r.RFStreamStartSample==e.StartSample && r.RFStreamEndSampleExclusive==e.EndSampleExclusive && ...
        localIsHash(r.RFInputWaveformSHA256) && localIsHash(r.RFOutputWaveformSHA256), ...
        'sixgr:truth:RFExecutionClockMismatch','RF hashes must describe the executed physical interval.');
    intervals(k,:)=[r.RFStreamStartSample r.RFStreamEndSampleExclusive];
    if k==1, records=r; else, records(k)=r; end %#ok<AGROW>
end
assert(intervals(1,1)<=observation.StartSample && intervals(end,2)>=observation.EndSampleExclusive && ...
    all(intervals(2:end,1)==intervals(1:end-1,2)), ...
    'sixgr:truth:RFExecutionCoverageGap','No missing, reordered or overlapping RF processor intervals are permitted.');
end

function yes=localIsHash(value)
yes=isscalar(string(value)) && ~isempty(regexp(char(string(value)),'^[0-9a-fA-F]{64}$','once'));
end
function hash=localHash(value)
hash=string(sixgr.util.sha256Hex(uint8(unicode2native(char(value),'UTF-8'))));
end
