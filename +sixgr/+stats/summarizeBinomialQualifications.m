function [decisive,qualification]=summarizeBinomialQualifications(rows)
% Aggregate decisions, not probabilities or correlated candidate counts.
% StatisticallyQualified in evaluateBinomialStopping means a confidence
% bound established PASS OR FAIL. It is not an acceptance flag.
arguments
    rows table
end
decisive=false;
qualification="NOT_EVALUATED";
required=["StatisticallyQualified","StatisticalQualification"];
if isempty(rows) || ~all(ismember(required,string(rows.Properties.VariableNames)))
    return;
end
flags=rows.StatisticallyQualified;
status=upper(strtrim(string(rows.StatisticalQualification)));
validFlags=(islogical(flags)||isnumeric(flags)) && isreal(flags) && ...
    isequal(size(flags),[height(rows) 1]) && all(isfinite(flags)) && all(ismember(flags,[0 1]));
validStatus=~ismissing(status) & ismember(status,["PASS","FAIL"]);
decisive=validFlags && all(flags==1) && all(validStatus);
% A retained failure cannot be upgraded by another row's confidence flag,
% nor erased by empty/inconclusive rows elsewhere in the same population.
if any(status=="FAIL")
    qualification="FAIL";
elseif decisive && all(status=="PASS")
    qualification="PASS";
end
end
