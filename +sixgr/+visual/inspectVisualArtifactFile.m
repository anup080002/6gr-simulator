function info = inspectVisualArtifactFile(filePath)
%INSPECTVISUALARTIFACTFILE Inspect visual artifact bytes and extension truth.

filePath = string(filePath);
[~, ~, ext] = fileparts(char(filePath));
ext = lower(string(ext));

info = struct( ...
    "file_path", filePath, ...
    "exists", false, ...
    "extension", ext, ...
    "declared_mime_type", localDeclaredMimeFromExtension(ext), ...
    "actual_mime_type", "missing", ...
    "expected_extension", "", ...
    "sha256", "", ...
    "byte_count", 0, ...
    "extension_mime_match", false, ...
    "signature_status", "missing_file", ...
    "reason", "file_missing");

ioFilePath = sixgr.util.ioPath(filePath);
if exist(ioFilePath, "file") ~= 2
    return;
end

data = localReadBytes(ioFilePath);
info.exists = true;
info.byte_count = double(numel(data));
info.sha256 = localSHA256Hex(data);
info.actual_mime_type = localDetectMime(data);
info.expected_extension = localExpectedExtension(info.actual_mime_type);
info.extension_mime_match = strlength(info.expected_extension) > 0 && ext == info.expected_extension;
if info.extension_mime_match
    info.signature_status = "ok";
    info.reason = "";
elseif info.actual_mime_type == "unknown"
    info.signature_status = "unknown_signature";
    info.reason = "unknown_visual_file_signature";
else
    info.signature_status = "extension_mime_mismatch";
    info.reason = "extension_declares_" + info.declared_mime_type + "_but_bytes_are_" + info.actual_mime_type;
end
end

function data = localReadBytes(filePath)
fid = fopen(filePath, "r");
if fid < 0
    data = uint8([]);
    return;
end
cleanupObj = onCleanup(@() fclose(fid)); %#ok<NASGU>
data = fread(fid, Inf, "*uint8");
data = reshape(data, [], 1);
end

function mime = localDetectMime(data)
mime = "unknown";
if numel(data) >= 8 && isequal(data(1:8).', uint8([137 80 78 71 13 10 26 10]))
    mime = "image/png";
    return;
end
if numel(data) >= 3 && isequal(data(1:3).', uint8([255 216 255]))
    mime = "image/jpeg";
    return;
end
if numel(data) >= 4 && isequal(data(1:4).', uint8([37 80 68 70]))
    mime = "application/pdf";
    return;
end
prefix = char(data(1:min(numel(data), 4096)).');
prefix = regexprep(prefix, "^\xEF\xBB\xBF", "");
prefix = strtrim(prefix);
prefixLower = lower(string(prefix));
if startsWith(prefixLower, "<svg") || startsWith(prefixLower, "<?xml") && contains(prefixLower, "<svg")
    mime = "image/svg+xml";
end
end

function mime = localDeclaredMimeFromExtension(ext)
switch lower(string(ext))
    case ".svg"
        mime = "image/svg+xml";
    case ".png"
        mime = "image/png";
    case {".jpg", ".jpeg"}
        mime = "image/jpeg";
    case ".pdf"
        mime = "application/pdf";
    otherwise
        mime = "application/octet-stream";
end
end

function ext = localExpectedExtension(mime)
switch lower(string(mime))
    case "image/svg+xml"
        ext = ".svg";
    case "image/png"
        ext = ".png";
    case "image/jpeg"
        ext = ".jpg";
    case "application/pdf"
        ext = ".pdf";
    otherwise
        ext = "";
end
end

function value = localSHA256Hex(data)
if isempty(data)
    value = "";
    return;
end
try
    md = java.security.MessageDigest.getInstance("SHA-256");
    md.update(typecast(uint8(data(:)), "int8"));
    digest = typecast(md.digest(), "uint8");
    value = lower(string(reshape(dec2hex(digest, 2).', 1, [])));
catch
    value = "";
end
end
