classdef SharedDataCompletionRuntime
    % Canonical completed DL/UL receiver commit and publication lifecycle.
    % Mechanical extraction from runWaveformLinkBundle. Immediate and shared
    % paths use the same row normalization; no second decoder/commit policy.
    % complete consumes one original completed item. Batch feedback rearming
    % remains with completeSharedReceiverBatch, not this per-item reducer.
    % logSink is the existing caller logger, not an execution-policy hook.
    methods (Static)
        function state = recordQueuedULSchedule(state, grants)
        if ~(isstruct(grants) && ~isempty(grants))
            grants = repmat(struct(), 0, 1);
        end
        ueIdx = arrayfun(@(g) double(sixgr.util.structGet(g, "UEIndex", NaN)), grants(:));
        ueIdx = ueIdx(isfinite(ueIdx));
        queueBitsByUE = double(sixgr.util.structGet(state, "ULQueueBits", 0));
        if isempty(ueIdx)
            activeUsers = sum(isfinite(queueBitsByUE(:)) & queueBitsByUE(:) > 0);
        else
            activeUsers = numel(unique(ueIdx));
        end
        info = struct( ...
            "Direction", "UL", ...
            "ActiveUsers", activeUsers, ...
            "GrantedUsers", numel(unique(ueIdx)), ...
            "GrantCount", numel(grants), ...
            "QueueBits", sum(queueBitsByUE, "omitnan"), ...
            "SchedulerDecisionRows", sixgr.truth.SharedDataCompletionRuntime.countQueuedULSchedulerDecisionRows(state));
        state.LastULGrantCount = numel(grants);
        state.LastULGrantedUsers = numel(unique(ueIdx));
        state.LastULActiveUsers = activeUsers;
        state = sixgr.truth.CoupledTruthRuntime.recordSlotTraceScheduleRuntime(state, "UL", info);
        end

        function [Tu,constT,waveT]=finalizeTables(res,cfgU,multiUser,ueIdx,direction,snr_dB)
        % Both immediate and deferred receive paths use the same row lifecycle.
        % This annotates actual receiver rows, never manufactures a receive attempt.
        userMeta=sixgr.util.structGet(cfgU,'lls6g.userContext',struct());
        Tu = sixgr.truth.SharedDataCompletionRuntime.ensureLinkTrialTable(sixgr.util.structGet(res, "TrialTable", table()), upper(string(direction)), snr_dB, cfgU);
        Tu = sixgr.truth.SharedDataCompletionRuntime.annotateUserTrials(Tu, cfgU, multiUser, ueIdx, userMeta);
        constT = sixgr.truth.SharedDataCompletionRuntime.annotateConstellationSamples( ...
            sixgr.util.structGet(res, "ConstellationSamples", table()), cfgU, multiUser, ueIdx, userMeta, snr_dB, direction);
        waveT = sixgr.truth.SharedDataCompletionRuntime.annotateWaveformPreviewTable(sixgr.util.structGet(res, "WaveformPreviewTable", table()), cfgU, ueIdx, direction);
        end

        function state=complete(state,item,logSink)
        c=item.Context; plan=c.Plan; job=c.Job; p=c.Prepared;
        controls=sixgr.util.structGet(state,'SharedReceivedGrantControls',{});
        hit=find(cellfun(@(x)x.Key==c.Key,controls));
        assert(numel(hit)==1,'sixgr:truth:SharedDataControlNotReceived', ...
            'Data reception needs the exact actual received control result, never a queued grant.');
        control=controls{hit};
        if ~control.Allowed && job.Direction=="DL"
            state=sixgr.truth.completeSharedDLWithoutAcceptedControl(state,item,control);
            return;
        end
        assert(control.Allowed,'sixgr:truth:SharedDataDTXDispositionRequired', ...
            'PDSCH transmitted with failed DCI needs a DTX/feedback disposition; it cannot be decoded using scheduler oracle authority.');
        [job.GrantSnapshot,receivedEvidenceFields]=sixgr.truth.bindReceivedPDCCHGrantEvidence( ...
            job.GrantSnapshot,control.Grant);
        plan.GrantSnapshot=job.GrantSnapshot;
        [post,pre,tx,replay,receiver]=sixgr.truth.sharedObservationEvidence(item.Planes,p);
        assert(control.AvailableAtSample<=post.EndSampleExclusive, ...
            'sixgr:truth:FutureSharedDCIAuthority','Control authority must already be available to the receiver.');
        replay=sixgr.truth.bindSharedDataNoiseEvidence( ...
            item.Planes,p,c.DesiredReferencePlane,replay,job.SNR_dB);
        job.PrepareOnly=false;
        job.ReceivedContext=struct('Prepared',p,'Observation',receiver, ...
            'PhysicalMeasurementObservation',pre,'TransmitterObservation',tx,'Replay',replay, ...
            'ChannelState',state.SharedWaveformStream.directionalChannelState(item.UE,job.Direction));
        job.ReceivedContext.ReceivedAssignment=control.ReceivedAssignment;
        job.ReceivedContext.UEIndex=item.UE;
        independentPUSCHUCI=job.Direction=="UL" && ...
            sixgr.truth.isPUSCHUCIAvailable(job.Cfg) && isfield( ...
            sixgr.util.structGet(job.Cfg,'phy.pdcch.operatorControl',struct()),'connected_dci');
        if independentPUSCHUCI
            % gNB schedule/calendar, not the UE's pending/encoded UCI, determines
            % the receive width even when the UE has no report or missed a DL DCI.
            job=sixgr.truth.bindSharedPUSCHReceiverContext(state,job);
        end
        connectedDL=job.Direction=="DL" && isfield( ...
            sixgr.util.structGet(job.Cfg,'phy.pdcch.operatorControl',struct()),'connected_dci');
        if connectedDL
            dlEntities=sixgr.util.structGet(state,'SharedUEDLHARQEntities',{});
            if numel(dlEntities)<item.UE || isempty(dlEntities{item.UE})
                dlEntities{item.UE}=sixgr.link.ReceivedDLHARQState(job.Cfg,item.UE);
            end
            job.ReceivedContext.ReceivedHARQState=dlEntities{item.UE};
            if ~dlEntities{item.UE}.requiresDecode(job.Cfg,control.ReceivedAssignment)
                % The actual TX remains in the physical-owner ledger. This event
                % acknowledges retained UE state, not a new CRC or delivered TB.
                sixgr.truth.validateSharedDataReceptionTX(state, ...
                    struct('SharedTransmissionID',c.TransmissionIdentity.TransmissionID), ...
                    job.GrantSnapshot,p.Tx.TransportBlock,item.UE,'DL',job.GrantSnapshot.Slot);
                state.SharedUEDLHARQEntities=dlEntities;
                [state,~]=sixgr.truth.CoupledTruthRuntime.queueRetainedDLACKRuntime( ...
                    state,job.Cfg,item.UE,control,state.SharedWaveformStream.Events.NextSampleIndex);
                ids=sixgr.util.structGet(state,'SharedDataRXCommittedIDs',strings(0,1));
                state.SharedDataRXCommittedIDs=[ids;string(c.TransmissionIdentity.TransmissionID)];
                state.DLCompletedSlots=max(double(sixgr.util.structGet(state,'DLCompletedSlots',0)), ...
                    double(job.GrantSnapshot.Slot));
                source=find(double(state.SlotTraceTable.CanonicalSlot)==double(job.GrantSnapshot.Slot));
                assert(isscalar(source),'sixgr:truth:MissingSharedSourceSlotTrace', ...
                    'Protocol completion requires its already-started source-slot trace.');
                state.DLCompletedFrames=max(double(sixgr.util.structGet(state,'DLCompletedFrames',0)), ...
                    double(state.SlotTraceTable.FrameLocal(source)));
                return;
            end
        end
        output=sixgr.truth.executeGrantPHYJob(job);
        assert(output.ReadyForReceiverCommit,'sixgr:truth:SharedDataReceptionMissing','A receiver attempt must produce actual trial evidence.');
        res=output.Result;
        % Capture the decoder's original row before shared annotations or MAC
        % credit can change its identity/GoodBits. The capsule is not re-signed.
        decoderTrial=res.TrialTable;
        dlOutcomeAnchor=struct();
        if job.Direction=="DL"
            % Complete the CSI receive clock before committing shared HARQ/CSI
            % state or exporting the coordinator's authoritative measurement rows.
            res=sixgr.truth.bindSharedDLCSICompletion(res,p,receiver,state.SharedWaveformStream);
        end
        if connectedDL
            assert(isfield(res,'ReceivedHARQState') && isa(res.ReceivedHARQState,'sixgr.link.ReceivedDLHARQState'), ...
                'sixgr:truth:MissingReceivedDLHARQCommit','Shared DL completion must return the UE-owned soft state.');
            dlEntities{item.UE}=res.ReceivedHARQState;
            state.SharedUEDLHARQEntities=dlEntities;
            [state,res.ReceivedHARQACKEvent]=sixgr.truth.commitReceivedDLHARQACKEvent( ...
                state,job.Cfg,control,res.ReceivedHARQDecision,res.ReceivedHARQState, ...
                state.SharedWaveformStream.Events.NextSampleIndex);
        end
        res.TrialTable=sixgr.truth.bindSharedLargeScaleEvidence(res.TrialTable,item.Planes);
        res.TrialTable=sixgr.truth.bindSharedRFExecutionEvidence(res.TrialTable,item.Planes);
        if job.Direction=="UL"
            res.TrialTable=sixgr.truth.bindSharedTransmitOccupancy(res.TrialTable,state,item);
        end
        receivedEvidence=sixgr.link.receivedWaveformEvidence(receiver);
        for name=string(fieldnames(receivedEvidence)).'
            res.TrialTable.(name)=repmat(receivedEvidence.(name),height(res.TrialTable),1);
        end
        if logical(sixgr.util.structGet(job.Cfg,'outputs.phySignalDiagnosticEnabled',false)) && ...
                (logical(job.ReceivedContext.ChannelState.UseFading) || ...
                sixgr.channel.IdentityAWGNRuntime.isState(job.ReceivedContext.ChannelState))
            % queueData already requested the exact executed channel coefficients.
            % Publish those retained captures, not an effective-link IQ manifest in
            % fields consumed as a pure-channel archive. Keep the separate noiseless
            % link observation for post-decode NMSE scoring; no channel/RF replay and
            % no change to the practical receiver or its completed CRC decision.
            [res.TrialTable,channelDiagnosticContext,channelCaptures,~,scoringObservation,scoringEvidence]=sixgr.truth.exportSharedChannelObservation( ...
                sixgr.util.structGet(c.Config,'run.rootRunFolder',""),res.TrialTable, ...
                item.Planes,p,c.DesiredReferencePlane);
            if any(job.Direction==["DL","UL"])
                res.TrialTable.ChannelEstimateCaptureStatus="unavailable_no_receiver_pilot_estimate";
                if isfield(res,'ChannelEstimateSnapshots') && numel(res.ChannelEstimateSnapshots)==1 && ...
                        ~isempty(res.ChannelEstimateSnapshots{1})
                    res.TrialTable=sixgr.truth.exportSharedDataChannelEstimate( ...
                        sixgr.util.structGet(c.Config,'run.rootRunFolder',""),res.TrialTable, ...
                        res.ChannelEstimateSnapshots{1},p,scoringObservation,scoringEvidence);
                    if job.Direction=="DL"
                        res.TrialTable=sixgr.truth.exportSharedPDSCHCSIRSComparison( ...
                            sixgr.util.structGet(c.Config,'run.rootRunFolder',""),res.TrialTable, ...
                            res.ChannelEstimateSnapshots{1},p,scoringEvidence,channelCaptures, ...
                            state.SharedWaveformStream,item,struct('Observation',receiver, ...
                            'GainCompensation',replay.ReceiverGainCompensation));
                    end
                end
                % The immutable files retain the pilot evidence. Do not accumulate
                % full-band receiver captures in the long-lived runtime state.
                if isfield(res,'ChannelEstimateSnapshots'), res=rmfield(res,'ChannelEstimateSnapshots'); end
            end
            % The executed channel coefficients are deliberately unavailable to the
            % practical receiver. Add them to publication evidence only after the
            % decode and CRC decision have completed.
            res.SignalDiagnostic=sixgr.link.buildPHYSignalDiagnosticSnapshot( ...
                job.Cfg,job.Direction,struct(),[],struct(),table(), ...
                channelDiagnosticContext,res.SignalDiagnostic);
        end
        res.HARQ.SharedTransmissionID=c.TransmissionIdentity.TransmissionID;
        res.HARQ.ReceivedTimingEvidence=sixgr.truth.receivedDataSymbolTiming( ...
            p,receiver,res.ReceiveTiming,state.SharedWaveformStream.Events.NextSampleIndex);
        if independentPUSCHUCI
            [state,res.HARQ]=sixgr.truth.CoupledTruthRuntime.completeSharedPUSCHHARQFeedbackRuntime( ...
                state,job.Cfg,res.HARQ,receiver,job.ReceivedContext.UCIReceiveContext);
            % The later legacy completion validates this receipt; it cannot apply a
            % second feedback update or fall back to transmitter-sized bit mapping.
        end
        receiveFields=sixgr.truth.harqFeedbackReceiveTimingFields(res.HARQ,res.HARQ.GrantSnapshot,true);
        for name=string(fieldnames(receiveFields)).'
            res.TrialTable.(name)=repmat(receiveFields.(name),height(res.TrialTable),1);
        end
        if connectedDL
            dlOutcomeAnchor=sixgr.truth.SharedDLSCHOutcomeBinding.capture( ...
                state,item,control,res,decoderTrial,receiver,replay);
        end
        if job.Direction=="UL" && isfield(res,'ReceiveTiming') && ...
                isfield(res,'TrialTable') && ~isempty(res.TrialTable) && ...
                ismember('CRCPass',res.TrialTable.Properties.VariableNames) && res.TrialTable.CRCPass(end)==1
            state=sixgr.truth.storeReceivedULTimingReference(state,item.UE, ...
                sixgr.phy.sync.ReceivedULTimingReference(p,receiver,res.ReceiveTiming));
        end
        plan.Cfg=job.Cfg;
        [trial,plan.ConstellationTable,plan.WaveformPreviewTable]= ...
            sixgr.truth.SharedDataCompletionRuntime.finalizeTables(res,job.Cfg,c.MultiUser,item.UE,job.Direction,job.SNR_dB);
        state.SharedWaveformPreviewTable=sixgr.truth.PDCCHControlRuntime.appendCompatTable( ...
            sixgr.util.structGet(state,'SharedWaveformPreviewTable',table()), ...
            plan.WaveformPreviewTable);
        trial=sixgr.truth.SharedDataCompletionRuntime.annotateGrantRows(trial,plan.GrantRow);
        % The planning row predates reception and cannot overwrite received DCI
        % evidence. Copy only the receiver-owned fields from this exact grant.
        for fieldIndex=1:numel(receivedEvidenceFields)
            name=receivedEvidenceFields{fieldIndex};
            value=job.GrantSnapshot.(name);
            if ischar(value), value=string(value); end
            trial.(name)=repmat(value,height(trial),1);
        end
        state=sixgr.truth.CoupledTruthRuntime.setCurrentUE(state,item.UE,job.Direction);
        [state,trial]=sixgr.truth.CoupledTruthRuntime.completeSlot(state,plan.Cfg,item.UE,job.Direction,trial,res);
        % Frozen CSI operands alone do not prove their application. Preserve a
        % separate receipt only after the actual transmitted and decoded attempt
        % has committed. Bootstrap grants without received CSI remain bootstrap.
        capsule=sixgr.util.structGet(p.RequestBinding.Grant,'CSIReportProvenance',struct());
        if job.Direction=="DL" && ...
                string(sixgr.util.structGet(capsule,'Version',""))=="received_csi_provenance/v1" && ...
                isequal(sixgr.util.structGet(capsule,'ReceiverObservationBound',false),true) && ...
                all(ismember({'Crash','CRCApplicable','DLSCHDecodeAttempted','DecodeAttempted','CRCPass'},trial.Properties.VariableNames)) && ...
                height(trial)==1 && ~trial.Crash && trial.CRCApplicable && ...
                trial.DLSCHDecodeAttempted && trial.DecodeAttempted && any(double(trial.CRCPass)==[0 1])
            res.TrialTable=trial;
            application=sixgr.truth.buildCompletedCSIApplicationEvidence(state,item,control,res);
            trial=sixgr.truth.bindCompletedCSIApplicationEvidence(trial,application);
            res.TrialTable=trial;
        end
        % Reception has validated the actual transmitted grant/TB. Publish the
        % exact projection retained by queueData, not an array rebuilt from YAML
        % or a logical-port count inferred from the transmitted layer count.
        trial=sixgr.truth.bindExecutedDataAntennaEvidence(trial, ...
            p.RequestBinding.PHYGrant,c.WaveformToElementMappingEvidence,c.WaveformToElementMatrix,p.Tx.Waveform);
        plan.Result=res;
        state=sixgr.truth.SharedDataCompletionRuntime.captureCommittedFullPHYISAC(state,c.Config,plan,job.Direction,logSink);
        state=sixgr.truth.SharedDataCompletionRuntime.captureCommittedTxIQ(state,c.Config,plan,job.Direction,logSink);
        trial=sixgr.truth.annotateFrozenMUMIMOTrialEvidence(trial,plan.GrantSnapshot);
        trial=sixgr.link.applyMeasuredDLMUMIMOReceiverEvidence(trial);
        plan.TrialTable=sixgr.link.applyScheduledOperatingPointEvidence(trial);
        if ~isempty(fieldnames(dlOutcomeAnchor))
            plan.TrialTable=sixgr.truth.SharedDLSCHOutcomeBinding.bind( ...
                state,item,control,plan.TrialTable,dlOutcomeAnchor);
        end
        plan.LinkAdaptationState=output.LinkAdaptationState;
        state.ObservedREAllocationTable=sixgr.truth.PDCCHControlRuntime.appendObservedREAllocation( ...
            sixgr.util.structGet(state,'ObservedREAllocationTable',table()), ...
            sixgr.util.structGet(res,'ObservedREAllocationTable',table()));
        state=sixgr.truth.SharedDataCompletionRuntime.recordPHYSignalDiagnostic(state,job.Direction,sixgr.util.structGet(res,'SignalDiagnostic',struct()));
        complete=sixgr.util.structGet(state,'SharedCompletedDataPlans',{});
        complete{end+1}=struct('Direction',job.Direction,'Plan',plan);
        state.SharedCompletedDataPlans=complete;
        end

        function [state,dl,ul,dc,uc,ds,us]=drain(state,dl,ul,dc,uc,ds,us)
        complete=sixgr.util.structGet(state,'SharedCompletedDataPlans',{});
        for k=1:numel(complete)
            p=complete{k}.Plan;
            if complete{k}.Direction=="DL"
                dl=sixgr.truth.PDCCHControlRuntime.appendCompatTable(dl,p.TrialTable); dc=sixgr.truth.PDCCHControlRuntime.appendCompatTable(dc,p.ConstellationTable);
                ds{p.UEIndex}=p.LinkAdaptationState;
            else
                ul=sixgr.truth.PDCCHControlRuntime.appendCompatTable(ul,p.TrialTable); uc=sixgr.truth.PDCCHControlRuntime.appendCompatTable(uc,p.ConstellationTable);
                us{p.UEIndex}=p.LinkAdaptationState;
            end
        end
        state.SharedCompletedDataPlans={};
        state.SharedULLinkAdaptationStates=us;
        end

        function T = annotateGrantRows(T, grantRow)
        if ~(istable(T) && ~isempty(T) && istable(grantRow) && ~isempty(grantRow))
            return;
        end
        vars = string(grantRow.Properties.VariableNames);
        for i = 1:numel(vars)
            name = char(vars(i));
            value = grantRow.(name)(1);
            if ismember(name, string(T.Properties.VariableNames))
                if isstring(T.(name))
                    T.(name)(:) = string(value);
                elseif islogical(T.(name))
                    T.(name)(:) = logical(value);
                else
                    T.(name)(:) = double(value);
                end
            else
                if isstring(value) || ischar(value)
                    T.(name) = repmat(string(value), height(T), 1);
                elseif islogical(value)
                    T.(name) = repmat(logical(value), height(T), 1);
                else
                    T.(name) = repmat(double(value), height(T), 1);
                end
            end
        end
        end

    end

    methods (Static, Hidden)
        function mode = resolveDopplerSourceMode(cfg)
        mode = string(sixgr.util.structGet(cfg, "channel.dopplerSourceMode", "configured"));
        mode = lower(strtrim(mode));
        if strlength(mode) == 0
            mode = "configured";
        end
        end

        function mask = rowsUseFadingChannelDoppler(T)
        mask = false(height(T), 1);
        if ~(istable(T) && height(T) > 0)
            return;
        end
        n = height(T);
        trackingSource = lower(strtrim(string(sixgr.truth.PDCCHControlRuntime.columnOrDefault(T, "TrackingEstimateSource", repmat("", n, 1)))));
        sourceArtifact = lower(strtrim(string(sixgr.truth.PDCCHControlRuntime.columnOrDefault(T, "SourceArtifact", repmat("", n, 1)))));
        isTRS = contains(trackingSource, "trs") | contains(sourceArtifact, "trs_trials");
        channelModel = upper(strtrim(string(sixgr.truth.PDCCHControlRuntime.columnOrDefault(T, "ChannelModel", repmat("", n, 1)))));
        channelModelApplied = upper(strtrim(string(sixgr.truth.PDCCHControlRuntime.columnOrDefault(T, "ChannelModelApplied", repmat("", n, 1)))));
        fadingFlag = double(sixgr.truth.PDCCHControlRuntime.columnOrDefault(T, "ChannelFadingApplied", nan(n, 1)));
        fadingApplied = isfinite(fadingFlag) & fadingFlag == 1;
        fadingModel = startsWith(channelModel, "TDL") | startsWith(channelModel, "CDL") | ...
            startsWith(channelModelApplied, "TDL") | startsWith(channelModelApplied, "CDL");
        mask = logical(isTRS & (fadingApplied | fadingModel));
        end

        function [mode, policy, actualMode] = resolveLinkAdaptationTokens(cfg, direction)
        mode = lower(string(sixgr.util.structGet(cfg, "phy.linkAdaptation.mode", "fixed")));
        if upper(string(direction)) == "UL"
            policy = lower(string(sixgr.util.structGet(cfg, "phy.linkAdaptation.ulPolicy", mode)));
        else
            policy = lower(string(sixgr.util.structGet(cfg, "phy.linkAdaptation.dlPolicy", mode)));
        end
        if strlength(strtrim(policy)) == 0
            policy = mode;
        end
        actualMode = "configured_fixed";
        if policy ~= "fixed"
            switch sixgr.link.resolveLinkAdaptationDomain(cfg, direction)
                case "effective_sinr"
                    actualMode = "effective_sinr_driven";
                case "bler_margin"
                    actualMode = "bler_margin_proxy";
                case "legacy_mcs"
                    actualMode = "legacy_mcs_smoothed";
                otherwise
                    actualMode = "cqi_driven";
            end
        end
        end

        function values = resolveOperatingPointSourceColumn(actualMode, linkMode)
        values = repmat("", numel(actualMode), 1);
        actualMode = lower(strtrim(string(actualMode)));
        linkMode = lower(strtrim(string(linkMode)));
        values(actualMode == "scheduler_grant") = "scheduler_grant";
        values(actualMode == "cqi_driven") = "cqi_link_adaptation";
        values(actualMode == "effective_sinr_driven") = "effective_sinr_link_adaptation";
        values(actualMode == "bler_margin_proxy") = "bler_margin_proxy_link_adaptation";
        values(actualMode == "legacy_mcs_smoothed") = "legacy_mcs_domain_smoothing";
        values(actualMode == "cqi_table") = "cqi_link_adaptation";
        values(actualMode == "configured_fixed") = "configured_fixed_mcs";
        values(actualMode == "configured_initial_mcs") = "configured_initial_mcs";
        values(actualMode == "feedback_cqi_derived_reference") = "feedback_cqi_derived_reference";
        values(actualMode == "bootstrap_large_scale_preview_cqi_lab_default") = "bootstrap_large_scale_preview_cqi_lab_default";
        values(actualMode == "bootstrap_cqi_conservative_lab_default") = "bootstrap_cqi_conservative_lab_default";
        mask = strlength(values) == 0 & strlength(linkMode) > 0;
        values(mask) = "link_adaptation_mode_reference";
        end

        function count = countQueuedULSchedulerDecisionRows(state)
        count = 0;
        T = sixgr.util.structGet(state, "SchedulerDecisionTable", table());
        if ~(istable(T) && ~isempty(T))
            return;
        end
        vars = string(T.Properties.VariableNames);
        if ~all(ismember(["Direction","ScheduledDataSlot"], vars))
            return;
        end
        direction = upper(strtrim(string(T.Direction)));
        dataSlot = double(T.ScheduledDataSlot);
        currentSlot = double(sixgr.util.structGet(state, "CurrentSlot", NaN));
        count = double(sum(direction == "UL" & isfinite(dataSlot) & dataSlot == currentSlot));
        end

        function runtimeState = captureCommittedFullPHYISAC(runtimeState,cfg,plan,direction,logSink)
        if ~logical(sixgr.util.structGet(cfg,"isac.enabled",false)) || ...
                upper(string(direction)) ~= "DL"
            return;
        end

        prior = sixgr.util.structGet(runtimeState,"ISAC",struct());
        if logical(sixgr.util.structGet(prior,"Executed",false)) || ...
                logical(sixgr.util.structGet(prior,"EvidenceValid",false))
            return;
        end
        sixgr.isac.validateConfig(cfg);
        capture = sixgr.util.structGet(plan,"Result.ISACWaveformCapture",struct());
        waveform = sixgr.util.structGet(capture,"Waveform",[]);
        sampleRateHz = double(sixgr.util.structGet(capture,"SampleRateHz",NaN));
        if isempty(waveform) || ~(isfinite(sampleRateHz) && sampleRateHz > 0)
            error("sixgr:isac:MissingCommittedPDSCHWaveform", ...
                "The first committed DL grant did not return its exact post-Tx-RF PDSCH waveform.");
        end

        ueIdx = round(double(sixgr.util.structGet(plan,"UEIndex",NaN)));
        grant = sixgr.util.structGet(plan,"GrantSnapshot",struct());
        servingCell = round(double(sixgr.util.structGet(grant,"ServingCell",NaN)));
        bsRuntime = sixgr.util.structGet(runtimeState,"BSAntennaRuntime",repmat(struct(),0,1));
        ueRuntime = sixgr.util.structGet(runtimeState,"UEAntennaRuntime",repmat(struct(),0,1));
        bsPositions = double(sixgr.util.structGet(runtimeState,"Layout.bs.pos_m",zeros(0,3)));
        uePositions = double(sixgr.util.structGet(runtimeState,"UE.pos_m",zeros(0,3)));
        if ~(isfinite(servingCell) && servingCell >= 1 && servingCell <= numel(bsRuntime) && ...
                servingCell <= size(bsPositions,1))
            error("sixgr:isac:MissingRuntimeGNBState", ...
                "Committed ISAC grant has no bound runtime gNB array/topology row.");
        end
        if ~(isfinite(ueIdx) && ueIdx >= 1 && ueIdx <= numel(ueRuntime) && ...
                ueIdx <= size(uePositions,1))
            error("sixgr:isac:MissingRuntimeUEState", ...
                "Committed ISAC grant has no bound runtime UE array/topology row.");
        end

        mode = lower(strtrim(string(cfg.isac.sensingMode)));
        txEntry = bsRuntime(servingCell);
        if mode == "monostatic_gnb"
            rxEntry = bsRuntime(servingCell);
        else
            rxEntry = ueRuntime(ueIdx);
        end
        context = struct( ...
            "SignalType","PDSCH", ...
            "ScenarioId",string(sixgr.util.structGet(cfg,"run.scenarioID", ...
                sixgr.util.structGet(cfg,"meta.lls6gScenarioID",""))), ...
            "CarrierFrequencyHz",double(sixgr.util.structGet(cfg,"channel.fc_Hz", ...
                sixgr.util.structGet(cfg,"phy.fc_Hz",NaN))), ...
            "SampleRateHz",sampleRateHz, ...
            "TxAntennaRuntime",txEntry, ...
            "RxAntennaRuntime",rxEntry, ...
            "GNBPositionM",reshape(bsPositions(servingCell,1:3),1,[]), ...
            "UEPositionM",reshape(uePositions(ueIdx,1:3),1,[]));
        sensing = sixgr.lls.runISACSensingTrial(cfg,struct("Waveform",waveform),context);
        grantContextId = string(sixgr.util.structGet(grant,"PHYGrantContextId", ...
            sixgr.util.structGet(grant,"GrantContextId","")));
        sensing.RuntimeTable = addvars(sensing.RuntimeTable, ...
            repmat(grantContextId,height(sensing.RuntimeTable),1), ...
            repmat(double(ueIdx),height(sensing.RuntimeTable),1), ...
            repmat(double(servingCell),height(sensing.RuntimeTable),1), ...
            repmat(double(sixgr.util.structGet(capture,"Frame",NaN)),height(sensing.RuntimeTable),1), ...
            repmat(double(sixgr.util.structGet(capture,"Slot",NaN)),height(sensing.RuntimeTable),1), ...
            repmat(string(sixgr.util.structGet(capture,"CapturePoint","")),height(sensing.RuntimeTable),1), ...
            'NewVariableNames',{'PHYGrantContextId','UEIndex','ServingCell','Frame','Slot','CapturePoint'});
        sensing.Executed = true;
        runtimeState.ISAC = sensing;
        logSink("INFO", ...
            "Committed full-PHY ISAC capture: ue=%d cell=%d frame=%g slot=%g waveform_samples=%d ports=%d evidence_valid=%d.", ...
            ueIdx,servingCell,double(sixgr.util.structGet(capture,"Frame",NaN)), ...
            double(sixgr.util.structGet(capture,"Slot",NaN)),size(waveform,1),size(waveform,2), ...
            double(logical(sensing.EvidenceValid)));
        end

        function runtimeState = captureCommittedTxIQ(runtimeState,cfg,plan,direction,logSink)
        if ~(logical(sixgr.util.structGet(cfg,"outputs.rawIQCaptureEnabled",false)) && ...
                logical(sixgr.util.structGet(cfg,"outputs.saveRawWaveforms",false)))
            return;
        end
        direction = upper(string(direction));
        fieldName = char(direction);
        prior = sixgr.util.structGet(runtimeState,"TxIQCapture",struct());
        if isstruct(prior) && isfield(prior,fieldName) && ...
                logical(sixgr.util.structGet(prior.(fieldName),"Ok",false))
            return;
        end
        capture = sixgr.util.structGet(plan,"Result.TxWaveformCapture",struct());
        if ~(isstruct(capture) && isfield(capture,"Waveform") && ...
                ~isempty(capture.Waveform))
            error("sixgr:truth:MissingCommittedTxIQWaveform", ...
                "The first committed %s grant did not return its exact pre-channel Tx-IQ waveform.", ...
                direction);
        end
        grant = sixgr.util.structGet(plan,"GrantSnapshot",struct());
        capture.UEIndex = double(sixgr.util.structGet(plan,"UEIndex",NaN));
        capture.ServingCell = double(sixgr.util.structGet(grant,"ServingCell",NaN));
        capture.GrantContextId = string(sixgr.util.structGet(grant,"PHYGrantContextId", ...
            sixgr.util.structGet(grant,"GrantContextId","")));
        capture = sixgr.truth.bindCommittedTxIQScope(capture,direction);
        rootRunFolder = string(sixgr.util.structGet(cfg,"run.rootRunFolder",""));
        if strlength(strtrim(rootRunFolder)) == 0 || ~isfolder(rootRunFolder)
            error("sixgr:truth:MissingTxIQRunFolder", ...
                "Runtime Tx-IQ capture has no valid root run folder.");
        end
        artifact = sixgr.truth.exportRuntimeTxIQCapture( ...
            rootRunFolder,capture,cfg,direction);
        if ~isstruct(prior)
            prior = struct();
        end
        prior.(fieldName) = artifact;
        runtimeState.TxIQCapture = prior;
        logSink("INFO", ...
            "Exported committed %s Tx-IQ: samples=%d ports=%d rate_hz=%.6f hash=%s.", ...
            char(direction),artifact.SampleCount,artifact.PortCount,artifact.SampleRateHz, ...
            char(artifact.WaveformSHA256));
        end

        function T = ensureLinkTrialTable(Tin, direction, snr_dB, cfg)
        vars = {'Direction','SNR_dB','Seed','Frame','Slot','MCS','PRBs','Layers','ConfiguredLayers','ConfiguredTxAntennas','ConfiguredRxAntennas','Modulation','TargetCodeRate','TBSize_bits', ...
            'TBSInputModulation','TBSInputNumLayers','TBSInputNPRB','TBSInputNREPerPRB','TBSInputTargetCodeRate','TBSInputXOverhead','TBSInputSource', ...
            'PRBStart','AllocatedPRBCount','PRBCount','SymbolStart','NumSymbols', ...
            'ChannelModel','ChannelModelApplied','ChannelFadingApplied','DopplerHz','CRCPass','CRCApplicable','CRCOutcome', ...
            'HARQProcess','HARQNDI','HARQRV','HARQIsRetransmission','HARQFeedbackDueSlot', ...
            'RV','HARQProcessId','HarqID','HARQRound','NDI','IsRetransmission','NDIEpoch','TBId', ...
            'OriginalTBSBits','CurrentTBSBits','OriginalRateMatchedBits','CurrentRateMatchedBits', ...
            'EffectiveInitialCodeRate','EffectiveCurrentTxCodeRate','ShortIRRetx','CodeBlockLayoutHash','HARQContextHash','HARQContextStatus', ...
            'HARQCurrentDecodeOK','HARQCombinedDecodeOK','HARQCombiningApplied','HARQLLRCombiningGain_dB', ...
            'HARQPreviousLLRCount','HARQCurrentLLRCount','HARQCombinedLLRCount', ...
            'HARQCombinedLDPCDecodeAttempted','HARQCombinedLDPCParityAvailable', ...
            'HARQCombinedLDPCParityEvidenceJSON','HARQCombinedLDPCPolicyReceiptJSON', ...
            'DecoderIterations','EVM_rms','EVMReferenceSource','EVMValueStatus','NMSE_dB', ...
            'DetectionMetric','CorrelationPeak','DetectionThreshold','DetectionThresholdMode','DetectionMetricStatus', ...
            'DetectorPeakMetric','DetectorNoiseFloor','RxAntennaCount','PDPAverageNoiseFloor','PeakToThresholdRatio','PeakToNoiseRatio','PeakToNoiseRatio_dB', ...
            'CandidateCount','CandidatesAboveThreshold','TargetFalseAlarmProbability','ThresholdBackgroundComponent','ThresholdGlobalPeakComponent','PeakGuardFactor','DetectorPeakLagSamples', ...
            'NoiseOnlyDetectionMetric','MissedDetection','FalseAlarm','FalseAlarmCandidateScope','FalseAlarmCandidateCount','DTXFlag','DTXReason', ...
            'PreambleIndex','RequestedPreambleIndex','DetectedPreambleIndex','PreambleIndexFromPeak', ...
            'DetectedPreambleSet','DetectedPreambleSetAvailable','DetectionPopulationScope', ...
            'PRACHRootSequenceIndex','PRACHZeroCorrelationZone','PRACHConfigurationIndex','PRACHOccasionIndex','PRACHCarrierSlot', ...
            'MeasuredSINR_dB','WidebandCQI','CQIValueStatus','CQISelectionSINR_dB','CQIAppliedSINRMargin_dB','CQIDerivedMCS','CQIDerivedModulation','CQIDerivedTargetCodeRate', ...
            'LinkAdaptationMode','ConfiguredLinkAdaptationMode','LinkAdaptationDomain','ActualMCSSelectionMode','ConfiguredMCSSelectionPolicy','SchedulerGrantMCSSelectionMode', ...
            'CQISource','MCSSelectionSource','MCSValueStatus','OLLADomain','OuterLoopEnabled','InnerLoopEnabled','OuterLoopApplied','InnerLoopApplied','OLLADeltaDb','OLLADeltaMCS','OLLAAdjustedMCSBeforeCQICeiling','OLLABaseRequiredSINR_dB','OLLATargetRequiredSINR_dB','OLLAThresholdSource','OLLAUpdateCount','OLLAState','CalibrationProfile', ...
            'RequestedOperatingPointSource','CQITable','MCSTable', ...
            'RankIndicator','RankSelectionPolicy','RankSelectionSource','RankDecisionReason','RankDowngradeApplied','MaxSupportedLayers','PMI','CRI','PMIType', ...
            'MUMIMOEnabled','MUMIMOGroupSize','MUMIMOGroupId','MUMIMOPairingStatus', ...
            'MUMIMOPairingMetricSource','MUMIMOPairingMetricValue_dB','MUMIMOPairingWorstMetricValue_dB', ...
            'MUMIMOPairingEvidenceSource','MUMIMOPrecoderType','MUMIMORequiredLeakageThreshold_dB', ...
            'MUMIMODesiredSubspaceGain_dB','MUMIMORequiredMinimumDesiredGain_dB', ...
            'MUMIMOSpatialDesignStatus','MUMIMOSpatialDesignContractVersion','MUMIMOSpatialSignatureSubspaceMode','MUMIMOSpatialDesignEvidenceSource', ...
            'MUMIMOSpatialFilterMatrixSHA256','MUMIMOReceiveCombiningMatrixSHA256', ...
            'MUMIMOAdmissionReceiveCombiningMatrixSHA256','MUMIMOReceiveProcessingMode','MUMIMOReceiverAlgorithm', ...
            'MUMIMOReceiveProcessingApplied','MUMIMOReceiveProcessingStatus','MUMIMOReceiveProcessingSource', ...
            'MUMIMOReceiveProcessingModeApplied', ...
            'MUMIMOReceiveCombinerApplied','MUMIMOReceiveCombinerStatus','MUMIMOReceiveCombinerSource', ...
            'MUMIMOReceiveCombinerInputBranches','MUMIMOReceiveCombinerOutputBranches', ...
            'MUMIMOReceiveCombinerMatrixSHA256','MUMIMOReceiveCombinerInterferenceProjected', ...
            'MUMIMOReceiveCombinerFullObservationPreserved','MUMIMOReceiveCombinerIdentityResidual', ...
            'MUMIMOReceiverAlgorithmApplied', ...
            'MUMIMOHybridRFDesignPolicy','MUMIMOHybridRFDesignStatus', ...
            'HybridElementToPortMatrixSHA256','BaseHybridElementToPortMatrixSHA256','NumLogicalPorts','NumRFChains', ...
            'PMICodebookMode','CSIReportMode','CSIPayloadBitLength','CSIPayloadHex', ...
            'ConfiguredBeamSelectionStrategy','PrecoderSource','PrecodingMode','PrecodingApplicationStage', ...
            'PrecodingActive','ExplicitBeamWeightsApplied','TransformPrecodingApplied', ...
            'FrequencyHoppingApplied','FrequencyHoppingMode','FrequencyHoppingToolboxMode','SecondHopStartPRB','BeamformingApplied', ...
            'AppliedBeamIndexSet','AppliedPrecoderPMI','AppliedPrecoderPMIType','AppliedPrecoderCodebookMode','RequestedVsAppliedPrecoderPMIMatchStatus', ...
            'BeamSelectionStrategy','BeamSelectionAuthority','BeamSelectionPolicyType','BeamSelectionPolicyFixed','RequestedBeamIndexSet', ...
            'RequestedPrecoderPMI','RequestedPrecoderSource','AppliedPrecoderSource', ...
            'RequestedBeamTruthClassification','RequestedPrecoderPMITruthClassification', ...
            'AppliedBeamApplicationSource','AppliedBeamTruthClassification', ...
            'AppliedPrecoderPMIApplicationSource','AppliedPrecoderPMITruthClassification', ...
            'MCSAuthority','ModulationAuthority','GrantOperatingPointSource','AppliedOperatingPointSource', ...
            'PrecodingNumPorts','PrecodingNumLayers','PrecodingMatrixRows','PrecodingMatrixCols', ...
            'AppliedPrecoderMatrixSHA256','RequestedPrecoderSHA256','AppliedPrecoderSHA256','PrecoderDigestDomain','FrozenGrantContextId', ...
            'RequestedFormat','ResolvedFormat','FormatAdapted','FormatAdaptationReason','ControlResourceValidity','ControlResourceSource', ...
            'PUCCHFormat','PUCCHResourceId','PUCCHPRBSet','PUCCHPRBStart','PUCCHPRBCount','PUCCHSymbolStart','PUCCHNumSymbols', ...
            'PUCCHRECount','PUCCHDMRSRECount','ExpectedBitCount','DecodedBitCount','PUCCHExpectedBitCount','PUCCHDecodedBitCount', ...
            'UCIExpectedBitVector','UCIDecodedBitVector','UCIBitErrorVector','UCICodedBitCount','UCICRCBitCount','UCICRCApplicable', ...
            'UCIOnPUSCHApplied','UCIOnPUSCHSource','HARQACKBitCount','ExpectedHARQACKBits','DecodedHARQACKBits', ...
            'UCIOnPUSCHFeedbackGrantIds','UCIOnPUSCHFeedbackSourceSlots','UCIOnPUSCHFeedbackHARQIds', ...
            'UCIOnPUSCHFeedbackBitCount','UCIOnPUSCHEvidenceSource','HARQACKContentMatch','HARQACKDecodeStatus','HARQACKDecodeReason', ...
            'PUCCHControlSINR_dB','PUCCHReceiverEvidenceSource','PUCCHGridHash','PUCCHWaveformHash','ReceiverHestSINRApplicable', ...
            'FalseAlarmFlag','NoiseFalseAlarmFlag','CollisionFalseAlarmFlag','FalseAlarmClassification','BlockingFlag','BlindDecodeCount', ...
            'CandidatesAttempted','PDCCHReceiverTrialExecuted','DCICrcPass','PDCCHPayloadMatch','PDCCHCausalGrantDecodeOk', ...
            'PDCCHExpectedDCIBitCount','PDCCHDecodedDCIBitCount','PDCCHDCIBitsCompared','PDCCHDCIBitErrors', ...
            'PDCCHMissedDetection','PDCCHFalseAlarm','PDCCHErrFlag','TxCCEIndex','SelectedCCEIndex','GrantValid','NegativeExpectedOk', ...
            'PDCCHBlindSearchEnabled','PDCCHCandidatesAvailable','PDCCHCandidatesAttempted','PDCCHCandidateIndex','PDCCHTxCCEIndex','PDCCHSelectedCCEIndex', ...
            'PDCCHDCICrcRNTI','PDCCHScramblingRNTI','PDCCHEncodedBits','PDCCHRECount','PDCCHDMRSRECount', ...
            'PDCCHCandidateErrFlagVector','PDCCHCandidateDecodeOKVector','PDCCHCandidateSINRVector_dB','PDCCHCandidateRECountVector','PDCCHCandidateDMRSRECountVector', ...
            'PDCCHCRCDecodeSource','PDCCHBlindDecodeEvidenceSource','PDCCHCCE_REGMappingEvidence','PDCCHREGMappingAvailable', ...
            'PDCCHCORESETDuration','PDCCHCORESETStartSymbol','PDCCHAllocatedPRBSetJSON','PDCCHCORESETFrequencyResources','PDCCHSearchSpaceNumCandidates','PDCCHGridHash','PDCCHWaveformHash','PDCCHResourceHash', ...
            'ExecutedResourceIntervalsJSON','ExecutedResourceIntervalSource','ResourceGridPRBCount','ResourceSymbolsPerSlot', ...
            'ExecutedSampleIntervalsJSON','ExecutedSampleIntervalSource','NativeAllocationID', ...
            'NativeGridSHA256','NativeWaveformSHA256','NativeWaveformHashPlane', ...
            'AvailableCCECount','UsedCCECount', ...
            'NonOverlappedCCEUsage','AggregationLevel','DCISize_bits','ControlCapacityBits', ...
            'ControlCapacityUtilization','CORESETUtilization','ControlLatency_ms', ...
            'ChannelGain_dB','NoiseVariance','DesiredSignalPowerBeforeNoise','CompositeSignalPowerBeforeNoise','AppliedNoiseSNR_dB','NoiseVarianceSource', ...
            'ReplaySampleNoiseVariance','ReplayGridNoiseVariance','ReceiverInputSampleNoiseVariance', ...
            'PreEqualizationNoiseVariance','PostEqualizationNoiseVariance','SampleToGridNoiseVarianceGain', ...
            'ReplaySampleNoiseVarianceDomain','ReplayGridNoiseVarianceDomain','ReceiverInputSampleNoiseVarianceDomain', ...
            'DesiredSignalPowerBeforeNoiseDomain','CompositeSignalPowerBeforeNoiseDomain','SNRReferencePlane', ...
            'AppliedNoiseSNRSource','RequestedAWGNReferenceSNR_dB','SignalEnergyPerOccupiedRE', ...
            'PreEqualizationNoiseVarianceDomain','PostEqualizationNoiseVarianceDomain','LLRNoiseVarianceDomain', ...
            'NoiseVarianceUnit','NoiseVarianceNormalization','NoiseVarianceAliasOf','NoiseVarianceDomain', ...
            'ReplaySampleNoiseVarianceSource','ReplayGridNoiseVarianceSource','ReceiverInputSampleNoiseVarianceSource', ...
            'PreEqualizationNoiseVarianceSource','PostEqualizationNoiseVarianceSource','LLRNoiseVarianceSource', ...
            'NoiseVarStatus','NoiseVarSource','NoiseVarReason','NoiseVarStrictFailure', ...
            'ReceiverUsable','DecodeAttempted','DecodeUsable','StrictReceiverEvidenceOk','StrictOk','TruthStatus', ...
            'ExecutionProfile','ExecutionTaxonomy','ExecutionBackend','ApproximationMode', ...
            'CalibrationProvenance','StrictSchedulingOwnership','ConnectedStrictCertified', ...
            'ChannelEstimateAttempted','ChannelEstimateAvailable','ChannelEstimateSource', ...
            'ResourceExtractionAttempted','ResourceExtractionAvailable', ...
            'EqualizationAttempted','EqualizationAvailable','DLSCHDecodeAttempted','DLSCHDecodeAvailable', ...
            'ULSCHDecodeAttempted','ULSCHDecodeAvailable','LLRAvailable','LLRFinite','LLRScaleSource','LLRNoiseVariance', ...
            'PostEqSINRWidebanddB','PostEqSINRAvailable','PostEqSINRReceiverDerived', ...
            'SINRValidationStatus','SINRValidationReason','SINRComputationMethod','ConfiguredSNRLikeSourceRejected', ...
            'EqualizerType','EqualizerRequestedType','EqualizerEngine','EqualizerCovarianceFactorizationCount', ...
            'InterferenceCovarianceAvailable','InterferenceCovarianceSource','InterferenceCovarianceStatus', ...
            'DetectionAttempted','DetectionSuccess','DetectionUsable', ...
            'MeasurementAttempted','MeasurementUsable','FailureReason','TimingOffset_samples','TimingAdvance_samples','TimingAdvance_us','TAOutOfRangeFlag','TAOutOfRangeReason','TAMaxValid_samples','TAMaxValid_us','RankEstimate', ...
            'SRSOccupiedPRBCount','SRSCarrierPRBCount','SRSBandwidthFraction','SRSFrequencyPRBStart','SRSFrequencyPRBEnd','SRSBandwidthCoverageStatus', ...
            'SRS_RSRP_dBm','SRS_RSRP_dB_re_UnitOccupiedRE_Es','SRSRSRPPerReceiveAntenna_dBm','SRSAbsolutePowerStatus', ...
            'SRSAbsolutePowerAvailable','SRSAbsolutePowerAccuracyQualified', ...
            'SRSAbsolutePowerBranchMean_dBm','SRSAbsolutePowerSelectedBranch0','SRSAbsolutePowerResourceID', ...
            'SRSAbsolutePowerSource','SRSAbsolutePowerReferencePlane','SRSAbsolutePowerAggregation', ...
            'SRSAbsolutePowerEvidenceJSON','SRSAbsolutePowerEvidenceSHA256','SRSAbsolutePowerErrorIdentifier', ...
            'SRSRSRPReferenceAvailable','SRSRSRPReferenceStatus','SRSRSRPReferenceSource','SRSRSRPReferencePlane', ...
            'SRSRSRPReferencePower_dBm','SRSRSRPEstimationError_dB', ...
            'SRSRSRPReferenceEvidenceJSON','SRSRSRPReferenceEvidenceSHA256','SRSRSRPReferenceErrorIdentifier', ...
            'ChannelNMSEReferenceAvailable','ChannelNMSEReferenceStatus', ...
            'ChannelNMSEReferenceEvidenceJSON','ChannelNMSEReferenceEvidenceSHA256','ChannelNMSEReferenceErrorIdentifier', ...
            'CompositeDesiredLinkNMSE_dB','CompositeDesiredLinkRawNMSE_dB','CompositeDesiredLinkNMSESource', ...
            'SRSInterPortLeakageMatrixJSON','SRSInterPortLeakageWorst_dB','SRSInterPortLeakageStatus','SRSInterPortLeakageSource', ...
            'ConditionNumber_dB','NumRxAntennas','NumTxPorts','TxWaveformColumns','PhysicalTxAntennas','RxWaveformBranches','PhysicalRxAntennas','TxWaveformDomain','HybridElementDomainApplied', ...
            'SelectedBeamIndex','BestBeamIndex','BeamHit','TopKBeamHit','BeamCandidateCount', ...
            'SelectedBeamGain_dB','BestBeamGain_dB','BeamGainGap_dB', ...
            'ConfiguredPMI','ConfiguredCRI','BitErrors','BitsCompared','RawBER', ...
            'OfferedBits','GoodBits','Throughput_Mbps','OfferedThroughput_Mbps','Goodput_Mbps', ...
            'ComputeLatency_ms','ComputeLatencySource','ProcedureDelay_ms','AirInterfaceTTI_ms','AirInterfaceObservation_ms', ...
            'Latency_ms','DecodeLatency_ms','DecodeLatencySource','ReceiverPipelineLatency_ms','ReceiverPipelineLatencySource', ...
            'EarlyStopRate','DecoderComplexityUnits','NormalizedDecoderComplexity','AreaEfficiencyProxy', ...
            'NumCodeBlocks','CodeBlockLength_bits','SegmentationOccurred','SegmentationPaddingBits','TBCRCLength_bits','TBLengthWithCRC_bits','BaseGraph', ...
            'EncodedBits','RateMatchedBits','RateMatchPunctureBits','RateMatchRepetitionBits', ...
            'CBCRCBits','CodeBlockInputBits','SegmentationOverheadBits','InherentLDPCPuncturedBits', ...
            'LogicalTBID','TransmissionAttemptID','IdentityContractVersion','AttemptIdentitySource', ...
            'RateMatchEligibleBits','RateMatchUniqueSelectedBits','CodingAccountingVersion','RateMatchAccountingJSON', ...
            'MeasuredDMRSRECount','MeasuredDMRSAntennaRECount','MeasuredDMRSSymbolCount','MeasuredDMRSPortCount','MeasuredDMRSAntennaPortCount', ...
            'MeasuredDMRSCDMLengthFD','MeasuredDMRSCDMLengthTD', ...
            'MeasuredRateMatchedCodewordLLRBits','MeasuredRateRecoveredLLRBits','MeasuredRateRecoveredFiniteLLRCount','MeasuredRateRecoverFillerBits', ...
            'MeasuredRateRecoveredCodeBlockCount','MeasuredRateRecoveredCodeBlockLength_bits','MeasuredRateRecoverNrefBits', ...
            'MeasuredLDPCDecoderMeanIterations','MeasuredLDPCDecoderMinIterations','MeasuredLDPCDecoderMaxIterations','MeasuredLDPCParityCheckFailures', ...
            'MeasuredLDPCParityCodewordCount','MeasuredLDPCParityObservedCodewordCount','MeasuredLDPCParityCheckCount', ...
            'MeasuredLDPCParityCodeBlockCount','MeasuredLDPCParityFailedCodeBlockCount','MeasuredLDPCParityAvailable', ...
            'MeasuredLDPCParityContractVersion','MeasuredLDPCParityStage','MeasuredLDPCParityScope','MeasuredLDPCParityEvidenceJSON', ...
            'MeasuredCodeBlockDecodeErrorCount','MeasuredCodeBlockDecodeCount','MeasuredCodeBlockDecodeFailureRate', ...
            'MeasuredCodeBlockCRCErrorCount','MeasuredCodeBlockCRCCount','MeasuredCodeBlockCRCFailureRate', ...
            'MeasuredLDPCDecoderAlgorithm','MeasuredLDPCDecoderEngine','MeasuredLDPCIterationVector','MeasuredLDPCParityCheckVector','MeasuredCodeBlockDecodeErrorVector','MeasuredCodeBlockCRCErrorVector', ...
            'CodeBlockErrors','CodeBlockCount','CodeBlockBLER','CBGErrors','CBGCount','CBGBLER', ...
            'PAPR_dB','PAPRMeasurementJSON','PeakClippingEvents','SymbolErrors','SymbolsCompared','SymbolErrorRate', ...
            'ResidualInterferencePower_dB', ...
            'DecisionResidualSymbolPower_dB','DecisionResidualEnergy','DecisionReferenceEnergy', ...
            'DecisionResidualSampleCount','DecisionResidualRatio_dB','ResidualMetricDefinition', ...
            'HestCoarseReconstructionErrorRatio_dB','HestCoarseReconstructionErrorEnergy', ...
            'HestCoarseReconstructionReferenceEnergy','HestMagnitudeStd_dB','HestDiagnosticSampleCount', ...
            'HestDiagnosticDefinition','HestMagnitudeDefinition','ChannelAgingDiagnosticDefinition', ...
            'ResourceSetAccountingVersion','GrossAllocationRE','MappedDataBaseRE', ...
            'PilotOccupiedBaseRE','ExplicitReservedBaseRE','UnoccupiedByThisChannelRE','NonDataBaseRE', ...
            'PilotOverGrossFraction','NonDataOverGrossFraction','PilotOverDataPlusPilotFraction', ...
            'UnoccupiedByThisChannelOverGrossFraction','ResourceSetAccountingStatus','ResourceSetAccountingDefinition', ...
            'LLRMeanAbs','LLRStdAbs','LLRImbalance','ModulationMappingSensitivity', ...
            'ShapingRateLoss','DistributionMatchingLatency_ms','HighOrderRobustness', ...
            'DetectorComplexityUnits_Modulation','DataRECount','DataRECountPerLayer','TotalDataRECount','ModulationOrderQm','ComputedE_TS38212','RateMatchedBitsDelta_TS38212','DMRSRECount','PTRSRECount','RSOverheadFraction', ...
            'PTRSConfiguredEnabled','PTRSCPECorrectionConfigured','PTRSCPECorrectionApplied','PTRSCPECorrectionSymbols','PTRSMeanCPE_deg', ...
            'PTRSCPECorrectionReason','PTRSCPECorrectionStatus','PTRSReceiverEvidenceSource', ...
            'InjectedCFO_Hz','EstimatedCFO_PreCorrection_Hz','ResidualCFO_PostCorrection_Hz', ...
            'EstimatedCFO_Hz','TrueCFO_Hz','CFOError_Hz', ...
            'InjectedTimingOffset_samples','EstimatedTimingOffset_PreCorrection_samples','ResidualTimingError_PostCorrection_samples', ...
            'TrueTimingOffset_samples','TimingError_samples', ...
            'IQImbalanceConfigured','IQImbalanceApplied','IQImbalanceModel', ...
            'ConfiguredIQGainImbalance_dB','ConfiguredIQPhaseImbalance_deg', ...
            'IQImbalanceMirrorPowerRatio_dB','IQImbalanceImageRejection_dB', ...
            'IQImbalanceIQPowerRatio_dB','IQImbalanceIQCorrelation', ...
            'IQImbalanceEstimatedAlphaAbs','IQImbalanceEstimatedBetaAbs', ...
            'IQImbalanceMeasurementSource','IQImbalanceMeasurementStatus', ...
            'InjectedDoppler_Hz','EstimatedDopplerHz','DopplerError_Hz','PhaseTrackingError_deg','QCLAccuracy', ...
            'ChannelAgingLoss_dB','InterpolationLoss_dB','MismatchSensitivity_dB','AcquisitionTime_ms','TrackingFailureProbability', ...
            'Status','Crash', ...
            'LinkAdaptationApplied','LinkAdaptationScheduled','FixedAnchorMode','AdaptiveMode','IsWarmupFrame','Notes', ...
            'SFN','UEID','UEIndex','RNTI','BaseStationID','AllocatedPRBCount','PRBStart','MCSIndex','Rank', ...
            'ConfiguredSNR_dB','ConfiguredSNRSource','SNRValueRole','AppliedAWGNSNR_dB','AppliedAWGNSNRSource', ...
            'PRACHSNRCalibrationStatus','PRACHSNRCalibrationSource','PRACHSNRCalibrationError_dB','PRACHNoiseReferencePower', ...
            'ReceiverHestSINR_dB','ReceiverHestSINRSource','ReceiverHestSINRValueRole','ReceiverHestSINRValueStatus','ReceiverHestSINRNAReason', ...
            'PostEqSINR_dB','PostEqSINRSource','PostEqSINRValueRole','PostEqSINRValueStatus','PostEqSINRNAReason','PostEqSINRPerLayer_dB', ...
            'ResidualInterLayerPowerMean','ResidualInterLayerPowerPerLayer','ResidualInterLayerPowerSource','ResidualInterLayerPowerStatus', ...
            'EVMProxySINR_dB','EVMProxySINRSource','EVMProxySINRValueRole','EVMProxySINRValueStatus','EVMProxySINRNAReason', ...
            'DecoderTruthProxySINR_dB','DecoderTruthProxySINRSource','DecoderTruthProxySINRValueRole','DecoderTruthProxySINRValueStatus','DecoderTruthProxySINRNAReason', ...
            'SINRValueRole','SINRSource','SINRValueStatus','SINRValueDefinition', ...
            'MeasuredTrialSINR_dB','MeasuredTrialSINRSource','MeasuredTrialSINRValueRole','MeasuredTrialSINRValueStatus','MeasuredTrialSINRNAReason', ...
            'SINRMeasurementDomain','PowerReferencePlane', ...
            'PUSCHSchedulingSINRAnchor_dB','PUSCHSchedulingSINRAnchorSource', ...
            'PUSCHSchedulingSINRAnchorPowerReferencePlane','PUSCHSchedulingSINRAnchorValueStatus', ...
            'PredictedPUSCHReferenceSignalPower','PredictedPUSCHDisturbancePower', ...
            'PUSCHToSRSReferenceEnergyRatio','PUSCHToSRSReferenceEnergySource', ...
            'ReferenceTxPower_dBm','ReferenceTxPowerSource','ServingRxPower_dBm','ServingRxPowerSource', ...
            'ThermalNoisePower_dBm','NoisePowerSource','NoiseFigure_dB','NoiseBandwidth_Hz', ...
            'PowerContextAmplitudeUnit','PowerContextTotalTxPower_dBm','PowerContextTxGain_dB','PowerContextRxGain_dB','PowerContextAdditionalLoss_dB', ...
            'CellTotalTxPower_dBm','EndpointPowerBudget_dBm','ConcurrentTransmitterGrantCount','GrantPowerFraction','GrantTargetTxPower_dBm', ...
            'ScheduledPowerPolicy','ScheduledPowerAuthority','SharedCellBudgetApplied', ...
            'PowerNormalizationPolicy','PowerNormalizationSource','PowerNormalizationGridSource', ...
            'PowerNormalizationGridSubcarrierCount','PowerNormalizationGridActiveSymbolCount', ...
            'PowerNormalizationGridMeanEnergyPerRE','FullBWPActivityFactor', ...
            'ReferenceInputPower_dBm','ReferenceOutputPower_dBm','ActualEmittedPower_dBm', ...
            'ReferenceInputPower_dB_re_UnitOccupiedRE_Es','ReferenceOutputPower_dB_re_UnitOccupiedRE_Es', ...
            'ActualEmittedPower_dB_re_UnitOccupiedRE_Es','PowerContextTotalTxPower_dB_re_UnitOccupiedRE_Es', ...
            'TransmitPowerEvidenceAvailable','TransmitPowerPhysicalApplicable','TransmitPowerReferencePlane', ...
            'ActualEmittedPowerBackoffFromBudget_dB','PowerClosureError_dB','PowerConversionEquation', ...
            'TxRFExecutionStatus','TxRFStageOrder','TxRFAppliedStageCount', ...
            'CompositeReceiverFrontEndApplied','CompositeReceiverFrontEndStatus', ...
            'PUCCHAppliedTxPower_dBm','PUCCHMeasuredTxOutputPower_dBm','PUCCHTxPowerClosureError_dB', ...
            'PUCCHWaveformAmplitudeUnit','PUCCHTxOutputWaveformHash', ...
            'AbsolutePowerReferencePlane','SamplePowerReferencePlane','InterferencePowerReferencePlane', ...
            'LargeScaleSINR_dB','LargeScaleSINRSource', ...
            'ServingRSRP_dBm','ServingRSRPSource', ...
            'CSI_RSRP_dB','CSI_RSRPSource', ...
            'AppliedLargeScaleGain_dB','AppliedLargeScaleLoss_dB','AppliedBasePathloss_dB','AppliedPathloss_dB', ...
            'AppliedShadowFading_dB','AppliedO2I_dB','AppliedLargeScaleGainSource', ...
            'ChannelComplianceMode','PathlossModelSource','PathlossComplianceStatus','FallbackUsedForPathloss', ...
            'O2IModelSource','O2IComplianceStatus','O2IComplianceReason', ...
            'LOSProbabilitySource','LOSComplianceStatus','LOSComplianceReason', ...
            'TimingEstimateUsed','UseIdealTimingSync','AppliedTimingCorrection_samples','TimingEstimateApplicationPolicy','TimingEstimateStatus','TimingEstimateWasClipped', ...
            'InterferenceMode','InterferenceContributorCount','InterferenceAggregatedRxPower_dBm', ...
            'InterferencePowerSource','FullInterfererChannelTruthUsed', ...
            'CFOEstimateAvailability','CFOErrorDefinition','CFOValueStatus', ...
            'TimingEstimateAvailability','TimingErrorDefinition','TimingValueStatus','TimingReferenceSource','TimingMetricRole', ...
            'LargeScaleSINRValueStatus','LargeScaleSINRFinalizedFlag','LargeScaleSINRNAReason', ...
            'PrimaryTruthValueStatus','SecondaryFieldGapFlag','SecondaryFieldGapCount','SecondaryFieldGapReason', ...
            'RowLifecycleState','PartialRowFlag','FinalizedFlag','FallbackFlag','PlaceholderFlag','NAReason', ...
            'RunUUID','RunTag','ScenarioID','RunnerProfile','ConfigHash','SourceArtifact','SourceTable','ArtifactClass','SemanticState', ...
            'CountsTowardCoverage','MachineReadable','HumanReadable', ...
            'InterfererBeamformingAppliedCount','InterfererExplicitBeamWeightCount','InterfererTransformPrecodingCount', ...
            'InterfererPrecoderSourceSet','InterfererPrecodingModeSet','InterfererBeamIndexSetSummary', ...
            'DopplerSourceMode','DopplerValueRole', ...
            'PBCHGatingActive','PRACHGatingActive','PDCCHGatingActive','SRSGatingActive', ...
            'ControlEligible','ControlDecodeOk','PDCCHCausalGrantDecodeOk','PDCCHControlFailureReason', ...
            'PDCCHControlEvidenceSource','ControlDecodeSource','GrantControlState', ...
            'CellAcquisitionState','AccessState','SRSValidityState','CSIValidityState','SRSValid','SRSAgeSlots', ...
            'TRSGatingActive','TRSValidityState','TrackingEligibility','TRSAgeSlots','LastSuccessfulTRSSlot','LastEstimatedTRSDopplerHz', ...
            'TRSStateSource','TRSRuntimeConsumer','TRSInfluencedDecision','TRSInfluenceDefinition','TRSReceiverIntegrationStatus','TRSReceiverIntegrationBlocker', ...
            'GrantContextId','PDCCHGrantBindingRequired','PDCCHGrantBindingOk','PDCCHGrantBindingStatus','PDCCHGrantBindingFailureCode', ...
            'PDCCHGrantDCIId','PDCCHGrantDCIFieldsHash','PDCCHGrantFieldsHash','PDCCHGrantSearchSpaceId','PDCCHGrantCORESETId', ...
            'PDCCHGrantAggregationLevel','PDCCHGrantCandidateIndex','PDCCHGrantDCIFormat','GrantWorkerSafe','GrantSharedStateCommitMode', ...
            'BSAntennaArrayClass','BSAntennaElementClass','BSAntennaArrayType', ...
            'BSAntennaRows','BSAntennaCols','BSAntennaElements','BSAntennaSpacingH_lambda','BSAntennaSpacingV_lambda', ...
            'BSAntennaPanelRows','BSAntennaPanelCols','BSAntennaPanelCount','BSAntennaPolarizationAngles_deg', ...
            'BSAntennaPolarization','BSAntennaAzimuth_deg','BSAntennaNumPorts','BSAntennaHasPhasedArrayObject', ...
            'UEAntennaArrayClass','UEAntennaElementClass','UEAntennaArrayType', ...
            'UEAntennaRows','UEAntennaCols','UEAntennaElements','UEAntennaSpacingH_lambda','UEAntennaSpacingV_lambda', ...
            'UEAntennaPanelRows','UEAntennaPanelCols','UEAntennaPanelCount','UEAntennaPolarizationAngles_deg', ...
            'UEAntennaPolarization','UEAntennaHeading_deg','UEAntennaNumPorts','UEAntennaHasPhasedArrayObject', ...
            'AntennaConfigSource','RuntimeAntennaObjectSource','AntennaRuntimeObjectCreated', ...
            'ChannelArrayModel','ChannelObjectSource','ChannelObjectClass','ChannelArrayHandlingStatus','ChannelArrayHandlingBlocker', ...
            'ChannelGeometryCouplingLevel','GeometryAdapterType','GeometryAdapterSource','GeometryAdapterLimitation','GeometryAdapterPortMapping', ...
            'ChannelUsesCountOnlyAntennaModel','ChannelUsesSameRuntimeAntennaAssumptions', ...
            'ElementPatternChannelApplicability','AntennaChannelConsistencyStatus','AntennaChannelConsistencyReason', ...
            'InterferenceChannelObjectSource','InterferenceChannelObjectClass','InterferenceChannelArrayHandlingStatus','InterferenceChannelArrayHandlingBlocker', ...
            'InterferenceUsesSameRuntimeAntennaAssumptions','InterferencePathUsesSameArrayAssumptions', ...
            'PropagationDistance_m','GeometricPropagationDelay_s','DominantPathDelay_s','ChannelFilterDelay_s','PropagationDelay_s', ...
            'ToD_s','ToA_s','ToAEstimate_s', ...
            'ToDSource','ToASource','ToAEstimateSource','ChannelDelaySource','AntennaGeometrySource', ...
            'RuntimeTraceSource','AntennaEvidenceSource','SameFlowEvidenceSource'};
        if nargin < 1 || ~istable(Tin)
            Tin = table();
        end
        if isempty(Tin)
            T = sixgr.truth.SharedDataCompletionRuntime.emptyLinkTrialTable(0);
            return;
        end
        T = Tin;
        for i = 1:numel(vars)
            v = vars{i};
            if ~ismember(v, T.Properties.VariableNames)
                        switch v
                            case {'Direction','ChannelModel','ChannelModelApplied','Status','Notes','PMIType','PMICodebookMode','CSIReportMode','Modulation', ...
                                    'EVMValueStatus','EVMReferenceSource', ...
                                    'TBSInputModulation','TBSInputSource','PTRSCPECorrectionReason','PTRSCPECorrectionStatus','PTRSReceiverEvidenceSource', ...
                                    'CQIDerivedModulation','LinkAdaptationMode','ConfiguredLinkAdaptationMode','LinkAdaptationDomain','ActualMCSSelectionMode','ConfiguredMCSSelectionPolicy', ...
                                    'SchedulerGrantMCSSelectionMode','CQISource','CQIValueStatus','MCSSelectionSource','MCSValueStatus','OLLADomain','OLLAState','CalibrationProfile', ...
                                    'RequestedOperatingPointSource','CQITable','MCSTable','CSIPayloadHex', ...
                                    'CRCOutcome','NoiseVarianceSource','NoiseVarStatus','NoiseVarSource','NoiseVarReason','FailureReason','TAOutOfRangeReason', ...
                                    'ReplaySampleNoiseVarianceDomain','ReplayGridNoiseVarianceDomain','ReceiverInputSampleNoiseVarianceDomain', ...
                                    'DesiredSignalPowerBeforeNoiseDomain','CompositeSignalPowerBeforeNoiseDomain','SNRReferencePlane','AppliedNoiseSNRSource', ...
                                    'PreEqualizationNoiseVarianceDomain','PostEqualizationNoiseVarianceDomain','LLRNoiseVarianceDomain', ...
                                    'NoiseVarianceUnit','NoiseVarianceNormalization','NoiseVarianceAliasOf','NoiseVarianceDomain', ...
                                    'ReplaySampleNoiseVarianceSource','ReplayGridNoiseVarianceSource','ReceiverInputSampleNoiseVarianceSource', ...
                                    'PreEqualizationNoiseVarianceSource','PostEqualizationNoiseVarianceSource','LLRNoiseVarianceSource', ...
                                    'TruthStatus','ChannelEstimateSource','LLRScaleSource','ComputeLatencySource','DecodeLatencySource','ReceiverPipelineLatencySource', ...
                                    'SRSAbsolutePowerStatus','SRSRSRPPerReceiveAntenna_dBm', ...
                                    'SRSAbsolutePowerSource','SRSAbsolutePowerReferencePlane','SRSAbsolutePowerAggregation', ...
                                    'SRSAbsolutePowerEvidenceJSON','SRSAbsolutePowerEvidenceSHA256','SRSAbsolutePowerErrorIdentifier', ...
                                    'SRSRSRPReferenceStatus','SRSRSRPReferenceSource','SRSRSRPReferencePlane', ...
                                    'SRSRSRPReferenceEvidenceJSON','SRSRSRPReferenceEvidenceSHA256','SRSRSRPReferenceErrorIdentifier', ...
                                    'ChannelNMSEReferenceStatus','ChannelNMSEReferenceEvidenceJSON', ...
                                    'ChannelNMSEReferenceEvidenceSHA256','ChannelNMSEReferenceErrorIdentifier','CompositeDesiredLinkNMSESource', ...
                                    'SINRValidationStatus','SINRValidationReason','SINRComputationMethod', ...
                                    'EqualizerType','EqualizerRequestedType','EqualizerEngine','InterferenceCovarianceSource','InterferenceCovarianceStatus', ...
                                    'ConfiguredSNRSource','SNRValueRole','AppliedAWGNSNRSource','PRACHSNRCalibrationStatus','PRACHSNRCalibrationSource', ...
                                    'ReceiverHestSINRSource','ReceiverHestSINRValueRole','ReceiverHestSINRValueStatus','ReceiverHestSINRNAReason', ...
                                    'PostEqSINRSource','PostEqSINRValueRole','PostEqSINRValueStatus','PostEqSINRNAReason','PostEqSINRPerLayer_dB', ...
                                    'ResidualInterLayerPowerPerLayer','ResidualInterLayerPowerSource','ResidualInterLayerPowerStatus', ...
                                    'EVMProxySINRSource','EVMProxySINRValueRole','EVMProxySINRValueStatus','EVMProxySINRNAReason', ...
                                    'DecoderTruthProxySINRSource','DecoderTruthProxySINRValueRole','DecoderTruthProxySINRValueStatus','DecoderTruthProxySINRNAReason', ...
                                    'SINRValueRole','SINRSource','SINRValueStatus','SINRValueDefinition', ...
                                    'MeasuredTrialSINRSource','MeasuredTrialSINRValueRole','MeasuredTrialSINRValueStatus','MeasuredTrialSINRNAReason', ...
                                    'ReferenceTxPowerSource','ServingRxPowerSource','NoisePowerSource', ...
                                    'PowerNormalizationPolicy','PowerNormalizationSource', ...
                                    'PowerNormalizationGridSource','PowerConversionEquation','TransmitPowerReferencePlane', ...
                                    'AbsolutePowerReferencePlane','SamplePowerReferencePlane','InterferencePowerReferencePlane', ...
                                    'LargeScaleSINRSource','ServingRSRPSource','CSI_RSRPSource', ...
                                    'AppliedLargeScaleGainSource','ChannelComplianceMode','PathlossModelSource','PathlossComplianceStatus', ...
                                    'O2IModelSource','O2IComplianceStatus','O2IComplianceReason', ...
                                    'LOSProbabilitySource','LOSComplianceStatus','LOSComplianceReason', ...
                                    'IQImbalanceModel','IQImbalanceMeasurementSource','IQImbalanceMeasurementStatus', ...
                                    'InterferenceMode','InterferencePowerSource','DopplerSourceMode','DopplerValueRole', ...
                                    'GrantControlState','PDCCHControlFailureReason','PDCCHControlEvidenceSource','ControlDecodeSource', ...
                                    'CellAcquisitionState','AccessState','SRSValidityState','CSIValidityState','TRSValidityState','SRSBandwidthCoverageStatus', ...
                                    'ConfiguredBeamSelectionStrategy','PrecoderSource','PrecodingMode','PrecodingApplicationStage','FrequencyHoppingMode','FrequencyHoppingToolboxMode', ...
                                    'MUMIMOPairingStatus','MUMIMOPairingMetricSource','MUMIMOPairingEvidenceSource','MUMIMOPrecoderType', ...
                                    'MUMIMOSpatialDesignStatus','MUMIMOSpatialDesignContractVersion','MUMIMOSpatialSignatureSubspaceMode','MUMIMOSpatialDesignEvidenceSource', ...
                                    'MUMIMOSpatialFilterMatrixSHA256','MUMIMOReceiveCombiningMatrixSHA256', ...
                                    'MUMIMOAdmissionReceiveCombiningMatrixSHA256','MUMIMOReceiveProcessingMode','MUMIMOReceiverAlgorithm', ...
                                    'MUMIMOReceiveProcessingStatus','MUMIMOReceiveProcessingSource','MUMIMOReceiveProcessingModeApplied', ...
                                    'MUMIMOReceiveCombinerStatus','MUMIMOReceiveCombinerSource','MUMIMOReceiveCombinerMatrixSHA256', ...
                                    'MUMIMOReceiverAlgorithmApplied', ...
                                    'MUMIMOHybridRFDesignPolicy','MUMIMOHybridRFDesignStatus', ...
                                    'HybridElementToPortMatrixSHA256','BaseHybridElementToPortMatrixSHA256','AppliedPrecoderMatrixSHA256', ...
                                    'RequestedPrecoderSHA256','AppliedPrecoderSHA256','PrecoderDigestDomain','FrozenGrantContextId', ...
                                    'AppliedBeamIndexSet','AppliedPrecoderPMIType','AppliedPrecoderCodebookMode','RequestedVsAppliedPrecoderPMIMatchStatus', ...
                                    'BeamSelectionStrategy','BeamSelectionAuthority','BeamSelectionPolicyType', ...
                                    'RequestedBeamIndexSet','RequestedPrecoderSource','AppliedPrecoderSource', ...
                                    'RequestedBeamTruthClassification','RequestedPrecoderPMITruthClassification', ...
                                    'AppliedBeamApplicationSource','AppliedBeamTruthClassification', ...
                                    'AppliedPrecoderPMIApplicationSource','AppliedPrecoderPMITruthClassification', ...
                                    'MCSAuthority','ModulationAuthority','GrantOperatingPointSource','AppliedOperatingPointSource', ...
                                    'MeasuredLDPCDecoderAlgorithm','MeasuredLDPCDecoderEngine','MeasuredLDPCIterationVector','MeasuredLDPCParityCheckVector','MeasuredCodeBlockDecodeErrorVector','MeasuredCodeBlockCRCErrorVector', ...
                                    'MeasuredLDPCParityContractVersion','MeasuredLDPCParityStage','MeasuredLDPCParityScope','MeasuredLDPCParityEvidenceJSON', ...
                                    'HARQCombinedLDPCParityEvidenceJSON','HARQCombinedLDPCPolicyReceiptJSON', ...
                                    'FormatAdaptationReason','ControlResourceSource','PUCCHResourceId','PUCCHPRBSet','UCIExpectedBitVector','UCIDecodedBitVector','UCIBitErrorVector', ...
                                    'UCIOnPUSCHSource','ExpectedHARQACKBits','DecodedHARQACKBits', ...
                                    'UCIOnPUSCHFeedbackGrantIds','UCIOnPUSCHFeedbackSourceSlots','UCIOnPUSCHFeedbackHARQIds', ...
                                    'UCIOnPUSCHEvidenceSource','HARQACKDecodeStatus','HARQACKDecodeReason', ...
                                    'PUCCHReceiverEvidenceSource','PUCCHGridHash','PUCCHWaveformHash', ...
                                    'PDCCHCandidateErrFlagVector','PDCCHCandidateDecodeOKVector','PDCCHCandidateSINRVector_dB','PDCCHCandidateRECountVector','PDCCHCandidateDMRSRECountVector', ...
                                    'PDCCHCRCDecodeSource','PDCCHBlindDecodeEvidenceSource','PDCCHCCE_REGMappingEvidence','PDCCHCORESETFrequencyResources','PDCCHSearchSpaceNumCandidates', ...
                                    'PDCCHGridHash','PDCCHWaveformHash','PDCCHResourceHash', ...
                                    'CFOEstimateAvailability','CFOErrorDefinition','CFOValueStatus', ...
                                    'TimingEstimateAvailability','TimingErrorDefinition','TimingValueStatus','TimingReferenceSource','TimingMetricRole','TimingEstimateApplicationPolicy','TimingEstimateStatus', ...
                                    'LargeScaleSINRValueStatus','LargeScaleSINRNAReason','PrimaryTruthValueStatus','SecondaryFieldGapReason','RowLifecycleState','NAReason', ...
                                    'RunUUID','RunTag','ScenarioID','RunnerProfile','ConfigHash','SourceArtifact','SourceTable','ArtifactClass','SemanticState', ...
                                    'InterfererPrecoderSourceSet','InterfererPrecodingModeSet','InterfererBeamIndexSetSummary', ...
                                    'TRSStateSource','TRSRuntimeConsumer','TRSInfluenceDefinition','TRSReceiverIntegrationStatus','TRSReceiverIntegrationBlocker', ...
                                    'GrantContextId','PDCCHGrantBindingStatus','PDCCHGrantBindingFailureCode','PDCCHGrantDCIId', ...
                                    'PDCCHGrantDCIFieldsHash','PDCCHGrantFieldsHash','PDCCHGrantDCIFormat', ...
                                    'GrantSharedStateCommitMode','TBId','CodeBlockLayoutHash','HARQContextHash','HARQContextStatus', ...
                                    'BSAntennaArrayClass','BSAntennaElementClass','BSAntennaArrayType','BSAntennaPolarization', ...
                                    'BSAntennaPolarizationAngles_deg','UEAntennaPolarizationAngles_deg', ...
                                    'UEAntennaArrayClass','UEAntennaElementClass','UEAntennaArrayType','UEAntennaPolarization', ...
                                    'AntennaConfigSource','RuntimeAntennaObjectSource','TxWaveformDomain','ChannelArrayModel','ChannelObjectSource','ChannelObjectClass', ...
                                    'ChannelArrayHandlingStatus','ChannelArrayHandlingBlocker','ChannelGeometryCouplingLevel','GeometryAdapterType','GeometryAdapterSource','GeometryAdapterLimitation','GeometryAdapterPortMapping', ...
                                    'ElementPatternChannelApplicability','AntennaChannelConsistencyStatus','AntennaChannelConsistencyReason', ...
                                    'InterferenceChannelObjectSource','InterferenceChannelObjectClass','InterferenceChannelArrayHandlingStatus','InterferenceChannelArrayHandlingBlocker', ...
                                    'ToDSource','ToASource','ToAEstimateSource','ChannelDelaySource','AntennaGeometrySource', ...
                                    'RuntimeTraceSource','AntennaEvidenceSource','SameFlowEvidenceSource'}
                                T.(v) = strings(height(T),1);
                            case 'Crash'
                                T.(v) = false(height(T),1);
                            case {'LinkAdaptationApplied','LinkAdaptationScheduled','FixedAnchorMode','AdaptiveMode','OuterLoopEnabled','InnerLoopEnabled','OuterLoopApplied','InnerLoopApplied', ...
                                    'IsWarmupFrame','TimingEstimateUsed','UseIdealTimingSync','TimingEstimateWasClipped', ...
                                    'ShortIRRetx', ...
                                    'CRCApplicable','NoiseVarStrictFailure','ReceiverUsable','DecodeAttempted','DecodeUsable','StrictReceiverEvidenceOk','StrictOk', ...
                                    'ChannelEstimateAttempted','ChannelEstimateAvailable','ResourceExtractionAttempted','ResourceExtractionAvailable', ...
                                    'EqualizationAttempted','EqualizationAvailable','DLSCHDecodeAttempted','DLSCHDecodeAvailable', ...
                                    'ULSCHDecodeAttempted','ULSCHDecodeAvailable','LLRAvailable','LLRFinite','PostEqSINRAvailable','PostEqSINRReceiverDerived', ...
                                    'ConfiguredSNRLikeSourceRejected','InterferenceCovarianceAvailable','DetectionAttempted','DetectionSuccess','DetectionUsable', ...
                                    'MeasurementAttempted','MeasurementUsable','TAOutOfRangeFlag', ...
                                    'SRSAbsolutePowerAvailable','SRSAbsolutePowerAccuracyQualified', ...
                                    'SRSRSRPReferenceAvailable','ChannelNMSEReferenceAvailable', ...
                                    'PBCHGatingActive','PRACHGatingActive','PDCCHGatingActive','SRSGatingActive','TRSGatingActive','ControlEligible','ControlDecodeOk','PDCCHCausalGrantDecodeOk','SRSValid', ...
                                    'TrackingEligibility','TRSInfluencedDecision', ...
                                    'IQImbalanceConfigured','IQImbalanceApplied', ...
                                    'FallbackUsedForPathloss', ...
                                    'FullInterfererChannelTruthUsed','PrecodingActive','ExplicitBeamWeightsApplied','TransformPrecodingApplied','FrequencyHoppingApplied','BeamformingApplied','ChannelFadingApplied', ...
                                    'FormatAdapted','ControlResourceValidity','UCICRCApplicable','ReceiverHestSINRApplicable', ...
                                    'UCIOnPUSCHApplied','HARQACKContentMatch', ...
                                    'DCICrcPass','PDCCHPayloadMatch','PDCCHMissedDetection','PDCCHFalseAlarm', ...
                                    'GrantValid','NegativeExpectedOk','PDCCHBlindSearchEnabled','PDCCHREGMappingAvailable', ...
                                    'MUMIMOEnabled','MUMIMOReceiveProcessingApplied','MUMIMOReceiveCombinerApplied','MUMIMOReceiveCombinerInterferenceProjected', ...
                                    'MUMIMOReceiveCombinerFullObservationPreserved', ...
                                    'BeamSelectionPolicyFixed','LargeScaleSINRFinalizedFlag','SecondaryFieldGapFlag','PartialRowFlag','FinalizedFlag','FallbackFlag','PlaceholderFlag', ...
                                    'CountsTowardCoverage','MachineReadable','HumanReadable', ...
                                    'TransmitPowerEvidenceAvailable','TransmitPowerPhysicalApplicable', ...
                                    'GrantWorkerSafe','PDCCHGrantBindingRequired','PDCCHGrantBindingOk', ...
                                    'BSAntennaHasPhasedArrayObject','UEAntennaHasPhasedArrayObject', ...
                                    'AntennaRuntimeObjectCreated','HybridElementDomainApplied','ChannelUsesCountOnlyAntennaModel','ChannelUsesSameRuntimeAntennaAssumptions', ...
                                    'InterferenceUsesSameRuntimeAntennaAssumptions','InterferencePathUsesSameArrayAssumptions'}
                                T.(v) = false(height(T),1);
                            otherwise
                                T.(v) = NaN(height(T),1);
                        end
            end
        end
        % `vars` is the mandatory canonical prefix, not an allow-list.  Trial
        % producers append measured receiver, channel-realization, RF-chain and
        % feature-specific evidence over time.  Projecting onto only `vars` used to
        % discard those real runtime measurements at the coupled-runtime boundary.
        % Preserve every producer column after the stable canonical prefix so the
        % exported row remains an auditable record of the exact Tx/channel/Rx path.
        noiseDefaults=sixgr.link.absoluteReferenceNoisePublication();
        for noiseField=string(fieldnames(noiseDefaults)).'
            if ~ismember(noiseField,string(T.Properties.VariableNames))
                T.(noiseField)=repmat(noiseDefaults.(noiseField),height(T),1);
            end
        end
        extraVars = setdiff(string(T.Properties.VariableNames), string(vars), "stable");
        T = T(:, [vars, cellstr(extraVars)]);
        if all(strlength(string(T.Direction)) == 0)
            T.Direction(:) = string(direction);
        end
        if all(~isfinite(double(T.SNR_dB)))
            T.SNR_dB(:) = double(snr_dB);
        end
        if all(strlength(string(T.ConfiguredSNRSource)) == 0)
            T.ConfiguredSNRSource(:) = "configured_operating_point_metadata";
        end
        if all(strlength(string(T.SNRValueRole)) == 0)
            T.SNRValueRole(:) = "configured_operating_point_metadata";
        end
        % ConfiguredLayers belongs to the original scheduler configuration. cfg
        % here may already contain the adaptive grant rank; missing stays missing.
        if all(~isfinite(double(T.ConfiguredTxAntennas)))
            T.ConfiguredTxAntennas(:) = double(sixgr.truth.SharedDataCompletionRuntime.configuredTxAntennaCount(cfg, direction));
        end
        if all(~isfinite(double(T.ConfiguredRxAntennas)))
            T.ConfiguredRxAntennas(:) = double(sixgr.truth.SharedDataCompletionRuntime.configuredRxAntennaCount(cfg, direction));
        end
        T = sixgr.truth.canonicalizeConfiguredPhysicalAntennaMetadata( ...
            T, cfg, direction);
        reqModel = sixgr.channel.resolveConcreteProfile(cfg);
        if all(strlength(string(T.ChannelModel)) == 0)
            T.ChannelModel(:) = reqModel;
        end
        if all(strlength(string(T.DopplerSourceMode)) == 0)
            T.DopplerSourceMode(:) = sixgr.truth.SharedDataCompletionRuntime.resolveDopplerSourceMode(cfg);
        end
        if all(strlength(string(T.DopplerValueRole)) == 0)
            T.DopplerValueRole(:) = "scenario_resolved_metadata";
        end
        if all(strlength(string(T.LinkAdaptationMode)) == 0)
            [~, policy, ~] = sixgr.truth.SharedDataCompletionRuntime.resolveLinkAdaptationTokens(cfg, direction);
            T.LinkAdaptationMode(:) = string(policy);
        end
        if all(strlength(string(T.CQITable)) == 0)
            T.CQITable(:) = string(sixgr.link.resolveConfiguredCQITable(cfg, direction));
        end
        if all(strlength(string(T.MCSTable)) == 0)
            if strcmpi(string(direction), "UL")
                T.MCSTable(:) = string(sixgr.link.resolveConfiguredMCSTable(cfg, "UL"));
            else
                T.MCSTable(:) = string(sixgr.link.resolveConfiguredMCSTable(cfg, "DL"));
            end
        end
        uCm = upper(strtrim(string(T.ChannelModel)));
        maskTDL = (uCm == "TDL") & startsWith(reqModel, "TDL");
        if any(maskTDL)
            T.ChannelModel(maskTDL) = reqModel;
        end
        maskCDL = (uCm == "CDL") & startsWith(reqModel, "CDL");
        if any(maskCDL)
            T.ChannelModel(maskCDL) = reqModel;
        end
        if all(~isfinite(double(T.DopplerHz)))
            T.DopplerHz(:) = double(sixgr.util.structGet(cfg, "channel.doppler_Hz", ...
                sixgr.util.structGet(cfg, "channel.dopplerHz", sixgr.util.structGet(cfg, "channel.fading.maxDoppler_Hz", 0))));
        end
        if all(~isfinite(double(T.InjectedDoppler_Hz))) && any(isfinite(double(T.DopplerHz)))
            scalarDopplerRows = ~sixgr.truth.SharedDataCompletionRuntime.rowsUseFadingChannelDoppler(T);
            if any(scalarDopplerRows)
                injected = double(T.InjectedDoppler_Hz);
                doppler = double(T.DopplerHz);
                fillMask = scalarDopplerRows & ~isfinite(injected) & isfinite(doppler);
                injected(fillMask) = doppler(fillMask);
                T.InjectedDoppler_Hz = injected;
            end
        end
        if all(~isfinite(double(T.Seed)))
            seed0 = double(sixgr.util.structGet(cfg, "run.seed", 1));
            T.Seed = seed0 + (0:height(T)-1).';
        end
        if all(~isfinite(double(T.Frame)))
            T.Frame = (1:height(T)).';
        end
        if all(~isfinite(double(T.Slot)))
            T.Slot = T.Frame;
        end
        if all(strlength(string(T.Status)) == 0)
            T.Status(:) = "NA";
        end
        if all(strlength(string(T.Notes)) == 0)
            T.Notes(:) = "";
        end
        if all(~isfinite(double(T.ComputeLatency_ms))) && any(isfinite(double(T.Latency_ms)))
            T.ComputeLatency_ms = double(T.Latency_ms);
        end
        if all(~isfinite(double(T.InjectedCFO_Hz))) && any(isfinite(double(T.TrueCFO_Hz)))
            T.InjectedCFO_Hz = double(T.TrueCFO_Hz);
        end
        if all(~isfinite(double(T.EstimatedCFO_PreCorrection_Hz))) && any(isfinite(double(T.EstimatedCFO_Hz)))
            T.EstimatedCFO_PreCorrection_Hz = double(T.EstimatedCFO_Hz);
        end
        % Arrival scoring, configured RF delay, receiver alignment and a measured
        % post-correction residual have different authorities/reference planes.
        % Only the executing producer can populate injection/application/residual
        % fields; this table adapter must not infer them from another timing value.
        if all(~isfinite(double(T.EstimatedTimingOffset_PreCorrection_samples))) && any(isfinite(double(T.TimingOffset_samples)))
            T.EstimatedTimingOffset_PreCorrection_samples = double(T.TimingOffset_samples);
        end
        if ~ismember("AppliedTimingCorrection_samples", string(T.Properties.VariableNames))
            T.AppliedTimingCorrection_samples = nan(height(T), 1);
        end
        if ~ismember("TimingEstimateApplicationPolicy", string(T.Properties.VariableNames))
            T.TimingEstimateApplicationPolicy = strings(height(T), 1);
        end
        if ~ismember("TimingEstimateStatus", string(T.Properties.VariableNames))
            T.TimingEstimateStatus = strings(height(T), 1);
        end
        if ~ismember("TimingEstimateWasClipped", string(T.Properties.VariableNames))
            T.TimingEstimateWasClipped = false(height(T), 1);
        end
        if all(~isfinite(double(T.SFN)))
            T.SFN = mod(max(0, round(double(T.Frame)) - 1), 1024);
        end
        if all(~isfinite(double(T.ConfiguredSNR_dB)))
            T.ConfiguredSNR_dB = double(T.SNR_dB);
        end
        T = sixgr.truth.SharedDataCompletionRuntime.populateSINRTruthColumns(T);
        T = sixgr.truth.SharedDataCompletionRuntime.repairLinkTrialEvidenceColumns(T, direction, cfg);
        % Bootstrap is a consequence of this grant's repaired causal evidence, not
        % the provisional pre-reconciliation flags. Never use current future CSI.
        T = sixgr.analytics.applyTrialMeasurementPhase(T, cfg);
        if all(~isfinite(double(T.MCSIndex))) && any(isfinite(double(T.MCS)))
            T.MCSIndex = double(T.MCS);
        end
        if all(~isfinite(double(T.AllocatedPRBCount))) && any(isfinite(double(T.PRBs)))
            T.AllocatedPRBCount = double(T.PRBs);
        end
        if ismember("Layers", string(T.Properties.VariableNames)) && any(isfinite(double(T.Layers)))
            layers = double(T.Layers);
            rank = double(T.Rank);
            mask = isfinite(layers) & (~isfinite(rank) | abs(rank - layers) > 1e-9);
            if any(mask)
                T.Rank(mask) = layers(mask);
            end
        elseif all(~isfinite(double(T.Rank))) && any(isfinite(double(T.RankIndicator)))
            T.Rank = double(T.RankIndicator);
        end
        if all(~isfinite(double(T.BaseStationID))) && ismember("ServingCell", string(T.Properties.VariableNames)) && any(isfinite(double(T.ServingCell)))
            T.BaseStationID = double(T.ServingCell);
        end
        if all(~isfinite(double(T.UEID))) && ismember("UEIndex", string(T.Properties.VariableNames)) && any(isfinite(double(T.UEIndex)))
            T.UEID = double(T.UEIndex);
        end
        T = sixgr.truth.SharedDataCompletionRuntime.applyTrialTruthAnnotations(T, direction, cfg);
        end

        function T = populateSINRTruthColumns(T)
        if ~(istable(T) && ~isempty(T))
            return;
        end
        n = height(T);
        vars = string(T.Properties.VariableNames);
        if ~ismember("ReceiverHestSINR_dB", vars)
            T.ReceiverHestSINR_dB = nan(n, 1);
        end
        if ~ismember("ReceiverHestSINRSource", vars)
            T.ReceiverHestSINRSource = strings(n, 1);
        end
        if ~ismember("DecoderTruthProxySINR_dB", vars)
            T.DecoderTruthProxySINR_dB = nan(n, 1);
        end
        if ~ismember("DecoderTruthProxySINRSource", vars)
            T.DecoderTruthProxySINRSource = strings(n, 1);
        end
        if ~ismember("DecoderTruthProxySINRValueRole", vars)
            T.DecoderTruthProxySINRValueRole = strings(n, 1);
        end
        if ~ismember("DecoderTruthProxySINRValueStatus", vars)
            T.DecoderTruthProxySINRValueStatus = strings(n, 1);
        end
        if ~ismember("DecoderTruthProxySINRNAReason", vars)
            T.DecoderTruthProxySINRNAReason = strings(n, 1);
        end
        if ~ismember("SINRValueRole", vars)
            T.SINRValueRole = strings(n, 1);
        end
        if ~ismember("SINRSource", vars)
            T.SINRSource = strings(n, 1);
        end
        if ~ismember("MeasuredTrialSINR_dB", vars)
            T.MeasuredTrialSINR_dB = nan(n, 1);
        end
        if ~ismember("MeasuredTrialSINRSource", vars)
            T.MeasuredTrialSINRSource = strings(n, 1);
        end
        if ~ismember("MeasuredTrialSINRValueRole", vars)
            T.MeasuredTrialSINRValueRole = strings(n, 1);
        end
        if ~ismember("MeasuredTrialSINRValueStatus", vars)
            T.MeasuredTrialSINRValueStatus = strings(n, 1);
        end
        if ~ismember("MeasuredTrialSINRNAReason", vars)
            T.MeasuredTrialSINRNAReason = strings(n, 1);
        end
        if ~ismember("PostEqSINR_dB", vars)
            T.PostEqSINR_dB = nan(n, 1);
        end
        if ~ismember("PostEqSINRSource", vars)
            T.PostEqSINRSource = strings(n, 1);
        end
        if ~ismember("PostEqSINRValueRole", vars)
            T.PostEqSINRValueRole = strings(n, 1);
        end
        if ~ismember("PostEqSINRValueStatus", vars)
            T.PostEqSINRValueStatus = strings(n, 1);
        end
        if ~ismember("MeasuredSINR_dB", vars)
            T.MeasuredSINR_dB = nan(n, 1);
        end
        if ~ismember("SINRMeasurementDomain", vars)
            T.SINRMeasurementDomain = strings(n, 1);
        end
        if ~ismember("PowerReferencePlane", vars)
            T.PowerReferencePlane = strings(n, 1);
        end
        vars = string(T.Properties.VariableNames);

        receiverHest = double(T.ReceiverHestSINR_dB);
        postEqSINR = double(T.PostEqSINR_dB);
        measuredTrial = double(T.MeasuredTrialSINR_dB);
        measuredSINR = double(T.MeasuredSINR_dB);
        postEqSource = strtrim(string(T.PostEqSINRSource));
        postEqRole = strtrim(string(T.PostEqSINRValueRole));
        postEqStatus = strtrim(string(T.PostEqSINRValueStatus));
        postEqEligible = isfinite(postEqSINR) & sixgr.truth.SharedDataCompletionRuntime.postEqSINRProvenanceEligible(postEqSource, postEqRole, postEqStatus);
        fillMeasuredTrialFromPostEq = ~isfinite(measuredTrial) & postEqEligible;
        if any(fillMeasuredTrialFromPostEq)
            measuredTrial(fillMeasuredTrialFromPostEq) = postEqSINR(fillMeasuredTrialFromPostEq);
            T.MeasuredTrialSINR_dB = measuredTrial;
            measuredSource = strtrim(string(T.MeasuredTrialSINRSource));
            measuredRole = strtrim(string(T.MeasuredTrialSINRValueRole));
            measuredStatus = strtrim(string(T.MeasuredTrialSINRValueStatus));
            fillSourceMask = fillMeasuredTrialFromPostEq & (strlength(measuredSource) == 0);
            fillRoleMask = fillMeasuredTrialFromPostEq & (strlength(measuredRole) == 0);
            fillStatusMask = fillMeasuredTrialFromPostEq & (strlength(measuredStatus) == 0);
            measuredSource(fillSourceMask) = postEqSource(fillSourceMask);
            measuredRole(fillRoleMask) = "measured_post_equalization_scheduling_input";
            measuredStatus(fillStatusMask) = "OK";
            T.MeasuredTrialSINRSource = measuredSource;
            T.MeasuredTrialSINRValueRole = measuredRole;
            T.MeasuredTrialSINRValueStatus = measuredStatus;
        end
        fillMeasuredAliasMask = ~isfinite(measuredSINR) & isfinite(measuredTrial);
        if any(fillMeasuredAliasMask)
            measuredSINR(fillMeasuredAliasMask) = measuredTrial(fillMeasuredAliasMask);
            T.MeasuredSINR_dB = measuredSINR;
        end

        receiverSource = strtrim(string(T.ReceiverHestSINRSource));
        fillReceiverSourceMask = strlength(receiverSource) == 0 & isfinite(receiverHest);
        if any(fillReceiverSourceMask)
            receiverSource(fillReceiverSourceMask) = "receiver_hest_reference_signal_measurement";
            T.ReceiverHestSINRSource = receiverSource;
        end
        sinrValueRole = strtrim(string(T.SINRValueRole));
        fillRoleMask = strlength(sinrValueRole) == 0 & postEqEligible;
        if any(fillRoleMask)
            sinrValueRole(fillRoleMask) = "measured_post_equalization_scheduling_input";
            T.SINRValueRole = sinrValueRole;
        end
        sinrSource = strtrim(string(T.SINRSource));
        fillSINRSourceMask = strlength(sinrSource) == 0 & postEqEligible & strlength(postEqSource) > 0;
        if any(fillSINRSourceMask)
            sinrSource(fillSINRSourceMask) = postEqSource(fillSINRSourceMask);
            T.SINRSource = sinrSource;
        end

        % A numerical receiver SINR is incomplete without the receiver domain in
        % which signal and disturbance powers were compared.  Bind the domain only
        % from the active receiver source columns; configured SNR-like inputs never
        % enter this classification.
        measurementDomain = strtrim(string(T.SINRMeasurementDomain));
        powerPlane = strtrim(string(T.PowerReferencePlane));
        measurementDomain(ismissing(measurementDomain)) = "";
        powerPlane(ismissing(powerPlane)) = "";
        direction = repmat("", n, 1);
        if ismember("Direction", string(T.Properties.VariableNames))
            direction = upper(strtrim(string(T.Direction)));
        end
        measuredSource = strtrim(string(T.MeasuredTrialSINRSource));
        measuredSource(ismissing(measuredSource)) = "";
        sourceForDomain = measuredSource;
        blankMeasuredSource = strlength(sourceForDomain) == 0;
        sourceForDomain(blankMeasuredSource) = postEqSource(blankMeasuredSource);
        finiteReceiverSINR = isfinite(double(T.MeasuredTrialSINR_dB));
        measuredValue = double(T.MeasuredTrialSINR_dB);
        postEqMatchTolerance = 1e-9 .* max(1, max(abs(measuredValue), abs(postEqSINR)));
        postEqValueMatch = finiteReceiverSINR & isfinite(postEqSINR) & ...
            abs(measuredValue - postEqSINR) <= postEqMatchTolerance;
        postEqDomain = finiteReceiverSINR & postEqValueMatch & postEqEligible;
        % Retain the explicit source classification for receiver implementations
        % whose canonical post-equalization value is not duplicated into the
        % PostEqSINR column, but never classify a configured/SNR-label source.
        postEqDomain = postEqDomain | (finiteReceiverSINR & ...
            (contains(lower(sourceForDomain), "post_equal") | contains(lower(sourceForDomain), "posteq")));
        receiverSourceForDomain = strtrim(string(T.ReceiverHestSINRSource));
        receiverSourceForDomain(ismissing(receiverSourceForDomain)) = "";
        hestMatchTolerance = 1e-9 .* max(1, max(abs(measuredValue), abs(receiverHest)));
        hestValueMatch = finiteReceiverSINR & isfinite(receiverHest) & ...
            abs(measuredValue - receiverHest) <= hestMatchTolerance;
        hestProvenance = contains(lower(receiverSourceForDomain), "hest") | ...
            contains(lower(receiverSourceForDomain), "reference_signal") | ...
            contains(lower(receiverSourceForDomain), "dmrs");
        hestDomain = finiteReceiverSINR & ~postEqDomain & hestValueMatch & hestProvenance;
        hestDomain = hestDomain | (finiteReceiverSINR & ~postEqDomain & (...
            contains(lower(sourceForDomain), "hest") | ...
            contains(lower(sourceForDomain), "reference_signal") | ...
            contains(lower(sourceForDomain), "dmrs")));

        dlPostEq = postEqDomain & direction == "DL" & strlength(measurementDomain) == 0;
        ulPostEq = postEqDomain & direction == "UL" & strlength(measurementDomain) == 0;
        dlHest = hestDomain & direction == "DL" & strlength(measurementDomain) == 0;
        ulHest = hestDomain & direction == "UL" & strlength(measurementDomain) == 0;
        measurementDomain(dlPostEq) = "pdsch_post_equalization_data_re";
        measurementDomain(ulPostEq) = "pusch_post_equalization_data_re";
        measurementDomain(dlHest) = "pdsch_dmrs_channel_estimate";
        measurementDomain(ulHest) = "pusch_dmrs_channel_estimate";

        postEqPlane = postEqDomain & strlength(powerPlane) == 0;
        hestPlane = hestDomain & strlength(powerPlane) == 0;
        powerPlane(postEqPlane) = "receiver_equalized_data_resource_elements";
        powerPlane(hestPlane) = "receiver_dmrs_resource_elements_after_ofdm_demodulation";
        T.SINRMeasurementDomain = measurementDomain;
        T.PowerReferencePlane = powerPlane;

        decoderProxy = double(T.DecoderTruthProxySINR_dB);
        decoderSource = strtrim(string(T.DecoderTruthProxySINRSource));
        decoderRole = strtrim(string(T.DecoderTruthProxySINRValueRole));
        decoderStatus = strtrim(string(T.DecoderTruthProxySINRValueStatus));
        decoderReason = strtrim(string(T.DecoderTruthProxySINRNAReason));
        proxyLike = isfinite(decoderProxy) | contains(lower(decoderSource), "evm_proxy") | ...
            contains(lower(decoderRole), "proxy") | contains(lower(decoderSource), "proxy");
        if any(proxyLike)
            decoderProxy(proxyLike) = NaN;
            decoderSource(proxyLike) = "evm_proxy_quarantined_not_decoder_truth";
            decoderRole(proxyLike) = "unavailable";
            decoderStatus(proxyLike) = "unavailable";
            decoderReason(proxyLike) = "decoder_truth_sinr_requires_receiver_or_decoder_evidence_not_evm_proxy";
        end
        blankSource = strlength(decoderSource) == 0;
        decoderSource(blankSource) = "unavailable_decoder_truth_proxy_not_materialized";
        blankRole = strlength(decoderRole) == 0;
        decoderRole(blankRole) = "unavailable";
        blankStatus = strlength(decoderStatus) == 0;
        decoderStatus(blankStatus) = "unavailable";
        blankReason = strlength(decoderReason) == 0;
        decoderReason(blankReason) = "decoder_truth_proxy_not_materialized";
        T.DecoderTruthProxySINR_dB = decoderProxy;
        T.DecoderTruthProxySINRSource = decoderSource;
        T.DecoderTruthProxySINRValueRole = decoderRole;
        T.DecoderTruthProxySINRValueStatus = decoderStatus;
        T.DecoderTruthProxySINRNAReason = decoderReason;
        end

        function tf = postEqSINRProvenanceEligible(source, role, status)
        token = lower(strjoin([string(source), string(role), string(status)], " "));
        hasBareHest = arrayfun(@(s) any(string(regexp(char(s), '[a-z0-9]+', 'match')) == "hest"), token);
        blocked = ["receiverhest", "receiver_hest", "pilot", ...
            "reference_signal", "evm_proxy", "proxy", "fallback", "configured", "sweep", ...
            "unavailable", "failed", "rejected"];
        tf = contains(token, "post_equalization") & ~hasBareHest & ~arrayfun(@(s) any(contains(s, blocked)), token);
        end

        function T = repairLinkTrialEvidenceColumns(T, direction, cfg)
        if ~(istable(T) && ~isempty(T))
            return;
        end
        n = height(T);
        bitErrors = double(sixgr.truth.PDCCHControlRuntime.columnOrDefault(T, "BitErrors", nan(n, 1)));
        bitsCompared = double(sixgr.truth.PDCCHControlRuntime.columnOrDefault(T, "BitsCompared", nan(n, 1)));

        if ismember("RawBER", string(T.Properties.VariableNames))
            rawBER = double(sixgr.truth.PDCCHControlRuntime.columnOrDefault(T, "RawBER", nan(n, 1)));
            rawBERMask = ~isfinite(rawBER) & isfinite(bitErrors) & isfinite(bitsCompared) & bitsCompared > 0;
            rawBER(rawBERMask) = bitErrors(rawBERMask) ./ bitsCompared(rawBERMask);
            T.RawBER = rawBER;
        end

        % Stage and channel-execution evidence belongs to the actual receiver
        % and executed replay. A finite transmitted TBS, CRC, pilot metric or
        % configured channel object cannot prove another stage ran. In
        % particular preserve explicit false flags on partial/NA receptions;
        % do not reconstruct absent evidence from numeric or YAML metadata.

        % Preserve the producer's decision-event flag. A finite MCS or frozen grant
        % proves an operating point, not that this trial scheduled a later feedback
        % decision. In particular connected, fixed and bootstrap grants can all
        % legitimately carry LinkAdaptationScheduled=false. Likewise retain the
        % producer's LinkAdaptationApplied flag: finite CQI/source metadata alone
        % does not prove that the decision was consumed. Bootstrap exclusions belong
        % to the actual DL/UL producer, not a reporting-time reconstruction.

        if ismember("AppliedPrecoderPMIType", string(T.Properties.VariableNames))
            pmiType = strtrim(string(T.AppliedPrecoderPMIType));
            codebookMode = strtrim(string(sixgr.truth.PDCCHControlRuntime.columnOrDefault(T, "AppliedPrecoderCodebookMode", repmat("", n, 1))));
            precoderSource = lower(strtrim(string(sixgr.truth.PDCCHControlRuntime.columnOrDefault(T, "PrecoderSource", repmat("", n, 1)))));
            precodingMode = lower(strtrim(string(sixgr.truth.PDCCHControlRuntime.columnOrDefault(T, "PrecodingMode", repmat("", n, 1)))));
            precodingActive = logical(sixgr.truth.PDCCHControlRuntime.columnOrDefault(T, "PrecodingActive", false(n, 1)));
            beamformingApplied = logical(sixgr.truth.PDCCHControlRuntime.columnOrDefault(T, "BeamformingApplied", false(n, 1)));
            appliedBeam = strtrim(string(sixgr.truth.PDCCHControlRuntime.columnOrDefault(T, "AppliedBeamIndexSet", repmat("", n, 1))));
            dftMask = (precodingActive | beamformingApplied) & (contains(precoderSource, "codebook_dft") | strlength(appliedBeam) > 0);
            transformMask = logical(sixgr.truth.PDCCHControlRuntime.columnOrDefault(T, "TransformPrecodingApplied", false(n, 1))) | contains(precodingMode, "transform");
            pmiType(strlength(pmiType) == 0 & dftMask) = "dft_beam_index_precoder";
            pmiType(strlength(pmiType) == 0 & transformMask) = "transform_precoding_no_pmi";
            pmiType(strlength(pmiType) == 0 & (precodingActive | beamformingApplied)) = "runtime_precoder_no_pmi_index";
            T.AppliedPrecoderPMIType = pmiType;
            if ismember("AppliedPrecoderCodebookMode", string(T.Properties.VariableNames))
                codebookMode(strlength(codebookMode) == 0 & dftMask) = "dft_beam_codebook";
                codebookMode(strlength(codebookMode) == 0 & transformMask) = "transform_precoding";
                codebookMode(strlength(codebookMode) == 0 & (precodingActive | beamformingApplied)) = "runtime_precoder_mode";
                T.AppliedPrecoderCodebookMode = codebookMode;
            end
        end
        end

        function T = applyTrialTruthAnnotations(T, direction, cfg)
        if ~(istable(T) && ~isempty(T))
            return;
        end
        T = sixgr.link.applyMeasuredDLMUMIMOReceiverEvidence(T);
        n = height(T);
        strategy = strtrim(string(T.ConfiguredBeamSelectionStrategy));
        configuredStrategy = strtrim(string(sixgr.util.structGet(cfg, ...
            "lls6g.userContext.BeamSelectionStrategy", ...
            sixgr.util.structGet(cfg, "lls6g.users.beam_selection_strategy", ...
            sixgr.util.structGet(cfg, "users.beam_selection_strategy", "")))));
        if strlength(configuredStrategy) > 0
            strategy(strlength(strategy) == 0) = configuredStrategy;
            T.ConfiguredBeamSelectionStrategy = strategy;
        end
        if ismember("BeamSelectionStrategy", string(T.Properties.VariableNames))
            appliedStrategy = strtrim(string(T.BeamSelectionStrategy));
            appliedStrategy(strlength(appliedStrategy) == 0) = strategy(strlength(appliedStrategy) == 0);
            T.BeamSelectionStrategy = appliedStrategy;
        end
        T.BeamSelectionAuthority = repmat("configured_beam_policy_reference", n, 1);
        fixedPolicyMask = startsWith(lower(strategy), "fixed");
        dynamicPolicyMask = strlength(strategy) > 0 & ~fixedPolicyMask;
        T.BeamSelectionPolicyType = repmat("", n, 1);
        T.BeamSelectionPolicyType(fixedPolicyMask) = "fixed_policy";
        T.BeamSelectionPolicyType(dynamicPolicyMask) = "dynamic_policy";
        T.BeamSelectionPolicyFixed = fixedPolicyMask;
        if ismember("BeamIndexSet", string(T.Properties.VariableNames))
            requestedBeam = strtrim(string(T.BeamIndexSet));
        else
            requestedBeam = strings(n, 1);
        end
        configuredBeamSet = strtrim(string(sixgr.util.structGet(cfg, "lls6g.userContext.BeamIndexSet", "")));
        if strlength(configuredBeamSet) > 0
            requestedBeam(strlength(requestedBeam) == 0) = configuredBeamSet;
        end
        selectedFinite = isfinite(double(T.SelectedBeamIndex));
        selectedMask = strlength(requestedBeam) == 0 & selectedFinite;
        requestedBeam(selectedMask) = string(round(double(T.SelectedBeamIndex(selectedMask))));
        T.RequestedBeamIndexSet = requestedBeam;
        [T.RequestedPrecoderPMI,T.RequestedPrecoderSource] = ...
            sixgr.phy.grant.requestedPrecoderColumns(T,upper(string(direction)));
        precoderSource = sixgr.truth.SharedDataCompletionRuntime.normalizeULAppliedPrecoderSourceBundle( ...
            sixgr.truth.PDCCHControlRuntime.columnOrDefault(T, "PrecoderSource", ""), ...
            sixgr.truth.PDCCHControlRuntime.columnOrDefault(T, "PrecodingMode", ""), ...
            sixgr.truth.PDCCHControlRuntime.columnOrDefault(T, "TransformPrecodingApplied", false));
        T.PrecoderSource = precoderSource;
        T.AppliedPrecoderSource = precoderSource;
        T = sixgr.truth.SharedDataCompletionRuntime.decorateBeamAndPrecoderTruthFieldsBundle(T, direction);
        configuredLinkMode = repmat("", n, 1);
        configuredSelectionMode = repmat("", n, 1);
        [configuredMode, policy, configuredActualMode] = sixgr.truth.SharedDataCompletionRuntime.resolveLinkAdaptationTokens(cfg, direction);
        configuredLinkMode(:) = string(configuredMode);
        configuredSelectionMode(:) = string(configuredActualMode);
        T.ConfiguredLinkAdaptationMode = configuredLinkMode;
        T.ConfiguredMCSSelectionPolicy = configuredSelectionMode;
        T.RequestedOperatingPointSource = sixgr.truth.SharedDataCompletionRuntime.resolveOperatingPointSourceColumn(configuredSelectionMode, configuredLinkMode);
        fixedLinkCampaignOnly = logical(sixgr.util.structGet(cfg, ...
            "run.fixedLinkCampaignOnly", false));
        T.SchedulerGrantMCSSelectionMode = string(T.SchedulerGrantMCSSelectionMode);
        if fixedLinkCampaignOnly
            noScheduler = strlength(strtrim(T.SchedulerGrantMCSSelectionMode)) == 0;
            T.SchedulerGrantMCSSelectionMode(noScheduler) = ...
                "not_applicable_fixed_link_calibration_no_scheduler_grant";
            if ismember("GrantControlState", string(T.Properties.VariableNames))
                grantState = strtrim(string(T.GrantControlState));
                grantState(strlength(grantState) == 0) = ...
                    "not_applicable_fixed_link_calibration_no_control_lifecycle";
                T.GrantControlState = grantState;
            end
        end
        operatingPointSource = sixgr.truth.SharedDataCompletionRuntime.resolveOperatingPointSourceColumn(T.ActualMCSSelectionMode, T.LinkAdaptationMode);
        T.GrantOperatingPointSource = operatingPointSource;
        T.AppliedOperatingPointSource = operatingPointSource;
        T.MCSAuthority = operatingPointSource;
        T.ModulationAuthority = operatingPointSource;
        T = sixgr.link.applyScheduledOperatingPointEvidence(T);
        T = sixgr.util.applyLLSRawTrialLifecycle(T);

        storeState = sixgr.truth.SharedDataCompletionRuntime.resolveArtifactStoreState();
        T.RunUUID = repmat(string(sixgr.util.structGet(storeState, "RunUUID", "")), n, 1);
        T.RunTag = repmat(string(sixgr.util.structGet(cfg, "run.runTag", "")), n, 1);
        scenarioId = string(sixgr.util.structGet(cfg, "run.scenarioID", sixgr.util.structGet(cfg, "meta.lls6gScenarioID", sixgr.util.structGet(cfg, "meta.loadedFrom", ""))));
        T.ScenarioID = repmat(scenarioId, n, 1);
        T.RunnerProfile = repmat(string(sixgr.util.structGet(cfg, "run.runnerProfile", "waveform_bundle")), n, 1);
        T.ConfigHash = repmat(string(sixgr.util.structGet(cfg, "meta.configHash", "")), n, 1);
        sourceArtifact = repmat(sixgr.truth.SharedDataCompletionRuntime.resolveDirectionalTrialArtifact(T, direction), n, 1);
        T.SourceArtifact = sourceArtifact;
        T.SourceTable = sourceArtifact;
        T.ArtifactClass = repmat("raw_runtime_trial_evidence", n, 1);
        T.SemanticState = string(T.RowLifecycleState);
        T.CountsTowardCoverage = sixgr.util.linkTrialDecodeCoverage(T);
        % Runtime materialization/source fields pass through from the actual
        % execution owner. Non-crash metadata alone is not waveform evidence.
        T.MachineReadable = true(n, 1);
        T.HumanReadable = true(n, 1);
        end

        function T = decorateBeamAndPrecoderTruthFieldsBundle(T, direction)
        if ~(istable(T) && ~isempty(T))
            return;
        end
        n = height(T);
        requestedBeam = strtrim(string(sixgr.truth.PDCCHControlRuntime.columnOrDefault(T, "RequestedBeamIndexSet", "")));
        requestedPMI = double(sixgr.truth.PDCCHControlRuntime.columnOrDefault(T, "RequestedPrecoderPMI", NaN));
        appliedBeam = strtrim(string(sixgr.truth.PDCCHControlRuntime.columnOrDefault(T, "AppliedBeamIndexSet", "")));
        appliedPMI = double(sixgr.truth.PDCCHControlRuntime.columnOrDefault(T, "AppliedPrecoderPMI", NaN));
        appliedSource = strtrim(string(sixgr.truth.PDCCHControlRuntime.columnOrDefault(T, "AppliedPrecoderSource", sixgr.truth.PDCCHControlRuntime.columnOrDefault(T, "PrecoderSource", ""))));
        appliedMatrixDigest = lower(strtrim(string(sixgr.truth.PDCCHControlRuntime.columnOrDefault(T, ...
            "AppliedPrecoderMatrixSHA256", ""))));
        requestedDigest = lower(strtrim(string(sixgr.truth.PDCCHControlRuntime.columnOrDefault(T, ...
            "RequestedPrecoderSHA256", ""))));
        appliedDigest = lower(strtrim(string(sixgr.truth.PDCCHControlRuntime.columnOrDefault(T, ...
            "AppliedPrecoderSHA256", appliedMatrixDigest))));
        precodingMode = lower(strtrim(string(sixgr.truth.PDCCHControlRuntime.columnOrDefault(T, "PrecodingMode", ""))));
        transformApplied = logical(sixgr.truth.PDCCHControlRuntime.columnOrDefault(T, "TransformPrecodingApplied", false)) | precodingMode == "transform_precoding";
        explicitBeamWeights = logical(sixgr.truth.PDCCHControlRuntime.columnOrDefault(T, "ExplicitBeamWeightsApplied", false));
        beamformingApplied = logical(sixgr.truth.PDCCHControlRuntime.columnOrDefault(T, "BeamformingApplied", false));
        isUL = upper(string(direction)) == "UL";
        codebookMask = isUL & (precodingMode == "ul_codebook_tpmi" | lower(appliedSource) == "ul_pusch_native_codebook_tpmi");
        T.RequestedBeamIndexSet = requestedBeam;

        T.RequestedBeamTruthClassification = repmat("", n, 1);
        T.RequestedPrecoderPMITruthClassification = repmat("", n, 1);
        T.AppliedBeamApplicationSource = appliedSource;
        T.AppliedBeamTruthClassification = repmat("", n, 1);
        T.AppliedPrecoderPMIApplicationSource = appliedSource;
        T.AppliedPrecoderPMITruthClassification = repmat("", n, 1);

        requestedBeamMask = strlength(requestedBeam) > 0;
        requestedPMIMask = isfinite(requestedPMI);
        appliedBeamMask = strlength(appliedBeam) > 0;
        appliedPMIMask = isfinite(appliedPMI);

        T.RequestedBeamTruthClassification(requestedBeamMask) = "requested_reference";
        T.RequestedPrecoderPMITruthClassification(requestedPMIMask) = "requested_reference";
        T.AppliedBeamTruthClassification(appliedBeamMask) = "applied_runtime_value";
        T.AppliedPrecoderPMITruthClassification(appliedPMIMask) = "applied_runtime_value";
        matrixIdentifiedWithoutPMI = ~isUL & ~appliedPMIMask & ...
            explicitBeamWeights & ~cellfun(@isempty, regexp(cellstr(appliedMatrixDigest), ...
            '^[0-9a-f]{64}$', 'once'));
        T.AppliedPrecoderPMIApplicationSource(matrixIdentifiedWithoutPMI) = ...
            "not_applicable_explicit_matrix_identified_by_sha256";
        T.AppliedPrecoderPMITruthClassification(matrixIdentifiedWithoutPMI) = ...
            "not_applicable_explicit_matrix_without_scalar_pmi";
        matchStatus = strings(n, 1);
        for ii = 1:n
            matchStatus(ii) = sixgr.truth.SharedDataCompletionRuntime.requestedVsAppliedPMIStatusBundle(requestedPMI(ii), appliedPMI(ii));
        end
        hashPattern = '^[0-9a-f]{64}$';
        sameComposedMatrix = ~isUL & requestedPMIMask & appliedPMIMask & ...
            requestedPMI ~= appliedPMI & ...
            ~cellfun(@isempty, regexp(cellstr(requestedDigest), hashPattern, 'once')) & ...
            ~cellfun(@isempty, regexp(cellstr(appliedDigest), hashPattern, 'once')) & ...
            requestedDigest == appliedDigest & ...
            contains(lower(appliedSource), "composed_with_csirs_port_basis");
        matchStatus(sameComposedMatrix) = ...
            "requested_equals_runtime_applied_matrix_after_csirs_basis_composition";
        T.RequestedVsAppliedPrecoderPMIMatchStatus = matchStatus;

        if ~isUL
            return;
        end

        directMask = ~transformApplied & ~codebookMask;
        missingAppliedBeamMask = ~appliedBeamMask;
        missingAppliedPMIMask = ~appliedPMIMask;

        beamAppSource = T.AppliedBeamApplicationSource;
        pmiAppSource = T.AppliedPrecoderPMIApplicationSource;
        beamAppSource(missingAppliedBeamMask & directMask) = "ul_direct_mapping_no_materialized_beam_index_set";
        beamAppSource(missingAppliedBeamMask & transformApplied) = "ul_transform_precoding_no_materialized_beam_index_set";
        beamAppSource(missingAppliedBeamMask & codebookMask) = "ul_pusch_native_codebook_no_materialized_beam_index_set";
        pmiAppSource(missingAppliedPMIMask & directMask) = "ul_direct_mapping_no_materialized_applied_pmi";
        pmiAppSource(missingAppliedPMIMask & transformApplied) = "ul_transform_precoding_no_materialized_applied_pmi";
        pmiAppSource(missingAppliedPMIMask & codebookMask) = "ul_pusch_native_codebook_no_runtime_tpmi";
        T.AppliedBeamApplicationSource = beamAppSource;
        T.AppliedPrecoderPMIApplicationSource = pmiAppSource;
        T.AppliedBeamTruthClassification(missingAppliedBeamMask) = "not_materialized_in_active_ul_path";
        T.AppliedPrecoderPMITruthClassification(missingAppliedPMIMask) = "not_materialized_in_active_ul_path";
        T.BeamformingApplied(missingAppliedBeamMask & ~beamformingApplied) = false;
        end

        function status = requestedVsAppliedPMIStatusBundle(requestedPMI, appliedPMI)
        requestedFinite = isfinite(double(requestedPMI));
        appliedFinite = isfinite(double(appliedPMI));
        if requestedFinite && appliedFinite
            if round(double(requestedPMI)) == round(double(appliedPMI))
                status = "requested_matches_runtime_applied";
            else
                status = "requested_differs_from_runtime_applied";
            end
        elseif requestedFinite && ~appliedFinite
            status = "requested_present_applied_unavailable";
        elseif ~requestedFinite && appliedFinite
            status = "runtime_applied_without_request_reference";
        else
            status = "no_requested_or_applied_pmi";
        end
        end

        function source = normalizeULAppliedPrecoderSourceBundle(source, mode, transformApplied)
        source = strtrim(string(source));
        mode = lower(strtrim(string(mode)));
        transformApplied = logical(transformApplied);
        directMask = mode == "direct_mapping_no_explicit_beam_weights" | (~transformApplied & strlength(mode) == 0);
        transformMask = mode == "transform_precoding" | transformApplied;
        repairMask = strlength(source) == 0 | lower(source) == "codebook_dft";
        source(repairMask & directMask) = "ul_direct_mapping_no_explicit_beam_weights";
        source(repairMask & transformMask) = "ul_pusch_transform_precoding";
        end

        function token = resolveDirectionalTrialArtifact(T, direction)
        direction = upper(strtrim(string(direction)));
        vars = strings(0, 1);
        if istable(T)
            vars = string(T.Properties.VariableNames);
        end
        hasFiniteTB = false;
        if istable(T) && ismember("TBSize_bits", vars)
            tbBits = double(T.TBSize_bits);
            hasFiniteTB = any(isfinite(tbBits) & tbBits > 0);
        end
        hasTBSizeColumn = istable(T) && ismember("TBSize_bits", vars);
        allTBMissing = ~hasTBSizeColumn;
        if hasTBSizeColumn
            tbBits = double(T.TBSize_bits);
            allTBMissing = all(~isfinite(tbBits) | tbBits <= 0);
        end
        if hasFiniteTB && direction == "DL"
            token = "air_interface/csv/dl_pdsch_trials.csv";
        elseif hasFiniteTB && direction == "UL"
            token = "air_interface/csv/ul_pusch_trials.csv";
        elseif direction == "UL" && (ismember("PUCCHResourceId", vars) || ...
                (ismember("RequestedFormat", vars) && any(isfinite(double(T.RequestedFormat)))))
            token = "air_interface/csv/pucch_trials.csv";
        elseif ismember("DCISize_bits", vars) && any(isfinite(double(T.DCISize_bits)))
            token = "air_interface/csv/pdcch_trials.csv";
        elseif ismember("TrackingEstimateSource", vars) && any(strlength(strtrim(string(T.TrackingEstimateSource))) > 0)
            if direction == "UL"
                token = "air_interface/csv/srs_trials.csv";
            else
                token = "air_interface/csv/trs_trials.csv";
            end
        elseif ismember("AcquisitionTime_ms", vars) && direction == "DL" && allTBMissing
            token = "air_interface/csv/pbch_trials.csv";
        elseif ismember("DetectionMetric", vars) && direction == "UL" && allTBMissing
            token = "air_interface/csv/prach_trials.csv";
        elseif direction == "UL"
            token = "air_interface/csv/ul_pusch_trials.csv";
        else
            token = "air_interface/csv/dl_pdsch_trials.csv";
        end
        end

        function state = resolveArtifactStoreState()
        state = struct();
        try
            state = sixgr.db.artifactStore("get_state");
        catch
            state = struct();
        end
        end

        function T = emptyLinkTrialTable(nRows)
        nRows = max(0, round(double(nRows)));
        rows = repmat(sixgr.truth.makeLinkTrialRow(struct(), "", NaN, 1), nRows, 1);
        T = struct2table(rows);
        T.TBSInputModulation = strings(nRows, 1);
        T.TBSInputNumLayers = NaN(nRows, 1);
        T.TBSInputNPRB = NaN(nRows, 1);
        T.TBSInputNREPerPRB = NaN(nRows, 1);
        T.TBSInputTargetCodeRate = NaN(nRows, 1);
        T.TBSInputXOverhead = NaN(nRows, 1);
        T.TBSInputSource = strings(nRows, 1);
        T.RequestedBeamTruthClassification = strings(nRows, 1);
        T.RequestedPrecoderPMITruthClassification = strings(nRows, 1);
        T.AppliedBeamApplicationSource = strings(nRows, 1);
        T.AppliedBeamTruthClassification = strings(nRows, 1);
        T.AppliedPrecoderPMIApplicationSource = strings(nRows, 1);
        T.AppliedPrecoderPMITruthClassification = strings(nRows, 1);
        T.RequestedVsAppliedPrecoderPMIMatchStatus = strings(nRows, 1);
        T.AppliedPrecoderMatrixSHA256 = strings(nRows, 1);
        T.RequestedPrecoderSHA256 = strings(nRows, 1);
        T.AppliedPrecoderSHA256 = strings(nRows, 1);
        T.PrecoderDigestDomain = strings(nRows, 1);
        T.FrozenGrantContextId = strings(nRows, 1);
        T.RV = NaN(nRows, 1);
        T.HARQProcessId = NaN(nRows, 1);
        T.HarqID = NaN(nRows, 1);
        T.HARQRound = NaN(nRows, 1);
        T.NDI = NaN(nRows, 1);
        T.IsRetransmission = false(nRows, 1);
        T.NDIEpoch = NaN(nRows, 1);
        T.TBId = strings(nRows, 1);
        T.OriginalTBSBits = NaN(nRows, 1);
        T.CurrentTBSBits = NaN(nRows, 1);
        T.OriginalRateMatchedBits = NaN(nRows, 1);
        T.CurrentRateMatchedBits = NaN(nRows, 1);
        T.EffectiveInitialCodeRate = NaN(nRows, 1);
        T.EffectiveCurrentTxCodeRate = NaN(nRows, 1);
        T.ShortIRRetx = false(nRows, 1);
        T.CodeBlockLayoutHash = strings(nRows, 1);
        T.HARQContextHash = strings(nRows, 1);
        T.HARQContextStatus = strings(nRows, 1);
        T.PDCCHGrantBindingRequired = false(nRows, 1);
        T.PDCCHGrantBindingOk = false(nRows, 1);
        T.PDCCHGrantBindingStatus = strings(nRows, 1);
        T.PDCCHGrantBindingFailureCode = strings(nRows, 1);
        T.PDCCHGrantDCIId = strings(nRows, 1);
        T.PDCCHGrantDCIFieldsHash = strings(nRows, 1);
        T.PDCCHGrantFieldsHash = strings(nRows, 1);
        T.PDCCHGrantSearchSpaceId = NaN(nRows, 1);
        T.PDCCHGrantCORESETId = NaN(nRows, 1);
        T.PDCCHGrantAggregationLevel = NaN(nRows, 1);
        T.PDCCHGrantCandidateIndex = NaN(nRows, 1);
        T.PDCCHGrantDCIFormat = strings(nRows, 1);
        T = sixgr.link.appendMeasuredPHYEvidenceColumns(T, cell(nRows, 1));
        if nRows==0
            T=sixgr.link.completeEmptyLinkTrialSchema(T);
        end
        end

        function T = annotateWaveformPreviewTable(T, cfg, ueIdx, direction)
        if ~istable(T)
            T = table();
            return;
        end
        T=sixgr.truth.CoupledRadioIdentity.annotateDataEvidence(T,cfg,ueIdx,direction);
        end

        function T = annotateUserTrials(T, cfg, multiUser, ueIdx, userMeta)
        if ~istable(T)
            T = table();
            return;
        end
        n = height(T);
        T=sixgr.truth.CoupledRadioIdentity.annotateDataEvidence(T,cfg,ueIdx,sixgr.truth.SharedDataCompletionRuntime.directionFromTable(T));
        if ~ismember("SFN", string(T.Properties.VariableNames)) || all(~isfinite(double(T.SFN)))
            T.SFN = mod(max(0, round(double(T.Frame)) - 1), 1024);
        end
        if ~ismember("ConfiguredSNR_dB", string(T.Properties.VariableNames)) || all(~isfinite(double(T.ConfiguredSNR_dB)))
            T.ConfiguredSNR_dB = double(T.SNR_dB);
        end
        T = sixgr.truth.SharedDataCompletionRuntime.populateSINRTruthColumns(T);
        if ~ismember("MCSIndex", string(T.Properties.VariableNames)) || all(~isfinite(double(T.MCSIndex)))
            T.MCSIndex = double(T.MCS);
        end
        if ~ismember("AllocatedPRBCount", string(T.Properties.VariableNames)) || all(~isfinite(double(T.AllocatedPRBCount)))
            T.AllocatedPRBCount = double(T.PRBs);
        end
        if ismember("Layers", string(T.Properties.VariableNames)) && any(isfinite(double(T.Layers)))
            if ~ismember("Rank", string(T.Properties.VariableNames))
                T.Rank = double(T.Layers);
            else
                layers = double(T.Layers);
                rank = double(T.Rank);
                mask = isfinite(layers) & (~isfinite(rank) | abs(rank - layers) > 1e-9);
                if any(mask)
                    T.Rank(mask) = layers(mask);
                end
            end
        elseif ~ismember("Rank", string(T.Properties.VariableNames)) || all(~isfinite(double(T.Rank)))
            T.Rank = double(T.RankIndicator);
        end
        T.BaseStationID = repmat(double(sixgr.util.structGet(userMeta, "RuntimeServingCell", NaN)), n, 1);
        if ~ismember("ServingCell", string(T.Properties.VariableNames))
            T.ServingCell = double(T.BaseStationID);
        end
        if ~ismember("ServingRSRP_dBm", string(T.Properties.VariableNames)) || all(~isfinite(double(T.ServingRSRP_dBm)))
            T.ServingRSRP_dBm = repmat(double(sixgr.util.structGet(userMeta, "RuntimeServingRSRP_dBm", NaN)), n, 1);
        end
        runtimeServingRSRPSource = string(sixgr.util.structGet( ...
            userMeta, "RuntimeServingRSRPSource", ""));
        if (~ismember("ServingRSRPSource", string(T.Properties.VariableNames)) || ...
                all(strlength(string(T.ServingRSRPSource)) == 0)) && ...
                strlength(strtrim(runtimeServingRSRPSource)) > 0
            T.ServingRSRPSource = repmat(runtimeServingRSRPSource, n, 1);
        end
        if ~ismember("LargeScaleSINR_dB", string(T.Properties.VariableNames)) || all(~isfinite(double(T.LargeScaleSINR_dB)))
            T.LargeScaleSINR_dB = repmat(double(sixgr.util.structGet(userMeta, "RuntimeServingLargeScaleSINR_dB", NaN)), n, 1);
        end
        if (~ismember("LargeScaleSINRSource", string(T.Properties.VariableNames)) || all(strlength(string(T.LargeScaleSINRSource)) == 0)) && any(isfinite(double(T.LargeScaleSINR_dB)))
            T.LargeScaleSINRSource = repmat("large_scale_interference_budget_preview", n, 1);
        end
        if ~ismember("InterferenceMode", string(T.Properties.VariableNames)) || all(strlength(string(T.InterferenceMode)) == 0)
            T.InterferenceMode = repmat(string(sixgr.util.structGet(userMeta, "RuntimeInterferenceMode", ...
                sixgr.truth.SharedDataCompletionRuntime.ternaryInterferenceMode(cfg))), n, 1);
        end
        direction = sixgr.truth.SharedDataCompletionRuntime.directionFromTable(T);
        T.ConfiguredTxAntennas = repmat(double(sixgr.truth.SharedDataCompletionRuntime.configuredTxAntennaCount(cfg, direction)), n, 1);
        T.ConfiguredRxAntennas = repmat(double(sixgr.truth.SharedDataCompletionRuntime.configuredRxAntennaCount(cfg, direction)), n, 1);
        if ~ismember("ConfiguredLayers", string(T.Properties.VariableNames))
            T.ConfiguredLayers = NaN(n, 1);
        end
        T.ExecutionModel = repmat(string(multiUser.ExecutionModel), n, 1);
        T.BeamSelectionStrategy = repmat(string(sixgr.util.structGet(userMeta, "BeamSelectionStrategy", multiUser.BeamSelectionStrategy)), n, 1);
        T.BeamIndexSet = repmat(string(sixgr.util.structGet(userMeta, "BeamIndexSet", "")), n, 1);
        T = sixgr.truth.SharedDataCompletionRuntime.applyTrialTruthAnnotations(T, sixgr.truth.SharedDataCompletionRuntime.directionFromTable(T), cfg);
        end

        function mode = ternaryInterferenceMode(cfg)
        mode = "none";
        configuredMode = string(sixgr.util.structGet(cfg, "run.interferenceExecutionMode", ""));
        intraCellMode = string(sixgr.util.structGet(cfg, ...
            "run.intraCellInterferenceExecutionMode", "none"));
        if strlength(strtrim(configuredMode)) > 0 && lower(strtrim(configuredMode)) ~= "none"
            mode = configuredMode;
        elseif lower(strtrim(intraCellMode)) == "shared_slot_waveform_superposition"
            mode = intraCellMode;
        elseif logical(sixgr.util.structGet(cfg, "run.useAbstractInterferenceModel", false))
            error("sixgr:truth:AbstractInterferenceModeRemoved", ...
                "run.useAbstractInterferenceModel=true is not allowed in no-proxy waveform LLS.");
        end
        end

        function T = annotateConstellationSamples(T, cfg, multiUser, ueIdx, userMeta, snr_dB, direction)
        if ~istable(T) || isempty(T)
            T = table();
            return;
        end
        n = height(T);
        T=sixgr.truth.CoupledRadioIdentity.annotateDataEvidence(T,cfg,ueIdx,direction);
        if ~ismember("Direction", string(T.Properties.VariableNames))
            if ismember("direction", string(T.Properties.VariableNames))
                T.Direction = string(T.direction);
            else
                T.Direction = repmat(string(direction), n, 1);
            end
        end
        if ~ismember("Modulation", string(T.Properties.VariableNames)) && ismember("modulation", string(T.Properties.VariableNames))
            T.Modulation = string(T.modulation);
        end
        if ~ismember("SNR_dB", string(T.Properties.VariableNames))
            if ismember("snr_db", string(T.Properties.VariableNames))
                T.SNR_dB = double(T.snr_db);
            else
                T.SNR_dB = repmat(double(snr_dB), n, 1);
            end
        end
        if ~ismember("Modulation", string(T.Properties.VariableNames))
            T.Modulation = strings(n, 1);
        end
        if ~ismember("BeamSelectionStrategy", string(T.Properties.VariableNames))
            T.BeamSelectionStrategy = repmat(string(sixgr.util.structGet(userMeta, "BeamSelectionStrategy", ...
                sixgr.util.structGet(multiUser, "BeamSelectionStrategy", "missing_from_config"))), n, 1);
        end
        if ~ismember("ConfiguredTxAntennas", string(T.Properties.VariableNames))
            T.ConfiguredTxAntennas = repmat(double(sixgr.truth.SharedDataCompletionRuntime.configuredTxAntennaCount(cfg, direction)), n, 1);
        end
        if ~ismember("ConfiguredRxAntennas", string(T.Properties.VariableNames))
            T.ConfiguredRxAntennas = repmat(double(sixgr.truth.SharedDataCompletionRuntime.configuredRxAntennaCount(cfg, direction)), n, 1);
        end
        T = sixgr.truth.SharedDataCompletionRuntime.canonicalizeConstellationSampleTable(T, direction, snr_dB);
        end

        function T = canonicalizeConstellationSampleTable(T, direction, snr_dB)
        if ~(istable(T) && ~isempty(T))
            return;
        end
        n = height(T);
        if ~ismember("Direction", string(T.Properties.VariableNames))
            T.Direction = repmat(string(direction), n, 1);
        end
        if ~ismember("SNR_dB", string(T.Properties.VariableNames))
            T.SNR_dB = repmat(double(snr_dB), n, 1);
        end
        if ~ismember("Modulation", string(T.Properties.VariableNames))
            T.Modulation = sixgr.truth.SharedDataCompletionRuntime.constellationStringColumn(T, ["modulation","RuntimeModulation"], strings(n, 1));
        end
        if ~ismember("TBId", string(T.Properties.VariableNames))
            if all(ismember(["Frame","Slot"], string(T.Properties.VariableNames)))
                T.TBId = double(T.Frame) .* 10000 + double(T.Slot);
            else
                T.TBId = nan(n, 1);
            end
        end
        if ismember("TxReal", string(T.Properties.VariableNames)) && ~ismember("ReferenceSymbolReal", string(T.Properties.VariableNames))
            T.ReferenceSymbolReal = T.TxReal;
        end
        if ismember("TxImag", string(T.Properties.VariableNames)) && ~ismember("ReferenceSymbolImag", string(T.Properties.VariableNames))
            T.ReferenceSymbolImag = T.TxImag;
        end
        if ~ismember("MCSIndex", string(T.Properties.VariableNames)) && ismember("MCS", string(T.Properties.VariableNames))
            T.MCSIndex = double(T.MCS);
        end
        if ~ismember("PostEqSINR_dB", string(T.Properties.VariableNames)) && ismember("MeasuredSINR_dB", string(T.Properties.VariableNames))
            T.PostEqSINR_dB = double(T.MeasuredSINR_dB);
        end
        if ~ismember("EVM_rms_pct", string(T.Properties.VariableNames))
            if ismember("evm_rms_pct", string(T.Properties.VariableNames))
                T.EVM_rms_pct = double(T.evm_rms_pct);
            elseif ismember("EVM_rms", string(T.Properties.VariableNames))
                T.EVM_rms_pct = double(T.EVM_rms) .* 100;
            elseif ismember("SymbolEVM_rms", string(T.Properties.VariableNames))
                T.EVM_rms_pct = double(T.SymbolEVM_rms) .* 100;
            else
                T.EVM_rms_pct = nan(n, 1);
            end
        end
        if ~ismember("EVM_dB", string(T.Properties.VariableNames))
            if ismember("evm_db", string(T.Properties.VariableNames))
                T.EVM_dB = double(T.evm_db);
            elseif ismember("EVM_rms", string(T.Properties.VariableNames))
                T.EVM_dB = 20 .* log10(max(double(T.EVM_rms), realmin));
            elseif ismember("SymbolEVM_rms", string(T.Properties.VariableNames))
                T.EVM_dB = 20 .* log10(max(double(T.SymbolEVM_rms), realmin));
            else
                T.EVM_dB = nan(n, 1);
            end
        end
        if ~ismember("Normalization", string(T.Properties.VariableNames))
            if any(ismember(["normalization","RuntimeNormalization"], string(T.Properties.VariableNames)))
                T.Normalization = sixgr.truth.SharedDataCompletionRuntime.constellationStringColumn(T, ["normalization","RuntimeNormalization"], ...
                    repmat("unavailable_normalization_not_recorded", n, 1));
            else
                T.Normalization = repmat("unavailable_normalization_not_recorded", n, 1);
            end
        end
        if ~ismember("TruthStatus", string(T.Properties.VariableNames))
            T.TruthStatus = sixgr.truth.SharedDataCompletionRuntime.constellationStringColumn(T, ["truth_status","RuntimeTruthStatus"], ...
                repmat("real_lls_evidence", n, 1));
        end

        T.direction = sixgr.truth.SharedDataCompletionRuntime.constellationStringColumn(T, ["direction","Direction","RuntimeDirection"], repmat(string(direction), n, 1));
        T.ue_id = sixgr.truth.SharedDataCompletionRuntime.constellationNumericColumn(T, ["ue_id","UEIndex","UEId","UEID","RNTI"]);
        T.slot = sixgr.truth.SharedDataCompletionRuntime.constellationNumericColumn(T, ["slot","Slot","RuntimeSlot"]);
        T.tb_id = sixgr.truth.SharedDataCompletionRuntime.constellationNumericColumn(T, ["tb_id","TBId"]);
        T.layer = sixgr.truth.SharedDataCompletionRuntime.constellationNumericColumn(T, ["layer","LayerIndex","Layer"]);
        T.modulation = sixgr.truth.SharedDataCompletionRuntime.constellationStringColumn(T, ["modulation","Modulation","RuntimeModulation"], strings(n, 1));
        T.mcs_index = sixgr.truth.SharedDataCompletionRuntime.constellationNumericColumn(T, ["mcs_index","MCSIndex","MCS"]);
        T.snr_db = sixgr.truth.SharedDataCompletionRuntime.constellationNumericColumn(T, ["snr_db","SNR_dB","RuntimeSNR_dB"]);
        T.posteq_sinr_db = sixgr.truth.SharedDataCompletionRuntime.constellationNumericColumn(T, ["posteq_sinr_db","PostEqSINR_dB","MeasuredSINR_dB","MeasuredTrialSINR_dB"]);
        T.symbol_index = sixgr.truth.SharedDataCompletionRuntime.constellationNumericColumn(T, ["symbol_index","SampleIndex"]);
        T.reference_symbol_i = sixgr.truth.SharedDataCompletionRuntime.constellationNumericColumn(T, ["reference_symbol_i","ReferenceSymbolReal","TxReal"]);
        T.reference_symbol_q = sixgr.truth.SharedDataCompletionRuntime.constellationNumericColumn(T, ["reference_symbol_q","ReferenceSymbolImag","TxImag"]);
        T.equalized_i = sixgr.truth.SharedDataCompletionRuntime.constellationNumericColumn(T, ["equalized_i","EqualizedReal"]);
        T.equalized_q = sixgr.truth.SharedDataCompletionRuntime.constellationNumericColumn(T, ["equalized_q","EqualizedImag"]);
        T.evm_rms_pct = sixgr.truth.SharedDataCompletionRuntime.constellationNumericColumn(T, ["evm_rms_pct","EVM_rms_pct","RuntimeEVMRms_pct"]);
        T.evm_db = sixgr.truth.SharedDataCompletionRuntime.constellationNumericColumn(T, ["evm_db","EVM_dB","RuntimeEVM_dB"]);
        T.normalization = sixgr.truth.SharedDataCompletionRuntime.constellationStringColumn(T, ["Normalization","normalization","RuntimeNormalization"], ...
            repmat("unavailable_normalization_not_recorded", n, 1));
        T.truth_status = sixgr.truth.SharedDataCompletionRuntime.constellationStringColumn(T, ["TruthStatus","truth_status","RuntimeTruthStatus"], ...
            repmat("real_lls_evidence", n, 1));
        T = sixgr.truth.SharedDataCompletionRuntime.disambiguateConstellationCaseCollisionColumns(T);
        end

        function T = disambiguateConstellationCaseCollisionColumns(T)
        renameMap = [ ...
            "Direction", "RuntimeDirection"; ...
            "Modulation", "RuntimeModulation"; ...
            "SNR_dB", "RuntimeSNR_dB"; ...
            "Slot", "RuntimeSlot"; ...
            "EVM_rms_pct", "RuntimeEVMRms_pct"; ...
            "EVM_dB", "RuntimeEVM_dB"; ...
            "Normalization", "RuntimeNormalization"];
        for i = 1:size(renameMap, 1)
            src = renameMap(i, 1);
            dst = renameMap(i, 2);
            names = string(T.Properties.VariableNames);
            if ~ismember(src, names)
                continue;
            end
            collidesCaseInsensitive = any(strcmpi(names, src) & names ~= src);
            if ~collidesCaseInsensitive
                continue;
            end
            target = dst;
            while ismember(target, names)
                T.(char(src)) = [];
                break;
            end
            if ~ismember(src, string(T.Properties.VariableNames))
                continue;
            end
            T = renamevars(T, src, target);
        end
        end

        function values = constellationNumericColumn(T, names)
        values = nan(height(T), 1);
        names = string(names);
        fallback = values;
        haveFallback = false;
        for i = 1:numel(names)
            if ~ismember(names(i), string(T.Properties.VariableNames))
                continue;
            end
            try
                candidate = double(T.(names(i)));
            catch
                candidate = str2double(string(T.(names(i))));
            end
            candidate = reshape(candidate, [], 1);
            if numel(candidate) == height(T)
                if any(isfinite(candidate))
                    values = candidate;
                    return;
                end
                if ~haveFallback
                    fallback = candidate;
                    haveFallback = true;
                end
            end
        end
        if haveFallback
            values = fallback;
        end
        end

        function values = constellationStringColumn(T, names, defaultValues)
        n = height(T);
        values = string(defaultValues);
        if isscalar(values) && n ~= 1
            values = repmat(values, n, 1);
        else
            values = reshape(values, [], 1);
            if numel(values) ~= n
                if isempty(values)
                    values = strings(n, 1);
                else
                    values = repmat(values(1), n, 1);
                end
            end
        end
        names = string(names);
        fallback = values;
        haveFallback = false;
        for i = 1:numel(names)
            if ~ismember(names(i), string(T.Properties.VariableNames))
                continue;
            end
            try
                candidate = string(T.(names(i)));
            catch
                continue;
            end
            candidate = candidate(:);
            if isscalar(candidate) && n ~= 1
                candidate = repmat(candidate, n, 1);
            end
            if numel(candidate) ~= n
                continue;
            end
            candidate(ismissing(candidate)) = "";
            if any(strlength(strtrim(candidate)) > 0)
                values = candidate;
                return;
            end
            if ~haveFallback
                fallback = candidate;
                haveFallback = true;
            end
        end
        if haveFallback
            values = fallback;
        end
        end

        function nTx = configuredTxAntennaCount(cfg, direction)
        direction = upper(string(direction));
        if direction == "UL"
            nTx = sixgr.phy.ul.resolveULDirectionalAntennaCount(cfg, "tx", 1);
        else
            nTx = double(sixgr.util.structGet(cfg, "scenario.bs.nTxAnt", ...
                sixgr.util.structGet(cfg, "channel.nTxAnt", sixgr.util.structGet(cfg, "phy.nTxAnt", 1))));
        end
        if ~(isscalar(nTx) && isfinite(nTx) && nTx >= 1)
            nTx = 1;
        end
        nTx = max(1, round(nTx));
        end

        function nRx = configuredRxAntennaCount(cfg, direction)
        direction = upper(string(direction));
        if direction == "UL"
            nRx = sixgr.phy.ul.resolveULDirectionalAntennaCount(cfg, "rx", 1);
        else
            nRx = double(sixgr.util.structGet(cfg, "scenario.ue.nRxAnt", ...
                sixgr.util.structGet(cfg, "channel.nRxAnt", sixgr.util.structGet(cfg, "phy.nRxAnt", 1))));
        end
        if ~(isscalar(nRx) && isfinite(nRx) && nRx >= 1)
            nRx = 1;
        end
        nRx = max(1, round(nRx));
        end

        function direction = directionFromTable(T)
        direction = "DL";
        if istable(T) && ~isempty(T) && ismember("Direction", string(T.Properties.VariableNames))
            direction = string(T.Direction(1));
        end
        end

        function snapshot = unavailablePHYSignalDiagnostic(direction)
        snapshot = struct( ...
            "Available", false, ...
            "Reason", "same_trial_runtime_evidence_unavailable", ...
            "Direction", upper(string(direction)), ...
            "SnapshotID", "", ...
            "Metadata", struct(), ...
            "SourceTable", table());
        end

        function selected = selectPHYSignalDiagnostic(existing, candidate)
        selected = existing;
        if ~(isstruct(candidate) && isscalar(candidate) && ...
                logical(sixgr.util.structGet(candidate, "Available", false)))
            return;
        end
        if ~(isstruct(existing) && isscalar(existing) && ...
                logical(sixgr.util.structGet(existing, "Available", false)))
            selected = candidate;
            return;
        end

        candidateRank = sixgr.truth.SharedDataCompletionRuntime.pHYSignalDiagnosticRank(candidate);
        existingRank = sixgr.truth.SharedDataCompletionRuntime.pHYSignalDiagnosticRank(existing);
        firstDifference = find(candidateRank ~= existingRank, 1, "first");
        if ~isempty(firstDifference) && candidateRank(firstDifference) < existingRank(firstDifference)
            selected = candidate;
            return;
        end
        if isempty(firstDifference) && ...
                string(sixgr.util.structGet(candidate,"SnapshotID","")) == ...
                string(sixgr.util.structGet(existing,"SnapshotID",""))
            % The shared receive path first creates a practical-receiver snapshot,
            % then augments that same trial after CRC with captured channel arrays.
            % Preserve earliest-trial selection while allowing the completed copy
            % of that exact SnapshotID to replace its pre-decode form.
            candidateEvidence = sixgr.truth.SharedDataCompletionRuntime.pHYSignalDiagnosticEvidenceRank(candidate);
            existingEvidence = sixgr.truth.SharedDataCompletionRuntime.pHYSignalDiagnosticEvidenceRank(existing);
            evidenceDifference = find(candidateEvidence ~= existingEvidence, 1, "first");
            if ~isempty(evidenceDifference) && ...
                    candidateEvidence(evidenceDifference) > existingEvidence(evidenceDifference)
                selected = candidate;
            end
        end
        end

        function rank = pHYSignalDiagnosticEvidenceRank(snapshot)
        T = sixgr.util.structGet(snapshot,"SourceTable",table());
        if ~(istable(T) && ~isempty(T))
            rank = [0 0 0];
            return;
        end
        names = string(T.Properties.VariableNames);
        provenanceColumns = ["AngleCoordinateFrame","AngleEvidenceSource", ...
            "RuntimeChannelLinkKey","RuntimeChannelStateKey", ...
            "RuntimeChannelReciprocityDirection","RuntimeChannelReciprocitySource", ...
            "RuntimeChannelReciprocityApproximationMode"];
        schemaComplete = all(ismember(provenanceColumns,names));
        angleComplete = false;
        if schemaComplete && ismember("Panel",names)
            angleMask = string(T.Panel)=="runtime_channel_angles";
            if any(angleMask)
                angleComplete = true;
                for field = provenanceColumns
                    column = T.(char(field));
                    values = lower(strtrim(string(column(angleMask))));
                    angleComplete = angleComplete && all(~ismissing(values) & ...
                        strlength(values)>0 & ~ismember(values,["nan","<missing>","null"]));
                end
            end
        end
        postChannelComplete = ismember("Panel",names) && ismember("Series",names) && ...
            any(string(T.Panel)=="time_domain" & string(T.Series)=="post_channel");
        rank = [double(schemaComplete) double(angleComplete) double(postChannelComplete)];
        end

        function rank = pHYSignalDiagnosticRank(snapshot)
        meta = sixgr.util.structGet(snapshot, "Metadata", struct());
        rank = [ ...
            double(sixgr.util.structGet(meta, "ConfiguredSNR_dB", Inf)), ...
            double(sixgr.util.structGet(meta, "Frame", Inf)), ...
            double(sixgr.util.structGet(meta, "Slot", Inf)), ...
            double(sixgr.util.structGet(meta, "UEIndex", Inf)), ...
            double(sixgr.util.structGet(meta, "RNTI", Inf))];
        rank(~isfinite(rank)) = Inf;
        end

        function runtimeState = recordPHYSignalDiagnostic(runtimeState, direction, candidate)
        direction = upper(string(direction));
        if ~any(direction == ["DL","UL"])
            return;
        end
        if ~isfield(runtimeState, "PHYSignalDiagnostics") || ...
                ~isstruct(runtimeState.PHYSignalDiagnostics)
            runtimeState.PHYSignalDiagnostics = struct( ...
                "DL", sixgr.truth.SharedDataCompletionRuntime.unavailablePHYSignalDiagnostic("DL"), ...
                "UL", sixgr.truth.SharedDataCompletionRuntime.unavailablePHYSignalDiagnostic("UL"));
        end
        field = char(direction);
        existing = sixgr.util.structGet(runtimeState.PHYSignalDiagnostics, field, ...
            sixgr.truth.SharedDataCompletionRuntime.unavailablePHYSignalDiagnostic(direction));
        runtimeState.PHYSignalDiagnostics.(field) = ...
            sixgr.truth.SharedDataCompletionRuntime.selectPHYSignalDiagnostic(existing, candidate);
        end

    end
end
