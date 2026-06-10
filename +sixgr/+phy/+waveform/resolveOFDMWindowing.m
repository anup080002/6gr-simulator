function [windowingSamples, info] = resolveOFDMWindowing(cfg, carrier)
%RESOLVEOFDMWINDOWING Resolve explicit OFDM windowing in samples.
%
% The value passed to nrOFDMModulate is a sample count. Researchers may set
% it directly or as a fraction of Nfft; absent config uses a conservative
% raised-cosine edge of 2.5% of Nfft instead of an implicit rectangular
% waveform.

if nargin < 1 || isempty(cfg)
    cfg = struct();
end

explicitSamples = localFirstFiniteScalar( ...
    sixgr.util.structGet(cfg, "phy.ofdm.windowingSamples", []), ...
    sixgr.util.structGet(cfg, "phy.waveform.ofdmWindowingSamples", []), ...
    sixgr.util.structGet(cfg, "phy.waveform.windowingSamples", []));
explicitPercent = localFirstFiniteScalar( ...
    sixgr.util.structGet(cfg, "phy.ofdm.windowingPercent", []), ...
    sixgr.util.structGet(cfg, "phy.waveform.ofdmWindowingPercent", []), ...
    sixgr.util.structGet(cfg, "phy.waveform.windowingPercent", []));

source = "phy.ofdm.windowingPercent_default";
if isfinite(explicitSamples)
    windowingSamples = max(0, round(double(explicitSamples)));
    source = "configured_windowing_samples";
elseif isfinite(explicitPercent)
    windowingSamples = max(0, round(double(explicitPercent) * localNfft(carrier)));
    source = "configured_windowing_percent";
else
    windowingSamples = max(0, round(0.025 * localNfft(carrier)));
end

info = struct( ...
    "OFDMWindowingSamples", double(windowingSamples), ...
    "OFDMWindowingSource", char(source), ...
    "OFDMWindowingEnabled", logical(windowingSamples > 0));
end

function nfft = localNfft(carrier)
nfft = NaN;
try
    ofdmInfo = nrOFDMInfo(carrier);
    nfft = double(sixgr.util.structGet(ofdmInfo, "Nfft", NaN));
catch
end
if ~(isfinite(nfft) && nfft > 0)
    nrb = double(sixgr.util.structGet(carrier, "NSizeGrid", 52));
    nfft = 2 ^ nextpow2(max(128, 12 * max(1, nrb)));
end
end

function value = localFirstFiniteScalar(varargin)
value = NaN;
for i = 1:nargin
    raw = varargin{i};
    if isempty(raw)
        continue;
    end
    if isnumeric(raw) || islogical(raw)
        raw = double(raw);
        if isscalar(raw) && isfinite(raw)
            value = raw;
            return;
        end
    end
end
end
