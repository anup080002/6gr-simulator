function ok = testRunArtifactAuditRelativeRoot()
%TESTRUNARTIFACTAUDITRELATIVEROOT Relative run roots must stay relative in audits.
%
% DIR returns absolute folder names on Windows.  If the recursive audit keeps
% a caller-supplied relative root, its prefix removal cannot match those
% absolute names and it writes absolute paths into relative_path.  The image
% reader then prefixes the run root a second time and falsely reports every
% discovered raster as missing.  This regression exercises the exact call
% shape used by persisted-run re-finalization.

setup6GRSimToolkit("Verbose", false);

fixtureRoot = tempname(fullfile(pwd, "tests"));
mkdir(fixtureRoot);
cleanupObj = onCleanup(@() rmdir(fixtureRoot, "s")); %#ok<NASGU>

csvDir = fullfile(fixtureRoot, "reports", "csv");
imageDir = fullfile(fixtureRoot, "reports", "image");
mkdir(csvDir);
mkdir(imageDir);

sourcePath = fullfile(csvDir, "runtime_source.csv");
sixgr.util.csvWriteTable(sourcePath, table((1:4).', [2; 4; 8; 16], ...
    'VariableNames', {'Sample','MeasuredValue'}));

imageRelativePath = "reports/image/runtime_measurement.png";
imagePath = fullfile(fixtureRoot, strrep(char(imageRelativePath), "/", filesep));
[x, y] = meshgrid(uint8(0:31), uint8(0:31));
image = cat(3, x .* 8, y .* 8, bitxor(x, y) .* 8);
imwrite(image, imagePath);

lineage = table("runtime-measurement", "reports/csv/runtime_source.csv", ...
    imageRelativePath, "pass", ...
    'VariableNames', {'PlotId','SourceCSVPath','ImagePath','Status'});
sixgr.util.csvWriteTable(fullfile(csvDir, "plot_manifest.csv"), lineage);

repositoryRoot = string(sixgr.util.canonicalPath(pwd));
canonicalFixture = string(sixgr.util.canonicalPath(fixtureRoot));
relativeFixture = extractAfter(canonicalFixture, strlength(repositoryRoot + filesep));
assert(strlength(relativeFixture) > 0 && ~java.io.File(char(relativeFixture)).isAbsolute(), ...
    "The regression fixture must call the audit with a relative run root.");

audit = sixgr.validation.auditRunArtifacts(relativeFixture, ...
    "Strict", false, "WriteOutputs", true);
assert(logical(audit.Ok), ...
    "A manifested runtime PNG under a relative run root must pass the audit.");
assert(height(audit.ImageAuditTable) == 1, ...
    "The relative-root fixture must produce exactly one image audit row.");
row = audit.ImageAuditTable(1,:);
assert(string(row.relative_path) == imageRelativePath, ...
    "relative_path must remain run-root relative, not an absolute path.");
assert(logical(row.readable) && logical(row.source_csv_exists), ...
    "The audit must read the raster and resolve its exact runtime CSV lineage.");
assert(string(row.status) == "pass", ...
    "The relative-root image row must pass without a false missing-path warning.");

ok = true;
end
