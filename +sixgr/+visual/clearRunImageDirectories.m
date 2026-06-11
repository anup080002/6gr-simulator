function report = clearRunImageDirectories(runFolder)
%CLEARRUNIMAGEDIRECTORIES Remove stale visual files from run image folders.

layout = sixgr.report.resultLayout(runFolder);
root = char(string(layout.Root));
dirs = strings(0, 1);
names = fieldnames(layout);
for i = 1:numel(names)
    name = string(names{i});
    if endsWith(name, "ImageDir")
        dirs(end + 1, 1) = string(layout.(names{i})); %#ok<AGROW>
    end
end
dirs(end + 1, 1) = string(layout.PlotsDir);
dirs = unique(dirs(strlength(dirs) > 0), "stable");

rows = repmat(struct("ImageDir", "", "Cleared", false, "DeletedEntries", 0, "Status", ""), 0, 1);
for i = 1:numel(dirs)
    dirPath = char(dirs(i));
    if ~localIsWithinRoot(dirPath, root)
        rows(end + 1, 1) = struct("ImageDir", string(dirPath), "Cleared", false, ...
            "DeletedEntries", 0, "Status", "skipped_outside_run_root"); %#ok<AGROW>
        continue;
    end
    sixgr.util.ensureFolder(dirPath);
    entries = dir(dirPath);
    entries = entries(~ismember({entries.name}, {'.','..'}));
    deleted = 0;
    for j = 1:numel(entries)
        target = fullfile(dirPath, entries(j).name);
        try
            if entries(j).isdir
                rmdir(target, "s");
            else
                delete(target);
            end
            deleted = deleted + 1;
        catch
        end
    end
    rows(end + 1, 1) = struct("ImageDir", string(dirPath), "Cleared", true, ...
        "DeletedEntries", double(deleted), "Status", "cleared"); %#ok<AGROW>
end
report = struct2table(rows);
end

function tf = localIsWithinRoot(pathValue, root)
try
    pathValue = char(java.io.File(char(pathValue)).getCanonicalPath());
    root = char(java.io.File(char(root)).getCanonicalPath());
catch
    pathValue = char(string(pathValue));
    root = char(string(root));
end
if ispc
    pathValue = lower(pathValue);
    root = lower(root);
end
tf = strcmp(pathValue, root) || startsWith(string(pathValue), string(root) + string(filesep));
end
