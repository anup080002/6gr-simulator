function pLOS = LOSProbability(scenarioName, d2d_m, varargin)
% sixgr.channel.LOSProbability
%
% Scenario-specific LOS probability P(LOS) as a function of 2D distance.
% This is used when the simulation needs a LOS/NLOS draw but only has a
% large-scale pathloss abstraction.
%
% Supported scenarioName (case-insensitive):
%   "UMa", "UMi", "RMa", "InH", "InF"
%
% Notes:
%   - The closed-form expressions are based on commonly-used 3GPP TR 38.901
%     LOS probability curves. Exact constants can be overridden by supplying
%     optional parameters in a future config extension.
%   - If a scenario is not recognized, an exponential fallback is used.
%   - ASCII-only file.
%
% Inputs:
%   scenarioName : string/char
%   d2d_m        : distance (m), scalar or vector
%
% Output:
%   pLOS         : probability in [0,1], same size as d2d_m

% Future: allow overrides via varargin (kept for interface stability)
if ~isempty(varargin) %#ok<NASGU>
    % reserved
end

scn = upper(string(scenarioName));
d = double(d2d_m);
d = max(d, 1e-3);

pLOS = zeros(size(d));

switch scn
    case "UMA"
        % UMa: min(18/d,1)*(1-exp(-d/63)) + exp(-d/63)
        pLOS = min(18./d, 1) .* (1 - exp(-d./63)) + exp(-d./63);

    case "UMI"
        % UMi: min(18/d,1)*(1-exp(-d/36)) + exp(-d/36)
        pLOS = min(18./d, 1) .* (1 - exp(-d./36)) + exp(-d./36);

    case "RMA"
        % RMa: 1 for d<=10, else exp(-(d-10)/1000)
        pLOS = ones(size(d));
        idx = d > 10;
        pLOS(idx) = exp(-(d(idx)-10)./1000);

    case "INH"
        % InH (office-like): 1 for d<=18, else exp(-(d-18)/27)
        pLOS = ones(size(d));
        idx = d > 18;
        pLOS(idx) = exp(-(d(idx)-18)./27);

    case "INF"
        % InF: factory-like. Use a conservative exponential decay.
        pLOS = exp(-d./50);

    otherwise
        % Generic fallback
        pLOS = exp(-d./100);
end

% Clamp
pLOS = max(min(pLOS, 1), 0);

end
