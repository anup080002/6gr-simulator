function validation = validatePDCCHConfigStrict(pdcchCfg)
%VALIDATEPDCCHCONFIGSTRICT Validate strict PDCCH config invariants.

reasons = strings(0, 1);
toolboxMissing = false;
needed = ["nrCarrierConfig","nrCORESETConfig","nrSearchSpaceConfig", ...
    "nrPDCCHConfig","nrPDCCHSpace","nrDCIEncode","nrDCIDecode", ...
    "nrPDCCH","nrPDCCHDecode","nrPDCCHResources","nrOFDMModulate", ...
    "nrOFDMDemodulate","nrChannelEstimate","nrEqualizeMMSE"];
for ii = 1:numel(needed)
    if isempty(which(char(needed(ii))))
        toolboxMissing = true;
        reasons(end + 1, 1) = "toolbox_missing:" + needed(ii); %#ok<AGROW>
    end
end
if ~(isfield(pdcchCfg, "ToolboxCarrier") && isa(pdcchCfg.ToolboxCarrier, "nrCarrierConfig"))
    reasons(end + 1, 1) = "toolbox_carrier_config_missing"; %#ok<AGROW>
end
if ~(isfield(pdcchCfg, "ToolboxPDCCH") && isa(pdcchCfg.ToolboxPDCCH, "nrPDCCHConfig"))
    reasons(end + 1, 1) = "toolbox_pdcch_config_missing"; %#ok<AGROW>
end
if ~ismember(double(pdcchCfg.AggregationLevel), [1 2 4 8 16])
    reasons(end + 1, 1) = "invalid_aggregation_level"; %#ok<AGROW>
end
numCand = [pdcchCfg.NumCandidatesAL1 pdcchCfg.NumCandidatesAL2 ...
    pdcchCfg.NumCandidatesAL4 pdcchCfg.NumCandidatesAL8 pdcchCfg.NumCandidatesAL16];
idx = find([1 2 4 8 16] == double(pdcchCfg.AggregationLevel), 1);
if isempty(idx) || double(numCand(idx)) < 1
    reasons(end + 1, 1) = "search_space_candidate_count_missing_for_tx_aggregation_level"; %#ok<AGROW>
end
if double(pdcchCfg.CORESETDurationSymbols) < 1 || double(pdcchCfg.CORESETDurationSymbols) > 3
    reasons(end + 1, 1) = "invalid_coreset_duration"; %#ok<AGROW>
end
if isempty(pdcchCfg.CORESETFrequencyDomainResources) || ~any(double(pdcchCfg.CORESETFrequencyDomainResources) > 0)
    reasons(end + 1, 1) = "coreset_frequency_resources_missing"; %#ok<AGROW>
end
supportedFormats = ["0_0","1_0"];
formats = string(pdcchCfg.DCIMonitoringFormats(:));
unsupported = setdiff(formats, supportedFormats);
if ~isempty(unsupported)
    reasons(end + 1, 1) = "unsupported_dci_format:" + strjoin(unsupported, "|"); %#ok<AGROW>
end
supportedRnti = ["C-RNTI","SI-RNTI","RA-RNTI","TC-RNTI"];
if ~ismember(string(pdcchCfg.RNTIType), supportedRnti)
    reasons(end + 1, 1) = "unsupported_rnti_type:" + string(pdcchCfg.RNTIType); %#ok<AGROW>
end
if ~(isfinite(double(pdcchCfg.RNTIValue)) && double(pdcchCfg.RNTIValue) >= 1 && double(pdcchCfg.RNTIValue) <= 65519)
    reasons(end + 1, 1) = "invalid_rnti_value"; %#ok<AGROW>
end
if ~(isfinite(double(pdcchCfg.DCIPayloadSizeBits)) && double(pdcchCfg.DCIPayloadSizeBits) >= 32)
    reasons(end + 1, 1) = "invalid_dci_payload_size"; %#ok<AGROW>
end
if ~(isfield(pdcchCfg, "ConfigHash") && strlength(string(pdcchCfg.ConfigHash)) > 0)
    reasons(end + 1, 1) = "config_hash_missing"; %#ok<AGROW>
end

validation = struct();
validation.StrictValid = isempty(reasons);
validation.ToolboxMissing = toolboxMissing;
validation.FailureReasons = reasons(:);
if isempty(reasons)
    validation.Status = "strict_config_valid";
else
    validation.Status = "strict_config_invalid";
end
validation.StrictUnsupportedReason = strjoin(reasons, "|");
end
