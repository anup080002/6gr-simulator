function ok=testSRSChannelQualificationSummary()
% Finite failed measurements must never be promoted to qualification PASS.
T=table([3.8;3.7],["FAIL";"FAIL"],[-8;-8], ...
    'VariableNames',{'NMSE_dB','Status','ChannelNMSEThreshold_dB'});
T.ChannelNMSEReferenceAvailable=true(height(T),1);
summary=sixgr.truth.summarizeSRSChannelQualification(T);
assert(summary.MeasurementAvailable && summary.MeasuredTrials==2 && ...
    summary.FailedTrials==2 && ~summary.AnyQualifiedTrial);
T.NMSE_dB=[-20;-10]; T.Status(:)="PASS";
summary=sixgr.truth.summarizeSRSChannelQualification(T);
assert(summary.AllTrialsQualified && ...
    abs(summary.NMSE_dB-10*log10(mean([0.01;0.1])))<1e-12);
% Favorable composite diagnostic values and a PASS label do not establish
% an independently authorized reference. Historical missing flags also fail.
unproven=removevars(T,'ChannelNMSEReferenceAvailable');
summary=sixgr.truth.summarizeSRSChannelQualification(unproven);
assert(~summary.MeasurementAvailable&&isnan(summary.NMSE_dB)&& ...
    summary.QualifiedTrials==0&&summary.UnreferencedNumericTrials==2);
unproven=T; unproven.ChannelNMSEReferenceAvailable(:)=false;
summary=sixgr.truth.summarizeSRSChannelQualification(unproven);
assert(~summary.AnyQualifiedTrial&&summary.ReferenceAvailableTrials==0);
mixed=T; mixed.ChannelNMSEReferenceAvailable=[true;false];
summary=sixgr.truth.summarizeSRSChannelQualification(mixed);
assert(summary.QualifiedTrials==1&&summary.MeasuredTrials==1&& ...
    summary.NMSE_dB==-20&&summary.UnreferencedNumericTrials==1);
missingThreshold=removevars(T,'ChannelNMSEThreshold_dB');
summary=sixgr.truth.summarizeSRSChannelQualification(missingThreshold);
assert(summary.MeasurementAvailable&&~summary.AnyQualifiedTrial);
missingThreshold=T; missingThreshold.ChannelNMSEThreshold_dB=[NaN;Inf];
summary=sixgr.truth.summarizeSRSChannelQualification(missingThreshold);
assert(summary.MeasurementAvailable&&~summary.AnyQualifiedTrial);
badStatus=T; badStatus.Status=repmat("PASS",2,2);
try
    sixgr.truth.summarizeSRSChannelQualification(badStatus);
    error('test:MissingSRSStatusGuard','Matrix statuses must not multiply trials.');
catch cause
    assert(string(cause.identifier)=="sixgr:truth:InvalidSRSStatusColumn");
end
noMeasurement=table(["FAIL";"CRASH"],'VariableNames',{'Status'});
summary=sixgr.truth.summarizeSRSChannelQualification(noMeasurement);
assert(summary.FailedTrials==2&&summary.QualifiedTrials==0);
invalid=T; invalid.ChannelNMSEReferenceAvailable=[1;NaN];
summary=sixgr.truth.summarizeSRSChannelQualification(invalid);
assert(summary.QualifiedTrials==1&&summary.MeasuredTrials==1);
invalid.ChannelNMSEReferenceAvailable=[1;2];
try
    sixgr.truth.summarizeSRSChannelQualification(invalid);
    error('test:MissingSRSReferenceGuard','Invalid authority must be rejected.');
catch cause
    assert(string(cause.identifier)=="sixgr:truth:InvalidSRSReferenceAuthority");
end
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
fprintf('SRS_QUALIFICATION_SUMMARY_PASS independent_reference_required=1 composite_diagnostic_qualified=0\n');
ok=true;
end
