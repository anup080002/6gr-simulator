function policy=resolveMCSTransitionPolicy(declared)
%RESOLVEMCSTRANSITIONPOLICY Validate authored YAML; defaults live in catalog.
% This is an implementation policy, not a 3GPP MCS-step requirement.
assert(isstruct(declared)&&isscalar(declared), ...
    'sixgr:lls6g:config:InvalidMCSTransitionPolicy', ...
    'link_adaptation.mcs_transition must be a scalar mapping.');
names=["enabled","max_up_step","max_down_step","increase_ack_count"];
targets=["enabled","maxUpStep","maxDownStep","increaseAckCount"];
assert(all(ismember(string(fieldnames(declared)),names)), ...
    'sixgr:lls6g:config:InvalidMCSTransitionPolicy', ...
    'mcs_transition allows only enabled, max_up_step, max_down_step, increase_ack_count.');
base=sixgr.config.defaultConfig(); policy=base.phy.linkAdaptation.mcsTransition;
for k=1:numel(names)
    if ~isfield(declared,names(k)), continue; end
    value=declared.(names(k));
    if k==1
        valid=islogical(value)&&isscalar(value);
    else
        valid=isnumeric(value)&&~islogical(value)&&isreal(value)&& ...
            isscalar(value)&&isfinite(value)&&value==fix(value)&&value>=1;
        if k<=3, valid=valid&&value<=31; end
    end
    assert(valid,'sixgr:lls6g:config:InvalidMCSTransitionPolicy', ...
        'link_adaptation.mcs_transition.%s must be %s.',names(k), ...
        requirement(k));
    policy.(targets(k))=value;
end
end

function text=requirement(k)
if k==1, text="a scalar boolean";
elseif k<=3, text="an integer in [1,31]";
else, text="a finite positive integer";
end
end
