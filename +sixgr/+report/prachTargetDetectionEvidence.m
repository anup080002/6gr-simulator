function [missed, wrong, scope] = prachTargetDetectionEvidence(raw)
%PRACHTARGETDETECTIONEVIDENCE Score targets after independent PRACH reception.
% A strongest candidate is not the whole received set. Repeated UE rows for
% one occasion are target observations, not independent false-alarm trials.
n = height(raw);
tx = double(raw.PreambleIndexTx);
rx = double(raw.PreambleIndexDetected);
present = double(raw.PreambleDetected);
missed = double(present == 0);
wrong = double(rx ~= tx);
wrong(~isfinite(tx) | ~isfinite(rx) | present ~= 1) = NaN;
scope = repmat("legacy_single_candidate", n, 1);
vars = string(raw.Properties.VariableNames);
fields = ["DetectedPreambleSet","DetectedPreambleSetAvailable"];
if ~any(ismember(fields, vars)), return; end
if ~all(ismember(fields, vars))
    error('sixgr:report:IncompletePRACHDetectionSet', ...
        'Received preamble set and its availability must be exported together.');
end
available = double(raw.DetectedPreambleSetAvailable);
if any(~ismember(available, [0 1]))
    error('sixgr:report:InvalidPRACHDetectionSet', 'Invalid received-set availability.');
end
for k = 1:n
    text = strtrim(string(raw.DetectedPreambleSet(k)));
    if ismissing(text), text = ""; end
    if ~available(k)
        if strlength(text) > 0
            error('sixgr:report:InvalidPRACHDetectionSet', ...
                'Unavailable received set must not contain candidate identities.');
        end
        continue;
    end
    indices = zeros(0,1);
    if strlength(text) > 0, indices = str2double(split(text, '|')); end
    if any(~isfinite(indices) | indices < 0 | indices > 63 | indices ~= fix(indices)) ...
            || numel(unique(indices)) ~= numel(indices) ...
            || ~isfinite(tx(k)) || tx(k) < 0 || tx(k) > 63 || tx(k) ~= fix(tx(k)) ...
            || ~ismember(present(k), [0 1]) ...
            || logical(present(k)) ~= ~isempty(indices) ...
            || (present(k) == 1 && ~ismember(rx(k), indices))
        error('sixgr:report:InvalidPRACHDetectionSet', ...
            'Received preamble set, detection flag, strongest candidate or target is inconsistent.');
    end
    missed(k) = double(~ismember(tx(k), indices));
    wrong(k) = NaN;
    if present(k) == 1, wrong(k) = missed(k); end
    scope(k) = "per_target_shared_occasion_not_independent_trials";
end
end
