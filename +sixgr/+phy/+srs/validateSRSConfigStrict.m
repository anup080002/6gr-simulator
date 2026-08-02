function validation = validateSRSConfigStrict(srsCfg)
%VALIDATESRSCONFIGSTRICT Validate strict SRS invariants.

reasons = strings(0, 1);
toolboxMissing = false;
needed = ["nrCarrierConfig","nrSRSConfig","nrSRS","nrSRSIndices", ...
    "nrOFDMModulate","nrOFDMDemodulate","nrChannelEstimate"];
for ii = 1:numel(needed)
    if isempty(which(char(needed(ii))))
        toolboxMissing = true;
        reasons(end+1, 1) = "toolbox_missing:" + needed(ii); %#ok<AGROW>
    end
end
if ~logical(sixgr.util.structGet(srsCfg.BaseConfig, "phy.srs.enable", false))
    reasons(end+1, 1) = "srs_disabled_in_strict_config"; %#ok<AGROW>
end
if ~ismember(lower(string(srsCfg.ResourceSetUsage)), ["codebook","noncodebook","beammanagement"])
    reasons(end+1, 1) = "unsupported_resource_set_usage:" + string(srsCfg.ResourceSetUsage); %#ok<AGROW>
end
resourceType = lower(string(srsCfg.ResourceType));
if resourceType == "aperiodic" && strlength(strtrim(string(srsCfg.DCITriggerReferenceId))) == 0
    reasons(end+1, 1) = "aperiodic_srs_missing_decoded_dci_trigger_reference"; %#ok<AGROW>
end
if resourceType == "semipersistent" || resourceType == "semi-persistent"
    reasons(end+1, 1) = "semi_persistent_srs_activation_not_supported_fail_closed"; %#ok<AGROW>
elseif ~ismember(resourceType, ["periodic","aperiodic"])
    reasons(end+1, 1) = "unsupported_resource_type:" + string(srsCfg.ResourceType); %#ok<AGROW>
end
if ~ismember(round(double(srsCfg.NumSRSPorts)), [1 2 4])
    reasons(end+1, 1) = "unsupported_srs_port_count"; %#ok<AGROW>
end
if ~(isfinite(double(srsCfg.SymbolStart)) && isfinite(double(srsCfg.NumSRSSymbols)) && ...
        double(srsCfg.SymbolStart) >= 0 && double(srsCfg.SymbolStart) + double(srsCfg.NumSRSSymbols) <= 14)
    reasons(end+1, 1) = "invalid_srs_symbol_allocation"; %#ok<AGROW>
end
if ~(isfinite(double(srsCfg.CombNumber)) && ismember(round(double(srsCfg.CombNumber)), [2 4 8]))
    reasons(end+1, 1) = "invalid_srs_comb_number"; %#ok<AGROW>
end
if ~(isfinite(double(srsCfg.CombOffset)) && double(srsCfg.CombOffset) >= 0 && double(srsCfg.CombOffset) < double(srsCfg.CombNumber))
    reasons(end+1, 1) = "invalid_srs_comb_offset"; %#ok<AGROW>
end
if ~(isfinite(double(srsCfg.CyclicShift)) && double(srsCfg.CyclicShift) >= 0)
    reasons(end+1, 1) = "invalid_srs_cyclic_shift"; %#ok<AGROW>
end
if ~(isfinite(double(srsCfg.SequenceId)) && double(srsCfg.SequenceId) >= 0 && double(srsCfg.SequenceId) <= 1023)
    reasons(end+1, 1) = "invalid_srs_sequence_id"; %#ok<AGROW>
end
try
    mapping = sixgr.phy.srs.generateSRSSymbolsAndIndices(srsCfg);
    if height(mapping.ResourceMappingTable) == 0
        reasons(end+1, 1) = "srs_resource_mapping_empty"; %#ok<AGROW>
    end
    if isfinite(double(srsCfg.ExpectedRECount)) && double(srsCfg.ExpectedRECount) ~= height(mapping.ResourceMappingTable)
        reasons(end+1, 1) = "configured_expected_re_count_mismatch"; %#ok<AGROW>
    end
    cov = mapping.Coverage;
    if logical(srsCfg.FullCarrierSoundingRequired) && ~logical(cov.FullCarrierClaimValid)
        reasons(end+1, 1) = "full_carrier_sounding_required_but_coverage_incomplete"; %#ok<AGROW>
    end
    if lower(string(srsCfg.CoverageRequirement)) == "configured_band" && ~logical(cov.ConfiguredBandClaimValid)
        reasons(end+1, 1) = "configured_band_sounding_required_but_coverage_incomplete"; %#ok<AGROW>
    end
catch ME
    reasons(end+1, 1) = "srs_resource_mapping_failed:" + string(ME.identifier); %#ok<AGROW>
end
if ~(isfield(srsCfg, "ConfigHash") && strlength(string(srsCfg.ConfigHash)) > 0)
    reasons(end+1, 1) = "config_hash_missing"; %#ok<AGROW>
end

validation = struct();
validation.StrictValid = isempty(reasons);
validation.ToolboxMissing = toolboxMissing;
validation.FailureReasons = reasons(:);
validation.Status = string(sixgr.phy.srs.localTernary(isempty(reasons), ...
    "strict_srs_config_valid", "strict_srs_config_invalid"));
validation.StrictUnsupportedReason = strjoin(reasons, "|");
end
