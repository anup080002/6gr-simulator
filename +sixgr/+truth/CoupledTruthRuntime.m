classdef CoupledTruthRuntime
%COUPLEDTRUTHRUNTIME Canonical per-slot runtime state for coupled LLS truth.
% Keep this file ASCII-only.

methods(Static)
    function state = initialize(cfg, runFolder, multiUser, controlTrials, totalTrafficFrames)
        if nargin < 4 || ~isstruct(controlTrials)
            controlTrials = struct();
        end
        if nargin < 5 || ~(isnumeric(totalTrafficFrames) && isscalar(totalTrafficFrames) && isfinite(totalTrafficFrames) && totalTrafficFrames >= 1)
            totalTrafficFrames = max(1, round(double(sixgr.util.structGet(cfg, "run.numFrames", 1))));
        end
        cfgMob = sixgr.truth.CoupledTruthRuntime.prepareMobilityConfig(cfg, multiUser);
        cfgLargeScale = sixgr.truth.CoupledTruthRuntime.prepareLargeScaleConfig(cfgMob);
        scenarioName = string(sixgr.util.structGet(cfgMob, "scenario.name", ...
            sixgr.util.structGet(cfgMob, "meta.lls6gScenarioID", "UMa")));
        seed = double(sixgr.util.structGet(cfgMob, "run.seed", 1));
        layoutStruct = sixgr.scenario.generateLayout(cfgMob, scenarioName);
        ue = sixgr.scenario.dropUEs(cfgMob, layoutStruct, scenarioName);
        [bsAntennaRuntime, ueAntennaRuntime, antennaConfigResolvedTable] = ...
            sixgr.truth.CoupledTruthRuntime.buildRuntimeAntennaState(cfgMob, layoutStruct, ue);
        harqDL = sixgr.l2.mac.HARQEntity(cfg, "Direction", "DL");
        harqUL = sixgr.l2.mac.HARQEntity(cfg, "Direction", "UL");
        numHarqProc = max(double(harqDL.NumProcesses), double(harqUL.NumProcesses));
        nUsers = size(ue.pos_m, 1);
        nCells = size(layoutStruct.bs.pos_m, 1);
        symbolsPerSlot = max(1, round(double(sixgr.util.structGet(cfgMob, "phy.numerology.symbolsPerSlot", 14))));

        state = struct();
        state.RunFolder = string(runFolder);
        state.MultiUser = multiUser;
        state.CfgMobility = cfgMob;
        state.CfgLargeScale = cfgLargeScale;
        state.NoiseOperatingMode = char(sixgr.truth.CoupledTruthRuntime.noiseOperatingModeFromConfig(cfgMob));
        state.Layout = layoutStruct;
        state.UE = ue;
        state.BSAntennaRuntime = bsAntennaRuntime;
        state.UEAntennaRuntime = ueAntennaRuntime;
        state.AntennaConfigResolvedTable = antennaConfigResolvedTable;
        state.MobilityModel = [];
        state.PLModel = sixgr.channel.TR38901Plus(cfgLargeScale, "Seed", seed + 901);
        state.BeamIdx = ones(nUsers, nCells);
        state.BeamGain_dB = zeros(nUsers, nCells);
        state.LargeScaleState = struct();
        state.CurrentServingIdx = zeros(nUsers, 1);
        state.CurrentServingMetric_dBm = nan(nUsers, 1);
        state.CurrentUELat = nan(nUsers, 1);
        state.CurrentUELon = nan(nUsers, 1);
        state.PrevServing = zeros(nUsers, 1);
        state.CurrentSlot = 0;
        state.CurrentCanonicalSlot = 0;
        state.CurrentFrame = 0;
        state.CurrentFrameLocal = NaN;
        state.CurrentSlotDLAllowed = true;
        state.CurrentSlotULAllowed = true;
        state.CurrentSlotDuplexLabel = "FDD_DLUL";
        state.CurrentSlotIsSpecial = false;
        state.CurrentSlotDLSymbolStart = 0;
        state.CurrentSlotDLNumSymbols = double(symbolsPerSlot);
        state.CurrentSlotGuardSymbolStart = double(symbolsPerSlot);
        state.CurrentSlotGuardNumSymbols = 0;
        state.CurrentSlotULSymbolStart = 0;
        state.CurrentSlotULNumSymbols = double(symbolsPerSlot);
        state.DLCompletedFrames = 0;
        state.ULCompletedFrames = 0;
        state.DLCompletedSlots = 0;
        state.ULCompletedSlots = 0;
        state.FramesPerSweepPoint = NaN;
        state.CanonicalSlotsPerSweepPoint = NaN;
        state.CurrentSNR_dB = NaN;
        state.CurrentDirection = "";
        state.CurrentUEIndex = NaN;
        state.NumUsers = nUsers;
        state.MIMOExecutionState = struct( ...
            "Initialized", true, ...
            "ExecutionSource", "sixgr.mimo.executeSpatialComposite", ...
            "LastCompositeSummary", struct());
        state.RunState = sixgr.truth.CoupledTruthRuntime.initializeRunState(cfgMob, multiUser, totalTrafficFrames);
        state.SlotTraceTable = struct2table(repmat(sixgr.truth.CoupledTruthRuntime.emptySlotTraceRow(), 0, 1));
        state.SlotDuration_s = sixgr.truth.CoupledTruthRuntime.slotDuration(cfgMob);
        state.SlotsPerFrame = sixgr.truth.CoupledTruthRuntime.slotsPerFrame(cfgMob, state.SlotDuration_s);
        state.MobilityEnabled = logical(sixgr.util.structGet(cfgMob, "scenario.mobility.enable", false));
        state.BeamUpdateSlots = max(1, round(double(sixgr.util.structGet(cfgMob, "system.beam.updatePeriod_slots", 4))));
        state.LargeScaleUpdateSlots = max(1, round(double(sixgr.util.structGet(cfgMob, "system.largeScaleUpdatePeriod_slots", 1))));
        state.SRSSlotPeriod = max(1, round(double(sixgr.util.structGet(cfgMob, "phy.srs.period_slots", 4))));
        state.TRSSlotPeriod = max(1, round(double(sixgr.util.structGet(cfgMob, "phy.trs.period_slots", 4))));
        state.PBCHSlotPeriod = max(10, round(double(sixgr.util.structGet(cfgMob, "phy.pbch.period_slots", 20))));
        state.TopCellCount = min(max(2, round(double(sixgr.util.structGet(cfgMob, "lls6g.users.live_top_cells", 4)))), max(1, nCells));
        state.NumRB = sixgr.truth.CoupledTruthRuntime.estimateNRB(cfgMob);
        state.Bandwidth_Hz = double(sixgr.util.structGet(cfgMob, "channel.bandwidth_Hz", 20e6));
        state.NoiseFigure_dB = double(sixgr.util.structGet(cfgMob, "scenario.ue.noiseFigure_dB", 9));
        state.NBeams = max(1, round(double(sixgr.util.structGet(cfgMob, "system.beam.numBeams", sixgr.util.structGet(cfgMob, "phy.ssb.nBeams", 8)))));
        state.BeamSpanDeg = max(30, min(240, double(sixgr.util.structGet(cfgMob, "system.beam.sectorSpan_deg", 120))));
        state.BeamMaxGain_dB = double(sixgr.util.structGet(cfgMob, "system.beam.maxGain_dB", 12));
        state.ControlTrials = struct("PBCH", sixgr.util.structGet(controlTrials, "PBCH", table()), ...
            "PRACH", sixgr.util.structGet(controlTrials, "PRACH", table()), ...
            "PRACHCorrelationTrace", sixgr.util.structGet(controlTrials, "PRACHCorrelationTrace", table()), ...
            "RAEvidenceTables", sixgr.util.structGet(controlTrials, "RAEvidenceTables", struct()), ...
            "PDCCH", sixgr.util.structGet(controlTrials, "PDCCH", table()), ...
            "PUCCH", sixgr.util.structGet(controlTrials, "PUCCH", table()), ...
            "SRS", sixgr.util.structGet(controlTrials, "SRS", table()), ...
            "TRS", sixgr.util.structGet(controlTrials, "TRS", table()));
        state.InitialAccessLifecycleTraceTable = struct2table(repmat(sixgr.truth.CoupledTruthRuntime.emptyInitialAccessLifecycleRow(), 0, 1));
        state.AccessTransitionLedgerTable = sixgr.monitor.AccessFlowRecorder.emptyLedger();
        state.ControlGating = sixgr.truth.CoupledTruthRuntime.resolveControlGatingConfig(cfgMob, multiUser);
        state.CellAcquisitionState = repmat(string(state.ControlGating.PBCHInitialState), nUsers, 1);
        state.AccessState = repmat(string(state.ControlGating.PRACHInitialState), nUsers, 1);
        state.LastPDCCHStatus = repmat("not_attempted", nUsers, 1);
        state.SRSValidityState = repmat(string(state.ControlGating.SRSInitialState), nUsers, 1);
        state.CSIValidityState = repmat(string(state.ControlGating.CSIInitialState), nUsers, 1);
        state.ReferenceSignalMeasurementTable = struct2table(repmat( ...
            sixgr.truth.CoupledTruthRuntime.emptyReferenceSignalMeasurementRow(), 0, 1));
        state.ControlEligibility = false(nUsers, 1);
        state.SchedulingEligibility = false(nUsers, 1);
        state.CoverageEligibility = true(nUsers, 1);
        state.CoverageOutageState = repmat("not_evaluated", nUsers, 1);
        state.LastSuccessfulPBCHSlotByUE = nan(nUsers, 1);
        state.LastSuccessfulPRACHSlotByUE = nan(nUsers, 1);
        state.LastTimingAdvanceSamplesByUE = nan(nUsers, 1);
        state.LastTimingAdvanceUsByUE = nan(nUsers, 1);
        state.TimeAlignmentState = repmat("not_time_aligned", nUsers, 1);
        state.LastTimingAdvanceSourceByUE = repmat("", nUsers, 1);
        state.LastTimingAdvanceUpdateSlotByUE = nan(nUsers, 1);
        state.LastTimingAdvanceServingCellByUE = nan(nUsers, 1);
        state.LastTimingAdvanceServingDistanceMByUE = nan(nUsers, 1);
        state.TimingAdvanceDriftSamplesByUE = nan(nUsers, 1);
        state.TimingAdvanceDriftUsByUE = nan(nUsers, 1);
        state.TimingAdvanceUpdateRequiredByUE = false(nUsers, 1);
        state.TimingAdvanceUpdateStatusByUE = repmat("not_evaluated", nUsers, 1);
        state.LastSuccessfulPDCCHSlotByUE = nan(nUsers, 1);
        state.LastSuccessfulPUCCHSlotByUE = nan(nUsers, 1);
        state.LastSuccessfulSRSSlotByUE = nan(nUsers, 1);
        state.LastSRSObservedSlotByUE = nan(nUsers, 1);
        state.TRSValidityStateByCell = repmat(string(state.ControlGating.TRSInitialState), nCells, 1);
        state.TrackingEligibilityByCell = false(nCells, 1);
        state.LastSuccessfulTRSSlotByCell = nan(nCells, 1);
        state.LastTRSObservedSlotByCell = nan(nCells, 1);
        state.LastEstimatedTRSDopplerHzByCell = nan(nCells, 1);
        state.TRSFailureCountByCell = zeros(nCells, 1);
        state.ReceiverTrackingStateByCell = repmat(sixgr.truth.CoupledTruthRuntime.emptyReceiverTrackingStateRow(), max(0, nCells), 1);
        for cellIdx = 1:max(0, nCells)
            state.ReceiverTrackingStateByCell(cellIdx).ServingCell = double(cellIdx);
        end
        state.ReceiverTrackingTraceTable = struct2table(repmat(sixgr.truth.CoupledTruthRuntime.emptyReceiverTrackingTraceRow(), 0, 1));
        state.PBCHFailureCount = zeros(nUsers, 1);
        state.PRACHFailureCount = zeros(nUsers, 1);
        state.PDCCHFailureCount = zeros(nUsers, 1);
        state.PUCCHFailureCount = zeros(nUsers, 1);
        state.PUCCHCrashCount = zeros(nUsers, 1);
        state.SRSInvalidEventCount = zeros(nUsers, 1);
        state.DLDecodeSuccessCountByUE = zeros(nUsers, 1);
        state.ULDecodeSuccessCountByUE = zeros(nUsers, 1);
        state.DLDecodeReuseSuccessCountByUE = zeros(nUsers, 1);
        state.ULDecodeReuseSuccessCountByUE = zeros(nUsers, 1);
        state.PUCCHChannelStateByUE = cell(nUsers, 1);
        state.SRSChannelStateByUE = cell(nUsers, 1);
        state.RuntimeChannelStates = repmat(sixgr.channel.ChannelFactory.emptyRuntimeChannelState(), 0, 1);
        state.SchedulingOpportunitiesBlockedByGatingCount = zeros(nUsers, 1);
        state.GrantsBlockedByGatingCount = zeros(nUsers, 1);
        state.ServingTraceTable = struct2table(repmat(sixgr.truth.CoupledTruthRuntime.emptyServingRow(), 0, 1));
        state.MeasurementTraceTable = struct2table(repmat(sixgr.truth.CoupledTruthRuntime.emptyMeasurementRow(), 0, 1));
        state.ReselectionEventTable = struct2table(repmat(sixgr.truth.CoupledTruthRuntime.emptyReselectionRow(), 0, 1));
        state.CoverageSnapshotTable = struct2table(repmat(sixgr.truth.CoupledTruthRuntime.emptyCoverageRow(), 0, 1));
        state.UserPerformanceTable = struct2table(repmat(sixgr.truth.CoupledTruthRuntime.emptyUserPerformanceRow(), 0, 1));
        state.CoverageLayerTable = struct2table(repmat(sixgr.truth.CoupledTruthRuntime.emptyCoverageLayerRow(), 0, 1));
        state.HARQTimelineTable = struct2table(repmat(sixgr.truth.CoupledTruthRuntime.emptyHARQTimelineRow(), 0, 1));
        state.HARQSummaryTable = struct2table(repmat(sixgr.truth.CoupledTruthRuntime.emptyHARQSummaryRow(), 0, 1));
        state.PacketDeliveryLedgerTable = struct2table(repmat(sixgr.truth.CoupledTruthRuntime.emptyPacketDeliveryLedgerRow(), 0, 1));
        state.PacketSDULedgerTable = struct2table(repmat(sixgr.truth.CoupledTruthRuntime.emptyPacketSDULedgerRow(), 0, 1));
        state.DLHarq = harqDL;
        state.ULHarq = harqUL;
        state.PendingFeedbackTable = struct2table(repmat(sixgr.truth.CoupledTruthRuntime.emptyFeedbackRow(), 0, 1));
        state.PUCCHGrantTraceTable = struct2table(repmat(sixgr.truth.CoupledTruthRuntime.emptyPUCCHGrantRow(), 0, 1));
        state.DLCombinedLLR = cell(nUsers, numHarqProc);
        state.ULCombinedLLR = cell(nUsers, numHarqProc);
        state.HARQFeedbackSlots = max(1, round(double(sixgr.util.structGet(cfg, "phy.harq.feedbackTimingSlots", 4))));
        state.CSIFeedbackSlots = sixgr.truth.CoupledTruthRuntime.resolveCSIFeedbackSlots(cfg);
        state.LastPRACHSlotByUE = zeros(nUsers, 1);
        state.LastSRSSlotByUE = zeros(nUsers, 1);
        state.DLStats = repmat(sixgr.truth.CoupledTruthRuntime.emptyDirectionStatRow(), nUsers, 1);
        state.ULStats = repmat(sixgr.truth.CoupledTruthRuntime.emptyDirectionStatRow(), nUsers, 1);
        state.TrafficFrameCount = max(1, round(double(totalTrafficFrames)));
        state.Traffic = sixgr.truth.CoupledTruthRuntime.buildRuntimeTraffic(cfgMob, nUsers, state.TrafficFrameCount, state.SlotDuration_s);
        state.LastTrafficFrameApplied = 0;
        state.DLQueueBits = zeros(nUsers, 1);
        state.ULQueueBits = zeros(nUsers, 1);
        state.DLOfferedBits = zeros(nUsers, 1);
        state.ULOfferedBits = zeros(nUsers, 1);
        state.DLTransmittedBits = zeros(nUsers, 1);
        state.ULTransmittedBits = zeros(nUsers, 1);
        state.PendingCSITable = struct2table(repmat(sixgr.truth.CoupledTruthRuntime.emptyCSIReportRow(), 0, 1));
        state.LatestDLFeedback = repmat(sixgr.truth.CoupledTruthRuntime.emptyLatestFeedbackRow(), nUsers, 1);
        state.LatestULFeedback = repmat(sixgr.truth.CoupledTruthRuntime.emptyLatestFeedbackRow(), nUsers, 1);
        state.DLLinkAdaptationState = cell(nUsers, 1);
        state.ULLinkAdaptationState = cell(nUsers, 1);
        state.LastPBCHSlot = 0;
        state.LastTRSSlot = 0;
        state.DLSchedulers = sixgr.truth.CoupledTruthRuntime.createSchedulers(cfgMob, nCells, "DL", state.DLHarq);
        state.ULSchedulers = sixgr.truth.CoupledTruthRuntime.createSchedulers(cfgMob, nCells, "UL", state.ULHarq);
        state.SchedulerDecisionTable = table();
        state.DLGrantTraceTable = struct2table(repmat(sixgr.truth.CoupledTruthRuntime.emptyGrantRow(), 0, 1));
        state.ULGrantTraceTable = struct2table(repmat(sixgr.truth.CoupledTruthRuntime.emptyGrantRow(), 0, 1));
        state.LastDLGrantCount = 0;
        state.LastULGrantCount = 0;
        state.LastDLGrantedUsers = 0;
        state.LastULGrantedUsers = 0;
        state.LastDLActiveUsers = 0;
        state.LastULActiveUsers = 0;
        state = sixgr.truth.CoupledTruthRuntime.refreshControlStateImpl(state);
    end

    function state = advanceFrame(state, cfg, multiUser, absoluteFrame, snr_dB)
        state = sixgr.truth.CoupledTruthRuntime.advanceFrameImpl(state, absoluteFrame, snr_dB);
    end

    function state = beginSlot(state, cfg, userCfg, ueIdx, direction, sweepIdx, sweepCount, absoluteFrame, totalFrames, snr_dB)
        state = sixgr.truth.CoupledTruthRuntime.beginSlotImpl(state, ueIdx, direction, sweepIdx, sweepCount, absoluteFrame, totalFrames, snr_dB);
    end

    function [cfgU, state] = applyUserContext(cfgIn, state, ueIdx, direction)
        [cfgU, state] = sixgr.truth.CoupledTruthRuntime.applyUserContextImpl(cfgIn, state, ueIdx, direction);
    end

    function state = startSlot(state, cfg, direction, sweepIdx, sweepCount, absoluteFrame, totalFrames, snr_dB)
        state = sixgr.truth.CoupledTruthRuntime.startSlotImpl(state, cfg, direction, sweepIdx, sweepCount, absoluteFrame, totalFrames, snr_dB);
    end

    function state = setCurrentUE(state, ueIdx, direction)
        state.CurrentDirection = upper(string(direction));
        state.CurrentUEIndex = double(ueIdx);
    end

    function [state, grants, info] = scheduleDirection(state, cfg, direction)
        [state, grants, info] = sixgr.truth.CoupledTruthRuntime.scheduleDirectionImpl(state, cfg, direction);
    end

    function [state, context, grantRow] = buildTrialContextFromGrant(state, cfg, ueIdx, direction, grant)
        [state, context, grantRow] = sixgr.truth.CoupledTruthRuntime.buildTrialContextFromGrantImpl(state, cfg, ueIdx, direction, grant);
    end

    function state = commitRuntimeChannelState(state, channelState)
        state = sixgr.truth.CoupledTruthRuntime.commitRuntimeChannelStateImpl(state, channelState);
    end

    function assertSharedSlotInterferenceBundle(bundle, context)
        if nargin < 2
            context = "coupled_truth_runtime";
        end
        if isempty(bundle) || ~isstruct(bundle) || isempty(fieldnames(bundle))
            return;
        end
        for ii = 1:numel(bundle)
            entry = bundle(ii);
            mode = lower(strtrim(string(sixgr.util.structGet(entry, "InterferenceMode", ""))));
            if mode ~= "full_per_link_channel_waveform_sum" && mode ~= "shared_slot_waveform_superposition"
                continue;
            end
            if logical(sixgr.util.structGet(entry, "Muted", false))
                continue;
            end
            hasContribution = sixgr.truth.CoupledTruthRuntime.interferenceEntryHasSharedSlotContribution(entry);
            hasWorkerCache = strlength(strtrim(string(sixgr.util.structGet(entry, "CacheKey", "")))) > 0 && ...
                isfinite(double(sixgr.util.structGet(entry, "CacheIndex", NaN)));
            if ~(hasContribution || hasWorkerCache)
                error("sixgr:truth:MissingSharedSlotInterferenceContribution", ...
                    "Full-truth interference entry %d in %s has no receiver-side shared-slot contribution waveform. The runtime must build all Tx waveforms, propagate persistent links, and pass contribution samples instead of asking the victim path to regenerate interferers.", ...
                    ii, char(string(context)));
            end
        end
    end

    function out = executeMIMOCompositeRuntime(txContributors, rxContexts, cfg, varargin)
        if nargin < 3 || ~isstruct(cfg)
            cfg = struct();
        end
        out = sixgr.mimo.executeSpatialComposite(txContributors, rxContexts, cfg, varargin{:});
        out.RuntimeConsumer = "sixgr.truth.CoupledTruthRuntime.executeMIMOCompositeRuntime";
    end

    function tf = interferenceEntryHasSharedSlotContribution(entry)
        tf = false;
        if ~(isstruct(entry) && ~isempty(fieldnames(entry)))
            return;
        end
        fields = ["SharedSlotContributionWaveform", "ContributionWaveform", ...
            "RxContributionWaveform", "PrecomputedRxWaveform", "PrecomputedContributionWaveform"];
        for fi = 1:numel(fields)
            f = char(fields(fi));
            if isfield(entry, f) && ~isempty(entry.(f))
                tf = true;
                return;
            end
        end
    end

    function state = commitGrantExecution(state, ueIdx, direction, grant)
        state = sixgr.truth.CoupledTruthRuntime.commitGrantExecutionImpl(state, ueIdx, direction, grant);
    end

    function context = resolveHARQTrialContext(state, ueIdx, direction)
        context = sixgr.truth.CoupledTruthRuntime.resolveHARQTrialContextImpl(state, ueIdx, direction);
    end

    function feedback = latestFeedbackForDirectionRuntime(state, ueIdx, direction)
        % Public wrapper for non-class helper code in the waveform bundle path.
        feedback = sixgr.truth.CoupledTruthRuntime.latestFeedbackForDirection(state, ueIdx, direction);
    end

    function state = appendGrantTraceRuntime(state, grant, direction, feedback)
        % Public wrapper for queued cross-slot grants built outside the class.
        state = sixgr.truth.CoupledTruthRuntime.appendGrantTrace(state, grant, direction, feedback);
    end

    function state = recordSlotTraceScheduleRuntime(state, direction, info)
        % Public wrapper for queued grants that execute in a later TDD slot.
        state = sixgr.truth.CoupledTruthRuntime.recordSlotTraceSchedule(state, direction, info);
    end

    function sinr_dB = estimateRuntimeWidebandSINRRuntime(state, ueIdx, servingCell, interferenceMode)
        % Public wrapper for waveform-bundle runtime SINR resolution.
        sinr_dB = sixgr.truth.CoupledTruthRuntime.estimateRuntimeWidebandSINR(state, ueIdx, servingCell, interferenceMode);
    end

    function [state, trialT] = completeSlot(state, cfgU, ueIdx, direction, trialT, res)
        [state, trialT] = sixgr.truth.CoupledTruthRuntime.completeSlotImpl(state, cfgU, ueIdx, direction, trialT, res);
    end

    function state = writeTables(state, runFolder)
        state = sixgr.truth.CoupledTruthRuntime.writeTablesImpl(state, runFolder);
    end

    function state = refreshControlState(state)
        state = sixgr.truth.CoupledTruthRuntime.refreshControlStateImpl(state);
    end

    function state = applyPBCHTrial(state, ueIdx, trialT)
        state = sixgr.truth.CoupledTruthRuntime.applyPBCHTrialImpl(state, ueIdx, trialT);
    end

    function state = applyPRACHTrial(state, ueIdx, trialT)
        state = sixgr.truth.CoupledTruthRuntime.applyPRACHTrialImpl(state, ueIdx, trialT);
    end

    function result = runFourStepRARuntime(cfg, varargin)
        result = sixgr.truth.CoupledTruthRuntime.runFourStepRARuntimeImpl(cfg, varargin{:});
    end

    function state = applySRSTrial(state, ueIdx, trialT)
        state = sixgr.truth.CoupledTruthRuntime.applySRSTrialImpl(state, ueIdx, trialT);
    end

    function state = applyTRSTrial(state, servingCell, trialT)
        state = sixgr.truth.CoupledTruthRuntime.applyTRSTrialImpl(state, servingCell, trialT);
    end

    function state = publishReferenceSignalMeasurementRuntime(state, signalType, targetType, targetId, row, varargin)
        state = sixgr.truth.CoupledTruthRuntime.publishReferenceSignalMeasurementImpl( ...
            state, signalType, targetType, targetId, row, varargin{:});
    end

    function result = consumeReferenceSignalMeasurementRuntime(state, signalType, targetType, targetId, consumerSlot, maxAgeSlots)
        if nargin < 6
            maxAgeSlots = inf;
        end
        result = sixgr.truth.CoupledTruthRuntime.consumeReferenceSignalMeasurementImpl( ...
            state, signalType, targetType, targetId, consumerSlot, maxAgeSlots);
    end

    function ageSlots = trsAgeSlotsRuntime(state, servingCell)
        ageSlots = sixgr.truth.CoupledTruthRuntime.trsAgeSlotsForServingCell(state, servingCell);
    end

    function ctx = resolveTRSRuntimeContextRuntime(state, cfg, ueIdx, servingCell)
        ctx = sixgr.truth.CoupledTruthRuntime.resolveTRSRuntimeContext(state, cfg, ueIdx, servingCell);
    end

    function resource = resolvePUCCHResourceAssignmentRuntime(state, feedbackRow)
        resource = sixgr.truth.CoupledTruthRuntime.resolvePUCCHResourceAssignment(state, feedbackRow);
    end

    function dueSlot = resolveHARQFeedbackDueSlotRuntime(state, sourceSlot, numUCIBits)
        if nargin < 3
            numUCIBits = 1;
        end
        dueSlot = sixgr.truth.CoupledTruthRuntime.resolveHARQFeedbackDueSlot(state, sourceSlot, numUCIBits);
    end

    function [state, observed] = observePUCCHFeedbackRuntime(state, feedbackRow)
        [state, observed] = sixgr.truth.CoupledTruthRuntime.observePUCCHFeedback(state, feedbackRow);
        grantId = string(sixgr.truth.CoupledTruthRuntime.rowValue(feedbackRow, "PUCCHGrantId", ""));
        if strlength(strtrim(grantId)) > 0
            state = sixgr.truth.CoupledTruthRuntime.updatePUCCHGrantTraceAfterObservation(state, feedbackRow, observed);
        end
    end

    function state = schedulePUCCHGrantRuntime(state, feedbackRow)
        state = sixgr.truth.CoupledTruthRuntime.appendPUCCHGrantTraceFromFeedback(state, feedbackRow);
    end

    function [grantsOut, blockedT] = excludeULGrantsCollidingWithPUCCHRuntime(state, grantsIn, dueSlot)
        [grantsOut, blockedT] = sixgr.truth.CoupledTruthRuntime.excludeULGrantsCollidingWithPUCCHImpl(state, grantsIn, dueSlot);
    end

    function dueUEs = pucchFeedbackDueUEsRuntime(state, dueSlot)
        [dueUEs, ~, ~, ~, ~] = sixgr.truth.CoupledTruthRuntime.collectPUCCHDueIdentityImpl(state, dueSlot);
        dueUEs = unique(dueUEs(isfinite(dueUEs) & dueUEs >= 1));
    end

    function due = pucchFeedbackDueHARQACKRuntime(state, dueSlot)
        due = sixgr.truth.CoupledTruthRuntime.collectPUCCHDueHARQACKImpl(state, dueSlot);
    end

    function [state, grant, allowExecution] = applyPDCCHGrantTrial(state, grant, direction, trialT)
        [state, grant, allowExecution] = sixgr.truth.CoupledTruthRuntime.applyPDCCHGrantTrialImpl(state, grant, direction, trialT);
    end

    function [state, grant] = blockPDCCHGrantTrial(state, grant, direction, reason)
        [state, grant] = sixgr.truth.CoupledTruthRuntime.blockPDCCHGrantTrialImpl(state, grant, direction, reason);
    end

    function state = cancelUnexecutedHARQGrantRuntime(state, grant, direction)
        state = sixgr.truth.CoupledTruthRuntime.cancelUnexecutedHARQGrantImpl(state, grant, direction);
    end

    function artifacts = mobilityArtifacts(state)
        artifacts = struct("ServingTraceTable", sixgr.util.structGet(state, "ServingTraceTable", table()), ...
            "MeasurementTraceTable", sixgr.util.structGet(state, "MeasurementTraceTable", table()), ...
            "ReselectionEventTable", sixgr.util.structGet(state, "ReselectionEventTable", table()), ...
            "CoverageSnapshotTable", sixgr.util.structGet(state, "CoverageSnapshotTable", table()), ...
            "UserPerformanceTable", sixgr.util.structGet(state, "UserPerformanceTable", table()), ...
            "CoverageLayerTable", sixgr.util.structGet(state, "CoverageLayerTable", table()), ...
            "HARQSummaryTable", sixgr.util.structGet(state, "HARQSummaryTable", table()), ...
            "HARQTimelineTable", sixgr.util.structGet(state, "HARQTimelineTable", table()), ...
            "RunStateTable", struct2table(sixgr.truth.CoupledTruthRuntime.refreshRunState(state)), ...
            "SlotTraceTable", sixgr.util.structGet(state, "SlotTraceTable", table()), ...
            "AntennaConfigResolvedTable", sixgr.util.structGet(state, "AntennaConfigResolvedTable", table()), ...
            "ReceiverTrackingStateTable", sixgr.truth.CoupledTruthRuntime.buildReceiverTrackingStateTable(state), ...
            "ReceiverTrackingTraceTable", sixgr.util.structGet(state, "ReceiverTrackingTraceTable", table()), ...
            "ControlGatingSummaryTable", sixgr.truth.CoupledTruthRuntime.buildControlSummaryTable(state), ...
            "ControlGatingStateTable", sixgr.truth.CoupledTruthRuntime.buildControlStateTable(state), ...
            "SchedulerDecisionTable", sixgr.util.structGet(state, "SchedulerDecisionTable", table()));
    end

    function T = canonicalizePersistedControlReferenceTable(signalName, T)
        if nargin < 2 || ~istable(T)
            T = table();
            return;
        end
        T = sixgr.truth.CoupledTruthRuntime.annotateControlReferenceTrialTableImpl(struct(), signalName, T);
        T = sixgr.truth.canonicalizeLLSLiveSignalChainTable(lower(strrep(char(string(signalName)), "-", "_")), T);
    end

    function T = canonicalizePersistedPUCCHGrantTraceTable(T)
        if nargin < 1 || ~istable(T)
            T = table();
            return;
        end
        T = sixgr.truth.CoupledTruthRuntime.annotatePUCCHGrantTraceTableImpl(struct(), T);
        T = sixgr.truth.canonicalizeLLSLiveSignalChainTable("pucch_grant_trace", T);
    end

    function rowOut = normalizeTelemetryRowToPrototype(rowIn, prototype)
        rowOut = sixgr.truth.CoupledTruthRuntime.normalizeStructRowToPrototype(rowIn, prototype);
    end

    function grant = realignGrantAMCFromMeasuredFeedbackRuntime(grant, feedback, scheduler, cfg, direction)
        grant = sixgr.truth.CoupledTruthRuntime.applyMeasuredFeedbackAMCToGrant( ...
            grant, feedback, scheduler, cfg, direction);
    end

    function csi = resolveMeasuredRuntimeCSIForRowRuntime(row, cfg, direction)
        % Public test wrapper for the measured SINR -> CQI feedback bridge.
        csi = sixgr.truth.CoupledTruthRuntime.resolveMeasuredRuntimeCSIForRow(row, cfg, direction);
    end

    function state = enqueueTrafficForFrameRuntime(state, absoluteFrame)
        % Public wrapper for K2 look-ahead scheduling outside this class.
        state = sixgr.truth.CoupledTruthRuntime.enqueueTrafficForFrame(state, absoluteFrame);
    end
end

methods(Static, Access=private)
    function mode = noiseOperatingModeFromConfig(cfgOrState)
        mode = "";
        cfg = cfgOrState;
        if isstruct(cfgOrState)
            if isfield(cfgOrState, "NoiseOperatingMode")
                mode = string(cfgOrState.NoiseOperatingMode);
            end
            if strlength(strtrim(mode)) == 0 && isfield(cfgOrState, "CfgMobility")
                cfg = cfgOrState.CfgMobility;
            end
        end
        if strlength(strtrim(mode)) == 0
            mode = string(sixgr.util.structGet(cfg, "run.noiseOperatingMode", ...
                "receiver_noise_figure_thermal_noise"));
        end
        mode = lower(strtrim(mode));
        if strlength(mode) == 0
            mode = "receiver_noise_figure_thermal_noise";
        end
    end

    function tf = usesReceiverNoiseMeasurementMode(cfgOrState)
        tf = sixgr.truth.CoupledTruthRuntime.noiseOperatingModeFromConfig(cfgOrState) == ...
            "receiver_noise_figure_thermal_noise";
    end

    function state = advanceFrameImpl(state, absoluteFrame, snr_dB)
        canonicalSlot = max(1, round(double(absoluteFrame(1))));
        snr_dB = double(snr_dB(1));
        beamUpdateSlots = sixgr.truth.CoupledTruthRuntime.scalarOrDefault(sixgr.util.structGet(state, "BeamUpdateSlots", 4), 4);
        largeScaleUpdateSlots = sixgr.truth.CoupledTruthRuntime.scalarOrDefault(sixgr.util.structGet(state, "LargeScaleUpdateSlots", 1), 1);
        mobilityEnabled = logical(sixgr.truth.CoupledTruthRuntime.scalarOrDefault(sixgr.util.structGet(state, "MobilityEnabled", false), false));
        if double(canonicalSlot) == double(sixgr.util.structGet(state, "CurrentCanonicalSlot", 0))
            state.CurrentSNR_dB = double(snr_dB);
            return;
        end
        mobilityAdvanced = false;
        if canonicalSlot > 1 && mobilityEnabled
            [state.UE, state.MobilityModel] = sixgr.scenario.mobility.updatePositions(state.UE, state.CfgMobility, state.SlotDuration_s, state.MobilityModel);
            mobilityAdvanced = true;
        end
        state = sixgr.truth.CoupledTruthRuntime.enqueueTrafficForFrame(state, canonicalSlot);
        doBeamUpdate = (canonicalSlot == 1) || (mod(canonicalSlot - 1, beamUpdateSlots) == 0);
        if doBeamUpdate
            [state.BeamIdx, state.BeamGain_dB] = sixgr.system.selectBestBeamPerLink( ...
                state.UE.pos_m, state.Layout.bs.pos_m, state.Layout.bs.azim_deg, ...
                state.NBeams, state.BeamSpanDeg, state.BeamMaxGain_dB);
        end
        doProp = (canonicalSlot == 1) || mobilityAdvanced || doBeamUpdate || (mod(canonicalSlot - 1, largeScaleUpdateSlots) == 0);
        reuseProp = ~isempty(fieldnames(state.LargeScaleState)) && ~doProp;
        state.LargeScaleState = sixgr.system.buildLargeScaleStateCache( ...
            state.CfgLargeScale, state.Layout, state.UE, state.BeamIdx, state.BeamGain_dB, state.PLModel, ...
            "NumRB", state.NumRB, "PreviousState", state.LargeScaleState, "ReusePropagation", reuseProp);
        [state.CurrentServingIdx, state.CurrentServingMetric_dBm] = sixgr.system.selectServingCellsFromPower(state.LargeScaleState.RSRP_dBm);
        state = sixgr.truth.CoupledTruthRuntime.refreshTimingAdvanceMobilityDriftImpl(state);
        [state.CurrentUELat, state.CurrentUELon] = sixgr.util.projectLocalXYToGeo(state.UE.pos_m(:,1), state.UE.pos_m(:,2), 19.122164, 72.999217);
        state.CurrentCanonicalSlot = double(canonicalSlot);
        state.CurrentFrame = double(sixgr.truth.CoupledTruthRuntime.frameIndexForSlot(state, canonicalSlot));
        state.CurrentSNR_dB = double(snr_dB);
    end

    function state = startSlotImpl(state, cfg, direction, sweepIdx, sweepCount, absoluteFrame, totalFrames, snr_dB)
        %#ok<INUSD>
        canonicalSlot = max(1, round(double(absoluteFrame)));
        totalCanonicalSlots = round(double(totalFrames));
        if ~(isfinite(totalCanonicalSlots) && totalCanonicalSlots >= 1)
            totalCanonicalSlots = 1;
        end
        [slotDLAllowed, slotULAllowed, slotLabel, slotPartition] = sixgr.truth.CoupledTruthRuntime.slotDuplexState( ...
            sixgr.util.structGet(state, "CfgMobility", struct()), canonicalSlot);
        frameIdx = sixgr.truth.CoupledTruthRuntime.frameIndexForSlot(state, canonicalSlot);
        totalSweepFrames = sixgr.truth.CoupledTruthRuntime.framesPerSweepPoint(state, totalCanonicalSlots);
        state.CurrentSlot = double(canonicalSlot);
        state.CurrentCanonicalSlot = double(canonicalSlot);
        state.CurrentDirection = upper(string(direction));
        state.CurrentUEIndex = NaN;
        state.CurrentFrame = double(frameIdx);
        state.CurrentFrameLocal = 1 + mod(double(frameIdx) - 1, max(1, round(double(totalSweepFrames))));
        state.FramesPerSweepPoint = double(totalSweepFrames);
        state.CanonicalSlotsPerSweepPoint = double(totalCanonicalSlots);
        state.CurrentSlotDLAllowed = logical(slotDLAllowed);
        state.CurrentSlotULAllowed = logical(slotULAllowed);
        state.CurrentSlotDuplexLabel = char(string(slotLabel));
        state.CurrentSlotIsSpecial = logical(sixgr.util.structGet(slotPartition, "IsSpecialSlot", false));
        state.CurrentSlotDLSymbolStart = double(sixgr.truth.CoupledTruthRuntime.firstNumeric(sixgr.util.structGet(slotPartition, "DLSymbolAllocation", [0 0]), 0));
        state.CurrentSlotDLNumSymbols = double(sixgr.truth.CoupledTruthRuntime.secondNumeric(sixgr.util.structGet(slotPartition, "DLSymbolAllocation", [0 0]), 0));
        state.CurrentSlotGuardSymbolStart = double(sixgr.truth.CoupledTruthRuntime.firstNumeric(sixgr.util.structGet(slotPartition, "GuardSymbolAllocation", [0 0]), 0));
        state.CurrentSlotGuardNumSymbols = double(sixgr.truth.CoupledTruthRuntime.secondNumeric(sixgr.util.structGet(slotPartition, "GuardSymbolAllocation", [0 0]), 0));
        state.CurrentSlotULSymbolStart = double(sixgr.truth.CoupledTruthRuntime.firstNumeric(sixgr.util.structGet(slotPartition, "ULSymbolAllocation", [0 0]), 0));
        state.CurrentSlotULNumSymbols = double(sixgr.truth.CoupledTruthRuntime.secondNumeric(sixgr.util.structGet(slotPartition, "ULSymbolAllocation", [0 0]), 0));
        state.CurrentSNR_dB = double(snr_dB);
        state.CurrentSweepPointIndex = double(sweepIdx);
        state.CurrentSweepPointCount = double(sweepCount);
        state = sixgr.truth.CoupledTruthRuntime.recordSlotTraceStart(state, direction, sweepIdx, sweepCount, canonicalSlot, totalCanonicalSlots, snr_dB);
        state = sixgr.truth.CoupledTruthRuntime.processDueFeedback(state);
    end

    function state = beginSlotImpl(state, ueIdx, direction, sweepIdx, sweepCount, absoluteFrame, totalFrames, snr_dB)
        canonicalSlot = max(1, round(double(absoluteFrame)));
        totalCanonicalSlots = round(double(totalFrames));
        if ~(isfinite(totalCanonicalSlots) && totalCanonicalSlots >= 1)
            totalCanonicalSlots = 1;
        end
        [slotDLAllowed, slotULAllowed, slotLabel, slotPartition] = sixgr.truth.CoupledTruthRuntime.slotDuplexState( ...
            sixgr.util.structGet(state, "CfgMobility", struct()), canonicalSlot);
        frameIdx = sixgr.truth.CoupledTruthRuntime.frameIndexForSlot(state, canonicalSlot);
        totalSweepFrames = sixgr.truth.CoupledTruthRuntime.framesPerSweepPoint(state, totalCanonicalSlots);
        state.CurrentSlot = double(canonicalSlot);
        state.CurrentCanonicalSlot = double(canonicalSlot);
        state.CurrentDirection = upper(string(direction));
        state.CurrentUEIndex = double(ueIdx);
        state.CurrentFrame = double(frameIdx);
        state.CurrentFrameLocal = 1 + mod(double(frameIdx) - 1, max(1, round(double(totalSweepFrames))));
        state.FramesPerSweepPoint = double(totalSweepFrames);
        state.CanonicalSlotsPerSweepPoint = double(totalCanonicalSlots);
        state.CurrentSlotDLAllowed = logical(slotDLAllowed);
        state.CurrentSlotULAllowed = logical(slotULAllowed);
        state.CurrentSlotDuplexLabel = char(string(slotLabel));
        state.CurrentSlotIsSpecial = logical(sixgr.util.structGet(slotPartition, "IsSpecialSlot", false));
        state.CurrentSlotDLSymbolStart = double(sixgr.truth.CoupledTruthRuntime.firstNumeric(sixgr.util.structGet(slotPartition, "DLSymbolAllocation", [0 0]), 0));
        state.CurrentSlotDLNumSymbols = double(sixgr.truth.CoupledTruthRuntime.secondNumeric(sixgr.util.structGet(slotPartition, "DLSymbolAllocation", [0 0]), 0));
        state.CurrentSlotGuardSymbolStart = double(sixgr.truth.CoupledTruthRuntime.firstNumeric(sixgr.util.structGet(slotPartition, "GuardSymbolAllocation", [0 0]), 0));
        state.CurrentSlotGuardNumSymbols = double(sixgr.truth.CoupledTruthRuntime.secondNumeric(sixgr.util.structGet(slotPartition, "GuardSymbolAllocation", [0 0]), 0));
        state.CurrentSlotULSymbolStart = double(sixgr.truth.CoupledTruthRuntime.firstNumeric(sixgr.util.structGet(slotPartition, "ULSymbolAllocation", [0 0]), 0));
        state.CurrentSlotULNumSymbols = double(sixgr.truth.CoupledTruthRuntime.secondNumeric(sixgr.util.structGet(slotPartition, "ULSymbolAllocation", [0 0]), 0));
        state.CurrentSNR_dB = double(snr_dB);
        state.CurrentSweepPointIndex = double(sweepIdx);
        state.CurrentSweepPointCount = double(sweepCount);
        state = sixgr.truth.CoupledTruthRuntime.recordSlotTraceStart(state, direction, sweepIdx, sweepCount, canonicalSlot, totalCanonicalSlots, snr_dB);
        state = sixgr.truth.CoupledTruthRuntime.processDueFeedback(state);
    end

    function [cfgU, state] = applyUserContextImpl(cfgIn, state, ueIdx, direction)
        cfgU = cfgIn;
        if ueIdx < 1 || ueIdx > numel(state.CurrentServingIdx)
            return;
        end
        largeScaleReady = isfield(state, 'LargeScaleState') && isstruct(state.LargeScaleState) && ...
            isfield(state.LargeScaleState, 'd2d_m') && isfield(state.LargeScaleState, 'PropagationDelay_s') && ...
            isfield(state.LargeScaleState, 'Doppler_Hz');
        if ~largeScaleReady
            state.LargeScaleState = sixgr.system.buildLargeScaleStateCache( ...
                state.CfgLargeScale, state.Layout, state.UE, state.BeamIdx, state.BeamGain_dB, state.PLModel, ...
                "NumRB", state.NumRB, "PreviousState", struct(), "ReusePropagation", false);
            [state.CurrentServingIdx, state.CurrentServingMetric_dBm] = sixgr.system.selectServingCellsFromPower(state.LargeScaleState.RSRP_dBm);
        end
        servingCell = double(state.CurrentServingIdx(ueIdx));
        if ~(isfinite(servingCell) && servingCell >= 1)
            servingCell = 1;
        end
        [cfgU, servingPhyIdentity] = sixgr.truth.CoupledTruthRuntime.applyRuntimeServingCellPHYIdentity(cfgU, state, servingCell);
        userMeta = sixgr.util.structGet(cfgU, "lls6g.userContext", struct());
        userMeta.RuntimeServingCell = servingCell;
        userMeta.RuntimeServingCellID = double(servingPhyIdentity.CellID);
        userMeta.RuntimeServingPCI = double(servingPhyIdentity.PCI);
        userMeta.RuntimeServingNCellID = double(servingPhyIdentity.NCellID);
        userMeta.RuntimeServingPHYIdentitySource = char(string(servingPhyIdentity.Source));
        userMeta.RuntimeUEIndex = double(ueIdx);
        userMeta.RuntimeServingSite = double(state.Layout.bs.siteId(servingCell));
        userMeta.RuntimeServingSector = double(state.Layout.bs.sectorId(servingCell));
        userMeta.RuntimeServingBeamIndex = double(state.LargeScaleState.BeamIndex(ueIdx, servingCell));
        userMeta.RuntimeServingBeamGain_dB = double(state.LargeScaleState.BeamGain_dB(ueIdx, servingCell));
        userMeta.RuntimeServingRSRP_dBm = double(state.CurrentServingMetric_dBm(ueIdx));
        userMeta.RuntimeServingRxPower_dBm = double(state.LargeScaleState.RxPower_dBm(ueIdx, servingCell));
        userMeta.RuntimeServingBasePathloss_dB = double(state.LargeScaleState.BasePathloss_dB(ueIdx, servingCell));
        userMeta.RuntimeServingPathloss_dB = double(state.LargeScaleState.Pathloss_dB(ueIdx, servingCell));
        userMeta.RuntimeServingShadowFading_dB = double(state.LargeScaleState.Shadow_dB(ueIdx, servingCell));
        userMeta.RuntimeServingO2I_dB = double(state.LargeScaleState.O2I_dB(ueIdx, servingCell));
        userMeta.RuntimeGeometrySource = char(string(sixgr.util.structGet(state.LargeScaleState, "GeometrySource", "")));
        userMeta.RuntimeGeometryDelaySource = char(string(sixgr.util.structGet(state.LargeScaleState, "DelaySource", "")));
        userMeta.RuntimeGeometryDopplerSource = char(string(sixgr.util.structGet(state.LargeScaleState, "DopplerSource", "")));
        userMeta.RuntimeServingDistance2D_m = double(state.LargeScaleState.d2d_m(ueIdx, servingCell));
        userMeta.RuntimeServingDistance3D_m = double(state.LargeScaleState.d3d_m(ueIdx, servingCell));
        userMeta.RuntimeServingPropagationDelay_s = double(state.LargeScaleState.PropagationDelay_s(ueIdx, servingCell));
        userMeta.RuntimeServingRadialVelocity_mps = double(state.LargeScaleState.RadialVelocity_mps(ueIdx, servingCell));
        userMeta.RuntimeServingSignedDopplerHz = double(state.LargeScaleState.SignedDoppler_Hz(ueIdx, servingCell));
        userMeta.RuntimeServingDopplerHz = double(state.LargeScaleState.Doppler_Hz(ueIdx, servingCell));
        userMeta.RuntimeServingLOSProbability = double(state.LargeScaleState.LOSProbability(ueIdx, servingCell));
        userMeta.RuntimeServingLOS = logical(state.LargeScaleState.LOS(ueIdx, servingCell));
        userMeta.RuntimeServingIndoorDistance_m = double(state.LargeScaleState.IndoorDistance_m(ueIdx, servingCell));
        userMeta.RuntimeChannelComplianceMode = char(string(sixgr.util.structGet(state.LargeScaleState, "ChannelComplianceMode", "")));
        userMeta.RuntimePathlossModelSource = char(string(sixgr.util.structGet(state.LargeScaleState, "PathlossModelSource", "")));
        userMeta.RuntimePathlossComplianceStatus = char(string(sixgr.util.structGet(state.LargeScaleState, "PathlossComplianceStatus", "")));
        userMeta.RuntimeFallbackUsedForPathloss = logical(sixgr.util.structGet(state.LargeScaleState, "FallbackUsedForPathloss", false));
        userMeta.RuntimeO2IModelSource = char(string(sixgr.util.structGet(state.LargeScaleState, "O2IModelSource", "")));
        userMeta.RuntimeO2IComplianceStatus = char(string(sixgr.util.structGet(state.LargeScaleState, "O2IComplianceStatus", "")));
        userMeta.RuntimeO2IComplianceReason = char(string(sixgr.util.structGet(state.LargeScaleState, "O2IComplianceReason", "")));
        userMeta.RuntimeLOSProbabilitySource = char(string(sixgr.util.structGet(state.LargeScaleState, "LOSProbabilitySource", "")));
        userMeta.RuntimeLOSComplianceStatus = char(string(sixgr.util.structGet(state.LargeScaleState, "LOSComplianceStatus", "")));
        userMeta.RuntimeLOSComplianceReason = char(string(sixgr.util.structGet(state.LargeScaleState, "LOSComplianceReason", "")));
        interferenceMode = sixgr.truth.CoupledTruthRuntime.resolveInterferenceExecutionMode(cfgU, state.MultiUser);
        userMeta.RuntimeServingLargeScaleSINR_dB = double(sixgr.truth.CoupledTruthRuntime.estimateRuntimeWidebandSINR( ...
            state, ueIdx, servingCell, interferenceMode));
        userMeta.RuntimeInterferenceMode = char(interferenceMode);
        userMeta.RuntimeCurrentSlot = double(state.CurrentSlot);
        userMeta.RuntimeCurrentDirection = upper(string(direction));
        userMeta.RuntimeSlotStartTime_s = max(0, double(state.CurrentSlot) - 1) * double(state.SlotDuration_s);
        if ueIdx <= size(state.UE.pos_m, 1)
            userMeta.RuntimeUEPosition_m = reshape(double(state.UE.pos_m(ueIdx, :)), 1, []);
        end
        if isfield(state.LargeScaleState, "UEVelocity_mps") && ueIdx <= size(state.LargeScaleState.UEVelocity_mps, 1)
            userMeta.RuntimeUEVelocity_mps = reshape(double(state.LargeScaleState.UEVelocity_mps(ueIdx, :)), 1, []);
        end
        if ueIdx <= numel(state.UE.heading_deg)
            userMeta.RuntimeUEHeading_deg = double(state.UE.heading_deg(ueIdx));
        end
        if servingCell <= size(state.Layout.bs.pos_m, 1)
            userMeta.RuntimeServingBSPosition_m = reshape(double(state.Layout.bs.pos_m(servingCell, :)), 1, []);
        end
        if isfield(state.LargeScaleState, "BSVelocity_mps") && servingCell <= size(state.LargeScaleState.BSVelocity_mps, 1)
            userMeta.RuntimeServingBSVelocity_mps = reshape(double(state.LargeScaleState.BSVelocity_mps(servingCell, :)), 1, []);
        end
        if servingCell <= numel(state.Layout.bs.azim_deg)
            userMeta.RuntimeServingBSAzimuth_deg = double(state.Layout.bs.azim_deg(servingCell));
        end
        [bsEntry, ueEntry] = sixgr.truth.CoupledTruthRuntime.runtimeAntennaEntriesForLink(state, ueIdx, servingCell);
        if isstruct(bsEntry) && ~isempty(fieldnames(bsEntry))
            userMeta.RuntimeServingBSAntenna = sixgr.util.structGet(bsEntry, "Antenna", struct());
            userMeta.RuntimeServingBSAntennaMeta = sixgr.util.structGet(bsEntry, "Metadata", struct());
        end
        if isstruct(ueEntry) && ~isempty(fieldnames(ueEntry))
            userMeta.RuntimeUEAntenna = sixgr.util.structGet(ueEntry, "Antenna", struct());
            userMeta.RuntimeUEAntennaMeta = sixgr.util.structGet(ueEntry, "Metadata", struct());
        end
        userMeta.RuntimeAntennaConfigSource = "browser_yaml_to_buildInternalConfig_to_CoupledTruthRuntime";
        userMeta.RuntimeAntennaObjectSource = "CoupledTruthRuntime.initialize:AntennaArrayFactory.build";
        userMeta.RuntimeChannelArrayModel = char(sixgr.truth.CoupledTruthRuntime.resolveChannelArrayModel(cfgU));
        cfgU = sixgr.util.structSet(cfgU, "channel.distance2D_m", userMeta.RuntimeServingDistance2D_m);
        cfgU = sixgr.util.structSet(cfgU, "channel.distance3D_m", userMeta.RuntimeServingDistance3D_m);
        cfgU = sixgr.util.structSet(cfgU, "channel.propagationDistance2D_m", userMeta.RuntimeServingDistance2D_m);
        cfgU = sixgr.util.structSet(cfgU, "channel.propagationDistance_m", userMeta.RuntimeServingDistance3D_m);
        cfgU = sixgr.util.structSet(cfgU, "channel.propagationDelay_s", userMeta.RuntimeServingPropagationDelay_s);
        cfgU = sixgr.util.structSet(cfgU, "channel.doppler_Hz", userMeta.RuntimeServingDopplerHz);
        cfgU = sixgr.util.structSet(cfgU, "channel.runtimeSignedDoppler_Hz", userMeta.RuntimeServingSignedDopplerHz);
        cfgU = sixgr.util.structSet(cfgU, "channel.losProbability", userMeta.RuntimeServingLOSProbability);
        cfgU = sixgr.util.structSet(cfgU, "channel.runtimeLOS", userMeta.RuntimeServingLOS);
        feedback = sixgr.truth.CoupledTruthRuntime.latestFeedbackForDirection(state, ueIdx, direction);
        if isfinite(double(sixgr.util.structGet(feedback, "PMI", NaN)))
            userMeta.RuntimeFeedbackPMI = double(feedback.PMI);
        end
        if isfinite(double(sixgr.util.structGet(feedback, "CRI", NaN)))
            userMeta.RuntimeFeedbackCRI = double(feedback.CRI);
        end
        if logical(sixgr.util.structGet(feedback, "Valid", false))
            userMeta.RuntimeFeedbackCQI = double(feedback.CQI);
            userMeta.RuntimeFeedbackRI = double(feedback.RI);
            userMeta.RuntimeFeedbackSINR_dB = double(feedback.SINR_dB);
        end
        if direction == "DL"
            if isfinite(double(sixgr.util.structGet(feedback, "PMI", NaN)))
                cfgU = sixgr.util.structSet(cfgU, "phy.pdsch.PMI", double(feedback.PMI));
            end
            if isfinite(double(sixgr.util.structGet(feedback, "CRI", NaN)))
                cfgU = sixgr.util.structSet(cfgU, "phy.beamManagement.selectedCRI", double(feedback.CRI));
                cfgU = sixgr.util.structSet(cfgU, "phy.csi.selectedCRI", double(feedback.CRI));
            end
        end
        trsContext = sixgr.truth.CoupledTruthRuntime.resolveTRSRuntimeContext(state, cfgU, ueIdx, servingCell);
        userMeta.RuntimeTRSGatingActive = logical(trsContext.TRSGatingActive);
        userMeta.RuntimeTRSValidityState = char(string(trsContext.TRSValidityState));
        userMeta.RuntimeTrackingEligibility = logical(trsContext.TrackingEligibility);
        userMeta.RuntimeTRSAgeSlots = double(trsContext.TRSAgeSlots);
        userMeta.RuntimeLastSuccessfulTRSSlot = double(trsContext.LastSuccessfulTRSSlot);
        userMeta.RuntimeLastEstimatedTRSDopplerHz = double(trsContext.LastEstimatedTRSDopplerHz);
        userMeta.RuntimeTRSStateSource = char(string(trsContext.TRSStateSource));
        userMeta.RuntimeTRSRuntimeConsumer = char(string(trsContext.TRSRuntimeConsumer));
        userMeta.RuntimeTRSInfluencedDecision = logical(trsContext.TRSInfluencedDecision);
        userMeta.RuntimeTRSInfluenceDefinition = char(string(trsContext.TRSInfluenceDefinition));
        userMeta.RuntimeTRSReceiverIntegrationStatus = char(string(trsContext.TRSReceiverIntegrationStatus));
        userMeta.RuntimeTRSReceiverIntegrationBlocker = char(string(trsContext.TRSReceiverIntegrationBlocker));
        userMeta.RuntimeTRSProcessed = logical(trsContext.TRSProcessed);
        userMeta.RuntimeTRSReceiverConsumerType = char(string(trsContext.TRSReceiverConsumerType));
        userMeta.RuntimeTRSTrackingStateBefore = char(string(trsContext.TRSTrackingStateBefore));
        userMeta.RuntimeTRSTrackingStateAfter = char(string(trsContext.TRSTrackingStateAfter));
        userMeta.RuntimeTRSTrackingUpdateTime_s = double(trsContext.TRSTrackingUpdateTime_s);
        userMeta.RuntimeTRSAssociatedCell = double(trsContext.TRSAssociatedCell);
        userMeta.RuntimeTRSUpdateOutcome = char(string(trsContext.TRSUpdateOutcome));
        userMeta.RuntimeTRSChannelTrackingFreshnessState = char(string(trsContext.TRSChannelTrackingFreshnessState));
        userMeta.RuntimeTRSFrequencyTrackingState = char(string(trsContext.TRSFrequencyTrackingState));
        userMeta.RuntimeTRSTimingTrackingState = char(string(trsContext.TRSTimingTrackingState));
        userMeta.RuntimeTRSTimingEstimateAvailable = logical(trsContext.TRSTimingEstimateAvailable);
        userMeta.RuntimeTRSTimingEstimate_samples = double(trsContext.TRSTimingEstimate_samples);
        userMeta.RuntimeTRSCFOEstimateAvailable = logical(trsContext.TRSCFOEstimateAvailable);
        userMeta.RuntimeTRSEstimatedCFO_Hz = double(trsContext.TRSEstimatedCFO_Hz);
        userMeta.RuntimeTRSEstimatedOscillatorCFO_Hz = double(trsContext.TRSEstimatedOscillatorCFO_Hz);
        userMeta.RuntimeTRSEstimatedCommonFrequency_Hz = double(trsContext.TRSEstimatedCommonFrequency_Hz);
        userMeta.RuntimeTRSPhysicalDoppler_Hz = double(trsContext.TRSPhysicalDoppler_Hz);
        userMeta.RuntimeTRSRuntimeEvidenceSource = char(string(trsContext.TRSRuntimeEvidenceSource));
        cfgU = sixgr.util.structSet(cfgU, "run.interferenceExecutionMode", char(interferenceMode));
        cfgU = sixgr.util.structSet(cfgU, "run.useAbstractInterferenceModel", false);
        cfgU = sixgr.util.structSet(cfgU, "lls6g.userContext", userMeta);
    end

    function [cfgOut, identity] = applyRuntimeServingCellPHYIdentity(cfgIn, state, servingCell)
        cfgOut = cfgIn;
        identity = sixgr.truth.CoupledTruthRuntime.runtimeServingCellPHYIdentity(state, servingCell);
        nCellId = double(identity.NCellID);

        cfgOut = sixgr.util.structSet(cfgOut, "phy.carrier.NCellID", nCellId);
        cfgOut = sixgr.util.structSet(cfgOut, "phy.NCellID", nCellId);
        cfgOut = sixgr.util.structSet(cfgOut, "scenario.NCellID", nCellId);
        cfgOut = sixgr.util.structSet(cfgOut, "phy.pdsch.NID", nCellId);
        cfgOut = sixgr.util.structSet(cfgOut, "phy.pusch.NID", nCellId);
        cfgOut = sixgr.util.structSet(cfgOut, "phy.pdcch.dmrsScramblingID", nCellId);
        cfgOut = sixgr.util.structSet(cfgOut, "phy.pdcch.coreset.shiftIndex", nCellId);
        cfgOut = sixgr.util.structSet(cfgOut, "reference_signals.csi_rs_scrambling_id", nCellId);
        cfgOut = sixgr.util.structSet(cfgOut, "random_access.n_cell_id", nCellId);
        cfgOut = sixgr.util.structSet(cfgOut, "prach_lls.NCellID", nCellId);
        cfgOut = sixgr.util.structSet(cfgOut, "phy.prach.NCellID", nCellId);

        userMeta = sixgr.util.structGet(cfgOut, "lls6g.userContext", struct());
        if ~(isstruct(userMeta) && ~isempty(fieldnames(userMeta)))
            userMeta = struct();
        end
        userMeta.RuntimeServingCellID = double(identity.CellID);
        userMeta.RuntimeServingPCI = double(identity.PCI);
        userMeta.RuntimeServingNCellID = nCellId;
        userMeta.RuntimeServingPHYIdentitySource = char(string(identity.Source));
        cfgOut = sixgr.util.structSet(cfgOut, "lls6g.userContext", userMeta);
    end

    function identity = runtimeServingCellPHYIdentity(state, servingCell)
        servingCell = max(1, round(double(servingCell)));
        layout = sixgr.util.structGet(state, "Layout", struct());
        bs = sixgr.util.structGet(layout, "bs", struct());
        cellId = sixgr.truth.CoupledTruthRuntime.vectorValueOrDefault( ...
            sixgr.util.structGet(bs, "cellId", []), servingCell, servingCell);
        pci = sixgr.truth.CoupledTruthRuntime.vectorValueOrDefault( ...
            sixgr.util.structGet(bs, "pci", []), servingCell, cellId);
        nCellId = sixgr.truth.CoupledTruthRuntime.vectorValueOrDefault( ...
            sixgr.util.structGet(bs, "nCellId", []), servingCell, pci);
        if ~(isfinite(nCellId) && nCellId >= 0)
            nCellId = max(0, servingCell - 1);
        end
        nCellId = mod(round(double(nCellId)), 1008);
        identity = struct( ...
            "ServingCell", double(servingCell), ...
            "CellID", double(cellId), ...
            "PCI", double(pci), ...
            "NCellID", double(nCellId), ...
            "Source", "layout.bs.nCellId_runtime_serving_cell");
    end

    function value = vectorValueOrDefault(vec, idx, defaultValue)
        value = double(defaultValue);
        idx = round(double(idx));
        if ~(isfinite(idx) && idx >= 1)
            return;
        end
        try
            vec = double(vec);
            if ~isempty(vec) && idx <= numel(vec)
                candidate = double(vec(idx));
                if isfinite(candidate)
                    value = candidate;
                end
            end
        catch
            value = double(defaultValue);
        end
    end

    function context = resolveHARQTrialContextImpl(state, ueIdx, direction)
        context = struct();
        direction = upper(string(direction));
        rnti = double(max(1, round(double(state.MultiUser.RNTIStart + ueIdx - 1))));
        if direction == "UL"
            harq = state.ULHarq;
            softBuffers = state.ULCombinedLLR;
        else
            harq = state.DLHarq;
            softBuffers = state.DLCombinedLLR;
        end
        retx = harq.peekRetx(rnti, sixgr.util.structGet(state, "CurrentSlot", NaN));
        if isempty(retx)
            context.HARQContext = struct("Direction", char(direction), "UEIndex", double(ueIdx), "RNTI", double(rnti), "IsRetransmission", false, "FeedbackDelaySlots", double(state.HARQFeedbackSlots));
            return;
        end
        pid = double(retx.HARQ.HarqID) + 1;
        prevLLR = harq.getSoftBuffer(rnti, double(retx.HARQ.HarqID));
        if ueIdx <= size(softBuffers, 1) && pid <= size(softBuffers, 2)
            mirrored = softBuffers{ueIdx, pid};
            if isempty(fieldnames(prevLLR)) && ~isempty(mirrored)
                prevLLR = mirrored;
            end
        end
        if isstruct(prevLLR) && isempty(fieldnames(prevLLR))
            prevLLR = [];
        end
        context.TransportBlockBits = int8(retx.TB(:));
        context.RV = double(retx.HARQ.RV);
        context.PreviousCombinedLLR = prevLLR;
        context.GrantSnapshot = sixgr.util.structGet(retx, "LastGrant", struct());
        context.HARQContext = struct("Direction", char(direction), "UEIndex", double(ueIdx), "RNTI", double(rnti), "HarqID", double(retx.HARQ.HarqID), "NDI", logical(retx.HARQ.NDI), "IsRetransmission", true, "FeedbackDelaySlots", double(state.HARQFeedbackSlots), "RV", double(retx.HARQ.RV), "GrantSnapshot", context.GrantSnapshot);
    end

    function [state, grants, info] = scheduleDirectionImpl(state, cfg, direction)
        direction = upper(string(direction));
        grants = repmat(struct(), 0, 1);
        info = struct("Direction", char(direction), "ActiveUsers", 0, "GrantedUsers", 0, "GrantCount", 0, "QueueBits", 0);
        slotDLAllowed = logical(sixgr.util.structGet(state, "CurrentSlotDLAllowed", true));
        slotULAllowed = logical(sixgr.util.structGet(state, "CurrentSlotULAllowed", true));
        if (direction == "DL" && ~slotDLAllowed) || (direction == "UL" && ~slotULAllowed)
            return;
        end
        servingIdx = double(sixgr.util.structGet(state, "CurrentServingIdx", zeros(state.NumUsers, 1)));
        nCells = size(state.Layout.bs.pos_m, 1);
        if nCells < 1 || numel(servingIdx) < 1
            return;
        end

        budget = sixgr.truth.CoupledTruthRuntime.defaultSlotBudget(state);
        byCell = cell(nCells, 1);
        nGrant = 0;
        activeUsers = 0;
        grantedUsers = [];
        for cellId = 1:nCells
            ueCell = find(servingIdx(:) == cellId);
            if isempty(ueCell)
                continue;
            end
            ueStates = repmat(struct(), 0, 1);
            for ii = 1:numel(ueCell)
                ueIdx = double(ueCell(ii));
                [state, ueState] = sixgr.truth.CoupledTruthRuntime.buildSchedulerUEState(state, cfg, ueIdx, direction, cellId);
                if ~logical(ueState.Active)
                    continue;
                end
                activeUsers = activeUsers + 1;
                if isempty(ueStates)
                    ueStates = ueState;
                else
                    ueStates(end + 1, 1) = ueState; %#ok<AGROW>
                end
            end
            if isempty(ueStates)
                continue;
            end
            if sixgr.truth.CoupledTruthRuntime.shouldDeferConservativeBootstrapCell(state, direction, cellId, ueStates)
                state = sixgr.truth.CoupledTruthRuntime.recordConservativeBootstrapCellDeferral(state, ueStates);
                continue;
            end
            scheduler = sixgr.truth.CoupledTruthRuntime.schedulerForDirection(state, direction, cellId);
            if isempty(scheduler)
                continue;
            end
            [cellGrants, schedInfo] = scheduler.schedule(double(state.CurrentSlot), ueStates, budget);
            state = sixgr.truth.CoupledTruthRuntime.appendSchedulerDecisionRows(state, schedInfo, direction, cellId);
            if isempty(cellGrants)
                continue;
            end
            for gi = 1:numel(cellGrants)
                grant = cellGrants(gi);
                ueIdx = sixgr.truth.CoupledTruthRuntime.resolveUEIndexFromRNTI(state, double(grant.RNTI));
                if ~(isfinite(ueIdx) && ueIdx >= 1)
                    continue;
                end
                if ~sixgr.truth.CoupledTruthRuntime.resolveSchedulingEligibilityForDirection(state, ueIdx, direction)
                    if ueIdx > numel(state.GrantsBlockedByGatingCount)
                        state.GrantsBlockedByGatingCount(ueIdx, 1) = 0;
                    end
                    state.GrantsBlockedByGatingCount(ueIdx) = double(state.GrantsBlockedByGatingCount(ueIdx)) + 1;
                    continue;
                end
                grant.UEIndex = double(ueIdx);
                grant.ServingCell = double(cellId);
                phyIdentity = sixgr.truth.CoupledTruthRuntime.runtimeServingCellPHYIdentity(state, cellId);
                grant.CellID = double(phyIdentity.CellID);
                grant.PCI = double(phyIdentity.PCI);
                grant.NCellID = double(phyIdentity.NCellID);
                grant.PhysicalCellID = double(phyIdentity.NCellID);
                grant.PHYIdentitySource = char(string(phyIdentity.Source));
                grant.Direction = char(direction);
                grant.Slot = double(state.CurrentSlot);
                grant.Frame = double(state.CurrentFrame);
                feedback = sixgr.truth.CoupledTruthRuntime.latestFeedbackForDirection(state, ueIdx, direction);
                if isfinite(double(sixgr.util.structGet(feedback, "CQI", NaN)))
                    grant.CQIUsed = double(feedback.CQI);
                end
                executableRICandidates = [ ...
                    double(sixgr.util.structGet(grant, "RIUsed", NaN)), ...
                    double(sixgr.util.structGet(grant, "RankIndicator", NaN)), ...
                    double(sixgr.util.structGet(grant, "Rank", NaN)), ...
                    double(sixgr.util.structGet(grant, "NumLayers", NaN)), ...
                    double(sixgr.util.structGet(grant, "Layers", NaN))];
                executableRI = sixgr.truth.CoupledTruthRuntime.firstNumeric(executableRICandidates, NaN);
                if isfinite(double(executableRI)) && double(executableRI) >= 1
                    executableRI = double(max(1, round(executableRI)));
                    grant.RI = executableRI;
                    grant.RIUsed = executableRI;
                    grant.Rank = executableRI;
                    grant.RankIndicator = executableRI;
                elseif isfinite(double(sixgr.util.structGet(feedback, "RI", NaN)))
                    grant.RIUsed = double(feedback.RI);
                    grant.Rank = double(feedback.RI);
                    grant.RankIndicator = double(feedback.RI);
                end
                if isfinite(double(sixgr.util.structGet(feedback, "PMI", NaN)))
                    grant.PMI = double(feedback.PMI);
                end
                if isfinite(double(sixgr.util.structGet(feedback, "CRI", NaN)))
                    grant.CRI = double(feedback.CRI);
                end
                bootstrapSource = strtrim(string(sixgr.util.structGet(feedback, "BootstrapCQISource", "")));
                if strlength(bootstrapSource) > 0
                    grant.MCSIndexAuthority = char(bootstrapSource);
                    grant.GrantOperatingPointSource = char(bootstrapSource);
                elseif logical(sixgr.util.structGet(feedback, "Valid", false)) && ...
                        isfinite(double(sixgr.util.structGet(feedback, "CQI", NaN))) && ...
                        double(sixgr.util.structGet(feedback, "CQI", NaN)) > 0
                    grant.MCSIndexAuthority = "feedback_cqi_derived_reference";
                    grant.GrantOperatingPointSource = "feedback_cqi_derived_reference";
                else
                    grant.MCSIndexAuthority = "scheduler_grant";
                    grant.GrantOperatingPointSource = "scheduler_grant";
                end
                grant = sixgr.truth.CoupledTruthRuntime.applyMeasuredFeedbackAMCToGrant( ...
                    grant, feedback, scheduler, state.CfgMobility, direction);
                grantedUsers(end + 1, 1) = double(ueIdx); %#ok<AGROW>
                nGrant = nGrant + 1;
                grant.DCI = scheduler.buildDCIBitfield(grant);
                grant.PBCHGatingActive = logical(sixgr.util.structGet(state.ControlGating, "PBCHRequired", false));
                grant.PRACHGatingActive = logical(sixgr.util.structGet(state.ControlGating, "PRACHRequired", false));
                grant.PDCCHGatingActive = logical(sixgr.util.structGet(state.ControlGating, "PDCCHRequired", false));
                grant.SRSGatingActive = sixgr.truth.CoupledTruthRuntime.srsGatingActiveForDirection(state, direction);
                grant.CellAcquisitionState = char(sixgr.truth.CoupledTruthRuntime.controlStateAt(state, "CellAcquisitionState", ueIdx, "unknown"));
                grant.AccessState = char(sixgr.truth.CoupledTruthRuntime.controlStateAt(state, "AccessState", ueIdx, "not_attempted"));
                grant.SRSValidityState = char(sixgr.truth.CoupledTruthRuntime.controlStateAt(state, "SRSValidityState", ueIdx, "unknown"));
                grant.CSIValidityState = char(sixgr.truth.CoupledTruthRuntime.controlStateAt(state, "CSIValidityState", ueIdx, "bootstrap_csi_unavailable"));
                csiMaxAgeSlots = max(0, round(double(sixgr.util.structGet(state.CfgMobility, "phy.csirs.maxAgeSlots", ...
                    sixgr.util.structGet(state.CfgMobility, "phy.csi.maxAgeSlots", ...
                    sixgr.util.structGet(state.CfgMobility, "mac.scheduler.csiMaxAgeSlots", 20))))));
                csirsCausal = sixgr.truth.CoupledTruthRuntime.consumeReferenceSignalMeasurementImpl( ...
                    state, "CSI-RS", "UE", ueIdx, state.CurrentSlot, csiMaxAgeSlots);
                grant.CSIRSCausalUsable = logical(csirsCausal.Usable);
                grant.CSIRSCausalAgeSlots = double(csirsCausal.AgeSlots);
                grant.CSIRSCausalStatus = char(string(csirsCausal.Status));
                grant.CSIRSCausalMeasurementId = char(string(csirsCausal.MeasurementId));
                grant.SRSValid = strcmpi(char(string(grant.SRSValidityState)), "valid");
                grant.LastSuccessfulSRSSlot = double(sixgr.truth.CoupledTruthRuntime.numericStateAt(state, "LastSuccessfulSRSSlotByUE", ueIdx, NaN));
                grant.SRSAgeSlots = double(sixgr.truth.CoupledTruthRuntime.srsAgeSlots(state, ueIdx));
                srsCausal = sixgr.truth.CoupledTruthRuntime.consumeReferenceSignalMeasurementImpl( ...
                    state, "SRS", "UE", ueIdx, state.CurrentSlot, ...
                    max(0, round(double(sixgr.util.structGet(state.ControlGating, "SRSMaxAgeSlots", 0)))));
                grant.SRSCausalUsable = logical(srsCausal.Usable);
                grant.SRSCausalAgeSlots = double(srsCausal.AgeSlots);
                grant.SRSCausalStatus = char(string(srsCausal.Status));
                grant.SRSCausalMeasurementId = char(string(srsCausal.MeasurementId));
                grant.ControlEligible = logical(sixgr.truth.CoupledTruthRuntime.controlLogicalAt(state, "ControlEligibility", ueIdx, true));
                grant.SchedulingEligible = sixgr.truth.CoupledTruthRuntime.resolveSchedulingEligibilityForDirection(state, ueIdx, direction);
                grant.SchedulingBlockedBySRS = logical(grant.ControlEligible && ~grant.SchedulingEligible && grant.SRSGatingActive);
                trsContext = sixgr.truth.CoupledTruthRuntime.resolveTRSRuntimeContext(state, cfg, ueIdx, cellId);
                trsCausal = sixgr.truth.CoupledTruthRuntime.consumeReferenceSignalMeasurementImpl( ...
                    state, "TRS", "CELL", cellId, state.CurrentSlot, ...
                    max(0, round(double(sixgr.util.structGet(state.ControlGating, "TRSMaxAgeSlots", 0)))));
                grant.TRSGatingActive = logical(trsContext.TRSGatingActive);
                grant.TRSValidityState = char(string(trsContext.TRSValidityState));
                grant.TrackingEligibility = logical(trsContext.TrackingEligibility);
                grant.TRSAgeSlots = double(trsContext.TRSAgeSlots);
                grant.TRSCausalUsable = logical(trsCausal.Usable);
                grant.TRSCausalAgeSlots = double(trsCausal.AgeSlots);
                grant.TRSCausalStatus = char(string(trsCausal.Status));
                grant.TRSCausalMeasurementId = char(string(trsCausal.MeasurementId));
                grant.LastSuccessfulTRSSlot = double(trsContext.LastSuccessfulTRSSlot);
                grant.LastEstimatedTRSDopplerHz = double(trsContext.LastEstimatedTRSDopplerHz);
                grant.TRSStateSource = char(string(trsContext.TRSStateSource));
                grant.TRSRuntimeConsumer = char(string(trsContext.TRSRuntimeConsumer));
                grant.TRSInfluencedDecision = logical(trsContext.TRSInfluencedDecision);
                grant.TRSInfluenceDefinition = char(string(trsContext.TRSInfluenceDefinition));
                grant.TRSReceiverIntegrationStatus = char(string(trsContext.TRSReceiverIntegrationStatus));
                grant.TRSReceiverIntegrationBlocker = char(string(trsContext.TRSReceiverIntegrationBlocker));
                grant.GrantWorkerSafe = true;
                grant.GrantSharedStateCommitMode = "serial_coordinator_commit";
                grant.GrantContextId = sixgr.truth.CoupledTruthRuntime.composeGrantContextId(grant, direction, state, ueIdx);
                if logical(grant.PDCCHGatingActive)
                    grant.GrantControlState = "control_pending";
                    grant.ControlDecodeOk = false;
                else
                    grant.GrantControlState = "control_not_required";
                    grant.ControlDecodeOk = true;
                end
                if isempty(byCell{cellId})
                    byCell{cellId} = grant;
                else
                    [byCell{cellId}, grant] = sixgr.truth.CoupledTruthRuntime.harmonizeStructArray(byCell{cellId}, grant);
                    byCell{cellId}(end + 1, 1) = grant; %#ok<AGROW>
                end
                state = sixgr.truth.CoupledTruthRuntime.appendGrantTrace(state, grant, direction, feedback);
            end
        end

        grants = repmat(struct(), 0, 1);
        for cellId = 1:nCells
            if isempty(byCell{cellId})
                continue;
            end
            if isempty(grants)
                grants = byCell{cellId};
            else
                [grants, cellGrants] = sixgr.truth.CoupledTruthRuntime.harmonizeStructArray(grants, byCell{cellId});
                grants = vertcat(grants, cellGrants); %#ok<AGROW>
            end
        end
        queueBits = 0;
        if direction == "UL"
            queueBits = sum(double(state.ULQueueBits), "omitnan");
            state.LastULGrantCount = nGrant;
            state.LastULGrantedUsers = numel(unique(grantedUsers));
            state.LastULActiveUsers = activeUsers;
        else
            queueBits = sum(double(state.DLQueueBits), "omitnan");
            state.LastDLGrantCount = nGrant;
            state.LastDLGrantedUsers = numel(unique(grantedUsers));
            state.LastDLActiveUsers = activeUsers;
        end
        info.ActiveUsers = activeUsers;
        info.GrantedUsers = numel(unique(grantedUsers));
        info.GrantCount = nGrant;
        info.QueueBits = queueBits;
        state = sixgr.truth.CoupledTruthRuntime.recordSlotTraceSchedule(state, direction, info);
    end

    function [state, context, grantRow] = buildTrialContextFromGrantImpl(state, cfg, ueIdx, direction, grant)
        direction = upper(string(direction));
        grant = sixgr.truth.CoupledTruthRuntime.normalizeGrantSnapshot(grant, direction, state, ueIdx);
        isRetx = logical(sixgr.util.structGet(sixgr.util.structGet(grant, "HARQ", struct()), "IsRetransmission", false));
        if isRetx
            context = sixgr.truth.CoupledTruthRuntime.resolveHARQTrialContextImpl(state, ueIdx, direction);
            replayGrant = sixgr.util.structGet(context, "GrantSnapshot", struct());
            if ~(isstruct(replayGrant) && ~isempty(fieldnames(replayGrant)))
                replayGrant = grant;
            end
            replayTBSizeBits = double(numel(sixgr.util.structGet(context, "TransportBlockBits", int8([]))));
            if isfinite(replayTBSizeBits) && replayTBSizeBits > 0
                replayGrant.TransportBlockSize = replayTBSizeBits;
                replayGrant.TBSBits = replayTBSizeBits;
                replayGrant.TBSBytes = floor(replayTBSizeBits / 8);
                if ~isfield(replayGrant, "ScheduledTransportBlockSize") || ...
                        ~(isfinite(double(sixgr.util.structGet(replayGrant, "ScheduledTransportBlockSize", NaN))) && ...
                        double(sixgr.util.structGet(replayGrant, "ScheduledTransportBlockSize", NaN)) > 0)
                    replayGrant.ScheduledTransportBlockSize = replayTBSizeBits;
                end
            end
            replayGrant.Direction = char(direction);
            replayGrant.UEIndex = double(sixgr.util.structGet(grant, "UEIndex", ueIdx));
            replayGrant.RNTI = double(sixgr.util.structGet(grant, "RNTI", max(1, round(double(state.MultiUser.RNTIStart + ueIdx - 1)))));
            replayGrant.Frame = double(sixgr.util.structGet(grant, "Frame", sixgr.util.structGet(replayGrant, "Frame", state.CurrentFrame)));
            replayGrant.Slot = double(sixgr.util.structGet(grant, "Slot", sixgr.util.structGet(replayGrant, "Slot", state.CurrentSlot)));
            replayGrant.ServingCell = double(sixgr.util.structGet(grant, "ServingCell", sixgr.util.structGet(replayGrant, "ServingCell", NaN)));
            replayPRBSet = double(sixgr.util.structGet(grant, "PRBSet", []));
            if ~isempty(replayPRBSet)
                replayGrant.PRBSet = replayPRBSet;
                replayGrant.PRBs = double(numel(replayPRBSet));
            end
            replaySymbolAllocation = double(sixgr.util.structGet(grant, "SymbolAllocation", []));
            if ~isempty(replaySymbolAllocation)
                replayGrant.SymbolAllocation = replaySymbolAllocation;
            end
            if isfinite(double(sixgr.util.structGet(grant, "PMI", NaN)))
                replayGrant.PMI = double(grant.PMI);
            end
            if isfinite(double(sixgr.util.structGet(grant, "CRI", NaN)))
                replayGrant.CRI = double(grant.CRI);
            end
            if isfinite(double(sixgr.util.structGet(grant, "CQIUsed", NaN)))
                replayGrant.CQIUsed = double(grant.CQIUsed);
            end
            if isfinite(double(sixgr.util.structGet(grant, "RIUsed", NaN)))
                replayGrant.RIUsed = double(grant.RIUsed);
            end
            context.GrantSnapshot = replayGrant;
            context.HARQContext = sixgr.util.structGet(context, "HARQContext", struct());
            context.HARQContext.GrantSnapshot = replayGrant;
        else
            tbBits = sixgr.truth.CoupledTruthRuntime.generateTransportBlockBits(cfg, grant, ueIdx, direction, state.CurrentSlot);
            harq = sixgr.util.structGet(grant, "HARQ", struct());
            context = struct();
            context.TransportBlockBits = tbBits;
            context.RV = sixgr.util.structGet(harq, "RV", []);
            context.PreviousCombinedLLR = [];
            context.GrantSnapshot = grant;
            context.HARQContext = struct( ...
                "Direction", char(direction), ...
                "UEIndex", double(ueIdx), ...
                "RNTI", double(sixgr.util.structGet(grant, "RNTI", NaN)), ...
                "HarqID", double(sixgr.util.structGet(harq, "HarqID", NaN)), ...
                "NDI", logical(sixgr.util.structGet(harq, "NDI", true)), ...
                "IsRetransmission", false, ...
                "FeedbackDelaySlots", double(state.HARQFeedbackSlots), ...
                "RV", double(sixgr.util.structGet(harq, "RV", 0)), ...
                "GrantSnapshot", grant);
        end
        expectedUCI = sixgr.truth.CoupledTruthRuntime.resolveGrantExpectedUCIBits(grant);
        if ~isempty(expectedUCI)
            context.ExpectedUCIBits = int8(expectedUCI(:));
            context.HARQContext.ExpectedUCIBits = int8(expectedUCI(:));
        end
        [state, context] = sixgr.truth.CoupledTruthRuntime.attachRuntimeChannelStateToGrantContext(state, cfg, ueIdx, direction, context);
        grantRow = sixgr.truth.CoupledTruthRuntime.buildGrantTraceRow( ...
            sixgr.util.structGet(context, "GrantSnapshot", grant), direction, ...
            sixgr.util.structGet(sixgr.util.structGet(context, "GrantSnapshot", grant), "Slot", state.CurrentSlot), ...
            sixgr.util.structGet(sixgr.util.structGet(context, "GrantSnapshot", grant), "Frame", state.CurrentFrame), ...
            ueIdx, ...
            sixgr.truth.CoupledTruthRuntime.latestFeedbackForDirection(state, ueIdx, direction));
    end

    function [state, context] = attachRuntimeChannelStateToGrantContext(state, cfg, ueIdx, direction, context)
        if ~(isstruct(context) && isstruct(sixgr.util.structGet(context, "GrantSnapshot", struct())))
            return;
        end
        if ~sixgr.channel.ChannelFactory.requiresRuntimeChannelState(cfg)
            return;
        end
        direction = upper(string(direction));
        grant = sixgr.util.structGet(context, "GrantSnapshot", struct());
        servingCell = double(sixgr.util.structGet(grant, "ServingCell", ...
            sixgr.truth.CoupledTruthRuntime.currentServingCellForUE(state, ueIdx)));
        if ~(isfinite(servingCell) && servingCell >= 1)
            servingCell = 1;
        end
        linkKey = sixgr.channel.ChannelFactory.runtimeChannelKey(cfg, direction, ...
            "UEIndex", ueIdx, "ServingCell", servingCell);
        [state, chState] = sixgr.truth.CoupledTruthRuntime.resolveRuntimeChannelState(state, cfg, direction, linkKey, ueIdx, servingCell);
        slotStartTime_s = max(0, double(sixgr.util.structGet(state, "CurrentSlot", 1)) - 1) * ...
            double(sixgr.util.structGet(state, "SlotDuration_s", sixgr.truth.CoupledTruthRuntime.slotDuration(cfg)));
        chState.TargetSlotStartTime_s = double(slotStartTime_s);
        chState.TargetSlot = double(sixgr.util.structGet(state, "CurrentSlot", NaN));
        chState.TargetFrame = double(sixgr.util.structGet(state, "CurrentFrame", NaN));
        chState.TargetUEIndex = double(ueIdx);
        chState.TargetServingCell = double(servingCell);
        chState.Direction = char(direction);

        grant.RuntimeChannelLinkKey = char(linkKey);
        grant.RuntimeChannelSeed = double(chState.Seed);
        grant.RuntimeChannelStateContract = char(string(chState.ContractVersion));
        grant.GrantWorkerSafe = false;
        grant.GrantSharedStateCommitMode = "serial_runtime_channel_state_commit";
        context.GrantSnapshot = grant;
        context.ChannelState = chState;
        context.RuntimeChannelLinkKey = char(linkKey);
        context.AbsoluteSampleTime_s = double(slotStartTime_s);
        context.HARQContext.ChannelStateKey = char(linkKey);
        context.HARQContext.RuntimeChannelSeed = double(chState.Seed);
    end

    function [state, chState] = resolveRuntimeChannelState(state, cfg, direction, linkKey, ueIdx, servingCell)
        if ~isfield(state, "RuntimeChannelStates") || ~isstruct(state.RuntimeChannelStates)
            state.RuntimeChannelStates = repmat(sixgr.channel.ChannelFactory.emptyRuntimeChannelState(), 0, 1);
        end
        idx = sixgr.truth.CoupledTruthRuntime.findRuntimeChannelStateIndex(state, linkKey);
        if isfinite(idx)
            chState = state.RuntimeChannelStates(idx);
            return;
        end
        seed = sixgr.channel.ChannelFactory.runtimeChannelSeed(cfg, linkKey);
        chState = sixgr.channel.ChannelFactory.createRuntimeChannelState(cfg, direction, ...
            "LinkKey", linkKey, "Seed", seed, "UEIndex", ueIdx, "ServingCell", servingCell);
        state.RuntimeChannelStates(end + 1, 1) = chState;
    end

    function state = commitRuntimeChannelStateImpl(state, channelState)
        if ~(isstruct(channelState) && isfield(channelState, "ContractVersion"))
            return;
        end
        linkKey = char(string(sixgr.util.structGet(channelState, "LinkKey", "")));
        if strlength(strtrim(string(linkKey))) == 0
            return;
        end
        if ~isfield(state, "RuntimeChannelStates") || ~isstruct(state.RuntimeChannelStates)
            state.RuntimeChannelStates = repmat(sixgr.channel.ChannelFactory.emptyRuntimeChannelState(), 0, 1);
        end
        idx = sixgr.truth.CoupledTruthRuntime.findRuntimeChannelStateIndex(state, linkKey);
        if isfinite(idx)
            state.RuntimeChannelStates(idx) = channelState;
        else
            state.RuntimeChannelStates(end + 1, 1) = channelState;
        end
    end

    function idx = findRuntimeChannelStateIndex(state, linkKey)
        idx = NaN;
        states = sixgr.util.structGet(state, "RuntimeChannelStates", repmat(struct(), 0, 1));
        if ~(isstruct(states) && ~isempty(states))
            return;
        end
        keys = arrayfun(@(s) string(sixgr.util.structGet(s, "LinkKey", "")), states(:));
        hit = find(keys == string(linkKey), 1, "first");
        if ~isempty(hit)
            idx = double(hit);
        end
    end

    function state = writeTablesImpl(state, runFolder)
        if nargin < 2 || strlength(string(runFolder)) == 0
            runFolder = state.RunFolder;
        end
        if ~(istable(state.UserPerformanceTable) && ~isempty(state.UserPerformanceTable))
            state.UserPerformanceTable = sixgr.truth.CoupledTruthRuntime.buildUserPerformanceTable(state);
        end
        if ~(istable(state.CoverageSnapshotTable) && ~isempty(state.CoverageSnapshotTable)) && ...
                istable(state.ServingTraceTable) && ~isempty(state.ServingTraceTable)
            state.CoverageSnapshotTable = sixgr.truth.CoupledTruthRuntime.buildCoverageSnapshotTable(state.ServingTraceTable);
        end
        if ~(istable(state.CoverageLayerTable) && ~isempty(state.CoverageLayerTable)) && ...
                istable(state.CoverageSnapshotTable) && ~isempty(state.CoverageSnapshotTable)
            state.CoverageLayerTable = sixgr.truth.CoupledTruthRuntime.buildCoverageLayerTable(state);
        end
        if ~(istable(state.HARQSummaryTable) && ~isempty(state.HARQSummaryTable)) && ...
                istable(state.HARQTimelineTable) && ~isempty(state.HARQTimelineTable)
            state.HARQSummaryTable = sixgr.truth.CoupledTruthRuntime.buildHARQSummary(state.HARQTimelineTable);
        end
        layout = sixgr.report.resultLayout(runFolder);
        state.ControlTrials.PBCH = sixgr.truth.CoupledTruthRuntime.annotateControlReferenceTrialTable(state, "PBCH", sixgr.util.structGet(state.ControlTrials, "PBCH", table()));
        state.ControlTrials.PRACH = sixgr.truth.CoupledTruthRuntime.annotateControlReferenceTrialTable(state, "PRACH", sixgr.util.structGet(state.ControlTrials, "PRACH", table()));
        state.ControlTrials.PDCCH = sixgr.truth.CoupledTruthRuntime.annotateControlReferenceTrialTable(state, "PDCCH", sixgr.util.structGet(state.ControlTrials, "PDCCH", table()));
        state.ControlTrials.PUCCH = sixgr.truth.CoupledTruthRuntime.annotateControlReferenceTrialTable(state, "PUCCH", sixgr.util.structGet(state.ControlTrials, "PUCCH", table()));
        state.ControlTrials.SRS = sixgr.truth.CoupledTruthRuntime.annotateControlReferenceTrialTable(state, "SRS", sixgr.util.structGet(state.ControlTrials, "SRS", table()));
        state.ControlTrials.TRS = sixgr.truth.CoupledTruthRuntime.annotateControlReferenceTrialTable(state, "TRS", sixgr.util.structGet(state.ControlTrials, "TRS", table()));
        state.PUCCHGrantTraceTable = sixgr.truth.CoupledTruthRuntime.annotatePUCCHGrantTraceTable(state, sixgr.util.structGet(state, "PUCCHGrantTraceTable", table()));
        if ~sixgr.util.persistenceEnabled()
            state.RunState = sixgr.truth.CoupledTruthRuntime.refreshRunState(state);
            state.RunFolder = string(runFolder);
            return;
        end

        % Keep control-plane trials on both canonical browser-owned
        % air-interface paths and explicit control mirrors; the mirror is
        % diagnostic, while the air-interface path is the browser owner.
        sixgr.truth.CoupledTruthRuntime.writeMirroredTable(layout, "pbch_trials.csv", sixgr.util.structGet(state.ControlTrials, "PBCH", table()));
        sixgr.truth.CoupledTruthRuntime.writeMirroredTable(layout, "prach_trials.csv", sixgr.util.structGet(state.ControlTrials, "PRACH", table()));
        sixgr.truth.CoupledTruthRuntime.writeMirroredTable(layout, "pdcch_trials.csv", sixgr.util.structGet(state.ControlTrials, "PDCCH", table()));
        sixgr.truth.CoupledTruthRuntime.writeMirroredTable(layout, "pucch_trials.csv", sixgr.util.structGet(state.ControlTrials, "PUCCH", table()));
        sixgr.truth.CoupledTruthRuntime.writeMirroredTable(layout, "srs_trials.csv", sixgr.util.structGet(state.ControlTrials, "SRS", table()));
        sixgr.truth.CoupledTruthRuntime.writeMirroredTable(layout, "trs_trials.csv", sixgr.util.structGet(state.ControlTrials, "TRS", table()));
        prachCorrelationTrace = sixgr.util.structGet(state.ControlTrials, "PRACHCorrelationTrace", table());
        if istable(prachCorrelationTrace) && ~isempty(prachCorrelationTrace)
            sixgr.util.csvWriteTable(fullfile(layout.ReportCSVDir, "prach_correlation_trace.csv"), prachCorrelationTrace);
            sixgr.util.csvWriteTable(fullfile(layout.ReportCSVDir, "prach_correlation_traces.csv"), prachCorrelationTrace);
        end
        sixgr.truth.CoupledTruthRuntime.writeRAEvidenceTables(layout, ...
            sixgr.util.structGet(state.ControlTrials, "RAEvidenceTables", struct()));
        sixgr.util.csvWriteTable(fullfile(layout.ReportCSVDir, "live_rsrp_serving_trace.csv"), state.ServingTraceTable);
        sixgr.util.csvWriteTable(fullfile(layout.ReportCSVDir, "live_cell_measurement_trace.csv"), state.MeasurementTraceTable);
        sixgr.util.csvWriteTable(fullfile(layout.ReportCSVDir, "live_cell_reselection_events.csv"), state.ReselectionEventTable);
        sixgr.util.csvWriteTable(fullfile(layout.ReportCSVDir, "live_coverage_snapshot.csv"), state.CoverageSnapshotTable);
        sixgr.util.csvWriteTable(fullfile(layout.ReportCSVDir, "live_user_performance_snapshot.csv"), state.UserPerformanceTable);
        sixgr.util.csvWriteTable(fullfile(layout.ReportCSVDir, "live_coverage_layer.csv"), state.CoverageLayerTable);
        sixgr.util.csvWriteTable(fullfile(layout.HARQCSVDir, "live_harq_observation_summary.csv"), state.HARQSummaryTable);
        sixgr.util.csvWriteTable(fullfile(layout.HARQCSVDir, "live_harq_observation_timeline.csv"), state.HARQTimelineTable);
        sixgr.util.csvWriteTable(fullfile(layout.PacketFlowCSVDir, "live_dl_scheduler_grants.csv"), sixgr.util.structGet(state, "DLGrantTraceTable", table()));
        sixgr.util.csvWriteTable(fullfile(layout.PacketFlowCSVDir, "live_ul_scheduler_grants.csv"), sixgr.util.structGet(state, "ULGrantTraceTable", table()));
        sixgr.util.csvWriteTable(fullfile(layout.PacketFlowCSVDir, "live_application_packet_delivery_ledger.csv"), ...
            sixgr.util.structGet(state, "PacketDeliveryLedgerTable", table()));
        sixgr.util.csvWriteTable(fullfile(layout.PacketFlowCSVDir, "live_packet_sdu_delivery_ledger.csv"), ...
            sixgr.util.structGet(state, "PacketSDULedgerTable", table()));
        schedulerDecisionT = sixgr.util.structGet(state, "SchedulerDecisionTable", table());
        if istable(schedulerDecisionT) && ~isempty(schedulerDecisionT)
            sixgr.util.csvWriteTable(fullfile(layout.PacketFlowCSVDir, "scheduler_decision_log.csv"), schedulerDecisionT);
            sixgr.util.csvWriteTable(fullfile(layout.PacketFlowCSVDir, "live_scheduler_decision_log.csv"), schedulerDecisionT);
            sixgr.util.csvWriteTable(fullfile(layout.PacketFlowCSVDir, "scheduler_ue_summary.csv"), ...
                sixgr.truth.CoupledTruthRuntime.buildSchedulerUESummaryTable(schedulerDecisionT));
        end
        sixgr.util.csvWriteTable(fullfile(layout.PacketFlowCSVDir, "live_pucch_grants.csv"), state.PUCCHGrantTraceTable);
        sixgr.util.csvWriteTable(fullfile(layout.ControlCSVDir, "initial_access_lifecycle_trace.csv"), ...
            sixgr.util.structGet(state, "InitialAccessLifecycleTraceTable", table()));
        sixgr.util.csvWriteTable(fullfile(layout.ReportCSVDir, "initial_access_lifecycle_trace.csv"), ...
            sixgr.util.structGet(state, "InitialAccessLifecycleTraceTable", table()));
        sixgr.monitor.AccessFlowRecorder.writeTables(runFolder, state);
        state.RunState = sixgr.truth.CoupledTruthRuntime.refreshRunState(state);
        runStateTable = struct2table(state.RunState);
        slotTraceTable = sixgr.util.structGet(state, "SlotTraceTable", table());
        sixgr.util.csvWriteTable(fullfile(layout.ReportCSVDir, "run_state.csv"), runStateTable);
        sixgr.util.csvWriteTable(fullfile(layout.ReportCSVDir, "slot_trace.csv"), slotTraceTable);
        sixgr.util.csvWriteTable(fullfile(layout.PacketFlowCSVDir, "slot_trace.csv"), slotTraceTable);
        receiverTrackingStateT = sixgr.truth.canonicalizeLLSLiveSignalChainTable("receiver_tracking_state", ...
            sixgr.truth.CoupledTruthRuntime.buildReceiverTrackingStateTable(state));
        receiverTrackingTraceT = sixgr.truth.canonicalizeLLSLiveSignalChainTable("receiver_tracking_trace", ...
            sixgr.util.structGet(state, "ReceiverTrackingTraceTable", table()));
        sixgr.util.csvWriteTable(fullfile(layout.ReportCSVDir, "live_receiver_tracking_state.csv"), receiverTrackingStateT);
        sixgr.util.csvWriteTable(fullfile(layout.ReportCSVDir, "live_receiver_tracking_trace.csv"), receiverTrackingTraceT);
        sixgr.util.csvWriteTable(fullfile(layout.ReportCSVDir, "live_control_gating_summary.csv"), ...
            sixgr.truth.CoupledTruthRuntime.buildControlSummaryTable(state));
        controlGatingStateT = sixgr.truth.canonicalizeLLSLiveSignalChainTable("control_gating_state", ...
            sixgr.truth.CoupledTruthRuntime.buildControlStateTable(state));
        sixgr.util.csvWriteTable(fullfile(layout.ReportCSVDir, "live_control_gating_state.csv"), controlGatingStateT);
        state.RunFolder = string(runFolder);
    end

    function T = annotateControlReferenceTrialTable(state, signalName, T)
        T = sixgr.truth.CoupledTruthRuntime.annotateControlReferenceTrialTableImpl(state, signalName, T);
    end

    function T = annotatePUCCHGrantTraceTable(state, T)
        T = sixgr.truth.CoupledTruthRuntime.annotatePUCCHGrantTraceTableImpl(state, T);
    end

    function state = commitGrantExecutionImpl(state, ueIdx, direction, grant)
        direction = upper(string(direction));
        if ~(isfinite(double(ueIdx)) && ueIdx >= 1 && ueIdx <= double(state.NumUsers))
            return;
        end
        if ~(isstruct(grant) && ~isempty(fieldnames(grant)))
            return;
        end

        tbsBits = double(sixgr.util.structGet(grant, "TransportBlockSize", sixgr.util.structGet(grant, "TBSBits", NaN)));
        if ~(isfinite(tbsBits) && tbsBits > 0)
            tbsBits = 0;
        end
        isRetx = logical(sixgr.util.structGet(sixgr.util.structGet(grant, "HARQ", struct()), "IsRetransmission", false));
        if ~isRetx && tbsBits > 0
            state = sixgr.truth.CoupledTruthRuntime.reserveGrantBits(state, ueIdx, direction, tbsBits, grant);
        end

        if direction == "UL"
            queueBitsAfter = double(state.ULQueueBits(ueIdx));
            traceT = sixgr.util.structGet(state, "ULGrantTraceTable", table());
        else
            queueBitsAfter = double(state.DLQueueBits(ueIdx));
            traceT = sixgr.util.structGet(state, "DLGrantTraceTable", table());
        end
        if ~(istable(traceT) && ~isempty(traceT))
            return;
        end

        slotNow = double(sixgr.util.structGet(grant, "Slot", sixgr.util.structGet(state, "CurrentSlot", NaN)));
        frameNow = double(sixgr.util.structGet(grant, "Frame", sixgr.util.structGet(state, "CurrentFrame", NaN)));
        mask = true(height(traceT), 1);
        if ismember("UEIndex", string(traceT.Properties.VariableNames))
            mask = mask & abs(double(traceT.UEIndex) - double(ueIdx)) < 1e-9;
        end
        if ismember("Slot", string(traceT.Properties.VariableNames)) && isfinite(slotNow)
            mask = mask & abs(double(traceT.Slot) - slotNow) < 1e-9;
        end
        if ismember("Frame", string(traceT.Properties.VariableNames)) && isfinite(frameNow)
            mask = mask & abs(double(traceT.Frame) - frameNow) < 1e-9;
        end
        idx = find(mask, 1, "last");
        if isempty(idx)
            return;
        end

        prbSet = double(sixgr.util.structGet(grant, "PRBSet", []));
        symAlloc = double(sixgr.util.structGet(grant, "SymbolAllocation", []));
        if ismember("PRBStart", string(traceT.Properties.VariableNames))
            traceT.PRBStart(idx) = sixgr.truth.CoupledTruthRuntime.firstNumeric(prbSet, NaN);
        end
        if ismember("PRBCount", string(traceT.Properties.VariableNames))
            traceT.PRBCount(idx) = double(numel(prbSet));
        end
        if ismember("SymbolStart", string(traceT.Properties.VariableNames))
            traceT.SymbolStart(idx) = sixgr.truth.CoupledTruthRuntime.firstNumeric(symAlloc, NaN);
        end
        if ismember("NumSymbols", string(traceT.Properties.VariableNames))
            traceT.NumSymbols(idx) = sixgr.truth.CoupledTruthRuntime.secondNumeric(symAlloc, NaN);
        end
        if ismember("TBSBits", string(traceT.Properties.VariableNames))
            traceT.TBSBits(idx) = double(tbsBits);
        end
        if ismember("TBSBytes", string(traceT.Properties.VariableNames))
            traceT.TBSBytes(idx) = floor(double(tbsBits) / 8);
        end
        if ismember("MCSIndex", string(traceT.Properties.VariableNames))
            traceT.MCSIndex(idx) = double(sixgr.util.structGet(grant, "MCSIndex", sixgr.util.structGet(grant, "MCS", NaN)));
        end
        if ismember("Modulation", string(traceT.Properties.VariableNames))
            modValue = sixgr.truth.CoupledTruthRuntime.firstString(sixgr.util.structGet(grant, "Modulation", ""), "");
            if iscell(traceT.Modulation)
                traceT.Modulation(idx) = {modValue};
            else
                traceT.Modulation(idx) = string(modValue);
            end
        end
        if ismember("TargetCodeRate", string(traceT.Properties.VariableNames))
            traceT.TargetCodeRate(idx) = double(sixgr.util.structGet(grant, "TargetCodeRate", NaN));
        end
        if ismember("NumLayers", string(traceT.Properties.VariableNames))
            traceT.NumLayers(idx) = double(sixgr.util.structGet(grant, "NumLayers", sixgr.util.structGet(grant, "Layers", NaN)));
        end
        if ismember("PMI", string(traceT.Properties.VariableNames))
            traceT.PMI(idx) = double(sixgr.util.structGet(grant, "PMI", NaN));
        end
        if ismember("CRI", string(traceT.Properties.VariableNames))
            traceT.CRI(idx) = double(sixgr.util.structGet(grant, "CRI", NaN));
        end
        if ismember("ConfiguredBeamSelectionStrategy", string(traceT.Properties.VariableNames))
            traceT = sixgr.truth.CoupledTruthRuntime.localAssignTraceTextValue(traceT, "ConfiguredBeamSelectionStrategy", idx, ...
                sixgr.util.structGet(grant, "ConfiguredBeamSelectionStrategy", ""));
        end
        if ismember("PrecoderSource", string(traceT.Properties.VariableNames))
            traceT = sixgr.truth.CoupledTruthRuntime.localAssignTraceTextValue(traceT, "PrecoderSource", idx, ...
                sixgr.util.structGet(grant, "PrecoderSource", ""));
        end
        if ismember("PrecodingMode", string(traceT.Properties.VariableNames))
            traceT = sixgr.truth.CoupledTruthRuntime.localAssignTraceTextValue(traceT, "PrecodingMode", idx, ...
                sixgr.util.structGet(grant, "PrecodingMode", ""));
        end
        if ismember("PrecodingApplicationStage", string(traceT.Properties.VariableNames))
            traceT = sixgr.truth.CoupledTruthRuntime.localAssignTraceTextValue(traceT, "PrecodingApplicationStage", idx, ...
                sixgr.util.structGet(grant, "PrecodingApplicationStage", ""));
        end
        if ismember("PrecodingActive", string(traceT.Properties.VariableNames))
            traceT.PrecodingActive(idx) = logical(sixgr.util.structGet(grant, "PrecodingActive", false));
        end
        if ismember("ExplicitBeamWeightsApplied", string(traceT.Properties.VariableNames))
            traceT.ExplicitBeamWeightsApplied(idx) = logical(sixgr.util.structGet(grant, "ExplicitBeamWeightsApplied", false));
        end
        if ismember("TransformPrecodingApplied", string(traceT.Properties.VariableNames))
            traceT.TransformPrecodingApplied(idx) = logical(sixgr.util.structGet(grant, "TransformPrecodingApplied", false));
        end
        if ismember("BeamformingApplied", string(traceT.Properties.VariableNames))
            traceT.BeamformingApplied(idx) = logical(sixgr.util.structGet(grant, "BeamformingApplied", false));
        end
        if ismember("AppliedBeamIndexSet", string(traceT.Properties.VariableNames))
            traceT = sixgr.truth.CoupledTruthRuntime.localAssignTraceTextValue(traceT, "AppliedBeamIndexSet", idx, ...
                sixgr.util.structGet(grant, "AppliedBeamIndexSet", ""));
        end
        if ismember("AppliedPrecoderPMI", string(traceT.Properties.VariableNames))
            traceT.AppliedPrecoderPMI(idx) = double(sixgr.util.structGet(grant, "AppliedPrecoderPMI", NaN));
        end
        if ismember("AppliedPrecoderPMIType", string(traceT.Properties.VariableNames))
            traceT = sixgr.truth.CoupledTruthRuntime.localAssignTraceTextValue(traceT, "AppliedPrecoderPMIType", idx, ...
                sixgr.util.structGet(grant, "AppliedPrecoderPMIType", ""));
        end
        if ismember("AppliedPrecoderCodebookMode", string(traceT.Properties.VariableNames))
            traceT = sixgr.truth.CoupledTruthRuntime.localAssignTraceTextValue(traceT, "AppliedPrecoderCodebookMode", idx, ...
                sixgr.util.structGet(grant, "AppliedPrecoderCodebookMode", ""));
        end
        if ismember("PrecodingNumPorts", string(traceT.Properties.VariableNames))
            traceT.PrecodingNumPorts(idx) = double(sixgr.util.structGet(grant, "PrecodingNumPorts", NaN));
        end
        if ismember("PrecodingNumLayers", string(traceT.Properties.VariableNames))
            traceT.PrecodingNumLayers(idx) = double(sixgr.util.structGet(grant, "PrecodingNumLayers", NaN));
        end
        if ismember("PrecodingMatrixRows", string(traceT.Properties.VariableNames))
            traceT.PrecodingMatrixRows(idx) = double(sixgr.util.structGet(grant, "PrecodingMatrixRows", NaN));
        end
        if ismember("PrecodingMatrixCols", string(traceT.Properties.VariableNames))
            traceT.PrecodingMatrixCols(idx) = double(sixgr.util.structGet(grant, "PrecodingMatrixCols", NaN));
        end
        if ismember("GrantContextId", string(traceT.Properties.VariableNames))
            traceT = sixgr.truth.CoupledTruthRuntime.localAssignTraceTextValue(traceT, "GrantContextId", idx, ...
                sixgr.util.structGet(grant, "GrantContextId", ""));
        end
        if ismember("GrantWorkerSafe", string(traceT.Properties.VariableNames))
            traceT.GrantWorkerSafe(idx) = logical(sixgr.util.structGet(grant, "GrantWorkerSafe", true));
        end
        if ismember("GrantSharedStateCommitMode", string(traceT.Properties.VariableNames))
            traceT = sixgr.truth.CoupledTruthRuntime.localAssignTraceTextValue(traceT, "GrantSharedStateCommitMode", idx, ...
                sixgr.util.structGet(grant, "GrantSharedStateCommitMode", "serial_coordinator_commit"));
        end
        if ~isRetx && ismember("QueueBytesAfter", string(traceT.Properties.VariableNames))
            traceT.QueueBytesAfter(idx) = floor(max(0, queueBitsAfter) / 8);
        end

        if direction == "UL"
            state.ULGrantTraceTable = traceT;
        else
            state.DLGrantTraceTable = traceT;
        end
    end

    function cfgOut = prepareMobilityConfig(cfg, multiUser)
        cfgOut = cfg;
        requestedUE = double(sixgr.util.structGet(cfg, "scenario.nUE", sixgr.util.structGet(cfg, "scenario.ue.nUE", 1)));
        requestedUE = max(requestedUE, double(sixgr.util.structGet(multiUser, "NumUsers", 1)));
        requestedUE = max(1, round(requestedUE));
        cfgOut = sixgr.util.structSet(cfgOut, "scenario.nUE", requestedUE);
        cfgOut = sixgr.util.structSet(cfgOut, "scenario.ue.nUE", requestedUE);
    end

    function cfgOut = prepareLargeScaleConfig(cfg)
        cfgOut = cfg;
        cfgOut = sixgr.util.structSet(cfgOut, "channel.pathlossEnabled", ...
            sixgr.truth.CoupledTruthRuntime.configLogicalOrDefault(cfg, ...
            ["channel.pathlossEnabled", "channel.pathloss.enabled", "channel.pathloss_enabled", ...
             "channels.pathloss_enabled", "lls6g.channels.pathloss_enabled"], true));
        cfgOut = sixgr.util.structSet(cfgOut, "channel.losEnabled", ...
            sixgr.truth.CoupledTruthRuntime.configLogicalOrDefault(cfg, ...
            ["channel.losEnabled", "channel.los.enabled", "channel.los_enabled", ...
             "channels.los_enabled", "lls6g.channels.los_enabled"], true));
        cfgOut = sixgr.util.structSet(cfgOut, "channel.shadowFadingEnabled", ...
            sixgr.truth.CoupledTruthRuntime.configLogicalOrDefault(cfg, ...
            ["channel.shadowFadingEnabled", "channel.shadowFading.enabled", "channel.shadow_fading_enabled", ...
             "channels.shadow_fading_enabled", "lls6g.channels.shadow_fading_enabled"], true));
        pathlossModel = string(sixgr.truth.CoupledTruthRuntime.configStringOrDefault(cfg, ...
            ["channel.pathlossModel", "channel.pathloss.model", "channel.pathloss_model", ...
             "channels.pathloss_model", "lls6g.channels.pathloss_model"], "nrPathLoss"));
        cfgOut = sixgr.util.structSet(cfgOut, "channel.pathlossModel", pathlossModel);
    end

    function nRB = estimateNRB(cfg)
        vals = double([sixgr.util.structGet(cfg, "phy.carrier.NSizeGrid", NaN), sixgr.util.structGet(cfg, "phy.pdsch.nPRB", NaN), sixgr.util.structGet(cfg, "phy.pusch.nPRB", NaN)]);
        vals = vals(isfinite(vals) & vals >= 1);
        if isempty(vals)
            nRB = 52;
        else
            nRB = max(1, round(vals(1)));
        end
    end

    function slotDur_s = slotDuration(cfg)
        scs = double(sixgr.util.structGet(cfg, "phy.carrier.SubcarrierSpacing", 30));
        slotsPerMs = max(scs / 15, 1);
        slotDur_s = 1e-3 / slotsPerMs;
    end

    function [allowDL, allowUL, slotLabel, partition] = slotDuplexState(cfg, canonicalSlot)
        partition = sixgr.util.resolveTDDSlotPartition(cfg, canonicalSlot);
        allowDL = logical(partition.AllowDL);
        allowUL = logical(partition.AllowUL);
        slotLabel = string(partition.SlotLabel);
    end

    function tokens = expandTDDPattern(pattern)
        if isstruct(pattern)
            dl = max(0, round(double(sixgr.util.structGet(pattern, "dlSlots", 4))));
            ul = max(0, round(double(sixgr.util.structGet(pattern, "ulSlots", 1))));
            sp = max(0, round(double(sixgr.util.structGet(pattern, "specialSlots", 0))));
            tokens = [repmat('D', 1, dl), repmat('S', 1, sp), repmat('U', 1, ul)];
            return;
        end
        if isstring(pattern) || ischar(pattern)
            tokens = regexprep(upper(char(string(pattern))), "[^DUS]", "");
            if isempty(tokens)
                tokens = 'DDDSU';
            end
            return;
        end
        if isnumeric(pattern)
            p = double(pattern(:).');
            tokens = repmat('S', 1, numel(p));
            tokens(p > 0) = 'D';
            tokens(p < 0) = 'U';
            return;
        end
        tokens = 'DDDSU';
    end

    function slots = slotsPerFrame(cfg, slotDuration_s)
        slots = double(sixgr.util.structGet(cfg, "frame_timing.slots_per_frame", NaN));
        if ~(isfinite(slots) && slots >= 1)
            slots = double(sixgr.util.structGet(cfg, "phy.numerology.slotsPerFrame", NaN));
        end
        if ~(isfinite(slots) && slots >= 1)
            slotDuration_s = max(eps, double(slotDuration_s));
            slots = round(0.01 / slotDuration_s);
        end
        slots = max(1, round(double(slots)));
    end

    function frameIdx = frameIndexForSlot(state, canonicalSlot)
        slotsPerFrame = max(1, round(double(sixgr.util.structGet(state, "SlotsPerFrame", 1))));
        canonicalSlot = max(1, round(double(canonicalSlot)));
        frameIdx = 1 + floor((canonicalSlot - 1) / slotsPerFrame);
    end

    function totalFrames = framesPerSweepPoint(state, totalCanonicalSlots)
        slotsPerFrame = max(1, round(double(sixgr.util.structGet(state, "SlotsPerFrame", 1))));
        totalCanonicalSlots = round(double(totalCanonicalSlots));
        if ~(isfinite(totalCanonicalSlots) && totalCanonicalSlots >= 1)
            totalCanonicalSlots = 1;
        end
        totalFrames = max(1, ceil(double(totalCanonicalSlots) / double(slotsPerFrame)));
    end

    function [state, trialT] = completeSlotImpl(state, cfgU, ueIdx, direction, trialT, res)
        if ~(istable(trialT) && ~isempty(trialT))
            return;
        end
        row = trialT(end, :);
        [state, harqFields] = sixgr.truth.CoupledTruthRuntime.updateHARQState(state, ueIdx, direction, cfgU, row, res);
        trialT = sixgr.truth.CoupledTruthRuntime.annotateHARQTrialTable(trialT, harqFields);
        state = sixgr.truth.CoupledTruthRuntime.enqueueCSIReport(state, ueIdx, direction, trialT(end, :));
        state = sixgr.truth.CoupledTruthRuntime.appendTelemetry(state, ueIdx, trialT(end, :));
        state = sixgr.truth.CoupledTruthRuntime.updateUserStats(state, ueIdx, direction, trialT(end, :));
        state = sixgr.truth.CoupledTruthRuntime.updateDecodeSuccessCount(state, ueIdx, direction, trialT(end, :));
        if upper(string(direction)) == "UL"
            state = sixgr.truth.CoupledTruthRuntime.updateTimingAdvanceFromReceiverTrialImpl( ...
                state, ueIdx, trialT(end, :), "ul_data_receiver_timing_estimate");
        end
        state.UserPerformanceTable = sixgr.truth.CoupledTruthRuntime.buildUserPerformanceTable(state);
        state.CoverageLayerTable = sixgr.truth.CoupledTruthRuntime.buildCoverageLayerTable(state);
        frameLocal = double(sixgr.util.structGet(state, "CurrentFrameLocal", NaN));
        if ~(isfinite(frameLocal) && frameLocal >= 1)
            frameLocal = double(sixgr.truth.CoupledTruthRuntime.rowValue(row, "Frame", state.CurrentFrameLocal));
        end
        canonicalSlot = double(sixgr.util.structGet(state, "CurrentCanonicalSlot", NaN));
        if upper(string(direction)) == "UL"
            state.ULCompletedFrames = max(double(sixgr.util.structGet(state, "ULCompletedFrames", 0)), frameLocal);
            if isfinite(canonicalSlot)
                state.ULCompletedSlots = max(double(sixgr.util.structGet(state, "ULCompletedSlots", 0)), canonicalSlot);
            end
        else
            state.DLCompletedFrames = max(double(sixgr.util.structGet(state, "DLCompletedFrames", 0)), frameLocal);
            if isfinite(canonicalSlot)
                state.DLCompletedSlots = max(double(sixgr.util.structGet(state, "DLCompletedSlots", 0)), canonicalSlot);
            end
        end
        state = sixgr.truth.CoupledTruthRuntime.recordSlotTraceTrial(state, direction, trialT(end, :));
        state = sixgr.truth.CoupledTruthRuntime.recordInitialAccessGrantCompletion(state, ueIdx, direction, trialT(end, :));
    end

    function state = processDueFeedback(state)
        grantTrace = sixgr.util.structGet(state, "PUCCHGrantTraceTable", table());
        if ~(istable(grantTrace) && ~isempty(grantTrace))
            dueGrantMask = false(0, 1);
        else
            currentULAllowed = logical(sixgr.util.structGet(state, "CurrentSlotULAllowed", true));
            currentULSymbols = double(sixgr.util.structGet(state, "CurrentSlotULNumSymbols", 14));
            if ~(currentULAllowed && isfinite(currentULSymbols) && currentULSymbols > 0)
                dueGrantMask = false(height(grantTrace), 1);
            else
                dueGrantMask = ~logical(grantTrace.GrantExecutedFlag) & ...
                    abs(double(grantTrace.ScheduledAbsoluteSlot) - double(state.CurrentSlot)) < 1e-9;
            end
        end
        if any(dueGrantMask)
            dueGrantRows = grantTrace(dueGrantMask, :);
            for i = 1:height(dueGrantRows)
                row = dueGrantRows(i, :);
                direction = upper(string(row.FeedbackForDirection));
                if strlength(strtrim(direction)) == 0
                    direction = upper(string(row.Direction));
                end
                [state, observedFeedback] = sixgr.truth.CoupledTruthRuntime.observePUCCHFeedback(state, row);
                observedAck = logical(sixgr.util.structGet(observedFeedback, "ObservedAck", false));
                if direction == "UL"
                    harq = state.ULHarq;
                    buffers = state.ULCombinedLLR;
                else
                    harq = state.DLHarq;
                    buffers = state.DLCombinedLLR;
                end
                harq.onFeedback(double(row.RNTI), double(row.HarqID), observedAck, ...
                    "SourceSlot", double(row.SourceSlot));
                pid = double(row.HarqID) + 1;
                if observedAck
                    try
                        harq.clearSoftBuffer(double(row.RNTI), double(row.HarqID));
                    catch
                    end
                    if double(row.UEIndex) <= size(buffers, 1) && pid <= size(buffers, 2)
                        buffers{double(row.UEIndex), pid} = [];
                    end
                end
                rowAck = row;
                rowAck.Ack(1) = observedAck;
                rowAck.Processed(1) = true;
                state = sixgr.truth.CoupledTruthRuntime.updateSchedulerAfterFeedback(state, rowAck, direction);
                state = sixgr.truth.CoupledTruthRuntime.updatePUCCHGrantTraceAfterObservation(state, row, observedFeedback);
                state = sixgr.truth.CoupledTruthRuntime.markPendingFeedbackProcessedByGrantId(state, ...
                    sixgr.truth.CoupledTruthRuntime.rowValue(row, "PUCCHGrantId", ""));
                if direction == "UL"
                    state.ULHarq = harq;
                    state.ULCombinedLLR = buffers;
                else
                    state.DLHarq = harq;
                    state.DLCombinedLLR = buffers;
                end
            end
        end

        if ~(istable(state.PendingCSITable) && ~isempty(state.PendingCSITable))
            return;
        end
        dueCSIMask = ~logical(state.PendingCSITable.Processed) & double(state.PendingCSITable.DueSlot) <= double(state.CurrentSlot);
        if ~any(dueCSIMask)
            return;
        end
        dueCSI = state.PendingCSITable(dueCSIMask, :);
        for i = 1:height(dueCSI)
            row = dueCSI(i, :);
            ueIdx = double(row.UEIndex);
            if ~(isfinite(ueIdx) && ueIdx >= 1 && ueIdx <= state.NumUsers)
                continue;
            end
            rowDirection = upper(string(row.Direction));
            latest = sixgr.truth.CoupledTruthRuntime.emptyLatestFeedbackRow();
            latest.Valid = true;
            latest.CQI = double(row.CQI);
            latest.RI = double(row.RI);
            latest.PMI = double(sixgr.truth.CoupledTruthRuntime.sanitizeFeedbackPMI( ...
                row.PMI, state.CfgMobility, rowDirection, latest.RI));
            latest.CRI = double(sixgr.truth.CoupledTruthRuntime.sanitizeFeedbackCRI( ...
                row.CRI, state.CfgMobility));
            latest.SINR_dB = double(row.SINR_dB);
            latest.MCSIndex = double(row.MCSIndex);
            latest.TargetCodeRate = double(row.TargetCodeRate);
            latest.ServingCell = double(row.ServingCell);
            latest.Slot = double(row.SourceSlot);
            latest.Modulation = char(string(row.Modulation));
            latest.Direction = char(rowDirection);
            latest.RawCQIDerivedMCS = double(sixgr.truth.CoupledTruthRuntime.rowValue(row, "RawCQIDerivedMCS", NaN));
            latest.RawCQIDerivedTargetCodeRate = double(sixgr.truth.CoupledTruthRuntime.rowValue(row, "RawCQIDerivedTargetCodeRate", NaN));
            latest.RawCQIDerivedModulation = char(string(sixgr.truth.CoupledTruthRuntime.rowValue(row, "RawCQIDerivedModulation", "")));
            latest.LinkAdaptationMCSIndex = double(sixgr.truth.CoupledTruthRuntime.rowValue(row, "LinkAdaptationMCSIndex", NaN));
            latest.LinkAdaptationDecisionReason = char(string(sixgr.truth.CoupledTruthRuntime.rowValue(row, "LinkAdaptationDecisionReason", "")));
            latest.MCSSelectionSource = char(string(sixgr.truth.CoupledTruthRuntime.rowValue(row, "MCSSelectionSource", "")));
            latest.MCSValueStatus = char(string(sixgr.truth.CoupledTruthRuntime.rowValue(row, "MCSValueStatus", "")));
            latest.CQIBasedMCS = double(sixgr.truth.CoupledTruthRuntime.rowValue(row, "CQIBasedMCS", NaN));
            latest.SmoothedCQI = double(sixgr.truth.CoupledTruthRuntime.rowValue(row, "SmoothedCQI", NaN));
            latest.InstantaneousCQIMCS = double(sixgr.truth.CoupledTruthRuntime.rowValue(row, "InstantaneousCQIMCS", NaN));
            latest.DeltaMCS = double(sixgr.truth.CoupledTruthRuntime.rowValue(row, "DeltaMCS", NaN));
            latest.EffectiveCQISmoothingAlpha = double(sixgr.truth.CoupledTruthRuntime.rowValue(row, "EffectiveCQISmoothingAlpha", NaN));
            latest.CSITemporalCorrelationWeight = double(sixgr.truth.CoupledTruthRuntime.rowValue(row, "CSITemporalCorrelationWeight", NaN));
            latest.CSIAgeSeconds = double(sixgr.truth.CoupledTruthRuntime.rowValue(row, "CSIAgeSeconds", NaN));
            latest.CSICoherenceTimeSeconds = double(sixgr.truth.CoupledTruthRuntime.rowValue(row, "CSICoherenceTimeSeconds", NaN));
            latest.CSIAgingModel = char(string(sixgr.truth.CoupledTruthRuntime.rowValue(row, "CSIAgingModel", "")));
            latest.SubbandSINRVector_dB = char(string(sixgr.truth.CoupledTruthRuntime.rowValue(row, "SubbandSINRVector_dB", "")));
            latest.AgedSubbandSINRVector_dB = char(string(sixgr.truth.CoupledTruthRuntime.rowValue(row, "AgedSubbandSINRVector_dB", "")));
            latest.PostEqSINRPerLayer_dB = char(string(sixgr.truth.CoupledTruthRuntime.rowValue(row, "PostEqSINRPerLayer_dB", "")));
            latest.AgedPostEqSINRPerLayer_dB = char(string(sixgr.truth.CoupledTruthRuntime.rowValue(row, "AgedPostEqSINRPerLayer_dB", "")));
            latest.SubbandAgingPenaltyVector_dB = char(string(sixgr.truth.CoupledTruthRuntime.rowValue(row, "SubbandAgingPenaltyVector_dB", "")));
            latest.LayerAgingPenaltyVector_dB = char(string(sixgr.truth.CoupledTruthRuntime.rowValue(row, "LayerAgingPenaltyVector_dB", "")));
            latest.OuterLoopEnabled = logical(sixgr.truth.CoupledTruthRuntime.rowLogical(row, "OuterLoopEnabled", false));
            latest.InnerLoopEnabled = logical(sixgr.truth.CoupledTruthRuntime.rowLogical(row, "InnerLoopEnabled", false));
            latest.LinkAdaptationStateUpdateCount = double(sixgr.truth.CoupledTruthRuntime.rowValue(row, "LinkAdaptationStateUpdateCount", NaN));
            latest.FeedbackSourceSignal = char(rowDirection + "_CSI_REPORT");
            latest.FeedbackCRCPass = double(sixgr.truth.CoupledTruthRuntime.rowValue(row, "CRCPass", NaN));
            if rowDirection == "UL"
                state.LatestULFeedback(ueIdx) = latest;
            else
                state.LatestDLFeedback(ueIdx) = latest;
            end
        end
        state.PendingCSITable.Processed(dueCSIMask) = true;
    end

    function state = cancelUnexecutedHARQGrantImpl(state, grant, direction)
        direction = upper(string(direction));
        harqStruct = sixgr.util.structGet(grant, "HARQ", struct());
        harqId0 = double(sixgr.util.structGet(harqStruct, "HarqID", NaN));
        isRetx = logical(sixgr.util.structGet(harqStruct, "IsRetransmission", false));
        rnti = double(sixgr.util.structGet(grant, "RNTI", NaN));
        if ~(isfinite(rnti) && isfinite(harqId0)) || isRetx
            return;
        end
        if direction == "UL"
            harq = state.ULHarq;
        else
            harq = state.DLHarq;
        end
        try
            harq.cancelTentativeTx(rnti, harqId0);
        catch
        end
        if direction == "UL"
            state.ULHarq = harq;
        else
            state.DLHarq = harq;
        end
    end

    function [state, harqFields] = updateHARQState(state, ueIdx, direction, cfgU, row, res)
        direction = upper(string(direction));
        rnti = double(max(1, round(double(state.MultiUser.RNTIStart + ueIdx - 1))));
        slotIdx = double(sixgr.truth.CoupledTruthRuntime.rowValue(row, "Slot", state.CurrentSlot));
        harqOut = sixgr.util.structGet(res, "HARQ", struct());
        tbBits = int8(sixgr.util.structGet(harqOut, "TransportBlockBits", int8([])));
        if isempty(tbBits)
            tbBits = zeros(max(0, round(double(sixgr.truth.CoupledTruthRuntime.rowValue(row, "TBSize_bits", 0)))), 1, "int8");
        end
        combinedLLR = sixgr.util.structGet(harqOut, "CombinedLLR", []);
        softBuffer = sixgr.util.structGet(harqOut, "SoftBuffer", ...
            sixgr.util.structGet(harqOut, "HARQSoftBuffer", struct()));
        currentDecodeOK = logical(sixgr.util.structGet(harqOut, "CurrentDecodeOK", sixgr.truth.CoupledTruthRuntime.rowLogical(row, "CRCPass", false)));
        combinedDecodeOK = logical(sixgr.util.structGet(harqOut, "CombinedDecodeOK", currentDecodeOK));
        context = sixgr.util.structGet(harqOut, "Context", struct());
        if direction == "UL"
            harq = state.ULHarq;
            buffers = state.ULCombinedLLR;
        else
            harq = state.DLHarq;
            buffers = state.DLCombinedLLR;
        end
        isRetx = logical(sixgr.util.structGet(context, "IsRetransmission", false));
        hasScheduledHarq = isfinite(double(sixgr.util.structGet(context, "HarqID", NaN)));
        if isRetx
            harqId0 = double(sixgr.util.structGet(context, "HarqID", NaN));
            ndi = double(sixgr.util.structGet(context, "NDI", NaN));
            rv = double(sixgr.util.structGet(context, "RV", sixgr.truth.CoupledTruthRuntime.rowValue(row, "HARQRV", 0)));
        elseif hasScheduledHarq
            harqId0 = double(sixgr.util.structGet(context, "HarqID", NaN));
            ndi = double(sixgr.util.structGet(context, "NDI", NaN));
            rv = double(sixgr.util.structGet(context, "RV", sixgr.truth.CoupledTruthRuntime.rowValue(row, "HARQRV", 0)));
        else
            txp = harq.allocate(rnti, slotIdx, ceil(max(numel(tbBits), 1) / 8), "NewData", true);
            harqId0 = double(txp.HARQ.HarqID);
            ndi = double(txp.HARQ.NDI);
            rv = double(txp.HARQ.RV);
        end
        grantSnapshot = sixgr.util.structGet(harqOut, "GrantSnapshot", struct());
        if ~(isstruct(grantSnapshot) && ~isempty(fieldnames(grantSnapshot)))
            grantSnapshot = sixgr.truth.CoupledTruthRuntime.buildGrantSnapshot(cfgU, row, direction, ueIdx, rnti);
        end
        if ~isempty(tbBits)
            actualTBSBits = double(numel(tbBits));
            grantSnapshot.TransportBlockSize = actualTBSBits;
            grantSnapshot.TBSBits = actualTBSBits;
            grantSnapshot.TBSBytes = floor(actualTBSBits / 8);
        end
        harq.onTx(rnti, harqId0, uint8(tbBits(:)), grantSnapshot, slotIdx);
        pid = harqId0 + 1;
        if combinedDecodeOK
            buffers{ueIdx, pid} = [];
            try
                harq.clearSoftBuffer(rnti, harqId0);
            catch
            end
        else
            if isstruct(softBuffer) && ~isempty(fieldnames(softBuffer))
                try
                    harq.storeSoftBuffer(rnti, harqId0, softBuffer);
                    buffers{ueIdx, pid} = softBuffer;
                catch
                    buffers{ueIdx, pid} = combinedLLR;
                end
            else
                buffers{ueIdx, pid} = combinedLLR;
            end
        end
        if direction == "UL"
            state.ULHarq = harq;
            state.ULCombinedLLR = buffers;
        else
            state.DLHarq = harq;
            state.DLCombinedLLR = buffers;
        end

        fb = sixgr.truth.CoupledTruthRuntime.emptyFeedbackRow();
        fb.Direction = char(direction);
        fb.UEIndex = double(ueIdx);
        fb.RNTI = double(rnti);
        fb.HarqID = double(harqId0);
        fb.SourceSlot = double(slotIdx);
        fb.UCIBitCount = 1;
        feedbackDueSlot = sixgr.truth.CoupledTruthRuntime.resolveHARQFeedbackDueSlot(state, slotIdx, fb.UCIBitCount);
        fb.DueSlot = double(feedbackDueSlot);
        fb.Ack = logical(combinedDecodeOK);
        fb.CurrentDecodeOK = logical(currentDecodeOK);
        fb.CombinedDecodeOK = logical(combinedDecodeOK);
        servingVec = double(sixgr.util.structGet(state, "CurrentServingIdx", zeros(state.NumUsers, 1)));
        servingCell = NaN;
        if ueIdx >= 1 && ueIdx <= numel(servingVec)
            servingCell = double(servingVec(ueIdx));
        end
        fb.ServingCell = double(sixgr.util.structGet(context, "ServingCell", servingCell));
        fb.BaseStationID = double(fb.ServingCell);
        fb.TBSBits = double(sixgr.truth.CoupledTruthRuntime.rowValue(row, "TBSize_bits", numel(tbBits)));
        resource = sixgr.truth.CoupledTruthRuntime.resolvePUCCHResourceAssignment(state, fb);
        fb.RequestedFormat = double(sixgr.util.structGet(resource, "RequestedFormat", NaN));
        fb.ResolvedFormat = double(sixgr.util.structGet(resource, "ResolvedFormat", NaN));
        fb.PUCCHResourceId = char(string(sixgr.util.structGet(resource, "ResourceId", "")));
        fb.PUCCHPRBStart = double(sixgr.util.structGet(resource, "PRBStart", NaN));
        fb.PUCCHPRBCount = double(sixgr.util.structGet(resource, "PRBCount", NaN));
        fb.PUCCHSymbolStart = double(sixgr.util.structGet(resource, "SymbolStart", NaN));
        fb.PUCCHNumSymbols = double(sixgr.util.structGet(resource, "NumSymbols", NaN));
        fb.UCIType = char(string(sixgr.util.structGet(resource, "UCIType", "harq_ack")));
        fb.ControlResourceSource = char(string(sixgr.util.structGet(resource, "ControlResourceSource", "runtime_deterministic_pucch_resource_assignment")));
        fb.ControlResourceValidity = logical(sixgr.util.structGet(resource, "ControlResourceValidity", false));
        fb.FormatAdaptationReason = char(string(sixgr.util.structGet(resource, "FormatAdaptationReason", "")));
        fb.PUCCHGrantId = sixgr.truth.CoupledTruthRuntime.composePUCCHGrantId(state, fb);
        state.PendingFeedbackTable = sixgr.truth.CoupledTruthRuntime.appendCompatTable(state.PendingFeedbackTable, struct2table(fb, "AsArray", true));
        state = sixgr.truth.CoupledTruthRuntime.appendPUCCHGrantTraceFromFeedback(state, fb);

        t = sixgr.truth.CoupledTruthRuntime.emptyHARQTimelineRow();
        t.Direction = char(direction);
        t.UEIndex = double(ueIdx);
        t.RNTI = double(rnti);
        t.Slot = double(slotIdx);
        t.Frame = double(sixgr.truth.CoupledTruthRuntime.rowValue(row, "Frame", state.CurrentFrame));
        t.HarqID = double(harqId0);
        t.NDI = double(ndi);
        t.RV = double(rv);
        t.IsRetransmission = logical(isRetx);
        t.FeedbackDueSlot = double(feedbackDueSlot);
        t.CurrentDecodeOK = logical(currentDecodeOK);
        t.CombinedDecodeOK = logical(combinedDecodeOK);
        t.PreviousLLRCount = double(sixgr.util.structGet(harqOut, "PreviousLLRCount", NaN));
        t.CurrentLLRCount = double(sixgr.util.structGet(harqOut, "CurrentLLRCount", NaN));
        t.CombinedLLRCount = double(sixgr.util.structGet(harqOut, "CombinedLLRCount", NaN));
        t.HARQCombiningApplied = logical(sixgr.util.structGet(harqOut, "HARQCombiningApplied", false));
        t.LLRCombiningGain_dB = double(sixgr.util.structGet(harqOut, "LLRCombiningGain_dB", NaN));
        t.MeasuredSINR_dB = double(sixgr.truth.CoupledTruthRuntime.rowValue(row, "MeasuredSINR_dB", NaN));
        t.WidebandCQI = double(sixgr.truth.CoupledTruthRuntime.rowValue(row, "WidebandCQI", NaN));
        t.CQIDerivedMCS = double(sixgr.truth.CoupledTruthRuntime.rowValue(row, "CQIDerivedMCS", NaN));
        t.CQIDerivedModulation = char(string(sixgr.truth.CoupledTruthRuntime.rowValue(row, "CQIDerivedModulation", "")));
        t.Goodput_Mbps = double(sixgr.truth.CoupledTruthRuntime.rowValue(row, "Goodput_Mbps", NaN));
        t.Status = char(string(sixgr.truth.CoupledTruthRuntime.rowValue(row, "Status", "")));
        t.Notes = "Canonical slot-runtime HARQ transmission attempt.";
        state.HARQTimelineTable = sixgr.truth.CoupledTruthRuntime.appendCompatTable(state.HARQTimelineTable, struct2table(t, "AsArray", true));
        state.HARQSummaryTable = sixgr.truth.CoupledTruthRuntime.buildHARQSummary(state.HARQTimelineTable);
        state = sixgr.truth.CoupledTruthRuntime.updatePacketDeliveryFromHARQ(state, direction, grantSnapshot, t);

        harqFields = struct("HARQProcess", double(harqId0), "HARQNDI", double(ndi), "HARQRV", double(rv), ...
            "HARQIsRetransmission", logical(isRetx), "HARQFeedbackDueSlot", double(feedbackDueSlot), ...
            "HARQCurrentDecodeOK", logical(currentDecodeOK), "HARQCombinedDecodeOK", logical(combinedDecodeOK), ...
            "HARQCombiningApplied", logical(t.HARQCombiningApplied), "HARQLLRCombiningGain_dB", double(t.LLRCombiningGain_dB), ...
            "HARQPreviousLLRCount", double(t.PreviousLLRCount), "HARQCurrentLLRCount", double(t.CurrentLLRCount), ...
            "HARQCombinedLLRCount", double(t.CombinedLLRCount));
    end

    function T = annotateHARQTrialTable(T, harqFields)
        n = height(T);
        names = fieldnames(harqFields);
        for i = 1:numel(names)
            name = string(names{i});
            value = harqFields.(names{i});
            if ~ismember(name, string(T.Properties.VariableNames))
                if islogical(value)
                    T.(name) = repmat(logical(value), n, 1);
                else
                    T.(name) = repmat(double(value), n, 1);
                end
            else
                if islogical(value)
                    T.(name)(:) = logical(value);
                else
                    T.(name)(:) = double(value);
                end
            end
        end
    end

    function state = appendTelemetry(state, ueIdx, row)
        servingCell = double(state.CurrentServingIdx(ueIdx));
        if ~(isfinite(servingCell) && servingCell >= 1)
            servingCell = 1;
        end
        configuredInterferenceMode = sixgr.truth.CoupledTruthRuntime.resolveInterferenceExecutionMode(state.CfgMobility, state.MultiUser);
        rowDirection = upper(string(sixgr.truth.CoupledTruthRuntime.rowValue(row, "Direction", sixgr.util.structGet(state, "CurrentDirection", "DL"))));
        largeScaleSINR = sixgr.truth.CoupledTruthRuntime.estimateRuntimeWidebandSINR(state, ueIdx, servingCell, configuredInterferenceMode);
        receiverHestSINR = double(sixgr.truth.CoupledTruthRuntime.rowValue(row, "ReceiverHestSINR_dB", NaN));
        receiverHestSource = string(sixgr.truth.CoupledTruthRuntime.rowValue(row, "ReceiverHestSINRSource", ""));
        postEqSINR = double(sixgr.truth.CoupledTruthRuntime.rowValue(row, "PostEqSINR_dB", NaN));
        postEqSource = string(sixgr.truth.CoupledTruthRuntime.rowValue(row, "PostEqSINRSource", ""));
        postEqRole = string(sixgr.truth.CoupledTruthRuntime.rowValue(row, "PostEqSINRValueRole", ""));
        postEqStatus = string(sixgr.truth.CoupledTruthRuntime.rowValue(row, "PostEqSINRValueStatus", ""));
        measuredTrialSINR = double(sixgr.truth.CoupledTruthRuntime.rowValue(row, "MeasuredTrialSINR_dB", NaN));
        measuredTrialSINRSource = string(sixgr.truth.CoupledTruthRuntime.rowValue(row, "MeasuredTrialSINRSource", ""));
        measuredTrialSINRRole = string(sixgr.truth.CoupledTruthRuntime.rowValue(row, "MeasuredTrialSINRValueRole", ""));
        decoderTruthProxySINR = double(sixgr.truth.CoupledTruthRuntime.rowValue(row, "DecoderTruthProxySINR_dB", NaN));
        decoderTruthProxySource = string(sixgr.truth.CoupledTruthRuntime.rowValue(row, "DecoderTruthProxySINRSource", ""));
        if isfinite(receiverHestSINR) && strlength(strtrim(receiverHestSource)) == 0
            receiverHestSource = "receiver_hest_reference_signal_measurement";
        end
        estimatedSINR = NaN;
        widebandSINRSource = "unavailable";
        widebandSINRValueRole = "unavailable";
        if isfinite(measuredTrialSINR) && sixgr.truth.CoupledTruthRuntime.schedulerSINRProvenanceIsEligible(measuredTrialSINRSource, measuredTrialSINRRole, "")
            estimatedSINR = double(measuredTrialSINR);
            if strlength(strtrim(measuredTrialSINRSource)) > 0
                widebandSINRSource = strtrim(measuredTrialSINRSource);
            else
                widebandSINRSource = "post_equalization_sinr_from_equalizer_channel_estimate";
            end
            widebandSINRValueRole = "measured_post_equalization_scheduling_input";
        elseif isfinite(postEqSINR) && sixgr.truth.CoupledTruthRuntime.schedulerSINRProvenanceIsEligible(postEqSource, postEqRole, postEqStatus)
            estimatedSINR = double(postEqSINR);
            if strlength(strtrim(postEqSource)) > 0
                widebandSINRSource = strtrim(postEqSource);
            else
                widebandSINRSource = "post_equalization_sinr_from_equalizer_channel_estimate";
            end
            widebandSINRValueRole = "measured_post_equalization_scheduling_input";
        elseif isfinite(largeScaleSINR)
            estimatedSINR = largeScaleSINR;
            widebandSINRSource = "large_scale_interference_budget_fallback_not_receiver_measured";
            widebandSINRValueRole = "derived_bootstrap_or_missing_receiver_evidence";
        end
        configuredSNR = double(sixgr.truth.CoupledTruthRuntime.rowValue(row, "ConfiguredSNR_dB", state.CurrentSNR_dB));
        appliedLargeScaleGain = double(sixgr.truth.CoupledTruthRuntime.rowValue(row, "AppliedLargeScaleGain_dB", NaN));
        csiRSRP = double(sixgr.truth.CoupledTruthRuntime.rowValue(row, "CSI_RSRP_dB", NaN));
        csiRSRPSource = string(sixgr.truth.CoupledTruthRuntime.rowValue(row, "CSI_RSRPSource", ""));
        interferenceMode = string(sixgr.truth.CoupledTruthRuntime.rowValue(row, "InterferenceMode", configuredInterferenceMode));
        csi = sixgr.truth.CoupledTruthRuntime.resolveMeasuredRuntimeCSIForRow( ...
            row, state.CfgMobility, rowDirection);
        cqi = double(csi.CQI);
        mcs = double(csi.MCSIndex);
        rate = double(csi.TargetCodeRate);
        modStr = string(csi.Modulation);
        r = sixgr.truth.CoupledTruthRuntime.emptyServingRow();
        slotStamp = double(sixgr.truth.CoupledTruthRuntime.rowValue(row, "Slot", state.CurrentSlot));
        r.Slot = double(slotStamp);
        r.Time_s = (double(slotStamp) - 1) * double(state.SlotDuration_s);
        r.UEID = sixgr.truth.CoupledTruthRuntime.resolveUEID(state.UE, ueIdx);
        r.Lat = double(state.CurrentUELat(ueIdx));
        r.Lon = double(state.CurrentUELon(ueIdx));
        r.X_m = double(state.UE.pos_m(ueIdx, 1));
        r.Y_m = double(state.UE.pos_m(ueIdx, 2));
        r.Z_m = double(state.UE.pos_m(ueIdx, 3));
        r.Speed_kmh = sixgr.truth.CoupledTruthRuntime.ueColumn(state.UE, "speed_kmh", ueIdx);
        r.Heading_deg = sixgr.truth.CoupledTruthRuntime.ueColumn(state.UE, "heading_deg", ueIdx);
        r.ServingCell = double(servingCell);
        r.ServingSite = double(state.Layout.bs.siteId(servingCell));
        r.ServingSector = double(state.Layout.bs.sectorId(servingCell));
        r.ServingBeamIndex = double(state.LargeScaleState.BeamIndex(ueIdx, servingCell));
        r.ServingBeamGain_dB = double(state.LargeScaleState.BeamGain_dB(ueIdx, servingCell));
        r.ConfiguredSNR_dB = double(configuredSNR);
        r.ConfiguredSNRSource = "configured_operating_point_metadata";
        r.ServingRSRP_dBm = double(state.CurrentServingMetric_dBm(ueIdx));
        r.RSRP_dBm = double(state.CurrentServingMetric_dBm(ueIdx));
        r.RxPower_dBm = double(state.LargeScaleState.RxPower_dBm(ueIdx, servingCell));
        r.Pathloss_dB = double(state.LargeScaleState.Pathloss_dB(ueIdx, servingCell));
        r.LOSFlag = logical(state.LargeScaleState.LOS(ueIdx, servingCell));
        r.ShadowFading_dB = double(state.LargeScaleState.Shadow_dB(ueIdx, servingCell));
        r.O2I_dB = double(state.LargeScaleState.O2I_dB(ueIdx, servingCell));
        r.ChannelComplianceMode = char(string(sixgr.util.structGet(state.LargeScaleState, "ChannelComplianceMode", "")));
        r.PathlossModelSource = char(string(sixgr.util.structGet(state.LargeScaleState, "PathlossModelSource", "")));
        r.PathlossComplianceStatus = char(string(sixgr.util.structGet(state.LargeScaleState, "PathlossComplianceStatus", "")));
        r.FallbackUsedForPathloss = logical(sixgr.util.structGet(state.LargeScaleState, "FallbackUsedForPathloss", false));
        r.O2IModelSource = char(string(sixgr.util.structGet(state.LargeScaleState, "O2IModelSource", "")));
        r.O2IComplianceStatus = char(string(sixgr.util.structGet(state.LargeScaleState, "O2IComplianceStatus", "")));
        r.O2IComplianceReason = char(string(sixgr.util.structGet(state.LargeScaleState, "O2IComplianceReason", "")));
        r.LOSProbabilitySource = char(string(sixgr.util.structGet(state.LargeScaleState, "LOSProbabilitySource", "")));
        r.LOSComplianceStatus = char(string(sixgr.util.structGet(state.LargeScaleState, "LOSComplianceStatus", "")));
        r.LOSComplianceReason = char(string(sixgr.util.structGet(state.LargeScaleState, "LOSComplianceReason", "")));
        r.ReceiverHestSINR_dB = double(receiverHestSINR);
        r.ReceiverHestSINRSource = char(receiverHestSource);
        r.PostEqSINR_dB = double(postEqSINR);
        r.PostEqSINRSource = char(postEqSource);
        r.PostEqSINRValueRole = char(postEqRole);
        r.PostEqSINRValueStatus = char(postEqStatus);
        r.DecoderTruthProxySINR_dB = double(decoderTruthProxySINR);
        r.DecoderTruthProxySINRSource = char(decoderTruthProxySource);
        r.MeasuredTrialSINR_dB = double(measuredTrialSINR);
        r.EstimatedWidebandSINR_dB = double(estimatedSINR);
        r.ReceiverHestWidebandSINR_dB = double(receiverHestSINR);
        r.PostEqWidebandSINR_dB = double(postEqSINR);
        r.DecoderTruthProxyWidebandSINR_dB = double(decoderTruthProxySINR);
        r.MeasuredWidebandSINR_dB = double(measuredTrialSINR);
        r.LargeScaleWidebandSINR_dB = double(largeScaleSINR);
        r.LargeScaleSINR_dB = double(largeScaleSINR);
        r.CSI_RSRP_dB = double(csiRSRP);
        r.CSI_RSRPSource = char(csiRSRPSource);
        r.AppliedLargeScaleGain_dB = double(appliedLargeScaleGain);
        r.RSRPSource = "large_scale_per_reference_re_power";
        r.ServingRSRPSource = "large_scale_per_reference_re_power";
        r.WidebandSINRSource = char(widebandSINRSource);
        r.WidebandSINRValueRole = char(widebandSINRValueRole);
        r.InterferenceMode = char(interferenceMode);
        r.WidebandCQI = double(cqi);
        r.CQIDerivedMCS = double(mcs);
        r.CQIDerivedModulation = char(modStr);
        r.CQIDerivedTargetCodeRate = double(rate);
        r.CoverageScore = sixgr.truth.CoupledTruthRuntime.coverageScore(r.ServingRSRP_dBm, r.EstimatedWidebandSINR_dB);
        r = sixgr.truth.CoupledTruthRuntime.normalizeStructRowToPrototype(r, sixgr.truth.CoupledTruthRuntime.emptyServingRow());
        state.ServingTraceTable = sixgr.truth.CoupledTruthRuntime.appendCompatTable(state.ServingTraceTable, struct2table(r, "AsArray", true));

        [sortedRSRP, sortIdx] = sort(double(state.LargeScaleState.RSRP_dBm(ueIdx, :)), "descend");
        keepIdx = sortIdx(1:min(double(state.TopCellCount), numel(sortIdx)));
        rows = repmat(sixgr.truth.CoupledTruthRuntime.emptyMeasurementRow(), 0, 1);
        for k = 1:numel(keepIdx)
            c = keepIdx(k);
            m = sixgr.truth.CoupledTruthRuntime.emptyMeasurementRow();
            m.Slot = r.Slot; m.Time_s = r.Time_s; m.UEID = r.UEID; m.CandidateRank = double(k);
            m.CellID = double(c); m.SiteID = double(state.Layout.bs.siteId(c)); m.SectorID = double(state.Layout.bs.sectorId(c));
            m.Lat = r.Lat; m.Lon = r.Lon; m.RSRP_dBm = double(sortedRSRP(k));
            m.RxPower_dBm = double(state.LargeScaleState.RxPower_dBm(ueIdx, c));
            m.Pathloss_dB = double(state.LargeScaleState.Pathloss_dB(ueIdx, c));
            m.BeamIndex = double(state.LargeScaleState.BeamIndex(ueIdx, c));
            m.BeamGain_dB = double(state.LargeScaleState.BeamGain_dB(ueIdx, c));
            m.LOSFlag = logical(state.LargeScaleState.LOS(ueIdx, c));
            m.ShadowFading_dB = double(state.LargeScaleState.Shadow_dB(ueIdx, c));
            m.O2I_dB = double(state.LargeScaleState.O2I_dB(ueIdx, c));
            m.ChannelComplianceMode = char(string(sixgr.util.structGet(state.LargeScaleState, "ChannelComplianceMode", "")));
            m.PathlossModelSource = char(string(sixgr.util.structGet(state.LargeScaleState, "PathlossModelSource", "")));
            m.PathlossComplianceStatus = char(string(sixgr.util.structGet(state.LargeScaleState, "PathlossComplianceStatus", "")));
            m.FallbackUsedForPathloss = logical(sixgr.util.structGet(state.LargeScaleState, "FallbackUsedForPathloss", false));
            m.O2IModelSource = char(string(sixgr.util.structGet(state.LargeScaleState, "O2IModelSource", "")));
            m.O2IComplianceStatus = char(string(sixgr.util.structGet(state.LargeScaleState, "O2IComplianceStatus", "")));
            m.O2IComplianceReason = char(string(sixgr.util.structGet(state.LargeScaleState, "O2IComplianceReason", "")));
            m.LOSProbabilitySource = char(string(sixgr.util.structGet(state.LargeScaleState, "LOSProbabilitySource", "")));
            m.LOSComplianceStatus = char(string(sixgr.util.structGet(state.LargeScaleState, "LOSComplianceStatus", "")));
            m.LOSComplianceReason = char(string(sixgr.util.structGet(state.LargeScaleState, "LOSComplianceReason", "")));
            rows(end+1, 1) = m; %#ok<AGROW>
        end
        if ~isempty(rows)
            state.MeasurementTraceTable = sixgr.truth.CoupledTruthRuntime.appendCompatTable(state.MeasurementTraceTable, struct2table(rows, "AsArray", true));
        end
        prevServing = double(state.PrevServing(ueIdx));
        if prevServing > 0 && prevServing ~= servingCell
            e = sixgr.truth.CoupledTruthRuntime.emptyReselectionRow();
            e.Slot = r.Slot; e.Time_s = r.Time_s; e.UEID = r.UEID;
            e.FromCell = double(prevServing); e.ToCell = double(servingCell);
            e.FromRSRP_dBm = double(state.LargeScaleState.RSRP_dBm(ueIdx, prevServing));
            e.ToRSRP_dBm = double(state.LargeScaleState.RSRP_dBm(ueIdx, servingCell));
            e.Reason = "rsrp_best_cell";
            state.ReselectionEventTable = sixgr.truth.CoupledTruthRuntime.appendCompatTable(state.ReselectionEventTable, struct2table(e, "AsArray", true));
            state.LastPRACHSlotByUE(ueIdx) = 0;
        end
        state.PrevServing(ueIdx) = servingCell;
        state.CoverageSnapshotTable = sixgr.truth.CoupledTruthRuntime.buildCoverageSnapshotTable(state.ServingTraceTable);
    end

    function state = updateUserStats(state, ueIdx, direction, row)
        direction = upper(string(direction));
        if direction == "UL"
            stats = state.ULStats;
        else
            stats = state.DLStats;
        end
        stats(ueIdx).RNTI = double(max(1, round(double(state.MultiUser.RNTIStart + ueIdx - 1))));
        stats(ueIdx).Frames = stats(ueIdx).Frames + 1;
        stats(ueIdx).CRCSum = stats(ueIdx).CRCSum + double(sixgr.truth.CoupledTruthRuntime.rowLogical(row, "CRCPass", false));
        goodBits = double(sixgr.truth.CoupledTruthRuntime.rowValue(row, "GoodBits", NaN));
        if ~(isfinite(goodBits) && goodBits >= 0)
            goodputMbps = double(sixgr.truth.CoupledTruthRuntime.rowValue(row, "Goodput_Mbps", NaN));
            if isfinite(goodputMbps) && isfinite(state.SlotDuration_s) && state.SlotDuration_s > 0
                goodBits = goodputMbps * 1e6 * double(state.SlotDuration_s);
            else
                goodBits = 0;
            end
        end
        stats(ueIdx).GoodBitsSum = stats(ueIdx).GoodBitsSum + double(goodBits);
        sinrVal = double(sixgr.truth.CoupledTruthRuntime.rowValue(row, "MeasuredSINR_dB", NaN));
        if isfinite(sinrVal)
            stats(ueIdx).SINRSum = stats(ueIdx).SINRSum + double(sinrVal);
            stats(ueIdx).SINRCount = stats(ueIdx).SINRCount + 1;
        end
        if direction == "UL"
            state.ULStats = stats;
        else
            state.DLStats = stats;
        end
    end

    function T = buildUserPerformanceTable(state)
        rows = repmat(sixgr.truth.CoupledTruthRuntime.emptyUserPerformanceRow(), 0, 1);
        observedSlots = max(1, round(double(sixgr.util.structGet(state, "CurrentCanonicalSlot", ...
            sixgr.util.structGet(state, "CurrentSlot", 0)))));
        duration_s = max(double(state.SlotDuration_s), eps) * double(observedSlots);
        harqTimelineT = sixgr.util.structGet(state, "HARQTimelineTable", table());
        for ueIdx = 1:double(state.NumUsers)
            dl = state.DLStats(ueIdx);
            ul = state.ULStats(ueIdx);
            r = sixgr.truth.CoupledTruthRuntime.emptyUserPerformanceRow();
            r.UEIndex = double(ueIdx);
            r.RNTI = double(dl.RNTI);
            if ~isfinite(r.RNTI)
                r.RNTI = double(ul.RNTI);
            end
            r.DL_FrameCount = double(dl.Frames);
            r.UL_FrameCount = double(ul.Frames);
            r.DL_CoverageStatus = sixgr.truth.CoupledTruthRuntime.directionExecutionStatus(dl.Frames);
            r.UL_CoverageStatus = sixgr.truth.CoupledTruthRuntime.directionExecutionStatus(ul.Frames);
            r.DL_Throughput_Mbps = sixgr.truth.CoupledTruthRuntime.directionThroughputMbps(dl.GoodBitsSum, duration_s, dl.Frames);
            r.UL_Throughput_Mbps = sixgr.truth.CoupledTruthRuntime.directionThroughputMbps(ul.GoodBitsSum, duration_s, ul.Frames);
            r.DL_BLER = sixgr.truth.CoupledTruthRuntime.directionBLER(dl.CRCSum, dl.Frames);
            r.UL_BLER = sixgr.truth.CoupledTruthRuntime.directionBLER(ul.CRCSum, ul.Frames);
            r.DL_MeanMeasuredSINR_dB = sixgr.truth.CoupledTruthRuntime.safeDivide(dl.SINRSum, dl.SINRCount);
            r.UL_MeanMeasuredSINR_dB = sixgr.truth.CoupledTruthRuntime.safeDivide(ul.SINRSum, ul.SINRCount);
            r.UserThroughput_Mbps = sum([r.DL_Throughput_Mbps r.UL_Throughput_Mbps], "omitnan");
            [r.DL_HARQFailureRate, r.DL_HARQObservationCount] = ...
                sixgr.truth.CoupledTruthRuntime.userHARQFailureMetrics(harqTimelineT, ueIdx, "DL");
            [r.UL_HARQFailureRate, r.UL_HARQObservationCount] = ...
                sixgr.truth.CoupledTruthRuntime.userHARQFailureMetrics(harqTimelineT, ueIdx, "UL");
            [r.HARQFailureRate, r.HARQObservationCount] = ...
                sixgr.truth.CoupledTruthRuntime.combineDirectionalHARQFailureMetrics( ...
                    r.DL_HARQFailureRate, r.DL_HARQObservationCount, ...
                    r.UL_HARQFailureRate, r.UL_HARQObservationCount);
            rows(end+1, 1) = r; %#ok<AGROW>
        end
        T = struct2table(rows, "AsArray", true);
    end

    function T = buildCoverageLayerTable(state)
        coverageT = sixgr.util.structGet(state, "CoverageSnapshotTable", table());
        userPerfT = sixgr.util.structGet(state, "UserPerformanceTable", table());
        if ~(istable(coverageT) && ~isempty(coverageT))
            T = struct2table(repmat(sixgr.truth.CoupledTruthRuntime.emptyCoverageLayerRow(), 0, 1));
            return;
        end
        T = coverageT;
        T.UserThroughput_Mbps = nan(height(T), 1);
        T.HARQFailureRate = nan(height(T), 1);
        T.CellThroughput_Mbps = nan(height(T), 1);
        for i = 1:height(T)
            ueIdx = double(T.UEID(i));
            mask = abs(double(userPerfT.UEIndex) - ueIdx) < 1e-9;
            if any(mask)
                idx = find(mask, 1, "last");
                T.UserThroughput_Mbps(i) = double(userPerfT.UserThroughput_Mbps(idx));
                T.HARQFailureRate(i) = double(userPerfT.HARQFailureRate(idx));
            end
        end
        cellList = unique(double(T.ServingCell), "stable");
        for i = 1:numel(cellList)
            mask = abs(double(T.ServingCell) - cellList(i)) < 1e-9;
            T.CellThroughput_Mbps(mask) = sum(double(T.UserThroughput_Mbps(mask)), "omitnan");
        end
    end

    function T = buildCoverageSnapshotTable(servingT)
        if ~(istable(servingT) && ~isempty(servingT))
            T = struct2table(repmat(sixgr.truth.CoupledTruthRuntime.emptyCoverageRow(), 0, 1));
            return;
        end
        ueList = unique(double(servingT.UEID), "stable");
        rows = repmat(sixgr.truth.CoupledTruthRuntime.emptyCoverageRow(), 0, 1);
        for i = 1:numel(ueList)
            mask = abs(double(servingT.UEID) - ueList(i)) < 1e-9;
            lastIdx = find(mask, 1, "last");
            r = sixgr.truth.CoupledTruthRuntime.emptyCoverageRow();
            r.UEID = double(servingT.UEID(lastIdx)); r.Slot = double(servingT.Slot(lastIdx)); r.Time_s = double(servingT.Time_s(lastIdx));
            r.Lat = double(servingT.Lat(lastIdx)); r.Lon = double(servingT.Lon(lastIdx));
            r.ServingCell = double(servingT.ServingCell(lastIdx)); r.ServingSite = double(servingT.ServingSite(lastIdx)); r.ServingSector = double(servingT.ServingSector(lastIdx));
            if ismember("ConfiguredSNR_dB", string(servingT.Properties.VariableNames))
                r.ConfiguredSNR_dB = double(servingT.ConfiguredSNR_dB(lastIdx));
            end
            if ismember("ConfiguredSNRSource", string(servingT.Properties.VariableNames))
                r.ConfiguredSNRSource = string(servingT.ConfiguredSNRSource(lastIdx));
            else
                r.ConfiguredSNRSource = "configured_operating_point_metadata";
            end
            if ismember("ServingRSRP_dBm", string(servingT.Properties.VariableNames))
                r.ServingRSRP_dBm = double(servingT.ServingRSRP_dBm(lastIdx));
            end
            r.RSRP_dBm = double(servingT.RSRP_dBm(lastIdx));
            if ~isfinite(r.ServingRSRP_dBm)
                r.ServingRSRP_dBm = r.RSRP_dBm;
            end
            if ismember("ReceiverHestSINR_dB", string(servingT.Properties.VariableNames))
                r.ReceiverHestSINR_dB = double(servingT.ReceiverHestSINR_dB(lastIdx));
            end
            if ismember("ReceiverHestSINRSource", string(servingT.Properties.VariableNames))
                r.ReceiverHestSINRSource = string(servingT.ReceiverHestSINRSource(lastIdx));
            end
            if ismember("DecoderTruthProxySINR_dB", string(servingT.Properties.VariableNames))
                r.DecoderTruthProxySINR_dB = double(servingT.DecoderTruthProxySINR_dB(lastIdx));
            end
            if ismember("DecoderTruthProxySINRSource", string(servingT.Properties.VariableNames))
                r.DecoderTruthProxySINRSource = string(servingT.DecoderTruthProxySINRSource(lastIdx));
            end
            if ismember("MeasuredTrialSINR_dB", string(servingT.Properties.VariableNames))
                r.MeasuredTrialSINR_dB = double(servingT.MeasuredTrialSINR_dB(lastIdx));
            else
                r.MeasuredTrialSINR_dB = NaN;
            end
            if ismember("PostEqSINR_dB", string(servingT.Properties.VariableNames))
                r.PostEqSINR_dB = double(servingT.PostEqSINR_dB(lastIdx));
            end
            if ismember("PostEqSINRSource", string(servingT.Properties.VariableNames))
                r.PostEqSINRSource = string(servingT.PostEqSINRSource(lastIdx));
            end
            if ismember("PostEqSINRValueRole", string(servingT.Properties.VariableNames))
                r.PostEqSINRValueRole = string(servingT.PostEqSINRValueRole(lastIdx));
            end
            if ismember("PostEqSINRValueStatus", string(servingT.Properties.VariableNames))
                r.PostEqSINRValueStatus = string(servingT.PostEqSINRValueStatus(lastIdx));
            end
            r.EstimatedWidebandSINR_dB = double(servingT.EstimatedWidebandSINR_dB(lastIdx));
            if ismember("ReceiverHestWidebandSINR_dB", string(servingT.Properties.VariableNames))
                r.ReceiverHestWidebandSINR_dB = double(servingT.ReceiverHestWidebandSINR_dB(lastIdx));
            else
                r.ReceiverHestWidebandSINR_dB = double(r.ReceiverHestSINR_dB);
            end
            if ismember("PostEqWidebandSINR_dB", string(servingT.Properties.VariableNames))
                r.PostEqWidebandSINR_dB = double(servingT.PostEqWidebandSINR_dB(lastIdx));
            else
                r.PostEqWidebandSINR_dB = double(r.PostEqSINR_dB);
            end
            if ismember("DecoderTruthProxyWidebandSINR_dB", string(servingT.Properties.VariableNames))
                r.DecoderTruthProxyWidebandSINR_dB = double(servingT.DecoderTruthProxyWidebandSINR_dB(lastIdx));
            else
                r.DecoderTruthProxyWidebandSINR_dB = double(r.DecoderTruthProxySINR_dB);
            end
            if ismember("MeasuredWidebandSINR_dB", string(servingT.Properties.VariableNames))
                r.MeasuredWidebandSINR_dB = double(servingT.MeasuredWidebandSINR_dB(lastIdx));
            elseif isfinite(double(r.MeasuredTrialSINR_dB))
                r.MeasuredWidebandSINR_dB = double(r.MeasuredTrialSINR_dB);
            else
                r.MeasuredWidebandSINR_dB = NaN;
            end
            if ismember("LargeScaleWidebandSINR_dB", string(servingT.Properties.VariableNames))
                r.LargeScaleWidebandSINR_dB = double(servingT.LargeScaleWidebandSINR_dB(lastIdx));
            else
                r.LargeScaleWidebandSINR_dB = NaN;
            end
            if ismember("LargeScaleSINR_dB", string(servingT.Properties.VariableNames))
                r.LargeScaleSINR_dB = double(servingT.LargeScaleSINR_dB(lastIdx));
            else
                r.LargeScaleSINR_dB = r.LargeScaleWidebandSINR_dB;
            end
            if ismember("CSI_RSRP_dB", string(servingT.Properties.VariableNames))
                r.CSI_RSRP_dB = double(servingT.CSI_RSRP_dB(lastIdx));
            end
            if ismember("CSI_RSRPSource", string(servingT.Properties.VariableNames))
                r.CSI_RSRPSource = string(servingT.CSI_RSRPSource(lastIdx));
            end
            if ismember("AppliedLargeScaleGain_dB", string(servingT.Properties.VariableNames))
                r.AppliedLargeScaleGain_dB = double(servingT.AppliedLargeScaleGain_dB(lastIdx));
            end
            if ismember("ServingRSRPSource", string(servingT.Properties.VariableNames))
                r.ServingRSRPSource = string(servingT.ServingRSRPSource(lastIdx));
            else
                r.ServingRSRPSource = "large_scale_per_reference_re_power";
            end
            if ismember("RSRPSource", string(servingT.Properties.VariableNames))
                r.RSRPSource = string(servingT.RSRPSource(lastIdx));
            else
                r.RSRPSource = "large_scale_per_reference_re_power";
            end
            if ismember("WidebandSINRSource", string(servingT.Properties.VariableNames))
                r.WidebandSINRSource = string(servingT.WidebandSINRSource(lastIdx));
            elseif isfinite(double(r.PostEqWidebandSINR_dB)) || isfinite(double(r.MeasuredWidebandSINR_dB))
                r.WidebandSINRSource = "post_equalization_sinr_from_equalizer_channel_estimate";
            elseif isfinite(double(r.LargeScaleWidebandSINR_dB))
                r.WidebandSINRSource = "large_scale_interference_budget_preview";
            elseif isfinite(double(r.ReceiverHestWidebandSINR_dB))
                r.WidebandSINRSource = "receiver_hest_diagnostic_not_scheduling_input";
            else
                r.WidebandSINRSource = "unavailable";
            end
            if ismember("WidebandSINRValueRole", string(servingT.Properties.VariableNames))
                r.WidebandSINRValueRole = string(servingT.WidebandSINRValueRole(lastIdx));
            elseif isfinite(double(r.PostEqWidebandSINR_dB)) || isfinite(double(r.MeasuredWidebandSINR_dB))
                r.WidebandSINRValueRole = "measured_post_equalization_scheduling_input";
            elseif isfinite(double(r.LargeScaleWidebandSINR_dB))
                r.WidebandSINRValueRole = "derived_preview";
            elseif isfinite(double(r.ReceiverHestWidebandSINR_dB))
                r.WidebandSINRValueRole = "diagnostic_estimate_not_scheduling_input";
            end
            if ismember("InterferenceMode", string(servingT.Properties.VariableNames))
                r.InterferenceMode = string(servingT.InterferenceMode(lastIdx));
            else
                r.InterferenceMode = string(sixgr.truth.CoupledTruthRuntime.resolveInterferenceExecutionMode(state.CfgLargeScale, state.MultiUser));
            end
            r.WidebandCQI = double(servingT.WidebandCQI(lastIdx)); r.CQIDerivedMCS = double(servingT.CQIDerivedMCS(lastIdx));
            r.CQIDerivedModulation = string(servingT.CQIDerivedModulation(lastIdx)); r.CQIDerivedTargetCodeRate = double(servingT.CQIDerivedTargetCodeRate(lastIdx));
            r.Pathloss_dB = double(servingT.Pathloss_dB(lastIdx)); r.CoverageScore = double(servingT.CoverageScore(lastIdx));
            rows(end+1, 1) = r; %#ok<AGROW>
        end
        T = struct2table(rows, "AsArray", true);
    end

    function summaryT = buildHARQSummary(timelineT)
        if ~(istable(timelineT) && ~isempty(timelineT))
            summaryT = struct2table(repmat(sixgr.truth.CoupledTruthRuntime.emptyHARQSummaryRow(), 0, 1));
            return;
        end
        rows = repmat(sixgr.truth.CoupledTruthRuntime.emptyHARQSummaryRow(), 0, 1);
        dirs = unique(string(timelineT.Direction), "stable");
        for i = 1:numel(dirs)
            mask = string(timelineT.Direction) == dirs(i);
            slice = timelineT(mask, :);
            r = sixgr.truth.CoupledTruthRuntime.emptyHARQSummaryRow();
            r.Direction = char(dirs(i));
            r.FramesObserved = double(height(slice));
            r.RetxObserved = double(sum(logical(slice.IsRetransmission), "omitnan"));
            r.AckRate = mean(double(slice.CombinedDecodeOK), "omitnan");
            r.NackRate = mean(1 - double(slice.CombinedDecodeOK), "omitnan");
            r.MeanMeasuredSINR_dB = mean(double(slice.MeasuredSINR_dB), "omitnan");
            r.MeanWidebandCQI = mean(double(slice.WidebandCQI), "omitnan");
            r.MeanCQIDerivedMCS = mean(double(slice.CQIDerivedMCS), "omitnan");
            r.Notes = "Canonical slot-runtime HARQ process summary.";
            rows(end+1, 1) = r; %#ok<AGROW>
        end
        summaryT = struct2table(rows, "AsArray", true);
    end

    function traffic = buildRuntimeTraffic(cfg, nUsers, nFrames, slotDuration_s)
        traffic = sixgr.system.TrafficFactory.generate(cfg, nUsers, nFrames, slotDuration_s);
    end

    function cells = createSchedulers(cfg, nCells, direction, harqEntity)
        nCells = max(1, round(double(nCells)));
        cells = cell(nCells, 1);
        schedulerName = lower(string(sixgr.util.structGet(cfg, "mac.scheduler.type", ...
            sixgr.util.structGet(cfg, "system.scheduler.type", "PF"))));
        for cellId = 1:nCells
            try
                if contains(schedulerName, "pf")
                    cells{cellId} = sixgr.l2.mac.SchedulerPF(cfg, "Direction", upper(char(string(direction))), "HARQ", harqEntity);
                else
                    cells{cellId} = sixgr.l2.mac.SchedulerRR(cfg, "Direction", upper(char(string(direction))), "HARQ", harqEntity);
                end
            catch
                cells{cellId} = sixgr.l2.mac.SchedulerRR(cfg, "Direction", upper(char(string(direction))), "HARQ", harqEntity);
            end
        end
    end

    function slots = resolveCSIFeedbackSlots(cfg)
        minNRProcessingSlots = 4;
        explicitSlots = double(sixgr.util.structGet(cfg, "phy.csi.feedbackDelaySlots", NaN));
        if isfinite(explicitSlots) && explicitSlots >= 0
            slots = max(minNRProcessingSlots, round(explicitSlots));
            return;
        end
        delayModel = lower(string(sixgr.util.structGet(cfg, "phy.linkAdaptation.delayModel", "baseline")));
        switch delayModel
            case {"zero","none","instant","immediate"}
                slots = minNRProcessingSlots;
            otherwise
                slots = minNRProcessingSlots;
        end
    end

    function state = enqueueTrafficForFrame(state, absoluteFrame)
        absoluteFrame = max(1, round(double(absoluteFrame)));
        if double(state.LastTrafficFrameApplied) >= absoluteFrame
            return;
        end
        traffic = sixgr.util.structGet(state, "Traffic", struct());
        rowIdx = min(absoluteFrame, size(double(sixgr.util.structGet(traffic, "OfferedBitsDL", zeros(0, 0))), 1));
        if rowIdx < 1
            state.LastTrafficFrameApplied = absoluteFrame;
            return;
        end
        dlBits = double(sixgr.util.structGet(traffic, "OfferedBitsDL", zeros(rowIdx, state.NumUsers)));
        ulBits = double(sixgr.util.structGet(traffic, "OfferedBitsUL", zeros(rowIdx, state.NumUsers)));
        if size(dlBits, 2) < state.NumUsers
            dlBits(:, end + 1:state.NumUsers) = 0;
        end
        if size(ulBits, 2) < state.NumUsers
            ulBits(:, end + 1:state.NumUsers) = 0;
        end
        dlRow = reshape(dlBits(rowIdx, 1:state.NumUsers), [], 1);
        ulRow = reshape(ulBits(rowIdx, 1:state.NumUsers), [], 1);
        state.DLQueueBits = max(0, double(state.DLQueueBits(:)) + dlRow);
        state.ULQueueBits = max(0, double(state.ULQueueBits(:)) + ulRow);
        state.DLOfferedBits = double(state.DLOfferedBits(:)) + dlRow;
        state.ULOfferedBits = double(state.ULOfferedBits(:)) + ulRow;
        state = sixgr.truth.CoupledTruthRuntime.appendOfferedTrafficPackets(state, "DL", absoluteFrame, dlRow);
        state = sixgr.truth.CoupledTruthRuntime.appendOfferedTrafficPackets(state, "UL", absoluteFrame, ulRow);
        state.LastTrafficFrameApplied = absoluteFrame;
    end

    function scheduler = schedulerForDirection(state, direction, cellId)
        direction = upper(string(direction));
        scheduler = [];
        if direction == "UL"
            schedCell = sixgr.util.structGet(state, "ULSchedulers", {});
        else
            schedCell = sixgr.util.structGet(state, "DLSchedulers", {});
        end
        if iscell(schedCell) && cellId >= 1 && cellId <= numel(schedCell)
            scheduler = schedCell{cellId};
        end
    end

    function [state, ueState] = buildSchedulerUEState(state, cfg, ueIdx, direction, servingCell)
        direction = upper(string(direction));
        state = sixgr.truth.CoupledTruthRuntime.refreshControlStateImpl(state);
        feedback = sixgr.truth.CoupledTruthRuntime.latestFeedbackForDirection(state, ueIdx, direction);
        rnti = double(max(1, round(double(state.MultiUser.RNTIStart + ueIdx - 1))));
        if direction == "UL"
            queueBits = double(state.ULQueueBits(ueIdx));
            harq = state.ULHarq;
            layersCfg = double(sixgr.util.structGet(cfg, "phy.pusch.nLayers", sixgr.util.structGet(cfg, "phy.pusch.numLayers", 1)));
        else
            queueBits = double(state.DLQueueBits(ueIdx));
            harq = state.DLHarq;
            layersCfg = double(sixgr.util.structGet(cfg, "phy.pdsch.nLayers", sixgr.util.structGet(cfg, "phy.pdsch.numLayers", 1)));
        end
        hasRetx = false;
        try
            hasRetx = harq.hasPendingRetx(rnti, sixgr.util.structGet(state, "CurrentSlot", NaN));
        catch
        end
        queueBytes = floor(max(queueBits, 0) / 8);
        if hasRetx
            queueBytes = max(queueBytes, 1);
        end
        cellState = sixgr.truth.CoupledTruthRuntime.controlStateAt(state, "CellAcquisitionState", ueIdx, "unknown");
        accessState = sixgr.truth.CoupledTruthRuntime.controlStateAt(state, "AccessState", ueIdx, "not_attempted");
        srsState = sixgr.truth.CoupledTruthRuntime.controlStateAt(state, "SRSValidityState", ueIdx, "unknown");
        csiState = sixgr.truth.CoupledTruthRuntime.controlStateAt(state, "CSIValidityState", ueIdx, "bootstrap_csi_unavailable");
        controlEligible = sixgr.truth.CoupledTruthRuntime.controlLogicalAt(state, "ControlEligibility", ueIdx, true);
        srsAgeSlots = sixgr.truth.CoupledTruthRuntime.srsAgeSlots(state, ueIdx);
        if direction == "UL" && logical(sixgr.util.structGet(state.ControlGating, "SRSRequired", false)) && ...
                ~(srsState == "valid" && isfinite(srsAgeSlots))
            feedback.Valid = false;
            feedback.CQI = NaN;
            feedback.SINR_dB = NaN;
            feedback.PMI = NaN;
            feedback.CRI = NaN;
            feedback.MCSIndex = NaN;
            feedback.Modulation = "";
            feedback.TargetCodeRate = NaN;
            feedback.RI = 1;
        end
        schedulingEligible = sixgr.truth.CoupledTruthRuntime.resolveSchedulingEligibilityForDirection(state, ueIdx, direction);
        schedulerUsesCQITable = sixgr.truth.CoupledTruthRuntime.schedulerUsesCQITableForDirection(state.CfgMobility, direction);
        feedbackValid = logical(sixgr.util.structGet(feedback, "Valid", false));
        feedbackMCSIndex = double(sixgr.util.structGet(feedback, "MCSIndex", NaN));
        schedulerCQI = double(sixgr.util.structGet(feedback, "CQI", NaN));
        schedulerModulation = char(string(sixgr.util.structGet(feedback, "Modulation", "")));
        schedulerTargetCodeRate = double(sixgr.util.structGet(feedback, "TargetCodeRate", NaN));
        schedulerMCSIndex = double(feedbackMCSIndex);
        schedulerMCSAuthority = "explicit_fixed_override";
        if logical(schedulerUsesCQITable)
            schedulerMCSIndex = NaN;
            if ~feedbackValid
                bootstrapCQIUsable = logical(sixgr.util.structGet(feedback, "BootstrapCQIUsableForScheduling", false));
                if bootstrapCQIUsable && isfinite(schedulerCQI) && schedulerCQI > 0
                    schedulerMCSAuthority = char(string(sixgr.util.structGet(feedback, ...
                        "BootstrapCQISource", "bootstrap_large_scale_interference_preview_cqi")));
                else
                    % Before any usable measured or explicitly enabled
                    % bootstrap CSI exists, stay conservative rather than
                    % inheriting a configured fixed MCS.
                    schedulerCQI = 0;
                    schedulerModulation = "";
                    schedulerTargetCodeRate = NaN;
                    schedulerMCSAuthority = "bootstrap_cqi_conservative_lab_default";
                end
            elseif isfinite(feedbackMCSIndex)
                schedulerMCSAuthority = "feedback_cqi_derived_reference";
            else
                schedulerMCSAuthority = "runtime_cqi_path_without_explicit_mcs_override";
            end
        elseif ~isfinite(schedulerMCSIndex)
            schedulerMCSAuthority = "configured_fixed_default";
        end
        ueState = struct();
        hasTrafficDemand = logical((queueBytes > 0) || hasRetx);
        if hasTrafficDemand && ~logical(schedulingEligible)
            if ueIdx > numel(state.SchedulingOpportunitiesBlockedByGatingCount)
                state.SchedulingOpportunitiesBlockedByGatingCount(ueIdx, 1) = 0;
            end
            state.SchedulingOpportunitiesBlockedByGatingCount(ueIdx) = ...
                double(state.SchedulingOpportunitiesBlockedByGatingCount(ueIdx)) + 1;
        end
        ueState.Active = logical(hasTrafficDemand && schedulingEligible);
        ueState.UEIndex = double(ueIdx);
        ueState.ServingCell = double(servingCell);
        ueState.RNTI = double(rnti);
        ueState.CQI = double(schedulerCQI);
        ueState.RI = max(1, round(double(sixgr.util.structGet(feedback, "RI", layersCfg))));
        ueState.PMI = double(sixgr.util.structGet(feedback, "PMI", NaN));
        ueState.CRI = double(sixgr.util.structGet(feedback, "CRI", NaN));
        ueState.MeasuredSINR_dB = double(sixgr.util.structGet(feedback, "SINR_dB", NaN));
        ueState.CSIAgingModel = char(string(sixgr.util.structGet(feedback, "CSIAgingModel", "")));
        ueState.SubbandSINRVector_dB = char(string(sixgr.util.structGet(feedback, "SubbandSINRVector_dB", "")));
        ueState.AgedSubbandSINRVector_dB = char(string(sixgr.util.structGet(feedback, "AgedSubbandSINRVector_dB", "")));
        ueState.PostEqSINRPerLayer_dB = char(string(sixgr.util.structGet(feedback, "PostEqSINRPerLayer_dB", "")));
        ueState.AgedPostEqSINRPerLayer_dB = char(string(sixgr.util.structGet(feedback, "AgedPostEqSINRPerLayer_dB", "")));
        ueState.PDCCHAggregationLevel = double(sixgr.truth.CoupledTruthRuntime.resolveSchedulerPDCCHAggregationLevel( ...
            state.CfgMobility, ueState.MeasuredSINR_dB));
        ueState.MCSIndex = double(schedulerMCSIndex);
        ueState.FeedbackMCSIndex = double(feedbackMCSIndex);
        ueState.MCSIndexAuthority = char(string(schedulerMCSAuthority));
        ueState.Modulation = char(string(schedulerModulation));
        ueState.TargetCodeRate = double(schedulerTargetCodeRate);
        ueState.FeedbackValid = logical(feedbackValid);
        ueState.BootstrapCQIUsableForScheduling = logical(sixgr.util.structGet(feedback, ...
            "BootstrapCQIUsableForScheduling", false));
        ueState.BootstrapRankUsableForScheduling = logical(sixgr.util.structGet(feedback, ...
            "BootstrapRankUsableForScheduling", false));
        ueState.BootstrapCQISource = char(string(sixgr.util.structGet(feedback, "BootstrapCQISource", "")));
        ueState.PreviewSINR_dB = double(sixgr.util.structGet(feedback, "PreviewSINR_dB", NaN));
        ueState.AdjustedPreviewSINR_dB = double(sixgr.util.structGet(feedback, "AdjustedPreviewSINR_dB", NaN));
        ueState.PreviewCQI = double(sixgr.util.structGet(feedback, "PreviewCQI", NaN));
        ueState.BootstrapMinCQIForScheduling = double(sixgr.util.structGet(feedback, ...
            "BootstrapMinCQIForScheduling", NaN));
        ueState.BootstrapCQIAdmissionStatus = char(string(sixgr.util.structGet(feedback, ...
            "BootstrapCQIAdmissionStatus", "")));
        ueState.BootstrapPreviewBackoff_dB = double(sixgr.util.structGet(feedback, "BootstrapPreviewBackoff_dB", NaN));
        if ~feedbackValid && logical(ueState.BootstrapCQIUsableForScheduling)
            ueState.CausalFeedbackUsable = true;
            ueState.CausalFeedbackStatus = char(string(ueState.BootstrapCQISource));
        else
            ueState.CausalFeedbackUsable = logical(feedbackValid);
            if feedbackValid
                ueState.CausalFeedbackStatus = "measured_runtime_cqi";
            else
                admissionStatus = strtrim(string(ueState.BootstrapCQIAdmissionStatus));
                if admissionStatus == "rejected_below_min_cqi_for_scheduling"
                    ueState.CausalFeedbackStatus = char(admissionStatus);
                else
                    ueState.CausalFeedbackStatus = "bootstrap_cqi_conservative_lab_default";
                end
            end
        end
        if direction == "UL" && sixgr.truth.CoupledTruthRuntime.ulSharedReuseProbeRequired(state, ueIdx)
            probeMCS = sixgr.truth.CoupledTruthRuntime.resolveULSharedReuseProbeMCS(state.CfgMobility);
            probeProfile = sixgr.link.resolveMCSProfile( ...
                sixgr.link.resolveConfiguredMCSTable(state.CfgMobility, "UL"), probeMCS);
            if logical(sixgr.util.structGet(probeProfile, "Valid", false))
                previewCQI = double(sixgr.util.structGet(ueState, "PreviewCQI", NaN));
                if isfinite(previewCQI) && isfinite(double(ueState.CQI))
                    ueState.CQI = min(double(ueState.CQI), previewCQI);
                end
                ueState.RI = 1;
                ueState.NumLayers = 1;
                ueState.MCSIndex = double(probeMCS);
                ueState.MCSIndexAuthority = "ul_shared_reuse_probe_conservative_mcs";
                ueState.Modulation = char(string(probeProfile.Modulation));
                ueState.TargetCodeRate = double(probeProfile.TargetCodeRate);
                ueState.CausalFeedbackUsable = true;
                ueState.CausalFeedbackStatus = "ul_shared_reuse_probe_pending";
            end
        end
        ueState.ControlEligible = logical(controlEligible);
        ueState.SchedulingEligible = logical(schedulingEligible);
        ueState.CellAcquisitionState = char(cellState);
        ueState.AccessState = char(accessState);
        ueState.SRSValidityState = char(srsState);
        ueState.CSIValidityState = char(csiState);
        ueState.SRSValid = srsState == "valid";
        ueState.SRSAgeSlots = double(srsAgeSlots);
        ueState.HeadOfLineDelay_ms = 0;
        if direction == "UL"
            ueState.ULBufferBytes = queueBytes;
        else
            ueState.DLBufferBytes = queueBytes;
        end
    end

    function tf = shouldDeferConservativeBootstrapCell(state, direction, cellId, ueStates)
        tf = false;
        direction = upper(string(direction));
        if direction ~= "DL" && direction ~= "UL"
            return;
        end
        mode = lower(strtrim(string(sixgr.util.structGet(state.CfgMobility, ...
            "run.interferenceExecutionMode", ""))));
        if mode ~= "full_per_link_channel_waveform_sum" && mode ~= "shared_slot_waveform_superposition"
            return;
        end
        nCells = size(sixgr.util.structGet(state, "Layout.bs.pos_m", zeros(0, 3)), 1);
        if nCells <= 1 || ~(isstruct(ueStates) && ~isempty(ueStates))
            return;
        end
        if ~sixgr.truth.CoupledTruthRuntime.slotNeedsConservativeBootstrapReuseGuard(state, direction)
            return;
        end
        allowedCell = sixgr.truth.CoupledTruthRuntime.allowedConservativeBootstrapCell(state, direction);
        tf = isfinite(allowedCell) && round(double(cellId)) ~= round(double(allowedCell));
    end

    function tf = slotNeedsConservativeBootstrapReuseGuard(state, direction)
        tf = false;
        direction = upper(string(direction));
        servingIdx = reshape(double(sixgr.util.structGet(state, "CurrentServingIdx", [])), [], 1);
        if direction == "UL"
            queues = reshape(double(sixgr.util.structGet(state, "ULQueueBits", zeros(numel(servingIdx), 1))), [], 1);
        else
            queues = reshape(double(sixgr.util.structGet(state, "DLQueueBits", zeros(numel(servingIdx), 1))), [], 1);
        end
        n = min(numel(servingIdx), numel(queues));
        for ueIdx = 1:n
            if ~(isfinite(servingIdx(ueIdx)) && servingIdx(ueIdx) >= 1 && queues(ueIdx) > 0)
                continue;
            end
            if sixgr.truth.CoupledTruthRuntime.decodeSuccessCountForUE(state, direction, ueIdx) > 0
                continue;
            end
            if direction == "UL"
                tf = true;
                return;
            end
            feedback = sixgr.truth.CoupledTruthRuntime.latestFeedbackForDirection(state, ueIdx, direction);
            feedbackValid = logical(sixgr.util.structGet(feedback, "Valid", false));
            if ~feedbackValid
                tf = true;
                return;
            end
        end
    end

    function tf = allUEStatesNeedConservativeBootstrapReuseGuard(state, ueStates, direction)
        tf = false;
        if nargin < 3
            direction = "DL";
        end
        direction = upper(string(direction));
        if ~(isstruct(ueStates) && ~isempty(ueStates))
            return;
        end
        anyActive = false;
        for i = 1:numel(ueStates)
            if ~logical(sixgr.util.structGet(ueStates(i), "Active", false))
                continue;
            end
            anyActive = true;
            status = lower(strtrim(string(sixgr.util.structGet(ueStates(i), ...
                "CausalFeedbackStatus", ""))));
            source = lower(strtrim(string(sixgr.util.structGet(ueStates(i), ...
                "MCSIndexAuthority", ""))));
            cqi = double(sixgr.util.structGet(ueStates(i), "CQI", NaN));
            bootstrapUsable = logical(sixgr.util.structGet(ueStates(i), ...
                "BootstrapCQIUsableForScheduling", false));
            if ~(status == "bootstrap_cqi_conservative_lab_default" || ...
                    source == "bootstrap_cqi_conservative_lab_default")
                return;
            end
            if bootstrapUsable || (isfinite(cqi) && cqi > 0)
                return;
            end
            ueIdx = max(1, round(double(sixgr.util.structGet(ueStates(i), "UEIndex", i))));
            successCount = sixgr.truth.CoupledTruthRuntime.decodeSuccessCountForUE(state, direction, ueIdx);
            if successCount > 0
                return;
            end
        end
        tf = anyActive;
    end

    function allowedCell = allowedConservativeBootstrapCell(state, direction)
        if nargin < 2
            direction = "DL";
        end
        direction = upper(string(direction));
        servingIdx = double(sixgr.util.structGet(state, "CurrentServingIdx", []));
        if direction == "UL"
            queues = double(sixgr.util.structGet(state, "ULQueueBits", zeros(numel(servingIdx), 1)));
        else
            queues = double(sixgr.util.structGet(state, "DLQueueBits", zeros(numel(servingIdx), 1)));
        end
        if isempty(servingIdx)
            allowedCell = NaN;
            return;
        end
        servingIdx = reshape(servingIdx, [], 1);
        queues = reshape(queues, [], 1);
        n = min(numel(servingIdx), numel(queues));
        active = servingIdx(1:n) >= 1 & queues(1:n) > 0;
        cells = unique(round(servingIdx(active)), "stable");
        cells = cells(isfinite(cells) & cells >= 1);
        if isempty(cells)
            cells = unique(round(servingIdx(isfinite(servingIdx) & servingIdx >= 1)), "stable");
        end
        if isempty(cells)
            allowedCell = NaN;
            return;
        end
        slotIdx = max(1, round(double(sixgr.util.structGet(state, "CurrentSlot", 1))));
        pos = 1 + mod(slotIdx - 1, numel(cells));
        allowedCell = double(cells(pos));
    end

    function state = recordConservativeBootstrapCellDeferral(state, ueStates)
        if ~(isstruct(ueStates) && ~isempty(ueStates))
            return;
        end
        for i = 1:numel(ueStates)
            ueIdx = max(1, round(double(sixgr.util.structGet(ueStates(i), "UEIndex", i))));
            if ueIdx > numel(state.SchedulingOpportunitiesBlockedByGatingCount)
                state.SchedulingOpportunitiesBlockedByGatingCount(ueIdx, 1) = 0;
            end
            state.SchedulingOpportunitiesBlockedByGatingCount(ueIdx) = ...
                double(state.SchedulingOpportunitiesBlockedByGatingCount(ueIdx)) + 1;
        end
    end

    function count = decodeSuccessCountForUE(state, direction, ueIdx)
        direction = upper(string(direction));
        ueIdx = round(double(ueIdx));
        count = 0;
        if ~(isfinite(ueIdx) && ueIdx >= 1)
            return;
        end
        if direction == "UL"
            vec = double(sixgr.util.structGet(state, "ULDecodeSuccessCountByUE", []));
        else
            vec = double(sixgr.util.structGet(state, "DLDecodeSuccessCountByUE", []));
        end
        if ~isempty(vec) && ueIdx <= numel(vec) && isfinite(vec(ueIdx))
            count = double(vec(ueIdx));
        end
    end

    function count = decodeReuseSuccessCountForUE(state, direction, ueIdx)
        direction = upper(string(direction));
        ueIdx = round(double(ueIdx));
        count = 0;
        if ~(isfinite(ueIdx) && ueIdx >= 1)
            return;
        end
        if direction == "UL"
            vec = double(sixgr.util.structGet(state, "ULDecodeReuseSuccessCountByUE", []));
        else
            vec = double(sixgr.util.structGet(state, "DLDecodeReuseSuccessCountByUE", []));
        end
        if ~isempty(vec) && ueIdx <= numel(vec) && isfinite(vec(ueIdx))
            count = double(vec(ueIdx));
        end
    end

    function tf = ulSharedReuseProbeRequired(state, ueIdx)
        tf = false;
        if ~sixgr.truth.CoupledTruthRuntime.ulSharedReuseProbeEnabled(state.CfgMobility)
            return;
        end
        if sixgr.truth.CoupledTruthRuntime.activeServingCellCountForDirection(state, "UL") <= 1
            return;
        end
        if sixgr.truth.CoupledTruthRuntime.decodeSuccessCountForUE(state, "UL", ueIdx) <= 0
            return;
        end
        tf = sixgr.truth.CoupledTruthRuntime.decodeReuseSuccessCountForUE(state, "UL", ueIdx) <= 0;
    end

    function tf = ulSharedReuseProbeEnabled(cfg)
        mode = lower(strtrim(string(sixgr.util.structGet(cfg, "run.interferenceExecutionMode", ""))));
        fullWaveformMode = mode == "full_per_link_channel_waveform_sum" || mode == "shared_slot_waveform_superposition";
        tf = logical(sixgr.util.structGet(cfg, ...
            "phy.linkAdaptation.ulSharedReuseProbe.enabled", fullWaveformMode));
    end

    function mcs = resolveULSharedReuseProbeMCS(cfg)
        mcs = double(sixgr.util.structGet(cfg, ...
            "phy.linkAdaptation.ulSharedReuseProbe.mcsIndex", ...
            sixgr.util.structGet(cfg, "phy.linkAdaptation.bootstrapMCSIndex", 1)));
        if ~(isfinite(mcs) && mcs >= 0)
            mcs = 1;
        end
        mcs = max(0, min(31, round(mcs)));
    end

    function count = activeServingCellCountForDirection(state, direction)
        direction = upper(string(direction));
        servingIdx = reshape(double(sixgr.util.structGet(state, "CurrentServingIdx", [])), [], 1);
        if direction == "UL"
            queues = reshape(double(sixgr.util.structGet(state, "ULQueueBits", zeros(numel(servingIdx), 1))), [], 1);
        else
            queues = reshape(double(sixgr.util.structGet(state, "DLQueueBits", zeros(numel(servingIdx), 1))), [], 1);
        end
        n = min(numel(servingIdx), numel(queues));
        if n <= 0
            count = 0;
            return;
        end
        active = isfinite(servingIdx(1:n)) & servingIdx(1:n) >= 1 & queues(1:n) > 0;
        cells = unique(round(servingIdx(active)), "stable");
        cells = cells(isfinite(cells) & cells >= 1);
        count = double(numel(cells));
    end

    function state = updateDecodeSuccessCount(state, ueIdx, direction, row)
        direction = upper(string(direction));
        ueIdx = round(double(ueIdx));
        if ~(isfinite(ueIdx) && ueIdx >= 1)
            return;
        end
        crcOk = logical(sixgr.truth.CoupledTruthRuntime.rowLogical(row, "CRCPass", false));
        if ~crcOk
            return;
        end
        if direction == "UL"
            if ~isfield(state, "ULDecodeSuccessCountByUE") || numel(state.ULDecodeSuccessCountByUE) < ueIdx
                state.ULDecodeSuccessCountByUE(ueIdx, 1) = 0;
            end
            state.ULDecodeSuccessCountByUE(ueIdx) = double(state.ULDecodeSuccessCountByUE(ueIdx)) + 1;
            if double(sixgr.truth.CoupledTruthRuntime.rowValue(row, "InterferenceContributorCount", 0)) > 0
                if ~isfield(state, "ULDecodeReuseSuccessCountByUE") || numel(state.ULDecodeReuseSuccessCountByUE) < ueIdx
                    state.ULDecodeReuseSuccessCountByUE(ueIdx, 1) = 0;
                end
                state.ULDecodeReuseSuccessCountByUE(ueIdx) = double(state.ULDecodeReuseSuccessCountByUE(ueIdx)) + 1;
            end
        else
            if ~isfield(state, "DLDecodeSuccessCountByUE") || numel(state.DLDecodeSuccessCountByUE) < ueIdx
                state.DLDecodeSuccessCountByUE(ueIdx, 1) = 0;
            end
            state.DLDecodeSuccessCountByUE(ueIdx) = double(state.DLDecodeSuccessCountByUE(ueIdx)) + 1;
            if double(sixgr.truth.CoupledTruthRuntime.rowValue(row, "InterferenceContributorCount", 0)) > 0
                if ~isfield(state, "DLDecodeReuseSuccessCountByUE") || numel(state.DLDecodeReuseSuccessCountByUE) < ueIdx
                    state.DLDecodeReuseSuccessCountByUE(ueIdx, 1) = 0;
                end
                state.DLDecodeReuseSuccessCountByUE(ueIdx) = double(state.DLDecodeReuseSuccessCountByUE(ueIdx)) + 1;
            end
        end
    end

    function tf = resolveSchedulingEligibilityForDirection(state, ueIdx, direction)
        sharedSchedulingEligible = sixgr.truth.CoupledTruthRuntime.controlLogicalAt(state, "SchedulingEligibility", ueIdx, true);
        tf = logical(sharedSchedulingEligible);
    end

    function [currentDirection, dlEligibility, ulEligibility, currentEligibility] = resolveSchedulingEligibilityViews(state)
        nUsers = double(sixgr.util.structGet(state, "NumUsers", 0));
        dlEligibility = false(max(0, nUsers), 1);
        ulEligibility = false(max(0, nUsers), 1);
        for ueIdx = 1:nUsers
            dlEligibility(ueIdx) = logical(sixgr.truth.CoupledTruthRuntime.resolveSchedulingEligibilityForDirection(state, ueIdx, "DL"));
            ulEligibility(ueIdx) = logical(sixgr.truth.CoupledTruthRuntime.resolveSchedulingEligibilityForDirection(state, ueIdx, "UL"));
        end
        currentDirection = upper(string(sixgr.util.structGet(state, "CurrentDirection", "")));
        if currentDirection ~= "DL" && currentDirection ~= "UL"
            slotDLAllowed = logical(sixgr.util.structGet(state, "CurrentSlotDLAllowed", true));
            slotULAllowed = logical(sixgr.util.structGet(state, "CurrentSlotULAllowed", true));
            if slotDLAllowed && ~slotULAllowed
                currentDirection = "DL";
            elseif slotULAllowed && ~slotDLAllowed
                currentDirection = "UL";
            else
                currentDirection = "DL";
            end
        end
        if currentDirection == "UL"
            currentEligibility = ulEligibility;
        else
            currentEligibility = dlEligibility;
        end
    end

    function tf = schedulerUsesCQITableForDirection(cfg, direction)
        direction = upper(string(direction));
        mode = lower(strtrim(string(sixgr.util.structGet(cfg, "phy.linkAdaptation.mode", "fixed"))));
        if direction == "UL"
            policy = lower(strtrim(string(sixgr.util.structGet(cfg, "phy.linkAdaptation.ulPolicy", mode))));
        else
            policy = lower(strtrim(string(sixgr.util.structGet(cfg, "phy.linkAdaptation.dlPolicy", mode))));
        end
        fixedTokens = ["fixed","fixed_mcs","configured_fixed","disabled","off","none","false"];
        tf = ~ismember(mode, fixedTokens) && ~ismember(policy, fixedTokens);
    end

    function tf = srsGatingActiveForDirection(state, direction)
        %#ok<INUSD>
        tf = logical(sixgr.util.structGet(state.ControlGating, "SRSRequired", false));
    end

    function state = refreshControlStateImpl(state)
        state = sixgr.truth.CoupledTruthRuntime.refreshSRSFreshnessImpl(state);
        state = sixgr.truth.CoupledTruthRuntime.refreshTRSFreshnessImpl(state);
        nUsers = double(sixgr.util.structGet(state, "NumUsers", 0));
        controlEligibility = true(max(0, nUsers), 1);
        schedulingEligibility = true(max(0, nUsers), 1);
        coverageEligibility = true(max(0, nUsers), 1);
        coverageOutageState = repmat("not_evaluated", max(0, nUsers), 1);
        servingVec = double(sixgr.util.structGet(state, "CurrentServingIdx", nan(nUsers, 1)));
        srsRequired = logical(sixgr.util.structGet(state.ControlGating, "SRSRequired", false));
        coverageGuardEnabled = logical(sixgr.util.structGet(state.CfgMobility, "mac.scheduler.coverageOutageGuardEnabled", ...
            sixgr.util.structGet(state.CfgMobility, "system.scheduler.coverageOutageGuardEnabled", false)));
        minSchedulingSINR_dB = double(sixgr.util.structGet(state.CfgMobility, "mac.scheduler.minSchedulingSINR_dB", ...
            sixgr.util.structGet(state.CfgMobility, "system.scheduler.minSchedulingSINR_dB", -5)));
        for ueIdx = 1:nUsers
            pbchRequired = logical(sixgr.util.structGet(state.ControlGating, "PBCHRequired", false));
            prachRequired = logical(sixgr.util.structGet(state.ControlGating, "PRACHRequired", false));
            trsRequired = logical(sixgr.util.structGet(state.ControlGating, "TRSRequired", false));
            pbchState = sixgr.truth.CoupledTruthRuntime.controlStateAt(state, "CellAcquisitionState", ueIdx, "unknown");
            accessState = sixgr.truth.CoupledTruthRuntime.controlStateAt(state, "AccessState", ueIdx, "not_attempted");
            srsState = sixgr.truth.CoupledTruthRuntime.controlStateAt(state, "SRSValidityState", ueIdx, "invalid");
            eligible = true;
            if pbchRequired
                eligible = eligible && (pbchState == "acquired");
            end
            if prachRequired
                eligible = eligible && (accessState == "succeeded");
            end
            if trsRequired
                servingCell = NaN;
                if ueIdx <= numel(servingVec)
                    servingCell = double(servingVec(ueIdx));
                end
                eligible = eligible && sixgr.truth.CoupledTruthRuntime.trsEligibleForServingCell(state, servingCell);
            end
            if coverageGuardEnabled
                servingCell = NaN;
                if ueIdx <= numel(servingVec)
                    servingCell = double(servingVec(ueIdx));
                end
                rxPowerCells = double(sixgr.util.structGet(state.LargeScaleState, "RxPower_dBm", []));
                sinr_dB = NaN;
                if ueIdx <= size(rxPowerCells, 1)
                    sinr_dB = sixgr.truth.CoupledTruthRuntime.estimateWidebandSINR( ...
                        rxPowerCells(ueIdx, :), servingCell, state.Bandwidth_Hz, state.NoiseFigure_dB);
                end
                coverageEligibility(ueIdx) = isfinite(sinr_dB) && sinr_dB >= minSchedulingSINR_dB;
                if coverageEligibility(ueIdx)
                    coverageOutageState(ueIdx) = "eligible";
                elseif isfinite(sinr_dB)
                    coverageOutageState(ueIdx) = "outage_below_min_sinr";
                else
                    coverageOutageState(ueIdx) = "outage_sinr_unavailable";
                end
            else
                coverageOutageState(ueIdx) = "guard_disabled";
            end
            controlEligibility(ueIdx) = logical(eligible);
            schedulingEligibility(ueIdx) = logical(eligible && coverageEligibility(ueIdx) && (~srsRequired || srsState == "valid"));
        end
        state.ControlEligibility = controlEligibility;
        state.SchedulingEligibility = schedulingEligibility;
        state.CoverageEligibility = coverageEligibility;
        state.CoverageOutageState = coverageOutageState;
    end

    function state = refreshSRSFreshnessImpl(state)
        srsRequired = logical(sixgr.util.structGet(state.ControlGating, "SRSRequired", false));
        maxAgeSlots = max(0, round(double(sixgr.util.structGet(state.ControlGating, "SRSMaxAgeSlots", 0))));
        nUsers = double(sixgr.util.structGet(state, "NumUsers", 0));
        currentSlot = double(sixgr.util.structGet(state, "CurrentSlot", 0));
        for ueIdx = 1:nUsers
            lastSuccess = sixgr.truth.CoupledTruthRuntime.numericStateAt(state, "LastSuccessfulSRSSlotByUE", ueIdx, NaN);
            prevState = sixgr.truth.CoupledTruthRuntime.controlStateAt(state, "SRSValidityState", ueIdx, "invalid");
            if isfinite(lastSuccess) && isfinite(currentSlot) && (currentSlot - lastSuccess) <= maxAgeSlots
                state.SRSValidityState(ueIdx) = "valid";
                state.CSIValidityState(ueIdx) = "fresh_srs";
            else
                if isfinite(lastSuccess)
                    nextState = "stale";
                    nextCSI = "stale_srs_not_usable";
                elseif srsRequired
                    nextState = "invalid";
                    nextCSI = "no_successful_srs";
                else
                    nextState = "not_required";
                    nextCSI = "not_required";
                end
                state.SRSValidityState(ueIdx) = nextState;
                state.CSIValidityState(ueIdx) = nextCSI;
                if srsRequired && prevState ~= nextState
                    state.SRSInvalidEventCount(ueIdx) = double(state.SRSInvalidEventCount(ueIdx)) + 1;
                end
            end
        end
    end

    function state = refreshTRSFreshnessImpl(state)
        state = sixgr.truth.CoupledTruthRuntime.ensureReceiverTrackingStateImpl(state);
        if ~logical(sixgr.util.structGet(state.ControlGating, "TRSRequired", false))
            return;
        end
        maxAgeSlots = max(0, round(double(sixgr.util.structGet(state.ControlGating, "TRSMaxAgeSlots", 0))));
        nCells = numel(sixgr.util.structGet(state, "TRSValidityStateByCell", strings(0, 1)));
        currentSlot = double(sixgr.util.structGet(state, "CurrentSlot", 0));
        for cellIdx = 1:nCells
            lastSuccess = sixgr.truth.CoupledTruthRuntime.numericServingStateAt(state, "LastSuccessfulTRSSlotByCell", cellIdx, NaN);
            lastObserved = sixgr.truth.CoupledTruthRuntime.numericServingStateAt(state, "LastTRSObservedSlotByCell", cellIdx, NaN);
            if isfinite(lastSuccess) && isfinite(currentSlot) && (currentSlot - lastSuccess) <= maxAgeSlots
                state.TRSValidityStateByCell(cellIdx) = "valid";
                state.TrackingEligibilityByCell(cellIdx) = true;
                state = sixgr.truth.CoupledTruthRuntime.updateReceiverTrackingFreshnessImpl(state, cellIdx, "valid");
            else
                if isfinite(lastSuccess)
                    nextState = "stale";
                elseif isfinite(lastObserved)
                    nextState = "failed";
                else
                    nextState = "invalid";
                end
                state.TRSValidityStateByCell(cellIdx) = nextState;
                state.TrackingEligibilityByCell(cellIdx) = false;
                state = sixgr.truth.CoupledTruthRuntime.updateReceiverTrackingFreshnessImpl(state, cellIdx, nextState);
            end
        end
    end

    function state = applyPBCHTrialImpl(state, ueIdx, trialT)
        if ~(isfinite(double(ueIdx)) && ueIdx >= 1 && ueIdx <= double(state.NumUsers))
            return;
        end
        oldCellState = string(sixgr.truth.CoupledTruthRuntime.controlStateAt(state, "CellAcquisitionState", ueIdx, "not_attempted"));
        oldAccessState = string(sixgr.truth.CoupledTruthRuntime.controlStateAt(state, "AccessState", ueIdx, "not_attempted"));
        ok = sixgr.truth.CoupledTruthRuntime.trialPassed(trialT);
        slotIdx = double(sixgr.truth.CoupledTruthRuntime.rowValue(trialT(end, :), "Slot", state.CurrentSlot));
        servingCell = double(sixgr.truth.CoupledTruthRuntime.numericStateAt(state, "CurrentServingIdx", ueIdx, NaN));
        if ok
            state.CellAcquisitionState(ueIdx) = "acquired";
            state.LastSuccessfulPBCHSlotByUE(ueIdx) = double(slotIdx);
            state = sixgr.truth.CoupledTruthRuntime.recordInitialAccessEvent(state, ueIdx, "SSB_DETECTED", "DL", ...
                "control/csv/pbch_trials.csv", "PBCH", slotIdx, ...
                "slot_coupled_pbch_cell_search_observation", "SSB detection observed in the coupled PBCH/cell-search runtime gate.");
            state = sixgr.truth.CoupledTruthRuntime.recordInitialAccessEvent(state, ueIdx, "PBCH_DECODED", "DL", ...
                "control/csv/pbch_trials.csv", "PBCH", slotIdx, ...
                "slot_coupled_pbch_decode_observation", "PBCH decode observed in the coupled PBCH/cell-search runtime gate.");
        else
            state.CellAcquisitionState(ueIdx) = "failed";
            state.PBCHFailureCount(ueIdx) = double(state.PBCHFailureCount(ueIdx)) + 1;
        end
        newCellState = string(sixgr.truth.CoupledTruthRuntime.controlStateAt(state, "CellAcquisitionState", ueIdx, "not_attempted"));
        state = sixgr.monitor.AccessFlowRecorder.recordEvent(state, ...
            "UEIndex", double(ueIdx), ...
            "CellID", servingCell, ...
            "OldState", oldCellState, ...
            "NewState", sixgr.truth.CoupledTruthRuntime.ternaryString(ok, "PBCH_DECODED", "PBCH_FAILED"), ...
            "TransitionReason", sixgr.truth.CoupledTruthRuntime.ternaryString(ok, "pbch_crc_pass", "pbch_decode_failed"), ...
            "SourceFunction", "sixgr.truth.CoupledTruthRuntime.applyPBCHTrialImpl", ...
            "SourceFile", "+sixgr/+truth/CoupledTruthRuntime.m", ...
            "Procedure", "INITIAL_ACCESS", ...
            "PhysicalChannel", "PBCH", ...
            "RequiredPrecondition", "ssb_pbch_occasion", ...
            "PreconditionValue", "attempted", ...
            "RNTI", sixgr.truth.CoupledTruthRuntime.rowFirstFinite(trialT(end, :), ["RNTI"], NaN), ...
            "SSBIndex", sixgr.truth.CoupledTruthRuntime.rowFirstFinite(trialT(end, :), ["SSBIndex","BeamIndex"], NaN), ...
            "AccessSuccess", false, ...
            "FailureReason", sixgr.truth.CoupledTruthRuntime.ternaryString(ok, "", "pbch_decode_failed"), ...
            "OldStateOriginal", oldAccessState, ...
            "NewStateOriginal", newCellState);
        state = sixgr.truth.CoupledTruthRuntime.refreshControlStateImpl(state);
    end

    function state = applyPRACHTrialImpl(state, ueIdx, trialT)
        if ~(isfinite(double(ueIdx)) && ueIdx >= 1 && ueIdx <= double(state.NumUsers))
            return;
        end
        if ~(istable(trialT) && ~isempty(trialT))
            return;
        end
        row = trialT(end, :);
        oldAccessState = string(sixgr.truth.CoupledTruthRuntime.controlStateAt(state, "AccessState", ueIdx, "not_attempted"));
        servingCell = double(sixgr.truth.CoupledTruthRuntime.numericStateAt(state, "CurrentServingIdx", ueIdx, NaN));
        status = upper(strtrim(string(sixgr.truth.CoupledTruthRuntime.rowValue(row, "Status", ""))));
        if status == "NA" || status == "SKIP" || logical(sixgr.truth.CoupledTruthRuntime.rowValue(row, "Skipped", false))
            state = sixgr.monitor.AccessFlowRecorder.recordEvent(state, ...
                "UEIndex", double(ueIdx), ...
                "CellID", servingCell, ...
                "OldState", oldAccessState, ...
                "NewState", "PRACH_SKIPPED", ...
                "TransitionReason", "prach_trial_skipped", ...
                "SourceFunction", "sixgr.truth.CoupledTruthRuntime.applyPRACHTrialImpl", ...
                "SourceFile", "+sixgr/+truth/CoupledTruthRuntime.m", ...
                "Procedure", "RACH_MSG1", ...
                "PhysicalChannel", "PRACH", ...
                "RequiredPrecondition", "pbch_acquired_and_prach_occasion", ...
                "PreconditionValue", "not_satisfied_or_skipped", ...
                "PRACHOccasionID", sixgr.truth.CoupledTruthRuntime.rowFirstFinite(row, ["PRACHOccasionIndex","PRACHCarrierSlot"], NaN), ...
                "PRACHPreambleIndex", sixgr.truth.CoupledTruthRuntime.rowFirstFinite(row, ["RequestedPreambleIndex","PreambleIndex"], NaN), ...
                "PRACHRootSequence", sixgr.truth.CoupledTruthRuntime.rowFirstFinite(row, ["PRACHRootSequenceIndex","RootSequenceIndex"], NaN), ...
                "PRACHFormat", string(sixgr.truth.CoupledTruthRuntime.rowValue(row, "PRACHFormat", "")), ...
                "FailureReason", string(sixgr.truth.CoupledTruthRuntime.rowValue(row, "Notes", "prach_skipped")), ...
                "OldStateOriginal", oldAccessState, ...
                "NewStateOriginal", oldAccessState);
            state = sixgr.truth.CoupledTruthRuntime.refreshControlStateImpl(state);
            return;
        end
        ok = sixgr.truth.CoupledTruthRuntime.trialPassed(trialT);
        slotIdx = double(sixgr.truth.CoupledTruthRuntime.rowValue(row, "Slot", state.CurrentSlot));
        if ok
            state.AccessState(ueIdx) = "succeeded";
            state.LastSuccessfulPRACHSlotByUE(ueIdx) = double(slotIdx);
            taSamples = sixgr.truth.CoupledTruthRuntime.rowFirstFinite(row, ...
                ["TimingAdvance_samples","TimingOffset_samples","TimingOffsetSamplesApplied","TimingOffsetSamplesRaw"], NaN);
            taUs = sixgr.truth.CoupledTruthRuntime.rowFirstFinite(row, ["TimingAdvance_us"], NaN);
            if isfinite(taSamples)
                state = sixgr.truth.CoupledTruthRuntime.updateTimingAdvanceMeasurementImpl( ...
                    state, ueIdx, taSamples, taUs, "prach_receiver_measurement", slotIdx, "time_aligned_from_prach");
            else
                state.TimeAlignmentState(ueIdx) = "access_succeeded_ta_unavailable";
                state.TimingAdvanceUpdateStatusByUE(ueIdx) = "prach_access_succeeded_ta_unavailable";
            end
            fullRA = logical(sixgr.truth.CoupledTruthRuntime.rowValue(row, "RACompleted", false)) || ...
                strlength(strtrim(string(sixgr.truth.CoupledTruthRuntime.rowValue(row, "FullRAEvidenceSource", "")))) > 0;
            eventSource = "slot_coupled_prach_detection_observation";
            eventNote = "Msg1 PRACH detection observed in the coupled PRACH runtime gate.";
            if fullRA
                eventSource = "slot_coupled_four_step_ra_waveform_chain";
                eventNote = "Four-step RA completed through Msg1 PRACH, Msg2 RAR, Msg3 PUSCH, and Msg4 contention-resolution waveform evidence.";
            end
            state = sixgr.truth.CoupledTruthRuntime.recordInitialAccessEvent(state, ueIdx, "PRACH_MSG1_DETECTED", "UL", ...
                "control/csv/prach_trials.csv", "PRACH", slotIdx, ...
                eventSource, eventNote);
            if fullRA
                state = sixgr.truth.CoupledTruthRuntime.recordInitialAccessEvent(state, ueIdx, "MSG2_RAR_DECODED", "DL", ...
                    "control/csv/msg2_rar_trials.csv", "RAR", slotIdx, ...
                    eventSource, "Msg2 RAR PDCCH/PDSCH decode observed inside the four-step RA chain.");
                state = sixgr.truth.CoupledTruthRuntime.recordInitialAccessEvent(state, ueIdx, "MSG3_PUSCH_COMPLETED", "UL", ...
                    "control/csv/msg3_pusch_trials.csv", "PUSCH", slotIdx, ...
                    eventSource, "Msg3 PUSCH decoded from the RAR UL grant inside the four-step RA chain.");
                state = sixgr.truth.CoupledTruthRuntime.recordInitialAccessEvent(state, ueIdx, "MSG4_CONTENTION_RESOLUTION_COMPLETED", "DL", ...
                    "control/csv/msg4_contention_resolution.csv", "PDSCH", slotIdx, ...
                    eventSource, "Msg4 contention-resolution identity matched and final C-RNTI assigned inside the four-step RA chain.");
            end
        else
            state.AccessState(ueIdx) = "failed";
            state.PRACHFailureCount(ueIdx) = double(state.PRACHFailureCount(ueIdx)) + 1;
        end
        newAccessState = string(sixgr.truth.CoupledTruthRuntime.controlStateAt(state, "AccessState", ueIdx, "not_attempted"));
        fullRA = logical(sixgr.truth.CoupledTruthRuntime.rowValue(row, "RACompleted", false));
        msg2Decoded = logical(sixgr.truth.CoupledTruthRuntime.rowValue(row, "Msg2RARNTIDetected", false)) && ...
            logical(sixgr.truth.CoupledTruthRuntime.rowValue(row, "Msg2PDSCHCrcPass", false));
        msg3GrantCreated = logical(sixgr.truth.CoupledTruthRuntime.rowValue(row, "RARULGrantValid", false));
        msg3Crc = logical(sixgr.truth.CoupledTruthRuntime.rowValue(row, "Msg3PUSCHCrcPass", false));
        msg4Decoded = logical(sixgr.truth.CoupledTruthRuntime.rowValue(row, "Msg4PDSCHCrcPass", false));
        contentionOk = logical(sixgr.truth.CoupledTruthRuntime.rowValue(row, "ContentionIdentityMatches", false));
        detected = logical(sixgr.truth.CoupledTruthRuntime.rowValue(row, "DetectionSuccess", false)) || ...
            logical(sixgr.truth.CoupledTruthRuntime.rowValue(row, "Detected", false)) || ok;
        failureReason = string(sixgr.truth.CoupledTruthRuntime.rowValue(row, "FailureReason", ""));
        if strlength(strtrim(failureReason)) == 0 && ~ok
            failureReason = string(sixgr.truth.CoupledTruthRuntime.rowValue(row, "Notes", "prach_detection_failed"));
        end
        state = sixgr.monitor.AccessFlowRecorder.recordEvent(state, ...
            "UEIndex", double(ueIdx), ...
            "CellID", servingCell, ...
            "OldState", oldAccessState, ...
            "NewState", sixgr.truth.CoupledTruthRuntime.ternaryString(ok, "ACCESS_SUCCEEDED", "ACCESS_FAILED"), ...
            "TransitionReason", sixgr.truth.CoupledTruthRuntime.ternaryString(ok, "prach_msg1_detected", "prach_msg1_failed"), ...
            "SourceFunction", "sixgr.truth.CoupledTruthRuntime.applyPRACHTrialImpl", ...
            "SourceFile", "+sixgr/+truth/CoupledTruthRuntime.m", ...
            "Procedure", sixgr.truth.CoupledTruthRuntime.ternaryString(fullRA, "FOUR_STEP_RANDOM_ACCESS", "RACH_MSG1"), ...
            "PhysicalChannel", "PRACH", ...
            "RequiredPrecondition", "pbch_acquired_and_prach_occasion", ...
            "PreconditionValue", "satisfied", ...
            "RNTI", sixgr.truth.CoupledTruthRuntime.rowFirstFinite(row, ["RNTI"], NaN), ...
            "TemporaryCRNTI", sixgr.truth.CoupledTruthRuntime.rowFirstFinite(row, ["TemporaryCRNTI"], NaN), ...
            "PRACHOccasionID", sixgr.truth.CoupledTruthRuntime.rowFirstFinite(row, ["PRACHOccasionIndex","PRACHCarrierSlot"], NaN), ...
            "PRACHPreambleIndex", sixgr.truth.CoupledTruthRuntime.rowFirstFinite(row, ["RequestedPreambleIndex","PreambleIndex","DetectedPreambleIndex"], NaN), ...
            "PRACHRootSequence", sixgr.truth.CoupledTruthRuntime.rowFirstFinite(row, ["PRACHRootSequenceIndex","RootSequenceIndex"], NaN), ...
            "PRACHFormat", string(sixgr.truth.CoupledTruthRuntime.rowValue(row, "PRACHFormat", "")), ...
            "PRACHDetected", detected, ...
            "PRACHDetectionMetric", sixgr.truth.CoupledTruthRuntime.rowFirstFinite(row, ["DetectionMetric","CorrelationPeak"], NaN), ...
            "TimingAdvanceSamples", sixgr.truth.CoupledTruthRuntime.rowFirstFinite(row, ["TimingAdvance_samples","TimingOffset_samples"], NaN), ...
            "RARCreated", msg2Decoded || msg3GrantCreated || fullRA, ...
            "RARDecoded", msg2Decoded, ...
            "Msg3GrantCreated", msg3GrantCreated, ...
            "Msg3TxExecuted", isfinite(sixgr.truth.CoupledTruthRuntime.rowFirstFinite(row, ["Msg3ScheduledSlot"], NaN)), ...
            "Msg3CRCPass", msg3Crc, ...
            "Msg4Created", isfinite(sixgr.truth.CoupledTruthRuntime.rowFirstFinite(row, ["Msg4ScheduledSlot"], NaN)), ...
            "Msg4Decoded", msg4Decoded, ...
            "ContentionResolutionPass", contentionOk, ...
            "AccessSuccess", ok, ...
            "FailureReason", failureReason, ...
            "OldStateOriginal", oldAccessState, ...
            "NewStateOriginal", newAccessState);
        state = sixgr.truth.CoupledTruthRuntime.refreshControlStateImpl(state);
    end

    function result = runFourStepRARuntimeImpl(cfg, varargin)
        p = inputParser;
        p.addParameter("RunFolder", "", @(x)ischar(x) || isstring(x));
        p.addParameter("RunId", "ra_coupled_runtime", @(x)ischar(x) || isstring(x));
        p.addParameter("ScenarioName", "", @(x)ischar(x) || isstring(x));
        p.addParameter("UEId", 1, @(x)isnumeric(x) && isscalar(x));
        p.addParameter("CellId", [], @(x)isempty(x) || (isnumeric(x) && isscalar(x)));
        p.addParameter("AttemptId", 1, @(x)isnumeric(x) && isscalar(x));
        p.addParameter("RuntimeSlot", NaN, @(x)isnumeric(x) && isscalar(x));
        p.addParameter("RuntimeNoiseSNR_dB", Inf, @(x)isnumeric(x) && isscalar(x));
        p.addParameter("RuntimeStageWaveforms", struct(), @(x) isempty(x) || isstruct(x));
        p.addParameter("RequireRuntimeStageWaveforms", false, @(x)islogical(x) || isnumeric(x));
        p.addParameter("WriteArtifacts", false, @(x)islogical(x) || isnumeric(x));
        p.parse(varargin{:});
        opt = p.Results;

        cfgRuntime = cfg;
        cfgRuntime = sixgr.util.structSet(cfgRuntime, "random_access.use_runtime_channel", true);
        cfgRuntime = sixgr.util.structSet(cfgRuntime, "lls6g.userContext.UEIndex", double(opt.UEId));
        cfgRuntime = sixgr.util.structSet(cfgRuntime, "lls6g.userContext.RuntimeUEIndex", double(opt.UEId));
        if ~isempty(opt.CellId)
            cfgRuntime = sixgr.util.structSet(cfgRuntime, "lls6g.userContext.RuntimeServingCell", double(opt.CellId));
            cfgRuntime = sixgr.util.structSet(cfgRuntime, "lls6g.userContext.RuntimeServingCellIndex", double(opt.CellId));
        end
        result = sixgr.phy.ra.runFourStepRA(cfgRuntime, ...
            "RunFolder", opt.RunFolder, ...
            "RunId", opt.RunId, ...
            "ScenarioName", opt.ScenarioName, ...
            "UEId", double(opt.UEId), ...
            "CellId", opt.CellId, ...
            "AttemptId", double(opt.AttemptId), ...
            "RuntimeIntegrationMode", "coupled_truth_runtime", ...
            "UseRuntimeChannel", true, ...
            "RuntimeNoiseSNR_dB", double(opt.RuntimeNoiseSNR_dB), ...
            "RuntimeSlot", double(opt.RuntimeSlot), ...
            "RuntimeStageWaveforms", opt.RuntimeStageWaveforms, ...
            "RequireRuntimeStageWaveforms", logical(opt.RequireRuntimeStageWaveforms), ...
            "AllowRuntimeStageWaveformComposition", true, ...
            "WriteArtifacts", logical(opt.WriteArtifacts));
    end

    function state = updateTimingAdvanceFromReceiverTrialImpl(state, ueIdx, row, sourceLabel)
        if ~(istable(row) && height(row) >= 1)
            return;
        end
        taSamples = sixgr.truth.CoupledTruthRuntime.rowFirstFinite(row, ...
            ["TimingAdvance_samples","TimingOffset_samples","EstimatedTimingOffset_PreCorrection_samples","TimingError_samples"], NaN);
        taUs = sixgr.truth.CoupledTruthRuntime.rowFirstFinite(row, ["TimingAdvance_us"], NaN);
        if ~isfinite(taSamples)
            return;
        end
        slotIdx = double(sixgr.truth.CoupledTruthRuntime.rowValue(row, "Slot", ...
            sixgr.util.structGet(state, "CurrentSlot", NaN)));
        alignedState = "time_aligned_from_ul_receiver_measurement";
        if contains(lower(string(sourceLabel)), "srs")
            alignedState = "time_aligned_from_srs_receiver_measurement";
        end
        state = sixgr.truth.CoupledTruthRuntime.updateTimingAdvanceMeasurementImpl( ...
            state, ueIdx, taSamples, taUs, sourceLabel, slotIdx, alignedState);
    end

    function state = updateTimingAdvanceMeasurementImpl(state, ueIdx, taSamples, taUs, sourceLabel, slotIdx, alignedState)
        ueIdx = round(double(ueIdx));
        if ~(isfinite(ueIdx) && ueIdx >= 1 && ueIdx <= double(sixgr.util.structGet(state, "NumUsers", 0)))
            return;
        end
        taSamples = double(taSamples);
        if ~isfinite(taSamples)
            return;
        end
        fsHz = sixgr.truth.CoupledTruthRuntime.timingAdvanceSampleRateHz(state);
        taUs = double(taUs);
        if ~(isfinite(taUs) && isscalar(taUs)) && isfinite(fsHz) && fsHz > 0
            taUs = taSamples / fsHz * 1e6;
        end
        slotIdx = double(slotIdx);
        if ~(isfinite(slotIdx) && isscalar(slotIdx))
            slotIdx = double(sixgr.util.structGet(state, "CurrentSlot", NaN));
        end
        servingCell = sixgr.truth.CoupledTruthRuntime.currentServingCellForUE(state, ueIdx);
        servingDistanceM = sixgr.truth.CoupledTruthRuntime.currentServingDistanceM(state, ueIdx, servingCell);
        state.LastTimingAdvanceSamplesByUE(ueIdx) = double(taSamples);
        state.LastTimingAdvanceUsByUE(ueIdx) = double(taUs);
        state.LastTimingAdvanceSourceByUE(ueIdx) = string(sourceLabel);
        state.LastTimingAdvanceUpdateSlotByUE(ueIdx) = double(slotIdx);
        state.LastTimingAdvanceServingCellByUE(ueIdx) = double(servingCell);
        state.LastTimingAdvanceServingDistanceMByUE(ueIdx) = double(servingDistanceM);
        state.TimingAdvanceDriftSamplesByUE(ueIdx) = 0;
        state.TimingAdvanceDriftUsByUE(ueIdx) = 0;
        state.TimingAdvanceUpdateRequiredByUE(ueIdx) = false;
        state.TimingAdvanceUpdateStatusByUE(ueIdx) = "updated_from_runtime_receiver_timing_measurement";
        if nargin >= 7 && strlength(strtrim(string(alignedState))) > 0
            state.TimeAlignmentState(ueIdx) = string(alignedState);
        else
            state.TimeAlignmentState(ueIdx) = "time_aligned_from_runtime_receiver_measurement";
        end
    end

    function state = refreshTimingAdvanceMobilityDriftImpl(state)
        mode = lower(strtrim(string(sixgr.util.structGet(state.ControlGating, "TimingAdvanceUpdateMode", "measurement_only"))));
        if mode == "disabled"
            return;
        end
        thresholdSamples = double(sixgr.util.structGet(state.ControlGating, "TimingAdvanceUpdateThresholdSamples", 1));
        if ~(isfinite(thresholdSamples) && isscalar(thresholdSamples) && thresholdSamples >= 0)
            thresholdSamples = 1;
        end
        fsHz = sixgr.truth.CoupledTruthRuntime.timingAdvanceSampleRateHz(state);
        nUsers = double(sixgr.util.structGet(state, "NumUsers", 0));
        for ueIdx = 1:nUsers
            lastTA = double(sixgr.truth.CoupledTruthRuntime.numericStateAt(state, "LastTimingAdvanceSamplesByUE", ueIdx, NaN));
            if ~isfinite(lastTA)
                state.TimingAdvanceUpdateStatusByUE(ueIdx) = "not_evaluated_no_timing_advance_baseline";
                continue;
            end
            baselineDistanceM = double(sixgr.truth.CoupledTruthRuntime.numericStateAt(state, "LastTimingAdvanceServingDistanceMByUE", ueIdx, NaN));
            baselineCell = double(sixgr.truth.CoupledTruthRuntime.numericStateAt(state, "LastTimingAdvanceServingCellByUE", ueIdx, NaN));
            servingCell = sixgr.truth.CoupledTruthRuntime.currentServingCellForUE(state, ueIdx);
            if isfinite(baselineCell) && isfinite(servingCell) && round(baselineCell) ~= round(servingCell)
                state.TimingAdvanceUpdateRequiredByUE(ueIdx) = true;
                state.TimingAdvanceUpdateStatusByUE(ueIdx) = "ta_update_required_serving_cell_changed_after_mobility";
                state.TimeAlignmentState(ueIdx) = "ta_update_required_serving_cell_changed";
                continue;
            end
            currentDistanceM = sixgr.truth.CoupledTruthRuntime.currentServingDistanceM(state, ueIdx, servingCell);
            if ~(isfinite(fsHz) && fsHz > 0)
                state.TimingAdvanceUpdateStatusByUE(ueIdx) = "not_evaluated_sample_rate_unavailable";
                continue;
            end
            if ~(isfinite(baselineDistanceM) && isfinite(currentDistanceM))
                state.TimingAdvanceUpdateStatusByUE(ueIdx) = "not_evaluated_serving_geometry_unavailable";
                continue;
            end
            driftSamples = 2 * (double(currentDistanceM) - double(baselineDistanceM)) / 299792458.0 * double(fsHz);
            driftUs = driftSamples / double(fsHz) * 1e6;
            state.TimingAdvanceDriftSamplesByUE(ueIdx) = double(driftSamples);
            state.TimingAdvanceDriftUsByUE(ueIdx) = double(driftUs);
            if abs(double(driftSamples)) < double(thresholdSamples)
                state.TimingAdvanceUpdateRequiredByUE(ueIdx) = false;
                state.TimingAdvanceUpdateStatusByUE(ueIdx) = "within_configured_ta_drift_threshold";
                continue;
            end
            if mode == "geometry_predictive"
                state.LastTimingAdvanceSamplesByUE(ueIdx) = double(lastTA) + double(driftSamples);
                state.LastTimingAdvanceUsByUE(ueIdx) = double(state.LastTimingAdvanceSamplesByUE(ueIdx)) / double(fsHz) * 1e6;
                state.LastTimingAdvanceSourceByUE(ueIdx) = "geometry_propagation_mobility_delta";
                state.LastTimingAdvanceUpdateSlotByUE(ueIdx) = double(sixgr.util.structGet(state, "CurrentCanonicalSlot", NaN));
                state.LastTimingAdvanceServingCellByUE(ueIdx) = double(servingCell);
                state.LastTimingAdvanceServingDistanceMByUE(ueIdx) = double(currentDistanceM);
                state.TimingAdvanceUpdateRequiredByUE(ueIdx) = false;
                state.TimingAdvanceUpdateStatusByUE(ueIdx) = "updated_from_geometry_mobility_delta";
                state.TimeAlignmentState(ueIdx) = "time_aligned_from_geometry_mobility_update";
            else
                state.TimingAdvanceUpdateRequiredByUE(ueIdx) = true;
                state.TimingAdvanceUpdateStatusByUE(ueIdx) = "ta_update_required_waiting_for_receiver_timing_measurement";
                state.TimeAlignmentState(ueIdx) = "ta_update_required_after_mobility";
            end
        end
    end

    function fsHz = timingAdvanceSampleRateHz(state)
        cfg = sixgr.util.structGet(state, "CfgMobility", struct());
        fsHz = double(sixgr.util.structGet(cfg, "phy.waveform.sampleRate_Hz", ...
            sixgr.util.structGet(cfg, "waveform.sample_rate_hz", NaN)));
        if ~(isfinite(fsHz) && isscalar(fsHz) && fsHz > 0)
            fsHz = NaN;
        end
    end

    function servingCell = currentServingCellForUE(state, ueIdx)
        servingCell = NaN;
        vec = double(sixgr.util.structGet(state, "CurrentServingIdx", []));
        if ueIdx >= 1 && ueIdx <= numel(vec)
            servingCell = double(vec(ueIdx));
        end
    end

    function distanceM = currentServingDistanceM(state, ueIdx, servingCell)
        distanceM = NaN;
        if ~(isfinite(double(servingCell)) && servingCell >= 1)
            return;
        end
        uePos = double(sixgr.util.structGet(sixgr.util.structGet(state, "UE", struct()), "pos_m", []));
        bsPos = double(sixgr.util.structGet(sixgr.util.structGet(sixgr.util.structGet(state, "Layout", struct()), "bs", struct()), "pos_m", []));
        if ueIdx < 1 || ueIdx > size(uePos, 1) || servingCell > size(bsPos, 1)
            return;
        end
        delta = uePos(ueIdx, :) - bsPos(round(double(servingCell)), :);
        distanceM = sqrt(sum(double(delta(:)).^2));
    end

    function state = publishReferenceSignalMeasurementImpl(state, signalType, targetType, targetId, row, varargin)
        opt = struct("AvailableSlot", NaN, "ProducerSlot", NaN, "Valid", [], ...
            "Direction", "", "SourceSignal", "", "MeasurementSource", "");
        if ~isempty(varargin)
            if mod(numel(varargin), 2) ~= 0
                error("sixgr:truth:ReferenceMeasurementBadNV", ...
                    "Reference measurement name-value inputs must come in pairs.");
            end
            for ii = 1:2:numel(varargin)
                key = lower(strtrim(string(varargin{ii})));
                switch key
                    case "availableslot"
                        opt.AvailableSlot = double(varargin{ii + 1});
                    case "producerslot"
                        opt.ProducerSlot = double(varargin{ii + 1});
                    case "valid"
                        opt.Valid = logical(varargin{ii + 1});
                    case "direction"
                        opt.Direction = string(varargin{ii + 1});
                    case "sourcesignal"
                        opt.SourceSignal = string(varargin{ii + 1});
                    case "measurementsource"
                        opt.MeasurementSource = string(varargin{ii + 1});
                    otherwise
                        error("sixgr:truth:ReferenceMeasurementUnknownOption", ...
                            "Unknown reference measurement option '%s'.", key);
                end
            end
        end
        if ~(isfield(state, "ReferenceSignalMeasurementTable") && istable(state.ReferenceSignalMeasurementTable))
            state.ReferenceSignalMeasurementTable = struct2table(repmat( ...
                sixgr.truth.CoupledTruthRuntime.emptyReferenceSignalMeasurementRow(), 0, 1));
        end
        signalType = upper(strtrim(string(signalType)));
        targetType = upper(strtrim(string(targetType)));
        if strlength(signalType) == 0 || strlength(targetType) == 0 || ~isfinite(double(targetId))
            return;
        end
        producerSlot = double(opt.ProducerSlot);
        if ~isfinite(producerSlot)
            producerSlot = sixgr.truth.CoupledTruthRuntime.rowFirstFinite(row, ...
                ["Slot","SourceSlot","ProducerSlot"], sixgr.util.structGet(state, "CurrentSlot", NaN));
        end
        availableSlot = double(opt.AvailableSlot);
        if ~isfinite(availableSlot)
            availableSlot = sixgr.truth.CoupledTruthRuntime.rowFirstFinite(row, ...
                ["AvailableSlot","DueSlot"], producerSlot);
        end
        valid = opt.Valid;
        if isempty(valid)
            valid = sixgr.truth.CoupledTruthRuntime.trialPassed(row);
        end
        meas = sixgr.truth.CoupledTruthRuntime.emptyReferenceSignalMeasurementRow();
        meas.SignalType = char(signalType);
        meas.TargetType = char(targetType);
        meas.TargetId = double(targetId);
        meas.ProducerSlot = double(producerSlot);
        meas.AvailableSlot = double(availableSlot);
        meas.Valid = logical(valid);
        meas.Direction = char(upper(strtrim(string(opt.Direction))));
        meas.SourceSignal = char(string(sixgr.util.structGet(opt, "SourceSignal", signalType)));
        if strlength(strtrim(string(meas.SourceSignal))) == 0
            meas.SourceSignal = char(signalType);
        end
        meas.MeasurementSource = char(string(opt.MeasurementSource));
        if strlength(strtrim(string(meas.MeasurementSource))) == 0
            meas.MeasurementSource = "CoupledTruthRuntime.publishReferenceSignalMeasurement";
        end
        meas.MeasurementId = char(signalType + "_" + targetType + "_" + string(targetId) + "_slot_" + string(producerSlot));
        meas.CQI = sixgr.truth.CoupledTruthRuntime.rowFirstFinite(row, ["WidebandCQI","CQI"], NaN);
        meas.RI = sixgr.truth.CoupledTruthRuntime.rowFirstFinite(row, ["RIEstimate","RankIndicator","RI","Rank"], NaN);
        meas.PMI = sixgr.truth.CoupledTruthRuntime.rowFirstFinite(row, ["TPMIEstimate","PMI"], NaN);
        meas.CRI = sixgr.truth.CoupledTruthRuntime.rowFirstFinite(row, ["CRI"], NaN);
        meas.SINR_dB = sixgr.truth.CoupledTruthRuntime.rowFirstFinite(row, ...
            ["WidebandSRSSINR_dB","SINR_dB","MeasuredSINR_dB","PostEqSINR_dB"], NaN);
        meas.NMSE_dB = sixgr.truth.CoupledTruthRuntime.rowFirstFinite(row, ["NMSE_dB","TrueChannelNMSE_dB"], NaN);
        meas.TimingOffset_samples = sixgr.truth.CoupledTruthRuntime.rowFirstFinite(row, ...
            ["EstimatedTimingOffset_samples","TimingEstimate_samples","TRSTimingEstimate_samples"], NaN);
        meas.CFO_Hz = sixgr.truth.CoupledTruthRuntime.rowFirstFinite(row, ...
            ["EstimatedCFO_Hz","EstimatedOscillatorCFO_Hz","EstimatedCFO_PreCorrection_Hz"], NaN);
        meas.EvidenceSource = sixgr.truth.CoupledTruthRuntime.rowFirstString(row, ...
            ["TrackingEstimateSource","RuntimeEvidenceSource","NMSEReferenceSource"], "");
        state.ReferenceSignalMeasurementTable = sixgr.truth.CoupledTruthRuntime.appendCompatTable( ...
            state.ReferenceSignalMeasurementTable, struct2table(meas, "AsArray", true));
    end

    function result = consumeReferenceSignalMeasurementImpl(state, signalType, targetType, targetId, consumerSlot, maxAgeSlots)
        T = sixgr.util.structGet(state, "ReferenceSignalMeasurementTable", table());
        result = sixgr.phy.refsig.causalMeasurementState(T, consumerSlot, ...
            "SignalType", signalType, "TargetType", targetType, ...
            "TargetId", targetId, "MaxAgeSlots", maxAgeSlots);
    end

    function state = applySRSTrialImpl(state, ueIdx, trialT)
        if ~(isfinite(double(ueIdx)) && ueIdx >= 1 && ueIdx <= double(state.NumUsers))
            return;
        end
        row = trialT(end, :);
        slotIdx = double(sixgr.truth.CoupledTruthRuntime.rowValue(row, "Slot", state.CurrentSlot));
        state.LastSRSObservedSlotByUE(ueIdx) = double(slotIdx);
        ok = sixgr.truth.CoupledTruthRuntime.srsRuntimeEvidenceComplete(row);
        if ok
            state.SRSValidityState(ueIdx) = "valid";
            state.CSIValidityState(ueIdx) = "fresh_srs";
            state.LastSuccessfulSRSSlotByUE(ueIdx) = double(slotIdx);
            state = sixgr.truth.CoupledTruthRuntime.updateLatestULFeedbackFromSRSTrial(state, ueIdx, row, slotIdx);
            state = sixgr.truth.CoupledTruthRuntime.updateTimingAdvanceFromReceiverTrialImpl( ...
                state, ueIdx, row, "srs_receiver_timing_estimate");
        else
            state.SRSValidityState(ueIdx) = "invalid";
            state.CSIValidityState(ueIdx) = "invalid_srs_not_usable";
            state.SRSInvalidEventCount(ueIdx) = double(state.SRSInvalidEventCount(ueIdx)) + 1;
        end
        state = sixgr.truth.CoupledTruthRuntime.publishReferenceSignalMeasurementImpl( ...
            state, "SRS", "UE", ueIdx, row, ...
            "ProducerSlot", slotIdx, "AvailableSlot", slotIdx, ...
            "Valid", ok, "Direction", "UL", "SourceSignal", "SRS", ...
            "MeasurementSource", "CoupledTruthRuntime.applySRSTrial");
        state = sixgr.truth.CoupledTruthRuntime.refreshControlStateImpl(state);
    end

    function state = updateLatestULFeedbackFromSRSTrial(state, ueIdx, row, slotIdx)
        ri = sixgr.truth.CoupledTruthRuntime.rowFirstFinite(row, ...
            ["RIEstimate","RankEstimate","EstimatedRI","RI"], NaN);
        tpmi = sixgr.truth.CoupledTruthRuntime.rowFirstFinite(row, ...
            ["TPMIEstimate","EstimatedTPMI","TPMI","PMI"], NaN);
        condDb = sixgr.truth.CoupledTruthRuntime.rowFirstFinite(row, ...
            ["SRSConditionNumber_dB","ConditionNumber_dB"], NaN);
        sinrDb = sixgr.truth.CoupledTruthRuntime.rowFirstFinite(row, ...
            ["SINR_dB","PostEqSINR_dB","MeasuredTrialSINR_dB","MeasuredSINR_dB"], NaN);
        cqi = double(sixgr.util.normalizeReportedCQI( ...
            sixgr.truth.CoupledTruthRuntime.rowFirstFinite(row, ["WidebandCQI","CQI"], NaN)));
        mcsIndex = sixgr.truth.CoupledTruthRuntime.rowFirstFinite(row, ...
            ["CQIDerivedMCS","MCSIndex"], NaN);
        targetCodeRate = sixgr.truth.CoupledTruthRuntime.rowFirstFinite(row, ...
            ["CQIDerivedTargetCodeRate","TargetCodeRate"], NaN);
        modulation = string(sixgr.truth.CoupledTruthRuntime.rowFirstString(row, ...
            ["CQIDerivedModulation","Modulation"], ""));
        rawSrsCQI = double(cqi);
        rawSrsMCSIndex = double(mcsIndex);
        rawSrsTargetCodeRate = double(targetCodeRate);
        rawSrsModulation = string(modulation);
        if ~(isfinite(ri) || isfinite(tpmi) || isfinite(condDb) || ...
                isfinite(sinrDb) || (isfinite(cqi) && cqi > 0) || isfinite(mcsIndex))
            return;
        end
        if ~(isfinite(cqi) && cqi > 0) && isfinite(sinrDb)
            try
                cqiFeedback = sixgr.link.resolveWidebandCQI( ...
                    struct("WidebandSINR_dB", double(sinrDb)), state.CfgMobility, "UL");
                cqi = double(sixgr.util.normalizeReportedCQI( ...
                    sixgr.util.structGet(cqiFeedback, "WidebandCQI", NaN)));
            catch
                cqi = NaN;
            end
        end
        if ~(isfinite(mcsIndex) && mcsIndex >= 0) && isfinite(cqi) && cqi > 0
            [modFromCQI, rateFromCQI, mcsFromCQI] = sixgr.link.amcFromCQI(cqi, "", NaN, state.CfgMobility, "UL");
            mcsIndex = double(mcsFromCQI);
            modulation = string(modFromCQI);
            targetCodeRate = double(rateFromCQI);
        end
        srsWidebandMCSUsable = sixgr.truth.CoupledTruthRuntime.srsWidebandMCSUsableForScheduling( ...
            row, state.CfgMobility);
        [schedCQI, schedMCSIndex, schedModulation, schedTargetCodeRate, ...
                schedAdjustedSINR_dB, schedBackoff_dB, schedSource] = ...
            sixgr.truth.CoupledTruthRuntime.resolveULSRSDataSchedulerCQI( ...
                state.CfgMobility, sinrDb, cqi, row);
        if srsWidebandMCSUsable && isfinite(schedCQI) && schedCQI > 0
            cqi = double(schedCQI);
            if isfinite(schedMCSIndex) && schedMCSIndex >= 0
                mcsIndex = double(schedMCSIndex);
            end
            if isfinite(schedTargetCodeRate) && schedTargetCodeRate > 0
                targetCodeRate = double(schedTargetCodeRate);
            end
            if strlength(strtrim(string(schedModulation))) > 0
                modulation = string(schedModulation);
            end
        end
        if ueIdx <= numel(state.LatestULFeedback)
            latest = state.LatestULFeedback(ueIdx);
        else
            latest = sixgr.truth.CoupledTruthRuntime.emptyLatestFeedbackRow();
        end
        protectDataMCS = sixgr.truth.CoupledTruthRuntime.shouldPreserveRecentULDataMCS( ...
            latest, mcsIndex, slotIdx, state.CfgMobility) || ...
            sixgr.truth.CoupledTruthRuntime.shouldPreservePendingULDataMCS( ...
            state, ueIdx, mcsIndex, slotIdx);
        latest.Valid = true;
        latest.Direction = "UL";
        if ~protectDataMCS
            latest.Slot = double(slotIdx);
            if srsWidebandMCSUsable
                latest.FeedbackSourceSignal = "SRS";
            else
                latest.FeedbackSourceSignal = "SRS_PARTIAL_BAND_RI_TPMI_ONLY";
            end
            latest.FeedbackCRCPass = NaN;
            if srsWidebandMCSUsable
                if isfinite(schedCQI) && schedCQI > 0
                    latest.MCSSelectionSource = char(schedSource);
                    latest.MCSValueStatus = "measured_srs_adjusted_for_pusch_data_channel";
                else
                    latest.MCSSelectionSource = "feedback_cqi_derived_reference";
                    latest.MCSValueStatus = "measured_cqi_mapped";
                end
            else
                latest.MCSSelectionSource = "srs_partial_bandwidth_not_wideband_mcs";
                latest.MCSValueStatus = "unavailable_srs_partial_bandwidth_not_wideband";
            end
        end
        if isfinite(sinrDb) && ~protectDataMCS && srsWidebandMCSUsable
            latest.SINR_dB = double(sinrDb);
        end
        if isfinite(cqi) && cqi > 0 && ~protectDataMCS && srsWidebandMCSUsable
            latest.CQI = double(cqi);
        end
        if isfinite(mcsIndex) && mcsIndex >= 0 && ~protectDataMCS && srsWidebandMCSUsable
            latest.MCSIndex = double(round(mcsIndex));
            if isfinite(rawSrsMCSIndex) && rawSrsMCSIndex >= 0
                latest.RawCQIDerivedMCS = double(round(rawSrsMCSIndex));
            else
                latest.RawCQIDerivedMCS = double(round(mcsIndex));
            end
        end
        if isfinite(targetCodeRate) && targetCodeRate > 0 && ~protectDataMCS && srsWidebandMCSUsable
            latest.TargetCodeRate = double(targetCodeRate);
            if isfinite(rawSrsTargetCodeRate) && rawSrsTargetCodeRate > 0
                latest.RawCQIDerivedTargetCodeRate = double(rawSrsTargetCodeRate);
            else
                latest.RawCQIDerivedTargetCodeRate = double(targetCodeRate);
            end
        end
        if strlength(strtrim(modulation)) > 0 && ~protectDataMCS && srsWidebandMCSUsable
            latest.Modulation = char(modulation);
            if strlength(strtrim(rawSrsModulation)) > 0
                latest.RawCQIDerivedModulation = char(rawSrsModulation);
            else
                latest.RawCQIDerivedModulation = char(modulation);
            end
        end
        if ~protectDataMCS && srsWidebandMCSUsable && isfinite(schedCQI) && schedCQI > 0
            latest.SchedulerCQIRawCQI = double(rawSrsCQI);
            latest.SchedulerAdjustedSINR_dB = double(schedAdjustedSINR_dB);
            latest.SchedulerSINRBackoff_dB = double(schedBackoff_dB);
            latest.SchedulerCQISource = char(schedSource);
        end
        if isfinite(ri)
            latest.RI = double(max(1, round(ri)));
        end
        if isfinite(tpmi)
            sanitizedTPMI = sixgr.truth.CoupledTruthRuntime.sanitizeFeedbackPMI( ...
                tpmi, state.CfgMobility, "UL", latest.RI);
            if isfinite(sanitizedTPMI)
                latest.PMI = double(round(sanitizedTPMI));
            end
        end
        servingCell = sixgr.truth.CoupledTruthRuntime.rowFirstFinite(row, ...
            ["ServingCell","BaseStationID","CellID"], NaN);
        if isfinite(servingCell)
            latest.ServingCell = double(servingCell);
        end
        state.LatestULFeedback(ueIdx) = latest;

        feedsDLFromSRS = sixgr.truth.CoupledTruthRuntime.srsReciprocityFeedsDLFeedback(state.CfgMobility);
        if feedsDLFromSRS
            if ueIdx <= numel(state.LatestDLFeedback)
                dlLatest = state.LatestDLFeedback(ueIdx);
            else
                dlLatest = sixgr.truth.CoupledTruthRuntime.emptyLatestFeedbackRow();
            end
            dlLatest.Valid = true;
            dlLatest.Direction = "DL";
            dlLatest.Slot = double(slotIdx);
            if srsWidebandMCSUsable
                dlLatest.FeedbackSourceSignal = "SRS_RECIPROCITY";
            else
                dlLatest.FeedbackSourceSignal = "SRS_RECIPROCITY_PARTIAL_BAND_RI_TPMI_ONLY";
            end
            dlLatest.FeedbackCRCPass = NaN;
            if srsWidebandMCSUsable
                dlLatest.MCSSelectionSource = "feedback_cqi_derived_reference";
                dlLatest.MCSValueStatus = "measured_cqi_mapped";
            else
                dlLatest.MCSSelectionSource = "srs_partial_bandwidth_not_wideband_mcs";
                dlLatest.MCSValueStatus = "unavailable_srs_partial_bandwidth_not_wideband";
            end
            if isfinite(sinrDb) && srsWidebandMCSUsable
                dlLatest.SINR_dB = double(sinrDb);
            end
            dlCqi = rawSrsCQI;
            if isfinite(sinrDb) && srsWidebandMCSUsable
                try
                    dlCqiFeedback = sixgr.link.resolveWidebandCQI( ...
                        struct("WidebandSINR_dB", double(sinrDb)), state.CfgMobility, "DL");
                    candidateDLCqi = double(sixgr.util.normalizeReportedCQI( ...
                        sixgr.util.structGet(dlCqiFeedback, "WidebandCQI", NaN)));
                    if isfinite(candidateDLCqi) && candidateDLCqi > 0
                        dlCqi = candidateDLCqi;
                    end
                catch
                end
            end
            if isfinite(dlCqi) && dlCqi > 0 && srsWidebandMCSUsable
                dlLatest.CQI = double(dlCqi);
                [dlMod, dlRate, dlMCS] = sixgr.link.amcFromCQI(dlCqi, "", NaN, state.CfgMobility, "DL");
                if isfinite(dlMCS) && dlMCS >= 0
                    dlLatest.MCSIndex = double(round(dlMCS));
                    dlLatest.Modulation = char(string(dlMod));
                    dlLatest.TargetCodeRate = double(dlRate);
                    dlLatest.RawCQIDerivedMCS = double(round(dlMCS));
                    dlLatest.RawCQIDerivedModulation = char(string(dlMod));
                    dlLatest.RawCQIDerivedTargetCodeRate = double(dlRate);
                end
            end
            if isfinite(ri)
                dlLatest.RI = double(max(1, round(ri)));
            end
            dlPMI = sixgr.truth.CoupledTruthRuntime.sanitizeFeedbackPMI( ...
                tpmi, state.CfgMobility, "DL", dlLatest.RI);
            if isfinite(dlPMI)
                dlLatest.PMI = double(round(dlPMI));
            end
            if isfinite(servingCell)
                dlLatest.ServingCell = double(servingCell);
            end
            state.LatestDLFeedback(ueIdx) = dlLatest;
        end
    end

    function [cqi, mcsIndex, modulation, targetCodeRate, adjustedSINR_dB, backoff_dB, source] = ...
            resolveULSRSDataSchedulerCQI(cfg, sinrDb, fallbackCQI, row)
        cqi = NaN;
        mcsIndex = NaN;
        modulation = "";
        targetCodeRate = NaN;
        adjustedSINR_dB = NaN;
        backoff_dB = NaN;
        source = "ul_srs_adjusted_data_scheduler_input";
        sinrDb = double(sinrDb);
        if ~(isscalar(sinrDb) && isfinite(sinrDb))
            return;
        end
        if nargin < 4
            row = struct();
        end
        backoff_dB = double(sixgr.truth.CoupledTruthRuntime.firstFiniteScalar( ...
            sixgr.util.structGet(cfg, "phy.linkAdaptation.ulReferenceSignalSchedulingBackoff_dB", NaN), ...
            sixgr.util.structGet(cfg, "phy.linkAdaptation.ulSRSToPUSCHSINRBackoff_dB", NaN), ...
            sixgr.util.structGet(cfg, "phy.linkAdaptation.ulMCSBackoff_dB", NaN), ...
            sixgr.util.structGet(cfg, "phy.linkAdaptation.ulBootstrapPreviewBackoff_dB", NaN), ...
            sixgr.util.structGet(cfg, "phy.linkAdaptation.bootstrapPreviewBackoff_dB", NaN), ...
            0));
        if ~(isfinite(backoff_dB) && backoff_dB >= 0)
            backoff_dB = 0;
        end
        adjustedSINR_dB = double(sinrDb) - double(backoff_dB);
        ri = double(sixgr.truth.CoupledTruthRuntime.rowFirstFinite(row, ...
            ["RIEstimate","RankEstimate","EstimatedRI","RI","RankIndicator","Layers"], NaN));
        if ~(isfinite(ri) && ri >= 1)
            ri = NaN;
        end
        try
            feedback = sixgr.link.resolveWidebandCQI(struct( ...
                "WidebandSINR_dB", double(adjustedSINR_dB), ...
                "SINRSource", char(source), ...
                "SINRValueRole", "measured_data_channel_scheduling_input_after_srs_to_pusch_margin", ...
                "SINRValueStatus", "PASS", ...
                "RankIndicator", double(ri)), cfg, "UL");
            cqi = double(sixgr.util.normalizeReportedCQI( ...
                sixgr.util.structGet(feedback, "WidebandCQI", NaN)));
        catch
            cqi = NaN;
        end
        if ~(isfinite(cqi) && cqi > 0)
            cqi = double(sixgr.util.normalizeReportedCQI(fallbackCQI));
            source = "ul_srs_raw_cqi_fallback_after_scheduler_adjustment_failed";
        end
        if ~(isfinite(cqi) && cqi > 0)
            return;
        end
        [modCandidate, rateCandidate, mcsCandidate] = sixgr.link.amcFromCQI( ...
            cqi, "", NaN, cfg, "UL");
        mcsIndex = double(mcsCandidate);
        modulation = char(string(modCandidate));
        targetCodeRate = double(rateCandidate);
    end

    function tf = srsWidebandMCSUsableForScheduling(row, cfg)
        tf = true;
        status = lower(strtrim(string(sixgr.truth.CoupledTruthRuntime.rowFirstString(row, ...
            ["SRSBandwidthCoverageStatus","BandwidthCoverageStatus"], ""))));
        fraction = sixgr.truth.CoupledTruthRuntime.rowFirstFinite(row, ...
            ["SRSBandwidthFraction","BandwidthCoverageFraction"], NaN);
        occupiedPRB = sixgr.truth.CoupledTruthRuntime.rowFirstFinite(row, ...
            ["SRSOccupiedPRBCount","SRSBandwidthPRBCount"], NaN);
        carrierPRB = sixgr.truth.CoupledTruthRuntime.rowFirstFinite(row, ...
            ["SRSCarrierPRBCount","CarrierPRBCount"], NaN);
        if ~(isfinite(fraction)) && isfinite(occupiedPRB) && isfinite(carrierPRB) && carrierPRB > 0
            fraction = double(occupiedPRB) / max(double(carrierPRB), eps);
        end
        minFraction = double(sixgr.util.structGet(cfg, ...
            "phy.srs.minWidebandCoverageFractionForMCS", ...
            sixgr.util.structGet(cfg, "phy.linkAdaptation.minSRSWidebandCoverageFraction", 0.8)));
        if ~(isfinite(minFraction) && minFraction > 0 && minFraction <= 1)
            minFraction = 0.8;
        end
        if strlength(status) > 0 && (contains(status, "narrow") || contains(status, "none") || ...
                contains(status, "no_coverage") || contains(status, "unavailable"))
            tf = false;
        end
        if strlength(status) > 0 && contains(status, "partial") && ...
                ~(isfinite(fraction) && fraction >= minFraction)
            tf = false;
        end
        if isfinite(fraction) && fraction < minFraction
            tf = false;
        end
    end

    function tf = shouldPreserveRecentULDataMCS(latest, srsMCSIndex, slotIdx, cfg)
        tf = false;
        if ~(isstruct(latest) && logical(sixgr.util.structGet(latest, "Valid", false)))
            return;
        end
        sourceSignal = upper(strtrim(string(sixgr.util.structGet(latest, "FeedbackSourceSignal", ""))));
        if ~any(sourceSignal == ["UL_CSI_REPORT", "PUSCH", "UL_PUSCH"])
            return;
        end
        latestMCS = double(sixgr.util.structGet(latest, "MCSIndex", NaN));
        if ~(isfinite(latestMCS) && latestMCS >= 0)
            return;
        end
        latestSlot = double(sixgr.util.structGet(latest, "Slot", NaN));
        ageSlots = double(slotIdx) - latestSlot;
        maxAgeSlots = double(sixgr.util.structGet(cfg, ...
            "phy.linkAdaptation.ulPUSCHFeedbackMaxAgeSlots", ...
            sixgr.util.structGet(cfg, "phy.linkAdaptation.ulDataFeedbackMaxAgeSlots", 20)));
        if ~(isfinite(ageSlots) && ageSlots >= 0 && isfinite(maxAgeSlots) && ageSlots <= maxAgeSlots)
            return;
        end
        srsMCSIndex = double(srsMCSIndex);
        crcPass = double(sixgr.util.structGet(latest, "FeedbackCRCPass", NaN));
        dataFailed = isfinite(crcPass) && crcPass == 0;
        if dataFailed || ~(isfinite(srsMCSIndex) && srsMCSIndex < latestMCS)
            tf = true;
        end
    end

    function tf = shouldPreservePendingULDataMCS(state, ueIdx, srsMCSIndex, slotIdx)
        tf = false;
        pendingT = sixgr.util.structGet(state, "PendingCSITable", table());
        if ~(istable(pendingT) && ~isempty(pendingT))
            return;
        end
        if ~ismember("Direction", string(pendingT.Properties.VariableNames)) || ...
                ~ismember("UEIndex", string(pendingT.Properties.VariableNames)) || ...
                ~ismember("SourceSlot", string(pendingT.Properties.VariableNames))
            return;
        end
        processed = false(height(pendingT), 1);
        if ismember("Processed", string(pendingT.Properties.VariableNames))
            processed = logical(pendingT.Processed);
        end
        mask = ~processed & upper(string(pendingT.Direction)) == "UL" & ...
            round(double(pendingT.UEIndex)) == round(double(ueIdx)) & ...
            double(pendingT.SourceSlot) <= double(slotIdx);
        if ~any(mask)
            return;
        end
        rows = pendingT(mask, :);
        [~, idx] = max(double(rows.SourceSlot));
        row = rows(idx, :);
        latest = sixgr.truth.CoupledTruthRuntime.emptyLatestFeedbackRow();
        latest.Valid = true;
        latest.Direction = "UL";
        latest.FeedbackSourceSignal = "UL_CSI_REPORT";
        latest.Slot = double(sixgr.truth.CoupledTruthRuntime.rowValue(row, "SourceSlot", NaN));
        latest.MCSIndex = double(sixgr.truth.CoupledTruthRuntime.rowValue(row, "MCSIndex", NaN));
        latest.FeedbackCRCPass = double(sixgr.truth.CoupledTruthRuntime.rowValue(row, "CRCPass", NaN));
        tf = sixgr.truth.CoupledTruthRuntime.shouldPreserveRecentULDataMCS( ...
            latest, srsMCSIndex, slotIdx, state.CfgMobility);
    end

    function tf = srsReciprocityFeedsDLFeedback(cfg)
        duplexMode = sixgr.truth.CoupledTruthRuntime.normalizedConfigString(cfg, ...
            ["phy.duplex.mode","frequency.duplex_mode","global_radio_scope.duplex_mode"]);
        orientation = sixgr.truth.CoupledTruthRuntime.normalizedConfigString(cfg, ...
            ["lls6g.reference_signals.operation_orientation","referenceSignals.operationOrientation", ...
            "reference_signals.operation_orientation","phy.csi.operationOrientation"]);
        csiMode = sixgr.truth.CoupledTruthRuntime.normalizedConfigString(cfg, ...
            ["lls6g.reference_signals.csi_acquisition_mode","referenceSignals.csiAcquisitionMode", ...
            "reference_signals.csi_acquisition_mode","phy.csi.acquisitionMode", ...
            "phy.csi.channelStateInformationMode"]);
        reciprocityMode = sixgr.truth.CoupledTruthRuntime.normalizedConfigString(cfg, ...
            ["lls6g.mimo.reciprocity_mode","mimo.reciprocity_mode"]);

        hasTDDReciprocity = duplexMode == "tdd" || reciprocityMode == "tdd" || contains(orientation, "tdd");
        hasJointCSI = contains(orientation, "reciprocity") || contains(csiMode, "joint") || contains(csiMode, "dl_ul");
        tf = logical(hasTDDReciprocity && hasJointCSI);
    end

    function value = normalizedConfigString(cfg, paths)
        value = "";
        for i = 1:numel(paths)
            candidate = string(sixgr.util.structGet(cfg, paths(i), ""));
            candidate = lower(strtrim(candidate(:)));
            candidate = candidate(strlength(candidate) > 0);
            if ~isempty(candidate)
                value = candidate(1);
                return;
            end
        end
    end

    function state = applyTRSTrialImpl(state, servingCell, trialT)
        servingCell = round(double(servingCell));
        if ~(isfinite(servingCell) && servingCell >= 1 && servingCell <= numel(sixgr.util.structGet(state, "TRSValidityStateByCell", strings(0, 1))))
            return;
        end
        state = sixgr.truth.CoupledTruthRuntime.ensureReceiverTrackingStateImpl(state);
        row = trialT(end, :);
        slotIdx = double(sixgr.truth.CoupledTruthRuntime.rowValue(row, "Slot", state.CurrentSlot));
        estDopplerHz = double(sixgr.truth.CoupledTruthRuntime.rowValue(row, "EstimatedDopplerHz", NaN));
        state.LastTRSObservedSlotByCell(servingCell) = double(slotIdx);
        rowPass = sixgr.truth.CoupledTruthRuntime.trialPassed(trialT);
        gatingActive = logical(sixgr.util.structGet(state.ControlGating, "TRSRequired", false));
        strictEvidenceOk = sixgr.truth.CoupledTruthRuntime.trsRuntimeEvidenceComplete(row);
        ok = rowPass && (~gatingActive || strictEvidenceOk);
        if ok
            state.TRSValidityStateByCell(servingCell) = "valid";
            state.TrackingEligibilityByCell(servingCell) = true;
            state.LastSuccessfulTRSSlotByCell(servingCell) = double(slotIdx);
        else
            state.TRSValidityStateByCell(servingCell) = "failed";
            state.TrackingEligibilityByCell(servingCell) = false;
            state.TRSFailureCountByCell(servingCell) = double(state.TRSFailureCountByCell(servingCell)) + 1;
        end
        if logical(ok) && isfinite(estDopplerHz)
            state.LastEstimatedTRSDopplerHzByCell(servingCell) = double(estDopplerHz);
        end
        state = sixgr.truth.CoupledTruthRuntime.updateReceiverTrackingFromTRSImpl(state, servingCell, row, ok);
        state = sixgr.truth.CoupledTruthRuntime.publishReferenceSignalMeasurementImpl( ...
            state, "TRS", "CELL", servingCell, row, ...
            "ProducerSlot", slotIdx, "AvailableSlot", slotIdx, ...
            "Valid", ok, "Direction", "DL", "SourceSignal", "TRS", ...
            "MeasurementSource", "CoupledTruthRuntime.applyTRSTrial");
        state = sixgr.truth.CoupledTruthRuntime.refreshControlStateImpl(state);
    end

    function state = ensureReceiverTrackingStateImpl(state)
        nCells = numel(sixgr.util.structGet(state, "TRSValidityStateByCell", strings(0, 1)));
        template = sixgr.truth.CoupledTruthRuntime.emptyReceiverTrackingStateRow();
        rows = repmat(template, max(0, nCells), 1);
        existing = sixgr.util.structGet(state, "ReceiverTrackingStateByCell", repmat(struct(), 0, 1));
        templateFields = fieldnames(template);
        if isstruct(existing)
            for cellIdx = 1:min(numel(existing), max(0, nCells))
                for fi = 1:numel(templateFields)
                    fieldName = templateFields{fi};
                    if isfield(existing, fieldName)
                        rows(cellIdx).(fieldName) = existing(cellIdx).(fieldName);
                    end
                end
            end
        end
        for cellIdx = 1:max(0, nCells)
            if ~isfinite(double(rows(cellIdx).ServingCell))
                rows(cellIdx).ServingCell = double(cellIdx);
            end
        end
        state.ReceiverTrackingStateByCell = rows;
        traceT = sixgr.util.structGet(state, "ReceiverTrackingTraceTable", table());
        if ~(istable(traceT))
            traceT = struct2table(repmat(sixgr.truth.CoupledTruthRuntime.emptyReceiverTrackingTraceRow(), 0, 1));
        end
        state.ReceiverTrackingTraceTable = traceT;
    end

    function state = updateReceiverTrackingFromTRSImpl(state, servingCell, row, ok)
        state = sixgr.truth.CoupledTruthRuntime.ensureReceiverTrackingStateImpl(state);
        if servingCell < 1 || servingCell > numel(state.ReceiverTrackingStateByCell)
            return;
        end
        prev = state.ReceiverTrackingStateByCell(servingCell);
        beforeState = string(sixgr.util.structGet(prev, "TrackingState", "not_initialized"));
        if strlength(strtrim(beforeState)) == 0
            beforeState = "not_initialized";
        end
        slotIdx = double(sixgr.truth.CoupledTruthRuntime.rowValue(row, "Slot", state.CurrentSlot));
        frameIdx = double(sixgr.truth.CoupledTruthRuntime.rowValue(row, "Frame", state.CurrentFrame));
        updateTime = max(0, double(slotIdx) - 1) * double(sixgr.util.structGet(state, "SlotDuration_s", NaN));
        estDopplerHz = sixgr.truth.CoupledTruthRuntime.rowFirstFinite(row, ["EstimatedDopplerHz","EstimatedDoppler_Hz"], NaN);
        nmse = sixgr.truth.CoupledTruthRuntime.rowFirstFinite(row, ["NMSE_dB"], NaN);
        phaseErr = sixgr.truth.CoupledTruthRuntime.rowFirstFinite(row, ["PhaseTrackingError_deg","PhaseError_deg"], NaN);
        qclAccuracy = sixgr.truth.CoupledTruthRuntime.rowFirstFinite(row, ["QCLAccuracy"], NaN);
        detectionMetric = sixgr.truth.CoupledTruthRuntime.rowFirstFinite(row, ["DetectionMetric"], NaN);
        timingEstimate = sixgr.truth.CoupledTruthRuntime.rowFirstFinite(row, ...
            ["EstimatedTimingOffset_samples","TimingEstimate_samples","TimingOffset_samples"], NaN);
        estimatedCFOHz = sixgr.truth.CoupledTruthRuntime.rowFirstFinite(row, ...
            ["EstimatedOscillatorCFO_Hz","EstimatedCFO_Hz","EstimatedCFO_PreCorrection_Hz"], NaN);
        estimatedCommonFrequencyHz = sixgr.truth.CoupledTruthRuntime.rowFirstFinite(row, ...
            ["EstimatedCommonFrequency_Hz","EstimatedCommonPhaseFrequency_Hz"], NaN);
        physicalDopplerHz = sixgr.truth.CoupledTruthRuntime.rowFirstFinite(row, ...
            ["PhysicalDoppler_Hz","EstimatedDopplerHz","EstimatedDoppler_Hz"], NaN);
        evidenceSource = sixgr.truth.CoupledTruthRuntime.rowFirstString(row, ...
            ["TrackingEstimateSource","RuntimeEvidenceSource"], "runtime_trs_trial_row");

        if logical(ok)
            afterState = "valid";
            outcome = "updated_from_trs_runtime_observation";
            channelFreshness = "fresh_trs_runtime_observation";
        else
            afterState = "failed";
            outcome = "trs_runtime_observation_failed";
            channelFreshness = "invalid_trs_runtime_observation";
        end
        explicitCFOAvailable = sixgr.truth.CoupledTruthRuntime.rowAnyLogical(row, ...
            ["TRSCFOEstimateAvailable","CFOEstimateAvailable"], isfinite(estimatedCFOHz));
        cfoAvailable = logical(ok) && logical(explicitCFOAvailable) && isfinite(estimatedCFOHz);
        if ~cfoAvailable
            estimatedCFOHz = NaN;
        end
        if isfinite(estDopplerHz) && cfoAvailable
            frequencyState = "doppler_and_cfo_estimates_updated_from_trs";
        elseif cfoAvailable
            frequencyState = "cfo_estimate_updated_from_trs";
        elseif isfinite(estDopplerHz)
            frequencyState = "doppler_estimate_updated_from_trs";
        else
            frequencyState = "not_updated_frequency_estimate_unavailable";
        end
        explicitTimingAvailable = sixgr.truth.CoupledTruthRuntime.rowAnyLogical(row, ...
            ["TRSTimingEstimateAvailable","TimingEstimateAvailable"], isfinite(timingEstimate));
        timingAvailable = logical(ok) && logical(explicitTimingAvailable) && isfinite(timingEstimate);
        if ~timingAvailable
            timingEstimate = NaN;
        end
        if timingAvailable
            timingState = "timing_estimate_updated_from_trs";
        else
            timingState = "not_updated_timing_estimate_unavailable";
        end
        tracked = prev;
        tracked.ServingCell = double(servingCell);
        tracked.SourceSignal = "TRS";
        tracked.ReceiverConsumerType = "shared_receiver_tracking_state";
        tracked.IntegrationStatus = "integrated_shared_tracking_object";
        tracked.IntegrationBlocker = "";
        tracked.TRSProcessed = true;
        tracked.TrackingState = char(afterState);
        tracked.TRSTrackingStateBefore = char(beforeState);
        tracked.TRSTrackingStateAfter = char(afterState);
        tracked.TRSUpdateOutcome = char(outcome);
        tracked.LastUpdateFrame = double(frameIdx);
        tracked.LastUpdateSlot = double(slotIdx);
        tracked.TRSTrackingUpdateTime_s = double(updateTime);
        tracked.MeasurementSFNSlot = sprintf("frame=%g,slot=%g", frameIdx, slotIdx);
        tracked.ChannelTrackingFreshnessState = char(channelFreshness);
        tracked.FrequencyTrackingState = char(frequencyState);
        tracked.TimingTrackingState = char(timingState);
        tracked.TimingEstimateAvailable = logical(timingAvailable);
        tracked.TimingEstimate_samples = double(timingEstimate);
        tracked.CFOEstimateAvailable = logical(cfoAvailable);
        tracked.EstimatedCFO_Hz = double(estimatedCFOHz);
        tracked.EstimatedOscillatorCFO_Hz = double(estimatedCFOHz);
        tracked.EstimatedCommonFrequency_Hz = double(estimatedCommonFrequencyHz);
        tracked.PhysicalDoppler_Hz = double(physicalDopplerHz);
        tracked.EstimatedDopplerHz = double(estDopplerHz);
        tracked.NMSE_dB = double(nmse);
        tracked.PhaseError_deg = double(phaseErr);
        tracked.QCLAccuracy = double(qclAccuracy);
        tracked.DetectionMetric = double(detectionMetric);
        tracked.RuntimeEvidenceSource = char(string(evidenceSource));
        tracked.SourceArtifact = "air_interface/csv/trs_trials.csv";
        state.ReceiverTrackingStateByCell(servingCell) = tracked;

        traceRow = sixgr.truth.CoupledTruthRuntime.emptyReceiverTrackingTraceRow();
        traceRow.ServingCell = double(servingCell);
        traceRow.SourceSignal = "TRS";
        traceRow.TRSProcessed = true;
        traceRow.TRSReceiverConsumerType = "shared_receiver_tracking_state";
        traceRow.TRSReceiverIntegrationStatus = "integrated_shared_tracking_object";
        traceRow.TRSReceiverIntegrationBlocker = "";
        traceRow.TRSTrackingStateBefore = char(beforeState);
        traceRow.TRSTrackingStateAfter = char(afterState);
        traceRow.TRSTrackingUpdateTime_s = double(updateTime);
        traceRow.TRSAssociatedCell = double(servingCell);
        traceRow.TRSUpdateOutcome = char(outcome);
        traceRow.TRSChannelTrackingFreshnessState = char(channelFreshness);
        traceRow.TRSFrequencyTrackingState = char(frequencyState);
        traceRow.TRSTimingTrackingState = char(timingState);
        traceRow.TRSTimingEstimateAvailable = logical(timingAvailable);
        traceRow.TRSTimingEstimate_samples = double(timingEstimate);
        traceRow.TRSCFOEstimateAvailable = logical(cfoAvailable);
        traceRow.TRSEstimatedCFO_Hz = double(estimatedCFOHz);
        traceRow.TRSEstimatedOscillatorCFO_Hz = double(estimatedCFOHz);
        traceRow.TRSEstimatedCommonFrequency_Hz = double(estimatedCommonFrequencyHz);
        traceRow.TRSPhysicalDoppler_Hz = double(physicalDopplerHz);
        traceRow.TRSRuntimeEvidenceSource = char(string(evidenceSource));
        traceRow.Frame = double(frameIdx);
        traceRow.Slot = double(slotIdx);
        traceRow.MeasurementSFNSlot = sprintf("frame=%g,slot=%g", frameIdx, slotIdx);
        traceRow.EstimatedDopplerHz = double(estDopplerHz);
        traceRow.NMSE_dB = double(nmse);
        traceRow.PhaseError_deg = double(phaseErr);
        traceRow.QCLAccuracy = double(qclAccuracy);
        traceRow.DetectionMetric = double(detectionMetric);
        traceRow.SourceArtifact = "air_interface/csv/trs_trials.csv";
        state.ReceiverTrackingTraceTable = sixgr.truth.CoupledTruthRuntime.appendCompatTable( ...
            sixgr.util.structGet(state, "ReceiverTrackingTraceTable", table()), ...
            struct2table(traceRow, "AsArray", true));
    end

    function state = updateReceiverTrackingFreshnessImpl(state, servingCell, validityState)
        if servingCell < 1 || servingCell > numel(sixgr.util.structGet(state, "ReceiverTrackingStateByCell", repmat(struct(), 0, 1)))
            return;
        end
        tracked = state.ReceiverTrackingStateByCell(servingCell);
        if ~logical(sixgr.util.structGet(tracked, "TRSProcessed", false))
            return;
        end
        validityState = lower(strtrim(string(validityState)));
        if validityState == "valid"
            tracked.TrackingState = "valid";
            tracked.TRSTrackingStateAfter = "valid";
            tracked.ChannelTrackingFreshnessState = "fresh_trs_runtime_observation";
        elseif validityState == "stale"
            tracked.TrackingState = "stale";
            tracked.TRSTrackingStateAfter = "stale";
            tracked.ChannelTrackingFreshnessState = "stale_trs_runtime_observation";
            tracked.TRSUpdateOutcome = "stale_age_exceeded";
        elseif validityState == "failed"
            tracked.TrackingState = "failed";
            tracked.TRSTrackingStateAfter = "failed";
            tracked.ChannelTrackingFreshnessState = "invalid_trs_runtime_observation";
        end
        state.ReceiverTrackingStateByCell(servingCell) = tracked;
    end

    function [state, grant, allowExecution] = applyPDCCHGrantTrialImpl(state, grant, direction, trialT)
        direction = upper(string(direction));
        ueIdx = double(sixgr.util.structGet(grant, "UEIndex", NaN));
        if ~(isfinite(ueIdx) && ueIdx >= 1 && ueIdx <= double(state.NumUsers))
            allowExecution = true;
            return;
        end
        gatingActive = logical(sixgr.util.structGet(state.ControlGating, "PDCCHRequired", false));
        [pdcchOk, pdcchReason] = sixgr.truth.CoupledTruthRuntime.pdcchCausalGrantDecodePassed(trialT);
        pdcchRow = table();
        if istable(trialT) && ~isempty(trialT)
            pdcchRow = trialT(end, :);
        end
        dciCrcPass = sixgr.truth.CoupledTruthRuntime.rowLogical(pdcchRow, "DCICrcPass", pdcchOk);
        payloadMatch = sixgr.truth.CoupledTruthRuntime.rowLogical(pdcchRow, "PDCCHPayloadMatch", pdcchOk);
        missedDetection = sixgr.truth.CoupledTruthRuntime.rowLogical(pdcchRow, "PDCCHMissedDetection", ~pdcchOk);
        falseAlarm = sixgr.truth.CoupledTruthRuntime.rowLogical(pdcchRow, "PDCCHFalseAlarm", false);
        blindSearch = sixgr.truth.CoupledTruthRuntime.rowLogical(pdcchRow, "PDCCHBlindSearchEnabled", false);
        regMapping = sixgr.truth.CoupledTruthRuntime.rowLogical(pdcchRow, "PDCCHREGMappingAvailable", false);
        grantValid = sixgr.truth.CoupledTruthRuntime.rowLogical(pdcchRow, "GrantValid", pdcchOk);
        negativeExpectedOk = sixgr.truth.CoupledTruthRuntime.rowLogical(pdcchRow, "NegativeExpectedOk", false);
        ok = ~gatingActive || pdcchOk;
        grant.PDCCHGatingActive = gatingActive;
        grant.ControlDecodeOk = logical(ok);
        grant.PDCCHCausalGrantDecodeOk = logical(pdcchOk);
        grant.DCICrcPass = logical(dciCrcPass);
        grant.PDCCHPayloadMatch = logical(payloadMatch);
        grant.PDCCHMissedDetection = logical(missedDetection);
        grant.PDCCHFalseAlarm = logical(falseAlarm);
        grant.PDCCHBlindSearchEnabled = logical(blindSearch);
        grant.PDCCHREGMappingAvailable = logical(regMapping);
        grant.GrantValid = logical(grantValid || pdcchOk);
        grant.NegativeExpectedOk = logical(negativeExpectedOk);
        grant.PDCCHControlFailureReason = char(string(pdcchReason));
        grant.PDCCHControlEvidenceSource = "pdcch_waveform_dci_crc_and_payload_match";
        if gatingActive
            if ok
                grant.GrantControlState = "control_ok";
                grant.ControlDecodeSource = "pdcch_waveform_dci_crc_and_payload_match";
                state.LastPDCCHStatus(ueIdx) = "control_ok";
                state.LastSuccessfulPDCCHSlotByUE(ueIdx) = double(sixgr.util.structGet(grant, "Slot", state.CurrentSlot));
                state = sixgr.truth.CoupledTruthRuntime.recordInitialAccessEvent(state, ueIdx, "PDCCH_DCI_DECODED", direction, ...
                    "control/csv/pdcch_trials.csv", "PDCCH", double(sixgr.util.structGet(grant, "Slot", state.CurrentSlot)), ...
                    "slot_coupled_grant_pdcch_decode_observation", ...
                    "PDCCH DCI decode observed for a scheduler grant in the coupled runtime.");
            else
                grant.GrantControlState = "control_failed";
                grant.ControlDecodeSource = "pdcch_waveform_dci_crc_and_payload_rejected";
                state.LastPDCCHStatus(ueIdx) = "control_failed";
                state.PDCCHFailureCount(ueIdx) = double(state.PDCCHFailureCount(ueIdx)) + 1;
                state.GrantsBlockedByGatingCount(ueIdx) = double(state.GrantsBlockedByGatingCount(ueIdx)) + 1;
            end
        else
            grant.GrantControlState = "control_not_required";
            state.LastPDCCHStatus(ueIdx) = "control_not_required";
        end
        state = sixgr.truth.CoupledTruthRuntime.updateGrantControlTrace(state, grant, direction);
        allowExecution = logical(ok);
    end

    function [state, grant] = blockPDCCHGrantTrialImpl(state, grant, direction, reason)
        direction = upper(string(direction));
        if nargin < 4 || strlength(strtrim(string(reason))) == 0
            reason = "control_blocked_no_pdcch_runtime_evidence";
        end
        ueIdx = double(sixgr.util.structGet(grant, "UEIndex", NaN));
        grant.PDCCHGatingActive = logical(sixgr.util.structGet(state.ControlGating, "PDCCHRequired", false));
        grant.ControlDecodeOk = false;
        grant.GrantControlState = char(string(reason));
        grant.ControlEligible = false;
        resourceDeferred = any(startsWith(lower(strtrim(string(reason))), ...
            ["control_blocked_coreset_cce_capacity_exhausted", "control_blocked_no_dl_control_symbols_in_tdd_slot"]));
        if isfinite(ueIdx) && ueIdx >= 1 && ueIdx <= double(state.NumUsers)
            state.LastPDCCHStatus(ueIdx) = string(reason);
            if ~resourceDeferred
                state.PDCCHFailureCount(ueIdx) = double(state.PDCCHFailureCount(ueIdx)) + 1;
                state.GrantsBlockedByGatingCount(ueIdx) = double(state.GrantsBlockedByGatingCount(ueIdx)) + 1;
            end
        end
        state = sixgr.truth.CoupledTruthRuntime.updateGrantControlTrace(state, grant, direction);
    end

    function state = recordInitialAccessGrantCompletion(state, ueIdx, direction, row)
        direction = upper(string(direction));
        if ~(isfinite(double(ueIdx)) && ueIdx >= 1 && ueIdx <= double(sixgr.util.structGet(state, "NumUsers", 0)))
            return;
        end
        if ~sixgr.truth.CoupledTruthRuntime.trialPassed(row)
            return;
        end
        msg3Enabled = logical(sixgr.util.structGet(state.CfgMobility, "phy.prach.enable", false)) && ...
            logical(sixgr.util.structGet(state.CfgMobility, "random_access.msg3_enabled", ...
            sixgr.util.structGet(state.CfgMobility, "pusch.msg3_flag", true)));
        if ~msg3Enabled
            return;
        end
        slotIdx = double(sixgr.truth.CoupledTruthRuntime.rowValue(row, "Slot", sixgr.util.structGet(state, "CurrentSlot", NaN)));
        if direction == "UL"
            if sixgr.truth.CoupledTruthRuntime.hasInitialAccessEvent(state, ueIdx, "PRACH_MSG1_DETECTED") && ...
                    sixgr.truth.CoupledTruthRuntime.hasInitialAccessEvent(state, ueIdx, "PDCCH_DCI_DECODED") && ...
                    ~sixgr.truth.CoupledTruthRuntime.hasInitialAccessEvent(state, ueIdx, "MSG3_PUSCH_COMPLETED")
                state = sixgr.truth.CoupledTruthRuntime.recordInitialAccessEvent(state, ueIdx, "MSG3_PUSCH_COMPLETED", "UL", ...
                    "air_interface/csv/ul_pusch_trials.csv", "PUSCH", slotIdx, ...
                    "slot_coupled_successful_ul_grant_after_prach_and_pdcch", ...
                    "Msg3 is materialized as the first successful UL PUSCH grant after PRACH success and grant-coupled PDCCH decode in the slot-coupled runtime.");
            end
        elseif direction == "DL"
            if sixgr.truth.CoupledTruthRuntime.hasInitialAccessEvent(state, ueIdx, "MSG3_PUSCH_COMPLETED") && ...
                    ~sixgr.truth.CoupledTruthRuntime.hasInitialAccessEvent(state, ueIdx, "MSG4_PDSCH_COMPLETED")
                state = sixgr.truth.CoupledTruthRuntime.recordInitialAccessEvent(state, ueIdx, "MSG4_PDSCH_COMPLETED", "DL", ...
                    "air_interface/csv/dl_pdsch_trials.csv", "PDSCH", slotIdx, ...
                    "slot_coupled_successful_dl_grant_after_msg3", ...
                    "Msg4 is materialized as the first successful DL PDSCH grant after Msg3 completion in the slot-coupled runtime.");
            end
        end
    end

    function state = recordInitialAccessEvent(state, ueIdx, eventName, direction, sourceArtifact, stageName, slotIdx, valueSource, notes)
        if ~(isfield(state, "InitialAccessLifecycleTraceTable") && istable(state.InitialAccessLifecycleTraceTable))
            state.InitialAccessLifecycleTraceTable = struct2table(repmat(sixgr.truth.CoupledTruthRuntime.emptyInitialAccessLifecycleRow(), 0, 1));
        end
        eventName = upper(strtrim(string(eventName)));
        direction = upper(strtrim(string(direction)));
        if sixgr.truth.CoupledTruthRuntime.hasInitialAccessEvent(state, ueIdx, eventName)
            return;
        end
        row = sixgr.truth.CoupledTruthRuntime.emptyInitialAccessLifecycleRow();
        row.Step = double(height(state.InitialAccessLifecycleTraceTable) + 1);
        row.UEIndex = double(ueIdx);
        row.RNTI = double(max(1, round(double(state.MultiUser.RNTIStart + ueIdx - 1))));
        row.ServingCell = double(sixgr.truth.CoupledTruthRuntime.numericStateAt(state, "CurrentServingIdx", ueIdx, NaN));
        row.Frame = double(sixgr.util.structGet(state, "CurrentFrame", NaN));
        row.Slot = double(slotIdx);
        row.Time_s = max(0, double(slotIdx) - 1) * double(sixgr.util.structGet(state, "SlotDuration_s", NaN));
        row.Direction = char(direction);
        row.StageName = char(string(stageName));
        row.EventName = char(eventName);
        row.LifecycleState = char(eventName);
        row.StageStatus = 'PASS';
        row.SourceArtifact = char(string(sourceArtifact));
        row.SourceRow = NaN;
        row.ValueSource = char(string(valueSource));
        row.ValueRole = 'measured_runtime_procedure_event';
        row.ValueStatus = 'available_runtime_observation';
        row.ValueDefinition = 'initial-access event timestamp recorded from the slot-coupled runtime evidence path';
        row.SlotDuration_s = double(sixgr.util.structGet(state, "SlotDuration_s", NaN));
        row.ProcedureStartSlot = NaN;
        row.ProcedureEndSlot = NaN;
        row.ProcedureDelay_ms = NaN;
        row.AccessDelay_ms = NaN;
        row.CompleteFlag = false;
        row.PlaceholderFlag = false;
        row.FallbackFlag = false;
        row.UnavailableReason = '';
        row.Notes = char(string(notes));
        state.InitialAccessLifecycleTraceTable = sixgr.truth.CoupledTruthRuntime.appendCompatTable( ...
            state.InitialAccessLifecycleTraceTable, struct2table(row, "AsArray", true));
        state = sixgr.truth.CoupledTruthRuntime.finalizeInitialAccessLifecycleIfReady(state, ueIdx);
    end

    function state = finalizeInitialAccessLifecycleIfReady(state, ueIdx)
        if sixgr.truth.CoupledTruthRuntime.hasInitialAccessEvent(state, ueIdx, "INITIAL_ACCESS_COMPLETE")
            return;
        end
        required = ["SSB_DETECTED","PBCH_DECODED","PRACH_MSG1_DETECTED","PDCCH_DCI_DECODED","MSG3_PUSCH_COMPLETED","MSG4_PDSCH_COMPLETED"];
        for i = 1:numel(required)
            if ~sixgr.truth.CoupledTruthRuntime.hasInitialAccessEvent(state, ueIdx, required(i))
                return;
            end
        end
        T = state.InitialAccessLifecycleTraceTable;
        ueMask = double(T.UEIndex) == double(ueIdx);
        eventNames = upper(strtrim(string(T.EventName)));
        slots = double(T.Slot);
        startSlots = slots(ueMask & ismember(eventNames, ["SSB_DETECTED","PBCH_DECODED"]));
        endSlots = slots(ueMask & eventNames == "MSG4_PDSCH_COMPLETED");
        if isempty(startSlots) || isempty(endSlots) || ~all(isfinite([startSlots(:); endSlots(:)]))
            return;
        end
        startSlot = min(startSlots);
        endSlot = max(endSlots);
        slotDuration_s = double(sixgr.util.structGet(state, "SlotDuration_s", NaN));
        if ~(isfinite(slotDuration_s) && slotDuration_s > 0)
            return;
        end
        delayMs = max(0, (endSlot - startSlot + 1) * slotDuration_s * 1e3);
        row = sixgr.truth.CoupledTruthRuntime.emptyInitialAccessLifecycleRow();
        row.Step = double(height(T) + 1);
        row.UEIndex = double(ueIdx);
        row.RNTI = double(max(1, round(double(state.MultiUser.RNTIStart + ueIdx - 1))));
        row.ServingCell = double(sixgr.truth.CoupledTruthRuntime.numericStateAt(state, "CurrentServingIdx", ueIdx, NaN));
        row.Frame = double(sixgr.util.structGet(state, "CurrentFrame", NaN));
        row.Slot = double(endSlot);
        row.Time_s = max(0, double(endSlot) - 1) * slotDuration_s;
        row.Direction = 'DL';
        row.StageName = 'INITIAL_ACCESS';
        row.EventName = 'INITIAL_ACCESS_COMPLETE';
        row.LifecycleState = 'CONNECTED';
        row.StageStatus = 'PASS';
        row.SourceArtifact = 'control/csv/pbch_trials.csv|control/csv/prach_trials.csv|control/csv/pdcch_trials.csv|air_interface/csv/ul_pusch_trials.csv|air_interface/csv/dl_pdsch_trials.csv';
        row.SourceRow = NaN;
        row.ValueSource = 'slot_coupled_runtime_initial_access_lifecycle';
        row.ValueRole = 'measured_runtime_procedure_delay';
        row.ValueStatus = 'available_runtime_procedure_sample';
        row.ValueDefinition = 'SSB/PBCH through PRACH/PDCCH/Msg3/Msg4 access delay from slot-coupled runtime event timestamps';
        row.SlotDuration_s = slotDuration_s;
        row.ProcedureStartSlot = double(startSlot);
        row.ProcedureEndSlot = double(endSlot);
        row.ProcedureDelay_ms = double(delayMs);
        row.AccessDelay_ms = double(delayMs);
        row.CompleteFlag = true;
        row.PlaceholderFlag = false;
        row.FallbackFlag = false;
        row.UnavailableReason = '';
        row.Notes = 'Finite delay sample uses only slot-coupled runtime event timestamps; compute runtime and independent signal-bundle trials are not substituted.';
        state.InitialAccessLifecycleTraceTable = sixgr.truth.CoupledTruthRuntime.appendCompatTable(T, struct2table(row, "AsArray", true));
    end

    function tf = hasInitialAccessEvent(state, ueIdx, eventName)
        tf = false;
        if ~(isfield(state, "InitialAccessLifecycleTraceTable") && istable(state.InitialAccessLifecycleTraceTable) && ~isempty(state.InitialAccessLifecycleTraceTable))
            return;
        end
        T = state.InitialAccessLifecycleTraceTable;
        if ~(ismember("UEIndex", string(T.Properties.VariableNames)) && ismember("EventName", string(T.Properties.VariableNames)))
            return;
        end
        tf = any(double(T.UEIndex) == double(ueIdx) & upper(strtrim(string(T.EventName))) == upper(strtrim(string(eventName))));
    end

    function feedback = latestFeedbackForDirection(state, ueIdx, direction)
        direction = upper(string(direction));
        if direction == "UL"
            if ueIdx >= 1 && ueIdx <= numel(state.LatestULFeedback)
                feedback = state.LatestULFeedback(ueIdx);
            else
                feedback = sixgr.truth.CoupledTruthRuntime.emptyLatestFeedbackRow();
            end
        else
            if ueIdx >= 1 && ueIdx <= numel(state.LatestDLFeedback)
                feedback = state.LatestDLFeedback(ueIdx);
            else
                feedback = sixgr.truth.CoupledTruthRuntime.emptyLatestFeedbackRow();
            end
        end
        if logical(sixgr.util.structGet(feedback, "Valid", false))
            return;
        end
        feedback = sixgr.truth.CoupledTruthRuntime.bootstrapFeedbackFromConfig(state, direction, ueIdx);
    end

    function feedback = bootstrapFeedbackFromConfig(state, direction, ueIdx)
        direction = upper(string(direction));
        feedback = sixgr.truth.CoupledTruthRuntime.emptyLatestFeedbackRow();
        feedback.Direction = char(direction);
        feedback.Valid = false;
        if ueIdx >= 1 && ueIdx <= numel(state.CurrentServingIdx)
            feedback.ServingCell = double(state.CurrentServingIdx(ueIdx));
        end
        linkAdaptationMode = lower(string(sixgr.util.structGet(state.CfgMobility, "phy.linkAdaptation.mode", "fixed")));
        fixedAdaptation = ismember(linkAdaptationMode, ["fixed","fixed_mcs","configured_fixed","disabled","off","none","false"]);
        modulation = "";
        targetCodeRate = NaN;
        mcsIndex = NaN;
        if direction == "UL"
            rankHint = double(sixgr.util.structGet(state.CfgMobility, "phy.pusch.nLayers", ...
                sixgr.util.structGet(state.CfgMobility, "phy.pusch.numLayers", 1)));
            if fixedAdaptation
                modulation = string(sixgr.util.structGet(state.CfgMobility, "phy.pusch.modulation", "QPSK"));
                targetCodeRate = double(sixgr.util.structGet(state.CfgMobility, "phy.pusch.codeRate", 0.5));
                mcsIndex = double(sixgr.util.structGet(state.CfgMobility, "phy.pusch.mcsIndex", NaN));
            end
        else
            rankHint = double(sixgr.util.structGet(state.CfgMobility, "phy.pdsch.nLayers", ...
                sixgr.util.structGet(state.CfgMobility, "phy.pdsch.numLayers", 1)));
            if fixedAdaptation
                modulation = string(sixgr.util.structGet(state.CfgMobility, "phy.pdsch.modulation", "QPSK"));
                targetCodeRate = double(sixgr.util.structGet(state.CfgMobility, "phy.pdsch.codeRate", 0.5));
                mcsIndex = double(sixgr.util.structGet(state.CfgMobility, "phy.pdsch.mcsIndex", NaN));
            end
        end
        mcsTable = sixgr.link.resolveConfiguredMCSTable(state.CfgMobility, direction);
        if fixedAdaptation && ~(isfinite(mcsIndex) && mcsIndex >= 0)
            fallbackProfile = sixgr.link.resolveMCSProfile(mcsTable, 0);
            if fallbackProfile.Valid
                mcsIndex = 0;
                modulation = string(fallbackProfile.Modulation);
                targetCodeRate = double(fallbackProfile.TargetCodeRate);
            end
        end
        schedulerUsesCQITable = sixgr.truth.CoupledTruthRuntime.schedulerUsesCQITableForDirection(state.CfgMobility, direction);
        if schedulerUsesCQITable
            feedback = sixgr.truth.CoupledTruthRuntime.bootstrapCQIFeedbackFromRuntimePreview( ...
                state, direction, ueIdx, mcsTable, feedback, rankHint);
        else
            feedback.CQI = 0;
            feedback.SINR_dB = NaN;
            feedback.Modulation = char(modulation);
            feedback.TargetCodeRate = double(targetCodeRate);
            feedback.MCSIndex = double(mcsIndex);
        end
        bootstrapCQIUsable = logical(sixgr.util.structGet(feedback, "BootstrapCQIUsableForScheduling", false));
        bootstrapCQISource = lower(strtrim(string(sixgr.util.structGet(feedback, "BootstrapCQISource", ""))));
        bootstrapRankUsable = logical(sixgr.util.structGet(feedback, ...
            "BootstrapRankUsableForScheduling", false));
        estimatedBootstrapRankUsable = bootstrapCQIUsable && bootstrapRankUsable && ...
            any(bootstrapCQISource == ["bootstrap_estimated_runtime_preview_cqi", "estimated_runtime_preview_cqi"]);
        if schedulerUsesCQITable && ~logical(sixgr.util.structGet(feedback, "Valid", false)) && ~estimatedBootstrapRankUsable
            % Before measured RI is available, keep bootstrap rank
            % conservative and explicit instead of inheriting configured
            % multi-layer study settings as if they were measured feedback.
            feedback.RI = 1;
        else
            feedback.RI = max(1, round(rankHint));
        end
        feedback.PMI = double(sixgr.truth.CoupledTruthRuntime.resolveFallbackPMI(state.CfgMobility, direction, feedback.RI));
        feedback.CRI = double(sixgr.truth.CoupledTruthRuntime.resolveFallbackCRI(state.CfgMobility));
    end

    function feedback = bootstrapCQIFeedbackFromRuntimePreview(state, direction, ueIdx, mcsTable, feedback, rankHint)
        bootstrapMode = lower(strtrim(string(sixgr.util.structGet(state.CfgMobility, "phy.linkAdaptation.bootstrapCQIMode", ""))));
        useLargeScalePreview = any(bootstrapMode == [ ...
            "estimated", ...
            "estimate", ...
            "runtime_estimated", ...
            "large_scale_preview", ...
            "large_scale_preview_lab_default", ...
            "large_scale_preview_cqi_lab_default"]);
        previewSource = "bootstrap_large_scale_interference_preview_cqi";
        if any(bootstrapMode == ["estimated", "estimate", "runtime_estimated"])
            previewSource = "bootstrap_estimated_runtime_preview_cqi";
        end
        previewSINR_dB = NaN;
        adjustedPreviewSINR_dB = NaN;
        previewCQI = NaN;
        previewMCSIndex = NaN;
        previewModulation = "";
        previewTargetCodeRate = NaN;
        if upper(string(direction)) == "UL"
            minBootstrapCQIForScheduling = double(sixgr.truth.CoupledTruthRuntime.firstFiniteScalar( ...
                sixgr.util.structGet(state.CfgMobility, "phy.linkAdaptation.ulBootstrapMinCQIForScheduling", NaN), ...
                sixgr.util.structGet(state.CfgMobility, "phy.linkAdaptation.bootstrapMinCQIForScheduling", NaN), ...
                1));
        else
            minBootstrapCQIForScheduling = double(sixgr.truth.CoupledTruthRuntime.firstFiniteScalar( ...
                sixgr.util.structGet(state.CfgMobility, "phy.linkAdaptation.dlBootstrapMinCQIForScheduling", NaN), ...
                sixgr.util.structGet(state.CfgMobility, "phy.linkAdaptation.bootstrapMinCQIForScheduling", NaN), ...
                1));
        end
        if ~(isfinite(minBootstrapCQIForScheduling) && minBootstrapCQIForScheduling >= 1)
            minBootstrapCQIForScheduling = 1;
        end
        minBootstrapCQIForScheduling = max(1, min(15, round(double(minBootstrapCQIForScheduling))));
        if upper(string(direction)) == "UL"
            bootstrapPreviewBackoff_dB = double(sixgr.truth.CoupledTruthRuntime.firstFiniteScalar( ...
                sixgr.util.structGet(state.CfgMobility, "phy.linkAdaptation.ulBootstrapPreviewBackoff_dB", NaN), ...
                sixgr.util.structGet(state.CfgMobility, "phy.linkAdaptation.bootstrapPreviewBackoff_dB", NaN), ...
                0));
        else
            bootstrapPreviewBackoff_dB = double(sixgr.truth.CoupledTruthRuntime.firstFiniteScalar( ...
                sixgr.util.structGet(state.CfgMobility, "phy.linkAdaptation.dlBootstrapPreviewBackoff_dB", NaN), ...
                sixgr.util.structGet(state.CfgMobility, "phy.linkAdaptation.bootstrapPreviewBackoff_dB", NaN), ...
                0));
        end
        if ~(isfinite(bootstrapPreviewBackoff_dB) && bootstrapPreviewBackoff_dB >= 0)
            bootstrapPreviewBackoff_dB = 0;
        end

        if useLargeScalePreview
            servingCell = NaN;
            if ueIdx >= 1 && ueIdx <= numel(state.CurrentServingIdx)
                servingCell = double(state.CurrentServingIdx(ueIdx));
            end
            try
                interferenceMode = sixgr.truth.CoupledTruthRuntime.resolveInterferenceExecutionMode(state.CfgMobility, state.MultiUser);
                previewSINR_dB = double(sixgr.truth.CoupledTruthRuntime.estimateRuntimeWidebandSINR( ...
                    state, ueIdx, servingCell, interferenceMode));
            catch
                previewSINR_dB = NaN;
            end
            if isfinite(previewSINR_dB)
                adjustedPreviewSINR_dB = double(previewSINR_dB) - double(bootstrapPreviewBackoff_dB);
                cqiFeedback = sixgr.link.resolveWidebandCQI(struct("WidebandSINR_dB", adjustedPreviewSINR_dB), state.CfgMobility, direction);
                previewCQI = double(sixgr.util.structGet(cqiFeedback, "WidebandCQI", NaN));
                if isfinite(previewCQI) && previewCQI > 0
                    [modStr, targetCodeRate, mcsIndex] = sixgr.link.amcFromCQI(previewCQI, "", NaN, state.CfgMobility, direction);
                    previewMCSIndex = double(mcsIndex);
                    previewModulation = char(string(modStr));
                    previewTargetCodeRate = double(targetCodeRate);
                end
            end
        end

        if useLargeScalePreview
            bootstrapMCS = max(0, round(double(sixgr.util.structGet(state.CfgMobility, ...
                "phy.linkAdaptation.bootstrapMCSIndex", 1))));
        else
            bootstrapMCS = 0;
        end
        bootstrapProfile = sixgr.link.resolveMCSProfile(mcsTable, bootstrapMCS);
        feedback.CQI = 0;
        feedback.SINR_dB = NaN;
        if bootstrapProfile.Valid
            feedback.Modulation = char(string(bootstrapProfile.Modulation));
            feedback.TargetCodeRate = double(bootstrapProfile.TargetCodeRate);
            feedback.MCSIndex = double(bootstrapMCS);
        else
            feedback.Modulation = "QPSK";
            feedback.TargetCodeRate = 0.1171875;
            feedback.MCSIndex = 1;
        end
        feedback.BootstrapCQIUsableForScheduling = false;
        feedback.BootstrapRankUsableForScheduling = false;
        feedback.BootstrapCQISource = "bootstrap_cqi_conservative_lab_default";
        feedback.PreviewSINR_dB = double(previewSINR_dB);
        feedback.AdjustedPreviewSINR_dB = double(adjustedPreviewSINR_dB);
        feedback.BootstrapPreviewBackoff_dB = double(bootstrapPreviewBackoff_dB);
        feedback.PreviewCQI = double(previewCQI);
        feedback.PreviewMCSIndex = double(previewMCSIndex);
        feedback.PreviewModulation = char(string(previewModulation));
        feedback.PreviewTargetCodeRate = double(previewTargetCodeRate);
        feedback.BootstrapMinCQIForScheduling = double(minBootstrapCQIForScheduling);
        feedback.BootstrapCQIAdmissionStatus = "not_applicable";
        if isfinite(previewCQI) && previewCQI > 0
            feedback.PreviewCQISource = char(previewSource);
            if double(previewCQI) >= double(minBootstrapCQIForScheduling)
                feedback.CQI = double(previewCQI);
                feedback.Modulation = char(string(previewModulation));
                feedback.TargetCodeRate = double(previewTargetCodeRate);
                feedback.MCSIndex = double(previewMCSIndex);
                feedback.BootstrapCQIUsableForScheduling = true;
                feedback.BootstrapCQISource = char(previewSource);
                feedback.BootstrapCQIAdmissionStatus = "admitted";
                if any(previewSource == ["bootstrap_estimated_runtime_preview_cqi", "estimated_runtime_preview_cqi"])
                    minRank2SINR = double(sixgr.util.structGet(state.CfgMobility, ...
                        "phy.linkAdaptation.minSINRForRank2_dB", 5));
                    feedback.BootstrapRankUsableForScheduling = ...
                        isfinite(adjustedPreviewSINR_dB) && adjustedPreviewSINR_dB >= minRank2SINR;
                end
            else
                feedback.BootstrapCQIAdmissionStatus = "rejected_below_min_cqi_for_scheduling";
                feedback.BootstrapCQISource = char(previewSource);
            end
        else
            feedback.PreviewCQISource = "";
            feedback.BootstrapCQIAdmissionStatus = "no_positive_preview_cqi";
        end
        feedback.RI = 1;
    end

    function pmi = resolveFallbackPMI(cfg, direction, rankHint)
        pmi = NaN;
        direction = upper(string(direction));
        if direction == "UL"
            [nLayers, numTxPorts, transformPrecoding] = sixgr.truth.CoupledTruthRuntime.resolveULPUSCHCodebookTuple(cfg, rankHint);
            pmiCfg = sixgr.truth.CoupledTruthRuntime.firstFiniteScalar( ...
                sixgr.util.structGet(cfg, "phy.pusch.TPMI", NaN), ...
                sixgr.util.structGet(cfg, "phy.pusch.PMI", NaN));
            if sixgr.truth.CoupledTruthRuntime.isValidULTPMI(pmiCfg, nLayers, numTxPorts, transformPrecoding)
                pmi = double(round(double(pmiCfg)));
                return;
            end
            pmi = sixgr.truth.CoupledTruthRuntime.firstValidULTPMI(nLayers, numTxPorts, transformPrecoding);
            return;
        else
            pmiCfg = sixgr.util.structGet(cfg, "phy.pdsch.PMI", NaN);
        end
        pmiCfgValid = isnumeric(pmiCfg) && isscalar(pmiCfg) && isfinite(pmiCfg);
        nLayers = max(1, round(double(rankHint)));
        numTxPorts = sixgr.util.structGet(cfg, "phy.nTxAnt", nLayers);
        numTxPorts = max(1, round(double(numTxPorts)));
        try
            candidates = sixgr.phy.dl.pmiCodebookCandidates(cfg, nLayers, numTxPorts);
            idx = round(double(pmiCfg));
            if pmiCfgValid && idx >= 0 && idx < numel(candidates)
                pmi = double(idx);
            elseif ~isempty(candidates)
                pmi = 0;
            end
        catch
            pmi = NaN;
        end
    end

    function pmi = sanitizeFeedbackPMI(rawPMI, cfg, direction, rankHint)
        pmi = NaN;
        rawPMI = double(rawPMI);
        if isempty(rawPMI)
            rawPMI = NaN;
        else
            rawPMI = rawPMI(1);
        end
        direction = upper(string(direction));
        rankHint = double(rankHint);
        if ~(isscalar(rankHint) && isfinite(rankHint) && rankHint >= 1)
            if direction == "UL"
                rankHint = double(sixgr.util.structGet(cfg, "phy.pusch.nLayers", ...
                    sixgr.util.structGet(cfg, "phy.pusch.numLayers", 1)));
            else
                rankHint = double(sixgr.util.structGet(cfg, "phy.pdsch.nLayers", ...
                    sixgr.util.structGet(cfg, "phy.pdsch.numLayers", 1)));
            end
        end
        nLayers = max(1, round(double(rankHint)));
        if direction == "UL"
            [~, numTxPorts, transformPrecoding] = sixgr.truth.CoupledTruthRuntime.resolveULPUSCHCodebookTuple(cfg, nLayers);
            if sixgr.truth.CoupledTruthRuntime.isValidULTPMI(rawPMI, nLayers, numTxPorts, transformPrecoding)
                pmi = double(round(rawPMI));
                return;
            end
            pmi = double(sixgr.truth.CoupledTruthRuntime.resolveFallbackPMI(cfg, direction, nLayers));
            return;
        end
        numTxPorts = sixgr.util.structGet(cfg, "phy.nTxAnt", nLayers);
        numTxPorts = max(1, round(double(numTxPorts)));
        try
            candidates = sixgr.phy.dl.pmiCodebookCandidates(cfg, nLayers, numTxPorts);
        catch
            candidates = struct([]);
        end
        if isempty(candidates)
            return;
        end
        if isfinite(rawPMI)
            idx = round(rawPMI);
            if idx >= 0 && idx < numel(candidates)
                pmi = double(idx);
                return;
            end
        end
        pmi = double(sixgr.truth.CoupledTruthRuntime.resolveFallbackPMI(cfg, direction, nLayers));
    end

    function [nLayers, numTxPorts, transformPrecoding] = resolveULPUSCHCodebookTuple(cfg, rankHint)
        transformPrecoding = logical(sixgr.util.structGet(cfg, "phy.pusch.transformPrecoding", false));
        nLayers = double(rankHint);
        if ~(isscalar(nLayers) && isfinite(nLayers) && nLayers >= 1)
            nLayers = double(sixgr.util.structGet(cfg, "phy.pusch.nLayers", ...
                sixgr.util.structGet(cfg, "phy.pusch.numLayers", 1)));
        end
        if ~(isscalar(nLayers) && isfinite(nLayers) && nLayers >= 1)
            nLayers = 1;
        end
        nLayers = max(1, round(double(nLayers)));

        numTxPorts = sixgr.truth.CoupledTruthRuntime.firstFiniteScalar( ...
            sixgr.util.structGet(cfg, "phy.pusch.NumAntennaPorts", NaN), ...
            sixgr.util.structGet(cfg, "phy.pusch.numAntennaPorts", NaN), ...
            sixgr.util.structGet(cfg, "phy.pusch.dmrs.nPorts", NaN), ...
            sixgr.util.structGet(cfg, "phy.pusch.nPorts", NaN), ...
            nLayers);
        allowedPorts = [1 2 4];
        numTxPorts = max(1, round(double(numTxPorts)));
        if ~ismember(numTxPorts, allowedPorts)
            idx = find(allowedPorts >= numTxPorts, 1, "first");
            if isempty(idx)
                idx = numel(allowedPorts);
            end
            numTxPorts = allowedPorts(idx);
        end
        if numTxPorts < nLayers
            idx = find(allowedPorts >= nLayers, 1, "first");
            if isempty(idx)
                idx = numel(allowedPorts);
            end
            numTxPorts = allowedPorts(idx);
        end
        nLayers = min(nLayers, numTxPorts);
    end

    function tf = isValidULTPMI(rawPMI, nLayers, numTxPorts, transformPrecoding)
        tf = false;
        try
            rawPMI = double(rawPMI);
        catch
            return;
        end
        if ~(isscalar(rawPMI) && isfinite(rawPMI))
            return;
        end
        if logical(transformPrecoding)
            return;
        end
        if exist("nrPUSCHCodebook", "file") ~= 2
            return;
        end
        try
            W = nrPUSCHCodebook(max(1, round(double(nLayers))), max(1, round(double(numTxPorts))), ...
                round(double(rawPMI)), logical(transformPrecoding));
        catch
            try
                W = nrPUSCHCodebook(max(1, round(double(nLayers))), max(1, round(double(numTxPorts))), ...
                    round(double(rawPMI)));
            catch
                W = [];
            end
        end
        tf = ~isempty(W);
    end

    function pmi = firstValidULTPMI(nLayers, numTxPorts, transformPrecoding)
        pmi = NaN;
        if logical(transformPrecoding) || exist("nrPUSCHCodebook", "file") ~= 2
            return;
        end
        for candidate = 0:255
            if sixgr.truth.CoupledTruthRuntime.isValidULTPMI(candidate, nLayers, numTxPorts, transformPrecoding)
                pmi = double(candidate);
                return;
            end
        end
    end

    function cri = sanitizeFeedbackCRI(rawCRI, cfg)
        cri = NaN;
        rawCRI = double(rawCRI);
        if isempty(rawCRI)
            return;
        end
        rawCRI = rawCRI(1);
        if ~(isscalar(rawCRI) && isfinite(rawCRI))
            return;
        end
        numCandidates = sixgr.util.structGet(cfg, "phy.csi.numResourceCandidates", ...
            sixgr.util.structGet(cfg, "phy.csirs.numResources", ...
            sixgr.util.structGet(cfg, "phy.beamManagement.trpCount", 1)));
        numCandidates = max(1, round(double(numCandidates)));
        idx = round(double(rawCRI));
        if idx >= 0 && idx < numCandidates
            cri = double(idx);
        end
    end

    function cri = resolveFallbackCRI(cfg)
        cri = NaN;
        criCfg = sixgr.util.structGet(cfg, "phy.csi.selectedCRI", ...
            sixgr.util.structGet(cfg, "phy.beamManagement.selectedCRI", NaN));
        if ~(isnumeric(criCfg) && isscalar(criCfg) && isfinite(criCfg))
            return;
        end
        numCandidates = sixgr.util.structGet(cfg, "phy.csi.numResourceCandidates", ...
            sixgr.util.structGet(cfg, "phy.csirs.numResources", ...
            sixgr.util.structGet(cfg, "phy.beamManagement.trpCount", 1)));
        numCandidates = max(1, round(double(numCandidates)));
        idx = round(double(criCfg));
        if idx >= 0 && idx < numCandidates
            cri = double(idx);
        end
    end

    function state = reserveGrantBits(state, ueIdx, direction, tbsBits, grant)
        if nargin < 5
            grant = struct();
        end
        tbsBits = max(0, round(double(tbsBits)));
        state = sixgr.truth.CoupledTruthRuntime.allocatePacketSegmentsToGrant(state, ueIdx, direction, tbsBits, grant);
        if upper(string(direction)) == "UL"
            state.ULQueueBits(ueIdx) = max(0, double(state.ULQueueBits(ueIdx)) - tbsBits);
            state.ULTransmittedBits(ueIdx) = double(state.ULTransmittedBits(ueIdx)) + tbsBits;
        else
            state.DLQueueBits(ueIdx) = max(0, double(state.DLQueueBits(ueIdx)) - tbsBits);
            state.DLTransmittedBits(ueIdx) = double(state.DLTransmittedBits(ueIdx)) + tbsBits;
        end
    end

    function state = appendOfferedTrafficPackets(state, direction, absoluteFrame, offeredBits)
        direction = upper(string(direction));
        offeredBits = double(offeredBits(:));
        if isempty(offeredBits)
            return;
        end
        if ~isfield(state, "PacketDeliveryLedgerTable") || ~istable(state.PacketDeliveryLedgerTable)
            state.PacketDeliveryLedgerTable = struct2table(repmat(sixgr.truth.CoupledTruthRuntime.emptyPacketDeliveryLedgerRow(), 0, 1));
        end
        nUsers = min(numel(offeredBits), double(sixgr.util.structGet(state, "NumUsers", numel(offeredBits))));
        slotsPerFrame = max(1, round(double(sixgr.util.structGet(state, "SlotsPerFrame", 10))));
        enqueueFrame = max(1, round(double(absoluteFrame)));
        enqueueSlot = (enqueueFrame - 1) * slotsPerFrame + 1;
        enqueueTime = sixgr.truth.CoupledTruthRuntime.slotStartTimeSec(state, enqueueSlot);
        rows = repmat(sixgr.truth.CoupledTruthRuntime.emptyPacketDeliveryLedgerRow(), 0, 1);
        for ueIdx = 1:nUsers
            bits = max(0, round(double(offeredBits(ueIdx))));
            if bits <= 0
                continue;
            end
            row = sixgr.truth.CoupledTruthRuntime.emptyPacketDeliveryLedgerRow();
            row.Direction = direction;
            row.UEIndex = double(ueIdx);
            row.RNTI = double(max(1, round(double(state.MultiUser.RNTIStart + ueIdx - 1))));
            row.EnqueueFrame = double(enqueueFrame);
            row.EnqueueSlot = double(enqueueSlot);
            row.EnqueueTime_s = double(enqueueTime);
            row.OfferedBits = double(bits);
            row.RemainingBits = double(bits);
            row.PacketId = sixgr.truth.CoupledTruthRuntime.composeRuntimePacketId(state, direction, ueIdx, enqueueFrame);
            row.ApplicationPacketId = row.PacketId;
            row.FlowId = direction + "_ue" + string(ueIdx);
            row.PacketizationSource = "runtime_offered_bits_frame_packet";
            row.Status = "queued";
            row.Notes = "Application packet created from the coupled runtime offered-bit arrival for this frame/UE/direction.";
            rows(end+1, 1) = row; %#ok<AGROW>
        end
        if ~isempty(rows)
            state.PacketDeliveryLedgerTable = sixgr.truth.CoupledTruthRuntime.appendCompatTable( ...
                state.PacketDeliveryLedgerTable, struct2table(rows, "AsArray", true));
        end
    end

    function state = allocatePacketSegmentsToGrant(state, ueIdx, direction, tbsBits, grant)
        direction = upper(string(direction));
        if ~(isfinite(double(ueIdx)) && double(ueIdx) >= 1) || ~(isfinite(double(tbsBits)) && double(tbsBits) > 0)
            return;
        end
        if ~isfield(state, "PacketDeliveryLedgerTable") || ~istable(state.PacketDeliveryLedgerTable) || isempty(state.PacketDeliveryLedgerTable)
            return;
        end
        if ~isfield(state, "PacketSDULedgerTable") || ~istable(state.PacketSDULedgerTable)
            state.PacketSDULedgerTable = struct2table(repmat(sixgr.truth.CoupledTruthRuntime.emptyPacketSDULedgerRow(), 0, 1));
        end
        packetT = state.PacketDeliveryLedgerTable;
        vars = string(packetT.Properties.VariableNames);
        if ~all(ismember(["Direction","UEIndex","RemainingBits","PacketId"], vars))
            return;
        end
        remainingBudget = max(0, round(double(tbsBits)));
        packetMask = upper(string(packetT.Direction)) == direction & ...
            abs(double(packetT.UEIndex) - double(ueIdx)) < 1e-9 & ...
            double(packetT.RemainingBits) > 0 & ~logical(packetT.DeliverySuccess);
        packetIdx = find(packetMask(:).');
        if isempty(packetIdx)
            return;
        end
        tbId = sixgr.truth.CoupledTruthRuntime.transportBlockIdFromGrant(state, grant, direction, ueIdx);
        grantContextId = char(string(sixgr.util.structGet(grant, "GrantContextId", "")));
        harqStruct = sixgr.util.structGet(grant, "HARQ", struct());
        harqId = double(sixgr.util.structGet(harqStruct, "HarqID", NaN));
        ndi = double(sixgr.util.structGet(harqStruct, "NDI", NaN));
        rv = double(sixgr.util.structGet(harqStruct, "RV", NaN));
        schedSlot = double(sixgr.util.structGet(grant, "Slot", sixgr.util.structGet(state, "CurrentSlot", NaN)));
        schedTime = sixgr.truth.CoupledTruthRuntime.slotStartTimeSec(state, schedSlot);
        rnti = double(sixgr.util.structGet(grant, "RNTI", NaN));
        if ~isfinite(rnti)
            rnti = double(max(1, round(double(state.MultiUser.RNTIStart + ueIdx - 1))));
        end
        segRows = repmat(sixgr.truth.CoupledTruthRuntime.emptyPacketSDULedgerRow(), 0, 1);
        for k = 1:numel(packetIdx)
            if remainingBudget <= 0
                break;
            end
            pi = packetIdx(k);
            segBits = min(remainingBudget, max(0, round(double(packetT.RemainingBits(pi)))));
            if segBits <= 0
                continue;
            end
            packetId = string(packetT.PacketId(pi));
            existingSduT = state.PacketSDULedgerTable;
            segmentIndex = 1;
            if istable(existingSduT) && ~isempty(existingSduT) && all(ismember(["Direction","PacketId"], string(existingSduT.Properties.VariableNames)))
                segmentIndex = 1 + sum(upper(string(existingSduT.Direction)) == direction & string(existingSduT.PacketId) == packetId);
            end
            row = sixgr.truth.CoupledTruthRuntime.emptyPacketSDULedgerRow();
            row.Direction = direction;
            row.UEIndex = double(ueIdx);
            row.RNTI = double(rnti);
            row.PacketId = packetId;
            row.ApplicationPacketId = string(packetT.ApplicationPacketId(pi));
            row.MACSDUId = packetId + "_macsdu" + string(segmentIndex);
            row.TransportBlockId = string(tbId);
            row.GrantContextId = string(grantContextId);
            row.HARQProcessId = double(harqId);
            row.NDI = double(ndi);
            row.RV = double(rv);
            row.SegmentIndex = double(segmentIndex);
            row.PayloadBits = double(segBits);
            row.ScheduleSlot = double(schedSlot);
            row.ScheduleTime_s = double(schedTime);
            row.Status = "scheduled_pending_harq";
            row.Notes = "MAC SDU segment mapped from queued application packet bits into a finalized new-data PHY grant.";
            segRows(end+1, 1) = row; %#ok<AGROW>

            packetT.RemainingBits(pi) = max(0, double(packetT.RemainingBits(pi)) - segBits);
            packetT.ScheduledBits(pi) = double(packetT.ScheduledBits(pi)) + segBits;
            packetT.SegmentCount(pi) = double(packetT.SegmentCount(pi)) + 1;
            if ~isfinite(double(packetT.FirstGrantSlot(pi)))
                packetT.FirstGrantSlot(pi) = double(schedSlot);
                packetT.FirstGrantTime_s(pi) = double(schedTime);
            end
            packetT.Status(pi) = "partially_scheduled";
            if double(packetT.RemainingBits(pi)) <= 0
                packetT.Status(pi) = "fully_scheduled_pending_delivery";
            end
            remainingBudget = remainingBudget - segBits;
        end
        state.PacketDeliveryLedgerTable = packetT;
        if ~isempty(segRows)
            state.PacketSDULedgerTable = sixgr.truth.CoupledTruthRuntime.appendCompatTable( ...
                state.PacketSDULedgerTable, struct2table(segRows, "AsArray", true));
        end
    end

    function state = updatePacketDeliveryFromHARQ(state, direction, grant, harqRow)
        direction = upper(string(direction));
        if ~isfield(state, "PacketSDULedgerTable") || ~istable(state.PacketSDULedgerTable) || isempty(state.PacketSDULedgerTable)
            return;
        end
        tbId = sixgr.truth.CoupledTruthRuntime.transportBlockIdFromGrant(state, grant, direction, ...
            double(sixgr.util.structGet(grant, "UEIndex", sixgr.truth.CoupledTruthRuntime.rowValue(harqRow, "UEIndex", NaN))));
        sduT = state.PacketSDULedgerTable;
        mask = upper(string(sduT.Direction)) == direction & string(sduT.TransportBlockId) == string(tbId);
        if ~any(mask)
            return;
        end
        attemptSlot = double(sixgr.truth.CoupledTruthRuntime.rowValue(harqRow, "Slot", NaN));
        feedbackSlot = double(sixgr.truth.CoupledTruthRuntime.rowValue(harqRow, "FeedbackDueSlot", attemptSlot));
        deliveryTime = sixgr.truth.CoupledTruthRuntime.slotStartTimeSec(state, feedbackSlot);
        sduT.HARQAttemptCount(mask) = double(sduT.HARQAttemptCount(mask)) + 1;
        sduT.LastAttemptSlot(mask) = double(attemptSlot);
        sduT.LastRV(mask) = double(sixgr.truth.CoupledTruthRuntime.rowValue(harqRow, "RV", NaN));
        sduT.TBCrcPass(mask) = logical(sixgr.truth.CoupledTruthRuntime.rowLogical(harqRow, "CombinedDecodeOK", false));
        if logical(sixgr.truth.CoupledTruthRuntime.rowLogical(harqRow, "CombinedDecodeOK", false))
            firstMask = mask & ~logical(sduT.DeliverySuccess);
            sduT.DeliverySuccess(firstMask) = true;
            sduT.FirstSuccessDelivery(firstMask) = true;
            sduT.FirstSuccessSlot(firstMask) = double(feedbackSlot);
            sduT.DeliveryTime_s(firstMask) = double(deliveryTime);
            sduT.DeliveryLatency_ms(firstMask) = (double(deliveryTime) - double(sduT.ScheduleTime_s(firstMask))) * 1e3;
            sduT.Status(firstMask) = "first_success_delivery";
        else
            sduT.Status(mask & ~logical(sduT.DeliverySuccess)) = "harq_pending_or_failed";
        end
        state.PacketSDULedgerTable = sduT;
        state = sixgr.truth.CoupledTruthRuntime.refreshApplicationPacketDeliveries(state);
    end

    function state = refreshApplicationPacketDeliveries(state)
        if ~isfield(state, "PacketDeliveryLedgerTable") || ~istable(state.PacketDeliveryLedgerTable) || isempty(state.PacketDeliveryLedgerTable) || ...
                ~isfield(state, "PacketSDULedgerTable") || ~istable(state.PacketSDULedgerTable)
            return;
        end
        packetT = state.PacketDeliveryLedgerTable;
        sduT = state.PacketSDULedgerTable;
        packetIds = unique(string(sduT.PacketId), "stable");
        for k = 1:numel(packetIds)
            pid = packetIds(k);
            pidx = find(string(packetT.PacketId) == pid, 1, "first");
            if isempty(pidx) || logical(packetT.DeliverySuccess(pidx))
                continue;
            end
            smask = string(sduT.PacketId) == pid;
            if ~any(smask)
                continue;
            end
            fullyScheduled = double(packetT.RemainingBits(pidx)) <= 0;
            allDelivered = all(logical(sduT.DeliverySuccess(smask)));
            if ~(fullyScheduled && allDelivered)
                continue;
            end
            deliveryTime = max(double(sduT.DeliveryTime_s(smask)), [], "omitnan");
            deliverySlot = max(double(sduT.FirstSuccessSlot(smask)), [], "omitnan");
            packetT.DeliveredBits(pidx) = double(packetT.OfferedBits(pidx));
            packetT.DeliverySuccess(pidx) = true;
            packetT.ReassemblyCompleteFlag(pidx) = true;
            packetT.DeliverySlot(pidx) = double(deliverySlot);
            packetT.DeliveryTime_s(pidx) = double(deliveryTime);
            packetT.Latency_ms(pidx) = (double(deliveryTime) - double(packetT.EnqueueTime_s(pidx))) * 1e3;
            packetT.HARQAttemptCount(pidx) = sum(double(sduT.HARQAttemptCount(smask)), "omitnan");
            packetT.DeliverySource(pidx) = "harq_first_success_reassembly";
            packetT.Status(pidx) = "delivered";
            sduT.ReassemblyCompleteFlag(smask) = true;
            sduT.ApplicationDeliveryFlag(smask) = true;
        end
        state.PacketDeliveryLedgerTable = packetT;
        state.PacketSDULedgerTable = sduT;
    end

    function packetId = composeRuntimePacketId(state, direction, ueIdx, frameIdx)
        existing = sixgr.util.structGet(state, "PacketDeliveryLedgerTable", table());
        serial = 1;
        if istable(existing) && ~isempty(existing)
            serial = height(existing) + 1;
        end
        packetId = upper(string(direction)) + "_ue" + string(double(ueIdx)) + "_frame" + string(double(frameIdx)) + "_pkt" + string(serial);
    end

    function tbId = transportBlockIdFromGrant(state, grant, direction, ueIdx)
        for name = ["TransportBlockId","TBId","MACPDUId","MACSDUId","GrantContextId"]
            raw = string(sixgr.util.structGet(grant, char(name), ""));
            if strlength(strtrim(raw)) > 0 && lower(strtrim(raw)) ~= "nan"
                tbId = raw;
                return;
            end
        end
        harqStruct = sixgr.util.structGet(grant, "HARQ", struct());
        rnti = double(sixgr.util.structGet(grant, "RNTI", NaN));
        if ~isfinite(rnti) && isstruct(state) && isfield(state, "MultiUser") && isfinite(double(ueIdx))
            rnti = double(max(1, round(double(state.MultiUser.RNTIStart + ueIdx - 1))));
        end
        harqId = double(sixgr.util.structGet(harqStruct, "HarqID", NaN));
        ndi = double(sixgr.util.structGet(harqStruct, "NDI", NaN));
        cw = double(sixgr.util.structGet(grant, "Codeword", sixgr.util.structGet(grant, "CodewordIndex", 0)));
        slot = double(sixgr.util.structGet(grant, "Slot", sixgr.util.structGet(state, "CurrentSlot", NaN)));
        tbId = upper(string(direction)) + "_rnti" + string(rnti) + "_harq" + string(harqId) + ...
            "_ndi" + string(ndi) + "_cw" + string(cw) + "_firstSlot" + string(slot);
    end

    function t = slotStartTimeSec(state, slotIdx)
        slotDur = double(sixgr.util.structGet(state, "SlotDuration_s", 0.5e-3));
        if ~(isfinite(slotDur) && slotDur > 0)
            slotDur = 0.5e-3;
        end
        slotIdx = double(slotIdx);
        if ~(isfinite(slotIdx) && slotIdx >= 1)
            slotIdx = double(sixgr.util.structGet(state, "CurrentSlot", 1));
        end
        t = max(0, slotIdx - 1) * slotDur;
    end

    function idx = resolveUEIndexFromRNTI(state, rnti)
        idx = NaN;
        rnti0 = double(max(1, round(double(state.MultiUser.RNTIStart))));
        idxCand = round(double(rnti) - rnti0 + 1);
        if isfinite(idxCand) && idxCand >= 1 && idxCand <= state.NumUsers
            idx = idxCand;
        end
    end

    function state = appendGrantTrace(state, grant, direction, feedback)
        rowT = struct2table(sixgr.truth.CoupledTruthRuntime.buildGrantTraceRow( ...
            grant, direction, ...
            sixgr.util.structGet(grant, "Slot", state.CurrentSlot), ...
            sixgr.util.structGet(grant, "Frame", state.CurrentFrame), ...
            sixgr.util.structGet(grant, "UEIndex", NaN), ...
            feedback), "AsArray", true);
        if upper(string(direction)) == "UL"
            state.ULGrantTraceTable = sixgr.truth.CoupledTruthRuntime.appendCompatTable(state.ULGrantTraceTable, rowT);
        else
            state.DLGrantTraceTable = sixgr.truth.CoupledTruthRuntime.appendCompatTable(state.DLGrantTraceTable, rowT);
        end
    end

    function state = appendSchedulerDecisionRows(state, info, direction, cellId)
        decisionT = sixgr.util.structGet(info, "CandidateTable", table());
        if ~(istable(decisionT) && ~isempty(decisionT))
            return;
        end
        direction = upper(string(direction));
        n = height(decisionT);
        vars = string(decisionT.Properties.VariableNames);
        if ismember("Direction", vars)
            decisionT.Direction = string(decisionT.Direction);
            blank = strlength(strtrim(decisionT.Direction)) == 0;
            decisionT.Direction(blank) = direction;
        else
            decisionT.Direction = repmat(direction, n, 1);
        end
        if ismember("Slot", vars)
            decisionT.Slot = double(decisionT.Slot);
            bad = ~isfinite(decisionT.Slot);
            decisionT.Slot(bad) = double(sixgr.util.structGet(state, "CurrentSlot", NaN));
        else
            decisionT.Slot = repmat(double(sixgr.util.structGet(state, "CurrentSlot", NaN)), n, 1);
        end
        if ismember("Frame", vars)
            decisionT.Frame = double(decisionT.Frame);
            bad = ~isfinite(decisionT.Frame);
            decisionT.Frame(bad) = double(sixgr.util.structGet(state, "CurrentFrame", NaN));
        else
            decisionT.Frame = repmat(double(sixgr.util.structGet(state, "CurrentFrame", NaN)), n, 1);
        end
        if ismember("ServingCell", vars)
            decisionT.ServingCell = double(decisionT.ServingCell);
            bad = ~isfinite(decisionT.ServingCell);
            decisionT.ServingCell(bad) = double(cellId);
        else
            decisionT.ServingCell = repmat(double(cellId), n, 1);
        end
        decisionT.SourceArtifact = repmat("packet_flow/csv/scheduler_decision_log.csv", n, 1);
        decisionT.SourceClassification = repmat("runtime_scheduler_candidate_decision", n, 1);
        decisionT.RuntimeMaterializationStatus = repmat("runtime_populated", n, 1);
        decisionT.ValueSource = repmat("sixgr.l2.mac.SchedulerPF.schedule", n, 1);
        decisionT.ValueRole = repmat("runtime_scheduler_candidate_rejection_lineage", n, 1);
        decisionT.ValueStatus = repmat("available_runtime_observation", n, 1);
        decisionT.ValueDefinition = repmat("Per-slot MAC scheduler candidate, PF metric, selected flag, and rejection reason emitted by the active scheduler.", n, 1);
        if ~ismember("CandidateDecisionRowsAvailable", vars)
            decisionT.CandidateDecisionRowsAvailable = true(n, 1);
        end
        if ~ismember("DecisionTruthStatus", vars)
            decisionT.DecisionTruthStatus = repmat("runtime_scheduler_candidate_truth", n, 1);
        end
        state.SchedulerDecisionTable = sixgr.truth.CoupledTruthRuntime.appendCompatTable( ...
            sixgr.util.structGet(state, "SchedulerDecisionTable", table()), decisionT);
    end

    function summaryT = buildSchedulerUESummaryTable(decisionT)
        if ~(istable(decisionT) && ~isempty(decisionT))
            summaryT = table();
            return;
        end
        direction = string(sixgr.truth.CoupledTruthRuntime.tableColumnOrDefault(decisionT, ...
            "Direction", repmat("", height(decisionT), 1)));
        rnti = double(sixgr.truth.CoupledTruthRuntime.tableColumnOrDefault(decisionT, ...
            "RNTI", nan(height(decisionT), 1)));
        ueIdx = double(sixgr.truth.CoupledTruthRuntime.tableColumnOrDefault(decisionT, ...
            "UEIndex", rnti));
        scheduled = logical(sixgr.truth.CoupledTruthRuntime.tableColumnOrDefault(decisionT, ...
            "Scheduled", false(height(decisionT), 1)));
        rejected = logical(sixgr.truth.CoupledTruthRuntime.tableColumnOrDefault(decisionT, ...
            "Rejected", false(height(decisionT), 1)));
        harqBlocked = false(height(decisionT), 1);
        if ismember("HARQBlocked", string(decisionT.Properties.VariableNames))
            harqBlocked = logical(decisionT.HARQBlocked);
        end
        if ismember("RejectionReason", string(decisionT.Properties.VariableNames))
            harqBlocked = harqBlocked | string(decisionT.RejectionReason) == "HARQ_ALL_PROCESSES_BUSY";
        end
        key = direction + "|" + string(rnti) + "|" + string(ueIdx);
        [~, firstIdx, groupIdx] = unique(key);
        rows = repmat(struct("Direction", "", "UEIndex", NaN, "RNTI", NaN, ...
            "CandidateCount", NaN, "ScheduledGrantCount", NaN, "RejectedCount", NaN, ...
            "HARQBlockedCount", NaN, "ScheduledFrac", NaN, "MeanPFMetric", NaN, ...
            "MeanInstantRate_bps", NaN, "MeanAvgThroughput_bps", NaN, ...
            "SourceArtifact", "packet_flow/csv/scheduler_decision_log.csv"), numel(firstIdx), 1);
        totalScheduledByDirection = containers.Map('KeyType', 'char', 'ValueType', 'double');
        dirs = unique(direction, "stable");
        for i = 1:numel(dirs)
            d = char(dirs(i));
            totalScheduledByDirection(d) = double(sum(scheduled(direction == dirs(i))));
        end
        pfMetric = double(sixgr.truth.CoupledTruthRuntime.tableColumnOrDefault(decisionT, ...
            "PFMetric", nan(height(decisionT), 1)));
        instRate = double(sixgr.truth.CoupledTruthRuntime.tableColumnOrDefault(decisionT, ...
            "InstantRate_bps", nan(height(decisionT), 1)));
        avgRate = double(sixgr.truth.CoupledTruthRuntime.tableColumnOrDefault(decisionT, ...
            "AvgThroughput_bps", nan(height(decisionT), 1)));
        for i = 1:numel(firstIdx)
            mask = groupIdx == i;
            rowDir = direction(firstIdx(i));
            schedCount = double(sum(scheduled(mask)));
            denom = totalScheduledByDirection(char(rowDir));
            rows(i).Direction = string(rowDir);
            rows(i).UEIndex = double(ueIdx(firstIdx(i)));
            rows(i).RNTI = double(rnti(firstIdx(i)));
            rows(i).CandidateCount = double(sum(mask));
            rows(i).ScheduledGrantCount = schedCount;
            rows(i).RejectedCount = double(sum(rejected(mask)));
            rows(i).HARQBlockedCount = double(sum(harqBlocked(mask)));
            rows(i).ScheduledFrac = schedCount / max(denom, 1);
            rows(i).MeanPFMetric = mean(pfMetric(mask), "omitnan");
            rows(i).MeanInstantRate_bps = mean(instRate(mask), "omitnan");
            rows(i).MeanAvgThroughput_bps = mean(avgRate(mask), "omitnan");
        end
        summaryT = struct2table(rows, "AsArray", true);
    end

    function row = buildGrantTraceRow(grant, direction, slotIdx, frameIdx, ueIdx, feedback)
        row = sixgr.truth.CoupledTruthRuntime.emptyGrantRow();
        prbSet = double(sixgr.util.structGet(grant, "PRBSet", []));
        symAlloc = double(sixgr.util.structGet(grant, "SymbolAllocation", []));
        row.Direction = char(upper(string(direction)));
        row.SFN = mod(max(0, round(double(frameIdx)) - 1), 1024);
        row.Slot = double(slotIdx);
        row.Frame = double(frameIdx);
        row.UEIndex = sixgr.truth.CoupledTruthRuntime.firstNumeric(ueIdx, NaN);
        row.UEID = row.UEIndex;
        row.RNTI = sixgr.truth.CoupledTruthRuntime.firstNumeric(sixgr.util.structGet(grant, "RNTI", NaN), NaN);
        row.ServingCell = sixgr.truth.CoupledTruthRuntime.firstNumeric(sixgr.util.structGet(grant, "ServingCell", NaN), NaN);
        row.BaseStationID = row.ServingCell;
        row.GrantReason = sixgr.truth.CoupledTruthRuntime.firstString(sixgr.util.structGet(grant, "GrantReason", ""), "");
        row.IsRetransmission = logical(sixgr.util.structGet(sixgr.util.structGet(grant, "HARQ", struct()), "IsRetransmission", false));
        row.HarqID = sixgr.truth.CoupledTruthRuntime.firstNumeric(sixgr.util.structGet(sixgr.util.structGet(grant, "HARQ", struct()), "HarqID", NaN), NaN);
        row.NDI = sixgr.truth.CoupledTruthRuntime.firstNumeric(sixgr.util.structGet(sixgr.util.structGet(grant, "HARQ", struct()), "NDI", NaN), NaN);
        row.RV = sixgr.truth.CoupledTruthRuntime.firstNumeric(sixgr.util.structGet(sixgr.util.structGet(grant, "HARQ", struct()), "RV", NaN), NaN);
        row.PRBStart = sixgr.truth.CoupledTruthRuntime.firstNumeric(prbSet, NaN);
        row.PRBCount = numel(prbSet);
        row.AllocatedPRBCount = row.PRBCount;
        row.SymbolStart = sixgr.truth.CoupledTruthRuntime.firstNumeric(symAlloc, NaN);
        row.NumSymbols = sixgr.truth.CoupledTruthRuntime.secondNumeric(symAlloc, NaN);
        row.TBSBits = sixgr.truth.CoupledTruthRuntime.firstNumeric(sixgr.util.structGet(grant, "TBSBits", NaN), NaN);
        row.TBSBytes = sixgr.truth.CoupledTruthRuntime.firstNumeric(sixgr.util.structGet(grant, "TBSBytes", NaN), NaN);
        row.MCSIndex = sixgr.truth.CoupledTruthRuntime.firstNumeric(sixgr.util.structGet(grant, "MCSIndex", NaN), NaN);
        row.MCSTable = sixgr.truth.CoupledTruthRuntime.firstString(sixgr.util.structGet(grant, "MCSTable", ""), "");
        row.CQITable = sixgr.truth.CoupledTruthRuntime.firstString(sixgr.util.structGet(grant, "CQITable", ""), "");
        row.Modulation = sixgr.truth.CoupledTruthRuntime.firstString(sixgr.util.structGet(grant, "Modulation", ""), "");
        row.TargetCodeRate = sixgr.truth.CoupledTruthRuntime.firstNumeric(sixgr.util.structGet(grant, "TargetCodeRate", NaN), NaN);
        row.RawCQIDerivedMCS = sixgr.truth.CoupledTruthRuntime.firstNumeric(sixgr.util.structGet(grant, "RawCQIDerivedMCS", NaN), NaN);
        row.LinkAdaptationMCSIndex = sixgr.truth.CoupledTruthRuntime.firstNumeric(sixgr.util.structGet(grant, "LinkAdaptationMCSIndex", NaN), NaN);
        row.LinkAdaptationDecisionReason = sixgr.truth.CoupledTruthRuntime.firstString(sixgr.util.structGet(grant, "LinkAdaptationDecisionReason", ""), "");
        row.CQIBasedMCS = sixgr.truth.CoupledTruthRuntime.firstNumeric(sixgr.util.structGet(grant, "CQIBasedMCS", NaN), NaN);
        row.SmoothedCQI = sixgr.truth.CoupledTruthRuntime.firstNumeric(sixgr.util.structGet(grant, "SmoothedCQI", NaN), NaN);
        row.InstantaneousCQIMCS = sixgr.truth.CoupledTruthRuntime.firstNumeric(sixgr.util.structGet(grant, "InstantaneousCQIMCS", NaN), NaN);
        row.DeltaMCS = sixgr.truth.CoupledTruthRuntime.firstNumeric(sixgr.util.structGet(grant, "DeltaMCS", NaN), NaN);
        row.StaticDeltaMCS = sixgr.truth.CoupledTruthRuntime.firstNumeric(sixgr.util.structGet(grant, "StaticDeltaMCS", NaN), NaN);
        row.AMCMode = sixgr.truth.CoupledTruthRuntime.firstString(sixgr.util.structGet(grant, "AMCMode", ""), "");
        row.OuterLoopEnabled = logical(sixgr.util.structGet(grant, "OuterLoopEnabled", false));
        row.OuterLoopApplied = logical(sixgr.util.structGet(grant, "OuterLoopApplied", false));
        row.OLLADeltaMCS = sixgr.truth.CoupledTruthRuntime.firstNumeric(sixgr.util.structGet(grant, "OLLADeltaMCS", NaN), NaN);
        row.OLLAUpdateCount = sixgr.truth.CoupledTruthRuntime.firstNumeric(sixgr.util.structGet(grant, "OLLAUpdateCount", NaN), NaN);
        row.OLLAState = sixgr.truth.CoupledTruthRuntime.firstString(sixgr.util.structGet(grant, "OLLAState", ""), "");
        row.MCSSelectionSource = sixgr.truth.CoupledTruthRuntime.firstString(sixgr.util.structGet(grant, "MCSSelectionSource", ""), "");
        row.CQIProvenance = sixgr.truth.CoupledTruthRuntime.firstString(sixgr.util.structGet(grant, "CQIProvenance", ""), "");
        row.MCSValueStatus = sixgr.truth.CoupledTruthRuntime.firstString(sixgr.util.structGet(grant, "MCSValueStatus", ""), "");
        row.MCSIndexAuthority = sixgr.truth.CoupledTruthRuntime.firstString(sixgr.util.structGet(grant, "MCSIndexAuthority", ""), "");
        row.GrantOperatingPointSource = sixgr.truth.CoupledTruthRuntime.firstString(sixgr.util.structGet(grant, "GrantOperatingPointSource", ""), "");
        row.NumLayers = sixgr.truth.CoupledTruthRuntime.firstNumeric(sixgr.util.structGet(grant, "NumLayers", NaN), NaN);
        row.Layers = row.NumLayers;
        row.CQIUsed = sixgr.truth.CoupledTruthRuntime.firstNumeric(sixgr.util.structGet(grant, "CQIUsed", sixgr.util.structGet(feedback, "CQI", NaN)), NaN);
        riCandidates = [ ...
            double(sixgr.util.structGet(grant, "RIUsed", NaN)), ...
            double(sixgr.util.structGet(grant, "RankIndicator", NaN)), ...
            double(sixgr.util.structGet(grant, "RI", NaN)), ...
            double(sixgr.util.structGet(grant, "Rank", NaN)), ...
            double(sixgr.util.structGet(grant, "NumLayers", NaN)), ...
            double(sixgr.util.structGet(grant, "Layers", NaN)), ...
            double(sixgr.util.structGet(feedback, "RI", NaN))];
        row.RIUsed = sixgr.truth.CoupledTruthRuntime.firstNumeric(riCandidates, NaN);
        rankCandidates = [ ...
            double(sixgr.util.structGet(grant, "Rank", NaN)), ...
            double(sixgr.util.structGet(grant, "NumLayers", NaN)), ...
            double(sixgr.util.structGet(grant, "Layers", NaN)), ...
            double(row.RIUsed)];
        row.Rank = sixgr.truth.CoupledTruthRuntime.firstNumeric(rankCandidates, row.RIUsed);
        row.PMI = sixgr.truth.CoupledTruthRuntime.firstNumeric(sixgr.util.structGet(grant, "PMI", sixgr.util.structGet(feedback, "PMI", NaN)), NaN);
        row.CRI = sixgr.truth.CoupledTruthRuntime.firstNumeric(sixgr.util.structGet(grant, "CRI", sixgr.util.structGet(feedback, "CRI", NaN)), NaN);
        row.MUMIMOEnabled = logical(sixgr.util.structGet(grant, "MUMIMOEnabled", false));
        row.MUMIMOGroupSize = sixgr.truth.CoupledTruthRuntime.firstNumeric(sixgr.util.structGet(grant, "MUMIMOGroupSize", NaN), NaN);
        row.MUMIMOGroupId = sixgr.truth.CoupledTruthRuntime.firstNumeric(sixgr.util.structGet(grant, "MUMIMOGroupId", NaN), NaN);
        row.MUMIMOPairingStatus = sixgr.truth.CoupledTruthRuntime.firstString(sixgr.util.structGet(grant, "MUMIMOPairingStatus", ""), "");
        row.MUMIMOPairingMetricSource = sixgr.truth.CoupledTruthRuntime.firstString(sixgr.util.structGet(grant, "MUMIMOPairingMetricSource", ""), "");
        row.MUMIMOPrecoderType = sixgr.truth.CoupledTruthRuntime.firstString(sixgr.util.structGet(grant, "MUMIMOPrecoderType", ""), "");
        row.ConfiguredBeamSelectionStrategy = sixgr.truth.CoupledTruthRuntime.firstString(sixgr.util.structGet(grant, "ConfiguredBeamSelectionStrategy", ""), "");
        row.PrecoderSource = sixgr.truth.CoupledTruthRuntime.firstString(sixgr.util.structGet(grant, "PrecoderSource", ""), "");
        row.PrecodingMode = sixgr.truth.CoupledTruthRuntime.firstString(sixgr.util.structGet(grant, "PrecodingMode", ""), "");
        row.PrecodingApplicationStage = sixgr.truth.CoupledTruthRuntime.firstString(sixgr.util.structGet(grant, "PrecodingApplicationStage", ""), "");
        row.PrecodingActive = logical(sixgr.util.structGet(grant, "PrecodingActive", false));
        row.ExplicitBeamWeightsApplied = logical(sixgr.util.structGet(grant, "ExplicitBeamWeightsApplied", false));
        row.TransformPrecodingApplied = logical(sixgr.util.structGet(grant, "TransformPrecodingApplied", false));
        row.BeamformingApplied = logical(sixgr.util.structGet(grant, "BeamformingApplied", false));
        row.AppliedBeamIndexSet = sixgr.truth.CoupledTruthRuntime.firstString(sixgr.util.structGet(grant, "AppliedBeamIndexSet", ""), "");
        row.AppliedPrecoderPMI = sixgr.truth.CoupledTruthRuntime.firstNumeric(sixgr.util.structGet(grant, "AppliedPrecoderPMI", NaN), NaN);
        row.AppliedPrecoderPMIType = sixgr.truth.CoupledTruthRuntime.firstString(sixgr.util.structGet(grant, "AppliedPrecoderPMIType", ""), "");
        row.AppliedPrecoderCodebookMode = sixgr.truth.CoupledTruthRuntime.firstString(sixgr.util.structGet(grant, "AppliedPrecoderCodebookMode", ""), "");
        row.PrecodingNumPorts = sixgr.truth.CoupledTruthRuntime.firstNumeric(sixgr.util.structGet(grant, "PrecodingNumPorts", NaN), NaN);
        row.PrecodingNumLayers = sixgr.truth.CoupledTruthRuntime.firstNumeric(sixgr.util.structGet(grant, "PrecodingNumLayers", NaN), NaN);
        row.PrecodingMatrixRows = sixgr.truth.CoupledTruthRuntime.firstNumeric(sixgr.util.structGet(grant, "PrecodingMatrixRows", NaN), NaN);
        row.PrecodingMatrixCols = sixgr.truth.CoupledTruthRuntime.firstNumeric(sixgr.util.structGet(grant, "PrecodingMatrixCols", NaN), NaN);
        row.GrantContextId = sixgr.truth.CoupledTruthRuntime.firstString(sixgr.util.structGet(grant, "GrantContextId", ""), "");
        row.GrantWorkerSafe = logical(sixgr.util.structGet(grant, "GrantWorkerSafe", true));
        row.GrantSharedStateCommitMode = sixgr.truth.CoupledTruthRuntime.firstString(sixgr.util.structGet(grant, "GrantSharedStateCommitMode", "serial_coordinator_commit"), "serial_coordinator_commit");
        row.QueueBytesBefore = sixgr.truth.CoupledTruthRuntime.firstNumeric(sixgr.util.structGet(grant, "BufferBytesBefore", NaN), NaN);
        row.QueueBytesAfter = sixgr.truth.CoupledTruthRuntime.firstNumeric(sixgr.util.structGet(grant, "BufferBytesAfter", NaN), NaN);
        row.PBCHGatingActive = logical(sixgr.util.structGet(grant, "PBCHGatingActive", false));
        row.PRACHGatingActive = logical(sixgr.util.structGet(grant, "PRACHGatingActive", false));
        row.PDCCHGatingActive = logical(sixgr.util.structGet(grant, "PDCCHGatingActive", false));
        row.SRSGatingActive = logical(sixgr.util.structGet(grant, "SRSGatingActive", false));
        row.ControlEligible = logical(sixgr.util.structGet(grant, "ControlEligible", true));
        row.SchedulingEligible = logical(sixgr.util.structGet(grant, "SchedulingEligible", row.ControlEligible));
        row.SchedulingBlockedBySRS = logical(sixgr.util.structGet(grant, "SchedulingBlockedBySRS", false));
        row.ControlDecodeOk = logical(sixgr.util.structGet(grant, "ControlDecodeOk", false));
        row.PDCCHCausalGrantDecodeOk = logical(sixgr.util.structGet(grant, "PDCCHCausalGrantDecodeOk", false));
        row.PDCCHControlFailureReason = sixgr.truth.CoupledTruthRuntime.firstString(sixgr.util.structGet(grant, "PDCCHControlFailureReason", ""), "");
        row.PDCCHControlEvidenceSource = sixgr.truth.CoupledTruthRuntime.firstString(sixgr.util.structGet(grant, "PDCCHControlEvidenceSource", ""), "");
        row.ControlDecodeSource = sixgr.truth.CoupledTruthRuntime.firstString(sixgr.util.structGet(grant, "ControlDecodeSource", ""), "");
        row.GrantControlState = sixgr.truth.CoupledTruthRuntime.firstString(sixgr.util.structGet(grant, "GrantControlState", ""), "");
        row.CellAcquisitionState = sixgr.truth.CoupledTruthRuntime.firstString(sixgr.util.structGet(grant, "CellAcquisitionState", ""), "");
        row.AccessState = sixgr.truth.CoupledTruthRuntime.firstString(sixgr.util.structGet(grant, "AccessState", ""), "");
        row.SRSValidityState = sixgr.truth.CoupledTruthRuntime.firstString(sixgr.util.structGet(grant, "SRSValidityState", ""), "");
        row.CSIValidityState = sixgr.truth.CoupledTruthRuntime.firstString(sixgr.util.structGet(grant, "CSIValidityState", ""), "");
        row.SRSValid = logical(sixgr.util.structGet(grant, "SRSValid", false));
        row.LastSuccessfulSRSSlot = sixgr.truth.CoupledTruthRuntime.firstNumeric(sixgr.util.structGet(grant, "LastSuccessfulSRSSlot", NaN), NaN);
        row.SRSAgeSlots = sixgr.truth.CoupledTruthRuntime.firstNumeric(sixgr.util.structGet(grant, "SRSAgeSlots", NaN), NaN);
        row.TRSGatingActive = logical(sixgr.util.structGet(grant, "TRSGatingActive", false));
        row.TRSValidityState = sixgr.truth.CoupledTruthRuntime.firstString(sixgr.util.structGet(grant, "TRSValidityState", ""), "");
        row.TrackingEligibility = logical(sixgr.util.structGet(grant, "TrackingEligibility", false));
        row.TRSAgeSlots = sixgr.truth.CoupledTruthRuntime.firstNumeric(sixgr.util.structGet(grant, "TRSAgeSlots", NaN), NaN);
        row.LastSuccessfulTRSSlot = sixgr.truth.CoupledTruthRuntime.firstNumeric(sixgr.util.structGet(grant, "LastSuccessfulTRSSlot", NaN), NaN);
        row.LastEstimatedTRSDopplerHz = sixgr.truth.CoupledTruthRuntime.firstNumeric(sixgr.util.structGet(grant, "LastEstimatedTRSDopplerHz", NaN), NaN);
        row.TRSStateSource = sixgr.truth.CoupledTruthRuntime.firstString(sixgr.util.structGet(grant, "TRSStateSource", ""), "");
        row.TRSRuntimeConsumer = sixgr.truth.CoupledTruthRuntime.firstString(sixgr.util.structGet(grant, "TRSRuntimeConsumer", ""), "");
        row.TRSInfluencedDecision = logical(sixgr.util.structGet(grant, "TRSInfluencedDecision", false));
        row.TRSInfluenceDefinition = sixgr.truth.CoupledTruthRuntime.firstString(sixgr.util.structGet(grant, "TRSInfluenceDefinition", ""), "");
        row.TRSReceiverIntegrationStatus = sixgr.truth.CoupledTruthRuntime.firstString(sixgr.util.structGet(grant, "TRSReceiverIntegrationStatus", ""), "");
        row.TRSReceiverIntegrationBlocker = sixgr.truth.CoupledTruthRuntime.firstString(sixgr.util.structGet(grant, "TRSReceiverIntegrationBlocker", ""), "");
    end

    function grant = normalizeGrantSnapshot(grant, direction, state, ueIdx)
        direction = upper(string(direction));
        grant.Direction = char(direction);
        grant.UEIndex = sixgr.truth.CoupledTruthRuntime.firstNumeric(sixgr.util.structGet(grant, "UEIndex", ueIdx), double(ueIdx));
        grant.RNTI = sixgr.truth.CoupledTruthRuntime.firstNumeric(sixgr.util.structGet(grant, "RNTI", max(1, round(double(state.MultiUser.RNTIStart + ueIdx - 1)))), ...
            max(1, round(double(state.MultiUser.RNTIStart + ueIdx - 1))));
        grant.MCS = sixgr.truth.CoupledTruthRuntime.firstNumeric(sixgr.util.structGet(grant, "MCS", sixgr.util.structGet(grant, "MCSIndex", NaN)), NaN);
        grant.MCSIndex = sixgr.truth.CoupledTruthRuntime.firstNumeric(sixgr.util.structGet(grant, "MCSIndex", grant.MCS), grant.MCS);
        grant.Layers = sixgr.truth.CoupledTruthRuntime.firstNumeric(sixgr.util.structGet(grant, "Layers", sixgr.util.structGet(grant, "NumLayers", NaN)), NaN);
        grant.NumLayers = sixgr.truth.CoupledTruthRuntime.firstNumeric(sixgr.util.structGet(grant, "NumLayers", grant.Layers), grant.Layers);
        grant.PRBs = sixgr.truth.CoupledTruthRuntime.firstNumeric(sixgr.util.structGet(grant, "PRBs", numel(double(sixgr.util.structGet(grant, "PRBSet", [])))), numel(double(sixgr.util.structGet(grant, "PRBSet", []))));
        grant.PRBSet = double(sixgr.util.structGet(grant, "PRBSet", []));
        grant.SymbolAllocation = double(sixgr.util.structGet(grant, "SymbolAllocation", []));
        grant.TBSBits = sixgr.truth.CoupledTruthRuntime.firstNumeric(sixgr.util.structGet(grant, "TBSBits", NaN), NaN);
        grant.TBSBytes = sixgr.truth.CoupledTruthRuntime.firstNumeric(sixgr.util.structGet(grant, "TBSBytes", NaN), NaN);
        feedback = sixgr.truth.CoupledTruthRuntime.latestFeedbackForDirection(state, ueIdx, direction);
        executableRICandidates = [ ...
            double(sixgr.util.structGet(grant, "RIUsed", NaN)), ...
            double(sixgr.util.structGet(grant, "RankIndicator", NaN)), ...
            double(sixgr.util.structGet(grant, "RI", NaN)), ...
            double(sixgr.util.structGet(grant, "Rank", NaN)), ...
            double(sixgr.util.structGet(grant, "NumLayers", NaN)), ...
            double(sixgr.util.structGet(grant, "Layers", NaN))];
        executableRI = sixgr.truth.CoupledTruthRuntime.firstNumeric(executableRICandidates, NaN);
        if ~(isfinite(double(executableRI)) && double(executableRI) >= 1)
            executableRI = sixgr.truth.CoupledTruthRuntime.firstNumeric(sixgr.util.structGet(feedback, "RI", NaN), NaN);
        end
        if isfinite(double(executableRI)) && double(executableRI) >= 1
            executableRI = double(max(1, round(executableRI)));
            grant.RI = executableRI;
            grant.RIUsed = executableRI;
            grant.Rank = executableRI;
            grant.RankIndicator = executableRI;
        end
        grant.PMI = sixgr.truth.CoupledTruthRuntime.firstNumeric(sixgr.util.structGet(grant, "PMI", NaN), NaN);
        if ~isfinite(double(grant.PMI))
            grant.PMI = sixgr.truth.CoupledTruthRuntime.firstNumeric(sixgr.util.structGet(feedback, "PMI", NaN), NaN);
        end
        grant.CRI = sixgr.truth.CoupledTruthRuntime.firstNumeric(sixgr.util.structGet(grant, "CRI", NaN), NaN);
        if ~isfinite(double(grant.CRI))
            grant.CRI = sixgr.truth.CoupledTruthRuntime.firstNumeric(sixgr.util.structGet(feedback, "CRI", NaN), NaN);
        end
        grant.MUMIMOEnabled = logical(sixgr.util.structGet(grant, "MUMIMOEnabled", false));
        grant.MUMIMOGroupSize = sixgr.truth.CoupledTruthRuntime.firstNumeric(sixgr.util.structGet(grant, "MUMIMOGroupSize", NaN), NaN);
        grant.MUMIMOGroupId = sixgr.truth.CoupledTruthRuntime.firstNumeric(sixgr.util.structGet(grant, "MUMIMOGroupId", NaN), NaN);
        grant.MUMIMOPairingStatus = sixgr.truth.CoupledTruthRuntime.firstString(sixgr.util.structGet(grant, "MUMIMOPairingStatus", ""), "");
        grant.MUMIMOPairingMetricSource = sixgr.truth.CoupledTruthRuntime.firstString(sixgr.util.structGet(grant, "MUMIMOPairingMetricSource", ""), "");
        grant.MUMIMOPrecoderType = sixgr.truth.CoupledTruthRuntime.firstString(sixgr.util.structGet(grant, "MUMIMOPrecoderType", ""), "");
        grant.ServingCell = sixgr.truth.CoupledTruthRuntime.firstNumeric(sixgr.util.structGet(grant, "ServingCell", NaN), NaN);
        if ~isfinite(double(grant.ServingCell))
            servingVec = double(sixgr.util.structGet(state, "CurrentServingIdx", nan(state.NumUsers, 1)));
            if ueIdx >= 1 && ueIdx <= numel(servingVec)
                grant.ServingCell = double(servingVec(ueIdx));
            else
                grant.ServingCell = NaN;
            end
        end
        grant.ConfiguredBeamSelectionStrategy = sixgr.truth.CoupledTruthRuntime.firstString(sixgr.util.structGet(grant, "ConfiguredBeamSelectionStrategy", ""), "");
        grant.PrecoderSource = sixgr.truth.CoupledTruthRuntime.firstString(sixgr.util.structGet(grant, "PrecoderSource", ""), "");
        grant.PrecodingMode = sixgr.truth.CoupledTruthRuntime.firstString(sixgr.util.structGet(grant, "PrecodingMode", ""), "");
        grant.PrecodingApplicationStage = sixgr.truth.CoupledTruthRuntime.firstString(sixgr.util.structGet(grant, "PrecodingApplicationStage", "none"), "none");
        grant.PrecodingActive = logical(sixgr.util.structGet(grant, "PrecodingActive", false));
        grant.ExplicitBeamWeightsApplied = logical(sixgr.util.structGet(grant, "ExplicitBeamWeightsApplied", false));
        grant.TransformPrecodingApplied = logical(sixgr.util.structGet(grant, "TransformPrecodingApplied", false));
        grant.BeamformingApplied = logical(sixgr.util.structGet(grant, "BeamformingApplied", false));
        grant.AppliedBeamIndexSet = sixgr.truth.CoupledTruthRuntime.firstString(sixgr.util.structGet(grant, "AppliedBeamIndexSet", ""), "");
        grant.AppliedPrecoderPMI = sixgr.truth.CoupledTruthRuntime.firstNumeric(sixgr.util.structGet(grant, "AppliedPrecoderPMI", NaN), NaN);
        grant.AppliedPrecoderPMIType = sixgr.truth.CoupledTruthRuntime.firstString(sixgr.util.structGet(grant, "AppliedPrecoderPMIType", ""), "");
        grant.AppliedPrecoderCodebookMode = sixgr.truth.CoupledTruthRuntime.firstString(sixgr.util.structGet(grant, "AppliedPrecoderCodebookMode", ""), "");
        grant.PrecodingNumPorts = sixgr.truth.CoupledTruthRuntime.firstNumeric(sixgr.util.structGet(grant, "PrecodingNumPorts", NaN), NaN);
        grant.PrecodingNumLayers = sixgr.truth.CoupledTruthRuntime.firstNumeric(sixgr.util.structGet(grant, "PrecodingNumLayers", NaN), NaN);
        grant.PrecodingMatrixRows = sixgr.truth.CoupledTruthRuntime.firstNumeric(sixgr.util.structGet(grant, "PrecodingMatrixRows", NaN), NaN);
        grant.PrecodingMatrixCols = sixgr.truth.CoupledTruthRuntime.firstNumeric(sixgr.util.structGet(grant, "PrecodingMatrixCols", NaN), NaN);
        grant.GrantWorkerSafe = logical(sixgr.util.structGet(grant, "GrantWorkerSafe", true));
        grant.GrantSharedStateCommitMode = sixgr.truth.CoupledTruthRuntime.firstString(sixgr.util.structGet(grant, "GrantSharedStateCommitMode", "serial_coordinator_commit"), "serial_coordinator_commit");
        grant.GrantContextId = sixgr.truth.CoupledTruthRuntime.firstString(sixgr.util.structGet(grant, "GrantContextId", ...
            sixgr.truth.CoupledTruthRuntime.composeGrantContextId(grant, direction, state, ueIdx)), ...
            sixgr.truth.CoupledTruthRuntime.composeGrantContextId(grant, direction, state, ueIdx));
        trsContext = sixgr.truth.CoupledTruthRuntime.resolveTRSRuntimeContext(state, state.CfgMobility, ueIdx, grant.ServingCell);
        grant.TRSGatingActive = logical(sixgr.util.structGet(grant, "TRSGatingActive", trsContext.TRSGatingActive));
        grant.TRSValidityState = char(string(sixgr.util.structGet(grant, "TRSValidityState", trsContext.TRSValidityState)));
        grant.TrackingEligibility = logical(sixgr.util.structGet(grant, "TrackingEligibility", trsContext.TrackingEligibility));
        grant.TRSAgeSlots = double(sixgr.util.structGet(grant, "TRSAgeSlots", trsContext.TRSAgeSlots));
        grant.LastSuccessfulTRSSlot = double(sixgr.util.structGet(grant, "LastSuccessfulTRSSlot", trsContext.LastSuccessfulTRSSlot));
        grant.LastEstimatedTRSDopplerHz = double(sixgr.util.structGet(grant, "LastEstimatedTRSDopplerHz", trsContext.LastEstimatedTRSDopplerHz));
        grant.TRSStateSource = char(string(sixgr.util.structGet(grant, "TRSStateSource", trsContext.TRSStateSource)));
        grant.TRSRuntimeConsumer = char(string(sixgr.util.structGet(grant, "TRSRuntimeConsumer", trsContext.TRSRuntimeConsumer)));
        grant.TRSInfluencedDecision = logical(sixgr.util.structGet(grant, "TRSInfluencedDecision", trsContext.TRSInfluencedDecision));
        grant.TRSInfluenceDefinition = char(string(sixgr.util.structGet(grant, "TRSInfluenceDefinition", trsContext.TRSInfluenceDefinition)));
        grant.TRSReceiverIntegrationStatus = char(string(sixgr.util.structGet(grant, "TRSReceiverIntegrationStatus", trsContext.TRSReceiverIntegrationStatus)));
        grant.TRSReceiverIntegrationBlocker = char(string(sixgr.util.structGet(grant, "TRSReceiverIntegrationBlocker", trsContext.TRSReceiverIntegrationBlocker)));
    end

    function tbBits = generateTransportBlockBits(cfg, grant, ueIdx, direction, slotIdx)
        nBits = max(0, round(double(sixgr.util.structGet(grant, "TBSBits", 0))));
        if nBits < 1
            tbBits = int8([]);
            return;
        end
        seedBase = double(sixgr.util.structGet(cfg, "run.seed", 1));
        dirOffset = double(sum(double(char(upper(string(direction))))));
        seed = mod(seedBase + 7919 * double(slotIdx) + 101 * double(ueIdx) + dirOffset, 2^31 - 1);
        rs = RandStream("mt19937ar", "Seed", max(1, round(seed)));
        tbBits = int8(randi(rs, [0 1], nBits, 1));
    end

    function state = updateSchedulerAfterFeedback(state, row, direction)
        servingCell = double(sixgr.truth.CoupledTruthRuntime.rowValue(row, "ServingCell", NaN));
        if ~(isfinite(servingCell) && servingCell >= 1)
            return;
        end
        scheduler = sixgr.truth.CoupledTruthRuntime.schedulerForDirection(state, direction, round(servingCell));
        if isempty(scheduler)
            return;
        end
        rxFeedback = struct("RNTI", double(row.RNTI), "TBSBits", double(row.TBSBits), "Ack", logical(row.Ack));
        scheduler.updateAfterRx(rxFeedback);
    end

    function grant = applyMeasuredFeedbackAMCToGrant(grant, feedback, scheduler, cfg, direction)
        if ~(isstruct(grant) && isstruct(feedback) && logical(sixgr.util.structGet(feedback, "Valid", false)))
            return;
        end
        cqi = double(sixgr.util.normalizeReportedCQI(sixgr.util.structGet(feedback, "CQI", NaN)));
        if ~(isfinite(cqi) && cqi > 0)
            return;
        end
        mcsTable = sixgr.link.resolveConfiguredMCSTable(cfg, direction);
        [cqiModStr, cqiTargetCodeRate, cqiMCSIndex] = sixgr.link.amcFromCQI(cqi, "", NaN, cfg, direction);
        cqiProfileValid = isfinite(cqiMCSIndex) && cqiMCSIndex >= 0 && ...
            isfinite(cqiTargetCodeRate) && cqiTargetCodeRate > 0 && strlength(string(cqiModStr)) > 0;
        feedbackMCS = double(sixgr.util.structGet(feedback, "MCSIndex", NaN));
        feedbackProfile = sixgr.link.resolveMCSProfile(mcsTable, feedbackMCS);
        useFeedbackDecision = isfinite(feedbackMCS) && feedbackMCS >= 0 && ...
            logical(sixgr.util.structGet(feedbackProfile, "Valid", false));
        if useFeedbackDecision
            mcsIndex = double(round(feedbackMCS));
            modStr = char(string(feedbackProfile.Modulation));
            targetCodeRate = double(feedbackProfile.TargetCodeRate);
        else
            modStr = char(string(cqiModStr));
            targetCodeRate = double(cqiTargetCodeRate);
            mcsIndex = double(cqiMCSIndex);
        end
        ollaDelta = 0;
        ollaCount = 0;
        ollaEnabled = false;
        ollaMCSAdjusted = false;
        mcsClampedToCQI = false;
        if useFeedbackDecision
            ollaDelta = double(sixgr.util.structGet(feedback, "DeltaMCS", 0));
            ollaCount = double(sixgr.util.structGet(feedback, "LinkAdaptationStateUpdateCount", 0));
            ollaEnabled = logical(sixgr.util.structGet(feedback, "OuterLoopEnabled", false));
        elseif ~isempty(scheduler) && ismethod(scheduler, "getOLLAMCSDelta")
            try
                [ollaDelta, ollaCount, ollaEnabled] = scheduler.getOLLAMCSDelta(double(sixgr.util.structGet(grant, "RNTI", NaN)));
            catch
                ollaDelta = 0;
                ollaCount = 0;
                ollaEnabled = false;
            end
        end
        if ~useFeedbackDecision && logical(ollaEnabled) && isfinite(mcsIndex) && isfinite(ollaDelta) && ollaCount > 0
            cqiCeiling = double(cqiMCSIndex);
            if ~(isfinite(cqiCeiling) && cqiCeiling >= 0)
                cqiCeiling = double(mcsIndex);
            end
            rawAdjustedMCS = round(double(mcsIndex) + double(ollaDelta));
            adjustedMCS = max(0, min(31, min(rawAdjustedMCS, round(cqiCeiling))));
            prof = sixgr.link.resolveMCSProfile(mcsTable, adjustedMCS);
            if prof.Valid
                mcsIndex = double(adjustedMCS);
                modStr = char(string(prof.Modulation));
                targetCodeRate = double(prof.TargetCodeRate);
                ollaMCSAdjusted = true;
                mcsClampedToCQI = rawAdjustedMCS > round(cqiCeiling);
            end
        end
        if cqiProfileValid && isfinite(mcsIndex) && round(double(mcsIndex)) > round(double(cqiMCSIndex))
            mcsIndex = double(round(cqiMCSIndex));
            modStr = char(string(cqiModStr));
            targetCodeRate = double(cqiTargetCodeRate);
            mcsClampedToCQI = true;
        end
        if ~(isfinite(mcsIndex) && mcsIndex >= 0 && isfinite(targetCodeRate) && targetCodeRate > 0)
            return;
        end
        smallPRBGuardApplied = false;
        smallPRBGuardSource = "wideband_cqi_small_prb_runtime_guard";
        grant.CQIUsed = double(cqi);
        grant = sixgr.truth.CoupledTruthRuntime.applyMeasuredFeedbackRankToGrant( ...
            grant, feedback, cfg, direction);
        if sixgr.truth.CoupledTruthRuntime.smallPRBWidebandFeedbackGuardApplies( ...
                grant, feedback, cfg, direction, mcsIndex)
            [mcsIndex, modStr, targetCodeRate] = ...
                sixgr.truth.CoupledTruthRuntime.smallPRBWidebandGuardMCS( ...
                cfg, direction, mcsTable, mcsIndex);
            grant = sixgr.truth.CoupledTruthRuntime.forceSingleLayerSmallPRBGuard( ...
                grant, feedback, cfg, direction);
            smallPRBGuardApplied = true;
        end
        grant.MCSIndex = double(round(mcsIndex));
        grant.MCS = double(round(mcsIndex));
        grant.Modulation = char(string(modStr));
        grant.TargetCodeRate = double(targetCodeRate);
        if useFeedbackDecision
            feedbackRawCQIMCS = double(sixgr.util.structGet(feedback, "RawCQIDerivedMCS", NaN));
            if cqiProfileValid
                grant.RawCQIDerivedMCS = double(cqiMCSIndex);
            else
                grant.RawCQIDerivedMCS = double(feedbackRawCQIMCS);
            end
            grant.LinkAdaptationMCSIndex = double(feedbackMCS);
            grant.LinkAdaptationDecisionReason = char(string(sixgr.util.structGet(feedback, "LinkAdaptationDecisionReason", "")));
            grant.CQIBasedMCS = double(sixgr.util.structGet(feedback, "CQIBasedMCS", NaN));
            grant.SmoothedCQI = double(sixgr.util.structGet(feedback, "SmoothedCQI", NaN));
            grant.InstantaneousCQIMCS = double(sixgr.util.structGet(feedback, "InstantaneousCQIMCS", NaN));
            grant.DeltaMCS = double(sixgr.util.structGet(feedback, "DeltaMCS", NaN));
            grant.StaticDeltaMCS = double(sixgr.util.structGet(feedback, "StaticDeltaMCS", 0));
        else
            grant.RawCQIDerivedMCS = double(cqiMCSIndex);
            grant.LinkAdaptationMCSIndex = NaN;
            grant.LinkAdaptationDecisionReason = "";
            grant.CQIBasedMCS = NaN;
            grant.SmoothedCQI = NaN;
            grant.InstantaneousCQIMCS = double(cqiMCSIndex);
            grant.DeltaMCS = NaN;
            grant.StaticDeltaMCS = 0;
        end
        selectionSource = strtrim(string(sixgr.util.structGet(feedback, "MCSSelectionSource", "")));
        if useFeedbackDecision
            if strlength(selectionSource) == 0
                sourceSignal = upper(strtrim(string(sixgr.util.structGet(feedback, "FeedbackSourceSignal", ""))));
                if any(sourceSignal == ["SRS", "SRS_RECIPROCITY"])
                    selectionSource = "feedback_cqi_derived_reference";
                else
                    selectionSource = "runtime_link_adaptation_decision";
                end
            end
            grant.MCSValueStatus = char(string(sixgr.util.structGet(feedback, "MCSValueStatus", "measured_feedback_adapted")));
        else
            selectionSource = "feedback_cqi_derived_reference";
            if ollaMCSAdjusted
                grant.MCSValueStatus = "measured_cqi_mapped_olla_adjusted";
            else
                grant.MCSValueStatus = "measured_cqi_mapped";
            end
        end
        if mcsClampedToCQI
            grant.MCSValueStatus = "clamped_to_cqi_max";
        end
        if smallPRBGuardApplied
            selectionSource = sixgr.truth.CoupledTruthRuntime.appendSourceToken( ...
                selectionSource, smallPRBGuardSource);
            grant.MCSValueStatus = "wideband_cqi_small_prb_guard_conservative";
        end
        grant.MCSIndexAuthority = char(selectionSource);
        grant.GrantOperatingPointSource = char(selectionSource);
        grant.AMCMode = "cqi_table";
        grant.CSIAgingModel = char(string(sixgr.util.structGet(feedback, "CSIAgingModel", "")));
        grant.SubbandSINRVector_dB = char(string(sixgr.util.structGet(feedback, "SubbandSINRVector_dB", "")));
        grant.AgedSubbandSINRVector_dB = char(string(sixgr.util.structGet(feedback, "AgedSubbandSINRVector_dB", "")));
        grant.PostEqSINRPerLayer_dB = char(string(sixgr.util.structGet(feedback, "PostEqSINRPerLayer_dB", "")));
        grant.AgedPostEqSINRPerLayer_dB = char(string(sixgr.util.structGet(feedback, "AgedPostEqSINRPerLayer_dB", "")));
        grant.SubbandAgingPenaltyVector_dB = char(string(sixgr.util.structGet(feedback, "SubbandAgingPenaltyVector_dB", "")));
        grant.LayerAgingPenaltyVector_dB = char(string(sixgr.util.structGet(feedback, "LayerAgingPenaltyVector_dB", "")));
        grant.OuterLoopEnabled = logical(ollaEnabled);
        grant.OuterLoopApplied = logical(ollaEnabled && ollaCount > 0 && isfinite(ollaDelta) && abs(double(ollaDelta)) > 0);
        grant.OLLADeltaMCS = double(ollaDelta);
        grant.OLLAUpdateCount = double(ollaCount);
        grant.SmallPRBWidebandCQIGuardApplied = logical(smallPRBGuardApplied);
        if smallPRBGuardApplied
            grant.SmallPRBWidebandCQIGuardSource = char(smallPRBGuardSource);
            grant.SmallPRBWidebandCQIGuardMinPRB = ...
                sixgr.truth.CoupledTruthRuntime.smallPRBWidebandGuardMinPRB(cfg);
        else
            grant.SmallPRBWidebandCQIGuardSource = "";
            grant.SmallPRBWidebandCQIGuardMinPRB = NaN;
        end
        if logical(grant.OuterLoopApplied)
            grant.OLLAState = "applied_scheduler_ack_nack_delta";
        elseif logical(grant.OuterLoopEnabled)
            grant.OLLAState = "configured_waiting_for_ack_feedback";
        else
            grant.OLLAState = "disabled";
        end

        prbSet = double(sixgr.util.structGet(grant, "PRBSet", []));
        symAlloc = double(sixgr.util.structGet(grant, "SymbolAllocation", []));
        if isempty(symAlloc)
            symStart = double(sixgr.util.structGet(grant, "SymbolStart", 0));
            nSym = double(sixgr.util.structGet(grant, "NumSymbols", NaN));
            if isfinite(nSym) && nSym > 0
                symAlloc = [symStart nSym];
            end
        end
        nLayers = double(sixgr.util.structGet(grant, "NumLayers", sixgr.util.structGet(grant, "Layers", 1)));
        if isempty(prbSet) || isempty(symAlloc) || ~(isfinite(nLayers) && nLayers >= 1) || isempty(scheduler)
            return;
        end
        try
            [tbsBits, tbsBytes, nrePerPRB] = scheduler.estimateTBS( ...
                char(string(modStr)), max(1, round(nLayers)), numel(prbSet), symAlloc, targetCodeRate, ...
                "ForceExact", true);
            if isfinite(tbsBits) && tbsBits > 0
                grant.TBSBits = double(tbsBits);
                grant.TransportBlockSize = double(tbsBits);
                grant.TBSBytes = double(tbsBytes);
                grant.NREPerPRB = double(nrePerPRB);
                grant.EstimatedTBSBits = double(tbsBits);
                grant.EstimatedTBSBytes = double(tbsBytes);
            end
        catch
            % Keep the already scheduled allocation if the toolbox TBS helper
            % cannot evaluate this exact grant shape; the MCS authority still
            % reflects measured CQI and the PHY runner will enforce validity.
        end
    end

    function state = enqueueCSIReport(state, ueIdx, direction, row)
        report = sixgr.truth.CoupledTruthRuntime.emptyCSIReportRow();
        report.Direction = char(upper(string(direction)));
        report.UEIndex = double(ueIdx);
        report.RNTI = double(max(1, round(double(state.MultiUser.RNTIStart + ueIdx - 1))));
        sourceSlot = double(sixgr.truth.CoupledTruthRuntime.rowValue(row, "Slot", state.CurrentSlot));
        report.SourceSlot = double(sourceSlot);
        report.DueSlot = double(sourceSlot + state.CSIFeedbackSlots);
        csi = sixgr.truth.CoupledTruthRuntime.resolveMeasuredRuntimeCSIForRow(row, state.CfgMobility, direction);
        report.CQI = double(csi.CQI);
        report.RI = double(csi.RI);
        report.PMI = double(sixgr.truth.CoupledTruthRuntime.sanitizeFeedbackPMI( ...
            sixgr.truth.CoupledTruthRuntime.rowValue(row, "PMI", NaN), state.CfgMobility, direction, report.RI));
        report.CRI = double(sixgr.truth.CoupledTruthRuntime.sanitizeFeedbackCRI( ...
            sixgr.truth.CoupledTruthRuntime.rowValue(row, "CRI", NaN), state.CfgMobility));
        report.SINR_dB = double(csi.SINR_dB);
        report.SINRSource = char(string(csi.SINRSource));
        report.SINRValueRole = char(string(csi.SINRValueRole));
        report.SINRValueStatus = char(string(csi.SINRValueStatus));
        report.MCSIndex = double(csi.MCSIndex);
        report.TargetCodeRate = double(csi.TargetCodeRate);
        report.Modulation = char(string(csi.Modulation));
        report.CRCPass = double(sixgr.truth.CoupledTruthRuntime.rowValue(row, "CRCPass", NaN));
        report.RawCQIDerivedMCS = double(report.MCSIndex);
        report.RawCQIDerivedTargetCodeRate = double(report.TargetCodeRate);
        report.RawCQIDerivedModulation = char(string(report.Modulation));
        subbandSINR = sixgr.truth.CoupledTruthRuntime.rowFirstNumericVector(row, ...
            ["SubbandSINRVector_dB","SubbandSINR_dB","PerRBSINR_dB"]);
        layerSINR = sixgr.truth.CoupledTruthRuntime.rowFirstNumericVector(row, ...
            ["PostEqSINRPerLayer_dB","PerLayerSINR_dB","SelectedLayerSINR_dB","LayerSINRdB"]);
        report.SubbandSINRVector_dB = sixgr.truth.CoupledTruthRuntime.numericVectorToken(subbandSINR);
        report.PostEqSINRPerLayer_dB = sixgr.truth.CoupledTruthRuntime.numericVectorToken(layerSINR);
        report.SubbandCSIAgeSlots = sixgr.truth.CoupledTruthRuntime.numericVectorToken( ...
            sixgr.truth.CoupledTruthRuntime.rowFirstNumericVector(row, ["SubbandCSIAgeSlots","SubbandAgeSlots","PerSubbandCSIAgeSlots","PerRBAgeSlots"]));
        report.LayerCSIAgeSlots = sixgr.truth.CoupledTruthRuntime.numericVectorToken( ...
            sixgr.truth.CoupledTruthRuntime.rowFirstNumericVector(row, ["LayerCSIAgeSlots","LayerAgeSlots","PerLayerCSIAgeSlots"]));
        report.SubbandDopplerHz = sixgr.truth.CoupledTruthRuntime.numericVectorToken( ...
            sixgr.truth.CoupledTruthRuntime.rowFirstNumericVector(row, ["SubbandDopplerHz","SubbandDoppler_Hz","PerSubbandDopplerHz","PerRBDopplerHz"]));
        report.LayerDopplerHz = sixgr.truth.CoupledTruthRuntime.numericVectorToken( ...
            sixgr.truth.CoupledTruthRuntime.rowFirstNumericVector(row, ["LayerDopplerHz","LayerDoppler_Hz","PerLayerDopplerHz"]));
        servingVec = double(sixgr.util.structGet(state, "CurrentServingIdx", nan(state.NumUsers, 1)));
        if ueIdx >= 1 && ueIdx <= numel(servingVec)
            report.ServingCell = double(servingVec(ueIdx));
        end
        [state, report] = sixgr.truth.CoupledTruthRuntime.applyLinkAdaptationToCSIReport(state, report, ueIdx, direction, row);
        sourceSignal = "CSI-RS";
        if upper(string(direction)) == "UL"
            sourceSignal = "SRS";
        end
        state = sixgr.truth.CoupledTruthRuntime.publishReferenceSignalMeasurementImpl( ...
            state, sourceSignal, "UE", ueIdx, row, ...
            "ProducerSlot", report.SourceSlot, "AvailableSlot", report.DueSlot, ...
            "Valid", isfinite(report.CQI) || isfinite(report.RI) || isfinite(report.SINR_dB), ...
            "Direction", direction, "SourceSignal", sourceSignal, ...
            "MeasurementSource", "CoupledTruthRuntime.enqueueCSIReport");
        state.PendingCSITable = sixgr.truth.CoupledTruthRuntime.appendCompatTable(state.PendingCSITable, struct2table(report, "AsArray", true));
        if report.DueSlot <= state.CurrentSlot
            latest = sixgr.truth.CoupledTruthRuntime.emptyLatestFeedbackRow();
            latest.Valid = true;
            latest.CQI = report.CQI;
            latest.RI = report.RI;
            latest.PMI = double(sixgr.truth.CoupledTruthRuntime.sanitizeFeedbackPMI( ...
                report.PMI, state.CfgMobility, direction, latest.RI));
            latest.CRI = double(sixgr.truth.CoupledTruthRuntime.sanitizeFeedbackCRI( ...
                report.CRI, state.CfgMobility));
            latest.SINR_dB = report.SINR_dB;
            latest.SINRSource = report.SINRSource;
            latest.SINRValueRole = report.SINRValueRole;
            latest.SINRValueStatus = report.SINRValueStatus;
            latest.MCSIndex = report.MCSIndex;
            latest.TargetCodeRate = report.TargetCodeRate;
            latest.Modulation = report.Modulation;
            latest.ServingCell = report.ServingCell;
            latest.Slot = report.SourceSlot;
            latest.Direction = report.Direction;
            latest.RawCQIDerivedMCS = report.RawCQIDerivedMCS;
            latest.RawCQIDerivedTargetCodeRate = report.RawCQIDerivedTargetCodeRate;
            latest.RawCQIDerivedModulation = report.RawCQIDerivedModulation;
            latest.LinkAdaptationMCSIndex = report.LinkAdaptationMCSIndex;
            latest.LinkAdaptationDecisionReason = report.LinkAdaptationDecisionReason;
            latest.MCSSelectionSource = report.MCSSelectionSource;
            latest.MCSValueStatus = report.MCSValueStatus;
            latest.CQIBasedMCS = report.CQIBasedMCS;
            latest.SmoothedCQI = report.SmoothedCQI;
            latest.InstantaneousCQIMCS = report.InstantaneousCQIMCS;
            latest.DeltaMCS = report.DeltaMCS;
            latest.EffectiveCQISmoothingAlpha = report.EffectiveCQISmoothingAlpha;
            latest.CSITemporalCorrelationWeight = report.CSITemporalCorrelationWeight;
            latest.CSIAgeSeconds = report.CSIAgeSeconds;
            latest.CSICoherenceTimeSeconds = report.CSICoherenceTimeSeconds;
            latest.CSIAgingModel = report.CSIAgingModel;
            latest.SubbandSINRVector_dB = report.SubbandSINRVector_dB;
            latest.AgedSubbandSINRVector_dB = report.AgedSubbandSINRVector_dB;
            latest.PostEqSINRPerLayer_dB = report.PostEqSINRPerLayer_dB;
            latest.AgedPostEqSINRPerLayer_dB = report.AgedPostEqSINRPerLayer_dB;
            latest.SubbandAgingPenaltyVector_dB = report.SubbandAgingPenaltyVector_dB;
            latest.LayerAgingPenaltyVector_dB = report.LayerAgingPenaltyVector_dB;
            latest.OuterLoopEnabled = report.OuterLoopEnabled;
            latest.InnerLoopEnabled = report.InnerLoopEnabled;
            latest.LinkAdaptationStateUpdateCount = report.LinkAdaptationStateUpdateCount;
            latest.FeedbackSourceSignal = char(upper(string(direction)) + "_CSI_REPORT");
            latest.FeedbackCRCPass = double(sixgr.truth.CoupledTruthRuntime.rowValue(row, "CRCPass", NaN));
            if upper(string(direction)) == "UL"
                state.LatestULFeedback(ueIdx) = latest;
            else
                state.LatestDLFeedback(ueIdx) = latest;
            end
            state.PendingCSITable.Processed(end) = true;
        end
    end

    function [state, report] = applyLinkAdaptationToCSIReport(state, report, ueIdx, direction, row)
        direction = upper(string(direction));
        report.LinkAdaptationMCSIndex = NaN;
        report.LinkAdaptationDecisionReason = "";
        report.MCSSelectionSource = "runtime_cqi_table_raw";
        report.MCSValueStatus = "measured_cqi_mapped_raw";
        report.CQIBasedMCS = NaN;
        report.SmoothedCQI = NaN;
        report.InstantaneousCQIMCS = NaN;
        report.DeltaMCS = NaN;
        report.EffectiveCQISmoothingAlpha = NaN;
        report.CSITemporalCorrelationWeight = NaN;
        report.CSIAgeSeconds = NaN;
        report.CSICoherenceTimeSeconds = NaN;
        report.CSIAgingModel = "";
        report.AgedSubbandSINRVector_dB = "";
        report.AgedPostEqSINRPerLayer_dB = "";
        report.SubbandAgingPenaltyVector_dB = "";
        report.LayerAgingPenaltyVector_dB = "";
        report.OuterLoopEnabled = false;
        report.InnerLoopEnabled = false;
        report.LinkAdaptationStateUpdateCount = NaN;

        if ~sixgr.truth.CoupledTruthRuntime.schedulerUsesCQITableForDirection(state.CfgMobility, direction)
            return;
        end
        if ~(isfinite(report.CQI) && report.CQI > 0)
            report.MCSSelectionSource = "missing_runtime_cqi";
            report.MCSValueStatus = "unavailable_missing_runtime_cqi";
            return;
        end

        previousState = sixgr.truth.CoupledTruthRuntime.linkAdaptationStateForUE(state, direction, ueIdx);
        previousState = sixgr.truth.CoupledTruthRuntime.seedRuntimeLinkAdaptationState( ...
            state.CfgMobility, direction, previousState, report.ServingCell);
        metrics = struct( ...
            "CQI", double(report.CQI), ...
            "RI", double(report.RI), ...
            "PMI", double(report.PMI), ...
            "CRI", double(report.CRI), ...
            "SINR_dB", double(report.SINR_dB), ...
            "CSIAgeSlots", max(0, double(report.DueSlot) - double(report.SourceSlot)), ...
            "CSIAgeSeconds", max(0, double(report.DueSlot) - double(report.SourceSlot)) * double(state.SlotDuration_s), ...
            "SINRSource", char(string(sixgr.util.structGet(report, "SINRSource", ...
                sixgr.truth.CoupledTruthRuntime.rowFirstString(row, ["MeasuredTrialSINRSource","SINRSource","PostEqSINRSource"], "")))), ...
            "SINRValueRole", char(string(sixgr.util.structGet(report, "SINRValueRole", ...
                sixgr.truth.CoupledTruthRuntime.rowFirstString(row, ["MeasuredTrialSINRValueRole","SINRValueRole","PostEqSINRValueRole"], "")))), ...
            "SINRValueStatus", char(string(sixgr.util.structGet(report, "SINRValueStatus", ...
                sixgr.truth.CoupledTruthRuntime.rowFirstString(row, ["MeasuredTrialSINRValueStatus","SINRValueStatus","PostEqSINRValueStatus"], "")))));
        metrics.SubbandSINRVector_dB = char(string(sixgr.util.structGet(report, "SubbandSINRVector_dB", "")));
        metrics.PostEqSINRPerLayer_dB = char(string(sixgr.util.structGet(report, "PostEqSINRPerLayer_dB", "")));
        metrics.SubbandCSIAgeSlots = char(string(sixgr.util.structGet(report, "SubbandCSIAgeSlots", "")));
        metrics.LayerCSIAgeSlots = char(string(sixgr.util.structGet(report, "LayerCSIAgeSlots", "")));
        metrics.SubbandDopplerHz = char(string(sixgr.util.structGet(report, "SubbandDopplerHz", "")));
        metrics.LayerDopplerHz = char(string(sixgr.util.structGet(report, "LayerDopplerHz", "")));
        if sixgr.truth.CoupledTruthRuntime.rowHasField(row, "CRCPass")
            metrics.CRCPass = logical(sixgr.truth.CoupledTruthRuntime.rowLogical(row, "CRCPass", false));
        end

        try
            [decision, nextState] = sixgr.link.computeLinkAdaptationDecision( ...
                state.CfgMobility, direction, metrics, "AdaptationState", previousState);
        catch
            report.LinkAdaptationDecisionReason = "link_adaptation_decision_failed";
            report.MCSSelectionSource = "runtime_cqi_table_raw_due_to_decision_error";
            return;
        end
        nextState.ServingCell = double(report.ServingCell);
        state = sixgr.truth.CoupledTruthRuntime.setLinkAdaptationStateForUE(state, direction, ueIdx, nextState);

        report.LinkAdaptationDecisionReason = char(string(sixgr.util.structGet(decision, "Reason", "")));
        report.CQIBasedMCS = double(sixgr.util.structGet(decision, "CQIBasedMCS", NaN));
        report.SmoothedCQI = double(sixgr.util.structGet(decision, "SmoothedCQI", NaN));
        report.InstantaneousCQIMCS = double(sixgr.util.structGet(decision, "InstantaneousCQIMCS", NaN));
        report.DeltaMCS = double(sixgr.util.structGet(decision, "DeltaMCS", NaN));
        report.EffectiveCQISmoothingAlpha = double(sixgr.util.structGet(decision, "EffectiveCQISmoothingAlpha", NaN));
        report.CSITemporalCorrelationWeight = double(sixgr.util.structGet(decision, "CSITemporalCorrelationWeight", NaN));
        report.CSIAgeSeconds = double(sixgr.util.structGet(decision, "CSIAgeSeconds", NaN));
        report.CSICoherenceTimeSeconds = double(sixgr.util.structGet(decision, "CSICoherenceTimeSeconds", NaN));
        report.CSIAgingModel = char(string(sixgr.util.structGet(decision, "CSIAgingModel", "")));
        report.AgedSubbandSINRVector_dB = char(string(sixgr.util.structGet(decision, "AgedSubbandSINRVector_dB", "")));
        report.AgedPostEqSINRPerLayer_dB = char(string(sixgr.util.structGet(decision, "AgedLayerSINRVector_dB", "")));
        report.SubbandAgingPenaltyVector_dB = char(string(sixgr.util.structGet(decision, "SubbandAgingPenaltyVector_dB", "")));
        report.LayerAgingPenaltyVector_dB = char(string(sixgr.util.structGet(decision, "LayerAgingPenaltyVector_dB", "")));
        report.OuterLoopEnabled = logical(sixgr.util.structGet(decision, "OuterLoopEnabled", false));
        report.InnerLoopEnabled = logical(sixgr.util.structGet(decision, "InnerLoopEnabled", false));
        report.LinkAdaptationStateUpdateCount = double(sixgr.util.structGet(decision, "StateUpdateCount", NaN));
        if logical(sixgr.util.structGet(decision, "Valid", false)) && ...
                isfinite(double(sixgr.util.structGet(decision, "MCSIndex", NaN)))
            decisionMCS = double(decision.MCSIndex);
            decisionTargetCodeRate = double(decision.TargetCodeRate);
            decisionModulation = char(string(decision.Modulation));
            crcPass = double(sixgr.truth.CoupledTruthRuntime.rowValue(row, "CRCPass", NaN));
            failedMCS = double(sixgr.truth.CoupledTruthRuntime.rowFirstFinite(row, ["MCSIndex","MCS"], NaN));
            if isfinite(crcPass) && crcPass == 0 && isfinite(failedMCS) && failedMCS >= 0
                cappedMCS = max(0, round(double(failedMCS)) - 1);
                if decisionMCS > cappedMCS
                    profile = sixgr.link.resolveMCSProfile( ...
                        sixgr.link.resolveConfiguredMCSTable(state.CfgMobility, direction), cappedMCS);
                    if logical(sixgr.util.structGet(profile, "Valid", false))
                        decisionMCS = double(cappedMCS);
                        decisionTargetCodeRate = double(profile.TargetCodeRate);
                        decisionModulation = char(string(profile.Modulation));
                        report.LinkAdaptationDecisionReason = char(string(report.LinkAdaptationDecisionReason) + "_crc_nack_mcs_backoff");
                    end
                end
            end
            report.MCSIndex = double(decisionMCS);
            report.LinkAdaptationMCSIndex = double(decisionMCS);
            report.TargetCodeRate = double(decisionTargetCodeRate);
            report.Modulation = char(string(decisionModulation));
            report.MCSSelectionSource = char(string(sixgr.util.structGet(decision, ...
                "MCSSelectionSource", "runtime_link_adaptation_decision")));
            report.MCSValueStatus = char(string(sixgr.util.structGet(decision, ...
                "MCSValueStatus", "measured_feedback_adapted")));
        end
    end

    function csi = resolveMeasuredRuntimeCSIForRow(row, cfg, direction)
        direction = upper(string(direction));
        rawCQI = double(sixgr.util.normalizeReportedCQI( ...
            sixgr.truth.CoupledTruthRuntime.rowValue(row, "WidebandCQI", NaN)));
        rawMCS = double(sixgr.truth.CoupledTruthRuntime.rowValue(row, "CQIDerivedMCS", NaN));
        rawRate = double(sixgr.truth.CoupledTruthRuntime.rowValue(row, "CQIDerivedTargetCodeRate", NaN));
        rawMod = string(sixgr.truth.CoupledTruthRuntime.rowValue(row, "CQIDerivedModulation", ""));
        ri = double(sixgr.truth.CoupledTruthRuntime.rowFirstFinite(row, ...
            ["RankIndicator","RI","RIUsed","Rank","Layers","NumLayers"], NaN));
        if ~(isfinite(ri) && ri >= 1)
            ri = NaN;
        else
            ri = max(1, round(ri));
        end

        [measuredSINR, sinrSource, sinrRole, sinrStatus] = ...
            sixgr.truth.CoupledTruthRuntime.schedulerMeasuredSINRFromRow(row);
        subbandSINR = sixgr.truth.CoupledTruthRuntime.rowFirstNumericVector(row, ...
            ["SubbandSINRVector_dB","SubbandSINR_dB","PerRBSINR_dB"]);
        layerSINR = sixgr.truth.CoupledTruthRuntime.rowFirstNumericVector(row, ...
            ["PostEqSINRPerLayer_dB","PerLayerSINR_dB","SelectedLayerSINR_dB","LayerSINRdB"]);
        cqi = rawCQI;
        mcs = rawMCS;
        targetCodeRate = rawRate;
        modStr = rawMod;
        cqiSource = "trial_row_wideband_cqi";
        derivedFromMeasuredSINR = false;
        if isfinite(measuredSINR)
            feedback = sixgr.link.resolveWidebandCQI(struct( ...
                "WidebandSINR_dB", double(measuredSINR), ...
                "PerRBSINR_dB", double(subbandSINR), ...
                "PostEqSINRPerLayer_dB", double(layerSINR), ...
                "SINRSource", char(sinrSource), ...
                "SINRValueRole", char(sinrRole), ...
                "SINRValueStatus", char(sinrStatus), ...
                "RankIndicator", double(ri)), cfg, direction);
            derivedCQI = double(sixgr.util.normalizeReportedCQI( ...
                sixgr.util.structGet(feedback, "WidebandCQI", NaN)));
            if isfinite(derivedCQI) && derivedCQI > 0 && ...
                    (~sixgr.truth.CoupledTruthRuntime.rowCQIHasMeasuredCSIProvenance(row) || ...
                    ~(isfinite(rawCQI) && rawCQI > 0) || double(derivedCQI) < double(rawCQI))
                cqi = double(derivedCQI);
                [modCandidate, rateCandidate, mcsCandidate] = sixgr.link.amcFromCQI( ...
                    cqi, "", NaN, cfg, direction);
                mcs = double(mcsCandidate);
                targetCodeRate = double(rateCandidate);
                modStr = string(modCandidate);
                cqiSource = "measured_post_equalization_sinr_to_cqi";
                derivedFromMeasuredSINR = true;
            elseif isfinite(rawCQI) && rawCQI > 0
                [modCandidate, rateCandidate, mcsCandidate] = sixgr.link.amcFromCQI( ...
                    rawCQI, char(rawMod), rawRate, cfg, direction);
                if ~(isfinite(mcs) && mcs >= 0)
                    mcs = double(mcsCandidate);
                end
                if ~(isfinite(targetCodeRate) && targetCodeRate > 0)
                    targetCodeRate = double(rateCandidate);
                end
                if strlength(strtrim(modStr)) == 0
                    modStr = string(modCandidate);
                end
            end
        elseif isfinite(rawCQI) && rawCQI > 0
            [modCandidate, rateCandidate, mcsCandidate] = sixgr.link.amcFromCQI( ...
                rawCQI, char(rawMod), rawRate, cfg, direction);
            if ~(isfinite(mcs) && mcs >= 0)
                mcs = double(mcsCandidate);
            end
            if ~(isfinite(targetCodeRate) && targetCodeRate > 0)
                targetCodeRate = double(rateCandidate);
            end
            if strlength(strtrim(modStr)) == 0
                modStr = string(modCandidate);
            end
        end
        crcPass = double(sixgr.truth.CoupledTruthRuntime.rowValue(row, "CRCPass", NaN));
        failedMCS = double(sixgr.truth.CoupledTruthRuntime.rowFirstFinite(row, ["MCSIndex","MCS"], NaN));
        if isfinite(crcPass) && crcPass == 0 && isfinite(failedMCS) && failedMCS >= 0
            cappedMCS = max(0, round(double(failedMCS)) - 1);
            if ~(isfinite(mcs) && mcs <= cappedMCS)
                profile = sixgr.link.resolveMCSProfile( ...
                    sixgr.link.resolveConfiguredMCSTable(cfg, direction), cappedMCS);
                if logical(sixgr.util.structGet(profile, "Valid", false))
                    mcs = double(cappedMCS);
                    targetCodeRate = double(profile.TargetCodeRate);
                    modStr = string(profile.Modulation);
                    cqiSource = string(cqiSource) + "_crc_nack_mcs_backoff";
                end
            end
        end

        csi = struct( ...
            "CQI", double(cqi), ...
            "RI", double(ri), ...
            "SINR_dB", double(measuredSINR), ...
            "SINRSource", char(sinrSource), ...
            "SINRValueRole", char(sinrRole), ...
            "SINRValueStatus", char(sinrStatus), ...
            "MCSIndex", double(mcs), ...
            "TargetCodeRate", double(targetCodeRate), ...
            "Modulation", char(string(modStr)), ...
            "CQISource", char(cqiSource), ...
            "SubbandSINRVector_dB", char(sixgr.truth.CoupledTruthRuntime.numericVectorToken(subbandSINR)), ...
            "PostEqSINRPerLayer_dB", char(sixgr.truth.CoupledTruthRuntime.numericVectorToken(layerSINR)), ...
            "DerivedFromMeasuredSINR", logical(derivedFromMeasuredSINR));
    end

    function [sinr_dB, source, role, status] = schedulerMeasuredSINRFromRow(row)
        sinr_dB = NaN;
        source = "";
        role = "";
        status = "";
        candidates = [
            "PostEqSINR_dB", "PostEqSINRSource", "PostEqSINRValueRole", "PostEqSINRValueStatus"
            "MeasuredTrialSINR_dB", "MeasuredTrialSINRSource", "MeasuredTrialSINRValueRole", "MeasuredTrialSINRValueStatus"
            "MeasuredSINR_dB", "MeasuredTrialSINRSource", "MeasuredTrialSINRValueRole", "MeasuredTrialSINRValueStatus"
            "ReceiverHestSINR_dB", "ReceiverHestSINRSource", "ReceiverHestSINRValueRole", "ReceiverHestSINRValueStatus"];
        validSINR = nan(size(candidates, 1), 1);
        validSource = strings(size(candidates, 1), 1);
        validRole = strings(size(candidates, 1), 1);
        validStatus = strings(size(candidates, 1), 1);
        for i = 1:size(candidates, 1)
            candidateSINR = double(sixgr.truth.CoupledTruthRuntime.rowValue(row, candidates(i, 1), NaN));
            candidateSource = string(sixgr.truth.CoupledTruthRuntime.rowValue(row, candidates(i, 2), ""));
            candidateRole = string(sixgr.truth.CoupledTruthRuntime.rowValue(row, candidates(i, 3), ""));
            candidateStatus = string(sixgr.truth.CoupledTruthRuntime.rowValue(row, candidates(i, 4), ""));
            if isfinite(candidateSINR) && sixgr.truth.CoupledTruthRuntime.schedulerSINRProvenanceIsEligible( ...
                    candidateSource, candidateRole, candidateStatus)
                validSINR(i) = double(candidateSINR);
                validSource(i) = candidateSource;
                validRole(i) = candidateRole;
                validStatus(i) = candidateStatus;
            end
        end
        valid = isfinite(validSINR);
        if ~any(valid)
            return;
        end
        receiverIdx = find(valid & candidates(:, 1) == "ReceiverHestSINR_dB", 1, "first");
        postEqIdx = find(valid & (candidates(:, 1) == "MeasuredSINR_dB" | ...
            candidates(:, 1) == "MeasuredTrialSINR_dB" | candidates(:, 1) == "PostEqSINR_dB"), 1, "first");
        if ~isempty(receiverIdx) && ~isempty(postEqIdx)
            if validSINR(receiverIdx) <= validSINR(postEqIdx)
                chosenIdx = receiverIdx;
            else
                chosenIdx = postEqIdx;
            end
            sinr_dB = double(validSINR(chosenIdx));
            source = "measured_scheduler_csi_conservative_min_channel_estimate_posteq";
            role = "measured_post_equalization_scheduling_input";
            status = "OK";
            return;
        end
        firstIdx = find(valid, 1, "first");
        sinr_dB = double(validSINR(firstIdx));
        [source, role, status] = sixgr.truth.CoupledTruthRuntime.schedulerCQIResolverSINRProvenance( ...
            validSource(firstIdx), validRole(firstIdx), validStatus(firstIdx));
    end

    function [source, role, status] = schedulerCQIResolverSINRProvenance(sourceIn, roleIn, statusIn)
        source = string(sourceIn);
        role = string(roleIn);
        status = string(statusIn);
        token = lower(strjoin([source role], " "));
        if contains(token, "measured_scheduler_csi") || contains(token, "post_equalization") || ...
                contains(token, "receiver_hest") || contains(token, "reference_signal_measurement") || ...
                contains(token, "channel_estimate")
            source = "measured_scheduler_csi_runtime_receiver_sinr";
            role = "measured_post_equalization_scheduling_input";
            if strlength(strtrim(status)) == 0 || lower(strtrim(status)) == "pass"
                status = "OK";
            end
        end
    end

    function tf = rowCQIHasMeasuredCSIProvenance(row)
        source = lower(strtrim(string(sixgr.truth.CoupledTruthRuntime.rowFirstString(row, ...
            ["CQIValueSource","CQIProvenance","WidebandCQISource"], ""))));
        status = lower(strtrim(string(sixgr.truth.CoupledTruthRuntime.rowFirstString(row, ...
            ["CQIValueStatus","WidebandCQIValueStatus"], ""))));
        if strlength(source) == 0 && strlength(status) == 0
            tf = false;
            return;
        end
        blocked = any(contains(source, ["bootstrap","fallback","proxy","stale","configured","unavailable"])) || ...
            any(contains(status, ["bootstrap","fallback","proxy","stale","configured","unavailable","failed","rejected"]));
        tf = ~blocked && (contains(source, "csi") || contains(source, "cqi") || contains(source, "ue_report"));
    end

    function grant = applyMeasuredFeedbackRankToGrant(grant, feedback, cfg, direction)
        finalizedGrant = logical(sixgr.util.structGet(grant, "ExactPHYFeasibilityChecked", false));
        phyGrant = sixgr.util.structGet(grant, "PHYGrant", struct());
        if ~finalizedGrant && isstruct(phyGrant) && ~isempty(fieldnames(phyGrant))
            finalizedGrant = true;
        end
        if finalizedGrant
            executableRICandidates = [ ...
                double(sixgr.util.structGet(grant, "NumLayers", NaN)), ...
                double(sixgr.util.structGet(grant, "Layers", NaN)), ...
                double(sixgr.util.structGet(grant, "RIUsed", NaN))];
            executableRI = sixgr.truth.CoupledTruthRuntime.firstNumeric(executableRICandidates, NaN);
            if isfinite(double(executableRI)) && double(executableRI) >= 1
                nLayers = max(1, min(sixgr.truth.CoupledTruthRuntime.resolveMaxGrantLayers(cfg, direction), round(double(executableRI))));
                grant.RI = double(nLayers);
                grant.RIUsed = double(nLayers);
                grant.Rank = double(nLayers);
                grant.RankIndicator = double(nLayers);
                grant.NumLayers = double(nLayers);
                grant.Layers = double(nLayers);
                grant.PrecodingNumLayers = double(nLayers);
                grant.PMI = double(sixgr.truth.CoupledTruthRuntime.sanitizeFeedbackPMI( ...
                    sixgr.util.structGet(feedback, "PMI", sixgr.util.structGet(grant, "PMI", NaN)), cfg, direction, nLayers));
                return;
            end
        end
        ri = double(sixgr.util.structGet(feedback, "RI", sixgr.util.structGet(grant, "RIUsed", NaN)));
        if ~(isfinite(ri) && ri >= 1)
            return;
        end
        nLayers = max(1, min(sixgr.truth.CoupledTruthRuntime.resolveMaxGrantLayers(cfg, direction), round(ri)));
        grant.RI = double(nLayers);
        grant.RIUsed = double(nLayers);
        grant.Rank = double(nLayers);
        grant.RankIndicator = double(nLayers);
        grant.NumLayers = double(nLayers);
        grant.Layers = double(nLayers);
        grant.PrecodingNumLayers = double(nLayers);
        grant.PMI = double(sixgr.truth.CoupledTruthRuntime.sanitizeFeedbackPMI( ...
            sixgr.util.structGet(feedback, "PMI", sixgr.util.structGet(grant, "PMI", NaN)), cfg, direction, nLayers));
    end

    function tf = smallPRBWidebandFeedbackGuardApplies(grant, feedback, cfg, direction, candidateMCS)
        tf = false;
        if upper(string(direction)) ~= "UL"
            return;
        end
        sourceToken = lower(strjoin([ ...
            string(sixgr.util.structGet(feedback, "MCSSelectionSource", "")), ...
            string(sixgr.util.structGet(feedback, "CQIProvenance", "")), ...
            string(sixgr.util.structGet(feedback, "MCSValueStatus", "")), ...
            string(sixgr.util.structGet(feedback, "FeedbackSourceSignal", ""))], " "));
        if ~(contains(sourceToken, "runtime") || contains(sourceToken, "measured") || ...
                contains(sourceToken, "cqi") || contains(sourceToken, "srs"))
            return;
        end
        if contains(sourceToken, "bootstrap") || contains(sourceToken, "fixed") || ...
                contains(sourceToken, "configured")
            return;
        end
        prbCount = sixgr.truth.CoupledTruthRuntime.grantPRBCount(grant);
        minPRB = sixgr.truth.CoupledTruthRuntime.smallPRBWidebandGuardMinPRB(cfg);
        if ~(isfinite(prbCount) && prbCount >= 1 && isfinite(minPRB) && prbCount < minPRB)
            return;
        end
        if sixgr.truth.CoupledTruthRuntime.feedbackHasSubbandEvidence(feedback, minPRB)
            return;
        end
        nLayers = double(sixgr.util.structGet(grant, "NumLayers", sixgr.util.structGet(grant, "Layers", 1)));
        floorMCS = sixgr.truth.CoupledTruthRuntime.smallPRBWidebandGuardMCSFloor(cfg);
        tf = round(max(1, nLayers)) > 1 || ...
            (isfinite(candidateMCS) && round(candidateMCS) >= floorMCS);
    end

    function prbCount = grantPRBCount(grant)
        prbSet = double(sixgr.util.structGet(grant, "PRBSet", []));
        if ~isempty(prbSet)
            prbCount = double(numel(prbSet));
            return;
        end
        prbCount = double(sixgr.util.structGet(grant, "AllocatedPRBCount", ...
            sixgr.util.structGet(grant, "PRBCount", NaN)));
    end

    function tf = feedbackHasSubbandEvidence(feedback, minPRB)
        tf = false;
        requiredBins = max(1, round(double(minPRB)));
        for fieldName = ["AgedSubbandSINRVector_dB","SubbandSINRVector_dB"]
            values = sixgr.truth.CoupledTruthRuntime.parseNumericVector( ...
                sixgr.util.structGet(feedback, fieldName, ""));
            values = values(isfinite(values));
            if numel(values) >= requiredBins
                tf = true;
                return;
            end
        end
    end

    function minPRB = smallPRBWidebandGuardMinPRB(cfg)
        carrierPRB = double(sixgr.util.structGet(cfg, "phy.carrier.NSizeGrid", ...
            sixgr.util.structGet(cfg, "phy.pusch.nPRB", ...
            sixgr.util.structGet(cfg, "phy.pdsch.nPRB", 106))));
        minPRB = double(sixgr.util.structGet(cfg, "phy.linkAdaptation.minPRBForWidebandCQIGrant", ...
            sixgr.util.structGet(cfg, "mac.scheduler.minPRBPerUE", NaN)));
        if ~(isfinite(minPRB) && minPRB >= 1)
            minPRB = max(4, ceil(0.02 * max(1, carrierPRB)));
        end
        minPRB = max(1, round(minPRB));
    end

    function floorMCS = smallPRBWidebandGuardMCSFloor(cfg)
        floorMCS = double(sixgr.util.structGet(cfg, "phy.linkAdaptation.smallPRBWidebandCQIMCSFloor", 10));
        if ~(isfinite(floorMCS) && floorMCS >= 0)
            floorMCS = 10;
        end
        floorMCS = round(floorMCS);
    end

    function [mcsIndex, modStr, targetCodeRate] = smallPRBWidebandGuardMCS(cfg, direction, mcsTable, requestedMCS)
        floorMCS = sixgr.truth.CoupledTruthRuntime.smallPRBWidebandGuardMCSFloor(cfg);
        defaultGuardMCS = double(sixgr.util.structGet(cfg, "phy.linkAdaptation.smallPRBWidebandCQIGuardMCSIndex", ...
            sixgr.util.structGet(cfg, "phy.linkAdaptation.bootstrapMCSIndex", 1)));
        if ~(isfinite(defaultGuardMCS) && defaultGuardMCS >= 0)
            defaultGuardMCS = 1;
        end
        maxGuardMCS = max(0, floorMCS - 1);
        if isfinite(requestedMCS)
            maxGuardMCS = min(maxGuardMCS, round(double(requestedMCS)));
        end
        mcsIndex = max(0, min(maxGuardMCS, round(defaultGuardMCS)));
        profile = sixgr.link.resolveMCSProfile(mcsTable, mcsIndex);
        while ~(logical(sixgr.util.structGet(profile, "Valid", false))) && mcsIndex > 0
            mcsIndex = mcsIndex - 1;
            profile = sixgr.link.resolveMCSProfile(mcsTable, mcsIndex);
        end
        if logical(sixgr.util.structGet(profile, "Valid", false))
            modStr = char(string(profile.Modulation));
            targetCodeRate = double(profile.TargetCodeRate);
        else
            [modStr, targetCodeRate, mcsIndex] = sixgr.link.amcFromCQI(1, "", NaN, cfg, direction);
            mcsIndex = max(0, min(maxGuardMCS, round(double(mcsIndex))));
            profile = sixgr.link.resolveMCSProfile(mcsTable, mcsIndex);
            if logical(sixgr.util.structGet(profile, "Valid", false))
                modStr = char(string(profile.Modulation));
                targetCodeRate = double(profile.TargetCodeRate);
            else
                modStr = "QPSK";
                targetCodeRate = 120 / 1024;
                mcsIndex = 0;
            end
        end
    end

    function grant = forceSingleLayerSmallPRBGuard(grant, feedback, cfg, direction)
        nLayers = 1;
        grant.RI = double(nLayers);
        grant.RIUsed = double(nLayers);
        grant.Rank = double(nLayers);
        grant.RankIndicator = double(nLayers);
        grant.NumLayers = double(nLayers);
        grant.Layers = double(nLayers);
        grant.PrecodingNumLayers = double(nLayers);
        grant.PMI = double(sixgr.truth.CoupledTruthRuntime.sanitizeFeedbackPMI( ...
            sixgr.util.structGet(feedback, "PMI", sixgr.util.structGet(grant, "PMI", NaN)), cfg, direction, nLayers));
    end

    function maxLayers = resolveMaxGrantLayers(cfg, direction)
        direction = upper(string(direction));
        if direction == "UL"
            candidates = [ ...
                "phy.pusch.maxLayers"
                "phy.maxULLayers"
                "phy.pusch.nLayers"
                "phy.pusch.numLayers"
                "phy.pusch.dmrs.nPorts"];
        else
            candidates = [ ...
                "phy.pdsch.maxLayers"
                "phy.maxDLLayers"
                "phy.pdsch.nLayers"
                "phy.pdsch.numLayers"
                "phy.pdsch.dmrs.nPorts"];
        end
        vals = nan(numel(candidates), 1);
        for i = 1:numel(candidates)
            vals(i) = double(sixgr.util.structGet(cfg, candidates(i), NaN));
        end
        vals = vals(isfinite(vals) & vals >= 1);
        if isempty(vals)
            maxLayers = 1;
        else
            maxLayers = max(1, round(min(vals)));
        end
    end

    function previousState = linkAdaptationStateForUE(state, direction, ueIdx)
        previousState = struct();
        direction = upper(string(direction));
        if direction == "UL"
            fieldName = "ULLinkAdaptationState";
        else
            fieldName = "DLLinkAdaptationState";
        end
        if ~(isfield(state, fieldName) && iscell(state.(fieldName)) && ...
                ueIdx >= 1 && ueIdx <= numel(state.(fieldName)))
            return;
        end
        candidate = state.(fieldName){ueIdx};
        if isstruct(candidate)
            previousState = candidate;
        end
    end

    function state = setLinkAdaptationStateForUE(state, direction, ueIdx, nextState)
        direction = upper(string(direction));
        if direction == "UL"
            fieldName = "ULLinkAdaptationState";
        else
            fieldName = "DLLinkAdaptationState";
        end
        if ~(isfield(state, fieldName) && iscell(state.(fieldName)))
            state.(fieldName) = cell(max(0, double(sixgr.util.structGet(state, "NumUsers", ueIdx))), 1);
        end
        if ueIdx > numel(state.(fieldName))
            state.(fieldName){ueIdx, 1} = [];
        end
        state.(fieldName){ueIdx} = nextState;
    end

    function previousState = seedRuntimeLinkAdaptationState(cfg, direction, previousState, servingCell)
        if nargin < 3 || ~isstruct(previousState)
            previousState = struct();
        end
        servingCell = double(servingCell);
        initialized = logical(sixgr.util.structGet(previousState, "Initialized", false));
        previousServingCell = double(sixgr.util.structGet(previousState, "ServingCell", NaN));
        servingChanged = initialized && isfinite(previousServingCell) && isfinite(servingCell) && ...
            abs(previousServingCell - servingCell) > 1e-9;
        if initialized && ~servingChanged
            return;
        end
        bootstrapMCS = max(0, min(31, round(double(sixgr.util.structGet(cfg, ...
            "phy.linkAdaptation.bootstrapMCSIndex", 1)))));
        bootstrapCQI = 0;
        previousState = struct( ...
            "Direction", char(upper(string(direction))), ...
            "Initialized", true, ...
            "CQIBasedMCS", double(bootstrapMCS), ...
            "LastMCSIndex", double(bootstrapMCS), ...
            "LastInstantaneousMCS", double(bootstrapMCS), ...
            "SmoothedCQI", double(bootstrapCQI), ...
            "LastCQI", double(bootstrapCQI), ...
            "LastRI", NaN, ...
            "DeltaMCS", 0, ...
            "UpdateCount", 0, ...
            "ServingCell", double(servingCell), ...
            "LastResetReason", "bootstrap_seed");
        if servingChanged
            previousState.LastResetReason = "serving_cell_change";
        end
    end

    function budget = defaultSlotBudget(state)
        symbolsPerSlot = max(1, round(double(sixgr.util.structGet(state, "SymbolsPerSlot", ...
            sixgr.util.structGet(sixgr.util.structGet(state, "CfgMobility", struct()), "phy.numerology.symbolsPerSlot", 14)))));
        budget = struct("NPRB", max(1, round(double(state.NumRB))), "SymbolAllocation", [0 double(symbolsPerSlot)]);
        direction = upper(string(sixgr.util.structGet(state, "CurrentDirection", "DL")));
        if direction == "UL"
            budget.SymbolAllocation = [ ...
                double(sixgr.util.structGet(state, "CurrentSlotULSymbolStart", 0)), ...
                double(sixgr.util.structGet(state, "CurrentSlotULNumSymbols", symbolsPerSlot))];
        else
            budget.SymbolAllocation = [ ...
                double(sixgr.util.structGet(state, "CurrentSlotDLSymbolStart", 0)), ...
                double(sixgr.util.structGet(state, "CurrentSlotDLNumSymbols", symbolsPerSlot))];
            dlWindowStart = max(0, round(double(budget.SymbolAllocation(1))));
            dlWindowEnd = min(double(symbolsPerSlot), dlWindowStart + max(0, round(double(budget.SymbolAllocation(2)))));
            pdcchSymbols = double(sixgr.util.structGet(state.CfgMobility, "phy.pdcch.coreset.duration", ...
                sixgr.util.structGet(state.CfgMobility, "phy.pdcch.numSymbols", ...
                sixgr.util.structGet(state.CfgMobility, "ctrl6gr.CORESET.DurationSymbols", 1))));
            if ~(isscalar(pdcchSymbols) && isfinite(pdcchSymbols) && pdcchSymbols >= 0)
                pdcchSymbols = 1;
            end
            pdcchRuntimeRequired = logical(sixgr.util.structGet(state.ControlGating, "PDCCHRequired", false));
            reserveCoresetSymbols = pdcchRuntimeRequired || logical(sixgr.util.structGet(state.CfgMobility, ...
                "phy.pdcch.reserveCoresetSymbolsForData", false));
            if reserveCoresetSymbols && pdcchSymbols > 0
                startSym = max(dlWindowStart, ceil(pdcchSymbols));
                startSym = min(max(0, startSym), dlWindowEnd);
                remainingDLSymbols = max(0, dlWindowEnd - startSym);
                budget.SymbolAllocation = [startSym remainingDLSymbols];
                if remainingDLSymbols <= 0
                    budget.NPRB = 0;
                    budget.PRBSet = zeros(1, 0);
                end
            end
        end
        if logical(sixgr.util.structGet(state.ControlGating, "PDCCHRequired", false))
            pdcchCCEBudget = sixgr.truth.CoupledTruthRuntime.resolveSchedulerPDCCHCCEBudget(state.CfgMobility);
            if isfinite(pdcchCCEBudget) && pdcchCCEBudget > 0
                defaultAL = sixgr.truth.CoupledTruthRuntime.resolveSchedulerPDCCHPlanningAggregationLevel(state.CfgMobility);
                budget.PDCCHCCEBudget = double(pdcchCCEBudget);
                budget.DefaultPDCCHAggregationLevel = double(defaultAL);
                budget.MaxUEPerSlot = max(1, floor(double(pdcchCCEBudget) / max(1, double(defaultAL))));
            end
        end
    end

    function availCCEs = resolveSchedulerPDCCHCCEBudget(cfg)
        freqResources = double(sixgr.util.structGet(cfg, "phy.pdcch.coreset.frequencyResources", []));
        if isempty(freqResources)
            freqResources = ones(1, 6);
        end
        duration = double(sixgr.util.structGet(cfg, "phy.pdcch.coreset.duration", 2));
        if ~(isfinite(duration) && duration > 0)
            availCCEs = NaN;
            return;
        end
        numREG = 6 * sum(freqResources(:) ~= 0) * duration;
        availCCEs = floor(numREG / 6);
    end

    function aggLevel = resolveSchedulerPDCCHAggregationLevel(cfg, snr_dB)
        levels = double(sixgr.util.structGet(cfg, "phy.pdcch.aggregationLevels", ...
            sixgr.util.structGet(cfg, "control.aggregation_levels", ...
            sixgr.util.structGet(cfg, "ctrl6gr.StudyAggregationLevels", ...
            sixgr.util.structGet(cfg, "phy.pdcch.aggregationLevel", 4)))));
        levels = unique(levels(ismember(levels, [1 2 4 8 16])), "stable");
        if isempty(levels)
            levels = 4;
        end
        policy = lower(strtrim(string(sixgr.util.structGet(cfg, "phy.pdcch.aggregationSelectionPolicy", "snr_threshold"))));
        configuredAL = double(sixgr.util.structGet(cfg, "phy.pdcch.schedulerAggregationLevel", NaN));
        if policy == "configured_scheduler_level" && isfinite(configuredAL)
            [~, idx] = min(abs(levels - configuredAL));
            aggLevel = double(levels(idx));
            return;
        end
        if policy == "most_robust"
            aggLevel = max(levels);
            return;
        end
        snr_dB = double(snr_dB);
        if ~isfinite(snr_dB)
            target = 4;
        elseif snr_dB < 0
            target = 16;
        elseif snr_dB < 5
            target = 8;
        elseif snr_dB < 10
            target = 4;
        elseif snr_dB < 15
            target = 2;
        else
            target = 1;
        end
        [~, idx] = min(abs(double(levels(:)) - double(target)));
        aggLevel = double(levels(idx));
    end

    function aggLevel = resolveSchedulerPDCCHPlanningAggregationLevel(cfg)
        levels = double(sixgr.util.structGet(cfg, "phy.pdcch.aggregationLevels", ...
            sixgr.util.structGet(cfg, "control.aggregation_levels", ...
            sixgr.util.structGet(cfg, "ctrl6gr.StudyAggregationLevels", ...
            sixgr.util.structGet(cfg, "phy.pdcch.aggregationLevel", 4)))));
        levels = unique(levels(ismember(levels, [1 2 4 8 16])), "stable");
        if isempty(levels)
            levels = 4;
        end
        policy = lower(strtrim(string(sixgr.util.structGet(cfg, "phy.pdcch.aggregationSelectionPolicy", "snr_threshold"))));
        configuredAL = double(sixgr.util.structGet(cfg, "phy.pdcch.schedulerAggregationLevel", NaN));
        if policy == "configured_scheduler_level" && isfinite(configuredAL)
            [~, idx] = min(abs(levels - configuredAL));
            aggLevel = double(levels(idx));
        elseif policy == "most_robust"
            aggLevel = double(max(levels));
        else
            aggLevel = double(min(levels));
        end
    end

    function layerPath = localDirectionLayerPath(direction)
        if upper(string(direction)) == "UL"
            layerPath = "phy.pusch.nLayers";
        else
            layerPath = "phy.pdsch.nLayers";
        end
    end

    function grant = buildGrantSnapshot(cfgU, row, direction, ueIdx, rnti)
        direction = upper(string(direction));
        if direction == "UL"
            root = "phy.pusch";
        else
            root = "phy.pdsch";
        end
        grant = struct( ...
            "Direction", char(direction), ...
            "UEIndex", double(ueIdx), ...
            "RNTI", double(rnti), ...
            "MCS", double(sixgr.truth.CoupledTruthRuntime.rowValue(row, "MCS", NaN)), ...
            "Modulation", char(string(sixgr.truth.CoupledTruthRuntime.rowValue(row, "Modulation", ""))), ...
            "TargetCodeRate", double(sixgr.truth.CoupledTruthRuntime.rowValue(row, "TargetCodeRate", NaN)), ...
            "Layers", double(sixgr.truth.CoupledTruthRuntime.rowValue(row, "Layers", NaN)), ...
            "PRBs", double(sixgr.truth.CoupledTruthRuntime.rowValue(row, "PRBs", NaN)), ...
            "PRBSet", sixgr.util.structGet(cfgU, root + ".prbSet", []), ...
            "SymbolAllocation", sixgr.util.structGet(cfgU, root + ".symbolAllocation", []), ...
            "MappingType", char(string(sixgr.util.structGet(cfgU, root + ".mappingType", ""))), ...
            "TransformPrecoding", logical(sixgr.util.structGet(cfgU, root + ".transformPrecoding", false)));
    end

    function sinr_dB = estimateWidebandSINR(rxPower_dBm, servingCell, bandwidth_Hz, noiseFigure_dB)
        sinr_dB = NaN;
        rxPower_dBm = double(rxPower_dBm(:).');
        if isempty(rxPower_dBm) || ~(isfinite(servingCell) && servingCell >= 1 && servingCell <= numel(rxPower_dBm))
            return;
        end
        desired_dBm = double(rxPower_dBm(servingCell));
        desired_mW = 10.^(desired_dBm / 10);
        mask = true(size(rxPower_dBm));
        mask(servingCell) = false;
        interferer_mW = 10.^(double(rxPower_dBm(mask)) / 10);
        interferer_mW = interferer_mW(isfinite(interferer_mW) & interferer_mW >= 0);
        noise_dBm = -174 + 10 * log10(max(double(bandwidth_Hz), eps)) + double(noiseFigure_dB);
        noise_mW = 10.^(noise_dBm / 10);
        denom = sum(interferer_mW, "omitnan") + noise_mW;
        if isfinite(desired_mW) && desired_mW > 0 && isfinite(denom) && denom > 0
            sinr_dB = 10 * log10(desired_mW / denom);
        end
    end

    function sinr_dB = estimateRuntimeWidebandSINR(state, ueIdx, servingCell, interferenceMode)
        sinr_dB = NaN;
        interferenceMode = string(interferenceMode);
        if interferenceMode ~= "full_per_link_channel_waveform_sum"
            return;
        end
        if ueIdx < 1 || ueIdx > size(state.LargeScaleState.RxPower_dBm, 1)
            return;
        end
        sinr_dB = sixgr.truth.CoupledTruthRuntime.estimateWidebandSINR( ...
            state.LargeScaleState.RxPower_dBm(ueIdx, :), servingCell, state.Bandwidth_Hz, state.NoiseFigure_dB);
    end

    function mode = resolveInterferenceExecutionMode(cfg, multiUser)
        if nargin < 2 || ~isstruct(multiUser)
            multiUser = struct();
        end
        mode = string(sixgr.util.structGet(cfg, "run.interferenceExecutionMode", ""));
        if strlength(strtrim(mode)) == 0
            mode = string(sixgr.util.structGet(cfg, "interference.inter_cell_execution_mode", ""));
        end
        if strlength(strtrim(mode)) == 0
            error("sixgr:truth:MissingInterferenceExecutionMode", ...
                "Missing explicit interference execution mode in cfg.run.interferenceExecutionMode or cfg.interference.inter_cell_execution_mode.");
        end
        if any(mode == ["abstract_large_scale_scheduler_context","explicit_activity_power_sum","waveform_overlap_large_scale"])
            error("sixgr:truth:NonWaveformInterferenceModeRemoved", ...
                "interference execution mode '%s' is not allowed in no-proxy waveform LLS. Use full_per_link_channel_waveform_sum or none.", char(mode));
        end
    end

    function score = coverageScore(rsrp_dBm, sinr_dB)
        rsrpTerm = 1 ./ (1 + exp(-(double(rsrp_dBm) + 100) / 6));
        sinrTerm = 1 ./ (1 + exp(-(double(sinr_dB) - 1) / 4));
        score = max(0, min(1, 0.55 * rsrpTerm + 0.45 * sinrTerm));
    end

    function tf = schedulerSINRProvenanceIsEligible(source, role, status)
        token = lower(strjoin([string(source), string(role), string(status)], " "));
        blocked = ["evm_proxy", "proxy", "fallback", "configured", "sweep", ...
            "diagnostic", "not_scheduling", "unavailable", "failed", "rejected"];
        measuredCSI = contains(token, "post_equalization") || contains(token, "receiver_hest") || ...
            contains(token, "reference_signal_measurement") || contains(token, "channel_estimate") || ...
            contains(token, "measured_scheduler_csi");
        tf = logical(measuredCSI) && ~any(contains(token, blocked));
    end

    function value = rowValue(row, name, defaultValue)
        if nargin < 3
            defaultValue = NaN;
        end
        value = defaultValue;
        hasField = false;
        if istable(row) && height(row) >= 1 && ismember(string(name), string(row.Properties.VariableNames))
            raw = row.(name);
            hasField = true;
        elseif isstruct(row) && isscalar(row) && isfield(row, char(string(name)))
            raw = row.(char(string(name)));
            hasField = true;
        end
        if ~hasField
            return;
        end
        if isstring(raw)
            raw = string(raw(1));
            if strlength(raw) > 0
                value = raw;
            end
        elseif iscell(raw)
            raw = raw{1};
            if isstring(raw)
                raw = string(raw);
                if strlength(raw) > 0
                    value = raw;
                end
            elseif ischar(raw)
                if strlength(string(raw)) > 0
                    value = raw;
                end
            elseif islogical(raw)
                value = logical(raw(1));
            elseif isnumeric(raw)
                raw = double(raw(1));
                if isfinite(raw)
                    value = raw;
                end
            end
        elseif ischar(raw)
            if strlength(string(raw)) > 0
                value = raw;
            end
        elseif islogical(raw)
            value = logical(raw(1));
        else
            raw = double(raw(1));
            if isfinite(raw)
                value = raw;
            end
        end
    end

    function tf = rowHasField(row, name)
        if istable(row)
            tf = height(row) >= 1 && ismember(string(name), string(row.Properties.VariableNames));
        elseif isstruct(row) && isscalar(row)
            tf = isfield(row, char(string(name)));
        else
            tf = false;
        end
    end

    function rowOut = normalizeStructRowToPrototype(rowIn, prototype)
        if ~(isstruct(prototype) && isscalar(prototype))
            rowOut = rowIn;
            return;
        end
        rowOut = prototype;
        fieldNames = string(fieldnames(prototype));
        for idx = 1:numel(fieldNames)
            fieldName = char(fieldNames(idx));
            defaultValue = prototype.(fieldName);
            rawValue = sixgr.util.structGet(rowIn, fieldName, defaultValue);
            rowOut.(fieldName) = sixgr.truth.CoupledTruthRuntime.scalarValueLike(rawValue, defaultValue);
        end
    end

    function value = scalarValueLike(rawValue, defaultValue)
        if isstring(defaultValue)
            value = string(sixgr.truth.CoupledTruthRuntime.firstString(rawValue, string(defaultValue)));
            return;
        end
        if ischar(defaultValue)
            value = sixgr.truth.CoupledTruthRuntime.firstString(rawValue, defaultValue);
            return;
        end
        if islogical(defaultValue)
            if isempty(rawValue)
                value = logical(defaultValue);
                return;
            end
            if islogical(rawValue)
                flat = rawValue(:);
                value = logical(flat(1));
                return;
            end
            nums = double(rawValue(:));
            nums = nums(isfinite(nums));
            if isempty(nums)
                value = logical(defaultValue);
            else
                value = logical(nums(1) ~= 0);
            end
            return;
        end
        if isnumeric(defaultValue)
            value = double(sixgr.truth.CoupledTruthRuntime.firstNumeric(rawValue, double(defaultValue)));
            return;
        end
        value = rawValue;
    end

    function value = rowLogical(row, name, defaultValue)
        if nargin < 3
            defaultValue = false;
        end
        raw = sixgr.truth.CoupledTruthRuntime.rowValue(row, name, defaultValue);
        if islogical(raw)
            value = raw;
        else
            value = logical(raw);
        end
    end

    function value = rowFirstFinite(row, names, defaultValue)
        value = double(defaultValue);
        for i = 1:numel(names)
            candidate = double(sixgr.truth.CoupledTruthRuntime.rowValue(row, char(string(names(i))), NaN));
            if isfinite(candidate)
                value = double(candidate);
                return;
            end
        end
    end

    function value = rowFirstString(row, names, defaultValue)
        value = string(defaultValue);
        for i = 1:numel(names)
            candidate = string(sixgr.truth.CoupledTruthRuntime.rowValue(row, char(string(names(i))), ""));
            if strlength(strtrim(candidate)) > 0
                value = candidate;
                return;
            end
        end
    end

    function values = rowFirstNumericVector(row, names)
        values = [];
        for i = 1:numel(names)
            raw = sixgr.truth.CoupledTruthRuntime.rowValue(row, char(string(names(i))), []);
            values = sixgr.truth.CoupledTruthRuntime.parseNumericVector(raw);
            if ~isempty(values)
                return;
            end
        end
    end

    function values = parseNumericVector(raw)
        values = [];
        if isempty(raw)
            return;
        end
        if isnumeric(raw) || islogical(raw)
            values = double(raw(:).');
        elseif ischar(raw) || isstring(raw)
            token = strtrim(strjoin(string(raw(:).'), "|"));
            if strlength(token) == 0
                return;
            end
            parts = regexp(char(token), '[-+]?\d*\.?\d+(?:[eE][-+]?\d+)?', 'match');
            if isempty(parts)
                return;
            end
            values = str2double(string(parts(:))).';
        else
            return;
        end
        values = double(values(:).');
        values = values(isfinite(values));
    end

    function token = numericVectorToken(values)
        values = double(values(:).');
        values = values(isfinite(values));
        if isempty(values)
            token = "";
            return;
        end
        parts = strings(1, numel(values));
        for i = 1:numel(values)
            parts(i) = string(sprintf("%.6g", values(i)));
        end
        token = char(strjoin(parts, "|"));
    end

    function source = appendSourceToken(source, token)
        source = string(source);
        token = string(token);
        if strlength(strtrim(token)) == 0
            source = char(source);
            return;
        end
        if strlength(strtrim(source)) == 0
            source = char(token);
            return;
        end
        parts = strtrim(split(source, "+"));
        if any(parts == token)
            source = char(source);
        else
            source = char(source + "+" + token);
        end
    end

    function tf = trialPassed(trialT)
        tf = false;
        if ~(istable(trialT) && ~isempty(trialT))
            return;
        end
        row = trialT(end, :);
        status = upper(strtrim(string(sixgr.truth.CoupledTruthRuntime.rowValue(row, "Status", ""))));
        if status == "PASS"
            tf = true;
            return;
        end
        crcPass = sixgr.truth.CoupledTruthRuntime.rowValue(row, "CRCPass", NaN);
        if isfinite(double(crcPass))
            tf = logical(crcPass);
        end
    end

    function [tf, reason] = pdcchCausalGrantDecodePassed(trialT)
        tf = false;
        reason = "pdcch_trial_missing";
        if ~(istable(trialT) && ~isempty(trialT))
            return;
        end
        row = trialT(end, :);
        basePass = sixgr.truth.CoupledTruthRuntime.trialPassed(row);
        dciCrcPass = sixgr.truth.CoupledTruthRuntime.rowLogical(row, "DCICrcPass", basePass);
        payloadMatch = sixgr.truth.CoupledTruthRuntime.rowLogical(row, "PDCCHPayloadMatch", true);
        causalDecodeOk = sixgr.truth.CoupledTruthRuntime.rowLogical(row, "PDCCHCausalGrantDecodeOk", dciCrcPass && payloadMatch);
        falseAlarm = sixgr.truth.CoupledTruthRuntime.rowLogical(row, "PDCCHFalseAlarm", false);
        missedDetection = sixgr.truth.CoupledTruthRuntime.rowLogical(row, "PDCCHMissedDetection", false);
        tf = logical(basePass && dciCrcPass && payloadMatch && causalDecodeOk && ~falseAlarm && ~missedDetection);
        if tf
            reason = "pdcch_dci_crc_and_payload_match";
        elseif ~basePass
            reason = "pdcch_trial_not_passed";
        elseif ~dciCrcPass
            reason = "pdcch_dci_crc_failed";
        elseif ~payloadMatch
            reason = "pdcch_dci_payload_mismatch";
        elseif falseAlarm
            reason = "pdcch_false_alarm_payload_rejected";
        elseif missedDetection
            reason = "pdcch_missed_detection";
        else
            reason = "pdcch_causal_grant_decode_rejected";
        end
    end

    function tf = trsRuntimeEvidenceComplete(row)
        tf = false;
        if ~(istable(row) && height(row) >= 1)
            return;
        end
        proxyClean = ~sixgr.truth.CoupledTruthRuntime.rowAnyLogical(row, ["ProxyUsed","Skipped","ToolboxMissing"], false) && ...
            strlength(strtrim(string(sixgr.truth.CoupledTruthRuntime.rowValue(row, "UsedOracleFields", "")))) == 0;
        detectionAttempted = sixgr.truth.CoupledTruthRuntime.rowAnyLogical(row, ...
            ["DetectionAttempted","TRSDetectionAttempted"], false);
        detectionAvailable = sixgr.truth.CoupledTruthRuntime.rowAnyLogical(row, ...
            ["DetectionSuccess","TRSDetected","DetectionUsable"], false);
        timingAttempted = sixgr.truth.CoupledTruthRuntime.rowAnyLogical(row, ...
            ["TimingTrackingAttempted","TRSTimingEstimateAttempted","TimingEstimateAttempted"], false);
        timingAvailable = sixgr.truth.CoupledTruthRuntime.rowAnyLogical(row, ...
            ["TRSTimingEstimateAvailable","TimingEstimateAvailable"], false) && ...
            isfinite(sixgr.truth.CoupledTruthRuntime.rowFirstFinite(row, ...
            ["EstimatedTimingOffset_samples","TimingEstimate_samples","TimingOffset_samples"], NaN));
        hasTimingUsableFlag = sixgr.truth.CoupledTruthRuntime.rowHasField(row, "TRSTimingEstimateUsable") || ...
            sixgr.truth.CoupledTruthRuntime.rowHasField(row, "TimingEstimateUsable");
        timingUsable = sixgr.truth.CoupledTruthRuntime.rowAnyLogical(row, ...
            ["TRSTimingEstimateUsable","TimingEstimateUsable"], false);
        if ~hasTimingUsableFlag
            timingUsable = logical(timingAvailable);
        end
        frequencyAttempted = sixgr.truth.CoupledTruthRuntime.rowAnyLogical(row, ...
            ["FrequencyTrackingAttempted","TRSCFOEstimateAttempted","CFOEstimateAttempted"], false);
        frequencyAvailable = sixgr.truth.CoupledTruthRuntime.rowAnyLogical(row, ...
            ["TRSCFOEstimateAvailable","CFOEstimateAvailable"], false) && ...
            isfinite(sixgr.truth.CoupledTruthRuntime.rowFirstFinite(row, ...
            ["EstimatedCFO_Hz","EstimatedCFO_PreCorrection_Hz"], NaN));
        hasFrequencyUsableFlag = sixgr.truth.CoupledTruthRuntime.rowHasField(row, "TRSCFOEstimateUsable") || ...
            sixgr.truth.CoupledTruthRuntime.rowHasField(row, "CFOEstimateUsable");
        frequencyUsable = sixgr.truth.CoupledTruthRuntime.rowAnyLogical(row, ...
            ["TRSCFOEstimateUsable","CFOEstimateUsable"], false);
        if ~hasFrequencyUsableFlag
            frequencyUsable = logical(frequencyAvailable);
        end
        channelAttempted = sixgr.truth.CoupledTruthRuntime.rowAnyLogical(row, ...
            ["ChannelEstimationAttempted","TRSChannelEstimationAttempted"], false);
        channelAvailable = sixgr.truth.CoupledTruthRuntime.rowAnyLogical(row, ...
            ["TRSChannelEstimateAvailable","ChannelEstimateAvailable"], false) && ...
            isfinite(sixgr.truth.CoupledTruthRuntime.rowFirstFinite(row, ["NMSE_dB"], NaN));
        runtimeUsable = sixgr.truth.CoupledTruthRuntime.rowAnyLogical(row, ...
            ["TRSRuntimeEvidenceUsable","RuntimeEvidenceUsable","MeasurementUsable"], false);
        tf = proxyClean && (runtimeUsable || (detectionAttempted && detectionAvailable && ...
            timingAttempted && timingAvailable && timingUsable && frequencyAttempted && ...
            frequencyAvailable && frequencyUsable && channelAttempted && channelAvailable));
    end

    function tf = srsRuntimeEvidenceComplete(row)
        tf = false;
        if ~(istable(row) && height(row) >= 1)
            return;
        end
        proxyClean = ~sixgr.truth.CoupledTruthRuntime.rowAnyLogical(row, ...
            ["ProxyUsed","Skipped","ToolboxMissing"], false) && ...
            strlength(strtrim(string(sixgr.truth.CoupledTruthRuntime.rowValue(row, "UsedOracleFields", "")))) == 0;
        detectionAttempted = sixgr.truth.CoupledTruthRuntime.rowAnyLogical(row, ...
            ["DetectionAttempted","SRSDetectionAttempted"], false);
        detectionAvailable = sixgr.truth.CoupledTruthRuntime.rowAnyLogical(row, ...
            ["DetectionSuccess","SRSDetected","DetectionUsable"], false);
        resourceAttempted = sixgr.truth.CoupledTruthRuntime.rowAnyLogical(row, ...
            ["ResourceExtractionAttempted","SRSResourceExtractionAttempted"], false);
        resourceAvailable = sixgr.truth.CoupledTruthRuntime.rowAnyLogical(row, ...
            ["ResourceExtractionAvailable","SRSResourceExtractionAvailable"], false);
        channelAttempted = sixgr.truth.CoupledTruthRuntime.rowAnyLogical(row, ...
            ["ChannelEstimateAttempted","ChannelEstimationAttempted","SRSChannelEstimationAttempted"], false);
        channelAvailable = sixgr.truth.CoupledTruthRuntime.rowAnyLogical(row, ...
            ["SRSChannelEstimateAvailable","ChannelEstimateAvailable"], false);
        measurementUsable = sixgr.truth.CoupledTruthRuntime.rowAnyLogical(row, ...
            ["SRSRuntimeEvidenceUsable","StrictReceiverEvidenceOk","MeasurementUsable"], false);
        hasCausalMetric = isfinite(sixgr.truth.CoupledTruthRuntime.rowFirstFinite(row, ...
            ["MeasuredTrialSINR_dB","ReceiverHestSINR_dB","SINR_dB","WidebandCQI","RankEstimate","RIEstimate"], NaN));
        nmse = sixgr.truth.CoupledTruthRuntime.rowFirstFinite(row, ["NMSE_dB","TrueChannelNMSE_dB"], NaN);
        nmseThreshold = sixgr.truth.CoupledTruthRuntime.rowFirstFinite(row, ["ChannelNMSEThreshold_dB"], -8);
        if ~(isfinite(nmseThreshold))
            nmseThreshold = -8;
        end
        nmseUsable = isfinite(nmse) && nmse <= nmseThreshold;
        tf = logical(proxyClean && detectionAttempted && detectionAvailable && ...
            resourceAttempted && resourceAvailable && channelAttempted && ...
            channelAvailable && measurementUsable && hasCausalMetric && nmseUsable);
    end

    function value = rowAnyLogical(row, names, defaultValue)
        value = logical(defaultValue);
        for i = 1:numel(names)
            name = char(string(names(i)));
            if istable(row) && ismember(name, row.Properties.VariableNames)
                value = value || sixgr.truth.CoupledTruthRuntime.rowLogical(row, name, false);
            end
        end
    end

    function value = controlStateAt(state, fieldName, ueIdx, defaultValue)
        value = string(defaultValue);
        raw = sixgr.util.structGet(state, fieldName, []);
        if isempty(raw) || ueIdx < 1 || ueIdx > numel(raw)
            return;
        end
        item = string(raw(ueIdx));
        if strlength(strtrim(item)) > 0
            value = item;
        end
    end

    function value = controlLogicalAt(state, fieldName, ueIdx, defaultValue)
        value = logical(defaultValue);
        raw = sixgr.util.structGet(state, fieldName, []);
        if isempty(raw) || ueIdx < 1 || ueIdx > numel(raw)
            return;
        end
        value = logical(raw(ueIdx));
    end

    function value = numericStateAt(state, fieldName, ueIdx, defaultValue)
        value = double(defaultValue);
        raw = double(sixgr.util.structGet(state, fieldName, []));
        if isempty(raw) || ueIdx < 1 || ueIdx > numel(raw)
            return;
        end
        if isfinite(raw(ueIdx))
            value = double(raw(ueIdx));
        end
    end

    function value = numericServingStateAt(state, fieldName, servingCell, defaultValue)
        value = double(defaultValue);
        raw = double(sixgr.util.structGet(state, fieldName, []));
        if isempty(raw) || servingCell < 1 || servingCell > numel(raw)
            return;
        end
        if isfinite(raw(servingCell))
            value = double(raw(servingCell));
        end
    end

    function age = srsAgeSlots(state, ueIdx)
        age = NaN;
        lastSuccess = sixgr.truth.CoupledTruthRuntime.numericStateAt(state, "LastSuccessfulSRSSlotByUE", ueIdx, NaN);
        currentSlot = double(sixgr.util.structGet(state, "CurrentSlot", NaN));
        if isfinite(lastSuccess) && isfinite(currentSlot)
            age = max(0, currentSlot - lastSuccess);
        end
    end

    function age = trsAgeSlotsForServingCell(state, servingCell)
        age = NaN;
        servingCell = round(double(servingCell));
        if ~(isfinite(servingCell) && servingCell >= 1)
            return;
        end
        lastSuccess = sixgr.truth.CoupledTruthRuntime.numericServingStateAt(state, "LastSuccessfulTRSSlotByCell", servingCell, NaN);
        currentSlot = double(sixgr.util.structGet(state, "CurrentSlot", NaN));
        if isfinite(lastSuccess) && isfinite(currentSlot)
            age = max(0, currentSlot - lastSuccess);
        end
    end

    function tf = trsEligibleForServingCell(state, servingCell)
        tf = false;
        servingCell = round(double(servingCell));
        if ~(isfinite(servingCell) && servingCell >= 1)
            return;
        end
        states = string(sixgr.util.structGet(state, "TRSValidityStateByCell", strings(0, 1)));
        eligibility = logical(sixgr.util.structGet(state, "TrackingEligibilityByCell", false(0, 1)));
        if servingCell > numel(states) || servingCell > numel(eligibility)
            return;
        end
        tf = logical(eligibility(servingCell)) && states(servingCell) == "valid";
    end

    function value = trsStateForUE(state, ueIdx)
        value = "unknown";
        servingVec = double(sixgr.util.structGet(state, "CurrentServingIdx", []));
        if ueIdx < 1 || ueIdx > numel(servingVec)
            return;
        end
        servingCell = round(double(servingVec(ueIdx)));
        states = string(sixgr.util.structGet(state, "TRSValidityStateByCell", strings(0, 1)));
        if servingCell >= 1 && servingCell <= numel(states)
            value = string(states(servingCell));
        end
    end

    function ctx = resolveTRSRuntimeContext(state, cfg, ueIdx, servingCell)
        if nargin < 4 || ~(isfinite(double(servingCell)) && double(servingCell) >= 1)
            servingCell = NaN;
            servingVec = double(sixgr.util.structGet(state, "CurrentServingIdx", []));
            if isfinite(double(ueIdx)) && ueIdx >= 1 && ueIdx <= numel(servingVec)
                servingCell = double(servingVec(ueIdx));
            end
        end
        trsEnabled = logical(sixgr.util.structGet(cfg, "phy.trs.enable", false));
        trsGatingActive = logical(sixgr.util.structGet(sixgr.util.structGet(state, "ControlGating", struct()), "TRSRequired", false));
        validity = "inactive";
        trackingEligible = false;
        trsAgeSlots = NaN;
        lastSuccess = NaN;
        lastDoppler = NaN;
        trackingRow = sixgr.truth.CoupledTruthRuntime.receiverTrackingRowForServingCell(state, servingCell);
        trsProcessed = logical(sixgr.util.structGet(trackingRow, "TRSProcessed", false));
        receiverConsumerType = string(sixgr.util.structGet(trackingRow, "ReceiverConsumerType", ""));
        trackingStateBefore = string(sixgr.util.structGet(trackingRow, "TRSTrackingStateBefore", ""));
        trackingStateAfter = string(sixgr.util.structGet(trackingRow, "TRSTrackingStateAfter", ...
            sixgr.util.structGet(trackingRow, "TrackingState", "")));
        updateOutcome = string(sixgr.util.structGet(trackingRow, "TRSUpdateOutcome", ""));
        channelFreshness = string(sixgr.util.structGet(trackingRow, "ChannelTrackingFreshnessState", ""));
        frequencyState = string(sixgr.util.structGet(trackingRow, "FrequencyTrackingState", ""));
        timingState = string(sixgr.util.structGet(trackingRow, "TimingTrackingState", ""));
        timingEstimateAvailable = logical(sixgr.util.structGet(trackingRow, "TimingEstimateAvailable", false));
        timingEstimateSamples = double(sixgr.util.structGet(trackingRow, "TimingEstimate_samples", NaN));
        cfoEstimateAvailable = logical(sixgr.util.structGet(trackingRow, "CFOEstimateAvailable", false));
        estimatedCFOHz = double(sixgr.util.structGet(trackingRow, "EstimatedCFO_Hz", NaN));
        estimatedOscillatorCFOHz = double(sixgr.util.structGet(trackingRow, "EstimatedOscillatorCFO_Hz", estimatedCFOHz));
        estimatedCommonFrequencyHz = double(sixgr.util.structGet(trackingRow, "EstimatedCommonFrequency_Hz", NaN));
        physicalDopplerHz = double(sixgr.util.structGet(trackingRow, "PhysicalDoppler_Hz", NaN));
        evidenceSource = string(sixgr.util.structGet(trackingRow, "RuntimeEvidenceSource", ""));
        trackingUpdateTime = double(sixgr.util.structGet(trackingRow, "TRSTrackingUpdateTime_s", NaN));
        if trsEnabled
            validity = sixgr.truth.CoupledTruthRuntime.trsStateForUE(state, ueIdx);
            trackingEligible = logical(sixgr.truth.CoupledTruthRuntime.trsEligibleForServingCell(state, servingCell));
            trsAgeSlots = double(sixgr.truth.CoupledTruthRuntime.trsAgeSlotsForServingCell(state, servingCell));
            lastSuccess = double(sixgr.truth.CoupledTruthRuntime.numericServingStateAt(state, "LastSuccessfulTRSSlotByCell", servingCell, NaN));
            lastDoppler = double(sixgr.truth.CoupledTruthRuntime.numericServingStateAt(state, "LastEstimatedTRSDopplerHzByCell", servingCell, NaN));
        end
        if trsEnabled
            if trsProcessed
                if strlength(strtrim(receiverConsumerType)) == 0
                    receiverConsumerType = "shared_receiver_tracking_state";
                end
                runtimeConsumer = receiverConsumerType;
                receiverStatus = "integrated_shared_tracking_object";
                receiverBlocker = "";
                influenceDefinition = "shared_receiver_tracking_state_feeds_scheduler_eligibility_when_trs_gating_active";
                influencedDecision = logical(trsGatingActive && trackingEligible);
                if ~trsGatingActive
                    influenceDefinition = "trs_updates_shared_receiver_tracking_state_without_scheduler_gate";
                    influencedDecision = false;
                end
            else
                runtimeConsumer = "pending_shared_receiver_tracking_state";
                influenceDefinition = "trs_runtime_observation_required_before_receiver_tracking_state_update";
                influencedDecision = false;
                receiverStatus = "pending_no_runtime_trs_observation";
                receiverBlocker = "no_trs_runtime_observation_for_serving_cell";
            end
        else
            runtimeConsumer = "inactive";
            influenceDefinition = "trs_disabled";
            influencedDecision = false;
            receiverStatus = "inactive";
            receiverBlocker = "";
        end
        ctx = struct( ...
            "TRSGatingActive", logical(trsGatingActive), ...
            "TRSValidityState", string(validity), ...
            "TrackingEligibility", logical(trackingEligible), ...
            "TRSAgeSlots", double(trsAgeSlots), ...
            "LastSuccessfulTRSSlot", double(lastSuccess), ...
            "LastEstimatedTRSDopplerHz", double(lastDoppler), ...
            "TRSStateSource", "CoupledTruthRuntime.ReceiverTrackingStateByCell", ...
            "TRSRuntimeConsumer", string(runtimeConsumer), ...
            "TRSInfluencedDecision", logical(influencedDecision), ...
            "TRSInfluenceDefinition", string(influenceDefinition), ...
            "TRSReceiverIntegrationStatus", string(receiverStatus), ...
            "TRSReceiverIntegrationBlocker", string(receiverBlocker), ...
            "TRSProcessed", logical(trsProcessed), ...
            "TRSReceiverConsumerType", string(receiverConsumerType), ...
            "TRSTrackingStateBefore", string(trackingStateBefore), ...
            "TRSTrackingStateAfter", string(trackingStateAfter), ...
            "TRSTrackingUpdateTime_s", double(trackingUpdateTime), ...
            "TRSAssociatedCell", double(servingCell), ...
            "TRSUpdateOutcome", string(updateOutcome), ...
            "TRSChannelTrackingFreshnessState", string(channelFreshness), ...
            "TRSFrequencyTrackingState", string(frequencyState), ...
            "TRSTimingTrackingState", string(timingState), ...
            "TRSTimingEstimateAvailable", logical(timingEstimateAvailable), ...
            "TRSTimingEstimate_samples", double(timingEstimateSamples), ...
            "TRSCFOEstimateAvailable", logical(cfoEstimateAvailable), ...
            "TRSEstimatedCFO_Hz", double(estimatedCFOHz), ...
            "TRSEstimatedOscillatorCFO_Hz", double(estimatedOscillatorCFOHz), ...
            "TRSEstimatedCommonFrequency_Hz", double(estimatedCommonFrequencyHz), ...
            "TRSPhysicalDoppler_Hz", double(physicalDopplerHz), ...
            "TRSRuntimeEvidenceSource", string(evidenceSource));
    end

    function state = updateGrantControlTrace(state, grant, direction)
        direction = upper(string(direction));
        if upper(string(direction)) == "UL"
            traceT = sixgr.util.structGet(state, "ULGrantTraceTable", table());
        else
            traceT = sixgr.util.structGet(state, "DLGrantTraceTable", table());
        end
        if ~(istable(traceT) && ~isempty(traceT))
            return;
        end
        ueIdx = double(sixgr.util.structGet(grant, "UEIndex", NaN));
        slotIdx = double(sixgr.util.structGet(grant, "Slot", sixgr.util.structGet(state, "CurrentSlot", NaN)));
        frameIdx = double(sixgr.util.structGet(grant, "Frame", sixgr.util.structGet(state, "CurrentFrame", NaN)));
        servingCell = double(sixgr.util.structGet(grant, "ServingCell", NaN));
        mask = true(height(traceT), 1);
        if ismember("UEIndex", string(traceT.Properties.VariableNames)) && isfinite(ueIdx)
            mask = mask & abs(double(traceT.UEIndex) - ueIdx) < 1e-9;
        end
        if ismember("Slot", string(traceT.Properties.VariableNames)) && isfinite(slotIdx)
            mask = mask & abs(double(traceT.Slot) - slotIdx) < 1e-9;
        end
        if ismember("Frame", string(traceT.Properties.VariableNames)) && isfinite(frameIdx)
            mask = mask & abs(double(traceT.Frame) - frameIdx) < 1e-9;
        end
        if ismember("ServingCell", string(traceT.Properties.VariableNames)) && isfinite(servingCell)
            mask = mask & abs(double(traceT.ServingCell) - servingCell) < 1e-9;
        end
        idx = find(mask, 1, "last");
        if isempty(idx)
            return;
        end
        updateFields = { ...
            "PBCHGatingActive", logical(sixgr.util.structGet(grant, "PBCHGatingActive", false)); ...
            "PRACHGatingActive", logical(sixgr.util.structGet(grant, "PRACHGatingActive", false)); ...
            "PDCCHGatingActive", logical(sixgr.util.structGet(grant, "PDCCHGatingActive", false)); ...
            "SRSGatingActive", logical(sixgr.util.structGet(grant, "SRSGatingActive", false)); ...
            "ControlEligible", logical(sixgr.util.structGet(grant, "ControlEligible", true)); ...
            "ControlDecodeOk", logical(sixgr.util.structGet(grant, "ControlDecodeOk", false)); ...
            "PDCCHCausalGrantDecodeOk", logical(sixgr.util.structGet(grant, "PDCCHCausalGrantDecodeOk", false)); ...
            "PDCCHControlFailureReason", string(sixgr.util.structGet(grant, "PDCCHControlFailureReason", "")); ...
            "PDCCHControlEvidenceSource", string(sixgr.util.structGet(grant, "PDCCHControlEvidenceSource", "")); ...
            "ControlDecodeSource", string(sixgr.util.structGet(grant, "ControlDecodeSource", "")); ...
            "GrantControlState", string(sixgr.util.structGet(grant, "GrantControlState", "")); ...
            "CellAcquisitionState", string(sixgr.util.structGet(grant, "CellAcquisitionState", "")); ...
            "AccessState", string(sixgr.util.structGet(grant, "AccessState", "")); ...
            "SRSValidityState", string(sixgr.util.structGet(grant, "SRSValidityState", "")); ...
            "CSIValidityState", string(sixgr.util.structGet(grant, "CSIValidityState", "")); ...
            "SRSValid", logical(sixgr.util.structGet(grant, "SRSValid", false)); ...
            "SRSAgeSlots", double(sixgr.util.structGet(grant, "SRSAgeSlots", NaN)); ...
            "TRSGatingActive", logical(sixgr.util.structGet(grant, "TRSGatingActive", false)); ...
            "TRSValidityState", string(sixgr.util.structGet(grant, "TRSValidityState", "")); ...
            "TrackingEligibility", logical(sixgr.util.structGet(grant, "TrackingEligibility", false)); ...
            "TRSAgeSlots", double(sixgr.util.structGet(grant, "TRSAgeSlots", NaN)); ...
            "LastSuccessfulTRSSlot", double(sixgr.util.structGet(grant, "LastSuccessfulTRSSlot", NaN)); ...
            "LastEstimatedTRSDopplerHz", double(sixgr.util.structGet(grant, "LastEstimatedTRSDopplerHz", NaN)); ...
            "TRSStateSource", string(sixgr.util.structGet(grant, "TRSStateSource", "")); ...
            "TRSRuntimeConsumer", string(sixgr.util.structGet(grant, "TRSRuntimeConsumer", "")); ...
            "TRSInfluencedDecision", logical(sixgr.util.structGet(grant, "TRSInfluencedDecision", false)); ...
            "TRSInfluenceDefinition", string(sixgr.util.structGet(grant, "TRSInfluenceDefinition", "")); ...
            "TRSReceiverIntegrationStatus", string(sixgr.util.structGet(grant, "TRSReceiverIntegrationStatus", "")); ...
            "TRSReceiverIntegrationBlocker", string(sixgr.util.structGet(grant, "TRSReceiverIntegrationBlocker", ""))};
        for i = 1:size(updateFields, 1)
            fieldName = char(updateFields{i, 1});
            fieldValue = updateFields{i, 2};
            if ~ismember(fieldName, string(traceT.Properties.VariableNames))
                continue;
            end
            if isstring(traceT.(fieldName))
                traceT.(fieldName)(idx) = string(fieldValue);
            elseif iscell(traceT.(fieldName))
                traceT.(fieldName)(idx) = {char(string(fieldValue))};
            elseif iscategorical(traceT.(fieldName))
                traceT.(fieldName)(idx) = categorical(string(fieldValue));
            elseif islogical(traceT.(fieldName))
                traceT.(fieldName)(idx) = logical(fieldValue);
            else
                traceT.(fieldName)(idx) = double(fieldValue);
            end
        end
        if upper(string(direction)) == "UL"
            state.ULGrantTraceTable = traceT;
        else
            state.DLGrantTraceTable = traceT;
        end
    end

    function gating = resolveControlGatingConfig(cfg, multiUser)
        pbchRequired = logical(sixgr.util.structGet(cfg, "run.controlGating.pbchRequired", ...
            sixgr.util.structGet(cfg, "control_gating.pbch_required", [])));
        prachRequired = logical(sixgr.util.structGet(cfg, "run.controlGating.prachRequired", ...
            sixgr.util.structGet(cfg, "control_gating.prach_required", [])));
        pdcchRequired = logical(sixgr.util.structGet(cfg, "run.controlGating.pdcchRequired", ...
            sixgr.util.structGet(cfg, "control_gating.pdcch_required", [])));
        srsRequired = logical(sixgr.util.structGet(cfg, "run.controlGating.srsRequired", ...
            sixgr.util.structGet(cfg, "control_gating.srs_required", [])));
        trsRequired = logical(sixgr.util.structGet(cfg, "run.controlGating.trsRequired", ...
            sixgr.util.structGet(cfg, "control_gating.trs_required", [])));
        srsMaxAgeSlots = double(sixgr.util.structGet(cfg, "run.controlGating.srsMaxAgeSlots", ...
            sixgr.util.structGet(cfg, "control_gating.srs_max_age_slots", [])));
        srsMaxAgeSlots = max(0, round(srsMaxAgeSlots));
        trsMaxAgeSlots = double(sixgr.util.structGet(cfg, "run.controlGating.trsMaxAgeSlots", ...
            sixgr.util.structGet(cfg, "control_gating.trs_max_age_slots", [])));
        trsMaxAgeSlots = max(0, round(trsMaxAgeSlots));
        timingAdvanceUpdateMode = lower(strtrim(string(sixgr.util.structGet(cfg, "run.controlGating.timingAdvanceUpdateMode", ...
            sixgr.util.structGet(cfg, "control_gating.timing_advance_update_mode", "measurement_only")))));
        if ~ismember(timingAdvanceUpdateMode, ["measurement_only","geometry_predictive","disabled"])
            error("sixgr:truth:InvalidTimingAdvanceUpdateMode", ...
                "Invalid timing advance update mode '%s'.", char(timingAdvanceUpdateMode));
        end
        timingAdvanceUpdateThresholdSamples = double(sixgr.util.structGet(cfg, "run.controlGating.timingAdvanceUpdateThresholdSamples", ...
            sixgr.util.structGet(cfg, "control_gating.timing_advance_update_threshold_samples", 1)));
        if ~(isfinite(timingAdvanceUpdateThresholdSamples) && isscalar(timingAdvanceUpdateThresholdSamples) && timingAdvanceUpdateThresholdSamples >= 0)
            error("sixgr:truth:InvalidTimingAdvanceUpdateThreshold", ...
                "Timing advance update threshold must be a finite nonnegative scalar.");
        end
        preAttachBeforeMeasurement = logical(sixgr.util.structGet(cfg, "run.controlGating.preAttachUEsBeforeMeasurement", ...
            sixgr.util.structGet(cfg, "control_gating.pre_attach_ues_before_measurement", false)));
        if any(cellfun(@isempty, {sixgr.util.structGet(cfg, "run.controlGating.pbchRequired", sixgr.util.structGet(cfg, "control_gating.pbch_required", [])), ...
                sixgr.util.structGet(cfg, "run.controlGating.prachRequired", sixgr.util.structGet(cfg, "control_gating.prach_required", [])), ...
                sixgr.util.structGet(cfg, "run.controlGating.pdcchRequired", sixgr.util.structGet(cfg, "control_gating.pdcch_required", [])), ...
                sixgr.util.structGet(cfg, "run.controlGating.srsRequired", sixgr.util.structGet(cfg, "control_gating.srs_required", [])), ...
                sixgr.util.structGet(cfg, "run.controlGating.trsRequired", sixgr.util.structGet(cfg, "control_gating.trs_required", [])), ...
                sixgr.util.structGet(cfg, "run.controlGating.srsMaxAgeSlots", sixgr.util.structGet(cfg, "control_gating.srs_max_age_slots", [])), ...
                sixgr.util.structGet(cfg, "run.controlGating.trsMaxAgeSlots", sixgr.util.structGet(cfg, "control_gating.trs_max_age_slots", []))}))
            error("sixgr:truth:MissingControlGatingConfig", ...
                "Missing explicit control-gating config. Coupled runtime requires resolved run.controlGating.* or control_gating.* values.");
        end
        gating = struct( ...
            "PBCHRequired", logical(pbchRequired), ...
            "PRACHRequired", logical(prachRequired), ...
            "PDCCHRequired", logical(pdcchRequired), ...
            "SRSRequired", logical(srsRequired), ...
            "TRSRequired", logical(trsRequired), ...
            "SRSMaxAgeSlots", double(srsMaxAgeSlots), ...
            "TRSMaxAgeSlots", double(trsMaxAgeSlots), ...
            "TimingAdvanceUpdateMode", char(timingAdvanceUpdateMode), ...
            "TimingAdvanceUpdateThresholdSamples", double(timingAdvanceUpdateThresholdSamples), ...
            "PreAttachUEsBeforeMeasurement", logical(preAttachBeforeMeasurement), ...
            "PBCHInitialState", "searching", ...
            "PRACHInitialState", sixgr.truth.CoupledTruthRuntime.ternaryString(logical(prachRequired), "pending", "not_required"), ...
            "SRSInitialState", sixgr.truth.CoupledTruthRuntime.ternaryString(logical(srsRequired), "invalid", "not_required"), ...
            "CSIInitialState", sixgr.truth.CoupledTruthRuntime.ternaryString(logical(srsRequired), "no_successful_srs", "not_required"), ...
            "TRSInitialState", sixgr.truth.CoupledTruthRuntime.ternaryString(logical(trsRequired), "invalid", "not_required"));
        if ~logical(pbchRequired)
            gating.PBCHInitialState = "not_required";
        end
    end

    function T = buildControlSummaryTable(state)
        row = sixgr.truth.CoupledTruthRuntime.emptyControlSummaryRow();
        [currentDirection, dlSchedulingEligibility, ulSchedulingEligibility, currentSchedulingEligibility] = ...
            sixgr.truth.CoupledTruthRuntime.resolveSchedulingEligibilityViews(state);
        controlEligibility = logical(sixgr.util.structGet(state, "ControlEligibility", false(0,1)));
        currentBlockedBySRS = controlEligibility & ~currentSchedulingEligibility & ...
            sixgr.truth.CoupledTruthRuntime.srsGatingActiveForDirection(state, currentDirection);
        row.ControlIntegrationMode = sixgr.truth.CoupledTruthRuntime.resolveControlIntegrationMode(state);
        row.CurrentSchedulingDirection = char(currentDirection);
        row.PBCHGatingActive = logical(sixgr.util.structGet(state.ControlGating, "PBCHRequired", false));
        row.PRACHGatingActive = logical(sixgr.util.structGet(state.ControlGating, "PRACHRequired", false));
        row.PDCCHGatingActive = logical(sixgr.util.structGet(state.ControlGating, "PDCCHRequired", false));
        row.SRSGatingActive = logical(sixgr.util.structGet(state.ControlGating, "SRSRequired", false));
        row.TRSGatingActive = logical(sixgr.util.structGet(state.ControlGating, "TRSRequired", false));
        row.PBCHFailureCount = sum(double(sixgr.util.structGet(state, "PBCHFailureCount", 0)), "omitnan");
        row.PRACHFailureCount = sum(double(sixgr.util.structGet(state, "PRACHFailureCount", 0)), "omitnan");
        row.ControlDecodeFailureCount = sum(double(sixgr.util.structGet(state, "PDCCHFailureCount", 0)), "omitnan");
        row.PUCCHDecodeFailureCount = sum(double(sixgr.util.structGet(state, "PUCCHFailureCount", 0)), "omitnan");
        row.PUCCHCrashCount = sum(double(sixgr.util.structGet(state, "PUCCHCrashCount", 0)), "omitnan");
        row.TRSFailureCount = sum(double(sixgr.util.structGet(state, "TRSFailureCountByCell", 0)), "omitnan");
        row.SRSInvalidEventCount = sum(double(sixgr.util.structGet(state, "SRSInvalidEventCount", 0)), "omitnan");
        row.SchedulingOpportunitiesBlockedByGating = sum(double(sixgr.util.structGet(state, "SchedulingOpportunitiesBlockedByGatingCount", 0)), "omitnan");
        row.GrantsBlockedByGating = sum(double(sixgr.util.structGet(state, "GrantsBlockedByGatingCount", 0)), "omitnan");
        pbchStates = string(sixgr.util.structGet(state, "CellAcquisitionState", strings(0,1)));
        accessStates = string(sixgr.util.structGet(state, "AccessState", strings(0,1)));
        row.UsersAcquired = sixgr.truth.CoupledTruthRuntime.countSatisfiedControlUsers( ...
            pbchStates, "acquired", logical(sixgr.util.structGet(state.ControlGating, "PBCHRequired", false)));
        row.UsersAccessReady = sixgr.truth.CoupledTruthRuntime.countSatisfiedControlUsers( ...
            accessStates, "succeeded", logical(sixgr.util.structGet(state.ControlGating, "PRACHRequired", false)));
        row.UsersWithValidSRS = sum(string(sixgr.util.structGet(state, "SRSValidityState", strings(0,1))) == "valid");
        servingVec = double(sixgr.util.structGet(state, "CurrentServingIdx", nan(state.NumUsers, 1)));
        trsValidUsers = 0;
        for ueIdx = 1:double(sixgr.util.structGet(state, "NumUsers", 0))
            servingCell = NaN;
            if ueIdx <= numel(servingVec)
                servingCell = double(servingVec(ueIdx));
            end
            trsValidUsers = trsValidUsers + double(sixgr.truth.CoupledTruthRuntime.trsEligibleForServingCell(state, servingCell));
        end
        row.UsersWithValidTRS = trsValidUsers;
        row.UsersControlEligible = sum(controlEligibility);
        row.UsersDLSchedulingEligible = sum(dlSchedulingEligibility);
        row.UsersULSchedulingEligible = sum(ulSchedulingEligibility);
        row.UsersSchedulingEligible = sum(currentSchedulingEligibility);
        row.UsersSchedulingBlockedBySRS = sum(currentBlockedBySRS);
        row.DLGrantsScheduledWithInvalidSRS = sixgr.truth.CoupledTruthRuntime.countInvalidSRSGrants( ...
            sixgr.util.structGet(state, "DLGrantTraceTable", table()), NaN);
        row.ULGrantsScheduledWithInvalidSRS = sixgr.truth.CoupledTruthRuntime.countInvalidSRSGrants( ...
            sixgr.util.structGet(state, "ULGrantTraceTable", table()), NaN);
        T = struct2table(row, "AsArray", true);
    end

    function T = buildControlStateTable(state)
        nUsers = double(sixgr.util.structGet(state, "NumUsers", 0));
        [currentDirection, ~, ~, ~] = sixgr.truth.CoupledTruthRuntime.resolveSchedulingEligibilityViews(state);
        rows = repmat(sixgr.truth.CoupledTruthRuntime.emptyControlStateRow(), max(0, nUsers), 1);
        for ueIdx = 1:nUsers
            rows(ueIdx).UEIndex = double(ueIdx);
            rows(ueIdx).RNTI = double(max(1, round(double(state.MultiUser.RNTIStart + ueIdx - 1))));
            rows(ueIdx).CurrentSchedulingDirection = char(currentDirection);
            rows(ueIdx).ServingCell = sixgr.truth.CoupledTruthRuntime.firstNumeric(sixgr.util.structGet(state, "CurrentServingIdx", NaN), NaN);
            if ueIdx <= numel(state.CurrentServingIdx)
                rows(ueIdx).ServingCell = double(state.CurrentServingIdx(ueIdx));
            end
            rows(ueIdx).CellAcquisitionState = char(sixgr.truth.CoupledTruthRuntime.controlStateAt(state, "CellAcquisitionState", ueIdx, "unknown"));
            rows(ueIdx).AccessState = char(sixgr.truth.CoupledTruthRuntime.controlStateAt(state, "AccessState", ueIdx, "not_attempted"));
            rows(ueIdx).TimeAlignmentState = char(sixgr.truth.CoupledTruthRuntime.controlStateAt(state, "TimeAlignmentState", ueIdx, "not_time_aligned"));
            rows(ueIdx).LastTimingAdvanceSource = char(sixgr.truth.CoupledTruthRuntime.controlStateAt(state, "LastTimingAdvanceSourceByUE", ueIdx, ""));
            rows(ueIdx).TimingAdvanceUpdateStatus = char(sixgr.truth.CoupledTruthRuntime.controlStateAt(state, "TimingAdvanceUpdateStatusByUE", ueIdx, "not_evaluated"));
            rows(ueIdx).TimingAdvanceUpdateRequired = logical(sixgr.truth.CoupledTruthRuntime.controlLogicalAt(state, "TimingAdvanceUpdateRequiredByUE", ueIdx, false));
            rows(ueIdx).LastPDCCHStatus = char(sixgr.truth.CoupledTruthRuntime.controlStateAt(state, "LastPDCCHStatus", ueIdx, "not_attempted"));
            rows(ueIdx).SRSValidityState = char(sixgr.truth.CoupledTruthRuntime.controlStateAt(state, "SRSValidityState", ueIdx, "unknown"));
            rows(ueIdx).CSIValidityState = char(sixgr.truth.CoupledTruthRuntime.controlStateAt(state, "CSIValidityState", ueIdx, "bootstrap_csi_unavailable"));
            rows(ueIdx).TRSValidityState = char(sixgr.truth.CoupledTruthRuntime.trsStateForUE(state, ueIdx));
            rows(ueIdx).ControlEligibility = logical(sixgr.truth.CoupledTruthRuntime.controlLogicalAt(state, "ControlEligibility", ueIdx, false));
            rows(ueIdx).SharedSchedulingEligibility = logical(sixgr.truth.CoupledTruthRuntime.controlLogicalAt(state, "SchedulingEligibility", ueIdx, false));
            rows(ueIdx).DLSchedulingEligibility = logical(sixgr.truth.CoupledTruthRuntime.resolveSchedulingEligibilityForDirection(state, ueIdx, "DL"));
            rows(ueIdx).ULSchedulingEligibility = logical(sixgr.truth.CoupledTruthRuntime.resolveSchedulingEligibilityForDirection(state, ueIdx, "UL"));
            rows(ueIdx).SchedulingEligibility = logical(sixgr.truth.CoupledTruthRuntime.resolveSchedulingEligibilityForDirection(state, ueIdx, currentDirection));
            rows(ueIdx).CoverageEligibility = logical(sixgr.truth.CoupledTruthRuntime.controlLogicalAt(state, "CoverageEligibility", ueIdx, true));
            rows(ueIdx).CoverageOutageState = char(sixgr.truth.CoupledTruthRuntime.controlStateAt(state, "CoverageOutageState", ueIdx, "not_evaluated"));
            rows(ueIdx).SchedulingBlockedBySRS = logical(rows(ueIdx).ControlEligibility && ~rows(ueIdx).SchedulingEligibility && ...
                sixgr.truth.CoupledTruthRuntime.srsGatingActiveForDirection(state, currentDirection));
            rows(ueIdx).SRSValid = strcmpi(rows(ueIdx).SRSValidityState, "valid");
            rows(ueIdx).SRSAgeSlots = double(sixgr.truth.CoupledTruthRuntime.srsAgeSlots(state, ueIdx));
            servingCell = double(rows(ueIdx).ServingCell);
            rows(ueIdx).TrackingEligibility = logical(sixgr.truth.CoupledTruthRuntime.trsEligibleForServingCell(state, servingCell));
            rows(ueIdx).TRSAgeSlots = double(sixgr.truth.CoupledTruthRuntime.trsAgeSlotsForServingCell(state, servingCell));
            rows(ueIdx).LastSuccessfulPBCHSlot = double(sixgr.truth.CoupledTruthRuntime.numericStateAt(state, "LastSuccessfulPBCHSlotByUE", ueIdx, NaN));
            rows(ueIdx).LastSuccessfulPRACHSlot = double(sixgr.truth.CoupledTruthRuntime.numericStateAt(state, "LastSuccessfulPRACHSlotByUE", ueIdx, NaN));
            rows(ueIdx).LastTimingAdvance_samples = double(sixgr.truth.CoupledTruthRuntime.numericStateAt(state, "LastTimingAdvanceSamplesByUE", ueIdx, NaN));
            rows(ueIdx).LastTimingAdvance_us = double(sixgr.truth.CoupledTruthRuntime.numericStateAt(state, "LastTimingAdvanceUsByUE", ueIdx, NaN));
            rows(ueIdx).LastTimingAdvanceUpdateSlot = double(sixgr.truth.CoupledTruthRuntime.numericStateAt(state, "LastTimingAdvanceUpdateSlotByUE", ueIdx, NaN));
            rows(ueIdx).LastTimingAdvanceServingCell = double(sixgr.truth.CoupledTruthRuntime.numericStateAt(state, "LastTimingAdvanceServingCellByUE", ueIdx, NaN));
            rows(ueIdx).LastTimingAdvanceServingDistance_m = double(sixgr.truth.CoupledTruthRuntime.numericStateAt(state, "LastTimingAdvanceServingDistanceMByUE", ueIdx, NaN));
            rows(ueIdx).TimingAdvanceDrift_samples = double(sixgr.truth.CoupledTruthRuntime.numericStateAt(state, "TimingAdvanceDriftSamplesByUE", ueIdx, NaN));
            rows(ueIdx).TimingAdvanceDrift_us = double(sixgr.truth.CoupledTruthRuntime.numericStateAt(state, "TimingAdvanceDriftUsByUE", ueIdx, NaN));
            rows(ueIdx).LastSuccessfulPDCCHSlot = double(sixgr.truth.CoupledTruthRuntime.numericStateAt(state, "LastSuccessfulPDCCHSlotByUE", ueIdx, NaN));
            rows(ueIdx).LastSuccessfulPUCCHSlot = double(sixgr.truth.CoupledTruthRuntime.numericStateAt(state, "LastSuccessfulPUCCHSlotByUE", ueIdx, NaN));
            rows(ueIdx).LastSuccessfulSRSSlot = double(sixgr.truth.CoupledTruthRuntime.numericStateAt(state, "LastSuccessfulSRSSlotByUE", ueIdx, NaN));
            rows(ueIdx).LastSuccessfulTRSSlot = double(sixgr.truth.CoupledTruthRuntime.numericServingStateAt(state, "LastSuccessfulTRSSlotByCell", servingCell, NaN));
            rows(ueIdx).LastEstimatedTRSDopplerHz = double(sixgr.truth.CoupledTruthRuntime.numericServingStateAt(state, "LastEstimatedTRSDopplerHzByCell", servingCell, NaN));
            trsCtx = sixgr.truth.CoupledTruthRuntime.resolveTRSRuntimeContext(state, state.CfgMobility, ueIdx, servingCell);
            rows(ueIdx).TRSRuntimeConsumer = char(string(trsCtx.TRSRuntimeConsumer));
            rows(ueIdx).TRSReceiverIntegrationStatus = char(string(trsCtx.TRSReceiverIntegrationStatus));
            rows(ueIdx).TRSReceiverIntegrationBlocker = char(string(trsCtx.TRSReceiverIntegrationBlocker));
            rows(ueIdx).TRSProcessed = logical(trsCtx.TRSProcessed);
            rows(ueIdx).TRSUpdateOutcome = char(string(trsCtx.TRSUpdateOutcome));
            rows(ueIdx).TRSTrackingStateAfter = char(string(trsCtx.TRSTrackingStateAfter));
            rows(ueIdx).TRSRuntimeEvidenceSource = char(string(trsCtx.TRSRuntimeEvidenceSource));
            rows(ueIdx).PBCHFailureCount = double(sixgr.truth.CoupledTruthRuntime.numericStateAt(state, "PBCHFailureCount", ueIdx, 0));
            rows(ueIdx).PRACHFailureCount = double(sixgr.truth.CoupledTruthRuntime.numericStateAt(state, "PRACHFailureCount", ueIdx, 0));
            rows(ueIdx).ControlDecodeFailureCount = double(sixgr.truth.CoupledTruthRuntime.numericStateAt(state, "PDCCHFailureCount", ueIdx, 0));
            rows(ueIdx).PUCCHDecodeFailureCount = double(sixgr.truth.CoupledTruthRuntime.numericStateAt(state, "PUCCHFailureCount", ueIdx, 0));
            rows(ueIdx).PUCCHCrashCount = double(sixgr.truth.CoupledTruthRuntime.numericStateAt(state, "PUCCHCrashCount", ueIdx, 0));
            rows(ueIdx).SRSInvalidEventCount = double(sixgr.truth.CoupledTruthRuntime.numericStateAt(state, "SRSInvalidEventCount", ueIdx, 0));
            rows(ueIdx).TRSFailureCount = double(sixgr.truth.CoupledTruthRuntime.numericServingStateAt(state, "TRSFailureCountByCell", servingCell, 0));
            rows(ueIdx).SchedulingOpportunitiesBlockedByGating = double(sixgr.truth.CoupledTruthRuntime.numericStateAt(state, "SchedulingOpportunitiesBlockedByGatingCount", ueIdx, 0));
            rows(ueIdx).GrantsBlockedByGating = double(sixgr.truth.CoupledTruthRuntime.numericStateAt(state, "GrantsBlockedByGatingCount", ueIdx, 0));
            rows(ueIdx).DLGrantsScheduledWithInvalidSRS = sixgr.truth.CoupledTruthRuntime.countInvalidSRSGrants( ...
                sixgr.util.structGet(state, "DLGrantTraceTable", table()), ueIdx);
            rows(ueIdx).ULGrantsScheduledWithInvalidSRS = sixgr.truth.CoupledTruthRuntime.countInvalidSRSGrants( ...
                sixgr.util.structGet(state, "ULGrantTraceTable", table()), ueIdx);
        end
        T = struct2table(rows, "AsArray", true);
    end

    function count = countInvalidSRSGrants(traceT, ueIdx)
        count = 0;
        if ~(istable(traceT) && ~isempty(traceT))
            return;
        end
        names = string(traceT.Properties.VariableNames);
        if ~ismember("SRSGatingActive", names) || ~ismember("SRSValidityState", names)
            return;
        end
        gating = logical(sixgr.truth.CoupledTruthRuntime.tableColumnOrDefault(traceT, "SRSGatingActive", false(height(traceT), 1)));
        validity = lower(strtrim(string(sixgr.truth.CoupledTruthRuntime.tableColumnOrDefault(traceT, "SRSValidityState", repmat("", height(traceT), 1)))));
        invalidMask = gating & validity ~= "valid";
        if isfinite(ueIdx) && ismember("UEIndex", names)
            invalidMask = invalidMask & double(traceT.UEIndex) == double(ueIdx);
        end
        count = sum(double(invalidMask), "omitnan");
    end

    function T = buildReceiverTrackingStateTable(state)
        rows = sixgr.util.structGet(state, "ReceiverTrackingStateByCell", repmat(sixgr.truth.CoupledTruthRuntime.emptyReceiverTrackingStateRow(), 0, 1));
        if ~(isstruct(rows) && ~isempty(rows))
            rows = repmat(sixgr.truth.CoupledTruthRuntime.emptyReceiverTrackingStateRow(), 0, 1);
        end
        T = struct2table(rows, "AsArray", true);
    end

    function row = receiverTrackingRowForServingCell(state, servingCell)
        row = sixgr.truth.CoupledTruthRuntime.emptyReceiverTrackingStateRow();
        servingCell = round(double(servingCell));
        if ~(isfinite(servingCell) && servingCell >= 1)
            return;
        end
        rows = sixgr.util.structGet(state, "ReceiverTrackingStateByCell", repmat(struct(), 0, 1));
        if ~(isstruct(rows) && servingCell <= numel(rows))
            return;
        end
        templateFields = fieldnames(row);
        for fi = 1:numel(templateFields)
            fieldName = templateFields{fi};
            if isfield(rows, fieldName)
                row.(fieldName) = rows(servingCell).(fieldName);
            end
        end
    end

    function ctx = resolveTRSControlAnnotationContext(state, T)
        servingCell = NaN;
        if istable(T) && ~isempty(T) && ismember("ServingCell", string(T.Properties.VariableNames))
            servingVals = double(T.ServingCell);
            servingVals = servingVals(isfinite(servingVals));
            if ~isempty(servingVals)
                servingCell = double(servingVals(end));
            end
        end
        if ~isfinite(servingCell)
            rows = sixgr.util.structGet(state, "ReceiverTrackingStateByCell", repmat(struct(), 0, 1));
            if isstruct(rows) && ~isempty(rows)
                processed = false(numel(rows), 1);
                for i = 1:numel(rows)
                    processed(i) = logical(sixgr.util.structGet(rows(i), "TRSProcessed", false));
                end
                idx = find(processed, 1, "last");
                if ~isempty(idx)
                    servingCell = double(idx);
                end
            end
        end
        row = sixgr.truth.CoupledTruthRuntime.receiverTrackingRowForServingCell(state, servingCell);
        processed = logical(sixgr.util.structGet(row, "TRSProcessed", false));
        if processed
            ctx = struct( ...
                "TRSStateSource", "CoupledTruthRuntime.ReceiverTrackingStateByCell", ...
                "TRSRuntimeConsumer", "shared_receiver_tracking_state", ...
                "TRSReceiverIntegrationStatus", "integrated_shared_tracking_object", ...
                "TRSReceiverIntegrationBlocker", "", ...
                "TRSProcessed", true, ...
                "TRSReceiverConsumerType", string(sixgr.util.structGet(row, "ReceiverConsumerType", "shared_receiver_tracking_state")), ...
                "TRSTrackingStateBefore", string(sixgr.util.structGet(row, "TRSTrackingStateBefore", "")), ...
                "TRSTrackingStateAfter", string(sixgr.util.structGet(row, "TRSTrackingStateAfter", sixgr.util.structGet(row, "TrackingState", ""))), ...
                "TRSTrackingUpdateTime_s", double(sixgr.util.structGet(row, "TRSTrackingUpdateTime_s", NaN)), ...
                "TRSAssociatedCell", double(servingCell), ...
                "TRSUpdateOutcome", string(sixgr.util.structGet(row, "TRSUpdateOutcome", "")), ...
                "TRSChannelTrackingFreshnessState", string(sixgr.util.structGet(row, "ChannelTrackingFreshnessState", "")), ...
                "TRSFrequencyTrackingState", string(sixgr.util.structGet(row, "FrequencyTrackingState", "")), ...
                "TRSTimingTrackingState", string(sixgr.util.structGet(row, "TimingTrackingState", "")), ...
                "TRSTimingEstimateAvailable", logical(sixgr.util.structGet(row, "TimingEstimateAvailable", false)), ...
                "TRSTimingEstimate_samples", double(sixgr.util.structGet(row, "TimingEstimate_samples", NaN)), ...
                "TRSCFOEstimateAvailable", logical(sixgr.util.structGet(row, "CFOEstimateAvailable", false)), ...
                "TRSEstimatedCFO_Hz", double(sixgr.util.structGet(row, "EstimatedCFO_Hz", NaN)), ...
                "TRSRuntimeEvidenceSource", string(sixgr.util.structGet(row, "RuntimeEvidenceSource", "")));
        else
            ctx = struct( ...
                "TRSStateSource", "CoupledTruthRuntime.ReceiverTrackingStateByCell", ...
                "TRSRuntimeConsumer", "pending_shared_receiver_tracking_state", ...
                "TRSReceiverIntegrationStatus", "pending_no_runtime_trs_observation", ...
                "TRSReceiverIntegrationBlocker", "no_trs_runtime_observation_for_serving_cell", ...
                "TRSProcessed", false, ...
                "TRSReceiverConsumerType", "", ...
                "TRSTrackingStateBefore", "", ...
                "TRSTrackingStateAfter", "", ...
                "TRSTrackingUpdateTime_s", NaN, ...
                "TRSAssociatedCell", double(servingCell), ...
                "TRSUpdateOutcome", "", ...
                "TRSChannelTrackingFreshnessState", "", ...
                "TRSFrequencyTrackingState", "", ...
                "TRSTimingTrackingState", "", ...
                "TRSTimingEstimateAvailable", false, ...
                "TRSTimingEstimate_samples", NaN, ...
                "TRSCFOEstimateAvailable", false, ...
                "TRSEstimatedCFO_Hz", NaN, ...
                "TRSRuntimeEvidenceSource", "");
        end
    end

    function [bsRuntime, ueRuntime, resolvedT] = buildRuntimeAntennaState(cfg, layoutStruct, ue)
        bsRuntime = repmat(struct(), 0, 1);
        ueRuntime = repmat(struct(), 0, 1);
        rows = repmat(struct( ...
            "NodeType", "", ...
            "NodeIndex", NaN, ...
            "BaseStationID", NaN, ...
            "UEIndex", NaN, ...
            "ArrayType", "", ...
            "ArrayClass", "", ...
            "ElementClass", "", ...
            "NumRows", NaN, ...
            "NumCols", NaN, ...
            "NumPolarizations", NaN, ...
            "NumElements", NaN, ...
            "SpacingH_lambda", NaN, ...
            "SpacingV_lambda", NaN, ...
            "Polarization", "", ...
            "Azimuth_deg", NaN, ...
            "Heading_deg", NaN, ...
            "Tilt_deg", NaN, ...
            "PositionX_m", NaN, ...
            "PositionY_m", NaN, ...
            "PositionZ_m", NaN, ...
            "NumPorts", NaN, ...
            "AntennaConfigSource", "", ...
            "RuntimeObjectSource", "", ...
            "HasPhasedArrayObject", false), 0, 1);

        bsTemplate = sixgr.rf.AntennaArrayFactory.build(cfg, "bs", ...
            "arrayType", string(sixgr.util.structGet(cfg, "antenna.bs.geometry", "URA")), ...
            "elementSpacingLambda", double(sixgr.util.structGet(cfg, "antenna.bs.spacingLambda", [0.5 0.5])));
        ueTemplate = sixgr.rf.AntennaArrayFactory.build(cfg, "ue", ...
            "arrayType", string(sixgr.util.structGet(cfg, "antenna.ue.geometry", "ULA")), ...
            "elementSpacingLambda", double(sixgr.util.structGet(cfg, "antenna.ue.spacingLambda", [0.5 0.5])));

        nCells = size(sixgr.util.structGet(layoutStruct, "bs.pos_m", zeros(0, 3)), 1);
        bsRuntime = repmat(struct(), max(0, nCells), 1);
        bsTiltDeg = double(sixgr.util.structGet(cfg, "antenna.bs.tilt_deg", ...
            sixgr.util.structGet(cfg, "scenario.bs.mechanicalTilt_deg", 0)));
        for cellIdx = 1:nCells
            meta = sixgr.truth.CoupledTruthRuntime.runtimeAntennaMetadata(bsTemplate, ...
                "BS", cellIdx, double(cellIdx), NaN, ...
                double(sixgr.util.structGet(layoutStruct, "bs.azim_deg", nan(nCells, 1))), ...
                NaN, ...
                double(sixgr.util.structGet(layoutStruct, "bs.pos_m", zeros(nCells, 3))), ...
                double(sixgr.util.structGet(bsTemplate, "NumPorts", bsTemplate.Nant)), ...
                char(sixgr.util.structGet(cfg, "antenna.bs.source", "runtime_default")));
            if isfinite(bsTiltDeg)
                meta.Tilt_deg = double(bsTiltDeg);
            end
            bsRuntime(cellIdx).Antenna = bsTemplate;
            bsRuntime(cellIdx).Metadata = meta;
            rows(end + 1, 1) = meta; %#ok<AGROW>
        end

        nUsers = size(sixgr.util.structGet(ue, "pos_m", zeros(0, 3)), 1);
        ueRuntime = repmat(struct(), max(0, nUsers), 1);
        for ueIdx = 1:nUsers
            meta = sixgr.truth.CoupledTruthRuntime.runtimeAntennaMetadata(ueTemplate, ...
                "UE", ueIdx, NaN, double(ueIdx), ...
                NaN, ...
                double(sixgr.util.structGet(ue, "heading_deg", nan(nUsers, 1))), ...
                double(sixgr.util.structGet(ue, "pos_m", zeros(nUsers, 3))), ...
                double(sixgr.util.structGet(ueTemplate, "NumPorts", ueTemplate.Nant)), ...
                char(sixgr.util.structGet(cfg, "antenna.ue.source", "runtime_default")));
            ueRuntime(ueIdx).Antenna = ueTemplate;
            ueRuntime(ueIdx).Metadata = meta;
            rows(end + 1, 1) = meta; %#ok<AGROW>
        end

        resolvedT = struct2table(rows, "AsArray", true);
    end

    function meta = runtimeAntennaMetadata(arr, nodeType, nodeIndex, baseStationId, ueIndex, azimuthVec, headingVec, posMat, numPorts, sourceToken)
        if nargin < 6
            azimuthVec = NaN;
        end
        if nargin < 7
            headingVec = NaN;
        end
        if nargin < 8
            posMat = zeros(1, 3);
        end
        if nargin < 9
            numPorts = NaN;
        end
        if nargin < 10
            sourceToken = "runtime_default";
        end
        if ~(isnumeric(numPorts) && isscalar(numPorts) && isfinite(double(numPorts)) && double(numPorts) >= 1)
            numPorts = double(sixgr.util.structGet(arr, "NumPorts", NaN));
        end
        azimuthDeg = NaN;
        if numel(azimuthVec) >= nodeIndex
            azimuthDeg = double(azimuthVec(nodeIndex));
        end
        headingDeg = NaN;
        if numel(headingVec) >= nodeIndex
            headingDeg = double(headingVec(nodeIndex));
        end
        pos = [NaN NaN NaN];
        if size(posMat, 1) >= nodeIndex && size(posMat, 2) >= 3
            pos = double(posMat(nodeIndex, 1:3));
        end
        spacing = double(sixgr.util.structGet(arr, "ElementSpacing_m", [NaN NaN]));
        lambda = double(sixgr.util.structGet(arr, "Lambda_m", NaN));
        spacingLambda = [NaN NaN];
        if isfinite(lambda) && lambda > 0 && numel(spacing) >= 2
            spacingLambda = spacing(1:2) ./ lambda;
        end
        sizeVec = double(sixgr.util.structGet(arr, "Size", [NaN NaN 1]));
        if numel(sizeVec) < 2
            sizeVec = [sizeVec(:).' NaN];
        end
        typeToken = string(sixgr.util.structGet(arr, "Type", ""));
        if strlength(strtrim(typeToken)) < 1
            typeToken = "runtime_array";
        end
        meta = struct( ...
            "NodeType", char(string(nodeType)), ...
            "NodeIndex", double(nodeIndex), ...
            "BaseStationID", double(baseStationId), ...
            "UEIndex", double(ueIndex), ...
            "ArrayType", char(typeToken), ...
            "ArrayClass", char(sixgr.truth.CoupledTruthRuntime.runtimeArrayClassToken(arr)), ...
            "ElementClass", char(sixgr.truth.CoupledTruthRuntime.runtimeElementClassToken(arr)), ...
            "NumRows", double(sizeVec(1)), ...
            "NumCols", double(sizeVec(2)), ...
            "NumPolarizations", double(sixgr.util.structGet(arr, "NPol", NaN)), ...
            "NumElements", double(sixgr.util.structGet(arr, "Nant", NaN)), ...
            "SpacingH_lambda", double(spacingLambda(1)), ...
            "SpacingV_lambda", double(spacingLambda(2)), ...
            "Polarization", char(sixgr.truth.CoupledTruthRuntime.runtimePolarizationToken(arr)), ...
            "Azimuth_deg", double(azimuthDeg), ...
            "Heading_deg", double(headingDeg), ...
            "Tilt_deg", 0, ...
            "PositionX_m", double(pos(1)), ...
            "PositionY_m", double(pos(2)), ...
            "PositionZ_m", double(pos(3)), ...
            "NumPorts", double(numPorts), ...
            "AntennaConfigSource", char(string(sourceToken)), ...
            "RuntimeObjectSource", "CoupledTruthRuntime.initialize:AntennaArrayFactory.build", ...
            "HasPhasedArrayObject", logical(sixgr.util.structGet(arr, "HasPhased", false)));
    end

    function token = runtimeArrayClassToken(arr)
        token = "numeric_positions_only";
        arrayObj = sixgr.util.structGet(arr, "ArrayObj", []);
        if ~isempty(arrayObj)
            token = string(class(arrayObj));
        elseif ~isempty(fieldnames(arr))
            token = "sixgr.rf.AntennaArrayFactory.struct";
        end
    end

    function token = runtimeElementClassToken(arr)
        token = "numeric_isotropic_placeholder";
        elemObj = sixgr.util.structGet(arr, "ElementObj", []);
        if ~isempty(elemObj)
            token = string(class(elemObj));
        end
    end

    function token = runtimePolarizationToken(arr)
        nPol = max(1, round(double(sixgr.util.structGet(arr, "NPol", 1))));
        if nPol > 1
            token = "dual";
        else
            token = "single";
        end
    end

    function [bsEntry, ueEntry] = runtimeAntennaEntriesForLink(state, ueIdx, servingCell)
        bsEntry = struct();
        ueEntry = struct();
        bsRuntime = sixgr.util.structGet(state, "BSAntennaRuntime", repmat(struct(), 0, 1));
        ueRuntime = sixgr.util.structGet(state, "UEAntennaRuntime", repmat(struct(), 0, 1));
        if isfinite(servingCell) && servingCell >= 1 && servingCell <= numel(bsRuntime)
            bsEntry = bsRuntime(servingCell);
        end
        if isfinite(ueIdx) && ueIdx >= 1 && ueIdx <= numel(ueRuntime)
            ueEntry = ueRuntime(ueIdx);
        end
    end

    function mode = resolveChannelArrayModel(cfg)
        model = upper(string(sixgr.util.structGet(cfg, "channel.model", "AWGN")));
        if model == "TDL"
            mode = "nrtdl_count_only_fading_channel";
        elseif model == "CDL"
            mode = "nrcdl_config_array_shape_channel";
        elseif any(model == ["AWGN","NONE","OFF",""])
            mode = "awgn_no_array_channel";
        else
            mode = "other_channel_model";
        end
    end

    function mode = resolveControlIntegrationMode(state)
        gating = sixgr.util.structGet(state, "ControlGating", struct());
        if logical(sixgr.util.structGet(gating, "PBCHRequired", false)) || ...
                logical(sixgr.util.structGet(gating, "PRACHRequired", false)) || ...
                logical(sixgr.util.structGet(gating, "PDCCHRequired", false)) || ...
                logical(sixgr.util.structGet(gating, "SRSRequired", false)) || ...
                logical(sixgr.util.structGet(gating, "TRSRequired", false))
            mode = "runtime_control_access_tracking_state_gated";
        else
            mode = "independent_signal_bundle";
        end
    end

    function count = countSatisfiedControlUsers(states, successState, gatingRequired)
        states = string(states);
        successState = string(successState);
        gatingRequired = logical(gatingRequired);
        if gatingRequired
            count = sum(states == successState);
        else
            count = sum(states == successState | states == "not_required");
        end
    end

    function runState = initializeRunState(cfg, multiUser, totalTrafficFrames)
        symbolsPerSlot = max(1, round(double(sixgr.util.structGet(cfg, "phy.numerology.symbolsPerSlot", 14))));
        runState = struct( ...
            "RunStateID", "coupled_truth_run_state", ...
            "ExecutionModel", string(sixgr.util.structGet(multiUser, "ExecutionModel", "slot_coupled_truth")), ...
            "ConfiguredUsers", double(sixgr.util.structGet(multiUser, "NumUsers", 1)), ...
            "TotalTrafficFrames", double(totalTrafficFrames), ...
            "CanonicalSlotsPerSweepPoint", NaN, ...
            "CurrentCanonicalSlot", NaN, ...
            "CurrentPhysicalSlot", NaN, ...
            "CurrentFrame", NaN, ...
            "CurrentSlotDuplexLabel", "", ...
            "CurrentSlotDLAllowed", true, ...
            "CurrentSlotULAllowed", true, ...
            "CurrentSlotIsSpecial", false, ...
            "CurrentSlotDLSymbolStart", 0, ...
            "CurrentSlotDLNumSymbols", double(symbolsPerSlot), ...
            "CurrentSlotGuardSymbolStart", double(symbolsPerSlot), ...
            "CurrentSlotGuardNumSymbols", 0, ...
            "CurrentSlotULSymbolStart", 0, ...
            "CurrentSlotULNumSymbols", double(symbolsPerSlot), ...
            "NoiseOperatingMode", char(sixgr.truth.CoupledTruthRuntime.noiseOperatingModeFromConfig(cfg)), ...
            "ConfiguredSNR_dB", NaN, ...
            "CurrentSNR_dB", NaN, ...
            "DLCompletedFrames", 0, ...
            "ULCompletedFrames", 0, ...
            "DLCompletedSlots", 0, ...
            "ULCompletedSlots", 0, ...
            "SlotTraceRows", 0, ...
            "DLGrantRows", 0, ...
            "ULGrantRows", 0, ...
            "HARQTimelineRows", 0, ...
            "ControlIntegrationMode", "runtime_control_access_state_gated", ...
            "SchedulerSource", "CoupledTruthRuntime.scheduleDirection", ...
            "PHYSource", "runWaveformLinkBundle.executeGrantPHYJob", ...
            "ReportSource", "CoupledTruthRuntime.SlotTraceTable", ...
            "StateStatus", "initialized", ...
            "ValueRole", "configured_quality_until_feedback", ...
            "ValueStatus", "configured_quality_pending_runtime_feedback", ...
            "ValueSource", "CoupledTruthRuntime.initialize:configured_operating_point", ...
            "ValueDefinition", "canonical run state for the slot-coupled LLS truth loop; CurrentSNR_dB starts as explicit configured operating-point quality only when legacy configured-SNR mode is selected and is promoted to representative measured UE feedback after valid runtime observations arrive", ...
            "NAReason", "");
        if sixgr.truth.CoupledTruthRuntime.usesReceiverNoiseMeasurementMode(cfg)
            runState.ValueRole = "runtime_receiver_measurement_pending";
            runState.ValueStatus = "unavailable_pending_runtime_feedback";
            runState.ValueSource = "CoupledTruthRuntime.initialize:receiver_measurement_pending";
            runState.ValueDefinition = "canonical run state for the slot-coupled LLS truth loop; CurrentSNR_dB remains unavailable until receiver/reference-signal measurements or valid CSI feedback arrive; ConfiguredSNR_dB is operating-point metadata only";
        end
        if isstruct(cfg)
            if logical(sixgr.truth.CoupledTruthRuntime.scalarOrDefault( ...
                    sixgr.util.structGet(cfg, "run.controlGating.trsRequired", false), false))
                runState.ControlIntegrationMode = "runtime_control_access_tracking_state_gated";
            end
        end
    end

    function state = recordSlotTraceStart(state, direction, sweepIdx, sweepCount, absoluteFrame, totalFrames, snr_dB)
        direction = upper(string(direction));
        [traceT, rowIdx] = sixgr.truth.CoupledTruthRuntime.ensureSlotTraceRow(state, sweepIdx, sweepCount, absoluteFrame, totalFrames, snr_dB);
        if direction == "UL"
            traceT.ULStarted(rowIdx) = true;
            traceT.ULSlot(rowIdx) = double(state.CurrentSlot);
            traceT.ULStatus(rowIdx) = "started";
        else
            traceT.DLStarted(rowIdx) = true;
            traceT.DLSlot(rowIdx) = double(state.CurrentSlot);
            traceT.DLStatus(rowIdx) = "started";
        end
        traceT.TraceStatus(rowIdx) = sixgr.truth.CoupledTruthRuntime.slotTraceStatus(traceT(rowIdx, :));
        state.RunState = sixgr.truth.CoupledTruthRuntime.refreshRunState(state);
        traceT = sixgr.truth.CoupledTruthRuntime.refreshSlotTraceLinkQuality(traceT, rowIdx, state.RunState, snr_dB);
        traceT.HARQTimelineRows(rowIdx) = height(sixgr.util.structGet(state, "HARQTimelineTable", table()));
        state.SlotTraceTable = traceT;
    end

    function state = recordSlotTraceSchedule(state, direction, info)
        direction = upper(string(direction));
        [traceT, rowIdx] = sixgr.truth.CoupledTruthRuntime.ensureCurrentSlotTraceRow(state);
        if isempty(rowIdx)
            return;
        end
        if direction == "UL"
            traceT.ULScheduled(rowIdx) = true;
            traceT.ULActiveUsers(rowIdx) = double(sixgr.util.structGet(info, "ActiveUsers", 0));
            traceT.ULGrantedUsers(rowIdx) = double(sixgr.util.structGet(info, "GrantedUsers", 0));
            traceT.ULGrantCount(rowIdx) = double(sixgr.util.structGet(info, "GrantCount", 0));
            traceT.ULQueueBits(rowIdx) = double(sixgr.util.structGet(info, "QueueBits", 0));
            traceT.ULStatus(rowIdx) = "scheduled";
        else
            traceT.DLScheduled(rowIdx) = true;
            traceT.DLActiveUsers(rowIdx) = double(sixgr.util.structGet(info, "ActiveUsers", 0));
            traceT.DLGrantedUsers(rowIdx) = double(sixgr.util.structGet(info, "GrantedUsers", 0));
            traceT.DLGrantCount(rowIdx) = double(sixgr.util.structGet(info, "GrantCount", 0));
            traceT.DLQueueBits(rowIdx) = double(sixgr.util.structGet(info, "QueueBits", 0));
            traceT.DLStatus(rowIdx) = "scheduled";
        end
        traceT.TraceStatus(rowIdx) = sixgr.truth.CoupledTruthRuntime.slotTraceStatus(traceT(rowIdx, :));
        state.RunState = sixgr.truth.CoupledTruthRuntime.refreshRunState(state);
        traceT = sixgr.truth.CoupledTruthRuntime.refreshSlotTraceLinkQuality(traceT, rowIdx, state.RunState, ...
            sixgr.truth.CoupledTruthRuntime.rowValue(traceT(rowIdx, :), "ConfiguredSNR_dB", ...
            sixgr.truth.CoupledTruthRuntime.rowValue(traceT(rowIdx, :), "SNR_dB", NaN)));
        state.SlotTraceTable = traceT;
    end

    function state = recordSlotTraceTrial(state, direction, row)
        direction = upper(string(direction));
        [traceT, rowIdx] = sixgr.truth.CoupledTruthRuntime.ensureCurrentSlotTraceRow(state);
        if isempty(rowIdx)
            return;
        end
        tbsBits = double(sixgr.truth.CoupledTruthRuntime.rowValue(row, "TBSize_bits", ...
            sixgr.truth.CoupledTruthRuntime.rowValue(row, "TBSBits", 0)));
        if ~(isfinite(tbsBits) && tbsBits > 0)
            tbsBits = 0;
        end
        crcOk = logical(sixgr.truth.CoupledTruthRuntime.rowLogical(row, "CRCPass", false));
        if direction == "UL"
            traceT.ULExecutedGrantCount(rowIdx) = traceT.ULExecutedGrantCount(rowIdx) + 1;
            traceT.ULTrialRows(rowIdx) = traceT.ULTrialRows(rowIdx) + 1;
            traceT.ULSuccessCount(rowIdx) = traceT.ULSuccessCount(rowIdx) + double(crcOk);
            traceT.ULTBSBits(rowIdx) = traceT.ULTBSBits(rowIdx) + tbsBits;
            traceT.ULStatus(rowIdx) = "published";
        else
            traceT.DLExecutedGrantCount(rowIdx) = traceT.DLExecutedGrantCount(rowIdx) + 1;
            traceT.DLTrialRows(rowIdx) = traceT.DLTrialRows(rowIdx) + 1;
            traceT.DLSuccessCount(rowIdx) = traceT.DLSuccessCount(rowIdx) + double(crcOk);
            traceT.DLTBSBits(rowIdx) = traceT.DLTBSBits(rowIdx) + tbsBits;
            traceT.DLStatus(rowIdx) = "published";
        end
        traceT.HARQTimelineRows(rowIdx) = height(sixgr.util.structGet(state, "HARQTimelineTable", table()));
        traceT.TraceStatus(rowIdx) = sixgr.truth.CoupledTruthRuntime.slotTraceStatus(traceT(rowIdx, :));
        state.RunState = sixgr.truth.CoupledTruthRuntime.refreshRunState(state);
        traceT = sixgr.truth.CoupledTruthRuntime.refreshSlotTraceLinkQuality(traceT, rowIdx, state.RunState, ...
            sixgr.truth.CoupledTruthRuntime.rowValue(traceT(rowIdx, :), "ConfiguredSNR_dB", ...
            sixgr.truth.CoupledTruthRuntime.rowValue(traceT(rowIdx, :), "SNR_dB", NaN)));
        state.SlotTraceTable = traceT;
    end

    function traceT = refreshSlotTraceLinkQuality(traceT, rowIdx, runState, configuredSNR)
        if ~(istable(traceT) && ~isempty(traceT) && isfinite(double(rowIdx)) && rowIdx >= 1 && rowIdx <= height(traceT))
            return;
        end
        if ~(isstruct(runState) && ~isempty(fieldnames(runState)))
            return;
        end
        configuredSNR = double(configuredSNR);
        currentSNR = double(sixgr.util.structGet(runState, "CurrentSNR_dB", configuredSNR));
        valueRole = string(sixgr.util.structGet(runState, "ValueRole", ""));
        receiverNoiseMode = sixgr.truth.CoupledTruthRuntime.usesReceiverNoiseMeasurementMode(runState);
        if ~(isfinite(currentSNR))
            if receiverNoiseMode || contains(lower(valueRole), "pending")
                currentSNR = NaN;
            else
                currentSNR = configuredSNR;
            end
        end
        traceT.ConfiguredSNR_dB(rowIdx) = configuredSNR;
        traceT.ConfiguredSNRSource(rowIdx) = string("configured_operating_point_metadata");
        traceT.CurrentSNR_dB(rowIdx) = currentSNR;
        traceT.CurrentSNRSource(rowIdx) = string(sixgr.util.structGet(runState, "ValueSource", ""));
        traceT.CurrentSNRValueRole(rowIdx) = valueRole;
        traceT.CurrentSNRValueStatus(rowIdx) = string(sixgr.util.structGet(runState, "ValueStatus", ""));
        traceT.SNR_dB(rowIdx) = currentSNR;
    end

    function runState = refreshRunState(state)
        runState = sixgr.util.structGet(state, "RunState", struct());
        if ~(isstruct(runState) && ~isempty(fieldnames(runState)))
            runState = sixgr.truth.CoupledTruthRuntime.initializeRunState( ...
                sixgr.util.structGet(state, "CfgMobility", struct()), ...
                sixgr.util.structGet(state, "MultiUser", struct()), ...
                sixgr.util.structGet(state, "TrafficFrameCount", NaN));
        end
        slotTraceT = sixgr.util.structGet(state, "SlotTraceTable", table());
        runState.CurrentCanonicalSlot = double(sixgr.util.structGet(state, "CurrentCanonicalSlot", NaN));
        runState.CurrentPhysicalSlot = double(sixgr.util.structGet(state, "CurrentSlot", NaN));
        runState.CurrentFrame = double(sixgr.util.structGet(state, "CurrentFrame", NaN));
        runState.CurrentSlotDuplexLabel = string(sixgr.util.structGet(state, "CurrentSlotDuplexLabel", ""));
        runState.CurrentSlotDLAllowed = logical(sixgr.util.structGet(state, "CurrentSlotDLAllowed", true));
        runState.CurrentSlotULAllowed = logical(sixgr.util.structGet(state, "CurrentSlotULAllowed", true));
        runState.CurrentSlotIsSpecial = logical(sixgr.util.structGet(state, "CurrentSlotIsSpecial", false));
        runState.CurrentSlotDLSymbolStart = double(sixgr.util.structGet(state, "CurrentSlotDLSymbolStart", 0));
        runState.CurrentSlotDLNumSymbols = double(sixgr.util.structGet(state, "CurrentSlotDLNumSymbols", 14));
        runState.CurrentSlotGuardSymbolStart = double(sixgr.util.structGet(state, "CurrentSlotGuardSymbolStart", 14));
        runState.CurrentSlotGuardNumSymbols = double(sixgr.util.structGet(state, "CurrentSlotGuardNumSymbols", 0));
        runState.CurrentSlotULSymbolStart = double(sixgr.util.structGet(state, "CurrentSlotULSymbolStart", 0));
        runState.CurrentSlotULNumSymbols = double(sixgr.util.structGet(state, "CurrentSlotULNumSymbols", 14));
        configuredSNR = double(sixgr.util.structGet(state, "CurrentSNR_dB", NaN));
        runState.NoiseOperatingMode = char(sixgr.truth.CoupledTruthRuntime.noiseOperatingModeFromConfig(state));
        [representativeLinkQuality, representativeLinkQualitySource] = ...
            sixgr.truth.CoupledTruthRuntime.representativeCurrentLinkQuality(state);
        runState.ConfiguredSNR_dB = configuredSNR;
        if isfinite(representativeLinkQuality)
            runState.CurrentSNR_dB = representativeLinkQuality;
            runState.ValueStatus = "OK";
            if string(representativeLinkQualitySource) == "pending_measured_feedback"
                runState.ValueRole = "representative_measured_feedback_pending_delivery";
                runState.ValueSource = "CoupledTruthRuntime.refreshRunState:pending_measured_csi_report";
                runState.ValueDefinition = "representative median UE-measured wideband SINR from the latest observed CSI reports for the active slot; this is not configured operating-point metadata, and delivery timing to the scheduler may still be pending";
            else
                runState.ValueRole = "representative_measured_feedback";
                runState.ValueSource = "CoupledTruthRuntime.refreshRunState:representative_feedback_sinr";
                runState.ValueDefinition = "representative median UE-reported/measured wideband SINR for the active slot; ConfiguredSNR_dB preserves configured operating-point metadata separately";
            end
        elseif sixgr.truth.CoupledTruthRuntime.usesReceiverNoiseMeasurementMode(state)
            runState.CurrentSNR_dB = NaN;
            runState.ValueRole = "runtime_receiver_measurement_pending";
            runState.ValueStatus = "unavailable_pending_runtime_feedback";
            runState.ValueSource = "CoupledTruthRuntime.refreshRunState:receiver_measurement_pending";
            runState.ValueDefinition = "no valid runtime receiver/reference-signal SINR or CSI feedback is available yet for the active slot; CurrentSNR_dB is unavailable and ConfiguredSNR_dB is operating-point metadata only";
        else
            runState.CurrentSNR_dB = configuredSNR;
            runState.ValueRole = "configured_quality_until_feedback";
            runState.ValueStatus = "configured_quality_pending_runtime_feedback";
            runState.ValueSource = "CoupledTruthRuntime.refreshRunState:configured_operating_point";
            runState.ValueDefinition = "no valid runtime feedback SINR is available yet for the active slot, so CurrentSNR_dB reflects explicit configured operating-point quality and is not a measured SINR; ConfiguredSNR_dB preserves that metadata separately";
        end
        runState.CanonicalSlotsPerSweepPoint = double(sixgr.util.structGet(state, "CanonicalSlotsPerSweepPoint", NaN));
        runState.DLCompletedFrames = double(sixgr.util.structGet(state, "DLCompletedFrames", 0));
        runState.ULCompletedFrames = double(sixgr.util.structGet(state, "ULCompletedFrames", 0));
        runState.DLCompletedSlots = double(sixgr.util.structGet(state, "DLCompletedSlots", 0));
        runState.ULCompletedSlots = double(sixgr.util.structGet(state, "ULCompletedSlots", 0));
        runState.SlotTraceRows = height(slotTraceT);
        runState.DLGrantRows = height(sixgr.util.structGet(state, "DLGrantTraceTable", table()));
        runState.ULGrantRows = height(sixgr.util.structGet(state, "ULGrantTraceTable", table()));
        runState.HARQTimelineRows = height(sixgr.util.structGet(state, "HARQTimelineTable", table()));
        runState.StateStatus = "active_slot_trace_first";
        if strlength(string(sixgr.util.structGet(runState, "ValueSource", ""))) == 0
            runState.ValueSource = "CoupledTruthRuntime.refreshRunState";
        end
    end

    function [quality_dB, sourceToken] = representativeCurrentLinkQuality(state)
        quality_dB = NaN;
        sourceToken = "";
        vals = [];
        dlFeedback = sixgr.util.structGet(state, "LatestDLFeedback", []);
        if isstruct(dlFeedback) && ~isempty(dlFeedback)
            valid = logical([dlFeedback.Valid]);
            sinrVals = double([dlFeedback.SINR_dB]);
            vals = [vals; sinrVals(valid & isfinite(sinrVals)).']; %#ok<AGROW>
        end
        ulFeedback = sixgr.util.structGet(state, "LatestULFeedback", []);
        if isstruct(ulFeedback) && ~isempty(ulFeedback)
            valid = logical([ulFeedback.Valid]);
            sinrVals = double([ulFeedback.SINR_dB]);
            vals = [vals; sinrVals(valid & isfinite(sinrVals)).']; %#ok<AGROW>
        end
        if ~isempty(vals)
            quality_dB = median(vals, "omitnan");
            sourceToken = "delivered_feedback";
            return;
        end
        pendingT = sixgr.util.structGet(state, "PendingCSITable", table());
        if istable(pendingT) && ~isempty(pendingT) && ...
                all(ismember(["SourceSlot","SINR_dB"], string(pendingT.Properties.VariableNames)))
            sinrVals = double(pendingT.SINR_dB);
            slotVals = double(pendingT.SourceSlot);
            finiteMask = isfinite(sinrVals) & isfinite(slotVals);
            if any(finiteMask)
                currentSlot = double(sixgr.util.structGet(state, "CurrentSlot", NaN));
                feedbackSlots = max(1, round(double(sixgr.util.structGet(state, "CSIFeedbackSlots", 1))));
                if isfinite(currentSlot)
                    recentMask = finiteMask & slotVals >= max(0, currentSlot - feedbackSlots);
                    if any(recentMask)
                        sinrVals = sinrVals(recentMask);
                    else
                        sinrVals = sinrVals(finiteMask);
                    end
                else
                    sinrVals = sinrVals(finiteMask);
                end
                if ~isempty(sinrVals)
                    quality_dB = median(sinrVals, "omitnan");
                    sourceToken = "pending_measured_feedback";
                end
            end
        end
    end

    function snr_dB = resolveRuntimeSignalSNRForUE(state, cfg, ueIdx, direction)
        snr_dB = NaN;
        direction = upper(string(direction));
        if ~(isfinite(double(ueIdx)) && double(ueIdx) >= 1)
            return;
        end
        feedback = sixgr.truth.CoupledTruthRuntime.latestFeedbackForDirection(state, ueIdx, direction);
        feedbackSINR = double(sixgr.util.structGet(feedback, "SINR_dB", NaN));
        if logical(sixgr.util.structGet(feedback, "Valid", false)) && isfinite(feedbackSINR)
            snr_dB = feedbackSINR;
            return;
        end
        pendingT = sixgr.util.structGet(state, "PendingCSITable", table());
        if istable(pendingT) && ~isempty(pendingT) && ...
                all(ismember(["UEIndex", "Direction", "SINR_dB"], string(pendingT.Properties.VariableNames)))
            pendingMask = isfinite(double(pendingT.UEIndex)) & ...
                double(pendingT.UEIndex) == double(ueIdx) & ...
                upper(string(pendingT.Direction)) == direction & ...
                isfinite(double(pendingT.SINR_dB));
            if any(pendingMask)
                pendingSlice = pendingT(pendingMask, :);
                if ismember("SourceSlot", string(pendingSlice.Properties.VariableNames))
                    [~, order] = sort(double(pendingSlice.SourceSlot), "descend");
                    pendingSlice = pendingSlice(order, :);
                end
                snr_dB = double(pendingSlice.SINR_dB(1));
                return;
            end
        end
        servingVec = double(sixgr.util.structGet(state, "CurrentServingIdx", []));
        servingCell = NaN;
        if double(ueIdx) <= numel(servingVec)
            servingCell = double(servingVec(ueIdx));
        end
        cfgEval = cfg;
        if ~(isstruct(cfgEval) && ~isempty(fieldnames(cfgEval)))
            cfgEval = sixgr.util.structGet(state, "CfgMobility", struct());
        end
        interferenceMode = string(sixgr.util.structGet(cfgEval, "run.interferenceExecutionMode", ...
            sixgr.util.structGet(cfgEval, "interference.inter_cell_execution_mode", "")));
        if strlength(strtrim(interferenceMode)) > 0 && isfinite(servingCell)
            estimatedSINR = sixgr.truth.CoupledTruthRuntime.estimateRuntimeWidebandSINR(state, ueIdx, servingCell, interferenceMode);
            if isfinite(estimatedSINR)
                snr_dB = estimatedSINR;
                return;
            end
        end
        runState = sixgr.util.structGet(state, "RunState", struct());
        representativeSNR = double(sixgr.util.structGet(runState, "CurrentSNR_dB", NaN));
        valueRole = lower(string(sixgr.util.structGet(runState, "ValueRole", "")));
        if isfinite(representativeSNR) && ~contains(valueRole, "configured")
            snr_dB = representativeSNR;
            return;
        end
        if ~sixgr.truth.CoupledTruthRuntime.usesReceiverNoiseMeasurementMode(state)
            snr_dB = double(sixgr.util.structGet(state, "CurrentSNR_dB", NaN));
        end
    end

    function [traceT, rowIdx] = ensureCurrentSlotTraceRow(state)
        traceT = sixgr.util.structGet(state, "SlotTraceTable", table());
        rowIdx = [];
        if ~(istable(traceT) && ~isempty(traceT))
            return;
        end
        slotId = sixgr.truth.CoupledTruthRuntime.composeSlotTraceID( ...
            sixgr.util.structGet(state, "CurrentSweepPointIndex", NaN), ...
            sixgr.util.structGet(state, "CurrentCanonicalSlot", NaN), ...
            sixgr.util.structGet(state, "CurrentSNR_dB", NaN));
        keys = string(traceT.SlotTraceID);
        rowIdx = find(keys == slotId, 1, "last");
    end

    function [traceT, rowIdx] = ensureSlotTraceRow(state, sweepIdx, sweepCount, absoluteFrame, totalFrames, snr_dB)
        traceT = sixgr.util.structGet(state, "SlotTraceTable", table());
        if ~(istable(traceT))
            traceT = struct2table(repmat(sixgr.truth.CoupledTruthRuntime.emptySlotTraceRow(), 0, 1));
        end
        canonicalSlot = max(1, round(double(absoluteFrame)));
        frameIdx = sixgr.truth.CoupledTruthRuntime.frameIndexForSlot(state, canonicalSlot);
        totalSweepFrames = sixgr.truth.CoupledTruthRuntime.framesPerSweepPoint(state, totalFrames);
        slotId = sixgr.truth.CoupledTruthRuntime.composeSlotTraceID(sweepIdx, canonicalSlot, snr_dB);
        if isempty(traceT)
            rowIdx = [];
        else
            rowIdx = find(string(traceT.SlotTraceID) == slotId, 1, "last");
        end
        if isempty(rowIdx)
            row = sixgr.truth.CoupledTruthRuntime.emptySlotTraceRow();
            row.SlotTraceID = slotId;
            row.CanonicalSlot = double(canonicalSlot);
            row.Frame = double(frameIdx);
            row.FrameLocal = 1 + mod(double(frameIdx) - 1, max(1, round(double(totalSweepFrames))));
            row.ConfiguredSNR_dB = double(snr_dB);
            row.ConfiguredSNRSource = "configured_operating_point_metadata";
            if sixgr.truth.CoupledTruthRuntime.usesReceiverNoiseMeasurementMode(state)
                row.CurrentSNR_dB = NaN;
                row.CurrentSNRSource = "receiver_measurement_pending";
                row.CurrentSNRValueRole = "runtime_receiver_measurement_pending";
                row.CurrentSNRValueStatus = "unavailable_pending_runtime_feedback";
                row.SNR_dB = NaN;
            else
                row.CurrentSNR_dB = double(snr_dB);
                row.CurrentSNRSource = "configured_operating_point_metadata";
                row.CurrentSNRValueRole = "configured_quality_until_feedback";
                row.CurrentSNRValueStatus = "configured_quality_pending_runtime_feedback";
                row.SNR_dB = double(snr_dB);
            end
            row.SweepPointIndex = double(sweepIdx);
            row.SweepPointCount = double(sweepCount);
            row.ValueSource = "CoupledTruthRuntime.recordSlotTraceStart";
            row.TraceStatus = "created";
            traceT = sixgr.truth.CoupledTruthRuntime.appendCompatTable(traceT, struct2table(row));
            rowIdx = height(traceT);
        end
        traceT.SpecialSlotActive(rowIdx) = logical(sixgr.util.structGet(state, "CurrentSlotIsSpecial", false));
        traceT.DLSymbolStart(rowIdx) = double(sixgr.util.structGet(state, "CurrentSlotDLSymbolStart", 0));
        traceT.DLNumSymbols(rowIdx) = double(sixgr.util.structGet(state, "CurrentSlotDLNumSymbols", 14));
        traceT.GuardSymbolStart(rowIdx) = double(sixgr.util.structGet(state, "CurrentSlotGuardSymbolStart", 14));
        traceT.GuardNumSymbols(rowIdx) = double(sixgr.util.structGet(state, "CurrentSlotGuardNumSymbols", 0));
        traceT.ULSymbolStart(rowIdx) = double(sixgr.util.structGet(state, "CurrentSlotULSymbolStart", 0));
        traceT.ULNumSymbols(rowIdx) = double(sixgr.util.structGet(state, "CurrentSlotULNumSymbols", 14));
    end

    function id = composeSlotTraceID(sweepIdx, canonicalSlot, snr_dB)
        id = "sweep=" + string(double(sweepIdx)) + ...
            ";canonical_slot=" + string(double(canonicalSlot)) + ...
            ";snr_db=" + string(round(double(snr_dB), 9));
    end

    function status = slotTraceStatus(row)
        dl = logical(sixgr.truth.CoupledTruthRuntime.rowLogical(row, "DLStarted", false));
        ul = logical(sixgr.truth.CoupledTruthRuntime.rowLogical(row, "ULStarted", false));
        dlSched = logical(sixgr.truth.CoupledTruthRuntime.rowLogical(row, "DLScheduled", false));
        ulSched = logical(sixgr.truth.CoupledTruthRuntime.rowLogical(row, "ULScheduled", false));
        dlPub = double(sixgr.truth.CoupledTruthRuntime.rowValue(row, "DLTrialRows", 0)) > 0;
        ulPub = double(sixgr.truth.CoupledTruthRuntime.rowValue(row, "ULTrialRows", 0)) > 0;
        if dlPub && ulPub
            status = "dl_ul_published";
        elseif dlSched && ulSched
            status = "dl_ul_scheduled";
        elseif dl && ul
            status = "dl_ul_started";
        elseif dl || ul
            status = "partial_direction_started";
        else
            status = "created";
        end
    end

    function row = emptySlotTraceRow()
        row = struct( ...
            "SlotTraceID", "", "CanonicalSlot", NaN, "Frame", NaN, "FrameLocal", NaN, ...
            "ConfiguredSNR_dB", NaN, "ConfiguredSNRSource", "", ...
            "CurrentSNR_dB", NaN, "CurrentSNRSource", "", "CurrentSNRValueRole", "", "CurrentSNRValueStatus", "", ...
            "SNR_dB", NaN, "SweepPointIndex", NaN, "SweepPointCount", NaN, ...
            "SpecialSlotActive", false, ...
            "DLSymbolStart", 0, "DLNumSymbols", 14, ...
            "GuardSymbolStart", 14, "GuardNumSymbols", 0, ...
            "ULSymbolStart", 0, "ULNumSymbols", 14, ...
            "DLSlot", NaN, "ULSlot", NaN, ...
            "DLStarted", false, "ULStarted", false, ...
            "DLScheduled", false, "ULScheduled", false, ...
            "DLActiveUsers", 0, "ULActiveUsers", 0, ...
            "DLGrantedUsers", 0, "ULGrantedUsers", 0, ...
            "DLGrantCount", 0, "ULGrantCount", 0, ...
            "DLExecutedGrantCount", 0, "ULExecutedGrantCount", 0, ...
            "DLTrialRows", 0, "ULTrialRows", 0, ...
            "DLSuccessCount", 0, "ULSuccessCount", 0, ...
            "DLQueueBits", 0, "ULQueueBits", 0, ...
            "DLTBSBits", 0, "ULTBSBits", 0, ...
            "HARQTimelineRows", 0, ...
            "MobilitySource", "CoupledTruthRuntime.advanceFrame", ...
            "SchedulerSource", "CoupledTruthRuntime.scheduleDirection", ...
            "PHYSource", "runWaveformLinkBundle.executeGrantPHYJob", ...
            "ReportSource", "slot_trace.csv", ...
            "DLStatus", "", "ULStatus", "", "TraceStatus", "", ...
            "ValueRole", "measured", "ValueStatus", "OK", ...
            "ValueSource", "CoupledTruthRuntime.SlotTraceTable", ...
            "ValueDefinition", "canonical per-slot trace parent for DL grants, UL grants, HARQ, mobility, control gating, and waveform PHY trial rows", ...
            "NAReason", "");
    end

    function Tout = appendCompatTable(Ta, Tb)
        if ~(istable(Ta) && ~isempty(Ta))
            if istable(Tb)
                Tout = Tb;
            else
                Tout = table();
            end
            return;
        end
        if ~(istable(Tb) && ~isempty(Tb))
            Tout = Ta;
            return;
        end
        vars = union(string(Ta.Properties.VariableNames), string(Tb.Properties.VariableNames), "stable");
        Ta = sixgr.truth.CoupledTruthRuntime.ensureTableVars(Ta, vars, Tb);
        Tb = sixgr.truth.CoupledTruthRuntime.ensureTableVars(Tb, vars, Ta);
        for i = 1:numel(vars)
            v = char(vars(i));
            [Ta.(v), Tb.(v)] = sixgr.truth.CoupledTruthRuntime.harmonizeColumns(Ta.(v), Tb.(v));
        end
        Tout = [Ta(:, cellstr(vars)); Tb(:, cellstr(vars))];
    end

    function T = ensureTableVars(T, vars, refT)
        for i = 1:numel(vars)
            v = char(vars(i));
            if ~ismember(v, T.Properties.VariableNames)
                T.(v) = sixgr.truth.CoupledTruthRuntime.defaultColumnLike(refT, v, height(T));
            end
        end
    end

    function [lhs, rhs] = harmonizeStructArray(lhs, rhs)
        if ~isstruct(lhs)
            lhs = struct();
        end
        if ~isstruct(rhs)
            rhs = struct();
        end
        lhsFields = string(fieldnames(lhs));
        rhsFields = string(fieldnames(rhs));
        allFields = union(lhsFields, rhsFields, "stable");
        for i = 1:numel(allFields)
            fieldName = char(allFields(i));
            if ~isfield(lhs, fieldName)
                [lhs(1:numel(lhs)).(fieldName)] = deal([]);
            end
            if ~isfield(rhs, fieldName)
                [rhs(1:numel(rhs)).(fieldName)] = deal([]);
            end
        end
    end

    function col = defaultColumnLike(refT, varName, nRows)
        if istable(refT) && ismember(varName, refT.Properties.VariableNames)
            refVal = refT.(varName);
            if isstring(refVal)
                col = strings(nRows, 1);
                return;
            end
            if iscellstr(refVal) || iscell(refVal) || ischar(refVal)
                col = strings(nRows, 1);
                return;
            end
            if islogical(refVal)
                col = false(nRows, 1);
                return;
            end
            if isnumeric(refVal)
                col = nan(nRows, 1);
                return;
            end
        end
        col = strings(nRows, 1);
    end

    function [a, b] = harmonizeColumns(a, b)
        if isstring(a) || isstring(b) || iscellstr(a) || iscellstr(b) || iscell(a) || iscell(b) || ischar(a) || ischar(b)
            a = string(a);
            b = string(b);
            a = a(:);
            b = b(:);
            return;
        end
        if islogical(a) && isnumeric(b)
            b = logical(b);
            return;
        end
        if isnumeric(a) && islogical(b)
            a = logical(a);
            return;
        end
    end

    function ueid = resolveUEID(ue, idx)
        ids = sixgr.util.structGet(ue, "id", []);
        if isempty(ids)
            ueid = double(idx);
        else
            ueid = double(ids(idx));
        end
    end

    function value = ueColumn(ue, fieldName, idx)
        value = sixgr.util.structGet(ue, fieldName, []);
        if isempty(value)
            value = NaN;
            return;
        end
        value = double(value(idx));
    end

    function value = safeDivide(num, den)
        if ~(isfinite(num) && isfinite(den) && den > 0)
            value = NaN;
        else
            value = double(num) / double(den);
        end
    end

    function mbps = directionThroughputMbps(goodBits, duration_s, frames)
        if ~(isfinite(double(frames)) && double(frames) > 0)
            mbps = NaN;
            return;
        end
        mbps = sixgr.truth.CoupledTruthRuntime.safeDivide(goodBits, duration_s) / 1e6;
    end

    function bler = directionBLER(crcSum, frames)
        if ~(isfinite(double(frames)) && double(frames) > 0)
            bler = NaN;
            return;
        end
        passRate = sixgr.truth.CoupledTruthRuntime.safeDivide(crcSum, frames);
        if isfinite(passRate)
            bler = 1 - passRate;
        else
            bler = NaN;
        end
    end

    function status = directionExecutionStatus(frames)
        if isfinite(double(frames)) && double(frames) > 0
            status = "executed";
        else
            status = "not_executed";
        end
    end

    function row = emptyDirectionStatRow()
        row = struct("RNTI", NaN, "Frames", 0, "CRCSum", 0, "GoodBitsSum", 0, "SINRSum", 0, "SINRCount", 0);
    end

    function row = emptyServingRow()
        row = struct( ...
            "Slot", NaN, "Time_s", NaN, "UEID", NaN, ...
            "Lat", NaN, "Lon", NaN, "X_m", NaN, "Y_m", NaN, "Z_m", NaN, ...
            "Speed_kmh", NaN, "Heading_deg", NaN, ...
            "ServingCell", NaN, "ServingSite", NaN, "ServingSector", NaN, ...
            "ServingBeamIndex", NaN, "ServingBeamGain_dB", NaN, ...
            "ConfiguredSNR_dB", NaN, "ConfiguredSNRSource", "", "ServingRSRP_dBm", NaN, ...
            "RSRP_dBm", NaN, "RxPower_dBm", NaN, "Pathloss_dB", NaN, ...
            "LOSFlag", false, "ShadowFading_dB", NaN, "O2I_dB", NaN, ...
            "ChannelComplianceMode", "", "PathlossModelSource", "", "PathlossComplianceStatus", "", "FallbackUsedForPathloss", false, ...
            "O2IModelSource", "", "O2IComplianceStatus", "", "O2IComplianceReason", "", ...
            "LOSProbabilitySource", "", "LOSComplianceStatus", "", "LOSComplianceReason", "", ...
            "ReceiverHestSINR_dB", NaN, "ReceiverHestSINRSource", "", ...
            "PostEqSINR_dB", NaN, "PostEqSINRSource", "", "PostEqSINRValueRole", "", "PostEqSINRValueStatus", "", ...
            "DecoderTruthProxySINR_dB", NaN, "DecoderTruthProxySINRSource", "", ...
            "MeasuredTrialSINR_dB", NaN, "EstimatedWidebandSINR_dB", NaN, "ReceiverHestWidebandSINR_dB", NaN, "PostEqWidebandSINR_dB", NaN, "DecoderTruthProxyWidebandSINR_dB", NaN, "MeasuredWidebandSINR_dB", NaN, ...
            "LargeScaleWidebandSINR_dB", NaN, "LargeScaleSINR_dB", NaN, ...
            "CSI_RSRP_dB", NaN, "CSI_RSRPSource", "", "AppliedLargeScaleGain_dB", NaN, ...
            "RSRPSource", "", "ServingRSRPSource", "", "WidebandSINRSource", "", "WidebandSINRValueRole", "", "InterferenceMode", "", ...
            "WidebandCQI", NaN, ...
            "CQIDerivedMCS", NaN, "CQIDerivedModulation", "", ...
            "CQIDerivedTargetCodeRate", NaN, "CoverageScore", NaN);
    end

    function row = emptyMeasurementRow()
        row = struct( ...
            "Slot", NaN, "Time_s", NaN, "UEID", NaN, "CandidateRank", NaN, ...
            "CellID", NaN, "SiteID", NaN, "SectorID", NaN, ...
            "Lat", NaN, "Lon", NaN, "RSRP_dBm", NaN, "RxPower_dBm", NaN, ...
            "Pathloss_dB", NaN, "BeamIndex", NaN, "BeamGain_dB", NaN, ...
            "LOSFlag", false, "ShadowFading_dB", NaN, "O2I_dB", NaN, ...
            "ChannelComplianceMode", "", "PathlossModelSource", "", "PathlossComplianceStatus", "", "FallbackUsedForPathloss", false, ...
            "O2IModelSource", "", "O2IComplianceStatus", "", "O2IComplianceReason", "", ...
            "LOSProbabilitySource", "", "LOSComplianceStatus", "", "LOSComplianceReason", "");
    end

    function row = emptyReselectionRow()
        row = struct( ...
            "Slot", NaN, "Time_s", NaN, "UEID", NaN, ...
            "FromCell", NaN, "ToCell", NaN, ...
            "FromRSRP_dBm", NaN, "ToRSRP_dBm", NaN, "Reason", "");
    end

    function row = emptyCoverageRow()
        row = struct( ...
            "UEID", NaN, "Slot", NaN, "Time_s", NaN, ...
            "Lat", NaN, "Lon", NaN, ...
            "ServingCell", NaN, "ServingSite", NaN, "ServingSector", NaN, ...
            "ConfiguredSNR_dB", NaN, "ConfiguredSNRSource", "", "ServingRSRP_dBm", NaN, "RSRP_dBm", NaN, ...
            "ReceiverHestSINR_dB", NaN, "ReceiverHestSINRSource", "", ...
            "PostEqSINR_dB", NaN, "PostEqSINRSource", "", "PostEqSINRValueRole", "", "PostEqSINRValueStatus", "", ...
            "DecoderTruthProxySINR_dB", NaN, "DecoderTruthProxySINRSource", "", ...
            "MeasuredTrialSINR_dB", NaN, "EstimatedWidebandSINR_dB", NaN, "ReceiverHestWidebandSINR_dB", NaN, "PostEqWidebandSINR_dB", NaN, "DecoderTruthProxyWidebandSINR_dB", NaN, "MeasuredWidebandSINR_dB", NaN, ...
            "LargeScaleWidebandSINR_dB", NaN, "LargeScaleSINR_dB", NaN, ...
            "CSI_RSRP_dB", NaN, "CSI_RSRPSource", "", "AppliedLargeScaleGain_dB", NaN, ...
            "RSRPSource", "", "ServingRSRPSource", "", "WidebandSINRSource", "", "WidebandSINRValueRole", "", "InterferenceMode", "", "WidebandCQI", NaN, ...
            "CQIDerivedMCS", NaN, "CQIDerivedModulation", "", ...
            "CQIDerivedTargetCodeRate", NaN, "Pathloss_dB", NaN, "CoverageScore", NaN);
    end

    function row = emptyCoverageLayerRow()
        row = struct( ...
            "UEID", NaN, "Slot", NaN, "Time_s", NaN, ...
            "Lat", NaN, "Lon", NaN, ...
            "ServingCell", NaN, "ServingSite", NaN, "ServingSector", NaN, ...
            "ConfiguredSNR_dB", NaN, "ConfiguredSNRSource", "", "ServingRSRP_dBm", NaN, "RSRP_dBm", NaN, ...
            "ReceiverHestSINR_dB", NaN, "ReceiverHestSINRSource", "", ...
            "PostEqSINR_dB", NaN, "PostEqSINRSource", "", "PostEqSINRValueRole", "", "PostEqSINRValueStatus", "", ...
            "DecoderTruthProxySINR_dB", NaN, "DecoderTruthProxySINRSource", "", ...
            "MeasuredTrialSINR_dB", NaN, "EstimatedWidebandSINR_dB", NaN, "ReceiverHestWidebandSINR_dB", NaN, "PostEqWidebandSINR_dB", NaN, "DecoderTruthProxyWidebandSINR_dB", NaN, "MeasuredWidebandSINR_dB", NaN, ...
            "LargeScaleWidebandSINR_dB", NaN, "LargeScaleSINR_dB", NaN, ...
            "CSI_RSRP_dB", NaN, "CSI_RSRPSource", "", "AppliedLargeScaleGain_dB", NaN, ...
            "RSRPSource", "", "ServingRSRPSource", "", "WidebandSINRSource", "", "WidebandSINRValueRole", "", "InterferenceMode", "", "WidebandCQI", NaN, ...
            "CQIDerivedMCS", NaN, "CQIDerivedModulation", "", ...
            "CQIDerivedTargetCodeRate", NaN, "Pathloss_dB", NaN, "CoverageScore", NaN, ...
            "UserThroughput_Mbps", NaN, "HARQFailureRate", NaN, "CellThroughput_Mbps", NaN);
    end

    function T = annotateControlReferenceTrialTableImpl(state, signalName, T)
        if nargin < 3 || ~istable(T)
            T = table();
        end
        if isempty(T)
            return;
        end
        signalName = upper(strtrim(string(signalName)));
        n = height(T);
        meta = sixgr.truth.CoupledTruthRuntime.runtimeExportMetadata(state);
        [classification, materialization, gatingEffect, consumer] = ...
            sixgr.truth.CoupledTruthRuntime.controlReferenceTruthTokens(signalName);

        status = upper(strtrim(string(sixgr.truth.CoupledTruthRuntime.tableColumnOrDefault(T, "Status", repmat("", n, 1)))));
        crcPass = double(sixgr.truth.CoupledTruthRuntime.tableColumnOrDefault(T, "CRCPass", nan(n, 1)));
        decodeSuccess = isfinite(crcPass) & crcPass ~= 0;
        decodeSuccess(~isfinite(crcPass) & status == "PASS") = true;
        pendingMask = status == "PENDING" | contains(status, "PENDING");
        failureFlag = (status == "FAIL" | status == "CRASH") | (~decodeSuccess & ~pendingMask & status ~= "" & status ~= "NA");

        T = sixgr.truth.CoupledTruthRuntime.setStringColumn(T, "SignalFamily", signalName, true);
        T = sixgr.truth.CoupledTruthRuntime.setStringColumn(T, "SourceClassification", classification, true);
        T = sixgr.truth.CoupledTruthRuntime.setStringColumn(T, "RuntimeMaterializationStatus", materialization, true);
        T = sixgr.truth.CoupledTruthRuntime.setStringColumn(T, "ControlGatingEffect", gatingEffect, true);
        T = sixgr.truth.CoupledTruthRuntime.setStringColumn(T, "RuntimeStateConsumer", consumer, false);
        T = sixgr.truth.CoupledTruthRuntime.setStringColumn(T, "RuntimeConsumer", consumer, false);
        T = sixgr.truth.CoupledTruthRuntime.applyPRACHFullRARuntimeTokens(signalName, T);
        T = sixgr.truth.CoupledTruthRuntime.setLogicalColumn(T, "DecodeSuccess", decodeSuccess);
        T = sixgr.truth.CoupledTruthRuntime.setLogicalColumn(T, "SuccessFlag", decodeSuccess);
        T = sixgr.truth.CoupledTruthRuntime.setLogicalColumn(T, "FailureFlag", failureFlag);
        T = sixgr.truth.CoupledTruthRuntime.setLogicalColumn(T, "ControlObservationAvailable", ~pendingMask);
        T = sixgr.truth.CoupledTruthRuntime.setStringColumn(T, "ValueSource", "runtime_control_reference_signal_observation", false);
        T = sixgr.truth.CoupledTruthRuntime.setStringColumn(T, "ValueRole", "control_reference_signal_runtime_evidence", false);
        T = sixgr.truth.CoupledTruthRuntime.setStringColumn(T, "ValueStatus", "available_runtime_observation", false);
        T = sixgr.truth.CoupledTruthRuntime.setStringColumn(T, "ValueDefinition", "canonical control/reference-signal row emitted by the active LLS coupled runtime", false);
        T = sixgr.truth.CoupledTruthRuntime.setLogicalColumn(T, "FinalizedFlag", ~pendingMask);
        T = sixgr.truth.CoupledTruthRuntime.setLogicalColumn(T, "PlaceholderFlag", false(n, 1));
        T = sixgr.truth.CoupledTruthRuntime.setLogicalColumn(T, "FallbackFlag", false(n, 1));
        T = sixgr.truth.CoupledTruthRuntime.setStringColumn(T, "NAReason", "", false);
        T = sixgr.truth.CoupledTruthRuntime.applyRuntimeMetadataColumns(T, meta, signalName);
        directionValues = string(sixgr.truth.CoupledTruthRuntime.tableColumnOrDefault(T, "Direction", repmat("", n, 1)));
        if ~ismember("Direction", string(T.Properties.VariableNames))
            directionValues = string(sixgr.truth.CoupledTruthRuntime.tableColumnOrDefault(T, "LinkDirection", repmat("", n, 1)));
            if all(strlength(strtrim(directionValues)) == 0)
                directionValues = string(sixgr.truth.CoupledTruthRuntime.tableColumnOrDefault(T, "TrialDirection", repmat("", n, 1)));
            end
            if all(strlength(strtrim(directionValues)) == 0)
                directionValues = string(sixgr.truth.CoupledTruthRuntime.tableColumnOrDefault(T, "GrantDirection", repmat("", n, 1)));
            end
            if any(strlength(strtrim(directionValues)) > 0)
                T = sixgr.truth.CoupledTruthRuntime.setStringColumn(T, "Direction", directionValues, false);
            end
        end
        directionValues = string(sixgr.truth.CoupledTruthRuntime.tableColumnOrDefault(T, "Direction", repmat("", n, 1)));
        if any(strlength(strtrim(directionValues)) > 0)
            T = sixgr.truth.CoupledTruthRuntime.setStringColumn(T, "TrialDirection", directionValues, false);
            T = sixgr.truth.CoupledTruthRuntime.setStringColumn(T, "LinkDirection", directionValues, false);
            T = sixgr.truth.CoupledTruthRuntime.setStringColumn(T, "GrantDirection", directionValues, false);
        end
        T = sixgr.truth.CoupledTruthRuntime.annotateControlReferenceSINRColumnsImpl(signalName, T);

        if signalName == "TRS"
            trsCtx = sixgr.truth.CoupledTruthRuntime.resolveTRSControlAnnotationContext(state, T);
            T = sixgr.truth.CoupledTruthRuntime.setStringColumn(T, "TRSStateSource", string(trsCtx.TRSStateSource), false);
            T = sixgr.truth.CoupledTruthRuntime.setStringColumn(T, "TRSRuntimeConsumer", string(trsCtx.TRSRuntimeConsumer), false);
            T = sixgr.truth.CoupledTruthRuntime.setStringColumn(T, "TRSReceiverIntegrationStatus", string(trsCtx.TRSReceiverIntegrationStatus), false);
            T = sixgr.truth.CoupledTruthRuntime.setStringColumn(T, "TRSReceiverIntegrationBlocker", string(trsCtx.TRSReceiverIntegrationBlocker), false);
            T = sixgr.truth.CoupledTruthRuntime.setStringColumn(T, "TRSReceiverConsumerType", string(trsCtx.TRSReceiverConsumerType), false);
            T = sixgr.truth.CoupledTruthRuntime.setStringColumn(T, "TRSTrackingStateBefore", string(trsCtx.TRSTrackingStateBefore), false);
            T = sixgr.truth.CoupledTruthRuntime.setStringColumn(T, "TRSTrackingStateAfter", string(trsCtx.TRSTrackingStateAfter), false);
            T = sixgr.truth.CoupledTruthRuntime.setStringColumn(T, "TRSUpdateOutcome", string(trsCtx.TRSUpdateOutcome), false);
            T = sixgr.truth.CoupledTruthRuntime.setStringColumn(T, "TRSChannelTrackingFreshnessState", string(trsCtx.TRSChannelTrackingFreshnessState), false);
            T = sixgr.truth.CoupledTruthRuntime.setStringColumn(T, "TRSFrequencyTrackingState", string(trsCtx.TRSFrequencyTrackingState), false);
            T = sixgr.truth.CoupledTruthRuntime.setStringColumn(T, "TRSTimingTrackingState", string(trsCtx.TRSTimingTrackingState), false);
            T = sixgr.truth.CoupledTruthRuntime.setStringColumn(T, "TRSRuntimeEvidenceSource", string(trsCtx.TRSRuntimeEvidenceSource), false);
            if ~ismember("TRSProcessed", string(T.Properties.VariableNames))
                T.TRSProcessed = repmat(logical(trsCtx.TRSProcessed), n, 1);
            end
            T = sixgr.truth.CoupledTruthRuntime.setNumericColumn(T, "TRSTrackingUpdateTime_s", repmat(double(trsCtx.TRSTrackingUpdateTime_s), n, 1), false);
            T = sixgr.truth.CoupledTruthRuntime.setNumericColumn(T, "TRSAssociatedCell", repmat(double(trsCtx.TRSAssociatedCell), n, 1), false);
            if ~ismember("TRSTimingEstimateAvailable", string(T.Properties.VariableNames))
                T.TRSTimingEstimateAvailable = repmat(logical(trsCtx.TRSTimingEstimateAvailable), n, 1);
            end
            T = sixgr.truth.CoupledTruthRuntime.setNumericColumn(T, "TRSTimingEstimate_samples", repmat(double(trsCtx.TRSTimingEstimate_samples), n, 1), false);
            if ~ismember("TRSCFOEstimateAvailable", string(T.Properties.VariableNames))
                T.TRSCFOEstimateAvailable = repmat(logical(trsCtx.TRSCFOEstimateAvailable), n, 1);
            end
            T = sixgr.truth.CoupledTruthRuntime.setNumericColumn(T, "TRSEstimatedCFO_Hz", repmat(double(trsCtx.TRSEstimatedCFO_Hz), n, 1), false);
        end
        T = sixgr.truth.CoupledTruthRuntime.fillBlankCategoricalColumns(T, lower(strrep(char(signalName), "-", "_")));
    end

    function T = annotatePUCCHGrantTraceTableImpl(state, T)
        if nargin < 2 || ~istable(T)
            T = table();
        end
        if isempty(T)
            return;
        end
        n = height(T);
        meta = sixgr.truth.CoupledTruthRuntime.runtimeExportMetadata(state);
        executed = logical(sixgr.truth.CoupledTruthRuntime.tableColumnOrDefault(T, "GrantExecutedFlag", false(n, 1)));
        decodeOk = logical(sixgr.truth.CoupledTruthRuntime.tableColumnOrDefault(T, "PUCCHDecodeOk", false(n, 1)));
        crashed = logical(sixgr.truth.CoupledTruthRuntime.tableColumnOrDefault(T, "Crash", false(n, 1)));
        status = strtrim(string(sixgr.truth.CoupledTruthRuntime.tableColumnOrDefault(T, "Status", repmat("", n, 1))));
        blank = strlength(status) == 0;
        status(blank & ~executed) = "PENDING";
        status(blank & executed & decodeOk) = "PASS";
        status(blank & executed & ~decodeOk & ~crashed) = "FAIL";
        status(blank & crashed) = "CRASH";
        T.Status = status;

        classification = repmat("active_integrated", n, 1);
        classification(~executed) = "active_but_simplified";
        materialization = repmat("active_integrated_waveform_feedback_runtime", n, 1);
        materialization(~executed) = "active_scheduled_pending_feedback_due_not_reached";
        materialization(executed & crashed) = "active_waveform_feedback_execution_crashed";

        T = sixgr.truth.CoupledTruthRuntime.setStringColumn(T, "SignalFamily", "PUCCH", true);
        T = sixgr.truth.CoupledTruthRuntime.setStringColumn(T, "SourceClassification", classification, true);
        T = sixgr.truth.CoupledTruthRuntime.setStringColumn(T, "RuntimeMaterializationStatus", materialization, true);
        T = sixgr.truth.CoupledTruthRuntime.setStringColumn(T, "ControlGatingEffect", "harq_feedback_resource_grant_and_state_update_when_due", true);
        T = sixgr.truth.CoupledTruthRuntime.setStringColumn(T, "RuntimeStateConsumer", "pending_feedback_due_slot", false);
        if any(executed)
            consumer = string(T.RuntimeStateConsumer);
            consumer(executed) = "HARQEntity.onFeedback";
            T.RuntimeStateConsumer = consumer;
        end
        T = sixgr.truth.CoupledTruthRuntime.setStringColumn(T, "RuntimeConsumer", string(T.RuntimeStateConsumer), true);
        T = sixgr.truth.CoupledTruthRuntime.setLogicalColumn(T, "DecodeSuccess", decodeOk);
        T = sixgr.truth.CoupledTruthRuntime.setLogicalColumn(T, "SuccessFlag", executed & decodeOk);
        T = sixgr.truth.CoupledTruthRuntime.setLogicalColumn(T, "FailureFlag", executed & ~decodeOk);
        T = sixgr.truth.CoupledTruthRuntime.setLogicalColumn(T, "ControlObservationAvailable", executed);
        T = sixgr.truth.CoupledTruthRuntime.setStringColumn(T, "ValueSource", "runtime_pucch_grant_trace", false);
        T = sixgr.truth.CoupledTruthRuntime.setStringColumn(T, "ValueRole", "explicit_pucch_grant_and_feedback_runtime_state", false);
        T = sixgr.truth.CoupledTruthRuntime.setStringColumn(T, "ValueStatus", "available_runtime_grant_state", false);
        T = sixgr.truth.CoupledTruthRuntime.setStringColumn(T, "ValueDefinition", "canonical PUCCH grant/resource row; waveform decode fields become available only after the feedback due slot is processed", false);
        T = sixgr.truth.CoupledTruthRuntime.setLogicalColumn(T, "FinalizedFlag", executed);
        T = sixgr.truth.CoupledTruthRuntime.setLogicalColumn(T, "PlaceholderFlag", false(n, 1));
        T = sixgr.truth.CoupledTruthRuntime.setLogicalColumn(T, "FallbackFlag", false(n, 1));
        naReason = repmat("", n, 1);
        naReason(~executed) = "feedback_due_slot_not_reached_in_this_bounded_run";
        T = sixgr.truth.CoupledTruthRuntime.setStringColumn(T, "NAReason", naReason, true);
        T = sixgr.truth.CoupledTruthRuntime.applyRuntimeMetadataColumns(T, meta, "PUCCH");
        T = sixgr.truth.CoupledTruthRuntime.fillBlankCategoricalColumns(T, "pucch_grant_trace");
    end

    function meta = runtimeExportMetadata(state)
        meta = struct("RunID", NaN, "RunUUID", "", "RunTag", "", "ScenarioID", "", "ConfigHash", "");
        storeState = struct();
        try
            storeState = sixgr.db.artifactStore("get_state");
        catch
            storeState = struct();
        end
        cfg = sixgr.util.structGet(state, "CfgMobility", struct());
        meta.RunID = double(sixgr.util.structGet(storeState, "RunID", sixgr.util.structGet(storeState, "run_id", NaN)));
        meta.RunUUID = char(string(sixgr.util.structGet(storeState, "RunUUID", "")));
        meta.RunTag = char(string(sixgr.util.structGet(cfg, "run.runTag", "")));
        meta.ScenarioID = char(string(sixgr.util.structGet(cfg, "run.scenarioID", ...
            sixgr.util.structGet(cfg, "meta.lls6gScenarioID", sixgr.util.structGet(cfg, "meta.loadedFrom", "")))));
        meta.ConfigHash = char(string(sixgr.util.structGet(cfg, "meta.configHash", "")));
    end

    function T = applyRuntimeMetadataColumns(T, meta, signalName)
        n = height(T);
        T = sixgr.truth.CoupledTruthRuntime.setNumericColumn(T, "RunID", repmat(double(meta.RunID), n, 1), false);
        T = sixgr.truth.CoupledTruthRuntime.setStringColumn(T, "RunUUID", string(meta.RunUUID), false);
        T = sixgr.truth.CoupledTruthRuntime.setStringColumn(T, "RunTag", string(meta.RunTag), false);
        T = sixgr.truth.CoupledTruthRuntime.setStringColumn(T, "ScenarioID", string(meta.ScenarioID), false);
        T = sixgr.truth.CoupledTruthRuntime.setStringColumn(T, "ConfigHash", string(meta.ConfigHash), false);
        artifact = "air_interface/csv/" + lower(string(signalName)) + "_trials.csv";
        if upper(string(signalName)) == "PUCCH" && ismember("PUCCHGrantState", string(T.Properties.VariableNames))
            artifact = "packet_flow/csv/live_pucch_grants.csv";
        end
        T = sixgr.truth.CoupledTruthRuntime.setStringColumn(T, "SourceArtifact", artifact, false);
        T = sixgr.truth.CoupledTruthRuntime.setStringColumn(T, "SourceTable", artifact, false);
        T = sixgr.truth.CoupledTruthRuntime.setStringColumn(T, "ArtifactClass", "canonical_control_reference_signal_runtime_evidence", false);
        T = sixgr.truth.CoupledTruthRuntime.setStringColumn(T, "SemanticState", "runtime_populated", false);
    end

    function [classification, materialization, gatingEffect, consumer] = controlReferenceTruthTokens(signalName)
        signalName = upper(string(signalName));
        switch signalName
            case "PBCH"
                classification = "active_integrated";
                materialization = "active_integrated_waveform_cell_search_gate";
                gatingEffect = "cell_acquisition_gate";
                consumer = "CoupledTruthRuntime.applyPBCHTrial";
            case "PRACH"
                classification = "active_but_simplified";
                materialization = "active_but_simplified_waveform_prach_detection_gate_no_full_ra_procedure";
                gatingEffect = "random_access_gate_simplified_ra";
                consumer = "CoupledTruthRuntime.applyPRACHTrial";
            case "PDCCH"
                classification = "active_integrated";
                materialization = "active_integrated_pdcch_blind_dci_crc_cce_reg_evidence";
                gatingEffect = "grant_execution_gate";
                consumer = "CoupledTruthRuntime.applyPDCCHGrantTrial";
            case "PUCCH"
                classification = "active_integrated";
                materialization = "active_integrated_waveform_feedback_runtime";
                gatingEffect = "harq_feedback_state_update";
                consumer = "HARQEntity.onFeedback";
            case "SRS"
                classification = "active_integrated";
                materialization = "active_integrated_waveform_srs_channel_estimation_gate";
                gatingEffect = "srs_freshness_csi_gate";
                consumer = "CoupledTruthRuntime.applySRSTrial";
            case "TRS"
                classification = "active_integrated";
                materialization = "active_integrated_waveform_trs_shared_receiver_tracking_state";
                gatingEffect = "shared_receiver_tracking_state_feeds_scheduler_eligibility_when_configured";
                consumer = "shared_receiver_tracking_state";
            otherwise
                classification = "missing";
                materialization = "missing_runtime_control_reference_signal";
                gatingEffect = "none";
                consumer = "none";
        end
    end

    function T = applyPRACHFullRARuntimeTokens(signalName, T)
        if upper(string(signalName)) ~= "PRACH" || ~(istable(T) && ~isempty(T))
            return;
        end
        n = height(T);
        raProcedure = lower(strtrim(string(sixgr.truth.CoupledTruthRuntime.tableColumnOrDefault( ...
            T, "RAProcedureType", repmat("", n, 1)))));
        fullSource = strtrim(string(sixgr.truth.CoupledTruthRuntime.tableColumnOrDefault( ...
            T, "FullRAEvidenceSource", repmat("", n, 1))));
        raCompleted = sixgr.truth.CoupledTruthRuntime.logicalVectorOrDefault( ...
            sixgr.truth.CoupledTruthRuntime.tableColumnOrDefault(T, "RACompleted", false(n, 1)), n, false);
        preambleDetected = sixgr.truth.CoupledTruthRuntime.logicalVectorOrDefault( ...
            sixgr.truth.CoupledTruthRuntime.tableColumnOrDefault(T, "PreambleDetected", false(n, 1)), n, false);
        msg2Ok = sixgr.truth.CoupledTruthRuntime.logicalVectorOrDefault( ...
            sixgr.truth.CoupledTruthRuntime.tableColumnOrDefault(T, "Msg2RARNTIDetected", false(n, 1)), n, false);
        msg3Ok = sixgr.truth.CoupledTruthRuntime.logicalVectorOrDefault( ...
            sixgr.truth.CoupledTruthRuntime.tableColumnOrDefault(T, "Msg3PUSCHCrcPass", false(n, 1)), n, false);
        msg4Ok = sixgr.truth.CoupledTruthRuntime.logicalVectorOrDefault( ...
            sixgr.truth.CoupledTruthRuntime.tableColumnOrDefault(T, "Msg4PDSCHCrcPass", false(n, 1)), n, false);
        preambleTx = double(sixgr.truth.CoupledTruthRuntime.tableColumnOrDefault(T, "PreambleIndexTx", nan(n, 1)));
        rarnti = double(sixgr.truth.CoupledTruthRuntime.tableColumnOrDefault(T, "RARNTI", nan(n, 1)));
        timingAdvance = double(sixgr.truth.CoupledTruthRuntime.tableColumnOrDefault(T, "TimingAdvanceCommand", nan(n, 1)));
        hasMsgEvidence = isfinite(preambleTx) | isfinite(rarnti) | isfinite(timingAdvance) | ...
            preambleDetected | msg2Ok | msg3Ok | msg4Ok;
        hasExplicitFullRA = raProcedure == "contention_based_four_step" | strlength(fullSource) > 0;
        fullMask = (raCompleted | hasExplicitFullRA) & hasMsgEvidence;
        if ~any(fullMask)
            return;
        end
        T = sixgr.truth.CoupledTruthRuntime.setStringColumn(T, "SourceClassification", "", false);
        T = sixgr.truth.CoupledTruthRuntime.setStringColumn(T, "RuntimeMaterializationStatus", "", false);
        T = sixgr.truth.CoupledTruthRuntime.setStringColumn(T, "ControlGatingEffect", "", false);
        T = sixgr.truth.CoupledTruthRuntime.setStringColumn(T, "RuntimeStateConsumer", "", false);
        T = sixgr.truth.CoupledTruthRuntime.setStringColumn(T, "RuntimeConsumer", "", false);
        T = sixgr.truth.CoupledTruthRuntime.setStringColumn(T, "RuntimeEvidenceSource", "", false);
        T = sixgr.truth.CoupledTruthRuntime.setStringColumn(T, "ValueDefinition", "", false);
        T.SourceClassification(fullMask) = "active_integrated";
        T.RuntimeMaterializationStatus(fullMask) = "active_integrated_four_step_ra_waveform_msg1_msg2_msg3_msg4";
        T.ControlGatingEffect(fullMask) = "random_access_gate_full_four_step_ra";
        T.RuntimeStateConsumer(fullMask) = "CoupledTruthRuntime.applyPRACHTrial";
        T.RuntimeConsumer(fullMask) = "CoupledTruthRuntime.applyPRACHTrial";
        T.RuntimeEvidenceSource(fullMask) = "sixgr.phy.ra.runFourStepRA";
        T.ValueDefinition(fullMask) = "canonical PRACH row backed by Msg1 PRACH, Msg2 RAR, Msg3 PUSCH, and Msg4 contention-resolution waveform evidence";
    end

    function writeRAEvidenceTables(layout, tables)
        if ~isstruct(tables)
            return;
        end
        names = ["ra_attempts","ra_state_transitions","msg1_prach_detection", ...
            "msg2_rar_trials","msg2_pdcch_candidates","msg3_pusch_trials", ...
            "msg4_contention_resolution","ra_timer_events","ra_negative_trials", ...
            "ra_collision_trials","ra_oracle_guard","ra_runtime_stage_waveforms"];
        for i = 1:numel(names)
            f = char(names(i));
            if isfield(tables, f) && istable(tables.(f)) && ~isempty(tables.(f))
                sixgr.util.csvWriteTable(fullfile(layout.ControlCSVDir, string(f) + ".csv"), tables.(f));
            end
        end
    end

    function values = logicalVectorOrDefault(raw, n, defaultValue)
        n = max(0, round(double(n)));
        if nargin < 3
            defaultValue = false;
        end
        values = repmat(logical(defaultValue), n, 1);
        if isempty(raw)
            return;
        end
        if islogical(raw)
            rawValues = reshape(raw, [], 1);
        elseif isnumeric(raw)
            rawValues = reshape(isfinite(double(raw)) & double(raw) ~= 0, [], 1);
        else
            tokens = lower(strtrim(string(raw)));
            rawValues = reshape(tokens == "true" | tokens == "1" | tokens == "yes" | ...
                tokens == "pass" | tokens == "passed", [], 1);
        end
        if isempty(rawValues)
            return;
        end
        if numel(rawValues) == 1 && n ~= 1
            rawValues = repmat(rawValues(1), n, 1);
        elseif numel(rawValues) ~= n
            rawValues = rawValues(1:min(numel(rawValues), n));
            if numel(rawValues) < n
                rawValues(end+1:n, 1) = logical(defaultValue);
            end
        end
        values = logical(rawValues);
    end

    function value = tableColumnOrDefault(T, name, defaultValue)
        if istable(T) && ismember(string(name), string(T.Properties.VariableNames))
            value = T.(char(name));
        else
            value = defaultValue;
        end
    end

    function T = fillBlankCategoricalColumns(T, scopeToken)
        if ~(istable(T) && ~isempty(T))
            return;
        end
        scopeToken = lower(regexprep(char(string(scopeToken)), "[^a-z0-9]+", "_"));
        names = string(T.Properties.VariableNames);
        for idx = 1:numel(names)
            fieldName = char(names(idx));
            rawCol = T.(fieldName);
            if ~(isstring(rawCol) || ischar(rawCol) || iscell(rawCol) || iscategorical(rawCol) || ...
                    sixgr.truth.CoupledTruthRuntime.isSemanticCategoricalField(fieldName, rawCol))
                continue;
            end
            values = string(rawCol);
            normalized = lower(strtrim(fillmissing(values, "constant", "")));
            blankMask = ismissing(values) | strlength(normalized) == 0 | normalized == "nan" | normalized == "<missing>";
            if ~any(blankMask)
                continue;
            end
            token = sixgr.truth.CoupledTruthRuntime.blankCategoricalToken(fieldName, scopeToken);
            if strlength(token) == 0
                continue;
            end
            values(blankMask) = token;
            T.(fieldName) = values;
        end
    end

    function token = blankCategoricalToken(fieldName, scopeToken)
        scope = string(scopeToken);
        fieldName = lower(char(string(fieldName)));
        if strcmp(fieldName, "usedoraclefields")
            token = "";
        elseif endsWith(fieldName, "source")
            token = "not_emitted_by_active_" + scope + "_runtime";
        elseif endsWith(fieldName, "valuerole")
            token = "not_available";
        elseif endsWith(fieldName, "valuestatus")
            token = "not_emitted_by_active_" + scope + "_runtime";
        elseif endsWith(fieldName, "nareason") || strcmp(fieldName, "nareason") || strcmp(fieldName, "unavailablereason")
            token = "field_not_emitted_by_active_" + scope + "_runtime";
        elseif contains(fieldName, "blocker")
            token = "not_blocked_in_active_" + scope + "_runtime";
        elseif contains(fieldName, "definition")
            token = "not_emitted_by_active_" + scope + "_runtime";
        elseif contains(fieldName, "authority")
            token = "not_recorded_by_active_" + scope + "_runtime";
        else
            token = "not_applicable_for_active_" + scope + "_runtime";
        end
    end

    function tf = isSemanticCategoricalField(fieldName, rawCol)
        name = lower(char(string(fieldName)));
        if isstring(rawCol) || ischar(rawCol) || iscell(rawCol) || iscategorical(rawCol)
            tf = true;
            return;
        end
        if ~(isnumeric(rawCol) || islogical(rawCol))
            tf = false;
            return;
        end
        numericNameHints = ["_db","db","_hz","hz","_deg","deg","_ms","ms","_s","_bits","bits","_bytes","bytes","count","index","slot","frame","time","cellid","ueid","ueindex","rnti","rank","layers","ports","prb","rb","resourceid","setid","iterations","power","gain","ratio","correlation","probability","rate","latency","throughput","error"];
        if any(contains(name, numericNameHints))
            tf = false;
            return;
        end
        semanticHints = ["source","valuerole","valuestatus","nareason","unavailablereason","definition","availability","modulation","mode","policy","strategy","table","type","hex","consumer","classification","materialization","gating","blocker","authority","beam","precoder","interferer","tracking","outcome"];
        semanticExact = ["cqitable","mcstable","pmitype","pmicodebookmode","csireportmode","csipayloadhex","iqimbalancemodel","iqimbalancemeasurementsource","iqimbalancemeasurementstatus","measuredtrialsinrsource","largescalesinrsource","servingrsrpsource","csi_rsrpsource","appliedlargescalegainsource","interferencemode","requestedvsappliedprecoderpmimatchstatus"];
        tf = any(strcmp(name, semanticExact)) || any(contains(name, semanticHints));
    end

    function T = setStringColumn(T, name, value, overwrite)
        n = height(T);
        if isscalar(value)
            value = repmat(string(value), n, 1);
        else
            value = reshape(string(value), [], 1);
            if numel(value) ~= n
                value = repmat(value(1), n, 1);
            end
        end
        if ~ismember(string(name), string(T.Properties.VariableNames)) || logical(overwrite)
            T.(char(name)) = value;
            return;
        end
        current = string(T.(char(name)));
        if numel(current) ~= n
            current = reshape(current, [], 1);
        end
        normalized = lower(strtrim(current));
        blank = strlength(strtrim(current)) == 0 | normalized == "missing" | normalized == "<missing>" | normalized == "nan";
        current(blank) = value(blank);
        T.(char(name)) = current;
    end

    function T = setStringValueAt(T, name, idx, value)
        n = height(T);
        idx = round(double(idx));
        if ~(idx >= 1 && idx <= n)
            return;
        end
        field = char(name);
        if ismember(string(name), string(T.Properties.VariableNames))
            current = reshape(string(T.(field)), [], 1);
            if numel(current) ~= n
                current = repmat("", n, 1);
            end
        else
            current = strings(n, 1);
        end
        current(idx) = string(value);
        T.(field) = current;
    end

    function T = setLogicalColumn(T, name, value)
        n = height(T);
        if isscalar(value)
            value = repmat(logical(value), n, 1);
        else
            value = reshape(logical(value), [], 1);
            if numel(value) ~= n
                value = repmat(value(1), n, 1);
            end
        end
        T.(char(name)) = value;
    end

    function T = setNumericColumn(T, name, value, overwrite)
        n = height(T);
        if isscalar(value)
            value = repmat(double(value), n, 1);
        else
            value = reshape(double(value), [], 1);
            if numel(value) ~= n
                value = repmat(value(1), n, 1);
            end
        end
        if ~ismember(string(name), string(T.Properties.VariableNames)) || logical(overwrite)
            T.(char(name)) = value;
            return;
        end
        current = double(T.(char(name)));
        current = reshape(current, [], 1);
        blank = ~isfinite(current);
        current(blank) = value(blank);
        T.(char(name)) = current;
    end

    function writeMirroredTable(layout, fileName, T)
        if ~sixgr.util.persistenceEnabled()
            return;
        end
        controlPath = fullfile(layout.ControlCSVDir, fileName);
        airPath = fullfile(layout.AirInterfaceCSVDir, fileName);
        if istable(T) && ~isempty(T)
            sixgr.util.csvWriteTable(controlPath, T);
            sixgr.util.csvWriteTable(airPath, T);
            return;
        end
        if exist(controlPath, "file") ~= 2
            sixgr.util.csvWriteTable(controlPath, T);
        end
        if exist(airPath, "file") ~= 2
            sixgr.util.csvWriteTable(airPath, T);
        end
    end

    function row = emptyUserPerformanceRow()
        row = struct( ...
            "UEIndex", NaN, "RNTI", NaN, ...
            "DL_FrameCount", NaN, "UL_FrameCount", NaN, ...
            "DL_CoverageStatus", "", "UL_CoverageStatus", "", ...
            "DL_Throughput_Mbps", NaN, "UL_Throughput_Mbps", NaN, ...
            "DL_BLER", NaN, "UL_BLER", NaN, ...
            "DL_MeanMeasuredSINR_dB", NaN, "UL_MeanMeasuredSINR_dB", NaN, ...
            "UserThroughput_Mbps", NaN, ...
            "DL_HARQFailureRate", NaN, "UL_HARQFailureRate", NaN, ...
            "DL_HARQObservationCount", NaN, "UL_HARQObservationCount", NaN, ...
            "HARQFailureRate", NaN, "HARQObservationCount", NaN);
    end

    function [failureRate, observationCount] = userHARQFailureMetrics(harqTimelineT, ueIdx, direction)
        failureRate = NaN;
        observationCount = NaN;
        if ~(istable(harqTimelineT) && ~isempty(harqTimelineT) && ...
                all(ismember(["UEIndex","CombinedDecodeOK"], string(harqTimelineT.Properties.VariableNames))))
            return;
        end
        mask = abs(double(harqTimelineT.UEIndex) - double(ueIdx)) < 1e-9;
        if ismember("Direction", string(harqTimelineT.Properties.VariableNames)) && strlength(strtrim(string(direction))) > 0
            mask = mask & upper(strtrim(string(harqTimelineT.Direction))) == upper(strtrim(string(direction)));
        end
        if ~any(mask)
            return;
        end
        vals = double(harqTimelineT.CombinedDecodeOK(mask));
        vals = vals(isfinite(vals));
        if isempty(vals)
            return;
        end
        observationCount = double(numel(vals));
        failureRate = mean(1 - vals, "omitnan");
    end

    function [failureRate, observationCount] = combineDirectionalHARQFailureMetrics(dlRate, dlCount, ulRate, ulCount)
        failureRate = NaN;
        observationCount = NaN;
        counts = [double(dlCount) double(ulCount)];
        rates = [double(dlRate) double(ulRate)];
        valid = isfinite(counts) & counts > 0 & isfinite(rates);
        if ~any(valid)
            return;
        end
        observationCount = sum(counts(valid), "omitnan");
        failureRate = sum(rates(valid) .* counts(valid), "omitnan") / max(observationCount, 1);
    end

    function [dueUEs, dueRNTIs, dueSourceSlots, dueGrantIds, dueEvidenceSources] = collectPUCCHDueIdentityImpl(state, dueSlot)
        dueUEs = [];
        dueRNTIs = [];
        dueSourceSlots = [];
        dueGrantIds = strings(0, 1);
        dueEvidenceSources = strings(0, 1);
        dueSlot = round(double(dueSlot));
        if ~(isfinite(dueSlot) && dueSlot >= 1)
            return;
        end

        pendingFeedback = sixgr.util.structGet(state, "PendingFeedbackTable", table());
        if istable(pendingFeedback) && ~isempty(pendingFeedback)
            for ri = 1:height(pendingFeedback)
                row = pendingFeedback(ri, :);
                rowDueSlot = double(sixgr.truth.CoupledTruthRuntime.rowValue(row, "DueSlot", ...
                    sixgr.truth.CoupledTruthRuntime.rowValue(row, "ScheduledAbsoluteSlot", NaN)));
                if ~(isfinite(rowDueSlot) && abs(rowDueSlot - dueSlot) < 1e-9)
                    continue;
                end
                if logical(sixgr.truth.CoupledTruthRuntime.rowLogical(row, "Processed", false))
                    continue;
                end
                uciType = lower(strtrim(string(sixgr.truth.CoupledTruthRuntime.rowValue(row, "UCIType", "harq_ack"))));
                if strlength(uciType) > 0 && ~contains(uciType, "harq")
                    continue;
                end
                dueUEs(end + 1, 1) = double(sixgr.truth.CoupledTruthRuntime.rowValue(row, "UEIndex", NaN)); %#ok<AGROW>
                dueRNTIs(end + 1, 1) = double(sixgr.truth.CoupledTruthRuntime.rowValue(row, "RNTI", NaN)); %#ok<AGROW>
                dueSourceSlots(end + 1, 1) = double(sixgr.truth.CoupledTruthRuntime.rowValue(row, "SourceSlot", NaN)); %#ok<AGROW>
                dueGrantIds(end + 1, 1) = string(sixgr.truth.CoupledTruthRuntime.rowValue(row, "PUCCHGrantId", "")); %#ok<AGROW>
                dueEvidenceSources(end + 1, 1) = "pending_feedback_table"; %#ok<AGROW>
            end
        end

        pucchGrants = sixgr.util.structGet(state, "PUCCHGrantTraceTable", table());
        if istable(pucchGrants) && ~isempty(pucchGrants)
            for ri = 1:height(pucchGrants)
                row = pucchGrants(ri, :);
                rowDueSlot = double(sixgr.truth.CoupledTruthRuntime.rowValue(row, "ScheduledAbsoluteSlot", ...
                    sixgr.truth.CoupledTruthRuntime.rowValue(row, "Slot", NaN)));
                if ~(isfinite(rowDueSlot) && abs(rowDueSlot - dueSlot) < 1e-9)
                    continue;
                end
                if logical(sixgr.truth.CoupledTruthRuntime.rowLogical(row, "GrantExecutedFlag", false))
                    continue;
                end
                uciType = lower(strtrim(string(sixgr.truth.CoupledTruthRuntime.rowValue(row, "UCIType", "harq_ack"))));
                if strlength(uciType) > 0 && ~contains(uciType, "harq")
                    continue;
                end
                dueUEs(end + 1, 1) = double(sixgr.truth.CoupledTruthRuntime.rowValue(row, "UEIndex", NaN)); %#ok<AGROW>
                dueRNTIs(end + 1, 1) = double(sixgr.truth.CoupledTruthRuntime.rowValue(row, "RNTI", NaN)); %#ok<AGROW>
                dueSourceSlots(end + 1, 1) = double(sixgr.truth.CoupledTruthRuntime.rowValue(row, "SourceSlot", NaN)); %#ok<AGROW>
                dueGrantIds(end + 1, 1) = string(sixgr.truth.CoupledTruthRuntime.rowValue(row, "PUCCHGrantId", "")); %#ok<AGROW>
                dueEvidenceSources(end + 1, 1) = "pucch_grant_trace"; %#ok<AGROW>
            end
        end
    end

    function bits = resolveGrantExpectedUCIBits(grant)
        bits = int8([]);
        if ~(isstruct(grant) && ~isempty(fieldnames(grant)))
            return;
        end
        paths = ["ExpectedUCIBits","MultiplexedUCIBits","HARQACKBits","MultiplexedHARQACKBits"];
        for i = 1:numel(paths)
            raw = sixgr.util.structGet(grant, char(paths(i)), []);
            if isempty(raw)
                continue;
            end
            bits = int8(logical(raw(:)));
            return;
        end
    end

    function due = collectPUCCHDueHARQACKImpl(state, dueSlot)
        proto = struct("UEIndex", NaN, "RNTI", NaN, "SourceSlot", NaN, ...
            "PUCCHGrantId", "", "AckBit", int8(0), "EvidenceSource", "");
        due = repmat(proto, 0, 1);
        dueSlot = round(double(dueSlot));
        if ~(isfinite(dueSlot) && dueSlot >= 1)
            return;
        end
        pendingFeedback = sixgr.util.structGet(state, "PendingFeedbackTable", table());
        if istable(pendingFeedback) && ~isempty(pendingFeedback)
            for ri = 1:height(pendingFeedback)
                row = pendingFeedback(ri, :);
                rowDueSlot = double(sixgr.truth.CoupledTruthRuntime.rowValue(row, "DueSlot", ...
                    sixgr.truth.CoupledTruthRuntime.rowValue(row, "ScheduledAbsoluteSlot", NaN)));
                if ~(isfinite(rowDueSlot) && abs(rowDueSlot - dueSlot) < 1e-9)
                    continue;
                end
                if logical(sixgr.truth.CoupledTruthRuntime.rowLogical(row, "Processed", false))
                    continue;
                end
                due(end + 1, 1) = sixgr.truth.CoupledTruthRuntime.buildDueHARQACKStruct(row, "pending_feedback_table"); %#ok<AGROW>
            end
        end
        pucchGrants = sixgr.util.structGet(state, "PUCCHGrantTraceTable", table());
        if istable(pucchGrants) && ~isempty(pucchGrants)
            for ri = 1:height(pucchGrants)
                row = pucchGrants(ri, :);
                rowDueSlot = double(sixgr.truth.CoupledTruthRuntime.rowValue(row, "ScheduledAbsoluteSlot", ...
                    sixgr.truth.CoupledTruthRuntime.rowValue(row, "Slot", NaN)));
                if ~(isfinite(rowDueSlot) && abs(rowDueSlot - dueSlot) < 1e-9)
                    continue;
                end
                if logical(sixgr.truth.CoupledTruthRuntime.rowLogical(row, "GrantExecutedFlag", false))
                    continue;
                end
                due(end + 1, 1) = sixgr.truth.CoupledTruthRuntime.buildDueHARQACKStruct(row, "pucch_grant_trace"); %#ok<AGROW>
            end
        end
    end

    function due = buildDueHARQACKStruct(row, source)
        due = struct("UEIndex", double(sixgr.truth.CoupledTruthRuntime.rowValue(row, "UEIndex", NaN)), ...
            "RNTI", double(sixgr.truth.CoupledTruthRuntime.rowValue(row, "RNTI", NaN)), ...
            "SourceSlot", double(sixgr.truth.CoupledTruthRuntime.rowValue(row, "SourceSlot", NaN)), ...
            "PUCCHGrantId", char(string(sixgr.truth.CoupledTruthRuntime.rowValue(row, "PUCCHGrantId", ""))), ...
            "AckBit", int8(logical(sixgr.truth.CoupledTruthRuntime.rowValue(row, "Ack", ...
                sixgr.truth.CoupledTruthRuntime.rowValue(row, "ExpectedAck", false)))), ...
            "EvidenceSource", char(string(source)));
    end

    function [grantsOut, blockedT] = excludeULGrantsCollidingWithPUCCHImpl(state, grantsIn, dueSlot)
        grantsOut = grantsIn;
        blockedPrototype = sixgr.truth.CoupledTruthRuntime.emptyPUSCHPUCCHCollisionRow();
        blockedT = struct2table(repmat(blockedPrototype, 0, 1));
        if ~(isstruct(grantsIn) && ~isempty(grantsIn))
            return;
        end
        [dueUEs, dueRNTIs, dueSourceSlots, dueGrantIds, dueEvidenceSources] = ...
            sixgr.truth.CoupledTruthRuntime.collectPUCCHDueIdentityImpl(state, dueSlot);
        if isempty(dueUEs) && isempty(dueRNTIs)
            return;
        end
        dueSlot = round(double(dueSlot));

        keep = true(1, numel(grantsIn));
        blockedRows = repmat(blockedPrototype, max(1, numel(grantsIn)), 1);
        blockedCount = 0;
        for gi = 1:numel(grantsIn)
            grant = grantsIn(gi);
            ueIdx = double(sixgr.util.structGet(grant, "UEIndex", NaN));
            rnti = double(sixgr.util.structGet(grant, "RNTI", NaN));
            if ~(isfinite(ueIdx) && ueIdx >= 1) && isfinite(rnti)
                ueIdx = sixgr.truth.CoupledTruthRuntime.resolveUEIndexFromRNTI(state, rnti);
            end
            match = false(size(dueUEs));
            if isfinite(ueIdx)
                match = match | (isfinite(dueUEs) & abs(dueUEs - ueIdx) < 1e-9);
            end
            if isfinite(rnti)
                match = match | (isfinite(dueRNTIs) & abs(dueRNTIs - rnti) < 1e-9);
            end
            matchIdx = find(match, 1, "first");
            if isempty(matchIdx)
                continue;
            end
            if ~isempty(sixgr.truth.CoupledTruthRuntime.resolveGrantExpectedUCIBits(grant))
                grantsIn(gi).PUCCHCollisionPolicy = "harq_ack_multiplexed_on_pusch";
                grantsIn(gi).PUCCHSourceSlot = double(dueSourceSlots(matchIdx));
                grantsIn(gi).PUCCHGrantId = char(dueGrantIds(matchIdx));
                continue;
            end
            keep(gi) = false;
            blockedCount = blockedCount + 1;
            blockedRows(blockedCount).Direction = "UL";
            blockedRows(blockedCount).DueSlot = double(dueSlot);
            blockedRows(blockedCount).UEIndex = double(ueIdx);
            blockedRows(blockedCount).RNTI = double(rnti);
            blockedRows(blockedCount).PUSCHGrantSlot = double(sixgr.util.structGet(grant, "ScheduledAbsoluteSlot", ...
                sixgr.util.structGet(grant, "Slot", NaN)));
            blockedRows(blockedCount).PUCCHSourceSlot = double(dueSourceSlots(matchIdx));
            blockedRows(blockedCount).PUCCHGrantId = char(dueGrantIds(matchIdx));
            blockedRows(blockedCount).CollisionEvidenceSource = char(dueEvidenceSources(matchIdx));
            blockedRows(blockedCount).Reason = "harq_ack_pucch_due_same_slot_same_ue";
            blockedRows(blockedCount).Policy = "avoid_standalone_pusch_without_uci_on_pusch_multiplexing";
        end

        grantsOut = grantsIn(keep);
        if blockedCount > 0
            blockedT = struct2table(blockedRows(1:blockedCount), "AsArray", true);
        end
    end

    function row = emptyPUSCHPUCCHCollisionRow()
        row = struct( ...
            "Direction", "", "DueSlot", NaN, "UEIndex", NaN, "RNTI", NaN, ...
            "PUSCHGrantSlot", NaN, "PUCCHSourceSlot", NaN, "PUCCHGrantId", "", ...
            "CollisionEvidenceSource", "", "Reason", "", "Policy", "");
    end

    function row = emptyPacketDeliveryLedgerRow()
        row = struct( ...
            "Direction", "", "UEIndex", NaN, "RNTI", NaN, ...
            "PacketId", "", "ApplicationPacketId", "", "FlowId", "", "QFI", NaN, ...
            "EnqueueFrame", NaN, "EnqueueSlot", NaN, "EnqueueTime_s", NaN, ...
            "OfferedBits", NaN, "ScheduledBits", 0, "DeliveredBits", 0, "RemainingBits", 0, ...
            "SegmentCount", 0, "HARQAttemptCount", 0, ...
            "FirstGrantSlot", NaN, "FirstGrantTime_s", NaN, ...
            "ReassemblyCompleteFlag", false, "DeliverySuccess", false, ...
            "DeliverySlot", NaN, "DeliveryTime_s", NaN, "Latency_ms", NaN, ...
            "PacketizationSource", "", "DeliverySource", "", ...
            "Status", "", "Notes", "");
    end

    function row = emptyPacketSDULedgerRow()
        row = struct( ...
            "Direction", "", "UEIndex", NaN, "RNTI", NaN, ...
            "PacketId", "", "ApplicationPacketId", "", "MACSDUId", "", ...
            "TransportBlockId", "", "GrantContextId", "", ...
            "HARQProcessId", NaN, "NDI", NaN, "RV", NaN, ...
            "SegmentIndex", NaN, "PayloadBits", NaN, ...
            "ScheduleSlot", NaN, "ScheduleTime_s", NaN, ...
            "FirstSuccessSlot", NaN, "DeliveryTime_s", NaN, "DeliveryLatency_ms", NaN, ...
            "HARQAttemptCount", 0, "LastAttemptSlot", NaN, "LastRV", NaN, ...
            "TBCrcPass", false, "DeliverySuccess", false, "FirstSuccessDelivery", false, ...
            "ReassemblyCompleteFlag", false, "ApplicationDeliveryFlag", false, ...
            "Status", "", "Notes", "");
    end

    function row = emptyHARQTimelineRow()
        row = struct( ...
            "Direction", "", "UEIndex", NaN, "RNTI", NaN, ...
            "Slot", NaN, "Frame", NaN, ...
            "HarqID", NaN, "NDI", NaN, "RV", NaN, ...
            "IsRetransmission", false, "FeedbackDueSlot", NaN, ...
            "CurrentDecodeOK", false, "CombinedDecodeOK", false, ...
            "PreviousLLRCount", NaN, "CurrentLLRCount", NaN, "CombinedLLRCount", NaN, ...
            "HARQCombiningApplied", false, "LLRCombiningGain_dB", NaN, ...
            "MeasuredSINR_dB", NaN, "WidebandCQI", NaN, "CQIDerivedMCS", NaN, ...
            "CQIDerivedModulation", "", "Goodput_Mbps", NaN, "Status", "", "Notes", "");
    end

    function row = emptyHARQSummaryRow()
        row = struct( ...
            "Direction", "", "FramesObserved", NaN, "RetxObserved", NaN, ...
            "AckRate", NaN, "NackRate", NaN, ...
            "MeanMeasuredSINR_dB", NaN, "MeanWidebandCQI", NaN, ...
            "MeanCQIDerivedMCS", NaN, "Notes", "");
    end

    function row = emptyFeedbackRow()
        row = struct( ...
            "Direction", "", "UEIndex", NaN, "RNTI", NaN, ...
            "HarqID", NaN, "SourceSlot", NaN, "DueSlot", NaN, "Ack", false, ...
            "CurrentDecodeOK", false, "CombinedDecodeOK", false, ...
            "ServingCell", NaN, "BaseStationID", NaN, "TBSBits", NaN, "UCIBitCount", NaN, ...
            "RequestedFormat", NaN, "ResolvedFormat", NaN, "PUCCHResourceId", "", ...
            "PUCCHPRBStart", NaN, "PUCCHPRBCount", NaN, ...
            "PUCCHSymbolStart", NaN, "PUCCHNumSymbols", NaN, ...
            "UCIType", "", "ControlResourceSource", "", "ControlResourceValidity", false, ...
            "FormatAdaptationReason", "", "PUCCHGrantId", "", ...
            "Processed", false);
    end

    function row = emptyReferenceSignalMeasurementRow()
        row = struct( ...
            "SignalType", "", "TargetType", "", "TargetId", NaN, ...
            "ProducerSlot", NaN, "AvailableSlot", NaN, "Valid", false, ...
            "Direction", "", "SourceSignal", "", "MeasurementId", "", ...
            "MeasurementSource", "", "EvidenceSource", "", ...
            "CQI", NaN, "RI", NaN, "PMI", NaN, "CRI", NaN, ...
            "SINR_dB", NaN, "NMSE_dB", NaN, ...
            "TimingOffset_samples", NaN, "CFO_Hz", NaN);
    end

    function row = emptyPUCCHGrantRow()
        row = struct( ...
            "Direction", "UL", "FeedbackForDirection", "", ...
            "Frame", NaN, "Slot", NaN, "ScheduledAbsoluteSlot", NaN, "SourceSlot", NaN, ...
            "UEIndex", NaN, "UEID", NaN, "RNTI", NaN, "ServingCell", NaN, "BaseStationID", NaN, ...
            "HarqID", NaN, "TBSBits", NaN, "ExpectedAck", false, "ObservedAck", false, ...
            "DecodedAck", false, "FalseAck", false, "FalseNack", false, "MissedFeedback", false, ...
            "ExpectedHARQCurrentDecodeOK", false, "ExpectedHARQCombinedDecodeOK", false, ...
            "CurrentDecodeOK", false, "CombinedDecodeOK", false, ...
            "UCIBitCount", NaN, "UCIType", "", ...
            "PUCCHGrantId", "", "PUCCHGrantSource", "runtime_harq_feedback_due_scheduler", ...
            "PUCCHGrantState", "scheduled_pending_execution", ...
            "GrantScheduledFlag", false, "GrantExecutedFlag", false, ...
            "RequestedFormat", NaN, "ResolvedFormat", NaN, "FormatAdaptationReason", "", ...
            "PUCCHResourceId", "", "PUCCHPRBStart", NaN, "PUCCHPRBCount", NaN, ...
            "PUCCHSymbolStart", NaN, "PUCCHNumSymbols", NaN, ...
            "ControlResourceSource", "", "ControlResourceValidity", false, ...
            "ConfiguredSNR_dB", NaN, "AppliedAWGNSNR_dB", NaN, ...
            "ChannelModel", "", "DopplerHz", NaN, ...
            "TimingEstimateUsed", false, "UseIdealTimingSync", false, ...
            "InterferenceMode", "", "InterferenceContributorCount", 0, ...
            "InterferenceAggregatedRxPower_dBm", NaN, "InterferencePowerSource", "", ...
            "FullInterfererChannelTruthUsed", false, ...
            "BitsCompared", NaN, "BitErrors", NaN, "DetectionMetric", NaN, ...
            "DetectionThreshold", NaN, "DetectionMetricStatus", "", ...
            "DetectorPeakMetric", NaN, "DetectorNoiseFloor", NaN, ...
            "DTXFlag", false, "DTXReason", "", ...
            "PUCCHDecodeOk", false, "UCIContentMatch", false, ...
            "RuntimeStateUpdated", false, "RuntimeStateConsumer", "", ...
            "ControlStateChanged", false, "StateChangeApplied", false, ...
            "ControlStateChangeDefinition", "harq_feedback_consumed_by_runtime_harq_and_scheduler", ...
            "Status", "PENDING", "Crash", false, "CrashSource", "", "CrashMessage", "", ...
            "Notes", "");
    end

    function row = emptyCSIReportRow()
        row = struct( ...
            "Direction", "", "UEIndex", NaN, "RNTI", NaN, ...
            "SourceSlot", NaN, "DueSlot", NaN, ...
            "CQI", NaN, "RI", NaN, "PMI", NaN, "CRI", NaN, ...
            "SINR_dB", NaN, "SINRSource", "", "SINRValueRole", "", "SINRValueStatus", "", ...
            "MCSIndex", NaN, "TargetCodeRate", NaN, ...
            "Modulation", "", "RawCQIDerivedMCS", NaN, ...
            "RawCQIDerivedTargetCodeRate", NaN, "RawCQIDerivedModulation", "", ...
            "LinkAdaptationMCSIndex", NaN, "LinkAdaptationDecisionReason", "", ...
            "MCSSelectionSource", "", "MCSValueStatus", "", ...
            "CQIBasedMCS", NaN, "SmoothedCQI", NaN, ...
            "InstantaneousCQIMCS", NaN, "DeltaMCS", NaN, ...
            "EffectiveCQISmoothingAlpha", NaN, "CSITemporalCorrelationWeight", NaN, ...
            "CSIAgeSeconds", NaN, "CSICoherenceTimeSeconds", NaN, ...
            "CSIAgingModel", "", ...
            "SubbandSINRVector_dB", "", "AgedSubbandSINRVector_dB", "", ...
            "PostEqSINRPerLayer_dB", "", "AgedPostEqSINRPerLayer_dB", "", ...
            "SubbandAgingPenaltyVector_dB", "", "LayerAgingPenaltyVector_dB", "", ...
            "SubbandCSIAgeSlots", "", "LayerCSIAgeSlots", "", ...
            "SubbandDopplerHz", "", "LayerDopplerHz", "", ...
            "OuterLoopEnabled", false, "InnerLoopEnabled", false, ...
            "LinkAdaptationStateUpdateCount", NaN, ...
            "CRCPass", NaN, "ServingCell", NaN, "Processed", false);
    end

    function row = emptyLatestFeedbackRow()
        row = struct( ...
            "Valid", false, "Direction", "", "Slot", NaN, ...
            "CQI", NaN, "RI", NaN, "PMI", NaN, "CRI", NaN, ...
            "SINR_dB", NaN, "SINRSource", "", "SINRValueRole", "", "SINRValueStatus", "", ...
            "MCSIndex", NaN, "TargetCodeRate", NaN, ...
            "Modulation", "", "RawCQIDerivedMCS", NaN, ...
            "RawCQIDerivedTargetCodeRate", NaN, "RawCQIDerivedModulation", "", ...
            "LinkAdaptationMCSIndex", NaN, "LinkAdaptationDecisionReason", "", ...
            "MCSSelectionSource", "", "MCSValueStatus", "", ...
            "CQIBasedMCS", NaN, "SmoothedCQI", NaN, ...
            "InstantaneousCQIMCS", NaN, "DeltaMCS", NaN, ...
            "EffectiveCQISmoothingAlpha", NaN, "CSITemporalCorrelationWeight", NaN, ...
            "CSIAgeSeconds", NaN, "CSICoherenceTimeSeconds", NaN, ...
            "CSIAgingModel", "", ...
            "SubbandSINRVector_dB", "", "AgedSubbandSINRVector_dB", "", ...
            "PostEqSINRPerLayer_dB", "", "AgedPostEqSINRPerLayer_dB", "", ...
            "SubbandAgingPenaltyVector_dB", "", "LayerAgingPenaltyVector_dB", "", ...
            "SubbandCSIAgeSlots", "", "LayerCSIAgeSlots", "", ...
            "SubbandDopplerHz", "", "LayerDopplerHz", "", ...
            "OuterLoopEnabled", false, "InnerLoopEnabled", false, ...
            "LinkAdaptationStateUpdateCount", NaN, ...
            "ServingCell", NaN, ...
            "BootstrapCQISource", "", "PreviewSINR_dB", NaN, ...
            "PreviewCQI", NaN, "PreviewMCSIndex", NaN, ...
            "PreviewModulation", "", "PreviewTargetCodeRate", NaN, ...
            "PreviewCQISource", "", "BootstrapCQIUsableForScheduling", false, ...
            "SchedulerCQIRawCQI", NaN, "SchedulerAdjustedSINR_dB", NaN, ...
            "SchedulerSINRBackoff_dB", NaN, "SchedulerCQISource", "", ...
            "FeedbackSourceSignal", "", "FeedbackCRCPass", NaN);
    end

    function row = emptyReceiverTrackingStateRow()
        row = struct( ...
            "ServingCell", NaN, "SourceSignal", "", ...
            "ReceiverConsumerType", "", "IntegrationStatus", "not_initialized", "IntegrationBlocker", "no_trs_runtime_observation", ...
            "TRSProcessed", false, "TrackingState", "not_initialized", ...
            "TRSTrackingStateBefore", "", "TRSTrackingStateAfter", "", ...
            "TRSUpdateOutcome", "", "LastUpdateFrame", NaN, "LastUpdateSlot", NaN, ...
            "TRSTrackingUpdateTime_s", NaN, "MeasurementSFNSlot", "", ...
            "ChannelTrackingFreshnessState", "uninitialized", "FrequencyTrackingState", "not_updated", ...
            "TimingTrackingState", "not_updated_timing_estimate_unavailable", ...
            "TimingEstimateAvailable", false, "TimingEstimate_samples", NaN, ...
            "CFOEstimateAvailable", false, "EstimatedCFO_Hz", NaN, ...
            "EstimatedOscillatorCFO_Hz", NaN, "EstimatedCommonFrequency_Hz", NaN, ...
            "PhysicalDoppler_Hz", NaN, ...
            "EstimatedDopplerHz", NaN, "NMSE_dB", NaN, "PhaseError_deg", NaN, ...
            "QCLAccuracy", NaN, "DetectionMetric", NaN, ...
            "RuntimeEvidenceSource", "", "SourceArtifact", "");
    end

    function row = emptyReceiverTrackingTraceRow()
        row = struct( ...
            "ServingCell", NaN, "SourceSignal", "", "TRSProcessed", false, ...
            "TRSReceiverConsumerType", "", "TRSReceiverIntegrationStatus", "", "TRSReceiverIntegrationBlocker", "", ...
            "TRSTrackingStateBefore", "", "TRSTrackingStateAfter", "", ...
            "TRSTrackingUpdateTime_s", NaN, "TRSAssociatedCell", NaN, ...
            "TRSUpdateOutcome", "", "TRSChannelTrackingFreshnessState", "", ...
            "TRSFrequencyTrackingState", "", "TRSTimingTrackingState", "", ...
            "TRSTimingEstimateAvailable", false, "TRSTimingEstimate_samples", NaN, ...
            "TRSCFOEstimateAvailable", false, "TRSEstimatedCFO_Hz", NaN, ...
            "TRSEstimatedOscillatorCFO_Hz", NaN, "TRSEstimatedCommonFrequency_Hz", NaN, ...
            "TRSPhysicalDoppler_Hz", NaN, ...
            "TRSRuntimeEvidenceSource", "", "Frame", NaN, "Slot", NaN, ...
            "MeasurementSFNSlot", "", "EstimatedDopplerHz", NaN, ...
            "NMSE_dB", NaN, "PhaseError_deg", NaN, ...
            "QCLAccuracy", NaN, "DetectionMetric", NaN, ...
            "SourceArtifact", "");
    end

    function row = emptyInitialAccessLifecycleRow()
        row = struct( ...
            "Step", NaN, "UEIndex", NaN, "RNTI", NaN, "ServingCell", NaN, ...
            "Frame", NaN, "Slot", NaN, "Time_s", NaN, ...
            "Direction", "", "StageName", "", "EventName", "", "LifecycleState", "", "StageStatus", "", ...
            "SourceArtifact", "", "SourceRow", NaN, ...
            "ValueSource", "", "ValueRole", "", "ValueStatus", "", "ValueDefinition", "", ...
            "SlotDuration_s", NaN, "ProcedureStartSlot", NaN, "ProcedureEndSlot", NaN, ...
            "ProcedureDelay_ms", NaN, "AccessDelay_ms", NaN, ...
            "CompleteFlag", false, "PlaceholderFlag", false, "FallbackFlag", false, ...
            "UnavailableReason", "", "Notes", "");
    end

    function row = emptyGrantRow()
        row = struct( ...
            "Direction", "", "SFN", NaN, "Slot", NaN, "Frame", NaN, ...
            "UEIndex", NaN, "UEID", NaN, "RNTI", NaN, "ServingCell", NaN, "BaseStationID", NaN, ...
            "GrantReason", "", "IsRetransmission", false, ...
            "HarqID", NaN, "NDI", NaN, "RV", NaN, ...
            "PRBStart", NaN, "PRBCount", NaN, "AllocatedPRBCount", NaN, ...
            "SymbolStart", NaN, "NumSymbols", NaN, ...
            "TBSBits", NaN, "TBSBytes", NaN, ...
            "MCSIndex", NaN, "MCSTable", "", "CQITable", "", "Modulation", "", "TargetCodeRate", NaN, ...
            "RawCQIDerivedMCS", NaN, "LinkAdaptationMCSIndex", NaN, "LinkAdaptationDecisionReason", "", ...
            "CQIBasedMCS", NaN, "SmoothedCQI", NaN, "InstantaneousCQIMCS", NaN, "DeltaMCS", NaN, "StaticDeltaMCS", NaN, ...
            "AMCMode", "", "OuterLoopEnabled", false, "OuterLoopApplied", false, ...
            "OLLADeltaMCS", NaN, "OLLAUpdateCount", NaN, "OLLAState", "", ...
            "MCSSelectionSource", "", "CQIProvenance", "", "MCSValueStatus", "", ...
            "MCSIndexAuthority", "", "GrantOperatingPointSource", "", ...
            "NumLayers", NaN, "Layers", NaN, "CQIUsed", NaN, "RIUsed", NaN, "Rank", NaN, ...
            "PMI", NaN, "CRI", NaN, ...
            "MUMIMOEnabled", false, "MUMIMOGroupSize", NaN, "MUMIMOGroupId", NaN, ...
            "MUMIMOPairingStatus", "", "MUMIMOPairingMetricSource", "", "MUMIMOPrecoderType", "", ...
            "ConfiguredBeamSelectionStrategy", "", "PrecoderSource", "", "PrecodingMode", "", "PrecodingApplicationStage", "", ...
            "PrecodingActive", false, "ExplicitBeamWeightsApplied", false, "TransformPrecodingApplied", false, "BeamformingApplied", false, ...
            "AppliedBeamIndexSet", "", "AppliedPrecoderPMI", NaN, "AppliedPrecoderPMIType", "", "AppliedPrecoderCodebookMode", "", ...
            "PrecodingNumPorts", NaN, "PrecodingNumLayers", NaN, "PrecodingMatrixRows", NaN, "PrecodingMatrixCols", NaN, ...
            "GrantContextId", "", "GrantWorkerSafe", false, "GrantSharedStateCommitMode", "", ...
            "QueueBytesBefore", NaN, "QueueBytesAfter", NaN, ...
            "PBCHGatingActive", false, "PRACHGatingActive", false, "PDCCHGatingActive", false, "SRSGatingActive", false, ...
            "ControlEligible", false, "SchedulingEligible", false, "SchedulingBlockedBySRS", false, ...
            "ControlDecodeOk", false, "PDCCHCausalGrantDecodeOk", false, ...
            "PDCCHControlFailureReason", "", "PDCCHControlEvidenceSource", "", ...
            "ControlDecodeSource", "", "GrantControlState", "", ...
            "CellAcquisitionState", "", "AccessState", "", "SRSValidityState", "", "CSIValidityState", "", ...
            "SRSValid", false, "LastSuccessfulSRSSlot", NaN, "SRSAgeSlots", NaN, ...
            "TRSGatingActive", false, "TRSValidityState", "", "TrackingEligibility", false, "TRSAgeSlots", NaN, ...
            "LastSuccessfulTRSSlot", NaN, "LastEstimatedTRSDopplerHz", NaN, ...
            "TRSStateSource", "", "TRSRuntimeConsumer", "", "TRSInfluencedDecision", false, ...
            "TRSInfluenceDefinition", "", "TRSReceiverIntegrationStatus", "", "TRSReceiverIntegrationBlocker", "");
    end

    function row = emptyControlSummaryRow()
        row = struct( ...
            "ControlIntegrationMode", "", "CurrentSchedulingDirection", "", ...
            "PBCHGatingActive", false, "PRACHGatingActive", false, "PDCCHGatingActive", false, "SRSGatingActive", false, ...
            "TRSGatingActive", false, ...
            "PBCHFailureCount", 0, "PRACHFailureCount", 0, "ControlDecodeFailureCount", 0, ...
            "PUCCHDecodeFailureCount", 0, "PUCCHCrashCount", 0, ...
            "TRSFailureCount", 0, ...
            "SRSInvalidEventCount", 0, "SchedulingOpportunitiesBlockedByGating", 0, "GrantsBlockedByGating", 0, ...
            "UsersAcquired", 0, "UsersAccessReady", 0, "UsersWithValidSRS", 0, "UsersWithValidTRS", 0, ...
            "UsersControlEligible", 0, "UsersDLSchedulingEligible", 0, "UsersULSchedulingEligible", 0, ...
            "UsersSchedulingEligible", 0, "UsersSchedulingBlockedBySRS", 0, ...
            "DLGrantsScheduledWithInvalidSRS", 0, "ULGrantsScheduledWithInvalidSRS", 0);
    end

    function row = emptyControlStateRow()
        row = struct( ...
            "UEIndex", NaN, "RNTI", NaN, "ServingCell", NaN, "CurrentSchedulingDirection", "", ...
            "CellAcquisitionState", "", "AccessState", "", "LastPDCCHStatus", "", ...
            "TimeAlignmentState", "", "LastTimingAdvance_samples", NaN, "LastTimingAdvance_us", NaN, ...
            "LastTimingAdvanceSource", "", "LastTimingAdvanceUpdateSlot", NaN, ...
            "LastTimingAdvanceServingCell", NaN, "LastTimingAdvanceServingDistance_m", NaN, ...
            "TimingAdvanceDrift_samples", NaN, "TimingAdvanceDrift_us", NaN, ...
            "TimingAdvanceUpdateRequired", false, "TimingAdvanceUpdateStatus", "", ...
            "SRSValidityState", "", "CSIValidityState", "", "TRSValidityState", "", ...
            "SharedSchedulingEligibility", false, "DLSchedulingEligibility", false, "ULSchedulingEligibility", false, ...
            "SchedulingEligibility", false, "ControlEligibility", false, "SchedulingBlockedBySRS", false, ...
            "CoverageEligibility", true, "CoverageOutageState", "", ...
            "SRSValid", false, "SRSAgeSlots", NaN, "TrackingEligibility", false, "TRSAgeSlots", NaN, ...
            "LastSuccessfulPBCHSlot", NaN, "LastSuccessfulPRACHSlot", NaN, ...
            "LastSuccessfulPDCCHSlot", NaN, "LastSuccessfulPUCCHSlot", NaN, "LastSuccessfulSRSSlot", NaN, ...
            "LastSuccessfulTRSSlot", NaN, "LastEstimatedTRSDopplerHz", NaN, ...
            "TRSRuntimeConsumer", "", "TRSReceiverIntegrationStatus", "", "TRSReceiverIntegrationBlocker", "", ...
            "TRSProcessed", false, "TRSUpdateOutcome", "", "TRSTrackingStateAfter", "", "TRSRuntimeEvidenceSource", "", ...
            "PBCHFailureCount", 0, "PRACHFailureCount", 0, ...
            "ControlDecodeFailureCount", 0, "PUCCHDecodeFailureCount", 0, "PUCCHCrashCount", 0, "SRSInvalidEventCount", 0, "TRSFailureCount", 0, ...
            "SchedulingOpportunitiesBlockedByGating", 0, "GrantsBlockedByGating", 0, "DLGrantsScheduledWithInvalidSRS", 0, "ULGrantsScheduledWithInvalidSRS", 0);
    end

    function [state, observed] = observePUCCHFeedback(state, feedbackRow)
        observed = struct("ExpectedAck", false, "ObservedAck", false, "DecodedAck", false, ...
            "DecodeOk", false, "DTXFlag", false, "MissedFeedback", true, ...
            "FalseAck", false, "FalseNack", false);
        if ~(istable(feedbackRow) && height(feedbackRow) >= 1)
            return;
        end
        row = feedbackRow(1, :);
        ueIdx = max(1, round(double(sixgr.truth.CoupledTruthRuntime.rowValue(row, "UEIndex", NaN))));
        if ~(isfinite(ueIdx) && ueIdx >= 1 && ueIdx <= double(sixgr.util.structGet(state, "NumUsers", 0)))
            return;
        end
        cfgU = state.CfgMobility;
        [cfgU, state] = sixgr.truth.CoupledTruthRuntime.applyUserContextImpl(cfgU, state, ueIdx, "UL");
        cfgU = sixgr.util.structSet(cfgU, "phy.rnti", double(sixgr.truth.CoupledTruthRuntime.rowValue(row, "RNTI", NaN)));
        cfgU = sixgr.util.structSet(cfgU, "phy.pucch.enable", true);
        prbStart = double(sixgr.truth.CoupledTruthRuntime.rowValue(row, "PUCCHPRBStart", NaN));
        prbCount = max(1, round(double(sixgr.truth.CoupledTruthRuntime.rowValue(row, "PUCCHPRBCount", 1))));
        if isfinite(prbStart)
            cfgU = sixgr.util.structSet(cfgU, "phy.pucch.PRBSet", double(prbStart) + (0:max(prbCount - 1, 0)));
        end
        symStart = double(sixgr.truth.CoupledTruthRuntime.rowValue(row, "PUCCHSymbolStart", NaN));
        numSym = max(1, round(double(sixgr.truth.CoupledTruthRuntime.rowValue(row, "PUCCHNumSymbols", 1))));
        if isfinite(symStart)
            cfgU = sixgr.util.structSet(cfgU, "phy.pucch.SymbolAllocation", [double(symStart) numSym]);
        end
        requestedFormat = double(sixgr.truth.CoupledTruthRuntime.rowValue(row, "RequestedFormat", ...
            sixgr.truth.CoupledTruthRuntime.rowValue(row, "ResolvedFormat", sixgr.util.structGet(cfgU, "phy.pucch.format", NaN))));
        if isfinite(requestedFormat)
            cfgU = sixgr.util.structSet(cfgU, "phy.pucch.format", requestedFormat);
        end
        interferenceBundle = sixgr.truth.CoupledTruthRuntime.buildPUCCHInterferenceBundle(state, row);
        expectedAck = sixgr.truth.CoupledTruthRuntime.rowExpectedPUCCHAck(row);
        observed.ExpectedAck = logical(expectedAck);
        pucchSNR_dB = sixgr.truth.CoupledTruthRuntime.resolveRuntimeSignalSNRForUE(state, cfgU, ueIdx, "UL");
        if ~isfield(state, "PUCCHChannelStateByUE") || numel(state.PUCCHChannelStateByUE) < ueIdx
            state.PUCCHChannelStateByUE{ueIdx, 1} = [];
        end
        trialIdx = max(1, round(double(sixgr.util.structGet(state, "CurrentSlot", 1))));
        trial = sixgr.link.runPUCCHWaveformTrial(cfgU, ...
            "ExpectedUCIBits", int8(logical(expectedAck)), ...
            "SNR_dB", double(pucchSNR_dB), ...
            "Format", sixgr.util.structGet(cfgU, "phy.pucch.format", []), ...
            "RNTI", double(sixgr.truth.CoupledTruthRuntime.rowValue(row, "RNTI", NaN)), ...
            "InterferenceBundle", interferenceBundle, ...
            "TrialIndex", trialIdx, ...
            "ChannelState", state.PUCCHChannelStateByUE{ueIdx});
        state.PUCCHChannelStateByUE{ueIdx, 1} = sixgr.util.structGet(trial, "ChannelState", state.PUCCHChannelStateByUE{ueIdx});
        observed.DecodeOk = logical(sixgr.util.structGet(trial, "Ok", false));
        observed.DTXFlag = logical(sixgr.util.structGet(trial, "DTXFlag", false)) || ~logical(observed.DecodeOk);
        observed.MissedFeedback = ~logical(observed.DecodeOk);
        observed.DecodedAck = logical(sixgr.util.structGet(trial, "AckObserved", false));
        observed.ObservedAck = logical(observed.DecodeOk && observed.DecodedAck);
        observed.FalseAck = logical(~expectedAck && observed.ObservedAck);
        observed.FalseNack = logical(expectedAck && observed.DecodeOk && ~observed.ObservedAck);
        trialCrashed = logical(sixgr.util.structGet(trial, "Crash", false));
        if observed.DecodeOk
            if ueIdx > numel(state.LastSuccessfulPUCCHSlotByUE)
                state.LastSuccessfulPUCCHSlotByUE(ueIdx, 1) = NaN;
            end
            state.LastSuccessfulPUCCHSlotByUE(ueIdx) = double(sixgr.util.structGet(state, "CurrentSlot", NaN));
        else
            if ueIdx > numel(state.PUCCHFailureCount)
                state.PUCCHFailureCount(ueIdx, 1) = 0;
            end
            state.PUCCHFailureCount(ueIdx) = double(state.PUCCHFailureCount(ueIdx)) + 1;
            if trialCrashed
                if ueIdx > numel(state.PUCCHCrashCount)
                    state.PUCCHCrashCount(ueIdx, 1) = 0;
                end
                state.PUCCHCrashCount(ueIdx) = double(state.PUCCHCrashCount(ueIdx)) + 1;
            end
        end
        state = sixgr.truth.CoupledTruthRuntime.appendPUCCHFeedbackTrial(state, feedbackRow, trial, observed);
    end

    function state = appendPUCCHFeedbackTrial(state, feedbackRow, trial, observed)
        if ~(istable(feedbackRow) && height(feedbackRow) >= 1)
            return;
        end
        fbRow = feedbackRow(1, :);
        if nargin < 4 || ~isstruct(observed)
            observed = struct("ExpectedAck", false, "ObservedAck", false, "DecodedAck", false, ...
                "DecodeOk", false, "DTXFlag", false, "MissedFeedback", true, ...
                "FalseAck", false, "FalseNack", false);
        end
        if nargin < 3 || ~isstruct(trial)
            trial = struct();
        end
        expectedBits = sixgr.truth.CoupledTruthRuntime.normalizeUCIBits( ...
            sixgr.util.structGet(trial, "ExpectedBits", int8(1)));
        decodedBits = sixgr.truth.CoupledTruthRuntime.normalizeUCIBits( ...
            sixgr.util.structGet(trial, "DecodedBits", int8([])));
        resolvedFormatForEvidence = double(sixgr.util.structGet(trial, "ResolvedFormat", NaN));
        expectedBitCount = double(sixgr.util.structGet(trial, "ExpectedBitCount", numel(expectedBits)));
        decodedBitCount = double(sixgr.util.structGet(trial, "DecodedBitCount", numel(decodedBits)));
        uciCrcBitCount = double(sixgr.util.structGet(trial, "UCICRCBitCount", ...
            sixgr.truth.CoupledTruthRuntime.pucchUCICRCBitCount(expectedBitCount, resolvedFormatForEvidence)));
        uciCodedBitCount = double(sixgr.util.structGet(trial, "UCICodedBitCount", ...
            sixgr.truth.CoupledTruthRuntime.pucchUCICodedBitCount(trial, resolvedFormatForEvidence)));
        dmrsReCountForEvidence = double(sixgr.util.structGet(trial, "PUCCHDMRSRECount", NaN));
        ack = logical(sixgr.util.structGet(observed, "ObservedAck", false));
        decodeOk = logical(sixgr.util.structGet(observed, "DecodeOk", false));
        detectionUsable = logical(sixgr.util.structGet(trial, "DetectionUsable", true));
        crcApplicable = logical(sixgr.util.structGet(trial, "CRCApplicable", uciCrcBitCount > 0));
        if crcApplicable && detectionUsable
            crcPassValue = double(decodeOk);
        else
            crcPassValue = NaN;
        end
        uciContentMatch = logical(sixgr.util.structGet(trial, "UCIContentMatch", ...
            (double(sixgr.util.structGet(trial, "BitErrors", 1)) == 0 && ...
            double(sixgr.util.structGet(trial, "BitsCompared", 0)) == numel(sixgr.util.structGet(trial, "ExpectedBits", int8(1))))));
        crcOutcome = string(sixgr.util.structGet(trial, "CRCOutcome", ...
            sixgr.truth.CoupledTruthRuntime.ternaryString(crcApplicable, ...
            sixgr.truth.CoupledTruthRuntime.ternaryString(decodeOk, "pass", "fail"), "not_applicable")));
        detectionOutcome = string(sixgr.util.structGet(trial, "DetectionOutcome", ...
            sixgr.truth.CoupledTruthRuntime.ternaryString(detectionUsable, ...
            sixgr.truth.CoupledTruthRuntime.ternaryString(uciContentMatch, "detected", "missed"), "unavailable")));
        status = string(sixgr.util.structGet(trial, "Status", ...
            sixgr.truth.CoupledTruthRuntime.ternaryString(ack, "PASS", "FAIL")));
        expectedAck = sixgr.truth.CoupledTruthRuntime.rowExpectedPUCCHAck(fbRow);
        row = struct( ...
            "Direction", "UL", ...
            "Frame", double(sixgr.util.structGet(state, "CurrentFrame", NaN)), ...
            "Slot", double(sixgr.util.structGet(state, "CurrentSlot", NaN)), ...
            "UEIndex", double(sixgr.truth.CoupledTruthRuntime.rowValue(fbRow, "UEIndex", NaN)), ...
            "UEID", double(sixgr.truth.CoupledTruthRuntime.rowValue(fbRow, "UEIndex", NaN)), ...
            "RNTI", double(sixgr.truth.CoupledTruthRuntime.rowValue(fbRow, "RNTI", NaN)), ...
            "BaseStationID", double(sixgr.truth.CoupledTruthRuntime.rowValue(fbRow, "BaseStationID", sixgr.truth.CoupledTruthRuntime.rowValue(fbRow, "ServingCell", NaN))), ...
            "TBSize_bits", double(numel(expectedBits)), ...
            "ExpectedBitCount", expectedBitCount, ...
            "DecodedBitCount", decodedBitCount, ...
            "UCIExpectedBitVector", char(string(sixgr.util.structGet(trial, "UCIExpectedBitVector", ...
                sixgr.truth.CoupledTruthRuntime.uciBitVectorString(expectedBits)))), ...
            "UCIDecodedBitVector", char(string(sixgr.util.structGet(trial, "UCIDecodedBitVector", ...
                sixgr.truth.CoupledTruthRuntime.uciBitVectorString(decodedBits)))), ...
            "UCIBitErrorVector", char(string(sixgr.util.structGet(trial, "UCIBitErrorVector", ...
                sixgr.truth.CoupledTruthRuntime.uciBitErrorVectorString(expectedBits, decodedBits)))), ...
            "UCICodedBitCount", uciCodedBitCount, ...
            "UCICRCBitCount", uciCrcBitCount, ...
            "UCICRCApplicable", logical(sixgr.util.structGet(trial, "UCICRCApplicable", uciCrcBitCount > 0)), ...
            "BitsCompared", double(sixgr.util.structGet(trial, "BitsCompared", 1)), ...
            "BitErrors", double(sixgr.util.structGet(trial, "BitErrors", double(~ack))), ...
            "CRCPass", crcPassValue, ...
            "CRCApplicable", crcApplicable, ...
            "CRCOutcome", char(crcOutcome), ...
            "UCIContentMatch", logical(uciContentMatch), ...
            "DetectionOutcome", char(detectionOutcome), ...
            "DetectionMetric", double(sixgr.util.structGet(trial, "DetectionMetric", double(ack))), ...
            "DetectionThreshold", double(sixgr.util.structGet(trial, "DetectionThreshold", NaN)), ...
            "DetectionMetricStatus", char(string(sixgr.util.structGet(trial, "DetectionMetricStatus", ""))), ...
            "DetectorPeakMetric", double(sixgr.util.structGet(trial, "DetectorPeakMetric", NaN)), ...
            "DetectorNoiseFloor", double(sixgr.util.structGet(trial, "DetectorNoiseFloor", NaN)), ...
            "DTXFlag", logical(sixgr.util.structGet(trial, "DTXFlag", false)), ...
            "DTXReason", char(string(sixgr.util.structGet(trial, "DTXReason", ""))), ...
            "AirInterfaceTTI_ms", double(sixgr.util.structGet(trial, "AirInterfaceTTI_ms", double(state.SlotDuration_s) * 1e3)), ...
            "ComputeLatency_ms", double(sixgr.util.structGet(trial, "ComputeLatency_ms", NaN)), ...
            "DecodeLatency_ms", double(sixgr.util.structGet(trial, "DecodeLatency_ms", NaN)), ...
            "NoiseVariance", double(sixgr.util.structGet(trial, "NoiseVariance", NaN)), ...
            "NoiseVarStatus", char(string(sixgr.util.structGet(trial, "NoiseVarStatus", ""))), ...
            "NoiseVarSource", char(string(sixgr.util.structGet(trial, "NoiseVarSource", ""))), ...
            "NoiseVarReason", char(string(sixgr.util.structGet(trial, "NoiseVarReason", ""))), ...
            "NoiseVarStrictFailure", logical(sixgr.util.structGet(trial, "NoiseVarStrictFailure", false)), ...
            "ReceiverUsable", logical(sixgr.util.structGet(trial, "ReceiverUsable", false)), ...
            "ChannelEstimateAttempted", logical(sixgr.util.structGet(trial, "ChannelEstimateAttempted", false)), ...
            "ChannelEstimateAvailable", logical(sixgr.util.structGet(trial, "ChannelEstimateAvailable", false)), ...
            "ChannelEstimateSource", char(string(sixgr.util.structGet(trial, "ChannelEstimateSource", "nrPUCCHDMRS_nrChannelEstimate"))), ...
            "ResourceExtractionAttempted", logical(sixgr.util.structGet(trial, "ResourceExtractionAttempted", false)), ...
            "ResourceExtractionAvailable", logical(sixgr.util.structGet(trial, "ResourceExtractionAvailable", false)), ...
            "EqualizationAttempted", logical(sixgr.util.structGet(trial, "EqualizationAttempted", false)), ...
            "EqualizationAvailable", logical(sixgr.util.structGet(trial, "EqualizationAvailable", false)), ...
            "StrictReceiverEvidenceOk", logical(sixgr.util.structGet(trial, "StrictReceiverEvidenceOk", false)), ...
            "StrictOk", logical(sixgr.util.structGet(trial, "StrictOk", false)), ...
            "TruthStatus", char(string(sixgr.util.structGet(trial, "TruthStatus", "real_pucch_waveform_uci_receiver_evidence"))), ...
            "DetectionAttempted", logical(sixgr.util.structGet(trial, "DetectionAttempted", false)), ...
            "DetectionUsable", detectionUsable, ...
            "FailureReason", char(string(sixgr.util.structGet(trial, "FailureReason", ""))), ...
            "ConfiguredSNR_dB", double(sixgr.util.structGet(trial, "ConfiguredSNR_dB", sixgr.util.structGet(state, "CurrentSNR_dB", NaN))), ...
            "ConfiguredSNRSource", char(string(sixgr.util.structGet(trial, "ConfiguredSNRSource", "configured_operating_point_metadata"))), ...
            "SNRValueRole", char(string(sixgr.util.structGet(trial, "SNRValueRole", "configured_operating_point_metadata"))), ...
            "AppliedAWGNSNR_dB", double(sixgr.util.structGet(trial, "AppliedAWGNSNR_dB", NaN)), ...
            "ReceiverHestSINR_dB", double(sixgr.util.structGet(trial, "ReceiverHestSINR_dB", NaN)), ...
            "ReceiverHestSINRApplicable", logical(sixgr.util.structGet(trial, "ReceiverHestSINRApplicable", dmrsReCountForEvidence > 0)), ...
            "ReceiverHestSINRSource", char(string(sixgr.util.structGet(trial, "ReceiverHestSINRSource", ""))), ...
            "ReceiverHestSINRValueRole", char(string(sixgr.util.structGet(trial, "ReceiverHestSINRValueRole", ""))), ...
            "ReceiverHestSINRValueStatus", char(string(sixgr.util.structGet(trial, "ReceiverHestSINRValueStatus", ""))), ...
            "ReceiverHestSINRNAReason", char(string(sixgr.util.structGet(trial, "ReceiverHestSINRNAReason", ""))), ...
            "DecoderTruthProxySINR_dB", double(sixgr.util.structGet(trial, "DecoderTruthProxySINR_dB", NaN)), ...
            "DecoderTruthProxySINRSource", char(string(sixgr.util.structGet(trial, "DecoderTruthProxySINRSource", ""))), ...
            "DecoderTruthProxySINRValueRole", char(string(sixgr.util.structGet(trial, "DecoderTruthProxySINRValueRole", ""))), ...
            "DecoderTruthProxySINRValueStatus", char(string(sixgr.util.structGet(trial, "DecoderTruthProxySINRValueStatus", ""))), ...
            "DecoderTruthProxySINRNAReason", char(string(sixgr.util.structGet(trial, "DecoderTruthProxySINRNAReason", ""))), ...
            "MeasuredTrialSINR_dB", double(sixgr.util.structGet(trial, "MeasuredTrialSINR_dB", NaN)), ...
            "MeasuredTrialSINRSource", char(string(sixgr.util.structGet(trial, "MeasuredTrialSINRSource", ""))), ...
            "MeasuredTrialSINRValueRole", char(string(sixgr.util.structGet(trial, "MeasuredTrialSINRValueRole", ""))), ...
            "MeasuredTrialSINRValueStatus", char(string(sixgr.util.structGet(trial, "MeasuredTrialSINRValueStatus", ""))), ...
            "MeasuredTrialSINRNAReason", char(string(sixgr.util.structGet(trial, "MeasuredTrialSINRNAReason", ""))), ...
            "MeasuredSINR_dB", double(sixgr.util.structGet(trial, "MeasuredTrialSINR_dB", NaN)), ...
            "SINRValueRole", char(string(sixgr.util.structGet(trial, "SINRValueRole", ""))), ...
            "SINRSource", char(string(sixgr.util.structGet(trial, "SINRSource", ""))), ...
            "SINRValueStatus", char(string(sixgr.util.structGet(trial, "SINRValueStatus", ""))), ...
            "SINRValueDefinition", char(string(sixgr.util.structGet(trial, "SINRValueDefinition", ""))), ...
            "RequestedFormat", double(sixgr.util.structGet(trial, "RequestedFormat", NaN)), ...
            "ResolvedFormat", double(sixgr.util.structGet(trial, "ResolvedFormat", NaN)), ...
            "PUCCHFormat", double(sixgr.util.structGet(trial, "PUCCHFormat", sixgr.util.structGet(trial, "ResolvedFormat", NaN))), ...
            "FormatAdapted", logical(sixgr.util.structGet(trial, "FormatAdapted", false)), ...
            "FormatAdaptationReason", char(string(sixgr.util.structGet(trial, "FormatAdaptationReason", ""))), ...
            "PUCCHResourceId", char(string(sixgr.util.structGet(trial, "PUCCHResourceId", sixgr.truth.CoupledTruthRuntime.rowValue(fbRow, "PUCCHResourceId", "")))), ...
            "PUCCHPRBSet", char(string(sixgr.util.structGet(trial, "PUCCHPRBSet", ""))), ...
            "PUCCHPRBStart", double(sixgr.util.structGet(trial, "PUCCHPRBStart", sixgr.truth.CoupledTruthRuntime.rowValue(fbRow, "PUCCHPRBStart", NaN))), ...
            "PUCCHPRBCount", double(sixgr.util.structGet(trial, "PUCCHPRBCount", sixgr.truth.CoupledTruthRuntime.rowValue(fbRow, "PUCCHPRBCount", NaN))), ...
            "PUCCHSymbolStart", double(sixgr.util.structGet(trial, "PUCCHSymbolStart", sixgr.truth.CoupledTruthRuntime.rowValue(fbRow, "PUCCHSymbolStart", NaN))), ...
            "PUCCHNumSymbols", double(sixgr.util.structGet(trial, "PUCCHNumSymbols", sixgr.truth.CoupledTruthRuntime.rowValue(fbRow, "PUCCHNumSymbols", NaN))), ...
            "PUCCHRECount", double(sixgr.util.structGet(trial, "PUCCHRECount", NaN)), ...
            "PUCCHDMRSRECount", dmrsReCountForEvidence, ...
            "PUCCHExpectedBitCount", double(sixgr.util.structGet(trial, "PUCCHExpectedBitCount", expectedBitCount)), ...
            "PUCCHDecodedBitCount", double(sixgr.util.structGet(trial, "PUCCHDecodedBitCount", decodedBitCount)), ...
            "PUCCHControlSINR_dB", double(sixgr.util.structGet(trial, "PUCCHControlSINR_dB", NaN)), ...
            "PUCCHReceiverEvidenceSource", char(string(sixgr.util.structGet(trial, "PUCCHReceiverEvidenceSource", ""))), ...
            "PUCCHGridHash", char(string(sixgr.util.structGet(trial, "PUCCHGridHash", ""))), ...
            "PUCCHWaveformHash", char(string(sixgr.util.structGet(trial, "PUCCHWaveformHash", ""))), ...
            "ChannelModel", char(string(sixgr.util.structGet(trial, "ChannelModel", ""))), ...
            "DopplerHz", double(sixgr.util.structGet(trial, "DopplerHz", NaN)), ...
            "TimingEstimateUsed", logical(sixgr.util.structGet(trial, "TimingEstimateUsed", false)), ...
            "UseIdealTimingSync", logical(sixgr.util.structGet(trial, "UseIdealTimingSync", false)), ...
            "InterferenceMode", char(string(sixgr.util.structGet(trial, "InterferenceMode", "none"))), ...
            "InterferenceContributorCount", double(sixgr.util.structGet(trial, "InterferenceContributorCount", 0)), ...
            "InterferenceAggregatedRxPower_dBm", double(sixgr.util.structGet(trial, "InterferenceAggregatedRxPower_dBm", NaN)), ...
            "InterferencePowerSource", char(string(sixgr.util.structGet(trial, "InterferencePowerSource", ""))), ...
            "FullInterfererChannelTruthUsed", logical(sixgr.util.structGet(trial, "FullInterfererChannelTruthUsed", false)), ...
            "SourceSlot", double(sixgr.truth.CoupledTruthRuntime.rowValue(fbRow, "SourceSlot", NaN)), ...
            "FeedbackForDirection", char(string(sixgr.truth.CoupledTruthRuntime.rowValue(fbRow, "Direction", ""))), ...
            "HARQProcess", double(sixgr.truth.CoupledTruthRuntime.rowValue(fbRow, "HarqID", NaN)), ...
            "UCIBitCount", double(sixgr.truth.CoupledTruthRuntime.rowValue(fbRow, "UCIBitCount", numel(expectedBits))), ...
            "PUCCHGrantId", char(string(sixgr.truth.CoupledTruthRuntime.rowValue(fbRow, "PUCCHGrantId", ""))), ...
            "UCIType", char(string(sixgr.truth.CoupledTruthRuntime.rowValue(fbRow, "UCIType", "harq_ack"))), ...
            "ControlResourceSource", char(string(sixgr.truth.CoupledTruthRuntime.rowValue(fbRow, "ControlResourceSource", "runtime_deterministic_pucch_resource_assignment"))), ...
            "ControlResourceValidity", logical(sixgr.util.structGet(trial, "ControlResourceValidity", true)), ...
            "ExpectedAck", logical(expectedAck), ...
            "ObservedAck", logical(ack), ...
            "DecodedAck", logical(sixgr.util.structGet(observed, "DecodedAck", ack)), ...
            "FalseAck", logical(sixgr.util.structGet(observed, "FalseAck", false)), ...
            "FalseNack", logical(sixgr.util.structGet(observed, "FalseNack", false)), ...
            "MissedFeedback", logical(sixgr.util.structGet(observed, "MissedFeedback", ~decodeOk)), ...
            "PUCCHDecodeOk", logical(decodeOk), ...
            "RuntimeStateUpdated", true, ...
            "RuntimeStateConsumer", "HARQEntity.onFeedback", ...
            "ControlStateChanged", logical(decodeOk), ...
            "StateChangeApplied", logical(decodeOk), ...
            "ControlStateChangeDefinition", "harq_feedback_consumed_by_runtime_harq_and_scheduler", ...
            "Status", char(status), ...
            "Crash", logical(sixgr.util.structGet(trial, "Crash", false)), ...
            "CrashSource", char(string(sixgr.util.structGet(trial, "CrashSource", ""))), ...
            "CrashMessage", char(string(sixgr.util.structGet(trial, "CrashMessage", ""))), ...
            "Notes", char(string(sixgr.util.structGet(trial, "Notes", "Active waveform-backed coupled PUCCH feedback observation."))));
        state.ControlTrials.PUCCH = sixgr.truth.CoupledTruthRuntime.appendCompatTable( ...
            sixgr.util.structGet(state.ControlTrials, "PUCCH", table()), struct2table(row, "AsArray", true));
    end

    function T = annotateControlReferenceSINRColumnsImpl(signalName, T)
        if nargin < 2 || ~istable(T) || isempty(T)
            return;
        end
        n = height(T);
        signalToken = lower(strrep(string(signalName), "-", "_"));

        configuredSINR = double(sixgr.truth.CoupledTruthRuntime.tableColumnOrDefault(T, "ConfiguredSNR_dB", nan(n, 1)));
        configuredSource = strtrim(string(sixgr.truth.CoupledTruthRuntime.tableColumnOrDefault(T, "ConfiguredSNRSource", repmat("", n, 1))));
        configuredRole = strtrim(string(sixgr.truth.CoupledTruthRuntime.tableColumnOrDefault(T, "SNRValueRole", repmat("", n, 1))));
        mask = strlength(configuredSource) == 0 & isfinite(configuredSINR);
        configuredSource(mask) = "configured_operating_point_metadata";
        mask = strlength(configuredRole) == 0 & isfinite(configuredSINR);
        configuredRole(mask) = "configured_operating_point_metadata";
        T.ConfiguredSNR_dB = configuredSINR;
        T.ConfiguredSNRSource = configuredSource;
        T.SNRValueRole = configuredRole;

        receiverHestSINR = double(sixgr.truth.CoupledTruthRuntime.tableColumnOrDefault(T, "ReceiverHestSINR_dB", nan(n, 1)));
        receiverSource = strtrim(string(sixgr.truth.CoupledTruthRuntime.tableColumnOrDefault(T, "ReceiverHestSINRSource", repmat("", n, 1))));
        receiverRole = strtrim(string(sixgr.truth.CoupledTruthRuntime.tableColumnOrDefault(T, "ReceiverHestSINRValueRole", repmat("", n, 1))));
        receiverStatus = strtrim(string(sixgr.truth.CoupledTruthRuntime.tableColumnOrDefault(T, "ReceiverHestSINRValueStatus", repmat("", n, 1))));
        receiverReason = strtrim(string(sixgr.truth.CoupledTruthRuntime.tableColumnOrDefault(T, "ReceiverHestSINRNAReason", repmat("", n, 1))));
        hasReceiver = isfinite(receiverHestSINR);
        lowerReceiverSource = lower(receiverSource);
        fallbackReceiver = contains(lowerReceiverSource, "fallback") | contains(lower(receiverRole), "fallback") | contains(lower(receiverStatus), "fallback");
        if any(fallbackReceiver)
            receiverHestSINR(fallbackReceiver) = NaN;
            receiverSource(fallbackReceiver) = "";
            receiverRole(fallbackReceiver) = "unavailable";
            receiverStatus(fallbackReceiver) = "unavailable";
            receiverReason(fallbackReceiver) = signalToken + "_receiver_hest_sinr_not_available_from_waveform_reference_signal";
            hasReceiver = isfinite(receiverHestSINR);
        end
        mask = strlength(receiverSource) == 0 & hasReceiver;
        receiverSource(mask) = "receiver_hest_reference_signal_measurement";
        mask = strlength(receiverRole) == 0 & hasReceiver & ~fallbackReceiver;
        receiverRole(mask) = "estimated";
        mask = strlength(receiverRole) == 0 & hasReceiver & fallbackReceiver;
        receiverRole(mask) = "estimated_fallback";
        mask = strlength(receiverStatus) == 0 & hasReceiver & ~fallbackReceiver;
        receiverStatus(mask) = "OK";
        mask = strlength(receiverStatus) == 0 & hasReceiver & fallbackReceiver;
        receiverStatus(mask) = "fallback";
        mask = strlength(receiverReason) == 0 & ~hasReceiver;
        receiverReason(mask) = signalToken + "_receiver_hest_sinr_unavailable";
        mask = strlength(receiverRole) == 0 & ~hasReceiver;
        receiverRole(mask) = "unavailable";
        mask = strlength(receiverStatus) == 0 & ~hasReceiver;
        receiverStatus(mask) = "unavailable";
        T.ReceiverHestSINR_dB = receiverHestSINR;
        T.ReceiverHestSINRSource = receiverSource;
        T.ReceiverHestSINRValueRole = receiverRole;
        T.ReceiverHestSINRValueStatus = receiverStatus;
        T.ReceiverHestSINRNAReason = receiverReason;

        decoderProxySINR = double(sixgr.truth.CoupledTruthRuntime.tableColumnOrDefault(T, "DecoderTruthProxySINR_dB", nan(n, 1)));
        decoderSource = strtrim(string(sixgr.truth.CoupledTruthRuntime.tableColumnOrDefault(T, "DecoderTruthProxySINRSource", repmat("", n, 1))));
        decoderRole = strtrim(string(sixgr.truth.CoupledTruthRuntime.tableColumnOrDefault(T, "DecoderTruthProxySINRValueRole", repmat("", n, 1))));
        decoderStatus = strtrim(string(sixgr.truth.CoupledTruthRuntime.tableColumnOrDefault(T, "DecoderTruthProxySINRValueStatus", repmat("", n, 1))));
        decoderReason = strtrim(string(sixgr.truth.CoupledTruthRuntime.tableColumnOrDefault(T, "DecoderTruthProxySINRNAReason", repmat("", n, 1))));
        proxyLike = isfinite(decoderProxySINR) | contains(lower(decoderSource), "evm_proxy") | ...
            contains(lower(decoderSource), "proxy") | contains(lower(decoderRole), "proxy");
        decoderProxySINR(proxyLike) = NaN;
        mask = proxyLike;
        decoderSource(mask) = "evm_proxy_quarantined_not_decoder_truth";
        decoderReason(mask) = "decoder_truth_sinr_requires_receiver_or_decoder_evidence_not_evm_proxy";
        mask = strlength(decoderSource) == 0;
        decoderSource(mask) = "unavailable_decoder_truth_proxy_not_materialized";
        mask = strlength(decoderReason) == 0;
        decoderReason(mask) = signalToken + "_decoder_truth_proxy_not_materialized";
        mask = strlength(decoderRole) == 0 | proxyLike;
        decoderRole(mask) = "unavailable";
        mask = strlength(decoderStatus) == 0 | proxyLike;
        decoderStatus(mask) = "unavailable";
        T.DecoderTruthProxySINR_dB = decoderProxySINR;
        T.DecoderTruthProxySINRSource = decoderSource;
        T.DecoderTruthProxySINRValueRole = decoderRole;
        T.DecoderTruthProxySINRValueStatus = decoderStatus;
        T.DecoderTruthProxySINRNAReason = decoderReason;

        measuredTrialSINR = double(sixgr.truth.CoupledTruthRuntime.tableColumnOrDefault(T, "MeasuredTrialSINR_dB", nan(n, 1)));
        measuredSource = strtrim(string(sixgr.truth.CoupledTruthRuntime.tableColumnOrDefault(T, "MeasuredTrialSINRSource", repmat("", n, 1))));
        measuredRole = strtrim(string(sixgr.truth.CoupledTruthRuntime.tableColumnOrDefault(T, "MeasuredTrialSINRValueRole", repmat("", n, 1))));
        measuredStatus = strtrim(string(sixgr.truth.CoupledTruthRuntime.tableColumnOrDefault(T, "MeasuredTrialSINRValueStatus", repmat("", n, 1))));
        measuredReason = strtrim(string(sixgr.truth.CoupledTruthRuntime.tableColumnOrDefault(T, "MeasuredTrialSINRNAReason", repmat("", n, 1))));
        hasMeasured = isfinite(measuredTrialSINR);
        mask = strlength(measuredSource) == 0 & hasMeasured & strlength(receiverSource) > 0 & ~contains(lower(receiverSource), "fallback");
        measuredSource(mask) = receiverSource(mask);
        mask = strlength(measuredSource) == 0 & hasMeasured;
        measuredSource(mask) = "waveform_trial_measurement";
        mask = strlength(measuredRole) == 0 & hasMeasured;
        measuredRole(mask) = "measured";
        mask = strlength(measuredStatus) == 0 & hasMeasured;
        measuredStatus(mask) = "OK";
        mask = strlength(measuredReason) == 0 & ~hasMeasured;
        measuredReason(mask) = signalToken + "_measured_trial_sinr_unavailable";
        mask = strlength(measuredRole) == 0 & ~hasMeasured;
        measuredRole(mask) = "unavailable";
        mask = strlength(measuredStatus) == 0 & ~hasMeasured;
        measuredStatus(mask) = "unavailable";
        T.MeasuredTrialSINR_dB = measuredTrialSINR;
        T.MeasuredTrialSINRSource = measuredSource;
        T.MeasuredTrialSINRValueRole = measuredRole;
        T.MeasuredTrialSINRValueStatus = measuredStatus;
        T.MeasuredTrialSINRNAReason = measuredReason;

        measuredSINR = double(sixgr.truth.CoupledTruthRuntime.tableColumnOrDefault(T, "MeasuredSINR_dB", nan(n, 1)));
        mask = ~isfinite(measuredSINR) & hasMeasured;
        measuredSINR(mask) = measuredTrialSINR(mask);
        T.MeasuredSINR_dB = measuredSINR;

        sinrRole = strtrim(string(sixgr.truth.CoupledTruthRuntime.tableColumnOrDefault(T, "SINRValueRole", repmat("", n, 1))));
        sinrSource = strtrim(string(sixgr.truth.CoupledTruthRuntime.tableColumnOrDefault(T, "SINRSource", repmat("", n, 1))));
        sinrStatus = strtrim(string(sixgr.truth.CoupledTruthRuntime.tableColumnOrDefault(T, "SINRValueStatus", repmat("", n, 1))));
        sinrDefinition = strtrim(string(sixgr.truth.CoupledTruthRuntime.tableColumnOrDefault(T, "SINRValueDefinition", repmat("", n, 1))));
        hasMeasuredAlias = isfinite(measuredSINR);
        genericMeasured = hasMeasuredAlias;
        genericReceiver = ~genericMeasured & hasReceiver;
        genericDecoder = false(n, 1);
        genericMissing = ~genericMeasured & ~hasReceiver;

        forbiddenGeneric = contains(lower(sinrRole), "fallback") | contains(lower(sinrRole), "proxy") | ...
            contains(lower(sinrSource), "fallback") | contains(lower(sinrSource), "proxy") | ...
            contains(lower(sinrStatus), "fallback") | contains(lower(sinrStatus), "proxy") | ...
            contains(lower(sinrDefinition), "fallback") | contains(lower(sinrDefinition), "proxy");
        if any(forbiddenGeneric)
            sinrRole(forbiddenGeneric) = "";
            sinrSource(forbiddenGeneric) = "";
            sinrStatus(forbiddenGeneric) = "";
            sinrDefinition(forbiddenGeneric) = "";
        end

        mask = strlength(sinrRole) == 0 & genericMeasured;
        sinrRole(mask) = "measured";
        mask = strlength(sinrRole) == 0 & genericReceiver;
        sinrRole(mask) = receiverRole(mask);
        mask = strlength(sinrRole) == 0 & genericDecoder;
        sinrRole(mask) = decoderRole(mask);
        mask = strlength(sinrRole) == 0 & genericMissing;
        sinrRole(mask) = "unavailable";

        mask = strlength(sinrSource) == 0 & genericMeasured;
        sinrSource(mask) = measuredSource(mask);
        mask = strlength(sinrSource) == 0 & genericReceiver;
        sinrSource(mask) = receiverSource(mask);
        mask = strlength(sinrSource) == 0 & genericDecoder;
        sinrSource(mask) = decoderSource(mask);
        mask = strlength(sinrSource) == 0 & genericMissing;
        sinrSource(mask) = "no_active_" + signalToken + "_sinr_observation";

        mask = strlength(sinrStatus) == 0 & genericMeasured;
        sinrStatus(mask) = "OK";
        mask = strlength(sinrStatus) == 0 & genericReceiver;
        sinrStatus(mask) = receiverStatus(mask);
        mask = strlength(sinrStatus) == 0 & genericDecoder;
        sinrStatus(mask) = decoderStatus(mask);
        mask = strlength(sinrStatus) == 0 & genericMissing;
        sinrStatus(mask) = "unavailable";

        mask = strlength(sinrDefinition) == 0 & genericMeasured;
        sinrDefinition(mask) = "measured_trial_sinr_from_control_waveform_observation";
        mask = strlength(sinrDefinition) == 0 & genericReceiver & receiverStatus == "fallback";
        sinrDefinition(mask) = "receiver_hest_sinr_from_control_waveform_fallback";
        mask = strlength(sinrDefinition) == 0 & genericReceiver & receiverStatus ~= "fallback";
        sinrDefinition(mask) = "receiver_hest_sinr_from_control_reference_signal_measurement";
        mask = strlength(sinrDefinition) == 0 & genericDecoder;
        sinrDefinition(mask) = "decoder_truth_proxy_sinr_from_control_waveform_observation";
        mask = strlength(sinrDefinition) == 0 & genericMissing;
        sinrDefinition(mask) = "no_control_sinr_observation_available_in_active_runtime";

        T.SINRValueRole = sinrRole;
        T.SINRSource = sinrSource;
        T.SINRValueStatus = sinrStatus;
        T.SINRValueDefinition = sinrDefinition;
        T = sixgr.truth.CoupledTruthRuntime.repairControlReferenceEvidenceColumnsImpl(signalToken, T);
    end

    function T = repairControlReferenceEvidenceColumnsImpl(signalToken, T)
        if ~(istable(T) && ~isempty(T))
            return;
        end
        n = height(T);
        signalToken = lower(strrep(string(signalToken), "-", "_"));
        signalBase = regexprep(signalToken, "_trials$", "");
        status = lower(strtrim(string(sixgr.truth.CoupledTruthRuntime.tableColumnOrDefault(T, "Status", repmat("", n, 1)))));
        crash = logical(sixgr.truth.CoupledTruthRuntime.tableColumnOrDefault(T, "Crash", false(n, 1)));
        crcPass = double(sixgr.truth.CoupledTruthRuntime.tableColumnOrDefault(T, "CRCPass", nan(n, 1)));
        detectionMetric = double(sixgr.truth.CoupledTruthRuntime.tableColumnOrDefault(T, "DetectionMetric", nan(n, 1)));
        correlationPeak = double(sixgr.truth.CoupledTruthRuntime.tableColumnOrDefault(T, "CorrelationPeak", nan(n, 1)));
        detectorPeak = double(sixgr.truth.CoupledTruthRuntime.tableColumnOrDefault(T, "DetectorPeakMetric", nan(n, 1)));
        detectedPreamble = double(sixgr.truth.CoupledTruthRuntime.tableColumnOrDefault(T, "DetectedPreambleIndex", nan(n, 1)));
        preambleFromPeak = double(sixgr.truth.CoupledTruthRuntime.tableColumnOrDefault(T, "PreambleIndexFromPeak", nan(n, 1)));
        bitsCompared = double(sixgr.truth.CoupledTruthRuntime.tableColumnOrDefault(T, "BitsCompared", nan(n, 1)));
        bitErrors = double(sixgr.truth.CoupledTruthRuntime.tableColumnOrDefault(T, "BitErrors", nan(n, 1)));

        activeOutcome = ~crash & any(status == ["pass","fail"], 2);
        detectionEvidence = activeOutcome | isfinite(crcPass) | isfinite(detectionMetric) | ...
            isfinite(correlationPeak) | isfinite(detectorPeak) | isfinite(detectedPreamble) | ...
            isfinite(preambleFromPeak) | isfinite(bitsCompared) | isfinite(bitErrors);
        detectionSignals = ["pbch","prach","pdcch","pucch"];
        if any(signalBase == detectionSignals)
            if ismember("DetectionAttempted", string(T.Properties.VariableNames))
                T.DetectionAttempted = logical(sixgr.truth.CoupledTruthRuntime.tableColumnOrDefault(T, "DetectionAttempted", false(n, 1)) | detectionEvidence);
            end
            if ismember("DetectionUsable", string(T.Properties.VariableNames))
                T.DetectionUsable = logical(sixgr.truth.CoupledTruthRuntime.tableColumnOrDefault(T, "DetectionUsable", false(n, 1)) | ...
                    (~crash & (isfinite(detectionMetric) | isfinite(correlationPeak) | isfinite(detectorPeak) | isfinite(crcPass))));
            end
        end

        receiverSINR = double(sixgr.truth.CoupledTruthRuntime.tableColumnOrDefault(T, "ReceiverHestSINR_dB", nan(n, 1)));
        measuredSINR = double(sixgr.truth.CoupledTruthRuntime.tableColumnOrDefault(T, "MeasuredTrialSINR_dB", nan(n, 1)));
        noiseVar = double(sixgr.truth.CoupledTruthRuntime.tableColumnOrDefault(T, "NoiseVariance", nan(n, 1)));
        nmse = double(sixgr.truth.CoupledTruthRuntime.tableColumnOrDefault(T, "NMSE_dB", nan(n, 1)));
        measurementEvidence = ~crash & (isfinite(receiverSINR) | isfinite(measuredSINR) | isfinite(noiseVar) | isfinite(nmse));
        if ismember("MeasurementAttempted", string(T.Properties.VariableNames))
            T.MeasurementAttempted = logical(sixgr.truth.CoupledTruthRuntime.tableColumnOrDefault(T, "MeasurementAttempted", false(n, 1)) | measurementEvidence);
        end
        if ismember("MeasurementUsable", string(T.Properties.VariableNames))
            T.MeasurementUsable = logical(sixgr.truth.CoupledTruthRuntime.tableColumnOrDefault(T, "MeasurementUsable", false(n, 1)) | ...
                (~crash & (isfinite(receiverSINR) | isfinite(measuredSINR))));
        end
        if ismember("ReceiverUsable", string(T.Properties.VariableNames))
            T.ReceiverUsable = logical(sixgr.truth.CoupledTruthRuntime.tableColumnOrDefault(T, "ReceiverUsable", false(n, 1)) | ...
                (~crash & (isfinite(receiverSINR) | isfinite(measuredSINR))));
        end

        if signalBase == "pdcch"
            crcApplicable = sixgr.truth.CoupledTruthRuntime.logicalVectorOrDefault( ...
                sixgr.truth.CoupledTruthRuntime.tableColumnOrDefault(T, "CRCApplicable", isfinite(crcPass)), n, false);
            dciCrcPass = sixgr.truth.CoupledTruthRuntime.logicalVectorOrDefault( ...
                sixgr.truth.CoupledTruthRuntime.tableColumnOrDefault(T, "DCICrcPass", crcPass == 1), n, false);
            payloadMatch = sixgr.truth.CoupledTruthRuntime.logicalVectorOrDefault( ...
                sixgr.truth.CoupledTruthRuntime.tableColumnOrDefault(T, "PDCCHPayloadMatch", bitErrors == 0 & bitsCompared > 0), n, false);
            candidates = double(sixgr.truth.CoupledTruthRuntime.tableColumnOrDefault(T, "CandidatesAttempted", ...
                sixgr.truth.CoupledTruthRuntime.tableColumnOrDefault(T, "PDCCHCandidatesAttempted", ...
                sixgr.truth.CoupledTruthRuntime.tableColumnOrDefault(T, "BlindDecodeCount", nan(n, 1)))));
            hestStatus = lower(strtrim(string(sixgr.truth.CoupledTruthRuntime.tableColumnOrDefault(T, "ReceiverHestSINRValueStatus", repmat("", n, 1)))));
            noiseStatus = lower(strtrim(string(sixgr.truth.CoupledTruthRuntime.tableColumnOrDefault(T, "NoiseVarStatus", repmat("", n, 1)))));
            noiseStrictFailure = logical(sixgr.truth.CoupledTruthRuntime.tableColumnOrDefault(T, "NoiseVarStrictFailure", false(n, 1)));
            chanOk = logical(sixgr.truth.CoupledTruthRuntime.tableColumnOrDefault(T, "ChannelEstimateAvailable", false(n, 1)));
            resOk = logical(sixgr.truth.CoupledTruthRuntime.tableColumnOrDefault(T, "ResourceExtractionAvailable", false(n, 1)));
            eqOk = logical(sixgr.truth.CoupledTruthRuntime.tableColumnOrDefault(T, "EqualizationAvailable", false(n, 1)));
            receiverOk = isfinite(receiverSINR) & (hestStatus == "ok" | strlength(hestStatus) == 0);
            noiseOk = isfinite(noiseVar) & noiseVar > 0 & (noiseStatus == "ok" | strlength(noiseStatus) == 0) & ~noiseStrictFailure;
            strict = ~crash & crcApplicable & dciCrcPass & payloadMatch & candidates > 0 & ...
                receiverOk & noiseOk & chanOk & resOk & eqOk;
            T = sixgr.truth.CoupledTruthRuntime.setLogicalColumn(T, "CRCApplicable", crcApplicable);
            T = sixgr.truth.CoupledTruthRuntime.setLogicalColumn(T, "DCICrcPass", dciCrcPass);
            T = sixgr.truth.CoupledTruthRuntime.setLogicalColumn(T, "StrictReceiverEvidenceOk", strict);
            T = sixgr.truth.CoupledTruthRuntime.setLogicalColumn(T, "StrictOk", strict);
            T = sixgr.truth.CoupledTruthRuntime.setLogicalColumn(T, "ReceiverUsable", strict);
            if ismember("Status", string(T.Properties.VariableNames))
                statusStrict = string(T.Status);
                statusStrict(~strict & lower(strtrim(statusStrict)) == "pass") = "FAIL";
                T.Status = statusStrict;
            end
        elseif signalBase == "pucch"
            uciMatch = logical(sixgr.truth.CoupledTruthRuntime.tableColumnOrDefault(T, "UCIContentMatch", false(n, 1)));
            detectionOk = logical(sixgr.truth.CoupledTruthRuntime.tableColumnOrDefault(T, "DetectionUsable", false(n, 1)));
            crcApplicable = sixgr.truth.CoupledTruthRuntime.logicalVectorOrDefault( ...
                sixgr.truth.CoupledTruthRuntime.tableColumnOrDefault(T, "CRCApplicable", false(n, 1)), n, false);
            crcOk = (~crcApplicable) | (crcPass == 1);
            resourceOk = logical(sixgr.truth.CoupledTruthRuntime.tableColumnOrDefault(T, "ResourceExtractionAvailable", false(n, 1)));
            controlResourceOk = logical(sixgr.truth.CoupledTruthRuntime.tableColumnOrDefault(T, "ControlResourceValidity", true(n, 1)));
            dmrsCount = double(sixgr.truth.CoupledTruthRuntime.tableColumnOrDefault(T, "PUCCHDMRSRECount", nan(n, 1)));
            dmrsRequired = isfinite(dmrsCount) & dmrsCount > 0;
            chanOk = logical(sixgr.truth.CoupledTruthRuntime.tableColumnOrDefault(T, "ChannelEstimateAvailable", false(n, 1)));
            eqOk = logical(sixgr.truth.CoupledTruthRuntime.tableColumnOrDefault(T, "EqualizationAvailable", false(n, 1)));
            hestStatus = lower(strtrim(string(sixgr.truth.CoupledTruthRuntime.tableColumnOrDefault(T, "ReceiverHestSINRValueStatus", repmat("", n, 1)))));
            noiseStatus = lower(strtrim(string(sixgr.truth.CoupledTruthRuntime.tableColumnOrDefault(T, "NoiseVarStatus", repmat("", n, 1)))));
            noiseStrictFailure = logical(sixgr.truth.CoupledTruthRuntime.tableColumnOrDefault(T, "NoiseVarStrictFailure", false(n, 1)));
            receiverOk = ~dmrsRequired | (isfinite(receiverSINR) & (hestStatus == "ok" | startsWith(hestStatus, "ok_") | strlength(hestStatus) == 0));
            noiseOk = isfinite(noiseVar) & noiseVar > 0 & (noiseStatus == "ok" | startsWith(noiseStatus, "ok_") | strlength(noiseStatus) == 0) & ~noiseStrictFailure;
            strict = ~crash & uciMatch & detectionOk & crcOk & resourceOk & controlResourceOk & ...
                noiseOk & receiverOk & (~dmrsRequired | (chanOk & eqOk));
            T = sixgr.truth.CoupledTruthRuntime.setLogicalColumn(T, "StrictReceiverEvidenceOk", strict);
            T = sixgr.truth.CoupledTruthRuntime.setLogicalColumn(T, "StrictOk", strict);
            T = sixgr.truth.CoupledTruthRuntime.setLogicalColumn(T, "ReceiverUsable", strict);
            if ismember("Status", string(T.Properties.VariableNames))
                statusStrict = string(T.Status);
                statusStrict(~strict & lower(strtrim(statusStrict)) == "pass") = "FAIL";
                T.Status = statusStrict;
            end
        end

        if ismember("ChannelFadingApplied", string(T.Properties.VariableNames))
            channelModel = upper(strtrim(string(sixgr.truth.CoupledTruthRuntime.tableColumnOrDefault(T, "ChannelModel", repmat("", n, 1)))));
            channelModelApplied = upper(strtrim(string(sixgr.truth.CoupledTruthRuntime.tableColumnOrDefault(T, "ChannelModelApplied", repmat("", n, 1)))));
            channelClass = lower(strtrim(string(sixgr.truth.CoupledTruthRuntime.tableColumnOrDefault(T, "ChannelObjectClass", repmat("", n, 1)))));
            channelSource = lower(strtrim(string(sixgr.truth.CoupledTruthRuntime.tableColumnOrDefault(T, "ChannelObjectSource", repmat("", n, 1)))));
            concreteFadingModel = startsWith(channelModel, "TDL") | startsWith(channelModel, "CDL") | ...
                startsWith(channelModelApplied, "TDL") | startsWith(channelModelApplied, "CDL");
            fadingRuntimeEvidence = concreteFadingModel | contains(channelClass, "nrtdl") | contains(channelClass, "nrcdl") | ...
                contains(channelSource, "tdl") | contains(channelSource, "cdl");
            T.ChannelFadingApplied = logical(sixgr.truth.CoupledTruthRuntime.tableColumnOrDefault(T, "ChannelFadingApplied", false(n, 1)) | ...
                (~crash & fadingRuntimeEvidence));
        end
    end

    function state = appendPUCCHGrantTraceFromFeedback(state, feedbackRow)
        row = sixgr.truth.CoupledTruthRuntime.buildPUCCHGrantTraceRowFromFeedback(state, feedbackRow);
        rowT = struct2table(row, "AsArray", true);
        state.PUCCHGrantTraceTable = sixgr.truth.CoupledTruthRuntime.appendCompatTable( ...
            sixgr.util.structGet(state, "PUCCHGrantTraceTable", table()), rowT);
    end

    function row = buildPUCCHGrantTraceRowFromFeedback(state, feedbackRow)
        row = sixgr.truth.CoupledTruthRuntime.emptyPUCCHGrantRow();
        if istable(feedbackRow) && height(feedbackRow) >= 1
            fbRow = feedbackRow(1, :);
        else
            fbRow = struct2table(feedbackRow, "AsArray", true);
            fbRow = fbRow(1, :);
        end
        dueSlot = double(sixgr.truth.CoupledTruthRuntime.rowValue(fbRow, "DueSlot", NaN));
        dueFrame = sixgr.truth.CoupledTruthRuntime.absoluteSlotToFrame(state, dueSlot);
        row.Direction = "UL";
        row.FeedbackForDirection = char(string(sixgr.truth.CoupledTruthRuntime.rowValue(fbRow, "Direction", "")));
        row.Frame = double(dueFrame);
        row.Slot = double(dueSlot);
        row.ScheduledAbsoluteSlot = double(dueSlot);
        row.SourceSlot = double(sixgr.truth.CoupledTruthRuntime.rowValue(fbRow, "SourceSlot", NaN));
        row.UEIndex = double(sixgr.truth.CoupledTruthRuntime.rowValue(fbRow, "UEIndex", NaN));
        row.UEID = double(row.UEIndex);
        row.RNTI = double(sixgr.truth.CoupledTruthRuntime.rowValue(fbRow, "RNTI", NaN));
        row.ServingCell = double(sixgr.truth.CoupledTruthRuntime.rowValue(fbRow, "ServingCell", NaN));
        row.BaseStationID = double(sixgr.truth.CoupledTruthRuntime.rowValue(fbRow, "BaseStationID", row.ServingCell));
        row.HarqID = double(sixgr.truth.CoupledTruthRuntime.rowValue(fbRow, "HarqID", NaN));
        row.TBSBits = double(sixgr.truth.CoupledTruthRuntime.rowValue(fbRow, "TBSBits", NaN));
        row.ExpectedAck = logical(sixgr.truth.CoupledTruthRuntime.rowLogical(fbRow, "Ack", false));
        row.ExpectedHARQCurrentDecodeOK = logical(sixgr.truth.CoupledTruthRuntime.rowLogical(fbRow, "CurrentDecodeOK", false));
        row.ExpectedHARQCombinedDecodeOK = logical(sixgr.truth.CoupledTruthRuntime.rowLogical(fbRow, "CombinedDecodeOK", false));
        row.CurrentDecodeOK = false;
        row.CombinedDecodeOK = false;
        row.UCIBitCount = double(sixgr.truth.CoupledTruthRuntime.rowValue(fbRow, "UCIBitCount", NaN));
        row.UCIType = char(string(sixgr.truth.CoupledTruthRuntime.rowValue(fbRow, "UCIType", "harq_ack")));
        row.PUCCHGrantId = char(string(sixgr.truth.CoupledTruthRuntime.rowValue(fbRow, "PUCCHGrantId", "")));
        row.GrantScheduledFlag = true;
        row.RequestedFormat = double(sixgr.truth.CoupledTruthRuntime.rowValue(fbRow, "RequestedFormat", NaN));
        row.ResolvedFormat = double(sixgr.truth.CoupledTruthRuntime.rowValue(fbRow, "ResolvedFormat", NaN));
        row.FormatAdaptationReason = char(string(sixgr.truth.CoupledTruthRuntime.rowValue(fbRow, "FormatAdaptationReason", "")));
        row.PUCCHResourceId = char(string(sixgr.truth.CoupledTruthRuntime.rowValue(fbRow, "PUCCHResourceId", "")));
        row.PUCCHPRBStart = double(sixgr.truth.CoupledTruthRuntime.rowValue(fbRow, "PUCCHPRBStart", NaN));
        row.PUCCHPRBCount = double(sixgr.truth.CoupledTruthRuntime.rowValue(fbRow, "PUCCHPRBCount", NaN));
        row.PUCCHSymbolStart = double(sixgr.truth.CoupledTruthRuntime.rowValue(fbRow, "PUCCHSymbolStart", NaN));
        row.PUCCHNumSymbols = double(sixgr.truth.CoupledTruthRuntime.rowValue(fbRow, "PUCCHNumSymbols", NaN));
        row.ControlResourceSource = char(string(sixgr.truth.CoupledTruthRuntime.rowValue(fbRow, "ControlResourceSource", "runtime_deterministic_pucch_resource_assignment")));
        row.ControlResourceValidity = logical(sixgr.truth.CoupledTruthRuntime.rowLogical(fbRow, "ControlResourceValidity", true)) && ...
            isfinite(row.PUCCHPRBStart) && isfinite(row.PUCCHSymbolStart) && ...
            isfinite(row.RequestedFormat) && isfinite(row.ResolvedFormat);
        row.ConfiguredSNR_dB = double(sixgr.util.structGet(state, "CurrentSNR_dB", NaN));
        row.InterferenceMode = char(string(sixgr.truth.CoupledTruthRuntime.resolveInterferenceExecutionMode(state.CfgMobility, state.MultiUser)));
        row.Notes = "Explicit runtime PUCCH grant/resource object scheduled from HARQ feedback timing.";
        if strlength(strtrim(string(row.FormatAdaptationReason))) == 0 && isfinite(row.RequestedFormat) && isfinite(row.ResolvedFormat) && row.RequestedFormat ~= row.ResolvedFormat
            row.FormatAdaptationReason = "scheduled_runtime_format_compatibility_adjustment";
        end
        if strlength(strtrim(string(row.PUCCHGrantId))) == 0
            row.PUCCHGrantId = sixgr.truth.CoupledTruthRuntime.composePUCCHGrantId(state, fbRow);
        end
    end

    function state = updatePUCCHGrantTraceAfterObservation(state, grantRow, observed)
        traceT = sixgr.util.structGet(state, "PUCCHGrantTraceTable", table());
        if ~(istable(traceT) && ~isempty(traceT))
            return;
        end
        grantId = string(sixgr.truth.CoupledTruthRuntime.rowValue(grantRow, "PUCCHGrantId", ""));
        if strlength(strtrim(grantId)) == 0 || ~ismember("PUCCHGrantId", string(traceT.Properties.VariableNames))
            return;
        end
        idx = find(string(traceT.PUCCHGrantId) == grantId, 1, "last");
        if isempty(idx)
            return;
        end
        trialT = sixgr.util.structGet(state.ControlTrials, "PUCCH", table());
        trialRow = table();
        if istable(trialT) && ~isempty(trialT) && ismember("PUCCHGrantId", string(trialT.Properties.VariableNames))
            trialIdx = find(string(trialT.PUCCHGrantId) == grantId, 1, "last");
            if ~isempty(trialIdx)
                trialRow = trialT(trialIdx, :);
            end
        end
        decodeOk = logical(sixgr.util.structGet(observed, "DecodeOk", false));
        observedAck = logical(sixgr.util.structGet(observed, "ObservedAck", false));
        traceT.ObservedAck(idx) = observedAck;
        if ismember("DecodedAck", string(traceT.Properties.VariableNames))
            traceT.DecodedAck(idx) = logical(sixgr.util.structGet(observed, "DecodedAck", observedAck));
        end
        if ismember("FalseAck", string(traceT.Properties.VariableNames))
            traceT.FalseAck(idx) = logical(sixgr.util.structGet(observed, "FalseAck", false));
        end
        if ismember("FalseNack", string(traceT.Properties.VariableNames))
            traceT.FalseNack(idx) = logical(sixgr.util.structGet(observed, "FalseNack", false));
        end
        if ismember("MissedFeedback", string(traceT.Properties.VariableNames))
            traceT.MissedFeedback(idx) = logical(sixgr.util.structGet(observed, "MissedFeedback", ~decodeOk));
        end
        traceT.PUCCHDecodeOk(idx) = decodeOk;
        traceT.CurrentDecodeOK(idx) = decodeOk;
        traceT.CombinedDecodeOK(idx) = decodeOk;
        traceT.GrantExecutedFlag(idx) = true;
        traceT.RuntimeStateUpdated(idx) = true;
        traceT = sixgr.truth.CoupledTruthRuntime.setStringValueAt(traceT, "RuntimeStateConsumer", idx, "HARQEntity.onFeedback");
        traceT.ControlStateChanged(idx) = decodeOk;
        traceT.StateChangeApplied(idx) = decodeOk;
        if decodeOk
            traceT = sixgr.truth.CoupledTruthRuntime.setStringValueAt(traceT, "PUCCHGrantState", idx, "waveform_observed_feedback_applied");
        else
            traceT = sixgr.truth.CoupledTruthRuntime.setStringValueAt(traceT, "PUCCHGrantState", idx, "waveform_observed_feedback_decode_failed");
        end
        if ~(istable(trialRow) && height(trialRow) >= 1)
            traceT = sixgr.truth.CoupledTruthRuntime.setStringValueAt(traceT, "Status", idx, ...
                sixgr.truth.CoupledTruthRuntime.ternaryString(decodeOk, "PASS", "FAIL"));
        else
            traceT.BitsCompared(idx) = double(sixgr.truth.CoupledTruthRuntime.rowValue(trialRow, "BitsCompared", NaN));
            traceT.BitErrors(idx) = double(sixgr.truth.CoupledTruthRuntime.rowValue(trialRow, "BitErrors", NaN));
            traceT.DetectionMetric(idx) = double(sixgr.truth.CoupledTruthRuntime.rowValue(trialRow, "DetectionMetric", NaN));
            traceT.ConfiguredSNR_dB(idx) = double(sixgr.truth.CoupledTruthRuntime.rowValue(trialRow, "ConfiguredSNR_dB", traceT.ConfiguredSNR_dB(idx)));
            traceT.AppliedAWGNSNR_dB(idx) = double(sixgr.truth.CoupledTruthRuntime.rowValue(trialRow, "AppliedAWGNSNR_dB", NaN));
            traceT = sixgr.truth.CoupledTruthRuntime.setStringValueAt(traceT, "ChannelModel", idx, ...
                sixgr.truth.CoupledTruthRuntime.rowValue(trialRow, "ChannelModel", ""));
            traceT.DopplerHz(idx) = double(sixgr.truth.CoupledTruthRuntime.rowValue(trialRow, "DopplerHz", NaN));
            traceT.TimingEstimateUsed(idx) = logical(sixgr.truth.CoupledTruthRuntime.rowLogical(trialRow, "TimingEstimateUsed", false));
            traceT.UseIdealTimingSync(idx) = logical(sixgr.truth.CoupledTruthRuntime.rowLogical(trialRow, "UseIdealTimingSync", false));
            traceT = sixgr.truth.CoupledTruthRuntime.setStringValueAt(traceT, "InterferenceMode", idx, ...
                sixgr.truth.CoupledTruthRuntime.rowValue(trialRow, "InterferenceMode", ""));
            traceT.InterferenceContributorCount(idx) = double(sixgr.truth.CoupledTruthRuntime.rowValue(trialRow, "InterferenceContributorCount", 0));
            traceT.InterferenceAggregatedRxPower_dBm(idx) = double(sixgr.truth.CoupledTruthRuntime.rowValue(trialRow, "InterferenceAggregatedRxPower_dBm", NaN));
            traceT = sixgr.truth.CoupledTruthRuntime.setStringValueAt(traceT, "InterferencePowerSource", idx, ...
                sixgr.truth.CoupledTruthRuntime.rowValue(trialRow, "InterferencePowerSource", ""));
            traceT.FullInterfererChannelTruthUsed(idx) = logical(sixgr.truth.CoupledTruthRuntime.rowLogical(trialRow, "FullInterfererChannelTruthUsed", false));
            traceT.UCIContentMatch(idx) = logical(sixgr.truth.CoupledTruthRuntime.rowLogical(trialRow, "UCIContentMatch", false));
            traceT = sixgr.truth.CoupledTruthRuntime.setStringValueAt(traceT, "Status", idx, ...
                sixgr.truth.CoupledTruthRuntime.rowValue(trialRow, "Status", sixgr.truth.CoupledTruthRuntime.ternaryString(decodeOk, "PASS", "FAIL")));
            traceT.Crash(idx) = logical(sixgr.truth.CoupledTruthRuntime.rowLogical(trialRow, "Crash", false));
            traceT = sixgr.truth.CoupledTruthRuntime.setStringValueAt(traceT, "CrashSource", idx, ...
                sixgr.truth.CoupledTruthRuntime.rowValue(trialRow, "CrashSource", ""));
            traceT = sixgr.truth.CoupledTruthRuntime.setStringValueAt(traceT, "CrashMessage", idx, ...
                sixgr.truth.CoupledTruthRuntime.rowValue(trialRow, "CrashMessage", ""));
            traceT = sixgr.truth.CoupledTruthRuntime.setStringValueAt(traceT, "Notes", idx, ...
                sixgr.truth.CoupledTruthRuntime.rowValue(trialRow, "Notes", traceT.Notes(idx)));
            if traceT.Crash(idx)
                traceT = sixgr.truth.CoupledTruthRuntime.setStringValueAt(traceT, "PUCCHGrantState", idx, "waveform_execution_crashed");
            end
        end
        state.PUCCHGrantTraceTable = traceT;
    end

    function state = markPendingFeedbackProcessedByGrantId(state, grantId)
        grantId = string(grantId);
        pending = sixgr.util.structGet(state, "PendingFeedbackTable", table());
        if ~(istable(pending) && ~isempty(pending) && strlength(strtrim(grantId)) > 0 && ...
                ismember("PUCCHGrantId", string(pending.Properties.VariableNames)))
            return;
        end
        mask = string(pending.PUCCHGrantId) == grantId;
        if any(mask)
            pending.Processed(mask) = true;
            state.PendingFeedbackTable = pending;
        end
    end

    function dueSlot = resolveHARQFeedbackDueSlot(state, sourceSlot, numUCIBits)
        sourceSlot = round(double(sourceSlot));
        if ~(isfinite(sourceSlot) && sourceSlot >= 1)
            sourceSlot = round(double(sixgr.util.structGet(state, "CurrentSlot", 1)));
        end
        if ~(isfinite(sourceSlot) && sourceSlot >= 1)
            sourceSlot = 1;
        end
        feedbackDelay = max(1, round(double(sixgr.util.structGet(state, "HARQFeedbackSlots", 4))));
        requestedFormat = double(sixgr.util.structGet(state.CfgMobility, "phy.pucch.format", 2));
        if ~(isfinite(requestedFormat) && any(round(requestedFormat) == [0 1 2 3 4]))
            requestedFormat = 2;
        end
        resolvedFormat = sixgr.truth.CoupledTruthRuntime.resolveCompatiblePUCCHFormat(requestedFormat, numUCIBits);
        requiredSymbols = sixgr.truth.CoupledTruthRuntime.ternaryNumeric(resolvedFormat >= 2, 2, 4);
        nominalDueSlot = sourceSlot + feedbackDelay;
        slotsPerFrame = max(1, round(double(sixgr.util.structGet(state, "SlotsPerFrame", ...
            sixgr.util.structGet(state.CfgMobility, "phy.numerology.slotsPerFrame", 10)))));
        maxSearchSlots = max(2 * slotsPerFrame, 64);
        for offset = 0:maxSearchSlots
            candidateSlot = nominalDueSlot + offset;
            if sixgr.truth.CoupledTruthRuntime.pucchSlotCanCarrySymbols(state, candidateSlot, requiredSymbols)
                dueSlot = double(candidateSlot);
                return;
            end
        end
        error("sixgr:truth:PUCCHNoValidFeedbackOccasion", ...
            "No TDD UL slot with %d symbols was found for HARQ feedback at or after nominal slot %d.", ...
            round(double(requiredSymbols)), round(double(nominalDueSlot)));
    end

    function tf = pucchSlotCanCarrySymbols(state, dueSlot, requiredSymbols)
        tf = false;
        if ~(isfinite(double(dueSlot)) && isfinite(double(requiredSymbols)) && double(requiredSymbols) >= 1)
            return;
        end
        [~, allowUL, ~, partition] = sixgr.truth.CoupledTruthRuntime.slotDuplexState( ...
            sixgr.util.structGet(state, "CfgMobility", struct()), dueSlot);
        ulAlloc = sixgr.util.structGet(partition, "ULSymbolAllocation", [0 0]);
        ulSymbols = round(double(sixgr.truth.CoupledTruthRuntime.secondNumeric(ulAlloc, 0)));
        tf = logical(allowUL) && ulSymbols >= round(double(requiredSymbols));
    end

    function [symbolStart, valid, note] = fitPUCCHSymbolsToULPartition(state, dueSlot, requestedSymbolStart, numSym)
        symbolStart = double(requestedSymbolStart);
        valid = false;
        note = "tdd_ul_symbol_partition_not_checked";
        dueSlot = double(dueSlot);
        numSym = max(1, round(double(numSym)));
        if ~(isfinite(dueSlot) && isfinite(numSym))
            symbolStart = NaN;
            note = "invalid_due_slot_or_symbol_count";
            return;
        end
        [~, allowUL, slotLabel, partition] = sixgr.truth.CoupledTruthRuntime.slotDuplexState( ...
            sixgr.util.structGet(state, "CfgMobility", struct()), dueSlot);
        ulAlloc = sixgr.util.structGet(partition, "ULSymbolAllocation", [0 0]);
        ulStart = max(0, round(double(sixgr.truth.CoupledTruthRuntime.firstNumeric(ulAlloc, 0))));
        ulCount = max(0, round(double(sixgr.truth.CoupledTruthRuntime.secondNumeric(ulAlloc, 0))));
        if ~(logical(allowUL) && ulCount >= numSym)
            symbolStart = NaN;
            note = "tdd_slot_has_insufficient_ul_symbols_for_resolved_pucch_format";
            return;
        end
        symbolsPerSlot = max(1, round(double(sixgr.util.structGet(state.CfgMobility, "phy.numerology.symbolsPerSlot", 14))));
        ulEndExclusive = min(symbolsPerSlot, ulStart + ulCount);
        requestedStart = round(double(requestedSymbolStart));
        if ~(isfinite(requestedStart))
            requestedStart = ulEndExclusive - numSym;
        end
        fittedStart = max(ulStart, min(requestedStart, ulEndExclusive - numSym));
        symbolStart = double(fittedStart);
        valid = true;
        if fittedStart ~= requestedStart
            note = "pucch_symbol_allocation_shifted_to_fit_tdd_ul_partition";
        elseif upper(string(slotLabel)) == "S"
            note = "pucch_symbol_allocation_inside_special_slot_ul_partition";
        else
            note = "pucch_symbol_allocation_inside_ul_partition";
        end
    end

    function resource = resolvePUCCHResourceAssignment(state, feedbackRow)
        if istable(feedbackRow) && height(feedbackRow) >= 1
            row = feedbackRow(1, :);
            servingCell = double(sixgr.truth.CoupledTruthRuntime.rowValue(row, "ServingCell", NaN));
            rnti = double(sixgr.truth.CoupledTruthRuntime.rowValue(row, "RNTI", NaN));
            dueSlot = double(sixgr.truth.CoupledTruthRuntime.rowValue(row, "DueSlot", sixgr.util.structGet(state, "CurrentSlot", NaN)));
            expectedAck = sixgr.truth.CoupledTruthRuntime.rowExpectedPUCCHAck(row);
            numUCIBits = max(1, round(double(sixgr.truth.CoupledTruthRuntime.rowValue(row, "UCIBitCount", ...
                sixgr.truth.CoupledTruthRuntime.ternaryNumeric(expectedAck, 1, 1)))));
        else
            row = feedbackRow;
            servingCell = double(sixgr.util.structGet(row, "ServingCell", NaN));
            rnti = double(sixgr.util.structGet(row, "RNTI", NaN));
            dueSlot = double(sixgr.util.structGet(row, "DueSlot", sixgr.util.structGet(state, "CurrentSlot", NaN)));
            expectedAck = sixgr.truth.CoupledTruthRuntime.rowExpectedPUCCHAck(row);
            numUCIBits = max(1, round(double(sixgr.util.structGet(row, "UCIBitCount", ...
                sixgr.truth.CoupledTruthRuntime.ternaryNumeric(expectedAck, 1, 1)))));
        end
        requestedFormat = double(sixgr.util.structGet(state.CfgMobility, "phy.pucch.format", 2));
        if ~(isfinite(requestedFormat) && any(round(requestedFormat) == [0 1 2 3 4]))
            requestedFormat = 2;
        end
        resolvedFormat = sixgr.truth.CoupledTruthRuntime.resolveCompatiblePUCCHFormat(requestedFormat, numUCIBits);
        prbCount = sixgr.truth.CoupledTruthRuntime.ternaryNumeric(resolvedFormat >= 2, 2, 1);
        numSym = sixgr.truth.CoupledTruthRuntime.ternaryNumeric(resolvedFormat >= 2, 2, 4);
        symbolStart = sixgr.truth.CoupledTruthRuntime.ternaryNumeric(resolvedFormat >= 2, 12, 10);
        if resolvedFormat >= 2
            symbolStart = min(symbolStart, 14 - numSym);
        end
        [symbolStart, resourceValid, resourceNote] = ...
            sixgr.truth.CoupledTruthRuntime.fitPUCCHSymbolsToULPartition(state, dueSlot, symbolStart, numSym);
        numRB = max(1, round(double(sixgr.util.structGet(state, "NumRB", 52))));
        prbSpan = max(1, min(numRB, round(prbCount)));
        prbMod = max(1, numRB - prbSpan + 1);
        prbStart = mod(max(0, round(rnti) - 1) + 7 * max(0, round(servingCell) - 1), prbMod);
        if resourceValid
            symbolToken = string(round(symbolStart)) + ":" + string(round(numSym));
        else
            symbolToken = "invalid:" + string(round(numSym));
        end
        resourceId = "pucch:cell=" + string(round(servingCell)) + ...
            ":slot=" + string(round(dueSlot)) + ...
            ":rnti=" + string(round(rnti)) + ...
            ":reqfmt=" + string(round(requestedFormat)) + ...
            ":resfmt=" + string(round(resolvedFormat)) + ...
            ":prb=" + string(round(prbStart)) + ":" + string(round(prbSpan)) + ...
            ":sym=" + symbolToken;
        resource = struct( ...
            "RequestedFormat", double(requestedFormat), ...
            "ResolvedFormat", double(resolvedFormat), ...
            "PRBStart", double(prbStart), ...
            "PRBCount", double(prbSpan), ...
            "SymbolStart", double(symbolStart), ...
            "NumSymbols", double(numSym), ...
            "ResourceId", char(resourceId), ...
            "UCIType", "harq_ack", ...
            "FormatAdaptationReason", char(sixgr.truth.CoupledTruthRuntime.resolvePUCCHFormatAdaptationReason(requestedFormat, resolvedFormat, numUCIBits)), ...
            "ControlResourceValidity", logical(resourceValid), ...
            "ControlResourceReason", char(resourceNote), ...
            "ControlResourceSource", "runtime_deterministic_pucch_resource_assignment_tdd_ul_symbol_checked");
    end

    function bundle = buildPUCCHInterferenceBundle(state, feedbackRow)
        bundle = struct([]);
        mode = lower(strtrim(string(sixgr.util.structGet(state.CfgMobility, "run.interferenceExecutionMode", "none"))));
        if mode ~= "full_per_link_channel_waveform_sum"
            return;
        end
        grants = sixgr.util.structGet(state, "PUCCHGrantTraceTable", table());
        if ~(istable(grants) && ~isempty(grants) && istable(feedbackRow) && height(feedbackRow) >= 1)
            return;
        end
        currentRow = feedbackRow(1, :);
        currentUE = double(sixgr.truth.CoupledTruthRuntime.rowValue(currentRow, "UEIndex", NaN));
        currentServingCell = double(sixgr.truth.CoupledTruthRuntime.rowValue(currentRow, "ServingCell", NaN));
        dueSlot = double(sixgr.truth.CoupledTruthRuntime.rowValue(currentRow, "ScheduledAbsoluteSlot", ...
            sixgr.truth.CoupledTruthRuntime.rowValue(currentRow, "DueSlot", NaN)));
        if ~isfinite(dueSlot)
            return;
        end
        mask = ~logical(grants.GrantExecutedFlag) & abs(double(grants.ScheduledAbsoluteSlot) - dueSlot) < 1e-9;
        if ismember("UEIndex", string(grants.Properties.VariableNames)) && isfinite(currentUE)
            mask = mask & abs(double(grants.UEIndex) - currentUE) > 1e-9;
        end
        peers = grants(mask, :);
        if isempty(peers)
            return;
        end
        count = 0;
        for i = 1:height(peers)
            peer = peers(i, :);
            if ~sixgr.truth.CoupledTruthRuntime.pucchResourcesOverlap(currentRow, peer)
                continue;
            end
            ueIdx = round(double(sixgr.truth.CoupledTruthRuntime.rowValue(peer, "UEIndex", NaN)));
            if ~(isfinite(ueIdx) && ueIdx >= 1 && ueIdx <= double(sixgr.util.structGet(state, "NumUsers", 0)))
                continue;
            end
            if ~(isfinite(currentServingCell) && currentServingCell >= 1 && ...
                    currentServingCell <= size(state.LargeScaleState.Pathloss_dB, 2))
                continue;
            end
            if ~(ueIdx <= size(state.LargeScaleState.Pathloss_dB, 1))
                continue;
            end
            [victimBsEntry, victimUeEntry] = sixgr.truth.CoupledTruthRuntime.runtimeAntennaEntriesForLink( ...
                state, max(1, round(double(currentUE))), currentServingCell);
            cfgI = state.CfgMobility;
            [cfgI, ~] = sixgr.truth.CoupledTruthRuntime.applyUserContextImpl(cfgI, state, ueIdx, "UL");
            cfgI = sixgr.util.structSet(cfgI, "phy.rnti", double(sixgr.truth.CoupledTruthRuntime.rowValue(peer, "RNTI", NaN)));
            cfgI = sixgr.util.structSet(cfgI, "phy.pucch.enable", true);
            prbStart = double(sixgr.truth.CoupledTruthRuntime.rowValue(peer, "PUCCHPRBStart", NaN));
            prbCount = max(1, round(double(sixgr.truth.CoupledTruthRuntime.rowValue(peer, "PUCCHPRBCount", 1))));
            if isfinite(prbStart)
                cfgI = sixgr.util.structSet(cfgI, "phy.pucch.PRBSet", double(prbStart) + (0:max(prbCount - 1, 0)));
            end
            symStart = double(sixgr.truth.CoupledTruthRuntime.rowValue(peer, "PUCCHSymbolStart", NaN));
            numSym = max(1, round(double(sixgr.truth.CoupledTruthRuntime.rowValue(peer, "PUCCHNumSymbols", 1))));
            if isfinite(symStart)
                cfgI = sixgr.util.structSet(cfgI, "phy.pucch.SymbolAllocation", [double(symStart) numSym]);
            end
            requestedFormat = double(sixgr.truth.CoupledTruthRuntime.rowValue(peer, "ResolvedFormat", ...
                sixgr.truth.CoupledTruthRuntime.rowValue(peer, "RequestedFormat", sixgr.util.structGet(cfgI, "phy.pucch.format", NaN))));
            if isfinite(requestedFormat)
                cfgI = sixgr.util.structSet(cfgI, "phy.pucch.format", requestedFormat);
            end
            count = count + 1;
            bundle(count).SignalType = "PUCCH"; %#ok<AGROW>
            bundle(count).Cfg = cfgI; %#ok<AGROW>
            bundle(count).Seed = double(sixgr.util.structGet(cfgI, "run.seed", NaN)) + double(dueSlot) + double(count); %#ok<AGROW>
            bundle(count).ServingCell = double(sixgr.truth.CoupledTruthRuntime.rowValue(peer, "ServingCell", NaN)); %#ok<AGROW>
            bundle(count).VictimUEIndex = double(currentUE); %#ok<AGROW>
            bundle(count).InterfererUEIndex = double(ueIdx); %#ok<AGROW>
            bundle(count).VictimServingCell = double(currentServingCell); %#ok<AGROW>
            bundle(count).VictimRxPower_dBm = double(state.LargeScaleState.RxPower_dBm(ueIdx, currentServingCell)); %#ok<AGROW>
            bundle(count).VictimRSRP_dBm = double(state.LargeScaleState.RSRP_dBm(ueIdx, currentServingCell)); %#ok<AGROW>
            bundle(count).BasePathloss_dB = double(state.LargeScaleState.BasePathloss_dB(ueIdx, currentServingCell)); %#ok<AGROW>
            bundle(count).Pathloss_dB = double(state.LargeScaleState.Pathloss_dB(ueIdx, currentServingCell)); %#ok<AGROW>
            bundle(count).ShadowFading_dB = double(state.LargeScaleState.Shadow_dB(ueIdx, currentServingCell)); %#ok<AGROW>
            bundle(count).O2I_dB = double(state.LargeScaleState.O2I_dB(ueIdx, currentServingCell)); %#ok<AGROW>
            bundle(count).BeamIndex = double(state.LargeScaleState.BeamIndex(ueIdx, currentServingCell)); %#ok<AGROW>
            bundle(count).BeamGain_dB = double(state.LargeScaleState.BeamGain_dB(ueIdx, currentServingCell)); %#ok<AGROW>
            bundle(count).VictimServingBSAntenna = sixgr.util.structGet(victimBsEntry, "Antenna", struct()); %#ok<AGROW>
            bundle(count).VictimServingBSAntennaMeta = sixgr.util.structGet(victimBsEntry, "Metadata", struct()); %#ok<AGROW>
            bundle(count).VictimUEAntenna = sixgr.util.structGet(victimUeEntry, "Antenna", struct()); %#ok<AGROW>
            bundle(count).VictimUEAntennaMeta = sixgr.util.structGet(victimUeEntry, "Metadata", struct()); %#ok<AGROW>
            bundle(count).InterferenceMode = char(string(sixgr.truth.CoupledTruthRuntime.resolveInterferenceExecutionMode(cfgI, state.MultiUser))); %#ok<AGROW>
            bundle(count).ExpectedUCIBits = int8(logical(sixgr.truth.CoupledTruthRuntime.rowExpectedPUCCHAck(peer))); %#ok<AGROW>
            bundle(count).RequestedFormat = double(sixgr.truth.CoupledTruthRuntime.rowValue(peer, "RequestedFormat", requestedFormat)); %#ok<AGROW>
            bundle(count).ResolvedFormat = double(requestedFormat); %#ok<AGROW>
            bundle(count).UCIBitCount = double(sixgr.truth.CoupledTruthRuntime.rowValue(peer, "UCIBitCount", 1)); %#ok<AGROW>
            bundle(count).RNTI = double(sixgr.truth.CoupledTruthRuntime.rowValue(peer, "RNTI", NaN)); %#ok<AGROW>
            bundle(count).ControlResourceSource = char(string(sixgr.truth.CoupledTruthRuntime.rowValue(peer, "ControlResourceSource", "runtime_deterministic_pucch_resource_assignment"))); %#ok<AGROW>
            bundle(count).PUCCHResourceId = char(string(sixgr.truth.CoupledTruthRuntime.rowValue(peer, "PUCCHResourceId", ""))); %#ok<AGROW>
            [contributionWaveform, contributionMeta] = sixgr.truth.CoupledTruthRuntime.buildPUCCHSharedSlotContribution( ...
                state, cfgI, bundle(count), ueIdx, currentServingCell, requestedFormat);
            bundle(count).SharedSlotContributionWaveform = contributionWaveform; %#ok<AGROW>
            bundle(count).ContributionSampleRate_Hz = double(contributionMeta.SampleRate_Hz); %#ok<AGROW>
            bundle(count).ContributionRxPower_dBm = double(contributionMeta.RxPower_dBm); %#ok<AGROW>
            bundle(count).ContributionSource = char(contributionMeta.Source); %#ok<AGROW>
            bundle(count).ChannelObjectSource = char(contributionMeta.ChannelObjectSource); %#ok<AGROW>
            bundle(count).ChannelObjectClass = char(contributionMeta.ChannelObjectClass); %#ok<AGROW>
            bundle(count).ChannelArrayHandlingStatus = char(contributionMeta.ChannelArrayHandlingStatus); %#ok<AGROW>
            bundle(count).ChannelArrayHandlingBlocker = char(contributionMeta.ChannelArrayHandlingBlocker); %#ok<AGROW>
            bundle(count).ChannelGeometryCouplingLevel = char(contributionMeta.ChannelGeometryCouplingLevel); %#ok<AGROW>
            bundle(count).GeometryAdapterType = char(contributionMeta.GeometryAdapterType); %#ok<AGROW>
            bundle(count).GeometryAdapterSource = char(contributionMeta.GeometryAdapterSource); %#ok<AGROW>
            bundle(count).GeometryAdapterLimitation = char(contributionMeta.GeometryAdapterLimitation); %#ok<AGROW>
            bundle(count).GeometryAdapterPortMapping = char(contributionMeta.GeometryAdapterPortMapping); %#ok<AGROW>
            bundle(count).ChannelUsesSameRuntimeAntennaAssumptions = logical(contributionMeta.ChannelUsesSameRuntimeAntennaAssumptions); %#ok<AGROW>
        end
    end

    function [contributionWaveform, meta] = buildPUCCHSharedSlotContribution(state, cfgIn, bundleEntry, ueIdx, victimCell, requestedFormat)
        expectedBits = int8(logical(sixgr.util.structGet(bundleEntry, "ExpectedUCIBits", int8(1))));
        if isempty(expectedBits)
            expectedBits = int8(1);
        end
        rnti = double(sixgr.util.structGet(bundleEntry, "RNTI", NaN));
        txArgs = {"Format", double(requestedFormat)};
        if isfinite(rnti)
            txArgs = [txArgs {"RNTI", rnti}]; %#ok<AGROW>
        end
        [tx, txInfo] = sixgr.phy.ul.PUCCH_Tx(cfgIn, expectedBits, txArgs{:});
        sampleRateHz = sixgr.truth.CoupledTruthRuntime.resolvePUCCHContributionSampleRate(tx, txInfo);
        cfgContribution = sixgr.truth.CoupledTruthRuntime.configurePUCCHContributionLinkBudget( ...
            cfgIn, state, ueIdx, victimCell, bundleEntry);
        [contributionWaveform, replay] = sixgr.link.applyWaveformImpairments(tx.Waveform, cfgContribution, sampleRateHz, ...
            "Endpoint", "rx", ...
            "UseLegacyGlobalConfig", true, ...
            "ApplyPA", false, ...
            "ApplyADC", true);
        meta = struct( ...
            "SampleRate_Hz", double(sampleRateHz), ...
            "RxPower_dBm", double(sixgr.util.structGet(replay, "ServingRxPower_dBm", NaN)), ...
            "Source", "runtime_prepropagated_pucch_shared_slot_receiver_contribution", ...
            "ChannelObjectSource", "runtime_large_scale_link_budget_and_rf_chain", ...
            "ChannelObjectClass", "sample_domain_large_scale_pucch_contribution", ...
            "ChannelArrayHandlingStatus", "shared_slot_receiver_contribution_precomputed", ...
            "ChannelArrayHandlingBlocker", "", ...
            "ChannelGeometryCouplingLevel", "runtime_geometry_large_scale_state", ...
            "GeometryAdapterType", "runtime_state", ...
            "GeometryAdapterSource", "CoupledTruthRuntime.buildPUCCHSharedSlotContribution", ...
            "GeometryAdapterLimitation", "large_scale_sample_domain_contribution;small_scale_pucch_peer_channel_reuse_not_modeled_here", ...
            "GeometryAdapterPortMapping", "contribution_waveform_columns_preserved", ...
            "ChannelUsesSameRuntimeAntennaAssumptions", true);
    end

    function sampleRateHz = resolvePUCCHContributionSampleRate(tx, txInfo)
        sampleRateHz = double(sixgr.util.structGet(txInfo, "OFDMInfo.SampleRate", NaN));
        if ~(isfinite(sampleRateHz) && sampleRateHz > 0)
            sampleRateHz = double(sixgr.util.structGet(txInfo, "OFDM.SampleRate", NaN));
        end
        if ~(isfinite(sampleRateHz) && sampleRateHz > 0)
            carrier = sixgr.util.structGet(tx, "Carrier", []);
            if ~isempty(carrier) && exist("nrOFDMInfo", "file") == 2
                ofdmInfo = nrOFDMInfo(carrier);
                sampleRateHz = double(sixgr.util.structGet(ofdmInfo, "SampleRate", NaN));
            end
        end
        if ~(isfinite(sampleRateHz) && sampleRateHz > 0)
            error("sixgr:truth:PUCCHContributionSampleRateUnavailable", ...
                "Cannot build shared-slot PUCCH contribution without a finite OFDM sample rate.");
        end
    end

    function cfgOut = configurePUCCHContributionLinkBudget(cfgIn, state, ueIdx, victimCell, bundleEntry)
        cfgOut = cfgIn;
        userMeta = sixgr.util.structGet(cfgOut, "lls6g.userContext", struct());
        if ~(isstruct(userMeta) && ~isempty(fieldnames(userMeta)))
            userMeta = struct();
        end
        ls = sixgr.util.structGet(state, "LargeScaleState", struct());
        userMeta.RuntimeCurrentDirection = "UL";
        userMeta.Direction = "UL";
        userMeta.RuntimeUEIndex = double(ueIdx);
        userMeta.RuntimeServingCell = double(victimCell);
        userMeta.RuntimeServingCellIndex = double(victimCell);
        userMeta.RuntimeServingBasePathloss_dB = sixgr.truth.CoupledTruthRuntime.largeScaleValue(ls, "BasePathloss_dB", ueIdx, victimCell);
        userMeta.RuntimeServingPathloss_dB = sixgr.truth.CoupledTruthRuntime.largeScaleValue(ls, "Pathloss_dB", ueIdx, victimCell);
        userMeta.RuntimeServingShadowFading_dB = sixgr.truth.CoupledTruthRuntime.largeScaleValue(ls, "Shadow_dB", ueIdx, victimCell);
        userMeta.RuntimeServingO2I_dB = sixgr.truth.CoupledTruthRuntime.largeScaleValue(ls, "O2I_dB", ueIdx, victimCell);
        userMeta.RuntimeServingRSRP_dBm = sixgr.truth.CoupledTruthRuntime.largeScaleValue(ls, "RSRP_dBm", ueIdx, victimCell);
        userMeta.RuntimeServingRxPower_dBm = sixgr.truth.CoupledTruthRuntime.largeScaleValue(ls, "RxPower_dBm", ueIdx, victimCell);
        userMeta.RuntimeChannelComplianceMode = "runtime_coupled_shared_slot_pucch_contribution";
        userMeta.RuntimePathlossModelSource = "CoupledTruthRuntime.LargeScaleState";
        userMeta.RuntimePathlossComplianceStatus = "applied";
        userMeta.RuntimeFallbackUsedForPathloss = false;
        if isfield(bundleEntry, "VictimServingBSAntenna")
            userMeta.RuntimeServingBSAntenna = bundleEntry.VictimServingBSAntenna;
        end
        if isfield(bundleEntry, "VictimUEAntenna")
            userMeta.RuntimeUEAntenna = bundleEntry.VictimUEAntenna;
        end
        cfgOut = sixgr.util.structSet(cfgOut, "lls6g.userContext", userMeta);
        cfgOut = sixgr.util.structSet(cfgOut, "run.noiseOperatingMode", "receiver_noise_figure_thermal_noise");
    end

    function value = largeScaleValue(ls, fieldName, rowIdx, colIdx)
        value = NaN;
        if ~(isstruct(ls) && isfield(ls, char(fieldName)))
            return;
        end
        M = double(ls.(char(fieldName)));
        rowIdx = round(double(rowIdx));
        colIdx = round(double(colIdx));
        if isfinite(rowIdx) && isfinite(colIdx) && rowIdx >= 1 && colIdx >= 1 && ...
                rowIdx <= size(M, 1) && colIdx <= size(M, 2)
            value = double(M(rowIdx, colIdx));
        end
    end

    function tf = pucchResourcesOverlap(a, b)
        tf = false;
        [aPrb0, aPrbCount, aSym0, aSymCount] = sixgr.truth.CoupledTruthRuntime.pucchResourceExtents(a);
        [bPrb0, bPrbCount, bSym0, bSymCount] = sixgr.truth.CoupledTruthRuntime.pucchResourceExtents(b);
        vals = [aPrb0, aPrbCount, aSym0, aSymCount, bPrb0, bPrbCount, bSym0, bSymCount];
        if any(~isfinite(vals)) || any([aPrbCount, aSymCount, bPrbCount, bSymCount] <= 0)
            return;
        end
        aPrbEnd = aPrb0 + aPrbCount;
        bPrbEnd = bPrb0 + bPrbCount;
        aSymEnd = aSym0 + aSymCount;
        bSymEnd = bSym0 + bSymCount;
        tf = max(aPrb0, bPrb0) < min(aPrbEnd, bPrbEnd) && ...
            max(aSym0, bSym0) < min(aSymEnd, bSymEnd);
    end

    function [prbStart, prbCount, symStart, symCount] = pucchResourceExtents(row)
        prbStart = double(sixgr.truth.CoupledTruthRuntime.rowValue(row, "PUCCHPRBStart", NaN));
        prbCount = double(sixgr.truth.CoupledTruthRuntime.rowValue(row, "PUCCHPRBCount", NaN));
        symStart = double(sixgr.truth.CoupledTruthRuntime.rowValue(row, "PUCCHSymbolStart", NaN));
        symCount = double(sixgr.truth.CoupledTruthRuntime.rowValue(row, "PUCCHNumSymbols", NaN));
    end

    function ack = rowExpectedPUCCHAck(row)
        ack = logical(sixgr.truth.CoupledTruthRuntime.rowLogical(row, "Ack", false));
        if ack
            return;
        end
        ack = logical(sixgr.truth.CoupledTruthRuntime.rowLogical(row, "ExpectedAck", false));
    end

    function fmt = resolveCompatiblePUCCHFormat(requestedFormat, numBits)
        fmt = double(requestedFormat);
        numBits = max(0, round(double(numBits)));
        if ~(isfinite(fmt) && any(round(fmt) == [0 1 2 3 4]))
            fmt = sixgr.truth.CoupledTruthRuntime.ternaryNumeric(numBits <= 2, 1, 2);
            return;
        end
        fmt = round(fmt);
        if numBits <= 2 && any(fmt == [2 3 4])
            fmt = 1;
        elseif numBits > 2 && any(fmt == [0 1])
            fmt = 2;
        end
    end

    function reason = resolvePUCCHFormatAdaptationReason(requestedFormat, resolvedFormat, numBits)
        reason = "";
        requestedFormat = double(requestedFormat);
        resolvedFormat = double(resolvedFormat);
        numBits = max(0, round(double(numBits)));
        if ~(isfinite(requestedFormat) && isfinite(resolvedFormat)) || requestedFormat == resolvedFormat
            return;
        end
        if numBits <= 2 && any(requestedFormat == [2 3 4]) && resolvedFormat == 1
            reason = "uci_payload_size_demoted_to_short_format";
        elseif numBits > 2 && any(requestedFormat == [0 1]) && resolvedFormat == 2
            reason = "uci_payload_size_promoted_to_long_format";
        else
            reason = "runtime_format_compatibility_adjustment";
        end
    end

    function bits = normalizeUCIBits(rawBits)
        bits = int8([]);
        if isempty(rawBits)
            return;
        end
        if iscell(rawBits)
            if isempty(rawBits)
                return;
            end
            rawBits = rawBits{1};
        end
        if islogical(rawBits)
            bits = int8(rawBits(:));
        elseif isnumeric(rawBits)
            bits = int8(logical(rawBits(:)));
        end
    end

    function token = uciBitVectorString(bits)
        bits = sixgr.truth.CoupledTruthRuntime.normalizeUCIBits(bits);
        if isempty(bits)
            token = "";
        else
            token = char("[" + strjoin(string(double(bits(:).')), "|") + "]");
        end
    end

    function token = uciBitErrorVectorString(expectedBits, decodedBits)
        expectedBits = sixgr.truth.CoupledTruthRuntime.normalizeUCIBits(expectedBits);
        decodedBits = sixgr.truth.CoupledTruthRuntime.normalizeUCIBits(decodedBits);
        n = max(numel(expectedBits), numel(decodedBits));
        if n < 1
            token = "";
            return;
        end
        errs = ones(n, 1, "int8");
        nCompare = min(numel(expectedBits), numel(decodedBits));
        if nCompare > 0
            errs(1:nCompare) = int8(expectedBits(1:nCompare) ~= decodedBits(1:nCompare));
        end
        token = sixgr.truth.CoupledTruthRuntime.uciBitVectorString(errs);
    end

    function n = pucchUCICRCBitCount(numBits, resolvedFormat)
        numBits = max(0, round(double(numBits)));
        resolvedFormat = round(double(resolvedFormat));
        if isfinite(resolvedFormat) && resolvedFormat >= 2 && numBits >= 12
            n = 6;
        else
            n = 0;
        end
    end

    function n = pucchUCICodedBitCount(trial, resolvedFormat)
        n = NaN;
        tx = sixgr.util.structGet(trial, "Tx", struct());
        if isstruct(tx)
            codedUCI = sixgr.util.structGet(tx, "CodedUCI", []);
            if ~isempty(codedUCI)
                n = double(numel(codedUCI));
                return;
            end
        end
        resolvedFormat = round(double(resolvedFormat));
        if isfinite(resolvedFormat) && resolvedFormat <= 1
            n = 0;
        end
    end

    function grantId = composePUCCHGrantId(state, row)
        dueSlot = double(sixgr.truth.CoupledTruthRuntime.rowValue(row, "DueSlot", ...
            sixgr.truth.CoupledTruthRuntime.rowValue(row, "ScheduledAbsoluteSlot", NaN)));
        sourceSlot = double(sixgr.truth.CoupledTruthRuntime.rowValue(row, "SourceSlot", NaN));
        ueIdx = double(sixgr.truth.CoupledTruthRuntime.rowValue(row, "UEIndex", NaN));
        rnti = double(sixgr.truth.CoupledTruthRuntime.rowValue(row, "RNTI", NaN));
        harqId = double(sixgr.truth.CoupledTruthRuntime.rowValue(row, "HarqID", NaN));
        servingCell = double(sixgr.truth.CoupledTruthRuntime.rowValue(row, "ServingCell", NaN));
        feedbackDirection = upper(string(sixgr.truth.CoupledTruthRuntime.rowValue(row, "Direction", "")));
        if ismissing(feedbackDirection)
            feedbackDirection = "";
        end
        if strlength(strtrim(feedbackDirection)) == 0
            feedbackDirection = "DL";
        end
        grantId = sprintf("pucchgrant:fbdir=%s:due=%g:src=%g:ue=%g:rnti=%g:harq=%g:cell=%g", ...
            char(feedbackDirection), dueSlot, sourceSlot, ueIdx, rnti, harqId, servingCell);
    end

    function frameIdx = absoluteSlotToFrame(state, absoluteSlot)
        frameIdx = NaN;
        absoluteSlot = double(absoluteSlot);
        if ~(isfinite(absoluteSlot) && absoluteSlot >= 1)
            return;
        end
        slotsPerFrame = double(sixgr.util.structGet(state.CfgMobility, "phy.numerology.slotsPerFrame", ...
            sixgr.util.structGet(state.CfgMobility, "phy.carrier.SlotsPerFrame", NaN)));
        if ~(isfinite(slotsPerFrame) && slotsPerFrame >= 1)
            slotsPerFrame = 10;
        end
        frameIdx = 1 + floor((absoluteSlot - 1) ./ slotsPerFrame);
    end

    function value = firstNumeric(vals, defaultValue)
        vals = double(vals(:));
        vals = vals(isfinite(vals));
        if isempty(vals)
            value = double(defaultValue);
        else
            value = double(vals(1));
        end
    end

    function value = firstFiniteScalar(varargin)
        value = NaN;
        for ii = 1:nargin
            candidate = varargin{ii};
            if isnumeric(candidate) && isscalar(candidate) && isfinite(candidate)
                value = double(candidate);
                return;
            end
        end
    end

    function value = firstString(raw, defaultValue)
        str = string(raw);
        str = reshape(str, [], 1);
        str = str(~ismissing(str));
        if isempty(str)
            value = char(string(defaultValue));
        else
            value = char(str(1));
        end
    end

    function T = localAssignTraceTextValue(T, fieldName, idx, rawValue)
        if ~(istable(T) && ismember(fieldName, string(T.Properties.VariableNames)))
            return;
        end
        textValue = string(sixgr.truth.CoupledTruthRuntime.firstString(rawValue, ""));
        if isstring(T.(fieldName))
            T.(fieldName)(idx) = textValue;
        elseif iscell(T.(fieldName))
            T.(fieldName)(idx) = {char(textValue)};
        elseif iscategorical(T.(fieldName))
            T.(fieldName)(idx) = categorical(textValue);
        else
            T.(fieldName)(idx) = textValue;
        end
    end

    function value = ternaryNumeric(cond, trueValue, falseValue)
        if cond
            value = double(trueValue);
        else
            value = double(falseValue);
        end
    end

    function value = secondNumeric(vals, defaultValue)
        vals = double(vals(:));
        vals = vals(isfinite(vals));
        if numel(vals) < 2
            value = double(defaultValue);
        else
            value = double(vals(2));
        end
    end

    function value = scalarOrDefault(raw, defaultValue)
        vals = double(raw);
        vals = vals(isfinite(vals));
        if isempty(vals)
            value = double(defaultValue);
        else
            value = double(vals(1));
        end
    end

    function value = configLogicalOrDefault(cfg, names, defaultValue)
        value = logical(defaultValue);
        for ii = 1:numel(names)
            raw = sixgr.util.structGet(cfg, char(string(names(ii))), []);
            if isempty(raw) || isstruct(raw)
                continue;
            end
            if islogical(raw)
                value = logical(raw(1));
                return;
            end
            if isnumeric(raw)
                vals = double(raw(:));
                vals = vals(isfinite(vals));
                if ~isempty(vals)
                    value = logical(vals(1) ~= 0);
                    return;
                end
                continue;
            end
            token = lower(strtrim(string(raw)));
            token = token(~ismissing(token) & strlength(token) > 0);
            if isempty(token)
                continue;
            end
            if any(token(1) == ["true", "yes", "on", "1"])
                value = true;
                return;
            end
            if any(token(1) == ["false", "no", "off", "0"])
                value = false;
                return;
            end
        end
    end

    function value = configStringOrDefault(cfg, names, defaultValue)
        value = char(string(defaultValue));
        for ii = 1:numel(names)
            raw = sixgr.util.structGet(cfg, char(string(names(ii))), []);
            if isempty(raw) || isstruct(raw)
                continue;
            end
            token = string(raw);
            token = token(~ismissing(token));
            if isempty(token)
                continue;
            end
            token = strtrim(token(1));
            if strlength(token) > 0
                value = char(token);
                return;
            end
        end
    end

    function token = composeGrantContextId(grant, direction, state, ueIdx)
        if nargin < 4
            ueIdx = NaN;
        end
        if nargin < 3 || ~isstruct(state)
            state = struct();
        end
        if nargin < 2
            direction = "";
        end
        dirToken = upper(string(direction));
        frameToken = double(sixgr.util.structGet(grant, "Frame", sixgr.util.structGet(state, "CurrentFrame", NaN)));
        slotToken = double(sixgr.util.structGet(grant, "Slot", sixgr.util.structGet(state, "CurrentSlot", NaN)));
        ueToken = double(sixgr.util.structGet(grant, "UEIndex", ueIdx));
        rntiToken = double(sixgr.util.structGet(grant, "RNTI", NaN));
        cellToken = double(sixgr.util.structGet(grant, "ServingCell", NaN));
        harqToken = double(sixgr.util.structGet(sixgr.util.structGet(grant, "HARQ", struct()), "HarqID", NaN));
        token = char("dir=" + dirToken + ...
            ";frame=" + string(frameToken) + ...
            ";slot=" + string(slotToken) + ...
            ";ue=" + string(ueToken) + ...
            ";rnti=" + string(rntiToken) + ...
            ";cell=" + string(cellToken) + ...
            ";harq=" + string(harqToken));
    end

    function value = ternaryString(tf, trueValue, falseValue)
        if logical(tf)
            value = char(string(trueValue));
        else
            value = char(string(falseValue));
        end
    end

end
end
