classdef SystemLevelRunner
% sixgr.system.SystemLevelRunner
% Abstract system-level simulation with traffic, scheduling, and KPI export.

    methods(Static)
        function out = run(ctx, params)
            if nargin < 2 || isempty(params)
                params = struct();
            end

            cfg = ctx.Cfg;
            log = ctx.Logger;
            runTimer = tic;
            startedUTC = localUTCStamp();

            nTTI = double(sixgr.util.structGet(params, "NumTTI", ...
                          sixgr.util.structGet(cfg, "run.numTTI", 200)));
            tti_s = localSlotDuration(cfg, params);

            simDuration_s = sixgr.util.structGet(params, "SimDuration_s", ...
                            sixgr.util.structGet(cfg, "system.simDuration_s", []));
            if ~isempty(simDuration_s)
                nTTI = ceil(double(simDuration_s) / max(tti_s, eps));
            end

            forceLong = logical(sixgr.util.structGet(params, "ForceLong", false));
            if sixgr.util.structGet(cfg, "run.shortRun", false) && ~forceLong
                nTTI = min(nTTI, 40);
            end
            nTTI = max(1, round(nTTI));

            detailedTrace = logical(sixgr.util.structGet(params, "DetailedTrace", ...
                               sixgr.util.structGet(cfg, "outputs.detailedSystemTrace", false)));
            bw_Hz = double(sixgr.util.structGet(cfg, "channel.bandwidth_Hz", 20e6));
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

            db = sixgr.util.structGet(params, "BLERDB", struct());
            lut = sixgr.util.structGet(params, "BLERLUT", []);
            pphy = params;
            pphy.BLERDB = db;
            pphy.BLERLUT = lut;
            pphy.PHYBackend = sixgr.util.structGet(params, "PHYBackend", ...
                sixgr.util.structGet(cfg, "system.phyBackend", "abstract"));
            phy = sixgr.system.PhyFactory.create(cfg, pphy, "Seed", seed + 31);
            [phyBackendLabel, phyModeLabel, waveformBacked] = localDescribeSystemPHY(phy);
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
            decodeOkCountUL = 0;
            decodeFailCountUL = 0;
            overflowEvents = 0;
            scheduler = lower(char(string(sixgr.util.structGet(cfg, "mac.scheduler.type", "rr"))));
            ulSinrOffset_dB = double(sixgr.util.structGet(cfg, "system.ulSinrOffset_dB", -1.0));
            scs_kHz = double(sixgr.util.structGet(cfg, "phy.carrier.SubcarrierSpacing", ...
                sixgr.util.structGet(cfg, "channel.subcarrierSpacing_kHz", 30)));
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
            handoverEnable = logical(sixgr.util.structGet(cfg, "system.handover.enable", nCells > 1));
            hoA3Offset_dB = double(sixgr.util.structGet(cfg, "system.handover.a3Offset_dB", 3.0));
            hoHyst_dB = double(sixgr.util.structGet(cfg, "system.handover.hysteresis_dB", 1.0));
            hoTTTslots = max(1, round(double(sixgr.util.structGet(cfg, "system.handover.timeToTrigger_slots", 6))));
            hoMinServingSlots = max(0, round(double(sixgr.util.structGet(cfg, "system.handover.minServingSlots", 8))));
            hoPrepSlots = max(0, round(double(sixgr.util.structGet(cfg, "system.handover.preparationSlots", 1))));
            hoInterruptionSlots = max(0, round(double(sixgr.util.structGet(cfg, "system.handover.interruptionSlots", 2))));
            hoBlockDuringPrep = logical(sixgr.util.structGet(cfg, "system.handover.blockDuringPreparation", false));

            measPeriodSlots = max(1, round(double(sixgr.util.structGet(cfg, "system.measurement.periodSlots", 2))));
            measAlpha = min(max(double(sixgr.util.structGet(cfg, "system.measurement.filterAlpha", 0.7)), 0), 0.99);

            beamEnable = logical(sixgr.util.structGet(cfg, "system.beam.enable", true));
            beamUpdatePeriodSlots = max(1, round(double(sixgr.util.structGet(cfg, "system.beam.updatePeriod_slots", 4))));
            nBeams = max(1, round(double(sixgr.util.structGet(cfg, "system.beam.numBeams", ...
                sixgr.util.structGet(cfg, "phy.ssb.nBeams", 8)))));
            beamSpanDeg = max(30, min(240, double(sixgr.util.structGet(cfg, "system.beam.sectorSpan_deg", 120))));
            beamMaxGain_dB = double(sixgr.util.structGet(cfg, "system.beam.maxGain_dB", 12));
            fc_GHz = max(double(sixgr.util.structGet(cfg, "channel.fc_Hz", 4e9)) / 1e9, 0.1);

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
            noiseFig_dB = double(sixgr.util.structGet(cfg, "scenario.bs.noiseFigure_dB", 7));
            noise_dBm = -174 + 10*log10(max(bw_Hz,1)) + noiseFig_dB;
            interfMargin_dB = double(sixgr.util.structGet(cfg, "channel.interferenceMargin_dB", 3));
            nRB = max(1, localEstimateNRB(cfg, bw_Hz));
            [fastFading_dB, interfVar_dB] = localBuildChannelVariationTraces(cfg, nTTI, K, tti_s, seed);
            mobilityEnable = logical(sixgr.util.structGet(cfg, "scenario.mobility.enable", true));
            mobilityPeriod_s = max(tti_s, double(sixgr.util.structGet(cfg, "scenario.mobility.updatePeriod_s", tti_s)));
            mobilityUpdateSlots = sixgr.util.structGet(cfg, "system.mobility.updatePeriod_slots", []);
            if isempty(mobilityUpdateSlots)
                mobilityUpdateSlots = mobilityPeriod_s / max(tti_s, eps);
            end
            mobilityUpdateSlots = max(1, round(double(mobilityUpdateSlots)));
            largeScaleUpdateSlots = sixgr.util.structGet(cfg, "system.largeScaleUpdatePeriod_slots", []);
            if isempty(largeScaleUpdateSlots)
                largeScaleUpdateSlots = mobilityUpdateSlots;
            end
            largeScaleUpdateSlots = max(1, round(double(largeScaleUpdateSlots)));

            d2d = zeros(K, nCells);
            rawRSRPCells_dBm = NaN(K, nCells);
            pl_dB_cache = NaN(K,1);
            prevServingIdx = servingIdxState;

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

            for t = 1:nTTI
                doMobilityUpdate = (t == 1) || (mod(t-1, mobilityUpdateSlots) == 0);
                if doMobilityUpdate && mobilityEnable
                    dtMove_s = tti_s * min(mobilityUpdateSlots, nTTI - t + 1);
                    [ue, mobModel] = sixgr.scenario.mobility.updatePositions(ue, cfg, dtMove_s, mobModel);
                end

                doLargeScaleUpdate = (t == 1) || doMobilityUpdate || (mod(t-1, largeScaleUpdateSlots) == 0);
                if doLargeScaleUpdate
                    d2d = localDistanceMatrix(ue.pos_m, layout.bs.pos_m, layout.wraparoundEnabled, layout.area_m);
                    rawRSRPCells_dBm = localEstimateCellRSRP(layout.bs.txPower_dBm(:).', d2d, fc_GHz, beamGain_dB);
                end
                if t == 1
                    [~, servingIdxState] = min(d2d, [], 2);
                    servingIdxState = min(max(round(servingIdxState), 1), nCells);
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

                if beamEnable && (t == 1 || mod(t-1, beamUpdatePeriodSlots) == 0)
                    [beamIdx, beamGain_dB] = localSelectBestBeamPerLink( ...
                        ue.pos_m, layout.bs.pos_m, layout.bs.azim_deg, nBeams, beamSpanDeg, beamMaxGain_dB);
                    beamUpdateCount(t) = K;
                    rawRSRPCells_dBm = localEstimateCellRSRP(layout.bs.txPower_dBm(:).', d2d, fc_GHz, beamGain_dB);
                end

                if t == 1 || mod(t-1, measPeriodSlots) == 0
                    if any(isnan(measRSRP_dBm(:)))
                        measRSRP_dBm = rawRSRPCells_dBm;
                    else
                        measRSRP_dBm = measAlpha .* measRSRP_dBm + (1 - measAlpha) .* rawRSRPCells_dBm;
                    end
                    measReportCount(t) = K;
                end

                if handoverEnable && nCells > 1
                    for u = 1:K
                        if hoPrepRemain(u) > 0 || hoInterRemain(u) > 0
                            continue;
                        end
                        sCell = min(max(round(servingIdxState(u)), 1), nCells);
                        sMetric = measRSRP_dBm(u, sCell);
                        if ~isfinite(sMetric)
                            [~, sCell] = min(d2d(u,:));
                            servingIdxState(u) = sCell;
                            servingSinceSlot(u) = t;
                            sMetric = measRSRP_dBm(u, sCell);
                        end
                        [bestMetric, bestCell] = max(measRSRP_dBm(u,:));
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
                linIdx = sub2ind(size(d2d), (1:K).', servingIdx);
                dServe = d2d(linIdx);
                dServeHist(t,:) = dServe(:).';

                txP_dBm = layout.bs.txPower_dBm(servingIdx);
                servingChanged = (servingIdx ~= prevServingIdx) | ~isfinite(pl_dB_cache);
                if doLargeScaleUpdate
                    txPos = layout.bs.pos_m(servingIdx, :).';
                    rxPos = ue.pos_m.';
                    [pl_dB, ~, ~] = plModel.pathloss(txPos, rxPos, "IndoorRx", ue.indoor(:).');
                    pl_dB = pl_dB(:);
                    pl_dB_cache = pl_dB;
                else
                    pl_dB = pl_dB_cache;
                    if any(servingChanged)
                        idxCh = find(servingChanged);
                        txPos = layout.bs.pos_m(servingIdx(idxCh), :).';
                        rxPos = ue.pos_m(idxCh, :).';
                        [pl_dB_ch, ~, ~] = plModel.pathloss(txPos, rxPos, "IndoorRx", ue.indoor(idxCh).');
                        pl_dB_ch = pl_dB_ch(:);
                        pl_dB(idxCh) = pl_dB_ch;
                        pl_dB_cache(idxCh) = pl_dB_ch;
                    end
                end
                prevServingIdx = servingIdx;

                rxP_dBm = txP_dBm(:) - pl_dB;
                sinr_dB = rxP_dBm - noise_dBm - interfMargin_dB + fastFading_dB(t,:).' - interfVar_dB(t,:).';
                sinrHist(t,:) = sinr_dB(:).';
                pathlossHist(t,:) = pl_dB(:).';
                rxPowerHist(t,:) = rxP_dBm(:).';
                rsrpHist(t,:) = localRxPowerToRSRP(rxP_dBm(:), nRB).';
                ebnoHist(t,:) = localSINRtoEbNo(sinr_dB(:)).';
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
                sinrUL_dB = sinr_dB + ulSinrOffset_dB;
                sinrHistUL(t,:) = sinrUL_dB(:).';

                [beamEventTrace, beamEventCount] = localAppendBeamEvents( ...
                    beamEventTrace, beamEventCount, t, tti_s, servingIdx, ...
                    servingBeamNow, servingBeamGainNow_dB, ...
                    prevServingBeamCell, prevServingBeamIdx, prevServingBeamGain_dB);
                prevServingBeamCell = servingIdx;
                prevServingBeamIdx = servingBeamNow;
                prevServingBeamGain_dB = servingBeamGainNow_dB;

                intrfIdx = (t-1) * K + (1:K);
                interferenceTrace.TTI(intrfIdx) = t;
                interferenceTrace.Time_s(intrfIdx) = (t - 1) * tti_s;
                interferenceTrace.UE(intrfIdx) = (1:K).';
                interferenceTrace.ServingCell(intrfIdx) = servingIdx(:);
                interferenceTrace.Pathloss_dB(intrfIdx) = pl_dB(:);
                interferenceTrace.RxPower_dBm(intrfIdx) = rxP_dBm(:);
                interferenceTrace.Noise_dBm(intrfIdx) = noise_dBm;
                interferenceTrace.InterferenceMargin_dB(intrfIdx) = interfMargin_dB;
                interferenceTrace.SmallScaleFading_dB(intrfIdx) = fastFading_dB(t,:).';
                interferenceTrace.InterferenceVariation_dB(intrfIdx) = interfVar_dB(t,:).';
                interferenceTrace.SINR_DL_dB(intrfIdx) = sinr_dB(:);
                interferenceTrace.SINR_UL_dB(intrfIdx) = sinrUL_dB(:);
                interferenceTrace.RSRP_dBm(intrfIdx) = rsrpHist(t,:).';

                queueBitsDL = queueBitsDL + traffic.OfferedBitsDL(t,:).';
                queueBitsUL = queueBitsUL + traffic.OfferedBitsUL(t,:).';
                queueBitsDL_Start = queueBitsDL;
                queueBitsUL_Start = queueBitsUL;
                offeredCellDL = accumarray(servingIdx, traffic.OfferedBitsDL(t,:).', [nCells, 1], @sum, 0);
                offeredCellUL = accumarray(servingIdx, traffic.OfferedBitsUL(t,:).', [nCells, 1], @sum, 0);
                cqiDLVec = localSINRtoCQI(sinr_dB);
                cqiULVec = localSINRtoCQI(sinrUL_dB);

                activeDL = find(queueBitsDL > 0 & ~interruptedMask);
                activeUL = find(queueBitsUL > 0 & ~interruptedMask);
                if ~slotDL
                    activeDL = zeros(0,1);
                end
                if ~slotUL
                    activeUL = zeros(0,1);
                end
                activeMask = false(K,1);
                activeMask(activeDL) = true;
                activeMask(activeUL) = true;
                activeUECount(t) = sum(activeMask);
                ueByCellDL = localSplitUEByServingCell(activeDL, servingIdx, nCells);
                ueByCellUL = localSplitUEByServingCell(activeUL, servingIdx, nCells);
                activeCellDL = cellfun("length", ueByCellDL);
                activeCellUL = cellfun("length", ueByCellUL);

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

                if slotDL
                    dlBudget = localSlotBudget(nRB, slotLabel, "DL");
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
                        ueStateDL = ueStateDLAll(ueCell);
                        try
                            [gCell, ~] = schedDLCells{cellId}.schedule(t-1, ueStateDL, dlBudget);
                        catch MEs
                            gCell = struct([]);
                            out.Errors(end+1,1) = "DL scheduling failed at slot " + string(t) + ...
                                " cell " + string(cellId) + ": " + string(MEs.message);
                        end
                        if ~isempty(gCell)
                            nGrantSetsDL = nGrantSetsDL + 1;
                            grantSetsDL{nGrantSetsDL} = gCell(:);
                            grantCellsDL{nGrantSetsDL} = repmat(cellId, numel(gCell), 1);
                        end
                    end
                    if nGrantSetsDL > 0
                        grantsDL = vertcat(grantSetsDL{1:nGrantSetsDL});
                        grantCellDL = vertcat(grantCellsDL{1:nGrantSetsDL});
                    end
                end

                if slotUL
                    ulBudget = localSlotBudget(nRB, slotLabel, "UL");
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
                        ueStateUL = ueStateULAll(ueCell);
                        try
                            [gCell, ~] = schedULCells{cellId}.schedule(t-1, ueStateUL, ulBudget);
                        catch MEs
                            gCell = struct([]);
                            out.Errors(end+1,1) = "UL scheduling failed at slot " + string(t) + ...
                                " cell " + string(cellId) + ": " + string(MEs.message);
                        end
                        if ~isempty(gCell)
                            nGrantSetsUL = nGrantSetsUL + 1;
                            grantSetsUL{nGrantSetsUL} = gCell(:);
                            grantCellsUL{nGrantSetsUL} = repmat(cellId, numel(gCell), 1);
                        end
                    end
                    if nGrantSetsUL > 0
                        grantsUL = vertcat(grantSetsUL{1:nGrantSetsUL});
                        grantCellUL = vertcat(grantCellsUL{1:nGrantSetsUL});
                    end
                end

                if ~isempty(grantCellDL)
                    grantCountDLByCell = accumarray(grantCellDL, 1, [nCells, 1], @sum, 0);
                    fbDLCount = accumarray(grantCellDL, 1, [nCells, 1]);
                    for c = 1:nCells
                        if fbDLCount(c) > 0
                            fbDLByCell{c} = repmat(struct("RNTI", 0, "TBSBits", 0, "Ack", false), fbDLCount(c), 1);
                        end
                    end
                end
                if ~isempty(grantCellUL)
                    grantCountULByCell = accumarray(grantCellUL, 1, [nCells, 1], @sum, 0);
                    fbULCount = accumarray(grantCellUL, 1, [nCells, 1]);
                    for c = 1:nCells
                        if fbULCount(c) > 0
                            fbULByCell{c} = repmat(struct("RNTI", 0, "TBSBits", 0, "Ack", false), fbULCount(c), 1);
                        end
                    end
                end

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
                    if isfield(g, "MCSIndex")
                        mcsIdx = double(g.MCSIndex);
                    else
                        mcsIdx = double(localCQIToMCS(cqiUsed));
                    end
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
                        "Grant", g, ...
                        "TBSBits", tbsBits);
                    [okDL, blerDL] = phy.decode(ctxDL);
                    if isnan(blerHistDL(t,u))
                        blerHistDL(t,u) = blerDL;
                    else
                        blerHistDL(t,u) = 0.5 * (blerHistDL(t,u) + blerDL);
                    end
                    if okDL
                        servedDL = min(queueBitsDL(u), tbsBits);
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
                        cellId, g, prbCount, tbsBits, cqiUsed, mcsIdx, numLayers, ...
                        tgtCodeRate, sinr_dB(u), blerDL, logical(okDL));
                    fb = struct("RNTI", u, "TBSBits", tbsBits, "Ack", logical(okDL));
                    fbIdx = fbDLWriteIdx(cellId) + 1;
                    if ~isempty(fbDLByCell{cellId}) && fbIdx <= numel(fbDLByCell{cellId})
                        fbDLByCell{cellId}(fbIdx) = fb;
                        fbDLWriteIdx(cellId) = fbIdx;
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
                    if isfield(g, "MCSIndex")
                        mcsIdx = double(g.MCSIndex);
                    else
                        mcsIdx = double(localCQIToMCS(cqiUsed));
                    end
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
                        "Grant", g, ...
                        "TBSBits", tbsBits);
                    [okUL, blerUL] = phy.decode(ctxUL);
                    if isnan(blerHistUL(t,u))
                        blerHistUL(t,u) = blerUL;
                    else
                        blerHistUL(t,u) = 0.5 * (blerHistUL(t,u) + blerUL);
                    end
                    if okUL
                        servedUL = min(queueBitsUL(u), tbsBits);
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
                        cellId, g, prbCount, tbsBits, cqiUsed, mcsIdx, numLayers, ...
                        tgtCodeRate, sinrUL_dB(u), blerUL, logical(okUL));
                    fb = struct("RNTI", u, "TBSBits", tbsBits, "Ack", logical(okUL));
                    fbIdx = fbULWriteIdx(cellId) + 1;
                    if ~isempty(fbULByCell{cellId}) && fbIdx <= numel(fbULByCell{cellId})
                        fbULByCell{cellId}(fbIdx) = fb;
                        fbULWriteIdx(cellId) = fbIdx;
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
            end

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
                'VariableNames', {'Throughput_Mbps','ThroughputDL_Mbps','ThroughputUL_Mbps', ...
                                  'PacketLoss','PacketLossDL','PacketLossUL','AvgBLER','JainFairness', ...
                                  'MeanQueue_bits','MeanSINR_dB','MeanRSRP_dBm','MeanEbNo_dB', ...
                                  'P05SINR_dB','P50SINR_dB','P95SINR_dB', ...
                                  'SpectralEfficiency_bpsHz','SpectralEfficiencyDL_bpsHz','SpectralEfficiencyUL_bpsHz', ...
                                  'Utilization','AvgActiveUE','ScheduleUtilization', ...
                                  'ApproxDelay_ms','NumUE','NumCells','NumTTI','SimDuration_s', ...
                                  'HO_Triggered','HO_Started','HO_Completed','HO_InterruptedUE_Mean','HO_InterruptionMean_ms', ...
                                  'ExecutionBackend','PHYMode','WaveformBacked'});
            out.KPITable = kpi;

            out.Details = struct();
            out.Details.ExecutionBackend = string(phyBackendLabel);
            out.Details.PHYMode = string(phyModeLabel);
            out.Details.WaveformBacked = logical(waveformBacked);
            if waveformBacked && isprop(phy, "LastReplay")
                out.Details.LastPHYReplay = phy.LastReplay;
            end
            out.Details.ScheduledUE_DL = scheduledUE_DL;
            out.Details.ScheduledUE_UL = scheduledUE_UL;
            out.Details.ScheduledUE = max(scheduledUE_DL, scheduledUE_UL);
            out.Details.GrantCountDL = grantCountDL;
            out.Details.GrantCountUL = grantCountUL;
            out.Details.GrantCount = grantCountDL + grantCountUL;
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
            out.Details.FlowDirection = sixgr.util.structGet(traffic, "FlowDirection", "BIDIR");
            out.Details.PacketDelayBudget_ms = sixgr.util.structGet(traffic, "PacketDelayBudget_ms", NaN);
            out.Details.FlowTable = sixgr.util.structGet(traffic, "FlowTable", table());
            out.Details.TTI_s = tti_s;
            out.Details.Noise_dBm = noise_dBm;
            out.Details.InterferenceMargin_dB = interfMargin_dB;
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
            out.Details.MeasurementReportCount = measReportCount;
            out.Details.BeamUpdateCount = beamUpdateCount;
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
                phyBackendLabel, phyModeLabel, waveformBacked);

            out.Details.UESummary = ueSummary;
            out.Details.TimeSeries = timeSeries;
            out.Details.AlgoProcessing = algoProc;

            doCSV = logical(sixgr.util.structGet(cfg, "outputs.saveCSV", true));
            doMAT = logical(sixgr.util.structGet(cfg, "outputs.saveMAT", true));
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

            runtimeSummary = localBuildRuntimeSummary(startedUTC, runTimer, ctx.RunFolder, out.Errors);
            environmentSummary = localBuildEnvironmentSummary(ctx);
            out.RuntimeSummary = runtimeSummary;
            out.EnvironmentSummary = environmentSummary;

            try
                out.OutputCatalog = sixgr.report.exportSLSOutputCatalog( ...
                    ctx.RunFolder, cfg, out, runtimeSummary, environmentSummary);
            catch MEcat
                out.Errors(end+1,1) = "SLS output catalog export failed: " + string(MEcat.message);
            end

            log.info("SystemLevelRunner completed: throughput=" + string(round(throughput_Mbps,3)) + " Mbps");
        end
    end
end

function tti_s = localSlotDuration(cfg, params)
tti_s = double(sixgr.util.structGet(params, "TTI_s", ...
               sixgr.util.structGet(cfg, "system.tti_s", [])));
if ~isempty(tti_s)
    tti_s = max(tti_s, 1e-4);
    return;
end
scs = double(sixgr.util.structGet(cfg, "phy.carrier.SubcarrierSpacing", 30));
mu = log2(scs/15);
if ~isfinite(mu) || mu < 0
    mu = 0;
end
tti_s = 1e-3 / (2^mu);
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

function nRB = localEstimateNRB(cfg, bw_Hz)
cfgGrid = double(sixgr.util.structGet(cfg, "phy.carrier.NSizeGrid", NaN));
if isfinite(cfgGrid) && cfgGrid >= 1
    nRB = round(cfgGrid);
    return;
end

scs_kHz = double(sixgr.util.structGet(cfg, "phy.carrier.SubcarrierSpacing", ...
                 sixgr.util.structGet(cfg, "channel.subcarrierSpacing_kHz", 30)));
scs_Hz = max(scs_kHz * 1e3, 1);
nRB = floor(double(bw_Hz) / (12 * scs_Hz));
nRB = min(275, max(1, nRB));
end

function rsrp_dBm = localRxPowerToRSRP(rxPower_dBm, nRB)
rsrp_dBm = double(rxPower_dBm) - 10*log10(max(12*nRB, 1));
end

function ebno_dB = localSINRtoEbNo(sinr_dB)
se = log2(1 + 10.^(double(sinr_dB)/10));
ebno_dB = double(sinr_dB) - 10*log10(max(se, 1e-9));
end

function [allowDL, allowUL, slotLabel] = localSlotDuplexState(cfg, t)
duplex = upper(string(sixgr.util.structGet(cfg, "phy.duplex.mode", ...
    sixgr.util.structGet(cfg, "scenario.duplexMode", "TDD"))));
if duplex == "FDD"
    allowDL = true;
    allowUL = true;
    slotLabel = "FDD_DLUL";
    return;
end

pattern = sixgr.util.structGet(cfg, "phy.duplex.tddPattern", ...
    sixgr.util.structGet(cfg, "scenario.tddPattern", "DDDSU"));
tokens = localExpandTDDPattern(pattern);
if isempty(tokens)
    tokens = 'DDDSU';
end
i = mod(max(0, round(t) - 1), numel(tokens)) + 1;
sw = upper(tokens(i));
switch sw
    case 'D'
        allowDL = true;
        allowUL = false;
        slotLabel = "DL";
    case 'U'
        allowDL = false;
        allowUL = true;
        slotLabel = "UL";
    otherwise
        % special slot: keep both enabled with reduced guard handled by scheduler budgets.
        allowDL = true;
        allowUL = true;
        slotLabel = "S";
end
end

function sched = localCreateScheduler(cfg, schedulerName, direction, log)
if nargin < 4
    log = [];
end
dir = upper(char(string(direction)));
sch = lower(char(string(schedulerName)));
try
    if contains(sch, "pf")
        sched = sixgr.l2.mac.SchedulerPF(cfg, "Direction", dir, "Logger", log);
    else
        sched = sixgr.l2.mac.SchedulerRR(cfg, "Direction", dir, "Logger", log);
    end
catch
    % Last-resort fallback keeps SLS runnable if a scheduler ctor changes.
    sched = sixgr.l2.mac.SchedulerRR(cfg, "Direction", dir);
end
end

function budget = localSlotBudget(nRB, slotLabel, direction)
slotTag = upper(char(string(slotLabel)));
dir = upper(char(string(direction)));
nPRB = max(1, round(double(nRB)));
symAlloc = [0 14];
if strcmp(slotTag, "S")
    nPRB = max(1, floor(nPRB * 0.5));
    if strcmp(dir, "DL")
        symAlloc = [0 7];
    else
        symAlloc = [7 7];
    end
end
budget = struct("NPRB", nPRB, "SymbolAllocation", symAlloc);
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

function cqi = localSINRtoCQI(sinr_dB)
s = double(sinr_dB);
cqi = max(1, min(15, round((s + 6.0) / 1.8)));
end

function mcs = localCQIToMCS(cqi)
mcs = max(0, min(27, round((double(cqi) - 1) * (27/14))));
end

function tokens = localExpandTDDPattern(pattern)
if isstruct(pattern)
    dl = max(0, round(double(sixgr.util.structGet(pattern, "dlSlots", 4))));
    ul = max(0, round(double(sixgr.util.structGet(pattern, "ulSlots", 1))));
    sp = max(0, round(double(sixgr.util.structGet(pattern, "specialSlots", 0))));
    tokens = [repmat('D', 1, dl), repmat('S', 1, sp), repmat('U', 1, ul)];
    return;
end

if isstring(pattern) || ischar(pattern)
    s = upper(char(string(pattern)));
    s = regexprep(s, "[^DUS]", "");
    if isempty(s)
        s = 'DDDSU';
    end
    tokens = s;
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

function [beamIdx, beamGain_dB] = localSelectBestBeamPerLink(uePos, bsPos, bsAzim_deg, nBeams, spanDeg, maxGain_dB)
K = size(uePos, 1);
B = size(bsPos, 1);
beamIdx = ones(K, B);
beamGain_dB = zeros(K, B);

nBeams = max(1, round(double(nBeams)));
spanDeg = max(30, min(240, double(spanDeg)));
maxGain_dB = double(maxGain_dB);

beamOffsets = linspace(-0.5*spanDeg, 0.5*spanDeg, nBeams);
beamBW = max(spanDeg / max(nBeams, 1), 5);
for b = 1:B
    dx = uePos(:,1) - bsPos(b,1);
    dy = uePos(:,2) - bsPos(b,2);
    linkAz = atan2d(dy, dx);
    beamCenters = double(bsAzim_deg(b)) + beamOffsets;
    delta = abs(localWrapTo180(linkAz - reshape(beamCenters, 1, [])));
    atten_dB = min(30, 12 .* (delta ./ beamBW).^2);
    [bestAtten, idx] = min(atten_dB, [], 2);
    beamIdx(:,b) = idx;
    beamGain_dB(:,b) = maxGain_dB - bestAtten;
end
end

function rsrpCell_dBm = localEstimateCellRSRP(txPower_dBm, d2d, fc_GHz, beamGain_dB)
K = size(d2d, 1);
B = size(d2d, 2);
tx = reshape(double(txPower_dBm), 1, []);
if numel(tx) ~= B
    tx = repmat(tx(1), 1, B);
end
d_km = max(double(d2d) / 1000, 1e-4);
pl_dB = 32.4 + 20*log10(max(fc_GHz, 0.1)) + 31.9*log10(d_km);
if isempty(beamGain_dB)
    beamGain_dB = zeros(K, B);
end
rsrpCell_dBm = repmat(tx, K, 1) - pl_dB + double(beamGain_dB);
end

function v = localGatherServingValues(M, servingIdx)
K = size(M, 1);
B = size(M, 2);
s = min(max(round(double(servingIdx(:))), 1), B);
lin = sub2ind([K B], (1:K).', s);
v = M(lin);
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
trace.SINR_dB = NaN(cap,1);
trace.BLER = NaN(cap,1);
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
    cellId, grant, prbCount, tbsBits, cqiUsed, mcsIdx, numLayers, targetCodeRate, sinr_dB, bler, ack)

[trace, count] = localEnsureGrantTraceCapacity(trace, count, 1);
count = count + 1;
i = count;

prbSet = sixgr.util.structGet(grant, "PRBSet", []);
if isempty(prbSet)
    prbStart = NaN;
else
    prbSet = double(prbSet(:));
    prbStart = min(prbSet);
end

symAlloc = double(sixgr.util.structGet(grant, "SymbolAllocation", [0 14]));
symAlloc = symAlloc(:).';
if numel(symAlloc) < 2
    symAlloc = [0 14];
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
trace.SINR_dB(i) = double(sinr_dB);
trace.BLER(i) = double(bler);
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
end

function T = localGrantTraceToTable(trace, count)
if count <= 0
    T = table([], [], string.empty(0,1), string.empty(0,1), [], [], [], [], [], [], [], [], [], [], [], [], [], ...
        false(0,1), [], [], [], false(0,1), [], [], [], [], [], [], [], [], [], string.empty(0,1), ...
        'VariableNames', {'TTI','Time_s','Direction','SlotDirection','CellID','UE','PRBStart','PRBCount', ...
        'SymbolStart','NumSymbols','TBSBits','CQIUsed','MCSIndex','NumLayers','TargetCodeRate', ...
        'SINR_dB','BLER','Ack','HarqID','RV','NDI','IsRetransmission','DAI','K1','K2', ...
        'SearchSpaceID','CORESETID','BWPId','HeadOfLineDelay_ms','BufferBytesBefore','BufferBytesAfter','GrantReason'});
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
    'VariableNames', {'TTI','Time_s','Direction','SlotDirection','CellID','UE','PRBStart','PRBCount', ...
    'SymbolStart','NumSymbols','TBSBits','CQIUsed','MCSIndex','NumLayers','TargetCodeRate', ...
    'SINR_dB','BLER','Ack','HarqID','RV','NDI','IsRetransmission','DAI','K1','K2', ...
    'SearchSpaceID','CORESETID','BWPId','HeadOfLineDelay_ms','BufferBytesBefore','BufferBytesAfter','GrantReason'});
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
trace.SINR_DL_dB = NaN(nRows,1);
trace.SINR_UL_dB = NaN(nRows,1);
trace.RSRP_dBm = NaN(nRows,1);
end

function T = localInterferenceTraceToTable(trace)
T = table(double(trace.TTI), double(trace.Time_s), double(trace.UE), double(trace.ServingCell), ...
    double(trace.Pathloss_dB), double(trace.RxPower_dBm), double(trace.Noise_dBm), ...
    double(trace.InterferenceMargin_dB), double(trace.SmallScaleFading_dB), ...
    double(trace.InterferenceVariation_dB), double(trace.SINR_DL_dB), ...
    double(trace.SINR_UL_dB), double(trace.RSRP_dBm), ...
    'VariableNames', {'TTI','Time_s','UE','ServingCell','Pathloss_dB','RxPower_dBm', ...
    'Noise_dBm','InterferenceMargin_dB','SmallScaleFading_dB','InterferenceVariation_dB', ...
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

function y = localWrapTo180(x)
y = mod(double(x) + 180, 360) - 180;
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

function [backendLabel, phyModeLabel, waveformBacked] = localDescribeSystemPHY(phy)
backendLabel = "ABSTRACT_SYSTEM_PHY";
phyModeLabel = "SINR_TO_BLER_ABSTRACTION";
waveformBacked = false;
if isa(phy, "sixgr.system.WaveformPHY")
    waveformBacked = true;
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

function algoProc = localBuildAlgoTable( ...
    cfg, trafficModel, trafficClass, nTTI, tti_s, K, decodeOkCount, decodeFailCount, overflowEvents, avgActiveUE, ...
    hoTriggerTotal, hoCompleteTotal, hoInterruptedUEmean, phyBackendLabel, phyModeLabel, waveformBacked)

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
        "PHYBackend";"PHYMode";"WaveformBacked"];
value = [string(nTTI);string(tti_s);string(K);scheduler;pathlossModel;string(trafficModel); ...
         string(uClass);duplexMode;wfDL;wfUL;string(decodeOkCount);string(decodeFailCount); ...
         string(overflowEvents);string(avgActiveUE); ...
         string(hoTriggerTotal);string(hoCompleteTotal);string(hoInterruptedUEmean); ...
         string(phyBackendLabel);string(phyModeLabel);string(logical(waveformBacked))];
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
cdfplot(sinrHist(~isnan(sinrHist))); grid on;
xlabel("SINR (dB)"); ylabel("CDF"); title("SINR CDF");
fp = fullfile(figDir, "system_sinr_cdf.png");
exportgraphics(f, fp, "Resolution", figRes); close(f);
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
exportgraphics(f, fp, "Resolution", figRes); close(f);
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
exportgraphics(f, fp, "Resolution", figRes); close(f);
files{end+1} = fp;

% Throughput and offered load vs time
f = figure("Color","w");
plot(t, timeSeries.Offered_Mbps, "LineWidth", 1.0); hold on;
plot(t, timeSeries.Throughput_Mbps, "LineWidth", 1.3);
grid on; xlabel("Time (s)"); ylabel("Mbps");
title("Offered Load vs Throughput");
legend({"Offered","Served"}, "Location", "best");
fp = fullfile(figDir, "system_throughput_vs_time.png");
exportgraphics(f, fp, "Resolution", figRes); close(f);
files{end+1} = fp;

% Queue evolution
f = figure("Color","w");
plot(t, timeSeries.MeanQueue_bits, "LineWidth", 1.2); hold on;
plot(t, timeSeries.P95Queue_bits, "LineWidth", 1.0);
grid on; xlabel("Time (s)"); ylabel("Queue (bits)");
title("Queue Evolution");
legend({"Mean queue","P95 queue"}, "Location", "best");
fp = fullfile(figDir, "system_queue_vs_time.png");
exportgraphics(f, fp, "Resolution", figRes); close(f);
files{end+1} = fp;

% UE throughput by traffic class
f = figure("Color","w");
cats = categorical(ueSummary.TrafficClass);
boxchart(cats, ueSummary.Throughput_Mbps); grid on;
xlabel("Traffic class"); ylabel("UE throughput (Mbps)");
title("UE Throughput by Traffic Class");
fp = fullfile(figDir, "system_ue_throughput_by_traffic_class.png");
exportgraphics(f, fp, "Resolution", figRes); close(f);
files{end+1} = fp;

% Cell-edge vs center SINR
f = figure("Color","w");
hold on;
zc = ueSummary.Zone == "center";
ze = ueSummary.Zone == "edge";
leg = strings(0,1);
if any(zc)
    cdfplot(ueSummary.MeanSINR_dB(zc));
    leg(end+1,1) = "Center"; %#ok<AGROW>
end
if any(ze)
    cdfplot(ueSummary.MeanSINR_dB(ze));
    leg(end+1,1) = "Edge"; %#ok<AGROW>
end
grid on; xlabel("Mean SINR (dB)"); ylabel("CDF");
title("Center vs Edge UE Mean SINR");
if ~isempty(leg)
    legend(cellstr(leg), "Location", "best");
end
fp = fullfile(figDir, "system_center_edge_sinr_cdf.png");
exportgraphics(f, fp, "Resolution", figRes); close(f);
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
    exportgraphics(f, fp, "Resolution", figRes); close(f);
    files{end+1} = fp;
end
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
