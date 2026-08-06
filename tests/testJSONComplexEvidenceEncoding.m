function ok = testJSONComplexEvidenceEncoding()
%TESTJSONCOMPLEXEVIDENCEENCODING Complex measurements use lossless JSON split form.

setup6GRSimToolkit("Verbose", false);
tmp = string(tempname) + ".json";
cleanup = onCleanup(@() localDelete(tmp)); %#ok<NASGU>
value = complex([1 2; 3 4], [-1 -2; -3 -4]);
payload = struct("Measurement", value, ...
    "NestedTable", table(complex(5, -6), 'VariableNames', {'H'}));
sixgr.util.jsonWrite(tmp, payload);
decoded = jsondecode(fileread(tmp));

assert(string(decoded.Measurement.json_type) == "complex_array_split");
assert(isequal(double(decoded.Measurement.size(:).'), [2 2]));
assert(isequal(double(decoded.Measurement.real), real(value)) && ...
    isequal(double(decoded.Measurement.imag), imag(value)), ...
    "Complex-array JSON encoding must preserve real and imaginary samples exactly.");
assert(string(decoded.NestedTable.H.json_type) == "complex_array_split" && ...
    double(decoded.NestedTable.H.real) == 5 && ...
    double(decoded.NestedTable.H.imag) == -6, ...
    "Complex values nested in tables must use the same explicit encoding.");

ok = true;
end

function localDelete(pathStr)
if exist(pathStr, "file") == 2
    delete(pathStr);
end
end
