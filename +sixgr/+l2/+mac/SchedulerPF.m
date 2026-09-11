classdef SchedulerPF < sixgr.l2.mac.SchedulerBase
% sixgr.l2.mac.SchedulerPF
% Proportional Fair (PF) scheduler.
%
% PF metric (baseline): (instantaneous throughput) / (average throughput)
% where average throughput is an EWMA maintained per UE.
%
% Practical notes
%  - HARQ retransmissions are served first (very common in gNB schedulers).
%  - New data is then scheduled by PF metric under a simple PRB chunking.
%  - This is intentionally "simple but correct" and is a good basis for
%    adding QoS (5QI), LCP, SR/BSR priorities, etc.

    properties
        MaxUEPerSlot (1,1) double = inf
        MinPRBPerUE (1,1) double = 4
        MaxPRBPerUE (1,1) double = inf
    end

    methods
        function obj = SchedulerPF(cfg, varargin)
            obj@sixgr.l2.mac.SchedulerBase(cfg, varargin{:});
            dirToken = upper(char(string(obj.Direction)));
            if strcmp(dirToken, 'UL')
                dirSpecificMaxUE = sixgr.util.structGet(cfg, "mac.scheduler.maxUEPerSlotUL", ...
                    sixgr.util.structGet(cfg, "system.scheduler.maxActiveUEsPerCellPerSlotUL", []));
            else
                dirSpecificMaxUE = sixgr.util.structGet(cfg, "mac.scheduler.maxUEPerSlotDL", ...
                    sixgr.util.structGet(cfg, "system.scheduler.maxActiveUEsPerCellPerSlotDL", []));
            end
            if isempty(dirSpecificMaxUE)
                dirSpecificMaxUE = sixgr.util.structGet(cfg,"mac.scheduler.maxUEPerSlot", ...
                    sixgr.util.structGet(cfg,"system.scheduler.maxActiveUEsPerSlot",obj.MaxUEPerSlot));
            end
            obj.MaxUEPerSlot = double(dirSpecificMaxUE);
            obj.MinPRBPerUE = double(sixgr.util.structGet(cfg,"mac.scheduler.minPRBPerUE",obj.MinPRBPerUE));
            obj.MaxPRBPerUE = double(sixgr.util.structGet(cfg,"mac.scheduler.maxPRBAllocationPerUE", ...
                sixgr.util.structGet(cfg,"system.scheduler.maxPRBAllocationPerUE",obj.MaxPRBPerUE)));
        end

        function [grants, info] = schedule(obj, slot, ueStates, budget)
            if nargin < 4
                budget = struct();
            end
            scheduleTimer = tic;
            [prbAvail, symAlloc] = obj.defaultBudget(budget);
            controlAbsoluteSlot = localBudgetControlAbsoluteSlot(budget);
            controlSymbolAllocation = ...
                localBudgetControlSymbolAllocation(budget);
            profScope = sixgr.perf.TimeProfiler.scope("sixgr.l2.mac.SchedulerPF.schedule", ...
                "Stage", "mac_pf_scheduler", ...
                "Metadata", struct("NumUE", double(numel(ueStates)), ...
                "NumPRB", double(numel(prbAvail)))); %#ok<NASGU>

            tmpl = localGrantTemplate(obj.Direction, slot);
            grants = repmat(tmpl, 0, 1);
            info = struct();
            info.Slot = slot;
            info.Direction = obj.Direction;
            info.SchedulerClass = string(class(obj));
            info.HARQDeferrals = table();
            info.ResourceExclusions = table();
            candidateRows = repmat(localCandidateRow(), 0, 1);
            info.CandidateTable = localCandidateTable(candidateRows);
            info.DecisionTable = info.CandidateTable;
            ssid = max(0, round(double(sixgr.util.structGet(obj.Cfg, ...
                "phy.pdcch.searchSpace.id", ...
                sixgr.util.structGet(obj.Cfg, "phy.dl.pdcch.SearchSpaceID", 1)))));
            coreset = max(0, round(double(sixgr.util.structGet(obj.Cfg, ...
                "phy.pdcch.coreset.id", ...
                sixgr.util.structGet(obj.Cfg, "phy.dl.pdcch.CORESETID", 0)))));

            if isempty(ueStates) || isempty(prbAvail)
                return;
            end

            % Active UEs based on buffers
            act = false(1, numel(ueStates));
            bufBytes = zeros(1, numel(ueStates));
            for k = 1:numel(ueStates)
                if ~isfield(ueStates(k),'RNTI') || isempty(ueStates(k).RNTI)
                    continue;
                end
                if strcmpi(obj.Direction,'DL')
                    if isfield(ueStates(k),'DLBufferBytes')
                        bufBytes(k) = double(ueStates(k).DLBufferBytes);
                    end
                else
                    if isfield(ueStates(k),'ULBufferBytes')
                        bufBytes(k) = double(ueStates(k).ULBufferBytes);
                    end
                end
                act(k) = bufBytes(k) > 0;
            end
            ueIdx = find(act);
            if isempty(ueIdx)
                return;
            end

            % Cap scheduled UEs per slot
            maxUE = obj.MaxUEPerSlot;
            if ~isfinite(maxUE) || maxUE <= 0
                maxUE = numel(ueIdx);
            end
            if isfield(budget, 'MaxUEPerSlot') && ~isempty(budget.MaxUEPerSlot)
                budgetMaxUE = double(budget.MaxUEPerSlot);
                if isfinite(budgetMaxUE) && budgetMaxUE > 0
                    maxUE = min(maxUE, floor(budgetMaxUE));
                end
            end
            maxUE = min(maxUE, numel(ueIdx));
            for t = 1:numel(ueIdx)
                obj.prewarmUEAverage(ueStates(ueIdx(t)), maxUE);
            end
            [controlBudgetActive, controlCCERemaining] = localPDCCHCCEBudget(budget);
            muEnabled = localMUMIMOEnabled(obj.Cfg, obj.Direction);
            muMaxUsers = localMUMIMOMaxUsers(obj.Cfg);
            scheduledRetxUECount = 0;

            % ------------------ 1) HARQ retransmissions first ------------------
            if ~isempty(obj.HARQ)
                retxProcessed = false(1, numel(ueIdx));
                for t = 1:numel(ueIdx)
                    if retxProcessed(t) || scheduledRetxUECount >= maxUE
                        continue;
                    end
                    k = ueIdx(t);
                    rnti = double(ueStates(k).RNTI);
                    if obj.HARQ.hasPendingRetx(rnti, slot)
                        retx = obj.HARQ.peekRetx(rnti, slot);
                        if isempty(retx)
                            continue;
                        end
                        g = localNormalizeGrant(retx.LastGrant, tmpl, obj.Direction, slot);
                        [fitsBudget, deferral] = sixgr.l2.mac.harqRetransmissionFitsSymbolBudget(g, symAlloc);
                        if ~fitsBudget
                            info.HARQDeferrals = [info.HARQDeferrals; deferral];
                            continue;
                        end
                        if isempty(prbAvail)
                            break;
                        end
                        nNeed = numel(g.PRBSet);
                        if nNeed <= 0
                            nNeed = max(1, round(double(sixgr.util.structGet(g, "NPRB", ...
                                sixgr.util.structGet(g, "PRBCount", sixgr.util.structGet(g, "NumPRB", NaN))))));
                        end
                        % Retx must preserve enough PRBs to carry the stored TB honestly.
                        if nNeed <= 0 || numel(prbAvail) < nNeed
                            continue;
                        end
                        retxIntent=g; retxIntent.HARQ=retx.HARQ;
                        [retxAvailable,excluded]=obj.ssbSafePRBSet(slot,budget, ...
                            prbAvail,g.SymbolAllocation,retxIntent);
                        info.ResourceExclusions=[info.ResourceExclusions;excluded];
                        [retxPRBs,~]=sixgr.l2.mac.contiguousPRBChunk(retxAvailable,1,nNeed,nNeed);
                        if isempty(retxPRBs)
                            info.HARQDeferrals=[info.HARQDeferrals; ...
                                sixgr.l2.mac.harqPRBDeferral(g,retxAvailable,symAlloc)];
                            continue;
                        end
                        neededCCE = localUEPDCCHCCE(ueStates(k), budget);
                        if controlBudgetActive && neededCCE > controlCCERemaining
                            continue;
                        end

                        peerT = NaN;
                        peerRetx = struct();
                        muSpatialDesign = struct();
                        if muEnabled && muMaxUsers >= 2 && ...
                                scheduledRetxUECount + 2 <= maxUE
                            for tt = (t + 1):numel(ueIdx)
                                if retxProcessed(tt)
                                    continue;
                                end
                                peerK = ueIdx(tt);
                                peerRNTI = double(ueStates(peerK).RNTI);
                                if ~obj.HARQ.hasPendingRetx(peerRNTI, slot)
                                    continue;
                                end
                                candidatePeerRetx = obj.HARQ.peekRetx(peerRNTI, slot);
                                if isempty(candidatePeerRetx)
                                    continue;
                                end
                                peerGrant = localNormalizeGrant(candidatePeerRetx.LastGrant, ...
                                    tmpl, obj.Direction, slot);
                                peerNeed = numel(peerGrant.PRBSet);
                                if peerNeed <= 0
                                    peerNeed = max(1, round(double(sixgr.util.structGet(peerGrant, ...
                                        "NPRB", sixgr.util.structGet(peerGrant, "PRBCount", ...
                                        sixgr.util.structGet(peerGrant, "NumPRB", NaN))))));
                                end
                                peerCCE = localUEPDCCHCCE(ueStates(peerK), budget);
                                sameAllocationShape = peerNeed == nNeed && ...
                                    isequal(double(peerGrant.SymbolAllocation(:).'), ...
                                    double(g.SymbolAllocation(:).'));
                                enoughCCE = ~controlBudgetActive || ...
                                    neededCCE + peerCCE <= controlCCERemaining;
                                [pairOK, ~, ~, candidateDesign] = localMUMIMOCompatible( ...
                                    ueStates(k), ueStates(peerK), obj.Cfg, obj.Direction, slot);
                                if sameAllocationShape && enoughCCE && pairOK
                                    peerT = tt;
                                    peerRetx = candidatePeerRetx;
                                    muSpatialDesign = candidateDesign;
                                    break;
                                end
                            end
                        end

                        if isfinite(peerT)
                            if all(ismember(g.PRBSet, retxAvailable)) && all(diff(g.PRBSet)==1)
                                sharedPRBSet = double(g.PRBSet(:).');
                            else
                                sharedPRBSet = retxPRBs;
                            end
                            memberT = [t peerT];
                            memberRetx = {retx, peerRetx};
                            groupId = double(localMUMIMOGroupId(slot, min(sharedPRBSet) + 1));
                            for memberIndex = 1:2
                                stateIndex = ueIdx(memberT(memberIndex));
                                memberRNTI = double(ueStates(stateIndex).RNTI);
                                memberCCE = localUEPDCCHCCE(ueStates(stateIndex), budget);
                                memberGrant = localNormalizeGrant( ...
                                    memberRetx{memberIndex}.LastGrant, tmpl, obj.Direction, slot);
                                memberGrant.PRBSet = sharedPRBSet;
                                memberGrant = localPrepareRetransmissionGrant(memberGrant, ...
                                    memberRetx{memberIndex}, ueStates(stateIndex), obj.Direction, ...
                                    slot, controlAbsoluteSlot, controlSymbolAllocation, ssid, ...
                                    coreset, memberCCE, bufBytes(stateIndex), obj.resolveMCSTable());
                                memberGrant.GrantReason = "harq_retx_mu_mimo";
                                memberGrant.MUMIMOEnabled = true;
                                memberGrant.MUMIMOGroupSize = 2;
                                memberGrant.MUMIMOGroupId = groupId;
                                memberGrant.MUMIMOPairingStatus = ...
                                    "paired_shared_prb_spatial_multiplexing";
                                memberGrant.DMRSPortSet = localMUMIMODMRSPortSet( ...
                                    obj.Cfg, obj.Direction, memberGrant.NumLayers, memberIndex, 2);
                                memberGrant = localApplyMUMIMOSpatialDesign( ...
                                    memberGrant, muSpatialDesign, memberIndex, obj.Direction);
                                memberGrant = obj.attachULSRSAuthorityToGrant( ...
                                    memberGrant, ueStates(stateIndex));
                                memberGrant = sixgr.l2.mac.attachReceivedULTimingAuthority(memberGrant,ueStates(stateIndex));
                                [memberGrant.DMRSPortSet, memberGrant.DMRSPortSetSource] = ...
                                    sixgr.phy.grant.resolveScheduledDMRSPortSet( ...
                                    obj.Cfg, obj.Direction, memberGrant.NumLayers, memberGrant);
                                memberGrant = obj.freezePHYGrantForGrant(memberGrant);
                                memberGrant.DCI = obj.buildDCIBitfield(memberGrant);
                                grants = localAppendGrant(grants, memberGrant);
                                if controlBudgetActive
                                    controlCCERemaining = max(0, controlCCERemaining - memberCCE);
                                end
                            end
                            prbAvail = setdiff(prbAvail, sharedPRBSet, 'stable');
                            retxProcessed(memberT) = true;
                            scheduledRetxUECount = scheduledRetxUECount + 2;
                            continue;
                        end

                        if ~all(ismember(g.PRBSet, retxAvailable)) || ~all(diff(g.PRBSet)==1)
                            g.PRBSet = retxPRBs;
                        end
                        prbAvail = setdiff(prbAvail, g.PRBSet, 'stable');
                        g = localPrepareRetransmissionGrant(g, retx, ueStates(k), ...
                            obj.Direction, slot, controlAbsoluteSlot, ...
                            controlSymbolAllocation, ssid, coreset, neededCCE, bufBytes(k), ...
                            obj.resolveMCSTable());
                        g.GrantReason = "harq_retx";
                        g = localMarkUnpairedRetransmission(g);
                        g = obj.attachULSRSAuthorityToGrant(g, ueStates(k));
                        g = sixgr.l2.mac.attachReceivedULTimingAuthority(g,ueStates(k));
                        g = obj.freezePHYGrantForGrant(g);
                        g.DCI = obj.buildDCIBitfield(g);
                        grants = localAppendGrant(grants, g);
                        if controlBudgetActive
                            controlCCERemaining = max(0, controlCCERemaining - neededCCE);
                        end
                        retxProcessed(t) = true;
                        scheduledRetxUECount = scheduledRetxUECount + 1;
                    end
                end
            end

            if isempty(prbAvail)
                info.NGrants = numel(grants);
                localDecayUnscheduledCandidates(obj, ueStates, ueIdx, grants);
                return;
            end

            % ------------------ 2) PF scheduling for new data ------------------
            [prbAvail,excluded]=obj.ssbSafePRBSet(slot,budget,prbAvail,symAlloc);
            info.ResourceExclusions=[info.ResourceExclusions;excluded];
            % Compute PF metric per UE using a hypothetical chunk size
            nPRBAvail = numel(prbAvail);
            nSym = double(symAlloc(2));

            % Choose a common reference budget for PF probing. The PF metric
            % must compare every UE on the same active-UE PRB chunk; MinPRB is
            % enforced only on the final grant allocation.
            probeChunk = max(1, floor(nPRBAvail / max(maxUE, 1)));
            prbChunk = max(obj.MinPRBPerUE, probeChunk);
            if isfinite(obj.MaxPRBPerUE) && obj.MaxPRBPerUE > 0
                prbChunk = min(prbChunk, floor(obj.MaxPRBPerUE));
                probeChunk = min(probeChunk, floor(obj.MaxPRBPerUE));
            end
            prbChunk = max(prbChunk, 1);
            probeChunk = max(probeChunk, 1);

            metrics = -inf(1, numel(ueIdx));
            estTBS = zeros(1, numel(ueIdx));
            candidateRowIdxByMetric = zeros(1, numel(ueIdx));
            probeTimer = tic;
            probePlanElapsed_s = zeros(1, numel(ueIdx));
            for t = 1:numel(ueIdx)
                k = ueIdx(t);
                rnti = double(ueStates(k).RNTI);
                avgRate = localUEAverageThroughput(obj, rnti);
                neededCCE = localUEPDCCHCCE(ueStates(k), budget);
                row = localCandidateRow();
                row.Slot = double(slot);
                row.Direction = string(obj.Direction);
                row.DecisionId = string(sprintf('%s_slot_%d_rnti_%d_candidate_%d', ...
                    upper(char(string(obj.Direction))), round(double(slot)), round(rnti), t));
                row.CandidateIndex = double(t);
                row.CandidateScope = "new_data_pf";
                row.RNTI = double(rnti);
                row.UEIndex = double(sixgr.util.structGet(ueStates(k), "UEIndex", NaN));
                row.ServingCell = double(sixgr.util.structGet(ueStates(k), "ServingCell", NaN));
                row.BufferBytes = double(bufBytes(k));
                row.CQI = double(localUECQI(ueStates(k)));
                row.RI = double(sixgr.util.structGet(ueStates(k), "RI", NaN));
                row.PMI = double(sixgr.util.structGet(ueStates(k), "PMI", NaN));
                row.CRI = double(sixgr.util.structGet(ueStates(k), "CRI", NaN));
                row.AvgThroughput_bps = double(avgRate);
                row.PDCCHAggregationLevel = double(neededCCE);
                row.ControlCCERemainingBefore = double(controlCCERemaining);
                row.SymbolStart = double(symAlloc(1));
                row.NumSymbols = double(symAlloc(2));
                row.CandidateDecisionRowsAvailable = true;
                row.DecisionTruthStatus = "runtime_scheduler_candidate_truth";

                % Skip if HARQ already pending retx (handled earlier)
                if ~isempty(obj.HARQ) && obj.HARQ.hasPendingRetx(rnti, slot)
                    row.HARQPendingRetx = true;
                    row.HARQHasFreeProcess = obj.HARQ.hasFreeProcess(rnti, slot);
                    row.HARQBlocked = ~row.HARQHasFreeProcess;
                    row.Rejected = true;
                    row.RejectionReason = "HARQ_PENDING_RETX_PRIORITY";
                    candidateRows(end+1, 1) = row; %#ok<AGROW>
                    candidateRowIdxByMetric(t) = numel(candidateRows);
                    continue;
                end
                if ~isempty(obj.HARQ) && ~obj.HARQ.hasFreeProcess(rnti, slot)
                    row.HARQHasFreeProcess = false;
                    row.HARQBlocked = true;
                    row.Rejected = true;
                    row.RejectionReason = "HARQ_ALL_PROCESSES_BUSY";
                    candidateRows(end+1, 1) = row; %#ok<AGROW>
                    candidateRowIdxByMetric(t) = numel(candidateRows);
                    continue;
                end
                row.HARQHasFreeProcess = true;

                [probePRBSet,~]=sixgr.l2.mac.contiguousPRBChunk(prbAvail,1,probeChunk,1);
                if isempty(probePRBSet)
                    row.Rejected=true;
                    row.RejectionReason="NO_LEGAL_CONTIGUOUS_PRB_ALLOCATION";
                    candidateRows(end+1,1)=row; %#ok<AGROW>
                    candidateRowIdxByMetric(t)=numel(candidateRows);
                    continue;
                end
                row.ProbePRBCount = double(numel(probePRBSet));
                probePlanTimer = tic;
                plan = obj.buildNewDataGrantPlan(ueStates(k), probePRBSet, symAlloc, bufBytes(k), ...
                    "PlanningOnly", true);
                probePlanElapsed_s(t) = toc(probePlanTimer);
                estTBS(t) = double(sixgr.util.structGet(plan, "TBSBits", 0));
                metrics(t) = obj.pfMetric(ueStates(k), estTBS(t));
                row.EstimatedTBSBits = double(estTBS(t));
                row.EstimatedTBSBytes = double(sixgr.util.structGet(plan, "TBSBytes", 0));
                row.InstantRate_bps = double(estTBS(t)) / max(obj.SlotDuration_s, eps);
                row.PFMetric = double(metrics(t));
                row.QueueLimited = logical(sixgr.util.structGet(plan, "QueueLimited", false));
                row.AMCMode = string(sixgr.util.structGet(plan, "AMCMode", ""));
                row.MCSIndex = double(sixgr.util.structGet(plan, "MCSIndex", NaN));
                row.MCSSelectionSource = string(sixgr.util.structGet(plan, "MCSSelectionSource", ""));
                row.CQIProvenance = string(sixgr.util.structGet(plan, "CQIProvenance", ""));
                row.MCSValueStatus = string(sixgr.util.structGet(plan, "MCSValueStatus", ""));
                row.GrantBlocker = string(sixgr.util.structGet(plan, "GrantBlocker", ""));
                if ~logical(sixgr.util.structGet(plan, "Valid", false)) || estTBS(t) <= 0
                    row.Rejected = true;
                    row.RejectionReason = localFirstNonempty(row.GrantBlocker, "NO_VALID_TBS_PLAN");
                    metrics(t) = -inf;
                    row.PFMetric = -inf;
                elseif metrics(t) <= 0
                    row.Rejected = true;
                    row.RejectionReason = "PF_METRIC_NONPOSITIVE";
                end
                candidateRows(end+1, 1) = row; %#ok<AGROW>
                candidateRowIdxByMetric(t) = numel(candidateRows);
            end
            probeElapsed_s = toc(probeTimer);

            % Sort UEs by PF metric descending
            candidateRows = localAssignPFRanks(candidateRows, metrics, candidateRowIdxByMetric);
            [~, ord] = sort(metrics, 'descend');
            ord = ord(metrics(ord) > 0);
            if isempty(ord)
                info.NGrants = numel(grants);
                candidateRows = localFinalizeCandidateRejections(candidateRows, "NO_PF_CANDIDATE_SELECTED");
                info.CandidateTable = localCandidateTable(candidateRows);
                info.DecisionTable = info.CandidateTable;
                localDecayUnscheduledCandidates(obj, ueStates, ueIdx, grants);
                return;
            end
            cursor = 1;
            usedOrd = false(1, numel(ord));
            scheduledNewUECount = 0;
            allocTimer = tic;
            finalPlanElapsed_s = zeros(1, numel(ord));
            for ii = 1:numel(ord)
                % MaxUEPerSlot limits transmitted UEs, not the CSI
                % compatibility search space.  Truncating ord before MU
                % pairing can hide a compatible third/fourth UE behind an
                % incompatible higher-PF candidate and silently turn an MU
                % opportunity into two orthogonal SU grants.
                if scheduledRetxUECount + scheduledNewUECount >= maxUE
                    break;
                end
                if usedOrd(ii)
                    continue;
                end
                if cursor > numel(prbAvail)
                    break;
                end
                [candidatePRBSet,chunkStart]=sixgr.l2.mac.contiguousPRBChunk( ...
                    prbAvail,cursor,prbChunk,obj.MinPRBPerUE);
                if isempty(candidatePRBSet)
                    break;
                end
                groupOrd = ord(ii);
                if muEnabled
                    groupCapacity = min(muMaxUsers, ...
                        maxUE - scheduledRetxUECount - scheduledNewUECount);
                    for jj = (ii + 1):numel(ord)
                        if usedOrd(jj) || numel(groupOrd) >= groupCapacity
                            continue;
                        end
                        compatibleWithGroup = true;
                        for existingIndex = 1:numel(groupOrd)
                            existingUE = ueStates(ueIdx(groupOrd(existingIndex)));
                            candidateUE = ueStates(ueIdx(ord(jj)));
                            [pairOK, pairLeakage_dB, pairEvidence, candidateDesign] = ...
                                localMUMIMOCompatible(existingUE, candidateUE, ...
                                obj.Cfg, obj.Direction, slot);
                            candidateRows = localRecordMUMIMOAdmission( ...
                                candidateRows, double(existingUE.RNTI), ...
                                double(candidateUE.RNTI), pairOK, ...
                                pairLeakage_dB, pairEvidence, candidateDesign);
                            candidateRows = localRecordMUMIMOAdmission( ...
                                candidateRows, double(candidateUE.RNTI), ...
                                double(existingUE.RNTI), pairOK, ...
                                pairLeakage_dB, pairEvidence, candidateDesign);
                            if ~pairOK
                                compatibleWithGroup = false;
                                break;
                            end
                        end
                        if compatibleWithGroup
                            groupOrd(end + 1) = ord(jj); %#ok<AGROW>
                        end
                    end
                end

                groupGrants = repmat(tmpl, 0, 1);
                groupValid = false(1, numel(groupOrd));
                prbSetForGroup = [];
                groupCCEUsed = 0;
                for gg = 1:numel(groupOrd)
                    k = ueIdx(groupOrd(gg));
                    rnti = double(ueStates(k).RNTI);
                    if ~isempty(obj.HARQ) && obj.HARQ.hasPendingRetx(rnti, slot)
                        candidateRows = localMarkCandidateRejected(candidateRows, rnti, ...
                            "HARQ_PENDING_RETX_PRIORITY");
                        continue;
                    end
                    if ~isempty(obj.HARQ) && ~obj.HARQ.hasFreeProcess(rnti, slot)
                        candidateRows = localMarkCandidateRejected(candidateRows, rnti, ...
                            "HARQ_ALL_PROCESSES_BUSY");
                        continue;
                    end
                    neededCCE = localUEPDCCHCCE(ueStates(k), budget);
                    if controlBudgetActive && neededCCE > max(0, controlCCERemaining - groupCCEUsed)
                        candidateRows = localMarkCandidateRejected(candidateRows, rnti, ...
                            "PDCCH_CCE_BUDGET_EXHAUSTED");
                        continue;
                    end
                    finalPlanTimer = tic;
                    plan = obj.buildNewDataGrantPlan(ueStates(k), candidatePRBSet, symAlloc, bufBytes(k));
                    finalPlanElapsed_s(ii) = finalPlanElapsed_s(ii) + toc(finalPlanTimer);
                    if ~plan.Valid || plan.TBSBits <= 0 || plan.TBSBytes <= 0
                        candidateRows = localMarkCandidateRejected(candidateRows, rnti, ...
                            localFirstNonempty(string(sixgr.util.structGet(plan, "GrantBlocker", "")), ...
                            "NO_VALID_TBS_PLAN"));
                        continue;
                    end
                    prbSet = double(plan.PRBSet(:).');
                    servedBytes = double(plan.TBSBytes);

                    harqInfo = struct('HarqID',[],'NDI',[],'RV',[],'IsRetransmission',false);
                    if ~isempty(obj.HARQ)
                        txp = obj.HARQ.allocate(rnti, slot, servedBytes, 'NewData', true);
                        if logical(sixgr.util.structGet(txp, "NoFreeProcess", false))
                            candidateRows = localMarkCandidateRejected(candidateRows, rnti, ...
                                "HARQ_ALL_PROCESSES_BUSY");
                            continue;
                        end
                        harqInfo = txp.HARQ;
                    end
                    if isempty(prbSetForGroup)
                        prbSetForGroup = prbSet;
                    end

                    g = tmpl;
                    g.Direction = obj.Direction;
                    g.Slot = slot;
                    if ~isempty(controlAbsoluteSlot)
                        g.ControlAbsoluteSlot = controlAbsoluteSlot;
                    end
                    if ~isempty(controlSymbolAllocation)
                        g.ControlSymbolAllocation = ...
                            controlSymbolAllocation;
                    end
                    g.RNTI = rnti;
                    g.PRBSet = prbSet;
                    g.SymbolAllocation = symAlloc;
                    g.Modulation = char(string(plan.Modulation));
                    g.NumLayers = double(plan.NumLayers);
                    g.Layers = double(plan.NumLayers);
                    [g.DMRSPortSet, g.DMRSPortSetSource] = ...
                        sixgr.phy.grant.resolveScheduledDMRSPortSet( ...
                        obj.Cfg, obj.Direction, g.NumLayers, g);
                    g.TargetCodeRate = double(plan.TargetCodeRate);
                    g.TBSBits = double(plan.TBSBits);
                    g.TBSBytes = double(plan.TBSBytes);
                    g.EstimatedTBSBits = double(plan.RawEstimatedTBSBits);
                    g.EstimatedTBSBytes = double(plan.RawEstimatedTBSBytes);
                    g.NREPerPRB = double(plan.NREPerPRB);
                    g.XOverhead = double(sixgr.util.structGet(plan, "XOverhead", 0));
                    g.TBSInputModulation = char(string(sixgr.util.structGet(plan, "TBSInputModulation", plan.Modulation)));
                    g.TBSInputNumLayers = double(sixgr.util.structGet(plan, "TBSInputNumLayers", plan.NumLayers));
                    g.TBSInputNPRB = double(sixgr.util.structGet(plan, "TBSInputNPRB", numel(prbSet)));
                    g.TBSInputNREPerPRB = double(sixgr.util.structGet(plan, "TBSInputNREPerPRB", plan.NREPerPRB));
                    g.TBSInputTargetCodeRate = double(sixgr.util.structGet(plan, "TBSInputTargetCodeRate", plan.TargetCodeRate));
                    g.TBSInputXOverhead = double(sixgr.util.structGet(plan, "TBSInputXOverhead", g.XOverhead));
                    g.TBSInputSource = char(string(sixgr.util.structGet(plan, "TBSInputSource", ...
                        "scheduler_exact_allocation_resource_accounting")));
                    g.MCSTable = char(string(plan.MCSTable));
                    g.CQITable = char(string(plan.CQITable));
                    g.AMCMode = char(string(plan.AMCMode));
                    g.InnerLoopEnabled = logical(sixgr.util.structGet(plan, "InnerLoopEnabled", false));
                    g.InnerLoopApplied = logical(sixgr.util.structGet(plan, "InnerLoopApplied", false));
                    g.OuterLoopEnabled = logical(sixgr.util.structGet(plan, "OuterLoopEnabled", false));
                    g.OuterLoopApplied = logical(sixgr.util.structGet(plan, "OuterLoopApplied", false));
                    g.OLLADeltaDb = double(sixgr.util.structGet(plan, "OLLADeltaDb", sixgr.util.structGet(plan, "OLLADeltaMCS", 0)));
                    g.OLLADeltaMCS = double(sixgr.util.structGet(plan, "OLLADeltaMCS", 0));
                    g.OLLAMarginMinDb = double(sixgr.util.structGet(plan, "OLLAMarginMinDb", NaN));
                    g.OLLAMarginMaxDb = double(sixgr.util.structGet(plan, "OLLAMarginMaxDb", NaN));
                    g.OLLAAdjustedMCSBeforeCQICeiling = double(sixgr.util.structGet(plan, "OLLAAdjustedMCSBeforeCQICeiling", NaN));
                    g.OLLABaseRequiredSINR_dB = double(sixgr.util.structGet(plan, "OLLABaseRequiredSINR_dB", NaN));
                    g.OLLATargetRequiredSINR_dB = double(sixgr.util.structGet(plan, "OLLATargetRequiredSINR_dB", NaN));
                    g.OLLAThresholdSource = char(string(sixgr.util.structGet(plan, "OLLAThresholdSource", "")));
                    g.OLLAUpdateCount = double(sixgr.util.structGet(plan, "OLLAUpdateCount", 0));
                    g.OLLAStateAuthority = char(string(sixgr.util.structGet(plan, ...
                        "OLLAStateAuthority", "scheduler_local_state")));
                    g.OLLAState = char(string(sixgr.util.structGet(plan, "OLLAState", "")));
                    g.MCSSelectionSource = char(string(sixgr.util.structGet(plan, "MCSSelectionSource", "")));
                    g.CQIProvenance = char(string(sixgr.util.structGet(plan, "CQIProvenance", "")));
                    g.MCSValueStatus = char(string(sixgr.util.structGet(plan, "MCSValueStatus", "")));
                    g.ConfiguredInitialMCSIndex = double(sixgr.util.structGet(plan, "ConfiguredInitialMCSIndex", NaN));
                    g.ConfiguredMaximumMCSIndex = double(sixgr.util.structGet(plan, "ConfiguredMaximumMCSIndex", NaN));
                    g.MaximumMCSBoundApplied = logical(sixgr.util.structGet(plan, "MaximumMCSBoundApplied", false));
                    g.CausalFeedbackUsable = logical(sixgr.util.structGet(plan, "CausalFeedbackUsable", false));
                    g.CausalFeedbackStatus = char(string(sixgr.util.structGet(plan, "CausalFeedbackStatus", "")));
                    g.FeedbackAgeSlots = double(sixgr.util.structGet(plan, "FeedbackAgeSlots", NaN));
                    g.FeedbackAgeSeconds = double(sixgr.util.structGet(plan, "FeedbackAgeSeconds", NaN));
                    g.SchedulerCQIRawCQI = double(sixgr.util.structGet(plan, "SchedulerCQIRawCQI", NaN));
                    g.SchedulerAdjustedSINR_dB = double(sixgr.util.structGet(plan, "SchedulerAdjustedSINR_dB", NaN));
                    g.SchedulerSINRBackoff_dB = double(sixgr.util.structGet(plan, "SchedulerSINRBackoff_dB", NaN));
                    g.SchedulerCQISource = char(string(sixgr.util.structGet(plan, "SchedulerCQISource", "")));
                    g.CQIUsed = double(sixgr.util.structGet(plan, "CQIUsed", localUECQI(ueStates(k))));
                    g.RawCQIDerivedMCS = double(sixgr.util.structGet(plan, "RawCQIDerivedMCS", NaN));
                    g.CQIBasedMCS = double(sixgr.util.structGet(plan, "CQIBasedMCS", NaN));
                    g.SmoothedCQI = double(sixgr.util.structGet(plan, "SmoothedCQI", NaN));
                    g.InstantaneousCQIMCS = double(sixgr.util.structGet(plan, "InstantaneousCQIMCS", NaN));
                    g.DeltaMCS = double(sixgr.util.structGet(plan, "DeltaMCS", NaN));
                    g.StaticDeltaMCS = double(sixgr.util.structGet(plan, "StaticDeltaMCS", 0));
                    g.SchedulerCQIRawCQI = double(sixgr.util.structGet(plan, "SchedulerCQIRawCQI", NaN));
                    g.SchedulerAdjustedSINR_dB = double(sixgr.util.structGet(plan, "SchedulerAdjustedSINR_dB", NaN));
                    g.SchedulerSINRBackoff_dB = double(sixgr.util.structGet(plan, "SchedulerSINRBackoff_dB", NaN));
                    g.SchedulerCQISource = char(string(sixgr.util.structGet(plan, "SchedulerCQISource", "")));
                    g.RankSelectionPolicy = char(string(sixgr.util.structGet(plan, "RankSelectionPolicy", "")));
                    g.RankSelectionSource = char(string(sixgr.util.structGet(plan, "RankSelectionSource", "")));
                    g.RankDecisionReason = char(string(sixgr.util.structGet(plan, "RankDecisionReason", "")));
                    g.RankDowngradeApplied = logical(sixgr.util.structGet(plan, "RankDowngradeApplied", false));
                    g.MaxSupportedLayers = double(sixgr.util.structGet(plan, "MaxSupportedLayers", NaN));
                    g.QueueLimited = logical(plan.QueueLimited);
                    g.QueuePaddingBits = double(sixgr.util.structGet(plan, "QueuePaddingBits", 0));
                    g.QueuePaddingBytes = double(sixgr.util.structGet(plan, "QueuePaddingBytes", 0));
                    g.InitialMCSIndex = double(sixgr.util.structGet(plan, "InitialMCSIndex", g.MCSIndex));
                    g.InitialNumLayers = double(sixgr.util.structGet(plan, "InitialNumLayers", g.NumLayers));
                    g.QueueAwareReductionEnabled = logical(sixgr.util.structGet(plan, "QueueAwareReductionEnabled", false));
                    g.QueueAwareReductionApplied = logical(sixgr.util.structGet(plan, "QueueAwareReductionApplied", false));
                    g.QueueAwareReductionSource = char(string(sixgr.util.structGet(plan, "QueueAwareReductionSource", "")));
                    g.MCSReductionSteps = double(sixgr.util.structGet(plan, "MCSReductionSteps", 0));
                    g.LayerReductionSteps = double(sixgr.util.structGet(plan, "LayerReductionSteps", 0));
                    g.HARQ = harqInfo;
                    g.PDCCHAggregationLevel = double(neededCCE);
                    g.ReportedRI = double(sixgr.util.structGet(ueStates(k), "RI", NaN));
                    g.RI = double(plan.NumLayers);
                    g.RIUsed = double(plan.NumLayers);
                    g.Rank = double(plan.NumLayers);
                    g.RankIndicator = double(plan.NumLayers);
                    g.PMI = double(sixgr.util.structGet(ueStates(k), "PMI", NaN));
                    g.CRI = double(sixgr.util.structGet(ueStates(k), "CRI", NaN));
                    g.MCSIndex = double(plan.MCSIndex);
                    g.DAI = 1;
                    g.SearchSpaceID = ssid;
                    g.CORESETID = coreset;
                    g.HeadOfLineDelay_ms = localUEHoLDelay(ueStates(k));
                    g.BufferBytesBefore = bufBytes(k);
                    g.BufferBytesAfter = max(bufBytes(k) - double(servedBytes), 0);
                    % Group status is finalized only after every member has
                    % produced a valid exact PHY plan.  A rejected peer must
                    % not inflate MUMIMOGroupSize or label a lone waveform as
                    % shared-PRB MU execution.
                    g.GrantReason = "new_data_pf";
                    g.MUMIMOEnabled = false;
                    g.MUMIMOGroupSize = 1;
                    g.MUMIMOGroupId = NaN;
                    g.MUMIMOPairingStatus = "single_user_or_mu_disabled";
                    g.MUMIMOPairingMetricSource = "";
                    g.MUMIMOPairingMetricValue_dB = NaN;
                    g.MUMIMOPairingEvidenceSource = "";
                    g.MUMIMOPrecoderType = char(localMUMIMOPrecoderType(obj.Cfg));
                    [g.TBSBits, ~] = sixgr.util.resolveGrantTBSBits(g, ...
                        sprintf("%s %s RNTI=%d", class(obj), char(g.GrantReason), round(rnti)));
                    g.TBSBytes = g.TBSBits / 8;
                    groupGrants = localAppendGrant(groupGrants, g);
                    groupValid(gg) = true;
                    if controlBudgetActive
                        groupCCEUsed = groupCCEUsed + neededCCE;
                    end
                end
                if isempty(groupGrants)
                    usedOrd(ii) = true;
                    continue;
                end
                actualGroupSize = numel(groupGrants);
                isActualMUGroup = logical(muEnabled && actualGroupSize > 1);
                if isActualMUGroup
                    localAssertSharedMUResources(groupGrants);
                end
                groupId = double(localMUMIMOGroupId(slot, cursor));
                muSpatialDesign = struct();
                if isActualMUGroup
                    if actualGroupSize ~= 2
                        error("sixgr:l2:mac:UnsupportedMUMIMOGroupSize", ...
                            "The production measured spatial designer currently requires exactly two MU users; got %d.", ...
                            actualGroupSize);
                    end
                    [compatibleMUDesign, ~, ~, muSpatialDesign] = localMUMIMOCompatible( ...
                        ueStates(ueIdx(groupOrd(1))), ueStates(ueIdx(groupOrd(2))), ...
                        obj.Cfg, obj.Direction, slot);
                    if ~compatibleMUDesign
                        error("sixgr:l2:mac:MUMIMOSpatialDesignInvalidated", ...
                            "The measured MU spatial design became invalid before grant freezing (%s).", ...
                            char(string(sixgr.util.structGet(muSpatialDesign, "Status", "unknown"))));
                    end
                end
                finalizedGroupGrants = repmat(tmpl, 0, 1);
                for gg = 1:actualGroupSize
                    g = groupGrants(gg);
                    g.GrantReason = char(localTernary(isActualMUGroup, ...
                        "new_data_pf_mu_mimo", "new_data_pf"));
                    g.MUMIMOEnabled = logical(isActualMUGroup);
                    g.MUMIMOGroupSize = double(actualGroupSize);
                    g.MUMIMOGroupId = double(localTernary(isActualMUGroup, groupId, NaN));
                    g.MUMIMOPairingStatus = char(localTernary(isActualMUGroup, ...
                        "paired_shared_prb_spatial_multiplexing", ...
                        "single_user_or_mu_disabled"));
                    if isActualMUGroup
                        g.DMRSPortSet = localMUMIMODMRSPortSet( ...
                            obj.Cfg, obj.Direction, g.NumLayers, gg, actualGroupSize);
                        g = localApplyMUMIMOSpatialDesign(g, muSpatialDesign, gg, obj.Direction);
                    else
                        g.MUMIMOPairingMetricSource = "not_applicable_single_user";
                        g.MUMIMOPairingEvidenceSource = "no_mu_pair_transmitted";
                    end
                    stateIndex = ueIdx(groupOrd(gg));
                    g = obj.attachULSRSAuthorityToGrant(g, ueStates(stateIndex));
                    g = sixgr.l2.mac.attachReceivedULTimingAuthority(g,ueStates(stateIndex));
                    [g.DMRSPortSet, g.DMRSPortSetSource] = ...
                        sixgr.phy.grant.resolveScheduledDMRSPortSet( ...
                        obj.Cfg, obj.Direction, g.NumLayers, g);
                    [g.TBSBits, ~] = sixgr.util.resolveGrantTBSBits(g, ...
                        sprintf("%s %s RNTI=%d", class(obj), char(g.GrantReason), round(g.RNTI)));
                    g.TBSBytes = g.TBSBits / 8;
                    g = obj.freezePHYGrantForGrant(g);
                    g.DCI = obj.buildDCIBitfield(g);
                    finalizedGroupGrants = localAppendGrant(finalizedGroupGrants, g);
                end
                groupGrants = finalizedGroupGrants;
                cursor = chunkStart + max(1, numel(prbSetForGroup));
                usedOrd(ii) = true;
                usedOrd(ismember(ord, groupOrd(groupValid))) = true;
                scheduledNewUECount = scheduledNewUECount + actualGroupSize;
                if controlBudgetActive
                    controlCCERemaining = max(0, controlCCERemaining - groupCCEUsed);
                end
                for gg = 1:numel(groupGrants)
                    grants = localAppendGrant(grants, groupGrants(gg));
                    rnti = double(groupGrants(gg).RNTI);
                    candidateRows = localMarkCandidateScheduled(candidateRows, rnti, groupGrants(gg), numel(grants));
                    obj.ensureUE(rnti);
                    obj.updateAvgThroughput(rnti, groupGrants(gg).TBSBits, true);
                    obj.UEStats(obj.ensureUE(rnti)).LastServedSlot = slot;
                end
            end
            allocElapsed_s = toc(allocTimer);
            localDecayUnscheduledCandidates(obj, ueStates, ueIdx, grants);

            info.NGrants = numel(grants);
            info.PRBUnderuse = numel(setdiff(prbAvail,[grants.PRBSet]));
            info.ProbeElapsed_s = probeElapsed_s;
            info.AllocationElapsed_s = allocElapsed_s;
            info.ScheduleElapsed_s = toc(scheduleTimer);
            info.ProbePlanTotalElapsed_s = sum(probePlanElapsed_s);
            info.ProbePlanMaxElapsed_s = max([0 probePlanElapsed_s]);
            info.FinalPlanTotalElapsed_s = sum(finalPlanElapsed_s);
            info.FinalPlanMaxElapsed_s = max([0 finalPlanElapsed_s]);
            candidateRows = localFinalizeCandidateRejections(candidateRows, "NOT_SELECTED_LOWER_PF_OR_RESOURCE_LIMIT");
            info.CandidateTable = localCandidateTable(candidateRows);
            info.DecisionTable = info.CandidateTable;
            if slot == 0
                obj.log('info', sprintf([ ...
                    'SchedulerPF[%s] slot=%d ueStates=%d activeUE=%d maxUE=%d prbAvail=%d ' ...
                    'probe_s=%.3f probePlanTotal_s=%.3f probePlanMax_s=%.3f ' ...
                    'alloc_s=%.3f finalPlanTotal_s=%.3f finalPlanMax_s=%.3f total_s=%.3f grants=%d'], ...
                    char(string(obj.Direction)), double(slot), double(numel(ueStates)), ...
                    double(numel(ueIdx)), double(maxUE), double(numel(prbAvail)), ...
                    double(probeElapsed_s), double(info.ProbePlanTotalElapsed_s), ...
                    double(info.ProbePlanMaxElapsed_s), double(allocElapsed_s), ...
                    double(info.FinalPlanTotalElapsed_s), double(info.FinalPlanMaxElapsed_s), ...
                    double(info.ScheduleElapsed_s), double(numel(grants))));
            end
        end
    end

    methods(Static)
        function rate_bps = cqiToApproxThroughputBps( ...
                cqi, nPRB, slotDuration_s, symbolsPerSlot)
            if nargin < 2 || isempty(nPRB)
                error("sixgr:SchedulerPF:MissingNRB", ...
                    "Approximate throughput requires explicit N_RB.");
            end
            if nargin < 3 || isempty(slotDuration_s)
                error("sixgr:SchedulerPF:MissingSlotDuration", ...
                    "Approximate throughput requires canonical slot duration.");
            end
            if nargin < 4 || isempty(symbolsPerSlot)
                error("sixgr:SchedulerPF:MissingSymbolsPerSlot", ...
                    "Approximate throughput requires canonical SymbolsPerSlot.");
            end
            nPRB = double(nPRB);
            slotDuration_s = double(slotDuration_s);
            symbolsPerSlot = double(symbolsPerSlot);
            if ~(isscalar(nPRB) && isfinite(nPRB) && ...
                    nPRB >= 1 && nPRB == fix(nPRB))
                error("sixgr:SchedulerPF:InvalidNRB", ...
                    "N_RB must be a positive integer.");
            end
            if ~(isscalar(slotDuration_s) && ...
                    isfinite(slotDuration_s) && slotDuration_s > 0)
                error("sixgr:SchedulerPF:InvalidSlotDuration", ...
                    "Slot duration must be a positive finite scalar.");
            end
            if ~(isscalar(symbolsPerSlot) && ...
                    isfinite(symbolsPerSlot) && ...
                    symbolsPerSlot == fix(symbolsPerSlot) && ...
                    any(symbolsPerSlot == [12, 14]))
                error("sixgr:SchedulerPF:InvalidSymbolsPerSlot", ...
                    "Canonical NR SymbolsPerSlot must be 12 or 14.");
            end
            cqi = sixgr.l2.mac.SchedulerBase.sanitizeCQI(cqi, 1);
            profile = sixgr.link.resolveCQIProfile("table2", cqi);
            se = double(sixgr.util.structGet(profile, "SpectralEfficiency", NaN));
            if ~(isfinite(se) && se > 0)
                se = max(0.15, 0.15 * double(cqi));
            end
            rate_bps = nPRB * 12 * symbolsPerSlot * se / slotDuration_s;
        end
    end
end

function value = localBudgetControlAbsoluteSlot(budget)
value = [];
if isstruct(budget) && isscalar(budget) && ...
        isfield(budget, "ControlAbsoluteSlot") && ...
        ~isempty(budget.ControlAbsoluteSlot)
    raw = double(budget.ControlAbsoluteSlot);
    if ~(isscalar(raw) && isfinite(raw) && raw >= 0 && raw == fix(raw))
        error("sixgr:SchedulerPF:InvalidControlAbsoluteSlot", ...
            "budget.ControlAbsoluteSlot must be a zero-based nonnegative integer.");
    end
    value = raw;
end
end

function value = localBudgetControlSymbolAllocation(budget)
value = [];
if isstruct(budget) && isscalar(budget) && ...
        isfield(budget, "ControlSymbolAllocation") && ...
        ~isempty(budget.ControlSymbolAllocation)
    raw = double(budget.ControlSymbolAllocation(:).');
    if ~(numel(raw) == 2 && all(isfinite(raw)) && ...
            all(raw == fix(raw)) && raw(1) >= 0 && raw(2) >= 1)
        error("sixgr:SchedulerPF:InvalidControlSymbolAllocation", ...
            "budget.ControlSymbolAllocation must be [start>=0 count>=1].");
    end
    value = raw;
end
end

function grants = localAppendGrant(grants, grant)
if isempty(grants)
    grants = grant;
    return;
end
[grants, grant] = localAlignGrantFields(grants, grant);
grants(end+1) = grant; %#ok<AGROW>
end

function [grants, grant] = localAlignGrantFields(grants, grant)
grantFields = fieldnames(grant);
arrayFields = fieldnames(grants);
missingInGrant = setdiff(arrayFields, grantFields);
for i = 1:numel(missingInGrant)
    f = missingInGrant{i};
    grant.(f) = localDefaultFieldLike(f, grants(1).(f));
end
missingInArray = setdiff(grantFields, arrayFields);
for i = 1:numel(missingInArray)
    f = missingInArray{i};
    v = localDefaultFieldLike(f, grant.(f));
    for k = 1:numel(grants)
        grants(k).(f) = v;
    end
end
end

function value = localDefaultFieldLike(fieldName, example)
if isstruct(example)
    % Struct-valued grant fields carry per-UE authority (for example the
    % frozen PHY grant, DCI, and HARQ TB context). Schema alignment may add
    % the field to another grant, but it must never copy another UE's value.
    value = struct();
elseif isstring(example)
    value = strings(size(example));
elseif ischar(example)
    value = '';
elseif islogical(example)
    if isscalar(example)
        value = false;
    else
        value = false(0, 0);
    end
elseif isa(example, 'uint8')
    % A missing coded-bit or payload authority is absent, not the bit zero.
    value = uint8([]);
elseif isnumeric(example)
    if isscalar(example)
        % Numeric zero is often a valid grant value (PMI, BWP, HARQ ID,
        % port/RF-chain count metadata, and so on). Manufacturing zero
        % while aligning heterogeneous grants therefore corrupts evidence.
        if isfloat(example)
            value = NaN(1, 1, "like", example);
        else
            value = zeros(0, 0, "like", example);
        end
    else
        % A non-scalar grant field is allocation or matrix authority.  A
        % same-shaped zero value is not neutral: it can masquerade as a
        % frozen precoder/combiner (or a real allocation) owned by another
        % UE.  Preserve only the schema and leave the semantic value absent.
        value = zeros(0, 0, "like", example);
    end
else
    value = [];
end
end

function grant = localPrepareRetransmissionGrant(grant, retx, ue, direction, ...
        slot, controlAbsoluteSlot, controlSymbolAllocation, searchSpaceID, ...
        coresetID, neededCCE, bufferBytes, resolvedMCSTable)
grant.Slot = double(slot);
if ~isempty(controlAbsoluteSlot)
    grant.ControlAbsoluteSlot = controlAbsoluteSlot;
end
if ~isempty(controlSymbolAllocation)
    grant.ControlSymbolAllocation = controlSymbolAllocation;
end
grant.Direction = char(string(direction));
if ~isfield(grant, "MCSTable") || strlength(string(grant.MCSTable)) == 0
    grant.MCSTable = char(string(resolvedMCSTable));
end
grant.HARQ = retx.HARQ;
grant.HARQTBContext = sixgr.util.structGet(retx, "TBContext", ...
    sixgr.util.structGet(grant, "HARQTBContext", struct()));
grant.IsRetransmission = true;
grant.CQIUsed = double(sixgr.util.structGet(grant, "CQIUsed", localUECQI(ue)));
grant.PDCCHAggregationLevel = double(neededCCE);
grant.DAI = 1;
grant.SearchSpaceID = searchSpaceID;
grant.CORESETID = coresetID;
grant.HeadOfLineDelay_ms = localUEHoLDelay(ue);
grant.BufferBytesBefore = double(bufferBytes);
[grant.TBSBits, ~] = sixgr.util.resolveGrantTBSBits(grant, ...
    sprintf("%s HARQ retransmission RNTI=%d process=%d", ...
    "sixgr.l2.mac.SchedulerPF", round(double(grant.RNTI)), ...
    round(double(sixgr.util.structGet(grant, "HARQ.HarqID", -1)))));
if grant.TBSBits <= 0
    error("sixgr:SchedulerPF:MissingRetransmissionTBS", ...
        "HARQ retransmission RNTI=%d has no positive frozen TBS.", ...
        round(double(grant.RNTI)));
end
grant.TBSBytes = grant.TBSBits / 8;
grant.BufferBytesAfter = max(double(bufferBytes) - double(grant.TBSBytes), 0);
end

function g = localGrantTemplate(direction, slot)
g = struct();
g.Direction = char(string(direction));
g.Slot = double(slot);
g.RNTI = 0;
g.PRBSet = zeros(1,0);
g.PRBStart = NaN;
g.AllocatedPRBCount = 0;
g.PRBCount = 0;
g.SymbolAllocation = [NaN NaN];
g.Modulation = 'QPSK';
g.NumLayers = 1;
g.Layers = 1;
g.TargetCodeRate = 0.5;
g.TBSBits = 0;
g.TBSBytes = 0;
g.TransportBlockSize = 0;
g.EstimatedTBSBits = 0;
g.EstimatedTBSBytes = 0;
g.NREPerPRB = 0;
g.XOverhead = 0;
g.TBSInputModulation = 'QPSK';
g.TBSInputNumLayers = 1;
g.TBSInputNPRB = 0;
g.TBSInputNREPerPRB = 0;
g.TBSInputTargetCodeRate = 0.5;
g.TBSInputXOverhead = 0;
g.TBSInputSource = '';
g.MCSTable = 'qam64_table1';
g.CQITable = 'table1';
g.AMCMode = 'fixed_modulation';
g.InnerLoopEnabled = false;
g.InnerLoopApplied = false;
g.OuterLoopEnabled = false;
g.OuterLoopApplied = false;
g.OLLADeltaDb = 0;
g.OLLADeltaMCS = 0;
g.OLLAMarginMinDb = NaN;
g.OLLAMarginMaxDb = NaN;
g.OLLAAdjustedMCSBeforeCQICeiling = NaN;
g.OLLABaseRequiredSINR_dB = NaN;
g.OLLATargetRequiredSINR_dB = NaN;
g.OLLAThresholdSource = "";
g.OLLAUpdateCount = 0;
g.OLLAStateAuthority = "";
g.OLLAState = "";
g.MCSSelectionSource = "";
g.CQIProvenance = "";
g.MCSValueStatus = "";
% Runtime link-adaptation lineage is part of the grant schema, including
% grants for which no feedback decision has yet been applied.  Keeping
% these fields in the template prevents heterogeneous multi-UE grant-array
% alignment from manufacturing empty values at the PHY execution boundary.
g.LinkAdaptationFeedbackApplied = false;
g.LinkAdaptationAppliedFeedbackSourceSlot = NaN;
g.LinkAdaptationAppliedFeedbackDeliveredSlot = NaN;
g.LinkAdaptationAppliedFeedbackAgeSlots = NaN;
g.AppliedLinkAdaptationResolvedCQI = NaN;
g.AppliedLinkAdaptationCQIBasedMCS = NaN;
g.AppliedLinkAdaptationMCS = NaN;
g.AppliedLinkAdaptationOLLADeltaDb = NaN;
g.AppliedLinkAdaptationOLLAUpdateCount = NaN;
g.AppliedLinkAdaptationOLLAFeedbackEligible = false;
g.LinkAdaptationDecisionReason = "";
g.LinkAdaptationMCSIndex = NaN;
g.ConfiguredInitialMCSIndex = NaN;
g.ConfiguredMaximumMCSIndex = NaN;
g.MaximumMCSBoundApplied = false;
g.CausalFeedbackUsable = false;
g.CausalFeedbackStatus = "";
g.FeedbackAgeSlots = NaN;
g.FeedbackAgeSeconds = NaN;
g.SchedulerCQIRawCQI = NaN;
g.SchedulerAdjustedSINR_dB = NaN;
g.SchedulerSINRBackoff_dB = NaN;
g.SchedulerCQISource = "";
g.RankSelectionPolicy = "";
g.RankSelectionSource = "";
g.RankDecisionReason = "";
g.RankDowngradeApplied = false;
g.MaxSupportedLayers = NaN;
g.QueueLimited = false;
g.QueuePaddingBits = 0;
g.QueuePaddingBytes = 0;
g.InitialMCSIndex = NaN;
g.InitialNumLayers = 1;
g.QueueAwareReductionEnabled = false;
g.QueueAwareReductionApplied = false;
g.QueueAwareReductionSource = "";
g.MCSReductionSteps = 0;
g.LayerReductionSteps = 0;
g.Valid = true;
g.ExactPHYFeasibilityChecked = false;
g.ExactPHYFeasible = false;
g.ExactPHYFeasibilitySource = "";
g.ExecutableTBSMode = "";
g.ExactPHYInfeasibilityReason = "";
g.ExactAllocationCapacityBits = NaN;
g.ExactAllocationCapacityBytes = NaN;
g.ExactTBSBits = NaN;
g.ExactTBSBytes = NaN;
g.ExactNREPerPRB = NaN;
g.ExactTBSUsedFastNREApprox = false;
g.ExactTBSInfo = struct("UsedFastNREApprox", false, "StrictTBSMode", false, ...
    "TBSMode", "", "ViennaEquivalent", false, "PlanningOnly", false, ...
    "ForceExact", false, "XOverhead", 0);
g.HARQ = struct('HarqID',[],'NDI',[],'RV',[],'IsRetransmission',false);
g.MCSIndex = 1;
g.CQIUsed = 1;
g.PDCCHAggregationLevel = NaN;
g.PDCCHCandidateIndex = 0;
g.RIUsed = NaN;
g.PMI = NaN;
g.CRI = NaN;
g.DAI = 1;
g.K0 = NaN;
g.K1 = NaN;
g.K2 = NaN;
g.SearchSpaceID = 0;
g.CORESETID = 0;
g.BWPId = NaN;
g.HeadOfLineDelay_ms = 0;
g.BufferBytesBefore = 0;
g.BufferBytesAfter = 0;
g.GrantReason = "new_data_pf";
g.MUMIMOEnabled = false;
g.MUMIMOGroupSize = 1;
g.MUMIMOGroupId = NaN;
g.MUMIMOPairingStatus = "";
g.MUMIMOPairingMetricSource = "";
g.MUMIMOPairingMetricValue_dB = NaN;
g.MUMIMOPairingEvidenceSource = "";
g.MUMIMOPrecoderType = "";
g.PHYGrant = struct();
g.PHYGrantContextId = "";
g.DCI = struct("Format","","Bits",uint8([]),"Hex","","FieldMap",struct(),"FieldValues",struct(), ...
    "RIV",0,"RBStart",0,"RBLength",0,"SLIV",NaN,"TimeDomainAssignmentIndex",NaN, ...
    "StandardProfile","","BitExactPDCCHPayload",false,"PHYGrant",struct(), ...
    "PHYGrantContextId","","PHYGrantEvidenceSource","","FinalizedGrant",false, ...
    "ExactPHYFeasibilityChecked",false,"ExactPHYFeasible",false, ...
    "SourceGrantTBSBits",NaN,"DCIGrantContract","","BitLength",0, ...
    "NRFieldLayoutSource","","NRResourceAssignmentSource","");
end

function [active, remainingCCE] = localPDCCHCCEBudget(budget)
remainingCCE = double(sixgr.util.structGet(budget, "PDCCHCCEBudget", NaN));
active = isfinite(remainingCCE) && remainingCCE > 0;
if ~active
    remainingCCE = inf;
end
end

function neededCCE = localUEPDCCHCCE(ue, budget)
neededCCE = double(sixgr.util.structGet(ue, "PDCCHAggregationLevel", ...
    sixgr.util.structGet(budget, "DefaultPDCCHAggregationLevel", 1)));
if ~(isfinite(neededCCE) && any(neededCCE == [1 2 4 8 16]))
    neededCCE = 1;
end
end

function g = localNormalizeGrant(gIn, tmpl, direction, slot)
g = tmpl;
if isstruct(gIn) && ~isempty(gIn)
    f = fieldnames(gIn);
    for i = 1:numel(f)
        g.(f{i}) = gIn.(f{i});
    end
    f = fieldnames(tmpl);
    for i = 1:numel(f)
        if ~isfield(g, f{i})
            g.(f{i}) = tmpl.(f{i});
        end
    end
end
g.Direction = char(string(direction));
g.Slot = double(slot);
if isempty(g.HARQ) || ~isstruct(g.HARQ)
    g.HARQ = tmpl.HARQ;
end
end

function cqi = localUECQI(ue)
raw = double(sixgr.util.structGet(ue, "CQI", NaN));
cqi = sixgr.l2.mac.SchedulerBase.sanitizeCQI( ...
    raw, 1);
end

function hol = localUEHoLDelay(ue)
hol = double(sixgr.util.structGet(ue, "HeadOfLineDelay_ms", 0));
if ~isfinite(hol) || hol < 0
    hol = 0;
end
end

function tf = localMUMIMOEnabled(cfg, direction)
direction = upper(string(direction));
muEnabled = logical(sixgr.util.structGet(cfg, "mac.scheduler.muMimoEnabled", ...
    sixgr.util.structGet(cfg, "phy.mimo.muMimoEnabled", ...
    sixgr.util.structGet(cfg, "mimo.mu_mimo_enable", false))));
sixgr.config.assertRuntimeFeatureUse(cfg, "mu_mimo", muEnabled, ...
    "SchedulerPF.MU-MIMO");
tf = muEnabled;
if direction ~= "DL"
    ulEnabled = logical(sixgr.util.structGet(cfg, ...
        "mac.scheduler.ulMuMimoEnabled", ...
        sixgr.util.structGet(cfg, "phy.mimo.ulMuMimoEnabled", false)));
    sixgr.config.assertRuntimeFeatureUse(cfg, "ul_mu_mimo", ulEnabled, ...
        "SchedulerPF.UL-MU-MIMO");
    tf = tf && ulEnabled;
end
end

function n = localMUMIMOMaxUsers(cfg)
n = double(sixgr.util.structGet(cfg, "mac.scheduler.muMimoMaxUsersPerPRB", ...
    sixgr.util.structGet(cfg, "phy.mimo.muMimoMaxUsersPerPRB", 2)));
if ~(isscalar(n) && isfinite(n) && n >= 2)
    n = 2;
end
n = max(2, min(8, round(n)));
end

function [tf, leakage_dB, evidenceSource, design] = localMUMIMOCompatible(ueA, ueB, cfg, direction, currentSlot)
tf = false;
leakage_dB = NaN;
evidenceSource = "";
design = struct("Compatible", false, "Status", "not_evaluated");
if ~(logical(sixgr.util.structGet(ueA, "FeedbackValid", false)) && ...
        logical(sixgr.util.structGet(ueB, "FeedbackValid", false)) && ...
        logical(sixgr.util.structGet(ueA, "CausalFeedbackUsable", false)) && ...
        logical(sixgr.util.structGet(ueB, "CausalFeedbackUsable", false)))
    evidenceSource = "missing_causal_measured_feedback";
    return;
end
[validSpatialA, spatialReasonA] = localMeasuredSpatialFeedbackValid(ueA, cfg, direction, currentSlot);
[validSpatialB, spatialReasonB] = localMeasuredSpatialFeedbackValid(ueB, cfg, direction, currentSlot);
if ~(validSpatialA && validSpatialB)
    if ~validSpatialA
        evidenceSource = "ue_a_" + spatialReasonA;
    else
        evidenceSource = "ue_b_" + spatialReasonB;
    end
    return;
end
cqiA = localUECQI(ueA);
cqiB = localUECQI(ueB);
if min(cqiA, cqiB) <= 0
    evidenceSource = "nonpositive_measured_cqi";
    return;
end
maxDeltaCQI = double(sixgr.util.structGet(cfg, "mac.scheduler.muMimoMaxCQIDelta", 4));
if abs(cqiA - cqiB) > maxDeltaCQI
    evidenceSource = "measured_cqi_delta_exceeds_limit";
    return;
end
riA = double(sixgr.util.structGet(ueA, "RI", 1));
riB = double(sixgr.util.structGet(ueB, "RI", 1));
if ~(isfinite(riA) && isfinite(riB) && riA >= 1 && riB >= 1)
    evidenceSource = "invalid_measured_rank";
    return;
end
wA = localSpatialSignature(ueA);
wB = localSpatialSignature(ueB);
if isempty(wA) || isempty(wB)
    evidenceSource = "measured_spatial_signature_unavailable";
    return;
end
authorityA = lower(strtrim(string(sixgr.util.structGet( ...
    ueA, "MUMIMOSpatialSignatureReciprocityMode", ""))));
authorityB = lower(strtrim(string(sixgr.util.structGet( ...
    ueB, "MUMIMOSpatialSignatureReciprocityMode", ""))));
if strlength(authorityA) == 0 || authorityA ~= authorityB
    evidenceSource = "measured_spatial_authority_mismatch";
    return;
end
try
    design = sixgr.phy.mimo.designMeasuredMUMIMOPair( ...
        wA, wB, cfg, direction, riA, riB, authorityA);
catch ME
    evidenceSource = "measured_spatial_design_error:" + string(ME.identifier);
    return;
end
tf = logical(sixgr.util.structGet(design, "Compatible", false));
leakage_dB = double(sixgr.util.structGet(design, "WorstLeakage_dB", NaN));
evidenceSource = string(sixgr.util.structGet(design, "EvidenceSource", ...
    sixgr.util.structGet(design, "Status", "measured_spatial_design_unavailable")));
end

function grant = localApplyMUMIMOSpatialDesign(grant, design, memberIndex, direction)
memberIndex = round(double(memberIndex));
direction = upper(string(direction));
if ~(memberIndex == 1 || memberIndex == 2) || ...
        ~logical(sixgr.util.structGet(design, "Compatible", false))
    error("sixgr:l2:mac:InvalidMUMIMOSpatialDesign", ...
        "A compatible two-member measured spatial design is required.");
end
grant.MUMIMOPairingMetricSource = char(string(design.MetricSource));
grant.MUMIMOPairingMetricValue_dB = double(design.MemberLeakage_dB(memberIndex));
grant.MUMIMOPairingWorstMetricValue_dB = double(design.WorstLeakage_dB);
grant.MUMIMOPairingEvidenceSource = char(string(design.EvidenceSource));
grant.MUMIMORequiredLeakageThreshold_dB = double(design.RequiredLeakageThreshold_dB);
grant.MUMIMODesiredSubspaceGain_dB = double(design.MemberDesiredGain_dB(memberIndex));
grant.MUMIMORequiredMinimumDesiredGain_dB = double(design.RequiredMinimumDesiredGain_dB);
grant.MUMIMOSpatialDesignStatus = char(string(design.Status));
grant.MUMIMOSpatialDesignContractVersion = char(string(design.ContractVersion));
grant.MUMIMOSpatialSignatureSubspaceMode = char(string( ...
    design.SpatialSignatureSubspaceMode));
grant.MUMIMOSpatialDesignEvidenceSource = char(string(design.EvidenceSource));
grant.MUMIMOSpatialFilterMatrixSHA256 = char(string( ...
    design.("Member" + string(memberIndex) + "MatrixSHA256")));
if direction == "DL"
    logicalMatrix = design.("Member" + string(memberIndex) + "PrecoderLogicalPorts");
    physicalMatrix = design.("Member" + string(memberIndex) + "PrecoderPhysical");
    grant.NumLogicalPorts = double(design.TotalLogicalPorts);
    grant.NumRFChains = double(design.NumRFChains);
    grant.PrecodingMatrixLogicalPorts = double(logicalMatrix);
    grant.LogicalPrecodingMatrix = double(logicalMatrix);
    grant.PrecodingMatrix = double(physicalMatrix);
    grant.PrecoderNormalizationConvention = char(string( ...
        design.PrecoderNormalizationConvention));
    grant.HybridElementToPortMatrix = double(design.HybridElementToPortMatrix);
    grant.HybridElementToPortMatrixSHA256 = char(string( ...
        design.HybridElementToPortMatrixSHA256));
    grant.BaseHybridElementToPortMatrixSHA256 = char(string( ...
        design.BaseHybridElementToPortMatrixSHA256));
    grant.MUMIMOHybridRFDesignPolicy = char(string(design.HybridRFDesignPolicy));
    grant.MUMIMOHybridRFDesignStatus = char(string(design.HybridRFDesignStatus));
    grant.MUMIMOTransmitArchitecture = char(string(design.TransmitArchitecture));
    grant.PrecodingActive = true;
    spatialAuthorityMode = lower(strtrim(string( ...
        sixgr.util.structGet(design, "SpatialAuthorityMode", ""))));
    if spatialAuthorityMode == "direct_dl_csirs"
        grant.PrecodingMode = "measured_fdd_csirs_block_diagonalization";
        grant.PrecoderSource = "causal_measured_csirs_mu_block_diagonalization";
        grant.MUMIMOPrecoderType = "measured_csirs_block_diagonalization";
    elseif spatialAuthorityMode == "tdd_reciprocity"
        grant.PrecodingMode = "measured_tdd_srs_block_diagonalization";
        grant.PrecoderSource = "causal_measured_srs_mu_block_diagonalization";
        grant.MUMIMOPrecoderType = "measured_srs_block_diagonalization";
    else
        error("sixgr:l2:mac:InvalidDLMUMIMOSpatialAuthority", ...
            "DL MU-MIMO design has unsupported spatial authority '%s'.", ...
            char(spatialAuthorityMode));
    end
    if string(design.TransmitArchitecture) == "fully_digital_element_control"
        grant.PrecodingApplicationStage = ...
            "fully_digital_baseband_before_nrPDSCH_RE_mapping";
    else
        grant.PrecodingApplicationStage = ...
            "hybrid_rf_bb_before_nrPDSCH_RE_mapping";
    end
else
    receiveCombiner = design.("Member" + string(memberIndex) + "ReceiveCombiner");
    admissionCombiner = design.("Member" + string(memberIndex) + "AdmissionReceiveCombiner");
    grant.MUMIMOReceiveCombiningMatrix = double(receiveCombiner);
    grant.ReceiveCombinerNormalizationConvention = char(string( ...
        design.ReceiveCombinerNormalizationConvention));
    grant.MUMIMOReceiveCombiningMatrixSHA256 = char( ...
        sixgr.phy.mimo.MatrixContract.digest(double(receiveCombiner)));
    grant.MUMIMOAdmissionReceiveCombiningMatrix = double(admissionCombiner);
    grant.MUMIMOAdmissionReceiveCombiningMatrixSHA256 = char(string( ...
        design.("Member" + string(memberIndex) + "AdmissionMatrixSHA256")));
    grant.MUMIMOReceiveProcessingMode = char(string(design.ULReceiveProcessingMode));
    grant.MUMIMOReceiverAlgorithm = "full_dimensional_per_re_irc";
    grant.MUMIMOPrecoderType = "measured_srs_pairing_full_dimensional_per_re_irc";
end
end

function [tf, reason] = localMeasuredSpatialFeedbackValid(ue, cfg, direction, currentSlot)
tf = false;
reason = "measured_spatial_signature_invalid";
if ~logical(sixgr.util.structGet(ue, "MUMIMOSpatialSignatureValid", false))
    reason = "measured_spatial_signature_not_causal_or_fresh";
    return;
end
w = localSpatialSignature(ue);
digest = lower(strtrim(string(sixgr.util.structGet( ...
    ue, "MUMIMOSpatialSignatureSHA256", ""))));
source = lower(strtrim(string(sixgr.util.structGet( ...
    ue, "MUMIMOSpatialSignatureSource", ""))));
measurementDirection = upper(strtrim(string(sixgr.util.structGet( ...
    ue, "MUMIMOSpatialSignatureMeasurementDirection", ""))));
reciprocityMode = lower(strtrim(string(sixgr.util.structGet( ...
    ue, "MUMIMOSpatialSignatureReciprocityMode", ""))));
sourceSlot = double(sixgr.util.structGet( ...
    ue, "MUMIMOSpatialSignatureSourceSlot", NaN));
ageSlots = double(sixgr.util.structGet( ...
    ue, "MUMIMOSpatialSignatureAgeSlots", NaN));
consumerRuntimeSlot = double(sixgr.util.structGet( ...
    ue, "MUMIMOSpatialSignatureConsumerRuntimeSlot", NaN));
maxAgeSlots = double(sixgr.util.structGet(cfg, ...
    "phy.mimo.measurementMaxAgeSlots", NaN));
if isempty(w) || strlength(digest) ~= 64 || ...
        digest ~= lower(string(sixgr.phy.mimo.MatrixContract.digest(w)))
    reason = "measured_spatial_signature_digest_mismatch";
    return;
end
if ~(isscalar(sourceSlot) && isfinite(sourceSlot) && sourceSlot >= 0 && ...
        isscalar(ageSlots) && isfinite(ageSlots) && ageSlots >= 0 && ...
        isscalar(maxAgeSlots) && isfinite(maxAgeSlots) && maxAgeSlots >= 0 && ...
        ageSlots <= maxAgeSlots && ...
        isscalar(consumerRuntimeSlot) && isfinite(consumerRuntimeSlot) && ...
        isscalar(currentSlot) && isfinite(currentSlot) && ...
        abs((sourceSlot + ageSlots) - consumerRuntimeSlot) <= 1e-9 && ...
        abs(consumerRuntimeSlot - (double(currentSlot) + 1)) <= 1e-9)
    reason = "measured_spatial_signature_stale";
    return;
end
direction = upper(strtrim(string(direction)));
if direction == "DL"
    directFDD = startsWith(source, ...
        "measured_csirs_receiver_channel_estimate_transmit_subspace") && ...
        measurementDirection == "DL" && reciprocityMode == "direct_dl_csirs";
    reciprocalTDD = startsWith(source, ...
        "measured_srs_receiver_channel_estimate") && ...
        measurementDirection == "UL" && reciprocityMode == "tdd_reciprocity";
    if ~(directFDD || reciprocalTDD)
        reason = "measured_dl_spatial_signature_source_or_authority_invalid";
        return;
    end
elseif direction == "UL"
    if ~startsWith(source, "measured_srs_receiver_channel_estimate") || ...
            measurementDirection ~= "UL" || reciprocityMode ~= "direct_ul_srs"
        reason = "measured_spatial_signature_not_direct_ul_srs";
        return;
    end
else
    reason = "measured_spatial_signature_direction_invalid";
    return;
end
tf = true;
reason = "causal_measured_spatial_signature:" + reciprocityMode;
end

function grant = localMarkUnpairedRetransmission(grant)
% A retransmission keeps the frozen spatial filter used by its immutable
% HARQ contract, but it is not a current MU execution unless a peer is
% scheduled over the same PRBs and symbols in this slot.
wasMU = logical(sixgr.util.structGet(grant, "MUMIMOEnabled", false)) || ...
    double(sixgr.util.structGet(grant, "MUMIMOGroupSize", 1)) > 1;
if wasMU
    grant.PriorMUMIMOGroupId = double(sixgr.util.structGet( ...
        grant, "MUMIMOGroupId", NaN));
    grant.PriorMUMIMOGroupSize = double(sixgr.util.structGet( ...
        grant, "MUMIMOGroupSize", NaN));
    grant.PriorMUMIMOPairingEvidenceSource = char(string(sixgr.util.structGet( ...
        grant, "MUMIMOPairingEvidenceSource", "")));
end
grant.MUMIMOEnabled = false;
grant.MUMIMOGroupSize = 1;
grant.MUMIMOGroupId = NaN;
grant.MUMIMOPairingStatus = "retransmission_without_current_shared_mu_peer";
grant.MUMIMOPairingMetricSource = "not_applicable_current_orthogonal_retransmission";
grant.MUMIMOPairingMetricValue_dB = NaN;
grant.MUMIMOPairingWorstMetricValue_dB = NaN;
grant.MUMIMOPairingEvidenceSource = "no_current_shared_prb_mu_peer";
end

function w = localSpatialSignature(ue)
w = [];
fields = ["MUMIMOSpatialSignature","MeasuredSpatialSignature", ...
    "SelectedPrecoder","PrecoderVector"];
for i = 1:numel(fields)
    raw = sixgr.util.structGet(ue, fields(i), []);
    if isnumeric(raw) && ~isempty(raw)
        raw = double(raw);
        if all(isfinite(real(raw(:)))) && all(isfinite(imag(raw(:)))) && ...
                norm(raw, "fro") > 0
            w = raw;
        end
        return;
    end
end
end

function groupId = localMUMIMOGroupId(slot, cursor)
groupId = 1.0e6 * max(0, round(double(slot))) + max(1, round(double(cursor)));
end

function token = localMUMIMOPrecoderType(cfg)
mode = lower(strtrim(string(sixgr.util.structGet(cfg, "phy.csi.pmiCodebookMode", ...
    sixgr.util.structGet(cfg, "phy.csi.codebookType", "type1")))));
if contains(mode, "type2") || contains(mode, "type_2")
    token = "type2_codebook";
elseif contains(mode, "noncodebook")
    token = "noncodebook";
else
    token = "type1_codebook";
end
end

function localAssertSharedMUResources(grants)
% A scheduler MU group is meaningful only when every transmitted member
% owns the exact same time-frequency opportunity.  Partial overlap cannot
% be upgraded to shared-PRB MU truth.
if numel(grants) < 2
    return;
end
referencePRBs = sort(double(grants(1).PRBSet(:)));
referenceSymbols = double(grants(1).SymbolAllocation(:).');
for index = 2:numel(grants)
    candidatePRBs = sort(double(grants(index).PRBSet(:)));
    candidateSymbols = double(grants(index).SymbolAllocation(:).');
    if ~isequal(referencePRBs, candidatePRBs) || ...
            ~isequal(referenceSymbols, candidateSymbols)
        error("sixgr:l2:mac:MUMIMOResourceContractMismatch", ...
            ['MU group members must have identical PRBSet and ' ...
            'SymbolAllocation values. Member 1 has %d PRBs/%s; member %d ' ...
            'has %d PRBs/%s.'], ...
            numel(referencePRBs), mat2str(referenceSymbols), index, ...
            numel(candidatePRBs), mat2str(candidateSymbols));
    end
end
end

function portSet = localMUMIMODMRSPortSet(cfg, direction, numLayers, memberIndex, groupSize)
% Allocate disjoint logical DM-RS ports within the immutable MU occasion.
% These are logical pilot ports, not physical antenna elements or RF chains.
direction = upper(string(direction));
numLayers = max(1, round(double(numLayers)));
memberIndex = max(1, round(double(memberIndex)));
groupSize = max(1, round(double(groupSize)));
requiredPorts = numLayers * groupSize;
if direction == "UL"
    candidates = [ ...
        double(sixgr.util.structGet(cfg, "runtime.antenna.gnb.NumRxRFChains", NaN)), ...
        double(sixgr.util.structGet(cfg, "antenna.bs.numRxRFChains", NaN)), ...
        double(sixgr.util.structGet(cfg, "scenario.bs.numRxRFChains", NaN))];
else
    candidates = [ ...
        double(sixgr.util.structGet(cfg, "runtime.antenna.gnb.NumTxRFChains", NaN)), ...
        double(sixgr.util.structGet(cfg, "antenna.bs.numTxRFChains", NaN)), ...
        double(sixgr.util.structGet(cfg, "scenario.bs.numTxRFChains", NaN))];
end
validCapacity = candidates(isfinite(candidates) & candidates >= 1);
if isempty(validCapacity)
    capacity = requiredPorts;
else
    capacity = max(validCapacity);
end
capacity = floor(double(capacity));
if capacity < requiredPorts
    error("sixgr:l2:mac:InsufficientMUDMRSPorts", ...
        ['A %s MU group with %d users and %d layers per user requires at ' ...
        'least %d logical DM-RS ports, but the runtime authority exposes %d.'], ...
        char(direction), groupSize, numLayers, requiredPorts, capacity);
end
firstPort = (memberIndex - 1) * numLayers;
portSet = firstPort:(firstPort + numLayers - 1);
end

function avg = localUEAverageThroughput(obj, rnti)
avg = 1;
stats = obj.getUEStats();
if isempty(stats)
    return;
end
idx = find([stats.RNTI] == double(rnti), 1, "first");
if isempty(idx)
    return;
end
avg = double(sixgr.util.structGet(stats(idx), "AvgThroughput_bps", 1));
if ~(isfinite(avg) && avg > 0)
    avg = 1;
end
end

function row = localCandidateRow()
row = struct( ...
    "DecisionId", "", ...
    "Slot", NaN, ...
    "Frame", NaN, ...
    "Direction", "", ...
    "CandidateIndex", NaN, ...
    "CandidateScope", "", ...
    "PFRank", NaN, ...
    "RNTI", NaN, ...
    "UEIndex", NaN, ...
    "ServingCell", NaN, ...
    "BufferBytes", NaN, ...
    "CQI", NaN, ...
    "RI", NaN, ...
    "PMI", NaN, ...
    "CRI", NaN, ...
    "EstimatedTBSBits", NaN, ...
    "EstimatedTBSBytes", NaN, ...
    "InstantRate_bps", NaN, ...
    "AvgThroughput_bps", NaN, ...
    "PFMetric", NaN, ...
    "HARQPendingRetx", false, ...
    "HARQHasFreeProcess", true, ...
    "HARQBlocked", false, ...
    "ProbePRBCount", NaN, ...
    "AllocatedPRBCount", NaN, ...
    "SymbolStart", NaN, ...
    "NumSymbols", NaN, ...
    "PDCCHAggregationLevel", NaN, ...
    "ControlCCERemainingBefore", NaN, ...
    "QueueLimited", false, ...
    "AMCMode", "", ...
    "MCSIndex", NaN, ...
    "MCSSelectionSource", "", ...
    "CQIProvenance", "", ...
    "MCSValueStatus", "", ...
    "GrantBlocker", "", ...
    "MUMIMOAdmissionEvaluated", false, ...
    "MUMIMOAdmissionPeerRNTI", NaN, ...
    "MUMIMOAdmissionCompatible", false, ...
    "MUMIMOAdmissionStatus", "not_evaluated", ...
    "MUMIMOAdmissionEvidenceSource", "", ...
    "MUMIMOAdmissionWorstLeakage_dB", NaN, ...
    "Scheduled", false, ...
    "Rejected", false, ...
    "RejectionReason", "", ...
    "GrantReason", "", ...
    "SelectedGrantIndex", NaN, ...
    "CandidateDecisionRowsAvailable", true, ...
    "DecisionTruthStatus", "runtime_scheduler_candidate_truth", ...
    "Source", "sixgr.l2.mac.SchedulerPF.schedule", ...
    "ValueRole", "runtime_scheduler_candidate_decision");
end

function T = localCandidateTable(rows)
if isempty(rows)
    rows = repmat(localCandidateRow(), 0, 1);
end
T = struct2table(rows, "AsArray", true);
end

function rows = localAssignPFRanks(rows, metrics, rowIdxByMetric)
if isempty(rows) || isempty(metrics)
    return;
end
validMetricIdx = find(isfinite(metrics(:).') & metrics(:).' > 0);
if isempty(validMetricIdx)
    return;
end
[~, ord] = sort(metrics(validMetricIdx), "descend");
rankedMetricIdx = validMetricIdx(ord);
for rankIdx = 1:numel(rankedMetricIdx)
    rowIdx = rowIdxByMetric(rankedMetricIdx(rankIdx));
    if rowIdx >= 1 && rowIdx <= numel(rows)
        rows(rowIdx).PFRank = double(rankIdx);
    end
end
end

function rows = localRecordMUMIMOAdmission(rows, rnti, peerRNTI, compatible, leakage_dB, evidenceSource, design)
if isempty(rows)
    return;
end
for i = 1:numel(rows)
    if abs(double(rows(i).RNTI) - double(rnti)) >= 1e-9 || ...
            string(rows(i).CandidateScope) ~= "new_data_pf"
        continue;
    end
    % Once a candidate has a compatible measured peer, retain that exact
    % successful admission even if the wider search later examines another
    % incompatible peer. Failed attempts remain visible until a success is
    % found; they are never silently converted into "not evaluated".
    if logical(rows(i).MUMIMOAdmissionEvaluated) && ...
            logical(rows(i).MUMIMOAdmissionCompatible) && ~logical(compatible)
        return;
    end
    status = string(sixgr.util.structGet(design, "Status", ""));
    if strlength(strtrim(status)) == 0 || status == "not_evaluated"
        status = string(evidenceSource);
    end
    rows(i).MUMIMOAdmissionEvaluated = true;
    rows(i).MUMIMOAdmissionPeerRNTI = double(peerRNTI);
    rows(i).MUMIMOAdmissionCompatible = logical(compatible);
    rows(i).MUMIMOAdmissionStatus = status;
    rows(i).MUMIMOAdmissionEvidenceSource = string(evidenceSource);
    rows(i).MUMIMOAdmissionWorstLeakage_dB = double(leakage_dB);
    return;
end
end

function rows = localMarkCandidateRejected(rows, rnti, reason)
if isempty(rows)
    return;
end
reason = localFirstNonempty(reason, "NOT_SELECTED_LOWER_PF_OR_RESOURCE_LIMIT");
for i = 1:numel(rows)
    if abs(double(rows(i).RNTI) - double(rnti)) < 1e-9 && ...
            string(rows(i).CandidateScope) == "new_data_pf" && ...
            ~logical(rows(i).Scheduled)
        rows(i).Rejected = true;
        rows(i).RejectionReason = string(reason);
        return;
    end
end
end

function rows = localMarkCandidateScheduled(rows, rnti, grant, grantIndex)
if isempty(rows)
    return;
end
for i = 1:numel(rows)
    if abs(double(rows(i).RNTI) - double(rnti)) < 1e-9 && ...
            string(rows(i).CandidateScope) == "new_data_pf"
        rows(i).Scheduled = true;
        rows(i).Rejected = false;
        rows(i).RejectionReason = "";
        rows(i).GrantReason = string(sixgr.util.structGet(grant, "GrantReason", ""));
        rows(i).SelectedGrantIndex = double(grantIndex);
        rows(i).AllocatedPRBCount = double(numel(sixgr.util.structGet(grant, "PRBSet", [])));
        rows(i).EstimatedTBSBits = double(sixgr.util.structGet(grant, "TBSBits", rows(i).EstimatedTBSBits));
        rows(i).EstimatedTBSBytes = double(sixgr.util.structGet(grant, "TBSBytes", rows(i).EstimatedTBSBytes));
        rows(i).MCSIndex = double(sixgr.util.structGet(grant, "MCSIndex", rows(i).MCSIndex));
        rows(i).DecisionTruthStatus = "runtime_scheduler_selected_candidate_truth";
        return;
    end
end
end

function rows = localFinalizeCandidateRejections(rows, defaultReason)
if isempty(rows)
    return;
end
defaultReason = localFirstNonempty(defaultReason, "NOT_SELECTED_LOWER_PF_OR_RESOURCE_LIMIT");
for i = 1:numel(rows)
    if ~logical(rows(i).Scheduled) && ~logical(rows(i).Rejected)
        rows(i).Rejected = true;
        rows(i).RejectionReason = string(defaultReason);
    end
end
end

function localDecayUnscheduledCandidates(obj, ueStates, ueIdx, grants)
if isempty(ueIdx)
    return;
end
scheduledRNTI = zeros(1, 0);
if isstruct(grants) && ~isempty(grants) && isfield(grants, "RNTI")
    scheduledRNTI = double([grants.RNTI]);
end
for i = 1:numel(ueIdx)
    k = ueIdx(i);
    if k < 1 || k > numel(ueStates) || ~isfield(ueStates(k), "RNTI")
        continue;
    end
    rnti = double(ueStates(k).RNTI);
    if any(abs(scheduledRNTI - rnti) < 1e-9)
        continue;
    end
    obj.markUnscheduled(rnti);
end
end

function out = localFirstNonempty(value, fallback)
out = string(value);
if isempty(out) || strlength(strtrim(out(1))) == 0
    out = string(fallback);
else
    out = out(1);
end
end

function out = localTernary(cond, yesVal, noVal)
if logical(cond)
    out = yesVal;
else
    out = noVal;
end
end
