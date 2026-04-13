function ok = testLLSFERRunScopeNoIdentityLeakage()
%TESTLLSFERRUNSCOPENOIDENTITYLEAKAGE Guard run-scope FER against UE identity bleed-through.

setup6GRSimToolkit("Verbose", false);

tmp = tempname;
mkdir(tmp);
c = onCleanup(@() rmdir(tmp, "s")); %#ok<NASGU>

cfg = sixgr.config.defaultConfig();
runFolder = fullfile(tmp, "run");
mkdir(runFolder);

% The raw rows deliberately carry UE/RNTI identity. The exporter must use
% those identities only for UE-scope rows, never for run-scope aggregates.
dlT = table( ...
    [4; 4; 7], [4; 4; 7], [4; 4; 7], [9; 9; 9], [1; 1; 1], [1; 1; 1], [1; 2; 2], [0; 1; 1], [0; 8; 0], [512; 512; 512], [false; false; false], ["PASS"; "FAIL"; "PASS"], ...
    'VariableNames', {'UEID','UEIndex','RNTI','SNR_dB','Frame','Slot','TransportBlockID','CRCPass','BitErrors','BitsCompared','Crash','Status'});
ulT = table( ...
    [4; 7], [4; 7], [4; 7], [9; 9], [1; 1], [1; 1], [1; 1], [1; 1], [0; 0], [512; 512], [false; false], ["PASS"; "PASS"], ...
    'VariableNames', {'UEID','UEIndex','RNTI','SNR_dB','Frame','Slot','TransportBlockID','CRCPass','BitErrors','BitsCompared','Crash','Status'});
rawTrials = struct( ...
    "DL", dlT, ...
    "UL", ulT, ...
    "SRS", table(), ...
    "TRS", table(), ...
    "MultiUserDL", table(), ...
    "MultiUserUL", table());

artifacts = sixgr.truth.exportLLSLiveDerivedTables(cfg, runFolder, rawTrials, struct(), struct(), struct());
ferT = artifacts.ErrorRateSummary;

assert(istable(ferT) && height(ferT) >= 2, ...
    "FER exporter must produce run-scope and UE-scope rows from raw runtime trials.");

runRows = ferT(strcmpi(string(ferT.Scope), "run"), :);
ueRows = ferT(strcmpi(string(ferT.Scope), "ue"), :);
assert(~isempty(runRows), "FER exporter must include explicit run-scope aggregate rows.");
assert(~isempty(ueRows), "FER exporter must include separate UE-scope rows.");

assert(all(~isfinite(double(runRows.UEID))) && all(~isfinite(double(runRows.UEIndex))) && all(~isfinite(double(runRows.RNTI))), ...
    "Run-scope FER rows must not carry UEID/UEIndex/RNTI, even when raw source rows carry RNTI=4.");
assert(~any(isfinite(double(runRows.RNTI)) & abs(double(runRows.RNTI) - 4) < 1e-9), ...
    "Run-scope FER rows must never leak RNTI=4.");
assert(any(isfinite(double(ueRows.RNTI)) & abs(double(ueRows.RNTI) - 4) < 1e-9), ...
    "UE-scope FER rows must remain the only scope allowed to carry RNTI=4.");
assert(all(strcmpi(string(runRows.ScopeDefinition), "all_ues_in_direction_aggregated_per_frame_no_ue_identity")), ...
    "Run-scope FER rows must declare aggregate/no-UE-identity semantics.");

persistedCells = readcell(char(artifacts.ErrorRateSummaryPath), "Delimiter", ",");
persistedHeader = string(persistedCells(1, :));
scopeCol = find(strcmpi(persistedHeader, "Scope"), 1, "first");
rntiCol = find(strcmpi(persistedHeader, "RNTI"), 1, "first");
assert(~isempty(scopeCol) && ~isempty(rntiCol), ...
    "Persisted FER CSV must expose Scope and RNTI columns.");
persistedRows = persistedCells(2:end, :);
persistedRunMask = strcmpi(string(persistedRows(:, scopeCol)), "run");
assert(any(persistedRunMask), "Persisted FER CSV must retain run-scope rows.");
persistedRunRNTI = persistedRows(persistedRunMask, rntiCol);
assert(all(cellfun(@localIsBlankOrNaN, persistedRunRNTI)), ...
    "Persisted run-scope FER CSV rows must keep RNTI blank/NaN.");

ok = true;
end

function tf = localIsBlankOrNaN(value)
if isempty(value)
    tf = true;
    return;
end
if isnumeric(value)
    tf = ~isfinite(double(value));
    return;
end
text = strtrim(string(value));
tf = strlength(text) == 0 || strcmpi(text, "NaN") || strcmpi(text, "missing");
end
