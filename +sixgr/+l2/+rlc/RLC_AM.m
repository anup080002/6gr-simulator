classdef RLC_AM < handle
% sixgr.l2.rlc.RLC_AM
% RLC Acknowledged Mode (AM)
%
% This implementation is "abstract but coherent" with a real message flow:
%   - SDU queueing from PDCP
%   - Segmentation into Data PDUs (with SN + SI + optional SO)
%   - Receiver reassembly with segment coverage tracking (SO-based)
%   - STATUS control PDUs carrying ACK_SN and NACK list
%   - Retransmission scheduling based on received STATUS PDUs
%
% It is NOT a full TS 38.322 bit-exact implementation; it is designed to be:
%   - stable, readable, and easy to extend
%   - correct in the high-level ARQ behaviors and interfaces
%   - suitable for L2/L3 message-flow simulation, and for PHY integration
%
% API:
%   addSDU(bytes)
%   buildPDUs(availBytes) -> PDUs to pass to MAC (same LCID)
%   receivePDU(pduBytes)  -> process incoming data/control
%   pullSDUs()            -> deliver reassembled SDUs to PDCP
%
% Defaults from cfg (best effort):
%   cfg.l2.rlc.am.snBits         (12 supported; 18 not yet)
%   cfg.l2.rlc.am.windowSize     (default 2048 for 12-bit? we use 2048? Actually half range)
%   cfg.l2.rlc.am.maxRetx        (default 3)
%   cfg.l2.rlc.am.pollEveryNPDU  (default 8)
%   cfg.l2.rlc.am.lcid           (default 4)
%
% Data PDU header (simplified, 12-bit SN):
%   Byte1: [D/C=0][P][SI(2)][SN(4)]
%   Byte2: SN(8)
%   If SI != 0 (segmented): add SO (2 bytes, big-endian)
%
% STATUS PDU (simplified):
%   Byte1: 0x80 (D/C=1, STATUS)
%   Byte2-3: ACK_SN (uint16, low 12 bits used)
%   Byte4: N (number of NACK entries)
%   Then N entries: each 2 bytes (uint16, low 12 bits used)
%
% Segmentation indicator SI:
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
        SNBits (1,1) double = 12
        WindowSize (1,1) double = 2048     % default for 12-bit (half range)
        MaxRetx (1,1) double = 3
        PollEveryNPDU (1,1) double = 8
        MaxPDUBytes (1,1) double = inf
    end

    properties(SetAccess=private)
        Stats (1,1) struct = struct( ...
            'TxSDU',0,'TxDataPDU',0,'TxCtrlPDU',0,'TxBytes',0, ...
            'RxDataPDU',0,'RxCtrlPDU',0,'RxSDU',0,'RxBytes',0, ...
            'Retx',0,'Ack',0,'Nack',0,'Drop',0, ...
            'DropDup',0,'StatusPDU',0)
    end

    properties(Access=private)
        Modulus (1,1) double = 4096

        % TX side
        TxQueue cell = {}
        TxMetaQueue cell = {}
        TxQHead (1,1) double = 1
        TxQCount (1,1) double = 0
        TxNextSN (1,1) double = 0
        TxSeg (1,1) struct = struct('Active',false,'SN',0,'Data',uint8([]),'Offset',0,'Total',0,'Meta',struct())
        TxBufValid logical = false(0,1) % [Modulus x 1]
        TxBufState cell = {}            % [Modulus x 1] per-SN tx state
        TxPDUCounter (1,1) double = 0

        CtrlTxQueue cell = {}        % control PDUs to send (STATUS)
        CtrlQHead (1,1) double = 1
        CtrlQCount (1,1) double = 0

        % RX side
        RxBufValid logical = false(0,1)  % [Modulus x 1]
        RxBufState cell = {}             % [Modulus x 1] segmented rx state
        RxDelivered logical = false(0,1) % [Modulus x 1]
        RxSDUQueue cell = {}
        RxMetaQueue cell = {}
        DropMetaQueue cell = {}
        RxSDUCount (1,1) double = 0
        RxDropCount (1,1) double = 0
        RxExpectedSN (1,1) double = 0
        RxMaxDist (1,1) double = 0   % farthest SN distance seen from RxExpectedSN (within window)
        StatusPending (1,1) logical = false
        Tick (1,1) double = 0
        ReassemblyDelaySlots double = zeros(128,1)
        StatusIntervals_slots double = zeros(64,1)
        ReassemblyDelayCount (1,1) double = 0
        StatusIntervalCount (1,1) double = 0
        LastStatusTick (1,1) double = NaN
        SNLifecycleUsed logical = false(0,1) % [Modulus x 1]
        SNLifecycleCount double = zeros(0,1) % [Modulus x 1]
        SNLifecycleCell cell = {}            % [Modulus x 1] event arrays
    end

    methods
        function obj = RLC_AM(cfg, varargin)
            if nargin < 1 || isempty(cfg)
                cfg = struct();
            end
            obj.Cfg = cfg;

            obj.Direction = upper(char(string(sixgr.util.structGet(cfg,"l2.rlc.am.direction",obj.Direction))));
            obj.LCID = double(sixgr.util.structGet(cfg,"l2.rlc.am.lcid",obj.LCID));
            obj.SNBits = double(sixgr.util.structGet(cfg,"l2.rlc.am.snBits",obj.SNBits));
            obj.MaxRetx = double(sixgr.util.structGet(cfg,"l2.rlc.am.maxRetx",obj.MaxRetx));
            obj.PollEveryNPDU = double(sixgr.util.structGet(cfg,"l2.rlc.am.pollEveryNPDU",obj.PollEveryNPDU));
            obj.MaxPDUBytes = double(sixgr.util.structGet(cfg,"l2.rlc.am.maxPDUBytes",obj.MaxPDUBytes));

            if obj.SNBits ~= 12
                error("sixgr:RLC_AM:SNBits","This Step-P AM implementation supports SNBits=12 only (got %g).", obj.SNBits);
            end
            obj.Modulus = 2^obj.SNBits;
            obj.WindowSize = double(sixgr.util.structGet(cfg,"l2.rlc.am.windowSize",obj.Modulus/2));

            if ~isempty(varargin)
                if mod(numel(varargin),2) ~= 0
                    error("sixgr:RLC_AM:BadNV","Name-value inputs must come in pairs.");
                end
                for i = 1:2:numel(varargin)
                    k = varargin{i}; v = varargin{i+1};
                    if isstring(k), k = char(k); end
                    switch lower(char(k))
                        case 'direction'
                            obj.Direction = upper(char(string(v)));
                        case 'lcid'
                            obj.LCID = double(v);
                        case 'logger'
                            obj.Logger = v;
                        case 'maxretx'
                            obj.MaxRetx = double(v);
                        case 'polleverynpdu'
                            obj.PollEveryNPDU = double(v);
                        case 'maxpdubytes'
                            obj.MaxPDUBytes = double(v);
                        otherwise
                            error("sixgr:RLC_AM:BadOpt","Unknown option: %s", string(k));
                    end
                end
            end

            obj.initStateArrays_();
            obj.initTxQueue_();
            obj.initCtrlQueue_();
            obj.initRxQueues_();
        end

        function reset(obj)
            obj.initTxQueue_();
            obj.TxNextSN = 0;
            obj.TxSeg = struct('Active',false,'SN',0,'Data',uint8([]),'Offset',0,'Total',0,'Meta',struct());
            obj.initStateArrays_();
            obj.TxPDUCounter = 0;
            obj.initCtrlQueue_();

            obj.initRxQueues_();
            obj.RxExpectedSN = 0;
            obj.RxMaxDist = 0;
            obj.StatusPending = false;
            obj.Tick = 0;
            obj.ReassemblyDelaySlots = zeros(128,1);
            obj.StatusIntervals_slots = zeros(64,1);
            obj.ReassemblyDelayCount = 0;
            obj.StatusIntervalCount = 0;
            obj.LastStatusTick = NaN;

            obj.Stats = struct('TxSDU',0,'TxDataPDU',0,'TxCtrlPDU',0,'TxBytes',0, ...
                'RxDataPDU',0,'RxCtrlPDU',0,'RxSDU',0,'RxBytes',0,'Retx',0,'Ack',0,'Nack',0,'Drop',0, ...
                'DropDup',0,'StatusPDU',0);
        end

        function addSDU(obj, sduBytes, varargin)
            if isempty(sduBytes), return; end
            sduBytes = localToU8(sduBytes);
            metaIn = localTraceMetaFromArgs(varargin{:});
            obj.enqueueTx_(sduBytes, metaIn);
            obj.Stats.TxSDU = obj.Stats.TxSDU + 1;
        end

        function tf = hasData(obj)
            tf = obj.TxSeg.Active || (obj.TxQCount > 0) || obj.hasPendingRetx();
        end

        function tf = hasCtrl(obj)
            tf = (obj.CtrlQCount > 0);
        end

        function tf = hasPendingRetx(obj)
            tf = false;
            if isempty(obj.TxBufValid) || ~any(obj.TxBufValid)
                return;
            end
            idx = find(obj.TxBufValid);
            for i = 1:numel(idx)
                st = obj.TxBufState{idx(i)};
                if isfield(st,'NeedsRetx') && st.NeedsRetx
                    tf = true;
                    return;
                end
            end
        end

        function [pdus, metas] = buildPDUs(obj, availBytes)
            % buildPDUs Build as many PDUs (CTRL then RETX then NEW) within availBytes.
            if nargin < 2 || isempty(availBytes)
                availBytes = inf;
            end
            budget = min(double(availBytes), double(obj.MaxPDUBytes) * 1e9);

            pdus = cell(8,1);
            metaTemplate = localMakeRLCMeta(localDefaultTraceMeta());
            metas = repmat(metaTemplate, 8, 1);
            pCount = 0;

            while budget > 0
                % 1) Control PDUs (STATUS) first
                if obj.CtrlQCount > 0
                    pdu = obj.peekCtrl_();
                    if numel(pdu) <= budget
                        [pdu, okCtrl] = obj.popCtrl_();
                        if ~okCtrl
                            break;
                        end
                        tr = localDefaultTraceMeta();
                        tr.DropCause = "RLC_AM_STATUS";
                        meta = localMakeRLCMeta(tr);
                        meta.LCID = obj.LCID;
                        meta.IsControl = true;
                        meta.Length = numel(pdu);
                        pCount = pCount + 1;
                        if pCount > numel(pdus)
                            newCap = numel(pdus) * 2;
                            pdus{newCap,1} = [];
                            metas(newCap,1) = metaTemplate;
                        end
                        pdus{pCount,1} = pdu;
                        metas(pCount,1) = meta;
                        budget = budget - numel(pdu);
                        obj.Stats.TxCtrlPDU = obj.Stats.TxCtrlPDU + 1;
                        obj.Stats.StatusPDU = obj.Stats.StatusPDU + 1;
                        obj.Stats.TxBytes = obj.Stats.TxBytes + numel(pdu);
                        continue;
                    else
                        break;
                    end
                end

                % 2) Retransmissions
                [pdu, meta] = obj.buildRetxPDU(budget);
                if ~isempty(pdu)
                    pCount = pCount + 1;
                    if pCount > numel(pdus)
                        newCap = numel(pdus) * 2;
                        pdus{newCap,1} = [];
                        metas(newCap,1) = metaTemplate;
                    end
                    pdus{pCount,1} = pdu;
                    metas(pCount,1) = meta;
                    budget = budget - numel(pdu);
                    continue;
                end

                % 3) New data
                [pdu, meta] = obj.buildNewDataPDU(budget);
                if ~isempty(pdu)
                    pCount = pCount + 1;
                    if pCount > numel(pdus)
                        newCap = numel(pdus) * 2;
                        pdus{newCap,1} = [];
                        metas(newCap,1) = metaTemplate;
                    end
                    pdus{pCount,1} = pdu;
                    metas(pCount,1) = meta;
                    budget = budget - numel(pdu);
                    continue;
                end

                break; % nothing to send
            end
            pdus = pdus(1:pCount);
            metas = metas(1:pCount);
        end


        function macSDUs = buildMACSDUs(obj, availBytes)
            % buildMACSDUs Convenience wrapper for MAC mux.
            % Returns struct array with fields: LCID, Payload
            [pdus, metas] = obj.buildPDUs(availBytes);
            n = numel(pdus);
            if n == 0
                macSDUs = struct('LCID',{},'Payload',{},'Meta',{});
                return;
            end
            macSDUs = repmat(struct('LCID',obj.LCID,'Payload',uint8([]),'Meta',metas(1)), n, 1);
            for i = 1:n
                macSDUs(i).LCID = obj.LCID;
                macSDUs(i).Payload = pdus{i};
                macSDUs(i).Meta = metas(i);
            end
        end

        function receivePDU(obj, pduBytes, varargin)
            % receivePDU Process incoming data/control PDU.
            if isempty(pduBytes), return; end
            metaIn = localTraceMetaFromArgs(varargin{:});
            obj.Tick = localResolveRxTick(obj.Tick, metaIn);
            pduBytes = localToU8(pduBytes);

            [kind, hdr, payload] = localDecodeAM(pduBytes);

            if strcmp(kind,'STATUS')
                obj.Stats.RxCtrlPDU = obj.Stats.RxCtrlPDU + 1;
                obj.onStatusReceived(hdr.ACK_SN, hdr.NACK_SN);
                return;
            end

            % Data PDU
            obj.Stats.RxDataPDU = obj.Stats.RxDataPDU + 1;

            sn = double(hdr.SN);
            si = double(hdr.SI);
            so = double(hdr.SO);
            poll = logical(hdr.Poll);
            rxMeta = localTraceMetaFromArgs(metaIn);
            rxMeta.RLC_SN = sn;
            rxMeta.SegmentOffset = so;
            rxMeta.DropCause = "";

            % Track farthest SN seen from RxExpectedSN within window
            d = localSNDistance(sn, obj.RxExpectedSN, obj.Modulus);
            if d < obj.WindowSize
                obj.RxMaxDist = max(obj.RxMaxDist, d);
            end

            if poll
                obj.StatusPending = true;
            end

            if si == 0
                % complete SDU
                rxMeta.DeliverySlot = obj.Tick;
                obj.enqueueSDU_(payload, rxMeta);
                idxSN = mod(round(sn), obj.Modulus) + 1;
                obj.RxDelivered(idxSN) = true;
                obj.Stats.RxSDU = obj.Stats.RxSDU + 1;
                obj.Stats.RxBytes = obj.Stats.RxBytes + numel(payload);
                obj.localLogSN(sn, "RX_DELIVER_COMPLETE");
            else
                % segmented: use SO-based reassembly
                st = [];
                idxSN = mod(round(sn), obj.Modulus) + 1;
                if obj.RxBufValid(idxSN)
                    st = obj.RxBufState{idxSN};
                else
                    st = struct('Segs',repmat(struct('SO',0,'Data',uint8([])), 8, 1), 'SegCount',0, 'Total',NaN, ...
                        'Meta',rxMeta, 'FirstTick',obj.Tick);
                end

                % Deduplicate by SO
                segCount = obj.localGetSegCount_(st);
                if segCount > 0
                    soVec = [st.Segs(1:segCount).SO];
                    if any(soVec == so)
                        obj.Stats.DropDup = obj.Stats.DropDup + 1;
                        obj.Stats.Drop = obj.Stats.Drop + 1;
                        dmeta = rxMeta;
                        dmeta.DropCause = "RLC_AM_DUPLICATE_SEGMENT";
                        obj.enqueueDrop_(dmeta);
                        obj.localLogSN(sn, "RX_DROP_DUP_SEG");
                        return;
                    end
                end

                st = obj.localAppendRxSegment_(st, so, payload);
                if si == 2
                    st.Total = so + numel(payload);
                end

                if isfinite(st.Total)
                    [ok, assembled] = localAssembleSegments(st.Segs(1:obj.localGetSegCount_(st)), st.Total);
                    if ok
                        m = localTraceMetaFromArgs(st.Meta);
                        m.RLC_SN = sn;
                        m.SegmentOffset = 0;
                        m.DeliverySlot = obj.Tick;
                        obj.enqueueSDU_(assembled, m);
                        if isfinite(double(st.FirstTick))
                            obj.appendReassemblyDelay_(max(0, obj.Tick - double(st.FirstTick)));
                        end
                        obj.RxDelivered(idxSN) = true;
                        obj.Stats.RxSDU = obj.Stats.RxSDU + 1;
                        obj.Stats.RxBytes = obj.Stats.RxBytes + numel(assembled);
                        obj.RxBufValid(idxSN) = false;
                        obj.RxBufState{idxSN} = [];
                        obj.localLogSN(sn, "RX_REASSEMBLED");
                    else
                        obj.RxBufValid(idxSN) = true;
                        obj.RxBufState{idxSN} = st;
                    end
                else
                    obj.RxBufValid(idxSN) = true;
                    obj.RxBufState{idxSN} = st;
                end
            end

            % If we have pending STATUS, enqueue one now (best-effort)
            if obj.StatusPending
                obj.enqueueStatusPDU(inf);
            end
        end

        function [sdus, metas] = pullSDUs(obj)
            if obj.RxSDUCount > 0
                sdus = obj.RxSDUQueue(1:obj.RxSDUCount);
            else
                sdus = {};
            end
            if nargout >= 2
                if obj.RxSDUCount > 0
                    metas = obj.RxMetaQueue(1:obj.RxSDUCount);
                else
                    metas = {};
                end
            end
            obj.RxSDUCount = 0;
            % Advance RxExpectedSN over contiguous delivered SNs
            advanced = true;
            while advanced
                advanced = false;
                idxExp = mod(round(obj.RxExpectedSN), obj.Modulus) + 1;
                if idxExp >= 1 && idxExp <= numel(obj.RxDelivered) && obj.RxDelivered(idxExp)
                    obj.RxDelivered(idxExp) = false;
                    obj.RxExpectedSN = mod(obj.RxExpectedSN + 1, obj.Modulus);
                    obj.RxMaxDist = max(0, obj.RxMaxDist - 1);
                    advanced = true;
                end
            end
        end

        function drops = pullDropMeta(obj)
            if obj.RxDropCount > 0
                drops = obj.DropMetaQueue(1:obj.RxDropCount);
            else
                drops = {};
            end
            obj.RxDropCount = 0;
        end

        function lifecycle = pullSNLifecycle(obj)
            idx = find(obj.SNLifecycleUsed);
            n = numel(idx);
            lifecycle = struct('SN',cell(n,1),'Events',cell(n,1));
            for i = 1:n
                lifecycle(i).SN = double(idx(i) - 1);
                c = max(0, round(double(obj.SNLifecycleCount(idx(i)))));
                if c > 0
                    lifecycle(i).Events = obj.SNLifecycleCell{idx(i)}(1:c);
                else
                    lifecycle(i).Events = struct('Tick',{},'Event',{});
                end
            end
            obj.SNLifecycleUsed(:) = false;
            obj.SNLifecycleCount(:) = 0;
            obj.SNLifecycleCell(:) = {[]};
        end

        function d = getReassemblyDelaySlots(obj)
            if obj.ReassemblyDelayCount > 0
                d = obj.ReassemblyDelaySlots(1:obj.ReassemblyDelayCount);
            else
                d = zeros(0,1);
            end
        end

        function s = getStatusIntervals(obj)
            if obj.StatusIntervalCount > 0
                s = obj.StatusIntervals_slots(1:obj.StatusIntervalCount);
            else
                s = zeros(0,1);
            end
        end

        function onStatusReceived(obj, ackSN, nackList)
            % onStatusReceived Apply STATUS feedback to TX buffer.
            ackSN = double(mod(ackSN, obj.Modulus));
            nackMask = false(max(1, obj.Modulus), 1);
            for i = 1:numel(nackList)
                idxN = mod(round(double(nackList(i))), obj.Modulus) + 1;
                nackMask(idxN) = true;
            end

            if isempty(obj.TxBufValid) || ~any(obj.TxBufValid)
                return;
            end

            idxAct = find(obj.TxBufValid);
            for i = 1:numel(idxAct)
                idxSN = idxAct(i);
                sn = double(idxSN - 1);
                st = obj.TxBufState{idxSN};

                % If SN is "before" ACK_SN in modulo sense, then either ACK or NACK
                if localSNLess(sn, ackSN, obj.Modulus)
                    if idxSN <= numel(nackMask) && nackMask(idxSN)
                        % NACK: schedule retransmission
                        st.NeedsRetx = true;
                        st.RetxSegIdx = 1;
                        st.RetxCause = "STATUS_NACK";
                        obj.Stats.Nack = obj.Stats.Nack + 1;
                        obj.localLogSN(sn, "STATUS_NACK");
                    else
                        % ACK: remove
                        obj.TxBufValid(idxSN) = false;
                        obj.TxBufState{idxSN} = [];
                        obj.Stats.Ack = obj.Stats.Ack + 1;
                        obj.localLogSN(sn, "STATUS_ACK");
                        continue;
                    end
                end
                obj.TxBufState{idxSN} = st;
            end
        end
    end

    methods(Access=private)
        function initStateArrays_(obj)
            m = max(1, round(double(obj.Modulus)));
            obj.TxBufValid = false(m,1);
            obj.TxBufState = cell(m,1);
            obj.RxBufValid = false(m,1);
            obj.RxBufState = cell(m,1);
            obj.RxDelivered = false(m,1);
            obj.SNLifecycleUsed = false(m,1);
            obj.SNLifecycleCount = zeros(m,1);
            obj.SNLifecycleCell = cell(m,1);
        end

        function initTxQueue_(obj)
            obj.TxQueue = cell(128,1);
            obj.TxMetaQueue = cell(128,1);
            obj.TxQHead = 1;
            obj.TxQCount = 0;
        end

        function enqueueTx_(obj, sdu, meta)
            idx = obj.TxQCount + 1;
            if idx > numel(obj.TxQueue)
                obj.growTxQueue_(max(numel(obj.TxQueue) * 2, idx));
            end
            pos = obj.TxQHead + obj.TxQCount;
            cap = numel(obj.TxQueue);
            if pos > cap
                pos = pos - cap;
            end
            obj.TxQueue{pos} = sdu;
            obj.TxMetaQueue{pos} = meta;
            obj.TxQCount = idx;
        end

        function [sdu, meta, ok] = popTx_(obj)
            sdu = uint8([]);
            meta = localDefaultTraceMeta();
            ok = false;
            if obj.TxQCount <= 0
                return;
            end
            pos = obj.TxQHead;
            sdu = localToU8(obj.TxQueue{pos});
            if isempty(obj.TxMetaQueue{pos})
                meta = localDefaultTraceMeta();
            else
                meta = localTraceMetaFromArgs(obj.TxMetaQueue{pos});
            end
            obj.TxQueue{pos} = [];
            obj.TxMetaQueue{pos} = [];
            obj.TxQHead = pos + 1;
            if obj.TxQHead > numel(obj.TxQueue)
                obj.TxQHead = 1;
            end
            obj.TxQCount = obj.TxQCount - 1;
            if obj.TxQCount <= 0
                obj.TxQHead = 1;
                obj.TxQCount = 0;
            end
            ok = true;
        end

        function growTxQueue_(obj, newCap)
            cap = numel(obj.TxQueue);
            newCap = max(cap + 1, round(double(newCap)));
            qNew = cell(newCap,1);
            mNew = cell(newCap,1);
            if obj.TxQCount > 0
                idx = localRingLinearIndices(obj.TxQHead, obj.TxQCount, cap);
                qNew(1:obj.TxQCount) = obj.TxQueue(idx);
                mNew(1:obj.TxQCount) = obj.TxMetaQueue(idx);
            end
            obj.TxQueue = qNew;
            obj.TxMetaQueue = mNew;
            obj.TxQHead = 1;
        end

        function initCtrlQueue_(obj)
            obj.CtrlTxQueue = cell(32,1);
            obj.CtrlQHead = 1;
            obj.CtrlQCount = 0;
        end

        function enqueueCtrl_(obj, pdu)
            idx = obj.CtrlQCount + 1;
            if idx > numel(obj.CtrlTxQueue)
                obj.growCtrlQueue_(max(numel(obj.CtrlTxQueue) * 2, idx));
            end
            pos = obj.CtrlQHead + obj.CtrlQCount;
            cap = numel(obj.CtrlTxQueue);
            if pos > cap
                pos = pos - cap;
            end
            obj.CtrlTxQueue{pos} = pdu;
            obj.CtrlQCount = idx;
        end

        function [pdu, ok] = popCtrl_(obj)
            pdu = uint8([]);
            ok = false;
            if obj.CtrlQCount <= 0
                return;
            end
            pos = obj.CtrlQHead;
            pdu = obj.CtrlTxQueue{pos};
            obj.CtrlTxQueue{pos} = [];
            obj.CtrlQHead = pos + 1;
            if obj.CtrlQHead > numel(obj.CtrlTxQueue)
                obj.CtrlQHead = 1;
            end
            obj.CtrlQCount = obj.CtrlQCount - 1;
            if obj.CtrlQCount <= 0
                obj.CtrlQHead = 1;
                obj.CtrlQCount = 0;
            end
            ok = true;
        end

        function pdu = peekCtrl_(obj)
            pdu = uint8([]);
            if obj.CtrlQCount <= 0
                return;
            end
            pdu = obj.CtrlTxQueue{obj.CtrlQHead};
        end

        function growCtrlQueue_(obj, newCap)
            cap = numel(obj.CtrlTxQueue);
            newCap = max(cap + 1, round(double(newCap)));
            qNew = cell(newCap,1);
            if obj.CtrlQCount > 0
                idx = localRingLinearIndices(obj.CtrlQHead, obj.CtrlQCount, cap);
                qNew(1:obj.CtrlQCount) = obj.CtrlTxQueue(idx);
            end
            obj.CtrlTxQueue = qNew;
            obj.CtrlQHead = 1;
        end

        function initRxQueues_(obj)
            obj.RxSDUQueue = cell(128,1);
            obj.RxMetaQueue = cell(128,1);
            obj.DropMetaQueue = cell(64,1);
            obj.RxSDUCount = 0;
            obj.RxDropCount = 0;
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
            if idx > numel(obj.DropMetaQueue)
                newCap = max(numel(obj.DropMetaQueue) * 2, idx);
                obj.DropMetaQueue{newCap,1} = [];
            end
            obj.DropMetaQueue{idx,1} = meta;
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

        function appendStatusInterval_(obj, v)
            idx = obj.StatusIntervalCount + 1;
            if idx > numel(obj.StatusIntervals_slots)
                newCap = max(numel(obj.StatusIntervals_slots) * 2, idx);
                obj.StatusIntervals_slots(newCap,1) = 0;
            end
            obj.StatusIntervals_slots(idx,1) = double(v);
            obj.StatusIntervalCount = idx;
        end

        function count = localGetSegCount_(obj, st)
            %#ok<INUSD>
            count = 0;
            try
                count = double(sixgr.util.structGet(st, "SegCount", 0));
            catch
                count = 0;
            end
            if count > 0
                return;
            end
            try
                segsCell = st.SegPDUs;
                count = double(numel(segsCell));
                return;
            catch
                count = 0;
            end
            try
                segsStruct = st.Segs;
                count = double(numel(segsStruct));
            catch
                count = 0;
            end
        end

        function st = localAppendSegPDU_(obj, st, pdu)
            %#ok<INUSD>
            isScalarStruct = false;
            try
                isScalarStruct = (numel(st) == 1) && isfield(st, 'SegPDUs');
            catch
                isScalarStruct = false;
            end
            if ~isScalarStruct
                st = struct('SegPDUs',{{}},'SegCount',0,'NeedsRetx',false,'RetxSegIdx',1,'RetxCount',0, ...
                    'Meta',localDefaultTraceMeta(),'RetxCause',"",'LastSO',0);
            end
            segs = {};
            try
                segs = st.SegPDUs;
            catch
                segs = {};
            end
            if isempty(segs)
                segs = {pdu};
            else
                segs{end+1,1} = pdu;
            end
            st.SegPDUs = segs;
            st.SegCount = numel(segs);
        end

        function st = localAppendRxSegment_(obj, st, so, payload)
            %#ok<INUSD>
            isScalarStruct = false;
            try
                isScalarStruct = (numel(st) == 1) && isfield(st, 'Segs');
            catch
                isScalarStruct = false;
            end
            if ~isScalarStruct
                st = struct('Segs',struct('SO',{},'Data',{}), 'SegCount',0, 'Total',NaN, ...
                    'Meta',localDefaultTraceMeta(), 'FirstTick',obj.Tick);
            end
            segs = struct('SO',{},'Data',{});
            try
                segs = st.Segs;
            catch
                segs = struct('SO',{},'Data',{});
            end
            segs(end+1,1) = struct('SO',so,'Data',payload);
            st.Segs = segs;
            st.SegCount = numel(segs);
        end

        function localLogSN(obj, sn, event)
            idx = mod(round(double(sn)), obj.Modulus) + 1;
            e = struct("Tick", obj.Tick, "Event", string(event));
            if ~(idx >= 1 && idx <= numel(obj.SNLifecycleUsed))
                return;
            end
            if ~obj.SNLifecycleUsed(idx)
                obj.SNLifecycleUsed(idx) = true;
                obj.SNLifecycleCount(idx) = 1;
                obj.SNLifecycleCell{idx} = repmat(e, 8, 1);
                obj.SNLifecycleCell{idx}(1) = e;
                return;
            end
            c = max(0, round(double(obj.SNLifecycleCount(idx)))) + 1;
            lst = obj.SNLifecycleCell{idx};
            if c > numel(lst)
                lst(max(numel(lst) * 2, c),1) = e;
            end
            lst(c) = e;
            obj.SNLifecycleCell{idx} = lst;
            obj.SNLifecycleCount(idx) = c;
        end

        function [pdu, meta] = buildRetxPDU(obj, maxBytes)
            pdu = uint8([]);
            meta = localMakeRLCMeta(localDefaultTraceMeta());
            meta.LCID = obj.LCID;
            meta.IsControl = false;

            if isempty(obj.TxBufValid) || ~any(obj.TxBufValid)
                return;
            end

            maxBytes = min(double(maxBytes), double(obj.MaxPDUBytes));

            % Find first SN needing retx (stable order by SN distance from TxNextSN)
            sns = find(obj.TxBufValid) - 1;
            if isempty(sns), return; end
            sns = sort(sns);

            for i = 1:numel(sns)
                sn = sns(i);
                idxSN = sn + 1;
                st = obj.TxBufState{idxSN};
                if ~isfield(st,'NeedsRetx') || ~st.NeedsRetx
                    continue;
                end

                if st.RetxCount >= obj.MaxRetx
                    dmeta = localTraceMetaFromArgs(sixgr.util.structGet(st, "Meta", struct()));
                    dmeta.RLC_SN = sn;
                    dmeta.DropCause = "RLC_AM_MAX_RETX";
                    obj.enqueueDrop_(dmeta);
                    obj.TxBufValid(idxSN) = false;
                    obj.TxBufState{idxSN} = [];
                    obj.Stats.Drop = obj.Stats.Drop + 1;
                    obj.localLogSN(sn, "DROP_MAX_RETX");
                    continue;
                end

                segCount = obj.localGetSegCount_(st);
                segs = st.SegPDUs;
                if segCount <= 0
                    st.NeedsRetx = false;
                    obj.TxBufState{idxSN} = st;
                    continue;
                end

                idx = max(1, min(double(st.RetxSegIdx), segCount));
                cand = segs{idx};

                if numel(cand) > maxBytes
                    % can't fit even one segment; stop
                    return;
                end

                % For retx, set poll on the last segment to trigger STATUS
                isLastSeg = (idx == segCount);
                cand = localSetPollBit(cand, isLastSeg);

                pdu = cand;
                tr = localTraceMetaFromArgs(sixgr.util.structGet(st, "Meta", struct()));
                tr.RLC_SN = sn;
                tr.SegmentOffset = double(sixgr.util.structGet(st, "LastSO", 0));
                tr.DropCause = string(sixgr.util.structGet(st, "RetxCause", "RLC_AM_RETX"));
                meta = localMakeRLCMeta(tr);
                meta.LCID = obj.LCID;
                meta.IsControl = false;
                meta.SN = sn;
                meta.Length = numel(pdu);
                meta.Poll = isLastSeg;

                % Update retransmission state
                st.RetxSegIdx = idx + 1;
                if st.RetxSegIdx > segCount
                    st.RetxSegIdx = 1;
                    st.NeedsRetx = false;
                    st.RetxCount = st.RetxCount + 1;
                    st.RetxCause = "";
                end
                obj.TxBufState{idxSN} = st;

                obj.Stats.TxDataPDU = obj.Stats.TxDataPDU + 1;
                obj.Stats.TxBytes = obj.Stats.TxBytes + numel(pdu);
                obj.Stats.Retx = obj.Stats.Retx + 1;
                obj.localLogSN(sn, "TX_RETX");
                return;
            end
        end

        function [pdu, meta] = buildNewDataPDU(obj, maxBytes)
            pdu = uint8([]);
            meta = localMakeRLCMeta(localDefaultTraceMeta());
            meta.LCID = obj.LCID;
            meta.IsControl = false;

            maxBytes = min(double(maxBytes), double(obj.MaxPDUBytes));

            if ~(obj.TxSeg.Active || (obj.TxQCount > 0))
                return;
            end

            % Ensure current SDU context
            if ~obj.TxSeg.Active
                [sdu, sduMeta, okPop] = obj.popTx_();
                if ~okPop
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
                obj.TxSeg.Active = false;
                return;
            end

            baseHdr = 2; % for 12-bit AM in this simplified format

            % Determine if we can send complete SDU (no SO)
            payloadMaxComplete = maxBytes - baseHdr;
            if off == 0 && rem <= payloadMaxComplete
                si = 0;
                soPresent = false;
                so = 0;
                chunkLen = rem;
            else
                soPresent = true;
                segHdr = baseHdr + 2;
                payloadMax = maxBytes - segHdr;
                if payloadMax <= 0
                    obj.Stats.Drop = obj.Stats.Drop + 1;
                    return;
                end
                chunkLen = min(rem, payloadMax);
                if off == 0 && chunkLen < rem
                    si = 1;
                elseif (off + chunkLen) == total
                    si = 2;
                else
                    si = 3;
                end
                so = off;
            end

            % Poll logic (set poll on complete or last segment occasionally)
            obj.TxPDUCounter = obj.TxPDUCounter + 1;
            pollNow = (mod(obj.TxPDUCounter, max(1,obj.PollEveryNPDU)) == 0) && (si == 0 || si == 2);

            hdr = localEncodeAMData(sn, si, pollNow, soPresent, so);
            chunk = obj.TxSeg.Data((off+1):(off+chunkLen));
            pdu = [hdr; chunk(:)];
            tr = localTraceMetaFromArgs(obj.TxSeg.Meta);
            tr.RLC_SN = sn;
            tr.SegmentOffset = so;
            tr.DropCause = "";
            meta = localMakeRLCMeta(tr);
            meta.LCID = obj.LCID;
            meta.IsControl = false;
            meta.SN = sn;
            meta.SI = si;
            meta.SO = so;
            meta.Poll = pollNow;
            meta.Length = numel(pdu);

            obj.Stats.TxDataPDU = obj.Stats.TxDataPDU + 1;
            obj.Stats.TxBytes = obj.Stats.TxBytes + numel(pdu);

            % Store segment in Tx buffer
            st = [];
            idxSN = mod(round(sn), obj.Modulus) + 1;
            if obj.TxBufValid(idxSN)
                st = obj.TxBufState{idxSN};
            else
                st = struct('SegPDUs',{{}},'SegCount',0,'NeedsRetx',false,'RetxSegIdx',1,'RetxCount',0, ...
                    'Meta',tr,'RetxCause',"",'LastSO',so);
            end
            st = obj.localAppendSegPDU_(st, pdu);
            st.Meta = tr;
            st.LastSO = so;
            obj.TxBufValid(idxSN) = true;
            obj.TxBufState{idxSN} = st;
            obj.localLogSN(sn, "TX_NEW");

            % Advance segmentation state
            off2 = off + chunkLen;
            if si == 0 || off2 >= total
                obj.TxSeg.Active = false;
                obj.TxSeg.Data = uint8([]);
                obj.TxSeg.Offset = 0;
                obj.TxSeg.Total = 0;
                obj.TxNextSN = mod(obj.TxNextSN + 1, obj.Modulus);
            else
                obj.TxSeg.Offset = off2;
            end
        end

        function enqueueStatusPDU(obj, maxBytes)
            % enqueueStatusPDU Build and enqueue a STATUS PDU if needed.
            if ~obj.StatusPending
                return;
            end
            if nargin < 2 || isempty(maxBytes)
                maxBytes = inf;
            end

            [statusPDU, ok] = obj.buildStatusPDU(maxBytes);
            if ok
                obj.enqueueCtrl_(statusPDU);
                obj.StatusPending = false;
                if isfinite(obj.LastStatusTick)
                    obj.appendStatusInterval_(max(0, obj.Tick - obj.LastStatusTick));
                end
                obj.LastStatusTick = obj.Tick;
            end
        end

        function [pdu, ok] = buildStatusPDU(obj, maxBytes)
            % Build simplified STATUS: ACK_SN + NACK list for missing/incomplete SNs.
            ok = false;
            pdu = uint8([]);

            maxBytes = double(maxBytes);
            if maxBytes < 4
                return;
            end

            % Advance ACK_SN over contiguous delivered SNs (without removing; removal happens in pullSDUs)
            ackSN = obj.RxExpectedSN;

            % Build NACK list between ackSN and ackSN+RxMaxDist
            maxNByDistance = max(0, round(double(obj.RxMaxDist)) + 1);
            nacks = zeros(maxNByDistance, 1);
            nNacks = 0;
            for d = 0:obj.RxMaxDist
                sn = mod(obj.RxExpectedSN + d, obj.Modulus);
                if sn == ackSN
                    % skip (ackSN refers to first missing)
                end
                idxSN = sn + 1;
                if idxSN >= 1 && idxSN <= numel(obj.RxDelivered) && obj.RxDelivered(idxSN)
                    continue;
                end
                % incomplete segmented SDU or not-seen yet -> NACK
                nNacks = nNacks + 1;
                if nNacks > numel(nacks)
                    nacks(max(2 * numel(nacks), nNacks),1) = 0;
                end
                nacks(nNacks) = sn;
            end

            % Determine ACK_SN as first SN not delivered starting from RxExpectedSN
            while true
                idxAck = ackSN + 1;
                if ~(idxAck >= 1 && idxAck <= numel(obj.RxDelivered) && obj.RxDelivered(idxAck))
                    break;
                end
                ackSN = mod(ackSN + 1, obj.Modulus);
            end

            % Compose, truncating NACK list to fit maxBytes
            base = uint8([128]); % 0x80
            ack16 = uint16(ackSN);
            ackBytes = typecast(ack16,'uint8'); % little-endian
            ackBE = uint8([ackBytes(2); ackBytes(1)]); % big-endian

            % Reserve byte for N
            head = [base; ackBE; uint8(0)];

            remaining = maxBytes - numel(head);
            maxN = floor(remaining / 2);
            if nNacks > 0
                nacks = nacks(1:min(nNacks, maxN));
            else
                nacks = zeros(0,1);
            end
            N = numel(nacks);

            nackBytes = zeros(2 * N, 1, 'uint8');
            for i = 1:N
                v = uint16(nacks(i));
                b = typecast(v,'uint8');
                j = (i - 1) * 2 + 1;
                nackBytes(j) = uint8(b(2));
                nackBytes(j + 1) = uint8(b(1));
            end

            head(4) = uint8(N);
            pdu = [head; nackBytes];

            ok = true;
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

function [kind, hdr, payload] = localDecodeAM(pdu)
    % Decode simplified AM header.
    b1 = uint8(pdu(1));
    if bitand(b1, uint8(128)) ~= 0
        % STATUS
        kind = 'STATUS';
        if numel(pdu) < 4
            error("sixgr:RLC_AM:BadStatus","STATUS PDU too short.");
        end
        ackSN = double(uint16(pdu(2))*256 + uint16(pdu(3)));
        N = double(pdu(4));
        hdr = struct('ACK_SN',ackSN,'NACK_SN',[]);
        expect = 4 + 2*N;
        if numel(pdu) < expect
            N = floor((numel(pdu)-4)/2);
        end
        nacks = zeros(1,N);
        idx = 5;
        for i = 1:N
            nacks(i) = double(uint16(pdu(idx))*256 + uint16(pdu(idx+1)));
            idx = idx + 2;
        end
        hdr.NACK_SN = nacks;
        payload = uint8([]);
        return;
    end

    kind = 'DATA';
    if numel(pdu) < 2
        error("sixgr:RLC_AM:BadData","DATA PDU too short.");
    end
    poll = bitand(b1, uint8(64)) ~= 0;
    si = bitand(bitshift(b1,-4), uint8(3)); % bits5..4
    snHi = bitand(b1, uint8(15));          % bits3..0
    snLo = uint8(pdu(2));
    sn = double(snHi)*256 + double(snLo);
    so = 0;
    hdrLen = 2;

    if si ~= 0
        if numel(pdu) < 4
            error("sixgr:RLC_AM:BadData","Segmented DATA PDU too short.");
        end
        so = double(uint16(pdu(3))*256 + uint16(pdu(4)));
        hdrLen = 4;
    end
    hdr = struct('Poll',poll,'SI',double(si),'SN',sn,'SO',so,'HeaderLen',hdrLen);
    payload = pdu((hdrLen+1):end);
    payload = payload(:);
end

function hdr = localEncodeAMData(sn, si, poll, soPresent, so)
    sn = mod(double(sn), 4096);
    snHi = floor(sn/256); % 0..15
    snLo = mod(sn, 256);  % 0..255
    b1 = uint8(0);
    if poll
        b1 = b1 + uint8(64);
    end
    b1 = b1 + bitshift(uint8(si),4);
    b1 = b1 + uint8(snHi);
    b2 = uint8(snLo);

    if ~soPresent
        hdr = [b1; b2];
    else
        so16 = uint16(so);
        soBytes = typecast(so16,'uint8');
        hdr = [b1; b2; uint8(soBytes(2)); uint8(soBytes(1))]; % big-endian
    end
end

function pdu2 = localSetPollBit(pdu, poll)
    pdu2 = pdu;
    if isempty(pdu2), return; end
    if poll
        pdu2(1) = bitor(uint8(pdu2(1)), uint8(64));
    else
        pdu2(1) = bitand(uint8(pdu2(1)), uint8(191)); % clear bit6
    end
end

function d = localSNDistance(sn, base, modulus)
    d = mod(double(sn) - double(base), double(modulus));
end

function tf = localSNLess(a, b, modulus)
    % True if a is "before" b within half-modulus.
    diff = mod(double(b) - double(a), double(modulus));
    tf = (diff > 0) && (diff < double(modulus)/2);
end

function [ok, assembled] = localAssembleSegments(segs, totalLen)
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

function idx = localRingLinearIndices(head, count, cap)
if count <= 0
    idx = zeros(0,1);
    return;
end
idx = head + (0:count-1);
idx = mod(idx - 1, cap) + 1;
idx = idx(:);
end

function metas = localEmptyRLCMeta()
metas = struct('LCID',{},'IsControl',{},'SN',{},'SI',{},'SO',{},'Poll',{},'Length',{}, ...
    'PktId',{},'FlowId',{},'QFI',{},'CreationSlot',{},'CreationTime_s',{}, ...
    'PDCP_SN',{},'RLC_SN',{},'SegmentOffset',{},'HARQProcess',{}, ...
    'GrantSlot',{},'DeliverySlot',{},'DropCause',{});
end

function meta = localMakeRLCMeta(trace)
tr = localTraceMetaFromArgs(trace);
meta = struct('LCID',NaN,'IsControl',false,'SN',NaN,'SI',NaN,'SO',NaN,'Poll',false,'Length',0, ...
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
