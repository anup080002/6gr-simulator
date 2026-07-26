function result = assertStrictDependencyIsolation()
%ASSERTSTRICTDEPENDENCYISOLATION Reject study-control dependencies in strict PHY.

root = fileparts(mfilename("fullpath"));
files = dir(fullfile(root, "*.m"));
violations = strings(0,1);
for ii = 1:numel(files)
    if string(files(ii).name) == "assertStrictDependencyIsolation.m"
        continue;
    end
    path = fullfile(files(ii).folder, files(ii).name);
    text = string(fileread(path));
    if contains(text, "sixgr.ctrl.") || contains(text, "+sixgr/+ctrl") || ...
            contains(text, "HashFunction6GR")
        violations(end+1,1) = string(files(ii).name); %#ok<AGROW>
    end
end
if ~isempty(violations)
    error("sixgr:phy:pdcch:legacy_study_dependency_forbidden", ...
        "Strict PDCCH production files import study modules: %s.", ...
        strjoin(violations, ", "));
end
result = struct("FilesChecked", numel(files), ...
    "ViolationCount", 0, "Status", "PASS");
end
