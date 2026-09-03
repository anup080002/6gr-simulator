function ok = testRuntimeTxIQCapture()
%TESTRUNTIMETXIQCAPTURE Exact waveform CSV/MAT/Keysight export contract.

setup6GRSimToolkit("Verbose", false);
root = tempname;
mkdir(root);
cleanup = onCleanup(@() localCleanup(root)); %#ok<NASGU>

n = 32;
t = (0:n-1).';
waveform = [0.25*exp(1j*2*pi*t/8), 0.5*exp(-1j*2*pi*t/5)];
capture = struct("Waveform", waveform, "SampleRateHz", 30.72e6, ...
    "Frame", 2, "Slot", 7, ...
    "CapturePoint", "post_power_and_tx_rf_pre_channel", ...
    "WaveformAuthority", "exact_runtime_pdsch_waveform", ...
    "EndpointType", "gnb_grant_component", ...
    "ArtifactScope", "first_committed_grant_component", ...
    "UEIndex", 1, "ServingCell", 1, "GrantContextId", "dl-grant-1", ...
    "CompositeTransmitterWaveform", false, ...
    "VSGImportScope", "single_grant_component_not_complete_cell_transmission");
cfg = struct("channel", struct("fc_Hz", 3.5e9));

% A killed prior run may leave an invalid MAT target.  The production
% exporter must replace it atomically rather than asking HDF5 to reuse the
% corrupt file.
staleMat = fullfile(root, "waveform", "mat", "final_tx_iq_dl.mat");
sixgr.util.ensureFolder(fileparts(staleMat));
fid = fopen(staleMat, "wb");
assert(fid >= 0);
fwrite(fid, uint8(char("interrupted-mat-file")), "uint8");
fclose(fid);

outDL = sixgr.truth.exportRuntimeTxIQCapture(root, capture, cfg, "DL");
capture.Waveform = 0.8 * waveform;
capture.WaveformAuthority = "exact_runtime_pusch_waveform";
capture.EndpointType = "ue_transmitter";
capture.ArtifactScope = "first_committed_ue_grant_waveform";
capture.GrantContextId = "ul-grant-1";
capture.CompositeTransmitterWaveform = true;
capture.VSGImportScope = "complete_selected_ue_grant_transmission";
outUL = sixgr.truth.exportRuntimeTxIQCapture(root, capture, cfg, "UL");
assert(outDL.Ok && outUL.Ok && outDL.SampleCount == n && ...
    outDL.PortCount == 2);
manifest = readtable(outDL.ManifestPath, "TextType", "string", ...
    "VariableNamingRule", "preserve");
assert(height(manifest) == 2 && ...
    all(sort(string(manifest.Direction)) == ["DL";"UL"]) && ...
    all(manifest.CaptureStatus == "PASS") && ...
    ~any(manifest.ProxyUsed | manifest.FallbackFlag | manifest.PlaceholderFlag));
assert(all(manifest.SampleCount == n) && all(manifest.PortCount == 2) && ...
    all(manifest.SampleRateHz == 30.72e6));
dlManifest = manifest(manifest.Direction == "DL",:);
ulManifest = manifest(manifest.Direction == "UL",:);
assert(dlManifest.EndpointType == "gnb_grant_component" && ...
    ~dlManifest.CompositeTransmitterWaveform && ...
    dlManifest.VSGImportScope == "single_grant_component_not_complete_cell_transmission");
assert(ulManifest.EndpointType == "ue_transmitter" && ...
    ulManifest.CompositeTransmitterWaveform && ...
    ulManifest.VSGImportScope == "complete_selected_ue_grant_transmission");
for pathValue = [outDL.KeysightCSVPaths; outUL.KeysightCSVPaths].'
    iq = readmatrix(pathValue);
    assert(isequal(size(iq), [n 2]) && all(isfinite(iq(:))) && ...
        max(abs(iq(:))) <= 1 + 10*eps);
end
loaded = load(outDL.MATPath, "waveform", "metadata");
assert(isequal(loaded.waveform, waveform) && ...
    loaded.metadata.SampleRateHz == 30.72e6 && ...
    loaded.metadata.CenterFrequencyHz == 3.5e9);

fprintf('Runtime Tx-IQ capture: exact CSV/MAT plus four headerless Keysight port files verified.\n');
ok = true;
end

function localCleanup(pathValue)
if isfolder(pathValue)
    rmdir(pathValue, "s");
end
end
