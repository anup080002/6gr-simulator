function result=readSharedRejectedULReceiveResult(state,observationID)
% Explicit on-demand access to completed diagnostic receiver evidence.
records=sixgr.util.structGet(state,'SharedRejectedULReceiveResults',{});
hit=find(cellfun(@(r)string(r.ObservationID)==string(observationID),records));
assert(isscalar(hit),'sixgr:truth:RejectedULResultUnavailable','Require one completed observation identity.');
record=records{hit};
if isfield(record,'EvidenceMATFile')
    result=sixgr.truth.SharedReceiveOnlyEvidence.read(record,"Result");
else
    % Preserve genuine in-memory results in older diagnostic checkpoints;
    % this is not a substitute for an absent or damaged new archive.
    assert(isfield(record,'Receiver') && isfield(record,'Observation') && ...
        record.Observation.isComplete(),'sixgr:truth:RejectedULResultUnavailable');
    result=record;
end
end
