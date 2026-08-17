function value = ioPath(pathValue)
%IOPATH Return a filesystem path that supports Windows extended lengths.

value = sixgr.util.canonicalPath(pathValue);
if ~ispc || strlength(value) < 248 || startsWith(value, "\\?\")
    return;
end
if startsWith(value, "\\")
    value = "\\?\UNC\" + extractAfter(value, 2);
else
    value = "\\?\" + value;
end
end
