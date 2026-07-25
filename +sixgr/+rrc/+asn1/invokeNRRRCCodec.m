function output = invokeNRRRCCodec(operation, input)
%INVOKENRRRCCODEC Invoke the pinned generated NR RRC UPER implementation.
operation = lower(strtrim(string(operation)));
if ~any(operation == ["encode","decode"])
    error("sixgr:rrc:asn1:InvalidCodecOperation", ...
        "NR RRC codec operation must be encode or decode.");
end
root = fileparts(fileparts(fileparts( ...
    fileparts(mfilename("fullpath")))));
script = fullfile(root, "tools", "initial_access", ...
    "nr_sib1_codec.py");
if exist(script, "file") ~= 2
    error("sixgr:rrc:asn1:CodecUnavailable", ...
        "Pinned NR RRC codec helper is missing: %s", script);
end
inputPath = tempname + ".json";
outputPath = tempname + ".json";
cleanup = onCleanup(@() localCleanup([inputPath, outputPath])); %#ok<NASGU>
sixgr.util.jsonWrite(inputPath, input);
python = localPythonExecutable();
command = sprintf('"%s" "%s" %s "%s" "%s"', ...
    python, script, operation, inputPath, outputPath);
[status, text] = system(command);
if status ~= 0 || exist(outputPath, "file") ~= 2
    error("sixgr:rrc:asn1:CodecUnavailable", ...
        "Pinned NR RRC codec failed (%d): %s", status, strtrim(text));
end
output = jsondecode(fileread(outputPath));
if string(output.codec) ~= "pycrate_asn1dir.RRCNR" || ...
        string(output.profile) ~= ...
        "3gpp_ts38331_v18_bounded_fr1_sib1"
    error("sixgr:rrc:asn1:CodecProvenanceMismatch", ...
        "NR RRC codec returned unexpected provenance.");
end
end

function executable = localPythonExecutable()
configured = string(getenv("SIXGR_PYTHON_EXECUTABLE"));
if strlength(strtrim(configured)) > 0
    executable = char(configured);
    return;
end
try
    environment = pyenv;
    candidate = string(environment.Executable);
catch
    candidate = "";
end
if strlength(strtrim(candidate)) > 0 && exist(candidate, "file") == 2
    executable = char(candidate);
else
    executable = "python";
end
end

function localCleanup(paths)
for path = string(paths)
    if exist(path, "file") == 2
        delete(path);
    end
end
end
