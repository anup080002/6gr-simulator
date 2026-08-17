function ok = testVisualArtifactMultiSourceAndDegenerateCDF()
%TESTVISUALARTIFACTMULTISOURCEANDDEGENERATECDF Retired raster contracts stay absent.

setup6GRSimToolkit("Verbose", false);
runFolder = string(tempname);
mkdir(runFolder);
cleanup = onCleanup(@() localRemoveTree(runFolder)); %#ok<NASGU>

contracts = sixgr.visual.loadVisualArtifactContract();
plotIds = string({contracts.PlotId});
retired = ["bler_vs_measured_sinr","throughput_vs_measured_sinr", ...
    "access_delay_cdf","power_energy_cumulative"];
assert(~any(ismember(plotIds, retired)), ...
    "Retired MATLAB raster contracts must not return to the visual catalog.");

reportCSV = fullfile(runFolder, "reports", "csv");
reportImage = fullfile(runFolder, "reports", "image");
mkdir(reportCSV);
mkdir(reportImage);

PostEqSINR_dB = [-5; 0; 5];
MetricValue = [-8; -12; -16];
Direction = repmat("DL", 3, 1);
SourceArtifact = repmat("runtime_channel_estimate", 3, 1);
CurveConstruction = repmat("measured_posteq_sinr_binning", 3, 1);
truth_status = repmat("real_lls_evidence", 3, 1);
nmseT = table(PostEqSINR_dB, MetricValue, Direction, SourceArtifact, ...
    CurveConstruction, truth_status);
writetable(nmseT, fullfile(reportCSV, "nmse_vs_measured_sinr.csv"));

nmseImage = fullfile(reportImage, "nmse_vs_measured_sinr.png");
imwrite(uint8(reshape(mod(0:8*8*3-1, 251), 8, 8, 3)), nmseImage);
enforcement = sixgr.visual.enforceVisualArtifactContract(runFolder, ...
    "StrictMode", true, "CreateUnavailableCards", false);
nmseRow = enforcement(enforcement.PlotId == "nmse_vs_measured_sinr", :);
assert(height(nmseRow) == 1 && ...
    string(nmseRow.EnforcementStatus) == "source_satisfies_contract" && ...
    exist(nmseImage, "file") == 2, ...
    "A current runtime-backed visual contract did not preserve its valid raster.");

provenance = sixgr.truth.buildLLSReportingProvenanceTables(runFolder, ...
    struct(), struct(), table(), struct("run_id", "visual_contract_regression"));
manifestRow = provenance.plot_manifest( ...
    provenance.plot_manifest.PlotId == "nmse_vs_measured_sinr", :);
assert(height(manifestRow) == 1 && ...
    string(manifestRow.PlotRenderStatus) == "rendered_real_plot" && ...
    exist(nmseImage, "file") == 2, ...
    "Provenance reduction deleted a valid current-contract image.");

ok = true;
end

function localRemoveTree(pathValue)
if exist(pathValue, "dir") == 7
    rmdir(pathValue, "s");
end
end
