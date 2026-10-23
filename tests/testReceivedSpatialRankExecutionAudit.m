function ok=testReceivedSpatialRankExecutionAudit()
% Bounded actual sample-operator receipts + audit-only snapshot persistence.
% No OFDM/PHY decoder, scheduler, RF, HARQ or rank population is exercised.
setup6GRSimToolkit('Verbose',false,'RunToolboxChecks',false);
scenario=sixgr.lls6g.config.loadScenarioConfig( ...
    'simulator/configs/scenarios/lls_tdd_four_port_received_rank_transition_fixture.yaml');
cfg=sixgr.lls6g.buildInternalConfig(scenario,tempname);
carrier=sixgr.phy.grid.makeCarrier(cfg); ofdm=nrOFDMInfo(carrier); fs=double(ofdm.SampleRate);
first=sixgr.phy.frame.slotStartSample(carrier,cfg.channel.awgnBeamFailureStartSlot,fs);
last=sixgr.phy.frame.slotStartSample(carrier,cfg.channel.awgnBeamFailureEndSlotExclusive,fs);
starts=[0 first-3 first last-3 last]; counts=[7 7 7 7 7];
for direction=["DL","UL"]
    for k=1:numel(starts)
        % Separate explicitly scoped interval invocations, not a fabricated
        % continuous execution spanning the omitted intervals.
        state=sixgr.channel.ChannelFactory.createRuntimeChannelState(cfg,direction, ...
            'UEIndex',1,'ServingCell',1,'AbsoluteSampleIndex',starts(k));
        state=sixgr.channel.ChannelFactory.materializeRuntimeChannelState(state,cfg, ...
            complex(zeros(1,4)),struct('OFDM',struct('SampleRate',fs)),'NumTxAnt',4,'NumRxAnt',4);
        x=reshape(complex(sin(1:4*counts(k)),cos(1:4*counts(k))),counts(k),4);
        [y,replay,done]=sixgr.channel.ChannelFactory.applyRuntimeChannelState(state,x, ...
            'OutputSampleAlignment','continuous_raw_samples','InputSampleDomain','materialized_channel_ports');
        assert(isequal(size(y),size(x))&&done.CurrentSampleIndex==starts(k)+counts(k));
        link=struct('ID',"declared_operator_interval",'TX',"declared_tx",'RX',"declared_rx",'Replay',replay);
        trace={struct('StartSample',starts(k),'EndSampleExclusive',done.CurrentSampleIndex, ...
            'Execution',struct('SampleRateHz',fs,'Links',link))};
        rows=ReceivedSpatialRankAudit.executedIntervals(trace,cfg,fs);
        assert(height(rows)==1&&rows.StartSample==starts(k)&& ...
            rows.AppliedSegmentMatrixSHA256==string(replay.AppliedAWGNSpatialMatrixSHA256));
    end
end
bad=trace; bad{1}.Execution.Links.Replay.RuntimeChannelTimingTruthSource="executed_fixed_matrix_operator_zero_delay";
reject(@()ReceivedSpatialRankAudit.executedIntervals(bad,cfg,fs));
bad=trace; bad{1}.Execution.Links.Replay.RuntimeChannelStartSample=bad{1}.StartSample+1;
reject(@()ReceivedSpatialRankAudit.executedIntervals(bad,cfg,fs));
bad=trace; bad{1}.Execution.Links.Replay.BeamFailureRecoveryActiveSampleCount=1;
reject(@()ReceivedSpatialRankAudit.executedIntervals(bad,cfg,fs));
bad=trace; bad{1}.Execution.Links.Replay.BeamFailureRecoverySegmentCount=2;
reject(@()ReceivedSpatialRankAudit.executedIntervals(bad,cfg,fs));
bad=trace; bad{1}.Execution.Links.Replay.AppliedAWGNSpatialMatrixSHA256=repmat('0',1,64);
reject(@()ReceivedSpatialRankAudit.executedIntervals(bad,cfg,fs));
badRate=trace; badRate{1}.Execution.SampleRateHz=fs*2;
reject(@()ReceivedSpatialRankAudit.executedIntervals(badRate,cfg,fs));
badCfg=cfg; badCfg.channel.awgnBeamFailureRecoveryEnabled=false;
reject(@()ReceivedSpatialRankAudit.executedIntervals(trace,badCfg,fs));

% Persistence must retain the original BAD receipt for diagnosis BEFORE
% validation rejects it. The sentinel is explicitly not a data application.
sentinel=struct('Scope',"declared_persistence_sentinel_not_received_data",'Value',pi);
declared=struct('SharedWaveformStream',struct('SampleRateHz',fs, ...
    'Events',struct('NextSampleIndex',done.CurrentSampleIndex,'ExecutionTrace',{bad})), ...
    'TestRankTransitionApplications',{{sentinel}},'TestPublishedDLTrials',table(), ...
    'TestPublishedULTrials',table(),'SharedGNBCSIReportTable',table(), ...
    'ReferenceSignalMeasurementTable',table(),'SchedulerAdmissionTable',table(), ...
    'PendingFeedbackTable',table(),'TestRankTransitionTermination',"declared_audit_failure", ...
    'TestRankTransitionInitialTAGExpiry',NaN,'TestRankTransitionAttemptOrdinal',0);
folder=tempname; mkdir(folder);
[path,missingAudit]=ReceivedSpatialRankAudit.saveOriginal(declared,cfg,"UL",folder,false);
reject(@()ReceivedSpatialRankAudit.executedIntervals(bad,cfg,fs));
saved=load(path,'original');
assert(isequaln(saved.original.ExecutionTrace,bad)&& ...
    isequaln(saved.original.Applications,{sentinel})&& ...
    isequaln(saved.original.FixtureConfig,cfg)&& ...
    saved.original.Status=="unverified_snapshot_before_wrapper_assertions"&& ...
    ~saved.original.WrapperIntegrityVerified&&~saved.original.HarnessReturnedOK&& ...
    ~saved.original.FullScenarioQualified&&~saved.original.StatisticalQualification);
assert(isequaln(saved.original.ULHARQAudit,missingAudit) && ...
    ~missingAudit.HARQTimelinePresent && isnan(missingAudit.HARQTimelineSourceRowCount) && ...
    ~missingAudit.SharedPUSCHHARQFeedbackReceiptsPresent && ~missingAudit.ULHARQStatsPresent && ...
    ~missingAudit.TestSRSContinuationInitialHARQPresent && ...
    ~missingAudit.TestRankTransitionAttemptHARQPresent && isempty(fieldnames(missingAudit.ULHARQStats)));

% Declared metadata persistence only: no HARQ allocation, receiver outcome
% or actual feedback is produced. Include two UEs and preserve cellstr types.
declared.HARQTimelineTable=table({'DL';'UL';'UL'},[1;1;2],[3;4;5], ...
    [0;1;0],[0;2;3],{"declared_dl";"declared_ul_A";"declared_ul_B"}, ...
    [NaN;101;NaN],logical([0;1;0]), ...
    'VariableNames',{'Direction','RNTI','HarqID','NDI','RV','PHYGrantContextId', ...
    'DataDecodeAvailableAtSample','CombinedDecodeOK'});
declared.HARQTimelineTable.Properties.UserData=struct('Scope',"declared_retention_fixture_no_feedback_execution");
receipt=struct('ObservationID',"declared_receiver_A",'GrantContextID',"declared_ul_A", ...
    'ReceiverContextDigest',"declared_context",'HARQMappingDigest',"declared_mapping", ...
    'AvailableAtSample',uint64(101),'CSIDecisionDigest',"declared_CSI",'Digest',"declared_digest");
secondReceipt=receipt; secondReceipt.ObservationID="declared_receiver_B";
secondReceipt.GrantContextID="declared_ul_B"; secondReceipt.AvailableAtSample=uint64(102);
declared.SharedPUSCHHARQFeedbackReceipts={receipt;secondReceipt};
harq=sixgr.l2.mac.HARQEntityUL(cfg); % Only construct an owner; no process allocation/execution.
harq.Stats.Tx=uint64(7); harq.Stats.Ack=uint64(5); harq.Stats.Nack=uint64(2);
declared.ULHarq=harq;
declared.TestSRSContinuationInitialHARQ=harq.Stats;
declared.TestRankTransitionAttemptHARQ=harq.Stats;
declared.TestRankTransitionAttemptHARQ.Tx=uint64(6);
originalTimeline=declared.HARQTimelineTable;
originalReceipts=declared.SharedPUSCHHARQFeedbackReceipts;
originalStats=harq.Stats;
originalRNG=rng;
folder2=tempname; mkdir(folder2);
[path2,audit]=ReceivedSpatialRankAudit.saveOriginal(declared,cfg,"UL",folder2,false);
assert(isequaln(rng,originalRNG));
saved2=load(path2,'original');
assert(isequaln(saved2.original.ULHARQAudit,audit) && ...
    audit.HARQTimelinePresent && audit.HARQTimelineSourceRowCount==3 && ...
    isequal(audit.HARQTimelineSourceRows,[2;3]) && ...
    isequaln(audit.HARQTimelineTable,originalTimeline([2;3],:)) && ...
    iscell(audit.HARQTimelineTable.Direction) && ...
    audit.SharedPUSCHHARQFeedbackReceiptsPresent && ...
    isequaln(audit.SharedPUSCHHARQFeedbackReceipts,originalReceipts) && ...
    audit.ULHARQStatsPresent && isequaln(audit.ULHARQStats,originalStats) && ...
    audit.TestSRSContinuationInitialHARQPresent && ...
    isequaln(audit.TestSRSContinuationInitialHARQ,declared.TestSRSContinuationInitialHARQ) && ...
    audit.TestRankTransitionAttemptHARQPresent && ...
    audit.TestRankTransitionAttemptHARQDirection=="UL" && ...
    isequaln(audit.TestRankTransitionAttemptHARQ,declared.TestRankTransitionAttemptHARQ));
assert(isstruct(audit.ULHARQStats) && ~isfield(audit,'ULHarq') && ...
    ~isfield(audit,'UEProcs') && ~saved2.original.WrapperIntegrityVerified && ...
    ~saved2.original.HarnessReturnedOK);
% Later owner/value mutations must not rewrite a saved original snapshot.
harq.Stats.Ack=uint64(6);
declared.HARQTimelineTable.RV(2)=0;
declared.SharedPUSCHHARQFeedbackReceipts{1}.AvailableAtSample=uint64(999);
assert(isequaln(audit.ULHARQStats,originalStats) && ...
    isequaln(audit.HARQTimelineTable,originalTimeline([2;3],:)) && ...
    isequaln(audit.SharedPUSCHHARQFeedbackReceipts,originalReceipts));
again=load(path2,'original'); assert(isequaln(again.original,saved2.original));
dlAudit=ReceivedSpatialRankAudit.ulHARQSnapshot(declared,"DL");
assert(dlAudit.TestRankTransitionAttemptHARQDirection=="DL" && ...
    isequaln(dlAudit.TestRankTransitionAttemptHARQ,declared.TestRankTransitionAttemptHARQ));
stringState=declared; stringState.HARQTimelineTable.Direction=string(originalTimeline.Direction);
stringAudit=ReceivedSpatialRankAudit.ulHARQSnapshot(stringState,"UL");
assert(isstring(stringAudit.HARQTimelineTable.Direction) && ...
    isequaln(stringAudit.HARQTimelineTable,stringState.HARQTimelineTable([2;3],:)));
emptyState=struct('HARQTimelineTable',originalTimeline([],:), ...
    'SharedPUSCHHARQFeedbackReceipts',{{}},'ULHarq',struct('Stats',struct()));
emptyAudit=ReceivedSpatialRankAudit.ulHARQSnapshot(emptyState,"UL");
assert(emptyAudit.HARQTimelinePresent && emptyAudit.HARQTimelineSourceRowCount==0 && ...
    isequaln(emptyAudit.HARQTimelineTable,originalTimeline([],:)) && ...
    emptyAudit.SharedPUSCHHARQFeedbackReceiptsPresent && emptyAudit.ULHARQStatsPresent);
id='test:RankTransitionHARQAudit';
badState=declared; badState.HARQTimelineTable.Direction{2}='unknown';
reject(@()ReceivedSpatialRankAudit.ulHARQSnapshot(badState,"UL"),id);
badState=declared; badState.HARQTimelineTable.Direction=[];
reject(@()ReceivedSpatialRankAudit.ulHARQSnapshot(badState,"UL"),id);
badState=declared; badState.HARQTimelineTable.Direction=repmat("UL",3,2);
reject(@()ReceivedSpatialRankAudit.ulHARQSnapshot(badState,"UL"),id);
badState=declared; badState.HARQTimelineTable.Properties.UserData=harq;
reject(@()ReceivedSpatialRankAudit.ulHARQSnapshot(badState,"UL"),id);
badState=declared; badState.ULHarq=struct('Stats',struct('SoftBuffer',[1 2]));
reject(@()ReceivedSpatialRankAudit.ulHARQSnapshot(badState,"UL"),id);
badState=declared; badState.SharedPUSCHHARQFeedbackReceipts{1}.LiveHandle=harq;
reject(@()ReceivedSpatialRankAudit.ulHARQSnapshot(badState,"UL"),id);
badState=declared; badState.TestRankTransitionAttemptHARQ=struct('Callback',@sin);
reject(@()ReceivedSpatialRankAudit.ulHARQSnapshot(badState,"UL"),id);
assert(isequaln(rng,originalRNG));
fprintf('RECEIVED_SPATIAL_RANK_EXECUTION_AUDIT_PASS operator_intervals=10 preserved_failed_audit=1 UL_HARQ_value_retention=1 declared_metadata_only=1 decoded_PHY=0\n');
ok=true;
end

function reject(fn,expected)
if nargin<2, expected='test:RankTransitionExecutionAudit'; end
try, fn(); catch cause
    assert(strcmp(cause.identifier,expected),'Unexpected error %s.',cause.identifier);
    return;
end
error('test:RankTransitionAuditExpectedError','Expected a strict original-execution audit rejection.');
end
