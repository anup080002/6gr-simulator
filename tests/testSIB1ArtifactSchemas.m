function ok = testSIB1ArtifactSchemas()
%TESTSIB1ARTIFACTSCHEMAS Mini-run must export SIB1 evidence artifacts.

setup6GRSimToolkit("Verbose", false);
if exist("nrWaveformGenerator", "file") ~= 2
    ok = true;
    return;
end
[supported, ~] = sixgr.phy.broadcast.siRNTIWaveformSupported();
if ~supported
    ok = true;
    return;
end
runFolder = fullfile(tempdir, "sixgr_test_sib1_artifacts");
if exist(runFolder, "dir")
    rmdir(runFolder, "s");
end
out = sixgr.phy.broadcast.runSIB1StrictMiniAnchor(runFolder, sixgr.config.defaultConfig());
assert(logical(out.Ok), "SIB1 strict mini-run must pass before artifact schema checks.");
required = [ ...
    "control/csv/sib1_recovery_trials.csv"
    "control/csv/pbch_recovery_trials.csv"
    "control/csv/mib_field_evidence.csv"
    "control/csv/mib_pdcch_config_sib1_recovery.csv"
    "control/csv/coreset0_derivation.csv"
    "control/csv/searchspace0_derivation.csv"
    "control/csv/sib1_pdcch_candidates.csv"
    "control/csv/sib1_negative_trials.csv"
    "control/csv/sib1_asn1_roundtrip.csv"
    "control/csv/sib1_conformance_summary.csv"
    "control/csv/sib1_waveform_decode_trace.csv"
    "air_interface/csv/pbch_mib_sib1_trials.csv"
    "reports/csv/sib1_conformance_summary.csv"
    "reports/json/sib1_tx_tree.json"
    "reports/json/sib1_rx_tree.json"
    "reports/binary/sib1_tx_payload.bin"
    "reports/binary/sib1_rx_payload.bin"
    "reports/figures/sib1_decode_flow.svg"];
for i = 1:numel(required)
    assert(exist(fullfile(runFolder, required(i)), "file") == 2, "Missing SIB1 artifact: " + required(i));
end
T = readtable(fullfile(runFolder, "control/csv/sib1_recovery_trials.csv"), "VariableNamingRule", "preserve");
assert(height(T) == 1 && logical(T.StrictOk(1)), "SIB1 recovery CSV must contain one strict passing positive row.");
C = readtable(fullfile(runFolder, "control/csv/sib1_conformance_summary.csv"), "VariableNamingRule", "preserve");
assert(height(C) == 1 && logical(C.StrictOk(1)), "Control-side SIB1 conformance summary must contain one strict passing row.");
Trace = readtable(fullfile(runFolder, "control/csv/sib1_waveform_decode_trace.csv"), "VariableNamingRule", "preserve");
assert(height(Trace) >= 8 && ismember("UsedOracleFields", string(Trace.Properties.VariableNames)), ...
    "SIB1 waveform decode trace must expose per-stage evidence and oracle guard state.");
PBCH = readtable(fullfile(runFolder, "control/csv/pbch_recovery_trials.csv"), "VariableNamingRule", "preserve");
assert(height(PBCH) == 1 && all(ismember(["BCHTransportBlockHash","MIBSFN4LSBValue", ...
    "MIBHalfFrameBit","MIBDecodedBitSource"], string(PBCH.Properties.VariableNames))), ...
    "PBCH recovery CSV must expose decoded BCH/MIB bit evidence.");
MIB = readtable(fullfile(runFolder, "control/csv/mib_field_evidence.csv"), "VariableNamingRule", "preserve");
assert(any(string(MIB.MIBEvidenceField) == "BCHTransportBlock") && ...
    any(string(MIB.MIBEvidenceField) == "SFN4LSB") && ...
    any(string(MIB.MIBEvidenceField) == "pdcch-ConfigSIB1"), ...
    "MIB field evidence CSV must expose decoded BCH block, SFN4LSB, and pdcch-ConfigSIB1 evidence.");
MIBPDCCH = readtable(fullfile(runFolder, "control/csv/mib_pdcch_config_sib1_recovery.csv"), "VariableNamingRule", "preserve");
assert(height(MIBPDCCH) == 1 && MIBPDCCH.PDCCHConfigSIB1(1) == 0 && ...
    MIBPDCCH.ControlResourceSetZero(1) == 0 && MIBPDCCH.SearchSpaceZero(1) == 0, ...
    "MIB pdcch-ConfigSIB1 recovery CSV must expose decoded Type0 CSS indices.");
CORESET0 = readtable(fullfile(runFolder, "control/csv/coreset0_derivation.csv"), "VariableNamingRule", "preserve");
SS0 = readtable(fullfile(runFolder, "control/csv/searchspace0_derivation.csv"), "VariableNamingRule", "preserve");
assert(height(CORESET0) == 1 && logical(CORESET0.CORESET0Present(1)), ...
    "CORESET0 derivation CSV must contain the resolved CORESET0 row.");
assert(height(SS0) == 1 && SS0.SearchSpaceZero(1) == 0 && SS0.PDCCHCandidatesAttempted(1) > 0, ...
    "SearchSpace0 derivation CSV must contain the resolved Type0 monitoring row.");
N = readtable(fullfile(runFolder, "control/csv/sib1_negative_trials.csv"), "VariableNamingRule", "preserve");
assert(height(N) >= 3 && ~any(logical(N.StrictOk)), "Negative SIB1 rows must not pass strict.");
ok = true;
end
