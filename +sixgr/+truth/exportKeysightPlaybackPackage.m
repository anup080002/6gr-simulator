function result = exportKeysightPlaybackPackage(sourceRunFolder, outputFolder)
%EXPORTKEYSIGHTPLAYBACKPACKAGE Repackage sealed exact Tx-IQ for Keysight.
%
% This function never edits the source run.  It verifies the source capture
% manifest and MAT hashes, loads the exact committed transmitter samples,
% and writes a separate M9383B/M9384B/89600 playback package.  Capture scope
% (for example a single DL grant rather than a continuous cell waveform) is
% preserved verbatim and must not be promoted by this packaging operation.

arguments
    sourceRunFolder {mustBeTextScalar}
    outputFolder {mustBeTextScalar}
end

sourceRunFolder = localCanonicalFolder(sourceRunFolder);
outputFolder = char(string(outputFolder));
sourceKey = lower(replace(string(sourceRunFolder),"\","/"));
outputKey = lower(replace(string(localAbsolutePath(outputFolder)),"\","/"));
if outputKey == sourceKey || startsWith(outputKey,sourceKey+"/")
    error("sixgr:truth:KeysightPackageInsideSealedRun", ...
        "Keysight playback packaging must use a separate output tree, not the sealed source run.");
end

manifestPath = fullfile(sourceRunFolder,"waveform","csv", ...
    "final_tx_iq_capture_manifest.csv");
if ~isfile(manifestPath)
    error("sixgr:truth:KeysightSourceManifestMissing", ...
        "Source run has no exact Tx-IQ capture manifest: %s",manifestPath);
end
source = sixgr.util.csvReadTable(manifestPath,"TextType","string");
required = ["Direction","ArtifactScope","VSGImportScope","SampleRateHz", ...
    "CenterFrequencyHz","SampleCount","PortCount","WaveformSHA256", ...
    "MATFile","MATFileSHA256","CaptureStatus","ProxyUsed", ...
    "FallbackFlag","PlaceholderFlag"];
missing = setdiff(required,string(source.Properties.VariableNames));
if ~isempty(missing)
    error("sixgr:truth:KeysightSourceManifestSchema", ...
        "Source Tx-IQ manifest is missing: %s",strjoin(missing,", "));
end
if isempty(source) || any(~strcmpi(string(source.CaptureStatus),"PASS")) || ...
        any(localLogical(source.ProxyUsed)) || any(localLogical(source.FallbackFlag)) || ...
        any(localLogical(source.PlaceholderFlag))
    error("sixgr:truth:KeysightSourceCaptureNotTruth", ...
        "Keysight packaging requires non-proxy, non-fallback PASS captures.");
end

rows = repmat(localProvenanceRow(),height(source),1);
artifacts = cell(height(source),1);
for index = 1:height(source)
    direction = upper(strtrim(string(source.Direction(index))));
    if ~ismember(direction,["DL","UL"])
        error("sixgr:truth:KeysightSourceDirection", ...
            "Unsupported source capture direction %s.",direction);
    end
    sourceMAT = localResolveChild(sourceRunFolder,string(source.MATFile(index)));
    observedMATHash = localFileSHA256(sourceMAT);
    expectedMATHash = lower(strtrim(string(source.MATFileSHA256(index))));
    if observedMATHash ~= expectedMATHash
        error("sixgr:truth:KeysightSourceMATHashMismatch", ...
            "Source %s MAT hash does not match its sealed capture manifest.",direction);
    end
    loaded = load(sourceMAT,"waveform","metadata");
    if ~isfield(loaded,"waveform") || ~isfield(loaded,"metadata")
        error("sixgr:truth:KeysightSourceMATSchema", ...
            "Source %s MAT lacks waveform/metadata.",direction);
    end
    metadata = loaded.metadata;
    capture = metadata;
    capture.Waveform = loaded.waveform;
    capture.SampleRateHz = double(source.SampleRateHz(index));
    capture.PlaybackRepeatPolicy = "operator_selected_no_implicit_repeat";
    cfg = struct("channel",struct("fc_Hz", ...
        double(source.CenterFrequencyHz(index))));
    artifacts{index} = sixgr.truth.exportRuntimeTxIQCapture( ...
        outputFolder,capture,cfg,direction);
    packagedHash = lower(string(artifacts{index}.WaveformSHA256));
    expectedWaveformHash = lower(strtrim(string(source.WaveformSHA256(index))));
    if packagedHash ~= expectedWaveformHash
        error("sixgr:truth:KeysightWaveformRoundtripMismatch", ...
            "Packaged %s waveform differs from the source capture.",direction);
    end
    row = localProvenanceRow();
    row.Direction = direction;
    row.SourceRunFolder = replace(string(sourceRunFolder),"\","/");
    row.SourceCaptureManifest = localRelativePath(sourceRunFolder,manifestPath);
    row.SourceCaptureManifestSHA256 = localFileSHA256(manifestPath);
    row.SourceMATFile = localRelativePath(sourceRunFolder,sourceMAT);
    row.SourceMATFileSHA256 = observedMATHash;
    row.SourceWaveformSHA256 = expectedWaveformHash;
    row.ArtifactScope = string(source.ArtifactScope(index));
    row.VSGImportScope = string(source.VSGImportScope(index));
    row.SampleRateHz = double(source.SampleRateHz(index));
    row.CenterFrequencyHz = double(source.CenterFrequencyHz(index));
    row.SampleCount = double(source.SampleCount(index));
    row.PortCount = double(source.PortCount(index));
    row.OutputCaptureManifest = localRelativePath(outputFolder, ...
        artifacts{index}.ManifestPath);
    row.OutputWaveformSHA256 = packagedHash;
    row.ProxyUsed = false;
    row.FallbackFlag = false;
    row.PlaceholderFlag = false;
    row.PhysicalInstrumentValidationStatus = ...
        "not_executed_requires_physical_instrument";
    row.Status = "PASS";
    rows(index) = row;
end

provenance = struct2table(rows,"AsArray",true);
provenancePath = fullfile(outputFolder,"waveform","csv", ...
    "keysight_playback_package_manifest.csv");
sixgr.util.csvWriteTable(provenancePath,provenance);
result = struct("Ok",true,"SourceRunFolder",string(sourceRunFolder), ...
    "OutputFolder",string(localAbsolutePath(outputFolder)), ...
    "Artifacts",{artifacts},"ManifestPath",string(provenancePath), ...
    "ManifestTable",provenance);
end

function row = localProvenanceRow()
row = struct("Direction","","SourceRunFolder","", ...
    "SourceCaptureManifest","","SourceCaptureManifestSHA256","", ...
    "SourceMATFile","","SourceMATFileSHA256","", ...
    "SourceWaveformSHA256","","ArtifactScope","","VSGImportScope","", ...
    "SampleRateHz",NaN,"CenterFrequencyHz",NaN,"SampleCount",NaN, ...
    "PortCount",NaN,"OutputCaptureManifest","", ...
    "OutputWaveformSHA256","","ProxyUsed",false,"FallbackFlag",false, ...
    "PlaceholderFlag",false,"PhysicalInstrumentValidationStatus","", ...
    "Status","");
end

function folder = localCanonicalFolder(pathValue)
folder = localAbsolutePath(pathValue);
if ~isfolder(folder)
    error("sixgr:truth:KeysightSourceRunMissing", ...
        "Source LLS run folder does not exist: %s",folder);
end
end

function pathOut = localAbsolutePath(pathValue)
pathOut = char(string(pathValue));
if ~isfolder(pathOut)
    parent = fileparts(pathOut);
    if isempty(parent), parent = pwd; end
    if ~isfolder(parent), sixgr.util.ensureFolder(parent); end
end
javaFile = java.io.File(pathOut);
pathOut = char(javaFile.getCanonicalPath());
end

function pathOut = localResolveChild(root,relative)
relative = replace(string(relative),"/",filesep);
pathOut = char(fullfile(root,relative));
rootKey = lower(replace(string(root),"\","/"));
pathKey = lower(replace(string(localAbsolutePath(pathOut)),"\","/"));
if ~startsWith(pathKey,rootKey+"/") || ~isfile(pathOut)
    error("sixgr:truth:KeysightSourcePathEscape", ...
        "Source artifact is missing or outside the source run: %s",pathOut);
end
end

function relative = localRelativePath(root,pathValue)
root = replace(string(localAbsolutePath(root)),"\","/");
pathValue = replace(string(localAbsolutePath(pathValue)),"\","/");
if startsWith(lower(pathValue),lower(root+"/"))
    relative = extractAfter(pathValue,strlength(root)+1);
else
    relative = pathValue;
end
end

function hash = localFileSHA256(pathValue)
hash = lower(string(sixgr.util.sha256File(char(string(pathValue)))));
end

function value = localLogical(raw)
if islogical(raw)
    value = raw;
elseif isnumeric(raw)
    value = raw ~= 0;
else
    value = ismember(lower(strtrim(string(raw))),["true","1","yes","pass"]);
end
end

function mustBeTextScalar(value)
if ~(ischar(value) || (isstring(value) && isscalar(value)))
    error("sixgr:truth:KeysightPathType", ...
        "Keysight package paths must be text scalars.");
end
end
