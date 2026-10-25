function srs = buildSRSResourceStrict(srsCfg, carrier)
%BUILDSRSRESOURCESTRICT Build an nrSRSConfig for the supported strict profile.

srs = nrSRSConfig;
srs.NumSRSPorts = max(1, round(double(srsCfg.NumSRSPorts)));
srs.SymbolStart = max(0, round(double(srsCfg.SymbolStart)));
srs.NumSRSSymbols = max(1, round(double(srsCfg.NumSRSSymbols)));
srs.Repetition = max(1, round(double(srsCfg.RepetitionFactor)));
srs.KTC = max(2, round(double(srsCfg.CombNumber)));
srs.KBarTC = max(0, round(double(srsCfg.CombOffset)));
srs.CyclicShift = max(0, round(double(srsCfg.CyclicShift)));
srs.NSRSID = max(0, round(double(srsCfg.SequenceId)));
srs.GroupSeqHopping = char(string(srsCfg.GroupOrSequenceHopping));
srs.FrequencyStart = max(0, round(double(srsCfg.FrequencyPosition)));
srs.NRRC = max(0, round(double(srsCfg.NRRC)));
if ~((islogical(srsCfg.EnableStartRBHopping) || ...
        isnumeric(srsCfg.EnableStartRBHopping)) && ...
        isscalar(srsCfg.EnableStartRBHopping) && ...
        isfinite(double(srsCfg.EnableStartRBHopping)) && ...
        any(double(srsCfg.EnableStartRBHopping) == [0 1]))
    error("sixgr:phy:srs:InvalidEnableStartRBHopping", ...
        "SRS EnableStartRBHopping must be a scalar boolean.");
end
srs.EnableStartRBHopping = logical(srsCfg.EnableStartRBHopping);
srs.FrequencyScalingFactor = max(1, round(double(srsCfg.FrequencyScalingFactor)));
srs.StartRBIndex = max(0, round(double(srsCfg.StartRBIndex)));
srs.BHop = max(0, round(double(srsCfg.BHop)));
if strcmpi(string(srsCfg.ResourceType),'aperiodic') && ...
        isnumeric(srsCfg.Periodicity) && isreal(srsCfg.Periodicity) && ...
        isscalar(srsCfg.Periodicity) && isnan(srsCfg.Periodicity)
    % This builder represents one triggered capture. 'on' is the native
    % waveform-generation context, not permission for periodic emissions;
    % decoded-DCI authority is checked by validateSRSConfigStrict. Preserve
    % an explicitly supplied native trigger calendar in the other branch.
    assert(isnumeric(srsCfg.Offset) && isreal(srsCfg.Offset) && isscalar(srsCfg.Offset) && isnan(srsCfg.Offset), ...
        'sixgr:phy:srs:InvalidPeriodOffset','An absent aperiodic trigger calendar cannot retain an orphan offset.');
    srs.SRSPeriod = 'on';
else
    [period,offset]=sixgr.phy.srs.validateSRSPeriodOffset(srsCfg.Periodicity,srsCfg.Offset);
    srs.SRSPeriod = [period offset];
end
srs.ResourceType = char(string(srsCfg.ResourceType));

csrs = double(srsCfg.C_SRS);
bsrs = double(srsCfg.B_SRS);
if ~(isfinite(csrs) && isfinite(bsrs))
    [csrs, bsrs] = localResolveBandwidthConfig(carrier, srs, srsCfg);
end
srs.CSRS = max(0, round(csrs));
srs.BSRS = max(0, round(bsrs));
end

function [bestCSRS, bestBSRS] = localResolveBandwidthConfig(carrier, srs, srsCfg)
target = max(1, round(double(srsCfg.ExpectedNumRB)));
if logical(srsCfg.FullCarrierSoundingRequired)
    target = max(1, round(double(carrier.NSizeGrid)));
end
bestCSRS = NaN;
bestBSRS = NaN;
bestCoverage = -Inf;
for cs = 0:63
    for bs = 0:3
        sTry = srs;
        try
            sTry.CSRS = cs;
            sTry.BSRS = bs;
            ind = nrSRSIndices(carrier, sTry);
            cov = sixgr.phy.srs.computeSRSCoverage(carrier, sTry, ind, srsCfg);
        catch
            continue;
        end
        coverageRB = double(cov.OccupiedPRBCount);
        if coverageRB > bestCoverage && coverageRB <= double(carrier.NSizeGrid)
            bestCoverage = coverageRB;
            bestCSRS = cs;
            bestBSRS = bs;
        end
        if coverageRB >= target
            bestCSRS = cs;
            bestBSRS = bs;
            return;
        end
    end
end
if ~(isfinite(bestCSRS) && isfinite(bestBSRS))
    error("sixgr:phy:srs:NoValidBandwidthConfig", ...
        "Unable to resolve an SRS CSRS/BSRS allocation within the carrier grid.");
end
end
