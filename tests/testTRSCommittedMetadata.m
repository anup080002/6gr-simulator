function ok=testTRSCommittedMetadata()
T=table([true;true;false],["";"measured_tracking_failure";""], ...
    'VariableNames',{'RuntimeStateUpdated','TRSReceiverIntegrationBlocker'});
T=sixgr.truth.annotateTRSIntegrationBlocker(T,"no_trs_runtime_observation_for_serving_cell");
assert(isequal(T.TRSReceiverIntegrationBlocker, ...
    ["";"measured_tracking_failure";"no_trs_runtime_observation_for_serving_cell"]));
ok=true;
end
