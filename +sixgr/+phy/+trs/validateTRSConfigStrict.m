function validation = validateTRSConfigStrict(trsCfg)
%VALIDATETRSCONFIGSTRICT Validate strict TRS/NZP-CSI-RS invariants.

reasons = strings(0, 1);
estimator=string(sixgr.util.structGet(trsCfg,'RuntimeChannelEstimator','nr_channel_estimate'));
if ~isscalar(estimator) || ~any(estimator==["nr_channel_estimate","flat_static_awgn_ls"])
    reasons(end+1,1)="invalid_runtime_channel_estimator";
elseif estimator=="flat_static_awgn_ls" && ...
        (~strcmpi(string(trsCfg.ChannelModel),'AWGN') || ...
        ~sixgr.channel.IdentityAWGNRuntime.enabled(sixgr.util.structGet(trsCfg,'BaseConfig',struct())))
    reasons(end+1,1)="flat_estimator_requires_explicit_awgn_operator";
end
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
slots=reshape(double(sixgr.util.structGet(trsCfg,"SlotNumbers",[])),1,[]);
burst=double(sixgr.util.structGet(trsCfg,"BurstLengthSlots",numel(slots)));
if ~isscalar(burst) || burst~=2 || mod(numel(slots),2)~=0 || isempty(slots)
    reasons(end+1,1)="implemented_tracking_receiver_requires_complete_two_slot_resource_sets";
elseif any(~isfinite(slots)) || any(slots~=fix(slots)) || ...
        any(diff(slots)<=0) || any(diff(reshape(slots,2,[]),1,1)~=1,'all')
    reasons(end+1,1)="tracking_resource_sets_require_consecutive_unique_slots";
end
if ~(isfinite(double(trsCfg.DetectionThreshold)) && double(trsCfg.DetectionThreshold) > 0 && double(trsCfg.DetectionThreshold) < 1)
    reasons(end+1, 1) = "invalid_detection_threshold"; %#ok<AGROW>
end
policy=string(sixgr.util.structGet(trsCfg,'DetectionPolicy','fixed_correlation'));
if ~isscalar(policy) || ~any(policy==["fixed_correlation","white_noise_projection_v1"])
    reasons(end+1,1)="invalid_detection_policy";
elseif policy=="white_noise_projection_v1"
    alpha=double(sixgr.util.structGet(trsCfg,'TargetFalseAlarmProbability',NaN));
    if ~isscalar(alpha) || ~isfinite(alpha) || alpha<=0 || alpha>=1
        reasons(end+1,1)="projection_detector_requires_explicit_false_alarm_probability";
    end
    if ~strcmpi(string(trsCfg.ChannelModel),'AWGN')
        reasons(end+1,1)="projection_detector_candidate_requires_awgn_channel";
    end
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
