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

ok = true;
end
