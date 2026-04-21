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
        HarqK1 (1,1) double = 4
        HarqK2 (1,1) double = 1
        SearchSpaceID (1,1) double = 0
        CORESETID (1,1) double = 0
        BWPId (1,1) double = 0
    end

    methods
        function obj = SchedulerRR(cfg, varargin)
            obj@sixgr.l2.mac.SchedulerBase(cfg, varargin{:});
            obj.MaxUEPerSlot = double(sixgr.util.structGet(cfg,"mac.scheduler.maxUEPerSlot", ...
                sixgr.util.structGet(cfg,"system.scheduler.maxActiveUEsPerSlot",obj.MaxUEPerSlot)));
            obj.MinPRBPerUE = double(sixgr.util.structGet(cfg,"mac.scheduler.minPRBPerUE",obj.MinPRBPerUE));
            obj.MaxPRBPerUE = double(sixgr.util.structGet(cfg,"mac.scheduler.maxPRBAllocationPerUE", ...
                sixgr.util.structGet(cfg,"system.scheduler.maxPRBAllocationPerUE",obj.MaxPRBPerUE)));
            obj.HarqK1 = max(0, round(double(sixgr.util.structGet(cfg, "mac.harq.k1", obj.HarqK1))));
            obj.HarqK2 = max(0, round(double(sixgr.util.structGet(cfg, "mac.harq.k2", obj.HarqK2))));
            obj.SearchSpaceID = max(0, round(double(sixgr.util.structGet(cfg, "phy.dl.pdcch.SearchSpaceID", obj.SearchSpaceID))));
            obj.CORESETID = max(0, round(double(sixgr.util.structGet(cfg, "phy.dl.pdcch.CORESETID", obj.CORESETID))));
            obj.BWPId = max(0, round(double(sixgr.util.structGet(cfg, "phy.bwp.id", obj.BWPId))));
        end

        function [grants, info] = schedule(obj, slot, ueStates, budget)
            if nargin < 4
                budget = struct();
            end
            [prbAvail, symAlloc] = obj.defaultBudget(budget);

            tmpl = localGrantTemplate(obj.Direction, slot);
            grants = repmat(tmpl, 0, 1);
            info = struct();
            info.Slot = slot;
            info.Direction = obj.Direction;
            nPRBAvail = numel(prbAvail);
            info.NPRBAvail = nPRBAvail;
            k1 = obj.HarqK1;
            k2 = obj.HarqK2;
            ssid = obj.SearchSpaceID;
            coreset = obj.CORESETID;
            bwpId = obj.BWPId;

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
            maxUE = min(maxUE, numel(ueIdx));
            maxGrantsEst = maxUE + numel(ueIdx);
            grants = repmat(tmpl, maxGrantsEst, 1);
            nGrant = 0;
            cursor = 1;
            hasHARQ = ~isempty(obj.HARQ);
            pendingRetx = false(1, nUEState);

            % --- 1) Schedule HARQ retransmissions first (if any) ---
            if hasHARQ
                for t = 1:numel(ueIdx)
                    k = ueIdx(t);
                    rnti = double(ueStates(k).RNTI);
                    pendingRetx(k) = obj.HARQ.hasPendingRetx(rnti);
                    if ~pendingRetx(k)
                        continue;
                    end
                    retx = obj.HARQ.peekRetx(rnti);
                    if isempty(retx) || cursor > nPRBAvail
                        continue;
                    end
                    g = localNormalizeGrant(retx.LastGrant, tmpl, obj.Direction, slot);

                    nNeed = numel(g.PRBSet);
                    if nNeed <= 0
                        nNeed = max(1, round(double(sixgr.util.structGet(g, "NPRB", ...
                            sixgr.util.structGet(g, "PRBCount", sixgr.util.structGet(g, "NumPRB", obj.MinPRBPerUE))))));
                    end
                    % Retx must preserve enough PRBs to carry the stored TB honestly.
                    if nNeed <= 0 || (nPRBAvail - cursor + 1) < nNeed
                        continue;
                    end
                    g.PRBSet = prbAvail(cursor:(cursor + nNeed - 1));
                    cursor = cursor + nNeed;

                    % Refresh slot + HARQ fields
                    g.Slot = slot;
                    g.Direction = obj.Direction;
                    if ~isfield(g, "MCSTable") || strlength(string(g.MCSTable)) == 0
                        g.MCSTable = obj.resolveMCSTable();
                    end
                    g.HARQ = retx.HARQ;
                    g.CQIUsed = double(sixgr.util.structGet(g, "CQIUsed", localUECQI(ueStates(k))));
                    g.DAI = 1;
                    g.K1 = k1;
                    g.K2 = k2;
                    g.SearchSpaceID = ssid;
                    g.CORESETID = coreset;
                    g.BWPId = bwpId;
                    g.HeadOfLineDelay_ms = localUEHoLDelay(ueStates(k));
                    g.BufferBytesBefore = localUEBufferByFlag(ueStates(k), isDL);
                    if ~isfinite(g.BufferBytesBefore)
                        g.BufferBytesBefore = 0;
                    end
                    g.TBSBits = double(sixgr.util.structGet(g, "TBSBits", sixgr.util.structGet(g, "TransportBlockSize", 0)));
                    g.TBSBytes = floor(max(g.TBSBits, 0) / 8);
                    g.BufferBytesAfter = max(g.BufferBytesBefore - double(g.TBSBytes), 0);
                    g.GrantReason = "harq_retx";
                    g.DCI = obj.buildDCIBitfield(g);

                    nGrant = nGrant + 1;
                    if nGrant > numel(grants)
                        grants = [grants; repmat(tmpl, max(32, round(0.5*numel(grants))+1), 1)]; %#ok<AGROW>
                    end
                    grants(nGrant) = g;

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

                nAlloc = min(prbPerUE, nPRBAvail - cursor + 1);
                if nAlloc <= 0
                    break;
                end

                bufB = localUEBufferByFlag(ueStates(k), isDL);
                candidatePRBSet = prbAvail(cursor:(cursor+nAlloc-1));
                plan = obj.buildNewDataGrantPlan(ueStates(k), candidatePRBSet, symAlloc, bufB);
                if ~plan.Valid || plan.TBSBits <= 0 || plan.TBSBytes <= 0
                    continue;
                end
                prbSet = double(plan.PRBSet(:).');
                cursor = cursor + numel(prbSet);
                servedBytes = double(plan.TBSBytes);

                % HARQ allocation (new data)
                harqInfo = struct('HarqID',[],'NDI',[],'RV',[],'IsRetransmission',false);
                if hasHARQ
                    txp = obj.HARQ.allocate(rnti, slot, servedBytes, 'NewData', true);
                    harqInfo = txp.HARQ;
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
                g.QueueLimited = logical(plan.QueueLimited);
                g.HARQ = harqInfo;
                g.CQIUsed = localUECQI(ueStates(k));
                g.MCSIndex = double(plan.MCSIndex);
                g.DAI = 1;
                g.K1 = k1;
                g.K2 = k2;
                g.SearchSpaceID = ssid;
                g.CORESETID = coreset;
                g.BWPId = bwpId;
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
                g.DCI = obj.buildDCIBitfield(g);

                nGrant = nGrant + 1;
                if nGrant > numel(grants)
                    grants = [grants; repmat(tmpl, max(32, round(0.5*numel(grants))+1), 1)]; %#ok<AGROW>
                end
                grants(nGrant) = g;

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
            info.PRBUnderuse = max(0, nPRBAvail - cursor + 1);
        end
    end
end

function g = localGrantTemplate(direction, slot)
g = struct();
g.Direction = char(string(direction));
g.Slot = double(slot);
g.RNTI = 0;
g.PRBSet = zeros(1,0);
g.SymbolAllocation = [0 14];
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
g.QueueLimited = false;
g.HARQ = struct('HarqID',[],'NDI',[],'RV',[],'IsRetransmission',false);
g.MCSIndex = 0;
g.CQIUsed = 0;
g.DAI = 1;
g.K1 = 4;
g.K2 = 1;
g.SearchSpaceID = 0;
g.CORESETID = 0;
g.BWPId = 0;
g.HeadOfLineDelay_ms = 0;
g.BufferBytesBefore = 0;
g.BufferBytesAfter = 0;
g.GrantReason = "new_data_rr";
g.DCI = struct("Format","","Bits",uint8([]),"Hex","","FieldMap",struct(),"RIV",0,"RBStart",0,"RBLength",0);
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

function mcs = localCQIToMCS(cqi)
mcs = max(0, min(27, round((double(cqi) - 1) * (27/14))));
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
