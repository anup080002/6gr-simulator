function tf = isPDCCHGrantBindingRequired(cfg, direction)
%ISPDCCHGRANTBINDINGREQUIRED True when data grants must bind to decoded DCI.
% Keep this file ASCII-only.

if nargin < 1 || ~isstruct(cfg)
    cfg = struct();
end
if nargin < 2
    direction = "";
end

direction = upper(strtrim(string(direction)));
checkDL = strlength(direction) == 0 || direction == "DL";
checkUL = strlength(direction) == 0 || direction == "UL";

commonPaths = [
    "run.controlGating.pdcchRequired"
    "canonical_control.control.pdcch_required"
    "control_gating.pdcch_required"
    "control.pdcch_required"
    ];
dlPaths = [
    "validation.dl_pdsch.require_pdcch_grant_reference"
    "phy.pdsch.strictScheduledDL"
    ];
ulPaths = [
    "validation.ul_pusch.require_pdcch_grant_reference"
    "phy.pusch.strictScheduledUL"
    ];

tf = localAnyTruthy(cfg, commonPaths);
if tf
    return;
end
if checkDL
    tf = localAnyTruthy(cfg, dlPaths) || ...
        (lower(strtrim(string(sixgr.util.structGet(cfg, "phy.pdsch.grantSource", "")))) == "decoded_pdcch");
    if tf
        return;
    end
end
if checkUL
    tf = localAnyTruthy(cfg, ulPaths) || ...
        (lower(strtrim(string(sixgr.util.structGet(cfg, "phy.pusch.grantSource", "")))) == "decoded_pdcch");
end
end

function tf = localAnyTruthy(cfg, paths)
tf = false;
for ii = 1:numel(paths)
    value = sixgr.util.structGet(cfg, paths(ii), []);
    if localTruthy(value)
        tf = true;
        return;
    end
end
end

function tf = localTruthy(value)
if isempty(value)
    tf = false;
elseif islogical(value) || isnumeric(value)
    tf = any(logical(value(:)));
else
    tokens = lower(strtrim(string(value(:))));
    tf = any(ismember(tokens, ["true", "1", "yes", "on", "required", "enabled"]));
end
end
