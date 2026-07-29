classdef ValueCorrectnessEngine
    %VALUECORRECTNESSENGINE Evaluate the checked-in bounded expressions.
    methods (Static)
        function results = evaluate(ctx)
            contract = ctx.Profile.ValueChecks;
            n = height(contract);
            observedValue = strings(n,1);
            expectedValue = strings(n,1);
            status = repmat("FAIL",n,1);
            details = strings(n,1);
            evidencePath = strings(n,1);
            for index = 1:n
                try
                    sourceNames = unique(localList(contract.SourceCSV(index)), ...
                        "stable");
                    sourceTables = cell(numel(sourceNames),1);
                    sourcePaths = strings(numel(sourceNames),1);
                    for sourceIndex = 1:numel(sourceNames)
                        sourcePaths(sourceIndex) = localFindUnique( ...
                            ctx.RunFolder,sourceNames(sourceIndex));
                        sourceTables{sourceIndex} = readtable( ...
                            sourcePaths(sourceIndex),"TextType","string", ...
                            "VariableNamingRule","preserve");
                    end
                    T = localAppendTables(sourceTables);
                    observed = localEvaluateExpression( ...
                        string(contract.ObservedExpression(index)),T);
                    expected = localEvaluateExpression( ...
                        string(contract.ExpectedExpression(index)),T);
                    observedValue(index) = localDisplay(observed);
                    expectedValue(index) = localDisplay(expected);
                    passed = localCompare(observed,expected, ...
                        string(contract.Comparator(index)));
                    if passed
                        status(index) = "PASS";
                        details(index) = "Expression evaluated against actual artifact evidence.";
                    else
                        details(index) = "Comparator rejected the observed artifact value.";
                    end
                    evidencePath(index) = strjoin(sourcePaths,"|");
                catch ME
                    details(index) = string(ME.identifier) + ": " + ...
                        string(ME.message);
                end
            end
            required = localTruth(contract.Required);
            results = table(repmat(ctx.RunID,n,1), ...
                string(contract.CheckID),string(contract.Domain), ...
                string(contract.SubcaseID),required, ...
                string(contract.SourceCSV), ...
                string(contract.ObservedExpression),observedValue, ...
                string(contract.ExpectedExpression),expectedValue, ...
                string(contract.Comparator),string(contract.Tolerance), ...
                string(contract.Units),status, ...
                string(contract.FailureCode),evidencePath,details, ...
                'VariableNames', {'RunID','CheckID','Domain','SubcaseID','Required', ...
                'SourceCSV','ObservedExpression','ObservedValue', ...
                'ExpectedExpression','ExpectedValue','Comparator', ...
                'Tolerance','Units','Status','FailureCode', ...
                'EvidenceArtifactID','Details'});
            sixgr.util.csvWriteTable(fullfile(ctx.CSVDir, ...
                "full_stack_value_correctness_results.csv"),results);
        end
    end
end

function value = localEvaluateExpression(expression,T)
expression = strtrim(string(expression));
numeric = str2double(expression);
if isfinite(numeric)
    value = numeric;
    return;
end
if lower(expression) == "true", value = true; return; end
if lower(expression) == "false", value = false; return; end

token = regexp(char(expression), ...
    '^all\(isfinite\(([A-Za-z0-9_]+)\)\)$','tokens','once');
if ~isempty(token)
    value = all(isfinite(localNumeric(T,string(token{1}))));
    return;
end
token = regexp(char(expression), ...
    '^all\(([A-Za-z0-9_]+)>=([-+0-9.eE]+) & \1<=([-+0-9.eE]+)\)$', ...
    'tokens','once');
if ~isempty(token)
    x = localNumeric(T,string(token{1}));
    value = all(x >= str2double(token{2}) & x <= str2double(token{3}));
    return;
end
token = regexp(char(expression),'^all\(([A-Za-z0-9_]+)\)$', ...
    'tokens','once');
if ~isempty(token)
    value = localColumn(T,string(token{1}));
    return;
end
token = regexp(char(expression), ...
    '^max\(abs\(([A-Za-z0-9_]+)-([A-Za-z0-9_]+)\)\)$', ...
    'tokens','once');
if ~isempty(token)
    value = max(abs(localNumeric(T,string(token{1})) - ...
        localNumeric(T,string(token{2}))),[],"omitnan");
    return;
end
token = regexp(char(expression), ...
    '^max\(abs\(Delay_s-Distance3D_m/c\)\)$','tokens','once');
if ~isempty(token)
    value = max(abs(localNumeric(T,"Delay_s") - ...
        localNumeric(T,"Distance3D_m")/299792458),[],"omitnan");
    return;
end
token = regexp(char(expression), ...
    '^max\(abs\(([A-Za-z0-9_]+)\)\)$','tokens','once');
if ~isempty(token)
    value = max(abs(localNumeric(T,string(token{1}))),[],"omitnan");
    return;
end
token = regexp(char(expression),'^max\(([A-Za-z0-9_]+)\)$', ...
    'tokens','once');
if ~isempty(token)
    value = max(localNumeric(T,string(token{1})),[],"omitnan");
    return;
end
token = regexp(char(expression),'^min\(([A-Za-z0-9_]+)\)$', ...
    'tokens','once');
if ~isempty(token)
    value = min(localNumeric(T,string(token{1})),[],"omitnan");
    return;
end
token = regexp(char(expression),'^abs\(([A-Za-z0-9_]+)\)$', ...
    'tokens','once');
if ~isempty(token)
    value = abs(localNumeric(T,string(token{1})));
    return;
end
token = regexp(char(expression), ...
    '^([A-Za-z0-9_]+)\((highest|lowest)SNR\)$','tokens','once');
if ~isempty(token)
    x = localNumeric(T,localSNRColumn(T));
    y = localNumeric(T,string(token{1}));
    if string(token{2}) == "highest"
        [~,idx] = max(x);
    else
        [~,idx] = min(x);
    end
    value = y(idx);
    return;
end
if contains(expression,"+")
    fields = strip(split(expression,"+"));
    value = 0;
    for index = 1:numel(fields)
        value = value + localNumeric(T,fields(index));
    end
    return;
end
if ismember(expression,string(T.Properties.VariableNames))
    value = localColumn(T,expression);
    return;
end
% Unquoted contract constants such as PASS and RRC_CONNECTED.
value = expression;
end

function passed = localCompare(observed,expected,comparator)
comparator = upper(strtrim(string(comparator)));
if isnumeric(observed) || islogical(observed)
    if ~(isnumeric(expected) || islogical(expected))
        expectedNumeric = str2double(string(expected));
        if any(~isfinite(expectedNumeric))
            passed = false;
            return;
        end
        expected = expectedNumeric;
    end
    a = double(observed);
    b = double(expected);
    if isscalar(a) && ~isscalar(b), a = repmat(a,size(b)); end
    if isscalar(b) && ~isscalar(a), b = repmat(b,size(a)); end
    if ~isequal(size(a),size(b)) || any(~isfinite(a(:))) || ...
            any(~isfinite(b(:)))
        passed = false;
        return;
    end
    switch comparator
        case {"EQUAL","ALL_EQUAL"}, passed = all(abs(a(:)-b(:)) <= eps(max(abs([a(:);b(:);1]))));
        case "LE", passed = all(a(:) <= b(:));
        case "LT", passed = all(a(:) < b(:));
        case "GE", passed = all(a(:) >= b(:));
        case "GT", passed = all(a(:) > b(:));
        otherwise, passed = false;
    end
else
    a = string(observed);
    b = string(expected);
    if isscalar(b) && ~isscalar(a), b = repmat(b,size(a)); end
    if ~isequal(size(a),size(b))
        passed = false;
        return;
    end
    switch comparator
        case {"EQUAL","ALL_EQUAL"}, passed = all(a(:) == b(:));
        otherwise, passed = false;
    end
end
passed = isscalar(passed) && logical(passed);
end

function value = localColumn(T,name)
if ~ismember(name,string(T.Properties.VariableNames))
    error("FULLSTACK:ValueColumnMissing", ...
        "Required value column '%s' is absent.", name);
end
value = T.(char(name));
if iscell(value), value = string(value); end
end

function value = localNumeric(T,name)
raw = localColumn(T,name);
if isnumeric(raw) || islogical(raw)
    value = double(raw);
else
    value = str2double(string(raw));
end
if isempty(value) || all(~isfinite(value))
    error("FULLSTACK:NonFiniteObservedValue", ...
        "Column '%s' has no finite numeric evidence.", name);
end
end

function name = localSNRColumn(T)
for candidate = ["ConfiguredSNR_dB","SNR_dB","SNRdB"]
    if ismember(candidate,string(T.Properties.VariableNames))
        name = candidate;
        return;
    end
end
error("FULLSTACK:SNRColumnMissing","BLER endpoint check has no SNR column.");
end

function T = localAppendTables(tables)
T = tables{1};
for index = 2:numel(tables)
    if isequal(string(T.Properties.VariableNames), ...
            string(tables{index}.Properties.VariableNames))
        T = [T;tables{index}]; %#ok<AGROW>
    else
        error("FULLSTACK:ValueSourceSchemaMismatch", ...
            "Multi-source value check tables have different schemas.");
    end
end
end

function path = localFindUnique(root,name)
listing = dir(fullfile(root,"**",char(name)));
listing = listing(~[listing.isdir]);
if isempty(listing)
    error("FULLSTACK:ValueSourceMissing", ...
        "Required value source '%s' is missing.", name);
end
paths = unique(string(fullfile({listing.folder},{listing.name})));
if numel(paths) ~= 1
    error("FULLSTACK:AmbiguousValueSource", ...
        "Required value source '%s' resolved to %d files.", name,numel(paths));
end
path = paths(1);
end

function out = localList(value)
out = strip(split(string(value),"|"));
out = out(strlength(out)>0);
end

function tf = localTruth(value)
tf = ismember(lower(strtrim(string(value))),["true","1","yes"]);
end

function value = localDisplay(raw)
if isnumeric(raw) || islogical(raw)
    if isscalar(raw)
        value = string(raw);
    else
        value = "[" + strjoin(string(raw(:).'),",") + "]";
    end
else
    value = strjoin(string(raw(:).'),"|");
end
if strlength(value) > 4096
    value = extractBefore(value,4094) + "...";
end
end
