function [pathGainsOut, info] = deembedDopplerFromPathGains(pathGainsIn, sampleTimes_s, perPathDoppler_Hz, varargin)
%DEEMBEDDOPPLERFROMPATHGAINS Remove known per-path Doppler phase rotation.
%
% The operation is intentionally defined on channel path-gain tensors, not on
% a composite received waveform:
%   h_p,deembed(t) = h_p(t) exp(-j 2 pi f_D,p (t - t_ref)).
%
% Tensor contract: dimension 1 is time/sample, dimension 2 is path. Any
% remaining dimensions are preserved (Tx/Rx antennas, polarization, etc.).

ip = inputParser;
ip.addParameter("ReferenceTime_s", NaN, @(x) isnumeric(x) && isscalar(x));
ip.parse(varargin{:});

pathGainsOut = pathGainsIn;
info = struct( ...
    "ContractVersion", "sixgr.phy.sync.PerPathDopplerDeembedding/v1", ...
    "Applied", false, ...
    "Status", "not_applied", ...
    "SampleCount", 0, ...
    "PathCount", 0, ...
    "ReferenceTime_s", NaN, ...
    "MaxAbsDoppler_Hz", NaN, ...
    "Equation", "h_out(t,p)=h_in(t,p)*exp(-j*2*pi*fD(p)*(t-t_ref))");

if isempty(pathGainsIn)
    info.Status = "empty_path_gains";
    return;
end
if ~isnumeric(pathGainsIn)
    error("sixgr:phy:sync:DopplerPathGainsNonNumeric", ...
        "Path gains must be numeric for per-path Doppler de-embedding.");
end

sampleTimes_s = double(sampleTimes_s(:));
fd = double(perPathDoppler_Hz(:)).';
nSamples = size(pathGainsIn, 1);
nPaths = size(pathGainsIn, 2);
if numel(sampleTimes_s) ~= nSamples
    error("sixgr:phy:sync:DopplerSampleTimeMismatch", ...
        "sampleTimes_s length (%d) must match pathGains dimension 1 (%d).", ...
        numel(sampleTimes_s), nSamples);
end
if numel(fd) ~= nPaths
    error("sixgr:phy:sync:DopplerPathCountMismatch", ...
        "perPathDoppler_Hz length (%d) must match pathGains dimension 2 (%d).", ...
        numel(fd), nPaths);
end
if any(~isfinite(sampleTimes_s)) || any(~isfinite(fd))
    error("sixgr:phy:sync:DopplerNonFiniteInput", ...
        "sampleTimes_s and perPathDoppler_Hz must be finite.");
end

tRef = double(ip.Results.ReferenceTime_s);
if ~(isscalar(tRef) && isfinite(tRef))
    tRef = sampleTimes_s(1);
end
phase = exp(-1j .* 2 .* pi .* (sampleTimes_s - tRef) .* fd);
shape = ones(1, max(ndims(pathGainsIn), 2));
shape(1) = nSamples;
shape(2) = nPaths;
pathGainsOut = pathGainsIn .* cast(reshape(phase, shape), "like", pathGainsIn);

info.Applied = true;
info.Status = "applied_per_path_path_gain_phase_deembedding";
info.SampleCount = double(nSamples);
info.PathCount = double(nPaths);
info.ReferenceTime_s = double(tRef);
info.MaxAbsDoppler_Hz = max(abs(fd), [], "omitnan");
end
