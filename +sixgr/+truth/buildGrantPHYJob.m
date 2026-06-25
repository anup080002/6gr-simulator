function job = buildGrantPHYJob(cfg, direction, snr_dB, frameIdx, laStateIn, trialContext)
%BUILDGRANTPHYJOB Build a worker-safe payload for one PHY grant execution.
% Keep this file ASCII-only.

if nargin < 6 || ~isstruct(trialContext)
    trialContext = struct();
end

grant = sixgr.util.structGet(trialContext, "GrantSnapshot", struct());
grantSlotIdx = double(sixgr.util.structGet(grant, "Slot", frameIdx));
phyGrant = sixgr.util.structGet(trialContext, "PHYGrant", ...
    sixgr.util.structGet(grant, "PHYGrant", struct()));
if ~(isstruct(phyGrant) && ~isempty(fieldnames(phyGrant)) && ...
        logical(sixgr.util.structGet(phyGrant, "IsFrozen", false)))
    phyGrant = sixgr.phy.grant.freezePHYGrant(cfg, direction, grant, ...
        "SNR_dB", snr_dB, ...
        "Frame", frameIdx, ...
        "Slot", grantSlotIdx, ...
        "HARQContext", sixgr.util.structGet(trialContext, "HARQContext", struct()));
end
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
job.GrantContextId = string(sixgr.util.structGet(grant, "GrantContextId", phyGrant.GrantContextId));
job.PreviousCombinedLLR = sixgr.util.structGet(trialContext, "PreviousCombinedLLR", []);
job.InterferenceBundle = sixgr.util.structGet(trialContext, "InterferenceBundle", struct([]));
job.WorkerSafe = true;
job.SharedStateCommitMode = "serial_coordinator_commit";
end
