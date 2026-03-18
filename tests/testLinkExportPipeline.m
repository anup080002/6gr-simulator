function ok = testLinkExportPipeline()
%TESTLINKEXPORTPIPELINE Ensure unified link export writes CSV/MAT/FIG artifacts.

setup6GRSimToolkit("Verbose", false);
tmp = tempname;
mkdir(tmp);
c = onCleanup(@() rmdir(tmp, 's')); %#ok<NASGU>

T = table( ...
    ["DL_PDSCH_Throughput"; "UL_PUSCH_Throughput"; "UL_SRS_ChannelEst"], ...
    [true; true; true], ...
    [false; false; false], ...
    [0.01; 0.02; NaN], ...
    [0.10; 0.15; NaN], ...
    [120; 95; NaN], ...
    'VariableNames', {'Case','Ok','Skipped','BER','BLER','Throughput_Mbps'});

art = sixgr.link.exportLinkKPIs(tmp, T, struct(), ...
    "SaveCSV", true, "SaveMAT", true, "SaveFigures", true, ...
    "SavePNG", true, "PlotVisible", false, "FigurePrefix", "linktest");

assert(isfield(art, "csv") && ~isempty(art.csv), "CSV artifacts missing.");
assert(isfield(art, "mat") && ~isempty(art.mat), "MAT artifacts missing.");
assert(isfield(art, "fig") && ~isempty(art.fig), "FIG artifacts missing.");

for i = 1:numel(art.csv)
    assert(exist(art.csv{i}, "file") == 2, "Missing CSV artifact: %s", art.csv{i});
end
for i = 1:numel(art.mat)
    assert(exist(art.mat{i}, "file") == 2, "Missing MAT artifact: %s", art.mat{i});
end
for i = 1:numel(art.fig)
    assert(exist(art.fig{i}, "file") == 2, "Missing FIG artifact: %s", art.fig{i});
end

ok = true;
end

