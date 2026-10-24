function policy=validateLDPCPolicy(policy,sourcePrefix)
%VALIDATELDPCPOLICY Validate present decoder-policy fields without defaulting.
% Catalog values are receiver implementation policy, not a 3GPP decoder
% mandate. A valid inactive scaling/offset remains configured, not applied.
% scheduleType asserts the algorithm's native schedule; it cannot select a
% different schedule or silently change the requested algorithm.
arguments
    policy (1,1) struct
    sourcePrefix (1,1) string = "phy.ldpc"
end
catalog=sixgr.config.loadCoreCatalog();
rules=catalog.parameters.phy.ldpc;
names=["algorithm","scalingFactor","minSumOffset","termination","scheduleType"];
id='sixgr:config:InvalidLDPCPolicy';
for name=names
    if ~isfield(policy,name), continue; end
    value=policy.(name); rule=rules.(name); path=sourcePrefix+"."+name;
    if string(rule.value_type)=="number"
        assert(isnumeric(value)&&isreal(value)&&isscalar(value)&&isfinite(value), ...
            id,'%s must be a nonempty real finite numeric scalar.',path);
        if isfield(rule,'min')
            assert(value>=rule.min,id,'%s must be >= %g.',path,rule.min);
        end
        if isfield(rule,'min_exclusive')
            assert(value>rule.min_exclusive,id,'%s must be > %g.',path,rule.min_exclusive);
        end
        if isfield(rule,'max')
            assert(value<=rule.max,id,'%s must be <= %g.',path,rule.max);
        end
        policy.(name)=double(value);
    else
        assert((ischar(value)&&isrow(value))||(isstring(value)&&isscalar(value)), ...
            id,'%s must be nonempty scalar text.',path);
        token=string(value); allowed=string(rule.allowed_values);
        assert(~ismissing(token)&&strlength(token)>0,id,'%s must be nonempty scalar text.',path);
        index=find(strcmpi(token,allowed));
        assert(isscalar(index),id,'%s must be one of: %s.',path,strjoin(allowed,', '));
        policy.(name)=char(allowed(index));
    end
end
if isfield(policy,'algorithm')&&isfield(policy,'scheduleType')
    index=find(strcmpi(string(policy.algorithm),string(rules.algorithm.allowed_values)));
    schedules=string(rules.algorithm.schedule_types);
    assert(strcmpi(string(policy.scheduleType),schedules(index)), ...
        'sixgr:config:LDPCScheduleConflict', ...
        '%s.scheduleType=%s conflicts with %s.algorithm=%s, whose native schedule is %s.', ...
        sourcePrefix,string(policy.scheduleType),sourcePrefix,string(policy.algorithm),schedules(index));
end
end
