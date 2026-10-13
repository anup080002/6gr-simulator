function ok=testStreamedChannelArtifactValidation()
% Re-serialize an actually executed small operator to exercise the v2 reader.
% Not a full scenario or a fading/throughput qualification.
[passed,originalRoot,row]=testSharedIdentityAWGNRuntime(); assert(passed);
originalSnapshot=sixgr.channel.readChannelObservationSnapshot(originalRoot,row);
original=sixgr.util.loadVerifiedMAT(fullfile(originalRoot,row.ChannelObservationMATFile), ...
    row.ChannelObservationMATFileSHA256,["ManifestJSON","Captures"]);
[unchanged,v1]=sixgr.channel.encodeCapturedChannelArchive(original.Captures);
assert(v1=="actual_shared_channel_observation/v1" && isequaln(unchanged.Captures,original.Captures));
[payload,v2]=sixgr.channel.encodeCapturedChannelArchive(original.Captures,0);
assert(v2=="actual_shared_channel_observation/v2" && ~isfield(payload,'Captures'));
for k=1:numel(original.Captures)
    name=sprintf('PathGains_%06d',k);
    assert(isequaln(payload.(name),original.Captures{k}.Reference.PathGains));
end
m=jsondecode(original.ManifestJSON); m.Contract=v2;
payload.ManifestJSON=string(jsonencode(m));
row.ChannelObservationManifestJSON=payload.ManifestJSON;
row.ChannelObservationManifestSHA256=sixgr.phy.waveform.WaveformHash.bytes(payload.ManifestJSON);
row.ChannelObservationID="chobs_"+row.ChannelObservationManifestSHA256;
token="channel_observation_"+row.ChannelObservationManifestSHA256;
row.ChannelObservationMATFile="channel/mat/"+token+".mat";
row.ChannelObservationSegmentsCSV="channel/csv/"+token+"_segments.csv";
csv=sixgr.util.csvReadTable(fullfile(originalRoot,"channel/csv/channel_observation_"+ ...
    sixgr.phy.waveform.WaveformHash.bytes(original.ManifestJSON)+"_segments.csv"),'TextType','string');
csv.ChannelObservationID(:)=row.ChannelObservationID;
csv.CoefficientMATFile(:)=row.ChannelObservationMATFile;
parent=string(tempname)+"_streamed_channel_artifact"; mkdir(parent);
cleanup=onCleanup(@()rmdir(parent,'s')); %#ok<NASGU>
root=parent;
while strlength(fullfile(root,row.ChannelObservationMATFile))<=310
    root=fullfile(root,'long_channel_archive_readback');
end
matPath=fullfile(root,row.ChannelObservationMATFile);
csvPath=fullfile(root,row.ChannelObservationSegmentsCSV);
sixgr.util.csvWriteTable(csvPath,csv,'PreserveSchema',true);
row.ChannelObservationSegmentsCSVSHA256=sixgr.phy.waveform.WaveformHash.file(csvPath);
row=localSave(row,matPath,payload);
verified=sixgr.channel.validateSharedChannelObservationArtifact(root,row);
assert(verified.Manifest.Contract==v2 && all(cellfun(@(e) ...
    ~e.FullArrayLoaded && e.MaxBlockElements<=e.ReadBudgetElements,verified.PathGainReadEvidence)));
streamedSnapshot=sixgr.channel.readChannelObservationSnapshot(root,row);
assert(isequaln(streamedSnapshot,originalSnapshot), ...
    'The offline spatial audit must see identical time/port coefficients under either storage layout.');

% Recompute the outer file checksum: actual array/metadata checks must still
% detect corruption, not accept any file just because its hash was updated.
bad=payload; bad.PathGains_000001(1)=bad.PathGains_000001(1)+1;
badRow=localSave(row,matPath,bad);
localReject(@()sixgr.channel.validateSharedChannelObservationArtifact(root,badRow), ...
    'sixgr:channel:ChannelArtifactSourceMismatch');
bad=payload; bad.CaptureMetadata{1}.Reference.SampleTimes_s(1)=999;
badRow=localSave(row,matPath,bad);
localReject(@()sixgr.channel.validateSharedChannelObservationArtifact(root,badRow), ...
    'sixgr:channel:ChannelArtifactArrayMismatch');
bad=payload; bad.CaptureMetadata{1}.Reference.PathGainsVariable="PathGains_999999";
badRow=localSave(row,matPath,bad);
localReject(@()sixgr.channel.validateSharedChannelObservationArtifact(root,badRow), ...
    'sixgr:channel:ChannelArtifactArrayMismatch');
% The production threshold must select v2 for a genuinely large array. This
% is a storage-only fixture, deliberately not published as channel evidence.
large=original.Captures; large{1}.Reference.PathGains=zeros(8388609,1,'single');
[encoded,contract]=sixgr.channel.encodeCapturedChannelArchive(large);
assert(contract==v2 && numel(encoded.PathGains_000001)==8388609 && ...
    ~isfield(encoded.CaptureMetadata{1}.Reference,'PathGains'));
ok=true;
fprintf('STREAMED_CHANNEL_ARTIFACT_PASS exact_coefficients=1 long_path=1 corruption_guards=3\n');
end

function row=localSave(row,path,payload)
sixgr.util.matSave(path,payload,'ForceV73',true,'UseArtifactStore',false);
row.ChannelObservationMATFileSHA256=sixgr.phy.waveform.WaveformHash.file(path);
end

function localReject(action,identifier)
try
    action();
catch cause
    assert(strcmp(cause.identifier,identifier),'Expected %s, got %s.',identifier,cause.identifier);
    return;
end
error('test:ExpectedRejection','Expected %s.',identifier);
end
