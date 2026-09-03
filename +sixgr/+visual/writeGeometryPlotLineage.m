function T = writeGeometryPlotLineage(runFolder)
%WRITEGEOMETRYPLOTLINEAGE Bind geometry/mobility PNGs to runtime CSV bytes.

arguments
    runFolder (1,1) string
end

specs = {
    "geometry/image/topology_map.png", ...
        ["geometry/csv/topology_nodes.csv","geometry/csv/trajectory_geometry.csv"]
    "geometry/image/ue_trajectory_xy.png", ...
        "geometry/csv/trajectory_geometry.csv"
    "geometry/image/distance_vs_slot.png", ...
        "geometry/csv/trajectory_geometry.csv"
    "mobility/image/doppler_vs_slot.png", ...
        ["geometry/csv/trajectory_geometry.csv","mobility/csv/doppler_reconciliation.csv"]
    "mobility/image/pathloss_vs_slot.png", ...
        ["geometry/csv/trajectory_geometry.csv","mobility/csv/pathloss_reconciliation.csv"]
    "reports/image/measured_sinr_vs_slot.png", ...
        "reports/csv/measured_sinr_timeseries.csv"
    "reports/image/mcs_rank_vs_slot.png", ...
        "reports/csv/measured_sinr_timeseries.csv"
    "reports/image/geometry_scenario_dashboard.png", ...
        ["geometry/csv/topology_nodes.csv","geometry/csv/trajectory_geometry.csv", ...
        "reports/csv/measured_sinr_timeseries.csv"]
    };

rows = repmat(localEmptyRow(), 0, 1);
for index = 1:size(specs, 1)
    imageRelative = string(specs{index, 1});
    imagePath = fullfile(runFolder, strrep(char(imageRelative), "/", filesep));
    if exist(imagePath, "file") ~= 2
        continue;
    end
    sources = reshape(string(specs{index, 2}), [], 1);
    sourceHashes = strings(numel(sources), 1);
    sourceRows = 0;
    sourcesOk = true;
    for sourceIndex = 1:numel(sources)
        sourcePath = fullfile(runFolder, strrep(char(sources(sourceIndex)), ...
            "/", filesep));
        if exist(sourcePath, "file") ~= 2
            sourcesOk = false;
            break;
        end
        sourceHashes(sourceIndex) = localFileSHA256(sourcePath);
        try
            sourceRows = sourceRows + height(readtable(sourcePath, ...
                "Delimiter", ",", "VariableNamingRule", "preserve", ...
                "TextType", "string"));
        catch
            sourcesOk = false;
            break;
        end
    end
    if ~sourcesOk
        continue;
    end
    [~, stem] = fileparts(imagePath);
    row = localEmptyRow();
    row.PlotId = "geometry_runtime__" + string(stem);
    row.ImagePath = imageRelative;
    row.SourceCSV = strjoin(sources, "|");
    row.SourceCSV_SHA256 = strjoin(sourceHashes, "|");
    row.ImageSHA256 = localFileSHA256(imagePath);
    row.Status = "PASS";
    row.Producer = "sixgr.visual.plotGeometryScenarioEvidence";
    row.SourceRows = double(sourceRows);
    rows(end+1, 1) = row; %#ok<AGROW>
end

if isempty(rows)
    T = struct2table(localEmptyRow());
    T(1, :) = [];
else
    T = struct2table(rows, "AsArray", true);
    T = sortrows(T, "ImagePath");
end
layout = sixgr.report.resultLayout(runFolder);
sixgr.util.csvWriteTable(fullfile(layout.ReportCSVDir, ...
    "geometry_plot_lineage.csv"), T);
end

function row = localEmptyRow()
row = struct( ...
    "PlotId", "", "ImagePath", "", "SourceCSV", "", ...
    "SourceCSV_SHA256", "", "ImageSHA256", "", "Status", "", ...
    "Producer", "", "SourceRows", 0);
end

function value = localFileSHA256(pathValue)
fid = fopen(pathValue, "rb");
if fid < 0
    error("sixgr:visual:GeometryPlotLineageReadFailed", ...
        "Unable to read lineage source %s.", pathValue);
end
cleanup = onCleanup(@() fclose(fid)); %#ok<NASGU>
value = lower(string(sixgr.util.sha256Hex(fread(fid, Inf, "*uint8"))));
end
