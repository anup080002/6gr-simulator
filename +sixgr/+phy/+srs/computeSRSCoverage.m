function coverage = computeSRSCoverage(carrier, srs, srsInd, srsCfg)
%COMPUTESRSCOVERAGE Compute PRB coverage from actual SRS indices.

K = max(1, round(double(carrier.NSizeGrid)) * 12);
L = max(1, round(double(carrier.SymbolsPerSlot)));
P = max(1, round(double(srs.NumSRSPorts)));
nCarrierPRB = max(1, round(double(carrier.NSizeGrid)));
idx = round(double(srsInd(:)));
idx = idx(isfinite(idx) & idx >= 1 & idx <= K * L * P);
if isempty(idx)
    prb = [];
else
    [kSub, ~, ~] = ind2sub([K L P], idx);
    prb = unique(floor((double(kSub(:)) - 1) / 12));
    prb = prb(prb >= 0 & prb < nCarrierPRB);
end
occupied = numel(prb);
coveragePercent = 100 * occupied / nCarrierPRB;
if occupied >= nCarrierPRB
    status = "full_carrier";
elseif occupied > 0
    status = "partial_band";
else
    status = "no_coverage";
end
if occupied > 0
    prbStart = min(prb);
    prbEnd = max(prb);
else
    prbStart = NaN;
    prbEnd = NaN;
end
coverage = struct();
coverage.ExpectedRECount = double(numel(idx));
coverage.ObservedRECount = double(numel(idx));
coverage.OccupiedPRBCount = double(occupied);
coverage.CarrierPRBCount = double(nCarrierPRB);
coverage.CoveragePercent = double(coveragePercent);
coverage.PRBStart = double(prbStart);
coverage.PRBEnd = double(prbEnd);
coverage.BandwidthCoverageStatus = string(status);
coverage.CoverageRequirement = string(srsCfg.CoverageRequirement);
coverage.FullCarrierSoundingRequired = logical(srsCfg.FullCarrierSoundingRequired);
coverage.FullCarrierClaimValid = sixgr.phy.srs.validateSRSFullCarrierClaim(coverage, srsCfg);
coverage.ConfiguredBandClaimValid = sixgr.phy.srs.validateSRSConfiguredBandClaim(coverage, srsCfg);
coverage.PartialBandValid = status == "partial_band" && string(srsCfg.CoverageRequirement) == "partial_band_allowed";
end
