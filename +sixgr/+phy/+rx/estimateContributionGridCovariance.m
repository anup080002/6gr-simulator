function [Rint, info] = estimateContributionGridCovariance(contributionTensor, carrier, ...
        dataInd, appliedTimingCorrection, source, domain, signalName)
%ESTIMATECONTRIBUTIONGRIDCOVARIANCE Covariance from shared-slot contributors.
%   CONTRIBUTIONTENSOR is Nsamp-by-Nrx-by-Nsrc in receiver sample domain.
%   The estimator demodulates the summed interference waveform and measures
%   covariance on the exact data REs used by the victim receiver.

if nargin < 7 || strlength(strtrim(string(signalName))) == 0
    signalName = "data";
end
signalName = lower(strtrim(string(signalName)));
Rint = [];
info = struct("Available", false, ...
    "Source", "shared_slot_contribution_grid_covariance_unavailable", ...
    "Status", "unavailable", ...
    "NAReason", "no_interference_contribution_tensor", ...
    "Domain", "resource_grid_" + signalName + "_re_receive_antenna_covariance", ...
    "CovarianceIncludesNoise", false, ...
    "NumSamples", 0, ...
    "ContributionSource", char(string(source)), ...
    "ContributionDomain", char(string(domain)));

if isempty(contributionTensor)
    return;
end
if ~isnumeric(contributionTensor) || size(contributionTensor, 1) < 1 || size(contributionTensor, 2) < 1
    info.NAReason = "contribution_tensor_must_have_sample_and_rx_dimensions";
    return;
end

try
    interferenceWave = sum(contributionTensor, 3);
    interferenceWave = localApplyTimingCorrection(interferenceWave, appliedTimingCorrection);
    interferenceGrid = sixgr.phy.waveform.ofdmDemodulate(carrier, interferenceWave);
    interferenceRE = nrExtractResources(dataInd, interferenceGrid);
catch ME
    info.Status = "contribution_grid_covariance_failed";
    info.NAReason = string(ME.identifier);
    return;
end

if isempty(interferenceRE)
    info.NAReason = "no_" + signalName + "_re_interference_samples";
    return;
end
if isvector(interferenceRE)
    interferenceRE = interferenceRE(:);
end
finiteRows = all(isfinite(real(interferenceRE)) & isfinite(imag(interferenceRE)), 2);
interferenceRE = double(interferenceRE(finiteRows, :));
if size(interferenceRE, 1) < 2
    info.NAReason = "insufficient_finite_" + signalName + "_re_interference_samples";
    return;
end

R = (interferenceRE' * interferenceRE) ./ max(1, size(interferenceRE, 1));
R = (R + R') ./ 2;
if any(~isfinite(real(R(:)))) || any(~isfinite(imag(R(:))))
    info.NAReason = "nonfinite_contribution_covariance";
    return;
end

Rint = R;
info.Available = true;
info.Source = "shared_slot_contribution_grid_covariance";
info.Status = "OK";
info.NAReason = "";
info.NumSamples = double(size(interferenceRE, 1));
info.NumRxAnt = double(size(interferenceRE, 2));
end

function y = localApplyTimingCorrection(x, timingOffset)
y = x;
timingOffset = double(timingOffset);
if ~(isscalar(timingOffset) && isfinite(timingOffset) && abs(timingOffset) > 0)
    return;
end
shift = round(timingOffset);
if shift > 0
    if shift < size(x, 1)
        y = x(shift+1:end, :);
        y(end+1:size(x,1), :) = cast(0, "like", x);
    end
elseif shift < 0
    shift = abs(shift);
    y = [zeros(shift, size(x,2), "like", x); x];
    y = y(1:size(x,1), :);
end
end
