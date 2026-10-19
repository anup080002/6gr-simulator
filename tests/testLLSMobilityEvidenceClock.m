function ok=testLLSMobilityEvidenceClock()
cfg=sixgr.config.defaultConfig();
ue=struct('K',1,'pos_m',[50 50 1.5],'speed_kmh',3,'heading_deg',0,'indoor',false);
s=struct('UE',ue,'CfgMobility',cfg,'SlotDuration_s',.0005,'MobilityEnabled',true, ...
    'MobilityModel',sixgr.scenario.mobility.MobilityRMaMixedSpeed([1000 1000],false));
for slot=1:50
    s=sixgr.truth.advanceMobilityClock(s,slot); position=s.UE.pos_m;
    % Model consumers may inspect DL, UL, control, or future grant calendars.
    for consumer=1:3
        s.CurrentCanonicalSlot=slot+consumer;
        s=sixgr.truth.advanceMobilityClock(s,slot);
        assert(isequal(s.UE.pos_m,position));
    end
    assert(abs(position(1)-(50+3/3.6*(slot-1)*.0005))<1e-10);
end
assert(s.MobilityStateVersion==49);
try, sixgr.truth.advanceMobilityClock(s,49); error('Expected clock rejection');
catch ME, assert(strcmp(ME.identifier,'sixgr:truth:MobilityClockRewind')); end
old=table(41,1,50.01,1,"old",'VariableNames',{'Slot','UEID','X_m','MobilityStateVersion','PositionSource'});
new=old; new.X_m=50.02; new.MobilityStateVersion=2; new.PositionSource="new";
new.PostEqSINR_dB=33;
out=sixgr.truth.preserveServingGeometry(old,new);
assert(out.X_m==old.X_m && out.MobilityStateVersion==1 && out.PostEqSINR_dB==33);
ok=true;
end
