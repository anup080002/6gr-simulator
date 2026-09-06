function result = executeGrantPHYJob(job)
%EXECUTEGRANTPHYJOB Execute one worker-safe PHY grant job.
% Keep this file ASCII-only.

job = localNormalizeHARQReplayJob(job);
direction = upper(string(sixgr.util.structGet(job, "Direction", "DL")));
assert(isscalar(direction) && any(direction==["DL","UL"]), ...
    'sixgr:truth:InvalidGrantDirection','A PHY job must explicitly resolve to DL or UL.');
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
expectedUCIPayload = sixgr.util.structGet(job, "ExpectedUCIPayload", []);
if ~isempty(expectedUCIPayload)
    if direction ~= "UL" || ~isa(expectedUCIPayload, ...
            "sixgr.phy.ul.pusch.PUSCHUCIPayload")
        error("sixgr:truth:InvalidGrantExpectedUCIPayload", ...
            "Only UL grant jobs may carry a typed PUSCHUCIPayload.");
    end
    args = [args {"ExpectedUCIPayload", expectedUCIPayload}]; %#ok<AGROW>
elseif ~isempty(expectedUCIBits)
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

executionProfile = strtrim(string(sixgr.util.structGet(job, ...
    "ExecutionProfile", "")));
if strlength(executionProfile) == 0
    error("sixgr:truth:MissingGrantPHYExecutionProfile", ...
        "%s grant PHY jobs require an explicit derived execution profile.", ...
        direction);
end
args = [args {"ExecutionProfile", char(executionProfile)}]; %#ok<AGROW>
prepareOnly=sixgr.util.structGet(job,'PrepareOnly',false);
receivedContext=sixgr.util.structGet(job,'ReceivedContext',struct());
args=[args {'PrepareOnly',prepareOnly,'ReceivedContext',receivedContext}];
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
% Readiness means a real receive attempt can be committed, not that CRC or
% qualification passed. A failed CRC remains genuine receiver evidence.
result.ReadyForReceiverCommit = ~prepareOnly && ...
    istable(sixgr.util.structGet(res,'TrialTable',[])) && ~isempty(res.TrialTable);
if prepareOnly
    assert(string(sixgr.util.structGet(res,'ExecutionStage',''))=="transmit_prepared_not_received" && ...
        isempty(res.TrialTable) && ~res.Ok, ...
        'sixgr:truth:PreparedGrantClaimedReception','A prepared waveform is not a completed PHY trial.');
    result.LinkAdaptationState=sixgr.util.structGet(job,'InitialLinkAdaptationState',[]);
    result.ChannelState=channelState;
end
end

function job = localNormalizeHARQReplayJob(job)
if ~(isstruct(job) && ~isempty(fieldnames(job)))
    return;
end
harqContext = sixgr.util.structGet(job, "HARQContext", struct());
tbBits = sixgr.util.structGet(job, "TransportBlockBits", []);
replayBits = double(numel(tbBits));
tbContext = localReplayTBContext(job);
resolvedTBSBits = double(sixgr.util.structGet(tbContext, "TBSBits", NaN));
grant = sixgr.util.structGet(job, "GrantSnapshot", struct());
isRetx = sixgr.phy.grant.isExplicitHARQRetransmission( ...
    grant, sixgr.util.structGet(grant, "PHYGrant", struct()), harqContext);
if ~(isRetx && ((isfinite(replayBits) && replayBits > 0) || (isfinite(resolvedTBSBits) && resolvedTBSBits > 0)))
    return;
end
if ~(isfinite(resolvedTBSBits) && resolvedTBSBits > 0)
    resolvedTBSBits = double(replayBits);
elseif isfinite(replayBits) && replayBits > 0 && round(resolvedTBSBits) ~= round(replayBits)
    error("sixgr:truth:HARQReplayJobTBSMismatch", ...
        "HARQ replay job context TBSBits=%d does not match stored TB bits=%d.", ...
        round(resolvedTBSBits), round(replayBits));
end
harqContext.IsRetransmission = true;
if ~isstruct(grant)
    grant = struct();
end
harq = sixgr.util.structGet(grant, "HARQ", struct());
if ~isstruct(harq)
    harq = struct();
end
harq.IsRetransmission = true;
copyFields = ["HARQProcess","HarqID","RV","NDI","NDIEpoch","CodewordIndex","TBIdentity"];
for i = 1:numel(copyFields)
    f = char(copyFields(i));
    v = sixgr.util.structGet(harqContext, f, []);
    if ~isempty(v)
        harq.(f) = v;
    end
end
if isstruct(tbContext) && ~isempty(fieldnames(tbContext))
    if ~isfield(harq, "NDI") || isempty(harq.NDI)
        harq.NDI = logical(sixgr.util.structGet(tbContext, "NDI", false));
    end
    if ~isfield(harq, "NDIEpoch") || ~(isfinite(double(sixgr.util.structGet(harq, "NDIEpoch", NaN))))
        harq.NDIEpoch = double(sixgr.util.structGet(tbContext, "NDIEpoch", NaN));
    end
    if ~isfield(harq, "HarqID") || ~(isfinite(double(sixgr.util.structGet(harq, "HarqID", NaN))))
        harq.HarqID = double(sixgr.util.structGet(tbContext, "HARQProcessId", NaN));
    end
    if ~isfield(harq, "HARQProcess") || ~(isfinite(double(sixgr.util.structGet(harq, "HARQProcess", NaN))))
        harq.HARQProcess = double(sixgr.util.structGet(tbContext, "HARQProcessId", NaN));
    end
end
grant.HARQ = harq;
grant.IsRetransmission = true;
if isstruct(tbContext) && ~isempty(fieldnames(tbContext))
    grant.HARQTBContext = tbContext;
    job.HARQContext.TransportBlockContext = tbContext;
    job.HARQContext.HARQTBContext = tbContext;
end
grant.TransportBlockSize = double(resolvedTBSBits);
grant.TBSBits = double(resolvedTBSBits);
grant.TBSBytes = floor(double(resolvedTBSBits) / 8);
grant.ScheduledTransportBlockSize = double(resolvedTBSBits);

phyGrant = sixgr.util.structGet(job, "PHYGrant", sixgr.util.structGet(grant, "PHYGrant", struct()));
phyTBS = double(sixgr.util.structGet(phyGrant, "CodingLayout.TBSBits", NaN));
phyRetx = sixgr.util.logicalAny(sixgr.util.structGet(phyGrant, "HARQProcessKey.IsRetransmission", false));
needsFreeze = ~(isstruct(phyGrant) && ~isempty(fieldnames(phyGrant)) && ...
    logical(sixgr.util.structGet(phyGrant, "IsFrozen", false)) && ...
    isfinite(phyTBS) && round(phyTBS) == round(resolvedTBSBits) && phyRetx);
if needsFreeze
    if isfield(grant, "PHYGrant") && ~(isstruct(tbContext) && ~isempty(fieldnames(tbContext)))
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

function tbContext = localReplayTBContext(job)
tbContext = struct();
if nargin < 1 || ~isstruct(job)
    return;
end
grant = sixgr.util.structGet(job, "GrantSnapshot", struct());
harqContext = sixgr.util.structGet(job, "HARQContext", struct());
candidates = { ...
    sixgr.util.structGet(harqContext, "TransportBlockContext", struct()), ...
    sixgr.util.structGet(harqContext, "HARQTBContext", struct()), ...
    sixgr.util.structGet(grant, "HARQTBContext", struct())};
for i = 1:numel(candidates)
    candidate = candidates{i};
    if isstruct(candidate) && ~isempty(fieldnames(candidate))
        tbContext = candidate;
        return;
    end
end
end
