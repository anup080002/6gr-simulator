function runtimeTrials = selectCanonicalRuntimeControlTrials(T, signalFamily)
%SELECTCANONICALRUNTIMECONTROLTRIALS Select slot-coupled primary evidence.
%
% Supplemental strict-validation campaigns are waveform truth, but they
% are not rows from the scenario's coupled slot runtime.  This selector
% preserves that semantic boundary using explicit lineage columns.

arguments
    T table
    signalFamily {mustBeTextScalar}
end

runtimeTrials = table();
if isempty(T)
    return;
end
signalFamily = lower(strtrim(string(signalFamily)));
expectedArtifact = "air_interface/csv/" + signalFamily + "_trials.csv";
mask = false(height(T), 1);
specs = [ ...
    struct("Column", "RuntimeStateConsumer", "Tokens", ["coupledtruthruntime"]); ...
    struct("Column", "RuntimeEvidenceSource", "Tokens", ["coupledtruthruntime","slot_coupled_truth"]); ...
    struct("Column", "SourceArtifact", "Tokens", [expectedArtifact]); ...
    struct("Column", "ArtifactClass", "Tokens", ["canonical_control_reference_signal_runtime_evidence","canonical_control_runtime_evidence"]); ...
    struct("Column", "ValueRole", "Tokens", ["control_reference_signal_runtime_evidence","measured_runtime"]); ...
    struct("Column", "ExecutionModel", "Tokens", ["slot_coupled_truth"] )];
for i = 1:numel(specs)
    name = string(specs(i).Column);
    if ~ismember(name, string(T.Properties.VariableNames))
        continue;
    end
    values = lower(strtrim(string(T.(char(name)))));
    for token = lower(string(specs(i).Tokens))
        mask = mask | contains(values, token);
    end
end
runtimeTrials = T(mask, :);
end

function mustBeTextScalar(value)
if ~(ischar(value) || (isstring(value) && isscalar(value)))
    error("sixgr:truth:BadSignalFamily", ...
        "signalFamily must be a character vector or scalar string.");
end
end
