function [grant, validation] = validateDecodedDCIGrant(dci, pdcchCfg)
%VALIDATEDECODEDDCIGRANT Convert decoded DCI fields into a guarded grant.

fields = dci.Fields;
failure = strings(0, 1);
prbStart = double(fields.prb_start);
numPRB = double(fields.num_prb);
symStart = double(fields.symbol_start);
numSym = double(fields.num_symbols);
mcs = double(fields.mcs);
if ~(isfinite(prbStart) && prbStart >= 0 && prbStart < double(pdcchCfg.NSizeGrid))
    failure(end + 1, 1) = "prb_start_out_of_range"; %#ok<AGROW>
end
if ~(isfinite(numPRB) && numPRB >= 1 && prbStart + numPRB <= double(pdcchCfg.NSizeGrid))
    failure(end + 1, 1) = "num_prb_out_of_range"; %#ok<AGROW>
end
if ~(isfinite(symStart) && isfinite(numSym) && symStart >= 0 && numSym >= 1 && symStart + numSym <= 14)
    failure(end + 1, 1) = "symbol_allocation_out_of_range"; %#ok<AGROW>
end
if ~(isfinite(mcs) && mcs >= 0 && mcs <= 27)
    failure(end + 1, 1) = "mcs_out_of_range"; %#ok<AGROW>
end

grant = struct();
grant.GrantType = string(dci.GrantType);
grant.DCIFormat = string(dci.Format);
grant.RNTIType = string(pdcchCfg.RNTIType);
grant.FrequencyResourceAssignment = double(fields.frequency_resource_assignment);
grant.TimeResourceAssignment = double(fields.time_resource_assignment);
grant.PRBStart = prbStart;
grant.NumPRB = numPRB;
grant.SymbolStart = symStart;
grant.NumSymbols = numSym;
grant.MCS = mcs;
grant.Modulation = localMCSModulation(mcs);
grant.TBS = double(max(0, floor(numPRB * numSym * localModOrder(grant.Modulation) * 0.5 * 12)));
grant.HARQProcess = double(fields.harq_process);
grant.NDI = double(fields.ndi);
grant.RV = double(fields.rv);
grant.TPC = double(fields.tpc);
grant.PUCCHResourceIndicator = double(localGetField(fields, "pucch_resource_indicator", NaN));
grant.PDSCHToHARQFeedbackTiming = double(localGetField(fields, "pdsch_to_harq_feedback_timing", NaN));
grant.Valid = isempty(failure);
grant.FailureReason = strjoin(failure, "|");
grant.GrantReferenceId = "pdcch_grant_" + extractBefore(string(dci.PayloadHash), min(17, strlength(string(dci.PayloadHash))+1));

validation = struct("Valid", grant.Valid, "FailureReason", string(grant.FailureReason));
end

function value = localGetField(s, name, defaultValue)
if isfield(s, name)
    value = s.(name);
else
    value = defaultValue;
end
end

function mod = localMCSModulation(mcs)
if mcs <= 9
    mod = "QPSK";
elseif mcs <= 16
    mod = "16QAM";
else
    mod = "64QAM";
end
end

function q = localModOrder(mod)
switch string(mod)
    case "QPSK"
        q = 2;
    case "16QAM"
        q = 4;
    otherwise
        q = 6;
end
end
