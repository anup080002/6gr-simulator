function [payload,contract]=encodeCapturedChannelArchive(captures,maxNestedElements)
%ENCODECAPTUREDCHANNELARCHIVE Preserve exact arrays, make large ones sliceable.
% Small archives retain v1 compatibility. V2 lifts PathGains out of nested
% cells/structs, which MATLAB cannot partially index from MAT files. Numeric
% assignments are copy-on-write; no whole-tensor concatenation or conversion.
arguments
    captures cell
    maxNestedElements (1,1) double {mustBeInteger,mustBeNonnegative} = 8388608
end
count=sum(cellfun(@(c)numel(c.Reference.PathGains),captures));
contract="actual_shared_channel_observation/v1";
payload=struct('Captures',{captures});
if count<=maxNestedElements, return; end
contract="actual_shared_channel_observation/v2";
metadata=captures;
payload=struct;
for k=1:numel(captures)
    name=string(sprintf('PathGains_%06d',k));
    payload.(name)=captures{k}.Reference.PathGains;
    metadata{k}.Reference=rmfield(metadata{k}.Reference,'PathGains');
    metadata{k}.Reference.PathGainsVariable=name;
end
payload.CaptureMetadata=metadata;
end
