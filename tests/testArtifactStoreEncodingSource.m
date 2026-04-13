function ok = testArtifactStoreEncodingSource()
%TESTARTIFACTSTOREENCODINGSOURCE Guard DB artifact byte and JSON serialization.

setup6GRSimToolkit("Verbose", false);

repoRoot = fileparts(fileparts(mfilename("fullpath")));
sourcePath = fullfile(repoRoot, "+sixgr", "+db", "artifactStore.m");
txt = string(fileread(sourcePath));

assert(contains(txt, 'typecast(uint8(bytesIn(:).''), "int8")'), ...
    "Artifact chunks must preserve PNG and binary bytes above 127 when passed to Java.");
assert(~contains(txt, "psChunk.setBytes(3, int8(chunk))"), ...
    "Artifact chunks must not use saturating int8(chunk) conversion.");
assert(~contains(txt, 'replace(txt, newline, "\n")'), ...
    "JSON artifacts must not replace structural newlines with invalid top-level literal escapes.");
assert(contains(txt, 'fopen(filePath, "rb")'), ...
    "Binary artifacts must be read in binary mode.");

ok = true;
end
