function out = validateRARULGrant(grant, raCfg)
%VALIDATERARULGRANT Validate decoded RAR UL grant for the anchor profile.
out = struct("Valid", false, "FailureReason", "", "Status", "invalid");
if isempty(grant) || ~isstruct(grant)
    out.FailureReason = "rar_invalid_ul_grant";
    return;
end
required = ["PRBStart","NumPRB","SymbolStart","NumSymbols","MCS","TemporaryCRNTI"];
for ii = 1:numel(required)
    if ~isfield(grant, required(ii))
        out.FailureReason = "rar_invalid_ul_grant";
        return;
    end
end
if grant.NumPRB <= 0 || grant.PRBStart < 0 || grant.PRBStart + grant.NumPRB > raCfg.NSizeGrid
    out.FailureReason = "rar_invalid_ul_grant_frequency_allocation";
    return;
end
if grant.SymbolStart < 0 || grant.NumSymbols <= 0 || grant.SymbolStart + grant.NumSymbols > 14
    out.FailureReason = "rar_invalid_ul_grant_time_allocation";
    return;
end
if grant.TemporaryCRNTI < 1 || grant.TemporaryCRNTI > 65519
    out.FailureReason = "rar_invalid_temporary_crnti";
    return;
end
out.Valid = true;
out.Status = "OK";
end
