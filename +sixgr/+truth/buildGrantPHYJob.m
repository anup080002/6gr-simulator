function job = buildGrantPHYJob(cfg, direction, snr_dB, frameIdx, laStateIn, trialContext)
%BUILDGRANTPHYJOB Build a worker-safe payload for one PHY grant execution.
% Keep this file ASCII-only.

if nargin < 6 || ~isstruct(trialContext)
    trialContext = struct();
end

grant = sixgr.util.structGet(trialContext, "GrantSnapshot", struct());
grant = localNormalizeGrantPrecodingForFreeze(grant, direction);
grant = localApplyHARQReplayContract(grant, trialContext);
grantSlotIdx = double(sixgr.util.structGet(grant, "Slot", frameIdx));
if isstruct(grant) && ~isempty(fieldnames(grant))
    scheduler = sixgr.l2.mac.SchedulerPF(cfg, "Direction", char(upper(string(direction))));
    grant = scheduler.freezePHYGrantForGrant(grant);
    grant = localApplyHARQReplayContract(grant, trialContext);
    if ~isfield(grant, "DCI") || ~isstruct(grant.DCI) || isempty(fieldnames(grant.DCI))
        grant.DCI = scheduler.buildDCIBitfield(grant);
    end
end
if localIsHARQReplay(trialContext)
    phyGrant = sixgr.util.structGet(grant, "PHYGrant", struct());
else
    phyGrant = sixgr.util.structGet(trialContext, "PHYGrant", ...
        sixgr.util.structGet(grant, "PHYGrant", struct()));
end
if ~(isstruct(phyGrant) && ~isempty(fieldnames(phyGrant)) && ...
        logical(sixgr.util.structGet(phyGrant, "IsFrozen", false)))
    grant = localApplyHARQReplayContract(grant, trialContext);
    phyGrant = sixgr.phy.grant.freezePHYGrant(cfg, direction, grant, ...
        "SNR_dB", snr_dB, ...
        "Frame", frameIdx, ...
        "Slot", grantSlotIdx, ...
        "HARQContext", sixgr.util.structGet(trialContext, "HARQContext", struct()));
end
localAssertHARQReplayPHYGrant(phyGrant, trialContext);
grant.PHYGrant = phyGrant;
grant.PHYGrantContextId = char(string(phyGrant.GrantContextId));

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
job.GrantSnapshot = grant;
job.PHYGrant = phyGrant;
job.DCI = sixgr.util.structGet(grant, "DCI", struct());
job.GrantContextId = string(sixgr.util.structGet(grant, "GrantContextId", phyGrant.GrantContextId));
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
colNorm = sqrt(sum(abs(Wports).^2, 1));
colNorm(colNorm <= eps) = 1;
Wports = Wports ./ colNorm;
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
if ~(isfinite(replayBits) && replayBits > 0)
    return;
end
harq = sixgr.util.structGet(grant, "HARQ", struct());
harqContext = sixgr.util.structGet(trialContext, "HARQContext", struct());
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
grant.IsRetransmission = true;
grant.HARQ = harq;
grant.TransportBlockSize = double(replayBits);
grant.TBSBits = double(replayBits);
grant.TBSBytes = floor(double(replayBits) / 8);
grant.ScheduledTransportBlockSize = double(replayBits);
if isfield(grant, "PHYGrant")
    grant = rmfield(grant, "PHYGrant");
end
if isfield(grant, "PHYGrantContextId")
    grant.PHYGrantContextId = "";
end
end

function tf = localIsHARQReplay(trialContext)
harqContext = sixgr.util.structGet(trialContext, "HARQContext", struct());
tf = isstruct(harqContext) && logical(sixgr.util.structGet(harqContext, "IsRetransmission", false)) && ...
    localReplayTransportBlockBits(trialContext) > 0;
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

function localAssertHARQReplayPHYGrant(phyGrant, trialContext)
if ~localIsHARQReplay(trialContext)
    return;
end
replayBits = localReplayTransportBlockBits(trialContext);
grantBits = double(sixgr.util.structGet(phyGrant, "CodingLayout.TBSBits", NaN));
if ~(isfinite(grantBits) && grantBits == replayBits)
    error("sixgr:truth:HARQReplayPHYGrantTBSMismatch", ...
        "HARQ replay PHYGrant TBS %s does not match stored transport block size %d.", ...
        mat2str(grantBits), round(replayBits));
end
end
