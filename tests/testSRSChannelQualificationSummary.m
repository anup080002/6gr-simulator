function ok=testSRSChannelQualificationSummary()
% Finite failed measurements must never be promoted to qualification PASS.
T=table([3.8;3.7],["FAIL";"FAIL"],[-8;-8], ...
    'VariableNames',{'NMSE_dB','Status','ChannelNMSEThreshold_dB'});
summary=sixgr.truth.summarizeSRSChannelQualification(T);
assert(summary.MeasurementAvailable && summary.MeasuredTrials==2 && ...
    summary.FailedTrials==2 && ~summary.AnyQualifiedTrial);
T.NMSE_dB=[-20;-10]; T.Status(:)="PASS";
summary=sixgr.truth.summarizeSRSChannelQualification(T);
assert(summary.AllTrialsQualified && ...
    abs(summary.NMSE_dB-10*log10(mean([0.01;0.1])))<1e-12);
T.Status(1)="FAIL";
summary=sixgr.truth.summarizeSRSChannelQualification(T);
assert(summary.AnyQualifiedTrial && ~summary.AllTrialsQualified && ...
    summary.QualifiedTrials==1 && summary.UnqualifiedTrials==1);
summary=sixgr.truth.summarizeSRSChannelQualification(removevars(T,'Status'));
assert(summary.MeasurementAvailable && ~summary.AnyQualifiedTrial);
T.NMSE_dB=[NaN;3]; T.Status(:)="PASS";
summary=sixgr.truth.summarizeSRSChannelQualification(T);
assert(~summary.AnyQualifiedTrial,'Invalid or above-threshold values cannot qualify.');
T=T(1,:); T.NMSE_dB=-Inf;
summary=sixgr.truth.summarizeSRSChannelQualification(T);
assert(summary.AllTrialsQualified && summary.NMSE_dB==-Inf);
summary=sixgr.truth.summarizeSRSChannelQualification(table());
assert(~summary.MeasurementAvailable && ~summary.AnyQualifiedTrial && isnan(summary.NMSE_dB));
ok=true;
end
