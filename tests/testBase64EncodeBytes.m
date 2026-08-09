function ok = testBase64EncodeBytes()
%TESTBASE64ENCODEBYTES Regression for zero-byte provenance files.

assert(sixgr.runtime.base64EncodeBytes(uint8([])) == "", ...
    "A zero-byte source file must have the canonical empty base64 payload.");
assert(sixgr.runtime.base64EncodeBytes(uint8('abc')) == "YWJj", ...
    "Non-empty source bytes must remain byte-exact during base64 encoding.");
assert(sixgr.runtime.base64EncodeBytes(uint8([0 1 2 255])) == "AAEC/w==", ...
    "Binary source bytes must not be text-decoded or reshaped semantically.");

threw = false;
try
    sixgr.runtime.base64EncodeBytes([1.5 2]);
catch ME
    threw = contains(string(ME.identifier), "expectedInteger") || ...
        contains(lower(string(ME.message)), "integer");
end
assert(threw, "Non-integer source payloads must fail validation.");
ok = true;
end
