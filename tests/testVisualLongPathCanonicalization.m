function result = testVisualLongPathCanonicalization()
%TESTVISUALLONGPATHCANONICALIZATION Guard Windows long-path visual audits.

if ~ispc
    result = true;
    return;
end
sep = string(filesep);
root = "C:" + sep + "SixGR";
segments = repmat("contract_chart_directory_with_a_long_semantic_name", 1, 8);
longPath = root + sep + strjoin(segments, sep) + ...
    sep + "intermediate" + sep + ".." + sep + "chart.png";
actual = sixgr.util.canonicalPath(longPath);
expected = root + sep + strjoin(segments, sep) + sep + "chart.png";
assert(strlength(actual) > 260, "The regression fixture must exceed MAX_PATH.");
assert(actual == expected, ...
    "Long-path canonicalization must resolve dot segments without Java filesystem I/O.");

extended = sep + sep + "?" + sep + expected;
assert(sixgr.util.canonicalPath(extended) == expected, ...
    "Windows extended-length and ordinary absolute paths must compare identically.");
assert(sixgr.util.ioPath(expected) == extended, ...
    "Long Windows paths must receive the extended-length filesystem prefix.");
result = true;
end
