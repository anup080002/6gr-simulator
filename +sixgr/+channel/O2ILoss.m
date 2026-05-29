function [LdB, status] = O2ILoss(fc_Hz, model, varargin)
% sixgr.channel.O2ILoss
%
% Outdoor-to-Indoor (O2I) penetration + indoor loss model.
%
% Inputs:
%   fc_Hz : carrier frequency (Hz)
%   model : "none" | "low" | "high" | "custom"
%
% Name-value:
%   "IndoorDistance_m" : indoor distance (m). Default 10 m.
%   "CustomLoss_dB"    : used if model="custom"
%   "Stream"           : RandStream for random component (optional)
%
% Output:
%   LdB : total O2I loss in dB
%
% Notes:
%   - The "low" and "high" models implement 3GPP TR 38.901 Table 7.4.3-1
%     material-mixture penetration loss plus the indoor-distance term.
%   - The "custom" model remains caller-supplied and is explicitly marked
%     non-strict.
%   - ASCII-only file.

opt.IndoorDistance_m = 10;
opt.CustomLoss_dB = 0;
opt.Stream = [];
opt.RandomComponentEnabled = true;

if mod(numel(varargin),2) ~= 0
    error("O2ILoss:BadNV","Name-value inputs must come in pairs.");
end
for i = 1:2:numel(varargin)
    name = string(varargin{i});
    val  = varargin{i+1};
    switch lower(name)
        case {"indoordistance_m","dindoor_m","dindoor"}
            opt.IndoorDistance_m = double(val);
        case {"customloss_db","custom_db"}
            opt.CustomLoss_dB = double(val);
        case "stream"
            opt.Stream = val;
        case {"randomcomponentenabled","applyrandomcomponent"}
            opt.RandomComponentEnabled = logical(val);
        otherwise
            error("O2ILoss:UnknownOpt","Unknown option: %s", name);
    end
end

fc_GHz = double(fc_Hz)/1e9;
m = lower(strtrim(string(model)));
status = struct( ...
    "ModelSource", "", ...
    "ComplianceStatus", "", ...
    "Reason", "", ...
    "StrictSupported", false, ...
    "IndoorLossModel", "tr38901_table_7_4_3_1_indoor_distance_loss", ...
    "RandomComponentApplied", false);

if m == "none" || m == "off"
    LdB = 0;
    status.ModelSource = "o2i_disabled";
    status.ComplianceStatus = "not_applicable_o2i_disabled";
    status.StrictSupported = true;
    return;
end

if m == "custom"
    L_pen = opt.CustomLoss_dB;
    status.ModelSource = "configured_custom_o2i_loss";
    status.ComplianceStatus = "configured_custom_o2i_loss_not_strict_38901";
    status.Reason = "custom configured o2i loss is caller supplied and not a strict tr38901 building penetration model";
else
    f = max(fc_GHz, 1e-3);
    lGlass = 2 + 0.2 * f;
    lIRRGlass = 23 + 0.3 * f;
    lConcrete = 5 + 4 * f;
    if m == "low"
        L_pen = 5 - 10 * log10(0.3 * 10.^(-lGlass/10) + 0.7 * 10.^(-lConcrete/10));
        sigma = 4.4;
        status.ModelSource = "tr38901_table_7_4_3_1_low_loss_building";
        status.ComplianceStatus = "strict_38901_o2i_model";
        status.StrictSupported = true;
    elseif m == "high"
        L_pen = 5 - 10 * log10(0.7 * 10.^(-lIRRGlass/10) + 0.3 * 10.^(-lConcrete/10));
        sigma = 6.5;
        status.ModelSource = "tr38901_table_7_4_3_1_high_loss_building";
        status.ComplianceStatus = "strict_38901_o2i_model";
        status.StrictSupported = true;
    else
        error("O2ILoss:UnsupportedModel", ...
            "O2I model must be 'none', 'low', 'high', or 'custom'; got '%s'.", char(m));
    end

    % Add TR 38.901 log-normal penetration-loss random component.
    if logical(opt.RandomComponentEnabled)
        if ~isempty(opt.Stream)
            rnd = randn(opt.Stream,1,1);
        else
            rnd = randn;
        end
        L_pen = L_pen + sigma*rnd;
        status.RandomComponentApplied = true;
    else
        status.RandomComponentApplied = false;
    end
end

% Indoor loss: simple linear loss vs indoor distance
dIn = max(opt.IndoorDistance_m, 0);
L_in = 0.5 * dIn;  % 0.5 dB per meter (configurable later)

LdB = max(L_pen + L_in, 0);

end
