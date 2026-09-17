function job=bindSharedPUSCHReceiverContext(state,job)
% Bind the gNB UCI schema before demapping; no UE payload/length authority.
assert(isstruct(job) && isscalar(job) && string(job.Direction)=="UL" && ...
    isequal(job.PrepareOnly,false), ...
    'sixgr:truth:InvalidSharedPUSCHReceiveStage', ...
    'Bind independent UCI only to a shared UL receive-completion job.');
observation=job.ReceivedContext.Observation;
binding=sixgr.truth.puschUCIObservationBinding(job.GrantSnapshot,observation);
owner=state.SharedWaveformStream;
assert(observation.SampleRateHz==owner.SampleRateHz && ...
    observation.EndSampleExclusive<=owner.Events.NextSampleIndex, ...
    'sixgr:truth:PUSCHHARQObservationClockMismatch', ...
    'The gNB receive schema must belong to a completed shared-clock capture.');
[obligation,report]=sixgr.truth.buildSharedPUSCHCSIReceiveObligation(job.Cfg,job.GrantSnapshot);
context=sixgr.truth.buildSharedPUSCHUCIReceiveContext( ...
    state,job.Cfg,job.GrantSnapshot,binding.ObservationID,obligation,report);
job.ReceivedContext.UCIReceiveContext=context;
job.ReceivedContext.UCIReportConfiguration=report;
[attempt,prior]=sixgr.truth.prepareSharedULHARQReception(state,job.Cfg,job.GrantSnapshot,observation);
% The receiver ledger, not a TX-preparation job's cached prior, owns soft state.
job.PreviousCombinedLLR=prior;
job.ReceivedContext.ULHARQReceiverKey=attempt.Attempt.ReceiverKey;
job.ReceivedContext.ULHARQReceiverAttempt=attempt;
end
