function T=annotateTRSIntegrationBlocker(T,defaultBlocker)
% A committed observation's empty blocker is authoritative, not missing data.
names=string(T.Properties.VariableNames);
if ismember('TRSReceiverIntegrationBlocker',names)
    value=string(T.TRSReceiverIntegrationBlocker);
else
    value=strings(height(T),1);
end
committed=false(height(T),1);
if ismember('RuntimeStateUpdated',names)
    committed=T.RuntimeStateUpdated==1;
end
missing=ismissing(value) | strlength(strtrim(value))==0;
value(missing & ~committed)=string(defaultBlocker);
T.TRSReceiverIntegrationBlocker=value;
end
