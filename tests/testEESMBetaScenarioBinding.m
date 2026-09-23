function ok=testEESMBetaScenarioBinding()
% Verify signed dB beta travels through the actual 5 MHz scenario builder.
% No new EESM mode or calibration claim is enabled by this config test.
setup6GRSimToolkit('Verbose',false,'RunToolboxChecks',false);
source=sixgr.lls6g.config.loadScenarioConfig(fullfile('simulator','configs', ...
    'scenarios','lls_tdd_5mhz_rank2_shared_awgn_20db_saturated.yaml'));
base=source.toStruct();
scopes=["link_adaptation" "csi_acquisition_and_reporting"];
for scope=scopes
    if isfield(base.(scope),'eesm_beta_db')
        base.(scope)=rmfield(base.(scope),'eesm_beta_db');
    end
end
for scope=scopes
    for betaDb=[-3 0 1.5]
        data=base; data.(scope).eesm_beta_db=betaDb;
        sixgr.lls6g.config.validateScenarioConfig(data);
        cfg=sixgr.lls6g.buildInternalConfig(sixgr.lls6g.config.ScenarioConfig(data),tempname);
        for channel=["csi" "pdsch" "pusch"]
            assert(cfg.phy.(channel).eesmBeta_dB==betaDb, ...
                'Signed dB beta was lost between %s and %s.',scope,channel);
        end
    end
end
ok=true;
fprintf('EESM_BETA_SCENARIO_BINDING_PASS source_fields=2 signed_beta_cases=6\n');
end
