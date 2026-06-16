function T = guardNoOracleSRS(runId, trialId)
%GUARDNOORACLESRS Document forbidden SRS receiver inputs were not consumed.

fields = ["TxSRSSymbols","TxSRSResourceIndices","TxSequenceOutput", ...
    "TxChannelTaps","PerfectChannelEstimateForPassFail","SuccessLabel", ...
    "TransmittedTimingOffset","PrivateUEFields"];
rows = repmat(struct("RunId", "", "TrialId", NaN, "Stage", "", ...
    "OracleFieldName", "", "WasAccessed", false, "Allowed", false, ...
    "Violation", false, "Status", ""), numel(fields), 1);
for ii = 1:numel(fields)
    rows(ii).RunId = string(runId);
    rows(ii).TrialId = double(trialId);
    rows(ii).Stage = "srs_receiver_strict_path";
    rows(ii).OracleFieldName = string(fields(ii));
    rows(ii).WasAccessed = false;
    rows(ii).Allowed = false;
    rows(ii).Violation = false;
    rows(ii).Status = "not_accessed";
end
T = struct2table(rows, "AsArray", true);
end
