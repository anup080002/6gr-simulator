function T=bindDataCRCOutcome(T)
% Label the original data decoder outcome; never infer CRC from goodput or status.
assert(istable(T)&&all(ismember({'CRCApplicable','CRCPass'},T.Properties.VariableNames)), ...
    'sixgr:truth:DataCRCColumns','Data CRC publication requires original applicability and decoder outcome.');
app=number(T.CRCApplicable); crc=number(T.CRCPass);
assert(all(isnan(app)|app==0|app==1)&&all(isnan(crc)|crc==0|crc==1), ...
    'sixgr:truth:DataCRCValue','CRC flags must be binary or explicitly unavailable.');
observed=app==1&isfinite(crc);
if ismember('DecodeAttempted',T.Properties.VariableNames)
    assert(all(~observed|number(T.DecodeAttempted)==1), ...
        'sixgr:truth:DataCRCWithoutDecode','An observed CRC requires an actual decoder attempt.');
end
outcome=repmat("unavailable",height(T),1);
outcome(app==0)="not_applicable";
outcome(observed&crc==0)="fail"; outcome(observed&crc==1)="pass";
if ismember('CRCOutcome',T.Properties.VariableNames)
    prior=lower(strtrim(string(T.CRCOutcome)));
    claimed=ismember(prior,["pass","fail"]);
    assert(all(~claimed|prior==outcome), ...
        'sixgr:truth:DataCRCConflict','Published CRC label conflicts with the original decoder evidence.');
end
T.CRCOutcome=outcome;
end

function value=number(value)
if isnumeric(value)||islogical(value), value=double(value); else
    token=lower(strtrim(string(value))); value=str2double(token);
    value(token=="true")=1; value(token=="false")=0;
end
value=value(:);
end
