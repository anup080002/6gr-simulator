function ok = testLLSCoverageLayerExport()
%TESTLLSCOVERAGELAYEREXPORT Preserve measured runtime coverage at finalization.

setup6GRSimToolkit("Verbose", false);
runFolder = string(tempname);
mkdir(runFolder);
cleanup = onCleanup(@()localRemoveTree(runFolder)); %#ok<NASGU>

coverageSnapshot = table(1, 14, 0.014, 0, 0, 1, 1, 1, ...
    12, "configured_operating_point_metadata", -89.25, -89.25, ...
    35.5, 34.8, 33.9, "large_scale_per_reference_re_power", ...
    'VariableNames', {'UEID','Slot','Time_s','Lat','Lon','ServingCell', ...
    'ServingSite','ServingSector','ConfiguredSNR_dB','ConfiguredSNRSource', ...
    'ServingRSRP_dBm','RSRP_dBm','SystemLevelSINR_dB','PostEqSINR_dB', ...
    'Pathloss_dB','RSRPSource'});
userPerformance = table(1, 17.5, 0, ...
    'VariableNames', {'UEIndex','UserThroughput_Mbps','HARQFailureRate'});
slotTrace = struct("CoverageSnapshotTable", coverageSnapshot, ...
    "CoverageLayerTable", table(), "UserPerformanceTable", userPerformance);

artifacts = sixgr.truth.exportLLSLiveDerivedTables( ...
    sixgr.config.defaultConfig(), runFolder, struct(), struct(), struct(), slotTrace);
actual = sixgr.util.csvReadTable(artifacts.CoverageLayerPath, "TextType", "string");
assert(height(actual) == 1, ...
    "A measured CoupledTruthRuntime coverage snapshot must survive finalization.");
assert(double(actual.UEID(1)) == 1 && double(actual.Slot(1)) == 14);
assert(abs(double(actual.ServingRSRP_dBm(1)) + 89.25) < 1e-12);
assert(abs(double(actual.UserThroughput_Mbps(1)) - 17.5) < 1e-12);
assert(abs(double(actual.CellThroughput_Mbps(1)) - 17.5) < 1e-12);
assert(abs(double(actual.HARQFailureRate(1))) < 1e-12);

ok = true;
fprintf("[PASS] testLLSCoverageLayerExport rows=%d\n", height(actual));
end

function localRemoveTree(pathValue)
if isfolder(pathValue)
    rmdir(pathValue, "s");
end
end
