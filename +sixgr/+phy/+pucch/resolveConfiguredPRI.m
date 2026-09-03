function authority = resolveConfiguredPRI(cfg, ueIndex, rnti, explicitPRI, purpose)
%RESOLVECONFIGUREDPRI Resolve one YAML-authorized PUCCH resource indicator.
%
% The DCI resource indicator selects an ordinal within an RRC-configured
% PUCCH resource set.  This function is the single production authority
% used by scheduler, HARQ-ACK, CSI and waveform-replay paths.  It never
% invents a resource when the configured multi-user policy is incomplete.

arguments
    cfg (1,1) struct
    ueIndex (1,1) double = NaN
    rnti (1,1) double = NaN
    explicitPRI (1,1) double = NaN
    purpose (1,1) string {mustBeMember(purpose,["harq","csi"])} = "harq"
end

section = sixgr.util.structGet(cfg, "validation.pucch_resources", struct());
if ~(isstruct(section) && logical(sixgr.util.structGet(section, "enabled", false)))
    error("sixgr:phy:pucch:MissingConfiguredPUCCHAuthority", ...
        "Connected PUCCH PRI resolution requires enabled validation.pucch_resources.");
end
sets = sixgr.util.structGet(section, "resource_sets", struct([]));
assignment = sixgr.util.structGet(section, "multi_user_assignment", struct());
if purpose == "csi"
    configuredPurposeIds = double(sixgr.util.structGet( ...
        section, "csi_resource_ids", []));
    configuredPurposeIds = configuredPurposeIds(:).';
    if isempty(configuredPurposeIds) || any(~isfinite(configuredPurposeIds))
        error("sixgr:phy:pucch:MissingConfiguredCSIResource", ...
            "CSI-on-PUCCH requires exact configured csi_resource_ids.");
    end
    matchingSets = false(numel(sets), 1);
    for index = 1:numel(sets)
        candidateIds = double(sixgr.util.structGet( ...
            sets(index), "resource_ids", []));
        matchingSets(index) = all(ismember(configuredPurposeIds, candidateIds));
    end
    matchingIndices = find(matchingSets);
    if numel(matchingIndices) ~= 1
        error("sixgr:phy:pucch:AmbiguousConfiguredCSIResourceSet", ...
            ["Configured CSI PUCCH resources must resolve to exactly one " + ...
             "RRC resource set; resolved %d sets."], numel(matchingIndices));
    end
    setId = double(sixgr.util.structGet(sets(matchingIndices), "id", NaN));
else
    setId = double(sixgr.util.structGet(assignment, "resource_set_id", 0));
end
if ~(isstruct(sets) && ~isempty(sets) && isscalar(setId) && ...
        isfinite(setId) && setId >= 0 && setId == fix(setId))
    error("sixgr:phy:pucch:MissingConfiguredResourceSet", ...
        "Connected PUCCH requires an exact configured resource-set authority.");
end

setIds = nan(numel(sets), 1);
for index = 1:numel(sets)
    setIds(index) = double(sixgr.util.structGet(sets(index), "id", NaN));
end
setIndex = find(setIds == setId, 1);
if isempty(setIndex)
    error("sixgr:phy:pucch:MissingConfiguredResourceSet", ...
        "Configured PUCCH resource set %d does not exist.", round(setId));
end
resourceIds = double(sixgr.util.structGet(sets(setIndex), ...
    "resource_ids", []));
resourceIds = resourceIds(:).';
if isempty(resourceIds) || any(~isfinite(resourceIds)) || ...
        any(resourceIds < 0) || any(resourceIds ~= fix(resourceIds)) || ...
        numel(unique(resourceIds)) ~= numel(resourceIds)
    error("sixgr:phy:pucch:InvalidConfiguredResourceSet", ...
        "PUCCH resource set %d must contain unique nonnegative resource IDs.", ...
        round(setId));
end

if isfinite(explicitPRI)
    if explicitPRI < 0 || explicitPRI ~= fix(explicitPRI)
        error("sixgr:phy:pucch:InvalidResourceIndicator", ...
            "Explicit PUCCH PRI must be a nonnegative integer.");
    end
    pri = round(explicitPRI);
    source = "explicit_scheduler_grant";
elseif numel(resourceIds) == 1
    pri = 0;
    source = "single_configured_resource";
else
    mode = lower(strtrim(string(sixgr.util.structGet(assignment, "mode", ""))));
    switch mode
        case "rnti_modulo_resource_set"
            if ~(isfinite(rnti) && rnti >= 0 && rnti == fix(rnti))
                error("sixgr:phy:pucch:MissingRNTIForResourceAssignment", ...
                    "RNTI-based PUCCH resource selection requires an exact RNTI.");
            end
            pri = mod(round(rnti), numel(resourceIds));
            source = "yaml_rnti_modulo_resource_set";
        case "ue_ordinal_modulo_resource_set"
            if ~(isfinite(ueIndex) && ueIndex >= 1 && ueIndex == fix(ueIndex))
                error("sixgr:phy:pucch:MissingUEForResourceAssignment", ...
                    "UE-ordinal PUCCH resource selection requires an exact UE index.");
            end
            pri = mod(round(ueIndex) - 1, numel(resourceIds));
            source = "yaml_ue_ordinal_modulo_resource_set";
        otherwise
            error("sixgr:phy:pucch:MissingMultiUserResourceAssignment", ...
                ["Multiple PUCCH resources require an explicit YAML " + ...
                 "multi_user_assignment.mode; received '%s'."], char(mode));
    end
end
if pri >= numel(resourceIds)
    error("sixgr:phy:pucch:InvalidResourceIndicator", ...
        "PUCCH PRI=%d is outside configured resource set %d (size %d).", ...
        round(pri), round(setId), numel(resourceIds));
end

authority = struct( ...
    "PRIValue", double(pri), ...
    "ResourceSetId", double(setId), ...
    "ResourceId", double(resourceIds(pri + 1)), ...
    "Source", char(source), ...
    "Authority", "configured_rrc_resource_set_and_gnb_selection", ...
    "ResourceListSize", double(numel(resourceIds)));
end
