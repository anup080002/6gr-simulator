function ok = testLoadAllTrialDataCanonicalCSVDelimiter()
%TESTLOADALLTRIALDATACANONICALCSVDELIMITER Keep vector payloads inside CSV fields.

setup6GRSimToolkit("Verbose", false);
root = tempname;
mkdir(root);
cleanup = onCleanup(@() localRemove(root)); %#ok<NASGU>

layout = sixgr.report.resultLayout(root);
sixgr.util.ensureFolder(layout.AirInterfaceCSVDir);
parityVector = join(repmat("0", 1, 5000), "|");
sourceT = table("DL", 1, 5, parityVector, ...
    'VariableNames', {'Direction','Frame','SNR_dB','MeasuredLDPCParityCheckVector'});
sixgr.util.csvWriteTable(fullfile(layout.AirInterfaceCSVDir, ...
    "dl_pdsch_trials.csv"), sourceT);

loaded = sixgr.analytics.loadAllTrialData(root);
assert(height(loaded.dl) == 1 && width(loaded.dl) == width(sourceT), ...
    "Canonical CSV loader must not infer pipe-delimited vector payloads as table columns.");
assert(isequal(string(loaded.dl.Properties.VariableNames), ...
    string(sourceT.Properties.VariableNames)), ...
    "Canonical CSV loader must preserve the named comma-separated trial schema.");
assert(string(loaded.dl.MeasuredLDPCParityCheckVector(1)) == parityVector, ...
    "Canonical CSV loader must preserve the complete vector-valued evidence field.");

ok = true;
end

function localRemove(pathStr)
if exist(pathStr, "dir") == 7
    rmdir(pathStr, "s");
end
end
