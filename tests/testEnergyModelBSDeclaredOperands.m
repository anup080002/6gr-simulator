function ok=testEnergyModelBSDeclaredOperands()
% Engineering-model arithmetic, not measured hardware or NR power limits.
% Compare directly with a separately written equation, including an allowed
% low efficiency which previously triggered a silent implementation clamp.
cfg.energy.bs=struct('staticW',100,'perTRxPW',4,'sleepW',10, ...
    'efficiencyPA',0.0005,'idleRFChainPowerFraction',0.3);
model=sixgr.rf.EnergyModelBS(cfg);
assert(model.EfficiencyPA==0.0005,'test:EnergyPAWasClamped', ...
    'A valid declared PA efficiency must not be changed by the model.');
for fraction=[0 0.3 1]
    cfg.energy.bs.idleRFChainPowerFraction=fraction;
    model=sixgr.rf.EnergyModelBS(cfg);
    for load=[0 0.25 1]
        p=model.power('active',64,load,0.2);
        expectedChains=4*64*(fraction+(1-fraction)*load);
        expectedPA=0.2/0.0005;
        assert(abs(p.trxW-expectedChains)<1e-12 && ...
            abs(p.paW-expectedPA)<1e-12 && ...
            abs(p.totalW-(100+expectedChains+expectedPA))<1e-12, ...
            'test:EnergyEquation','The model must use the declared operands exactly.');
        assert(p.idleRFChainPowerFraction==fraction);
    end
end
% Explicit sleeping state does not inherit the active-chain/PA terms.
p=model.power('sleep',64,0,0);
assert(p.totalW==10 && p.trxW==0 && p.paW==0);
for efficiency=[0 -1 1.01 Inf NaN]
    bad=cfg; bad.energy.bs.efficiencyPA=efficiency;
    reject(@()sixgr.rf.EnergyModelBS(bad));
end
for fraction=[-0.1 1.1 Inf NaN]
    bad=cfg; bad.energy.bs.idleRFChainPowerFraction=fraction;
    reject(@()sixgr.rf.EnergyModelBS(bad));
end
for field=["staticW","perTRxPW","sleepW"]
    bad=cfg; bad.energy.bs.(field)=-1;
    reject(@()sixgr.rf.EnergyModelBS(bad));
end
for load=[-0.01 1.01 Inf NaN]
    reject(@()model.power('active',4,load,1));
end
reject(@()model.power('active',1.5,0.5,1));
reject(@()model.power('active',4,0.5,-1));
reject(@()model.power('misspelled_state',4,0.5,1));
reject(@()model.power('sleep',4,0,1));
reject(@()model.power('active',0,0,1));
ok=true;
end

function reject(call)
caught=false;
try
    call();
catch
    caught=true;
end
assert(caught,'test:EnergyAcceptedInvalidOperand', ...
    'Invalid model operands must fail, not be silently clamped.');
end
