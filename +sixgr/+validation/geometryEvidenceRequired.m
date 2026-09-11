function required = geometryEvidenceRequired(scfg, cfg)
%GEOMETRYEVIDENCEREQUIRED Shared normal/recovery policy; no run-name inference.
if nargin < 2, cfg = struct(); end
runClass = lower(strtrim(string(localGet(scfg, cfg, "validation.RunClass", ...
    localGet(scfg, cfg, "validation.run_class", "")))));
required = runClass == "ue_placement_geometry_lls" || ...
    localBool(localGet(scfg, cfg, "validation.geometry_evidence_required", false)) || ...
    localBool(localGet(scfg, cfg, "canonical_control.launch.geometry_enabled", false));
end

function value = localGet(scfg, cfg, path, default)
% A present false in the resolved scenario is authority, not a missing value.
if isobject(scfg) && ismethod(scfg, "has") && scfg.has(path)
    value = scfg.get(path, default);
    return;
end
if isstruct(scfg)
    value = scfg;
    parts = split(path, ".");
    found = true;
    for index = 1:numel(parts)
        if ~isstruct(value) || ~isscalar(value) || ~isfield(value, parts(index))
            found = false;
            break;
        end
        value = value.(parts(index));
    end
    if found, return; end
end
value = sixgr.util.structGet(cfg, path, default);
end

function value = localBool(raw)
if (islogical(raw) || isnumeric(raw)) && isscalar(raw) && ...
        isreal(raw) && isfinite(raw) && (raw == 0 || raw == 1)
    value = logical(raw);
elseif (ischar(raw) || isstring(raw)) && isscalar(string(raw)) && ...
        any(lower(strtrim(string(raw))) == ["true","false","1","0","yes","no","on","off"])
    value = any(lower(strtrim(string(raw))) == ["true","1","yes","on"]);
else
    error("sixgr:validation:InvalidGeometryEvidencePolicy", ...
        "Geometry audit policy requires an explicit scalar boolean.");
end
end
