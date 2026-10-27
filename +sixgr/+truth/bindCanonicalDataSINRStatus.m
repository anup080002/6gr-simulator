function T=bindCanonicalDataSINRStatus(T)
% Bind legacy data-SINR labels to the same original receiver observation.
% This creates no measurement and does not qualify estimator accuracy.
if ~istable(T) || isempty(T), return; end
required=["MeasuredSINR_dB","MeasuredTrialSINR_dB","SINRSource", ...
    "MeasuredTrialSINRSource","SINRValueRole","MeasuredTrialSINRValueRole", ...
    "MeasuredTrialSINRValueStatus","SINRMeasurementDomain"];
if ~all(ismember(required,string(T.Properties.VariableNames))), return; end
assert(isnumeric(T.MeasuredSINR_dB)&&isnumeric(T.MeasuredTrialSINR_dB)&& ...
    size(T.MeasuredSINR_dB,2)==1&&size(T.MeasuredTrialSINR_dB,2)==1, ...
    'sixgr:truth:DataSINRAliasMismatch','SINR aliases must be scalar numeric observations.');
status=string(T.MeasuredTrialSINRValueStatus);
eligible=isfinite(T.MeasuredTrialSINR_dB)&startsWith(upper(status),"OK");
if ~any(eligible), return; end
for pair={["SINRSource","MeasuredTrialSINRSource"], ...
        ["SINRValueRole","MeasuredTrialSINRValueRole"]}
    names=pair{1}; a=string(T.(names(1))); b=string(T.(names(2)));
    assert(all(a(eligible)==b(eligible))&&all(localRecorded(b(eligible))), ...
        'sixgr:truth:DataSINRAliasMismatch','SINR alias source/role differs from its original receiver record.');
end
assert(all(T.MeasuredSINR_dB(eligible)==T.MeasuredTrialSINR_dB(eligible))&& ...
    all(localRecorded(string(T.SINRMeasurementDomain(eligible)))), ...
    'sixgr:truth:DataSINRAliasMismatch','SINR aliases require identical values and an original measurement domain.');
if ~ismember('SINRValueStatus',T.Properties.VariableNames)
    T.SINRValueStatus=strings(height(T),1);
end
if ~ismember('SINRValueDefinition',T.Properties.VariableNames)
    T.SINRValueDefinition=strings(height(T),1);
end
old=string(T.SINRValueStatus); definition=string(T.SINRValueDefinition);
% Explicit contrary verdicts are not silently overwritten by this repair.
generic=ismember(lower(strtrim(old)),["available","ok","measured","estimated"]);
assert(all(~localRecorded(old(eligible))|generic(eligible)|old(eligible)==status(eligible)), ...
    'sixgr:truth:DataSINRAliasMismatch','Conflicting explicit SINR status must be resolved by its producer.');
old(eligible)=status(eligible);
missing=eligible&~localRecorded(definition);
definition(missing)="Alias of original MeasuredTrialSINR_dB; domain="+ ...
    string(T.SINRMeasurementDomain(missing))+"; estimator="+ ...
    string(T.MeasuredTrialSINRSource(missing))+"; estimator accuracy not qualified by this binding";
T.SINRValueStatus=old; T.SINRValueDefinition=definition;
end

function yes=localRecorded(values)
v=lower(strtrim(values));
yes=~ismissing(v)&strlength(v)>0&~ismember(v,["nan","unavailable","not_available"])& ...
    ~startsWith(v,"not_emitted_by_active_");
end
