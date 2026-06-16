function tf = validateSRSFullCarrierClaim(coverage, srsCfg)
%VALIDATESRSFULLCARRIERCLAIM True only when actual PRB union covers carrier.

tf = double(coverage.OccupiedPRBCount) >= double(coverage.CarrierPRBCount) && ...
    double(coverage.CarrierPRBCount) > 0;
if logical(srsCfg.FullCarrierSoundingRequired)
    tf = tf && string(coverage.BandwidthCoverageStatus) == "full_carrier";
end
end
