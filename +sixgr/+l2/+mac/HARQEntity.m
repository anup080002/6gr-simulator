classdef HARQEntity < handle
% sixgr.l2.mac.HARQEntity
% Simple HARQ process manager for MAC/PHY integration.
%
% This class tracks HARQ process state per UE and per direction (DL/UL).
% It does NOT implement soft-combining arithmetic itself; it provides the
% process ID, redundancy version (RV) sequence, NDI toggling, and lifecycle
% ownership for the position-aware PHY soft buffer.
%
% Typical usage pattern (gNB DL scheduler)
%   harq = sixgr.l2.mac.HARQEntity(cfg,'Direction','DL');
%   txp = harq.allocate(rnti, slot, tbsBytes, 'NewData', true);
%   % build TB bytes for UE (MAC PDU) ...
%   harq.onTx(rnti, txp.HARQ.HarqID, tbBytes, grant, slot);
%   % later, when feedback arrives:
%   harq.onFeedback(rnti, harqId, ack);
%
% Typical usage pattern (UE UL transmitter)
%   harqUE = sixgr.l2.mac.HARQEntity(cfg,'Direction','UL');
%   txp = harqUE.allocate(rnti, slot, tbsBytes, 'NewData', true);
%   harqUE.onTx(...); % store TB to repeat on NACK
%   % gNB provides ACK/NACK later; UE calls onFeedback(...)
%
% Notes
%  - HARQ process IDs are exposed as 0-based (0..N-1) to match 5G Toolbox /
%    DCI conventions, while internal indexing is 1-based.
%  - RV sequence follows the common 0,2,3,1 cycling.
%  - MaxRetx is "max retransmissions" (excluding initial transmission).
%  - Soft-combining arithmetic is performed by sixgr.phy.harq.combineSoftLLR.
%    HARQEntity stores and clears the returned soft-buffer state so RV
%    observations are paired by process identity and coding-layout hash.
%
% Keep this file ASCII-only.

    properties
        Direction (1,:) char = 'DL'         % 'DL' or 'UL'
        NumProcesses (1,1) double = 16
        MaxRetx (1,1) double = 3
        RVSequence (1,:) double = [0 2 3 1]
        StoreTB (1,1) logical = true
        StaleProcessTimeoutSlots (1,1) double = NaN
        Logger = []                         % optional sixgr.core.Logger
    end

    properties(SetAccess=private)
        % UE list and per-UE process state cell array
        UEList (1,:) double = double.empty(1,0)
        UEProcs = {}                        % {NUE} each is struct array NumProcesses
    end

    properties
        Stats = struct('Tx',0,'Retx',0,'Ack',0,'Nack',0,'Drop',0, ...
            'TimeoutDrop',0,'StaleFeedbackIgnored',0,'SoftBufferStore',0, ...
            'SoftBufferClear',0,'FirstSuccessDelivery',0)
    end

    methods
        function obj = HARQEntity(cfg, varargin)
            %#ok<INUSD> cfg (reserved for future)
            if nargin < 1
                cfg = struct(); %#ok<NASGU>
            end

            % Parse overrides
            if ~isempty(varargin)
                if mod(numel(varargin),2) ~= 0
                    error('sixgr:HARQEntity:BadNV','Name-value inputs must come in pairs.');
                end
                for i = 1:2:numel(varargin)
                    key = varargin{i};
                    val = varargin{i+1};
                    if isstring(key), key = char(key); end
                    switch lower(char(key))
                        case 'direction'
                            obj.Direction = upper(char(string(val)));
                        case 'numprocesses'
                            obj.NumProcesses = double(val);
                        case 'maxretx'
                            obj.MaxRetx = double(val);
                        case 'rvsequence'
                            obj.RVSequence = double(val(:).');
                        case 'storetb'
                            obj.StoreTB = logical(val);
                        case 'staleprocesstimeoutslots'
                            obj.StaleProcessTimeoutSlots = double(val);
                        case 'logger'
                            obj.Logger = val;
                    end
                end
            end

            obj.NumProcesses = max(1, round(obj.NumProcesses));
            obj.MaxRetx = max(0, round(obj.MaxRetx));

            % If cfg has mac.harq.*, use it as defaults unless overridden above
            try
                obj.MaxRetx = double(sixgr.util.structGet(cfg,"mac.harq.maxRetx",obj.MaxRetx));
                obj.NumProcesses = double(sixgr.util.structGet(cfg,"mac.harq.numProcesses", ...
                    sixgr.util.structGet(cfg,"phy.harq.nProcesses",obj.NumProcesses)));
                obj.StaleProcessTimeoutSlots = double(sixgr.util.structGet(cfg,"mac.harq.staleProcessTimeoutSlots", ...
                    sixgr.util.structGet(cfg,"phy.harq.staleProcessTimeoutSlots",obj.StaleProcessTimeoutSlots)));
            catch
            end
            if ~(isfinite(obj.StaleProcessTimeoutSlots) && obj.StaleProcessTimeoutSlots > 0)
                rttSlots = double(sixgr.util.structGet(cfg, "tdd_timing.harq_roundtrip_slots", NaN));
                if isfinite(rttSlots) && rttSlots > 0
                    obj.StaleProcessTimeoutSlots = 2 * rttSlots;
                else
                    feedbackSlots = double(sixgr.util.structGet(cfg, "phy.harq.feedbackTimingSlots", ...
                        sixgr.util.structGet(cfg, "mac.harq.k1", 4)));
                    if ~(isfinite(feedbackSlots) && feedbackSlots > 0)
                        feedbackSlots = 4;
                    end
                    obj.StaleProcessTimeoutSlots = max(16, 4 * feedbackSlots);
                end
            end
            obj.NumProcesses = max(1, round(obj.NumProcesses));
            obj.MaxRetx = max(0, round(obj.MaxRetx));
            obj.StaleProcessTimeoutSlots = max(1, round(double(obj.StaleProcessTimeoutSlots)));
        end

        function reset(obj)
            obj.UEList = double.empty(1,0);
            obj.UEProcs = {};
            obj.Stats = struct('Tx',0,'Retx',0,'Ack',0,'Nack',0,'Drop',0, ...
                'TimeoutDrop',0,'StaleFeedbackIgnored',0,'SoftBufferStore',0, ...
                'SoftBufferClear',0,'FirstSuccessDelivery',0);
        end

        function tf = hasUE(obj, rnti)
            tf = any(obj.UEList == double(rnti));
        end

        function tf = hasPendingRetx(obj, rnti, currentSlot)
            if nargin < 3
                currentSlot = NaN;
            end
            obj.expireStaleProcesses(double(rnti), currentSlot);
            [ui, procs] = obj.getUE(double(rnti), false);
            if ui < 1
                tf = false;
                return;
            end
            tf = any([procs.NeedsRetx]);
        end

        function tf = hasFreeProcess(obj, rnti, currentSlot)
            % New-data grants must be blocked cleanly when every HARQ
            % process is active/awaiting feedback. TS 38.321 HARQ process
            % exhaustion is a scheduler gating condition, not a runtime
            % exception path.
            if nargin < 3
                currentSlot = NaN;
            end
            obj.expireStaleProcesses(double(rnti), currentSlot);
            [ui, procs] = obj.getUE(double(rnti), false);
            if ui < 1
                tf = true;
                return;
            end
            tf = any(~[procs.Active]);
        end

        function retx = peekRetx(obj, rnti, currentSlot)
            % Return information for the first pending retransmission, or [].
            retx = [];
            if nargin < 3
                currentSlot = NaN;
            end
            obj.expireStaleProcesses(double(rnti), currentSlot);
            [ui, procs] = obj.getUE(double(rnti), false);
            if ui < 1
                return;
            end
            pid = find([procs.NeedsRetx], 1, 'first');
            if isempty(pid)
                return;
            end
            p = procs(pid);
            harq = struct('HarqID', pid-1, 'NDI', p.NDI, 'RV', p.RV, 'IsRetransmission', true);
            retx = struct('HARQ',harq,'TBSBytes',p.TBSBytes,'LastGrant',p.LastGrant,'TB',p.TB);
        end

        function txp = allocate(obj, rnti, slot, tbsBytes, varargin)
            % allocate Choose a HARQ process for transmission.
            %
            % Inputs:
            %   rnti     : UE id
            %   slot     : slot index (for bookkeeping)
            %   tbsBytes : planned TB size in bytes (for new data)
            % Name-Value:
            %   'NewData' (logical) : request new data (default true)
            %
            % Output:
            %   txp.HARQ : struct with HarqID, NDI, RV, IsRetransmission
            %   txp.ProcessIndex : 1-based internal index
            %   txp.ExpectTBSizeBytes : TB size (bytes) for this process
            if nargin < 4
                error('sixgr:HARQEntity:BadInputs','allocate(rnti,slot,tbsBytes,...) requires tbsBytes.');
            end
            newDataRequested = true;
            if ~isempty(varargin)
                if mod(numel(varargin),2) ~= 0
                    error('sixgr:HARQEntity:BadNV','Name-value inputs must come in pairs.');
                end
                for i = 1:2:numel(varargin)
                    key = varargin{i};
                    val = varargin{i+1};
                    if isstring(key), key = char(key); end
                    switch lower(char(key))
                        case 'newdata'
                            newDataRequested = logical(val);
                    end
                end
            end

            rnti = double(rnti);
            slot = double(slot);
            tbsBytes = double(tbsBytes);

            [ui, procs] = obj.getUE(rnti, true);
            procs = obj.expireStaleProcessArray(procs, slot);

            % 1) Serve pending retransmissions first
            pid = find([procs.NeedsRetx], 1, 'first');
            isRetx = ~isempty(pid);

            if ~isRetx
                if ~newDataRequested
                    txp = struct();
                    txp.HARQ = struct('HarqID',[],'NDI',[],'RV',[],'IsRetransmission',false);
                    txp.ProcessIndex = [];
                    txp.ExpectTBSizeBytes = 0;
                    txp.NoFreeProcess = false;
                    return;
                end

                % 2) Otherwise pick an idle process for new data
                pid = find(~[procs.Active], 1, 'first');
                if isempty(pid)
                    txp = struct();
                    txp.HARQ = struct('HarqID',[],'NDI',[],'RV',[],'IsRetransmission',false);
                    txp.ProcessIndex = [];
                    txp.ExpectTBSizeBytes = 0;
                    txp.NoFreeProcess = true;
                    return;
                end

                % Initialize new TB
                procs(pid).Active = true;
                procs(pid).NeedsRetx = false;
                procs(pid).AwaitingFeedback = false;
                procs(pid).RVIdx = 1;
                procs(pid).RV = obj.RVSequence(1);
                procs(pid).NDI = ~procs(pid).NDI; % toggle NDI on new TB
                procs(pid).TBSBytes = tbsBytes;
                procs(pid).TB = uint8([]);
                procs(pid).LastGrant = struct();
                procs(pid).LastTxSlot = slot;
                procs(pid).SoftBuffer = struct();
                procs(pid).SoftBufferKey = "";
                % TxCount incremented in onTx
            end

            % Prepare output
            p = procs(pid);
            harq = struct('HarqID', pid-1, 'NDI', p.NDI, 'RV', p.RV, 'IsRetransmission', isRetx);
            txp = struct('HARQ',harq,'ProcessIndex',pid,'ExpectTBSizeBytes',p.TBSBytes,'NoFreeProcess',false);

            % Write back
            obj.UEProcs{ui} = procs;
        end

        function onTx(obj, rnti, harqId0, tbBytes, grant, slot)
            % onTx Mark that a HARQ process has transmitted a TB.
            rnti = double(rnti);
            pid = double(harqId0) + 1;
            if nargin < 4, tbBytes = uint8([]); end
            if nargin < 5, grant = struct(); end
            if nargin < 6, slot = NaN; end

            [ui, procs] = obj.getUE(rnti, true);
            if pid < 1 || pid > numel(procs)
                error('sixgr:HARQEntity:BadHarqId','Bad HarqID=%d for UE RNTI=%d.', harqId0, rnti);
            end

            % Update process state
            procs(pid).Active = true;
            procs(pid).AwaitingFeedback = true;
            procs(pid).NeedsRetx = false;
            procs(pid).LastTxSlot = double(slot);

            % Update Tx counter and RV
            procs(pid).TxCount = procs(pid).TxCount + 1;

            if procs(pid).TxCount > 1
                obj.Stats.Retx = obj.Stats.Retx + 1;
            end
            obj.Stats.Tx = obj.Stats.Tx + 1;

            % Store TB if requested
            if obj.StoreTB
                if ~isa(tbBytes,'uint8')
                    tbBytes = uint8(tbBytes(:));
                else
                    tbBytes = tbBytes(:);
                end
                procs(pid).TB = tbBytes;
            end

            % Keep the stored grant snapshot aligned with the actual transmitted
            % HARQ payload length. Retransmission replay must follow the TB that
            % was really sent, even if an upstream grant shell carried stale or
            % queue-limited sizing fields.
            if ~isstruct(grant)
                grant = struct();
            end
            actualTBSBits = double(numel(tbBytes));
            if ~(isfinite(actualTBSBits) && actualTBSBits > 0)
                actualTBSBits = double(sixgr.util.structGet(grant, 'TBSBits', ...
                    sixgr.util.structGet(grant, 'TransportBlockSize', NaN)));
            end
            if isfinite(actualTBSBits) && actualTBSBits > 0
                grant.TransportBlockSize = actualTBSBits;
                grant.TBSBits = actualTBSBits;
                grant.TBSBytes = floor(actualTBSBits / 8);
                if ~isfield(grant, 'ScheduledTransportBlockSize') || ...
                        ~(isfinite(double(grant.ScheduledTransportBlockSize)) && double(grant.ScheduledTransportBlockSize) > 0)
                    grant.ScheduledTransportBlockSize = actualTBSBits;
                end
            end
            procs(pid).LastGrant = grant;

            obj.UEProcs{ui} = procs;
        end

        function onFeedback(obj, rnti, harqId0, ack, varargin)
            % onFeedback Update HARQ process state after ACK/NACK.
            rnti = double(rnti);
            pid = double(harqId0) + 1;
            ack = logical(ack);
            sourceSlot = NaN;
            if ~isempty(varargin)
                if mod(numel(varargin),2) ~= 0
                    error('sixgr:HARQEntity:BadNV','Name-value inputs must come in pairs.');
                end
                for i = 1:2:numel(varargin)
                    key = varargin{i};
                    val = varargin{i+1};
                    if isstring(key), key = char(key); end
                    switch lower(char(key))
                        case 'sourceslot'
                            sourceSlot = double(val);
                    end
                end
            end

            [ui, procs] = obj.getUE(rnti, false);
            if ui < 1
                error('sixgr:HARQEntity:UnknownRNTI', ...
                    'RNTI %d not registered.', round(rnti));
            end
            if pid < 1 || pid > numel(procs)
                error('sixgr:HARQEntity:BadHarqId', ...
                    'Bad HarqID=%d for UE RNTI=%d.', harqId0, round(rnti));
            end

            p = procs(pid);
            if ~logical(p.Active) && ~logical(p.AwaitingFeedback) && ...
                    ~logical(p.NeedsRetx) && double(p.TxCount) == 0
                obj.Stats.StaleFeedbackIgnored = obj.Stats.StaleFeedbackIgnored + 1;
                return;
            end
            if isfinite(sourceSlot) && isfinite(double(p.LastTxSlot)) && ...
                    abs(double(sourceSlot) - double(p.LastTxSlot)) > 1e-9
                obj.Stats.StaleFeedbackIgnored = obj.Stats.StaleFeedbackIgnored + 1;
                return;
            end

            procs(pid).AwaitingFeedback = false;

            if ack
                % ACK: release process
                if ~isempty(fieldnames(procs(pid).SoftBuffer))
                    obj.Stats.SoftBufferClear = obj.Stats.SoftBufferClear + 1;
                end
                if double(procs(pid).TxCount) >= 1
                    obj.Stats.FirstSuccessDelivery = obj.Stats.FirstSuccessDelivery + 1;
                end
                procs(pid) = obj.resetProc(procs(pid));
                obj.Stats.Ack = obj.Stats.Ack + 1;
            else
                obj.Stats.Nack = obj.Stats.Nack + 1;

                % NACK: if max transmissions reached, drop; else schedule retx
                maxTx = 1 + obj.MaxRetx;
                if procs(pid).TxCount >= maxTx
                    if ~isempty(fieldnames(procs(pid).SoftBuffer))
                        obj.Stats.SoftBufferClear = obj.Stats.SoftBufferClear + 1;
                    end
                    procs(pid) = obj.resetProc(procs(pid));
                    obj.Stats.Drop = obj.Stats.Drop + 1;
                else
                    procs(pid).NeedsRetx = true;
                    procs(pid).RVIdx = min(procs(pid).RVIdx + 1, numel(obj.RVSequence));
                    procs(pid).RV = obj.RVSequence(procs(pid).RVIdx);
                end
            end

            obj.UEProcs{ui} = procs;
        end

        function tb = getStoredTB(obj, rnti, harqId0)
            tb = uint8([]);
            rnti = double(rnti);
            pid = double(harqId0) + 1;
            [ui, procs] = obj.getUE(rnti, false);
            if ui < 1 || pid < 1 || pid > numel(procs)
                return;
            end
            tb = procs(pid).TB;
        end

        function softBuffer = getSoftBuffer(obj, rnti, harqId0)
            softBuffer = struct();
            rnti = double(rnti);
            pid = double(harqId0) + 1;
            [ui, procs] = obj.getUE(rnti, false);
            if ui < 1 || pid < 1 || pid > numel(procs)
                return;
            end
            softBuffer = procs(pid).SoftBuffer;
        end

        function storeSoftBuffer(obj, rnti, harqId0, softBuffer)
            if ~(isstruct(softBuffer) && ~isempty(fieldnames(softBuffer)))
                return;
            end
            if ~(isfield(softBuffer, "LLRSum") && isfield(softBuffer, "ObservationWeight"))
                error('sixgr:HARQEntity:BadSoftBuffer', ...
                    'HARQ soft buffer must contain LLRSum and ObservationWeight.');
            end
            rnti = double(rnti);
            pid = double(harqId0) + 1;
            [ui, procs] = obj.getUE(rnti, true);
            if pid < 1 || pid > numel(procs)
                error('sixgr:HARQEntity:BadHarqId','Bad HarqID=%d for UE RNTI=%d.', harqId0, rnti);
            end
            procs(pid).SoftBuffer = softBuffer;
            procs(pid).SoftBufferKey = char(string(sixgr.util.structGet(softBuffer, "CodingLayoutHash", "")));
            obj.UEProcs{ui} = procs;
            obj.Stats.SoftBufferStore = obj.Stats.SoftBufferStore + 1;
        end

        function clearSoftBuffer(obj, rnti, harqId0)
            rnti = double(rnti);
            pid = double(harqId0) + 1;
            [ui, procs] = obj.getUE(rnti, false);
            if ui < 1 || pid < 1 || pid > numel(procs)
                return;
            end
            if ~isempty(fieldnames(procs(pid).SoftBuffer))
                obj.Stats.SoftBufferClear = obj.Stats.SoftBufferClear + 1;
            end
            procs(pid).SoftBuffer = struct();
            procs(pid).SoftBufferKey = "";
            obj.UEProcs{ui} = procs;
        end

        function cancelled = cancelTentativeTx(obj, rnti, harqId0)
            % cancelTentativeTx Release a new-data HARQ reservation that never
            % reached PHY transmission, e.g. a scheduler grant blocked by
            % PDCCH decode/gating. Retransmission state and transmitted
            % awaiting-feedback processes are intentionally left untouched.
            cancelled = false;
            rnti = double(rnti);
            pid = double(harqId0) + 1;
            [ui, procs] = obj.getUE(rnti, false);
            if ui < 1 || pid < 1 || pid > numel(procs)
                return;
            end
            p = procs(pid);
            if logical(p.Active) && ~logical(p.AwaitingFeedback) && ...
                    ~logical(p.NeedsRetx) && double(p.TxCount) == 0
                procs(pid) = obj.resetProc(p);
                obj.UEProcs{ui} = procs;
                cancelled = true;
            end
        end
    end

    methods(Access=private)
        function [ui, procs] = getUE(obj, rnti, createIfMissing)
            ui = find(obj.UEList == double(rnti), 1, 'first');
            if isempty(ui)
                if ~createIfMissing
                    ui = -1;
                    procs = struct([]);
                    return;
                end
                obj.UEList(end+1) = double(rnti); %#ok<AGROW>
                procs = repmat(obj.newProcTemplate(), 1, obj.NumProcesses);
                obj.UEProcs{end+1} = procs; %#ok<AGROW>
                ui = numel(obj.UEList);
            end
            procs = obj.UEProcs{ui};
        end

        function p = newProcTemplate(obj)
            %#ok<INUSD> obj
            p = struct();
            p.Active = false;
            p.NDI = false;
            p.RVIdx = 1;
            p.RV = 0;
            p.TxCount = 0;
            p.AwaitingFeedback = false;
            p.NeedsRetx = false;
            p.TBSBytes = 0;
            p.TB = uint8([]);
            p.LastGrant = struct();
            p.LastTxSlot = -inf;
            p.LastDropReason = "";
            p.SoftBuffer = struct();
            p.SoftBufferKey = "";
        end

        function p = resetProc(obj, p)
            % Reset process to idle while keeping NDI state (so it toggles next time).
            ndi = p.NDI;
            p = obj.newProcTemplate();
            p.NDI = ndi;
        end

        function expireStaleProcesses(obj, rnti, currentSlot)
            if ~(isfinite(double(currentSlot)) && isfinite(double(obj.StaleProcessTimeoutSlots)) && ...
                    double(obj.StaleProcessTimeoutSlots) > 0)
                return;
            end
            [ui, procs] = obj.getUE(double(rnti), false);
            if ui < 1
                return;
            end
            procs = obj.expireStaleProcessArray(procs, currentSlot);
            obj.UEProcs{ui} = procs;
        end

        function procs = expireStaleProcessArray(obj, procs, currentSlot)
            if ~(isfinite(double(currentSlot)) && isfinite(double(obj.StaleProcessTimeoutSlots)) && ...
                    double(obj.StaleProcessTimeoutSlots) > 0) || isempty(procs)
                return;
            end
            timeoutSlots = max(1, round(double(obj.StaleProcessTimeoutSlots)));
            for pid = 1:numel(procs)
                if ~logical(procs(pid).Active)
                    continue;
                end
                ageSlots = double(currentSlot) - double(procs(pid).LastTxSlot);
                if isfinite(ageSlots) && ageSlots >= timeoutSlots
                    ndi = procs(pid).NDI;
                    if ~isempty(fieldnames(procs(pid).SoftBuffer))
                        obj.Stats.SoftBufferClear = obj.Stats.SoftBufferClear + 1;
                    end
                    procs(pid) = obj.newProcTemplate();
                    procs(pid).NDI = ndi;
                    procs(pid).LastDropReason = "stale_harq_process_timeout";
                    obj.Stats.Drop = obj.Stats.Drop + 1;
                    obj.Stats.TimeoutDrop = obj.Stats.TimeoutDrop + 1;
                end
            end
        end
    end
end
