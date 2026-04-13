function markRunStatus(statusText, statusPayload)
if nargin < 2
    statusPayload = struct();
end
sixgr.db.artifactStore("mark_status", statusText, statusPayload);
end
