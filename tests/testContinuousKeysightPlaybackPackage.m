function ok=testContinuousKeysightPlaybackPackage()
%TESTCONTINUOUSKEYSIGHTPLAYBACKPACKAGE Exact continuous source conversion.

setup6GRSimToolkit('Verbose',false);
root=string(tempname)+"_continuous_keysight_source";
output=string(tempname)+"_continuous_keysight_output";
cleanup=onCleanup(@()localCleanup([root output])); %#ok<NASGU>
cfg=struct('channel',struct('fc_Hz',7e9), ...
    'rf',struct('configurationEpoch',3));
rec=sixgr.truth.RuntimeTxIQStreamRecorder(root,cfg,491.52e6);
nodes=[struct('ID',"gnb_1",'Direction',"DL",'NumPorts',2); ...
    struct('ID',"ue_1",'Direction',"UL",'NumPorts',1)];
t=(0:2047).';
gnb=[0.4*exp(1j*2*pi*t/31),0.2*exp(-1j*2*pi*t/47)];
ue=zeros(2048,1);
waves={gnb;ue};
replay=repmat(struct('Replay',struct()),2,1);
for endpoint=1:2
    replay(endpoint).Replay=struct('RFOutputWaveformSHA256', ...
        char(sixgr.rf.waveformSHA256(waves{endpoint})));
end
rec.appendBatch(nodes,waves,replay,0,2048);
rec.finalize(2048,1);

result=sixgr.truth.exportContinuousKeysightPlaybackPackage(root,output);
assert(result.Ok && result.EndpointCount==2 && result.PortArtifactCount==3);
manifest=result.ManifestTable;
assert(height(manifest)==3 && all(manifest.Status=="PASS") && ...
    ~any(manifest.ProxyUsed|manifest.FallbackFlag|manifest.PlaceholderFlag) && ...
    all(manifest.SampleCount==2048) && ...
    all(manifest.SampleRateHz==491.52e6) && ...
    all(manifest.CenterFrequencyHz==7e9) && ...
    all(manifest.KeysightInt16ClippedComponentCount==0));
assert(all(manifest.PlaybackInstrumentTargets=="M9484C|89600_VSA") && ...
    all(~manifest.KeysightWIQHasEmbeddedSampleRate) && ...
    all(manifest.RequiredBinaryImportFormat=="I16Little") && ...
    all(manifest.RequiredPlaybackSampleRateHz==manifest.SampleRateHz) && ...
    all(manifest.PhysicalInstrumentCapabilityVerified=="UNKNOWN") && ...
    all(manifest.StatusScope=="source_hash_and_digital_file_roundtrip_only"));
guide=string(fileread(result.InstrumentHandoffGuide));
assert(contains(guide,"Fs=491520000 Hz; Fc=7000000000 Hz; ports=2") && ...
    contains(guide,"XDelta=1/SampleRateHz seconds") && ...
    contains(guide,":SYSTem:WAVeform:BFILe:FORMat:DEFault I16Little") && ...
    contains(guide,"PHYSICAL INSTRUMENT CAPABILITY VERIFIED: UNKNOWN") && ...
    ~contains(guide,"STATe ON"), ...
    'Handoff must state clocks/import format without asserting hardware readiness or enabling RF.');
gnbRows=manifest(manifest.EndpointID=="gnb_1",:);
ueRow=manifest(manifest.EndpointID=="ue_1",:);
assert(height(gnbRows)==2 && height(ueRow)==1 && ...
    all(gnbRows.CommonEndpointNormalizationFullScale==0.4) && ...
    ueRow.CommonEndpointNormalizationFullScale==1 && ...
    ueRow.NormalizationPolicy=="identity_scale_for_exact_intentional_silence" && ...
    ueRow.NormalizedPeak==0);
for index=1:height(manifest)
    wiq=localChild(output,manifest.KeysightInt16(index));
    mat=localChild(output,manifest.KeysightVSAMAT(index));
    assert(isfile(wiq) && isfile(mat));
    info=dir(wiq);
    assert(info.bytes==2048*4);
    vars=string({whos('-file',mat).name});
    assert(all(ismember(["Y","XDelta","InputCenter","InputZoom","XDomain"],vars)));
end
localReject(@()sixgr.truth.exportContinuousKeysightPlaybackPackage(root,output), ...
    'sixgr:truth:ContinuousKeysightRefusesOverwrite');
localReject(@()sixgr.truth.exportContinuousKeysightPlaybackPackage(root, ...
    fullfile(root,'invalid_child')), ...
    'sixgr:truth:ContinuousKeysightPackageInsideSource');
localTest64PortHandoff();
localTestM9484SampleExtent();

fprintf(['Continuous Keysight package: sealed source hashes, shared MIMO ' ...
    'normalization, WIQ readback and 89600 MAT schema verified.\n']);
ok=true;
end

function localTest64PortHandoff()
% Export-only deterministic vectors, not a PHY/array qualification claim.
% Put the largest component on the last gNB port to exercise a common
% endpoint scale discovered across all ports, not per-port normalization.
root=string(tempname)+"_64port_keysight_source";
output=string(tempname)+"_64port_keysight_output";
corruptOutput=string(tempname)+"_64port_keysight_rejected";
cleanup=onCleanup(@()localCleanup([root output corruptOutput])); %#ok<NASGU>
cfg=struct('channel',struct('fc_Hz',4e9), ...
    'rf',struct('configurationEpoch',3));
fs=122.88e6;
rec=sixgr.truth.RuntimeTxIQStreamRecorder(root,cfg,fs);
nodes=[struct('ID',"gnb_1",'Direction',"DL",'NumPorts',64); ...
    struct('ID',"ue_1",'Direction',"UL",'NumPorts',4)];
t=(0:2047).';
gnb=single(exp(1j*2*pi*(t*(1:64))/257).*((1:64)/160));
ue=[.15*exp(1j*2*pi*t/29),.1j*exp(-1j*2*pi*t/37), ...
    -.05*exp(1j*2*pi*t/43),zeros(2048,1)];
waves={gnb;ue};
for block=0:1
    samples=cellfun(@(w)w(block*1024+(1:1024),:),waves,'UniformOutput',false);
    replay=repmat(struct('Replay',struct()),2,1);
    for endpoint=1:2
        replay(endpoint).Replay.RFOutputWaveformSHA256= ...
            char(sixgr.rf.waveformSHA256(samples{endpoint}));
    end
    rec.appendBatch(nodes,samples,replay,block*1024,(block+1)*1024);
end
sealed=rec.finalize(2048,2);
source=sixgr.util.csvReadTable(sealed.ManifestPath,'TextType','string');
result=sixgr.truth.exportContinuousKeysightPlaybackPackage(root,output);
assert(result.Ok && result.EndpointCount==2 && result.PortArtifactCount==68);
T=result.ManifestTable;
guide=string(fileread(result.InstrumentHandoffGuide));
assert(contains(guide,"Fs=122880000 Hz; Fc=4000000000 Hz; ports=64") && ...
    contains(guide,"Fs=122880000 Hz; Fc=4000000000 Hz; ports=4") && ...
    contains(guide,"A subset of 64 gNB ports is not an equivalent four-layer"));
for endpoint=1:2
    expectedWave=double(waves{endpoint});
    commonPeak=max(abs([real(expectedWave(:));imag(expectedWave(:))]));
    rows=T(T.EndpointID==string(nodes(endpoint).ID),:);
    assert(height(rows)==nodes(endpoint).NumPorts && ...
        all(rows.CommonEndpointNormalizationFullScale==commonPeak) && ...
        all(rows.SampleRateHz==fs) && all(rows.CenterFrequencyHz==4e9) && ...
        all(rows.CaptureStartSample==0) && all(rows.CaptureEndSampleExclusive==2048) && ...
        all(rows.SynchronizedPortCount==nodes(endpoint).NumPorts) && ...
        all(rows.KeysightInt16ClippedComponentCount==0));
    for port=1:nodes(endpoint).NumPorts
        row=rows(rows.PortIndex==port,:);
        expected=expectedWave(:,port)/commonPeak;
        iqCSV=readmatrix(localChild(output,row.KeysightCSV));
        assert(max(abs(complex(iqCSV(:,1),iqCSV(:,2))-expected))<1e-12);
        vsa=load(localChild(output,row.KeysightVSAMAT));
        assert(isequal(vsa.Y,single(expected)) && vsa.XDelta==1/fs && ...
            vsa.InputCenter==4e9 && vsa.InputZoom==1 && vsa.XDomain==2);
        fid=fopen(localChild(output,row.KeysightInt16),'rb','ieee-le');
        closeFile=onCleanup(@()fclose(fid));
        codes=fread(fid,[2 Inf],'int16=>int16');
        clear closeFile;
        expectedCodes=int16(round(32767*[real(expected).';imag(expected).']));
        assert(isequal(codes,expectedCodes), ...
            'Every physical port must preserve common-scale I/Q order and exact WIQ codes.');
        sourcePath=localChild(root,row.SourcePortFile);
        assert(strcmpi(sixgr.util.sha256File(sourcePath),row.SourcePortFileSHA256), ...
            'Playback conversion must not change source waveform bytes.');
    end
end
% A stale seal must still be rejected, including a non-first physical port.
sourceFiles=split(string(source.PortFiles(source.EndpointID=="gnb_1")),'|');
fid=fopen(localChild(root,sourceFiles(31)),'r+','ieee-le');
closeFile=onCleanup(@()fclose(fid));
fwrite(fid,single(123),'single');
clear closeFile;
localReject(@()sixgr.truth.exportContinuousKeysightPlaybackPackage(root,corruptOutput), ...
    'sixgr:truth:ContinuousKeysightSourceHashMismatch');
assert(~isfile(fullfile(corruptOutput,'waveform','csv', ...
    'continuous_keysight_playback_manifest.csv')));
end

function localTestM9484SampleExtent()
% VXG's documented 512-sample minimum / eight-sample quantum. Do not pad
% or repeat a physical capture to satisfy an instrument import constraint.
for sampleCount=[504 512 520 521]
    root=string(tempname)+"_vxg_extent_source";
    output=string(tempname)+"_vxg_extent_output";
    cleanup=onCleanup(@()localCleanup([root output]));
    cfg=struct('channel',struct('fc_Hz',4e9),'rf',struct('configurationEpoch',1));
    rec=sixgr.truth.RuntimeTxIQStreamRecorder(root,cfg,122.88e6);
    node=struct('ID',"gnb_1",'Direction',"DL",'NumPorts',1);
    wave=.3*exp(2i*pi*(0:sampleCount-1)'/17);
    replay=struct('Replay',struct('RFOutputWaveformSHA256', ...
        char(sixgr.rf.waveformSHA256(wave))));
    rec.appendBatch(node,{wave},replay,0,sampleCount);
    rec.finalize(sampleCount,1);
    if sampleCount<512 || mod(sampleCount,8)~=0
        localReject(@()sixgr.truth.exportContinuousKeysightPlaybackPackage(root,output), ...
            'sixgr:truth:ContinuousKeysightPlaybackDimensions');
    else
        result=sixgr.truth.exportContinuousKeysightPlaybackPackage(root,output);
        row=result.ManifestTable;
        wiqInfo=dir(localChild(output,row.KeysightInt16));
        assert(result.Ok && row.SampleCount==sampleCount && wiqInfo.bytes==4*sampleCount);
    end
    clear cleanup;
end
end

function pathValue=localChild(root,relative)
pathValue=fullfile(root,replace(string(relative),'/',filesep));
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

function localCleanup(paths)
for pathValue=reshape(string(paths),1,[])
    if isfolder(pathValue), rmdir(pathValue,'s'); end
end
end
