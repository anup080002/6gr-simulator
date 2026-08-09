function ok = testDefaultRunFolderProfileRoot()
%TESTDEFAULTRUNFOLDERPROFILEROOT Do not duplicate an explicit profile root.

setup6GRSimToolkit("Verbose", false, "RunToolboxChecks", false);

repoRoot = fileparts(fileparts(mfilename("fullpath")));
profile = "webgui_sinr_sweep_64x4_mu_mimo_repair_slice";
explicitProfileRoot = fullfile(repoRoot, "results", profile);
leaf = "profile_root_contract_test";
expected = fullfile(explicitProfileRoot, leaf);
cleanup = onCleanup(@() localCleanup(expected, explicitProfileRoot)); %#ok<NASGU>

actual = sixgr.report.defaultRunFolder(explicitProfileRoot, ...
    "Bucket", "lls", "Profile", profile, "Leaf", leaf, ...
    "CleanExisting", true);

assert(strcmpi(char(string(actual)), char(string(expected))), ...
    "An explicit scenario/profile output root must receive only the run leaf.");
assert(~contains(lower(string(actual)), ...
    lower(profile + filesep + "lls" + filesep + profile)), ...
    "The result path must not duplicate bucket/profile below an explicit profile root.");

ok = true;
end

function localCleanup(expected, profileRoot)
if isfolder(expected)
    rmdir(expected, "s");
end
if isfolder(profileRoot)
    remaining = dir(profileRoot);
    remaining = remaining(~ismember({remaining.name}, {'.','..'}));
    if isempty(remaining)
        rmdir(profileRoot);
    end
end
end
