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

fprintf(['Continuous Keysight package: sealed source hashes, shared MIMO ' ...
    'normalization, WIQ readback and 89600 MAT schema verified.\n']);
ok=true;
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
