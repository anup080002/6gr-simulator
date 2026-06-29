function det = detectSRSFromULGrid(rx, srsCfg)
%DETECTSRSFROMULGRID Detect SRS from received grid using receiver config.

ex = sixgr.phy.srs.extractSRSResources(rx, srsCfg);
obs = ex.ObservedSymbols(:);
ref = ex.ReferenceSymbols(:);
N = min(numel(obs), numel(ref));
metric = NaN;
energy = NaN;
if N > 0
    obs = obs(1:N);
    ref = ref(1:N);
    mask = isfinite(real(obs)) & isfinite(imag(obs)) & isfinite(real(ref)) & isfinite(imag(ref));
    if any(mask)
        obs = obs(mask);
        ref = ref(mask);
        energy = mean(abs(obs).^2, "omitnan");
        denom = max(norm(obs) * norm(ref), eps);
        metric = abs(ref' * obs) / denom;
    end
end
coverage = sixgr.phy.srs.computeSRSCoverage(srsCfg.ToolboxCarrier, srsCfg.ToolboxSRS, ...
    vertcat(sixgr.phy.srs.generateSRSSymbolsAndIndices(srsCfg).SlotResources.Indices), srsCfg);
observedFiniteRECount = double(ex.ObservedFiniteRECount);
expectedRECount = double(ex.ExpectedRECount);
coverageOk = logical(coverage.ConfiguredBandClaimValid) && ...
    (double(coverage.CoveragePercent) >= 95 || observedFiniteRECount >= expectedRECount);
metricOk = isfinite(metric) && metric >= double(srsCfg.DetectionThreshold);
energyOk = isfinite(energy) && energy > 0;
success = metricOk && energyOk && coverageOk;
if success
    failureReason = "";
elseif ~metricOk
    failureReason = "detection_metric_below_threshold";
elseif ~energyOk
    failureReason = "srs_observed_energy_unavailable";
elseif ~coverageOk
    failureReason = "coverage_insufficient";
else
    failureReason = "srs_detection_failed";
end
row = struct("RunId", string(srsCfg.RunId), "TrialId", NaN, "UEId", double(srsCfg.UEId), ...
    "ResourceId", double(srsCfg.ResourceId), "DetectionAttempted", true, ...
    "DetectionSuccess", logical(success), "DetectionMetric", double(metric), ...
    "ObservedEnergy", double(energy), "Threshold", double(srsCfg.DetectionThreshold), ...
    "ExpectedRECount", double(expectedRECount), "ObservedRECount", double(observedFiniteRECount), ...
    "CoveragePercent", double(coverage.CoveragePercent), ...
    "BandwidthCoverageStatus", string(coverage.BandwidthCoverageStatus), ...
    "FailureReason", string(failureReason), ...
    "ConfigHash", string(srsCfg.ConfigHash), "TruthStatus", "real_lls_evidence");
det = struct("DetectionAttempted", true, "DetectionSuccess", logical(success), ...
    "DetectionMetric", double(metric), "Extracted", ex, "Coverage", coverage, ...
    "Table", struct2table(row, "AsArray", true));
end
