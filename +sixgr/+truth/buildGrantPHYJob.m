function job = buildGrantPHYJob(cfg, direction, snr_dB, frameIdx, laStateIn, trialContext)
%BUILDGRANTPHYJOB Build a worker-safe payload for one PHY grant execution.
% Keep this file ASCII-only.

if nargin < 6 || ~isstruct(trialContext)
    trialContext = struct();
end

grant = sixgr.util.structGet(trialContext, "GrantSnapshot", struct());
grant = localNormalizeGrantPrecodingForFreeze(grant, direction);
grant = localApplyHARQReplayContract(grant, trialContext);
isReplay = localIsHARQReplay(trialContext);
grantSlotIdx = double(sixgr.util.structGet(grant, "Slot", frameIdx));
if isstruct(grant) && ~isempty(fieldnames(grant))
    scheduler = sixgr.l2.mac.SchedulerPF(cfg, "Direction", char(upper(string(direction))));
    if ~isfield(grant, "DCI") || ~isstruct(grant.DCI) || isempty(fieldnames(grant.DCI))
        grant.DCI = scheduler.buildDCIBitfield(grant);
    end
end
if isReplay
    phyGrant = sixgr.util.structGet(grant, "PHYGrant", struct());
else
    phyGrant = sixgr.util.structGet(trialContext, "PHYGrant", ...
        sixgr.util.structGet(grant, "PHYGrant", struct()));
end
if ~(isstruct(phyGrant) && ~isempty(fieldnames(phyGrant)) && ...
        logical(sixgr.util.structGet(phyGrant, "IsFrozen", false)))
    if isReplay
        grant = localApplyHARQReplayContract(grant, trialContext);
        phyGrant = sixgr.phy.grant.freezePHYGrant(cfg, direction, grant, ...
            "SNR_dB", snr_dB, ...
            "Frame", frameIdx, ...
            "Slot", grantSlotIdx, ...
            "HARQContext", sixgr.util.structGet(trialContext, "HARQContext", struct()));
    else
        phyGrant = struct();
        if isfield(grant, "PHYGrant")
            grant = rmfield(grant, "PHYGrant");
        end
        if isfield(grant, "PHYGrantContextId")
            grant.PHYGrantContextId = "";
        end
    end
end
localAssertHARQReplayPHYGrant(phyGrant, trialContext);
if isstruct(phyGrant) && ~isempty(fieldnames(phyGrant))
    grant.PHYGrant = phyGrant;
    grant.PHYGrantContextId = char(string(phyGrant.GrantContextId));
end

job = struct();
job.Cfg = cfg;
job.Direction = upper(string(direction));
job.NumFrames = 1;
job.SNR_dB = double(snr_dB);
job.StartFrameIndex = double(frameIdx);
job.StartSlotIndex = double(grantSlotIdx);
job.InitialLinkAdaptationState = laStateIn;
job.TransportBlockBits = sixgr.util.structGet(trialContext, "TransportBlockBits", []);
job.RV = sixgr.util.structGet(trialContext, "RV", []);
job.ExpectedUCIBits = sixgr.util.structGet(trialContext, "ExpectedUCIBits", ...
    sixgr.util.structGet(grant, "ExpectedUCIBits", []));
job.HARQContext = sixgr.util.structGet(trialContext, "HARQContext", struct());
tbContext = localReplayTBContext(grant, trialContext);
if isstruct(tbContext) && ~isempty(fieldnames(tbContext))
    job.HARQContext.TransportBlockContext = tbContext;
    job.HARQContext.HARQTBContext = tbContext;
end
job.GrantSnapshot = grant;
job.PHYGrant = phyGrant;
job.DCI = sixgr.util.structGet(grant, "DCI", struct());
job.GrantContextId = string(sixgr.util.structGet(grant, "GrantContextId", ...
    sixgr.util.structGet(phyGrant, "GrantContextId", "")));
job.PreviousCombinedLLR = sixgr.util.structGet(trialContext, "PreviousCombinedLLR", []);
job.InterferenceBundle = sixgr.util.structGet(trialContext, "InterferenceBundle", struct([]));
job.ChannelState = sixgr.util.structGet(trialContext, "ChannelState", struct());
job.AbsoluteSampleTime_s = double(sixgr.util.structGet(trialContext, "AbsoluteSampleTime_s", NaN));
hasRuntimeChannelState = isstruct(job.ChannelState) && isfield(job.ChannelState, "ContractVersion");
job.WorkerSafe = ~hasRuntimeChannelState;
job.SharedStateCommitMode = "serial_coordinator_commit";
if hasRuntimeChannelState
    job.SharedStateCommitMode = "serial_runtime_channel_state_commit";
end
end

function grant = localNormalizeGrantPrecodingForFreeze(grant, direction)
if ~(upper(string(direction)) == "DL" && isstruct(grant) && ~isempty(fieldnames(grant)))
    return;
end
W = sixgr.util.structGet(grant, "PrecodingMatrix", []);
if isempty(W) || ~isnumeric(W)
    return;
end
nLayers = double(sixgr.util.structGet(grant, "NumLayers", sixgr.util.structGet(grant, "Layers", NaN)));
if ~(isfinite(nLayers) && nLayers >= 1)
    return;
end
nLayers = max(1, round(nLayers));
if ndims(W) > 2 && size(W, 3) == 1
    W = squeeze(W);
end
if ~ismatrix(W)
    return;
end
if size(W, 2) == nLayers
    Wports = double(W);
elseif size(W, 1) == nLayers
    Wports = double(W.');
elseif size(W, 2) > nLayers && size(W, 1) >= nLayers
    Wports = double(W(:, 1:nLayers));
else
    return;
end
if size(Wports, 1) < nLayers || size(Wports, 2) ~= nLayers
    return;
end
% The selected physical matrix is part of the immutable scheduler/grant
% contract.  resolvePDSCHPrecoding owns any configured normalization before
% the grant is frozen.  Normalizing the element-domain columns here changes
% F*Wlogical while leaving both F and Wlogical untouched, so replay no
% longer lies in its frozen hybrid subspace.
grant.PrecodingMatrix = Wports;
grant.PrecodingNumPorts = double(size(Wports, 1));
grant.PrecodingNumLayers = double(size(Wports, 2));
grant.PrecodingMatrixRows = double(size(Wports, 1));
grant.PrecodingMatrixCols = double(size(Wports, 2));
grant.NumTxAnt = max(double(sixgr.util.structGet(grant, "NumTxAnt", size(Wports, 1))), double(size(Wports, 1)));
end

function grant = localApplyHARQReplayContract(grant, trialContext)
if ~(isstruct(grant) && ~isempty(fieldnames(grant)) && localIsHARQReplay(trialContext))
    return;
end
replayBits = localReplayTransportBlockBits(trialContext);
tbContext = localReplayTBContext(grant, trialContext);
resolvedTBSBits = double(sixgr.util.structGet(tbContext, "TBSBits", NaN));
if ~(isfinite(replayBits) && replayBits > 0) && ~(isfinite(resolvedTBSBits) && resolvedTBSBits > 0)
    return;
end
if ~(isfinite(resolvedTBSBits) && resolvedTBSBits > 0)
    resolvedTBSBits = double(replayBits);
elseif isfinite(replayBits) && replayBits > 0 && round(resolvedTBSBits) ~= round(replayBits)
    error("sixgr:truth:HARQReplayContractTBSMismatch", ...
        "HARQ replay context TBSBits=%d does not match stored TB bits=%d.", ...
        round(resolvedTBSBits), round(replayBits));
end
harq = sixgr.util.structGet(grant, "HARQ", struct());
harqContext = sixgr.util.structGet(trialContext, "HARQContext", struct());
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
grant.IsRetransmission = true;
grant.HARQ = harq;
if isstruct(tbContext) && ~isempty(fieldnames(tbContext))
    grant.HARQTBContext = tbContext;
end
grant.TransportBlockSize = double(resolvedTBSBits);
grant.TBSBits = double(resolvedTBSBits);
grant.TBSBytes = floor(double(resolvedTBSBits) / 8);
grant.ScheduledTransportBlockSize = double(resolvedTBSBits);
if ~(isstruct(tbContext) && ~isempty(fieldnames(tbContext))) && isfield(grant, "PHYGrant")
    grant = rmfield(grant, "PHYGrant");
end
if ~(isstruct(tbContext) && ~isempty(fieldnames(tbContext))) && isfield(grant, "PHYGrantContextId")
    grant.PHYGrantContextId = "";
end
end

function tf = localIsHARQReplay(trialContext)
grant = sixgr.util.structGet(trialContext, "GrantSnapshot", struct());
harqContext = sixgr.util.structGet(trialContext, "HARQContext", struct());
tbContext = localReplayTBContext(grant, trialContext);
replayBits = localReplayTransportBlockBits(trialContext);
ctxBits = double(sixgr.util.structGet(tbContext, "TBSBits", NaN));
hasReplayPayload = replayBits > 0 || (isfinite(ctxBits) && ctxBits > 0);
if ~hasReplayPayload
    tf = false;
    return;
end
tf = sixgr.phy.grant.isExplicitHARQRetransmission( ...
    grant, sixgr.util.structGet(grant, "PHYGrant", struct()), harqContext);
end

function replayBits = localReplayTransportBlockBits(trialContext)
tbBits = sixgr.util.structGet(trialContext, "TransportBlockBits", []);
replayBits = double(numel(tbBits));
if replayBits > 0
    return;
end
harqContext = sixgr.util.structGet(trialContext, "HARQContext", struct());
tbBits = sixgr.util.structGet(harqContext, "TransportBlockBits", []);
replayBits = double(numel(tbBits));
end

function tbContext = localReplayTBContext(grant, trialContext)
tbContext = struct();
if nargin < 1 || ~isstruct(grant)
    grant = struct();
end
if nargin < 2 || ~isstruct(trialContext)
    trialContext = struct();
end
harqContext = sixgr.util.structGet(trialContext, "HARQContext", struct());
candidates = { ...
    sixgr.util.structGet(harqContext, "TransportBlockContext", struct()), ...
    sixgr.util.structGet(harqContext, "HARQTBContext", struct()), ...
    sixgr.util.structGet(grant, "HARQTBContext", struct()), ...
    sixgr.util.structGet(sixgr.util.structGet(trialContext, "GrantSnapshot", struct()), "HARQTBContext", struct())};
for i = 1:numel(candidates)
    candidate = candidates{i};
    if isstruct(candidate) && ~isempty(fieldnames(candidate))
        tbContext = candidate;
        return;
    end
end
end

function localAssertHARQReplayPHYGrant(phyGrant, trialContext)
if ~localIsHARQReplay(trialContext)
    return;
end
tbContext = localReplayTBContext(struct(), trialContext);
replayBits = double(sixgr.util.structGet(tbContext, "TBSBits", localReplayTransportBlockBits(trialContext)));
grantBits = double(sixgr.util.structGet(phyGrant, "CodingLayout.TBSBits", NaN));
if ~(isfinite(grantBits) && grantBits == replayBits)
    error("sixgr:truth:HARQReplayPHYGrantTBSMismatch", ...
        "HARQ replay PHYGrant TBS %s does not match stored transport block size %d.", ...
        mat2str(grantBits), round(replayBits));
end
if ~sixgr.util.logicalAny(sixgr.util.structGet(phyGrant, "HARQProcessKey.IsRetransmission", false))
    error("sixgr:truth:HARQReplayPHYGrantNotRetransmission", ...
        "HARQ replay PHYGrant must be frozen as a retransmission grant.");
end
end
