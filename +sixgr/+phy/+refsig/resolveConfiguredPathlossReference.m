function ref = resolveConfiguredPathlossReference(cfg, channel)
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

if nargin<2, channel="PUSCH"; end
channel=upper(string(channel));
assert(isscalar(channel) && any(channel==["PUSCH","PUCCH","SRS"]), ...
    'sixgr:refsig:UnsupportedPowerControlChannel','Resolve a PUSCH, PUCCH or SRS reference.');
paths = [ ...
    "phy.pusch.powerControl.pathlossReference", ...
    "phy.pusch.power_control.pathloss_reference", ...
    "lls6g.pucch_resources.spatial_relations", ...
    "lls6g.resolvedConfig.pucch_resources.spatial_relations", ...
    "validation.pucch_resources.spatial_relations", ...
    "pucch_resources.spatial_relations"];
if channel=="PUCCH"
    % materialize() consumes the installed validation catalog. An installed
    % empty/malformed catalog must not fall through to PUSCH or a legacy copy.
    paths="validation.pucch_resources.spatial_relations";
    if ~isfield(sixgr.util.structGet(cfg,'validation',struct()),'pucch_resources')
        paths=["lls6g.pucch_resources.spatial_relations", ...
            "lls6g.resolvedConfig.pucch_resources.spatial_relations", ...
            "pucch_resources.spatial_relations"];
    end
elseif channel=="SRS"
    % TS 38.213 7.3.1: a dedicated SRS resource-set reference is not
    % implicitly the configured PUSCH or PUCCH reference. The acquisition
    % SSB default needs actual MIB/selection evidence, not an assumed beam.
    paths=["rf.frontend.ul_power_control.srs.pathloss_reference", ...
        "rf_frontend.ul_power_control.srs.pathloss_reference", ...
        "phy.srs.powerControl.pathlossReference"];
end
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

rawReferenceSignalId = localField(relation, ...
    ["reference_signal_id","ReferenceSignalId","resource_id"], NaN);
localNumericIdentity(rawReferenceSignalId,'sixgr:refsig:InvalidPathlossReferenceSignalId');
referenceSignalId = double(rawReferenceSignalId);
if ~(isscalar(referenceSignalId) && isfinite(referenceSignalId) && ...
        referenceSignalId >= 0 && referenceSignalId == fix(referenceSignalId))
    error("sixgr:refsig:InvalidPathlossReferenceSignalId", ...
        "The configured %s pathloss reference requires a nonnegative integer reference_signal_id.", ...
        signalType);
end
rawPathlossRSId = localField(relation, ...
    ["pathloss_reference_rs_id","PathlossReferenceRSId"], referenceSignalId);
localNumericIdentity(rawPathlossRSId,'sixgr:refsig:InvalidPathlossReferenceRSId');
pathlossRSId = double(rawPathlossRSId);
if ~(isscalar(pathlossRSId) && isfinite(pathlossRSId) && ...
        pathlossRSId >= 0 && pathlossRSId == fix(pathlossRSId))
    error("sixgr:refsig:InvalidPathlossReferenceRSId", ...
        "The configured pathloss_reference_rs_id must be a nonnegative integer.");
end
rawMaximumAge = localField(relation, ["maximum_age_slots","MaximumAgeSlots"], Inf);
assert(isnumeric(rawMaximumAge) && isreal(rawMaximumAge) && isscalar(rawMaximumAge) && ...
    ~isnan(rawMaximumAge) && rawMaximumAge>=0, ...
    'sixgr:refsig:InvalidPathlossReferenceAge','Maximum age must be nonnegative numeric or positive inf.');
maximumAgeSlots = double(rawMaximumAge);
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

function localNumericIdentity(value,id)
assert(isnumeric(value) && isreal(value) && isscalar(value) && isfinite(value) && ...
    value>=0 && value==fix(value),id,'A reference identity must be a nonnegative numeric integer.');
end

function relation = localSelectActiveRelation(relations)
ids=NaN(1,numel(relations)); active=[];
for ii = 1:numel(relations)
    value=localField(relations(ii),["id","Id"],[]);
    if ~isempty(value)
        localNumericIdentity(value,'sixgr:refsig:InvalidPathlossSpatialRelationId');
        ids(ii)=double(value);
    elseif numel(relations)>1
        error('sixgr:refsig:InvalidPathlossSpatialRelationId','Every relation in a multi-relation catalog requires its own numeric id.');
    end
    value=localField(relations(ii),["active_id","ActiveId"],[]);
    if ~isempty(value)
        localNumericIdentity(value,'sixgr:refsig:InvalidActivePathlossSpatialRelationId');
        active(end+1)=double(value); %#ok<AGROW>
    end
end
assert(numel(unique(ids(isfinite(ids))))==nnz(isfinite(ids)), ...
    'sixgr:refsig:AmbiguousPathlossSpatialRelation','Spatial relation IDs must be unique.');
assert(numel(unique(active))<=1,'sixgr:refsig:AmbiguousPathlossSpatialRelation', ...
    'All authored active selectors must name the same spatial relation.');
if isempty(active)
    assert(isscalar(relations),'sixgr:refsig:AmbiguousPathlossSpatialRelation', ...
        'Multiple spatial relations require one explicit active selector.');
    relation=relations; return;
end
hit=find(ids==active(1));
assert(isscalar(hit),'sixgr:refsig:MissingActivePathlossSpatialRelation', ...
    'Exactly one configured spatial relation must match the active selector.');
relation=relations(hit);
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
