function qualified = referencePointStatisticallyQualified( ...
        transportBlocks, confidenceQualificationEligible, ...
        requiredQualificationTransportBlocks)
%REFERENCEPOINTSTATISTICALLYQUALIFIED Verify the prespecified sample floor.
%
% The normative 3GPP receiver decision is one-sided at the stated SNR. Its
% pass/fail decision is made separately from the corresponding one-sided
% confidence bound. A descriptive two-sided metric half-width is disclosed
% in the FRC result, but is not a second normative acceptance requirement.
% This function therefore verifies only that the fixed, prespecified sample
% floor actually completed and was eligible under the full execution plan.

arguments
    transportBlocks (1,1) double {mustBeNonnegative,mustBeInteger}
    confidenceQualificationEligible (1,1) logical
    requiredQualificationTransportBlocks (1,1) double
end

if ~confidenceQualificationEligible
    qualified = false;
    return;
end
if ~isfinite(requiredQualificationTransportBlocks) || ...
        requiredQualificationTransportBlocks < 1 || ...
        requiredQualificationTransportBlocks ~= ...
        fix(requiredQualificationTransportBlocks)
    error("sixgr:conformance:InvalidQualificationSampleFloor", ...
        ["An eligible FRC qualification plan requires a positive integer " + ...
        "sample floor, not %.12g."], requiredQualificationTransportBlocks);
end
qualified = transportBlocks >= requiredQualificationTransportBlocks;
end
