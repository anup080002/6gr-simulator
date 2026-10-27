function ok=testCanonicalDataSINRStatus()
% Declared alias fixture; no PHY execution or accuracy claim.
T=table(14,14,"original_receiver","original_receiver","estimated","estimated", ...
    "OK_DECISION_RESIDUAL_BOUNDED","pdsch_post_equalization_data_re", ...
    "not_emitted_by_active_dl_pdsch_trials_runtime","", ...
    'VariableNames',{'MeasuredSINR_dB','MeasuredTrialSINR_dB','SINRSource', ...
    'MeasuredTrialSINRSource','SINRValueRole','MeasuredTrialSINRValueRole', ...
    'MeasuredTrialSINRValueStatus','SINRMeasurementDomain','SINRValueStatus','SINRValueDefinition'});
before=rng; fixed=sixgr.truth.bindCanonicalDataSINRStatus(T);
assert(isequal(before,rng)&&fixed.SINRValueStatus==T.MeasuredTrialSINRValueStatus);
assert(contains(fixed.SINRValueDefinition,"accuracy not qualified"));
assert(isequal(fixed,sixgr.truth.bindCanonicalDataSINRStatus(fixed)));
for field=["MeasuredSINR_dB","SINRSource","SINRValueRole","SINRMeasurementDomain","SINRValueStatus"]
    bad=T;
    if field=="MeasuredSINR_dB", bad.(field)=15;
    elseif field=="SINRMeasurementDomain", bad.(field)="";
    else, bad.(field)="contradictory_original"; end
    rejected=false;
    try, sixgr.truth.bindCanonicalDataSINRStatus(bad);
    catch cause, rejected=strcmp(cause.identifier,'sixgr:truth:DataSINRAliasMismatch'); end
    assert(rejected,'test:MissingSINRAliasGuard','Reject contradictory original aliases.');
end
unavailable=T; unavailable.MeasuredTrialSINRValueStatus="unavailable";
assert(isequal(unavailable,sixgr.truth.bindCanonicalDataSINRStatus(unavailable)));
unavailable=T; unavailable.MeasuredTrialSINR_dB=NaN; unavailable.MeasuredSINR_dB=NaN;
assert(isequaln(unavailable,sixgr.truth.bindCanonicalDataSINRStatus(unavailable)));
assert(isempty(sixgr.truth.bindCanonicalDataSINRStatus(table())));
ok=true; fprintf('testCanonicalDataSINRStatus PASS\n');
end
