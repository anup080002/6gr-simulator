function result = executeGrantPHYJob(job)
%EXECUTEGRANTPHYJOB Execute one worker-safe PHY grant job.
% Keep this file ASCII-only.

job = localNormalizeHARQReplayJob(job);
direction = upper(string(sixgr.util.structGet(job, "Direction", "DL")));
cfg = sixgr.util.structGet(job, "Cfg", struct());
interferenceBundle = sixgr.util.structGet(job, "InterferenceBundle", struct([]));
sixgr.truth.CoupledTruthRuntime.assertSharedSlotInterferenceBundle(interferenceBundle, "executeGrantPHYJob");

args = { ...
    "NumFrames", max(1, round(double(sixgr.util.structGet(job, "NumFrames", 1)))), ...
    "SNR_dB", double(sixgr.util.structGet(job, "SNR_dB", NaN)), ...
    "InitialLinkAdaptationState", sixgr.util.structGet(job, "InitialLinkAdaptationState", struct()), ...
    "StartFrameIndex", double(sixgr.util.structGet(job, "StartFrameIndex", 1)), ...
    "StartSlotIndex", double(sixgr.util.structGet(job, "StartSlotIndex", 1)), ...
    "HARQContext", sixgr.util.structGet(job, "HARQContext", struct()), ...
    "PreviousCombinedLLR", sixgr.util.structGet(job, "PreviousCombinedLLR", []), ...
    "InterferenceBundle", interferenceBundle};
channelState = sixgr.util.structGet(job, "ChannelState", struct());
if isstruct(channelState) && isfield(channelState, "ContractVersion")
    args = [args {"ChannelState", channelState}]; %#ok<AGROW>
end

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
phyGrant = sixgr.util.structGet(job, "PHYGrant", sixgr.util.structGet(grant, "PHYGrant", struct()));
if isstruct(phyGrant) && ~isempty(fieldnames(phyGrant))
    sixgr.phy.grant.assertPHYGrantDimensions(phyGrant, "execute_grant_phy_job");
    args = [args {"PHYGrant", phyGrant}]; %#ok<AGROW>
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
result.PHYGrant = phyGrant;
result.Result = res;
result.LinkAdaptationState = sixgr.util.structGet(res, "LinkAdaptationState", sixgr.util.structGet(job, "InitialLinkAdaptationState", struct()));
result.ChannelState = sixgr.util.structGet(res, "ChannelState", channelState);
result.WorkerSafe = logical(sixgr.util.structGet(job, "WorkerSafe", true));
result.SharedStateCommitMode = char(string(sixgr.util.structGet(job, "SharedStateCommitMode", "serial_coordinator_commit")));
end

function job = localNormalizeHARQReplayJob(job)
if ~(isstruct(job) && ~isempty(fieldnames(job)))
    return;
end
harqContext = sixgr.util.structGet(job, "HARQContext", struct());
tbBits = sixgr.util.structGet(job, "TransportBlockBits", []);
replayBits = double(numel(tbBits));
if ~(isstruct(harqContext) && logical(sixgr.util.structGet(harqContext, "IsRetransmission", false)) && ...
        isfinite(replayBits) && replayBits > 0)
    return;
end
grant = sixgr.util.structGet(job, "GrantSnapshot", struct());
if ~isstruct(grant)
    grant = struct();
end
harq = sixgr.util.structGet(grant, "HARQ", struct());
if ~isstruct(harq)
    harq = struct();
end
harq.IsRetransmission = true;
copyFields = ["HARQProcess","HarqID","RV","NDI","CodewordIndex","TBIdentity"];
for i = 1:numel(copyFields)
    f = char(copyFields(i));
    v = sixgr.util.structGet(harqContext, f, []);
    if ~isempty(v)
        harq.(f) = v;
    end
end
grant.HARQ = harq;
grant.IsRetransmission = true;
grant.TransportBlockSize = double(replayBits);
grant.TBSBits = double(replayBits);
grant.TBSBytes = floor(double(replayBits) / 8);
grant.ScheduledTransportBlockSize = double(replayBits);

phyGrant = sixgr.util.structGet(job, "PHYGrant", sixgr.util.structGet(grant, "PHYGrant", struct()));
phyTBS = double(sixgr.util.structGet(phyGrant, "CodingLayout.TBSBits", NaN));
phyRetx = logical(sixgr.util.structGet(phyGrant, "HARQProcessKey.IsRetransmission", false));
needsFreeze = ~(isstruct(phyGrant) && ~isempty(fieldnames(phyGrant)) && ...
    logical(sixgr.util.structGet(phyGrant, "IsFrozen", false)) && ...
    isfinite(phyTBS) && round(phyTBS) == round(replayBits) && phyRetx);
if needsFreeze
    if isfield(grant, "PHYGrant")
        grant = rmfield(grant, "PHYGrant");
    end
    direction = upper(string(sixgr.util.structGet(job, "Direction", sixgr.util.structGet(grant, "Direction", "DL"))));
    cfg = sixgr.util.structGet(job, "Cfg", struct());
    phyGrant = sixgr.phy.grant.freezePHYGrant(cfg, direction, grant, ...
        "SNR_dB", double(sixgr.util.structGet(job, "SNR_dB", NaN)), ...
        "Frame", double(sixgr.util.structGet(job, "StartFrameIndex", sixgr.util.structGet(grant, "Frame", NaN))), ...
        "Slot", double(sixgr.util.structGet(job, "StartSlotIndex", sixgr.util.structGet(grant, "Slot", NaN))), ...
        "HARQContext", harqContext);
end
grant.PHYGrant = phyGrant;
grant.PHYGrantContextId = char(string(phyGrant.GrantContextId));
job.GrantSnapshot = grant;
job.PHYGrant = phyGrant;
end
