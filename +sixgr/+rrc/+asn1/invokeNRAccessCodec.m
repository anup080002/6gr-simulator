function output = invokeNRAccessCodec(operation, input)
%INVOKENRRRCCODEC Invoke the pinned generated NR RRC UPER implementation.
operation = lower(strtrim(string(operation)));
if ~any(operation == ["encode","decode","inspect_received"])
    error("sixgr:rrc:asn1:InvalidCodecOperation", ...
        "NR RRC codec operation must be encode, decode or inspect_received.");
end
root = fileparts(fileparts(fileparts( ...
    fileparts(mfilename("fullpath")))));
script = fullfile(root, "tools", "initial_access", ...
    "nr_rrc_access_codec.py");
if exist(script, "file") ~= 2
    error("sixgr:rrc:asn1:CodecUnavailable", ...
        "Pinned NR RRC codec helper is missing: %s", script);
end
inputPath = tempname + ".json";
outputPath = tempname + ".json";
cleanup = onCleanup(@() localCleanup([inputPath, outputPath])); %#ok<NASGU>
localWriteProcessInputJSON(inputPath, input);
python = localPythonExecutable();
command = sprintf('"%s" "%s" %s "%s" "%s"', ...
    python, script, operation, inputPath, outputPath);
[status, text] = system(command);
if status ~= 0 || exist(outputPath, "file") ~= 2
    error("sixgr:rrc:asn1:CodecUnavailable", ...
        "Pinned NR RRC codec failed (%d): %s", status, strtrim(text));
end
output = jsondecode(fileread(outputPath));
expectedProfile="nr_rrc_access_base_srb1_uper_v1";
if any(string(input.message_kind)==["security_mode_command","security_mode_complete", ...
        "security_mode_failure","reconfiguration","reconfiguration_complete"])
    expectedProfile="nr_rrc_rel18_security_new_drb_uper_v1";
end
if string(output.codec) ~= "pycrate_asn1dir.RRCNR" || ...
        string(output.profile) ~= expectedProfile
    error("sixgr:rrc:asn1:CodecProvenanceMismatch", ...
        "NR RRC codec returned unexpected provenance.");
end
end

function localWriteProcessInputJSON(filePath, input)
% The codec is an external process and therefore requires a physical file.
% Do not route this process-handoff JSON through the active artifact store:
% mysql_web persistence can correctly consume an artifact without creating
% the temporary filesystem file that Python must open.
try
    text = jsonencode(input, "PrettyPrint", true);
catch
    text = jsonencode(input);
end
fid = fopen(char(filePath), "w", "n", "UTF-8");
if fid < 0
    error("sixgr:rrc:asn1:CodecInputWriteFailed", ...
        "Cannot create the NR RRC codec input file: %s", filePath);
end
cleanup = onCleanup(@() fclose(fid)); %#ok<NASGU>
written = fwrite(fid, char(text), "char");
if written ~= strlength(string(text))
    error("sixgr:rrc:asn1:CodecInputWriteFailed", ...
        "NR RRC codec input file was only partially written: %s", filePath);
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
