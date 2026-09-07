function ok=testPRACHMultiFrameRuntimeGating()
% Authored TDD timing plus a real multi-frame table row, not fabricated occasions.
setup6GRSimToolkit('Verbose',false);
s=sixgr.lls6g.config.loadScenarioConfig(fullfile('simulator','configs','scenarios', ...
    'lls_causal_access_to_data_wiring_tdd.yaml'));
cfg=sixgr.lls6g.buildInternalConfig(s,tempname);
localCheck(cfg,false);
% FR1 unpaired configuration 0 is the long-format multi-frame fixture.
% The resolver must materialize it against the same actual carrier/TDD map.
multi=cfg;
multi.phy.prach.configurationIndex=0;
multi.phy.prach.subcarrierSpacing_kHz=1.25;
multi.phy.prach.zeroCorrelationZone=0;
engine=sixgr.phy.FrameStructureEngine(multi);
multi.phy.prach.timing=engine.PRACHTiming;
multi.phy.prach.period_slots=engine.PRACHTiming.PeriodCarrierSlots;
multi.phy.prach.validSlots1Based=engine.PRACHValidSlots1Based;
localCheck(multi,true);
ok=true;
end

function localCheck(cfg,requireMultiFrame)
engine=sixgr.phy.FrameStructureEngine(cfg);
period=double(engine.PRACHTiming.PeriodCarrierSlots);
if requireMultiFrame
    assert(period>cfg.phy.numerology.slotsPerFrame, ...
        'This regression must exercise a multi-frame PRACH period.');
end
withoutAlias=cfg; withoutAlias.phy.prach.validSlots1Based=[];
for slot=1:2*period
    expected=engine.IsPRACHSlot(slot-1);
    assert(sixgr.truth.isActivePRACHOccasion(cfg,slot)==expected);
    % Cover both alias and canonical-engine entry paths, not the same
    % one-based modulo calculation copied into the expected result.
    if ismember(slot,[1 period period+1 cfg.phy.prach.validSlots1Based])
        assert(sixgr.truth.isActivePRACHOccasion(withoutAlias,slot)==expected);
    end
end
bad=cfg; bad.phy.prach.period_slots=period+1;
try
    sixgr.truth.isActivePRACHOccasion(bad,1);
    error('TEST:MissingPRACHAuthorityGuard','Contradictory timing aliases were accepted.');
catch e
    assert(strcmp(e.identifier,'sixgr:truth:PRACHPeriodAuthorityConflict'));
end
fprintf('PRACH_MULTIFRAME_GATING_PASS: period=%g valid one-based slots=%s\n', ...
    period,mat2str(cfg.phy.prach.validSlots1Based));
end
