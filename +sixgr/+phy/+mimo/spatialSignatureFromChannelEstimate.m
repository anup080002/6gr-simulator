function signature = spatialSignatureFromChannelEstimate(hEst, varargin)
%SPATIALSIGNATUREFROMCHANNELESTIMATE Build a measured wideband spatial matrix.
%
% NR channel estimates use K-by-L-by-Nrx-by-Ntx ordering.  Averaging the
% actual estimate over frequency and OFDM symbols preserves the receiver
% and transmitter spatial axes used for inter-user subspace leakage. When
% a measured Rank is supplied, return the dominant measured receive
% subspace at that rank. This prevents unused/noise-dominated antenna modes
% from being presented to the scheduler as active spatial streams.

p = inputParser;
p.addParameter("Rank", NaN, @(x)isnumeric(x) && isscalar(x));
p.parse(varargin{:});
measuredRank = double(p.Results.Rank);

if ~isnumeric(hEst) || isempty(hEst) || ...
        any(~isfinite(real(hEst(:))) | ~isfinite(imag(hEst(:))))
    error("sixgr:mimo:InvalidChannelEstimateForSpatialSignature", ...
        "A finite, nonempty numeric channel estimate is required.");
end

dims = size(hEst);
if numel(dims) < 3
    signature = complex(mean(hEst(:)), 0);
    if ~isreal(hEst)
        signature = mean(hEst(:));
    end
else
    wideband = mean(mean(double(hEst), 1), 2);
    if numel(dims) == 3
        signature = reshape(wideband, dims(3), 1);
    else
        signature = reshape(wideband, dims(3), prod(dims(4:end)));
    end
end
if isempty(signature) || any(~isfinite(real(signature(:))) | ...
        ~isfinite(imag(signature(:)))) || norm(signature, "fro") <= 0
    error("sixgr:mimo:InvalidChannelEstimateForSpatialSignature", ...
        "The measured wideband channel signature is nonfinite or zero-power.");
end
signature = double(signature);
if isfinite(measuredRank) && measuredRank >= 1
    measuredRank = min(max(1, round(measuredRank)), min(size(signature)));
    [dominantSubspace, ~, ~] = svd(signature, "econ");
    signature = dominantSubspace(:, 1:measuredRank);
end
signature = signature ./ norm(signature, "fro");
end
