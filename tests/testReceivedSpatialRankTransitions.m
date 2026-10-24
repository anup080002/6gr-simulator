function [ok,evidence]=testReceivedSpatialRankTransitions(direction,preflightOnly)
% Actual shared four-port channel stimulus -> independently received CSI or
% SRS -> normal acceptance/scheduling -> received DCI -> completed data.
% Each direction uses a fresh owner. The finite initial connected/TAG input
% is declared, not received RA. No rank, PMI, grant, ACK or noise threshold
% is changed to compel a population. Boundary integrity and observed rank
% coverage are separate outputs; missing rank populations remain OPEN.
if nargin<1, direction="DL"; end
if nargin<2, preflightOnly=false; end
direction=string(direction);
assert(isscalar(direction) && any(direction==["DL","UL"]));
assert(islogical(preflightOnly) && isscalar(preflightOnly));
setup6GRSimToolkit('Verbose',false);
root=fileparts(fileparts(mfilename('fullpath')));
fixture=fullfile(root,'simulator','configs','scenarios', ...
    'lls_tdd_four_port_received_rank_transition_fixture.yaml');
s=sixgr.lls6g.config.loadScenarioConfig(fixture);
cfg=sixgr.lls6g.buildInternalConfig(s,tempname);
localPreflight(cfg);
evidence=struct('Scope',"declared_connected_four_port_deterministic_channel_component", ...
    'Direction',direction,'WaveformExecuted',false,'FullScenarioQualified',false, ...
    'RandomAccessQualified',false,'StatisticalQualification',false, ...
    'RankTransitionCoverageComplete',false,'ObservedApplications',table());
if preflightOnly, ok=true; return; end
assert(nargin('testSharedPUSCHChannelArtifacts')>=20, ...
    'test:RankTransitionContinuationNotIntegrated', ...
    'The optional sustained physical continuation is not installed.');
folder=fullfile(root,'logs','received_spatial_rank_transitions');
if ~isfolder(folder), mkdir(folder); end
outputRoot=tempname(folder);
[ok,state]=testSharedPUSCHChannelArtifacts('TDD',false,false,true,true,true,false, ...
    outputRoot,fixture,false,true,false,false,true,4,false,false, ...
    direction=="DL",direction=="UL",true);
% Persist the ORIGINAL completed metadata before any wrapper audit can
% throw. This is audit-only evidence, not a successful wrapper verdict.
[originalAuditPath,evidence.ULHARQAudit]=ReceivedSpatialRankAudit.saveOriginal( ...
    state,cfg,direction,outputRoot,ok);
assert(ok && state.TestRankTransitions && state.TestCanonicalCompletionDrainVerified);
apps=state.TestRankTransitionApplications;
assert(iscell(apps));
rows=table();
for k=1:numel(apps)
    a=apps{k};
    assert(a.WaveformApplicationVerified && ~a.FullScenarioQualified);
    if direction=="DL"
        g=a.Grant; source=a.OriginalProvenance;
        sourceID=string(source.ReportIdentity); sourceSlot0=double(source.SourceSlot)-1;
        available=double(source.AvailableAtSample);
        decision=double(g.CSIReportDecisionContext.AtSample);
        reportedRank=double(source.RI);
        assert(isequaln(g.CSIReportProvenance,source));
    else
        g=a.ScheduledGrant; source=a.AcceptedSRS;
        sourceID=string(source.MeasurementId); sourceSlot0=double(source.ProducerSlot)-1;
        available=double(source.ResultAvailableAtSample);
        decision=double(g.AcceptedSRSDecisionContext.KnownAtSample);
        reportedRank=double(source.RI);
        assert(isequaln(g.AcceptedSRSSpatialDecision,source) && ...
            a.UEPrecodingAuthority.AuthoritativeDCIDecisionUsed && ...
            ~a.UEPrecodingAuthority.AuthoritativeSRSDecisionUsed);
    end
    control=a.ReceivedControl; receipt=a.TransmissionReceipt;
    assert(available<=decision && decision<control.AvailableAtSample && ...
        control.Allowed && control.ReceivedAssignment.NumLayers==g.NumLayers && ...
        g.NumLayers==reportedRank && g.PHYGrant.PrecodingState.NumLayers==g.NumLayers && ...
        control.AvailableAtSample<=a.ReceiverEndSampleExclusive && ...
        receipt.Identity.EndSampleExclusive<=a.CompletedAtSample && ...
        a.ReceiverEndSampleExclusive<=a.CompletedAtSample);
    phase="before";
    if sourceSlot0>=cfg.channel.awgnBeamFailureEndSlotExclusive
        phase="after";
    elseif sourceSlot0>=cfg.channel.awgnBeamFailureStartSlot
        phase="episode";
    end
    row=table(direction,k,sourceID,sourceSlot0,phase,available,decision, ...
        double(g.ControlAbsoluteSlot),double(g.ScheduledAbsoluteSlot), ...
        reportedRank,double(g.NumLayers),double(g.MCSIndex),double(a.CRCPass), ...
        string(g.PHYGrant.GrantContextId),string(receipt.Identity.TransmissionID), ...
        string(a.ReceiverObservationID),double(a.CompletedAtSample), ...
        'VariableNames',{'Direction','ApplicationOrdinal','ReceivedSourceID', ...
        'SourceSlot0','SourceEpisode','AvailableAtSample','DecisionAtSample', ...
        'ControlSlot0','DataSlot0','ReceivedRI','ScheduledRank','MCSIndex','CRCPass', ...
        'PHYGrantContextID','TransmissionID','ReceiverObservationID','CompletedAtSample'});
    rows=[rows;row]; %#ok<AGROW>
end
if ~isempty(rows)
    assert(numel(unique(rows.TransmissionID))==height(rows) && ...
        numel(unique(rows.ReceiverObservationID))==height(rows));
end
trials=state.TestPublishedDLTrials;
if direction=="UL", trials=state.TestPublishedULTrials; end
assert(height(trials)==height(rows) && isempty(state.SharedCompletedDataPlans) && ...
    isequaln(state.SharedULLinkAdaptationStates,state.TestPublishedULStates));
for k=1:height(rows)
    hit=find(string(trials.FrozenGrantContextId)==rows.PHYGrantContextID(k));
    assert(isscalar(hit) && trials.Layers(hit)==rows.ScheduledRank(k) && ...
        isequaln(double(trials.CRCPass(hit)),rows.CRCPass(k)));
end
assert(state.ConnectedULTimingByUE{1}.TimeAlignmentExpirySampleExclusive== ...
    state.TestRankTransitionInitialTAGExpiry);
evidence.WaveformExecuted=true;
evidence.ObservedApplications=rows;
evidence.ObservedRanks=zeros(1,0);
if ~isempty(rows), evidence.ObservedRanks=unique(rows.ScheduledRank).'; end
evidence.UnexercisedTargetRanks=setdiff([2 4],evidence.ObservedRanks);
if ~isempty(rows)
    evidence.RankTransitionCoverageComplete= ...
        any(rows.SourceEpisode=="before" & rows.ScheduledRank==4) && ...
        any(rows.SourceEpisode=="episode" & rows.ScheduledRank==2) && ...
        any(rows.SourceEpisode=="after" & rows.ScheduledRank==4);
end
evidence.RankPopulationStatus="incomplete_observed_population_not_qualified";
if evidence.RankTransitionCoverageComplete
    evidence.RankPopulationStatus="observed_single_realization_4_2_4_not_statistical";
end
evidence.Termination=state.TestRankTransitionTermination;
evidence.QueuedApplicationCount=state.TestRankTransitionAttemptOrdinal;
evidence.UncompletedQueuedApplicationCount=state.TestRankTransitionAttemptOrdinal-numel(apps);
evidence.SchedulingPopulationScope="one_outstanding_new_source_application_until_physical_failure_or_configured_horizon";
evidence.InitialTAGExpirySample=state.TestRankTransitionInitialTAGExpiry;
evidence.FinalPhysicalSample=state.SharedWaveformStream.Events.NextSampleIndex;
evidence.OriginalAuditPath=string(originalAuditPath);
evidence.ExecutedChannelIntervals=ReceivedSpatialRankAudit.executedIntervals( ...
    state.SharedWaveformStream.Events.ExecutionTrace,cfg,state.SharedWaveformStream.SampleRateHz);
evidence.PendingObservationKinds=string({state.SharedWaveformStream.Pending.Kind});
evidence.PendingFeedback=state.PendingFeedbackTable(~state.PendingFeedbackTable.Processed,:);
evidence.HARQRetryQualified=false;
evidence.OutputRoot=string(outputRoot);
evidence.PeriodicCSIRefreshAfterULQuality=struct('Observed',false,'Scope',"not_UL_continuation");
if direction=="UL"
    evidence.PeriodicCSIRefreshAfterULQuality=PeriodicCSIRefreshAudit.verify(state.TestPeriodicCSIRefreshSnapshots);
    fprintf('PERIODIC_CSI_PHYSICAL_REFRESH observed=%d witnesses=%d UCI_delivery_qualified=0\n', ...
        evidence.PeriodicCSIRefreshAfterULQuality.Observed, ...
        height(evidence.PeriodicCSIRefreshAfterULQuality.Witnesses));
end
receivedCSI=state.SharedGNBCSIReportTable;
receivedReferences=state.ReferenceSignalMeasurementTable;
independentCSI=sixgr.util.structGet(state,'ControlTrials.CSIRS',table());
admission=state.SchedulerAdmissionTable;
if ~isempty(rows)
    sixgr.util.csvWriteTable(fullfile(outputRoot,'observed_rank_applications.csv'), ...
        rows,'PreserveSchema',true,'RoundTripNumericText',true);
end
ok=~isempty(apps);
evidence.CompletedApplicationIntegrityVerified=ok;
save(fullfile(outputRoot,'rank_transition_boundary.mat'),'evidence','apps','trials', ...
    'receivedCSI','receivedReferences','independentCSI','admission','-v7.3');
status="NOT_EXERCISED";
if ok, status="BOUNDARY_PASS"; end
fprintf('RECEIVED_SPATIAL_RANK_%s direction=%s applications=%d observed_ranks=%s rank_transition_coverage=%d termination=%s full_scenario=0\n', ...
    status,direction,height(rows),mat2str(evidence.ObservedRanks), ...
    evidence.RankTransitionCoverageComplete,evidence.Termination);
end

function localPreflight(cfg)
assert(sixgr.channel.IdentityAWGNRuntime.enabled(cfg) && ...
    isequal(cfg.channel.awgnSpatialMatrixDL,eye(4)) && ...
    isequal(size(cfg.channel.awgnBeamFailureMatrixDL),[4 4]) && ...
    rank(cfg.channel.awgnBeamFailureMatrixDL)==2 && ...
    all(vecnorm(cfg.channel.awgnBeamFailureMatrixDL)>0) && ...
    all(vecnorm(cfg.channel.awgnBeamFailureMatrixDL,2,2)>0));
assert(cfg.channel.awgnBeamFailureStartSlot==20 && ...
    cfg.channel.awgnBeamFailureEndSlotExclusive==35 && cfg.run.totalSlots==50);
assert(cfg.phy.pdsch.maxLayers==4 && cfg.phy.pusch.NumAntennaPorts==4 && ...
    cfg.phy.pusch.maxLayers==4 && cfg.phy.srs.nPorts==4 && ...
    all(ismember([2 4],cfg.phy.csi.rankDomain)) && ...
    all(ismember([2 4],cfg.phy.csi.reportConfiguration.AllowedRanks)) && ...
    cfg.phy.linkAdaptation.rankIncreaseConfirmationReports==2);
assert(~cfg.run.controlGating.prachRequired && cfg.run.controlGating.pbchRequired && ...
    cfg.run.controlGating.srsRequired && cfg.run.controlGating.trsRequired);
strict=sixgr.phy.srs.buildSRSConfigFromScenario(cfg);
assert(strict.NumSRSSymbols==1 && strict.Periodicity==5 && strict.Offset==4 && ...
    isequal(double(cfg.phy.pusch.symbolAllocation),[0 11]));
carrier=strict.ToolboxCarrier; carrier.NSlot=strict.ExpectedSlotSet(1);
ix=double(nrSRSIndices(carrier,strict.ToolboxSRS));
symbols=unique(floor(mod(ix-1,double(carrier.NSizeGrid)*12*double(carrier.SymbolsPerSlot))/ ...
    (double(carrier.NSizeGrid)*12)));
assert(isequal(symbols,11));
policy=sixgr.mimo.resolveRankPolicy(cfg);
assert(policy.AdaptiveRank && ~policy.FixedRankAnchor);
dmrs=sixgr.phy.grant.validatePDSCHDMRSRankDomain(cfg);
assert(isequal(dmrs.Ranks,1:4) && all(dmrs.NumCDMGroupsWithoutData==2));
fprintf('RANK_TRANSITION_CONFIG_PREFLIGHT_PASS physical_ports=4 configured_channel_ranks=4_2_4 forced_RI=0 waveform_executed=0\n');
end
