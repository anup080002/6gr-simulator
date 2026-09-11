function ok=testRuntimeCSIScoringIsolation
% Prescribed receiver/score values test causality; these are not PHY rows.
setup6GRSimToolkit('Verbose',false);
for mode=["TDD","FDD"]
    file='lls_causal_access_to_data_wiring_tdd.yaml';
    if mode=="FDD", file='lls_causal_access_to_data_wiring.yaml'; end
    s=sixgr.lls6g.config.loadScenarioConfig(fullfile('simulator','configs','scenarios',file));
    cfg=sixgr.lls6g.buildInternalConfig(s,tempname);
    for direction=["DL","UL"]
        row=struct2table(struct('Direction',direction,'WidebandCQI',1, ...
            'MeasuredTrialSINR_dB',18.5,'MeasuredTrialSINRSource', ...
            "post_equalization_sinr_from_equalizer_channel_estimate", ...
            'MeasuredTrialSINRValueRole',"measured_post_equalization_scheduling_input", ...
            'MeasuredTrialSINRValueStatus',"OK",'RankIndicator',1));
        baseline=sixgr.truth.CoupledTruthRuntime.resolveMeasuredRuntimeCSIForRowRuntime(row,cfg,direction);
        for field=["NMSE_dB","TrueChannelNMSE_dB","PilotResidualNMSE_dB", ...
                "ChannelEstimatePilotResidualNMSE_dB","ChannelAgingLoss_dB","MismatchSensitivity_dB"]
            for value=[NaN -Inf -80 -5 40 Inf]
                changed=row; changed.(field)=value;
                actual=sixgr.truth.CoupledTruthRuntime.resolveMeasuredRuntimeCSIForRowRuntime(changed,cfg,direction);
                assert(isequaln(actual,baseline),'Scoring/diagnostic %s changed runtime CSI.',field);
            end
        end
        low=row; low.MeasuredTrialSINR_dB=0;
        degraded=sixgr.truth.CoupledTruthRuntime.resolveMeasuredRuntimeCSIForRowRuntime(low,cfg,direction);
        assert(degraded.SINR_dB==0 && degraded.CQI<baseline.CQI && ...
            degraded.MCSIndex<baseline.MCSIndex,'Actual received degradation must still reduce AMC.');
        absent=row; absent.MeasuredTrialSINR_dB=NaN; absent.WidebandCQI=NaN;
        absent.NMSE_dB=-80; absent.TrueChannelNMSE_dB=-80;
        missing=sixgr.truth.CoupledTruthRuntime.resolveMeasuredRuntimeCSIForRowRuntime(absent,cfg,direction);
        assert(isnan(missing.SINR_dB) && ~missing.DerivedFromMeasuredSINR, ...
            'Good scoring must not manufacture a missing received SINR.');
    end
end
fprintf('RUNTIME_CSI_SCORING_ISOLATION_PASS: TDD/FDD DL/UL, score invariance and actual AMC response.\n');
ok=true;
end
