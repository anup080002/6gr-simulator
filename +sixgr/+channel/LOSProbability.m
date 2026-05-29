function [pLOS, status] = LOSProbability(scenarioName, d2d_m, varargin)
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
%   - The supported closed-form expressions follow 3GPP TR 38.901
%     Table 7.4.2-1 for the named scenario families.
%   - If a scenario is not recognized, an exponential fallback is used and
%     the returned status marks the result as non-strict.
%   - ASCII-only file.
%
% Inputs:
%   scenarioName : string/char
%   d2d_m        : distance (m), scalar or vector
%
% Output:
%   pLOS         : probability in [0,1], same size as d2d_m

opt.HUT_m = [];
if mod(numel(varargin), 2) ~= 0
    error("sixgr:channel:LOSProbability:BadNV", "Name-value inputs must come in pairs.");
end
for i = 1:2:numel(varargin)
    name = lower(string(varargin{i}));
    value = varargin{i + 1};
    switch name
        case {"hut_m","hut","ueheight_m","rxheight_m"}
            opt.HUT_m = double(value);
        otherwise
            error("sixgr:channel:LOSProbability:UnknownOpt", ...
                "Unknown LOS probability option '%s'.", char(name));
    end
end

scn = upper(string(scenarioName));
d = double(d2d_m);
d = max(d, 1e-3);

pLOS = zeros(size(d));
status = struct( ...
    "Source", "", ...
    "ComplianceStatus", "", ...
    "Reason", "", ...
    "KnownScenario", false, ...
    "StrictSupported", false);

switch scn
    case "UMA"
        % UMa: min(18/d,1)*(1-exp(-d/63)) + exp(-d/63)
        pLOS = min(18./d, 1) .* (1 - exp(-d./63)) + exp(-d./63);
        if ~isempty(opt.HUT_m)
            hUT = double(opt.HUT_m);
            if isscalar(hUT)
                hUT = repmat(hUT, size(d));
            else
                hUT = reshape(hUT, size(d));
            end
            highMask = isfinite(hUT) & hUT > 13;
            if any(highMask(:))
                cPrime = ones(size(d));
                dh = hUT(highMask) - 13;
                cPrime(highMask) = 1 + (5/4) .* ((dh ./ 10).^3) .* exp(-abs(dh)./10);
                pLOS = pLOS .* cPrime;
            end
        end
        status.Source = "tr38901_uma_closed_form_los_probability";
        status.ComplianceStatus = "scenario_specific_tr38901_curve";
        status.KnownScenario = true;
        status.StrictSupported = true;

    case "UMI"
        % UMi: min(18/d,1)*(1-exp(-d/36)) + exp(-d/36)
        pLOS = min(18./d, 1) .* (1 - exp(-d./36)) + exp(-d./36);
        status.Source = "tr38901_umi_closed_form_los_probability";
        status.ComplianceStatus = "scenario_specific_tr38901_curve";
        status.KnownScenario = true;
        status.StrictSupported = true;

    case "RMA"
        % RMa: 1 for d<=10, else exp(-(d-10)/1000)
        pLOS = ones(size(d));
        idx = d > 10;
        pLOS(idx) = exp(-(d(idx)-10)./1000);
        status.Source = "tr38901_rma_closed_form_los_probability";
        status.ComplianceStatus = "scenario_specific_tr38901_curve";
        status.KnownScenario = true;
        status.StrictSupported = true;

    case "INH"
        % InH-Office: TR 38.901 Table 7.4.2-1.
        pLOS = ones(size(d));
        mid = d > 1.2 & d <= 6.5;
        pLOS(mid) = exp(-(d(mid) - 1.2) ./ 4.7);
        far = d > 6.5;
        x = exp(-(d(far) - 6.5) ./ 32.6);
        pLOS(far) = exp(-0.9971) .* (1 - x) + x;
        status.Source = "tr38901_inh_closed_form_los_probability";
        status.ComplianceStatus = "scenario_specific_tr38901_curve";
        status.KnownScenario = true;
        status.StrictSupported = true;

    case "INF"
        % InF: factory-like. Use a conservative exponential decay.
        pLOS = exp(-d./50);
        status.Source = "approximate_inf_factory_proxy_los_probability";
        status.ComplianceStatus = "approximate_factory_proxy_not_strict_38901";
        status.Reason = "the current inf los probability uses a conservative proxy curve rather than a strict tr38901 factory-specific formula";
        status.KnownScenario = true;
        status.StrictSupported = false;

    otherwise
        % Generic fallback
        pLOS = exp(-d./100);
        status.Source = "generic_exponential_fallback";
        status.ComplianceStatus = "generic_fallback_not_strict_38901";
        status.Reason = sprintf("unknown propagation scenario '%s' fell back to a generic exponential los curve", char(scn));
end

% Clamp
pLOS = max(min(pLOS, 1), 0);

end
