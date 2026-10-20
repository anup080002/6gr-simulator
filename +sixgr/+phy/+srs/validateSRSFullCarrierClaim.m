function tf = validateSRSFullCarrierClaim(coverage, srsCfg)
%VALIDATESRSFULLCARRIERCLAIM True when actual PRB union covers the carrier,
%or the explicitly configured full-carrier tolerance covers a Toolbox RB edge.

targetRB = double(sixgr.util.structGet(coverage, "FullCarrierEffectiveTargetRB", coverage.CarrierPRBCount));
tf = double(coverage.OccupiedPRBCount) >= targetRB && ...
    double(coverage.CarrierPRBCount) > 0 && targetRB > 0;
if logical(srsCfg.FullCarrierSoundingRequired)
    status=string(coverage.BandwidthCoverageStatus);
    if status=="full_carrier"
        tf=tf && coverage.OccupiedPRBCount==coverage.CarrierPRBCount;
    elseif status=="within_configured_carrier_edge_tolerance"
        tolerance=double(sixgr.util.structGet(srsCfg,'FullCarrierCoverageToleranceRB',0));
        tf=tf && coverage.OccupiedPRBCount<coverage.CarrierPRBCount && ...
            coverage.CarrierPRBCount-coverage.OccupiedPRBCount<=tolerance;
    else
        tf=false;
    end
end
end
