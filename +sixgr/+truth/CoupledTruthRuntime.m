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
        state.ControlTrials = struct("PBCH", sixgr.util.structGet(controlTrials, "PBCH", table()), "PRACH", sixgr.util.structGet(controlTrials, "PRACH", table()), "PDCCH", sixgr.util.structGet(controlTrials, "PDCCH", table()), "PUCCH", sixgr.util.structGet(controlTrials, "PUCCH", table()), "SRS", sixgr.util.structGet(controlTrials, "SRS", table()), "TRS", sixgr.util.structGet(controlTrials, "TRS", table()));
        state.InitialAccessLifecycleTraceTable = struct2table(repmat(sixgr.truth.CoupledTruthRuntime.emptyInitialAccessLifecycleRow(), 0, 1));
        state.ControlGating = sixgr.truth.CoupledTruthRuntime.resolveControlGatingConfig(cfgMob, multiUser);
        state.CellAcquisitionState = repmat(string(state.ControlGating.PBCHInitialState), nUsers, 1);
        state.AccessState = repmat(string(state.ControlGating.PRACHInitialState), nUsers, 1);
        state.LastPDCCHStatus = repmat("not_attempted", nUsers, 1);
        state.SRSValidityState = repmat(string(state.ControlGating.SRSInitialState), nUsers, 1);
        state.CSIValidityState = repmat(string(state.ControlGating.CSIInitialState), nUsers, 1);
        state.ControlEligibility = false(nUsers, 1);
        state.SchedulingEligibility = false(nUsers, 1);
        state.CoverageEligibility = true(nUsers, 1);
        state.CoverageOutageState = repmat("not_evaluated", nUsers, 1);
        state.LastSuccessfulPBCHSlotByUE = nan(nUsers, 1);
        state.LastSuccessfulPRACHSlotByUE = nan(nUsers, 1);
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
        state.LastPBCHSlot = 0;
        state.LastTRSSlot = 0;
        state.DLSchedulers = sixgr.truth.CoupledTruthRuntime.createSchedulers(cfgMob, nCells, "DL", state.DLHarq);
        state.ULSchedulers = sixgr.truth.CoupledTruthRuntime.createSchedulers(cfgMob, nCells, "UL", state.ULHarq);
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

    function state = applySRSTrial(state, ueIdx, trialT)
        state = sixgr.truth.CoupledTruthRuntime.applySRSTrialImpl(state, ueIdx, trialT);
    end

    function state = applyTRSTrial(state, servingCell, trialT)
        state = sixgr.truth.CoupledTruthRuntime.applyTRSTrialImpl(state, servingCell, trialT);
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
            "ControlGatingStateTable", sixgr.truth.CoupledTruthRuntime.buildControlStateTable(state));
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
end

methods(Static, Access=private)
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
        if canonicalSlot > 1 && mobilityEnabled
            [state.UE, state.MobilityModel] = sixgr.scenario.mobility.updatePositions(state.UE, state.CfgMobility, state.SlotDuration_s, state.MobilityModel);
        end
        state = sixgr.truth.CoupledTruthRuntime.enqueueTrafficForFrame(state, canonicalSlot);
        doBeamUpdate = (canonicalSlot == 1) || (mod(canonicalSlot - 1, beamUpdateSlots) == 0);
        if doBeamUpdate
            [state.BeamIdx, state.BeamGain_dB] = sixgr.system.selectBestBeamPerLink( ...
                state.UE.pos_m, state.Layout.bs.pos_m, state.Layout.bs.azim_deg, ...
                state.NBeams, state.BeamSpanDeg, state.BeamMaxGain_dB);
        end
        doProp = (canonicalSlot == 1) || doBeamUpdate || (mod(canonicalSlot - 1, largeScaleUpdateSlots) == 0);
        reuseProp = ~isempty(fieldnames(state.LargeScaleState)) && ~doProp;
        state.LargeScaleState = sixgr.system.buildLargeScaleStateCache( ...
            state.CfgLargeScale, state.Layout, state.UE, state.BeamIdx, state.BeamGain_dB, state.PLModel, ...
            "NumRB", state.NumRB, "PreviousState", state.LargeScaleState, "ReusePropagation", reuseProp);
        [state.CurrentServingIdx, state.CurrentServingMetric_dBm] = sixgr.system.selectServingCellsFromPower(state.LargeScaleState.RSRP_dBm);
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
        servingCell = double(state.CurrentServingIdx(ueIdx));
        if ~(isfinite(servingCell) && servingCell >= 1)
            servingCell = 1;
        end
        userMeta = sixgr.util.structGet(cfgU, "lls6g.userContext", struct());
        userMeta.RuntimeServingCell = servingCell;
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
        if ueIdx <= numel(state.UE.heading_deg)
            userMeta.RuntimeUEHeading_deg = double(state.UE.heading_deg(ueIdx));
        end
        if servingCell <= size(state.Layout.bs.pos_m, 1)
            userMeta.RuntimeServingBSPosition_m = reshape(double(state.Layout.bs.pos_m(servingCell, :)), 1, []);
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
        userMeta.RuntimeTRSRuntimeEvidenceSource = char(string(trsContext.TRSRuntimeEvidenceSource));
        cfgU = sixgr.util.structSet(cfgU, "run.interferenceExecutionMode", char(interferenceMode));
        cfgU = sixgr.util.structSet(cfgU, "run.useAbstractInterferenceModel", false);
        cfgU = sixgr.util.structSet(cfgU, "lls6g.userContext", userMeta);
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
        retx = harq.peekRetx(rnti);
        if isempty(retx)
            context.HARQContext = struct("Direction", char(direction), "UEIndex", double(ueIdx), "RNTI", double(rnti), "IsRetransmission", false, "FeedbackDelaySlots", double(state.HARQFeedbackSlots));
            return;
        end
        pid = double(retx.HARQ.HarqID) + 1;
        prevLLR = [];
        if ueIdx <= size(softBuffers, 1) && pid <= size(softBuffers, 2)
            prevLLR = softBuffers{ueIdx, pid};
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
            scheduler = sixgr.truth.CoupledTruthRuntime.schedulerForDirection(state, direction, cellId);
            if isempty(scheduler)
                continue;
            end
            [cellGrants, ~] = scheduler.schedule(double(state.CurrentSlot), ueStates, budget);
            if isempty(cellGrants)
                continue;
            end
            for gi = 1:numel(cellGrants)
                grant = cellGrants(gi);
                ueIdx = sixgr.truth.CoupledTruthRuntime.resolveUEIndexFromRNTI(state, double(grant.RNTI));
                if ~(isfinite(ueIdx) && ueIdx >= 1)
                    continue;
                end
                grant.UEIndex = double(ueIdx);
                grant.ServingCell = double(cellId);
                grant.Direction = char(direction);
                grant.Slot = double(state.CurrentSlot);
                grant.Frame = double(state.CurrentFrame);
                feedback = sixgr.truth.CoupledTruthRuntime.latestFeedbackForDirection(state, ueIdx, direction);
                if isfinite(double(sixgr.util.structGet(feedback, "CQI", NaN)))
                    grant.CQIUsed = double(feedback.CQI);
                end
                if isfinite(double(sixgr.util.structGet(feedback, "RI", NaN)))
                    grant.RIUsed = double(feedback.RI);
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
                grant.SRSValid = strcmpi(char(string(grant.SRSValidityState)), "valid");
                grant.LastSuccessfulSRSSlot = double(sixgr.truth.CoupledTruthRuntime.numericStateAt(state, "LastSuccessfulSRSSlotByUE", ueIdx, NaN));
                grant.SRSAgeSlots = double(sixgr.truth.CoupledTruthRuntime.srsAgeSlots(state, ueIdx));
                grant.ControlEligible = logical(sixgr.truth.CoupledTruthRuntime.controlLogicalAt(state, "ControlEligibility", ueIdx, true));
                grant.SchedulingEligible = sixgr.truth.CoupledTruthRuntime.resolveSchedulingEligibilityForDirection(state, ueIdx, direction);
                grant.SchedulingBlockedBySRS = logical(grant.ControlEligible && ~grant.SchedulingEligible && grant.SRSGatingActive);
                trsContext = sixgr.truth.CoupledTruthRuntime.resolveTRSRuntimeContext(state, cfg, ueIdx, cellId);
                grant.TRSGatingActive = logical(trsContext.TRSGatingActive);
                grant.TRSValidityState = char(string(trsContext.TRSValidityState));
                grant.TrackingEligibility = logical(trsContext.TrackingEligibility);
                grant.TRSAgeSlots = double(trsContext.TRSAgeSlots);
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
        grantRow = sixgr.truth.CoupledTruthRuntime.buildGrantTraceRow( ...
            sixgr.util.structGet(context, "GrantSnapshot", grant), direction, ...
            sixgr.util.structGet(sixgr.util.structGet(context, "GrantSnapshot", grant), "Slot", state.CurrentSlot), ...
            sixgr.util.structGet(sixgr.util.structGet(context, "GrantSnapshot", grant), "Frame", state.CurrentFrame), ...
            ueIdx, ...
            sixgr.truth.CoupledTruthRuntime.latestFeedbackForDirection(state, ueIdx, direction));
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

        % Keep control-plane trials on both canonical browser-owned
        % air-interface paths and explicit control mirrors; the mirror is
        % diagnostic, while the air-interface path is the browser owner.
        sixgr.truth.CoupledTruthRuntime.writeMirroredTable(layout, "pbch_trials.csv", sixgr.util.structGet(state.ControlTrials, "PBCH", table()));
        sixgr.truth.CoupledTruthRuntime.writeMirroredTable(layout, "prach_trials.csv", sixgr.util.structGet(state.ControlTrials, "PRACH", table()));
        sixgr.truth.CoupledTruthRuntime.writeMirroredTable(layout, "pdcch_trials.csv", sixgr.util.structGet(state.ControlTrials, "PDCCH", table()));
        sixgr.truth.CoupledTruthRuntime.writeMirroredTable(layout, "pucch_trials.csv", sixgr.util.structGet(state.ControlTrials, "PUCCH", table()));
        sixgr.truth.CoupledTruthRuntime.writeMirroredTable(layout, "srs_trials.csv", sixgr.util.structGet(state.ControlTrials, "SRS", table()));
        sixgr.truth.CoupledTruthRuntime.writeMirroredTable(layout, "trs_trials.csv", sixgr.util.structGet(state.ControlTrials, "TRS", table()));
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
        sixgr.util.csvWriteTable(fullfile(layout.PacketFlowCSVDir, "live_pucch_grants.csv"), state.PUCCHGrantTraceTable);
        sixgr.util.csvWriteTable(fullfile(layout.ControlCSVDir, "initial_access_lifecycle_trace.csv"), ...
            sixgr.util.structGet(state, "InitialAccessLifecycleTraceTable", table()));
        sixgr.util.csvWriteTable(fullfile(layout.ReportCSVDir, "initial_access_lifecycle_trace.csv"), ...
            sixgr.util.structGet(state, "InitialAccessLifecycleTraceTable", table()));
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
            state = sixgr.truth.CoupledTruthRuntime.reserveGrantBits(state, ueIdx, direction, tbsBits);
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
        cfgOut = sixgr.util.structSet(cfgOut, "channel.pathlossEnabled", true);
        cfgOut = sixgr.util.structSet(cfgOut, "channel.losEnabled", true);
        cfgOut = sixgr.util.structSet(cfgOut, "channel.shadowFadingEnabled", true);
        cfgOut = sixgr.util.structSet(cfgOut, "channel.pathlossModel", "nrPathLoss");
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
            dueGrantMask = ~logical(grantTrace.GrantExecutedFlag) & ...
                double(grantTrace.ScheduledAbsoluteSlot) <= double(state.CurrentSlot);
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
                harq.onFeedback(double(row.RNTI), double(row.HarqID), observedAck);
                pid = double(row.HarqID) + 1;
                if observedAck && double(row.UEIndex) <= size(buffers, 1) && pid <= size(buffers, 2)
                    buffers{double(row.UEIndex), pid} = [];
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
            latest = sixgr.truth.CoupledTruthRuntime.emptyLatestFeedbackRow();
            latest.Valid = true;
            latest.CQI = double(row.CQI);
            latest.RI = double(row.RI);
            latest.PMI = double(sixgr.truth.CoupledTruthRuntime.sanitizeFeedbackPMI( ...
                row.PMI, state.CfgMobility, direction, latest.RI));
            latest.CRI = double(sixgr.truth.CoupledTruthRuntime.sanitizeFeedbackCRI( ...
                row.CRI, state.CfgMobility));
            latest.SINR_dB = double(row.SINR_dB);
            latest.MCSIndex = double(row.MCSIndex);
            latest.TargetCodeRate = double(row.TargetCodeRate);
            latest.ServingCell = double(row.ServingCell);
            latest.Slot = double(row.SourceSlot);
            latest.Modulation = char(string(row.Modulation));
            latest.Direction = char(string(row.Direction));
            if upper(string(row.Direction)) == "UL"
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
        else
            buffers{ueIdx, pid} = combinedLLR;
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
        fb.DueSlot = double(slotIdx + state.HARQFeedbackSlots);
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
        fb.UCIBitCount = 1;
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
        t.FeedbackDueSlot = double(slotIdx + state.HARQFeedbackSlots);
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

        harqFields = struct("HARQProcess", double(harqId0), "HARQNDI", double(ndi), "HARQRV", double(rv), ...
            "HARQIsRetransmission", logical(isRetx), "HARQFeedbackDueSlot", double(slotIdx + state.HARQFeedbackSlots), ...
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
        measuredTrialSINR = double(sixgr.truth.CoupledTruthRuntime.rowValue(row, "MeasuredTrialSINR_dB", NaN));
        measuredTrialSINRSource = string(sixgr.truth.CoupledTruthRuntime.rowValue(row, "MeasuredTrialSINRSource", ""));
        decoderTruthProxySINR = double(sixgr.truth.CoupledTruthRuntime.rowValue(row, "DecoderTruthProxySINR_dB", NaN));
        decoderTruthProxySource = string(sixgr.truth.CoupledTruthRuntime.rowValue(row, "DecoderTruthProxySINRSource", ""));
        if isfinite(receiverHestSINR) && strlength(strtrim(receiverHestSource)) == 0
            receiverHestSource = "receiver_hest_reference_signal_measurement";
        end
        estimatedSINR = NaN;
        widebandSINRSource = "unavailable";
        widebandSINRValueRole = "unavailable";
        if isfinite(measuredTrialSINR)
            estimatedSINR = double(measuredTrialSINR);
            if strlength(strtrim(measuredTrialSINRSource)) > 0
                widebandSINRSource = strtrim(measuredTrialSINRSource);
            else
                widebandSINRSource = "post_equalization_error_vector_measurement";
            end
            widebandSINRValueRole = "measured";
        elseif isfinite(decoderTruthProxySINR)
            estimatedSINR = double(decoderTruthProxySINR);
            if strlength(strtrim(decoderTruthProxySource)) > 0
                widebandSINRSource = strtrim(decoderTruthProxySource);
            else
                widebandSINRSource = "post_equalization_evm_proxy";
            end
            widebandSINRValueRole = "derived_proxy";
        elseif isfinite(largeScaleSINR)
            estimatedSINR = largeScaleSINR;
            widebandSINRSource = "large_scale_interference_budget_preview";
            widebandSINRValueRole = "derived_preview";
        elseif isfinite(receiverHestSINR)
            estimatedSINR = receiverHestSINR;
            if strlength(strtrim(receiverHestSource)) > 0
                widebandSINRSource = strtrim(receiverHestSource);
            else
                widebandSINRSource = "receiver_hest_reference_signal_measurement";
            end
            widebandSINRValueRole = "estimated_diagnostic";
        end
        configuredSNR = double(sixgr.truth.CoupledTruthRuntime.rowValue(row, "ConfiguredSNR_dB", state.CurrentSNR_dB));
        appliedLargeScaleGain = double(sixgr.truth.CoupledTruthRuntime.rowValue(row, "AppliedLargeScaleGain_dB", NaN));
        csiRSRP = double(sixgr.truth.CoupledTruthRuntime.rowValue(row, "CSI_RSRP_dB", NaN));
        csiRSRPSource = string(sixgr.truth.CoupledTruthRuntime.rowValue(row, "CSI_RSRPSource", ""));
        interferenceMode = string(sixgr.truth.CoupledTruthRuntime.rowValue(row, "InterferenceMode", configuredInterferenceMode));
        cqi = double(sixgr.util.normalizeReportedCQI( ...
            sixgr.truth.CoupledTruthRuntime.rowValue(row, "WidebandCQI", NaN)));
        mcs = double(sixgr.truth.CoupledTruthRuntime.rowValue(row, "CQIDerivedMCS", NaN));
        rate = double(sixgr.truth.CoupledTruthRuntime.rowValue(row, "CQIDerivedTargetCodeRate", NaN));
        modStr = string(sixgr.truth.CoupledTruthRuntime.rowValue(row, "CQIDerivedModulation", ""));
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
        r.ConfiguredSNRSource = "configured_runtime_operating_point_reference";
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
        r.DecoderTruthProxySINR_dB = double(decoderTruthProxySINR);
        r.DecoderTruthProxySINRSource = char(decoderTruthProxySource);
        r.MeasuredTrialSINR_dB = double(measuredTrialSINR);
        r.EstimatedWidebandSINR_dB = double(estimatedSINR);
        r.ReceiverHestWidebandSINR_dB = double(receiverHestSINR);
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
            r.DL_Throughput_Mbps = sixgr.truth.CoupledTruthRuntime.safeDivide(dl.GoodBitsSum, duration_s) / 1e6;
            r.UL_Throughput_Mbps = sixgr.truth.CoupledTruthRuntime.safeDivide(ul.GoodBitsSum, duration_s) / 1e6;
            r.DL_BLER = 1 - sixgr.truth.CoupledTruthRuntime.safeDivide(dl.CRCSum, max(dl.Frames, 1));
            r.UL_BLER = 1 - sixgr.truth.CoupledTruthRuntime.safeDivide(ul.CRCSum, max(ul.Frames, 1));
            r.DL_MeanMeasuredSINR_dB = sixgr.truth.CoupledTruthRuntime.safeDivide(dl.SINRSum, max(dl.SINRCount, 1));
            r.UL_MeanMeasuredSINR_dB = sixgr.truth.CoupledTruthRuntime.safeDivide(ul.SINRSum, max(ul.SINRCount, 1));
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
                r.ConfiguredSNRSource = "configured_runtime_operating_point_reference";
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
            r.EstimatedWidebandSINR_dB = double(servingT.EstimatedWidebandSINR_dB(lastIdx));
            if ismember("ReceiverHestWidebandSINR_dB", string(servingT.Properties.VariableNames))
                r.ReceiverHestWidebandSINR_dB = double(servingT.ReceiverHestWidebandSINR_dB(lastIdx));
            else
                r.ReceiverHestWidebandSINR_dB = double(r.ReceiverHestSINR_dB);
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
            else
                r.WidebandSINRSource = "large_scale_interference_budget_preview";
            end
            if ismember("WidebandSINRValueRole", string(servingT.Properties.VariableNames))
                r.WidebandSINRValueRole = string(servingT.WidebandSINRValueRole(lastIdx));
            elseif isfinite(double(r.ReceiverHestWidebandSINR_dB))
                r.WidebandSINRValueRole = "estimated";
            elseif isfinite(double(r.LargeScaleWidebandSINR_dB))
                r.WidebandSINRValueRole = "derived_preview";
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
            hasRetx = harq.hasPendingRetx(rnti);
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
            feedback.MCSIndex = 0;
            feedback.Modulation = "QPSK";
            feedback.TargetCodeRate = 0.12;
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
                % Before the first real CSI report is available, keep any
                % large-scale runtime preview diagnostic-only. Scheduler AMC
                % must not consume non-measured preview CQI as live feedback.
                schedulerCQI = 0;
                schedulerModulation = "";
                schedulerTargetCodeRate = NaN;
                schedulerMCSAuthority = "bootstrap_cqi_conservative_lab_default";
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
        ueState.MCSIndex = double(schedulerMCSIndex);
        ueState.FeedbackMCSIndex = double(feedbackMCSIndex);
        ueState.MCSIndexAuthority = char(string(schedulerMCSAuthority));
        ueState.Modulation = char(string(schedulerModulation));
        ueState.TargetCodeRate = double(schedulerTargetCodeRate);
        ueState.FeedbackValid = logical(feedbackValid);
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

    function tf = resolveSchedulingEligibilityForDirection(state, ueIdx, direction)
        direction = upper(string(direction));
        controlEligible = sixgr.truth.CoupledTruthRuntime.controlLogicalAt(state, "ControlEligibility", ueIdx, true);
        sharedSchedulingEligible = sixgr.truth.CoupledTruthRuntime.controlLogicalAt(state, "SchedulingEligibility", ueIdx, true);
        dlCSIEnabled = logical(sixgr.util.structGet(state.CfgMobility, "phy.csi.enable", false)) || ...
            logical(sixgr.util.structGet(state.CfgMobility, "phy.csirs.enable", false));
        if direction == "DL" && dlCSIEnabled
            tf = logical(controlEligible);
        else
            tf = logical(sharedSchedulingEligible);
        end
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
        direction = upper(string(direction));
        tf = direction == "UL" && logical(sixgr.util.structGet(state.ControlGating, "SRSRequired", false));
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
        ok = sixgr.truth.CoupledTruthRuntime.trialPassed(trialT);
        slotIdx = double(sixgr.truth.CoupledTruthRuntime.rowValue(trialT(end, :), "Slot", state.CurrentSlot));
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
        state = sixgr.truth.CoupledTruthRuntime.refreshControlStateImpl(state);
    end

    function state = applyPRACHTrialImpl(state, ueIdx, trialT)
        if ~(isfinite(double(ueIdx)) && ueIdx >= 1 && ueIdx <= double(state.NumUsers))
            return;
        end
        row = trialT(end, :);
        status = upper(strtrim(string(sixgr.truth.CoupledTruthRuntime.rowValue(row, "Status", ""))));
        if status == "NA" || status == "SKIP" || logical(sixgr.truth.CoupledTruthRuntime.rowValue(row, "Skipped", false))
            state = sixgr.truth.CoupledTruthRuntime.refreshControlStateImpl(state);
            return;
        end
        ok = sixgr.truth.CoupledTruthRuntime.trialPassed(trialT);
        slotIdx = double(sixgr.truth.CoupledTruthRuntime.rowValue(row, "Slot", state.CurrentSlot));
        if ok
            state.AccessState(ueIdx) = "succeeded";
            state.LastSuccessfulPRACHSlotByUE(ueIdx) = double(slotIdx);
            state = sixgr.truth.CoupledTruthRuntime.recordInitialAccessEvent(state, ueIdx, "PRACH_MSG1_DETECTED", "UL", ...
                "control/csv/prach_trials.csv", "PRACH", slotIdx, ...
                "slot_coupled_prach_detection_observation", "Msg1 PRACH detection observed in the coupled PRACH runtime gate.");
        else
            state.AccessState(ueIdx) = "failed";
            state.PRACHFailureCount(ueIdx) = double(state.PRACHFailureCount(ueIdx)) + 1;
        end
        state = sixgr.truth.CoupledTruthRuntime.refreshControlStateImpl(state);
    end

    function state = applySRSTrialImpl(state, ueIdx, trialT)
        if ~(isfinite(double(ueIdx)) && ueIdx >= 1 && ueIdx <= double(state.NumUsers))
            return;
        end
        row = trialT(end, :);
        slotIdx = double(sixgr.truth.CoupledTruthRuntime.rowValue(row, "Slot", state.CurrentSlot));
        state.LastSRSObservedSlotByUE(ueIdx) = double(slotIdx);
        ok = sixgr.truth.CoupledTruthRuntime.trialPassed(trialT);
        if ok
            state.SRSValidityState(ueIdx) = "valid";
            state.CSIValidityState(ueIdx) = "fresh_srs";
            state.LastSuccessfulSRSSlotByUE(ueIdx) = double(slotIdx);
            state = sixgr.truth.CoupledTruthRuntime.updateLatestULFeedbackFromSRSTrial(state, ueIdx, row, slotIdx);
        else
            state.SRSValidityState(ueIdx) = "invalid";
            state.CSIValidityState(ueIdx) = "invalid_srs_not_usable";
            state.SRSInvalidEventCount(ueIdx) = double(state.SRSInvalidEventCount(ueIdx)) + 1;
        end
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
            ["SINR_dB","MeasuredTrialSINR_dB","ReceiverHestSINR_dB","MeasuredSINR_dB"], NaN);
        cqi = double(sixgr.util.normalizeReportedCQI( ...
            sixgr.truth.CoupledTruthRuntime.rowFirstFinite(row, ["WidebandCQI","CQI"], NaN)));
        mcsIndex = sixgr.truth.CoupledTruthRuntime.rowFirstFinite(row, ...
            ["CQIDerivedMCS","MCSIndex"], NaN);
        targetCodeRate = sixgr.truth.CoupledTruthRuntime.rowFirstFinite(row, ...
            ["CQIDerivedTargetCodeRate","TargetCodeRate"], NaN);
        modulation = string(sixgr.truth.CoupledTruthRuntime.rowFirstString(row, ...
            ["CQIDerivedModulation","Modulation"], ""));
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
        if ueIdx <= numel(state.LatestULFeedback)
            latest = state.LatestULFeedback(ueIdx);
        else
            latest = sixgr.truth.CoupledTruthRuntime.emptyLatestFeedbackRow();
        end
        latest.Valid = true;
        latest.Direction = "UL";
        latest.Slot = double(slotIdx);
        if isfinite(sinrDb)
            latest.SINR_dB = double(sinrDb);
        end
        if isfinite(cqi) && cqi > 0
            latest.CQI = double(cqi);
        end
        if isfinite(mcsIndex) && mcsIndex >= 0
            latest.MCSIndex = double(round(mcsIndex));
        end
        if isfinite(targetCodeRate) && targetCodeRate > 0
            latest.TargetCodeRate = double(targetCodeRate);
        end
        if strlength(strtrim(modulation)) > 0
            latest.Modulation = char(modulation);
        end
        if isfinite(ri)
            latest.RI = double(max(1, round(ri)));
        end
        if isfinite(tpmi)
            latest.PMI = double(round(tpmi));
        end
        servingCell = sixgr.truth.CoupledTruthRuntime.rowFirstFinite(row, ...
            ["ServingCell","BaseStationID","CellID"], NaN);
        if isfinite(servingCell)
            latest.ServingCell = double(servingCell);
        end
        state.LatestULFeedback(ueIdx) = latest;

        if sixgr.truth.CoupledTruthRuntime.srsReciprocityFeedsDLFeedback(state.CfgMobility)
            if ueIdx <= numel(state.LatestDLFeedback)
                dlLatest = state.LatestDLFeedback(ueIdx);
            else
                dlLatest = sixgr.truth.CoupledTruthRuntime.emptyLatestFeedbackRow();
            end
            dlLatest.Valid = true;
            dlLatest.Direction = "DL";
            dlLatest.Slot = double(slotIdx);
            if isfinite(sinrDb)
                dlLatest.SINR_dB = double(sinrDb);
            end
            dlCqi = cqi;
            if isfinite(sinrDb)
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
            if isfinite(dlCqi) && dlCqi > 0
                dlLatest.CQI = double(dlCqi);
                [dlMod, dlRate, dlMCS] = sixgr.link.amcFromCQI(dlCqi, "", NaN, state.CfgMobility, "DL");
                if isfinite(dlMCS) && dlMCS >= 0
                    dlLatest.MCSIndex = double(round(dlMCS));
                    dlLatest.Modulation = char(string(dlMod));
                    dlLatest.TargetCodeRate = double(dlRate);
                end
            end
            if isfinite(ri)
                dlLatest.RI = double(max(1, round(ri)));
            end
            if isfinite(servingCell)
                dlLatest.ServingCell = double(servingCell);
            end
            state.LatestDLFeedback(ueIdx) = dlLatest;
        end
    end

    function tf = srsReciprocityFeedsDLFeedback(cfg)
        duplexMode = lower(strtrim(string(sixgr.util.structGet(cfg, "phy.duplex.mode", ...
            sixgr.util.structGet(cfg, "frequency.duplex_mode", ...
            sixgr.util.structGet(cfg, "global_radio_scope.duplex_mode", ""))))));
        orientation = lower(strtrim(string(sixgr.util.structGet(cfg, "referenceSignals.operationOrientation", ...
            sixgr.util.structGet(cfg, "reference_signals.operation_orientation", "")))));
        csiMode = lower(strtrim(string(sixgr.util.structGet(cfg, "referenceSignals.csiAcquisitionMode", ...
            sixgr.util.structGet(cfg, "reference_signals.csi_acquisition_mode", "")))));
        tf = (duplexMode == "tdd" || contains(orientation, "tdd")) && ...
            (contains(orientation, "reciprocity") || contains(csiMode, "joint") || contains(csiMode, "dl_ul"));
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
        ok = sixgr.truth.CoupledTruthRuntime.trialPassed(trialT);
        if ok
            state.TRSValidityStateByCell(servingCell) = "valid";
            state.TrackingEligibilityByCell(servingCell) = true;
            state.LastSuccessfulTRSSlotByCell(servingCell) = double(slotIdx);
        else
            state.TRSValidityStateByCell(servingCell) = "failed";
            state.TrackingEligibilityByCell(servingCell) = false;
            state.TRSFailureCountByCell(servingCell) = double(state.TRSFailureCountByCell(servingCell)) + 1;
        end
        if isfinite(estDopplerHz)
            state.LastEstimatedTRSDopplerHzByCell(servingCell) = double(estDopplerHz);
        end
        state = sixgr.truth.CoupledTruthRuntime.updateReceiverTrackingFromTRSImpl(state, servingCell, row, ok);
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
            ["EstimatedCFO_Hz","EstimatedCFO_PreCorrection_Hz"], NaN);
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
        cfoAvailable = isfinite(estimatedCFOHz);
        if isfinite(estDopplerHz) && cfoAvailable
            frequencyState = "doppler_and_cfo_estimates_updated_from_trs";
        elseif cfoAvailable
            frequencyState = "cfo_estimate_updated_from_trs";
        elseif isfinite(estDopplerHz)
            frequencyState = "doppler_estimate_updated_from_trs";
        else
            frequencyState = "not_updated_frequency_estimate_unavailable";
        end
        timingAvailable = isfinite(timingEstimate);
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
        ok = ~gatingActive || sixgr.truth.CoupledTruthRuntime.trialPassed(trialT);
        grant.PDCCHGatingActive = gatingActive;
        grant.ControlDecodeOk = logical(ok);
        if gatingActive
            if ok
                grant.GrantControlState = "control_ok";
                state.LastPDCCHStatus(ueIdx) = "control_ok";
                state.LastSuccessfulPDCCHSlotByUE(ueIdx) = double(sixgr.util.structGet(grant, "Slot", state.CurrentSlot));
                state = sixgr.truth.CoupledTruthRuntime.recordInitialAccessEvent(state, ueIdx, "PDCCH_DCI_DECODED", direction, ...
                    "control/csv/pdcch_trials.csv", "PDCCH", double(sixgr.util.structGet(grant, "Slot", state.CurrentSlot)), ...
                    "slot_coupled_grant_pdcch_decode_observation", ...
                    "PDCCH DCI decode observed for a scheduler grant in the coupled runtime.");
            else
                grant.GrantControlState = "control_failed";
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
        if isfinite(ueIdx) && ueIdx >= 1 && ueIdx <= double(state.NumUsers)
            state.LastPDCCHStatus(ueIdx) = string(reason);
            state.PDCCHFailureCount(ueIdx) = double(state.PDCCHFailureCount(ueIdx)) + 1;
            state.GrantsBlockedByGatingCount(ueIdx) = double(state.GrantsBlockedByGatingCount(ueIdx)) + 1;
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
        if schedulerUsesCQITable && ~logical(sixgr.util.structGet(feedback, "Valid", false))
            % Before measured RI is available, keep bootstrap rank
            % conservative and explicit instead of inheriting configured
            % multi-layer study settings as if they were feedback.
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
            "large_scale_preview", ...
            "large_scale_preview_lab_default", ...
            "large_scale_preview_cqi_lab_default"]);
        previewSINR_dB = NaN;
        previewCQI = NaN;
        previewMCSIndex = NaN;
        previewModulation = "";
        previewTargetCodeRate = NaN;

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
                cqiFeedback = sixgr.link.resolveWidebandCQI(struct("WidebandSINR_dB", previewSINR_dB), state.CfgMobility, direction);
                previewCQI = double(sixgr.util.structGet(cqiFeedback, "WidebandCQI", NaN));
                if isfinite(previewCQI) && previewCQI > 0
                    [modStr, targetCodeRate, mcsIndex] = sixgr.link.amcFromCQI(previewCQI, "", NaN, state.CfgMobility, direction);
                    previewMCSIndex = double(mcsIndex);
                    previewModulation = char(string(modStr));
                    previewTargetCodeRate = double(targetCodeRate);
                end
            end
        end

        bootstrapProfile = sixgr.link.resolveMCSProfile(mcsTable, 0);
        feedback.CQI = 0;
        feedback.SINR_dB = NaN;
        if bootstrapProfile.Valid
            feedback.Modulation = char(string(bootstrapProfile.Modulation));
            feedback.TargetCodeRate = double(bootstrapProfile.TargetCodeRate);
            feedback.MCSIndex = 0;
        else
            feedback.Modulation = "QPSK";
            feedback.TargetCodeRate = 0.1171875;
            feedback.MCSIndex = 0;
        end
        feedback.BootstrapCQISource = "bootstrap_cqi_conservative_lab_default";
        feedback.PreviewSINR_dB = double(previewSINR_dB);
        feedback.PreviewCQI = double(previewCQI);
        feedback.PreviewMCSIndex = double(previewMCSIndex);
        feedback.PreviewModulation = char(string(previewModulation));
        feedback.PreviewTargetCodeRate = double(previewTargetCodeRate);
        if isfinite(previewCQI) && previewCQI > 0
            feedback.PreviewCQISource = "bootstrap_large_scale_preview_diagnostic_only";
        else
            feedback.PreviewCQISource = "";
        end
        feedback.RI = 1;
    end

    function pmi = resolveFallbackPMI(cfg, direction, rankHint)
        pmi = NaN;
        direction = upper(string(direction));
        if direction == "UL"
            pmiCfg = sixgr.util.structGet(cfg, "phy.pusch.PMI", NaN);
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

    function state = reserveGrantBits(state, ueIdx, direction, tbsBits)
        tbsBits = max(0, round(double(tbsBits)));
        if upper(string(direction)) == "UL"
            state.ULQueueBits(ueIdx) = max(0, double(state.ULQueueBits(ueIdx)) - tbsBits);
            state.ULTransmittedBits(ueIdx) = double(state.ULTransmittedBits(ueIdx)) + tbsBits;
        else
            state.DLQueueBits(ueIdx) = max(0, double(state.DLQueueBits(ueIdx)) - tbsBits);
            state.DLTransmittedBits(ueIdx) = double(state.DLTransmittedBits(ueIdx)) + tbsBits;
        end
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
        row.Modulation = sixgr.truth.CoupledTruthRuntime.firstString(sixgr.util.structGet(grant, "Modulation", ""), "");
        row.TargetCodeRate = sixgr.truth.CoupledTruthRuntime.firstNumeric(sixgr.util.structGet(grant, "TargetCodeRate", NaN), NaN);
        row.NumLayers = sixgr.truth.CoupledTruthRuntime.firstNumeric(sixgr.util.structGet(grant, "NumLayers", NaN), NaN);
        row.Layers = row.NumLayers;
        row.CQIUsed = sixgr.truth.CoupledTruthRuntime.firstNumeric(sixgr.util.structGet(grant, "CQIUsed", sixgr.util.structGet(feedback, "CQI", NaN)), NaN);
        row.RIUsed = sixgr.truth.CoupledTruthRuntime.firstNumeric(sixgr.util.structGet(grant, "RIUsed", sixgr.util.structGet(feedback, "RI", NaN)), NaN);
        row.Rank = row.RIUsed;
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

    function state = enqueueCSIReport(state, ueIdx, direction, row)
        report = sixgr.truth.CoupledTruthRuntime.emptyCSIReportRow();
        report.Direction = char(upper(string(direction)));
        report.UEIndex = double(ueIdx);
        report.RNTI = double(max(1, round(double(state.MultiUser.RNTIStart + ueIdx - 1))));
        sourceSlot = double(sixgr.truth.CoupledTruthRuntime.rowValue(row, "Slot", state.CurrentSlot));
        report.SourceSlot = double(sourceSlot);
        report.DueSlot = double(sourceSlot + state.CSIFeedbackSlots);
        report.CQI = double(sixgr.truth.CoupledTruthRuntime.rowValue(row, "WidebandCQI", NaN));
        report.RI = double(sixgr.truth.CoupledTruthRuntime.rowValue(row, "RankIndicator", NaN));
        report.PMI = double(sixgr.truth.CoupledTruthRuntime.sanitizeFeedbackPMI( ...
            sixgr.truth.CoupledTruthRuntime.rowValue(row, "PMI", NaN), state.CfgMobility, direction, report.RI));
        report.CRI = double(sixgr.truth.CoupledTruthRuntime.sanitizeFeedbackCRI( ...
            sixgr.truth.CoupledTruthRuntime.rowValue(row, "CRI", NaN), state.CfgMobility));
        report.SINR_dB = double(sixgr.truth.CoupledTruthRuntime.rowValue(row, "MeasuredSINR_dB", NaN));
        report.MCSIndex = double(sixgr.truth.CoupledTruthRuntime.rowValue(row, "CQIDerivedMCS", NaN));
        report.TargetCodeRate = double(sixgr.truth.CoupledTruthRuntime.rowValue(row, "CQIDerivedTargetCodeRate", NaN));
        report.Modulation = char(string(sixgr.truth.CoupledTruthRuntime.rowValue(row, "CQIDerivedModulation", "")));
        servingVec = double(sixgr.util.structGet(state, "CurrentServingIdx", nan(state.NumUsers, 1)));
        if ueIdx >= 1 && ueIdx <= numel(servingVec)
            report.ServingCell = double(servingVec(ueIdx));
        end
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
            latest.MCSIndex = report.MCSIndex;
            latest.TargetCodeRate = report.TargetCodeRate;
            latest.Modulation = report.Modulation;
            latest.ServingCell = report.ServingCell;
            latest.Slot = report.SourceSlot;
            latest.Direction = report.Direction;
            if upper(string(direction)) == "UL"
                state.LatestULFeedback(ueIdx) = latest;
            else
                state.LatestDLFeedback(ueIdx) = latest;
            end
            state.PendingCSITable.Processed(end) = true;
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
                double(sixgr.util.structGet(cfg, "phy.nTxAnt", bsTemplate.Nant)), ...
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
                double(sixgr.util.structGet(cfg, "phy.nRxAnt", ueTemplate.Nant)), ...
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
            "ValueRole", "configured_anchor_until_feedback", ...
            "ValueStatus", "configured_anchor_pending_runtime_feedback", ...
            "ValueSource", "CoupledTruthRuntime.initialize:configured_runtime_anchor", ...
            "ValueDefinition", "canonical run state for the slot-coupled LLS truth loop; CurrentSNR_dB starts as the configured runtime anchor and is promoted to representative measured UE feedback after valid runtime observations arrive", ...
            "NAReason", "");
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
        if ~(isfinite(currentSNR))
            currentSNR = configuredSNR;
        end
        traceT.ConfiguredSNR_dB(rowIdx) = configuredSNR;
        traceT.ConfiguredSNRSource(rowIdx) = string("configured_runtime_operating_point_reference");
        traceT.CurrentSNR_dB(rowIdx) = currentSNR;
        traceT.CurrentSNRSource(rowIdx) = string(sixgr.util.structGet(runState, "ValueSource", ""));
        traceT.CurrentSNRValueRole(rowIdx) = string(sixgr.util.structGet(runState, "ValueRole", ""));
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
        [representativeLinkQuality, representativeLinkQualitySource] = ...
            sixgr.truth.CoupledTruthRuntime.representativeCurrentLinkQuality(state);
        runState.ConfiguredSNR_dB = configuredSNR;
        if isfinite(representativeLinkQuality)
            runState.CurrentSNR_dB = representativeLinkQuality;
            runState.ValueStatus = "OK";
            if string(representativeLinkQualitySource) == "pending_measured_feedback"
                runState.ValueRole = "representative_measured_feedback_pending_delivery";
                runState.ValueSource = "CoupledTruthRuntime.refreshRunState:pending_measured_csi_report";
                runState.ValueDefinition = "representative median UE-measured wideband SINR from the latest observed CSI reports for the active slot; this is not the configured sweep anchor, and delivery timing to the scheduler may still be pending";
            else
                runState.ValueRole = "representative_measured_feedback_proxy";
                runState.ValueSource = "CoupledTruthRuntime.refreshRunState:representative_feedback_sinr_proxy";
                runState.ValueDefinition = "representative median UE-reported/measured wideband SINR proxy for the active slot; this is not the configured sweep anchor, and ConfiguredSNR_dB preserves that configured runtime anchor separately";
            end
        else
            runState.CurrentSNR_dB = configuredSNR;
            runState.ValueRole = "configured_anchor_until_feedback";
            runState.ValueStatus = "configured_anchor_pending_runtime_feedback";
            runState.ValueSource = "CoupledTruthRuntime.refreshRunState:configured_runtime_anchor_fallback";
            runState.ValueDefinition = "no valid runtime feedback SINR is available yet for the active slot, so CurrentSNR_dB temporarily reflects the configured runtime SNR anchor and is not a measured SINR; ConfiguredSNR_dB preserves that anchor explicitly";
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
            row.ConfiguredSNRSource = "configured_runtime_operating_point_reference";
            row.CurrentSNR_dB = double(snr_dB);
            row.CurrentSNRSource = "configured_runtime_operating_point_reference";
            row.CurrentSNRValueRole = "configured_anchor_until_feedback";
            row.CurrentSNRValueStatus = "configured_anchor_pending_runtime_feedback";
            row.SNR_dB = double(snr_dB);
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
            "ReceiverHestSINR_dB", NaN, "ReceiverHestSINRSource", "", "DecoderTruthProxySINR_dB", NaN, "DecoderTruthProxySINRSource", "", ...
            "MeasuredTrialSINR_dB", NaN, "EstimatedWidebandSINR_dB", NaN, "ReceiverHestWidebandSINR_dB", NaN, "DecoderTruthProxyWidebandSINR_dB", NaN, "MeasuredWidebandSINR_dB", NaN, ...
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
            "ReceiverHestSINR_dB", NaN, "ReceiverHestSINRSource", "", "DecoderTruthProxySINR_dB", NaN, "DecoderTruthProxySINRSource", "", ...
            "MeasuredTrialSINR_dB", NaN, "EstimatedWidebandSINR_dB", NaN, "ReceiverHestWidebandSINR_dB", NaN, "DecoderTruthProxyWidebandSINR_dB", NaN, "MeasuredWidebandSINR_dB", NaN, ...
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
            "ReceiverHestSINR_dB", NaN, "ReceiverHestSINRSource", "", "DecoderTruthProxySINR_dB", NaN, "DecoderTruthProxySINRSource", "", ...
            "MeasuredTrialSINR_dB", NaN, "EstimatedWidebandSINR_dB", NaN, "ReceiverHestWidebandSINR_dB", NaN, "DecoderTruthProxyWidebandSINR_dB", NaN, "MeasuredWidebandSINR_dB", NaN, ...
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
                materialization = "active_integrated_grant_coupled_dci_decode_gate";
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
        if endsWith(fieldName, "source")
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
            "UCIType", "", "ControlResourceSource", "", "FormatAdaptationReason", "", "PUCCHGrantId", "", ...
            "Processed", false);
    end

    function row = emptyPUCCHGrantRow()
        row = struct( ...
            "Direction", "UL", "FeedbackForDirection", "", ...
            "Frame", NaN, "Slot", NaN, "ScheduledAbsoluteSlot", NaN, "SourceSlot", NaN, ...
            "UEIndex", NaN, "UEID", NaN, "RNTI", NaN, "ServingCell", NaN, "BaseStationID", NaN, ...
            "HarqID", NaN, "TBSBits", NaN, "ExpectedAck", false, "ObservedAck", false, ...
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
            "SINR_dB", NaN, "MCSIndex", NaN, "TargetCodeRate", NaN, ...
            "Modulation", "", "ServingCell", NaN, "Processed", false);
    end

    function row = emptyLatestFeedbackRow()
        row = struct( ...
            "Valid", false, "Direction", "", "Slot", NaN, ...
            "CQI", NaN, "RI", NaN, "PMI", NaN, "CRI", NaN, ...
            "SINR_dB", NaN, "MCSIndex", NaN, "TargetCodeRate", NaN, ...
            "Modulation", "", "ServingCell", NaN, ...
            "BootstrapCQISource", "", "PreviewSINR_dB", NaN, ...
            "PreviewCQI", NaN, "PreviewMCSIndex", NaN, ...
            "PreviewModulation", "", "PreviewTargetCodeRate", NaN, ...
            "PreviewCQISource", "");
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
            "MCSIndex", NaN, "Modulation", "", "TargetCodeRate", NaN, ...
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
            "ControlDecodeOk", false, "GrantControlState", "", ...
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
        observed = struct("ObservedAck", false, "DecodeOk", false);
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
        trial = sixgr.link.runPUCCHWaveformTrial(cfgU, ...
            "ExpectedUCIBits", int8(logical(expectedAck)), ...
            "SNR_dB", double(sixgr.util.structGet(state, "CurrentSNR_dB", NaN)), ...
            "Format", sixgr.util.structGet(cfgU, "phy.pucch.format", []), ...
            "RNTI", double(sixgr.truth.CoupledTruthRuntime.rowValue(row, "RNTI", NaN)), ...
            "InterferenceBundle", interferenceBundle);
        observed.DecodeOk = logical(sixgr.util.structGet(trial, "Ok", false));
        observed.ObservedAck = logical(observed.DecodeOk && sixgr.util.structGet(trial, "AckObserved", false));
        trialCrashed = logical(sixgr.util.structGet(trial, "Crash", false));
        if observed.DecodeOk
            if ueIdx > numel(state.LastSuccessfulPUCCHSlotByUE)
                state.LastSuccessfulPUCCHSlotByUE(ueIdx, 1) = NaN;
            end
            state.LastSuccessfulPUCCHSlotByUE(ueIdx) = double(sixgr.util.structGet(state, "CurrentSlot", NaN));
        else
            if trialCrashed
                if ueIdx > numel(state.PUCCHCrashCount)
                    state.PUCCHCrashCount(ueIdx, 1) = 0;
                end
                state.PUCCHCrashCount(ueIdx) = double(state.PUCCHCrashCount(ueIdx)) + 1;
            else
                if ueIdx > numel(state.PUCCHFailureCount)
                    state.PUCCHFailureCount(ueIdx, 1) = 0;
                end
                state.PUCCHFailureCount(ueIdx) = double(state.PUCCHFailureCount(ueIdx)) + 1;
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
            observed = struct("ObservedAck", false, "DecodeOk", false);
        end
        if nargin < 3 || ~isstruct(trial)
            trial = struct();
        end
        ack = logical(sixgr.util.structGet(observed, "ObservedAck", false));
        decodeOk = logical(sixgr.util.structGet(observed, "DecodeOk", false));
        detectionUsable = logical(sixgr.util.structGet(trial, "DetectionUsable", true));
        crcApplicable = logical(sixgr.util.structGet(trial, "CRCApplicable", false));
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
            "TBSize_bits", double(numel(sixgr.util.structGet(trial, "ExpectedBits", int8(1)))), ...
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
            "DetectionAttempted", logical(sixgr.util.structGet(trial, "DetectionAttempted", false)), ...
            "DetectionUsable", detectionUsable, ...
            "FailureReason", char(string(sixgr.util.structGet(trial, "FailureReason", ""))), ...
            "ConfiguredSNR_dB", double(sixgr.util.structGet(trial, "ConfiguredSNR_dB", sixgr.util.structGet(state, "CurrentSNR_dB", NaN))), ...
            "ConfiguredSNRSource", char(string(sixgr.util.structGet(trial, "ConfiguredSNRSource", "configured_runtime_operating_point_reference"))), ...
            "SNRValueRole", char(string(sixgr.util.structGet(trial, "SNRValueRole", "configured_reference_metadata"))), ...
            "AppliedAWGNSNR_dB", double(sixgr.util.structGet(trial, "AppliedAWGNSNR_dB", NaN)), ...
            "ReceiverHestSINR_dB", double(sixgr.util.structGet(trial, "ReceiverHestSINR_dB", NaN)), ...
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
            "FormatAdapted", logical(sixgr.util.structGet(trial, "FormatAdapted", false)), ...
            "FormatAdaptationReason", char(string(sixgr.util.structGet(trial, "FormatAdaptationReason", ""))), ...
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
            "UCIBitCount", double(sixgr.truth.CoupledTruthRuntime.rowValue(fbRow, "UCIBitCount", numel(sixgr.util.structGet(trial, "ExpectedBits", int8(1))))), ...
            "PUCCHGrantId", char(string(sixgr.truth.CoupledTruthRuntime.rowValue(fbRow, "PUCCHGrantId", ""))), ...
            "PUCCHResourceId", char(string(sixgr.truth.CoupledTruthRuntime.rowValue(fbRow, "PUCCHResourceId", ""))), ...
            "PUCCHPRBStart", double(sixgr.truth.CoupledTruthRuntime.rowValue(fbRow, "PUCCHPRBStart", NaN)), ...
            "PUCCHPRBCount", double(sixgr.truth.CoupledTruthRuntime.rowValue(fbRow, "PUCCHPRBCount", NaN)), ...
            "PUCCHSymbolStart", double(sixgr.truth.CoupledTruthRuntime.rowValue(fbRow, "PUCCHSymbolStart", NaN)), ...
            "PUCCHNumSymbols", double(sixgr.truth.CoupledTruthRuntime.rowValue(fbRow, "PUCCHNumSymbols", NaN)), ...
            "UCIType", char(string(sixgr.truth.CoupledTruthRuntime.rowValue(fbRow, "UCIType", "harq_ack"))), ...
            "ControlResourceSource", char(string(sixgr.truth.CoupledTruthRuntime.rowValue(fbRow, "ControlResourceSource", "runtime_deterministic_pucch_resource_assignment"))), ...
            "ControlResourceValidity", logical(sixgr.util.structGet(trial, "ControlResourceValidity", true)), ...
            "ExpectedAck", logical(expectedAck), ...
            "ObservedAck", logical(ack), ...
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
        configuredSource(mask) = "configured_runtime_operating_point_reference";
        mask = strlength(configuredRole) == 0 & isfinite(configuredSINR);
        configuredRole(mask) = "configured_reference_metadata";
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
        hasDecoder = isfinite(decoderProxySINR);
        mask = strlength(decoderSource) == 0 & hasDecoder;
        decoderSource(mask) = "post_equalization_evm_proxy";
        mask = strlength(decoderRole) == 0 & hasDecoder;
        decoderRole(mask) = "derived";
        mask = strlength(decoderStatus) == 0 & hasDecoder;
        decoderStatus(mask) = "OK";
        mask = strlength(decoderReason) == 0 & ~hasDecoder;
        decoderReason(mask) = signalToken + "_decoder_truth_proxy_unavailable";
        mask = strlength(decoderRole) == 0 & ~hasDecoder;
        decoderRole(mask) = "unavailable";
        mask = strlength(decoderStatus) == 0 & ~hasDecoder;
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
        row.ControlResourceValidity = isfinite(row.PUCCHPRBStart) && isfinite(row.PUCCHSymbolStart) && ...
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
        numRB = max(1, round(double(sixgr.util.structGet(state, "NumRB", 52))));
        prbSpan = max(1, min(numRB, round(prbCount)));
        prbMod = max(1, numRB - prbSpan + 1);
        prbStart = mod(max(0, round(rnti) - 1) + 7 * max(0, round(servingCell) - 1), prbMod);
        resourceId = "pucch:cell=" + string(round(servingCell)) + ...
            ":slot=" + string(round(dueSlot)) + ...
            ":rnti=" + string(round(rnti)) + ...
            ":reqfmt=" + string(round(requestedFormat)) + ...
            ":resfmt=" + string(round(resolvedFormat)) + ...
            ":prb=" + string(round(prbStart)) + ":" + string(round(prbSpan)) + ...
            ":sym=" + string(round(symbolStart)) + ":" + string(round(numSym));
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
            "ControlResourceSource", "runtime_deterministic_pucch_resource_assignment");
    end

    function bundle = buildPUCCHInterferenceBundle(state, feedbackRow)
        bundle = struct([]);
        grants = sixgr.util.structGet(state, "PUCCHGrantTraceTable", table());
        if ~(istable(grants) && ~isempty(grants) && istable(feedbackRow) && height(feedbackRow) >= 1)
            return;
        end
        currentRow = feedbackRow(1, :);
        currentUE = double(sixgr.truth.CoupledTruthRuntime.rowValue(currentRow, "UEIndex", NaN));
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
            ueIdx = round(double(sixgr.truth.CoupledTruthRuntime.rowValue(peer, "UEIndex", NaN)));
            if ~(isfinite(ueIdx) && ueIdx >= 1 && ueIdx <= double(sixgr.util.structGet(state, "NumUsers", 0)))
                continue;
            end
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
            bundle(count).InterferenceMode = char(string(sixgr.truth.CoupledTruthRuntime.resolveInterferenceExecutionMode(cfgI, state.MultiUser))); %#ok<AGROW>
            bundle(count).ExpectedUCIBits = int8(logical(sixgr.truth.CoupledTruthRuntime.rowExpectedPUCCHAck(peer))); %#ok<AGROW>
            bundle(count).RequestedFormat = double(sixgr.truth.CoupledTruthRuntime.rowValue(peer, "RequestedFormat", requestedFormat)); %#ok<AGROW>
            bundle(count).ResolvedFormat = double(requestedFormat); %#ok<AGROW>
            bundle(count).UCIBitCount = double(sixgr.truth.CoupledTruthRuntime.rowValue(peer, "UCIBitCount", 1)); %#ok<AGROW>
            bundle(count).RNTI = double(sixgr.truth.CoupledTruthRuntime.rowValue(peer, "RNTI", NaN)); %#ok<AGROW>
            bundle(count).ControlResourceSource = char(string(sixgr.truth.CoupledTruthRuntime.rowValue(peer, "ControlResourceSource", "runtime_deterministic_pucch_resource_assignment"))); %#ok<AGROW>
            bundle(count).PUCCHResourceId = char(string(sixgr.truth.CoupledTruthRuntime.rowValue(peer, "PUCCHResourceId", ""))); %#ok<AGROW>
        end
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
