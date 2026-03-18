function ok = testOrganizeRunResults_E2EArtifactPreservation()
%TESTORGANIZERUNRESULTS_E2EARTIFACTPRESERVATION
% Ensure structured organizer preserves key E2E validation tables.

setup6GRSimToolkit("Verbose", false);
tmp = tempname;
mkdir(tmp);
c = onCleanup(@() rmdir(tmp, 's')); %#ok<NASGU>

runFolder = fullfile(tmp, "full3gpp_20990101_000000");
sixgr.util.ensureDir(fullfile(runFolder, "csv", ".keep"));

ioT = table(1, "DL", 100, 110, 95, ...
    'VariableNames', {'Slot','SlotDirection','DL_AppIn_Bytes','DL_SDAP_TxOut_Bytes','DL_AppOut_Bytes'});
chkT = table("DL", "SEMANTIC_INTEGRITY", true, "ok", ...
    'VariableNames', {'Direction','Component','Pass','Notes'});
pktT = table("DL", 10, 10, 0, true, ...
    'VariableNames', {'Direction','GeneratedPackets','DeliveredPackets','DeadlineMissPackets','SemanticPass'});

sixgr.util.csvWriteTable(fullfile(runFolder, "csv", "probe_e2e_component_io.csv"), ioT);
sixgr.util.csvWriteTable(fullfile(runFolder, "csv", "probe_e2e_component_checks.csv"), chkT);
sixgr.util.csvWriteTable(fullfile(runFolder, "csv", "probe_e2e_packet_integrity.csv"), pktT);

out = sixgr.report.OrganizeRunResults(runFolder, ...
    "ResultsRoot", tmp, ...
    "MirrorToResultsRoot", false);

e2eRoot = fullfile(out.StructuredFolder, "cross_layer", "e2e");
f1 = fullfile(e2eRoot, "probe_e2e_component_io.csv");
f2 = fullfile(e2eRoot, "probe_e2e_component_checks.csv");
f3 = fullfile(e2eRoot, "probe_e2e_packet_integrity.csv");

assert(exist(f1, "file") == 2, "Missing preserved E2E artifact: %s", f1);
assert(exist(f2, "file") == 2, "Missing preserved E2E artifact: %s", f2);
assert(exist(f3, "file") == 2, "Missing preserved E2E artifact: %s", f3);

txt = fileread(out.ManifestCSV);
assert(contains(txt, "csv/probe_e2e_component_io.csv"), "Manifest missing component_io source record.");
assert(contains(txt, "csv/probe_e2e_component_checks.csv"), "Manifest missing component_checks source record.");
assert(contains(txt, "csv/probe_e2e_packet_integrity.csv"), "Manifest missing packet_integrity source record.");

ok = true;
end
