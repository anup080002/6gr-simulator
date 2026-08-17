function ok = testPhase7EnergyGateWithoutDefectRows()
%TESTPHASE7ENERGYGATEWITHOUTDEFECTROWS Empty exception evidence is healthy.

root = tempname();
cleanup = onCleanup(@() localRemove(root)); %#ok<NASGU>
mkdir(fullfile(root, "reports", "csv"));
mkdir(fullfile(root, "rf", "csv"));

energy = table( ...
    ["ue_energy_per_successful_bit";"gnb_energy_per_successful_bit"], ...
    ["UE";"gNB"], ["observed";"observed"], [1e-7;2e-6], ...
    'VariableNames', {'MetricKey','Entity','Availability','ValueNumeric'});
sixgr.util.csvWriteTable(fullfile(root, "reports", "csv", ...
    "energy_efficiency_outputs.csv"), energy);

terms = table("term_" + string((1:12).'), repmat("AVAILABLE",12,1), ...
    ones(12,1), 'VariableNames', {'Term','Availability','Value'});
sixgr.util.csvWriteTable(fullfile(root, "rf", "csv", ...
    "energy_model_terms.csv"), terms);

% Intentionally do not create energy_root_cause_table.csv. It is an
% exception ledger and must not require fake rows on a defect-free run.
result = sixgr.analytics.evaluatePublicationReadinessGates(struct(), root);
T = result.Tables.Energy;
assert(logical(T.EnergyModelOk(1)) && logical(T.HasUEEnergyRows(1)) && ...
    logical(T.HasCellEnergyRows(1)) && T.RootCauseRows(1) == 0, ...
    "Measured UE/gNB energy with complete model terms must pass without synthetic root-cause rows.");

ok = true;
fprintf("PASS testPhase7EnergyGateWithoutDefectRows: no-defect energy evidence does not require fabricated exceptions.\n");
end

function localRemove(pathValue)
if isfolder(pathValue)
    rmdir(pathValue, "s");
end
end
