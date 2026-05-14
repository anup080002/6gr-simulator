function [LdB, status] = O2ILoss(fc_Hz, model, varargin)
% sixgr.channel.O2ILoss
%
% Outdoor-to-Indoor (O2I) penetration + indoor loss model.
% Provides a configurable approximation suitable for system-level studies.
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
%   - This implementation is intentionally simple and configurable.
%   - For strict TR 38.901 compliance, replace the parameterization with
%     the exact table-based building penetration loss model.
%   - ASCII-only file.

opt.IndoorDistance_m = 10;
opt.CustomLoss_dB = 0;
opt.Stream = [];

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
    "IndoorLossModel", "linear_0p5_db_per_meter_proxy", ...
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
    % Frequency-dependent penetration loss approximation.
    % These are conservative defaults:
    %   - low-loss: standard glass / light materials
    %   - high-loss: IRR glass + concrete-like materials
    %
    % You should calibrate these constants for your study.
    if m == "low"
        % ~ 12 dB @ 3.5 GHz, ~ 28 dB @ 28 GHz
        L_pen = 5 + 0.30*fc_GHz + 10*log10(max(fc_GHz,1e-3));
        sigma = 4;
        status.ModelSource = "approximate_tr38901_plus_low_loss_penetration_proxy";
        status.ComplianceStatus = "approximate_o2i_model";
        status.Reason = "low loss o2i uses a simplified frequency-dependent proxy plus random spread rather than the exact tr38901 building penetration table";
    elseif m == "high"
        % ~ 20 dB @ 3.5 GHz, ~ 40 dB @ 28 GHz
        L_pen = 10 + 0.45*fc_GHz + 15*log10(max(fc_GHz,1e-3));
        sigma = 6;
        status.ModelSource = "approximate_tr38901_plus_high_loss_penetration_proxy";
        status.ComplianceStatus = "approximate_o2i_model";
        status.Reason = "high loss o2i uses a simplified frequency-dependent proxy plus random spread rather than the exact tr38901 building penetration table";
    else
        % Unknown -> treat as low
        L_pen = 5 + 0.30*fc_GHz + 10*log10(max(fc_GHz,1e-3));
        sigma = 4;
        status.ModelSource = "approximate_o2i_unknown_model_defaulted_to_low_loss_proxy";
        status.ComplianceStatus = "approximate_o2i_model_unknown_token_defaulted";
        status.Reason = sprintf("unknown o2i model '%s' defaulted to the low-loss proxy", char(m));
    end

    % Add random term (log-normal around penetration loss)
    if ~isempty(opt.Stream)
        rnd = randn(opt.Stream,1,1);
    else
        rnd = randn;
    end
    L_pen = L_pen + sigma*rnd;
    status.RandomComponentApplied = true;
end

% Indoor loss: simple linear loss vs indoor distance
dIn = max(opt.IndoorDistance_m, 0);
L_in = 0.5 * dIn;  % 0.5 dB per meter (configurable later)

LdB = max(L_pen + L_in, 0);

end
