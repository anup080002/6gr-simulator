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
scatter(ax, x, sin(x ./ 7), 18, "filled", "DisplayName", "runtime trial");
grid(ax, "on");
legend(ax, "Location", "best");
xlabel(ax, "Trial");
ylabel(ax, "Measured value");
title(ax, "Headless raster export regression");

pngPath = fullfile(tmpRoot, "probe.png");
jpgPath = fullfile(tmpRoot, "probe.jpg");
actualPNG = sixgr.util.exportFigureArtifact(fig, pngPath, "Resolution", 160);
actualJPG = sixgr.util.exportFigureArtifact(fig, jpgPath, "Resolution", 160);

assert(string(actualPNG) == string(pngPath) && isfile(pngPath), ...
    "PNG export did not create the requested raster artifact.");
assert(string(actualJPG) == string(jpgPath) && isfile(jpgPath), ...
    "JPEG export did not create the requested raster artifact.");
pngInfo = imfinfo(pngPath);
jpgInfo = imfinfo(jpgPath);
assert(strcmpi(string(pngInfo.Format), "png") && ...
    pngInfo.Width >= 640 && pngInfo.Height >= 400, ...
    "PNG export has the wrong MIME format or unexpectedly small dimensions.");
assert(any(strcmpi(string(jpgInfo.Format), ["jpg", "jpeg"])) && ...
    jpgInfo.Width >= 640 && jpgInfo.Height >= 400, ...
    "JPEG export has the wrong MIME format or unexpectedly small dimensions.");

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
