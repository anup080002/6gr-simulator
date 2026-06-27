function tf = validateSRSFullCarrierClaim(coverage, srsCfg)
%VALIDATESRSFULLCARRIERCLAIM True when actual PRB union covers the carrier,
%or the explicitly configured full-carrier tolerance covers a Toolbox RB edge.

targetRB = double(sixgr.util.structGet(coverage, "FullCarrierEffectiveTargetRB", coverage.CarrierPRBCount));
tf = double(coverage.OccupiedPRBCount) >= targetRB && ...
    double(coverage.CarrierPRBCount) > 0 && targetRB > 0;
if logical(srsCfg.FullCarrierSoundingRequired)
    tf = tf && string(coverage.BandwidthCoverageStatus) == "full_carrier";
end
end
