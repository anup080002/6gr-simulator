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
    end

    methods
        function obj = SchedulerPF(cfg, varargin)
            obj@sixgr.l2.mac.SchedulerBase(cfg, varargin{:});
            obj.MaxUEPerSlot = double(sixgr.util.structGet(cfg,"mac.scheduler.maxUEPerSlot",obj.MaxUEPerSlot));
            obj.MinPRBPerUE = double(sixgr.util.structGet(cfg,"mac.scheduler.minPRBPerUE",obj.MinPRBPerUE));
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
            k1 = max(0, round(double(sixgr.util.structGet(obj.Cfg, "mac.harq.k1", 4))));
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
            maxUE = min(maxUE, numel(ueIdx));

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
                        g = localNormalizeGrant(retx.LastGrant, tmpl, obj.Direction, slot);
                        if isempty(prbAvail)
                            break;
                        end
                        % Best-effort remap if needed
                        if ~all(ismember(g.PRBSet, prbAvail))
                            nNeed = numel(g.PRBSet);
                            nNeed = min(nNeed, numel(prbAvail));
                            g.PRBSet = prbAvail(1:nNeed);
                        end
                        prbAvail = setdiff(prbAvail, g.PRBSet, 'stable');

                        g.Slot = slot;
                        g.Direction = obj.Direction;
                        g.HARQ = retx.HARQ;
                        g.CQIUsed = localUECQI(ueStates(k));
                        g.MCSIndex = localCQIToMCS(g.CQIUsed);
                        g.DAI = 1;
                        g.K1 = k1;
                        g.K2 = k2;
                        g.SearchSpaceID = ssid;
                        g.CORESETID = coreset;
                        g.BWPId = bwpId;
                        g.HeadOfLineDelay_ms = localUEHoLDelay(ueStates(k));
                        g.BufferBytesBefore = bufBytes(k);
                        g.BufferBytesAfter = max(bufBytes(k) - double(g.TBSBytes), 0);
                        g.GrantReason = "harq_retx";
                        g.DCI = obj.buildDCIBitfield(g);
                        grants(end+1) = g; %#ok<AGROW>
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

            % Choose an initial chunk size.
            prbChunk = max(obj.MinPRBPerUE, floor(nPRBAvail / maxUE));
            prbChunk = max(prbChunk, 1);

            metrics = -inf(1, numel(ueIdx));
            estTBS = zeros(1, numel(ueIdx));
            for t = 1:numel(ueIdx)
                k = ueIdx(t);
                rnti = double(ueStates(k).RNTI);

                % Skip if HARQ already pending retx (handled earlier)
                if ~isempty(obj.HARQ) && obj.HARQ.hasPendingRetx(rnti)
                    continue;
                end

                [modStr, nLayers, tcr] = obj.selectAMC(ueStates(k));
                [tbsBits, tbsBytes, ~] = obj.estimateTBS(modStr, nLayers, prbChunk, symAlloc, tcr);

                % Clamp by buffer
                tbsBytes = min(tbsBytes, floor(bufBytes(k)));
                tbsBits = 8*floor(tbsBytes/8);

                estTBS(t) = tbsBits;
                metrics(t) = obj.pfMetric(ueStates(k), tbsBits);
            end

            % Sort UEs by PF metric descending
            [~, ord] = sort(metrics, 'descend');
            ord = ord(metrics(ord) > 0);
            if isempty(ord)
                info.NGrants = numel(grants);
                return;
            end
            ord = ord(1:min(numel(ord), maxUE));

            cursor = 1;
            for ii = 1:numel(ord)
                if cursor > numel(prbAvail)
                    break;
                end
                k = ueIdx(ord(ii));
                rnti = double(ueStates(k).RNTI);

                if ~isempty(obj.HARQ) && obj.HARQ.hasPendingRetx(rnti)
                    continue;
                end

                nAlloc = min(prbChunk, numel(prbAvail)-cursor+1);
                prbSet = prbAvail(cursor:(cursor+nAlloc-1));
                cursor = cursor + nAlloc;

                [modStr, nLayers, tcr] = obj.selectAMC(ueStates(k));
                [tbsBits, tbsBytes, ~] = obj.estimateTBS(modStr, nLayers, numel(prbSet), symAlloc, tcr);

                % Clamp by buffer
                tbsBytes = min(tbsBytes, floor(bufBytes(k)));
                tbsBits = 8*floor(tbsBytes/8);

                harqInfo = struct('HarqID',[],'NDI',[],'RV',[],'IsRetransmission',false);
                if ~isempty(obj.HARQ)
                    txp = obj.HARQ.allocate(rnti, slot, tbsBytes, 'NewData', true);
                    harqInfo = txp.HARQ;
                end

                g = tmpl;
                g.Direction = obj.Direction;
                g.Slot = slot;
                g.RNTI = rnti;
                g.PRBSet = prbSet;
                g.SymbolAllocation = symAlloc;
                g.Modulation = char(modStr);
                g.NumLayers = nLayers;
                g.TargetCodeRate = tcr;
                g.TBSBits = tbsBits;
                g.TBSBytes = tbsBytes;
                g.HARQ = harqInfo;
                g.CQIUsed = localUECQI(ueStates(k));
                g.MCSIndex = localCQIToMCS(g.CQIUsed);
                g.DAI = 1;
                g.K1 = k1;
                g.K2 = k2;
                g.SearchSpaceID = ssid;
                g.CORESETID = coreset;
                g.BWPId = bwpId;
                g.HeadOfLineDelay_ms = localUEHoLDelay(ueStates(k));
                g.BufferBytesBefore = bufBytes(k);
                g.BufferBytesAfter = max(bufBytes(k) - double(tbsBytes), 0);
                g.GrantReason = "new_data_pf";
                g.DCI = obj.buildDCIBitfield(g);

                grants(end+1) = g; %#ok<AGROW>

                % record served time
                obj.ensureUE(rnti);
                obj.UEStats(obj.ensureUE(rnti)).LastServedSlot = slot;
            end

            info.NGrants = numel(grants);
            info.PRBUnderuse = numel(prbAvail) - max(0, cursor-1);
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
g.HARQ = struct('HarqID',[],'NDI',[],'RV',[],'IsRetransmission',false);
g.MCSIndex = 0;
g.CQIUsed = 1;
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
cqi = double(sixgr.util.structGet(ue, "CQI", 1));
cqi = max(1, min(15, round(cqi)));
end

function mcs = localCQIToMCS(cqi)
mcs = max(0, min(27, round((double(cqi) - 1) * (27/14))));
end

function hol = localUEHoLDelay(ue)
hol = double(sixgr.util.structGet(ue, "HeadOfLineDelay_ms", 0));
if ~isfinite(hol) || hol < 0
    hol = 0;
end
end
