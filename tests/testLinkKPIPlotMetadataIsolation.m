function ok = testLinkKPIPlotMetadataIsolation()
%TESTLINKKPIPLOTMETADATAISOLATION Plot metadata is never treated as a figure.

setup6GRSimToolkit("Verbose", false);
root = string(tempname);
cleanupObj = onCleanup(@()localCleanup(root)); %#ok<NASGU>
mkdir(root);

kpi = table([-5; 0; 5], [0.9; 0.3; 0.01], [5; 40; 95], ...
    'VariableNames', {'SNR_dB','DL_BLER','DL_Throughput_Mbps'});
papr = table([4; 6; 8], [1e-1; 1e-2; 1e-3], ...
    repmat("DL", 3, 1), 'VariableNames', {'PAPR_dB','CCDF','Direction'});
details = struct('PAPRCCDF', papr);

plotInput = struct('KPIs', struct('LinkKPI', kpi, 'PAPRCCDF', papr));
figs = sixgr.visual.PlotLinkKPIs(plotInput, ...
    'FigurePrefix', 'metadata_isolation', 'MakeInvisible', true);
cleanupFigs = onCleanup(@()localCloseFigures(figs)); %#ok<NASGU>
assert(isfield(figs, 'MetadataDebugTables') && ~isfield(figs, 'DebugTables'), ...
    'Plot diagnostic metadata must have an explicit non-figure field name.');
names = fieldnames(figs);
for idx = 1:numel(names)
    if strcmp(names{idx}, 'MetadataDebugTables')
        continue;
    end
    value = figs.(names{idx});
    assert(isscalar(value) && isgraphics(value, 'figure'), ...
        'Every public plot field must contain exactly one figure handle.');
end

artifacts = sixgr.link.exportLinkKPIs(root, kpi, details, ...
    'SaveCSV', false, 'SaveMAT', false, 'SaveFigures', true, ...
    'SavePNG', true, 'PlotVisible', false, ...
    'FigurePrefix', 'metadata_isolation');
assert(~isempty(artifacts.fig), ...
    'Raster link KPI figures must be exported when both KPI and PAPR tables exist.');
for idx = 1:numel(artifacts.fig)
    [~, ~, extension] = fileparts(artifacts.fig{idx});
    assert(strcmpi(extension, '.png') && exist(artifacts.fig{idx}, 'file') == 2, ...
        'Link KPI plots must be materialized as PNG files.');
end
ok = true;
end

function localCloseFigures(figs)
names = fieldnames(figs);
for idx = 1:numel(names)
    value = figs.(names{idx});
    if isscalar(value) && isgraphics(value, 'figure')
        close(value);
    end
end
end

function localCleanup(pathValue)
if exist(pathValue, 'dir') == 7
    rmdir(pathValue, 's');
end
end
