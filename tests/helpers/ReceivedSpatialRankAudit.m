classdef ReceivedSpatialRankAudit
    % Test-only persistence/audit of original completed execution metadata.
    % No channel replay or coefficients enter a practical receiver here.
    methods (Static)
        function [path,ulHARQAudit]=saveOriginal(state,cfg,direction,outputRoot,harnessOK)
            % The lifetime ExecutionTrace is already the physical owner's
            % metadata-only trace (no IQ/path-gain tensor duplication). Keep
            % it unchanged, plus original application/control/feedback values;
            % never serialize the live runtime/owner/shared handles.
            owner=state.SharedWaveformStream;
            ulHARQAudit=ReceivedSpatialRankAudit.ulHARQSnapshot(state,direction);
            original=struct('Contract',"received_spatial_rank_original_audit/v1", ...
                'Status',"unverified_snapshot_before_wrapper_assertions", ...
                'Direction',string(direction),'HarnessReturnedOK',harnessOK, ...
                'WrapperIntegrityVerified',false,'FullScenarioQualified',false, ...
                'StatisticalQualification',false,'FixtureConfig',cfg, ...
                'SampleRateHz',owner.SampleRateHz,'FinalPhysicalSample',owner.Events.NextSampleIndex, ...
                'ExecutionTrace',{owner.Events.ExecutionTrace}, ...
                'Applications',{state.TestRankTransitionApplications}, ...
                'PublishedDLTrials',state.TestPublishedDLTrials, ...
                'PublishedULTrials',state.TestPublishedULTrials, ...
                'ReceivedCSI',state.SharedGNBCSIReportTable, ...
                'ReceivedReferences',state.ReferenceSignalMeasurementTable, ...
                'IndependentCSI',sixgr.util.structGet(state,'ControlTrials.CSIRS',table()), ...
                'SchedulerAdmission',state.SchedulerAdmissionTable, ...
                'PendingFeedback',state.PendingFeedbackTable, ...
                'PeriodicCSIRefreshSnapshots',{sixgr.util.structGet(state,'TestPeriodicCSIRefreshSnapshots',{})}, ...
                'Termination',state.TestRankTransitionTermination, ...
                'InitialTAGExpirySample',state.TestRankTransitionInitialTAGExpiry, ...
                'QueuedApplicationCount',state.TestRankTransitionAttemptOrdinal, ...
                'ULHARQAudit',ulHARQAudit);
            path=fullfile(outputRoot,'rank_transition_original_audit.mat');
            save(path,'original','-v7.3');
            fprintf('RECEIVED_SPATIAL_RANK_ORIGINAL_AUDIT path=%s applications=%d segments=%d wrapper_verified=0\n', ...
                path,numel(original.Applications),numel(original.ExecutionTrace));
        end

        function audit=ulHARQSnapshot(state,direction)
            % Retain original metadata, not live HARQ owners/processes/LLRs.
            % Presence is distinct from a present empty timeline or zero count.
            id='test:RankTransitionHARQAudit';
            direction=string(direction);
            assert(isstruct(state)&&isscalar(state)&&isscalar(direction)&& ...
                any(direction==["DL","UL"]),id,'Expected original state and explicit direction.');
            audit=struct('Contract',"received_spatial_rank_ul_harq_audit/v1", ...
                'Source',"original_runtime_values_no_feedback_recomputation", ...
                'ContinuationDirection',direction,'HARQTimelinePresent',false, ...
                'HARQTimelineSourceRowCount',NaN,'HARQTimelineSourceRows',zeros(0,1), ...
                'HARQTimelineTable',table(),'SharedPUSCHHARQFeedbackReceiptsPresent',false, ...
                'SharedPUSCHHARQFeedbackReceipts',{{}}, ...
                'ULHARQStatsPresent',false,'ULHARQStats',struct(), ...
                'TestSRSContinuationInitialHARQPresent',false, ...
                'TestSRSContinuationInitialHARQ',struct(), ...
                'TestRankTransitionAttemptHARQPresent',false, ...
                'TestRankTransitionAttemptHARQDirection',direction, ...
                'TestRankTransitionAttemptHARQ',struct());
            if isfield(state,'HARQTimelineTable')
                timeline=state.HARQTimelineTable;
                assert(istable(timeline),id,'Original HARQ timeline must remain a table.');
                ReceivedSpatialRankAudit.assertValueOnly(timeline);
                indices=zeros(0,1);
                if height(timeline)>0
                    assert(ismember('Direction',timeline.Properties.VariableNames),id, ...
                        'A nonempty original timeline requires its direction.');
                    directions=string(timeline.Direction);
                    assert(isequal(size(directions),[height(timeline),1]) && ...
                        all(~ismissing(directions)) && all(ismember(directions,["DL","UL"])),id, ...
                        'Do not infer or silently discard an unknown timeline direction.');
                    indices=find(directions=="UL");
                end
                audit.HARQTimelinePresent=true;
                audit.HARQTimelineSourceRowCount=height(timeline);
                audit.HARQTimelineSourceRows=indices;
                audit.HARQTimelineTable=timeline(indices,:);
            end
            if isfield(state,'SharedPUSCHHARQFeedbackReceipts')
                receipts=state.SharedPUSCHHARQFeedbackReceipts;
                assert(iscell(receipts),id,'Keep the original PUSCH receipt cell shape/order.');
                for k=1:numel(receipts)
                    ReceivedSpatialRankAudit.assertScalarRecord(receipts{k});
                end
                audit.SharedPUSCHHARQFeedbackReceiptsPresent=true;
                audit.SharedPUSCHHARQFeedbackReceipts=receipts;
            end
            if isfield(state,'ULHarq')
                owner=state.ULHarq;
                assert((isa(owner,'sixgr.l2.mac.HARQEntity') && isscalar(owner) && ...
                    string(owner.Direction)=="UL") || ...
                    (isstruct(owner) && isscalar(owner) && isfield(owner,'Stats')),id, ...
                    'Only read the original UL HARQ scalar Stats value, never serialize its owner.');
                stats=owner.Stats;
                ReceivedSpatialRankAudit.assertScalarRecord(stats);
                audit.ULHARQStatsPresent=true; audit.ULHARQStats=stats;
            end
            % The generic attempt baseline belongs to DL in a DL continuation.
            % Preserve its explicit direction instead of relabelling it as UL.
            for name=["TestSRSContinuationInitialHARQ","TestRankTransitionAttemptHARQ"]
                if isfield(state,name)
                    value=state.(name);
                    ReceivedSpatialRankAudit.assertScalarRecord(value);
                    audit.(name+"Present")=true; audit.(name)=value;
                end
            end
        end

        function rows=executedIntervals(trace,cfg,sampleRate)
            id='test:RankTransitionExecutionAudit';
            assert(iscell(trace)&&isscalar(sampleRate)&&isfinite(sampleRate)&&sampleRate>0&& ...
                isequal(cfg.channel.awgnBeamFailureRecoveryEnabled,true),id, ...
                'This audit is for the explicitly enabled piecewise fixture.');
            carrier=sixgr.phy.grid.makeCarrier(cfg);
            first=sixgr.phy.frame.slotStartSample(carrier,cfg.channel.awgnBeamFailureStartSlot,sampleRate);
            last=sixgr.phy.frame.slotStartSample(carrier,cfg.channel.awgnBeamFailureEndSlotExclusive,sampleRate);
            rows=table();
            for k=1:numel(trace)
                segment=trace{k}; execution=segment.Execution;
                assert(isfinite(segment.StartSample)&&segment.StartSample>=0&& ...
                    segment.StartSample==fix(segment.StartSample)&& ...
                    isfinite(segment.EndSampleExclusive)&&segment.EndSampleExclusive>segment.StartSample&& ...
                    segment.EndSampleExclusive==fix(segment.EndSampleExclusive)&& ...
                    execution.SampleRateHz==sampleRate,id,'Original processor bounds/rate changed.');
                for link=reshape(execution.Links,1,[])
                    r=link.Replay;
                    % Episode-capable execution remains piecewise even when
                    % this particular interval has only its baseline segment.
                    sha=string(r.AppliedAWGNSpatialMatrixSHA256);
                    assert(string(r.ChannelModelApplied)=="AWGN" && ...
                        string(r.RuntimeChannelTimingTruthSource)=="executed_piecewise_matrix_operator_zero_delay" && ...
                        r.RuntimeChannelStartSample==segment.StartSample && ...
                        r.RuntimeChannelEndSample==segment.EndSampleExclusive && ...
                        isscalar(sha)&&strlength(sha)==64&& ...
                        ~isempty(regexp(char(sha),'^[0-9a-fA-F]{64}$','once')),id, ...
                        'Retain the exact executed piecewise source, full interval and operator signature.');
                    overlap=max(0,min(segment.EndSampleExclusive,last)-max(segment.StartSample,first));
                    segmentCount=1+double(first>segment.StartSample&&first<segment.EndSampleExclusive)+ ...
                        double(last>segment.StartSample&&last<segment.EndSampleExclusive);
                    assert(r.BeamFailureRecoveryActiveSampleCount==overlap && ...
                        r.BeamFailureRecoveryEpisodeActive==(overlap>0)&& ...
                        r.BeamFailureRecoverySegmentCount==segmentCount,id, ...
                        'Original episode overlap and segment count must match exact native-clock bounds.');
                    % Compare the ORIGINAL full-interval execution signature
                    % with the fixture's declared operator, not a cropped
                    % window or a new waveform/channel execution.
                    direction=string(r.RuntimeChannelReciprocityDirection);
                    assert(isscalar(direction)&&any(direction==["DL","UL"]),id, ...
                        'Retain actual executed reciprocal direction.');
                    bounds=[segment.StartSample segment.EndSampleExclusive];
                    if first>segment.StartSample&&first<segment.EndSampleExclusive
                        bounds(end+1)=first;
                    end
                    if last>segment.StartSample&&last<segment.EndSampleExclusive
                        bounds(end+1)=last;
                    end
                    bounds=sort(bounds);
                    expected=struct('FirstOffset',{},'EndOffsetExclusive',{},'Matrix',{},'EpisodeActive',{});
                    for j=1:numel(bounds)-1
                        active=bounds(j)>=first&&bounds(j)<last;
                        matrix=cfg.channel.awgnSpatialMatrixDL;
                        if active, matrix=cfg.channel.awgnBeamFailureMatrixDL; end
                        if direction=="UL", matrix=matrix.'; end
                        expected(end+1)=struct('FirstOffset',bounds(j)-segment.StartSample, ... %#ok<AGROW>
                            'EndOffsetExclusive',bounds(j+1)-segment.StartSample, ...
                            'Matrix',matrix,'EpisodeActive',active);
                    end
                    assert(sha==sixgr.channel.PiecewiseAWGNReference.signature(expected),id, ...
                        'Original full-interval applied operator signature differs from this fixture.');
                    row=table(string(link.ID),string(link.TX),string(link.RX), ...
                        double(segment.StartSample),double(segment.EndSampleExclusive), ...
                        double(execution.SampleRateHz),double(overlap),sha, ...
                        'VariableNames',{'LinkID','TransmitterID','ReceiverID','StartSample', ...
                        'EndSampleExclusive','SampleRateHz','ExecutedEpisodeSamples','AppliedSegmentMatrixSHA256'});
                    rows=[rows;row]; %#ok<AGROW>
                end
            end
            assert(~isempty(rows)&&all(rows.SampleRateHz==sampleRate),id,'No original executed link intervals.');
        end
    end

    methods (Static, Access=private)
        function assertScalarRecord(value)
            id='test:RankTransitionHARQAudit';
            assert(isstruct(value)&&isscalar(value),id,'Original compact receipt/counters must be scalar structs.');
            names=fieldnames(value);
            for k=1:numel(names)
                v=value.(names{k});
                valid=((isnumeric(v)||islogical(v))&&isscalar(v)&&isreal(v)) || ...
                    (isstring(v)&&isscalar(v)) || (ischar(v)&&(isrow(v)||isempty(v)));
                assert(valid,id,'Original compact field %s is not a scalar value; no handles or payload arrays.',names{k});
            end
        end

        function assertValueOnly(value)
            id='test:RankTransitionHARQAudit';
            if isnumeric(value)||islogical(value)||ischar(value)||isstring(value), return; end
            if istable(value)
                for name=string(value.Properties.VariableNames)
                    ReceivedSpatialRankAudit.assertValueOnly(value.(name));
                end
                ReceivedSpatialRankAudit.assertValueOnly(value.Properties.UserData);
            elseif iscell(value)
                for k=1:numel(value), ReceivedSpatialRankAudit.assertValueOnly(value{k}); end
            elseif isstruct(value)
                names=fieldnames(value);
                for k=1:numel(value)
                    for n=1:numel(names)
                        ReceivedSpatialRankAudit.assertValueOnly(value(k).(names{n}));
                    end
                end
            else
                error(id,'The original HARQ timeline contains a non-value object; do not serialize live state.');
            end
        end
    end
end
