classdef SchedulerRR < sixgr.l2.mac.SchedulerBase
% sixgr.l2.mac.SchedulerRR
% Round-robin scheduler (very simple baseline).
%
% Behavior
%  - Prioritizes HARQ retransmissions if a HARQ entity is attached.
%  - Otherwise, allocates PRBs across active UEs in a cyclic order.
%  - Uses fixed modulation/code rate defaults from cfg unless overridden
%    by UE state.
%
% This is intended as a stable baseline for unit tests and for isolating
% PHY issues from scheduling heuristics.

    properties
        NextUE (1,1) double = 1       % next UE index in rr list
        MaxUEPerSlot (1,1) double = inf
        MinPRBPerUE (1,1) double = 4  % keep allocations non-trivial
        MaxPRBPerUE (1,1) double = inf
        SearchSpaceID (1,1) double = 0
        CORESETID (1,1) double = 0
    end

    methods
        function obj = SchedulerRR(cfg, varargin)
            obj@sixgr.l2.mac.SchedulerBase(cfg, varargin{:});
            obj.MaxUEPerSlot = double(sixgr.util.structGet(cfg,"mac.scheduler.maxUEPerSlot", ...
                sixgr.util.structGet(cfg,"system.scheduler.maxActiveUEsPerSlot",obj.MaxUEPerSlot)));
            obj.MinPRBPerUE = double(sixgr.util.structGet(cfg,"mac.scheduler.minPRBPerUE",obj.MinPRBPerUE));
            obj.MaxPRBPerUE = double(sixgr.util.structGet(cfg,"mac.scheduler.maxPRBAllocationPerUE", ...
                sixgr.util.structGet(cfg,"system.scheduler.maxPRBAllocationPerUE",obj.MaxPRBPerUE)));
            obj.SearchSpaceID = max(0, round(double(sixgr.util.structGet(cfg, ...
                "phy.pdcch.searchSpace.id", ...
                sixgr.util.structGet(cfg, "phy.dl.pdcch.SearchSpaceID", 1)))));
            obj.CORESETID = max(0, round(double(sixgr.util.structGet(cfg, ...
                "phy.pdcch.coreset.id", ...
                sixgr.util.structGet(cfg, "phy.dl.pdcch.CORESETID", obj.CORESETID)))));
        end

        function [grants, info] = schedule(obj, slot, ueStates, budget)
            if nargin < 4
                budget = struct();
            end
            [prbAvail, symAlloc] = obj.defaultBudget(budget);
            controlAbsoluteSlot = localBudgetControlAbsoluteSlot(budget);
            controlSymbolAllocation = ...
                localBudgetControlSymbolAllocation(budget);

            tmpl = localGrantTemplate(obj.Direction, slot);
            grants = repmat(tmpl, 0, 1);
            info = struct();
            info.Slot = slot;
            info.Direction = obj.Direction;
            info.SchedulerClass = string(class(obj));
            info.HARQDeferrals = table();
            info.ResourceExclusions = table();
            nPRBAvail = numel(prbAvail);
            info.NPRBAvail = nPRBAvail;
            ssid = obj.SearchSpaceID;
            coreset = obj.CORESETID;

            if isempty(ueStates)
                return;
            end

            % Active UEs based on buffers
            nUEState = numel(ueStates);
            act = false(1, nUEState);
            isDL = strcmpi(obj.Direction, 'DL');
            for k = 1:nUEState
                if ~isfield(ueStates(k),'RNTI') || isempty(ueStates(k).RNTI)
                    continue;
                end
                if isDL
                    if isfield(ueStates(k),'DLBufferBytes')
                        b = double(ueStates(k).DLBufferBytes);
                        act(k) = isfinite(b) && (b > 0);
                    end
                else
                    if isfield(ueStates(k),'ULBufferBytes')
                        b = double(ueStates(k).ULBufferBytes);
                        act(k) = isfinite(b) && (b > 0);
                    end
                end
            end
            ueIdx = find(act);
            if isempty(ueIdx)
                return;
            end

            % Cap number of UEs per slot if configured
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
            grants = repmat(tmpl, 0, 1);
            nGrant = 0;
            cursor = 1;
            hasHARQ = ~isempty(obj.HARQ);
            pendingRetx = false(1, nUEState);

            % --- 1) Schedule HARQ retransmissions first (if any) ---
            if hasHARQ
                for t = 1:numel(ueIdx)
                    k = ueIdx(t);
                    rnti = double(ueStates(k).RNTI);
                    pendingRetx(k) = obj.HARQ.hasPendingRetx(rnti, slot);
                    if ~pendingRetx(k)
                        continue;
                    end
                    retx = obj.HARQ.peekRetx(rnti, slot);
                    if isempty(retx) || cursor > nPRBAvail
                        continue;
                    end
                    neededCCE = localUEPDCCHCCE(ueStates(k), budget);
                    if controlBudgetActive && neededCCE > controlCCERemaining
                        continue;
                    end
                    g = localNormalizeGrant(retx.LastGrant, tmpl, obj.Direction, slot);
                    [fitsBudget, deferral] = sixgr.l2.mac.harqRetransmissionFitsSymbolBudget(g, symAlloc);
                    if ~fitsBudget
                        info.HARQDeferrals = [info.HARQDeferrals; deferral];
                        continue;
                    end

                    nNeed = numel(g.PRBSet);
                    if nNeed <= 0
                        nNeed = max(1, round(double(sixgr.util.structGet(g, "NPRB", ...
                            sixgr.util.structGet(g, "PRBCount", sixgr.util.structGet(g, "NumPRB", obj.MinPRBPerUE))))));
                    end
                    % Retx must preserve enough PRBs to carry the stored TB honestly.
                    if nNeed <= 0 || (nPRBAvail - cursor + 1) < nNeed
                        continue;
                    end
                    retxIntent=g; retxIntent.HARQ=retx.HARQ;
                    [retxAvailable,excluded]=obj.ssbSafePRBSet(slot,budget, ...
                        prbAvail(cursor:end),g.SymbolAllocation,retxIntent);
                    info.ResourceExclusions=[info.ResourceExclusions;excluded];
                    [retxPRBs,~]=sixgr.l2.mac.contiguousPRBChunk(retxAvailable,1,nNeed,nNeed);
                    if isempty(retxPRBs)
                        info.HARQDeferrals=[info.HARQDeferrals; ...
                            sixgr.l2.mac.harqPRBDeferral(g,retxAvailable,symAlloc)];
                        continue;
                    end
                    g.PRBSet=retxPRBs;
                    % Keep all unallocated islands available for subsequent
                    % grants; moving a cursor would lose preceding holes.
                    prbAvail=setdiff(prbAvail,retxPRBs,'stable');
                    nPRBAvail=numel(prbAvail); cursor=1;

                    % Refresh slot + HARQ fields
                    g.Slot = slot;
                    if ~isempty(controlAbsoluteSlot)
                        g.ControlAbsoluteSlot = controlAbsoluteSlot;
                    end
                    if ~isempty(controlSymbolAllocation)
                        g.ControlSymbolAllocation = ...
                            controlSymbolAllocation;
                    end
                    g.Direction = obj.Direction;
                    if ~isfield(g, "MCSTable") || strlength(string(g.MCSTable)) == 0
                        g.MCSTable = obj.resolveMCSTable();
                    end
                    g.HARQ = retx.HARQ;
                    g.CQIUsed = double(sixgr.util.structGet(g, "CQIUsed", localUECQI(ueStates(k))));
                    g.PDCCHAggregationLevel = double(neededCCE);
                    g.DAI = 1;
                    g.SearchSpaceID = ssid;
                    g.CORESETID = coreset;
                    g.HeadOfLineDelay_ms = localUEHoLDelay(ueStates(k));
                    g.BufferBytesBefore = localUEBufferByFlag(ueStates(k), isDL);
                    if ~isfinite(g.BufferBytesBefore)
                        g.BufferBytesBefore = 0;
                    end
                    [g.TBSBits, ~] = sixgr.util.resolveGrantTBSBits(g, ...
                        sprintf("%s HARQ retransmission RNTI=%d process=%d", ...
                        class(obj), round(double(g.RNTI)), ...
                        round(double(sixgr.util.structGet(g, "HARQ.HarqID", -1)))));
                    if g.TBSBits <= 0
                        error("sixgr:SchedulerRR:MissingRetransmissionTBS", ...
                            "HARQ retransmission RNTI=%d has no positive frozen TBS.", ...
                            round(double(g.RNTI)));
                    end
                    g.TBSBytes = g.TBSBits / 8;
                    g.BufferBytesAfter = max(g.BufferBytesBefore - double(g.TBSBytes), 0);
                    g.GrantReason = "harq_retx";
                    g = obj.attachULSRSAuthorityToGrant(g, ueStates(k));
                    g = sixgr.l2.mac.attachReceivedULTimingAuthority(g,ueStates(k));
                    g = obj.freezePHYGrantForGrant(g);
                    g.DCI = obj.buildDCIBitfield(g);

                    grants = localAppendGrant(grants, g);
                    nGrant = numel(grants);
                    if controlBudgetActive
                        controlCCERemaining = max(0, controlCCERemaining - neededCCE);
                    end

                    if cursor > nPRBAvail
                        break;
                    end
                end
            end

            % Remaining active UEs (including ones with retx pending may still get new data if PRBs allow)
            if cursor > nPRBAvail
                grants = grants(1:nGrant);
                info.NGrants = numel(grants);
                info.PRBUnderuse = 0;
                return;
            end

            % --- 2) Round-robin new-data grants ---
            [prbAvail,excluded]=obj.ssbSafePRBSet(slot,budget,prbAvail,symAlloc);
            info.ResourceExclusions=[info.ResourceExclusions;excluded];
            nPRBAvail=numel(prbAvail);
            rrList = ueIdx(:).';
            nUE = numel(rrList);
            start = obj.NextUE;
            if start < 1 || start > nUE
                start = 1;
            end

            % Build cyclic order
            order = [rrList(start:end) rrList(1:start-1)];
            order = order(1:maxUE);

            % PRB chunking
            nPRBRemain = nPRBAvail - cursor + 1;
            prbPerUE = floor(nPRBRemain / max(numel(order), 1));
            prbPerUE = max(prbPerUE, obj.MinPRBPerUE);
            if isfinite(obj.MaxPRBPerUE) && obj.MaxPRBPerUE > 0
                prbPerUE = min(prbPerUE, floor(obj.MaxPRBPerUE));
            end
            prbPerUE = max(prbPerUE, 1);
            servedRNTI = zeros(numel(order), 1);
            servedCount = 0;
            for t = 1:numel(order)
                k = order(t);
                if cursor > nPRBAvail
                    break;
                end

                % If HARQ has pending retx for this UE, skip new-data allocation (retx already handled above)
                rnti = double(ueStates(k).RNTI);
                if hasHARQ && pendingRetx(k)
                    continue;
                end
                if hasHARQ && ~obj.HARQ.hasFreeProcess(rnti, slot)
                    continue;
                end

                [candidatePRBSet,chunkStart]=sixgr.l2.mac.contiguousPRBChunk( ...
                    prbAvail,cursor,prbPerUE,obj.MinPRBPerUE);
                if isempty(candidatePRBSet)
                    break;
                end

                bufB = localUEBufferByFlag(ueStates(k), isDL);
                neededCCE = localUEPDCCHCCE(ueStates(k), budget);
                if controlBudgetActive && neededCCE > controlCCERemaining
                    continue;
                end
                plan = obj.buildNewDataGrantPlan(ueStates(k), candidatePRBSet, symAlloc, bufB);
                if ~plan.Valid || plan.TBSBits <= 0 || plan.TBSBytes <= 0
                    continue;
                end
                prbSet = double(plan.PRBSet(:).');
                cursor = chunkStart + numel(prbSet);
                servedBytes = double(plan.TBSBytes);

                % HARQ allocation (new data)
                harqInfo = struct('HarqID',[],'NDI',[],'RV',[],'IsRetransmission',false);
                if hasHARQ
                    txp = obj.HARQ.allocate(rnti, slot, servedBytes, 'NewData', true);
                    if logical(sixgr.util.structGet(txp, "NoFreeProcess", false))
                        continue;
                    end
                    harqInfo = txp.HARQ;
                end

                g = tmpl;
                g.Direction = obj.Direction;
                g.Slot = slot;
                if ~isempty(controlAbsoluteSlot)
                    g.ControlAbsoluteSlot = controlAbsoluteSlot;
                end
                if ~isempty(controlSymbolAllocation)
                    g.ControlSymbolAllocation = controlSymbolAllocation;
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
                g.RankSelectionPolicy = char(string(sixgr.util.structGet(plan, "RankSelectionPolicy", "")));
                g.ConfiguredLayers = double(sixgr.util.structGet(plan, "ConfiguredLayers", NaN));
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
                g.CQIUsed = localUECQI(ueStates(k));
                g.PDCCHAggregationLevel = double(neededCCE);
                g.ReportedRI = double(sixgr.util.structGet(ueStates(k), "RI", NaN));
                g.RI = double(plan.NumLayers);
                g.RIUsed = double(plan.NumLayers);
                g.Rank = double(plan.NumLayers);
                g.RankIndicator = double(plan.NumLayers);
                g.MCSIndex = double(plan.MCSIndex);
                g.DAI = 1;
                g.SearchSpaceID = ssid;
                g.CORESETID = coreset;
                g.HeadOfLineDelay_ms = localUEHoLDelay(ueStates(k));
                g.BufferBytesBefore = localUEBufferByFlag(ueStates(k), isDL);
                if ~isfinite(g.BufferBytesBefore)
                    g.BufferBytesBefore = 0;
                end
                g.BufferBytesAfter = max(g.BufferBytesBefore - double(servedBytes), 0);
                g.GrantReason = "new_data_rr";
                [g.TBSBits, ~] = sixgr.util.resolveGrantTBSBits(g, ...
                    sprintf("%s new_data_rr RNTI=%d", class(obj), round(rnti)));
                g.TBSBytes = g.TBSBits / 8;
                g = obj.attachULSRSAuthorityToGrant(g, ueStates(k));
                g = sixgr.l2.mac.attachReceivedULTimingAuthority(g,ueStates(k));
                g = obj.freezePHYGrantForGrant(g);
                g.DCI = obj.buildDCIBitfield(g);

                grants = localAppendGrant(grants, g);
                nGrant = numel(grants);
                if controlBudgetActive
                    controlCCERemaining = max(0, controlCCERemaining - neededCCE);
                end

                servedCount = servedCount + 1;
                servedRNTI(servedCount) = rnti;
            end
            if servedCount > 0
                ur = unique(servedRNTI(1:servedCount));
                for ii = 1:numel(ur)
                    iUE = obj.ensureUE(ur(ii));
                    obj.UEStats(iUE).LastServedSlot = slot;
                end
            end

            % Update next UE pointer
            obj.NextUE = start + 1;
            if obj.NextUE > nUE
                obj.NextUE = 1;
            end

            grants = grants(1:nGrant);
            info.NGrants = numel(grants);
            info.PRBUnderuse = numel(setdiff(prbAvail,[grants.PRBSet]));
        end
    end
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
% Runtime link-adaptation lineage is part of every grant's schema.  A
% scalar false/NaN value means "not applied"; an empty value is malformed
% and must never be introduced while aligning grants from different UEs.
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
g.ConfiguredLayers = NaN;
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
g.GrantReason = "new_data_rr";
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
        % Numeric zero is frequently a valid grant value. Schema alignment
        % must preserve absence instead of manufacturing a measured or
        % configured zero for another UE's grant.
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
cqi = sixgr.l2.mac.SchedulerBase.sanitizeCQI( ...
    sixgr.util.structGet(ue, "CQI", NaN), 1);
end

function value = localBudgetControlAbsoluteSlot(budget)
value = [];
if isstruct(budget) && isscalar(budget) && ...
        isfield(budget, "ControlAbsoluteSlot") && ...
        ~isempty(budget.ControlAbsoluteSlot)
    raw = double(budget.ControlAbsoluteSlot);
    if ~(isscalar(raw) && isfinite(raw) && raw >= 0 && raw == fix(raw))
        error("sixgr:SchedulerRR:InvalidControlAbsoluteSlot", ...
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
        error("sixgr:SchedulerRR:InvalidControlSymbolAllocation", ...
            "budget.ControlSymbolAllocation must be [start>=0 count>=1].");
    end
    value = raw;
end
end

function hol = localUEHoLDelay(ue)
hol = 0;
if isfield(ue, "HeadOfLineDelay_ms") && ~isempty(ue.HeadOfLineDelay_ms)
    hol = double(ue.HeadOfLineDelay_ms);
end
if ~isfinite(hol) || hol < 0
    hol = 0;
end
end

function b = localUEBufferByFlag(ue, isDL)
if logical(isDL)
    if isfield(ue, "DLBufferBytes") && ~isempty(ue.DLBufferBytes)
        b = double(ue.DLBufferBytes);
    else
        b = inf;
    end
else
    if isfield(ue, "ULBufferBytes") && ~isempty(ue.ULBufferBytes)
        b = double(ue.ULBufferBytes);
    else
        b = inf;
    end
end
if ~isfinite(b)
    b = inf;
elseif b < 0
    b = 0;
end
end
