classdef ValueComparator
    %VALUECOMPARATOR Typed, tolerance-aware qualification comparator.
    methods (Static)
        function result = compare(observed,expected,comparator,tolerance)
            op = upper(strtrim(string(comparator)));
            tol = str2double(string(tolerance));
            if ~isfinite(tol)
                tol = 0;
            end
            a = observed.Value;
            b = expected.Value;
            passed = false;
            if ismember(op,["EQUAL","NOT_EQUAL","LT","LE","GT","GE", ...
                    "WITHIN_ABS_TOLERANCE","WITHIN_REL_TOLERANCE"])
                [a,b] = localComparableScalars(a,b,observed.Type, ...
                    expected.Type);
                switch op
                    case "EQUAL"
                        if isnumeric(a) || islogical(a)
                            passed = abs(double(a)-double(b))<=tol;
                        else
                            passed = string(a)==string(b);
                        end
                    case "NOT_EQUAL"
                        if isnumeric(a) || islogical(a)
                            passed = abs(double(a)-double(b))>tol;
                        else
                            passed = string(a)~=string(b);
                        end
                    case "LT", passed = double(a)<double(b);
                    case "LE", passed = double(a)<=double(b)+tol;
                    case "GT", passed = double(a)>double(b);
                    case "GE", passed = double(a)>=double(b)-tol;
                    case "WITHIN_ABS_TOLERANCE"
                        passed = abs(double(a)-double(b))<=tol;
                    case "WITHIN_REL_TOLERANCE"
                        scale = max(abs(double(b)),eps);
                        passed = abs(double(a)-double(b))<=tol*scale;
                end
            elseif op=="STRING_EQUAL"
                localRequirePresentStrings(a,b);
                passed = string(a)==string(b);
            elseif op=="SHA256_EQUAL"
                a = lower(string(a));
                b = lower(string(b));
                localRequireSHA256(a);
                localRequireSHA256(b);
                passed = a==b;
            elseif op=="ALL_EQUAL"
                a = string(a);
                b = string(b);
                if isscalar(b)
                    passed = all(a(:)==b);
                elseif isequal(size(a),size(b))
                    passed = all(a(:)==b(:));
                end
            elseif op=="ALL_TRUE"
                passed = all(localLogical(a));
            elseif op=="ANY_TRUE"
                passed = any(localLogical(a));
            elseif op=="SET_EQUAL"
                passed = isequal(sort(unique(string(a(:)))), ...
                    sort(unique(string(b(:)))));
            elseif op=="NONDECREASING"
                x = localFiniteVector(a);
                passed = all(diff(x)>=-tol);
            elseif op=="NONINCREASING"
                x = localFiniteVector(a);
                passed = all(diff(x)<=tol);
            else
                error("FULLSTACK:UnsupportedValueComparator", ...
                    "Unsupported comparator '%s'.",op);
            end
            result = struct("Passed",isscalar(passed)&&logical(passed), ...
                "Comparator",op,"Tolerance",tol);
        end
    end
end

function [a,b] = localComparableScalars(a,b,aType,bType)
if numel(a)~=1 || numel(b)~=1
    error("FULLSTACK:ScalarComparatorRequired", ...
        "Comparator requires scalar operands.");
end
numericTypes = ["DOUBLE","INTEGER","LOGICAL"];
if ismember(string(aType),numericTypes)
    if ~ismember(string(bType),numericTypes)
        candidate = str2double(string(b));
        if ~isfinite(candidate)
            error("FULLSTACK:ValueTypeMismatch", ...
                "Numeric observation cannot be compared to '%s'.",string(b));
        end
        b = candidate;
    end
    a = double(a);
    b = double(b);
    if ~isfinite(a) || ~isfinite(b)
        error("FULLSTACK:NonFiniteObservedValue", ...
            "Numeric comparator operand is nonfinite.");
    end
elseif ismember(string(bType),numericTypes)
    candidate = str2double(string(a));
    if ~isfinite(candidate)
        error("FULLSTACK:ValueTypeMismatch", ...
            "String observation cannot be converted to numeric.");
    end
    a = candidate;
    b = double(b);
else
    localRequirePresentStrings(a,b);
    a = string(a);
    b = string(b);
end
end

function localRequirePresentStrings(a,b)
a = string(a);
b = string(b);
if any(ismissing(a(:))) || any(ismissing(b(:))) || ...
        any(strlength(strtrim(a(:)))==0) || ...
        any(strlength(strtrim(b(:)))==0)
    error("FULLSTACK:RequiredValueMissing", ...
        "A required string comparator operand is missing.");
end
end

function localRequireSHA256(value)
if numel(value)~=1 || isempty(regexp(char(value), ...
        '^[0-9a-f]{64}$','once'))
    error("FULLSTACK:InvalidSHA256Value", ...
        "SHA-256 comparator requires 64 lower-case hexadecimal characters.");
end
end

function value = localLogical(raw)
if islogical(raw)
    value = raw;
elseif isnumeric(raw)
    if any(~ismember(raw(:),[0 1]))
        error("FULLSTACK:InvalidLogicalValue", ...
            "Logical comparator accepts only 0 or 1 numeric values.");
    end
    value = logical(raw);
else
    text = lower(strtrim(string(raw)));
    value = false(size(text));
    trueMask = ismember(text,["true","1","pass"]);
    falseMask = ismember(text,["false","0","fail"]);
    if any(~(trueMask|falseMask))
        error("FULLSTACK:InvalidLogicalValue", ...
            "Logical comparator received a noncanonical text value.");
    end
    value(trueMask) = true;
end
end

function value = localFiniteVector(raw)
if ~isnumeric(raw)
    raw = str2double(string(raw));
end
value = double(raw(:));
if isempty(value) || any(~isfinite(value))
    error("FULLSTACK:NonFiniteObservedValue", ...
        "Monotonic comparator requires a finite numeric vector.");
end
end
