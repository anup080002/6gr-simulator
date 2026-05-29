function domain = resolveLinkAdaptationDomain(cfg, direction)
%RESOLVELINKADAPTATIONDOMAIN Resolve the configured operating domain for AMC updates.
%
% Default behavior intentionally avoids smoothing in quantized MCS-space.
% Unless legacy mode is explicitly requested, closed-loop adaptation runs in
% CQI-space and only maps to MCS after smoothing/provenance resolution.

if nargin < 1 || isempty(cfg)
    cfg = struct();
end
if nargin < 2 || isempty(direction)
    direction = "DL";
end

direction = upper(string(direction));
if direction == "UL"
    candidates = [ ...
        "phy.linkAdaptation.ulDomain"
        "phy.linkAdaptation.domain"];
else
    candidates = [ ...
        "phy.linkAdaptation.dlDomain"
        "phy.linkAdaptation.domain"];
end

raw = "";
for i = 1:numel(candidates)
    raw = lower(strtrim(string(sixgr.util.structGet(cfg, candidates(i), ""))));
    if strlength(raw) > 0
        break;
    end
end

switch raw
    case {"", "default", "cqi", "cqi_domain", "cqi_smoothed"}
        domain = "cqi";
    case {"effective_sinr", "effective-sinr", "eesm", "sinr"}
        domain = "effective_sinr";
    case {"bler_margin", "bler-margin", "olla_bler_margin"}
        domain = "bler_margin";
    case {"legacy_mcs", "mcs", "mcs_domain", "legacy", "radisys_l1_mcs", "flexran_mcs", "mcs_hundredths"}
        domain = "legacy_mcs";
    otherwise
        domain = "cqi";
end
end
