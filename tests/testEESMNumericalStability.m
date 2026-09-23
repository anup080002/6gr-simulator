function ok = testEESMNumericalStability()
% Numerical fixtures only: this does not qualify any beta/BLER calibration.
setup6GRSimToolkit('Verbose',false,'RunToolboxChecks',false);
% Agree with the original equation where it is numerically representable.
for gamma={[0 0],[0 .1 1],[.001 .002 .003],[1 2 3],[10 20 30]}
    values=gamma{1};
    expected=-2*log(mean(exp(-values/2)));
    actual=sixgr.util.eesmLinear(values,2);
    assert(abs(actual-expected)<1e-12);
end
assert(sixgr.util.eesmLinear([1e-200 1e-200],1)==1e-200);
points=[-30 -20 -10 0 10 20 30 40];
for betaDb=[-3 0 1.5 10]
    for snrDb=points
        actual=sixgr.phy.rsla.EESMMapper.map(repmat(snrDb,25,1),betaDb,"declared_math_fixture");
        assert(isfinite(actual.EffectiveSINRDb) && abs(actual.EffectiveSINRDb-snrDb)<1e-9, ...
            'test:EESMFlatChannelIdentity', ...
            'Flat %g dB must remain %g dB for beta=%g dB; got %g.', ...
            snrDb,snrDb,betaDb,actual.EffectiveSINRDb);
    end
end

% Compare the public DL/UL CQI path with a stable independent two-point
% closed form, not a whole-band average or a configured SNR substitution.
cfg=struct();
cfg.phy.csi=struct('sinrToCQIMode','effective_sinr_bler_lut', ...
    'effectiveSINRMethod','eesm','allowUncalibratedBLERLUT',true,'cqiTable','table1');
for direction=["DL" "UL"]
    if direction=="DL", channel='pdsch'; else, channel='pusch'; end
    for betaDb=[-3 0 1.5 10]
        cfg.phy.(channel).eesmBeta_dB=betaDb;
        for pair={[0 3],[30 40],[40 40]}
            values=pair{1}; gamma=10.^(values/10); beta=10^(betaDb/10);
            expected=10*log10(min(gamma)+beta*(log(2)-log1p(exp(-abs(diff(gamma))/beta))));
            input=struct('WidebandSINR_dB',-99,'PerRBSINR_dB',values);
            actual=sixgr.link.resolveWidebandCQI(input,cfg,direction);
            assert(abs(actual.EffectiveSINRBeta_dB-betaDb)<1e-12, ...
                'test:EESMBetaUnits','Finite beta in dB must not be rejected for being <=0.');
            assert(isfinite(actual.EffectiveSINR_dB) && abs(actual.EffectiveSINR_dB-expected)<1e-9, ...
                'test:EESMHighSNRSubstitution','EESM must not retain the poisoned wideband value on underflow.');
        end
    end
    cfg.phy.(channel).mcsIndex=4;
    cfg.phy.(channel).eesmBetaMCSIndex=[3 4 5];
    for betaDb=[-3 0]
        cfg.phy.(channel).eesmBetaByMCS_dB=[1 betaDb 2];
        actual=sixgr.link.resolveWidebandCQI( ...
            struct('WidebandSINR_dB',-99,'PerRBSINR_dB',[40 40]),cfg,direction);
        assert(actual.EffectiveSINRBeta_dB==betaDb && abs(actual.EffectiveSINR_dB-40)<1e-9);
        assert(string(actual.EffectiveSINRBetaValueRole)=="configured_mcs_index_beta_catalog");
    end
end
ok=true;
fprintf('EESM_NUMERICAL_STABILITY_PASS flat_cases=32 public_DL_UL_cases=24 catalog_cases=4\n');
end
