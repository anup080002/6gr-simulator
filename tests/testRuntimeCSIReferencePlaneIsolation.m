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
