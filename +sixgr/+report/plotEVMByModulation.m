function evidence = plotEVMByModulation(ax, data, valueColumn)
%PLOTEVMBYMODULATION Plot actual EVM rows, never identifiers or padded samples.
% Limits, if present, are configured comparison values, not a declaration of
% RF conformance. The caller must retain the measurement-plane/test scope.
arguments
    ax (1,1) matlab.graphics.axis.Axes
    data table
    valueColumn (1,1) string
end
names = string(data.Properties.VariableNames);
if ~all(ismember(["Modulation", valueColumn], names)) || isempty(data)
    error('sixgr:report:MissingEVMEvidence', 'Modulation and measured EVM rows are required.');
end
y = data.(valueColumn);
modulation = string(data.Modulation);
if ~isnumeric(y) || ~iscolumn(y) || any(~isfinite(y) | y < 0) || ...
        any(ismissing(modulation) | strlength(modulation) == 0)
    error('sixgr:report:InvalidEVMEvidence', 'EVM must be finite nonnegative numeric data with modulation identity.');
end
limit = [];
if ismember("Limit_pct", names)
    limit = data.Limit_pct;
    if ~isnumeric(limit) || ~iscolumn(limit) || any(~isfinite(limit) | limit <= 0)
        error('sixgr:report:InvalidEVMEvidence', 'Configured EVM limits must be finite positive numeric data.');
    end
end
% Preserve every input observation exactly once in the measured series.
mods = unique(modulation, 'stable');
[~, x] = ismember(modulation, mods);
group = repmat("Measured EVM", height(data), 1);
for field = ["Direction", "Channel", "ReferencePlane", "ReferencePoint"]
    if ismember(field, names)
        group = group + " / " + string(data.(field));
    end
end
groups = unique(group, 'stable');
set(ax, 'Color', 'white', 'XColor', [.15 .15 .15], ...
    'YColor', [.15 .15 .15], 'GridColor', [.5 .5 .5]);
colororder(ax, lines(numel(groups)));
hold(ax, 'on');
for k = 1:numel(groups)
    selected = group == groups(k);
    plot(ax, x(selected), y(selected), 'o', 'LineStyle', 'none', ...
        'DisplayName', groups(k), 'Tag', 'MeasuredEVM');
end
if ~isempty(limit)
    plot(ax, x, limit, 'kx', 'LineStyle', 'none', ...
        'DisplayName', 'Configured comparison limit (not conformance)', ...
        'Tag', 'ConfiguredEVMLimit');
end
xticks(ax, 1:numel(mods));
xticklabels(ax, mods);
xtickangle(ax, 25);
xlim(ax, [.5 numel(mods)+.5]);
xlabel(ax, 'Modulation');
ylabel(ax, 'RMS EVM (%)');
grid(ax, 'on');
legend(ax, 'Location', 'eastoutside', 'Interpreter', 'none', ...
    'Color', 'white', 'TextColor', 'black');
evidence = struct('MeasuredPointCount', height(data), ...
    'FinitePointCount', height(data) + numel(limit), ...
    'SeriesCount', numel(groups) + double(~isempty(limit)), ...
    'ValueColumn', valueColumn, 'Modulations', mods);
end
