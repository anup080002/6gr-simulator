function T=bindDataChannelScoreRows(T,scores)
% Keep observed per-attempt scores separate from unknown/unexecuted rows.
assert(istable(T) && iscell(scores) && numel(scores)==height(T), ...
    'sixgr:link:ChannelScoreCardinality','One score slot is required per actual trial.');
for row=1:height(T)
    score=scores{row};
    if isempty(score), continue; end
    assert(isstruct(score) && isscalar(score),'sixgr:link:ChannelScoreSchema','Use one actual score per row.');
    for name=string(fieldnames(score)).'
        value=score.(name);
        assert(isscalar(value),'sixgr:link:ChannelScoreSchema','Raw trial scores must be scalar.');
        if ~ismember(name,string(T.Properties.VariableNames))
            if isstring(value), T.(name)=strings(height(T),1);
            else, T.(name)=nan(height(T),1); end
        end
        T.(name)(row)=value;
    end
end
end
