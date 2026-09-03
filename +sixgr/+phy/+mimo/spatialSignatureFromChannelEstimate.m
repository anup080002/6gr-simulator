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
p.addParameter("SpatialDomain", "receiver", ...
    @(x)ischar(x) || (isstring(x) && isscalar(x)));
p.parse(varargin{:});
measuredRank = double(p.Results.Rank);
subspaceMode = lower(strtrim(string(p.Results.SubspaceMode)));
spatialDomain = lower(strtrim(string(p.Results.SpatialDomain)));
if ~ismember(subspaceMode, ["dominant_scheduled_rank", ...
        "complete_detectable_subspace"])
    error("sixgr:mimo:InvalidSpatialSignatureSubspaceMode", ...
        "SubspaceMode must be dominant_scheduled_rank or " + ...
        "complete_detectable_subspace.");
end
if ~ismember(spatialDomain, ["receiver", "transmitter"])
    error("sixgr:mimo:InvalidSpatialSignatureDomain", ...
        "SpatialDomain must be receiver or transmitter.");
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
    if spatialDomain == "receiver"
        observations = reshape(permute(double(hEst), ...
            [3, 1, 2, 4:numel(dims)]), nRx, []);
    else
        % Each downlink snapshot is H (Nrx-by-Ntx).  Its right-singular
        % transmit subspace is the left-singular subspace of H^H.  Stack
        % H^H over frequency/time without coherent phase averaging.
        observations = reshape(permute(conj(double(hEst)), ...
            [4, 1, 2, 3]), nTx, []);
    end
    reductionMode = spatialDomain + "_frequency_time_snapshot_covariance";
else
    if numel(dims) < 3
        observations = mean(double(hEst(:)));
    else
        wideband = mean(mean(double(hEst), 1), 2);
        if numel(dims) == 3
            channelMatrix = reshape(wideband, dims(3), 1);
        else
            channelMatrix = reshape(wideband, dims(3), prod(dims(4:end)));
        end
        if spatialDomain == "receiver"
            observations = channelMatrix;
        else
            observations = channelMatrix';
        end
    end
    reductionMode = spatialDomain + "_wideband_frequency_time_mean";
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
        % Estimate signal covariance from the actual pilot observations.
        % E[Y*Y'] = H*H' + Nsnapshot*sigma^2*I for white complex
        % estimator noise.  Subtract that measured noise floor before mode
        % selection instead of applying the spectral-norm upper edge as a
        % hard cutoff.  The old cutoff discarded physically relevant weak
        % channel modes; a precoder could then exactly null the exported
        % signature yet leak strongly through the omitted FIR modes.
        noiseFloorSingularPower = snapshotCount * noiseVariance;
        signalSingularPower = max(singularValues.^2 - ...
            noiseFloorSingularPower, 0);
        excessPowerThreshold = noiseFloorSingularPower * ...
            max(10.^(noiseMargin_dB / 10) - 1, 0);
        signalPowerTolerance = max(numericalTolerance.^2, ...
            eps(max([signalSingularPower(:); 1])));
        detectionThreshold = sqrt(max(noiseFloorSingularPower * ...
            10.^(noiseMargin_dB / 10), signalPowerTolerance));
        detectionThreshold = max(detectionThreshold, numericalTolerance);
        detectedRank = nnz(signalSingularPower > ...
            max(excessPowerThreshold, signalPowerTolerance));
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
    if subspaceMode == "complete_detectable_subspace"
        % Preserve measured mode energy as well as direction.  Returning
        % only U made every retained mode equally important and allowed a
        % geometrically nulled design to choose a weak desired direction;
        % the exact reciprocal FIR could then have much worse peer-to-
        % desired leakage than the admission metric.  U*S is a compact
        % square-root spatial covariance factor derived solely from the
        % measured pilot snapshots.
        effectiveSingularValues = sqrt(signalSingularPower(1:retainedRank));
        signature = dominantSubspace(:, 1:retainedRank) * ...
            diag(effectiveSingularValues);
        weightingMode = "noise_debiased_measured_singular_value_weighted_subspace";
    else
        signature = dominantSubspace(:, 1:retainedRank);
        weightingMode = "orthonormal_subspace";
    end
else
    weightingMode = "raw_measured_observation";
end
signature = signature ./ norm(signature, "fro");

info = struct();
info.SubspaceMode = char(subspaceMode);
info.SpatialDomain = char(spatialDomain);
info.ReductionMode = char(reductionMode);
info.RawNumericalRank = double(numericalRank);
info.RetainedRank = double(retainedRank);
info.DetectionThreshold = double(detectionThreshold);
info.NoiseVariance = double(noiseVariance);
info.NoiseMargin_dB = double(noiseMargin_dB);
info.SnapshotCount = double(size(observations, 2));
info.WeightingMode = char(weightingMode);
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
