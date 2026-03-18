function [csi, info] = CSI_Feedback(hEst, nVar, cfg, varargin)
%CSI_Feedback Compute basic CSI feedback hooks (CQI/PMI/RI) for simulator.
%
%   [CSI,INFO] = sixgr.phy.dl.CSI_Feedback(HEST, NVAR, CFG) computes a
%   lightweight CSI report that can be used by higher layers (scheduler,
%   link adaptation). This module is intentionally designed as a "hook":
%   - If 5G Toolbox CSI selection helpers are available in the running
%     MATLAB version, you can enable them later without touching callers.
%   - By default, it uses a conservative, SINR-to-CQI mapping suitable for
%     smoke tests.
%
%   Inputs:
%     HEST : Channel estimate. Any numeric array; average power is used.
%     NVAR : Noise variance (scalar, linear).
%     CFG  : Simulator config struct.
%
%   Name-Value options:
%     "Method"        : "simple" (default) or "toolbox".
%     "MaxRank"       : max RI to report (default 1).
%     "WidebandOnly"  : true (default).
%
%   Outputs:
%     CSI.CQI : [0..15] wideband CQI (0 means out-of-range)
%     CSI.RI  : rank indicator (>=1)
%     CSI.PMI : placeholder PMI index (>=0)

ip = inputParser;
ip.addParameter('Method', "simple", @(s) ischar(s) || isstring(s));
ip.addParameter('MaxRank', 1, @(x) isnumeric(x) && isscalar(x) && x>=1);
ip.addParameter('WidebandOnly', true, @(x) islogical(x) && isscalar(x));
ip.parse(varargin{:});
opt = ip.Results;

method = lower(string(opt.Method));

% Basic sanity
if isempty(hEst)
    hPow = 0;
else
    hPow = mean(abs(hEst(:)).^2);
end
nVar = double(nVar);
if ~isfinite(nVar) || nVar < 0
    nVar = 0;
end

% Wideband SINR estimate (very simple)
if nVar == 0
    sinrLin = inf;
else
    sinrLin = hPow / nVar;
end
sinr_dB = 10*log10(sinrLin);

% Defaults
ri = min(double(opt.MaxRank), 1);
pmi = 0;

cqi = 0;
engineUsed = "simple";

if method == "toolbox"
    % Optional: attempt to use toolbox CSI selection helpers if present.
    % We keep this guarded to avoid runtime failures across MATLAB releases.
    if exist('nrCQISelect','file') == 2
        try
            % Many toolbox CSI helpers require a CSI-RS configuration and
            % per-subband processing. We keep a narrow wideband fallback:
            % use SINR-based CQI mapping below even if function exists.
            engineUsed = "toolbox-present";
        catch
            engineUsed = "simple";
        end
    end
end

% Simple SINR->CQI mapping (wideband)
% This is a conservative mapping intended for link smoke tests. Replace with
% 3GPP table-based mapping when the CSI-RS measurement module is integrated.
thresholds_dB = [-inf -5 -2 0 2 4 6 8 10 12 14 16 18 20 22 24];
% thresholds_dB(k) corresponds to CQI=k-1. Output range [0..15].
idx = find(sinr_dB >= thresholds_dB, 1, 'last');
if isempty(idx)
    cqi = 0;
else
    cqi = max(0, min(15, idx-1));
end

csi = struct();
csi.CQI = double(cqi);
csi.RI = double(ri);
csi.PMI = double(pmi);
csi.SINR_dB = double(sinr_dB);

info = struct();
info.Method = char(method);
info.EngineUsed = char(engineUsed);
info.NoiseVar = nVar;
info.ChannelPower = hPow;
info.WidebandOnly = logical(opt.WidebandOnly);

% Keep a hook for future per-UE, per-subband reporting
info.Hints = struct();
info.Hints.AddCSIRSBasedCQI = true;
info.Hints.AddPMISelection = true;
info.Hints.AddRISelection = true;

% Echo a few config knobs used by later schedulers
info.Config = struct();
info.Config.TargetBLER = double(sixgr.util.structGet(cfg, 'phy.pdsch.targetBLER', 0.1));

end
