function [pathloss_dB, meta] = Pathloss38901(scenario, condition, fc_GHz, ...
    distance2D_m, hBS_m, hUT_m, streetWidth_m, buildingHeight_m)
%PATHLOSS38901 Deterministic TR 38.901 V19.2.0 pathloss equations.
%
% This function is the strict analytical large-scale pathloss boundary used
% when a toolbox nrPathLoss execution is unavailable. It does not add
% shadow fading, O2I loss, oxygen loss, or any other random component.

arguments
    scenario
    condition
    fc_GHz (1,1) double {mustBeFinite,mustBePositive}
    distance2D_m double {mustBeFinite,mustBeNonnegative}
    hBS_m double {mustBeFinite,mustBePositive}
    hUT_m double {mustBeFinite,mustBePositive}
    streetWidth_m double = 20
    buildingHeight_m double = 5
end

scenario = localScenario(scenario);
condition = upper(strtrim(string(condition)));
if ~any(condition == ["LOS","NLOS"])
    error("CHANNEL:UnsupportedProfile", ...
        "Pathloss condition must be LOS or NLOS; got '%s'.", condition);
end
if ~any(scenario == ["UMa","UMi-StreetCanyon","RMa","InH-Office"])
    error("CHANNEL:UnsupportedProfile", ...
        "No enabled strict TR 38.901 pathloss profile exists for '%s'.", scenario);
end

sz = size(distance2D_m);
d2D = double(distance2D_m);
hBS = localExpand(hBS_m, sz, "hBS_m");
hUT = localExpand(hUT_m, sz, "hUT_m");
w = localExpand(streetWidth_m, sz, "streetWidth_m");
h = localExpand(buildingHeight_m, sz, "buildingHeight_m");
if any(~isfinite(w(:)) | w(:) <= 0 | ~isfinite(h(:)) | h(:) <= 0)
    error("CHANNEL:InvalidGeometry", ...
        "Street width and building height must be finite and positive.");
end
d3D = hypot(d2D, hBS - hUT);
c = 299792458;
fc_Hz = fc_GHz * 1e9;
breakpoint = nan(sz);

switch scenario
    case "UMa"
        localRange(d2D, 10, 5000, scenario);
        breakpoint = 4 .* (hBS - 1) .* (hUT - 1) .* fc_Hz ./ c;
        pl1 = 28 + 22 .* log10(d3D) + 20 .* log10(fc_GHz);
        pl2 = 28 + 40 .* log10(d3D) + 20 .* log10(fc_GHz) ...
            - 9 .* log10(breakpoint.^2 + (hBS - hUT).^2);
        plLOS = pl1;
        plLOS(d2D > breakpoint) = pl2(d2D > breakpoint);
        plNLOS = max(plLOS, 13.54 + 39.08 .* log10(d3D) ...
            + 20 .* log10(fc_GHz) - 0.6 .* (hUT - 1.5));

    case "UMi-StreetCanyon"
        localRange(d2D, 10, 5000, scenario);
        breakpoint = 4 .* (hBS - 1) .* (hUT - 1) .* fc_Hz ./ c;
        pl1 = 32.4 + 21 .* log10(d3D) + 20 .* log10(fc_GHz);
        pl2 = 32.4 + 40 .* log10(d3D) + 20 .* log10(fc_GHz) ...
            - 9.5 .* log10(breakpoint.^2 + (hBS - hUT).^2);
        plLOS = pl1;
        plLOS(d2D > breakpoint) = pl2(d2D > breakpoint);
        plNLOS = max(plLOS, 22.4 + 35.3 .* log10(d3D) ...
            + 21.3 .* log10(fc_GHz) - 0.3 .* (hUT - 1.5));

    case "RMa"
        localRange(d2D, 10, 10000, scenario);
        breakpoint = 2 .* pi .* hBS .* hUT .* fc_Hz ./ c;
        breakpoint3D = hypot(breakpoint, hBS - hUT);
        losAt = @(d) 20 .* log10(40 .* pi .* d .* fc_GHz ./ 3) ...
            + min(0.03 .* h.^1.72, 10) .* log10(d) ...
            - min(0.044 .* h.^1.72, 14.77) ...
            + 0.002 .* log10(h) .* d;
        pl1 = losAt(d3D);
        pl2 = losAt(breakpoint3D) + 40 .* log10(d3D ./ breakpoint3D);
        plLOS = pl1;
        plLOS(d2D > breakpoint) = pl2(d2D > breakpoint);
        plNLOS = max(plLOS, 161.04 - 7.1 .* log10(w) + 7.5 .* log10(h) ...
            - (24.37 - 3.7 .* (h ./ hBS).^2) .* log10(hBS) ...
            + (43.42 - 3.1 .* log10(hBS)) .* (log10(d3D) - 3) ...
            + 20 .* log10(fc_GHz) ...
            - (3.2 .* (log10(11.75 .* hUT)).^2 - 4.97));

    case "InH-Office"
        localRange(d2D, 1, 150, scenario);
        plLOS = 32.4 + 17.3 .* log10(d3D) + 20 .* log10(fc_GHz);
        plNLOS = max(plLOS, 17.3 + 38.3 .* log10(d3D) ...
            + 24.9 .* log10(fc_GHz));

end

pathloss_dB = plLOS;
if condition == "NLOS"
    pathloss_dB = plNLOS;
end
meta = struct( ...
    "Scenario", scenario, ...
    "Condition", condition, ...
    "Distance3D_m", d3D, ...
    "BreakpointDistance_m", breakpoint, ...
    "SpecVersion", "TR38.901-V19.2.0", ...
    "ExecutionBackend", "tr38901_v19_2_0_closed_form", ...
    "ApproximationMode", "none");
end

function value = localExpand(value, sz, field)
value = double(value);
if isscalar(value)
    value = repmat(value, sz);
elseif ~isequal(size(value), sz)
    error("CHANNEL:InvalidGeometry", ...
        "%s must be scalar or match distance2D_m.", field);
end
end

function localRange(value, lowerBound, upperBound, scenario)
if any(value(:) < lowerBound | value(:) > upperBound)
    error("CHANNEL:PathlossOutOfRange", ...
        "%s pathloss requires distance2D_m in [%g,%g] m.", ...
        scenario, lowerBound, upperBound);
end
end

function scenario = localScenario(value)
token = lower(regexprep(strtrim(string(value)), "[^a-z0-9]", ""));
switch token
    case "uma"
        scenario = "UMa";
    case {"umi","umistreetcanyon"}
        scenario = "UMi-StreetCanyon";
    case "rma"
        scenario = "RMa";
    case {"inh","inhoffice"}
        scenario = "InH-Office";
    otherwise
        scenario = string(value);
end
end
