function result = feederDelayTaylorError(timeS, exactDelayS, epochS, order)
%FEEDERDELAYTAYLORERROR Fit an epoch-local Taylor model and report error.

timeS = double(timeS(:)); exactDelayS = double(exactDelayS(:));
if numel(timeS) ~= numel(exactDelayS) || numel(timeS) < 5
    error("sixgr:ntn:resilientsync:InvalidFeederSeries", ...
        "Feeder Taylor evaluation requires equal-length series with at least five samples.");
end
if ~ismember(order, [0,1,2])
    error("sixgr:ntn:resilientsync:InvalidDerivativeOrder", ...
        "Feeder derivative order must be 0, 1, or 2.");
end
[~, center] = min(abs(timeS - epochS));
fitIndex = max(1,center-2):min(numel(timeS),center+2);
coefs = polyfit(timeS(fitIndex)-epochS, exactDelayS(fitIndex), min(2,numel(fitIndex)-1));
coefs = [zeros(1,3-numel(coefs)), coefs];
dt = timeS - epochS;
switch order
    case 0, approx = coefs(3) + zeros(size(dt));
    case 1, approx = coefs(3) + coefs(2).*dt;
    otherwise, approx = coefs(3) + coefs(2).*dt + coefs(1).*dt.^2;
end
err = approx - exactDelayS;
result = struct("Time_s", timeS, "ExactDelay_s", exactDelayS, ...
    "ApproximateDelay_s", approx, "Error_s", err, "Order", order, ...
    "EndpointError_s", err(end), "MaximumAbsoluteError_s", max(abs(err)), ...
    "RMSError_s", sqrt(mean(err.^2)), "Epoch_s", epochS);
end
