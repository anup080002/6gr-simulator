function artifacts = exportRuntimeTxIQCapture(runFolder, capture, cfg, direction)
%EXPORTRUNTIMETXIQCAPTURE Persist exact committed pre-channel transmit IQ.
%
% The canonical CSV and MAT retain the complex samples after the runtime
% power context and enabled transmitter RF impairments, immediately before
% the channel.  Per-port headerless two-column CSV files contain normalized
% I,Q values for import through Keysight PathWave Signal Generation/AWU.
% The common normalization scale is published in the manifest; samples are
% never regenerated from grants, configured values, or plot data.

arguments
    runFolder {mustBeTextScalar}
    capture (1,1) struct
    cfg (1,1) struct
    direction {mustBeTextScalar}
end

direction = upper(strtrim(string(direction)));
if ~ismember(direction, ["DL","UL"])
    error("sixgr:truth:InvalidTxIQDirection", ...
        "Runtime Tx-IQ direction must be DL or UL.");
end
waveform = sixgr.util.structGet(capture, "Waveform", []);
sampleRateHz = double(sixgr.util.structGet(capture, "SampleRateHz", NaN));
if ~(isnumeric(waveform) && ismatrix(waveform) && ~isempty(waveform) && ...
        all(isfinite(real(waveform(:)))) && all(isfinite(imag(waveform(:)))))
    error("sixgr:truth:InvalidRuntimeTxIQWaveform", ...
        "Committed %s Tx-IQ capture is empty or non-finite.", direction);
end
if ~(isscalar(sampleRateHz) && isfinite(sampleRateHz) && sampleRateHz > 0)
    error("sixgr:truth:InvalidRuntimeTxIQSampleRate", ...
        "Committed %s Tx-IQ capture has no finite positive sample rate.", direction);
end

runFolder = char(string(runFolder));
csvDir = fullfile(runFolder, "waveform", "csv");
matDir = fullfile(runFolder, "waveform", "mat");
sixgr.util.ensureFolder(csvDir);
sixgr.util.ensureFolder(matDir);
token = lower(direction);

nSamples = size(waveform,1);
nPorts = size(waveform,2);
sampleIndex = (0:nSamples-1).';
time_s = sampleIndex ./ sampleRateHz;
canonicalT = table(sampleIndex, time_s, ...
    'VariableNames', {'SampleIndex','Time_s'});
for portIndex = 1:nPorts
    canonicalT.(sprintf('I_Port%d', portIndex)) = double(real(waveform(:,portIndex)));
    canonicalT.(sprintf('Q_Port%d', portIndex)) = double(imag(waveform(:,portIndex)));
end
canonicalPath = fullfile(csvDir, "final_tx_iq_" + token + ".csv");
sixgr.util.csvWriteTable(canonicalPath, canonicalT);

fullScale = max(abs([real(waveform(:)); imag(waveform(:))]));
if ~(isfinite(fullScale) && fullScale > 0)
    error("sixgr:truth:ZeroRuntimeTxIQWaveform", ...
        "Committed %s Tx-IQ capture has zero full-scale amplitude.", direction);
end
normalized = double(waveform) ./ double(fullScale);
keysightPaths = strings(nPorts,1);
keysightHashes = strings(nPorts,1);
keysightRelativePaths = strings(nPorts,1);
for portIndex = 1:nPorts
    keysightPaths(portIndex) = string(fullfile(csvDir, sprintf( ...
        'final_tx_iq_%s_port%d_keysight.csv', token, portIndex)));
    % Keysight user-defined CSV convention: one numeric I,Q sample per
    % line, no column-name row. Sample rate and common scaling are bound by
    % the adjacent manifest rather than embedded as fake waveform samples.
    writematrix([real(normalized(:,portIndex)), imag(normalized(:,portIndex))], ...
        keysightPaths(portIndex), "Delimiter", ",");
    keysightHashes(portIndex) = localFileSHA256(keysightPaths(portIndex));
    keysightRelativePaths(portIndex) = localRelativePath( ...
        runFolder, keysightPaths(portIndex));
end

metadata = struct( ...
    "Direction", direction, ...
    "SampleRateHz", sampleRateHz, ...
    "CenterFrequencyHz", double(sixgr.util.structGet(cfg, ...
        "channel.fc_Hz", sixgr.util.structGet(cfg, "phy.fc_Hz", NaN))), ...
    "SampleCount", double(nSamples), ...
    "PortCount", double(nPorts), ...
    "Frame", double(sixgr.util.structGet(capture, "Frame", NaN)), ...
    "Slot", double(sixgr.util.structGet(capture, "Slot", NaN)), ...
    "CapturePoint", string(sixgr.util.structGet(capture, "CapturePoint", "")), ...
    "WaveformAuthority", string(sixgr.util.structGet(capture, "WaveformAuthority", "")), ...
    "CommonNormalizationFullScale", double(fullScale), ...
    "NormalizedPeak", double(max(abs([real(normalized(:)); imag(normalized(:))]))), ...
    "NormalizedRMS", double(sqrt(mean(abs(normalized(:)).^2))), ...
    "WaveformSHA256", localComplexSHA256(waveform));
matPath = fullfile(matDir, "final_tx_iq_" + token + ".mat");
save(matPath, "waveform", "metadata", "-v7.3");

manifestPath = fullfile(csvDir, "final_tx_iq_capture_manifest.csv");
row = table(direction, metadata.Frame, metadata.Slot, metadata.SampleRateHz, ...
    metadata.CenterFrequencyHz, metadata.SampleCount, metadata.PortCount, ...
    metadata.CapturePoint, metadata.WaveformAuthority, ...
    metadata.CommonNormalizationFullScale, metadata.NormalizedPeak, ...
    metadata.NormalizedRMS, metadata.WaveformSHA256, ...
    localRelativePath(runFolder, canonicalPath), localFileSHA256(canonicalPath), ...
    strjoin(keysightRelativePaths, "|"), ...
    strjoin(keysightHashes, "|"), localRelativePath(runFolder, matPath), ...
    localFileSHA256(matPath), false, false, false, "PASS", ...
    'VariableNames', {'Direction','Frame','Slot','SampleRateHz', ...
    'CenterFrequencyHz','SampleCount','PortCount','CapturePoint', ...
    'WaveformAuthority','CommonNormalizationFullScale','NormalizedPeak', ...
    'NormalizedRMS','WaveformSHA256','CanonicalCSV','CanonicalCSV_SHA256', ...
    'KeysightCSVPerPort','KeysightCSV_SHA256','MATFile','MATFileSHA256', ...
    'ProxyUsed','FallbackFlag','PlaceholderFlag','CaptureStatus'});
manifestT = localReadTable(manifestPath);
if ~isempty(manifestT) && ismember("Direction", ...
        string(manifestT.Properties.VariableNames))
    manifestT(strcmpi(string(manifestT.Direction), direction),:) = [];
end
manifestT = localAppendCompat(manifestT, row);
manifestT = sortrows(manifestT, "Direction");
sixgr.util.csvWriteTable(manifestPath, manifestT);

artifacts = struct( ...
    "Ok", true, "Direction", direction, ...
    "CanonicalCSVPath", string(canonicalPath), ...
    "KeysightCSVPaths", keysightPaths, ...
    "MATPath", string(matPath), ...
    "ManifestPath", string(manifestPath), ...
    "ManifestTable", manifestT, ...
    "SampleCount", double(nSamples), "PortCount", double(nPorts), ...
    "SampleRateHz", sampleRateHz, ...
    "WaveformSHA256", metadata.WaveformSHA256);
end

function relative = localRelativePath(root, pathValue)
root = replace(string(root), "\", "/");
pathValue = replace(string(pathValue), "\", "/");
if startsWith(lower(pathValue), lower(root + "/"))
    relative = extractAfter(pathValue, strlength(root) + 1);
else
    relative = pathValue;
end
end

function hash = localFileSHA256(pathValue)
fid = fopen(char(string(pathValue)), "rb");
if fid < 0
    error("sixgr:truth:TxIQArtifactReadFailed", ...
        "Cannot read Tx-IQ artifact %s for hashing.", string(pathValue));
end
cleanup = onCleanup(@() fclose(fid)); %#ok<NASGU>
hash = lower(string(sixgr.util.sha256Hex(fread(fid, Inf, "*uint8"))));
end

function hash = localComplexSHA256(value)
% Hash shape and the exact IEEE-754 real/imaginary sample payload. JSON
% encoders do not have a portable complex-number representation.
shapeBytes = reshape(typecast(uint64(size(value)), "uint8"), [], 1);
realBytes = reshape(typecast(double(real(value(:))), "uint8"), [], 1);
imagBytes = reshape(typecast(double(imag(value(:))), "uint8"), [], 1);
hash = lower(string(sixgr.util.sha256Hex( ...
    [shapeBytes; realBytes; imagBytes])));
end

function T = localReadTable(pathValue)
T = table();
if ~isfile(pathValue)
    return;
end
try
    T = readtable(pathValue, "TextType", "string", ...
        "VariableNamingRule", "preserve");
catch
    T = table();
end
end

function out = localAppendCompat(a, b)
if isempty(a)
    out = b;
    return;
end
vars = union(string(a.Properties.VariableNames), ...
    string(b.Properties.VariableNames), "stable");
a = localEnsureVariables(a, vars);
b = localEnsureVariables(b, vars);
out = [a(:,cellstr(vars)); b(:,cellstr(vars))];
end

function T = localEnsureVariables(T, vars)
current = string(T.Properties.VariableNames);
for name = vars(:).'
    if ismember(name, current)
        continue;
    end
    T.(char(name)) = strings(height(T),1);
end
end
