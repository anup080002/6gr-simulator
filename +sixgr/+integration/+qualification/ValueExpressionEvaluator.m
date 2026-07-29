classdef ValueExpressionEvaluator
    %VALUEEXPRESSIONEVALUATOR Evaluate parsed expressions without eval().
    methods (Static)
        function result = evaluate(ast,T)
            kind = string(ast.Kind);
            switch kind
                case "NUMERIC_LITERAL"
                    value = double(ast.Value);
                    type = "DOUBLE";
                case "LOGICAL_LITERAL"
                    value = logical(ast.Value);
                    type = "LOGICAL";
                case "IDENTIFIER"
                    if ismember(ast.Column,string(T.Properties.VariableNames))
                        value = localRequiredColumn(T,ast.Column);
                        localRequireScalar(value,ast.Text);
                        [value,type] = localNormalizeScalar(value,ast.Column);
                    else
                        value = string(ast.Column);
                        type = localStringType(value);
                    end
                case {"MAX","MIN","SUM"}
                    values = localNumeric(T,ast.Column);
                    switch kind
                        case "MAX", value = max(values);
                        case "MIN", value = min(values);
                        otherwise, value = sum(values);
                    end
                    type = "DOUBLE";
                case "COUNT"
                    localRequiredColumn(T,ast.Column);
                    value = height(T);
                    type = "INTEGER";
                case "ALL"
                    raw = localRequiredColumn(T,ast.Column);
                    if isnumeric(raw) || islogical(raw)
                        value = all(logical(raw));
                        type = "LOGICAL";
                    else
                        status = upper(strtrim(string(raw)));
                        localRejectMissingString(status,ast.Column);
                        if all(ismember(status,["PASS","FAIL"]))
                            if all(status=="PASS")
                                value = "PASS";
                            else
                                value = "FAIL";
                            end
                            type = "ENUM";
                        else
                            value = all(strlength(status)>0);
                            type = "LOGICAL";
                        end
                    end
                case "ANY"
                    raw = localRequiredColumn(T,ast.Column);
                    if isnumeric(raw) || islogical(raw)
                        value = any(logical(raw));
                    else
                        text = string(raw);
                        localRejectMissingString(text,ast.Column);
                        value = any(strlength(strtrim(text))>0);
                    end
                    type = "LOGICAL";
                case "ALL_ISFINITE"
                    values = localNumeric(T,ast.Column);
                    value = all(isfinite(values));
                    type = "LOGICAL";
                case "ALL_RANGE"
                    values = localNumeric(T,ast.Column);
                    value = all(values>=ast.Value(1) & values<=ast.Value(2));
                    type = "LOGICAL";
                case "MAX_ABS_DIFFERENCE"
                    a = localNumeric(T,ast.Columns(1));
                    b = localNumeric(T,ast.Columns(2));
                    if ~isequal(size(a),size(b))
                        error("FULLSTACK:ValueShapeMismatch", ...
                            "Difference operands have different sizes.");
                    end
                    if ast.Selector=="SECOND_DIVIDED_BY_C"
                        b = b/299792458;
                    end
                    value = max(abs(a-b));
                    type = "DOUBLE";
                case "MAX_ABS"
                    value = max(abs(localNumeric(T,ast.Column)));
                    type = "DOUBLE";
                case "ABS"
                    raw = localNumeric(T,ast.Column);
                    localRequireScalar(raw,ast.Text);
                    value = abs(raw);
                    type = "DOUBLE";
                case "SUM_COLUMNS"
                    value = 0;
                    for index = 1:numel(ast.Columns)
                        term = localNumeric(T,ast.Columns(index));
                        value = value + sum(term(:));
                    end
                    type = "DOUBLE";
                case "SELECT"
                    value = localSelect(T,ast.Column,ast.Selector);
                    [value,type] = localNormalizeScalar(value,ast.Column);
                case "SELECT_WHERE"
                    value = localWhere(T,ast.Column,ast.Columns(1), ...
                        ast.Selector);
                    [value,type] = localNormalizeScalar(value,ast.Column);
                otherwise
                    error("FULLSTACK:UnsupportedValueExpression", ...
                        "Unsupported AST kind '%s'.",kind);
            end
            result = localResult(ast,value,type);
        end
    end
end

function value = localSelect(T,column,selector)
raw = localRequiredColumn(T,column);
switch string(selector)
    case "first"
        index = 1;
    case "last"
        index = height(T);
    case {"highestSNR","lowestSNR"}
        name = localFirstColumn(T, ...
            ["ConfiguredSNR_dB","SNR_dB","SNRdB","SNR"]);
        x = localNumeric(T,name);
        if selector=="highestSNR"
            extreme = max(x);
        else
            extreme = min(x);
        end
        match = find(x==extreme);
        if numel(match)~=1
            error("FULLSTACK:AmbiguousValueSelector", ...
                "%s retained %d rows.",selector,numel(match));
        end
        index = match;
    case {"latestTime","earliestTime"}
        name = localFirstColumn(T, ...
            ["Timestamp","Time","UTC","GeneratedUTC","CompletedUTC"]);
        times = datetime(string(localRequiredColumn(T,name)), ...
            "TimeZone","UTC");
        if any(isnat(times))
            error("FULLSTACK:InvalidValueSelectorTime", ...
                "Time selector column contains missing timestamps.");
        end
        if selector=="latestTime"
            extreme = max(times);
        else
            extreme = min(times);
        end
        match = find(times==extreme);
        if numel(match)~=1
            error("FULLSTACK:AmbiguousValueSelector", ...
                "%s retained %d rows.",selector,numel(match));
        end
        index = match;
    otherwise
        error("FULLSTACK:UnsupportedValueSelector", ...
            "Unsupported row selector '%s'.",selector);
end
value = raw(index,:);
end

function value = localWhere(T,target,predicateColumn,predicateValue)
raw = localRequiredColumn(T,target);
predicate = localRequiredColumn(T,predicateColumn);
literal = string(predicateValue);
numericLiteral = str2double(literal);
if isnumeric(predicate) && isfinite(numericLiteral)
    match = double(predicate)==numericLiteral;
else
    match = string(predicate)==literal;
end
index = find(match);
if numel(index)~=1
    error("FULLSTACK:AmbiguousValueSelector", ...
        "where(%s == %s) retained %d rows.", ...
        predicateColumn,literal,numel(index));
end
value = raw(index,:);
end

function name = localFirstColumn(T,candidates)
present = candidates(ismember(candidates,string(T.Properties.VariableNames)));
if isempty(present)
    error("FULLSTACK:ValueSelectorColumnMissing", ...
        "No selector column is available.");
end
name = present(1);
end

function value = localRequiredColumn(T,name)
if ~ismember(name,string(T.Properties.VariableNames))
    error("FULLSTACK:ValueColumnMissing", ...
        "Required value column '%s' is absent.",name);
end
value = T.(char(name));
if iscell(value)
    value = string(value);
end
if isempty(value)
    error("FULLSTACK:RequiredValueMissing", ...
        "Required value column '%s' is empty.",name);
end
end

function value = localNumeric(T,name)
raw = localRequiredColumn(T,name);
if isnumeric(raw) || islogical(raw)
    value = double(raw);
else
    text = string(raw);
    localRejectMissingString(text,name);
    value = str2double(text);
end
if isempty(value) || any(~isfinite(value(:)))
    error("FULLSTACK:NonFiniteObservedValue", ...
        "Column '%s' contains missing, NaN, or Inf values.",name);
end
end

function localRequireScalar(value,expression)
if numel(value)~=1
    error("FULLSTACK:ScalarValueRequired", ...
        "Expression '%s' produced %d values without a reducer.", ...
        expression,numel(value));
end
end

function [value,type] = localNormalizeScalar(value,name)
localRequireScalar(value,name);
if islogical(value)
    type = "LOGICAL";
    return;
end
if isnumeric(value)
    if ~isfinite(value)
        error("FULLSTACK:NonFiniteObservedValue", ...
            "Required scalar '%s' is nonfinite.",name);
    end
    if value==fix(value)
        type = "INTEGER";
    else
        type = "DOUBLE";
    end
    value = double(value);
    return;
end
value = string(value);
localRejectMissingString(value,name);
value = value(1);
type = localStringType(value);
end

function type = localStringType(value)
text = string(value);
if ~ismissing(text) && ...
        ~isempty(regexp(char(lower(text)), ...
        '^[0-9a-f]{64}$','once'))
    type = "SHA256";
elseif ismember(upper(text),["PASS","FAIL","BLOCKED","SKIPPED", ...
        "INTERRUPTED","NOT_APPLICABLE"])
    type = "ENUM";
else
    type = "STRING";
end
end

function localRejectMissingString(value,name)
value = string(value);
if any(ismissing(value(:))) || any(strlength(strtrim(value(:)))==0)
    error("FULLSTACK:RequiredValueMissing", ...
        "Required string value '%s' is missing or empty.",name);
end
end

function result = localResult(ast,value,type)
result = struct();
result.Value = value;
result.Type = string(type);
result.Scalar = isscalar(value);
result.ParsedExpression = string(ast.Kind) + ":" + string(ast.Text);
result.Display = localDisplay(value);
result.Digest = lower(string(sixgr.util.sha256Hex( ...
    unicode2native(char(result.Display),"UTF-8"))));
end

function text = localDisplay(value)
if islogical(value)
    text = lower(string(value));
elseif isnumeric(value)
    text = compose("%.17g",double(value));
elseif isdatetime(value) || isduration(value)
    text = string(value);
else
    text = string(value);
end
text = strjoin(reshape(text,1,[]),"|");
end
