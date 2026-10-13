function snapshot=readChannelObservationSnapshot(root,row,segmentIndex,sampleIndex)
%READCHANNELOBSERVATIONSNAPSHOT Exact frozen-time coefficients for diagnostics.
% Validates the complete archive first. A snapshot is not a full observation
% or a practical receiver channel estimate; no primary PHY row is created.
arguments
    root {mustBeTextScalar}
    row table
    segmentIndex (1,1) double {mustBeInteger,mustBePositive} = 1
    sampleIndex (1,1) double = NaN
end
v=sixgr.channel.validateSharedChannelObservationArtifact(root,row);
assert(segmentIndex<=numel(v.Manifest.Segments),'sixgr:channel:ChannelSnapshotIndex');
s=v.Manifest.Segments(segmentIndex);
ns=s.EndSampleExclusive-s.StartSample;
if isnan(sampleIndex), sampleIndex=max(1,round(ns/2)); end
assert(isfinite(sampleIndex) && sampleIndex==fix(sampleIndex) && sampleIndex>=1 && sampleIndex<=ns, ...
    'sixgr:channel:ChannelSnapshotIndex');
snapshot=sixgr.util.withVerifiedMAT(v.MATPath,row.ChannelObservationMATFileSHA256, ...
    @(path)localRead(path,v.Manifest.Contract,segmentIndex,sampleIndex,s));
end

function snapshot=localRead(path,contract,k,index,segment)
if string(contract)=="actual_shared_channel_observation/v2"
    saved=load(path,'CaptureMetadata'); r=saved.CaptureMetadata{k}.Reference;
    archive=matfile(path,'Writable',false);
    name=char(r.PathGainsVariable);
    dims=reshape(jsondecode(segment.PathGainDimensions),1,[]);
    gains=archive.(name)(index,1:dims(2),1:dims(3),1:dims(4));
else
    saved=load(path,'Captures'); r=saved.Captures{k}.Reference;
    gains=r.PathGains(index,:,:,:);
end
snapshot=struct('Scope',"exact_frozen_time_channel_snapshot_not_receiver_Hest", ...
    'PathGains',gains,'PathFilters',r.PathFilters, ...
    'SegmentIndex',k,'TimeIndexWithinSegment1Based',index, ...
    'AbsoluteSampleIndex',r.StartSample+index-1);
end
