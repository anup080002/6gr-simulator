function ok=testLiveSINRProgressStatus()
% Deterministic reporting fixtures, not channel measurements or RF tests.
setup6GRSimToolkit('Verbose',false);
metrics=["ReceiverHestSINR_dB","PostEqSINR_dB","MeasuredTrialSINR_dB"];
for metric=metrics
    statusName=regexprep(metric,'_dB$','ValueStatus');
    T=table([-100;10;20;100;NaN],'VariableNames',metric);
    T.(statusName)=["REJECTED";"OK";"OK_PILOT_ESTIMATE";"LOWER_BOUND_NOISE_FLOOR";"unavailable"];
    before=T;
    [text,e]=sixgr.truth.formatLiveSINRStatistic(T,metric,metric);
    assert(e.AcceptedCount==2 && e.ExcludedCount==3 && e.NoiseFloorBoundCount==1);
    assert(e.Median_dB==15 && contains(text,'15.000 dB') && ~contains(text,'100.000 dB'));
    assert(isequaln(T,before),'Progress formatting must not alter raw measurements.');
    quarantined=T(1:3,:);
    quarantined.(statusName)=["OK_PROXY";"OK_FALLBACK";"OK_LOWER_BOUND_NOISE_FLOOR"];
    retained=quarantined;
    [~,e]=sixgr.truth.formatLiveSINRStatistic(quarantined,metric,metric);
    assert(e.AcceptedCount==0 && isnan(e.Median_dB) && isequaln(quarantined,retained));
    bounded=T(4,:);
    [text,e]=sixgr.truth.formatLiveSINRStatistic(bounded,metric,metric);
    assert(e.AcceptedCount==0 && isnan(e.Median_dB) && contains(text,'unavailable'));
    assert(contains(text,'noise-floor bounds=1') && ~contains(text,'100.000'));
    absent=removevars(T,statusName);
    [~,e]=sixgr.truth.formatLiveSINRStatistic(absent,metric,metric);
    assert(e.AcceptedCount==0 && e.MissingStatusCount==height(T));
    rejected=T;
    switch metric
        case "ReceiverHestSINR_dB", rejected.ReceiverHestSINRApplicable=false(height(T),1);
        case "PostEqSINR_dB", rejected.PostEqSINRAvailable=false(height(T),1);
        case "MeasuredTrialSINR_dB", rejected.MeasurementUsable=false(height(T),1);
    end
    [~,e]=sixgr.truth.formatLiveSINRStatistic(rejected,metric,metric);
    assert(e.AcceptedCount==0 && isnan(e.Median_dB));
    T.(statusName)(2:3)=["";missing];
    [~,e]=sixgr.truth.formatLiveSINRStatistic(T,metric,metric);
    assert(e.AcceptedCount==0 && e.MissingStatusCount==2);
end
[text,e]=sixgr.truth.formatLiveSINRStatistic(table(),'PostEqSINR_dB','PostEqSINR_dB');
assert(text=="PostEqSINR_dB pending" && e.Rows==0 && isnan(e.Median_dB));
ok=true; fprintf('LIVE_SINR_PROGRESS_STATUS_PASS: accepted status and receiver flags required; bounds counted separately.\n');
end
