function job = buildGrantPHYJob(cfg, direction, snr_dB, frameIdx, laStateIn, trialContext)
%BUILDGRANTPHYJOB Build a worker-safe payload for one PHY grant execution.
% Keep this file ASCII-only.

if nargin < 6 || ~isstruct(trialContext)
    trialContext = struct();
end

grant = sixgr.util.structGet(trialContext, "GrantSnapshot", struct());
grantSlotIdx = double(sixgr.util.structGet(grant, "Slot", frameIdx));

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
job.GrantContextId = string(sixgr.util.structGet(grant, "GrantContextId", ""));
job.PreviousCombinedLLR = sixgr.util.structGet(trialContext, "PreviousCombinedLLR", []);
job.InterferenceBundle = sixgr.util.structGet(trialContext, "InterferenceBundle", struct([]));
job.WorkerSafe = true;
job.SharedStateCommitMode = "serial_coordinator_commit";
end
