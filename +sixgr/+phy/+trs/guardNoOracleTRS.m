function T = guardNoOracleTRS(runId, trialId, accessedFields)
%GUARDNOORACLETRS Emit TRS oracle-guard evidence rows.

if nargin < 3
    accessedFields = strings(0, 1);
end
forbidden = ["tx_waveform_symbols","perfect_channel_estimate","known_noise_realization", ...
    "injected_timing_offset_for_receiver","injected_cfo_for_receiver"];
rows = repmat(localOracleRow(), numel(forbidden), 1);
accessed = lower(strtrim(string(accessedFields(:))));
for ii = 1:numel(forbidden)
    wasAccessed = any(accessed == lower(forbidden(ii)));
    rows(ii) = localOracleRow();
    rows(ii).RunId = string(runId);
    rows(ii).TrialId = double(trialId);
    rows(ii).Stage = "trs_receiver";
    rows(ii).OracleFieldName = string(forbidden(ii));
    rows(ii).WasAccessed = logical(wasAccessed);
    rows(ii).Allowed = false;
    rows(ii).Violation = logical(wasAccessed);
    rows(ii).Status = string(sixgr.phy.trs.localTernary(wasAccessed, "violation", "not_accessed"));
end
T = struct2table(rows, "AsArray", true);
end

function row = localOracleRow()
row = struct("RunId", "", "TrialId", NaN, "Stage", "", "OracleFieldName", "", ...
    "WasAccessed", false, "Allowed", false, "Violation", false, "Status", "");
end
