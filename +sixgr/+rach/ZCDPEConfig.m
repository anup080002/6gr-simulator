function zcdpeCfg = ZCDPEConfig(baseCfg, varargin)
%ZCDPECONFIG Resolve ZC-DPE PRACH design parameters.

if nargin < 1 || isempty(baseCfg)
    baseCfg = struct();
end

p = inputParser;
p.FunctionName = "sixgr.rach.ZCDPEConfig";
addRequired(p, "baseCfg", @(x) isstruct(x) || isobject(x));
addParameter(p, "DPI_D", [], @(x) isempty(x) || (isscalar(x) && isnumeric(x) && isfinite(x)));
addParameter(p, "DPIIndex", [], @(x) isempty(x) || isnumeric(x));
addParameter(p, "NumSymbols", [], @(x) isempty(x) || (isscalar(x) && isnumeric(x) && isfinite(x)));
parse(p, baseCfg, varargin{:});
opts = p.Results;

cfg = localStructFromInput(baseCfg);
zcdpeEnabled = logical(localFirstNonEmpty( ...
    sixgr.util.structGet(cfg, "ZCDPE.Enable", []), ...
    sixgr.util.structGet(cfg, "zcdpe.enable", []), ...
    sixgr.util.structGet(cfg, "random_access.zcdpe_enabled", []), false));
D = round(double(localFirstNonEmpty(opts.DPI_D, ...
    sixgr.util.structGet(cfg, "ZCDPE.DPI_D", []), ...
    sixgr.util.structGet(cfg, "zcdpe.dpi_D", []), ...
    sixgr.util.structGet(cfg, "zcdpe.dpi_d_count", []), ...
    sixgr.util.structGet(cfg, "random_access.zcdpe_dpi_D", []), 4)));
d = double(localFirstNonEmpty(opts.DPIIndex, ...
    sixgr.util.structGet(cfg, "ZCDPE.DPI_d", []), ...
    sixgr.util.structGet(cfg, "zcdpe.dpi_d", []), ...
    sixgr.util.structGet(cfg, "random_access.zcdpe_dpi_d", []), 0));
M = round(double(localFirstNonEmpty(opts.NumSymbols, ...
    sixgr.util.structGet(cfg, "ZCDPE.NumSymbols", []), ...
    sixgr.util.structGet(cfg, "zcdpe.num_symbols", []), ...
    sixgr.util.structGet(cfg, "random_access.zcdpe_num_symbols", []), ...
    sixgr.util.structGet(cfg, "ToolboxPRACH.NumOccupiedSymbols", []), 1)));

if ~(isfinite(D) && D >= 1 && D <= 12 && D == round(D))
    error("sixgr:rach:ZCDPEConfig:InvalidD", "ZC-DPE DPI_D must be an integer in [1..12]. Got: %g", D);
end
if isempty(d)
    d = 0;
end
d = round(double(d));
if any(~isfinite(d)) || any(d < 0) || any(d > D-1)
    error("sixgr:rach:ZCDPEConfig:InvalidDPIIndex", "ZC-DPE DPI_d must be in [0..DPI_D-1].");
end
if ~(isfinite(M) && M >= 1 && M <= 12 && M == round(M))
    error("sixgr:rach:ZCDPEConfig:InvalidM", "ZC-DPE NumSymbols must be an integer in [1..12]. Got: %g", M);
end

rho2 = localDPICrossCorrelation(D, M);
if zcdpeEnabled && mod(M, D) ~= 0
    warning("sixgr:rach:ZCDPEConfig:NonOrthogonal", ...
        "D=%g does not divide M=%g. DPI hypotheses are not exactly orthogonal (|rho|^2 = %.4f). Use D=4 or D=6 for M=12, D=4 for M=4.", ...
        D, M, rho2);
end
if zcdpeEnabled && D == 5 && M == 12
    warning("sixgr:rach:ZCDPEConfig:D5M12Stress", ...
        "D=5 with M=12 gives |rho|^2=%.4f and is only valid as a non-orthogonal stress case.", rho2);
end

freqSearchPoints = round(double(localFirstNonEmpty( ...
    sixgr.util.structGet(cfg, "ZCDPE.FreqSearchPoints", []), ...
    sixgr.util.structGet(cfg, "zcdpe.freq_search_points", []), ...
    sixgr.util.structGet(cfg, "random_access.zcdpe_freq_search_points", []), 64)));
residualBound = double(localFirstNonEmpty( ...
    sixgr.util.structGet(cfg, "ZCDPE.ResidualFreqBound_Hz", []), ...
    sixgr.util.structGet(cfg, "zcdpe.residual_freq_bound_hz", []), ...
    sixgr.util.structGet(cfg, "random_access.zcdpe_residual_freq_bound_hz", []), Inf));

zcdpeCfg = struct();
zcdpeCfg.DPI_D = D;
zcdpeCfg.DPI_d = d;
zcdpeCfg.NumSymbols = M;
zcdpeCfg.IsOrthogonal = mod(M, D) == 0;
zcdpeCfg.PhaseStep_rad = 2*pi*d./D;
zcdpeCfg.TheoreticalPool = 64 * D;
zcdpeCfg.PoolGainFactor = D;
zcdpeCfg.IsBackwardCompat = all(d == 0);
zcdpeCfg.FreqSearchPoints = max(1, freqSearchPoints);
zcdpeCfg.ResidualFreqBound_Hz = residualBound;
zcdpeCfg.CrossCorrelationAbsSq = rho2;
end

function cfg = localStructFromInput(baseCfg)
if isstruct(baseCfg)
    cfg = baseCfg;
elseif isobject(baseCfg)
    cfg = struct(baseCfg);
else
    cfg = struct();
end
end

function value = localFirstNonEmpty(varargin)
value = [];
for iArg = 1:nargin
    candidate = varargin{iArg};
    if isempty(candidate)
        continue;
    end
    value = candidate;
    return;
end
end

function rho2 = localDPICrossCorrelation(D, M)
if D <= 1
    rho2 = 0;
    return;
end
if M <= 1
    rho2 = 1;
    return;
end
delta = 2*pi / D;
num = sin(M * delta / 2);
den = M * sin(delta / 2);
if abs(den) < eps
    rho2 = 1;
else
    rho2 = abs(num / den)^2;
end
end
