function ok=testPiecewiseAWGNChannelArchive()
% Persisted v1/v2 readback of actual shared-owner piecewise coefficients.
% No practical decoder/performance claim. No additional channel execution
% occurs during either archive validation or the corruption probes.
[passed,originalRoot,row]=testPiecewiseAWGNChannelReference(); assert(passed);
original=sixgr.util.loadVerifiedMAT(fullfile(originalRoot,row.ChannelObservationMATFile), ...
    row.ChannelObservationMATFileSHA256,["ManifestJSON","Captures"]);
v1=sixgr.channel.validateSharedChannelObservationArtifact(originalRoot,row);
[payload,contract]=sixgr.channel.encodeCapturedChannelArchive(original.Captures,0);
assert(contract=="actual_shared_channel_observation/v2");
manifest=jsondecode(original.ManifestJSON); manifest.Contract=contract;
payload.ManifestJSON=string(jsonencode(manifest));
v2row=row;
v2row.ChannelObservationManifestJSON=payload.ManifestJSON;
v2row.ChannelObservationManifestSHA256=sixgr.phy.waveform.WaveformHash.bytes(payload.ManifestJSON);
v2row.ChannelObservationID="chobs_"+v2row.ChannelObservationManifestSHA256;
token="channel_observation_"+v2row.ChannelObservationManifestSHA256;
v2row.ChannelObservationMATFile="channel/mat/"+token+".mat";
v2row.ChannelObservationSegmentsCSV="channel/csv/"+token+"_segments.csv";
csv=sixgr.util.csvReadTable(fullfile(originalRoot,row.ChannelObservationSegmentsCSV),'TextType','string');
csv.ChannelObservationID(:)=v2row.ChannelObservationID;
csv.CoefficientMATFile(:)=v2row.ChannelObservationMATFile;
root=tempname; mkdir(root);
csvPath=fullfile(root,v2row.ChannelObservationSegmentsCSV);
matPath=fullfile(root,v2row.ChannelObservationMATFile);
sixgr.util.csvWriteTable(csvPath,csv,'PreserveSchema',true);
v2row.ChannelObservationSegmentsCSVSHA256=sixgr.phy.waveform.WaveformHash.file(csvPath);
v2row=localSave(v2row,matPath,payload);
v2=sixgr.channel.validateSharedChannelObservationArtifact(root,v2row);
assert(isequaln(v1.PathMeanCoefficientPower,v2.PathMeanCoefficientPower) && ...
    all(cellfun(@(e)~e.FullArrayLoaded && e.MaxBlockElements<=e.ReadBudgetElements,v2.PathGainReadEvidence)));
for k=1:numel(original.Captures)
    for sample=[1 size(original.Captures{k}.Reference.PathGains,1)]
        a=sixgr.channel.readChannelObservationSnapshot(originalRoot,row,k,sample);
        b=sixgr.channel.readChannelObservationSnapshot(root,v2row,k,sample);
        assert(isequaln(a,b));
    end
end
% A streamed block may select subsets of TX/RX and cross an episode edge.
r=original.Captures{end}.Reference;
indices={1:size(r.PathGains,1),1,[1 3],2};
assert(sixgr.channel.PiecewiseAWGNReference.blockValid(r,r.PathGains(indices{:}),indices));
piece=r.PathGains(indices{:}); piece(end)=piece(end)+1;
assert(~sixgr.channel.PiecewiseAWGNReference.blockValid(r,piece,indices));
% Rehashing the modified MAT must not bypass actual matrix/time checks.
bad=payload; bad.PathGains_000003(1)=bad.PathGains_000003(1)+1;
localReject(@()sixgr.channel.validateSharedChannelObservationArtifact(root, ...
    localSave(v2row,matPath,bad)),'sixgr:channel:ChannelArtifactSourceMismatch');
bad=payload; bad.CaptureMetadata{3}.Reference.OperatorSegments(1).Matrix(1)=19;
localReject(@()sixgr.channel.validateSharedChannelObservationArtifact(root, ...
    localSave(v2row,matPath,bad)),'sixgr:channel:ChannelArtifactSourceMismatch');
bad=payload; bad.CaptureMetadata{3}.Reference.SampleTimes_s(1)=1;
localReject(@()sixgr.channel.validateSharedChannelObservationArtifact(root, ...
    localSave(v2row,matPath,bad)),'sixgr:channel:ChannelArtifactSourceMismatch');
bad=payload; bad.CaptureMetadata{1}.Reference.OperatorExecutionStartSample=1;
localReject(@()sixgr.channel.validateSharedChannelObservationArtifact(root, ...
    localSave(v2row,matPath,bad)),'sixgr:channel:ChannelArtifactSourceMismatch');
bad=payload; bad.CaptureMetadata{2}.Reference.AppliedAWGNSpatialMatrixSHA256="not_the_executed_operator";
localReject(@()sixgr.channel.validateSharedChannelObservationArtifact(root, ...
    localSave(v2row,matPath,bad)),'sixgr:channel:ChannelArtifactSourceMismatch');
% Full execution metadata must not be replaced by cropped observation bounds.
bad=payload; bad.CaptureMetadata{1}.Reference.ExecutionStartSample= ...
    bad.CaptureMetadata{1}.Reference.StartSample;
localReject(@()sixgr.channel.validateSharedChannelObservationArtifact(root, ...
    localSave(v2row,matPath,bad)),'sixgr:channel:ChannelArtifactSegmentMismatch');
localSave(v2row,matPath,payload); % leave the temporary artifact valid
ok=true;
fprintf('PIECEWISE_AWGN_ARCHIVE_PASS actual_capture=1 v1_v2=1 streamed_corruption_guards=6 decoded_PHY=0\n');
end

function row=localSave(row,path,payload)
sixgr.util.matSave(path,payload,'ForceV73',true,'UseArtifactStore',false);
row.ChannelObservationMATFileSHA256=sixgr.phy.waveform.WaveformHash.file(path);
end

function localReject(action,id)
try, action(); catch cause
    assert(strcmp(cause.identifier,id),'Expected %s; got %s: %s',id,cause.identifier,cause.message);
    return;
end
error('test:ExpectedRejection','Expected %s.',id);
end
