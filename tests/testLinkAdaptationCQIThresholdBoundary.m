function ok = testLinkAdaptationCQIThresholdBoundary()
%TESTLINKADAPTATIONCQITHRESHOLDBOUNDARY Guard inclusive CQI boundaries.

setup6GRSimToolkit("Verbose",false,"RunToolboxChecks",false);

thresholds = [-5.90, -4.78, -2.87, -1.02, 1.00, 3.05, 5.08, ...
    7.25, 9.46, 11.81, 14.34, 16.52, 18.88, 21.47, 23.84];
roundedBoundary = -5.90000000000007;
[cqi, detail] = sixgr.link.resolveCQIFromConfiguredThresholds( ...
    roundedBoundary, thresholds, 1e-9);
assert(cqi == 1 && detail.CQI == 1 && ...
    detail.ComparisonSINRdB >= thresholds(1), ...
    ["An SINR equal to the first configured threshold within the explicit " + ...
    "floating-point tolerance must map to CQI 1, not CQI 0."]);

[below, ~] = sixgr.link.resolveCQIFromConfiguredThresholds( ...
    thresholds(1)-1e-4, thresholds, 1e-9);
assert(below == 0, ...
    "The equality tolerance must not promote a physically lower SINR to CQI 1.");

localAssertError(@()sixgr.link.resolveCQIFromConfiguredThresholds( ...
    thresholds(1), thresholds, 0.01), ...
    "sixgr:link:CQIThresholdToleranceTooLarge");

ok = true;
end

function localAssertError(f, expectedIdentifier)
caught = "";
try
    f();
catch ME
    caught = string(ME.identifier);
end
assert(caught == string(expectedIdentifier), ...
    "Expected typed error %s, received %s.",expectedIdentifier,caught);
end
