function source=seedInstalledControlScenario(base,policy,seed,signal)
% Seed authored paths BEFORE normal runtime configuration construction.
arguments
    base (1,1) sixgr.lls6g.config.ScenarioConfig
    policy (1,1) struct
    seed (1,1) double {mustBeInteger,mustBeNonnegative}
    signal (1,1) string {mustBeMember(signal,["PUCCH","PDCCH"])}
end
assert(seed<=2^32-1,char("sixgr:"+lower(signal)+":InvalidEpisodeSeed"),'Seed exceeds uint32.');
data=base.toStruct();
for path=string(policy.scenario_seed_paths(:)).'
    assert(base.has(path),char("sixgr:"+lower(signal)+":MissingEpisodeSeedPath"), ...
        'The installed scenario has no authored seed path %s.',path);
    old=base.get(path);
    assert(isnumeric(old)&&isscalar(old)&&isfinite(old),char("sixgr:"+lower(signal)+":AmbiguousEpisodeSeed"), ...
        'Independent episodes require one numeric seed at %s, not a seed sweep.',path);
    data=sixgr.util.structSet(data,path,seed);
end
sixgr.lls6g.config.validateScenarioConfig(data,'Context',policy.profile_id);
source=sixgr.lls6g.config.ScenarioConfig(data,'SourceFiles',base.SourceFiles, ...
    'ConfigPath',base.ConfigPath,'Kind',base.Kind, ...
    'ConfigHash',sixgr.lls6g.config.hashResolvedScenario(data));
end
