function ok=testMainSharedRARetry()
% Authored nominal-12-dB TDD scenario: actual second PRACH after UE expiry.
% This proves retry causality/power authority, not full data qualification.
folder=diagnoseMainSharedRA(58);
csv=fullfile(folder,'control','csv');
events=readtable(fullfile(csv,'ra_retry_events.csv'),'TextType','string');
assert(height(events)==1 && events.CompletedAttempt==1 && events.NextTransmissionCounter==2 && ...
    events.PowerRampingCounter==1 && events.PreambleBackoff_ms==0 && events.BackoffTicks==0 && ...
    events.EarliestRetryTicks==events.ResponseExpiryTicks && ~events.PreambleTransMaxExhausted);
files=dir(fullfile(folder,'air_interface','mat','ra_received_observations','*Msg1*.mat'));
assert(numel(files)==2,'The main stream must transmit a real retry, not only update a planned counter.');
captures=cell(1,2);
for k=1:2
    data=load(fullfile(files(k).folder,files(k).name),'capture'); captures{k}=data.capture;
end
[~,order]=sort(cellfun(@(x)x.StartSample,captures)); captures=captures(order);
first=captures{1}; second=captures{2};
a=first.ReceivedResult; b=second.ReceivedResult;
assert(a.PreambleAttemptNumber==1 && b.PreambleAttemptNumber==2);
assert(a.AssociatedSSBIndex==b.AssociatedSSBIndex && a.PreamblePowerRampingCounter==1 && b.PreamblePowerRampingCounter==2);
assert(abs(b.PreambleTargetReceivedPower_dBm-a.PreambleTargetReceivedPower_dBm-b.PowerRampingStep_dB)<1e-10);
assert(abs(b.PreambleRequestedTxPower_dBm-(b.PreambleTargetReceivedPower_dBm+b.PowerPathloss_dB))<1e-10);
assert(second.StartSample>first.EndSampleExclusive && ...
    second.StartSample*1966080000/second.SampleRateHz>=events.EarliestRetryTicks);
assert(second.Prepared.AbsoluteSlot==54 && second.StartSample==418560);
assert(strlength(string(a.PowerPathlossMeasurementId))>0 && strlength(string(b.PowerPathlossMeasurementId))>0);
assert(a.PowerPathlossMeasurementAgeSlots<=20 && b.PowerPathlossMeasurementAgeSlots<=20);
decisions=readtable(fullfile(csv,'ra_power_reference_decisions.csv'),'TextType','string');
deferred=decisions(decisions.Slot==45,:);
assert(height(deferred)==1 && ~deferred.ReferenceUsable && deferred.Status=="stale" && ...
    deferred.MinimumAvailableAgeSlots==24 && deferred.MaximumAgeSlots==20 && isnan(deferred.Pathloss_dB));
for result={a,b}
    r=result{1}; selected=decisions(decisions.MeasurementId==string(r.PowerPathlossMeasurementId) & decisions.ReferenceUsable,:);
    assert(height(selected)==1 && abs(r.PowerPathloss_dB-selected.Pathloss_dB)<1e-10 && ...
        abs(r.PowerPathloss_dB-(selected.ReferenceSignalTxEPRE_dBm-selected.MeasuredRSRP_dBm))<1e-8);
end
assert(first.ExecutionReplay.RuntimeChannelStateUsed && second.ExecutionReplay.RuntimeChannelStateUsed);
assert(~a.RuntimeSelfLoopWaveformsUsed && ~b.RuntimeSelfLoopWaveformsUsed && ~a.ProxyUsed && ~b.ProxyUsed);
monitor=readtable(fullfile(csv,'rar_monitoring_observations.csv'),'TextType','string');
assert(nnz(monitor.RunId==string(a.RunId))==16 && nnz(monitor.RunId==string(b.RunId))>0, ...
    'Both attempts need actual receive rows; an empty selection cannot prove attempt binding.');
assert(all(monitor.AttemptId(monitor.RunId==string(a.RunId))==1));
assert(all(monitor.AttemptId(monitor.RunId==string(b.RunId))==2));
assert(~isfolder(fullfile(folder,'air_interface','air_interface')));
ok=true; disp('MAIN_SHARED_RA_RETRY_PASS: actual second TDD PRACH, separate counters, fresh physical-reference identity and stale-reference deferral; SIB1/L3 power contract remains unqualified.');
end
