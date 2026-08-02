function [numRFChains, sourcePath] = resolveDirectionalRFChainAuthority(cfg, direction, varargin)
%RESOLVEDIRECTIONALRFCHAINAUTHORITY Resolve YAML-owned TX RF-chain capacity.
%
% Per-link rank is not an RF hardware configuration. In particular, two
% rank-2 MU-MIMO users require four simultaneous gNB TX RF chains. This
% resolver consumes the immutable runtime authority installed from the
% resolved scenario YAML and rejects contradictory legacy mirrors.

arguments
    cfg (1,1) struct
    direction {mustBeTextScalar}
end
arguments (Repeating)
    varargin
end

p = inputParser;
p.addParameter("RequiredLogicalPorts", 1, ...
    @(x)isnumeric(x) && isscalar(x) && isfinite(x) && x >= 1 && x == fix(x));
p.parse(varargin{:});
requiredPorts = double(p.Results.RequiredLogicalPorts);

direction = upper(strtrim(string(direction)));
switch direction
    case "DL"
        paths = [ ...
            "runtime.antenna.gnb.NumTxRFChains"
            "antenna.bs.numTxRFChains"
            "scenario.bs.numTxRFChains"
            "lls6g.antenna_and_array.bs_num_txrus"];
        role = "gNB TX";
    case "UL"
        paths = [ ...
            "runtime.antenna.ue.NumTxRFChains"
            "antenna.ue.numTxRFChains"
            "scenario.ue.numTxRFChains"
            "lls6g.antenna_and_array.ue_num_txrus"];
        role = "UE TX";
    otherwise
        error("sixgr:phy:mimo:InvalidRFChainDirection", ...
            "RF-chain authority direction must be DL or UL; received '%s'.", ...
            char(direction));
end

values = zeros(0, 1);
sources = strings(0, 1);
for path = paths.'
    value = sixgr.util.structGet(cfg, path, []);
    if isempty(value)
        continue;
    end
    if ~((isnumeric(value) || islogical(value)) && isscalar(value) && ...
            isfinite(double(value)) && double(value) >= 1 && ...
            double(value) == fix(double(value)))
        error("sixgr:phy:mimo:InvalidRFChainAuthority", ...
            "%s must be a positive integer at %s.", char(role), char(path));
    end
    values(end + 1, 1) = double(value); %#ok<AGROW>
    sources(end + 1, 1) = path; %#ok<AGROW>
end
if isempty(values)
    error("sixgr:phy:mimo:MissingRFChainAuthority", ...
        "%s RF-chain capacity is absent; configure the directional *_num_txrus YAML field.", ...
        char(role));
end
if numel(unique(values)) ~= 1
    error("sixgr:phy:mimo:ContradictoryRFChainAuthority", ...
        "%s RF-chain aliases disagree: %s.", char(role), ...
        char(strjoin(sources + "=" + string(values), ", ")));
end

numRFChains = values(1);
sourcePath = sources(1);
if numRFChains < requiredPorts
    error("sixgr:phy:mimo:RFChainCapacityInsufficient", ...
        "%s YAML authority provides %d RF chain(s), but this waveform requires %d logical port(s).", ...
        char(role), numRFChains, requiredPorts);
end
end
