function summary = validatePDCCHImpactPairing(experimentMatrix, rawTrials)
%VALIDATEPDCCHIMPACTPAIRING Enforce the paired-experiment identity contract.

if ischar(experimentMatrix) || isstring(experimentMatrix)
    experiments = readtable(experimentMatrix, "TextType", "string", ...
        "VariableNamingRule", "preserve");
else
    experiments = experimentMatrix;
end
if ischar(rawTrials) || isstring(rawTrials)
    trials = readtable(rawTrials, "TextType", "string", ...
        "VariableNamingRule", "preserve");
else
    trials = rawTrials;
end
if ~istable(experiments) || ~istable(trials)
    error("sixgr:phy:pdcch:impact_pairing_failure", ...
        "Pairing validation requires experiment and raw-trial tables.");
end

pairIDs = unique(string(experiments.PairID), "stable");
matrixFailures = strings(0,1);
ignored = ["ExperimentID","Variant","FactorValue"];
columns = setdiff(string(experiments.Properties.VariableNames), ignored, "stable");
for ii = 1:numel(pairIDs)
    pair = experiments(string(experiments.PairID) == pairIDs(ii),:);
    if height(pair) ~= 2 || ...
            ~isequal(sort(string(pair.Variant)), ["baseline";"treatment"])
        matrixFailures(end+1,1) = pairIDs(ii) + ":variant_coverage"; %#ok<AGROW>
        continue;
    end
    for jj = 1:numel(columns)
        values = string(pair.(columns(jj)));
        if any(values ~= values(1))
            matrixFailures(end+1,1) = pairIDs(ii) + ":" + columns(jj); %#ok<AGROW>
        end
    end
end

trialFailures = strings(0,1);
identityFields = ["ChannelRealizationID","NoiseRealizationID","PayloadID"];
trialPairIDs = unique(string(trials.PairID), "stable");
for ii = 1:numel(trialPairIDs)
    pair = trials(string(trials.PairID) == trialPairIDs(ii),:);
    if ~isequal(sort(unique(string(pair.Variant))), ["baseline";"treatment"])
        trialFailures(end+1,1) = trialPairIDs(ii) + ":variant_coverage"; %#ok<AGROW>
        continue;
    end
    for jj = 1:numel(identityFields)
        values = unique(string(pair.(identityFields(jj))));
        if numel(values) ~= 1 || strlength(values) == 0
            trialFailures(end+1,1) = trialPairIDs(ii) + ":" + ...
                identityFields(jj); %#ok<AGROW>
        end
    end
end

failures = [matrixFailures; trialFailures];
if ~isempty(failures)
    error("sixgr:phy:pdcch:impact_pairing_failure", ...
        "Paired PDCCH impact inputs differ outside the declared factor: %s.", ...
        strjoin(failures(1:min(10,numel(failures))), ", "));
end
summary = struct("Passed", true, "PairCount", numel(pairIDs), ...
    "RawPairCount", numel(trialPairIDs), "FailureCount", 0, ...
    "Status", "PASS");
end
