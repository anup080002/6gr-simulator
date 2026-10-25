function ok=testPRACHPeriodAliasAuthority()
% Period assertions cannot override native PRACH-table/TDD occasions.
% Native mapping and YAML integration, not received/detection qualification.
setup6GRSimToolkit('Verbose',false,'RunToolboxChecks',false);
slotPaths=["phy.prach.period_slots","random_access.prach_periodicity_slots", ...
    "random_access.periodicity_slots"];
msPaths=["random_access.prach_periodicity_ms","random_access.periodicity_ms"];
for scs=[15 30]
    cfg=struct('phy',struct('frequencyRange',"FR1",'duplex',struct('mode',"FDD"), ...
        'carrier',struct('SubcarrierSpacing',scs,'NSizeGrid',52), ...
        'prach',struct('configurationIndex',16,'subcarrierSpacing_kHz',1.25)));
    original=sixgr.phy.frame.PRACHOccasionResolver.resolveFromConfig(cfg);
    assert(original.ResolvedValid && original.IndependentReferenceValidated);
    both=cfg;
    for path=slotPaths
        both=sixgr.util.structSet(both,path,original.PeriodCarrierSlots);
    end
    for path=msPaths
        both=sixgr.util.structSet(both,path,original.PeriodCarrierSlots/(scs/15));
    end
    actual=sixgr.phy.frame.PRACHOccasionResolver.resolveFromConfig(both);
    assert(isequaln(original,actual),'Matching aliases must not modify native occasions.');
    for path=[slotPaths msPaths]
        value=sixgr.util.structGet(both,path,[]);
        bad=sixgr.util.structSet(both,path,value*2);
        reject(@()sixgr.phy.frame.validatePRACHPeriodAliases(bad,original), ...
            'sixgr:phy:frame:PRACHPeriodAliasConflict');
        for malformed={true,'10',NaN,Inf,-1,0,1i,[1 2],bitshift(uint64(1),53)+uint64(1)}
            bad=sixgr.util.structSet(both,path,malformed{1});
            reject(@()sixgr.phy.frame.validatePRACHPeriodAliases(bad,original), ...
                'sixgr:phy:frame:InvalidPRACHPeriodAlias');
        end
    end
    bad=both;bad.random_access.periodicity_ms=0.3;
    reject(@()sixgr.phy.frame.validatePRACHPeriodAliases(bad,original), ...
        'sixgr:phy:frame:InvalidPRACHPeriodAlias');
    bad=both;bad.random_access.periodicity_ms=2*both.random_access.periodicity_ms;
    reject(@()sixgr.phy.frame.PRACHOccasionResolver.resolveFromConfig(bad), ...
        'sixgr:phy:frame:PRACHPeriodAliasConflict');
end
% Exercise the actual n40 YAML builder, including a shadowed ms alias that
% formerly disappeared when the final native timing overwrote period_slots.
scenario=sixgr.lls6g.config.loadScenarioConfig( ...
    'simulator/configs/scenarios/lls_tdd_n40_20mhz_64txru_4rx_cdlc100_reference_snr_sweep.yaml');
cfg=sixgr.lls6g.buildInternalConfig(scenario,tempname);
original=cfg.phy.prach.timing;
data=scenario.Data;
data.random_access.prach_periodicity_slots=original.PeriodCarrierSlots;
data.random_access.periodicity_ms=original.PeriodCarrierSlots/(cfg.phy.carrier.SubcarrierSpacing/15);
same=sixgr.lls6g.buildInternalConfig(data,tempname);
assert(isequaln(same.phy.prach.timing,original));
bad=data;bad.random_access.periodicity_ms=2*data.random_access.periodicity_ms;
reject(@()sixgr.lls6g.buildInternalConfig(bad,tempname), ...
    'sixgr:phy:frame:PRACHPeriodAliasConflict');
bad=sixgr.util.structSet(data,'phy.prach.period_slots',2*original.PeriodCarrierSlots);
% Internal PHY nodes are not authored scenario fields. The front-door
% schema must reject this before native alias resolution; internal cfg
% callers above separately exercise the exact period-conflict guard.
reject(@()sixgr.lls6g.buildInternalConfig(bad,tempname), ...
    'sixgr:lls6g:config:UnknownTopLevelKey');
% The map entry point must enforce the same ownership on its own.
reject(@()sixgr.rach.mapPRACHToOccasion( ...
    sixgr.util.structSet(cfg,'random_access.periodicity_slots',2*original.PeriodCarrierSlots)), ...
    'sixgr:phy:frame:PRACHPeriodAliasConflict');
fprintf('PRACH_PERIOD_ALIAS_AUTHORITY_PASS native_FDD15_30 n40_TDD_builder all_aliases_no_override receiver_trials=0\n');
ok=true;
end

function reject(action,id)
try,action();catch cause
    matched=strcmp(cause.identifier,id);
    if strcmp(cause.identifier,'sixgr:lls6g:config:PrachULSafeOccasionValidationFailed')
        % The YAML validator adds scenario context but must preserve the
        % exact native rejection, not just a flattened message substring.
        matched=numel(cause.cause)==1 && strcmp(cause.cause{1}.identifier,id);
    end
    assert(matched,'Expected %s (direct or retained YAML cause), got %s: %s',id,cause.identifier,cause.message);
    return;
end
error('test:MissingPRACHPeriodGuard','Expected %s.',id);
end
