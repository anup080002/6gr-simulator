function [mode, evidence] = resolveDuplexMode(cfg, varargin)
%RESOLVEDUPLEXMODE Resolve one fail-closed duplex authority for all PHY users.
%
% Every configured FDD/TDD spelling is compared. No consumer may select a
% preferred alias while ignoring a contradictory value elsewhere.

ip = inputParser;
ip.addRequired("cfg", @(x)(isstruct(x) || isobject(x)) && isscalar(x));
ip.addParameter("RequireYAMLAuthority", false, ...
    @(x)(islogical(x) || isnumeric(x)) && isscalar(x));
ip.parse(cfg, varargin{:});

paths = [ ...
    "DuplexMode"
    "frequency.duplex_mode"
    "global_radio_scope.duplex_mode"
    "radio.duplex_mode"
    "phy.duplex.mode"
    "phy.frameStructure.DuplexMode"
    "random_access.duplex_mode"
    "prach.duplex_mode"
    "prach_lls.duplex_mode"
    "prach_lls.DuplexMode"
    "pdsch6gr.duplex_mode"
    "pdsch6gr.DuplexMode"
    "frame.duplex_mode"
    "scenario.duplexMode"];
values = strings(0, 1);
sources = strings(0, 1);
for path = paths.'
    candidate = sixgr.util.structGet(cfg, path, []);
    if isempty(candidate)
        continue;
    end
    if ~(ischar(candidate) || (isstring(candidate) && isscalar(candidate)))
        error("sixgr:phy:frame:InvalidDuplexAuthority", ...
            "%s must be a scalar YAML/runtime string.", path);
    end
    token = upper(strtrim(string(candidate)));
    if ~any(token == ["FDD", "TDD"])
        error("sixgr:phy:frame:InvalidDuplexMode", ...
            "%s contains unsupported duplex mode '%s'.", path, token);
    end
    values(end + 1, 1) = token; %#ok<AGROW>
    sources(end + 1, 1) = path; %#ok<AGROW>
end
if isempty(values)
    error("sixgr:phy:frame:MissingDuplexMode", ...
        "A resolved FDD or TDD duplex authority is required.");
end
if logical(ip.Results.RequireYAMLAuthority) && ...
        ~any(sources == "frequency.duplex_mode")
    error("sixgr:phy:frame:MissingDuplexYAMLAuthority", ...
        "frequency.duplex_mode is the mandatory YAML duplex authority.");
end
if numel(unique(values)) ~= 1
    pairs = sources + "=" + values;
    error("sixgr:phy:frame:DuplexAuthorityMismatch", ...
        "Duplex authorities disagree: %s.", strjoin(pairs, ", "));
end
mode = values(1);
evidence = table(sources, values, ...
    repmat(mode, numel(values), 1), true(numel(values), 1), ...
    'VariableNames', {'AuthorityPath','ConfiguredMode', ...
    'ResolvedMode','MatchesResolvedMode'});
end
