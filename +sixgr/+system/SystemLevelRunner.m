classdef SystemLevelRunner
% sixgr.system.SystemLevelRunner
% Abstract system-level simulation with traffic, scheduling, and KPI export.

    methods(Static)
        function out = run(ctx, params)
            if nargin < 2 || isempty(params)
                params = struct();
            end

            cfg = ctx.Cfg;
            [cfg, canonicalFrame] = localAttachCanonicalFrameCore(cfg);
            log = ctx.Logger;
            runTimer = tic;
            startedUTC = localUTCStamp();

            explicitNumTTI = isfield(params, "NumTTI") && ~isempty(params.NumTTI);
            nTTI = double(sixgr.util.structGet(params, "NumTTI", ...
                          sixgr.util.structGet(cfg, "run.numTTI", 200)));
            tti_s = localSlotDuration(cfg, params);

            simDuration_s = sixgr.util.structGet(params, "SimDuration_s", ...
                            sixgr.util.structGet(cfg, "system.simDuration_s", []));
            if ~explicitNumTTI && ~isempty(simDuration_s)
                nTTI = ceil(double(simDuration_s) / max(tti_s, eps));
            end

            forceLong = logical(sixgr.util.structGet(params, "ForceLong", false));
            if sixgr.util.structGet(cfg, "run.shortRun", false) && ~forceLong
                nTTI = min(nTTI, 40);
            end
            nTTI = max(1, round(nTTI));

            detailedTrace = logical(sixgr.util.structGet(params, "DetailedTrace", ...
                               sixgr.util.structGet(cfg, "outputs.detailedSystemTrace", false)));
            bw_Hz = double(canonicalFrame.BandwidthHz);
            seed = double(sixgr.util.structGet(cfg, "run.seed", 1));

            out = struct();
            out.Ok = true;
            out.Skipped = false;
            out.Errors = strings(0,1);
            out.KPITable = table();
            out.Artifacts = struct('csv',{{}},'mat',{{}},'fig',{{}},'m',{{}});

            try
                layout = sixgr.scenario.generateLayout(cfg);
                ue = sixgr.scenario.dropUEs(cfg, layout);
            catch ME
                out.Ok = false;
                out.Errors(end+1,1) = "Scenario generation failed: " + string(ME.message);
                return;
            end

            K = ue.K;
            if K <= 0
                out.Ok = false;
                out.Errors(end+1,1) = "No UEs available for system simulation.";
                return;
            end
            ueInitial = struct( ...
                "profileName", sixgr.util.structGet(ue, "profileName", ""), ...
                "id", sixgr.util.structGet(ue, "id", (1:K).'), ...
                "pos_m", sixgr.util.structGet(ue, "pos_m", zeros(K,3)), ...
                "indoor", logical(sixgr.util.structGet(ue, "indoor", false(K,1))), ...
                "speed_kmh", double(sixgr.util.structGet(ue, "speed_kmh", zeros(K,1))), ...
                "heading_deg", double(sixgr.util.structGet(ue, "heading_deg", zeros(K,1))));

            traffic = localBuildTraffic(cfg, params, K, nTTI, tti_s);

            pphy = params;
            proxyParamNames = intersect(fieldnames(pphy), {'BLERDB'; 'BLERLUT'});
            if ~isempty(proxyParamNames)
                pphy = rmfield(pphy, proxyParamNames);
            end
            pphy.PHYBackend = sixgr.util.structGet(params, "PHYBackend", ...
                sixgr.util.structGet(cfg, "system.phyBackend", "waveform"));
            phy = sixgr.system.PhyFactory.create(cfg, pphy, "Seed", seed + 31);
            [phyBackendLabel, phyModeLabel, waveformBacked, proxyPHYActive, fallbackUsed] = localDescribeSystemPHY(phy);
            plModel = sixgr.channel.TR38901Plus(cfg, "Seed", seed + 17);

            queueBitsDL = zeros(K,1);
            queueBitsUL = zeros(K,1);
            servedPerUE_DL = zeros(K,1);
            servedPerUE_UL = zeros(K,1);
            droppedPerUE_DL = zeros(K,1);
            droppedPerUE_UL = zeros(K,1);
            qMaxBits = double(sixgr.util.structGet(cfg, "system.queueMaxBits", 5e7));

            servedBitsTotalDL = 0;
            servedBitsTotalUL = 0;
            droppedBitsTotalDL = 0;
            droppedBitsTotalUL = 0;
            sinrHist = NaN(nTTI, K);
            sinrHistUL = NaN(nTTI, K);
            blerHistDL = NaN(nTTI, K);
            blerHistUL = NaN(nTTI, K);
            rsrpHist = NaN(nTTI, K);
            ebnoHist = NaN(nTTI, K);
            rxPowerHist = NaN(nTTI, K);
            desiredPowerHistDL = NaN(nTTI, K);
            desiredPowerHistUL = NaN(nTTI, K);
            interferencePowerHistDL = NaN(nTTI, K);
            interferencePowerHistUL = NaN(nTTI, K);
            noisePowerHistDL = NaN(nTTI, K);
            noisePowerHistUL = NaN(nTTI, K);
            interfererCellCountHistDL = zeros(nTTI, K);
            interfererCellCountHistUL = zeros(nTTI, K);
            pathlossHist = NaN(nTTI, K);
            dServeHist = NaN(nTTI, K);
            queueHist = NaN(nTTI, K);
            queueHistDL = NaN(nTTI, K);
            queueHistUL = NaN(nTTI, K);
            scheduledUE_DL = zeros(nTTI,1);
            scheduledUE_UL = zeros(nTTI,1);
            grantCountDL = zeros(nTTI,1);
            grantCountUL = zeros(nTTI,1);
            slotDirection = strings(nTTI,1);
            offeredBitsTTI = sum(traffic.OfferedBits, 2);
            offeredBitsTTI_DL = sum(traffic.OfferedBitsDL, 2);
            offeredBitsTTI_UL = sum(traffic.OfferedBitsUL, 2);
            servedBitsTTI = zeros(nTTI,1);
            servedBitsTTI_DL = zeros(nTTI,1);
            servedBitsTTI_UL = zeros(nTTI,1);
            droppedBitsTTI = zeros(nTTI,1);
            droppedBitsTTI_DL = zeros(nTTI,1);
            droppedBitsTTI_UL = zeros(nTTI,1);
            activeUECount = zeros(nTTI,1);
            decodeOkCountDL = 0;
            decodeFailCountDL = 0;
            decodeUnavailableCountDL = 0;
            decodeOkCountUL = 0;
            decodeFailCountUL = 0;
            decodeUnavailableCountUL = 0;
            overflowEvents = 0;
            scheduler = lower(char(string(sixgr.util.structGet(cfg, "mac.scheduler.type", "rr"))));
            ulSinrOffset_dB = double(sixgr.util.structGet(cfg, "system.ulSinrOffset_dB", -1.0));
            scs_kHz = double(canonicalFrame.SCSkHz);
            channelModel = string(sixgr.util.structGet(cfg, "channel.model", "TDL"));
            dopplerHz = double(sixgr.util.structGet(cfg, "channel.dopplerHz", 0));
            nLayersDL = max(1, round(double(sixgr.util.structGet(cfg, "phy.pdsch.numLayers", ...
                sixgr.util.structGet(cfg, "phy.pdsch.nLayers", 1)))));
            nLayersUL = max(1, round(double(sixgr.util.structGet(cfg, "phy.pusch.numLayers", ...
                sixgr.util.structGet(cfg, "phy.pusch.nLayers", 1)))));
            tcrDL = min(max(double(sixgr.util.structGet(cfg, "phy.pdsch.codeRate", 0.5)), 0.05), 0.95);
            tcrUL = min(max(double(sixgr.util.structGet(cfg, "phy.pusch.codeRate", 0.5)), 0.05), 0.95);

            nCells = size(layout.bs.pos_m, 1);
            schedDLCells = cell(nCells,1);
            schedULCells = cell(nCells,1);
            for c = 1:nCells
                schedDLCells{c} = localCreateScheduler(cfg, scheduler, "DL", log);
                schedULCells{c} = localCreateScheduler(cfg, scheduler, "UL", log);
            end

            % Mobility-control closed loop: measurement -> beam update ->
            % handover trigger/execution -> interruption -> resumed data.
            handoverEnable = logical(sixgr.util.structGet(cfg, "system.handover.enable", false));
            hoA3Offset_dB = double(sixgr.util.structGet(cfg, "system.handover.a3Offset_dB", 3.0));
            hoHyst_dB = double(sixgr.util.structGet(cfg, "system.handover.hysteresis_dB", 1.0));
            hoTTTslots = max(1, round(double(sixgr.util.structGet(cfg, "system.handover.timeToTrigger_slots", 6))));
            hoMinServingSlots = max(0, round(double(sixgr.util.structGet(cfg, "system.handover.minServingSlots", 8))));
            hoPrepSlots = max(0, round(double(sixgr.util.structGet(cfg, "system.handover.preparationSlots", 1))));
            hoInterruptionSlots = max(0, round(double(sixgr.util.structGet(cfg, "system.handover.interruptionSlots", 2))));
            hoBlockDuringPrep = logical(sixgr.util.structGet(cfg, "system.handover.blockDuringPreparation", false));

            measPeriodSlots = max(1, round(double(sixgr.util.structGet(cfg, "system.measurement.periodSlots", 2))));
            measAlpha = min(max(double(sixgr.util.structGet(cfg, "system.measurement.filterAlpha", 0.7)), 0), 0.99);

            beamEnable = logical(sixgr.util.structGet(cfg, "system.beam.enable", false));
            beamUpdatePeriodSlots = max(1, round(double(sixgr.util.structGet(cfg, "system.beam.updatePeriod_slots", 4))));
            nBeams = max(1, round(double(sixgr.util.structGet(cfg, "system.beam.numBeams", ...
                sixgr.util.structGet(cfg, "phy.ssb.nBeams", 8)))));
            beamSpanDeg = max(30, min(240, double(sixgr.util.structGet(cfg, "system.beam.sectorSpan_deg", 120))));
            beamMaxGain_dB = double(sixgr.util.structGet(cfg, "system.beam.maxGain_dB", 12));

            servingIdxState = ones(K,1);
            servingSinceSlot = ones(K,1);
            hoCandidateCell = zeros(K,1);
            hoCandidateCount = zeros(K,1);
            hoTargetCell = zeros(K,1);
            hoPrepRemain = zeros(K,1);
            hoInterRemain = zeros(K,1);
            hoActiveEventIdx = zeros(K,1);
            hoInterruptAccumSlots = zeros(K,1);

            measRSRP_dBm = NaN(K, nCells);
            measRSRPTrace_dBm = NaN(nTTI, K, nCells);
            beamIdx = ones(K, nCells);
            beamGain_dB = zeros(K, nCells);

            servingCellHist = NaN(nTTI, K);
            servingBeamHist = NaN(nTTI, K);
            servingBeamGainHist = NaN(nTTI, K);
            hoStateHist = strings(nTTI, K);
            measReportCount = zeros(nTTI, 1);
            beamUpdateCount = zeros(nTTI, 1);
            hoTriggerCount = zeros(nTTI, 1);
            hoStartCount = zeros(nTTI, 1);
            hoCompleteCount = zeros(nTTI, 1);
            hoInterruptedUECount = zeros(nTTI, 1);

            hoEventUE = zeros(0,1);
            hoEventFromCell = zeros(0,1);
            hoEventToCell = zeros(0,1);
            hoEventTriggerTTI = zeros(0,1);
            hoEventStartTTI = NaN(0,1);
            hoEventCompleteTTI = NaN(0,1);
            hoEventStatus = strings(0,1);
            hoEventReason = strings(0,1);

            % Event-level traces for reproducible debugging/publication.
            grantTraceCap = max(2048, round(nTTI * max(K, 1) * 4));
            grantTrace = localInitGrantTrace(grantTraceCap);
            grantTraceCount = 0;

            cellLoadTrace = localInitCellLoadTrace(nTTI * nCells);
            interferenceTrace = localInitInterferenceTrace(nTTI * K);

            beamEventCap = max(1024, round(K * (2 + ceil(nTTI / max(1, beamUpdatePeriodSlots)))));
            beamEventTrace = localInitBeamEventTrace(beamEventCap);
            beamEventCount = 0;
            prevServingBeamCell = NaN(K,1);
            prevServingBeamIdx = NaN(K,1);
            prevServingBeamGain_dB = NaN(K,1);

            captureGeometryTrace = true;
            posXHist = NaN(nTTI, K);
            posYHist = NaN(nTTI, K);
            posZHist = NaN(nTTI, K);
            headingHist = NaN(nTTI, K);

            mobModel = [];
            sinrModel = localResolveSINRModel(cfg);
            legacySINRMode = sinrModel == "legacy_margin_calibration";
            noiseFigDL_dB = double(sixgr.util.structGet(cfg, "scenario.ue.noiseFigure_dB", 9));
            noiseFigUL_dB = double(sixgr.util.structGet(cfg, "scenario.bs.noiseFigure_dB", 7));
            interfMargin_dB = double(sixgr.util.structGet(cfg, "channel.interferenceMargin_dB", 3));
            nRB = double(canonicalFrame.NRB);
            if legacySINRMode
                [fastFading_dB, interfVar_dB] = localBuildChannelVariationTraces(cfg, nTTI, K, tti_s, seed);
            else
                fastFading_dB = zeros(nTTI, K);
                interfVar_dB = zeros(nTTI, K);
            end
            mobilityEnable = logical(sixgr.util.structGet(cfg, "scenario.mobility.enable", false));
            mobilityPeriod_s = max(tti_s, double(sixgr.util.structGet(cfg, "scenario.mobility.updatePeriod_s", tti_s)));
            mobilityUpdateSlots = sixgr.util.structGet(cfg, "system.mobility.updatePeriod_slots", []);
            if isempty(mobilityUpdateSlots)
                mobilityUpdateSlots = mobilityPeriod_s / max(tti_s, eps);
            end
            mobilityUpdateSlots = max(1, round(double(mobilityUpdateSlots)));
            largeScaleUpdateSlots = sixgr.util.structGet(cfg, "system.largeScaleUpdatePeriod_slots", []);
            if isempty(largeScaleUpdateSlots)
                if mobilityEnable
                    largeScaleUpdateSlots = mobilityUpdateSlots;
                else
                    largeScaleUpdateSlots = NaN;
                end
            else
                largeScaleUpdateSlots = double(largeScaleUpdateSlots);
                if isfinite(largeScaleUpdateSlots)
                    largeScaleUpdateSlots = max(1, round(largeScaleUpdateSlots));
                else
                    largeScaleUpdateSlots = NaN;
                end
            end
            hasPeriodicLargeScaleUpdate = isfinite(largeScaleUpdateSlots) && largeScaleUpdateSlots >= 1;
            largeScaleState = struct();
            largeScaleRefreshMask = false(nTTI, 1);
            largeScalePropagationUpdateMask = false(nTTI, 1);

            ueStateDLAll = repmat(struct( ...
                "RNTI", 0, ...
                "DLBufferBytes", 0, ...
                "CQI", 1, ...
                "RI", nLayersDL, ...
                "NumLayers", nLayersDL, ...
                "TargetCodeRate", NaN, ...
                "HeadOfLineDelay_ms", 0), K, 1);
            ueStateULAll = repmat(struct( ...
                "RNTI", 0, ...
                "ULBufferBytes", 0, ...
                "CQI", 1, ...
                "RI", nLayersUL, ...
                "NumLayers", nLayersUL, ...
                "TargetCodeRate", NaN, ...
                "HeadOfLineDelay_ms", 0), K, 1);
            for k = 1:K
                ueStateDLAll(k).RNTI = k;
                ueStateULAll(k).RNTI = k;
            end

            progressEverySlots = localResolveProgressEverySlots(cfg, nTTI);
            [noProgressGuardEnabled, noProgressTimeout_s, noProgressSlotLimit] = ...
                localResolveNoProgressGuard(cfg, progressEverySlots, nTTI);
            lastProgressEmit_s = -Inf;
            replayHeartbeatEveryGrants = max(1, round(double(sixgr.util.structGet(cfg, ...
                "outputs.liveReplayHeartbeatEveryGrants", 4))));
            replayHeartbeatEverySeconds = max(5, double(sixgr.util.structGet(cfg, ...
                "outputs.liveReplayHeartbeatEverySeconds", 20)));
            lastReplayHeartbeat_s = -Inf;
            lastUsefulProgress_s = 0;
            lastUsefulProgressSlot = 0;
            lastUsefulBitCount = 0;
            stalledDemandSlotCount = 0;
            localEmitLiveProgress(cfg, log, runTimer, 0, nTTI, tti_s, ...
                "initializing", K, nCells, 0, 0, 0, 0, "system_level_lls_started");

            for t = 1:nTTI
                doMobilityUpdate = mobilityEnable && ((t == 1) || (mod(t-1, mobilityUpdateSlots) == 0));
                if doMobilityUpdate && mobilityEnable
                    dtMove_s = tti_s * min(mobilityUpdateSlots, nTTI - t + 1);
                    [ue, mobModel] = sixgr.scenario.mobility.updatePositions(ue, cfg, dtMove_s, mobModel);
                end
                if t == 1
                    localEmitLiveProgress(cfg, log, runTimer, 0, nTTI, tti_s, ...
                        "slot1_post_mobility_update", K, nCells, 0, ...
                        servedBitsTotalDL + servedBitsTotalUL, ...
                        droppedBitsTotalDL + droppedBitsTotalUL, overflowEvents, ...
                        "system_level_lls_slot1_post_mobility_update");
                end

                doPeriodicLargeScaleUpdate = hasPeriodicLargeScaleUpdate && ((t == 1) || (mod(t-1, largeScaleUpdateSlots) == 0));
                doLargeScaleUpdate = (t == 1) || doMobilityUpdate || doPeriodicLargeScaleUpdate;
                doBeamUpdate = beamEnable && (t == 1 || mod(t-1, beamUpdatePeriodSlots) == 0);
                if doBeamUpdate
                    [beamIdx, beamGain_dB] = sixgr.system.selectBestBeamPerLink( ...
                        ue.pos_m, layout.bs.pos_m, layout.bs.azim_deg, nBeams, beamSpanDeg, beamMaxGain_dB);
                    beamUpdateCount(t) = K;
                end
                reusePropagation = ~isempty(fieldnames(largeScaleState)) && ~doLargeScaleUpdate;
                if isempty(fieldnames(largeScaleState)) || doLargeScaleUpdate || doBeamUpdate
                    largeScaleState = sixgr.system.buildLargeScaleStateCache( ...
                        cfg, layout, ue, beamIdx, beamGain_dB, plModel, ...
                        "NumRB", nRB, ...
                        "PreviousState", largeScaleState, ...
                        "ReusePropagation", reusePropagation);
                    largeScaleRefreshMask(t) = true;
                    largeScalePropagationUpdateMask(t) = logical(~reusePropagation);
                end
                if t == 1
                    localEmitLiveProgress(cfg, log, runTimer, 0, nTTI, tti_s, ...
                        "slot1_large_scale_ready", K, nCells, 0, ...
                        servedBitsTotalDL + servedBitsTotalUL, ...
                        droppedBitsTotalDL + droppedBitsTotalUL, overflowEvents, ...
                        "system_level_lls_slot1_large_scale_ready");
                end
                rawRSRPCells_dBm = largeScaleState.RSRP_dBm;
                if t == 1
                    [servingIdxState, ~] = sixgr.system.selectServingCellsFromPower(rawRSRPCells_dBm);
                    servingSinceSlot(:) = 1;
                end

                % Advance ongoing handovers before making new decisions.
                for u = 1:K
                    if hoPrepRemain(u) > 0
                        hoPrepRemain(u) = hoPrepRemain(u) - 1;
                        if hoPrepRemain(u) == 0
                            if hoInterruptionSlots <= 0
                                tgt = min(max(round(hoTargetCell(u)), 1), nCells);
                                if tgt ~= servingIdxState(u)
                                    servingIdxState(u) = tgt;
                                    servingSinceSlot(u) = t;
                                end
                                hoTargetCell(u) = 0;
                                hoCompleteCount(t) = hoCompleteCount(t) + 1;
                                eIdx = hoActiveEventIdx(u);
                                if eIdx > 0
                                    hoEventStartTTI(eIdx) = t;
                                    hoEventCompleteTTI(eIdx) = t;
                                    hoEventStatus(eIdx) = "completed";
                                    hoActiveEventIdx(u) = 0;
                                end
                            else
                                hoInterRemain(u) = hoInterruptionSlots;
                                hoStartCount(t) = hoStartCount(t) + 1;
                                eIdx = hoActiveEventIdx(u);
                                if eIdx > 0 && isnan(hoEventStartTTI(eIdx))
                                    hoEventStartTTI(eIdx) = t;
                                end
                            end
                        end
                    elseif hoInterRemain(u) > 0
                        hoInterRemain(u) = hoInterRemain(u) - 1;
                        hoInterruptAccumSlots(u) = hoInterruptAccumSlots(u) + 1;
                        if hoInterRemain(u) == 0
                            tgt = min(max(round(hoTargetCell(u)), 1), nCells);
                            if tgt ~= servingIdxState(u)
                                servingIdxState(u) = tgt;
                            end
                            servingSinceSlot(u) = t;
                            hoTargetCell(u) = 0;
                            hoCompleteCount(t) = hoCompleteCount(t) + 1;
                            eIdx = hoActiveEventIdx(u);
                            if eIdx > 0
                                hoEventCompleteTTI(eIdx) = t;
                                hoEventStatus(eIdx) = "completed";
                                hoActiveEventIdx(u) = 0;
                            end
                        end
                    end
                end

                if t == 1 || mod(t-1, measPeriodSlots) == 0
                    if any(isnan(measRSRP_dBm(:)))
                        measRSRP_dBm = rawRSRPCells_dBm;
                    else
                        measRSRP_dBm = measAlpha .* measRSRP_dBm + (1 - measAlpha) .* rawRSRPCells_dBm;
                    end
                    measReportCount(t) = K;
                end
                measRSRPTrace_dBm(t,:,:) = measRSRP_dBm;

                if handoverEnable && nCells > 1
                    [bestMeasCell, bestMeasMetric_dBm] = sixgr.system.selectServingCellsFromPower( ...
                        measRSRP_dBm, "FallbackMetric_dBm", rawRSRPCells_dBm);
                    for u = 1:K
                        if hoPrepRemain(u) > 0 || hoInterRemain(u) > 0
                            continue;
                        end
                        sCell = min(max(round(servingIdxState(u)), 1), nCells);
                        sMetric = measRSRP_dBm(u, sCell);
                        if ~isfinite(sMetric)
                            sMetric = rawRSRPCells_dBm(u, sCell);
                        end
                        if ~isfinite(sMetric)
                            sCell = bestMeasCell(u);
                            servingIdxState(u) = sCell;
                            servingSinceSlot(u) = t;
                            sMetric = bestMeasMetric_dBm(u);
                        end
                        bestCell = bestMeasCell(u);
                        bestMetric = bestMeasMetric_dBm(u);
                        if ~isfinite(bestMetric) || ~isfinite(sMetric) || bestCell == sCell
                            hoCandidateCell(u) = 0;
                            hoCandidateCount(u) = 0;
                            continue;
                        end
                        isA3 = (bestMetric - sMetric) >= (hoA3Offset_dB + hoHyst_dB);
                        enoughDwell = (t - servingSinceSlot(u)) >= hoMinServingSlots;
                        if isA3 && enoughDwell
                            if hoCandidateCell(u) == bestCell
                                hoCandidateCount(u) = hoCandidateCount(u) + 1;
                            else
                                hoCandidateCell(u) = bestCell;
                                hoCandidateCount(u) = 1;
                            end
                            if hoCandidateCount(u) >= hoTTTslots
                                fromCell = sCell;
                                hoTargetCell(u) = bestCell;
                                hoCandidateCell(u) = 0;
                                hoCandidateCount(u) = 0;
                                hoTriggerCount(t) = hoTriggerCount(t) + 1;

                                if hoPrepSlots > 0
                                    hoPrepRemain(u) = hoPrepSlots;
                                elseif hoInterruptionSlots > 0
                                    hoInterRemain(u) = hoInterruptionSlots;
                                    hoStartCount(t) = hoStartCount(t) + 1;
                                else
                                    servingIdxState(u) = bestCell;
                                    servingSinceSlot(u) = t;
                                    hoTargetCell(u) = 0;
                                    hoCompleteCount(t) = hoCompleteCount(t) + 1;
                                end

                                eIdx = numel(hoEventUE) + 1;
                                hoEventUE(eIdx,1) = u;
                                hoEventFromCell(eIdx,1) = fromCell;
                                hoEventToCell(eIdx,1) = bestCell;
                                hoEventTriggerTTI(eIdx,1) = t;
                                hoEventStartTTI(eIdx,1) = NaN;
                                hoEventCompleteTTI(eIdx,1) = NaN;
                                hoEventStatus(eIdx,1) = "triggered";
                                hoEventReason(eIdx,1) = "A3_TTT";
                                hoActiveEventIdx(u) = eIdx;

                                if hoPrepSlots <= 0 && hoInterruptionSlots > 0
                                    hoEventStartTTI(eIdx,1) = t;
                                elseif hoPrepSlots <= 0 && hoInterruptionSlots <= 0
                                    hoEventStartTTI(eIdx,1) = t;
                                    hoEventCompleteTTI(eIdx,1) = t;
                                    hoEventStatus(eIdx,1) = "completed";
                                    hoActiveEventIdx(u) = 0;
                                end
                            end
                        else
                            hoCandidateCell(u) = 0;
                            hoCandidateCount(u) = 0;
                        end
                    end
                end

                interruptedMask = hoInterRemain > 0;
                if hoBlockDuringPrep
                    interruptedMask = interruptedMask | (hoPrepRemain > 0);
                end
                hoInterruptedUECount(t) = sum(interruptedMask);

                servingIdx = min(max(round(servingIdxState), 1), nCells);
                servingIdxState = servingIdx;
                linIdx = sub2ind(size(largeScaleState.d2d_m), (1:K).', servingIdx);
                dServe = largeScaleState.d2d_m(linIdx);
                dServeHist(t,:) = dServe(:).';
                pl_dB = largeScaleState.Pathloss_dB(linIdx);
                rxP_dBm = largeScaleState.RxPower_dBm(linIdx);
                ulLinkPowerCells_dBm = localBuildULLinkPowerTable(cfg, largeScaleState);
                rxPUL_dBm = ulLinkPowerCells_dBm(linIdx);
                rsrpServing_dBm = largeScaleState.RSRP_dBm(linIdx);
                pathlossHist(t,:) = pl_dB(:).';
                rxPowerHist(t,:) = rxP_dBm(:).';
                desiredPowerHistDL(t,:) = rxP_dBm(:).';
                desiredPowerHistUL(t,:) = rxPUL_dBm(:).';
                rsrpHist(t,:) = rsrpServing_dBm(:).';
                servingCellHist(t,:) = servingIdx(:).';
                servingBeamNow = localGatherServingValues(double(beamIdx), servingIdx);
                servingBeamGainNow_dB = localGatherServingValues(beamGain_dB, servingIdx);
                servingBeamHist(t,:) = servingBeamNow(:).';
                servingBeamGainHist(t,:) = servingBeamGainNow_dB(:).';
                hoStateHist(t,:) = localEncodeHOState(hoPrepRemain, hoInterRemain).';
                if captureGeometryTrace
                    posXHist(t,:) = ue.pos_m(:,1).';
                    posYHist(t,:) = ue.pos_m(:,2).';
                    posZHist(t,:) = ue.pos_m(:,3).';
                    headingHist(t,:) = ue.heading_deg(:).';
                end

                [slotDL, slotUL, slotLabel] = localSlotDuplexState(cfg, t);
                slotDirection(t) = slotLabel;
                dlBudget = localSlotBudget(cfg, t, nRB, "DL");
                ulBudget = localSlotBudget(cfg, t, nRB, "UL");
                slotDLDataSchedulable = slotDL && ...
                    localSlotBudgetSupportsExecutableDataGrants(cfg, "DL", dlBudget);
                slotULDataSchedulable = slotUL && ...
                    localSlotBudgetSupportsExecutableDataGrants(cfg, "UL", ulBudget);

                [beamEventTrace, beamEventCount] = localAppendBeamEvents( ...
                    beamEventTrace, beamEventCount, t, tti_s, servingIdx, ...
                    servingBeamNow, servingBeamGainNow_dB, ...
                    prevServingBeamCell, prevServingBeamIdx, prevServingBeamGain_dB);
                prevServingBeamCell = servingIdx;
                prevServingBeamIdx = servingBeamNow;
                prevServingBeamGain_dB = servingBeamGainNow_dB;

                queueBitsDL = queueBitsDL + traffic.OfferedBitsDL(t,:).';
                queueBitsUL = queueBitsUL + traffic.OfferedBitsUL(t,:).';
                queueBitsDL_Start = queueBitsDL;
                queueBitsUL_Start = queueBitsUL;
                offeredCellDL = accumarray(servingIdx, traffic.OfferedBitsDL(t,:).', [nCells, 1], @sum, 0);
                offeredCellUL = accumarray(servingIdx, traffic.OfferedBitsUL(t,:).', [nCells, 1], @sum, 0);

                activeDL = find(queueBitsDL > 0 & ~interruptedMask);
                activeUL = find(queueBitsUL > 0 & ~interruptedMask);
                if ~slotDLDataSchedulable
                    activeDL = zeros(0,1);
                end
                if ~slotULDataSchedulable
                    activeUL = zeros(0,1);
                end
                activeMask = false(K,1);
                activeMask(activeDL) = true;
                activeMask(activeUL) = true;
                activeUECount(t) = sum(activeMask);
                if t == 1
                    localEmitLiveProgress(cfg, log, runTimer, 0, nTTI, tti_s, ...
                        slotLabel, activeUECount(t), nCells, 0, ...
                        servedBitsTotalDL + servedBitsTotalUL, ...
                        droppedBitsTotalDL + droppedBitsTotalUL, overflowEvents, ...
                        "system_level_lls_slot1_active_ues_ready");
                end
                ueByCellDL = localSplitUEByServingCell(activeDL, servingIdx, nCells);
                ueByCellUL = localSplitUEByServingCell(activeUL, servingIdx, nCells);
                activeCellDL = cellfun("length", ueByCellDL);
                activeCellUL = cellfun("length", ueByCellUL);
                if t == 1
                    localEmitLiveProgress(cfg, log, runTimer, 0, nTTI, tti_s, ...
                        slotLabel, activeUECount(t), nCells, 0, ...
                        servedBitsTotalDL + servedBitsTotalUL, ...
                        droppedBitsTotalDL + droppedBitsTotalUL, overflowEvents, ...
                        "system_level_lls_slot1_ue_by_cell_ready");
                end

                if legacySINRMode
                    [schedSinrDL_dB, schedSinrUL_dB, schedPowerState] = localBuildLegacySINRState( ...
                        rxP_dBm, rxPUL_dBm, slotDL, slotUL, dlBudget, ulBudget, scs_kHz, ...
                        noiseFigDL_dB, noiseFigUL_dB, fastFading_dB(t,:).', interfVar_dB(t,:).', ...
                        interfMargin_dB, ulSinrOffset_dB);
                else
                    schedPowerState = localBuildExplicitSINRState( ...
                        rxP_dBm, rxPUL_dBm, largeScaleState.RxPower_dBm, ulLinkPowerCells_dBm, ...
                        servingIdx, slotDL, slotUL, dlBudget, ulBudget, scs_kHz, noiseFigDL_dB, noiseFigUL_dB, ...
                        activeCellDL > 0, activeUL, servingIdx(activeUL));
                    schedSinrDL_dB = schedPowerState.SINR_DL_dB;
                    schedSinrUL_dB = schedPowerState.SINR_UL_dB;
                end
                cqiDLVec = localResolveWidebandCQI(schedSinrDL_dB, cfg, "DL");
                cqiULVec = localResolveWidebandCQI(schedSinrUL_dB, cfg, "UL");
                if t == 1
                    localEmitLiveProgress(cfg, log, runTimer, 0, nTTI, tti_s, ...
                        slotLabel, activeUECount(t), nCells, 0, ...
                        servedBitsTotalDL + servedBitsTotalUL, ...
                        droppedBitsTotalDL + droppedBitsTotalUL, overflowEvents, ...
                        "system_level_lls_slot1_scheduler_inputs_ready");
                end

                grantsDL = struct([]);
                grantsUL = struct([]);
                grantCellDL = zeros(0,1);
                grantCellUL = zeros(0,1);
                grantCountDLByCell = zeros(nCells,1);
                grantCountULByCell = zeros(nCells,1);
                servedCellDL = zeros(nCells,1);
                servedCellUL = zeros(nCells,1);
                fbDLByCell = cell(nCells,1);
                fbULByCell = cell(nCells,1);
                fbDLWriteIdx = zeros(nCells,1);
                fbULWriteIdx = zeros(nCells,1);

                if ~isempty(activeDL)
                    dlBufBytes = floor(max(queueBitsDL(activeDL), 0) / 8);
                    for ii = 1:numel(activeDL)
                        k = activeDL(ii);
                        ueStateDLAll(k).DLBufferBytes = dlBufBytes(ii);
                        ueStateDLAll(k).CQI = cqiDLVec(k);
                        ueStateDLAll(k).HeadOfLineDelay_ms = 0;
                    end
                end
                if ~isempty(activeUL)
                    ulBufBytes = floor(max(queueBitsUL(activeUL), 0) / 8);
                    for ii = 1:numel(activeUL)
                        k = activeUL(ii);
                        ueStateULAll(k).ULBufferBytes = ulBufBytes(ii);
                        ueStateULAll(k).CQI = cqiULVec(k);
                        ueStateULAll(k).HeadOfLineDelay_ms = 0;
                    end
                end

                if slotDLDataSchedulable
                    activeCellsDL = find(activeCellDL > 0).';
                    grantSetsDL = cell(numel(activeCellsDL), 1);
                    grantCellsDL = cell(numel(activeCellsDL), 1);
                    nGrantSetsDL = 0;
                    for ci = 1:numel(activeCellsDL)
                        cellId = activeCellsDL(ci);
                        ueCell = ueByCellDL{cellId};
                        if isempty(ueCell)
                            continue;
                        end
                        if t == 1
                            localEmitLiveProgress(cfg, log, runTimer, 0, nTTI, tti_s, ...
                                slotLabel, activeUECount(t), nCells, 0, ...
                                servedBitsTotalDL + servedBitsTotalUL, ...
                                droppedBitsTotalDL + droppedBitsTotalUL, overflowEvents, ...
                                "system_level_lls_slot1_dl_scheduler_cell_" + string(cellId) + "_started");
                        end
                        ueStateDL = ueStateDLAll(ueCell);
                        schedCellTimer = tic;
                        try
                            [gCell, ~] = schedDLCells{cellId}.schedule(t-1, ueStateDL, dlBudget);
                        catch MEs
                            gCell = struct([]);
                            schedulingError = "DL scheduling failed at slot " + string(t) + ...
                                " cell " + string(cellId) + ": " + string(MEs.message);
                            out.Errors(end+1,1) = schedulingError;
                            log.warn(char(schedulingError));
                        end
                        schedCellElapsed_s = toc(schedCellTimer);
                        if t == 1
                            log.info(sprintf("Slot1 DL scheduler cell=%d activeUE=%d grants=%d elapsed_s=%.3f", ...
                                double(cellId), double(numel(ueCell)), double(numel(gCell)), double(schedCellElapsed_s)));
                            localEmitLiveProgress(cfg, log, runTimer, 0, nTTI, tti_s, ...
                                slotLabel, activeUECount(t), nCells, numel(gCell), ...
                                servedBitsTotalDL + servedBitsTotalUL, ...
                                droppedBitsTotalDL + droppedBitsTotalUL, overflowEvents, ...
                                "system_level_lls_slot1_dl_scheduler_cell_" + string(cellId) + "_finished");
                        end
                        if ~isempty(gCell)
                            nGrantSetsDL = nGrantSetsDL + 1;
                            grantSetsDL{nGrantSetsDL} = gCell(:);
                            grantCellsDL{nGrantSetsDL} = repmat(cellId, numel(gCell), 1);
                        end
                    end
                    if nGrantSetsDL > 0
                        grantsDL = localVertcatGrantSets(grantSetsDL, nGrantSetsDL);
                        grantCellDL = vertcat(grantCellsDL{1:nGrantSetsDL});
                    end
                    if t == 1
                        localEmitLiveProgress(cfg, log, runTimer, 0, nTTI, tti_s, ...
                            slotLabel, activeUECount(t), nCells, numel(grantsDL), ...
                            servedBitsTotalDL + servedBitsTotalUL, ...
                            droppedBitsTotalDL + droppedBitsTotalUL, overflowEvents, ...
                            "system_level_lls_slot1_dl_scheduler_ready");
                    end
                end

                if slotULDataSchedulable
                    activeCellsUL = find(activeCellUL > 0).';
                    grantSetsUL = cell(numel(activeCellsUL), 1);
                    grantCellsUL = cell(numel(activeCellsUL), 1);
                    nGrantSetsUL = 0;
                    for ci = 1:numel(activeCellsUL)
                        cellId = activeCellsUL(ci);
                        ueCell = ueByCellUL{cellId};
                        if isempty(ueCell)
                            continue;
                        end
                        if t == 1
                            localEmitLiveProgress(cfg, log, runTimer, 0, nTTI, tti_s, ...
                                slotLabel, activeUECount(t), nCells, numel(grantsDL), ...
                                servedBitsTotalDL + servedBitsTotalUL, ...
                                droppedBitsTotalDL + droppedBitsTotalUL, overflowEvents, ...
                                "system_level_lls_slot1_ul_scheduler_cell_" + string(cellId) + "_started");
                        end
                        ueStateUL = ueStateULAll(ueCell);
                        schedCellTimer = tic;
                        try
                            [gCell, ~] = schedULCells{cellId}.schedule(t-1, ueStateUL, ulBudget);
                        catch MEs
                            gCell = struct([]);
                            schedulingError = "UL scheduling failed at slot " + string(t) + ...
                                " cell " + string(cellId) + ": " + string(MEs.message);
                            out.Errors(end+1,1) = schedulingError;
                            log.warn(char(schedulingError));
                        end
                        schedCellElapsed_s = toc(schedCellTimer);
                        if t == 1
                            log.info(sprintf("Slot1 UL scheduler cell=%d activeUE=%d grants=%d elapsed_s=%.3f", ...
                                double(cellId), double(numel(ueCell)), double(numel(gCell)), double(schedCellElapsed_s)));
                            localEmitLiveProgress(cfg, log, runTimer, 0, nTTI, tti_s, ...
                                slotLabel, activeUECount(t), nCells, numel(grantsDL) + numel(gCell), ...
                                servedBitsTotalDL + servedBitsTotalUL, ...
                                droppedBitsTotalDL + droppedBitsTotalUL, overflowEvents, ...
                                "system_level_lls_slot1_ul_scheduler_cell_" + string(cellId) + "_finished");
                        end
                        if ~isempty(gCell)
                            nGrantSetsUL = nGrantSetsUL + 1;
                            grantSetsUL{nGrantSetsUL} = gCell(:);
                            grantCellsUL{nGrantSetsUL} = repmat(cellId, numel(gCell), 1);
                        end
                    end
                    if nGrantSetsUL > 0
                        grantsUL = localVertcatGrantSets(grantSetsUL, nGrantSetsUL);
                        grantCellUL = vertcat(grantCellsUL{1:nGrantSetsUL});
                    end
                    if t == 1
                        localEmitLiveProgress(cfg, log, runTimer, 0, nTTI, tti_s, ...
                            slotLabel, activeUECount(t), nCells, numel(grantsDL) + numel(grantsUL), ...
                            servedBitsTotalDL + servedBitsTotalUL, ...
                            droppedBitsTotalDL + droppedBitsTotalUL, overflowEvents, ...
                            "system_level_lls_slot1_ul_scheduler_ready");
                    end
                end
                if t == 1
                    localEmitLiveProgress(cfg, log, runTimer, 0, nTTI, tti_s, ...
                        slotLabel, activeUECount(t), nCells, numel(grantsDL) + numel(grantsUL), ...
                        servedBitsTotalDL + servedBitsTotalUL, ...
                        droppedBitsTotalDL + droppedBitsTotalUL, overflowEvents, ...
                        "system_level_lls_slot1_scheduler_ready");
                end

                if ~isempty(grantCellDL)
                    grantCountDLByCell = accumarray(grantCellDL, 1, [nCells, 1], @sum, 0);
                    fbDLCount = accumarray(grantCellDL, 1, [nCells, 1]);
                    for c = 1:nCells
                        if fbDLCount(c) > 0
                            fbDLByCell{c} = repmat(struct( ...
                                "RNTI", 0, "TBSBits", 0, "Ack", false, ...
                                "HarqID", NaN, "RV", NaN, "NDI", NaN, ...
                                "IsRetransmission", false), fbDLCount(c), 1);
                        end
                    end
                end
                if ~isempty(grantCellUL)
                    grantCountULByCell = accumarray(grantCellUL, 1, [nCells, 1], @sum, 0);
                    fbULCount = accumarray(grantCellUL, 1, [nCells, 1]);
                    for c = 1:nCells
                        if fbULCount(c) > 0
                            fbULByCell{c} = repmat(struct( ...
                                "RNTI", 0, "TBSBits", 0, "Ack", false, ...
                                "HarqID", NaN, "RV", NaN, "NDI", NaN, ...
                                "IsRetransmission", false), fbULCount(c), 1);
                        end
                    end
                end

                if legacySINRMode
                    finalPowerState = localBuildLegacySINRState( ...
                        rxP_dBm, rxPUL_dBm, slotDL, slotUL, dlBudget, ulBudget, scs_kHz, ...
                        noiseFigDL_dB, noiseFigUL_dB, fastFading_dB(t,:).', interfVar_dB(t,:).', ...
                        interfMargin_dB, ulSinrOffset_dB);
                else
                    finalPowerState = localBuildExplicitSINRState( ...
                        rxP_dBm, rxPUL_dBm, largeScaleState.RxPower_dBm, ulLinkPowerCells_dBm, ...
                        servingIdx, slotDL, slotUL, dlBudget, ulBudget, scs_kHz, noiseFigDL_dB, noiseFigUL_dB, ...
                        grantCountDLByCell > 0, localGrantRNTI(grantsUL), grantCellUL);
                end

                sinr_dB = finalPowerState.SINR_DL_dB;
                sinrUL_dB = finalPowerState.SINR_UL_dB;
                sinrHist(t,:) = sinr_dB(:).';
                sinrHistUL(t,:) = sinrUL_dB(:).';
                ebnoHist(t,:) = localSINRtoEbNo(sinr_dB(:)).';
                desiredPowerHistDL(t,:) = finalPowerState.DesiredPowerDL_dBm(:).';
                desiredPowerHistUL(t,:) = finalPowerState.DesiredPowerUL_dBm(:).';
                interferencePowerHistDL(t,:) = finalPowerState.InterferencePowerDL_dBm(:).';
                interferencePowerHistUL(t,:) = finalPowerState.InterferencePowerUL_dBm(:).';
                noisePowerHistDL(t,:) = finalPowerState.NoisePowerDL_dBm(:).';
                noisePowerHistUL(t,:) = finalPowerState.NoisePowerUL_dBm(:).';
                interfererCellCountHistDL(t,:) = finalPowerState.ActiveInterfererCountDL(:).';
                interfererCellCountHistUL(t,:) = finalPowerState.ActiveInterfererCountUL(:).';

                intrfIdx = (t-1) * K + (1:K);
                interferenceTrace.TTI(intrfIdx) = t;
                interferenceTrace.Time_s(intrfIdx) = (t - 1) * tti_s;
                interferenceTrace.UE(intrfIdx) = (1:K).';
                interferenceTrace.ServingCell(intrfIdx) = servingIdx(:);
                interferenceTrace.Pathloss_dB(intrfIdx) = pl_dB(:);
                interferenceTrace.RxPower_dBm(intrfIdx) = finalPowerState.DesiredPowerDL_dBm(:);
                interferenceTrace.Noise_dBm(intrfIdx) = finalPowerState.NoisePowerDL_dBm(:);
                interferenceTrace.InterferenceMargin_dB(intrfIdx) = finalPowerState.LegacyInterferenceMarginDL_dB(:);
                interferenceTrace.SmallScaleFading_dB(intrfIdx) = finalPowerState.SmallScaleFading_dB(:);
                interferenceTrace.InterferenceVariation_dB(intrfIdx) = finalPowerState.InterferenceVariation_dB(:);
                interferenceTrace.DesiredPowerDL_dBm(intrfIdx) = finalPowerState.DesiredPowerDL_dBm(:);
                interferenceTrace.InterferencePowerDL_dBm(intrfIdx) = finalPowerState.InterferencePowerDL_dBm(:);
                interferenceTrace.NoiseDL_dBm(intrfIdx) = finalPowerState.NoisePowerDL_dBm(:);
                interferenceTrace.ActiveInterfererCountDL(intrfIdx) = finalPowerState.ActiveInterfererCountDL(:);
                interferenceTrace.DesiredPowerUL_dBm(intrfIdx) = finalPowerState.DesiredPowerUL_dBm(:);
                interferenceTrace.InterferencePowerUL_dBm(intrfIdx) = finalPowerState.InterferencePowerUL_dBm(:);
                interferenceTrace.NoiseUL_dBm(intrfIdx) = finalPowerState.NoisePowerUL_dBm(:);
                interferenceTrace.ActiveInterfererCountUL(intrfIdx) = finalPowerState.ActiveInterfererCountUL(:);
                interferenceTrace.SINR_DL_dB(intrfIdx) = sinr_dB(:);
                interferenceTrace.SINR_UL_dB(intrfIdx) = sinrUL_dB(:);
                interferenceTrace.RSRP_dBm(intrfIdx) = rsrpHist(t,:).';

                if ~isempty(grantsDL)
                    scheduledUE_DL(t) = numel(unique(double([grantsDL.RNTI])));
                end
                if ~isempty(grantsUL)
                    scheduledUE_UL(t) = numel(unique(double([grantsUL.RNTI])));
                end
                grantCountDL(t) = numel(grantsDL);
                grantCountUL(t) = numel(grantsUL);

                for gi = 1:numel(grantsDL)
                    g = grantsDL(gi);
                    cellId = min(max(round(grantCellDL(gi)), 1), nCells);
                    u = min(max(1, round(double(g.RNTI))), K);
                    prbCount = 0;
                    if isfield(g, "PRBSet")
                        prbCount = numel(g.PRBSet);
                    end
                    if prbCount <= 0
                        if isfield(g, "NPRB")
                            prbCount = max(1, round(double(g.NPRB)));
                        else
                            prbCount = nRB;
                        end
                    end
                    if isfield(g, "CQIUsed")
                        cqiUsed = double(g.CQIUsed);
                    else
                        cqiUsed = double(cqiDLVec(u));
                    end
                    gTBS = g;
                    if (~isfield(gTBS, "PRBSet") || isempty(gTBS.PRBSet)) && ...
                            (~isfield(gTBS, "NPRB") || isempty(gTBS.NPRB))
                        gTBS.NPRB = prbCount;
                    end
                    [tbsBits, ~] = sixgr.util.resolveGrantTBSBits(gTBS, ...
                        sprintf("SystemLevelRunner DL TTI=%d Cell=%d RNTI=%d", ...
                        round(t), round(cellId), round(u)));
                    if tbsBits <= 0
                        continue;
                    end
                    mcsIdx = double(localResolveGrantMCSIndex(cfg, g, cqiUsed, "DL"));
                    if isfield(g, "NumLayers")
                        numLayers = double(g.NumLayers);
                    else
                        numLayers = nLayersDL;
                    end
                    if isfield(g, "TargetCodeRate")
                        tgtCodeRate = double(g.TargetCodeRate);
                    else
                        tgtCodeRate = tcrDL;
                    end
                    ctxDL = struct( ...
                        "Direction", "DL", ...
                        "SINR_dB", sinr_dB(u), ...
                        "CQI", cqiUsed, ...
                        "MCSIndex", mcsIdx, ...
                        "PRBCount", prbCount, ...
                        "NumLayers", numLayers, ...
                        "TargetCodeRate", tgtCodeRate, ...
                        "ChannelModel", channelModel, ...
                        "DopplerHz", dopplerHz, ...
                        "SCS_kHz", scs_kHz, ...
                        "ServingCellID", cellId, ...
                        "TTI", t, ...
                        "GrantIndex", gi, ...
                        "GrantCountInSlot", numel(grantsDL), ...
                        "Grant", g, ...
                        "ReplayUserContext", localBuildReplayUserContext("DL", u, cellId, largeScaleState, finalPowerState), ...
                        "TBSBits", tbsBits);
                    harqIdDL = double(sixgr.util.structGet(sixgr.util.structGet(g, "HARQ", struct()), "HarqID", NaN));
                    if ~isempty(schedDLCells{cellId}.HARQ) && isfinite(harqIdDL)
                        schedDLCells{cellId}.HARQ.onTx(u, harqIdDL, uint8([]), g, t - 1);
                    end
                    if localShouldEmitReplayHeartbeat(gi, numel(grantsDL), runTimer, ...
                            lastReplayHeartbeat_s, replayHeartbeatEveryGrants, replayHeartbeatEverySeconds)
                        localEmitLiveReplayProgress(cfg, log, runTimer, t - 1, nTTI, tti_s, ...
                            slotLabel, activeUECount(t), nCells, numel(grantsDL) + numel(grantsUL), ...
                            servedBitsTotalDL + servedBitsTotalUL, ...
                            droppedBitsTotalDL + droppedBitsTotalUL, overflowEvents, ...
                            "system_level_lls_dl_replay_progress", "DL", gi, numel(grantsDL), cellId, u);
                        lastReplayHeartbeat_s = toc(runTimer);
                    end
                    if t == 1 && gi == 1
                        localEmitLiveProgress(cfg, log, runTimer, 0, nTTI, tti_s, ...
                            slotLabel, activeUECount(t), nCells, numel(grantsDL) + numel(grantsUL), ...
                            servedBitsTotalDL + servedBitsTotalUL, ...
                            droppedBitsTotalDL + droppedBitsTotalUL, overflowEvents, ...
                            "system_level_lls_slot1_first_dl_replay_started");
                    end
                    [okDL, blerDL] = phy.decode(ctxDL);
                    replayDL = localLastPHYReplay(phy);
                    replayTbsDL = localReplayTransportBlockSize(replayDL, tbsBits);
                    decisionUnavailableDL = localPHYDecisionUnavailable(replayDL);
                    if t == 1 && gi == 1
                        localEmitLiveProgress(cfg, log, runTimer, 0, nTTI, tti_s, ...
                            slotLabel, activeUECount(t), nCells, numel(grantsDL) + numel(grantsUL), ...
                            servedBitsTotalDL + servedBitsTotalUL, ...
                            droppedBitsTotalDL + droppedBitsTotalUL, overflowEvents, ...
                            "system_level_lls_slot1_first_dl_replay_finished");
                    end
                    if isnan(blerHistDL(t,u))
                        blerHistDL(t,u) = blerDL;
                    else
                        blerHistDL(t,u) = 0.5 * (blerHistDL(t,u) + blerDL);
                    end
                    if decisionUnavailableDL
                        decodeUnavailableCountDL = decodeUnavailableCountDL + 1;
                    elseif okDL
                        servedDL = min(queueBitsDL(u), replayTbsDL);
                        queueBitsDL(u) = queueBitsDL(u) - servedDL;
                        servedBitsTotalDL = servedBitsTotalDL + servedDL;
                        servedBitsTTI_DL(t) = servedBitsTTI_DL(t) + servedDL;
                        servedPerUE_DL(u) = servedPerUE_DL(u) + servedDL;
                        servedCellDL(cellId) = servedCellDL(cellId) + servedDL;
                        decodeOkCountDL = decodeOkCountDL + 1;
                    else
                        decodeFailCountDL = decodeFailCountDL + 1;
                    end
                    [grantTrace, grantTraceCount] = localAppendGrantTrace( ...
                        grantTrace, grantTraceCount, t, tti_s, slotLabel, "DL", ...
                        cellId, g, prbCount, replayTbsDL, cqiUsed, mcsIdx, numLayers, ...
                        tgtCodeRate, sinr_dB(u), blerDL, logical(okDL), replayDL);
                    if ~decisionUnavailableDL
                        fbHarqDL = sixgr.util.structGet(g, "HARQ", struct());
                        fb = struct( ...
                            "RNTI", u, ...
                            "TBSBits", replayTbsDL, ...
                            "Ack", logical(okDL), ...
                            "HarqID", double(sixgr.util.structGet(fbHarqDL, "HarqID", NaN)), ...
                            "RV", double(sixgr.util.structGet(fbHarqDL, "RV", NaN)), ...
                            "NDI", double(sixgr.util.structGet(fbHarqDL, "NDI", NaN)), ...
                            "IsRetransmission", logical(sixgr.util.structGet(fbHarqDL, "IsRetransmission", false)));
                        fbIdx = fbDLWriteIdx(cellId) + 1;
                        if ~isempty(fbDLByCell{cellId}) && fbIdx <= numel(fbDLByCell{cellId})
                            fbDLByCell{cellId}(fbIdx) = fb;
                            fbDLWriteIdx(cellId) = fbIdx;
                        end
                    end
                end

                for gi = 1:numel(grantsUL)
                    g = grantsUL(gi);
                    cellId = min(max(round(grantCellUL(gi)), 1), nCells);
                    u = min(max(1, round(double(g.RNTI))), K);
                    prbCount = 0;
                    if isfield(g, "PRBSet")
                        prbCount = numel(g.PRBSet);
                    end
                    if prbCount <= 0
                        if isfield(g, "NPRB")
                            prbCount = max(1, round(double(g.NPRB)));
                        else
                            prbCount = nRB;
                        end
                    end
                    if isfield(g, "CQIUsed")
                        cqiUsed = double(g.CQIUsed);
                    else
                        cqiUsed = double(cqiULVec(u));
                    end
                    gTBS = g;
                    if (~isfield(gTBS, "PRBSet") || isempty(gTBS.PRBSet)) && ...
                            (~isfield(gTBS, "NPRB") || isempty(gTBS.NPRB))
                        gTBS.NPRB = prbCount;
                    end
                    [tbsBits, ~] = sixgr.util.resolveGrantTBSBits(gTBS, ...
                        sprintf("SystemLevelRunner UL TTI=%d Cell=%d RNTI=%d", ...
                        round(t), round(cellId), round(u)));
                    if tbsBits <= 0
                        continue;
                    end
                    mcsIdx = double(localResolveGrantMCSIndex(cfg, g, cqiUsed, "UL"));
                    if isfield(g, "NumLayers")
                        numLayers = double(g.NumLayers);
                    else
                        numLayers = nLayersUL;
                    end
                    if isfield(g, "TargetCodeRate")
                        tgtCodeRate = double(g.TargetCodeRate);
                    else
                        tgtCodeRate = tcrUL;
                    end
                    ctxUL = struct( ...
                        "Direction", "UL", ...
                        "SINR_dB", sinrUL_dB(u), ...
                        "CQI", cqiUsed, ...
                        "MCSIndex", mcsIdx, ...
                        "PRBCount", prbCount, ...
                        "NumLayers", numLayers, ...
                        "TargetCodeRate", tgtCodeRate, ...
                        "ChannelModel", channelModel, ...
                        "DopplerHz", dopplerHz, ...
                        "SCS_kHz", scs_kHz, ...
                        "ServingCellID", cellId, ...
                        "TTI", t, ...
                        "GrantIndex", gi, ...
                        "GrantCountInSlot", numel(grantsUL), ...
                        "Grant", g, ...
                        "ReplayUserContext", localBuildReplayUserContext("UL", u, cellId, largeScaleState, finalPowerState), ...
                        "TBSBits", tbsBits);
                    harqIdUL = double(sixgr.util.structGet(sixgr.util.structGet(g, "HARQ", struct()), "HarqID", NaN));
                    if ~isempty(schedULCells{cellId}.HARQ) && isfinite(harqIdUL)
                        schedULCells{cellId}.HARQ.onTx(u, harqIdUL, uint8([]), g, t - 1);
                    end
                    if localShouldEmitReplayHeartbeat(gi, numel(grantsUL), runTimer, ...
                            lastReplayHeartbeat_s, replayHeartbeatEveryGrants, replayHeartbeatEverySeconds)
                        localEmitLiveReplayProgress(cfg, log, runTimer, t - 1, nTTI, tti_s, ...
                            slotLabel, activeUECount(t), nCells, numel(grantsDL) + numel(grantsUL), ...
                            servedBitsTotalDL + servedBitsTotalUL, ...
                            droppedBitsTotalDL + droppedBitsTotalUL, overflowEvents, ...
                            "system_level_lls_ul_replay_progress", "UL", gi, numel(grantsUL), cellId, u);
                        lastReplayHeartbeat_s = toc(runTimer);
                    end
                    if t == 1 && gi == 1
                        localEmitLiveProgress(cfg, log, runTimer, 0, nTTI, tti_s, ...
                            slotLabel, activeUECount(t), nCells, numel(grantsDL) + numel(grantsUL), ...
                            servedBitsTotalDL + servedBitsTotalUL, ...
                            droppedBitsTotalDL + droppedBitsTotalUL, overflowEvents, ...
                            "system_level_lls_slot1_first_ul_replay_started");
                    end
                    [okUL, blerUL] = phy.decode(ctxUL);
                    replayUL = localLastPHYReplay(phy);
                    replayTbsUL = localReplayTransportBlockSize(replayUL, tbsBits);
                    decisionUnavailableUL = localPHYDecisionUnavailable(replayUL);
                    if t == 1 && gi == 1
                        localEmitLiveProgress(cfg, log, runTimer, 0, nTTI, tti_s, ...
                            slotLabel, activeUECount(t), nCells, numel(grantsDL) + numel(grantsUL), ...
                            servedBitsTotalDL + servedBitsTotalUL, ...
                            droppedBitsTotalDL + droppedBitsTotalUL, overflowEvents, ...
                            "system_level_lls_slot1_first_ul_replay_finished");
                    end
                    if isnan(blerHistUL(t,u))
                        blerHistUL(t,u) = blerUL;
                    else
                        blerHistUL(t,u) = 0.5 * (blerHistUL(t,u) + blerUL);
                    end
                    if decisionUnavailableUL
                        decodeUnavailableCountUL = decodeUnavailableCountUL + 1;
                    elseif okUL
                        servedUL = min(queueBitsUL(u), replayTbsUL);
                        queueBitsUL(u) = queueBitsUL(u) - servedUL;
                        servedBitsTotalUL = servedBitsTotalUL + servedUL;
                        servedBitsTTI_UL(t) = servedBitsTTI_UL(t) + servedUL;
                        servedPerUE_UL(u) = servedPerUE_UL(u) + servedUL;
                        servedCellUL(cellId) = servedCellUL(cellId) + servedUL;
                        decodeOkCountUL = decodeOkCountUL + 1;
                    else
                        decodeFailCountUL = decodeFailCountUL + 1;
                    end
                    [grantTrace, grantTraceCount] = localAppendGrantTrace( ...
                        grantTrace, grantTraceCount, t, tti_s, slotLabel, "UL", ...
                        cellId, g, prbCount, replayTbsUL, cqiUsed, mcsIdx, numLayers, ...
                        tgtCodeRate, sinrUL_dB(u), blerUL, logical(okUL), replayUL);
                    if ~decisionUnavailableUL
                        fbHarqUL = sixgr.util.structGet(g, "HARQ", struct());
                        fb = struct( ...
                            "RNTI", u, ...
                            "TBSBits", replayTbsUL, ...
                            "Ack", logical(okUL), ...
                            "HarqID", double(sixgr.util.structGet(fbHarqUL, "HarqID", NaN)), ...
                            "RV", double(sixgr.util.structGet(fbHarqUL, "RV", NaN)), ...
                            "NDI", double(sixgr.util.structGet(fbHarqUL, "NDI", NaN)), ...
                            "IsRetransmission", logical(sixgr.util.structGet(fbHarqUL, "IsRetransmission", false)));
                        fbIdx = fbULWriteIdx(cellId) + 1;
                        if ~isempty(fbULByCell{cellId}) && fbIdx <= numel(fbULByCell{cellId})
                            fbULByCell{cellId}(fbIdx) = fb;
                            fbULWriteIdx(cellId) = fbIdx;
                        end
                    end
                end

                for c = 1:nCells
                    if ~isempty(fbDLByCell{c})
                        nFb = fbDLWriteIdx(c);
                        if nFb > 0
                            schedDLCells{c}.updateAfterRx(fbDLByCell{c}(1:nFb));
                        end
                    end
                    if ~isempty(fbULByCell{c})
                        nFb = fbULWriteIdx(c);
                        if nFb > 0
                            schedULCells{c}.updateAfterRx(fbULByCell{c}(1:nFb));
                        end
                    end
                end

                overflowDL = max(queueBitsDL - qMaxBits, 0);
                overflowUL = max(queueBitsUL - qMaxBits, 0);
                droppedCellDL = accumarray(servingIdx, overflowDL, [nCells, 1], @sum, 0);
                droppedCellUL = accumarray(servingIdx, overflowUL, [nCells, 1], @sum, 0);
                if any(overflowDL > 0) || any(overflowUL > 0)
                    ovDL = sum(overflowDL);
                    ovUL = sum(overflowUL);
                    droppedBitsTotalDL = droppedBitsTotalDL + ovDL;
                    droppedBitsTotalUL = droppedBitsTotalUL + ovUL;
                    droppedBitsTTI_DL(t) = droppedBitsTTI_DL(t) + ovDL;
                    droppedBitsTTI_UL(t) = droppedBitsTTI_UL(t) + ovUL;
                    droppedPerUE_DL = droppedPerUE_DL + overflowDL;
                    droppedPerUE_UL = droppedPerUE_UL + overflowUL;
                    queueBitsDL = min(queueBitsDL, qMaxBits);
                    queueBitsUL = min(queueBitsUL, qMaxBits);
                    overflowEvents = overflowEvents + 1;
                end

                queueCellDL_End = accumarray(servingIdx, queueBitsDL, [nCells, 1], @sum, 0);
                queueCellUL_End = accumarray(servingIdx, queueBitsUL, [nCells, 1], @sum, 0);
                queueCellDL_Start = accumarray(servingIdx, queueBitsDL_Start, [nCells, 1], @sum, 0);
                queueCellUL_Start = accumarray(servingIdx, queueBitsUL_Start, [nCells, 1], @sum, 0);
                cellRows = (t-1) * nCells + (1:nCells);
                cellLoadTrace.TTI(cellRows) = t;
                cellLoadTrace.Time_s(cellRows) = (t - 1) * tti_s;
                cellLoadTrace.CellID(cellRows) = (1:nCells).';
                cellLoadTrace.SlotDirection(cellRows) = repmat(string(slotLabel), nCells, 1);
                cellLoadTrace.ActiveUE_DL(cellRows) = activeCellDL;
                cellLoadTrace.ActiveUE_UL(cellRows) = activeCellUL;
                cellLoadTrace.GrantCountDL(cellRows) = grantCountDLByCell;
                cellLoadTrace.GrantCountUL(cellRows) = grantCountULByCell;
                cellLoadTrace.OfferedBitsDL(cellRows) = offeredCellDL;
                cellLoadTrace.OfferedBitsUL(cellRows) = offeredCellUL;
                cellLoadTrace.QueueBitsDL_Begin(cellRows) = queueCellDL_Start;
                cellLoadTrace.QueueBitsUL_Begin(cellRows) = queueCellUL_Start;
                cellLoadTrace.ServedBitsDL(cellRows) = servedCellDL;
                cellLoadTrace.ServedBitsUL(cellRows) = servedCellUL;
                cellLoadTrace.DroppedBitsDL(cellRows) = droppedCellDL;
                cellLoadTrace.DroppedBitsUL(cellRows) = droppedCellUL;
                cellLoadTrace.QueueBitsDL_End(cellRows) = queueCellDL_End;
                cellLoadTrace.QueueBitsUL_End(cellRows) = queueCellUL_End;

                queueHistDL(t,:) = queueBitsDL(:).';
                queueHistUL(t,:) = queueBitsUL(:).';
                queueHist(t,:) = (queueBitsDL(:) + queueBitsUL(:)).';

                elapsedNow_s = toc(runTimer);
                totalGrantCount = grantCountDL(t) + grantCountUL(t);
                totalServedOrDroppedBits = servedBitsTotalDL + servedBitsTotalUL + droppedBitsTotalDL + droppedBitsTotalUL;
                backlogBitsNow = sum(queueBitsDL, "omitnan") + sum(queueBitsUL, "omitnan");
                offeredBitsNow = offeredBitsTTI_DL(t) + offeredBitsTTI_UL(t);
                if totalGrantCount > 0 || totalServedOrDroppedBits > lastUsefulBitCount
                    lastUsefulProgress_s = elapsedNow_s;
                    lastUsefulProgressSlot = t;
                    lastUsefulBitCount = totalServedOrDroppedBits;
                    stalledDemandSlotCount = 0;
                elseif noProgressGuardEnabled
                    backlogDemand = activeUECount(t) > 0 && (backlogBitsNow > 0 || offeredBitsNow > 0);
                    if backlogDemand
                        stalledDemandSlotCount = stalledDemandSlotCount + 1;
                        stagnationElapsed_s = elapsedNow_s - lastUsefulProgress_s;
                        if stalledDemandSlotCount >= noProgressSlotLimit || stagnationElapsed_s >= noProgressTimeout_s
                            localEmitLiveProgress(cfg, log, runTimer, t, nTTI, tti_s, ...
                                slotLabel, activeUECount(t), nCells, totalGrantCount, ...
                                servedBitsTotalDL + servedBitsTotalUL, ...
                                droppedBitsTotalDL + droppedBitsTotalUL, overflowEvents, ...
                                "system_level_lls_stalled_no_progress");
                            error("sixgr:system:SystemLevelRunner:NoProgressTimeout", ...
                                ['System-level LLS stalled with queued traffic but no grant/service progress ' ...
                                 '(slot=%d, lastProductiveSlot=%d, stalledSlots=%d, elapsedSinceProgress=%.1fs, ' ...
                                 'backlogBits=%.0f, offeredBits=%.0f).'], ...
                                t, lastUsefulProgressSlot, stalledDemandSlotCount, ...
                                stagnationElapsed_s, backlogBitsNow, offeredBitsNow);
                        end
                    else
                        stalledDemandSlotCount = 0;
                    end
                end
                if t == 1 || t == nTTI || mod(t, progressEverySlots) == 0 || ...
                        (elapsedNow_s - lastProgressEmit_s) >= 30
                    localEmitLiveProgress(cfg, log, runTimer, t, nTTI, tti_s, ...
                        slotLabel, activeUECount(t), nCells, ...
                        totalGrantCount, ...
                        servedBitsTotalDL + servedBitsTotalUL, ...
                        droppedBitsTotalDL + droppedBitsTotalUL, overflowEvents, ...
                        "system_level_lls_slot_progress");
                    lastProgressEmit_s = elapsedNow_s;
                end
            end

            localEmitLiveProgress(cfg, log, runTimer, nTTI, nTTI, tti_s, ...
                "finalizing", activeUECount(end), nCells, ...
                grantCountDL(end) + grantCountUL(end), ...
                servedBitsTotalDL + servedBitsTotalUL, ...
                droppedBitsTotalDL + droppedBitsTotalUL, overflowEvents, ...
                "system_level_lls_finalizing_exports");
            localEmitLiveProgress(cfg, log, runTimer, nTTI, nTTI, tti_s, ...
                "finalizing_tables", activeUECount(end), nCells, ...
                grantCountDL(end) + grantCountUL(end), ...
                servedBitsTotalDL + servedBitsTotalUL, ...
                droppedBitsTotalDL + droppedBitsTotalUL, overflowEvents, ...
                "system_level_lls_finalizing_tables_started");

            for u = 1:K
                eIdx = hoActiveEventIdx(u);
                if eIdx > 0 && hoEventStatus(eIdx) ~= "completed"
                    hoEventStatus(eIdx) = "incomplete";
                end
            end

            hoEvents = localBuildHandoverEventsTable( ...
                hoEventUE, hoEventFromCell, hoEventToCell, ...
                hoEventTriggerTTI, hoEventStartTTI, hoEventCompleteTTI, ...
                hoEventStatus, hoEventReason, tti_s);
            mobilityTS = localBuildMobilityControlSeries( ...
                tti_s, measReportCount, beamUpdateCount, hoTriggerCount, ...
                hoStartCount, hoCompleteCount, hoInterruptedUECount);
            schedulerGrants = localGrantTraceToTable(grantTrace, grantTraceCount);
            harqProcesses = localBuildHARQProcessTable(schedulerGrants);
            cellLoadTS = localCellLoadTraceToTable(cellLoadTrace);
            interferenceDetail = localInterferenceTraceToTable(interferenceTrace);
            beamEvents = localBeamEventTraceToTable(beamEventTrace, beamEventCount);
            localEmitLiveProgress(cfg, log, runTimer, nTTI, nTTI, tti_s, ...
                "finalizing_tables_ready", activeUECount(end), nCells, ...
                grantCountDL(end) + grantCountUL(end), ...
                servedBitsTotalDL + servedBitsTotalUL, ...
                droppedBitsTotalDL + droppedBitsTotalUL, overflowEvents, ...
                "system_level_lls_finalizing_tables_ready");

            servedPerUE = servedPerUE_DL + servedPerUE_UL;
            droppedPerUE = droppedPerUE_DL + droppedPerUE_UL;
            servedBitsTTI = servedBitsTTI_DL + servedBitsTTI_UL;
            droppedBitsTTI = droppedBitsTTI_DL + droppedBitsTTI_UL;
            queueBits = queueBitsDL + queueBitsUL;
            servedBitsTotal = servedBitsTotalDL + servedBitsTotalUL;
            droppedBitsTotal = droppedBitsTotalDL + droppedBitsTotalUL;

            simDur_s = nTTI * tti_s;
            offeredTotalDL = sum(traffic.OfferedBitsDL, "all");
            offeredTotalUL = sum(traffic.OfferedBitsUL, "all");
            offeredTotal = offeredTotalDL + offeredTotalUL;
            throughputDL_Mbps = (servedBitsTotalDL / max(simDur_s, eps)) / 1e6;
            throughputUL_Mbps = (servedBitsTotalUL / max(simDur_s, eps)) / 1e6;
            throughput_Mbps = throughputDL_Mbps + throughputUL_Mbps;
            packetLossDL = droppedBitsTotalDL / max(offeredTotalDL, 1);
            packetLossUL = droppedBitsTotalUL / max(offeredTotalUL, 1);
            packetLoss = droppedBitsTotal / max(offeredTotal, 1);

            validBler = [blerHistDL(~isnan(blerHistDL)); blerHistUL(~isnan(blerHistUL))];
            if isempty(validBler)
                avgBler = NaN;
            else
                avgBler = mean(validBler);
            end

            fairness = (sum(servedPerUE)^2) / max(K * sum(servedPerUE.^2), eps);
            meanQueueBits = localMeanNoNan(queueHist(:));
            meanSinr_dB = localMeanNoNan(sinrHist(:));
            meanRsrp_dBm = localMeanNoNan(rsrpHist(:));
            meanEbNo_dB = localMeanNoNan(ebnoHist(:));
            p05Sinr_dB = localQuantileNoNan(sinrHist(:), 0.05);
            p50Sinr_dB = localQuantileNoNan(sinrHist(:), 0.50);
            p95Sinr_dB = localQuantileNoNan(sinrHist(:), 0.95);

            arrRatePerUE = mean(traffic.OfferedBits,1).' / max(tti_s, eps);
            delay_s = localMeanNoNan((queueBits ./ max(arrRatePerUE, 1)));
            spectralEff_bpsHz = (servedBitsTotal / max(simDur_s, eps)) / max(bw_Hz, 1);
            spectralEffDL_bpsHz = (servedBitsTotalDL / max(simDur_s, eps)) / max(bw_Hz, 1);
            spectralEffUL_bpsHz = (servedBitsTotalUL / max(simDur_s, eps)) / max(bw_Hz, 1);
            util = servedBitsTotal / max(offeredTotal, 1);
            avgActiveUE = mean(activeUECount);
            schedUtil = mean((scheduledUE_DL > 0) | (scheduledUE_UL > 0));
            hoTriggerTotal = sum(hoTriggerCount);
            hoStartTotal = sum(hoStartCount);
            hoCompleteTotal = sum(hoCompleteCount);
            hoInterruptedUEmean = mean(hoInterruptedUECount);
            hoInterruption_ms = 1e3 * tti_s * localMeanNoNan(hoInterruptAccumSlots(hoInterruptAccumSlots > 0));
            if ~isfinite(hoInterruption_ms)
                hoInterruption_ms = 0;
            end

            kpi = table(throughput_Mbps, throughputDL_Mbps, throughputUL_Mbps, ...
                packetLoss, packetLossDL, packetLossUL, ...
                avgBler, fairness, meanQueueBits, meanSinr_dB, ...
                meanRsrp_dBm, meanEbNo_dB, p05Sinr_dB, p50Sinr_dB, p95Sinr_dB, ...
                spectralEff_bpsHz, spectralEffDL_bpsHz, spectralEffUL_bpsHz, ...
                util, avgActiveUE, schedUtil, ...
                1e3*delay_s, K, nCells, nTTI, simDur_s, ...
                hoTriggerTotal, hoStartTotal, hoCompleteTotal, hoInterruptedUEmean, hoInterruption_ms, ...
                string(phyBackendLabel), string(phyModeLabel), logical(waveformBacked), ...
                logical(waveformBacked), logical(proxyPHYActive), logical(fallbackUsed), ...
                'VariableNames', {'Throughput_Mbps','ThroughputDL_Mbps','ThroughputUL_Mbps', ...
                                  'PacketLoss','PacketLossDL','PacketLossUL','AvgBLER','JainFairness', ...
                                  'MeanQueue_bits','MeanSINR_dB','MeanRSRP_dBm','MeanEbNo_dB', ...
                                  'P05SINR_dB','P50SINR_dB','P95SINR_dB', ...
                                  'SpectralEfficiency_bpsHz','SpectralEfficiencyDL_bpsHz','SpectralEfficiencyUL_bpsHz', ...
                                  'Utilization','AvgActiveUE','ScheduleUtilization', ...
                                  'ApproxDelay_ms','NumUE','NumCells','NumTTI','SimDuration_s', ...
                                  'HO_Triggered','HO_Started','HO_Completed','HO_InterruptedUE_Mean','HO_InterruptionMean_ms', ...
                                  'ExecutionBackend','PHYMode','WaveformBacked', ...
                                  'WaveformPHYActive','ProxyPHYActive','FallbackUsed'});
            out.KPITable = kpi;

            out.Details = struct();
            out.Details.ExecutionBackend = string(phyBackendLabel);
            out.Details.PHYMode = string(phyModeLabel);
            out.Details.WaveformBacked = logical(waveformBacked);
            out.Details.WaveformPHYActive = logical(waveformBacked);
            out.Details.ProxyPHYActive = logical(proxyPHYActive);
            out.Details.FallbackUsed = logical(fallbackUsed);
            if waveformBacked && isprop(phy, "LastReplay")
                out.Details.LastPHYReplay = phy.LastReplay;
            end
            out.Details.ScheduledUE_DL = scheduledUE_DL;
            out.Details.ScheduledUE_UL = scheduledUE_UL;
            out.Details.ScheduledUE = max(scheduledUE_DL, scheduledUE_UL);
            out.Details.GrantCountDL = grantCountDL;
            out.Details.GrantCountUL = grantCountUL;
            out.Details.GrantCount = grantCountDL + grantCountUL;
            out.Details.DecodeUnavailableDL = decodeUnavailableCountDL;
            out.Details.DecodeUnavailableUL = decodeUnavailableCountUL;
            out.Details.SlotDirection = slotDirection;
            out.Details.OfferedBits = traffic.OfferedBits;
            out.Details.OfferedBitsDL = traffic.OfferedBitsDL;
            out.Details.OfferedBitsUL = traffic.OfferedBitsUL;
            out.Details.RemainingQueueBits = queueBits;
            out.Details.RemainingQueueBitsDL = queueBitsDL;
            out.Details.RemainingQueueBitsUL = queueBitsUL;
            out.Details.ServedBitsPerUE = servedPerUE;
            out.Details.ServedBitsPerUE_DL = servedPerUE_DL;
            out.Details.ServedBitsPerUE_UL = servedPerUE_UL;
            out.Details.DroppedBitsPerUE = droppedPerUE;
            out.Details.DroppedBitsPerUE_DL = droppedPerUE_DL;
            out.Details.DroppedBitsPerUE_UL = droppedPerUE_UL;
            out.Details.ServedBitsPerTTI = servedBitsTTI;
            out.Details.ServedBitsPerTTI_DL = servedBitsTTI_DL;
            out.Details.ServedBitsPerTTI_UL = servedBitsTTI_UL;
            out.Details.OfferedBitsPerTTI = offeredBitsTTI;
            out.Details.OfferedBitsPerTTI_DL = offeredBitsTTI_DL;
            out.Details.OfferedBitsPerTTI_UL = offeredBitsTTI_UL;
            out.Details.DroppedBitsPerTTI = droppedBitsTTI;
            out.Details.DroppedBitsPerTTI_DL = droppedBitsTTI_DL;
            out.Details.DroppedBitsPerTTI_UL = droppedBitsTTI_UL;
            out.Details.ActiveUECount = activeUECount;
            out.Details.SINR_dB = sinrHist;
            out.Details.SINR_UL_dB = sinrHistUL;
            out.Details.RSRP_dBm = rsrpHist;
            out.Details.EbNo_dB = ebnoHist;
            out.Details.RxPower_dBm = rxPowerHist;
            out.Details.DesiredPowerDL_dBm = desiredPowerHistDL;
            out.Details.DesiredPowerUL_dBm = desiredPowerHistUL;
            out.Details.InterferencePowerDL_dBm = interferencePowerHistDL;
            out.Details.InterferencePowerUL_dBm = interferencePowerHistUL;
            out.Details.NoiseDL_dBm = noisePowerHistDL;
            out.Details.NoiseUL_dBm = noisePowerHistUL;
            out.Details.ActiveInterfererCountDL = interfererCellCountHistDL;
            out.Details.ActiveInterfererCountUL = interfererCellCountHistUL;
            out.Details.Pathloss_dB = pathlossHist;
            out.Details.ServingDistance_m = dServeHist;
            out.Details.QueueBits = queueHist;
            out.Details.QueueBitsDL = queueHistDL;
            out.Details.QueueBitsUL = queueHistUL;
            out.Details.BLER = max(blerHistDL, blerHistUL);
            out.Details.BLER_DL = blerHistDL;
            out.Details.BLER_UL = blerHistUL;
            out.Details.TrafficModel = traffic.Model;
            out.Details.TrafficClass = traffic.UserClass;
            out.Details.TrafficTransport = sixgr.util.structGet(traffic, "Transport", "UDP");
            out.Details.TrafficTransportSemanticClass = sixgr.util.structGet(traffic, "TransportSemanticClass", "");
            out.Details.TrafficTransportTruthLabel = sixgr.util.structGet(traffic, "TransportTruthLabel", "");
            out.Details.TrafficTransportApproximationReason = sixgr.util.structGet(traffic, "TransportApproximationReason", "");
            out.Details.FlowDirection = sixgr.util.structGet(traffic, "FlowDirection", "BIDIR");
            out.Details.PacketDelayBudget_ms = sixgr.util.structGet(traffic, "PacketDelayBudget_ms", NaN);
            out.Details.FlowTable = sixgr.util.structGet(traffic, "FlowTable", table());
            out.Details.TTI_s = tti_s;
            out.Details.SINRModel = sinrModel;
            out.Details.Noise_dBm = noisePowerHistDL;
            out.Details.InterferenceMargin_dB = localInterferenceMarginFromPowers( ...
                interferencePowerHistDL, noisePowerHistDL);
            out.Details.SmallScaleFading_dB = fastFading_dB;
            out.Details.InterferenceVariation_dB = interfVar_dB;
            out.Details.NumRB = nRB;
            out.Details.Layout = layout;
            out.Details.UEInitial = ueInitial;
            out.Details.UEFinal = ue;
            out.Details.DecodeOK = decodeOkCountDL + decodeOkCountUL;
            out.Details.DecodeFail = decodeFailCountDL + decodeFailCountUL;
            out.Details.DecodeOK_DL = decodeOkCountDL;
            out.Details.DecodeFail_DL = decodeFailCountDL;
            out.Details.DecodeOK_UL = decodeOkCountUL;
            out.Details.DecodeFail_UL = decodeFailCountUL;
            out.Details.OverflowEvents = overflowEvents;
            out.Details.ServingCell = servingCellHist;
            out.Details.ServingBeamIndex = servingBeamHist;
            out.Details.ServingBeamGain_dB = servingBeamGainHist;
            out.Details.HandoverState = hoStateHist;
            out.Details.MeasurementRSRP_dBm = measRSRP_dBm;
            out.Details.MeasurementRSRPTrace_dBm = measRSRPTrace_dBm;
            out.Details.MeasurementReportCount = measReportCount;
            out.Details.BeamUpdateCount = beamUpdateCount;
            out.Details.LargeScaleRefreshMask = largeScaleRefreshMask;
            out.Details.LargeScalePropagationUpdateMask = largeScalePropagationUpdateMask;
            out.Details.LargeScaleState = largeScaleState;
            out.Details.LargeScaleUpdatePeriod_slots = largeScaleUpdateSlots;
            out.Details.HandoverTriggerCount = hoTriggerCount;
            out.Details.HandoverStartCount = hoStartCount;
            out.Details.HandoverCompleteCount = hoCompleteCount;
            out.Details.HandoverInterruptedUECount = hoInterruptedUECount;
            out.Details.HandoverInterruptAccumSlots = hoInterruptAccumSlots;
            out.Details.HandoverEvents = hoEvents;
            out.Details.BeamEvents = beamEvents;
            out.Details.SchedulerGrants = schedulerGrants;
            out.Details.HARQProcesses = harqProcesses;
            out.Details.CellLoad = cellLoadTS;
            out.Details.InterferenceDetail = interferenceDetail;
            out.Details.MobilityControlSeries = mobilityTS;
            out.Details.HandoverConfig = struct( ...
                "Enabled", handoverEnable, ...
                "A3Offset_dB", hoA3Offset_dB, ...
                "Hysteresis_dB", hoHyst_dB, ...
                "TTT_slots", hoTTTslots, ...
                "PreparationSlots", hoPrepSlots, ...
                "InterruptionSlots", hoInterruptionSlots, ...
                "BlockDuringPreparation", hoBlockDuringPrep);
            out.Details.BeamConfig = struct( ...
                "Enabled", beamEnable, ...
                "NumBeams", nBeams, ...
                "UpdatePeriod_slots", beamUpdatePeriodSlots, ...
                "SectorSpan_deg", beamSpanDeg, ...
                "MaxGain_dB", beamMaxGain_dB);
            if captureGeometryTrace
                out.Details.UEPosX_m = posXHist;
                out.Details.UEPosY_m = posYHist;
                out.Details.UEPosZ_m = posZHist;
                out.Details.UEHeading_deg = headingHist;
            end

            ueSummary = localBuildUESummary( ...
                ue, layout, traffic.UserClass, traffic.OfferedBits, servedPerUE, droppedPerUE, ...
                sinrHist, rsrpHist, ebnoHist, max(blerHistDL, blerHistUL), queueHist, dServeHist, simDur_s);
            timeSeries = localBuildTimeSeries( ...
                tti_s, offeredBitsTTI, servedBitsTTI, droppedBitsTTI, activeUECount, ...
                scheduledUE_DL, scheduledUE_UL, slotDirection, ...
                offeredBitsTTI_DL, offeredBitsTTI_UL, servedBitsTTI_DL, servedBitsTTI_UL, ...
                droppedBitsTTI_DL, droppedBitsTTI_UL, ...
                sinrHist, rsrpHist, ebnoHist, queueHist, queueHistDL, queueHistUL);
            algoProc = localBuildAlgoTable( ...
                cfg, traffic.Model, traffic.UserClass, nTTI, tti_s, K, ...
                decodeOkCountDL + decodeOkCountUL, decodeFailCountDL + decodeFailCountUL, overflowEvents, avgActiveUE, ...
                hoTriggerTotal, hoCompleteTotal, mean(hoInterruptedUECount), ...
                phyBackendLabel, phyModeLabel, waveformBacked, proxyPHYActive, fallbackUsed);

            out.Details.UESummary = ueSummary;
            out.Details.TimeSeries = timeSeries;
            out.Details.AlgoProcessing = algoProc;

            doCSV = logical(sixgr.util.structGet(cfg, "outputs.saveCSV", true));
            doMAT = logical(sixgr.util.structGet(cfg, "outputs.saveMAT", true));
            localEmitLiveProgress(cfg, log, runTimer, nTTI, nTTI, tti_s, ...
                "finalizing_persistence", activeUECount(end), nCells, ...
                grantCountDL(end) + grantCountUL(end), ...
                servedBitsTotalDL + servedBitsTotalUL, ...
                droppedBitsTotalDL + droppedBitsTotalUL, overflowEvents, ...
                "system_level_lls_finalizing_persistence_started");
            if doCSV
                csvFile = fullfile(ctx.RunFolder, "csv", "system_kpis.csv");
                sixgr.util.csvWriteTable(csvFile, out.KPITable);
                out.Artifacts.csv{end+1} = csvFile;

                csvUE = fullfile(ctx.RunFolder, "csv", "system_ue_summary.csv");
                sixgr.util.csvWriteTable(csvUE, ueSummary);
                out.Artifacts.csv{end+1} = csvUE;

                csvTS = fullfile(ctx.RunFolder, "csv", "system_time_series.csv");
                sixgr.util.csvWriteTable(csvTS, timeSeries);
                out.Artifacts.csv{end+1} = csvTS;

                csvAlgo = fullfile(ctx.RunFolder, "csv", "system_algo_processing.csv");
                sixgr.util.csvWriteTable(csvAlgo, algoProc);
                out.Artifacts.csv{end+1} = csvAlgo;

                csvMob = fullfile(ctx.RunFolder, "csv", "system_mobility_control_series.csv");
                sixgr.util.csvWriteTable(csvMob, mobilityTS);
                out.Artifacts.csv{end+1} = csvMob;

                csvHO = fullfile(ctx.RunFolder, "csv", "system_handover_events.csv");
                sixgr.util.csvWriteTable(csvHO, hoEvents);
                out.Artifacts.csv{end+1} = csvHO;

                csvBeam = fullfile(ctx.RunFolder, "csv", "system_beam_events.csv");
                sixgr.util.csvWriteTable(csvBeam, beamEvents);
                out.Artifacts.csv{end+1} = csvBeam;

                csvSched = fullfile(ctx.RunFolder, "csv", "system_scheduler_grants.csv");
                sixgr.util.csvWriteTable(csvSched, schedulerGrants);
                out.Artifacts.csv{end+1} = csvSched;

                csvHarq = fullfile(ctx.RunFolder, "csv", "system_harq_processes.csv");
                sixgr.util.csvWriteTable(csvHarq, harqProcesses);
                out.Artifacts.csv{end+1} = csvHarq;

                csvLoad = fullfile(ctx.RunFolder, "csv", "system_cell_load.csv");
                sixgr.util.csvWriteTable(csvLoad, cellLoadTS);
                out.Artifacts.csv{end+1} = csvLoad;

                csvInterf = fullfile(ctx.RunFolder, "csv", "system_interference_detail.csv");
                sixgr.util.csvWriteTable(csvInterf, interferenceDetail);
                out.Artifacts.csv{end+1} = csvInterf;
            end
            if doMAT
                matFile = fullfile(ctx.RunFolder, "mat", "system_results.mat");
                sixgr.util.matSave(matFile, struct("kpi", out.KPITable, "details", out.Details));
                out.Artifacts.mat{end+1} = matFile;
            end

            doFig = localResolveSaveFigures(cfg, false);
            if doFig
                try
                    figRes = max(72, round(double(sixgr.util.structGet(cfg, "outputs.figureResolution", 140))));
                    scatterCap = max(2000, round(double(sixgr.util.structGet(cfg, "outputs.figureScatterMaxPoints", 12000))));
                    figFiles = localExportFigures(ctx.RunFolder, timeSeries, ueSummary, ...
                        sinrHist, rsrpHist, ebnoHist, queueHist, servedBitsTTI, ...
                        detailedTrace, posXHist, posYHist, figRes, scatterCap);
                    out.Artifacts.fig = figFiles;
                catch MEf
                    out.Errors(end+1,1) = "Figure export failed: " + string(MEf.message);
                end
            end

            try
                mFile = fullfile(ctx.RunFolder, "run_replay_system.m");
                localWriteReplayScript(mFile, nTTI, tti_s, detailedTrace);
                out.Artifacts.m{end+1} = mFile;
            catch MEm
                out.Errors(end+1,1) = "Replay script write failed: " + string(MEm.message);
            end
            localEmitLiveProgress(cfg, log, runTimer, nTTI, nTTI, tti_s, ...
                "finalizing_persistence_ready", activeUECount(end), nCells, ...
                grantCountDL(end) + grantCountUL(end), ...
                servedBitsTotalDL + servedBitsTotalUL, ...
                droppedBitsTotalDL + droppedBitsTotalUL, overflowEvents, ...
                "system_level_lls_finalizing_persistence_ready");

            runtimeSummary = localBuildRuntimeSummary(startedUTC, runTimer, ctx.RunFolder, out.Errors);
            environmentSummary = localBuildEnvironmentSummary(ctx);
            out.RuntimeSummary = runtimeSummary;
            out.EnvironmentSummary = environmentSummary;

            exportOutputCatalog = logical(sixgr.util.structGet(cfg, ...
                "outputs.exportSLSOutputCatalog", true));
            if exportOutputCatalog
                localEmitLiveProgress(cfg, log, runTimer, nTTI, nTTI, tti_s, ...
                    "finalizing_catalog", activeUECount(end), nCells, ...
                    grantCountDL(end) + grantCountUL(end), ...
                    servedBitsTotalDL + servedBitsTotalUL, ...
                    droppedBitsTotalDL + droppedBitsTotalUL, overflowEvents, ...
                    "system_level_lls_finalizing_catalog_started");
                try
                    out.OutputCatalog = sixgr.report.exportSLSOutputCatalog( ...
                        ctx.RunFolder, cfg, out, runtimeSummary, environmentSummary);
                catch MEcat
                    out.Errors(end+1,1) = "SLS output catalog export failed: " + string(MEcat.message);
                end
            else
                out.OutputCatalog = struct();
                out.Details.OutputCatalogSkipped = true;
                out.Details.OutputCatalogSkipReason = ...
                    "outputs.exportSLSOutputCatalog=false";
            end

            log.info("SystemLevelRunner completed: throughput=" + string(round(throughput_Mbps,3)) + " Mbps");
        end
    end
end

function tti_s = localSlotDuration(cfg, params)
configured = sixgr.util.structGet(params, "TTI_s", ...
    sixgr.util.structGet(cfg, "system.tti_s", []));
if ~isempty(configured)
    configured = double(configured);
    if ~(isscalar(configured) && isfinite(configured) && configured > 0)
        error("sixgr:system:InvalidTTIDuration", ...
            "Configured TTI_s must be a positive finite scalar.");
    end
    % Explicit TTI_s is the system-level simulation integration step. It
    % may intentionally span many PHY slots for mobility studies, so it is
    % not relabelled as a resolved NR slot duration.
    tti_s = configured;
    return;
end
tti_s = sixgr.time.slotDurationSec(cfg);
end

function d = localDistanceMatrix(uePos, bsPos, wrapEn, area_m)
if wrapEn
    d = sixgr.scenario.wraparoundDistance(uePos, bsPos, area_m);
    return;
end
dx = uePos(:,1) - bsPos(:,1).';
dy = uePos(:,2) - bsPos(:,2).';
d = sqrt(dx.^2 + dy.^2);
end

function m = localMeanNoNan(x)
x = x(~isnan(x));
if isempty(x)
    m = NaN;
else
    m = mean(x);
end
end

function q = localQuantileNoNan(x, p)
x = x(~isnan(x));
if isempty(x)
    q = NaN;
    return;
end
q = quantile(x, p);
end

function [cfg, frame] = localAttachCanonicalFrameCore(cfg)
engine = sixgr.phy.FrameStructureEngine(cfg, "FrameCoreOnly", true);
frame = engine.toStruct();
existing = sixgr.util.structGet(cfg, "phy.frameStructure", struct());
if isstruct(existing) && isscalar(existing)
    preserved = setdiff(string(fieldnames(existing)), ...
        string(fieldnames(frame)), "stable");
    for name = preserved(:).'
        frame.(name) = existing.(name);
    end
    if logical(sixgr.util.structGet( ...
            existing, "SignalTimingResolved", false))
        signalFields = [ ...
            "SSBTiming", "PRACHTiming", "SSBCase", "SSBLmax", ...
            "SSBCandidateSymbols", "PRACHConfigurationIndex", ...
            "PRACHFormat", "PRACHStartSymbol", ...
            "PRACHDurationSymbols", "PRACHValidSlots0Based", ...
            "PRACHValidationStatus", "ValidationLog", ...
            "SignalTimingResolved"];
        for name = signalFields
            if isfield(existing, name)
                frame.(name) = existing.(name);
            end
        end
    end
end
cfg = sixgr.util.structSet(cfg, "phy.frameStructure", frame);
end

function ebno_dB = localSINRtoEbNo(sinr_dB)
se = log2(1 + 10.^(double(sinr_dB)/10));
ebno_dB = double(sinr_dB) - 10*log10(max(se, 1e-9));
end

function [allowDL, allowUL, slotLabel] = localSlotDuplexState(cfg, t)
duplex = localCanonicalDuplexMode(cfg);
if duplex == "FDD"
    localRequireFDDContext(cfg);
    allowDL = true;
    allowUL = true;
    slotLabel = "FDD_SEPARATE_DL_UL";
    return;
end
partition = sixgr.util.resolveTDDSlotPartition(cfg, t - 1);
allowDL = logical(partition.AllowDL);
allowUL = logical(partition.AllowUL);
slotLabel = string(partition.SlotLabel);
end

function sched = localCreateScheduler(cfg, schedulerName, direction, log)
if nargin < 4
    log = [];
end
dir = upper(char(string(direction)));
sch = lower(char(string(schedulerName)));
if contains(sch, "pf")
    sched = sixgr.l2.mac.SchedulerPF(cfg, "Direction", dir, "Logger", log);
else
    sched = sixgr.l2.mac.SchedulerRR( ...
        cfg, "Direction", dir, "Logger", log);
end
end

function budget = localSlotBudget(cfg, t, nRB, direction)
dir = upper(char(string(direction)));
nPRB = double(nRB);
if ~(isscalar(nPRB) && isfinite(nPRB) && nPRB >= 1 && ...
        nPRB == fix(nPRB))
    error("sixgr:system:SystemLevelRunner:InvalidCanonicalGrid", ...
        "Canonical frame resolution must provide a positive integer N_RB.");
end
duplex = localCanonicalDuplexMode(cfg);
if duplex == "FDD"
    context = localRequireFDDContext(cfg);
    symbolsPerSlot = double(context.SymbolsPerSlot);
    if strcmp(dir, "UL")
        symAlloc = localRequiredAllocation(cfg, ...
            ["phy.pusch.symbolAllocation", ...
            "phy.pusch.SymbolAllocation"], "PUSCH");
    else
        symAlloc = localRequiredAllocation(cfg, ...
            ["phy.pdsch.symbolAllocation", ...
            "phy.pdsch.SymbolAllocation"], "PDSCH");
    end
else
    partition = sixgr.util.resolveTDDSlotPartition(cfg, t - 1);
    symbolsPerSlot = double(sixgr.util.structGet( ...
        partition, "SymbolsPerSlot", NaN));
    if strcmp(dir, "UL")
        partitionAllocation = double(sixgr.util.structGet( ...
            partition, "ULSymbolAllocation", []));
        configuredAllocation = localRequiredAllocation(cfg, ...
            ["phy.pusch.symbolAllocation", ...
            "phy.pusch.SymbolAllocation"], "PUSCH");
    else
        partitionAllocation = double(sixgr.util.structGet( ...
            partition, "DLSymbolAllocation", []));
        configuredAllocation = localRequiredAllocation(cfg, ...
            ["phy.pdsch.symbolAllocation", ...
            "phy.pdsch.SymbolAllocation"], "PDSCH");
    end
    if numel(partitionAllocation) ~= 2 || any(~isfinite(partitionAllocation))
        partitionAllocation = [0, 0];
    end
    symAlloc = localIntersectSymbolAllocations( ...
        configuredAllocation, partitionAllocation);
end
if ~(isfinite(symbolsPerSlot) && symbolsPerSlot >= 1)
    error("sixgr:system:SystemLevelRunner:MissingSymbolsPerSlot", ...
        "Canonical duplex context must provide SymbolsPerSlot.");
end
controlAllocation = localRequiredAllocation(cfg, [ ...
    "phy.pdcch.symbolAllocation", ...
    "phy.pdcch.SymbolAllocation"], "PDCCH");
budget = struct( ...
    "NPRB", nPRB, ...
    "SymbolAllocation", reshape(symAlloc(1:2), 1, 2), ...
    "ControlAbsoluteSlot", double(t - 1), ...
    "ControlSymbolAllocation", controlAllocation);
end

function allocation = localIntersectSymbolAllocations(configured, partition)
configured = double(configured(:).');
partition = double(partition(:).');
if numel(configured) ~= 2 || numel(partition) ~= 2 || ...
        any(~isfinite(configured)) || any(~isfinite(partition))
    error("sixgr:system:SystemLevelRunner:InvalidSymbolAllocation", ...
        "Configured and TDD-partition symbol allocations must be finite [start,count] pairs.");
end
configuredStart = round(configured(1));
configuredEnd = configuredStart + max(0, round(configured(2)));
partitionStart = round(partition(1));
partitionEnd = partitionStart + max(0, round(partition(2)));
startSymbol = max(configuredStart, partitionStart);
endSymbol = min(configuredEnd, partitionEnd);
allocation = [startSymbol, max(0, endSymbol - startSymbol)];
if allocation(2) == 0
    allocation(1) = 0;
end
end

function tf = localSlotBudgetSupportsExecutableDataGrants(cfg, direction, budget)
tf = true;
if nargin < 3 || ~isstruct(budget) || isempty(fieldnames(budget))
    return;
end

symAlloc = double(sixgr.util.structGet(budget, "SymbolAllocation", [0 0]));
if numel(symAlloc) < 2
    tf = false;
    return;
end
symAlloc = reshape(symAlloc(1:2), 1, 2);
nSym = round(double(symAlloc(2)));
if ~(isfinite(nSym) && nSym > 0)
    tf = false;
    return;
end
requiresExactGrantNRE = localRequiresExactGrantNRE(direction, symAlloc);

nPRB = double(sixgr.util.structGet(budget, "NPRB", NaN));
if ~(isscalar(nPRB) && isfinite(nPRB) && nPRB >= 1 && ...
        nPRB == fix(nPRB))
    tf = false;
    return;
end
canonicalGrid = double(sixgr.util.structGet(cfg, ...
    "phy.frameStructure.CarrierGrid.NSizeGrid", NaN));
if ~(isscalar(canonicalGrid) && isfinite(canonicalGrid) && ...
        canonicalGrid >= 1 && canonicalGrid == fix(canonicalGrid)) || ...
        nPRB > canonicalGrid
    tf = false;
    return;
end
dir = upper(string(direction));
switch dir
    case "UL"
        modStr = char(string(sixgr.util.structGet(cfg, "phy.pusch.modulation", "QPSK")));
        nLayers = max(1, round(double(sixgr.util.structGet(cfg, "phy.pusch.numLayers", ...
            sixgr.util.structGet(cfg, "phy.pusch.nLayers", 1)))));
    otherwise
        modStr = char(string(sixgr.util.structGet(cfg, "phy.pdsch.modulation", "QPSK")));
        nLayers = max(1, round(double(sixgr.util.structGet(cfg, "phy.pdsch.numLayers", ...
            sixgr.util.structGet(cfg, "phy.pdsch.nLayers", 1)))));
end

try
    [carrier, ~] = sixgr.phy.grid.makeCarrier(cfg, ...
        "NSizeGrid", canonicalGrid);
    if dir == "UL"
        [~, allocInfo] = sixgr.phy.grid.allocREsPUSCH(carrier, cfg, ...
            "PRBSet", 0:(max(nPRB, 1) - 1), ...
            "SymbolAllocation", symAlloc, ...
            "Modulation", modStr, ...
            "NumLayers", double(nLayers));
    else
        [~, allocInfo] = sixgr.phy.grid.allocREsPDSCH(carrier, cfg, ...
            "PRBSet", 0:(max(nPRB, 1) - 1), ...
            "SymbolAllocation", symAlloc, ...
            "Modulation", modStr, ...
            "NumLayers", double(nLayers));
    end
    [nrePerPRB, ~] = sixgr.util.resolveDataNREPerPRB(allocInfo, nPRB, modStr, nLayers);
    if isfinite(double(nrePerPRB))
        tf = double(nrePerPRB) > 0;
    elseif requiresExactGrantNRE
        tf = false;
    end
catch
    % An unresolved exact allocation cannot authorize a primary grant.
    tf = false;
end
end

function duplex = localCanonicalDuplexMode(cfg)
duplex = upper(string(sixgr.util.structGet(cfg, ...
    "phy.frameStructure.DuplexMode", ...
    sixgr.util.structGet(cfg, "phy.duplex.mode", ""))));
if ~any(duplex == ["TDD", "FDD"])
    error("sixgr:system:SystemLevelRunner:MissingDuplexMode", ...
        "System-level scheduling requires canonical TDD or FDD mode.");
end
end

function context = localRequireFDDContext(cfg)
context = sixgr.util.structGet(cfg, ...
    "phy.frameStructure.FDDContexts", []);
if ~(isstruct(context) && isscalar(context) && ...
        isfield(context, "Downlink") && ...
        isfield(context, "Uplink") && ...
        isfield(context, "SymbolsPerSlot") && ...
        string(sixgr.util.structGet(context, ...
            "DuplexMode", "")) == "FDD")
    error("sixgr:system:SystemLevelRunner:MissingFDDContext", ...
        "FDD scheduling requires explicit canonical DL and UL contexts.");
end
end

function allocation = localRequiredAllocation(cfg, paths, label)
allocation = [];
for path = string(paths(:)).'
    candidate = sixgr.util.structGet(cfg, path, []);
    if ~isempty(candidate)
        allocation = candidate;
        break;
    end
end
if ~(isnumeric(allocation) && isreal(allocation) && ...
        numel(allocation) == 2 && ...
        all(isfinite(double(allocation(:)))) && ...
        all(double(allocation(:)) == fix(double(allocation(:)))) && ...
        double(allocation(1)) >= 0 && double(allocation(2)) >= 1)
    error("sixgr:system:SystemLevelRunner:MissingSymbolAllocation", ...
        "%s requires an explicit [start,count] SymbolAllocation.", label);
end
allocation = reshape(double(allocation), 1, 2);
end

function grants = localVertcatGrantSets(grantSets, nSets)
if nargin < 2
    nSets = numel(grantSets);
end
nSets = min(max(round(double(nSets)), 0), numel(grantSets));
if nSets <= 0
    grants = struct([]);
    return;
end
sets = grantSets(1:nSets);
allFields = strings(0, 1);
for i = 1:numel(sets)
    if isempty(sets{i})
        continue;
    end
    allFields = union(allFields, string(fieldnames(sets{i})), "stable");
end
if isempty(allFields)
    grants = struct([]);
    return;
end
defaults = struct();
for i = 1:numel(allFields)
    fieldName = char(allFields(i));
    defaults.(fieldName) = localDefaultGrantSetFieldValue(sets, fieldName);
end
for i = 1:numel(sets)
    if isempty(sets{i})
        continue;
    end
    sets{i} = localEnsureGrantSetFields(sets{i}, allFields, defaults);
end
grants = vertcat(sets{:});
end

function grants = localEnsureGrantSetFields(grants, fields, defaults)
for i = 1:numel(fields)
    fieldName = char(fields(i));
    if ~isfield(grants, fieldName)
        [grants.(fieldName)] = deal(defaults.(fieldName));
    end
end
grants = orderfields(grants, cellstr(fields));
end

function value = localDefaultGrantSetFieldValue(sets, fieldName)
value = [];
for i = 1:numel(sets)
    s = sets{i};
    if isempty(s) || ~isfield(s, fieldName)
        continue;
    end
    value = localTypedGrantFieldDefault(s(1).(fieldName));
    return;
end
end

function value = localTypedGrantFieldDefault(sample)
if ischar(sample) || isstring(sample)
    value = "";
elseif islogical(sample)
    value = false;
elseif isnumeric(sample)
    value = NaN;
elseif isstruct(sample)
    value = struct();
elseif istable(sample)
    value = table();
elseif iscell(sample)
    value = {};
else
    value = [];
end
end

function tf = localRequiresExactGrantNRE(direction, symAlloc)
tf = false;
if upper(string(direction)) ~= "UL"
    return;
end
if nargin < 2 || isempty(symAlloc)
    % An unresolved UL allocation must not be approved by approximate RE
    % accounting. Force the exact path, which will fail closed if needed.
    tf = true;
    return;
end
sa = double(symAlloc(:).');
if numel(sa) < 2 || any(~isfinite(sa(1:2)))
    tf = true;
    return;
end
startSym = max(0, round(double(sa(1))));
nSym = max(0, round(double(sa(2))));
tf = startSym > 3 || nSym <= 2;
end

function mode = localResolveSINRModel(cfg)
raw = string(sixgr.util.structGet(cfg, "system.sinrModel", ...
    sixgr.util.structGet(cfg, "channel.interferenceModel", "explicit_activity_power_sum")));
raw = lower(strtrim(raw));
switch raw
    case {"legacy","legacy_margin","legacy_margin_calibration","margin_calibration", ...
            "non_vienna_calibration","placeholder_margin"}
        mode = "legacy_margin_calibration";
    otherwise
        mode = "explicit_activity_power_sum";
end
end

function ulLinkPower_dBm = localBuildULLinkPowerTable(cfg, largeScaleState)
K = double(sixgr.util.structGet(largeScaleState, "NumUE", size(largeScaleState.Pathloss_dB, 1)));
nCells = double(sixgr.util.structGet(largeScaleState, "NumCells", size(largeScaleState.Pathloss_dB, 2)));
ueTxPower_dBm = double(sixgr.util.structGet(cfg, "scenario.ue.txPower_dBm", 23));
if isscalar(ueTxPower_dBm)
    ueTxPower_dBm = repmat(ueTxPower_dBm, K, 1);
else
    ueTxPower_dBm = reshape(ueTxPower_dBm, [], 1);
    if numel(ueTxPower_dBm) ~= K
        ueTxPower_dBm = repmat(ueTxPower_dBm(1), K, 1);
    end
end
ulLinkPower_dBm = repmat(ueTxPower_dBm, 1, nCells) + ...
    double(largeScaleState.BeamGain_dB) - double(largeScaleState.Pathloss_dB);
end

function [sinrDL_dB, sinrUL_dB, state] = localBuildLegacySINRState( ...
    desiredDL_dBm, desiredUL_dBm, slotDL, slotUL, dlBudget, ulBudget, scs_kHz, ...
    noiseFigDL_dB, noiseFigUL_dB, fastFading_dB, interfVar_dB, interfMargin_dB, ulSinrOffset_dB)
K = numel(desiredDL_dBm);
state = localInitSINRState(K);
state.DesiredPowerDL_dBm = double(desiredDL_dBm(:));
state.DesiredPowerUL_dBm = double(desiredUL_dBm(:));
state.SmallScaleFading_dB = double(fastFading_dB(:));
state.InterferenceVariation_dB = double(interfVar_dB(:));

if slotDL
    noiseDL_dBm = localThermalNoisePower_dBm(dlBudget.NPRB, scs_kHz, noiseFigDL_dB);
    state.NoisePowerDL_dBm(:) = noiseDL_dBm;
    state.InterferencePowerDL_dBm = localInterferencePowerFromMargin(noiseDL_dBm, interfMargin_dB, K);
    state.LegacyInterferenceMarginDL_dB(:) = interfMargin_dB;
    sinrDL_dB = state.DesiredPowerDL_dBm - noiseDL_dBm - interfMargin_dB + ...
        state.SmallScaleFading_dB - state.InterferenceVariation_dB;
else
    sinrDL_dB = NaN(K,1);
end

if slotUL
    noiseUL_dBm = localThermalNoisePower_dBm(ulBudget.NPRB, scs_kHz, noiseFigUL_dB);
    state.NoisePowerUL_dBm(:) = noiseUL_dBm;
    state.InterferencePowerUL_dBm = localInterferencePowerFromMargin(noiseUL_dBm, interfMargin_dB, K);
    sinrUL_dB = state.DesiredPowerUL_dBm - noiseUL_dBm - interfMargin_dB + ...
        state.SmallScaleFading_dB - state.InterferenceVariation_dB + double(ulSinrOffset_dB);
else
    sinrUL_dB = NaN(K,1);
end

state.SINR_DL_dB = sinrDL_dB;
state.SINR_UL_dB = sinrUL_dB;
end

function state = localBuildExplicitSINRState( ...
    desiredDL_dBm, desiredUL_dBm, dlLinkCells_dBm, ulLinkCells_dBm, servingIdx, ...
    slotDL, slotUL, dlBudget, ulBudget, scs_kHz, noiseFigDL_dB, noiseFigUL_dB, ...
    activeDLCellMask, activeULTxUE, activeULTxCell)
K = numel(servingIdx);
state = localInitSINRState(K);
state.DesiredPowerDL_dBm = double(desiredDL_dBm(:));
state.DesiredPowerUL_dBm = double(desiredUL_dBm(:));
state.SmallScaleFading_dB(:) = 0;
state.InterferenceVariation_dB(:) = 0;

if slotDL
    [interfDL_dBm, activeCntDL] = localSumDLCellInterference(dlLinkCells_dBm, servingIdx, activeDLCellMask);
    noiseDL_dBm = localThermalNoisePower_dBm(dlBudget.NPRB, scs_kHz, noiseFigDL_dB);
    state.InterferencePowerDL_dBm = interfDL_dBm;
    state.NoisePowerDL_dBm(:) = noiseDL_dBm;
    state.ActiveInterfererCountDL = activeCntDL;
    state.LegacyInterferenceMarginDL_dB = localInterferenceMarginFromPowers(interfDL_dBm, state.NoisePowerDL_dBm);
    state.SINR_DL_dB = localComputeSINRFromPowers(state.DesiredPowerDL_dBm, interfDL_dBm, state.NoisePowerDL_dBm);
end

if slotUL
    [interfUL_dBm, activeCntUL] = localSumULGrantInterference(ulLinkCells_dBm, servingIdx, activeULTxUE, activeULTxCell);
    noiseUL_dBm = localThermalNoisePower_dBm(ulBudget.NPRB, scs_kHz, noiseFigUL_dB);
    state.InterferencePowerUL_dBm = interfUL_dBm;
    state.NoisePowerUL_dBm(:) = noiseUL_dBm;
    state.ActiveInterfererCountUL = activeCntUL;
    state.SINR_UL_dB = localComputeSINRFromPowers(state.DesiredPowerUL_dBm, interfUL_dBm, state.NoisePowerUL_dBm);
end
end

function state = localInitSINRState(K)
K = max(1, round(double(K)));
state = struct();
state.DesiredPowerDL_dBm = NaN(K,1);
state.InterferencePowerDL_dBm = -Inf(K,1);
state.NoisePowerDL_dBm = NaN(K,1);
state.ActiveInterfererCountDL = zeros(K,1);
state.DesiredPowerUL_dBm = NaN(K,1);
state.InterferencePowerUL_dBm = -Inf(K,1);
state.NoisePowerUL_dBm = NaN(K,1);
state.ActiveInterfererCountUL = zeros(K,1);
state.LegacyInterferenceMarginDL_dB = NaN(K,1);
state.SmallScaleFading_dB = zeros(K,1);
state.InterferenceVariation_dB = zeros(K,1);
state.SINR_DL_dB = NaN(K,1);
state.SINR_UL_dB = NaN(K,1);
end

function [interf_dBm, activeCount] = localSumDLCellInterference(linkCells_dBm, servingIdx, activeCellMask)
K = numel(servingIdx);
interf_dBm = -Inf(K,1);
activeCount = zeros(K,1);
activeCellMask = reshape(logical(activeCellMask), 1, []);
for u = 1:K
    mask = activeCellMask;
    s = min(max(round(double(servingIdx(u))), 1), numel(mask));
    mask(s) = false;
    activeCount(u) = nnz(mask);
    interf_mW = sum(localDbmToMilliwatt(linkCells_dBm(u, mask)));
    interf_dBm(u) = localMilliwattToDbm(interf_mW);
end
end

function [interf_dBm, activeCount] = localSumULGrantInterference(ulLinkCells_dBm, servingIdx, activeULTxUE, activeULTxCell)
K = numel(servingIdx);
interf_dBm = -Inf(K,1);
activeCount = zeros(K,1);
if isempty(activeULTxUE) || isempty(activeULTxCell)
    return;
end
ueVec = reshape(double(activeULTxUE), [], 1);
cellVec = reshape(double(activeULTxCell), [], 1);
pairMat = unique([ueVec, cellVec], "rows", "stable");
ueVec = pairMat(:,1);
cellVec = pairMat(:,2);
for u = 1:K
    s = min(max(round(double(servingIdx(u))), 1), size(ulLinkCells_dBm, 2));
    mask = cellVec ~= s;
    if ~any(mask)
        continue;
    end
    interfererUE = ueVec(mask);
    activeCount(u) = numel(unique(cellVec(mask)));
    interf_mW = sum(localDbmToMilliwatt(ulLinkCells_dBm(interfererUE, s)));
    interf_dBm(u) = localMilliwattToDbm(interf_mW);
end
end

function noise_dBm = localThermalNoisePower_dBm(nPRB, scs_kHz, noiseFig_dB)
nPRB = max(0, round(double(nPRB)));
if nPRB <= 0
    noise_dBm = NaN;
    return;
end
bw_Hz = max(double(nPRB) * 12 * max(double(scs_kHz), 1) * 1e3, 1);
noise_dBm = -174 + 10*log10(bw_Hz) + double(noiseFig_dB);
end

function mW = localDbmToMilliwatt(p_dBm)
mW = zeros(size(p_dBm), "double");
finiteMask = isfinite(p_dBm);
mW(finiteMask) = 10.^(double(p_dBm(finiteMask)) / 10);
end

function p_dBm = localMilliwattToDbm(mW)
p_dBm = -Inf(size(mW), "double");
finiteMask = isfinite(mW) & (mW > 0);
p_dBm(finiteMask) = 10*log10(double(mW(finiteMask)));
end

function sinr_dB = localComputeSINRFromPowers(desired_dBm, interference_dBm, noise_dBm)
desired_mW = localDbmToMilliwatt(desired_dBm);
interference_mW = localDbmToMilliwatt(interference_dBm);
noise_mW = localDbmToMilliwatt(noise_dBm);
den_mW = interference_mW + noise_mW;
sinr_dB = NaN(size(desired_mW));
validMask = isfinite(desired_dBm) & isfinite(noise_dBm) & (den_mW > 0);
sinr_dB(validMask) = 10*log10(desired_mW(validMask) ./ den_mW(validMask));
end

function margin_dB = localInterferenceMarginFromPowers(interference_dBm, noise_dBm)
interference_mW = localDbmToMilliwatt(interference_dBm);
noise_mW = localDbmToMilliwatt(noise_dBm);
margin_dB = NaN(size(noise_mW));
validMask = isfinite(noise_dBm) & (noise_mW > 0);
margin_dB(validMask) = 10*log10(1 + (interference_mW(validMask) ./ noise_mW(validMask)));
end

function interf_dBm = localInterferencePowerFromMargin(noise_dBm, margin_dB, K)
totalImpairment_mW = localDbmToMilliwatt(repmat(double(noise_dBm), K, 1)) .* 10.^(double(margin_dB) / 10);
noise_mW = localDbmToMilliwatt(repmat(double(noise_dBm), K, 1));
interf_dBm = localMilliwattToDbm(max(totalImpairment_mW - noise_mW, 0));
end

function ueIdx = localGrantRNTI(grants)
if isempty(grants)
    ueIdx = zeros(0,1);
    return;
end
ueIdx = reshape(double([grants.RNTI]), [], 1);
end

function [fastFading_dB, interfVar_dB] = localBuildChannelVariationTraces(cfg, nTTI, nUE, tti_s, seed)
awgnOnly = logical(sixgr.util.structGet(cfg, "channel.awgnOnly", false));
dopp = max(0, double(sixgr.util.structGet(cfg, "channel.dopplerHz", 0)));
if awgnOnly
    fSigma = 0;
else
    fSigma = max(0, double(sixgr.util.structGet(cfg, "channel.smallScaleStd_dB", 1.5)));
end
iSigma = max(0, double(sixgr.util.structGet(cfg, "channel.interferenceStd_dB", 0.0)));
rhoF = exp(-2*pi*max(dopp, 0) * max(tti_s, eps));
rhoI = exp(-2*pi*max(dopp, 10) * max(tti_s, eps) * 0.35);
fastFading_dB = localAR1Trace(nTTI, nUE, fSigma, rhoF, seed + 101);
interfVar_dB = localAR1Trace(nTTI, nUE, iSigma, rhoI, seed + 173);
end

function x = localAR1Trace(nTTI, nUE, sigma, rho, seed)
nTTI = max(1, round(double(nTTI)));
nUE = max(1, round(double(nUE)));
sigma = max(0, double(sigma));
rho = min(max(double(rho), 0), 0.9999);
if sigma <= 0
    x = zeros(nTTI, nUE);
    return;
end
rs = RandStream("mt19937ar", "Seed", max(1, round(double(seed))));
x = zeros(nTTI, nUE);
x(1,:) = sigma * randn(rs, 1, nUE);
gain = sqrt(max(1 - rho^2, 0));
for t = 2:nTTI
    x(t,:) = rho .* x(t-1,:) + gain .* sigma .* randn(rs, 1, nUE);
end
end

function cqi = localResolveWidebandCQI(sinr_dB, cfg, direction)
feedback = sixgr.link.resolveWidebandCQI(struct("WidebandSINR_dB", sinr_dB), cfg, direction);
cqi = double(feedback.WidebandCQI);
end

function mcs = localResolveGrantMCSIndex(cfg, grant, cqiUsed, direction)
if isfield(grant, "MCSIndex") && ~isempty(grant.MCSIndex) && isfinite(double(grant.MCSIndex))
    mcs = double(grant.MCSIndex);
    return;
end
if isfield(grant, "MCSTable") && strlength(string(grant.MCSTable)) > 0
    mcsTable = char(string(grant.MCSTable));
else
    mcsTable = localResolveDirectionMCSTable(cfg, direction, sixgr.util.structGet(grant, "Modulation", "QPSK"));
end
modStr = char(string(sixgr.util.structGet(grant, "Modulation", "QPSK")));
tcr = double(sixgr.util.structGet(grant, "TargetCodeRate", 0.5));
decision = sixgr.link.resolveMCSIndexFromProfile(modStr, tcr, ...
    "MCSTable", mcsTable, ...
    "CQI", cqiUsed, ...
    "CQITable", localResolveDirectionCQITable(cfg, direction, mcsTable));
mcs = double(decision.MCSIndex);
end

function tableName = localResolveDirectionMCSTable(cfg, direction, modulation)
dir = upper(char(string(direction)));
if strcmp(dir, "UL")
    token = sixgr.util.structGet(cfg, "phy.pusch.mcsTable", []);
else
    token = sixgr.util.structGet(cfg, "phy.pdsch.mcsTable", []);
end
if strlength(string(token)) == 0
    if sixgr.l2.mac.SchedulerBase.modOrder(modulation) >= 8
        token = "qam256_table2";
    else
        token = "qam64_table1";
    end
end
tableName = char(lower(string(token)));
end

function tableName = localResolveDirectionCQITable(cfg, direction, mcsTable)
dir = upper(char(string(direction)));
if strcmp(dir, "UL")
    token = sixgr.util.structGet(cfg, "phy.pusch.cqiTable", []);
else
    token = sixgr.util.structGet(cfg, "phy.pdsch.cqiTable", []);
end
if strlength(string(token)) == 0
    token = sixgr.link.resolveConfiguredCQITable(cfg, dir);
end
if strlength(string(token)) == 0
    if contains(lower(string(mcsTable)), "256") || contains(lower(string(mcsTable)), "table2")
        token = "table2";
    else
        token = "table1";
    end
end
tableName = char(lower(string(token)));
end

function traffic = localBuildTraffic(cfg, params, nUE, nTTI, tti_s)
customOffered = sixgr.util.structGet(params, "OfferedBits", []);
customOfferedDL = sixgr.util.structGet(params, "OfferedBitsDL", []);
customOfferedUL = sixgr.util.structGet(params, "OfferedBitsUL", []);
trafficClass = sixgr.util.structGet(params, "TrafficClass", []);
scaleVec = sixgr.util.structGet(params, "UETrafficScale", []);

if isempty(customOffered) && isempty(customOfferedDL) && isempty(customOfferedUL)
    t = sixgr.system.TrafficFactory.generate(cfg, nUE, nTTI, tti_s);
    offered = localExpandTrafficMatrix(sixgr.util.structGet(t, "OfferedBits", []), nTTI, nUE, "TrafficFactory.OfferedBits");
    offeredDL = localExpandTrafficMatrix(sixgr.util.structGet(t, "OfferedBitsDL", []), nTTI, nUE, "TrafficFactory.OfferedBitsDL");
    offeredUL = localExpandTrafficMatrix(sixgr.util.structGet(t, "OfferedBitsUL", []), nTTI, nUE, "TrafficFactory.OfferedBitsUL");
    if isempty(offeredDL) && isempty(offeredUL)
        [dlRatio, ulRatio] = localDirectionSplit(cfg);
        offeredDL = offered * dlRatio;
        offeredUL = offered * ulRatio;
    elseif isempty(offeredDL)
        offeredDL = max(0, offered - offeredUL);
    elseif isempty(offeredUL)
        offeredUL = max(0, offered - offeredDL);
    end
    offered = offeredDL + offeredUL;
    model = string(t.Model);
    transport = string(sixgr.util.structGet(t, "Transport", sixgr.util.structGet(cfg, "traffic.transport", "UDP")));
    flowDirection = string(sixgr.util.structGet(t, "FlowDirection", sixgr.util.structGet(cfg, "traffic.flowDirection", "BIDIR")));
    packetDelayBudget_ms = double(sixgr.util.structGet(t, "PacketDelayBudget_ms", ...
        sixgr.util.structGet(cfg, "traffic.packetDelayBudget_ms", ...
        sixgr.util.structGet(cfg, "traffic.qos.latencyBudget_ms", 50))));
    flowTable = sixgr.util.structGet(t, "FlowTable", table());
else
    if ~isempty(customOffered)
        offered = localExpandTrafficMatrix(double(customOffered), nTTI, nUE, "OfferedBits");
    else
        offered = [];
    end
    if ~isempty(customOfferedDL)
        offeredDL = localExpandTrafficMatrix(double(customOfferedDL), nTTI, nUE, "OfferedBitsDL");
    else
        offeredDL = [];
    end
    if ~isempty(customOfferedUL)
        offeredUL = localExpandTrafficMatrix(double(customOfferedUL), nTTI, nUE, "OfferedBitsUL");
    else
        offeredUL = [];
    end

    if isempty(offeredDL) && isempty(offeredUL)
        [dlRatio, ulRatio] = localDirectionSplit(cfg);
        if isempty(offered)
            offered = zeros(nTTI, nUE);
        end
        offeredDL = offered * dlRatio;
        offeredUL = offered * ulRatio;
    elseif isempty(offeredDL)
        if isempty(offered)
            offered = offeredUL;
        end
        offeredDL = max(0, offered - offeredUL);
    elseif isempty(offeredUL)
        if isempty(offered)
            offered = offeredDL;
        end
        offeredUL = max(0, offered - offeredDL);
    end
    if isempty(offered)
        offered = offeredDL + offeredUL;
    end
    offered = offeredDL + offeredUL;

    model = string(sixgr.util.structGet(params, "TrafficModel", "custom"));
    transport = string(sixgr.util.structGet(params, "TrafficTransport", ...
        sixgr.util.structGet(cfg, "traffic.transport", "UDP")));
    flowDirection = string(sixgr.util.structGet(params, "TrafficFlowDirection", ...
        sixgr.util.structGet(cfg, "traffic.flowDirection", "BIDIR")));
    packetDelayBudget_ms = double(sixgr.util.structGet(params, "PacketDelayBudget_ms", ...
        sixgr.util.structGet(cfg, "traffic.packetDelayBudget_ms", ...
        sixgr.util.structGet(cfg, "traffic.qos.latencyBudget_ms", 50))));
    flowTable = table();
end

if isempty(trafficClass)
    trafficClass = repmat("default", nUE, 1);
else
    trafficClass = string(trafficClass(:));
    if isscalar(trafficClass)
        trafficClass = repmat(trafficClass, nUE, 1);
    end
    if numel(trafficClass) ~= nUE
        error("sixgr:system:BadTrafficClass", "TrafficClass must have one entry per UE.");
    end
end

if isempty(scaleVec)
    scaleVec = ones(nUE,1);
    for k = 1:nUE
        cls = lower(strtrim(char(trafficClass(k))));
        switch cls
            case {"null","idle"}
                scaleVec(k) = 0;
            case {"low","light"}
                scaleVec(k) = 0.25;
            case {"high","heavy"}
                scaleVec(k) = 1.25;
            case {"full","fullbuffer","saturated"}
                scaleVec(k) = 2.5;
            otherwise
                scaleVec(k) = 1.0;
        end
    end
else
    scaleVec = double(scaleVec(:));
    if isscalar(scaleVec)
        scaleVec = repmat(scaleVec, nUE, 1);
    end
    if numel(scaleVec) ~= nUE
        error("sixgr:system:BadTrafficScale", "UETrafficScale must have one value per UE.");
    end
end

offeredDL = max(0, round(offeredDL .* scaleVec(:).'));
offeredUL = max(0, round(offeredUL .* scaleVec(:).'));
offered = offeredDL + offeredUL;

traffic = struct();
traffic.Model = model;
traffic.OfferedBits = offered;
traffic.OfferedBitsDL = offeredDL;
traffic.OfferedBitsUL = offeredUL;
traffic.MeanBitsPerUEPerTTI = mean(offered, 1);
traffic.UserClass = trafficClass;
traffic.Scale = scaleVec;
traffic.Transport = upper(string(transport));
traffic.FlowDirection = upper(string(flowDirection));
traffic.PacketDelayBudget_ms = packetDelayBudget_ms;
traffic.FlowTable = flowTable;
end

function bits = localExpandTrafficMatrix(bitsIn, nTTI, nUE, label)
if nargin < 4 || isempty(label)
    label = "traffic";
end
bits = [];
if isempty(bitsIn)
    return;
end

bits = double(bitsIn);
if isvector(bits)
    if numel(bits) == nUE
        bits = repmat(bits(:).', nTTI, 1);
    elseif numel(bits) == nTTI
        bits = repmat(bits(:), 1, nUE);
    else
        error("sixgr:system:BadTrafficShape", "%s must be scalar, NumUE, NumTTI, or NumTTI x NumUE.", label);
    end
elseif isscalar(bits)
    bits = repmat(bits, nTTI, nUE);
end

if size(bits,1) ~= nTTI || size(bits,2) ~= nUE
    error("sixgr:system:BadTrafficShape", "%s must be %d x %d (NumTTI x NumUE).", label, nTTI, nUE);
end
bits = max(bits, 0);
end

function [dlRatio, ulRatio] = localDirectionSplit(cfg)
dlRatio = double(sixgr.util.structGet(cfg, "traffic.dlRatio", 0.8));
ulRatio = double(sixgr.util.structGet(cfg, "traffic.ulRatio", 0.2));
s = max(dlRatio + ulRatio, eps);
dlRatio = dlRatio / s;
ulRatio = ulRatio / s;
end

function doFig = localResolveSaveFigures(cfg, defaultVal)
if nargin < 2
    defaultVal = false;
end
if isfield(cfg, "outputs") && isstruct(cfg.outputs)
    if isfield(cfg.outputs, "saveFigures")
        doFig = logical(cfg.outputs.saveFigures);
        return;
    end
    if isfield(cfg.outputs, "saveFIG")
        doFig = logical(cfg.outputs.saveFIG);
        return;
    end
end
doFig = logical(defaultVal);
end

function v = localGatherServingValues(M, servingIdx)
K = size(M, 1);
B = size(M, 2);
s = min(max(round(double(servingIdx(:))), 1), B);
lin = sub2ind([K B], (1:K).', s);
v = M(lin);
end

function tbsBits = localReplayTransportBlockSize(replay, fallbackTbsBits)
tbsBits = double(fallbackTbsBits);
replayTbs = double(sixgr.util.structGet(replay, "TransportBlockSize", NaN));
if isfinite(replayTbs) && replayTbs > 0
    tbsBits = replayTbs;
end
if ~(isfinite(tbsBits) && tbsBits > 0)
    tbsBits = 0;
end
end

function userMeta = localBuildReplayUserContext(direction, ueIdx, cellId, largeScaleState, powerState)
direction = upper(string(direction));
ueIdx = max(1, round(double(ueIdx)));
cellId = max(1, round(double(cellId)));

userMeta = struct();
userMeta.RuntimeCurrentDirection = char(direction);
userMeta.UEIndex = double(ueIdx);
userMeta.RuntimeServingCell = double(cellId);
userMeta.RuntimeServingPathloss_dB = localMatrixValue(largeScaleState, "Pathloss_dB", ueIdx, cellId);
userMeta.RuntimeServingBasePathloss_dB = localMatrixValue(largeScaleState, "BasePathloss_dB", ueIdx, cellId);
userMeta.RuntimeServingShadowFading_dB = localMatrixValue(largeScaleState, "ShadowFading_dB", ueIdx, cellId);
userMeta.RuntimeServingO2I_dB = localMatrixValue(largeScaleState, "O2ILoss_dB", ueIdx, cellId);
userMeta.RuntimeServingLOS = localMatrixValue(largeScaleState, "LOS", ueIdx, cellId);
userMeta.RuntimeServingRSRP_dBm = localMatrixValue(largeScaleState, "RSRP_dBm", ueIdx, cellId);
userMeta.RuntimeServingBeamGain_dB = localMatrixValue(largeScaleState, "BeamGain_dB", ueIdx, cellId);
userMeta.RuntimePathlossModelSource = char(string(sixgr.util.structGet(largeScaleState, "PathlossModelSource", "")));
userMeta.RuntimePathlossComplianceStatus = char(string(sixgr.util.structGet(largeScaleState, "PathlossComplianceStatus", "")));
userMeta.RuntimeFallbackUsedForPathloss = logical(sixgr.util.structGet(largeScaleState, "FallbackUsedForPathloss", false));
userMeta.RuntimeChannelComplianceMode = char(string(sixgr.util.structGet(largeScaleState, "ChannelComplianceMode", "")));
userMeta.RuntimeO2IModelSource = char(string(sixgr.util.structGet(largeScaleState, "O2IModelSource", "")));
userMeta.RuntimeO2IComplianceStatus = char(string(sixgr.util.structGet(largeScaleState, "O2IComplianceStatus", "")));
userMeta.RuntimeO2IComplianceReason = char(string(sixgr.util.structGet(largeScaleState, "O2IComplianceReason", "")));
userMeta.RuntimeLOSProbabilitySource = char(string(sixgr.util.structGet(largeScaleState, "LOSProbabilitySource", "")));
userMeta.RuntimeLOSComplianceStatus = char(string(sixgr.util.structGet(largeScaleState, "LOSComplianceStatus", "")));
userMeta.RuntimeLOSComplianceReason = char(string(sixgr.util.structGet(largeScaleState, "LOSComplianceReason", "")));

if direction == "UL"
    userMeta.RuntimeServingRxPower_dBm = localVectorValue(powerState, "DesiredPowerUL_dBm", ueIdx);
    userMeta.RuntimeServingLargeScaleSINR_dB = localVectorValue(powerState, "SINR_UL_dB", ueIdx);
else
    userMeta.RuntimeServingRxPower_dBm = localVectorValue(powerState, "DesiredPowerDL_dBm", ueIdx);
    userMeta.RuntimeServingLargeScaleSINR_dB = localVectorValue(powerState, "SINR_DL_dB", ueIdx);
end
end

function value = localMatrixValue(s, fieldName, rowIdx, colIdx)
value = NaN;
if ~(isstruct(s) && isfield(s, fieldName))
    return;
end
raw = double(s.(fieldName));
if isempty(raw)
    return;
end
rowIdx = max(1, min(size(raw, 1), round(double(rowIdx))));
if isvector(raw)
    colIdx = 1;
else
    colIdx = max(1, min(size(raw, 2), round(double(colIdx))));
end
value = double(raw(rowIdx, colIdx));
end

function value = localVectorValue(s, fieldName, idx)
value = NaN;
if ~(isstruct(s) && isfield(s, fieldName))
    return;
end
raw = double(s.(fieldName));
raw = raw(:);
if isempty(raw)
    return;
end
idx = max(1, min(numel(raw), round(double(idx))));
value = double(raw(idx));
end

function st = localEncodeHOState(hoPrepRemain, hoInterRemain)
K = numel(hoPrepRemain);
st = repmat("CONNECTED", K, 1);
st(hoPrepRemain > 0) = "HO_PREP";
st(hoInterRemain > 0) = "HO_INTERRUPT";
end

function trace = localInitGrantTrace(cap)
cap = max(1, round(double(cap)));
trace = struct();
trace.TTI = zeros(cap,1);
trace.Time_s = zeros(cap,1);
trace.Direction = strings(cap,1);
trace.SlotDirection = strings(cap,1);
trace.CellID = zeros(cap,1);
trace.UE = zeros(cap,1);
trace.PRBStart = NaN(cap,1);
trace.PRBCount = zeros(cap,1);
trace.SymbolStart = zeros(cap,1);
trace.NumSymbols = zeros(cap,1);
trace.TBSBits = zeros(cap,1);
trace.CQIUsed = zeros(cap,1);
trace.MCSIndex = zeros(cap,1);
trace.NumLayers = zeros(cap,1);
trace.TargetCodeRate = zeros(cap,1);
trace.AMCMode = strings(cap,1);
trace.MCSTable = strings(cap,1);
trace.CQITable = strings(cap,1);
trace.OuterLoopEnabled = false(cap,1);
trace.OuterLoopApplied = false(cap,1);
trace.OLLADeltaDb = NaN(cap,1);
trace.OLLADeltaMCS = NaN(cap,1);
trace.OLLAMarginMinDb = NaN(cap,1);
trace.OLLAMarginMaxDb = NaN(cap,1);
trace.OLLAAdjustedMCSBeforeCQICeiling = NaN(cap,1);
trace.OLLABaseRequiredSINR_dB = NaN(cap,1);
trace.OLLATargetRequiredSINR_dB = NaN(cap,1);
trace.OLLAThresholdSource = strings(cap,1);
trace.OLLAUpdateCount = NaN(cap,1);
trace.OLLAState = strings(cap,1);
trace.MCSSelectionSource = strings(cap,1);
trace.CQIProvenance = strings(cap,1);
trace.MCSValueStatus = strings(cap,1);
trace.RankSelectionPolicy = strings(cap,1);
trace.RankSelectionSource = strings(cap,1);
trace.RankDecisionReason = strings(cap,1);
trace.RankDowngradeApplied = false(cap,1);
trace.MaxSupportedLayers = NaN(cap,1);
trace.NREPerPRB = NaN(cap,1);
trace.EstimatedTBSBits = NaN(cap,1);
trace.EstimatedTBSBytes = NaN(cap,1);
trace.QueueLimited = false(cap,1);
trace.SINR_dB = NaN(cap,1);
trace.BLER = NaN(cap,1);
trace.BitErrors = NaN(cap,1);
trace.BitsCompared = NaN(cap,1);
trace.RawBER = NaN(cap,1);
trace.Ack = false(cap,1);
trace.HarqID = NaN(cap,1);
trace.RV = NaN(cap,1);
trace.NDI = NaN(cap,1);
trace.IsRetransmission = false(cap,1);
trace.DAI = NaN(cap,1);
trace.K1 = NaN(cap,1);
trace.K2 = NaN(cap,1);
trace.SearchSpaceID = NaN(cap,1);
trace.CORESETID = NaN(cap,1);
trace.BWPId = NaN(cap,1);
trace.HeadOfLineDelay_ms = NaN(cap,1);
trace.BufferBytesBefore = NaN(cap,1);
trace.BufferBytesAfter = NaN(cap,1);
trace.GrantReason = strings(cap,1);
trace.PHYDecisionRole = strings(cap,1);
trace.PHYDecisionStatus = strings(cap,1);
trace.PHYDecisionSource = strings(cap,1);
trace.PHYDecisionReason = strings(cap,1);
trace.WaveformReplayExecuted = false(cap,1);
trace.WaveformReplayReused = false(cap,1);
trace.WaveformReplayKey = strings(cap,1);
trace.ReceiverHestSINR_dB = NaN(cap,1);
trace.ReceiverHestSINRSource = strings(cap,1);
trace.ReceiverHestSINRValueRole = strings(cap,1);
trace.ReceiverHestSINRValueStatus = strings(cap,1);
trace.ReceiverHestSINRNAReason = strings(cap,1);
trace.PostEqSINR_dB = NaN(cap,1);
trace.PostEqSINRSource = strings(cap,1);
trace.PostEqSINRValueRole = strings(cap,1);
trace.PostEqSINRValueStatus = strings(cap,1);
trace.PostEqSINRNAReason = strings(cap,1);
trace.PostEqSINRPerLayer_dB = strings(cap,1);
trace.DecoderIterations = NaN(cap,1);
trace.ChannelEstimateAvailable = false(cap,1);
trace.EqualizationAvailable = false(cap,1);
trace.DecodeAttempted = false(cap,1);
trace.DecodeAvailable = false(cap,1);
trace.LLRAvailable = false(cap,1);
trace.LLRFinite = false(cap,1);
trace.TimingEstimateUsed = false(cap,1);
trace.RawTimingEstimate_samples = NaN(cap,1);
trace.AppliedTimingCorrection_samples = NaN(cap,1);
trace.TimingEstimateApplicationPolicy = strings(cap,1);
trace.TimingEstimateStatus = strings(cap,1);
trace.TimingEstimateWasClipped = false(cap,1);
trace.TimingEstimateAvailability = strings(cap,1);
trace.TimingErrorDefinition = strings(cap,1);
trace.TimingValueStatus = strings(cap,1);
trace.InjectedCFO_Hz = NaN(cap,1);
trace.TrueCFO_Hz = NaN(cap,1);
trace.EstimatedCFO_PreCorrection_Hz = NaN(cap,1);
trace.ResidualCFO_PostCorrection_Hz = NaN(cap,1);
trace.CFOError_Hz = NaN(cap,1);
trace.EstimatedCFO_Hz = NaN(cap,1);
trace.CFOEstimateAvailable = false(cap,1);
trace.CFOEstimateAvailability = strings(cap,1);
trace.ReceiverTrackingCorrectionSource = strings(cap,1);
trace.ReceiverTrackingCorrectionStatus = strings(cap,1);
trace.ReceiverTrackingCorrectionNAReason = strings(cap,1);
trace.CFOErrorDefinition = strings(cap,1);
trace.CFOValueStatus = strings(cap,1);
trace.InjectedTimingOffset_samples = NaN(cap,1);
trace.TrueTimingOffset_samples = NaN(cap,1);
trace.EstimatedTimingOffset_PreCorrection_samples = NaN(cap,1);
trace.TimingError_samples = NaN(cap,1);
trace.AppliedPathloss_dB = NaN(cap,1);
trace.AppliedShadowFading_dB = NaN(cap,1);
trace.AppliedLargeScaleGain_dB = NaN(cap,1);
trace.AppliedO2I_dB = NaN(cap,1);
trace.ServingRxPower_dBm = NaN(cap,1);
trace.ThermalNoisePower_dBm = NaN(cap,1);
trace.NoisePowerSource = strings(cap,1);
trace.PhaseNoiseConfigured = false(cap,1);
trace.PhaseNoiseApplied = false(cap,1);
trace.PhaseNoiseRMS_rad = NaN(cap,1);
trace.PTRSCPECorrectionApplied = false(cap,1);
trace.PTRSCPECorrectedSymbols = NaN(cap,1);
trace.PTRSMeanCPE_deg = NaN(cap,1);
trace.PTRSCPECorrectionReason = strings(cap,1);
trace.IQImbalanceConfigured = false(cap,1);
trace.IQImbalanceApplied = false(cap,1);
trace.IQImbalanceImageRejection_dB = NaN(cap,1);
trace.IQImbalanceMeasurementStatus = strings(cap,1);
trace.IQImbalanceCorrectionApplied = false(cap,1);
trace.IQImbalanceCorrectionAlphaAbs = NaN(cap,1);
trace.IQImbalanceCorrectionBetaAbs = NaN(cap,1);
trace.IQImbalanceCorrectionNoiseScale = NaN(cap,1);
trace.IQImbalanceCorrectionStatus = strings(cap,1);
trace.DecoderTruthProxySINR_dB = NaN(cap,1);
trace.DecoderTruthProxySINRSource = strings(cap,1);
trace.DecoderTruthProxySINRValueRole = strings(cap,1);
trace.DecoderTruthProxySINRValueStatus = strings(cap,1);
trace.DecoderTruthProxySINRNAReason = strings(cap,1);
trace.PrecoderSource = strings(cap,1);
trace.RequestedPrecoderSource = strings(cap,1);
trace.AppliedPrecoderSource = strings(cap,1);
trace.RequestedPrecoderPMI = NaN(cap,1);
trace.PrecodingMode = strings(cap,1);
trace.PrecodingApplicationStage = strings(cap,1);
trace.PrecodingActive = false(cap,1);
trace.ExplicitBeamWeightsApplied = false(cap,1);
trace.TransformPrecodingApplied = false(cap,1);
trace.BeamformingApplied = false(cap,1);
trace.AppliedBeamIndexSet = strings(cap,1);
trace.AppliedPrecoderPMI = NaN(cap,1);
trace.AppliedPrecoderValueRole = strings(cap,1);
trace.AppliedPrecoderValueStatus = strings(cap,1);
trace.AppliedPrecoderNAReason = strings(cap,1);
trace.ExplicitPrecoderReplayStatus = strings(cap,1);
trace.ExplicitPrecoderReplayBlocker = strings(cap,1);
trace.AppliedPrecoderPMIType = strings(cap,1);
trace.AppliedPrecoderCodebookMode = strings(cap,1);
trace.PrecodingNumPorts = NaN(cap,1);
trace.PrecodingNumLayers = NaN(cap,1);
trace.PrecodingMatrixRows = NaN(cap,1);
trace.PrecodingMatrixCols = NaN(cap,1);
trace = localInitializeMeasuredPHYEvidenceTrace(trace, cap);
end

function [trace, count] = localEnsureGrantTraceCapacity(trace, count, need)
if nargin < 3
    need = 1;
end
cap = numel(trace.TTI);
if count + need <= cap
    return;
end
newCap = max(count + need, round(cap * 1.5) + 256);
fn = fieldnames(trace);
for i = 1:numel(fn)
    name = fn{i};
    v = trace.(name);
    if isstring(v)
        v(cap+1:newCap,1) = "";
    elseif islogical(v)
        v(cap+1:newCap,1) = false;
    else
        v(cap+1:newCap,1) = 0;
    end
    trace.(name) = v;
end
end

function [trace, count] = localAppendGrantTrace(trace, count, t, tti_s, slotLabel, direction, ...
    cellId, grant, prbCount, tbsBits, cqiUsed, mcsIdx, numLayers, targetCodeRate, sinr_dB, bler, ack, replay)

if nargin < 18 || ~isstruct(replay)
    replay = struct();
end

[trace, count] = localEnsureGrantTraceCapacity(trace, count, 1);
count = count + 1;
i = count;

prbSet = sixgr.util.structGet(grant, "PRBSet", []);
if ~(isnumeric(prbSet) && isreal(prbSet) && ~isempty(prbSet))
    error("sixgr:system:SystemLevelRunner:MissingGrantPRBSet", ...
        "Primary grant-trace rows require the scheduler's explicit PRBSet.");
end
prbSet = double(prbSet(:));
if any(~isfinite(prbSet)) || any(prbSet ~= fix(prbSet)) || ...
        any(prbSet < 0)
    error("sixgr:system:SystemLevelRunner:InvalidGrantPRBSet", ...
        "Primary grant-trace PRBSet values must be finite nonnegative integers.");
end
prbStart = min(prbSet);

symAlloc = sixgr.util.structGet(grant, "SymbolAllocation", []);
if ~(isnumeric(symAlloc) && isreal(symAlloc) && numel(symAlloc) == 2)
    error("sixgr:system:SystemLevelRunner:MissingGrantSymbolAllocation", ...
        "Primary grant-trace rows require the scheduler's explicit " + ...
        "SymbolAllocation [start,count].");
end
symAlloc = double(symAlloc);
symAlloc = symAlloc(:).';
if any(~isfinite(symAlloc)) || any(symAlloc ~= fix(symAlloc)) || ...
        symAlloc(1) < 0 || symAlloc(2) < 1
    error("sixgr:system:SystemLevelRunner:InvalidGrantSymbolAllocation", ...
        "Primary grant-trace SymbolAllocation must contain finite integer " + ...
        "[start,count] values with start >= 0 and count >= 1.");
end
harq = sixgr.util.structGet(grant, "HARQ", struct());

trace.TTI(i) = double(t);
trace.Time_s(i) = (double(t) - 1) * double(tti_s);
trace.Direction(i) = string(direction);
trace.SlotDirection(i) = string(slotLabel);
trace.CellID(i) = double(cellId);
trace.UE(i) = double(sixgr.util.structGet(grant, "RNTI", NaN));
trace.PRBStart(i) = double(prbStart);
trace.PRBCount(i) = double(prbCount);
trace.SymbolStart(i) = double(symAlloc(1));
trace.NumSymbols(i) = double(symAlloc(2));
trace.TBSBits(i) = double(tbsBits);
trace.CQIUsed(i) = double(cqiUsed);
trace.MCSIndex(i) = double(mcsIdx);
trace.NumLayers(i) = double(numLayers);
trace.TargetCodeRate(i) = double(targetCodeRate);
trace.AMCMode(i) = string(sixgr.util.structGet(grant, "AMCMode", ""));
trace.MCSTable(i) = string(sixgr.util.structGet(grant, "MCSTable", ""));
trace.CQITable(i) = string(sixgr.util.structGet(grant, "CQITable", ""));
trace.OuterLoopEnabled(i) = logical(sixgr.util.structGet(grant, "OuterLoopEnabled", false));
trace.OuterLoopApplied(i) = logical(sixgr.util.structGet(grant, "OuterLoopApplied", false));
trace.OLLADeltaDb(i) = double(sixgr.util.structGet(grant, "OLLADeltaDb", ...
    sixgr.util.structGet(grant, "OLLADeltaMCS", NaN)));
trace.OLLADeltaMCS(i) = double(sixgr.util.structGet(grant, "OLLADeltaMCS", NaN));
trace.OLLAMarginMinDb(i) = double(sixgr.util.structGet(grant, "OLLAMarginMinDb", NaN));
trace.OLLAMarginMaxDb(i) = double(sixgr.util.structGet(grant, "OLLAMarginMaxDb", NaN));
trace.OLLAAdjustedMCSBeforeCQICeiling(i) = double(sixgr.util.structGet(grant, "OLLAAdjustedMCSBeforeCQICeiling", NaN));
trace.OLLABaseRequiredSINR_dB(i) = double(sixgr.util.structGet(grant, "OLLABaseRequiredSINR_dB", NaN));
trace.OLLATargetRequiredSINR_dB(i) = double(sixgr.util.structGet(grant, "OLLATargetRequiredSINR_dB", NaN));
trace.OLLAThresholdSource(i) = string(sixgr.util.structGet(grant, "OLLAThresholdSource", ""));
trace.OLLAUpdateCount(i) = double(sixgr.util.structGet(grant, "OLLAUpdateCount", NaN));
trace.OLLAState(i) = string(sixgr.util.structGet(grant, "OLLAState", ""));
trace.MCSSelectionSource(i) = string(sixgr.util.structGet(grant, "MCSSelectionSource", ""));
trace.CQIProvenance(i) = string(sixgr.util.structGet(grant, "CQIProvenance", ""));
trace.MCSValueStatus(i) = string(sixgr.util.structGet(grant, "MCSValueStatus", ""));
trace.RankSelectionPolicy(i) = string(sixgr.util.structGet(grant, "RankSelectionPolicy", ""));
trace.RankSelectionSource(i) = string(sixgr.util.structGet(grant, "RankSelectionSource", ""));
trace.RankDecisionReason(i) = string(sixgr.util.structGet(grant, "RankDecisionReason", ""));
trace.RankDowngradeApplied(i) = logical(sixgr.util.structGet(grant, "RankDowngradeApplied", false));
trace.MaxSupportedLayers(i) = double(sixgr.util.structGet(grant, "MaxSupportedLayers", NaN));
trace.NREPerPRB(i) = double(sixgr.util.structGet(grant, "NREPerPRB", NaN));
trace.EstimatedTBSBits(i) = double(sixgr.util.structGet(grant, "EstimatedTBSBits", NaN));
trace.EstimatedTBSBytes(i) = double(sixgr.util.structGet(grant, "EstimatedTBSBytes", NaN));
trace.QueueLimited(i) = logical(sixgr.util.structGet(grant, "QueueLimited", false));
trace.SINR_dB(i) = double(sinr_dB);
trace.BLER(i) = double(bler);
trace.BitErrors(i) = double(sixgr.util.structGet(replay, "BitErrors", NaN));
trace.BitsCompared(i) = double(sixgr.util.structGet(replay, "BitsCompared", NaN));
trace.RawBER(i) = double(sixgr.util.structGet(replay, "RawBER", NaN));
trace.Ack(i) = logical(ack);
trace.HarqID(i) = double(sixgr.util.structGet(harq, "HarqID", NaN));
trace.RV(i) = double(sixgr.util.structGet(harq, "RV", NaN));
trace.NDI(i) = double(sixgr.util.structGet(harq, "NDI", NaN));
trace.IsRetransmission(i) = logical(sixgr.util.structGet(harq, "IsRetransmission", false));
trace.DAI(i) = double(sixgr.util.structGet(grant, "DAI", NaN));
trace.K1(i) = double(sixgr.util.structGet(grant, "K1", NaN));
trace.K2(i) = double(sixgr.util.structGet(grant, "K2", NaN));
trace.SearchSpaceID(i) = double(sixgr.util.structGet(grant, "SearchSpaceID", NaN));
trace.CORESETID(i) = double(sixgr.util.structGet(grant, "CORESETID", NaN));
trace.BWPId(i) = double(sixgr.util.structGet(grant, "BWPId", NaN));
trace.HeadOfLineDelay_ms(i) = double(sixgr.util.structGet(grant, "HeadOfLineDelay_ms", NaN));
trace.BufferBytesBefore(i) = double(sixgr.util.structGet(grant, "BufferBytesBefore", NaN));
trace.BufferBytesAfter(i) = double(sixgr.util.structGet(grant, "BufferBytesAfter", NaN));
trace.GrantReason(i) = string(sixgr.util.structGet(grant, "GrantReason", ""));
trace.PHYDecisionRole(i) = string(sixgr.util.structGet(replay, "PHYDecisionRole", "measured"));
trace.PHYDecisionStatus(i) = string(sixgr.util.structGet(replay, "PHYDecisionStatus", "OK"));
trace.PHYDecisionSource(i) = string(sixgr.util.structGet(replay, "PHYDecisionSource", "sixgr.system.waveform.replayGrant"));
trace.PHYDecisionReason(i) = string(sixgr.util.structGet(replay, "PHYDecisionReason", "waveform_replay_executed"));
trace.WaveformReplayExecuted(i) = logical(sixgr.util.structGet(replay, "WaveformReplayExecuted", true));
trace.WaveformReplayReused(i) = logical(sixgr.util.structGet(replay, "WaveformReplayReused", false));
trace.WaveformReplayKey(i) = string(sixgr.util.structGet(replay, "WaveformReplayKey", ""));
trace.ReceiverHestSINR_dB(i) = double(sixgr.util.structGet(replay, "ReceiverHestSINR_dB", NaN));
trace.ReceiverHestSINRSource(i) = string(sixgr.util.structGet(replay, "ReceiverHestSINRSource", ""));
trace.ReceiverHestSINRValueRole(i) = string(sixgr.util.structGet(replay, "ReceiverHestSINRValueRole", ""));
trace.ReceiverHestSINRValueStatus(i) = string(sixgr.util.structGet(replay, "ReceiverHestSINRValueStatus", ""));
trace.ReceiverHestSINRNAReason(i) = string(sixgr.util.structGet(replay, "ReceiverHestSINRNAReason", ""));
trace.PostEqSINR_dB(i) = double(sixgr.util.structGet(replay, "PostEqSINR_dB", NaN));
trace.PostEqSINRSource(i) = string(sixgr.util.structGet(replay, "PostEqSINRSource", ""));
trace.PostEqSINRValueRole(i) = string(sixgr.util.structGet(replay, "PostEqSINRValueRole", ""));
trace.PostEqSINRValueStatus(i) = string(sixgr.util.structGet(replay, "PostEqSINRValueStatus", ""));
trace.PostEqSINRNAReason(i) = string(sixgr.util.structGet(replay, "PostEqSINRNAReason", ""));
trace.PostEqSINRPerLayer_dB(i) = localFormatNumericVector(sixgr.util.structGet(replay, "PostEqSINRPerLayer_dB", NaN));
trace.DecoderIterations(i) = double(sixgr.util.structGet(replay, "DecoderIterations", NaN));
trace = localAssignMeasuredPHYEvidenceTrace(trace, i, replay);
trace.ChannelEstimateAvailable(i) = logical(sixgr.util.structGet(replay, "ChannelEstimateAvailable", false));
trace.EqualizationAvailable(i) = logical(sixgr.util.structGet(replay, "EqualizationAvailable", false));
trace.DecodeAttempted(i) = logical(sixgr.util.structGet(replay, "DecodeAttempted", false));
trace.DecodeAvailable(i) = logical(sixgr.util.structGet(replay, "DecodeAvailable", false));
trace.LLRAvailable(i) = logical(sixgr.util.structGet(replay, "LLRAvailable", false));
trace.LLRFinite(i) = logical(sixgr.util.structGet(replay, "LLRFinite", false));
trace.TimingEstimateUsed(i) = logical(sixgr.util.structGet(replay, "TimingEstimateUsed", false));
trace.RawTimingEstimate_samples(i) = double(sixgr.util.structGet(replay, "RawTimingEstimate_samples", NaN));
trace.AppliedTimingCorrection_samples(i) = double(sixgr.util.structGet(replay, "AppliedTimingCorrection_samples", NaN));
trace.TimingEstimateApplicationPolicy(i) = string(sixgr.util.structGet(replay, "TimingEstimateApplicationPolicy", ""));
trace.TimingEstimateStatus(i) = string(sixgr.util.structGet(replay, "TimingEstimateStatus", ""));
trace.TimingEstimateWasClipped(i) = logical(sixgr.util.structGet(replay, "TimingEstimateWasClipped", false));
trace.TimingEstimateAvailability(i) = string(sixgr.util.structGet(replay, "TimingEstimateAvailability", ""));
trace.TimingErrorDefinition(i) = string(sixgr.util.structGet(replay, "TimingErrorDefinition", ""));
trace.TimingValueStatus(i) = string(sixgr.util.structGet(replay, "TimingValueStatus", ""));
trace.InjectedCFO_Hz(i) = double(sixgr.util.structGet(replay, "InjectedCFO_Hz", NaN));
trace.TrueCFO_Hz(i) = double(sixgr.util.structGet(replay, "TrueCFO_Hz", NaN));
trace.EstimatedCFO_PreCorrection_Hz(i) = double(sixgr.util.structGet(replay, "EstimatedCFO_PreCorrection_Hz", NaN));
trace.ResidualCFO_PostCorrection_Hz(i) = double(sixgr.util.structGet(replay, "ResidualCFO_PostCorrection_Hz", NaN));
trace.CFOError_Hz(i) = double(sixgr.util.structGet(replay, "CFOError_Hz", NaN));
trace.EstimatedCFO_Hz(i) = double(sixgr.util.structGet(replay, "EstimatedCFO_Hz", NaN));
trace.CFOEstimateAvailable(i) = logical(sixgr.util.structGet(replay, "CFOEstimateAvailable", false));
trace.CFOEstimateAvailability(i) = string(sixgr.util.structGet(replay, "CFOEstimateAvailability", ""));
trace.ReceiverTrackingCorrectionSource(i) = string(sixgr.util.structGet(replay, "ReceiverTrackingCorrectionSource", ""));
trace.ReceiverTrackingCorrectionStatus(i) = string(sixgr.util.structGet(replay, "ReceiverTrackingCorrectionStatus", ""));
trace.ReceiverTrackingCorrectionNAReason(i) = string(sixgr.util.structGet(replay, "ReceiverTrackingCorrectionNAReason", ""));
trace.CFOErrorDefinition(i) = string(sixgr.util.structGet(replay, "CFOErrorDefinition", ""));
trace.CFOValueStatus(i) = string(sixgr.util.structGet(replay, "CFOValueStatus", ""));
trace.InjectedTimingOffset_samples(i) = double(sixgr.util.structGet(replay, "InjectedTimingOffset_samples", NaN));
trace.TrueTimingOffset_samples(i) = double(sixgr.util.structGet(replay, "TrueTimingOffset_samples", NaN));
trace.EstimatedTimingOffset_PreCorrection_samples(i) = double(sixgr.util.structGet(replay, "EstimatedTimingOffset_PreCorrection_samples", NaN));
trace.TimingError_samples(i) = double(sixgr.util.structGet(replay, "TimingError_samples", NaN));
trace.AppliedPathloss_dB(i) = double(sixgr.util.structGet(replay, "AppliedPathloss_dB", NaN));
trace.AppliedShadowFading_dB(i) = double(sixgr.util.structGet(replay, "AppliedShadowFading_dB", NaN));
trace.AppliedLargeScaleGain_dB(i) = double(sixgr.util.structGet(replay, "AppliedLargeScaleGain_dB", NaN));
trace.AppliedO2I_dB(i) = double(sixgr.util.structGet(replay, "AppliedO2I_dB", NaN));
trace.ServingRxPower_dBm(i) = double(sixgr.util.structGet(replay, "ServingRxPower_dBm", NaN));
trace.ThermalNoisePower_dBm(i) = double(sixgr.util.structGet(replay, "ThermalNoisePower_dBm", NaN));
trace.NoisePowerSource(i) = string(sixgr.util.structGet(replay, "NoisePowerSource", ""));
trace.PhaseNoiseConfigured(i) = logical(sixgr.util.structGet(replay, "PhaseNoiseConfigured", false));
trace.PhaseNoiseApplied(i) = logical(sixgr.util.structGet(replay, "PhaseNoiseApplied", false));
trace.PhaseNoiseRMS_rad(i) = double(sixgr.util.structGet(replay, "PhaseNoiseRMS_rad", NaN));
trace.PTRSCPECorrectionApplied(i) = logical(sixgr.util.structGet(replay, "PTRSCPECorrectionApplied", false));
trace.PTRSCPECorrectedSymbols(i) = double(sixgr.util.structGet(replay, "PTRSCPECorrectedSymbols", NaN));
trace.PTRSMeanCPE_deg(i) = double(sixgr.util.structGet(replay, "PTRSMeanCPE_deg", NaN));
trace.PTRSCPECorrectionReason(i) = string(sixgr.util.structGet(replay, "PTRSCPECorrectionReason", ""));
trace.IQImbalanceConfigured(i) = logical(sixgr.util.structGet(replay, "IQImbalanceConfigured", false));
trace.IQImbalanceApplied(i) = logical(sixgr.util.structGet(replay, "IQImbalanceApplied", false));
trace.IQImbalanceImageRejection_dB(i) = double(sixgr.util.structGet(replay, "IQImbalanceImageRejection_dB", NaN));
trace.IQImbalanceMeasurementStatus(i) = string(sixgr.util.structGet(replay, "IQImbalanceMeasurementStatus", ""));
trace.IQImbalanceCorrectionApplied(i) = logical(sixgr.util.structGet(replay, "IQImbalanceCorrectionApplied", false));
trace.IQImbalanceCorrectionAlphaAbs(i) = double(sixgr.util.structGet(replay, "IQImbalanceCorrectionAlphaAbs", NaN));
trace.IQImbalanceCorrectionBetaAbs(i) = double(sixgr.util.structGet(replay, "IQImbalanceCorrectionBetaAbs", NaN));
trace.IQImbalanceCorrectionNoiseScale(i) = double(sixgr.util.structGet(replay, "IQImbalanceCorrectionNoiseScale", NaN));
trace.IQImbalanceCorrectionStatus(i) = string(sixgr.util.structGet(replay, "IQImbalanceCorrectionStatus", ""));
trace.DecoderTruthProxySINR_dB(i) = double(sixgr.util.structGet(replay, "DecoderTruthProxySINR_dB", NaN));
trace.DecoderTruthProxySINRSource(i) = string(sixgr.util.structGet(replay, "DecoderTruthProxySINRSource", ""));
trace.DecoderTruthProxySINRValueRole(i) = string(sixgr.util.structGet(replay, "DecoderTruthProxySINRValueRole", ""));
trace.DecoderTruthProxySINRValueStatus(i) = string(sixgr.util.structGet(replay, "DecoderTruthProxySINRValueStatus", ""));
trace.DecoderTruthProxySINRNAReason(i) = string(sixgr.util.structGet(replay, "DecoderTruthProxySINRNAReason", ""));
trace.PrecoderSource(i) = string(sixgr.util.structGet(replay, "PrecoderSource", ""));
trace.RequestedPrecoderSource(i) = string(sixgr.util.structGet(replay, "RequestedPrecoderSource", ""));
trace.AppliedPrecoderSource(i) = string(sixgr.util.structGet(replay, "AppliedPrecoderSource", ""));
trace.RequestedPrecoderPMI(i) = double(sixgr.util.structGet(replay, "RequestedPrecoderPMI", NaN));
trace.PrecodingMode(i) = string(sixgr.util.structGet(replay, "PrecodingMode", ""));
trace.PrecodingApplicationStage(i) = string(sixgr.util.structGet(replay, "PrecodingApplicationStage", ""));
trace.PrecodingActive(i) = logical(sixgr.util.structGet(replay, "PrecodingActive", false));
trace.ExplicitBeamWeightsApplied(i) = logical(sixgr.util.structGet(replay, "ExplicitBeamWeightsApplied", false));
trace.TransformPrecodingApplied(i) = logical(sixgr.util.structGet(replay, "TransformPrecodingApplied", false));
trace.BeamformingApplied(i) = logical(sixgr.util.structGet(replay, "BeamformingApplied", false));
trace.AppliedBeamIndexSet(i) = string(sixgr.util.structGet(replay, "AppliedBeamIndexSet", ""));
trace.AppliedPrecoderPMI(i) = double(sixgr.util.structGet(replay, "AppliedPrecoderPMI", NaN));
trace.AppliedPrecoderValueRole(i) = string(sixgr.util.structGet(replay, "AppliedPrecoderValueRole", ""));
trace.AppliedPrecoderValueStatus(i) = string(sixgr.util.structGet(replay, "AppliedPrecoderValueStatus", ""));
trace.AppliedPrecoderNAReason(i) = string(sixgr.util.structGet(replay, "AppliedPrecoderNAReason", ""));
trace.ExplicitPrecoderReplayStatus(i) = string(sixgr.util.structGet(replay, "ExplicitPrecoderReplayStatus", ""));
trace.ExplicitPrecoderReplayBlocker(i) = string(sixgr.util.structGet(replay, "ExplicitPrecoderReplayBlocker", ""));
trace.AppliedPrecoderPMIType(i) = string(sixgr.util.structGet(replay, "AppliedPrecoderPMIType", ""));
trace.AppliedPrecoderCodebookMode(i) = string(sixgr.util.structGet(replay, "AppliedPrecoderCodebookMode", ""));
trace.PrecodingNumPorts(i) = double(sixgr.util.structGet(replay, "PrecodingNumPorts", NaN));
trace.PrecodingNumLayers(i) = double(sixgr.util.structGet(replay, "PrecodingNumLayers", NaN));
trace.PrecodingMatrixRows(i) = double(sixgr.util.structGet(replay, "PrecodingMatrixRows", NaN));
trace.PrecodingMatrixCols(i) = double(sixgr.util.structGet(replay, "PrecodingMatrixCols", NaN));
end

function T = localGrantTraceToTable(trace, count)
if count <= 0
    T = table([], [], string.empty(0,1), string.empty(0,1), [], [], [], [], [], [], [], [], [], [], [], [], [], ...
        false(0,1), [], [], [], false(0,1), [], [], [], [], [], [], [], [], [], string.empty(0,1), ...
        string.empty(0,1), string.empty(0,1), string.empty(0,1), string.empty(0,1), false(0,1), false(0,1), string.empty(0,1), ...
        'VariableNames', {'TTI','Time_s','Direction','SlotDirection','CellID','UE','PRBStart','PRBCount', ...
        'SymbolStart','NumSymbols','TBSBits','CQIUsed','MCSIndex','NumLayers','TargetCodeRate', ...
        'SINR_dB','BLER','Ack','HarqID','RV','NDI','IsRetransmission','DAI','K1','K2', ...
        'SearchSpaceID','CORESETID','BWPId','HeadOfLineDelay_ms','BufferBytesBefore','BufferBytesAfter','GrantReason', ...
        'PHYDecisionRole','PHYDecisionStatus','PHYDecisionSource','PHYDecisionReason','WaveformReplayExecuted','WaveformReplayReused','WaveformReplayKey'});
    T = localAttachGrantTraceEvidenceColumns(T, trace, []);
    return;
end
idx = 1:count;
T = table(double(trace.TTI(idx)), double(trace.Time_s(idx)), string(trace.Direction(idx)), string(trace.SlotDirection(idx)), ...
    double(trace.CellID(idx)), double(trace.UE(idx)), double(trace.PRBStart(idx)), double(trace.PRBCount(idx)), ...
    double(trace.SymbolStart(idx)), double(trace.NumSymbols(idx)), double(trace.TBSBits(idx)), ...
    double(trace.CQIUsed(idx)), double(trace.MCSIndex(idx)), double(trace.NumLayers(idx)), ...
    double(trace.TargetCodeRate(idx)), double(trace.SINR_dB(idx)), double(trace.BLER(idx)), ...
    logical(trace.Ack(idx)), double(trace.HarqID(idx)), double(trace.RV(idx)), double(trace.NDI(idx)), ...
    logical(trace.IsRetransmission(idx)), double(trace.DAI(idx)), double(trace.K1(idx)), double(trace.K2(idx)), ...
    double(trace.SearchSpaceID(idx)), double(trace.CORESETID(idx)), double(trace.BWPId(idx)), ...
    double(trace.HeadOfLineDelay_ms(idx)), double(trace.BufferBytesBefore(idx)), ...
    double(trace.BufferBytesAfter(idx)), string(trace.GrantReason(idx)), ...
    string(trace.PHYDecisionRole(idx)), string(trace.PHYDecisionStatus(idx)), string(trace.PHYDecisionSource(idx)), ...
    string(trace.PHYDecisionReason(idx)), logical(trace.WaveformReplayExecuted(idx)), logical(trace.WaveformReplayReused(idx)), ...
    string(trace.WaveformReplayKey(idx)), ...
    'VariableNames', {'TTI','Time_s','Direction','SlotDirection','CellID','UE','PRBStart','PRBCount', ...
    'SymbolStart','NumSymbols','TBSBits','CQIUsed','MCSIndex','NumLayers','TargetCodeRate', ...
    'SINR_dB','BLER','Ack','HarqID','RV','NDI','IsRetransmission','DAI','K1','K2', ...
    'SearchSpaceID','CORESETID','BWPId','HeadOfLineDelay_ms','BufferBytesBefore','BufferBytesAfter','GrantReason', ...
    'PHYDecisionRole','PHYDecisionStatus','PHYDecisionSource','PHYDecisionReason','WaveformReplayExecuted','WaveformReplayReused','WaveformReplayKey'});
T = localAttachGrantTraceEvidenceColumns(T, trace, idx);
end

function T = localAttachGrantTraceEvidenceColumns(T, trace, idx)
n = height(T);
T.AMCMode = localTraceString(trace, "AMCMode", idx, n, "");
T.MCSTable = localTraceString(trace, "MCSTable", idx, n, "");
T.CQITable = localTraceString(trace, "CQITable", idx, n, "");
T.OuterLoopEnabled = localTraceLogical(trace, "OuterLoopEnabled", idx, n, false);
T.OuterLoopApplied = localTraceLogical(trace, "OuterLoopApplied", idx, n, false);
T.OLLADeltaDb = localTraceNumeric(trace, "OLLADeltaDb", idx, n, NaN);
T.OLLADeltaMCS = localTraceNumeric(trace, "OLLADeltaMCS", idx, n, NaN);
T.OLLAMarginMinDb = localTraceNumeric(trace, "OLLAMarginMinDb", idx, n, NaN);
T.OLLAMarginMaxDb = localTraceNumeric(trace, "OLLAMarginMaxDb", idx, n, NaN);
T.OLLAAdjustedMCSBeforeCQICeiling = localTraceNumeric(trace, "OLLAAdjustedMCSBeforeCQICeiling", idx, n, NaN);
T.OLLABaseRequiredSINR_dB = localTraceNumeric(trace, "OLLABaseRequiredSINR_dB", idx, n, NaN);
T.OLLATargetRequiredSINR_dB = localTraceNumeric(trace, "OLLATargetRequiredSINR_dB", idx, n, NaN);
T.OLLAThresholdSource = localTraceString(trace, "OLLAThresholdSource", idx, n, "");
T.OLLAUpdateCount = localTraceNumeric(trace, "OLLAUpdateCount", idx, n, NaN);
T.OLLAState = localTraceString(trace, "OLLAState", idx, n, "");
T.MCSSelectionSource = localTraceString(trace, "MCSSelectionSource", idx, n, "");
T.CQIProvenance = localTraceString(trace, "CQIProvenance", idx, n, "");
T.MCSValueStatus = localTraceString(trace, "MCSValueStatus", idx, n, "");
T.RankSelectionPolicy = localTraceString(trace, "RankSelectionPolicy", idx, n, "");
T.RankSelectionSource = localTraceString(trace, "RankSelectionSource", idx, n, "");
T.RankDecisionReason = localTraceString(trace, "RankDecisionReason", idx, n, "");
T.RankDowngradeApplied = localTraceLogical(trace, "RankDowngradeApplied", idx, n, false);
T.MaxSupportedLayers = localTraceNumeric(trace, "MaxSupportedLayers", idx, n, NaN);
T.NREPerPRB = localTraceNumeric(trace, "NREPerPRB", idx, n, NaN);
T.EstimatedTBSBits = localTraceNumeric(trace, "EstimatedTBSBits", idx, n, NaN);
T.EstimatedTBSBytes = localTraceNumeric(trace, "EstimatedTBSBytes", idx, n, NaN);
T.QueueLimited = localTraceLogical(trace, "QueueLimited", idx, n, false);
T.ReceiverHestSINR_dB = localTraceNumeric(trace, "ReceiverHestSINR_dB", idx, n, NaN);
T.BitErrors = localTraceNumeric(trace, "BitErrors", idx, n, NaN);
T.BitsCompared = localTraceNumeric(trace, "BitsCompared", idx, n, NaN);
T.RawBER = localTraceNumeric(trace, "RawBER", idx, n, NaN);
T.ReceiverHestSINRSource = localTraceString(trace, "ReceiverHestSINRSource", idx, n, "");
T.ReceiverHestSINRValueRole = localTraceString(trace, "ReceiverHestSINRValueRole", idx, n, "");
T.ReceiverHestSINRValueStatus = localTraceString(trace, "ReceiverHestSINRValueStatus", idx, n, "");
T.ReceiverHestSINRNAReason = localTraceString(trace, "ReceiverHestSINRNAReason", idx, n, "");
T.PostEqSINR_dB = localTraceNumeric(trace, "PostEqSINR_dB", idx, n, NaN);
T.PostEqSINRSource = localTraceString(trace, "PostEqSINRSource", idx, n, "");
T.PostEqSINRValueRole = localTraceString(trace, "PostEqSINRValueRole", idx, n, "");
T.PostEqSINRValueStatus = localTraceString(trace, "PostEqSINRValueStatus", idx, n, "");
T.PostEqSINRNAReason = localTraceString(trace, "PostEqSINRNAReason", idx, n, "");
T.PostEqSINRPerLayer_dB = localTraceString(trace, "PostEqSINRPerLayer_dB", idx, n, "");
T.DecoderIterations = localTraceNumeric(trace, "DecoderIterations", idx, n, NaN);
T = localAttachMeasuredPHYEvidenceTraceColumns(T, trace, idx);
T.ChannelEstimateAvailable = localTraceLogical(trace, "ChannelEstimateAvailable", idx, n, false);
T.EqualizationAvailable = localTraceLogical(trace, "EqualizationAvailable", idx, n, false);
T.DecodeAttempted = localTraceLogical(trace, "DecodeAttempted", idx, n, false);
T.DecodeAvailable = localTraceLogical(trace, "DecodeAvailable", idx, n, false);
T.LLRAvailable = localTraceLogical(trace, "LLRAvailable", idx, n, false);
T.LLRFinite = localTraceLogical(trace, "LLRFinite", idx, n, false);
T.TimingEstimateUsed = localTraceLogical(trace, "TimingEstimateUsed", idx, n, false);
T.RawTimingEstimate_samples = localTraceNumeric(trace, "RawTimingEstimate_samples", idx, n, NaN);
T.AppliedTimingCorrection_samples = localTraceNumeric(trace, "AppliedTimingCorrection_samples", idx, n, NaN);
T.TimingEstimateApplicationPolicy = localTraceString(trace, "TimingEstimateApplicationPolicy", idx, n, "");
T.TimingEstimateStatus = localTraceString(trace, "TimingEstimateStatus", idx, n, "");
T.TimingEstimateWasClipped = localTraceLogical(trace, "TimingEstimateWasClipped", idx, n, false);
T.TimingEstimateAvailability = localTraceString(trace, "TimingEstimateAvailability", idx, n, "");
T.TimingErrorDefinition = localTraceString(trace, "TimingErrorDefinition", idx, n, "");
T.TimingValueStatus = localTraceString(trace, "TimingValueStatus", idx, n, "");
T.InjectedCFO_Hz = localTraceNumeric(trace, "InjectedCFO_Hz", idx, n, NaN);
T.TrueCFO_Hz = localTraceNumeric(trace, "TrueCFO_Hz", idx, n, NaN);
T.EstimatedCFO_PreCorrection_Hz = localTraceNumeric(trace, "EstimatedCFO_PreCorrection_Hz", idx, n, NaN);
T.ResidualCFO_PostCorrection_Hz = localTraceNumeric(trace, "ResidualCFO_PostCorrection_Hz", idx, n, NaN);
T.CFOError_Hz = localTraceNumeric(trace, "CFOError_Hz", idx, n, NaN);
T.EstimatedCFO_Hz = localTraceNumeric(trace, "EstimatedCFO_Hz", idx, n, NaN);
T.CFOEstimateAvailable = localTraceLogical(trace, "CFOEstimateAvailable", idx, n, false);
T.CFOEstimateAvailability = localTraceString(trace, "CFOEstimateAvailability", idx, n, "");
T.ReceiverTrackingCorrectionSource = localTraceString(trace, "ReceiverTrackingCorrectionSource", idx, n, "");
T.ReceiverTrackingCorrectionStatus = localTraceString(trace, "ReceiverTrackingCorrectionStatus", idx, n, "");
T.ReceiverTrackingCorrectionNAReason = localTraceString(trace, "ReceiverTrackingCorrectionNAReason", idx, n, "");
T.CFOErrorDefinition = localTraceString(trace, "CFOErrorDefinition", idx, n, "");
T.CFOValueStatus = localTraceString(trace, "CFOValueStatus", idx, n, "");
T.InjectedTimingOffset_samples = localTraceNumeric(trace, "InjectedTimingOffset_samples", idx, n, NaN);
T.TrueTimingOffset_samples = localTraceNumeric(trace, "TrueTimingOffset_samples", idx, n, NaN);
T.EstimatedTimingOffset_PreCorrection_samples = localTraceNumeric(trace, "EstimatedTimingOffset_PreCorrection_samples", idx, n, NaN);
T.TimingError_samples = localTraceNumeric(trace, "TimingError_samples", idx, n, NaN);
T.AppliedPathloss_dB = localTraceNumeric(trace, "AppliedPathloss_dB", idx, n, NaN);
T.AppliedShadowFading_dB = localTraceNumeric(trace, "AppliedShadowFading_dB", idx, n, NaN);
T.AppliedLargeScaleGain_dB = localTraceNumeric(trace, "AppliedLargeScaleGain_dB", idx, n, NaN);
T.AppliedO2I_dB = localTraceNumeric(trace, "AppliedO2I_dB", idx, n, NaN);
T.ServingRxPower_dBm = localTraceNumeric(trace, "ServingRxPower_dBm", idx, n, NaN);
T.ThermalNoisePower_dBm = localTraceNumeric(trace, "ThermalNoisePower_dBm", idx, n, NaN);
T.NoisePowerSource = localTraceString(trace, "NoisePowerSource", idx, n, "");
T.PhaseNoiseConfigured = localTraceLogical(trace, "PhaseNoiseConfigured", idx, n, false);
T.PhaseNoiseApplied = localTraceLogical(trace, "PhaseNoiseApplied", idx, n, false);
T.PhaseNoiseRMS_rad = localTraceNumeric(trace, "PhaseNoiseRMS_rad", idx, n, NaN);
T.PTRSCPECorrectionApplied = localTraceLogical(trace, "PTRSCPECorrectionApplied", idx, n, false);
T.PTRSCPECorrectedSymbols = localTraceNumeric(trace, "PTRSCPECorrectedSymbols", idx, n, NaN);
T.PTRSMeanCPE_deg = localTraceNumeric(trace, "PTRSMeanCPE_deg", idx, n, NaN);
T.PTRSCPECorrectionReason = localTraceString(trace, "PTRSCPECorrectionReason", idx, n, "");
T.IQImbalanceConfigured = localTraceLogical(trace, "IQImbalanceConfigured", idx, n, false);
T.IQImbalanceApplied = localTraceLogical(trace, "IQImbalanceApplied", idx, n, false);
T.IQImbalanceImageRejection_dB = localTraceNumeric(trace, "IQImbalanceImageRejection_dB", idx, n, NaN);
T.IQImbalanceMeasurementStatus = localTraceString(trace, "IQImbalanceMeasurementStatus", idx, n, "");
T.IQImbalanceCorrectionApplied = localTraceLogical(trace, "IQImbalanceCorrectionApplied", idx, n, false);
T.IQImbalanceCorrectionAlphaAbs = localTraceNumeric(trace, "IQImbalanceCorrectionAlphaAbs", idx, n, NaN);
T.IQImbalanceCorrectionBetaAbs = localTraceNumeric(trace, "IQImbalanceCorrectionBetaAbs", idx, n, NaN);
T.IQImbalanceCorrectionNoiseScale = localTraceNumeric(trace, "IQImbalanceCorrectionNoiseScale", idx, n, NaN);
T.IQImbalanceCorrectionStatus = localTraceString(trace, "IQImbalanceCorrectionStatus", idx, n, "");
T.DecoderTruthProxySINR_dB = localTraceNumeric(trace, "DecoderTruthProxySINR_dB", idx, n, NaN);
T.DecoderTruthProxySINRSource = localTraceString(trace, "DecoderTruthProxySINRSource", idx, n, "");
T.DecoderTruthProxySINRValueRole = localTraceString(trace, "DecoderTruthProxySINRValueRole", idx, n, "");
T.DecoderTruthProxySINRValueStatus = localTraceString(trace, "DecoderTruthProxySINRValueStatus", idx, n, "");
T.DecoderTruthProxySINRNAReason = localTraceString(trace, "DecoderTruthProxySINRNAReason", idx, n, "");
T.PrecoderSource = localTraceString(trace, "PrecoderSource", idx, n, "");
T.RequestedPrecoderSource = localTraceString(trace, "RequestedPrecoderSource", idx, n, "");
T.AppliedPrecoderSource = localTraceString(trace, "AppliedPrecoderSource", idx, n, "");
T.RequestedPrecoderPMI = localTraceNumeric(trace, "RequestedPrecoderPMI", idx, n, NaN);
T.PrecodingMode = localTraceString(trace, "PrecodingMode", idx, n, "");
T.PrecodingApplicationStage = localTraceString(trace, "PrecodingApplicationStage", idx, n, "");
T.PrecodingActive = localTraceLogical(trace, "PrecodingActive", idx, n, false);
T.ExplicitBeamWeightsApplied = localTraceLogical(trace, "ExplicitBeamWeightsApplied", idx, n, false);
T.TransformPrecodingApplied = localTraceLogical(trace, "TransformPrecodingApplied", idx, n, false);
T.BeamformingApplied = localTraceLogical(trace, "BeamformingApplied", idx, n, false);
T.AppliedBeamIndexSet = localTraceString(trace, "AppliedBeamIndexSet", idx, n, "");
T.AppliedPrecoderPMI = localTraceNumeric(trace, "AppliedPrecoderPMI", idx, n, NaN);
T.AppliedPrecoderValueRole = localTraceString(trace, "AppliedPrecoderValueRole", idx, n, "");
T.AppliedPrecoderValueStatus = localTraceString(trace, "AppliedPrecoderValueStatus", idx, n, "");
T.AppliedPrecoderNAReason = localTraceString(trace, "AppliedPrecoderNAReason", idx, n, "");
T.ExplicitPrecoderReplayStatus = localTraceString(trace, "ExplicitPrecoderReplayStatus", idx, n, "");
T.ExplicitPrecoderReplayBlocker = localTraceString(trace, "ExplicitPrecoderReplayBlocker", idx, n, "");
T.AppliedPrecoderPMIType = localTraceString(trace, "AppliedPrecoderPMIType", idx, n, "");
T.AppliedPrecoderCodebookMode = localTraceString(trace, "AppliedPrecoderCodebookMode", idx, n, "");
T.PrecodingNumPorts = localTraceNumeric(trace, "PrecodingNumPorts", idx, n, NaN);
T.PrecodingNumLayers = localTraceNumeric(trace, "PrecodingNumLayers", idx, n, NaN);
T.PrecodingMatrixRows = localTraceNumeric(trace, "PrecodingMatrixRows", idx, n, NaN);
T.PrecodingMatrixCols = localTraceNumeric(trace, "PrecodingMatrixCols", idx, n, NaN);
end

function trace = localInitializeMeasuredPHYEvidenceTrace(trace, cap)
row = sixgr.link.emptyMeasuredPHYEvidenceRow();
names = fieldnames(row);
for i = 1:numel(names)
    name = names{i};
    if isstring(row.(name)) || ischar(row.(name))
        trace.(name) = strings(cap, 1);
    else
        trace.(name) = NaN(cap, 1);
    end
end
end

function trace = localAssignMeasuredPHYEvidenceTrace(trace, rowIdx, replay)
evidence = sixgr.link.deriveMeasuredPHYEvidence(replay);
defaults = sixgr.link.emptyMeasuredPHYEvidenceRow();
names = fieldnames(defaults);
for i = 1:numel(names)
    name = names{i};
    if isstring(defaults.(name)) || ischar(defaults.(name))
        trace.(name)(rowIdx) = string(evidence.(name));
    else
        trace.(name)(rowIdx) = double(evidence.(name));
    end
end
end

function T = localAttachMeasuredPHYEvidenceTraceColumns(T, trace, idx)
n = height(T);
defaults = sixgr.link.emptyMeasuredPHYEvidenceRow();
names = fieldnames(defaults);
for i = 1:numel(names)
    name = names{i};
    if isstring(defaults.(name)) || ischar(defaults.(name))
        T.(name) = localTraceString(trace, name, idx, n, "");
    else
        T.(name) = localTraceNumeric(trace, name, idx, n, NaN);
    end
end
end

function values = localTraceNumeric(trace, name, idx, n, defaultValue)
values = repmat(double(defaultValue), n, 1);
if n == 0 || ~isfield(trace, name)
    return;
end
values = double(trace.(name)(idx));
values = values(:);
end

function values = localTraceString(trace, name, idx, n, defaultValue)
values = repmat(string(defaultValue), n, 1);
if n == 0 || ~isfield(trace, name)
    return;
end
values = string(trace.(name)(idx));
values = values(:);
end

function values = localTraceLogical(trace, name, idx, n, defaultValue)
values = repmat(logical(defaultValue), n, 1);
if n == 0 || ~isfield(trace, name)
    return;
end
values = logical(trace.(name)(idx));
values = values(:);
end

function token = localFormatNumericVector(values)
values = double(values(:));
values = values(isfinite(values));
if isempty(values)
    token = "";
    return;
end
parts = strings(numel(values), 1);
for i = 1:numel(values)
    parts(i) = string(values(i));
end
token = strjoin(parts, "|");
end

function T = localBuildHARQProcessTable(grantTable)
if isempty(grantTable)
    T = table([], [], string.empty(0,1), [], [], [], [], [], false(0,1), false(0,1), string.empty(0,1), [], [], [], [], ...
        'VariableNames', {'TTI','Time_s','Direction','CellID','UE','HarqID','RV','NDI', ...
        'IsRetransmission','Ack','Outcome','TBSBits','MCSIndex','CQIUsed','BLER'});
    return;
end
n = height(grantTable);
outcome = repmat("NACK", n, 1);
outcome(logical(grantTable.Ack)) = "ACK";
T = table(double(grantTable.TTI), double(grantTable.Time_s), string(grantTable.Direction), ...
    double(grantTable.CellID), double(grantTable.UE), double(grantTable.HarqID), ...
    double(grantTable.RV), double(grantTable.NDI), logical(grantTable.IsRetransmission), ...
    logical(grantTable.Ack), outcome, double(grantTable.TBSBits), ...
    double(grantTable.MCSIndex), double(grantTable.CQIUsed), double(grantTable.BLER), ...
    'VariableNames', {'TTI','Time_s','Direction','CellID','UE','HarqID','RV','NDI', ...
    'IsRetransmission','Ack','Outcome','TBSBits','MCSIndex','CQIUsed','BLER'});
end

function trace = localInitCellLoadTrace(nRows)
nRows = max(1, round(double(nRows)));
trace = struct();
trace.TTI = zeros(nRows,1);
trace.Time_s = zeros(nRows,1);
trace.CellID = zeros(nRows,1);
trace.SlotDirection = strings(nRows,1);
trace.ActiveUE_DL = zeros(nRows,1);
trace.ActiveUE_UL = zeros(nRows,1);
trace.GrantCountDL = zeros(nRows,1);
trace.GrantCountUL = zeros(nRows,1);
trace.OfferedBitsDL = zeros(nRows,1);
trace.OfferedBitsUL = zeros(nRows,1);
trace.QueueBitsDL_Begin = zeros(nRows,1);
trace.QueueBitsUL_Begin = zeros(nRows,1);
trace.ServedBitsDL = zeros(nRows,1);
trace.ServedBitsUL = zeros(nRows,1);
trace.DroppedBitsDL = zeros(nRows,1);
trace.DroppedBitsUL = zeros(nRows,1);
trace.QueueBitsDL_End = zeros(nRows,1);
trace.QueueBitsUL_End = zeros(nRows,1);
end

function T = localCellLoadTraceToTable(trace)
T = table(double(trace.TTI), double(trace.Time_s), double(trace.CellID), string(trace.SlotDirection), ...
    double(trace.ActiveUE_DL), double(trace.ActiveUE_UL), ...
    double(trace.GrantCountDL), double(trace.GrantCountUL), ...
    double(trace.OfferedBitsDL), double(trace.OfferedBitsUL), ...
    double(trace.QueueBitsDL_Begin), double(trace.QueueBitsUL_Begin), ...
    double(trace.ServedBitsDL), double(trace.ServedBitsUL), ...
    double(trace.DroppedBitsDL), double(trace.DroppedBitsUL), ...
    double(trace.QueueBitsDL_End), double(trace.QueueBitsUL_End), ...
    'VariableNames', {'TTI','Time_s','CellID','SlotDirection','ActiveUE_DL','ActiveUE_UL', ...
    'GrantCountDL','GrantCountUL','OfferedBitsDL','OfferedBitsUL', ...
    'QueueBitsDL_Begin','QueueBitsUL_Begin','ServedBitsDL','ServedBitsUL', ...
    'DroppedBitsDL','DroppedBitsUL','QueueBitsDL_End','QueueBitsUL_End'});
end

function trace = localInitInterferenceTrace(nRows)
nRows = max(1, round(double(nRows)));
trace = struct();
trace.TTI = zeros(nRows,1);
trace.Time_s = zeros(nRows,1);
trace.UE = zeros(nRows,1);
trace.ServingCell = zeros(nRows,1);
trace.Pathloss_dB = NaN(nRows,1);
trace.RxPower_dBm = NaN(nRows,1);
trace.Noise_dBm = NaN(nRows,1);
trace.InterferenceMargin_dB = NaN(nRows,1);
trace.SmallScaleFading_dB = NaN(nRows,1);
trace.InterferenceVariation_dB = NaN(nRows,1);
trace.DesiredPowerDL_dBm = NaN(nRows,1);
trace.InterferencePowerDL_dBm = NaN(nRows,1);
trace.NoiseDL_dBm = NaN(nRows,1);
trace.ActiveInterfererCountDL = zeros(nRows,1);
trace.DesiredPowerUL_dBm = NaN(nRows,1);
trace.InterferencePowerUL_dBm = NaN(nRows,1);
trace.NoiseUL_dBm = NaN(nRows,1);
trace.ActiveInterfererCountUL = zeros(nRows,1);
trace.SINR_DL_dB = NaN(nRows,1);
trace.SINR_UL_dB = NaN(nRows,1);
trace.RSRP_dBm = NaN(nRows,1);
end

function T = localInterferenceTraceToTable(trace)
% Keep the legacy DL alias columns for downstream readers:
% RxPower_dBm == DesiredPowerDL_dBm, Noise_dBm == NoiseDL_dBm, and
% InterferenceMargin_dB is the exact DL interference-over-noise margin.
T = table(double(trace.TTI), double(trace.Time_s), double(trace.UE), double(trace.ServingCell), ...
    double(trace.Pathloss_dB), double(trace.RxPower_dBm), double(trace.Noise_dBm), ...
    double(trace.InterferenceMargin_dB), double(trace.SmallScaleFading_dB), ...
    double(trace.InterferenceVariation_dB), double(trace.DesiredPowerDL_dBm), ...
    double(trace.InterferencePowerDL_dBm), double(trace.NoiseDL_dBm), ...
    double(trace.ActiveInterfererCountDL), double(trace.DesiredPowerUL_dBm), ...
    double(trace.InterferencePowerUL_dBm), double(trace.NoiseUL_dBm), ...
    double(trace.ActiveInterfererCountUL), double(trace.SINR_DL_dB), ...
    double(trace.SINR_UL_dB), double(trace.RSRP_dBm), ...
    'VariableNames', {'TTI','Time_s','UE','ServingCell','Pathloss_dB','RxPower_dBm', ...
    'Noise_dBm','InterferenceMargin_dB','SmallScaleFading_dB','InterferenceVariation_dB', ...
    'DesiredPowerDL_dBm','InterferencePowerDL_dBm','NoiseDL_dBm','ActiveInterfererCountDL', ...
    'DesiredPowerUL_dBm','InterferencePowerUL_dBm','NoiseUL_dBm','ActiveInterfererCountUL', ...
    'SINR_DL_dB','SINR_UL_dB','RSRP_dBm'});
end

function trace = localInitBeamEventTrace(cap)
cap = max(1, round(double(cap)));
trace = struct();
trace.TTI = zeros(cap,1);
trace.Time_s = zeros(cap,1);
trace.UE = zeros(cap,1);
trace.ServingCell = zeros(cap,1);
trace.PrevBeamIndex = NaN(cap,1);
trace.NewBeamIndex = NaN(cap,1);
trace.PrevBeamGain_dB = NaN(cap,1);
trace.NewBeamGain_dB = NaN(cap,1);
trace.EventType = strings(cap,1);
end

function [trace, count] = localEnsureBeamEventCapacity(trace, count, need)
if nargin < 3
    need = 1;
end
cap = numel(trace.TTI);
if count + need <= cap
    return;
end
newCap = max(count + need, round(cap * 1.5) + 256);
fn = fieldnames(trace);
for i = 1:numel(fn)
    name = fn{i};
    v = trace.(name);
    if isstring(v)
        v(cap+1:newCap,1) = "";
    else
        v(cap+1:newCap,1) = NaN;
    end
    trace.(name) = v;
end
end

function [trace, count] = localAppendBeamEvents(trace, count, t, tti_s, servingCell, ...
    beamIdxNow, beamGainNow_dB, prevCell, prevBeamIdx, prevBeamGain_dB)
K = numel(servingCell);
for u = 1:K
    if ~isfinite(beamIdxNow(u))
        continue;
    end
    isInitial = ~isfinite(prevBeamIdx(u)) || ~isfinite(prevCell(u));
    isChanged = ~isInitial && ...
        (round(double(beamIdxNow(u))) ~= round(double(prevBeamIdx(u))) || ...
         round(double(servingCell(u))) ~= round(double(prevCell(u))));
    if ~(isInitial || isChanged)
        continue;
    end
    [trace, count] = localEnsureBeamEventCapacity(trace, count, 1);
    count = count + 1;
    i = count;
    trace.TTI(i) = double(t);
    trace.Time_s(i) = (double(t) - 1) * double(tti_s);
    trace.UE(i) = double(u);
    trace.ServingCell(i) = double(servingCell(u));
    trace.PrevBeamIndex(i) = double(prevBeamIdx(u));
    trace.NewBeamIndex(i) = double(beamIdxNow(u));
    trace.PrevBeamGain_dB(i) = double(prevBeamGain_dB(u));
    trace.NewBeamGain_dB(i) = double(beamGainNow_dB(u));
    if isInitial
        trace.EventType(i) = "initial_attach";
    else
        trace.EventType(i) = "beam_or_cell_switch";
    end
end
end

function T = localBeamEventTraceToTable(trace, count)
if count <= 0
    T = table([], [], [], [], [], [], [], [], string.empty(0,1), ...
        'VariableNames', {'TTI','Time_s','UE','ServingCell','PrevBeamIndex','NewBeamIndex', ...
        'PrevBeamGain_dB','NewBeamGain_dB','EventType'});
    return;
end
idx = 1:count;
T = table(double(trace.TTI(idx)), double(trace.Time_s(idx)), double(trace.UE(idx)), ...
    double(trace.ServingCell(idx)), double(trace.PrevBeamIndex(idx)), ...
    double(trace.NewBeamIndex(idx)), double(trace.PrevBeamGain_dB(idx)), ...
    double(trace.NewBeamGain_dB(idx)), string(trace.EventType(idx)), ...
    'VariableNames', {'TTI','Time_s','UE','ServingCell','PrevBeamIndex','NewBeamIndex', ...
    'PrevBeamGain_dB','NewBeamGain_dB','EventType'});
end

function T = localBuildHandoverEventsTable(ue, fromCell, toCell, trigTTI, startTTI, completeTTI, status, reason, tti_s)
if isempty(ue)
    T = table([], [], [], [], [], [], [], string.empty(0,1), string.empty(0,1), ...
        'VariableNames', {'UE','FromCell','ToCell','TriggerTTI','StartTTI','CompleteTTI','Interruption_ms','Status','Reason'});
    return;
end
interruption_ms = zeros(numel(ue),1);
valid = isfinite(startTTI) & isfinite(completeTTI);
interruption_ms(valid) = 1e3 * tti_s .* max(completeTTI(valid) - startTTI(valid) + 1, 0);
T = table(double(ue), double(fromCell), double(toCell), double(trigTTI), ...
    double(startTTI), double(completeTTI), double(interruption_ms), string(status), string(reason), ...
    'VariableNames', {'UE','FromCell','ToCell','TriggerTTI','StartTTI','CompleteTTI','Interruption_ms','Status','Reason'});
end

function T = localBuildMobilityControlSeries(tti_s, measReports, beamUpdates, hoTriggers, hoStarts, hoCompletes, hoInterruptedUE)
n = numel(measReports);
tti = (1:n).';
t = (tti - 1) .* tti_s;
T = table(tti, t, ...
    double(measReports(:)), double(beamUpdates(:)), double(hoTriggers(:)), ...
    double(hoStarts(:)), double(hoCompletes(:)), double(hoInterruptedUE(:)), ...
    'VariableNames', {'TTI','Time_s','MeasurementReports','BeamUpdates','HO_Triggered', ...
                      'HO_Started','HO_Completed','UEInterrupted'});
end

function ueByCell = localSplitUEByServingCell(activeUE, servingIdx, nCells)
ueByCell = cell(max(1, round(double(nCells))), 1);
if isempty(activeUE)
    return;
end
idx = activeUE(:);
cellOfUE = servingIdx(idx);
[cellOfUESorted, ord] = sort(cellOfUE);
idxSorted = idx(ord);
cut = [0; find(diff(cellOfUESorted) ~= 0); numel(cellOfUESorted)];
for i = 1:(numel(cut)-1)
    s = cut(i) + 1;
    e = cut(i + 1);
    c = min(max(round(double(cellOfUESorted(s))), 1), numel(ueByCell));
    ueByCell{c} = idxSorted(s:e);
end
end

function ueSummary = localBuildUESummary( ...
    ue, layout, trafficClass, offeredBits, servedPerUE, droppedPerUE, ...
    sinrHist, rsrpHist, ebnoHist, blerHist, queueHist, dServeHist, simDur_s)

K = size(sinrHist, 2);
if numel(servedPerUE) ~= K
    servedPerUE = reshape(servedPerUE, [], 1);
    K = numel(servedPerUE);
end
offeredPerUE = sum(offeredBits, 1).';

dMean = mean(dServeHist, 1, "omitnan").';
zone = repmat("mid", K, 1);
v = dMean(~isnan(dMean));
if ~isempty(v)
    centerThr = quantile(v, 0.20);
    edgeThr = quantile(v, 0.80);
    zone(dMean <= centerThr) = "center";
    zone(dMean >= edgeThr) = "edge";
end

throughputUE_Mbps = servedPerUE / max(simDur_s, eps) / 1e6;
meanSINR = mean(sinrHist, 1, "omitnan").';
p05SINR = localQuantilePerColumn(sinrHist, 0.05).';
p95SINR = localQuantilePerColumn(sinrHist, 0.95).';
meanRSRP = mean(rsrpHist, 1, "omitnan").';
meanEbNo = mean(ebnoHist, 1, "omitnan").';
meanBLER = mean(blerHist, 1, "omitnan").';
meanQueue = mean(queueHist, 1, "omitnan").';

ueId = (1:K).';
indoor = false(K,1);
speed = NaN(K,1);
if isfield(ue, "indoor"), indoor = logical(ue.indoor(:)); end
if isfield(ue, "speed_kmh"), speed = double(ue.speed_kmh(:)); end

ueSummary = table(ueId, zone, string(trafficClass(:)), indoor, speed, dMean, ...
    offeredPerUE, servedPerUE, droppedPerUE, throughputUE_Mbps, ...
    meanSINR, p05SINR, p95SINR, meanRSRP, meanEbNo, meanBLER, meanQueue, ...
    'VariableNames', {'UE','Zone','TrafficClass','Indoor','Speed_kmh','MeanServingDistance_m', ...
                      'OfferedBits','ServedBits','DroppedBits','Throughput_Mbps', ...
                      'MeanSINR_dB','P05SINR_dB','P95SINR_dB','MeanRSRP_dBm','MeanEbNo_dB', ...
                      'MeanBLER','MeanQueue_bits'});
end

function timeSeries = localBuildTimeSeries( ...
    tti_s, offeredBitsTTI, servedBitsTTI, droppedBitsTTI, activeUECount, ...
    scheduledUE_DL, scheduledUE_UL, slotDirection, ...
    offeredBitsTTI_DL, offeredBitsTTI_UL, servedBitsTTI_DL, servedBitsTTI_UL, ...
    droppedBitsTTI_DL, droppedBitsTTI_UL, ...
    sinrHist, rsrpHist, ebnoHist, queueHist, queueHistDL, queueHistUL)

nTTI = size(sinrHist, 1);
ttis = (1:nTTI).';
time_s = (ttis - 1) * tti_s;

meanSINR = mean(sinrHist, 2, "omitnan");
p05SINR = localQuantilePerRow(sinrHist, 0.05);
p95SINR = localQuantilePerRow(sinrHist, 0.95);
meanRSRP = mean(rsrpHist, 2, "omitnan");
meanEbNo = mean(ebnoHist, 2, "omitnan");
meanQueue = mean(queueHist, 2, "omitnan");
p95Queue = localQuantilePerRow(queueHist, 0.95);
meanQueueDL = mean(queueHistDL, 2, "omitnan");
meanQueueUL = mean(queueHistUL, 2, "omitnan");

instThroughput_Mbps = (servedBitsTTI / max(tti_s, eps)) / 1e6;
offered_Mbps = (offeredBitsTTI / max(tti_s, eps)) / 1e6;
instThroughputDL_Mbps = (servedBitsTTI_DL / max(tti_s, eps)) / 1e6;
instThroughputUL_Mbps = (servedBitsTTI_UL / max(tti_s, eps)) / 1e6;
offeredDL_Mbps = (offeredBitsTTI_DL / max(tti_s, eps)) / 1e6;
offeredUL_Mbps = (offeredBitsTTI_UL / max(tti_s, eps)) / 1e6;
scheduledAny = max(scheduledUE_DL, scheduledUE_UL);

timeSeries = table(ttis, time_s, string(slotDirection), ...
    offeredBitsTTI, offeredBitsTTI_DL, offeredBitsTTI_UL, ...
    servedBitsTTI, servedBitsTTI_DL, servedBitsTTI_UL, ...
    droppedBitsTTI, droppedBitsTTI_DL, droppedBitsTTI_UL, ...
    offered_Mbps, offeredDL_Mbps, offeredUL_Mbps, ...
    instThroughput_Mbps, instThroughputDL_Mbps, instThroughputUL_Mbps, ...
    activeUECount, scheduledAny, scheduledUE_DL, scheduledUE_UL, ...
    meanSINR, p05SINR, p95SINR, meanRSRP, meanEbNo, meanQueue, p95Queue, ...
    meanQueueDL, meanQueueUL, ...
    'VariableNames', {'TTI','Time_s','SlotDirection', ...
                      'OfferedBits','OfferedBitsDL','OfferedBitsUL', ...
                      'ServedBits','ServedBitsDL','ServedBitsUL', ...
                      'DroppedBits','DroppedBitsDL','DroppedBitsUL', ...
                      'Offered_Mbps','OfferedDL_Mbps','OfferedUL_Mbps', ...
                      'Throughput_Mbps','ThroughputDL_Mbps','ThroughputUL_Mbps', ...
                      'ActiveUE','ScheduledUE','ScheduledUE_DL','ScheduledUE_UL', ...
                      'MeanSINR_dB','P05SINR_dB','P95SINR_dB','MeanRSRP_dBm', ...
                      'MeanEbNo_dB','MeanQueue_bits','P95Queue_bits', ...
                      'MeanQueueDL_bits','MeanQueueUL_bits'});
end

function [backendLabel, phyModeLabel, waveformBacked, proxyPHYActive, fallbackUsed] = localDescribeSystemPHY(phy)
backendLabel = "NON_WAVEFORM_SYSTEM_PHY_BLOCKED";
phyModeLabel = "BLOCKED_NON_WAVEFORM_BACKEND";
waveformBacked = false;
proxyPHYActive = true;
fallbackUsed = true;
if isa(phy, "sixgr.system.WaveformPHY")
    waveformBacked = true;
    proxyPHYActive = false;
    fallbackUsed = false;
    if isprop(phy, "ExecutionBackend")
        backendLabel = string(phy.ExecutionBackend);
    else
        backendLabel = "WAVEFORM_SYSTEM_PHY";
    end
    if isprop(phy, "PHYMode")
        phyModeLabel = string(phy.PHYMode);
    else
        phyModeLabel = "GRANT_CRC_WAVEFORM_REPLAY_EXPERIMENTAL";
    end
end
end

function replay = localLastPHYReplay(phy)
replay = struct();
try
    if isprop(phy, "LastReplay")
        replay = phy.LastReplay;
    end
catch
    replay = struct();
end
end

function tf = localPHYDecisionUnavailable(replay)
tf = false;
if nargin < 1 || ~isstruct(replay)
    return;
end
status = upper(strtrim(string(sixgr.util.structGet(replay, "PHYDecisionStatus", ""))));
role = lower(strtrim(string(sixgr.util.structGet(replay, "PHYDecisionRole", ""))));
tf = any(status == ["NOT_AVAILABLE", "UNSUPPORTED"]) || any(role == ["unavailable", "unsupported"]);
end

function algoProc = localBuildAlgoTable( ...
    cfg, trafficModel, trafficClass, nTTI, tti_s, K, decodeOkCount, decodeFailCount, overflowEvents, avgActiveUE, ...
    hoTriggerTotal, hoCompleteTotal, hoInterruptedUEmean, phyBackendLabel, phyModeLabel, waveformBacked, proxyPHYActive, fallbackUsed)

scheduler = string(sixgr.util.structGet(cfg, "mac.scheduler.type", "rr"));
pathlossModel = string(sixgr.util.structGet(cfg, "channel.pathlossModel", "nrPathLoss"));
duplexMode = string(sixgr.util.structGet(cfg, "phy.duplex.mode", "TDD"));
wfDL = string(sixgr.util.structGet(cfg, "phy.waveform.dl", "CP-OFDM"));
wfUL = string(sixgr.util.structGet(cfg, "phy.waveform.ul", "CP-OFDM"));
uClass = unique(string(trafficClass(:)));
uClass = join(uClass, ",");

name = ["NumTTI";"TTI_s";"NumUE";"Scheduler";"PathlossModel";"TrafficModel"; ...
        "TrafficClasses";"DuplexMode";"WaveformDL";"WaveformUL"; ...
        "DecodeOK";"DecodeFail";"OverflowEvents";"AvgActiveUE"; ...
        "HOTriggered";"HOCompleted";"HOInterruptedUE_Mean"; ...
        "PHYBackend";"PHYMode";"WaveformBacked";"WaveformPHYActive";"ProxyPHYActive";"FallbackUsed"];
value = [string(nTTI);string(tti_s);string(K);scheduler;pathlossModel;string(trafficModel); ...
         string(uClass);duplexMode;wfDL;wfUL;string(decodeOkCount);string(decodeFailCount); ...
         string(overflowEvents);string(avgActiveUE); ...
         string(hoTriggerTotal);string(hoCompleteTotal);string(hoInterruptedUEmean); ...
         string(phyBackendLabel);string(phyModeLabel);string(logical(waveformBacked)); ...
         string(logical(waveformBacked));string(logical(proxyPHYActive));string(logical(fallbackUsed))];
algoProc = table(name, value, 'VariableNames', {'Metric','Value'});
end

function q = localQuantilePerColumn(X, p)
n = size(X, 2);
q = NaN(1, n);
for c = 1:n
    v = X(:,c);
    v = v(~isnan(v));
    if ~isempty(v)
        q(c) = quantile(v, p);
    end
end
end

function q = localQuantilePerRow(X, p)
n = size(X, 1);
q = NaN(n, 1);
for r = 1:n
    v = X(r,:);
    v = v(~isnan(v));
    if ~isempty(v)
        q(r) = quantile(v, p);
    end
end
end

function files = localExportFigures(runFolder, timeSeries, ueSummary, ...
    sinrHist, rsrpHist, ebnoHist, queueHist, servedBitsTTI, detailedTrace, posXHist, posYHist, figRes, scatterCap)

if nargin < 12 || ~(isfinite(figRes) && figRes >= 72)
    figRes = 140;
end
if nargin < 13 || ~(isfinite(scatterCap) && scatterCap >= 2000)
    scatterCap = 12000;
end

files = {};
figDir = fullfile(runFolder, "image");
sixgr.util.ensureDir(figDir);
set(groot, "defaultFigureVisible", "off");

% SINR CDF
f = figure("Color","w");
ax = axes(f);
localPlotEmpiricalCDF(ax, sinrHist(~isnan(sinrHist)));
grid(ax, "on");
xlabel("SINR (dB)"); ylabel("CDF"); title("SINR CDF");
fp = fullfile(figDir, "system_sinr_cdf.png");
sixgr.util.exportFigureArtifact(f, fp, "Resolution", figRes); close(f);
files{end+1} = fp;

% RSRP vs SINR
f = figure("Color","w");
x = sinrHist(:); y = rsrpHist(:);
good = isfinite(x) & isfinite(y);
idx = find(good);
if numel(idx) > scatterCap
    idx = idx(round(linspace(1,numel(idx),scatterCap)));
end
scatter(x(idx), y(idx), 4, ".", "MarkerEdgeAlpha", 0.3); grid on;
xlabel("SINR (dB)"); ylabel("RSRP (dBm)"); title("RSRP vs SINR");
fp = fullfile(figDir, "system_rsrp_vs_sinr.png");
sixgr.util.exportFigureArtifact(f, fp, "Resolution", figRes); close(f);
files{end+1} = fp;

% EbNo vs time
f = figure("Color","w");
t = timeSeries.Time_s;
plot(t, timeSeries.MeanEbNo_dB, "LineWidth", 1.2); hold on;
plot(t, timeSeries.MeanSINR_dB, "LineWidth", 1.0);
grid on; xlabel("Time (s)"); ylabel("dB");
title("Mean Eb/No and SINR vs Time");
legend({"Mean Eb/No","Mean SINR"}, "Location", "best");
fp = fullfile(figDir, "system_ebno_sinr_vs_time.png");
sixgr.util.exportFigureArtifact(f, fp, "Resolution", figRes); close(f);
files{end+1} = fp;

% Throughput and offered load vs time
f = figure("Color","w");
plot(t, timeSeries.Offered_Mbps, "LineWidth", 1.0); hold on;
plot(t, timeSeries.Throughput_Mbps, "LineWidth", 1.3);
grid on; xlabel("Time (s)"); ylabel("Mbps");
title("Offered Load vs Throughput");
legend({"Offered","Served"}, "Location", "best");
fp = fullfile(figDir, "system_throughput_vs_time.png");
sixgr.util.exportFigureArtifact(f, fp, "Resolution", figRes); close(f);
files{end+1} = fp;

% Queue evolution
f = figure("Color","w");
plot(t, timeSeries.MeanQueue_bits, "LineWidth", 1.2); hold on;
plot(t, timeSeries.P95Queue_bits, "LineWidth", 1.0);
grid on; xlabel("Time (s)"); ylabel("Queue (bits)");
title("Queue Evolution");
legend({"Mean queue","P95 queue"}, "Location", "best");
fp = fullfile(figDir, "system_queue_vs_time.png");
sixgr.util.exportFigureArtifact(f, fp, "Resolution", figRes); close(f);
files{end+1} = fp;

% UE throughput by traffic class
f = figure("Color","w");
cats = categorical(ueSummary.TrafficClass);
boxchart(cats, ueSummary.Throughput_Mbps); grid on;
xlabel("Traffic class"); ylabel("UE throughput (Mbps)");
title("UE Throughput by Traffic Class");
fp = fullfile(figDir, "system_ue_throughput_by_traffic_class.png");
sixgr.util.exportFigureArtifact(f, fp, "Resolution", figRes); close(f);
files{end+1} = fp;

% Cell-edge vs center SINR
f = figure("Color","w");
ax = axes(f);
hold(ax, "on");
zc = ueSummary.Zone == "center";
ze = ueSummary.Zone == "edge";
leg = strings(0,1);
if any(zc)
    localPlotEmpiricalCDF(ax, ueSummary.MeanSINR_dB(zc));
    leg(end+1,1) = "Center"; %#ok<AGROW>
end
if any(ze)
    localPlotEmpiricalCDF(ax, ueSummary.MeanSINR_dB(ze));
    leg(end+1,1) = "Edge"; %#ok<AGROW>
end
grid(ax, "on"); xlabel("Mean SINR (dB)"); ylabel("CDF");
title("Center vs Edge UE Mean SINR");
if ~isempty(leg)
    legend(cellstr(leg), "Location", "best");
end
fp = fullfile(figDir, "system_center_edge_sinr_cdf.png");
sixgr.util.exportFigureArtifact(f, fp, "Resolution", figRes); close(f);
files{end+1} = fp;

% Mobility trajectories (if captured)
if detailedTrace && ~isempty(posXHist) && ~isempty(posYHist)
    f = figure("Color","w"); hold on; grid on; axis equal;
    nUE = size(posXHist, 2);
    pick = round(linspace(1, nUE, min(nUE, 24)));
    for i = 1:numel(pick)
        u = pick(i);
        plot(posXHist(:,u), posYHist(:,u), "-");
    end
    xlabel("x (m)"); ylabel("y (m)");
    title("Sample UE Mobility Trajectories");
    fp = fullfile(figDir, "system_ue_trajectories.png");
    sixgr.util.exportFigureArtifact(f, fp, "Resolution", figRes); close(f);
    files{end+1} = fp;
end
end

function h = localPlotEmpiricalCDF(ax, values)
if nargin < 1 || isempty(ax) || ~isgraphics(ax, "axes")
    ax = gca;
end
values = double(values(:));
values = values(isfinite(values));
if isempty(values)
    h = plot(ax, NaN, NaN, "LineWidth", 1.2);
    return;
end
values = sort(values);
y = (1:numel(values)) ./ numel(values);
h = stairs(ax, values, y, "LineWidth", 1.2);
ylim(ax, [0 1]);
end

function localWriteReplayScript(mFile, nTTI, tti_s, detailedTrace)
fid = fopen(mFile, "w");
if fid < 0
    error("sixgr:system:WriteReplayFailed", "Cannot write replay script.");
end
cleanup = onCleanup(@() fclose(fid)); %#ok<NASGU>

fprintf(fid, "function out = run_replay_system(cfgFile)\\n");
fprintf(fid, "%% Auto-generated replay script for system-level run\\n");
fprintf(fid, "if nargin < 1 || isempty(cfgFile), cfgFile = 'config/suite_config.json'; end\\n");
fprintf(fid, "setup6GRSimToolkit('Verbose',true);\\n");
fprintf(fid, "cfg = sixgr_loadConfig(cfgFile);\\n");
fprintf(fid, "cfg.run.mode = 'system';\\n");
fprintf(fid, "cfg.run.shortRun = false;\\n");
fprintf(fid, "rootDir = fileparts(which('setup6GRSimToolkit'));\\n");
fprintf(fid, "ctx = sixgr.core.SimContext(cfg,'RootDir',rootDir);\\n");
fprintf(fid, "params = struct();\\n");
fprintf(fid, "params.NumTTI = %d;\\n", nTTI);
fprintf(fid, "params.TTI_s = %.6f;\\n", tti_s);
fprintf(fid, "params.DetailedTrace = %d;\\n", double(logical(detailedTrace)));
fprintf(fid, "out = sixgr.system.SystemLevelRunner.run(ctx, params);\\n");
fprintf(fid, "disp(out.KPITable);\\n");
fprintf(fid, "end\\n");
end

function runtime = localBuildRuntimeSummary(startUTC, runTimer, runFolder, errors)
runtime = struct();
runtime.StartedUTC = char(string(startUTC));
runtime.CompletedUTC = char(string(localUTCStamp()));
runtime.ElapsedSeconds = double(toc(runTimer));
runtime.RunFolder = char(string(runFolder));
runtime.WarningCount = 0;
runtime.Warnings = strings(0,1);
runtime.ErrorCount = double(numel(errors));
runtime.Errors = string(errors(:));
end

function nSlots = localResolveProgressEverySlots(cfg, nTTI)
nSlots = sixgr.util.structGet(cfg, "run.logEverySlots", ...
    sixgr.util.structGet(cfg, "run.snapshotEverySlots", ...
    sixgr.util.structGet(cfg, "outputs.liveProgressEverySlots", [])));
if isempty(nSlots) || ~isfinite(double(nSlots)) || double(nSlots) <= 0
    nSlots = max(1, floor(double(nTTI) / 100));
end
nSlots = max(1, round(double(nSlots)));
end

function [enabled, timeout_s, slotLimit] = localResolveNoProgressGuard(cfg, progressEverySlots, nTTI)
enabled = logical(sixgr.util.structGet(cfg, "run.hangDetectionEnabled", ...
    sixgr.util.structGet(cfg, "run.hangDetection.enabled", true)));
timeout_s = double(sixgr.util.structGet(cfg, "run.noProgressTimeoutSeconds", ...
    sixgr.util.structGet(cfg, "run.hangDetection.noProgressTimeoutSeconds", 180)));
if ~(isfinite(timeout_s) && timeout_s > 0)
    timeout_s = inf;
end
slotLimit = sixgr.util.structGet(cfg, "run.noProgressSlotLimit", []);
if isempty(slotLimit) || ~isfinite(double(slotLimit)) || double(slotLimit) <= 0
    slotLimit = max([50, 3 * max(1, round(double(progressEverySlots))), ceil(0.02 * max(1, double(nTTI)))]);
end
slotLimit = max(1, round(double(slotLimit)));
end

function localEmitLiveProgress(cfg, log, runTimer, slotIdx, totalSlots, tti_s, ...
    slotLabel, activeUECount, nCells, grantCount, servedBits, droppedBits, ...
    overflowEvents, stageName)

if nargin < 14 || strlength(string(stageName)) == 0
    stageName = "system_level_lls_progress";
end
slotIdx = max(0, round(double(slotIdx)));
totalSlots = max(1, round(double(totalSlots)));
elapsed_s = double(toc(runTimer));
completion = min(1, max(0, double(slotIdx) / max(double(totalSlots), 1)));
simTime_ms = 1e3 * double(tti_s) * double(slotIdx);
stageText = char(string(stageName));
slotText = char(string(slotLabel));
nowUTC = localUTCStamp();

msg = sprintf(['%s slot=%d/%d completion=%.4f elapsed_s=%.1f ' ...
    'slot_direction=%s active_ue=%d cells=%d grants=%d served_bits=%.0f ' ...
    'dropped_bits=%.0f overflow_events=%d'], ...
    stageText, slotIdx, totalSlots, completion, elapsed_s, slotText, ...
    round(double(activeUECount)), round(double(nCells)), round(double(grantCount)), ...
    double(servedBits), double(droppedBits), round(double(overflowEvents)));

try
    fprintf('[%s] INFO %s\n', nowUTC, msg);
catch
end
try
    if ~isempty(log)
        log.info(string(msg));
    end
catch
end

localEmitFilesystemLiveProgress(cfg, nowUTC, stageText, slotIdx, totalSlots, ...
    completion, elapsed_s, simTime_ms, tti_s, slotText, "", NaN, NaN, ...
    NaN, NaN, activeUECount, nCells, grantCount, servedBits, droppedBits, ...
    overflowEvents);

try
    if sixgr.db.isArtifactStoreActive()
        payload = struct();
        payload.stage = stageText;
        payload.current_slot = double(slotIdx);
        payload.total_slots = double(totalSlots);
        payload.run_completion = completion;
        payload.elapsed_s = elapsed_s;
        payload.sim_time_ms = simTime_ms;
        payload.slot_duration_ms = 1e3 * double(tti_s);
        payload.slot_direction = slotText;
        payload.active_ue_count = double(activeUECount);
        payload.cell_count = double(nCells);
        payload.grant_count_slot = double(grantCount);
        payload.served_bits_total = double(servedBits);
        payload.dropped_bits_total = double(droppedBits);
        payload.overflow_event_count = double(overflowEvents);
        payload.scenario_id = char(string(sixgr.util.structGet(cfg, ...
            "meta.lls6gScenarioID", sixgr.util.structGet(cfg, "scenario.id", ""))));
        payload.run_profile = char(string(sixgr.util.structGet(cfg, "run.profile", ...
            sixgr.util.structGet(cfg, "run.mode", ""))));
        payload.value_role = "measured";
        payload.value_source = "sixgr.system.SystemLevelRunner";
        payload.value_status = "OK";
        payload.placeholder_flag = false;
        payload.fallback_flag = false;
        payload.config_only_flag = false;
        payload.timestamp_utc = nowUTC;
        sixgr.db.markRunStatus("running", payload);
        sixgr.db.appendLogLine("INFO", nowUTC, msg);
    end
catch ME
    try
        fprintf('[%s] WARN system progress DB heartbeat failed: %s\n', nowUTC, ME.message);
    catch
    end
    end
end

function tf = localShouldEmitReplayHeartbeat(grantIndex, grantTotal, runTimer, ...
    lastHeartbeat_s, everyGrants, everySeconds)

grantIndex = max(1, round(double(grantIndex)));
grantTotal = max(1, round(double(grantTotal)));
everyGrants = max(1, round(double(everyGrants)));
everySeconds = max(1, double(everySeconds));
elapsedNow_s = double(toc(runTimer));

tf = grantIndex == 1 || grantIndex == grantTotal || ...
    mod(grantIndex - 1, everyGrants) == 0 || ...
    (elapsedNow_s - double(lastHeartbeat_s)) >= everySeconds;
end

function localEmitLiveReplayProgress(cfg, log, runTimer, slotIdx, totalSlots, tti_s, ...
    slotLabel, activeUECount, nCells, grantCount, servedBits, droppedBits, ...
    overflowEvents, stageName, replayDirection, grantIndex, grantTotal, cellId, ueId)

slotIdx = max(0, round(double(slotIdx)));
totalSlots = max(1, round(double(totalSlots)));
grantIndex = max(1, round(double(grantIndex)));
grantTotal = max(1, round(double(grantTotal)));
cellId = max(1, round(double(cellId)));
ueId = max(1, round(double(ueId)));
elapsed_s = double(toc(runTimer));
completion = min(1, max(0, double(slotIdx) / max(double(totalSlots), 1)));
simTime_ms = 1e3 * double(tti_s) * double(slotIdx);
stageText = char(string(stageName));
slotText = char(string(slotLabel));
dirText = char(upper(string(replayDirection)));
nowUTC = localUTCStamp();

msg = sprintf(['%s slot=%d/%d completion=%.4f elapsed_s=%.1f ' ...
    'slot_direction=%s replay_direction=%s replay_grant=%d/%d ' ...
    'cell=%d ue=%d active_ue=%d cells=%d grants=%d served_bits=%.0f ' ...
    'dropped_bits=%.0f overflow_events=%d'], ...
    stageText, slotIdx, totalSlots, completion, elapsed_s, slotText, dirText, ...
    grantIndex, grantTotal, cellId, ueId, round(double(activeUECount)), ...
    round(double(nCells)), round(double(grantCount)), double(servedBits), ...
    double(droppedBits), round(double(overflowEvents)));

try
    fprintf('[%s] INFO %s\n', nowUTC, msg);
catch
end
try
    if ~isempty(log)
        log.info(string(msg));
    end
catch
end

localEmitFilesystemLiveProgress(cfg, nowUTC, stageText, slotIdx, totalSlots, ...
    completion, elapsed_s, simTime_ms, tti_s, slotText, dirText, grantIndex, ...
    grantTotal, cellId, ueId, activeUECount, nCells, grantCount, servedBits, ...
    droppedBits, overflowEvents);

try
    if sixgr.db.isArtifactStoreActive()
        payload = struct();
        payload.stage = stageText;
        payload.current_slot = double(slotIdx);
        payload.total_slots = double(totalSlots);
        payload.run_completion = completion;
        payload.elapsed_s = elapsed_s;
        payload.sim_time_ms = simTime_ms;
        payload.slot_duration_ms = 1e3 * double(tti_s);
        payload.slot_direction = slotText;
        payload.replay_direction = dirText;
        payload.replay_grant_index = double(grantIndex);
        payload.replay_grant_total = double(grantTotal);
        payload.replay_cell_id = double(cellId);
        payload.replay_ue_id = double(ueId);
        payload.active_ue_count = double(activeUECount);
        payload.cell_count = double(nCells);
        payload.grant_count_slot = double(grantCount);
        payload.served_bits_total = double(servedBits);
        payload.dropped_bits_total = double(droppedBits);
        payload.overflow_event_count = double(overflowEvents);
        payload.scenario_id = char(string(sixgr.util.structGet(cfg, ...
            "meta.lls6gScenarioID", sixgr.util.structGet(cfg, "scenario.id", ""))));
        payload.run_profile = char(string(sixgr.util.structGet(cfg, "run.profile", ...
            sixgr.util.structGet(cfg, "run.mode", ""))));
        payload.value_role = "measured";
        payload.value_source = "sixgr.system.SystemLevelRunner";
        payload.value_status = "OK";
        payload.placeholder_flag = false;
        payload.fallback_flag = false;
        payload.config_only_flag = false;
        payload.timestamp_utc = nowUTC;
        sixgr.db.markRunStatus("running", payload);
        sixgr.db.appendLogLine("INFO", nowUTC, msg);
    end
catch ME
    try
        fprintf('[%s] WARN system replay DB heartbeat failed: %s\n', nowUTC, ME.message);
    catch
    end
end
end

function localEmitFilesystemLiveProgress(cfg, nowUTC, stageText, slotIdx, totalSlots, ...
    completion, elapsed_s, simTime_ms, tti_s, slotText, replayDirection, ...
    replayGrantIndex, replayGrantTotal, cellId, ueId, activeUECount, nCells, ...
    grantCount, servedBits, droppedBits, overflowEvents)

runFolder = localResolveLLSRunFolder(cfg);
if strlength(runFolder) == 0
    return;
end

try
    sixgr.util.ensureFolder(runFolder);
    reportCsvDir = fullfile(runFolder, "reports", "csv");
    sixgr.util.ensureFolder(reportCsvDir);

    payload = struct();
    payload.LastUpdateAt = char(string(nowUTC));
    payload.CurrentStage = char(string(stageText));
    payload.CurrentSlot = double(slotIdx);
    payload.TotalSlots = double(totalSlots);
    payload.RunCompletion = double(completion);
    payload.ElapsedSeconds = double(elapsed_s);
    payload.SimTime_ms = double(simTime_ms);
    payload.SlotDuration_ms = 1e3 * double(tti_s);
    payload.SlotDirection = char(string(slotText));
    payload.ReplayDirection = char(string(replayDirection));
    payload.ReplayGrantIndex = double(replayGrantIndex);
    payload.ReplayGrantTotal = double(replayGrantTotal);
    payload.CellId = double(cellId);
    payload.UEId = double(ueId);
    payload.ActiveUECount = double(activeUECount);
    payload.CellCount = double(nCells);
    payload.GrantCountSlot = double(grantCount);
    payload.ServedBitsTotal = double(servedBits);
    payload.DroppedBitsTotal = double(droppedBits);
    payload.OverflowEventCount = double(overflowEvents);
    payload.RunCompleted = false;
    payload.ResultOk = false;
    payload.MatlabPID = feature("getpid");
    payload.Source = "sixgr.system.SystemLevelRunner";
    sixgr.util.jsonWrite(fullfile(runFolder, "RUNNING.status.json"), payload);

    row = table( ...
        string(nowUTC), string(stageText), double(slotIdx), double(totalSlots), ...
        double(completion), double(elapsed_s), double(simTime_ms), ...
        1e3 * double(tti_s), string(slotText), string(replayDirection), ...
        double(replayGrantIndex), double(replayGrantTotal), double(cellId), ...
        double(ueId), double(activeUECount), double(nCells), double(grantCount), ...
        double(servedBits), double(droppedBits), double(overflowEvents), ...
        string("sixgr.system.SystemLevelRunner"), ...
        'VariableNames', {'TimestampUTC','StageName','CurrentSlot','TotalSlots', ...
        'RunCompletion','ElapsedSeconds','SimTime_ms','SlotDuration_ms', ...
        'SlotDirection','ReplayDirection','ReplayGrantIndex','ReplayGrantTotal', ...
        'CellId','UEId','ActiveUECount','CellCount','GrantCountSlot', ...
        'ServedBitsTotal','DroppedBitsTotal','OverflowEventCount','Source'});

    progressPath = fullfile(reportCsvDir, "live_stage_progress.csv");
    T = localReadProgressTable(progressPath);
    T = [T; row]; %#ok<AGROW>
    sixgr.util.csvWriteTable(progressPath, T);
catch ME
    try
        fprintf('[%s] WARN filesystem live progress heartbeat failed: %s\n', ...
            char(string(nowUTC)), ME.message);
    catch
    end
end
end

function runFolder = localResolveLLSRunFolder(cfg)
runFolder = string(sixgr.util.structGet(cfg, "lls6g.outputRunFolder", ""));
if strlength(strtrim(runFolder)) > 0
    return;
end
runFolder = string(sixgr.util.structGet(cfg, "outputs.runFolder", ...
    sixgr.util.structGet(cfg, "run.runFolder", "")));
end

function T = localReadProgressTable(pathText)
if exist(pathText, "file") ~= 2
    T = localEmptyProgressTable();
    return;
end
try
    T = readtable(pathText, "VariableNamingRule", "preserve");
    expected = string(localEmptyProgressTable().Properties.VariableNames);
    if ~all(ismember(expected, string(T.Properties.VariableNames)))
        T = localEmptyProgressTable();
    end
catch
    T = localEmptyProgressTable();
end
end

function T = localEmptyProgressTable()
T = table(strings(0,1), strings(0,1), zeros(0,1), zeros(0,1), ...
    zeros(0,1), zeros(0,1), zeros(0,1), zeros(0,1), ...
    strings(0,1), strings(0,1), NaN(0,1), NaN(0,1), NaN(0,1), ...
    NaN(0,1), zeros(0,1), zeros(0,1), zeros(0,1), zeros(0,1), ...
    zeros(0,1), zeros(0,1), strings(0,1), ...
    'VariableNames', {'TimestampUTC','StageName','CurrentSlot','TotalSlots', ...
    'RunCompletion','ElapsedSeconds','SimTime_ms','SlotDuration_ms', ...
    'SlotDirection','ReplayDirection','ReplayGrantIndex','ReplayGrantTotal', ...
    'CellId','UEId','ActiveUECount','CellCount','GrantCountSlot', ...
    'ServedBitsTotal','DroppedBitsTotal','OverflowEventCount','Source'});
end

function env = localBuildEnvironmentSummary(ctx)
env = struct();
env.Platform = char(string(computer));
env.Architecture = char(string(computer("arch")));
env.MATLABVersion = char(string(version));
env.MATLABRelease = char(string(version("-release")));
env.JavaVersion = char(string(version("-java")));
env.Hostname = char(string(getenv("COMPUTERNAME")));
env.OS = char(string(getenv("OS")));
env.Toolboxes = sixgr.util.getToolboxStatus();
env.RunFolder = char(string(ctx.RunFolder));
end

function txt = localUTCStamp()
dt = datetime("now", "TimeZone", "UTC", "Format", "yyyy-MM-dd HH:mm:ss");
txt = char(replace(string(dt), " ", "T") + "Z");
end
