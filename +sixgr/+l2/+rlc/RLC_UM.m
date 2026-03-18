classdef RLC_UM < handle
% sixgr.l2.rlc.RLC_UM
% RLC Unacknowledged Mode (UM)
%
% This is an "abstract but coherent" UM implementation intended for an
% end-to-end simulator where:
%   SDAP -> PDCP -> RLC(UM) -> MAC -> PHY -> ... -> MAC -> RLC(UM) -> PDCP -> SDAP
%
% Key behaviors implemented (spec-inspired):
%  - RLC SDU queueing
%  - Segmentation / concatenation into RLC PDUs (within a byte budget)
%  - UM data PDU header carrying:
%       SI (segmentation indicator)
%       SN (sequence number)
%       SO (segment offset) when segmented
%  - Receiver reassembly using SO + segment coverage
%
% Not implemented (by design, for stepwise build):
%  - Status reporting / retransmissions (UM has none)
%
% API:
%   addSDU(bytes)
%   buildPDUs(availBytes) -> cell array of uint8 PDUs
%   receivePDU(pduBytes)
%   pullSDUs() -> cell array of reassembled SDUs (uint8)
%
% Defaults pulled (best effort) from cfg:
%   cfg.l2.rlc.um.snBits           (6 or 12, default 12)
%   cfg.l2.rlc.um.lcid             (default 4)
%   cfg.l2.rlc.um.maxPDUBytes      (default inf)
%   cfg.l2.rlc.um.reorderingTimer_slots (default 32)
%
% Segmentation Indicator (SI) encoding:
%   0 = Complete SDU in one PDU
%   1 = First segment
%   2 = Last segment
%   3 = Middle segment

    properties
        Cfg (1,1) struct
        Direction (1,:) char = 'DL'
        LCID (1,1) double = 4
        Logger = []
    end

    properties
        SNBits (1,1) double = 12    % 6 or 12 supported
        MaxPDUBytes (1,1) double = inf
        ReorderingTimer_slots (1,1) double = 32
    end

    properties(SetAccess=private)
        Stats (1,1) struct = struct( ...
            'TxSDU',0,'TxPDU',0,'TxBytes',0, ...
            'RxPDU',0,'RxSDU',0,'RxBytes',0,'Drop',0, ...
            'DropDup',0,'ReorderTimeout',0 )
    end

    properties(Access=private)
        Modulus (1,1) double = 4096

        % TX
        TxQueue cell = {}           % ring queue data
        TxMetaQueue cell = {}       % ring queue metadata
        TxQHead (1,1) double = 1
        TxQCount (1,1) double = 0
        TxNextSN (1,1) double = 0
        TxSeg (1,1) struct = struct('Active',false,'SN',0,'Data',uint8([]),'Offset',0,'Total',0,'Meta',struct())

        % RX
        RxBufValid logical = false(0,1) % [Modulus x 1]
        RxBufState cell = {}            % [Modulus x 1] segmented reassembly state
        RxSDUQueue cell = {}        % delivered SDUs
        RxMetaQueue cell = {}       % delivered metadata
        RxDropMetaQueue cell = {}   % dropped metadata/cause
        RxSDUCount (1,1) double = 0
        RxDropCount (1,1) double = 0
        RxExpectedSN (1,1) double = 0
        RxReorderValid logical = false(0,1) % [Modulus x 1]
        RxReorderPayload cell = {}          % [Modulus x 1]
        RxReorderMeta cell = {}             % [Modulus x 1]
        RxReorderTick double = zeros(0,1)   % [Modulus x 1]
        RxTick (1,1) double = 0
        ReorderTimerActive (1,1) logical = false
        ReorderTimerStartTick (1,1) double = 0
        ReassemblyDelaySlots double = zeros(128,1)
        ReassemblyDelayCount (1,1) double = 0
    end

    methods
        function obj = RLC_UM(cfg, varargin)
            if nargin < 1 || isempty(cfg)
                cfg = struct();
            end
            obj.Cfg = cfg;

            obj.Direction = upper(char(string(sixgr.util.structGet(cfg,"l2.rlc.um.direction",obj.Direction))));
            obj.LCID = double(sixgr.util.structGet(cfg,"l2.rlc.um.lcid",obj.LCID));
            obj.SNBits = double(sixgr.util.structGet(cfg,"l2.rlc.um.snBits",obj.SNBits));
            obj.MaxPDUBytes = double(sixgr.util.structGet(cfg,"l2.rlc.um.maxPDUBytes",obj.MaxPDUBytes));
            obj.ReorderingTimer_slots = double(sixgr.util.structGet(cfg,"l2.rlc.um.reorderingTimer_slots",obj.ReorderingTimer_slots));

            if ~ismember(obj.SNBits, [6 12])
                error("sixgr:RLC_UM:BadSNBits","RLC UM supports SNBits 6 or 12 (got %g).", obj.SNBits);
            end

            if ~isempty(varargin)
                if mod(numel(varargin),2) ~= 0
                    error("sixgr:RLC_UM:BadNV","Name-value inputs must come in pairs.");
                end
                for i = 1:2:numel(varargin)
                    k = varargin{i}; v = varargin{i+1};
                    if isstring(k), k = char(k); end
                    switch lower(char(k))
                        case 'direction'
                            obj.Direction = upper(char(string(v)));
                        case 'lcid'
                            obj.LCID = double(v);
                        case 'snbits'
                            obj.SNBits = double(v);
                        case 'maxpdubytes'
                            obj.MaxPDUBytes = double(v);
                        case 'logger'
                            obj.Logger = v;
                        case 'reorderingtimer_slots'
                            obj.ReorderingTimer_slots = double(v);
                        otherwise
                            error("sixgr:RLC_UM:BadOpt","Unknown option: %s", string(k));
                    end
                end
            end

            obj.Modulus = 2^obj.SNBits;
            obj.initRxArrays_();
            obj.initTxQueue_();
            obj.initRxQueues_();
        end

        function reset(obj)
            obj.initTxQueue_();
            obj.TxNextSN = 0;
            obj.TxSeg = struct('Active',false,'SN',0,'Data',uint8([]),'Offset',0,'Total',0,'Meta',struct());

            obj.Modulus = 2^obj.SNBits;
            obj.initRxArrays_();
            obj.initRxQueues_();
            obj.RxExpectedSN = 0;
            obj.RxTick = 0;
            obj.ReorderTimerActive = false;
            obj.ReorderTimerStartTick = 0;
            obj.ReassemblyDelaySlots = zeros(128,1);
            obj.ReassemblyDelayCount = 0;

            obj.Stats = struct('TxSDU',0,'TxPDU',0,'TxBytes',0, ...
                'RxPDU',0,'RxSDU',0,'RxBytes',0,'Drop',0,'DropDup',0,'ReorderTimeout',0);
        end

        function addSDU(obj, sduBytes, varargin)
            if isempty(sduBytes)
                return;
            end
            sduBytes = localToU8(sduBytes);
            metaIn = localTraceMetaFromArgs(varargin{:});
            obj.enqueueTx_(sduBytes, metaIn);
            obj.Stats.TxSDU = obj.Stats.TxSDU + 1;
        end

        function tf = hasData(obj)
            tf = obj.TxSeg.Active || (obj.TxQCount > 0);
        end

        function [pdus, metas] = buildPDUs(obj, availBytes)
            % buildPDUs Build as many PDUs as fit within availBytes total.
            if nargin < 2 || isempty(availBytes)
                availBytes = inf;
            end
            budget = min(double(availBytes), double(obj.MaxPDUBytes) * 1e9); % avoid inf*0 issues
            pdus = cell(8,1);
            metaTemplate = localMakeRLCMeta(localDefaultTraceMeta());
            metas = repmat(metaTemplate, 8, 1);
            pCount = 0;

            while budget > 0 && obj.hasData()
                [pdu, meta] = obj.buildOnePDU(budget);
                if isempty(pdu)
                    break;
                end
                pCount = pCount + 1;
                if pCount > numel(pdus)
                    newCap = numel(pdus) * 2;
                    pdus{newCap,1} = [];
                    metas(newCap,1) = metaTemplate;
                end
                pdus{pCount,1} = pdu;
                metas(pCount,1) = meta;
                budget = budget - numel(pdu);
            end
            pdus = pdus(1:pCount);
            metas = metas(1:pCount);
        end

        function [pdu, meta] = buildOnePDU(obj, maxBytes)
            % Produce one UM data PDU that fits within maxBytes (including header)
            pdu = uint8([]);
            meta = localMakeRLCMeta(localDefaultTraceMeta());

            if nargin < 2 || isempty(maxBytes)
                maxBytes = inf;
            end
            maxBytes = min(double(maxBytes), double(obj.MaxPDUBytes));

            if ~obj.hasData()
                return;
            end

            % Ensure current SDU context
            if ~obj.TxSeg.Active
                % Pop next SDU
                [sdu, sduMeta, ok] = obj.popTx_();
                if ~ok
                    return;
                end
                obj.TxSeg.Active = true;
                obj.TxSeg.SN = obj.TxNextSN;
                obj.TxSeg.Data = sdu(:);
                obj.TxSeg.Offset = 0;
                obj.TxSeg.Total = numel(sdu);
                obj.TxSeg.Meta = sduMeta;
            end

            sn = double(obj.TxSeg.SN);
            off = double(obj.TxSeg.Offset);
            total = double(obj.TxSeg.Total);
            rem = total - off;
            if rem <= 0
                % Shouldn't happen; reset state
                obj.TxSeg.Active = false;
                return;
            end

            baseHdr = localBaseHdrLen(obj.SNBits);

            % If whole remaining fits as complete SDU (no SO field)
            payloadMaxComplete = maxBytes - baseHdr;
            if off == 0 && rem <= payloadMaxComplete
                si = 0;
                soPresent = false;
                so = 0;
                chunkLen = rem;
                hdr = localEncodeHdrUM(obj.SNBits, sn, si, soPresent, so);
            else
                % segmented: include SO field
                si = localSI(off, rem, maxBytes, baseHdr);
                soPresent = true;
                so = off;
                segHdr = baseHdr + 2; % +SO
                payloadMax = maxBytes - segHdr;
                if payloadMax <= 0
                    % can't fit any payload
                    obj.Stats.Drop = obj.Stats.Drop + 1;
                    return;
                end
                chunkLen = min(rem, payloadMax);

                % Recompute SI precisely based on chosen chunk length
                if off == 0 && chunkLen < rem
                    si = 1; % first
                elseif (off + chunkLen) == total
                    si = 2; % last
                else
                    si = 3; % middle
                end

                hdr = localEncodeHdrUM(obj.SNBits, sn, si, soPresent, so);
            end

            chunk = obj.TxSeg.Data((off+1):(off+chunkLen));
            pdu = [hdr; chunk(:)];
            tr = localTraceMetaFromArgs(obj.TxSeg.Meta);
            tr.RLC_SN = sn;
            tr.SegmentOffset = so;
            tr.DropCause = "";
            meta = localMakeRLCMeta(tr);
            meta.LCID = obj.LCID;
            meta.SN = sn;
            meta.SI = si;
            meta.SO = so;
            meta.Length = numel(pdu);

            obj.Stats.TxPDU = obj.Stats.TxPDU + 1;
            obj.Stats.TxBytes = obj.Stats.TxBytes + numel(pdu);

            % Advance segmentation state
            off2 = off + chunkLen;
            if si == 0 || off2 >= total
                % Completed SDU
                obj.TxSeg.Active = false;
                obj.TxSeg.Data = uint8([]);
                obj.TxSeg.Offset = 0;
                obj.TxSeg.Total = 0;
                obj.TxNextSN = mod(obj.TxNextSN + 1, 2^obj.SNBits);
            else
                obj.TxSeg.Offset = off2;
            end
        end


        function macSDUs = buildMACSDUs(obj, availBytes)
            % buildMACSDUs Convenience wrapper for MAC mux.
            % Returns struct array with fields: LCID, Payload
            [pdus, metas] = obj.buildPDUs(availBytes);
            n = numel(pdus);
            if n <= 0
                macSDUs = struct('LCID',{},'Payload',{},'Meta',{});
                return;
            end
            macSDUs = repmat(struct('LCID',obj.LCID,'Payload',uint8([]),'Meta',metas(1)), n, 1);
            for i = 1:n
                macSDUs(i) = struct('LCID',obj.LCID,'Payload',pdus{i},'Meta',metas(i));
            end
        end

        function receivePDU(obj, pduBytes, varargin)
            % receivePDU Consume one UM data PDU
            if isempty(pduBytes)
                return;
            end
            metaIn = localTraceMetaFromArgs(varargin{:});
            obj.RxTick = localResolveRxTick(obj.RxTick, metaIn);
            pduBytes = localToU8(pduBytes);

            [hdr, payload] = localDecodeHdrUM(obj.SNBits, pduBytes);
            obj.Stats.RxPDU = obj.Stats.RxPDU + 1;

            sn = double(hdr.SN);
            si = double(hdr.SI);
            so = double(hdr.SO);
            rxMeta = localTraceMetaFromArgs(metaIn);
            rxMeta.RLC_SN = sn;
            rxMeta.SegmentOffset = so;

            if si == 0
                idxSN = mod(round(sn), obj.Modulus) + 1;
                if obj.RxReorderValid(idxSN)
                    obj.Stats.DropDup = obj.Stats.DropDup + 1;
                    obj.Stats.Drop = obj.Stats.Drop + 1;
                    d = rxMeta;
                    d.DropCause = "RLC_UM_DUPLICATE_SN";
                    obj.enqueueDrop_(d);
                    return;
                end
                obj.localStoreForReorder(sn, payload, rxMeta);
                obj.localFlushReorder(false);
                return;
            end

            % Segmented: reassembly by SO
            st = [];
            idxSN = mod(round(sn), obj.Modulus) + 1;
            if obj.RxBufValid(idxSN)
                st = obj.RxBufState{idxSN};
            else
                st = struct('Segs',repmat(struct('SO',0,'Data',uint8([])), 8, 1), 'SegCount',0, 'Total',NaN, ...
                    'Meta', rxMeta, 'FirstTick', obj.RxTick);
            end

            % Deduplicate by SO
            segCount = obj.localGetSegCount_(st);
            if segCount > 0
                soVec = [st.Segs(1:segCount).SO];
                if any(soVec == so)
                    % duplicate segment
                    obj.Stats.DropDup = obj.Stats.DropDup + 1;
                    obj.Stats.Drop = obj.Stats.Drop + 1;
                    d = rxMeta;
                    d.DropCause = "RLC_UM_DUPLICATE_SEGMENT";
                    obj.enqueueDrop_(d);
                    return;
                end
            end

            st = obj.localAppendSegment_(st, so, payload);

            if si == 2
                st.Total = so + numel(payload);
            end

            % Try completion if total known
            if isfinite(st.Total) && st.Total >= 0
                [ok, assembled] = localAssembleSegments(st.Segs(1:obj.localGetSegCount_(st)), st.Total);
                if ok
                    tr = localTraceMetaFromArgs(st.Meta);
                    tr.RLC_SN = sn;
                    tr.SegmentOffset = 0;
                    tr.DropCause = "";
                    if isfinite(double(st.FirstTick))
                        obj.appendReassemblyDelay_(max(0, obj.RxTick - double(st.FirstTick)));
                    end
                    obj.localStoreForReorder(sn, assembled, tr);
                    obj.RxBufValid(idxSN) = false;
                    obj.RxBufState{idxSN} = [];
                    obj.localFlushReorder(false);
                    return;
                end
            end

            obj.RxBufValid(idxSN) = true;
            obj.RxBufState{idxSN} = st;
            obj.localFlushReorder(true);
        end

        function [sdus, metas] = pullSDUs(obj)
            if obj.RxSDUCount > 0
                sdus = obj.RxSDUQueue(1:obj.RxSDUCount);
                if nargout >= 2
                    metas = obj.RxMetaQueue(1:obj.RxSDUCount);
                end
            else
                sdus = {};
                if nargout >= 2
                    metas = {};
                end
            end
            obj.RxSDUCount = 0;
            if nargout >= 2
                % assigned above
            end
        end

        function drops = pullDropMeta(obj)
            if obj.RxDropCount > 0
                drops = obj.RxDropMetaQueue(1:obj.RxDropCount);
            else
                drops = {};
            end
            obj.RxDropCount = 0;
        end

        function delays = getReassemblyDelaySlots(obj)
            if obj.ReassemblyDelayCount > 0
                delays = obj.ReassemblyDelaySlots(1:obj.ReassemblyDelayCount);
            else
                delays = zeros(0,1);
            end
        end
    end

    methods(Access=private)
        function initRxArrays_(obj)
            m = max(1, round(double(obj.Modulus)));
            obj.RxBufValid = false(m,1);
            obj.RxBufState = cell(m,1);
            obj.RxReorderValid = false(m,1);
            obj.RxReorderPayload = cell(m,1);
            obj.RxReorderMeta = cell(m,1);
            obj.RxReorderTick = zeros(m,1);
        end

        function initTxQueue_(obj)
            cap = 256;
            obj.TxQueue = cell(cap,1);
            obj.TxMetaQueue = cell(cap,1);
            obj.TxQHead = 1;
            obj.TxQCount = 0;
        end

        function initRxQueues_(obj)
            cap = 256;
            obj.RxSDUQueue = cell(cap,1);
            obj.RxMetaQueue = cell(cap,1);
            obj.RxDropMetaQueue = cell(cap,1);
            obj.RxSDUCount = 0;
            obj.RxDropCount = 0;
        end

        function enqueueTx_(obj, sdu, meta)
            cap = numel(obj.TxQueue);
            if obj.TxQCount >= cap
                obj.growTxQueue_();
                cap = numel(obj.TxQueue);
            end
            tail = obj.TxQHead + obj.TxQCount;
            while tail > cap
                tail = tail - cap;
            end
            obj.TxQueue{tail,1} = sdu;
            obj.TxMetaQueue{tail,1} = meta;
            obj.TxQCount = obj.TxQCount + 1;
        end

        function [sdu, meta, ok] = popTx_(obj)
            ok = false;
            sdu = uint8([]);
            meta = localDefaultTraceMeta();
            if obj.TxQCount <= 0
                return;
            end
            idx = obj.TxQHead;
            sdu = obj.TxQueue{idx,1};
            meta = localTraceMetaFromArgs(obj.TxMetaQueue{idx,1});
            obj.TxQueue{idx,1} = [];
            obj.TxMetaQueue{idx,1} = [];
            obj.TxQHead = idx + 1;
            if obj.TxQHead > numel(obj.TxQueue)
                obj.TxQHead = 1;
            end
            obj.TxQCount = obj.TxQCount - 1;
            ok = true;
        end

        function growTxQueue_(obj)
            oldCap = numel(obj.TxQueue);
            newCap = max(256, oldCap * 2);
            qNew = cell(newCap,1);
            mNew = cell(newCap,1);
            for i = 1:obj.TxQCount
                idx = obj.TxQHead + i - 1;
                while idx > oldCap
                    idx = idx - oldCap;
                end
                qNew{i,1} = obj.TxQueue{idx,1};
                mNew{i,1} = obj.TxMetaQueue{idx,1};
            end
            obj.TxQueue = qNew;
            obj.TxMetaQueue = mNew;
            obj.TxQHead = 1;
        end

        function enqueueSDU_(obj, sdu, meta)
            idx = obj.RxSDUCount + 1;
            if idx > numel(obj.RxSDUQueue)
                newCap = max(numel(obj.RxSDUQueue) * 2, idx);
                obj.RxSDUQueue{newCap,1} = [];
                obj.RxMetaQueue{newCap,1} = [];
            end
            obj.RxSDUQueue{idx,1} = sdu;
            obj.RxMetaQueue{idx,1} = meta;
            obj.RxSDUCount = idx;
        end

        function enqueueDrop_(obj, meta)
            idx = obj.RxDropCount + 1;
            if idx > numel(obj.RxDropMetaQueue)
                newCap = max(numel(obj.RxDropMetaQueue) * 2, idx);
                obj.RxDropMetaQueue{newCap,1} = [];
            end
            obj.RxDropMetaQueue{idx,1} = meta;
            obj.RxDropCount = idx;
        end

        function appendReassemblyDelay_(obj, v)
            idx = obj.ReassemblyDelayCount + 1;
            if idx > numel(obj.ReassemblyDelaySlots)
                newCap = max(numel(obj.ReassemblyDelaySlots) * 2, idx);
                obj.ReassemblyDelaySlots(newCap,1) = 0;
            end
            obj.ReassemblyDelaySlots(idx,1) = double(v);
            obj.ReassemblyDelayCount = idx;
        end

        function count = localGetSegCount_(obj, st)
            %#ok<INUSD>
            count = double(sixgr.util.structGet(st, "SegCount", 0));
            if count > 0
                return;
            end
            if ~isfield(st, 'Segs')
                count = 0;
                return;
            end
            segs = st.Segs;
            if isempty(segs)
                count = 0;
                return;
            end
            hasData = false(numel(segs),1);
            for i = 1:numel(segs)
                hasData(i) = ~isempty(segs(i).Data);
            end
            nz = find(hasData, 1, 'last');
            if isempty(nz)
                count = 0;
            else
                count = double(nz);
            end
        end

        function st = localAppendSegment_(obj, st, so, payload)
            %#ok<INUSD>
            if ~isfield(st, "Segs")
                st.Segs = repmat(struct('SO',0,'Data',uint8([])), 8, 1);
                st.SegCount = 0;
            end
            count = obj.localGetSegCount_(st);
            idx = count + 1;
            if idx > numel(st.Segs)
                growTo = max(numel(st.Segs) * 2, idx);
                st.Segs(growTo,1) = struct('SO',0,'Data',uint8([]));
            end
            st.Segs(idx,1) = struct('SO',so,'Data',payload);
            st.SegCount = idx;
        end

        function localStoreForReorder(obj, sn, payload, meta)
            m = localTraceMetaFromArgs(meta);
            m.RLC_SN = sn;
            idxSN = mod(round(sn), obj.Modulus) + 1;
            if ~obj.RxReorderValid(idxSN)
                obj.RxReorderValid(idxSN) = true;
                obj.RxReorderPayload{idxSN} = payload(:);
                obj.RxReorderMeta{idxSN} = m;
                obj.RxReorderTick(idxSN) = obj.RxTick;
            else
                obj.Stats.DropDup = obj.Stats.DropDup + 1;
                obj.Stats.Drop = obj.Stats.Drop + 1;
                d = m;
                d.DropCause = "RLC_UM_DUPLICATE_SN";
                obj.enqueueDrop_(d);
            end
        end

        function localFlushReorder(obj, checkTimeout)
            if nargin < 2
                checkTimeout = false;
            end
            modSN = obj.Modulus;
            win = max(1, floor(modSN/2));

            % Deliver contiguous sequence from expected SN.
            delivered = false;
            while true
                idxExp = mod(round(obj.RxExpectedSN), modSN) + 1;
                if ~(idxExp >= 1 && idxExp <= numel(obj.RxReorderValid) && obj.RxReorderValid(idxExp))
                    break;
                end
                tr = localTraceMetaFromArgs(obj.RxReorderMeta{idxExp});
                tr.DeliverySlot = obj.RxTick;
                obj.enqueueSDU_(obj.RxReorderPayload{idxExp}, tr);
                obj.Stats.RxSDU = obj.Stats.RxSDU + 1;
                obj.Stats.RxBytes = obj.Stats.RxBytes + numel(obj.RxReorderPayload{idxExp});
                obj.RxReorderValid(idxExp) = false;
                obj.RxReorderPayload{idxExp} = [];
                obj.RxReorderMeta{idxExp} = [];
                obj.RxReorderTick(idxExp) = 0;
                obj.RxExpectedSN = mod(obj.RxExpectedSN + 1, modSN);
                delivered = true;
            end

            if delivered
                obj.ReorderTimerActive = false;
            end

            % Start timer if there are out-of-order entries.
            if any(obj.RxReorderValid) && ~obj.ReorderTimerActive
                obj.ReorderTimerActive = true;
                obj.ReorderTimerStartTick = obj.RxTick;
            end

            if ~checkTimeout || ~obj.ReorderTimerActive
                return;
            end

            if (obj.RxTick - obj.ReorderTimerStartTick) < max(1, round(obj.ReorderingTimer_slots))
                return;
            end

            % Timer expiry: skip missing SN(s) until first buffered SN is reachable.
            obj.Stats.ReorderTimeout = obj.Stats.ReorderTimeout + 1;
            keys = find(obj.RxReorderValid) - 1;
            if isempty(keys)
                obj.ReorderTimerActive = false;
                return;
            end
            d = mod(double(keys(:)) - double(obj.RxExpectedSN), double(modSN));
            d(d >= win) = inf;
            [minD, idx] = min(d);
            if isfinite(minD)
                obj.RxExpectedSN = double(keys(idx));
            end
            obj.ReorderTimerActive = false;
            obj.localFlushReorder(false);
        end
    end
end

% =============================== Helpers =================================

function b = localToU8(x)
    if isa(x,'uint8')
        b = x(:);
    elseif islogical(x)
        b = uint8(x(:));
    else
        b = uint8(x(:));
    end
end

function L = localBaseHdrLen(snBits)
    if snBits == 6
        L = 1;
    else
        L = 2;
    end
end

function si = localSI(off, rem, maxBytes, baseHdr)
    %#ok<INUSD>
    % Placeholder SI calculation; final SI is recomputed after choosing chunkLen
    if off == 0
        si = 1;
    elseif rem <= (maxBytes - (baseHdr+2))
        si = 2;
    else
        si = 3;
    end
end

function hdr = localEncodeHdrUM(snBits, sn, si, soPresent, so)
    if snBits == 6
        b1 = bitshift(uint8(si),6) + uint8(mod(sn, 64));
        if ~soPresent
            hdr = b1;
        else
            hdr = [b1; typecast(uint16(so),'uint8')];
            hdr = hdr([1 3 2]); % ensure big-endian: [MSB LSB]
        end
    else
        sn = mod(sn, 4096);
        snHi = floor(sn / 64); % 6 bits
        snLo = mod(sn, 64);    % 6 bits
        b1 = bitshift(uint8(si),6) + uint8(snHi);
        b2 = uint8(snLo); % bits5..0 used; bits7..6 reserved 0
        if ~soPresent
            hdr = [b1; b2];
        else
            so16 = uint16(so);
            soBytes = typecast(so16,'uint8'); % little-endian in MATLAB
            hdr = [b1; b2; soBytes(2); soBytes(1)]; % big-endian
        end
    end
end

function [hdr, payload] = localDecodeHdrUM(snBits, pdu)
    if snBits == 6
        b1 = uint8(pdu(1));
        si = bitshift(b1, -6);
        sn = bitand(b1, uint8(63));
        if si == 0
            hdr = struct('SI',double(si),'SN',double(sn),'SO',0,'HeaderLen',1);
            payload = pdu(2:end);
        else
            if numel(pdu) < 3
                error("sixgr:RLC_UM:BadPDU","Segmented UM PDU too short.");
            end
            so = double(uint16(pdu(2))*256 + uint16(pdu(3)));
            hdr = struct('SI',double(si),'SN',double(sn),'SO',so,'HeaderLen',3);
            payload = pdu(4:end);
        end
    else
        if numel(pdu) < 2
            error("sixgr:RLC_UM:BadPDU","UM PDU too short.");
        end
        b1 = uint8(pdu(1));
        b2 = uint8(pdu(2));
        si = bitshift(b1,-6);
        snHi = bitand(b1, uint8(63));
        snLo = bitand(b2, uint8(63));
        sn = double(snHi)*64 + double(snLo);
        if si == 0
            hdr = struct('SI',double(si),'SN',sn,'SO',0,'HeaderLen',2);
            payload = pdu(3:end);
        else
            if numel(pdu) < 4
                error("sixgr:RLC_UM:BadPDU","Segmented UM PDU too short.");
            end
            so = double(uint16(pdu(3))*256 + uint16(pdu(4)));
            hdr = struct('SI',double(si),'SN',sn,'SO',so,'HeaderLen',4);
            payload = pdu(5:end);
        end
    end
    payload = payload(:);
end

function [ok, assembled] = localAssembleSegments(segs, totalLen)
    % Assemble segments into a single SDU if coverage is complete.
    ok = false;
    assembled = uint8([]);
    if ~isfinite(totalLen) || totalLen < 0
        return;
    end
    totalLen = double(totalLen);
    if totalLen == 0
        ok = true;
        assembled = uint8([]);
        return;
    end

    cov = false(totalLen, 1);
    buf = zeros(totalLen, 1, 'uint8');

    for i = 1:numel(segs)
        so = double(segs(i).SO);
        d = segs(i).Data(:);
        if isempty(d)
            continue;
        end
        s = so + 1;
        e = so + numel(d);
        if s < 1 || e > totalLen
            % out of bounds segment
            return;
        end
        buf(s:e) = d;
        cov(s:e) = true;
    end

    if all(cov)
        ok = true;
        assembled = buf;
    end
end

function tick = localResolveRxTick(prevTick, meta)
tick = double(prevTick) + 1;
if ~isstruct(meta)
    return;
end
g = double(sixgr.util.structGet(meta, "GrantSlot", NaN));
d = double(sixgr.util.structGet(meta, "DeliverySlot", NaN));
if isfinite(g)
    tick = max(tick, g);
end
if isfinite(d)
    tick = max(tick, d);
end
end

function metas = localEmptyRLCMeta()
metas = struct('LCID',{},'SN',{},'SI',{},'SO',{},'Length',{}, ...
    'PktId',{},'FlowId',{},'QFI',{},'CreationSlot',{},'CreationTime_s',{}, ...
    'PDCP_SN',{},'RLC_SN',{},'SegmentOffset',{},'HARQProcess',{}, ...
    'GrantSlot',{},'DeliverySlot',{},'DropCause',{});
end

function meta = localMakeRLCMeta(trace)
tr = localTraceMetaFromArgs(trace);
meta = struct('LCID',NaN,'SN',NaN,'SI',NaN,'SO',NaN,'Length',0, ...
    'PktId',tr.PktId,'FlowId',tr.FlowId,'QFI',tr.QFI,'CreationSlot',tr.CreationSlot,'CreationTime_s',tr.CreationTime_s, ...
    'PDCP_SN',tr.PDCP_SN,'RLC_SN',tr.RLC_SN,'SegmentOffset',tr.SegmentOffset, ...
    'HARQProcess',tr.HARQProcess,'GrantSlot',tr.GrantSlot,'DeliverySlot',tr.DeliverySlot,'DropCause',tr.DropCause);
end

function meta = localDefaultTraceMeta()
meta = struct( ...
    "PktId", NaN, ...
    "FlowId", NaN, ...
    "QFI", NaN, ...
    "CreationSlot", NaN, ...
    "CreationTime_s", NaN, ...
    "PDCP_SN", NaN, ...
    "RLC_SN", NaN, ...
    "SegmentOffset", NaN, ...
    "HARQProcess", NaN, ...
    "GrantSlot", NaN, ...
    "DeliverySlot", NaN, ...
    "DropCause", "");
end

function meta = localTraceMetaFromArgs(varargin)
meta = localDefaultTraceMeta();
if isempty(varargin)
    return;
end
in = varargin{1};
if isempty(in) || ~isstruct(in)
    return;
end
f = fieldnames(in);
for i = 1:numel(f)
    meta.(f{i}) = in.(f{i});
end
if ~isfield(meta, "DropCause") || strlength(string(meta.DropCause)) == 0
    meta.DropCause = "";
end
end
