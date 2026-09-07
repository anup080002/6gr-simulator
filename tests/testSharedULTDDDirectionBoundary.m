function ok=testSharedULTDDDirectionBoundary()
% Integer-sample scheduler direction contract, not a waveform result.
for suffix=["_tdd", ""]
    s=sixgr.lls6g.config.loadScenarioConfig(fullfile('simulator','configs', ...
        'scenarios','lls_causal_access_to_data_wiring'+suffix+'.yaml'));
    cfg=sixgr.lls6g.buildInternalConfig(s,tempname);
    fs=7680000;
    % Authored TDD map: DDD, 10D/2G/2U, U. Guard begins at slot 3,
    % symbol 10; next fixed DL is slot 5. Check one-sample edges too.
    g=sixgr.phy.frame.AbsoluteTime.fromAbsoluteSlotSymbol(3,10,0);
    guard=double(g.Ticks)/256;
    starts=[0 1 guard-1 guard guard+1 4*7680-100 4*7680 5*7680-1 5*7680 111260];
    fixedDL=logical([1 1 1 0 0 0 0 0 1 0]);
    for k=1:numel(starts)
        if suffix=="_tdd" && fixedDL(k)
            localReject(@()sixgr.truth.CoupledWaveformStream.assertULTransmitTime(cfg,starts(k),fs));
        else
            sixgr.truth.CoupledWaveformStream.assertULTransmitTime(cfg,starts(k),fs);
        end
    end
end
ok=true; disp('SHARED_UL_DIRECTION_BOUNDARY_PASS: exact and in-symbol TDD edges; FDD independent directions.');
end
function localReject(fn)
try, fn(); catch e
    assert(strcmp(e.identifier,'sixgr:truth:PhysicalTDDDirectionCollision'),e.message);
    return;
end
error('test:MissingDirectionRejection','A fixed DL symbol accepted actual UL energy.');
end
