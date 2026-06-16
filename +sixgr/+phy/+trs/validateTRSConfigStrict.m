function validation = validateTRSConfigStrict(trsCfg)
%VALIDATETRSCONFIGSTRICT Validate strict TRS/NZP-CSI-RS invariants.

reasons = strings(0, 1);
toolboxMissing = false;
needed = ["nrCarrierConfig","nrCSIRSConfig","nrCSIRS","nrCSIRSIndices", ...
    "nrOFDMModulate","nrOFDMDemodulate","nrTimingEstimate","nrChannelEstimate"];
for ii = 1:numel(needed)
    if isempty(which(char(needed(ii))))
        toolboxMissing = true;
        reasons(end+1, 1) = "toolbox_missing:" + needed(ii); %#ok<AGROW>
    end
end
if ~(isfield(trsCfg, "ToolboxCarrier") && isa(trsCfg.ToolboxCarrier, "nrCarrierConfig"))
    reasons(end+1, 1) = "toolbox_carrier_config_missing"; %#ok<AGROW>
end
if ~(isfield(trsCfg, "ToolboxCSIRS") && isa(trsCfg.ToolboxCSIRS, "nrCSIRSConfig"))
    reasons(end+1, 1) = "toolbox_nzp_csirs_config_missing"; %#ok<AGROW>
end
if ~logical(sixgr.util.structGet(trsCfg, "TRSInfoEnabled", false))
    reasons(end+1, 1) = "trs_info_not_enabled"; %#ok<AGROW>
end
if double(sixgr.util.structGet(trsCfg, "NumCSIRSPorts", 0)) < 1
    reasons(end+1, 1) = "no_csirs_ports"; %#ok<AGROW>
end
if numel(double(sixgr.util.structGet(trsCfg, "SlotNumbers", []))) < 2
    reasons(end+1, 1) = "frequency_tracking_requires_at_least_two_trs_slots"; %#ok<AGROW>
end
if ~(isfinite(double(trsCfg.DetectionThreshold)) && double(trsCfg.DetectionThreshold) > 0 && double(trsCfg.DetectionThreshold) < 1)
    reasons(end+1, 1) = "invalid_detection_threshold"; %#ok<AGROW>
end
if ~(isfinite(double(trsCfg.MinCoverageRatio)) && double(trsCfg.MinCoverageRatio) > 0 && double(trsCfg.MinCoverageRatio) <= 1)
    reasons(end+1, 1) = "invalid_min_coverage_ratio"; %#ok<AGROW>
end
try
    tmp = sixgr.phy.trs.generateTRSSymbolsAndIndices(trsCfg);
    if isempty(tmp.SlotResources) || height(tmp.ResourceMappingTable) == 0
        reasons(end+1, 1) = "trs_resource_mapping_empty"; %#ok<AGROW>
    end
catch ME
    reasons(end+1, 1) = "trs_resource_mapping_failed:" + string(ME.identifier); %#ok<AGROW>
end
if ~(isfield(trsCfg, "ConfigHash") && strlength(string(trsCfg.ConfigHash)) > 0)
    reasons(end+1, 1) = "config_hash_missing"; %#ok<AGROW>
end

validation = struct();
validation.StrictValid = isempty(reasons);
validation.ToolboxMissing = toolboxMissing;
validation.FailureReasons = reasons(:);
if isempty(reasons)
    validation.Status = "strict_trs_config_valid";
else
    validation.Status = "strict_trs_config_invalid";
end
validation.StrictUnsupportedReason = strjoin(reasons, "|");
end
