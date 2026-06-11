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
            profScope = sixgr.perf.TimeProfiler.scope("sixgr.l2.mac.SchedulerPF.schedule", ...
                "Stage", "mac_pf_scheduler", ...
                "Metadata", struct("NumUE", double(numel(ueStates)), ...
                "NumPRB", double(numel(prbAvail)))); %#ok<NASGU>

            tmpl = localGrantTemplate(obj.Direction, slot);
            grants = repmat(tmpl, 0, 1);
            info = struct();
            info.Slot = slot;
            info.Direction = obj.Direction;
            k1 = max(1, round(double(sixgr.util.structGet(obj.Cfg, "mac.harq.k1", 4))));
            k2 = max(0, round(double(sixgr.util.structGet(obj.Cfg, "mac.harq.k2", 1))));
            ssid = max(0, round(double(sixgr.util.structGet(obj.Cfg, "phy.dl.pdcch.SearchSpaceID", 0))));
            coreset = max(0, round(double(sixgr.util.structGet(obj.Cfg, "phy.dl.pdcch.CORESETID", 0))));
            bwpId = max(0, round(double(sixgr.util.structGet(obj.Cfg, "phy.bwp.id", 0))));

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

            % ------------------ 1) HARQ retransmissions first ------------------
            if ~isempty(obj.HARQ)
                for t = 1:numel(ueIdx)
                    k = ueIdx(t);
                    rnti = double(ueStates(k).RNTI);
                    if obj.HARQ.hasPendingRetx(rnti)
                        retx = obj.HARQ.peekRetx(rnti);
                        if isempty(retx)
                            continue;
                        end
                        neededCCE = localUEPDCCHCCE(ueStates(k), budget);
                        if controlBudgetActive && neededCCE > controlCCERemaining
                            continue;
                        end
                        g = localNormalizeGrant(retx.LastGrant, tmpl, obj.Direction, slot);
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
                        if ~all(ismember(g.PRBSet, prbAvail))
                            g.PRBSet = prbAvail(1:nNeed);
                        end
                        prbAvail = setdiff(prbAvail, g.PRBSet, 'stable');

                        g.Slot = slot;
                        g.Direction = obj.Direction;
                        if ~isfield(g, "MCSTable") || strlength(string(g.MCSTable)) == 0
                            g.MCSTable = obj.resolveMCSTable();
                        end
                        g.HARQ = retx.HARQ;
                        g.CQIUsed = double(sixgr.util.structGet(g, "CQIUsed", localUECQI(ueStates(k))));
                        g.PDCCHAggregationLevel = double(neededCCE);
                        g.DAI = 1;
                        g.K1 = k1;
                        g.K2 = k2;
                        g.SearchSpaceID = ssid;
                        g.CORESETID = coreset;
                        g.BWPId = bwpId;
                        g.HeadOfLineDelay_ms = localUEHoLDelay(ueStates(k));
                        g.BufferBytesBefore = bufBytes(k);
                        g.TBSBits = double(sixgr.util.structGet(g, "TBSBits", sixgr.util.structGet(g, "TransportBlockSize", 0)));
                        g.TBSBytes = floor(max(g.TBSBits, 0) / 8);
                        g.BufferBytesAfter = max(bufBytes(k) - double(g.TBSBytes), 0);
                        g.GrantReason = "harq_retx";
                        g.DCI = obj.buildDCIBitfield(g);
                        grants(end+1) = g; %#ok<AGROW>
                        if controlBudgetActive
                            controlCCERemaining = max(0, controlCCERemaining - neededCCE);
                        end
                    end
                end
            end

            if isempty(prbAvail)
                info.NGrants = numel(grants);
                return;
            end

            % ------------------ 2) PF scheduling for new data ------------------
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
            probeTimer = tic;
            probePlanElapsed_s = zeros(1, numel(ueIdx));
            for t = 1:numel(ueIdx)
                k = ueIdx(t);
                rnti = double(ueStates(k).RNTI);

                % Skip if HARQ already pending retx (handled earlier)
                if ~isempty(obj.HARQ) && obj.HARQ.hasPendingRetx(rnti)
                    continue;
                end
                if ~isempty(obj.HARQ) && ~obj.HARQ.hasFreeProcess(rnti)
                    continue;
                end

                probePRBSet = prbAvail(1:min(probeChunk, numel(prbAvail)));
                probePlanTimer = tic;
                plan = obj.buildNewDataGrantPlan(ueStates(k), probePRBSet, symAlloc, bufBytes(k), ...
                    "PlanningOnly", true);
                probePlanElapsed_s(t) = toc(probePlanTimer);
                estTBS(t) = double(sixgr.util.structGet(plan, "TBSBits", 0));
                metrics(t) = obj.pfMetric(ueStates(k), estTBS(t));
            end
            probeElapsed_s = toc(probeTimer);

            % Sort UEs by PF metric descending
            [~, ord] = sort(metrics, 'descend');
            ord = ord(metrics(ord) > 0);
            if isempty(ord)
                info.NGrants = numel(grants);
                return;
            end
            ord = ord(1:min(numel(ord), maxUE));

            cursor = 1;
            muEnabled = localMUMIMOEnabled(obj.Cfg, obj.Direction);
            muMaxUsers = localMUMIMOMaxUsers(obj.Cfg);
            usedOrd = false(1, numel(ord));
            allocTimer = tic;
            finalPlanElapsed_s = zeros(1, numel(ord));
            for ii = 1:numel(ord)
                if usedOrd(ii)
                    continue;
                end
                if cursor > numel(prbAvail)
                    break;
                end
                nAlloc = min(prbChunk, numel(prbAvail)-cursor+1);
                if nAlloc < obj.MinPRBPerUE
                    break;
                end
                candidatePRBSet = prbAvail(cursor:(cursor+nAlloc-1));
                groupOrd = ord(ii);
                if muEnabled
                    for jj = (ii + 1):numel(ord)
                        if usedOrd(jj) || numel(groupOrd) >= muMaxUsers
                            continue;
                        end
                        if localMUMIMOCompatible(ueStates(ueIdx(groupOrd(1))), ueStates(ueIdx(ord(jj))), obj.Cfg)
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
                    if ~isempty(obj.HARQ) && obj.HARQ.hasPendingRetx(rnti)
                        continue;
                    end
                    if ~isempty(obj.HARQ) && ~obj.HARQ.hasFreeProcess(rnti)
                        continue;
                    end
                    neededCCE = localUEPDCCHCCE(ueStates(k), budget);
                    if controlBudgetActive && neededCCE > max(0, controlCCERemaining - groupCCEUsed)
                        continue;
                    end
                    finalPlanTimer = tic;
                    plan = obj.buildNewDataGrantPlan(ueStates(k), candidatePRBSet, symAlloc, bufBytes(k));
                    finalPlanElapsed_s(ii) = finalPlanElapsed_s(ii) + toc(finalPlanTimer);
                    if ~plan.Valid || plan.TBSBits <= 0 || plan.TBSBytes <= 0
                        continue;
                    end
                    prbSet = double(plan.PRBSet(:).');
                    servedBytes = double(plan.TBSBytes);

                    harqInfo = struct('HarqID',[],'NDI',[],'RV',[],'IsRetransmission',false);
                    if ~isempty(obj.HARQ)
                        txp = obj.HARQ.allocate(rnti, slot, servedBytes, 'NewData', true);
                        if logical(sixgr.util.structGet(txp, "NoFreeProcess", false))
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
                    g.RNTI = rnti;
                    g.PRBSet = prbSet;
                    g.SymbolAllocation = symAlloc;
                    g.Modulation = char(string(plan.Modulation));
                    g.NumLayers = double(plan.NumLayers);
                    g.TargetCodeRate = double(plan.TargetCodeRate);
                    g.TBSBits = double(plan.TBSBits);
                    g.TBSBytes = double(plan.TBSBytes);
                    g.EstimatedTBSBits = double(plan.RawEstimatedTBSBits);
                    g.EstimatedTBSBytes = double(plan.RawEstimatedTBSBytes);
                    g.NREPerPRB = double(plan.NREPerPRB);
                    g.MCSTable = char(string(plan.MCSTable));
                    g.CQITable = char(string(plan.CQITable));
                    g.AMCMode = char(string(plan.AMCMode));
                    g.OuterLoopEnabled = logical(sixgr.util.structGet(plan, "OuterLoopEnabled", false));
                    g.OuterLoopApplied = logical(sixgr.util.structGet(plan, "OuterLoopApplied", false));
                    g.OLLADeltaMCS = double(sixgr.util.structGet(plan, "OLLADeltaMCS", 0));
                    g.OLLAUpdateCount = double(sixgr.util.structGet(plan, "OLLAUpdateCount", 0));
                    g.OLLAState = char(string(sixgr.util.structGet(plan, "OLLAState", "")));
                    g.QueueLimited = logical(plan.QueueLimited);
                    g.QueuePaddingBits = double(sixgr.util.structGet(plan, "QueuePaddingBits", 0));
                    g.QueuePaddingBytes = double(sixgr.util.structGet(plan, "QueuePaddingBytes", 0));
                    g.HARQ = harqInfo;
                    g.CQIUsed = localUECQI(ueStates(k));
                    g.PDCCHAggregationLevel = double(neededCCE);
                    g.RIUsed = double(sixgr.util.structGet(ueStates(k), "RI", NaN));
                    g.PMI = double(sixgr.util.structGet(ueStates(k), "PMI", NaN));
                    g.CRI = double(sixgr.util.structGet(ueStates(k), "CRI", NaN));
                    g.MCSIndex = double(plan.MCSIndex);
                    g.DAI = 1;
                    g.K1 = k1;
                    g.K2 = k2;
                    g.SearchSpaceID = ssid;
                    g.CORESETID = coreset;
                    g.BWPId = bwpId;
                    g.HeadOfLineDelay_ms = localUEHoLDelay(ueStates(k));
                    g.BufferBytesBefore = bufBytes(k);
                    g.BufferBytesAfter = max(bufBytes(k) - double(servedBytes), 0);
                    g.GrantReason = localTernary(muEnabled && numel(groupOrd) > 1, "new_data_pf_mu_mimo", "new_data_pf");
                    g.MUMIMOEnabled = logical(muEnabled);
                    g.MUMIMOGroupSize = double(numel(groupOrd));
                    g.MUMIMOGroupId = double(localMUMIMOGroupId(slot, cursor));
                    g.MUMIMOPairingStatus = char(localTernary(muEnabled && numel(groupOrd) > 1, "paired_shared_prb_spatial_multiplexing", "single_user_or_mu_disabled"));
                    g.MUMIMOPairingMetricSource = "pf_order_cqi_ri_pmi_orthogonality";
                    g.MUMIMOPrecoderType = char(localMUMIMOPrecoderType(obj.Cfg));
                    [g.TBSBits, ~] = sixgr.util.resolveGrantTBSBits(g, ...
                        sprintf("%s %s RNTI=%d", class(obj), char(g.GrantReason), round(rnti)));
                    g.TBSBytes = g.TBSBits / 8;
                    g.DCI = obj.buildDCIBitfield(g);
                    groupGrants(end+1) = g; %#ok<AGROW>
                    groupValid(gg) = true;
                    if controlBudgetActive
                        groupCCEUsed = groupCCEUsed + neededCCE;
                    end
                end
                if isempty(groupGrants)
                    usedOrd(ii) = true;
                    continue;
                end
                cursor = cursor + max(1, numel(prbSetForGroup));
                usedOrd(ii) = true;
                usedOrd(ismember(ord, groupOrd(groupValid))) = true;
                if controlBudgetActive
                    controlCCERemaining = max(0, controlCCERemaining - groupCCEUsed);
                end
                for gg = 1:numel(groupGrants)
                    grants(end+1) = groupGrants(gg); %#ok<AGROW>
                    rnti = double(groupGrants(gg).RNTI);
                    obj.ensureUE(rnti);
                    obj.UEStats(obj.ensureUE(rnti)).LastServedSlot = slot;
                end
            end
            allocElapsed_s = toc(allocTimer);

            info.NGrants = numel(grants);
            info.PRBUnderuse = numel(prbAvail) - max(0, cursor-1);
            info.ProbeElapsed_s = probeElapsed_s;
            info.AllocationElapsed_s = allocElapsed_s;
            info.ScheduleElapsed_s = toc(scheduleTimer);
            info.ProbePlanTotalElapsed_s = sum(probePlanElapsed_s);
            info.ProbePlanMaxElapsed_s = max([0 probePlanElapsed_s]);
            info.FinalPlanTotalElapsed_s = sum(finalPlanElapsed_s);
            info.FinalPlanMaxElapsed_s = max([0 finalPlanElapsed_s]);
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
end

function g = localGrantTemplate(direction, slot)
g = struct();
g.Direction = char(string(direction));
g.Slot = double(slot);
g.RNTI = 0;
g.PRBSet = zeros(1,0);
g.SymbolAllocation = [NaN NaN];
g.Modulation = 'QPSK';
g.NumLayers = 1;
g.TargetCodeRate = 0.5;
g.TBSBits = 0;
g.TBSBytes = 0;
g.EstimatedTBSBits = 0;
g.EstimatedTBSBytes = 0;
g.NREPerPRB = 0;
g.MCSTable = 'qam64_table1';
g.CQITable = 'table1';
g.AMCMode = 'fixed_modulation';
g.OuterLoopEnabled = false;
g.OuterLoopApplied = false;
g.OLLADeltaMCS = 0;
g.OLLAUpdateCount = 0;
g.OLLAState = "";
g.QueueLimited = false;
g.QueuePaddingBits = 0;
g.QueuePaddingBytes = 0;
g.HARQ = struct('HarqID',[],'NDI',[],'RV',[],'IsRetransmission',false);
g.MCSIndex = 0;
g.CQIUsed = 0;
g.PDCCHAggregationLevel = NaN;
g.RIUsed = NaN;
g.PMI = NaN;
g.CRI = NaN;
g.DAI = 1;
g.K1 = 4;
g.K2 = 1;
g.SearchSpaceID = 0;
g.CORESETID = 0;
g.BWPId = 0;
g.HeadOfLineDelay_ms = 0;
g.BufferBytesBefore = 0;
g.BufferBytesAfter = 0;
g.GrantReason = "new_data_pf";
g.MUMIMOEnabled = false;
g.MUMIMOGroupSize = 1;
g.MUMIMOGroupId = NaN;
g.MUMIMOPairingStatus = "";
g.MUMIMOPairingMetricSource = "";
g.MUMIMOPrecoderType = "";
g.DCI = struct("Format","","Bits",uint8([]),"Hex","","FieldMap",struct(),"FieldValues",struct(), ...
    "RIV",0,"RBStart",0,"RBLength",0,"SLIV",NaN,"TimeDomainAssignmentIndex",NaN, ...
    "StandardProfile","","BitExactPDCCHPayload",false,"BitLength",0, ...
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
    f = fieldnames(g);
    for i = 1:numel(f)
        if isfield(gIn, f{i})
            g.(f{i}) = gIn.(f{i});
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
    sixgr.util.structGet(ue, "CQI", NaN), 0);
end

function hol = localUEHoLDelay(ue)
hol = double(sixgr.util.structGet(ue, "HeadOfLineDelay_ms", 0));
if ~isfinite(hol) || hol < 0
    hol = 0;
end
end

function tf = localMUMIMOEnabled(cfg, direction)
direction = upper(string(direction));
tf = logical(sixgr.util.structGet(cfg, "mac.scheduler.muMimoEnabled", ...
    sixgr.util.structGet(cfg, "phy.mimo.muMimoEnabled", ...
    sixgr.util.structGet(cfg, "mimo.mu_mimo_enable", false))));
if direction ~= "DL"
    tf = tf && logical(sixgr.util.structGet(cfg, "mac.scheduler.ulMuMimoEnabled", ...
        sixgr.util.structGet(cfg, "phy.mimo.ulMuMimoEnabled", false)));
end
end

function n = localMUMIMOMaxUsers(cfg)
n = double(sixgr.util.structGet(cfg, "mac.scheduler.muMimoMaxUsersPerPRB", ...
    sixgr.util.structGet(cfg, "phy.mimo.muMimoMaxUsersPerPRB", 2)));
if ~(isscalar(n) && isfinite(n) && n >= 2)
    n = 2;
end
n = max(2, min(4, round(n)));
end

function tf = localMUMIMOCompatible(ueA, ueB, cfg)
cqiA = localUECQI(ueA);
cqiB = localUECQI(ueB);
if min(cqiA, cqiB) <= 0
    tf = false;
    return;
end
maxDeltaCQI = double(sixgr.util.structGet(cfg, "mac.scheduler.muMimoMaxCQIDelta", 4));
if abs(cqiA - cqiB) > maxDeltaCQI
    tf = false;
    return;
end
riA = double(sixgr.util.structGet(ueA, "RI", 1));
riB = double(sixgr.util.structGet(ueB, "RI", 1));
if ~(isfinite(riA) && isfinite(riB) && riA >= 1 && riB >= 1)
    tf = false;
    return;
end
pmiA = double(sixgr.util.structGet(ueA, "PMI", NaN));
pmiB = double(sixgr.util.structGet(ueB, "PMI", NaN));
if isfinite(pmiA) && isfinite(pmiB)
    tf = round(pmiA) ~= round(pmiB);
else
    sinrA = double(sixgr.util.structGet(ueA, "MeasuredSINR_dB", NaN));
    sinrB = double(sixgr.util.structGet(ueB, "MeasuredSINR_dB", NaN));
    tf = isfinite(sinrA) && isfinite(sinrB) && abs(sinrA - sinrB) <= 6;
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

function out = localTernary(cond, yesVal, noVal)
if logical(cond)
    out = yesVal;
else
    out = noVal;
end
end
