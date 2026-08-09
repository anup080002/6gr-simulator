function ok = testRasterFigureStyle()
%TESTRASTERFIGURESTYLE Raster exports must not inherit desktop dark theme.

setup6GRSimToolkit("Verbose", false, "RunToolboxChecks", false);
prior = sixgr.visual.RasterFigureStyle.installDefaults();
cleanupDefaults = onCleanup(@() ...
    sixgr.visual.RasterFigureStyle.restoreDefaults(prior)); %#ok<NASGU>

fig = figure("Visible", "off");
cleanupFigure = onCleanup(@() close(fig)); %#ok<NASGU>
ax = axes(fig);
plot(ax, 1:4, [0.9 0.5 0.2 0.1], "-o", ...
    "DisplayName", "Measured BLER");
title(ax, "Runtime PDSCH BLER");
xlabel(ax, "SNR (dB)");
ylabel(ax, "BLER");
legend(ax, "Location", "best");

% Phase validators export their own figures before the contract publisher
% sees a handle, so their protection depends on installed HG defaults.
assert(isequal(fig.Color, [1 1 1]) && isequal(ax.Color, [1 1 1]), ...
    "New phase-runner figures must inherit the canonical light raster defaults.");
assert(max(abs(ax.XColor - [0.12 0.16 0.22])) < 1e-12 && ...
    max(abs(ax.YColor - [0.12 0.16 0.22])) < 1e-12, ...
    "New phase-runner axes must inherit canonical dark text/ticks.");

% Deliberately emulate a figure produced under a dark desktop theme, then
% prove that the final raster normalizer restores the canonical light look.
fig.Color = [0.05 0.05 0.05];
ax.Color = [0.05 0.05 0.05];
ax.XColor = [1 1 1];
ax.YColor = [1 1 1];
ax.Title.Color = [1 1 1];
sixgr.visual.RasterFigureStyle.apply(fig);

assert(isequal(fig.Color, [1 1 1]));
assert(isequal(ax.Color, [1 1 1]));
assert(max(abs(ax.XColor - [0.12 0.16 0.22])) < 1e-12);
assert(max(abs(ax.YColor - [0.12 0.16 0.22])) < 1e-12);
assert(max(abs(ax.Title.Color - [0.12 0.16 0.22])) < 1e-12);
legendHandle = findall(fig, "Type", "legend");
assert(numel(legendHandle) == 1 && isequal(legendHandle.Color, [1 1 1]));
assert(max(abs(legendHandle.TextColor - [0.12 0.16 0.22])) < 1e-12);
ok = true;
end
