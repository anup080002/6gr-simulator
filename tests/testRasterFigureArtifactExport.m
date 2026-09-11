function ok = testRasterFigureArtifactExport()
%TESTRASTERFIGUREARTIFACTEXPORT Validate bounded headless PNG/JPEG export.

setup6GRSimToolkit("Verbose", false);
tmpRoot = string(tempname);
mkdir(tmpRoot);
cleanupRoot = onCleanup(@() localRemoveTree(tmpRoot)); %#ok<NASGU>

fig = figure("Visible", "off", "Color", "w", ...
    "Position", [100 100 720 480]);
cleanupFigure = onCleanup(@() localCloseFigure(fig)); %#ok<NASGU>
ax = axes(fig);
x = (1:80).';
points = scatter(ax, x, sin(x ./ 7), 18, "filled", "DisplayName", "rendering fixture only");
grid(ax, "on");
legend(ax, "Location", "best");
xlabel(ax, "Trial");
ylabel(ax, "Measured value");
title(ax, "Headless raster export regression");
before = struct('X',points.XData,'Y',points.YData,'C',points.CData, ...
    'Title',ax.Title.String,'XLabel',ax.XLabel.String,'YLabel',ax.YLabel.String);
% Reproduce a direct runtime caller's white figure / dark-theme axes mix.
ax.Color=[.05 .05 .05]; ax.XColor=[1 1 1]; ax.YColor=[1 1 1];
ax.Title.Color=[1 1 1];

pngPath = fullfile(tmpRoot, "probe.png");
jpgPath = fullfile(tmpRoot, "probe.jpg");
actualPNG = sixgr.util.exportFigureArtifact(fig, pngPath, "Resolution", 160);
assert(isequal(ax.Color,[1 1 1]) && ...
    isequal(ax.XColor,[.12 .16 .22]) && isequal(ax.YColor,[.12 .16 .22]) && ...
    isequal(ax.Title.Color,[.12 .16 .22]), ...
    'Direct runtime exports must normalize their completed figure, not rely on runner defaults.');
after = struct('X',points.XData,'Y',points.YData,'C',points.CData, ...
    'Title',ax.Title.String,'XLabel',ax.XLabel.String,'YLabel',ax.YLabel.String);
assert(isequaln(before,after),'Rendering normalization must not alter data, labels or trace identity.');
actualJPG = sixgr.util.exportFigureArtifact(fig, jpgPath, "Resolution", 160);
title(ax, "Headless raster overwrite regression");
actualPNGOverwrite = sixgr.util.exportFigureArtifact(fig, pngPath, "Resolution", 160);

assert(string(actualPNG) == string(pngPath) && isfile(pngPath), ...
    "PNG export did not create the requested raster artifact.");
assert(string(actualJPG) == string(jpgPath) && isfile(jpgPath), ...
    "JPEG export did not create the requested raster artifact.");
assert(string(actualPNGOverwrite) == string(pngPath) && isfile(pngPath), ...
    "Atomic PNG overwrite did not publish the requested raster artifact.");
pngInfo = imfinfo(pngPath);
jpgInfo = imfinfo(jpgPath);
assert(strcmpi(string(pngInfo.Format), "png") && ...
    pngInfo.Width >= 640 && pngInfo.Height >= 400, ...
    "PNG export has the wrong MIME format or unexpectedly small dimensions.");
assert(any(strcmpi(string(jpgInfo.Format), ["jpg", "jpeg"])) && ...
    jpgInfo.Width >= 640 && jpgInfo.Height >= 400, ...
    "JPEG export has the wrong MIME format or unexpectedly small dimensions.");
remainingFiles = dir(fullfile(tmpRoot, "*"));
remainingFiles = remainingFiles(~[remainingFiles.isdir]);
assert(numel(remainingFiles) == 2, ...
    "Raster export left an incomplete staging artifact behind.");

ok = true;
end

function localCloseFigure(fig)
if ishghandle(fig)
    close(fig);
end
end

function localRemoveTree(pathValue)
if isfolder(pathValue)
    rmdir(pathValue, "s");
end
end
