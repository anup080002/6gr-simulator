classdef HARQEntity < handle
% sixgr.l2.mac.HARQEntity
% Compatibility facade for direction-specific event-driven HARQ entities.
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
        StaleProcessTimeoutSlots (1,1) double = NaN % deprecated; never expires state
        Logger = []                         % optional sixgr.core.Logger
    end

    properties(SetAccess=private)
        % UE list and per-UE process state cell array
        UEList (1,:) double = double.empty(1,0)
        UEProcs = {}                        % {NUE} each is struct array NumProcesses
        DeliveryLedger table = table()
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
                            if isfinite(double(val))
                                error("sixgr:mac:SynthesizedHARQTimeoutForbidden", ...
                                    "HARQ process lifetime is event-driven; age timeouts are forbidden.");
                            end
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
            catch
            end
            obj.NumProcesses = max(1, round(obj.NumProcesses));
            obj.MaxRetx = max(0, round(obj.MaxRetx));
            obj.StaleProcessTimeoutSlots = NaN;
        end

        function reset(obj)
            obj.UEList = double.empty(1,0);
            obj.UEProcs = {};
            obj.DeliveryLedger = table();
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
            harq = struct('HarqID', pid-1, 'NDI', p.NDI, 'NDIEpoch', p.NDIEpoch, ...
                'RV', p.RV, 'IsRetransmission', true);
            retx = struct('HARQ',harq,'TBSBytes',p.TBSBytes,'LastGrant',p.LastGrant, ...
                'TB',p.TB,'TBContext',p.TBContext);
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
                procs(pid).NDIEpoch = procs(pid).NDIEpoch + 1;
                procs(pid).TBSBytes = tbsBytes;
                procs(pid).TB = uint8([]);
                procs(pid).LastGrant = struct();
                procs(pid).LastTxSlot = slot;
                procs(pid).TBContext = struct();
                procs(pid).SoftBuffer = struct();
                procs(pid).SoftBufferKey = "";
                % TxCount incremented in onTx
            end

            % Prepare output
            p = procs(pid);
            obj.assertStoredTBContract(double(rnti), pid - 1, p);
            harq = struct('HarqID', pid-1, 'NDI', p.NDI, 'NDIEpoch', p.NDIEpoch, ...
                'RV', p.RV, 'IsRetransmission', isRetx);
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

            priorTxCount = double(procs(pid).TxCount);
            priorTB = procs(pid).TB;
            if ~isa(tbBytes,'uint8')
                tbBytes = uint8(tbBytes(:));
            else
                tbBytes = tbBytes(:);
            end
            actualPayloadBits = double(numel(tbBytes));
            if actualPayloadBits > 0 && mod(actualPayloadBits, 8) ~= 0
                error('sixgr:HARQEntity:NonByteAlignedTB', ...
                    ['HARQ TB for RNTI=%d process=%d contains %d bits; ' ...
                    'a transport block must be byte aligned.'], ...
                    round(rnti), round(harqId0), round(actualPayloadBits));
            end
            if obj.StoreTB && priorTxCount > 0 && ~isempty(priorTB) && ...
                    ~isequal(uint8(priorTB(:)), tbBytes)
                error('sixgr:HARQEntity:RetransmissionPayloadChanged', ...
                    ['HARQ retransmission for RNTI=%d process=%d changed the ' ...
                    'stored transport block instead of replaying the first transmission.'], ...
                    round(rnti), round(harqId0));
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
                procs(pid).TB = tbBytes;
            end

            % Keep the stored grant snapshot aligned with the actual transmitted
            % HARQ payload length. Retransmission replay must follow the TB that
            % was really sent, even if an upstream grant shell carried stale or
            % queue-limited sizing fields.
            if ~isstruct(grant)
                grant = struct();
            end
            actualTBSBits = actualPayloadBits;
            if ~(isfinite(actualTBSBits) && actualTBSBits > 0)
                actualTBSBits = double(sixgr.util.structGet(grant, 'TBSBits', ...
                    sixgr.util.structGet(grant, 'TransportBlockSize', NaN)));
            end
            if isfinite(actualTBSBits) && actualTBSBits > 0
                actualTBSBytes = actualTBSBits / 8;
                if priorTxCount == 0
                    % allocate() reserves a tentative scheduler size. The
                    % first executed PHY transmission is authoritative and
                    % is frozen for every later redundancy version.
                    procs(pid).TBSBytes = actualTBSBytes;
                elseif abs(double(procs(pid).TBSBytes) - actualTBSBytes) > 1e-9
                    error('sixgr:HARQEntity:RetransmissionTBSChanged', ...
                        ['HARQ retransmission for RNTI=%d process=%d has %d bits, ' ...
                        'but the first transmitted TB has %d bits.'], ...
                        round(rnti), round(harqId0), round(actualTBSBits), ...
                        round(double(procs(pid).TBSBytes) * 8));
                end
                grant.TransportBlockSize = actualTBSBits;
                grant.TBSBits = actualTBSBits;
                grant.TBSBytes = actualTBSBytes;
                if ~isfield(grant, 'ScheduledTransportBlockSize') || ...
                        ~(isfinite(double(grant.ScheduledTransportBlockSize)) && double(grant.ScheduledTransportBlockSize) > 0)
                    grant.ScheduledTransportBlockSize = actualTBSBits;
                end
            end
            harqStruct = sixgr.util.structGet(grant, 'HARQ', struct());
            if ~isstruct(harqStruct)
                harqStruct = struct();
            end
            harqStruct.HarqID = double(harqId0);
            harqStruct.HARQProcess = double(harqId0);
            harqStruct.RV = double(procs(pid).RV);
            harqStruct.NDI = logical(procs(pid).NDI);
            harqStruct.NDIEpoch = double(procs(pid).NDIEpoch);
            harqStruct.IsRetransmission = double(procs(pid).TxCount) > 1;
            grant.HARQ = harqStruct;
            grant.IsRetransmission = logical(harqStruct.IsRetransmission);
            ctx = sixgr.util.structGet(grant, 'HARQTBContext', struct());
            if ~(isstruct(ctx) && ~isempty(fieldnames(ctx)))
                ctx = procs(pid).TBContext;
            end
            if priorTxCount == 0 && ...
                    ~(isstruct(ctx) && ~isempty(fieldnames(ctx)))
                % The first executed transmission is the immutable HARQ TB
                % authority.  Build its context from the exact finalized
                % grant now; do not wait for a retransmission and then infer
                % layers/coding from current scheduler state.
                ctx = sixgr.harq.createTBContext(struct( ...
                    'Grant', grant, ...
                    'PHYGrant', sixgr.util.structGet( ...
                        grant, 'PHYGrant', struct()), ...
                    'Direction', sixgr.util.structGet( ...
                        grant, 'Direction', obj.Direction), ...
                    'TBSBits', actualTBSBits));
            end
            if isstruct(ctx) && ~isempty(fieldnames(ctx))
                ctx.NDI = logical(procs(pid).NDI);
                ctx.NDIEpoch = double(procs(pid).NDIEpoch);
                ctx.HARQProcessId = double(harqId0);
                ctx.LastObservedRV = double(procs(pid).RV);
                grant.HARQTBContext = ctx;
                procs(pid).TBContext = ctx;
            end
            procs(pid).LastGrant = grant;
            if strlength(string(procs(pid).TBIdentity)) == 0
                procs(pid).FirstTxSlot = double(slot);
                procs(pid).TBIdentity = obj.composeTBIdentity(rnti, harqId0, procs(pid), grant);
            end
            obj.appendDeliveryAttempt(rnti, harqId0, slot, procs(pid), grant);

            obj.UEProcs{ui} = procs;
        end

        function onFeedback(obj, rnti, harqId0, feedback, varargin)
            % onFeedback Apply a typed ACK/NACK/DTX outcome.
            rnti = double(rnti);
            pid = double(harqId0) + 1;
            if isa(feedback, "sixgr.l2.mac.HARQFeedbackEvent")
                outcome = feedback.Outcome;
            elseif islogical(feedback) || ...
                    (isnumeric(feedback) && isscalar(feedback))
                % Compatibility callers remain supported, but the live
                % scheduler installs an explicit Outcome before dispatch.
                if logical(feedback), outcome = "ACK"; else, outcome = "NACK"; end
            else
                outcome = upper(string(feedback));
            end
            if ~ismember(outcome, ["ACK","NACK","DTX"])
                error("sixgr:mac:InvalidHARQFeedbackContext", ...
                    "Feedback outcome must be ACK, NACK, or DTX.");
            end
            ack = outcome == "ACK";
            sourceSlot = NaN;
            feedbackSlot = NaN;
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
                        case 'feedbackslot'
                            feedbackSlot = double(val);
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
            if ~logical(p.AwaitingFeedback)
                obj.Stats.StaleFeedbackIgnored = obj.Stats.StaleFeedbackIgnored + 1;
                return;
            end

            procs(pid).AwaitingFeedback = false;

            if ack
                % ACK: release process
                obj.markDeliveryFeedback(rnti, harqId0, true, sourceSlot, feedbackSlot, "");
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
                obj.markDeliveryFeedback(rnti, harqId0, false, sourceSlot, feedbackSlot, lower(outcome));

                % NACK: if max transmissions reached, drop; else schedule retx
                maxTx = 1 + obj.MaxRetx;
                if procs(pid).TxCount >= maxTx
                    if ~isempty(fieldnames(procs(pid).SoftBuffer))
                        obj.Stats.SoftBufferClear = obj.Stats.SoftBufferClear + 1;
                    end
                    procs(pid) = obj.resetProc(procs(pid));
                    obj.Stats.Drop = obj.Stats.Drop + 1;
                    obj.markDeliveryFeedback(rnti, harqId0, false, sourceSlot, feedbackSlot, "max_retx_drop");
                else
                    procs(pid).NeedsRetx = true;
                    procs(pid).RVIdx = min(procs(pid).RVIdx + 1, numel(obj.RVSequence));
                    procs(pid).RV = obj.RVSequence(procs(pid).RVIdx);
                end
            end

            obj.UEProcs{ui} = procs;
        end

        function ledger = getDeliveryLedger(obj)
            ledger = obj.DeliveryLedger;
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
        function assertStoredTBContract(obj, rnti, harqId0, p)
            if ~obj.StoreTB || isempty(p.TB)
                return;
            end
            storedBits = double(numel(p.TB));
            reservedBits = double(p.TBSBytes) * 8;
            if ~(isfinite(reservedBits) && reservedBits > 0 && ...
                    abs(storedBits - reservedBits) < 1e-9)
                error('sixgr:HARQEntity:StoredTBContractMismatch', ...
                    ['Stored HARQ TB for RNTI=%d process=%d has %d bits, ' ...
                    'while the HARQ process is bound to %d bits.'], ...
                    round(rnti), round(harqId0), round(storedBits), round(reservedBits));
            end
            ctxBits = double(sixgr.util.structGet(p.TBContext, 'TBSBits', NaN));
            if isfinite(ctxBits) && ctxBits > 0 && round(ctxBits) ~= round(storedBits)
                error('sixgr:HARQEntity:StoredTBContextMismatch', ...
                    ['Stored HARQ TB for RNTI=%d process=%d has %d bits, ' ...
                    'while its frozen TB context declares %d bits.'], ...
                    round(rnti), round(harqId0), round(storedBits), round(ctxBits));
            end
        end

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
            p.NDIEpoch = 0;
            p.RVIdx = 1;
            p.RV = 0;
            p.TxCount = 0;
            p.AwaitingFeedback = false;
            p.NeedsRetx = false;
            p.TBSBytes = 0;
            p.TB = uint8([]);
            p.LastGrant = struct();
            p.LastTxSlot = -inf;
            p.FirstTxSlot = NaN;
            p.TBIdentity = "";
            p.LastDropReason = "";
            p.TBContext = struct();
            p.SoftBuffer = struct();
            p.SoftBufferKey = "";
        end

        function p = resetProc(obj, p)
            % Reset process to idle while keeping NDI state (so it toggles next time).
            ndi = p.NDI;
            ndiEpoch = p.NDIEpoch;
            p = obj.newProcTemplate();
            p.NDI = ndi;
            p.NDIEpoch = ndiEpoch;
        end

        function expireStaleProcesses(obj, rnti, currentSlot)
            %#ok<INUSD>
            % Intentionally empty. Process lifetime is changed only by
            % decoded feedback, cancellation, release, reset, or TA expiry.
        end

        function procs = expireStaleProcessArray(obj, procs, currentSlot)
            %#ok<INUSD>
            % Compatibility no-op; synthesized age expiry is forbidden.
        end

        function key = composeTBIdentity(obj, rnti, harqId0, p, grant)
            %#ok<INUSD> obj
            for name = ["TransportBlockId","TBId","MACPDUId","MACSDUId","GrantContextId"]
                if isstruct(grant) && isfield(grant, char(name))
                    raw = strtrim(string(grant.(char(name))));
                    if strlength(raw) > 0 && lower(raw) ~= "nan"
                        key = raw;
                        return;
                    end
                end
            end
            cw = double(sixgr.util.structGet(grant, "Codeword", sixgr.util.structGet(grant, "CodewordIndex", 0)));
            key = string(obj.Direction) + "_rnti" + string(double(rnti)) + "_harq" + string(double(harqId0)) + ...
                "_ndi" + string(double(p.NDI)) + "_cw" + string(cw) + "_firstSlot" + string(double(p.FirstTxSlot));
        end

        function appendDeliveryAttempt(obj, rnti, harqId0, slot, p, grant)
            row = obj.emptyDeliveryLedgerRow();
            row.Direction = string(obj.Direction);
            row.RNTI = double(rnti);
            row.HARQProcessId = double(harqId0);
            row.TransportBlockId = string(p.TBIdentity);
            row.Codeword = double(sixgr.util.structGet(grant, "Codeword", sixgr.util.structGet(grant, "CodewordIndex", 0)));
            row.NDI = double(p.NDI);
            row.RV = double(p.RV);
            row.AttemptIndex = double(p.TxCount);
            row.NewDataFlag = double(p.TxCount) == 1;
            row.RetransmissionFlag = double(p.TxCount) > 1;
            row.ScheduleSlot = double(p.FirstTxSlot);
            row.AttemptSlot = double(slot);
            row.TBSBits = double(sixgr.util.structGet(grant, "TBSBits", sixgr.util.structGet(grant, "TransportBlockSize", p.TBSBytes * 8)));
            row.CrcPass = false;
            row.FirstSuccessDelivery = false;
            row.CountedGoodputBits = 0;
            row.Status = "tx_attempt";
            obj.DeliveryLedger = [obj.DeliveryLedger; struct2table(row, "AsArray", true)]; %#ok<AGROW>
        end

        function markDeliveryFeedback(obj, rnti, harqId0, ack, sourceSlot, feedbackSlot, reason)
            if isempty(obj.DeliveryLedger)
                return;
            end
            T = obj.DeliveryLedger;
            mask = double(T.HARQProcessId) == double(harqId0);
            if isfinite(double(rnti))
                mask = mask & double(T.RNTI) == double(rnti);
            end
            if isfinite(double(sourceSlot))
                mask = mask & abs(double(T.AttemptSlot) - double(sourceSlot)) < 1e-9;
            end
            idx = find(mask, 1, "last");
            if isempty(idx)
                return;
            end
            obj.DeliveryLedger.CrcPass(idx) = logical(ack);
            if isfinite(double(feedbackSlot))
                obj.DeliveryLedger.FeedbackSlot(idx) = double(feedbackSlot);
            elseif isfinite(double(sourceSlot))
                obj.DeliveryLedger.FeedbackSlot(idx) = double(sourceSlot);
            end
            if ack
                tbKey = string(obj.DeliveryLedger.TransportBlockId(idx));
                prior = string(obj.DeliveryLedger.TransportBlockId) == tbKey & logical(obj.DeliveryLedger.FirstSuccessDelivery);
                if ~any(prior)
                    obj.DeliveryLedger.FirstSuccessDelivery(idx) = true;
                    obj.DeliveryLedger.CountedGoodputBits(idx) = double(obj.DeliveryLedger.TBSBits(idx));
                    obj.DeliveryLedger.FirstSuccessSlot(idx) = double(obj.DeliveryLedger.FeedbackSlot(idx));
                    obj.DeliveryLedger.Status(idx) = "first_success_delivery";
                else
                    obj.DeliveryLedger.Status(idx) = "duplicate_success_delivery";
                end
            elseif strlength(string(reason)) > 0
                obj.DeliveryLedger.Status(idx) = string(reason);
            else
                obj.DeliveryLedger.Status(idx) = "nack";
            end
        end

        function row = emptyDeliveryLedgerRow(obj)
            %#ok<INUSD> obj
            row = struct("Direction","", "RNTI",NaN, "HARQProcessId",NaN, ...
                "TransportBlockId","", "Codeword",NaN, "NDI",NaN, "RV",NaN, ...
                "AttemptIndex",NaN, "NewDataFlag",false, "RetransmissionFlag",false, ...
                "ScheduleSlot",NaN, "AttemptSlot",NaN, "FeedbackSlot",NaN, "FirstSuccessSlot",NaN, ...
                "TBSBits",NaN, "CrcPass",false, "FirstSuccessDelivery",false, ...
                "CountedGoodputBits",NaN, "Status","");
        end
    end
end
