function result = executeGrantPHYJob(job)
%EXECUTEGRANTPHYJOB Execute one worker-safe PHY grant job.
% Keep this file ASCII-only.

direction = upper(string(sixgr.util.structGet(job, "Direction", "DL")));
cfg = sixgr.util.structGet(job, "Cfg", struct());

args = { ...
    "NumFrames", max(1, round(double(sixgr.util.structGet(job, "NumFrames", 1)))), ...
    "SNR_dB", double(sixgr.util.structGet(job, "SNR_dB", NaN)), ...
    "InitialLinkAdaptationState", sixgr.util.structGet(job, "InitialLinkAdaptationState", struct()), ...
    "StartFrameIndex", double(sixgr.util.structGet(job, "StartFrameIndex", 1)), ...
    "StartSlotIndex", double(sixgr.util.structGet(job, "StartSlotIndex", 1)), ...
    "HARQContext", sixgr.util.structGet(job, "HARQContext", struct()), ...
    "PreviousCombinedLLR", sixgr.util.structGet(job, "PreviousCombinedLLR", []), ...
    "InterferenceBundle", sixgr.util.structGet(job, "InterferenceBundle", struct([]))};

transportBlockBits = sixgr.util.structGet(job, "TransportBlockBits", []);
if ~isempty(transportBlockBits)
    args = [args {"TransportBlockBits", transportBlockBits}]; %#ok<AGROW>
end
rv = sixgr.util.structGet(job, "RV", []);
if ~isempty(rv)
    args = [args {"RV", rv}]; %#ok<AGROW>
end
expectedUCIBits = sixgr.util.structGet(job, "ExpectedUCIBits", []);
if ~isempty(expectedUCIBits)
    args = [args {"ExpectedUCIBits", expectedUCIBits}]; %#ok<AGROW>
end
grant = sixgr.util.structGet(job, "GrantSnapshot", struct());
if isstruct(grant) && ~isempty(fieldnames(grant))
    args = [args {"GrantSnapshot", grant}]; %#ok<AGROW>
end

if direction == "UL"
    res = sixgr.link.runULPUSCHThroughput(cfg, args{:});
else
    res = sixgr.link.runDLPDSCHThroughput(cfg, args{:});
end

result = struct();
result.Direction = char(direction);
result.Frame = double(sixgr.util.structGet(job, "StartFrameIndex", NaN));
result.Slot = double(sixgr.util.structGet(job, "StartSlotIndex", NaN));
result.GrantContextId = char(string(sixgr.util.structGet(job, "GrantContextId", "")));
result.Result = res;
result.LinkAdaptationState = sixgr.util.structGet(res, "LinkAdaptationState", sixgr.util.structGet(job, "InitialLinkAdaptationState", struct()));
result.WorkerSafe = logical(sixgr.util.structGet(job, "WorkerSafe", true));
result.SharedStateCommitMode = char(string(sixgr.util.structGet(job, "SharedStateCommitMode", "serial_coordinator_commit")));
end
