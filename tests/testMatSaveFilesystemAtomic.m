function ok = testMatSaveFilesystemAtomic()
%TESTMATSAVEFILESYSTEMATOMIC MAT publication is reloadable and leaves no partial file.

% Keep the destination inside the repository so this regression exercises
% the synchronized OneDrive result volume that exposed the production
% corruption.  matSave itself must stage outside this tree.
root = tempname(pwd);
mkdir(root);
cleanupRoot = onCleanup(@() localRemove(root)); %#ok<NASGU>
target = fullfile(root, "nested", "runtime_result.mat");
payload = struct( ...
    "Scalar", 17, ...
    "Matrix", reshape(1:24, 6, 4), ...
    "Text", "same_chain_truth");

mkdir(fileparts(target));
fid = fopen(target, "wb");
assert(fid >= 0, "Unable to create the corrupt-target regression fixture.");
cleanupFid = onCleanup(@() localClose(fid)); %#ok<NASGU>
fwrite(fid, uint8(char("deliberately incomplete MAT payload")), "uint8");
fclose(fid);
clear cleanupFid

sixgr.util.matSave(target, payload);
assert(isfile(target), "MAT artifact was not atomically published.");
loaded = load(target);
assert(isequal(loaded.Scalar, payload.Scalar));
assert(isequal(loaded.Matrix, payload.Matrix));
assert(string(loaded.Text) == payload.Text);

leftovers = dir(fullfile(fileparts(target), "*.mat"));
assert(numel(leftovers) == 1 && string(leftovers(1).name) == "runtime_result.mat", ...
    "MAT publication left a temporary or duplicate artifact.");

localTarget = fullfile(root, "checkpoint", "local_execution_state.mat");
sixgr.util.matSave(localTarget, payload, "UseArtifactStore", false);
assert(isfile(localTarget), ...
    "Filesystem-authoritative execution state was not published locally.");
localLoaded = load(localTarget);
assert(isequal(localLoaded.Matrix, payload.Matrix));

% Exercise the HDF5-backed format that exposed delayed OneDrive visibility
% in production.  The final destination must be reopenable immediately;
% delayed provider hydration is not accepted as a successful publication.
v73Target = fullfile(root, "hdf5", "validated_copy.mat");
v73Payload = struct("Samples", reshape(1:1e6, 1000, 1000), ...
    "Contract", "v7.3_provider_safe_copy");
sixgr.util.matSave(v73Target, v73Payload, ...
    "UseArtifactStore", false, "ForceV73", true);
inventory = whos("-file", v73Target);
assert(any(string({inventory.name}) == "Samples"));
v73Loaded = load(v73Target, "Contract");
assert(string(v73Loaded.Contract) == v73Payload.Contract);

% Reproduce production result trees whose absolute v7.3 MAT pathname is
% longer than the Windows HDF5 backend's legacy MAX_PATH boundary.  The
% file remains in the real synchronized workspace; matSave must validate
% its exact bytes through an equivalent accessible pathname.
deepRoot = root;
while strlength(string(fullfile(deepRoot, "long_path_payload.mat"))) <= 285
    deepRoot = fullfile(deepRoot, "runtime_evidence_segment");
end
deepTarget = fullfile(deepRoot, "long_path_payload.mat");
assert(strlength(string(java.io.File(deepTarget).getAbsolutePath())) > 260, ...
    "Long-path MAT regression did not exceed 260 characters.");
sixgr.util.matSave(deepTarget, v73Payload, ...
    "UseArtifactStore", false, "ForceV73", true);
deepReadback = char(string(tempname()) + ".mat");
cleanupDeepReadback = onCleanup(@() localDelete(deepReadback)); %#ok<NASGU>
copyfile(deepTarget, deepReadback, "f");
deepInventory = whos("-file", deepReadback);
assert(any(string({deepInventory.name}) == "Samples"));
ok = true;
end

function localDelete(filePath)
if isfile(filePath)
    delete(filePath);
end
end

function localClose(fid)
if fid >= 0
    try
        fclose(fid);
    catch
    end
end
end

function localRemove(root)
if isfolder(root)
    rmdir(root, "s");
end
end
