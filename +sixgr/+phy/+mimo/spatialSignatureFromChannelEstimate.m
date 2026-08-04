function [signature, info] = spatialSignatureFromChannelEstimate(hEst, varargin)
%SPATIALSIGNATUREFROMCHANNELESTIMATE Build measured receiver-subspace evidence.
%
% NR channel estimates use K-by-L-by-Nrx-by-Ntx ordering. The legacy
% dominant_scheduled_rank mode reduces K and L to one wideband channel and
% retains the scheduled receive subspace. The strict
% complete_detectable_subspace mode does not average frequency-selective
% channel snapshots: it forms an Nrx-by-(K*L*Ntx) observation matrix and
% retains every singular direction above a receiver-noise-derived bound.

p = inputParser;
p.addParameter("Rank", NaN, @(x)isnumeric(x) && isscalar(x));
p.addParameter("SubspaceMode", "dominant_scheduled_rank", ...
    @(x)ischar(x) || (isstring(x) && isscalar(x)));
p.addParameter("NoiseVariance", [], ...
    @(x)isempty(x) || (isnumeric(x) && isscalar(x) && isfinite(x) && x >= 0));
p.addParameter("NoiseMargin_dB", [], ...
    @(x)isempty(x) || (isnumeric(x) && isscalar(x) && isfinite(x) && x >= 0));
p.parse(varargin{:});
measuredRank = double(p.Results.Rank);
subspaceMode = lower(strtrim(string(p.Results.SubspaceMode)));
if ~ismember(subspaceMode, ["dominant_scheduled_rank", ...
        "complete_detectable_subspace"])
    error("sixgr:mimo:InvalidSpatialSignatureSubspaceMode", ...
        "SubspaceMode must be dominant_scheduled_rank or " + ...
        "complete_detectable_subspace.");
end

if subspaceMode == "complete_detectable_subspace"
    if isempty(p.Results.NoiseVariance)
        error("sixgr:mimo:MissingSpatialSignatureNoiseVariance", ...
            "complete_detectable_subspace requires the measured receiver " + ...
            "noise variance; a hidden or configured-value substitute is forbidden.");
    end
    if isempty(p.Results.NoiseMargin_dB)
        error("sixgr:mimo:MissingSpatialSignatureNoiseMargin", ...
            "complete_detectable_subspace requires an explicit YAML-owned " + ...
            "noise margin in dB.");
    end
end

if ~isnumeric(hEst) || isempty(hEst) || ...
        any(~isfinite(real(hEst(:))) | ~isfinite(imag(hEst(:))))
    error("sixgr:mimo:InvalidChannelEstimateForSpatialSignature", ...
        "A finite, nonempty numeric channel estimate is required.");
end

dims = size(hEst);
if subspaceMode == "complete_detectable_subspace" && numel(dims) >= 3
    nRx = dims(3);
    nTx = prod(dims(4:end));
    if numel(dims) == 3
        nTx = 1;
    end
    observations = reshape(permute(double(hEst), ...
        [3, 1, 2, 4:numel(dims)]), nRx, []);
    reductionMode = "frequency_time_snapshot_covariance";
else
    if numel(dims) < 3
        observations = mean(double(hEst(:)));
    else
        wideband = mean(mean(double(hEst), 1), 2);
        if numel(dims) == 3
            observations = reshape(wideband, dims(3), 1);
        else
            observations = reshape(wideband, dims(3), prod(dims(4:end)));
        end
    end
    reductionMode = "wideband_frequency_time_mean";
end
if isempty(observations) || any(~isfinite(real(observations(:))) | ...
        ~isfinite(imag(observations(:)))) || norm(observations, "fro") <= 0
    error("sixgr:mimo:InvalidChannelEstimateForSpatialSignature", ...
        "The measured channel observation matrix is nonfinite or zero-power.");
end

signature = double(observations);
singularValues = [];
numericalRank = NaN;
retainedRank = NaN;
detectionThreshold = NaN;
noiseVariance = NaN;
noiseMargin_dB = NaN;
if isfinite(measuredRank) && measuredRank >= 1 || ...
        subspaceMode == "complete_detectable_subspace"
    [dominantSubspace, singularMatrix, ~] = svd(signature, "econ");
    singularValues = diag(singularMatrix);
    numericalTolerance = max(size(signature)) * eps(max([singularValues(:); 1]));
    numericalRank = nnz(singularValues > numericalTolerance);
    if subspaceMode == "complete_detectable_subspace"
        noiseVariance = double(p.Results.NoiseVariance);
        noiseMargin_dB = double(p.Results.NoiseMargin_dB);
        snapshotCount = size(signature, 2);
        % For an Nrx-by-Nsnapshot independent complex-noise matrix, the
        % spectral norm concentrates near sigma*(sqrt(Nsnapshot)+sqrt(Nrx)).
        % The YAML margin accounts for estimator correlation and finite
        % sample variation. This threshold operates on measured Hest units.
        detectionThreshold = sqrt(noiseVariance) * ...
            (sqrt(snapshotCount) + sqrt(size(signature, 1))) * ...
            10.^(noiseMargin_dB / 20);
        detectionThreshold = max(detectionThreshold, numericalTolerance);
        detectedRank = nnz(singularValues > detectionThreshold);
    else
        detectionThreshold = numericalTolerance;
        detectedRank = numericalRank;
    end
    if detectedRank < 1
        error("sixgr:mimo:InvalidChannelEstimateForSpatialSignature", ...
            "The measured channel has no receiver subspace above the detection threshold.");
    end
    if isfinite(measuredRank) && measuredRank >= 1
        requiredRank = max(1, round(measuredRank));
        if requiredRank > min(size(signature))
            error("sixgr:mimo:SpatialSignatureRankDeficient", ...
                "The measured channel dimensions support at most rank %d but the " + ...
                "scheduled operating point requires rank %d.", ...
                min(size(signature)), requiredRank);
        end
        if detectedRank < requiredRank
            error("sixgr:mimo:SpatialSignatureRankDeficient", ...
                "The measured channel has %d detectable receiver dimensions " + ...
                "but the scheduled operating point requires rank %d.", ...
                detectedRank, requiredRank);
        end
    else
        requiredRank = 1;
    end
    if subspaceMode == "complete_detectable_subspace"
        retainedRank = detectedRank;
    else
        retainedRank = requiredRank;
    end
    signature = dominantSubspace(:, 1:retainedRank);
end
signature = signature ./ norm(signature, "fro");

info = struct();
info.SubspaceMode = char(subspaceMode);
info.ReductionMode = char(reductionMode);
info.RawNumericalRank = double(numericalRank);
info.RetainedRank = double(retainedRank);
info.DetectionThreshold = double(detectionThreshold);
info.NoiseVariance = double(noiseVariance);
info.NoiseMargin_dB = double(noiseMargin_dB);
info.SnapshotCount = double(size(observations, 2));
if isempty(singularValues)
    info.MaximumSingularValue = NaN;
    info.MinimumRetainedSingularValue = NaN;
else
    info.MaximumSingularValue = double(singularValues(1));
    if isfinite(retainedRank) && retainedRank >= 1
        info.MinimumRetainedSingularValue = double(singularValues(retainedRank));
    else
        info.MinimumRetainedSingularValue = NaN;
    end
end
end
