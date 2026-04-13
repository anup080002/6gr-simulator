function ok = testHybrid_CalibrationCoverage()
%TESTHYBRID_CALIBRATIONCOVERAGE Calibration/provenance helpers should be removed.

setup6GRSimToolkit("Verbose", false);
repoRoot = fileparts(which("setup6GRSimToolkit"));
assert(exist(fullfile(repoRoot, "+sixgr", "+hybrid", "CalibrateBLER.m"), "file") == 0, ...
    "CalibrateBLER should be removed from the active repository.");
assert(exist(fullfile(repoRoot, "+sixgr", "+hybrid", "ExportCalibrationArtifacts.m"), "file") == 0, ...
    "ExportCalibrationArtifacts should be removed from the active repository.");
ok = true;
end
