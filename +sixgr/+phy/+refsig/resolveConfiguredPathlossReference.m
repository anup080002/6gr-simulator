function ref = resolveConfiguredPathlossReference(cfg)
%RESOLVECONFIGUREDPATHLOSSREFERENCE Resolve the YAML-owned DL RS for UL PC.
%   NR PUSCH open-loop power control consumes pathloss measured from the
%   configured downlink SSB or CSI-RS spatial relation.  This resolver does
%   not substitute SRS, configured SNR, or a large-scale channel-model
%   value when the configured waveform measurement is unavailable.

ref = struct( ...
    "Available", false, ...
    "SignalType", "", ...
    "ReferenceSignalId", NaN, ...
    "PathlossReferenceRSId", NaN, ...
    "ReferenceIdentity", "", ...
    "MaximumAgeSlots", Inf, ...
    "SpatialRelationId", NaN, ...
    "Source", "unavailable_no_configured_spatial_relation");

paths = [ ...
    "phy.pusch.powerControl.pathlossReference", ...
    "phy.pusch.power_control.pathloss_reference", ...
    "lls6g.pucch_resources.spatial_relations", ...
    "lls6g.resolvedConfig.pucch_resources.spatial_relations", ...
    "validation.pucch_resources.spatial_relations", ...
    "pucch_resources.spatial_relations"];
relation = struct();
sourcePath = "";
for path = paths
    candidate = sixgr.util.structGet(cfg, path, []);
    if isstruct(candidate) && ~isempty(candidate)
        relation = localSelectActiveRelation(candidate);
        sourcePath = path;
        break;
    end
end
if isempty(fieldnames(relation))
    return;
end

signalType = upper(strtrim(string(localField(relation, ...
    ["reference_signal_type","ReferenceSignalType","SignalType","signal_type"], ""))));
signalType = replace(signalType, "_", "-");
signalType = replace(signalType, " ", "-");
if signalType == "CSIRS"
    signalType = "CSI-RS";
end
if ~any(signalType == ["SSB","CSI-RS"])
    error("sixgr:refsig:UnsupportedPathlossReferenceSignal", ...
        "Configured pathloss-reference signal '%s' is unsupported; use SSB or CSI-RS.", ...
        signalType);
end

referenceSignalId = double(localField(relation, ...
    ["reference_signal_id","ReferenceSignalId","resource_id"], NaN));
if ~(isscalar(referenceSignalId) && isfinite(referenceSignalId) && ...
        referenceSignalId >= 0 && referenceSignalId == fix(referenceSignalId))
    error("sixgr:refsig:InvalidPathlossReferenceSignalId", ...
        "The configured %s pathloss reference requires a nonnegative integer reference_signal_id.", ...
        signalType);
end
pathlossRSId = double(localField(relation, ...
    ["pathloss_reference_rs_id","PathlossReferenceRSId"], referenceSignalId));
if ~(isscalar(pathlossRSId) && isfinite(pathlossRSId) && ...
        pathlossRSId >= 0 && pathlossRSId == fix(pathlossRSId))
    error("sixgr:refsig:InvalidPathlossReferenceRSId", ...
        "The configured pathloss_reference_rs_id must be a nonnegative integer.");
end
maximumAgeSlots = double(localField(relation, ...
    ["maximum_age_slots","MaximumAgeSlots"], Inf));
if ~(isscalar(maximumAgeSlots) && (isinf(maximumAgeSlots) || ...
        (isfinite(maximumAgeSlots) && maximumAgeSlots >= 0)))
    error("sixgr:refsig:InvalidPathlossReferenceAge", ...
        "The configured pathloss-reference maximum_age_slots must be nonnegative or inf.");
end
relationId = double(localField(relation, ["id","Id"], NaN));

ref.Available = true;
ref.SignalType = signalType;
ref.ReferenceSignalId = referenceSignalId;
ref.PathlossReferenceRSId = pathlossRSId;
ref.ReferenceIdentity = signalType + "-" + string(referenceSignalId);
ref.MaximumAgeSlots = maximumAgeSlots;
ref.SpatialRelationId = relationId;
ref.Source = "yaml:" + sourcePath;
end

function relation = localSelectActiveRelation(relations)
relation = struct();
if isscalar(relations)
    relation = relations;
    return;
end
activeId = NaN;
for ii = 1:numel(relations)
    value = double(localField(relations(ii), ["active_id","ActiveId"], NaN));
    if isfinite(value)
        activeId = value;
        break;
    end
end
if isfinite(activeId)
    for ii = 1:numel(relations)
        relationId = double(localField(relations(ii), ["id","Id"], NaN));
        if isfinite(relationId) && relationId == activeId
            relation = relations(ii);
            return;
        end
    end
    error("sixgr:refsig:MissingActivePathlossSpatialRelation", ...
        "No spatial relation has id=%g selected by active_id.", activeId);
end
if numel(relations) == 1
    relation = relations(1);
else
    error("sixgr:refsig:AmbiguousPathlossSpatialRelation", ...
        "Multiple spatial relations are configured without an active_id authority.");
end
end

function value = localField(s, names, defaultValue)
value = defaultValue;
for name = string(names)
    if isfield(s, name)
        value = s.(name);
        return;
    end
end
end
