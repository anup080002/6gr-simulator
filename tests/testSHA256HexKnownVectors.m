function ok = testSHA256HexKnownVectors()
%TESTSHA256HEXKNOWNVECTORS Verify text and full-octet SHA-256 inputs.

setup6GRSimToolkit("Verbose", false);

assert(sixgr.util.sha256Hex(uint8(unicode2native('abc', 'UTF-8'))) == ...
    "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad", ...
    "SHA-256 text-vector digest mismatch.");
assert(sixgr.util.sha256Hex(uint8([0 127 128 255])) == ...
    "89273d2f70b93285bb7ddb4bcee86a5347ca7159352e3cbdd20c23e9d1e507d3", ...
    "SHA-256 must preserve octets above 127 in MATLAB-to-Java conversion.");

sourceRows = table([1; 2], [string(missing); "payload|with,newline" + newline], ...
    'VariableNames', {'Index','Payload'});
hashA = sixgr.kpi.hashKPISourceRows(sourceRows);
hashB = sixgr.kpi.hashKPISourceRows(sourceRows);
assert(strlength(hashA) == 64 && hashA == hashB, ...
    "KPI source-row hashing must serialize missing and delimited text deterministically.");

% File hashing must depend on bytes, not MATLAB's executable-file class.
% These are inert fixtures; no MEX/P-code is executed.
root = string(tempname) + "_sha256_file_kinds";
mkdir(root);
cleanup = onCleanup(@() rmdir(root, 's')); %#ok<NASGU>
for extension = [".bin", ".m", ".p", "." + string(mexext)]
    path = fullfile(root, "known_bytes" + extension);
    fid = fopen(path, 'wb');
    assert(fid >= 0);
    fwrite(fid, uint8([0 127 128 255]), 'uint8');
    fclose(fid);
    assert(sixgr.util.sha256File(path) == ...
        "89273d2f70b93285bb7ddb4bcee86a5347ca7159352e3cbdd20c23e9d1e507d3", ...
        "File hashing must preserve all bytes regardless of file kind.");
end
for path = [fullfile(root, 'does_not_exist'), root]
    rejected = false;
    try
        sixgr.util.sha256File(path);
    catch cause
        rejected = strcmp(cause.identifier, 'sixgr:util:sha256File:MissingFile');
    end
    assert(rejected, 'Missing files and directories must remain rejected.');
end

ok = true;
end
