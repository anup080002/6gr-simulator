function estimate = estimateRangeRateOscillator(y, H, g, covariance)
%ESTIMATERANGERATEOSCILLATOR Stable WLS estimate of [rho; epsilon].

y = double(y(:)); H = double(H); g = double(g(:)); covariance = double(covariance);
if size(H,1) ~= numel(y) || size(H,2) ~= 2 || numel(g) ~= numel(y) || ...
        ~isequal(size(covariance), [numel(y), numel(y)])
    error("sixgr:ntn:resilientsync:EstimatorDimensionMismatch", ...
        "WLS dimensions are inconsistent.");
end
if rank(H) < 2
    error("sixgr:ntn:resilientsync:EstimatorRankDeficient", ...
        "Observation matrix H must have rank two.");
end
[L,p] = chol(covariance, "lower");
if p ~= 0
    error("sixgr:ntn:resilientsync:InvalidMeasurementCovariance", ...
        "Measurement covariance must be symmetric positive definite.");
end
weightedH = L \ H;
weightedY = L \ (y-g);
xHat = weightedH \ weightedY;
normal = weightedH.' * weightedH;
estimate = struct("RhoHat", xHat(1), "EpsilonHat", xHat(2), ...
    "XHat", xHat, "Covariance", normal \ eye(2), ...
    "Residual", y - (H*xHat + g), "Method", "stable_whitened_wls");
end
