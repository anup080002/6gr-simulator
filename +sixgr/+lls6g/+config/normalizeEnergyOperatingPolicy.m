function cfg=normalizeEnergyOperatingPolicy(cfg,authority)
% One authored policy across modern/legacy energy surfaces. No default wins.
arguments
    cfg (1,1) struct
    authority (1,1) struct = struct()
end
pairs={ ...
    ["energy_and_complexity.sleep_state_model","energy_efficiency.sleep_state_model"], ...
    ["energy_and_complexity.race_to_sleep_metrics","energy_efficiency.race_to_sleep_enabled"]};
for k=1:numel(pairs)
    paths=pairs{k}; values=cell(1,2); present=false(1,2);
    for n=1:2
        parts=split(paths(n),'.');
        present(n)=isfield(authority,parts(1)) && isfield(authority.(parts(1)),parts(2));
        if present(n), values{n}=authority.(parts(1)).(parts(2)); end
    end
    if ~any(present)
        for n=1:2
            values{n}=sixgr.util.structGet(cfg,paths(n),[]);
            present(n)=~isempty(values{n});
        end
    end
    if ~any(present), continue; end
    if k==1
        values(present)=cellfun(@(v)string(v),values(present),'UniformOutput',false);
    else
        if present(1)
            token=string(values{1});
            assert(isscalar(token)&&any(token==["enabled","disabled"]), ...
                'sixgr:lls6g:config:EnergyOperatingPolicyConflict', ...
                'energy_and_complexity.race_to_sleep_metrics must be enabled or disabled.');
            values{1}=token=="enabled";
        end
        if present(2)
            assert(islogical(values{2})&&isscalar(values{2}), ...
                'sixgr:lls6g:config:EnergyOperatingPolicyConflict', ...
                'energy_efficiency.race_to_sleep_enabled must be a boolean.');
        end
    end
    assert(~all(present)||isequaln(values{1},values{2}), ...
        'sixgr:lls6g:config:EnergyOperatingPolicyConflict', ...
        'Conflicting energy policy aliases %s and %s in the same authority.',paths(1),paths(2));
    value=values{find(present,1)};
    if k==1
        cfg=sixgr.util.structSet(cfg,paths(1),value);
    else
        token="disabled"; if value, token="enabled"; end
        cfg=sixgr.util.structSet(cfg,paths(1),token);
    end
    cfg=sixgr.util.structSet(cfg,paths(2),value);
end
sixgr.lls6g.config.validateEnergyOperatingPolicy(cfg);
end
