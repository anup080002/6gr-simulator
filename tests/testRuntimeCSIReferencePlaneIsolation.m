function ok=testRuntimeCSIReferencePlaneIsolation()
% Receiver metadata fixture, not waveform qualification or calibrated CQI.
% The reference-pilot plane must not replace an available data-plane SINR.
setup6GRSimToolkit('Verbose',false,'RunToolboxChecks',false);
scfg=sixgr.lls6g.config.loadScenarioConfig(fullfile('simulator','configs', ...
    'scenarios','lls_tdd_5mhz_rank2_shared_awgn_20db.yaml'));
cfg=sixgr.lls6g.buildInternalConfig(scfg,tempname);
failures=0; cases=0;
for direction=["DL","UL"]
    row=struct('Direction',direction,'WidebandCQI',NaN,'RankIndicator',2, ...
        'PostEqSINR_dB',21.5, ...
        'PostEqSINRSource',"post_equalization_sinr_from_equalizer_channel_estimate", ...
        'PostEqSINRValueRole',"measured_post_equalization_scheduling_input", ...
        'PostEqSINRValueStatus',"OK", ...
        'ReceiverHestSINR_dB',NaN, ...
        'ReceiverHestSINRSource',"receiver_hest_reference_signal_measurement", ...
        'ReceiverHestSINRValueRole',"estimated",'ReceiverHestSINRValueStatus',"OK");
    baseline=sixgr.truth.CoupledTruthRuntime.resolveMeasuredRuntimeCSIForRowRuntime(row,cfg,direction);
    for numericalRank=[1 2 4]
        diagnostic=row; diagnostic.RankEstimate=numericalRank;
        diagnostic.RankEstimateSource="received_channel_estimate_numerical_svd_not_RI:maximum_snapshot";
        selected=sixgr.truth.CoupledTruthRuntime.resolveMeasuredRuntimeCSIForRowRuntime(diagnostic,cfg,direction);
        assert(isequaln(selected,baseline), ...
            'Numerical rank must not override reported RI or alter CSI adaptation.');
        diagnostic=rmfield(diagnostic,'RankIndicator');
        selected=sixgr.truth.CoupledTruthRuntime.resolveMeasuredRuntimeCSIForRowRuntime(diagnostic,cfg,direction);
        assert(isnan(selected.RI),'A numerical diagnostic cannot fill a missing RI.');
    end
    for referenceSINR=[-5 6 19.7776672573192 21.5 30 NaN]
        changed=row; changed.ReceiverHestSINR_dB=referenceSINR;
        actual=sixgr.truth.CoupledTruthRuntime.resolveMeasuredRuntimeCSIForRowRuntime(changed,cfg,direction);
        passed=abs(actual.SINR_dB-row.PostEqSINR_dB)<1e-10 && ...
            actual.CQI==baseline.CQI && actual.MCSIndex==baseline.MCSIndex && ...
            string(actual.SINRSource)==row.PostEqSINRSource && ...
            string(actual.SINRValueRole)==row.PostEqSINRValueRole && ...
            string(actual.SINRValueStatus)==row.PostEqSINRValueStatus;
        fprintf('CSI_REFERENCE_PLANE_CASE direction=%s reference=%g data=%g selected=%g passed=%d\n', ...
            direction,referenceSINR,row.PostEqSINR_dB,actual.SINR_dB,passed);
        cases=cases+1; failures=failures+~passed;
    end
    % A genuine change to the receiver's data measurement still matters.
    degraded=row; degraded.PostEqSINR_dB=0;
    low=sixgr.truth.CoupledTruthRuntime.resolveMeasuredRuntimeCSIForRowRuntime(degraded,cfg,direction);
    assert(low.SINR_dB==0 && low.CQI<baseline.CQI, ...
        'Measured data degradation must remain visible to adaptation.');
    % A qualified out-of-range decision is distinct from absent evidence.
    % Poison the cached positive mapping: it must not survive CQI zero.
    outage=row; outage.PostEqSINR_dB=-30;
    outage.WidebandCQI=10; outage.CQIDerivedMCS=18;
    outage.CQIDerivedTargetCodeRate=.5; outage.CQIDerivedModulation="64QAM";
    actual=sixgr.truth.CoupledTruthRuntime.resolveMeasuredRuntimeCSIForRowRuntime(outage,cfg,direction);
    assert(actual.CQI==0 && actual.DerivedFromMeasuredSINR && ...
        isnan(actual.MCSIndex) && isnan(actual.TargetCodeRate) && ...
        strlength(string(actual.Modulation))==0, ...
        'Measured CQI zero must clear stale positive MCS/rate/modulation.');
    reported=outage; reported.PostEqSINR_dB=NaN; reported.WidebandCQI=0;
    reported.CQIValueSource="ue_report_csi"; reported.CQIValueStatus="measured";
    actual=sixgr.truth.CoupledTruthRuntime.resolveMeasuredRuntimeCSIForRowRuntime(reported,cfg,direction);
    assert(actual.CQI==0 && ~actual.DerivedFromMeasuredSINR && isnan(actual.MCSIndex));
    % A pilot observation cannot fill an unavailable data measurement. Test
    % both runtime row forms, and preserve the caller's measured quantities.
    unavailable=row; unavailable.PostEqSINR_dB=NaN;
    unavailable.ReceiverHestSINR_dB=30;
    original=unavailable;
    for asTable=[false true]
        input=unavailable;
        if asTable, input=struct2table(input,'AsArray',true); end
        actual=sixgr.truth.CoupledTruthRuntime.resolveMeasuredRuntimeCSIForRowRuntime(input,cfg,direction);
        passed=isnan(actual.SINR_dB) && ~actual.DerivedFromMeasuredSINR && ...
            isnan(actual.CQI) && strlength(string(actual.SINRSource))==0;
        fprintf('CSI_REFERENCE_ONLY_CASE direction=%s table=%d passed=%d\n',direction,asTable,passed);
        cases=cases+1; failures=failures+~passed;
    end
    assert(isequaln(original,unavailable),'Measurement selection changed its input evidence.');
end
assert(failures==0,'sixgr:test:CSIReferencePlaneMixed', ...
    '%d/%d cases mixed reference-pilot evidence into data SINR or altered its provenance.',failures,cases);
fprintf('RUNTIME_CSI_REFERENCE_PLANE_ISOLATION_PASS cases=%d\n',cases);
ok=true;
end
