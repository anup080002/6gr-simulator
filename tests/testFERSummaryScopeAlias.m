function ok = testFERSummaryScopeAlias()
%TESTFERSUMMARYSCOPEALIAS FER summary alias must keep scope evidence.

setup6GRSimToolkit("Verbose", false);
runFolder = fullfile(tempdir, "sixgr_test_fer_scope_alias");
if exist(runFolder, "dir")
    rmdir(runFolder, "s");
end

dlT = localTrialTable("DL", [1; 2], [1; 1], [1; 0]);
ulT = localTrialTable("UL", [1; 2], [1; 1], [1; 1]);
rawTrials = struct("DL", dlT, "UL", ulT);

sixgr.truth.exportLLSLiveDerivedTables(sixgr.config.defaultConfig(), runFolder, rawTrials, struct(), struct(), struct());

ferPath = fullfile(runFolder, "air_interface", "csv", "fer_summary.csv");
assert(exist(ferPath, "file") == 2, "FER alias must be written under air_interface/csv.");
ferT = readtable(ferPath, "FileType", "text", "Delimiter", ",", ...
    "ReadVariableNames", true, "TextType", "string", "VariableNamingRule", "preserve");
assert(ismember("Scope", string(ferT.Properties.VariableNames)), "FER summary must include Scope.");
assert(any(ferT.Scope == "run"), "FER summary must include run-scope aggregate rows.");
assert(any(ferT.Scope == "ue"), "FER summary must include UE-scope rows.");
ok = true;
end

function T = localTrialTable(direction, ueIndex, frame, crcPass)
n = numel(ueIndex);
T = table( ...
    repmat(string(direction), n, 1), double(ueIndex(:)), double(100 + ueIndex(:)), ...
    double(frame(:)), (0:n-1).', ones(n, 1), repmat(20, n, 1), repmat(20, n, 1), ...
    repmat(19, n, 1), repmat(20, n, 1), repmat(20, n, 1), repmat(15, n, 1), ...
    repmat(10, n, 1), repmat(0, n, 1), repmat(0, n, 1), repmat(1, n, 1), ...
    repmat("QPSK", n, 1), repmat(0.25, n, 1), repmat("", n, 1), repmat("", n, 1), ...
    double(crcPass(:)), zeros(n, 1), repmat("PASS", n, 1), zeros(n, 1), repmat(1000, n, 1), ...
    'VariableNames', {'Direction','UEIndex','RNTI','Frame','Slot','BaseStationID', ...
    'SNR_dB','ConfiguredSNR_dB','AppliedAWGNSNR_dB','PostEqSINR_dB', ...
    'ReceiverHestSINR_dB','WidebandCQI','MCSIndex','PMI','CRI','RankIndicator', ...
    'Modulation','TargetCodeRate','PrecodingMode','AppliedPrecoderSource', ...
    'CRCPass','Crash','Status','BitErrors','BitsCompared'});
end
