function ok=testEmptyLinkTrialSchema(retainedCSV,outputCSV)
% Schema only; no fake trial, configured measurement, lifecycle or CRC row.
if nargin<1, T=table(zeros(0,1),'VariableNames',{'Slot'});
else, T=readtable(retainedCSV,'TextType','string'); end
before=T; fields=string(T.Properties.VariableNames);
out=sixgr.link.completeEmptyLinkTrialSchema(T);
assert(height(out)==0 && isequaln(out(:,cellstr(fields)),before));
assert(isa(out.EffectiveLayers,'double') && isstring(out.ConfigHash) && islogical(out.FinalizedFlag));
assert(isequaln(out,sixgr.link.completeEmptyLinkTrialSchema(out)));
bad=table(1,'VariableNames',{'Slot'}); caught=false;
try, sixgr.link.completeEmptyLinkTrialSchema(bad);
catch ex, caught=strcmp(ex.identifier,'sixgr:link:NonemptySchemaCompletion'); end
assert(caught,'Never use schema completion to fill actual measurement gaps.');
if nargin>1
    sixgr.util.csvWriteTable(outputCSV,out,'PreserveSchema',true);
    saved=readtable(outputCSV,'TextType','string');
    assert(height(saved)==0 && isequal(saved.Properties.VariableNames,out.Properties.VariableNames));
end
fprintf('EMPTY_LINK_SCHEMA_PASS rows=0 columns=%d existing_values_unchanged=1\n',width(out));
ok=true;
end
