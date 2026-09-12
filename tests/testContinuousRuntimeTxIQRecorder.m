function ok=testContinuousRuntimeTxIQRecorder()
%TESTCONTINUOUSRUNTIMETXIQRECORDER Exact disk stream and seal contract.

setup6GRSimToolkit('Verbose',false);
root=string(tempname)+"_continuous_iq";
cleanup=onCleanup(@()localCleanup(root)); %#ok<NASGU>
cfg=struct('channel',struct('fc_Hz',3.5e9), ...
    'rf',struct('configurationEpoch',0));
rec=sixgr.truth.RuntimeTxIQStreamRecorder(root,cfg,30.72e6);
nodes=[struct('ID',"gnb_1",'Direction',"DL",'NumPorts',2); ...
    struct('ID',"ue_1",'Direction',"UL",'NumPorts',1)];
t=(0:15).';
dl=[0.25*exp(1j*2*pi*t/8),0.5*exp(-1j*2*pi*t/5)];
ul=0.125*exp(1j*2*pi*t/7);
for batch=1:2
    first=(batch-1)*8;
    stop=batch*8;
    index=(first+1):stop;
    waves={dl(index,:);ul(index,:)};
    replay=repmat(struct('Replay',struct()),2,1);
    for endpoint=1:2
        replay(endpoint).Replay=struct('RFOutputWaveformSHA256', ...
            char(sixgr.rf.waveformSHA256(waves{endpoint})));
    end
    rec.appendBatch(nodes,waves,replay,first,stop);
end
out=rec.finalize(16,2);
assert(out.Ok && out.SampleCount==16 && out.EndpointCount==2);
manifest=out.ManifestTable;
segments=out.SegmentTable;
assert(height(manifest)==2 && height(segments)==4 && ...
    all(manifest.CaptureStatus=="PASS") && ...
    all(manifest.ContinuousCoverage) && ...
    all(manifest.AllSchedulerSamplesIncluded) && ...
    all(manifest.ApproximationMode=="none") && ...
    ~any(manifest.ProxyUsed|manifest.FallbackFlag|manifest.PlaceholderFlag) && ...
    all(segments.RFHashExactMatch));
localAssertEndpoint(root,manifest(manifest.EndpointID=="gnb_1",:),dl);
localAssertEndpoint(root,manifest(manifest.EndpointID=="ue_1",:),ul);

slotCountRoot=string(tempname)+"_continuous_iq_slot_count";
cleanupSlotCount=onCleanup(@()localCleanup(slotCountRoot)); %#ok<NASGU>
slotCount=sixgr.truth.RuntimeTxIQStreamRecorder( ...
    slotCountRoot,cfg,30.72e6);
waves={dl;ul};
replay=repmat(struct('Replay',struct()),2,1);
for endpoint=1:2
    replay(endpoint).Replay=struct('RFOutputWaveformSHA256', ...
        char(sixgr.rf.waveformSHA256(waves{endpoint})));
end
slotCount.appendBatch(nodes,waves,replay,0,16);
localReject(@()slotCount.finalize(16,2), ...
    'sixgr:truth:ContinuousTxIQCoverageGap');
assert(~isfile(fullfile(slotCountRoot,'waveform','csv', ...
    'continuous_tx_iq_capture_manifest.csv')));

incompleteRoot=string(tempname)+"_continuous_iq_incomplete";
cleanupIncomplete=onCleanup(@()localCleanup(incompleteRoot)); %#ok<NASGU>
incomplete=sixgr.truth.RuntimeTxIQStreamRecorder( ...
    incompleteRoot,cfg,30.72e6);
waves={dl(1:8,:);ul(1:8,:)};
replay=repmat(struct('Replay',struct()),2,1);
for endpoint=1:2
    replay(endpoint).Replay=struct('RFOutputWaveformSHA256', ...
        char(sixgr.rf.waveformSHA256(waves{endpoint})));
end
incomplete.appendBatch(nodes,waves,replay,0,8);
localReject(@()incomplete.finalize(16,2), ...
    'sixgr:truth:ContinuousTxIQHorizonIncomplete');
assert(~isfile(fullfile(incompleteRoot,'waveform','csv', ...
    'continuous_tx_iq_capture_manifest.csv')));

fprintf(['Continuous runtime Tx-IQ recorder: exact per-port binary, RF hash ' ...
    'binding, contiguous horizon and fail-closed sealing verified.\n']);
ok=true;
end

function localAssertEndpoint(root,row,expected)
assert(height(row)==1 && row.SampleCountPerPort==size(expected,1) && ...
    row.PortCount==size(expected,2));
paths=split(string(row.PortFiles),'|');
assert(numel(paths)==size(expected,2));
for port=1:numel(paths)
    pathValue=fullfile(root,replace(paths(port),'/',filesep));
    fid=fopen(pathValue,'rb','ieee-le');
    assert(fid>=0);
    closeFile=onCleanup(@()fclose(fid)); %#ok<NASGU>
    values=fread(fid,Inf,'double=>double');
    clear closeFile;
    observed=complex(values(1:2:end),values(2:2:end));
    assert(isequal(observed,expected(:,port)));
end
end

function localReject(fn,identifier)
try
    fn();
catch cause
    assert(strcmp(cause.identifier,identifier),cause.message);
    return;
end
error('test:MissingExpectedRejection','Expected %s.',identifier);
end

function localCleanup(pathValue)
if isfolder(pathValue)
    rmdir(pathValue,'s');
end
end
