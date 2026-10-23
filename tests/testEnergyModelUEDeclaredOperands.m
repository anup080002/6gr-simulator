function ok=testEnergyModelUEDeclaredOperands()
% Independent engineering-model arithmetic; not measured device watts.
cfg.energy.ue=struct('idleW',0.7,'rxW',1.2,'sleepW',0.03,'txWPerWattRF',2.7);
m=sixgr.rf.EnergyModelUE(cfg);
assert(m.power('idle',0).totalW==0.7);
assert(m.power('rx',0).totalW==1.2);
assert(m.power('sleep',0).totalW==0.03);
for rf=[0 0.2 3]
    p=m.power('tx',rf);
    assert(abs(p.totalW-(0.7+2.7*rf))<1e-13 && p.txPowerW==rf);
end
for state=["idle","rx","sleep"]
    reject(@()m.power(char(state),0.2));
end
for rf=[-1 NaN Inf complex(1,1)]
    reject(@()m.power('tx',rf));
end
for field=string(fieldnames(cfg.energy.ue)).'
    for value=[-1 NaN Inf complex(1,1)]
        invalid=cfg; invalid.energy.ue.(field)=value;
        reject(@()sixgr.rf.EnergyModelUE(invalid));
    end
end
reject(@()m.power('not_a_state',0));
invalid=cfg; invalid.energy.ue.txWPerWattRF=0;
reject(@()sixgr.rf.EnergyModelUE(invalid));
huge=cfg; huge.energy.ue.txWPerWattRF=realmax;
overflow=sixgr.rf.EnergyModelUE(huge);
reject(@()overflow.power('tx',2));
ok=true;
end

function reject(call)
caught=false;
try
    call();
catch
    caught=true;
end
assert(caught,'test:UEEnergyInvalidOperandAccepted', ...
    'Invalid declared UE power operands must fail, not be clamped or ignored.');
end
