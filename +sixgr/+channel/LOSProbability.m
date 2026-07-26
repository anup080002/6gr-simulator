function [pLOS, status] = LOSProbability(scenarioName, d2d_m, varargin)
% sixgr.channel.LOSProbability
%
% Scenario-specific LOS probability P(LOS) as a function of 2D distance.
% This is used when the simulation needs a LOS/NLOS draw but only has a
% large-scale pathloss abstraction.
%
% Supported scenarioName (case-insensitive):
%   "UMa", "UMi-StreetCanyon", "RMa", "InH-MixedOffice",
%   "InH-OpenOffice"
%
% Notes:
%   - The supported closed-form expressions follow 3GPP TR 38.901
%     Table 7.4.2-1 for the named scenario families.
%   - Unknown and unpinned scenarios fail closed. There is no generic
%     exponential fallback in the strict production API.
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
if any(~isfinite(d(:)) | d(:) <= 0)
    error("CHANNEL:InvalidGeometry", ...
        "LOS probability requires finite, positive 2D distances.");
end

pLOS = zeros(size(d));
status = struct( ...
    "Source", "", ...
    "ComplianceStatus", "", ...
    "Reason", "", ...
    "KnownScenario", false, ...
    "StrictSupported", false);

scn = upper(regexprep(scn, "[^A-Z0-9]", ""));
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
            highMask = isfinite(hUT) & hUT > 13 & hUT <= 23;
            if any(highMask(:))
                cPrime = zeros(size(d));
                cPrime(highMask) = ((hUT(highMask) - 13) ./ 10).^1.5;
                correction = 1 + cPrime .* (5/4) .* (d ./ 100).^3 .* exp(-d ./ 150);
                pLOS = pLOS .* correction;
            end
        end
        status.Source = "tr38901_uma_closed_form_los_probability";
        status.ComplianceStatus = "scenario_specific_tr38901_curve";
        status.KnownScenario = true;
        status.StrictSupported = true;

    case {"UMI","UMISTREETCANYON"}
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

    case {"INH","INHMIXEDOFFICE"}
        % InH mixed office: TR 38.901 Table 7.4.2-1.
        pLOS = ones(size(d));
        mid = d > 1.2 & d < 6.5;
        pLOS(mid) = exp(-(d(mid) - 1.2) ./ 4.7);
        far = d >= 6.5;
        pLOS(far) = 0.32 .* exp(-(d(far) - 6.5) ./ 32.6);
        status.Source = "tr38901_inh_mixed_office_closed_form_los_probability";
        status.ComplianceStatus = "scenario_specific_tr38901_curve";
        status.KnownScenario = true;
        status.StrictSupported = true;

    case "INHOPENOFFICE"
        pLOS = ones(size(d));
        mid = d > 5 & d <= 49;
        pLOS(mid) = 0.9 .* exp(-(d(mid) - 5) ./ 70.8);
        far = d > 49;
        pLOS(far) = 0.54 .* exp(-(d(far) - 49) ./ 211.7);
        status.Source = "tr38901_inh_open_office_closed_form_los_probability";
        status.ComplianceStatus = "scenario_specific_tr38901_curve";
        status.KnownScenario = true;
        status.StrictSupported = true;

    otherwise
        error("CHANNEL:UnknownLOSScenario", ...
            "No pinned LOS-probability equation exists for scenario '%s'.", ...
            char(string(scenarioName)));
end

% Clamp
pLOS = max(min(pLOS, 1), 0);

end
