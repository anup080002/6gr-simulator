classdef RRC < handle
% sixgr.l3.rrc.RRC
% RRC entity (UE or gNB) with coherent attach and handover message flow.
%
% This is a procedure-faithful RRC layer for the simulator. It focuses on
% slot-driven control-plane sequencing and explicit interfaces:
%   - System Information acquisition hooks (MIB/SIB1)
%   - Random Access (RACH) and RRC Setup (Attach) procedure
%   - Handover hooks (measurement report and reconfiguration command)
%   - SRB0 (CCCH) and SRB1 (DCCH) carried over your L2 stack:
%         SRB0: RLC TM  (no PDCP)
%         SRB1: PDCP + RLC AM
%
% Message encoding:
%   RRC messages are encoded as UTF-8 JSON bytes for simulator use. This is
%   NOT ASN.1 / PER bit-accurate, but the control-plane state progression
%   (Msg1..Msg4, SRB mapping, UE/gNB roles) is modeled explicitly.
%
% Typical usage (single UE <-> gNB back-to-back):
%   cfg = sixgr.config.defaultConfig();
%   ue  = sixgr.l3.rrc.RRC(cfg,'UE','UEId',1);
%   gnb = sixgr.l3.rrc.RRC(cfg,'gNB','CellID',cfg.phy.carrier.NCellID);
%
%   % Provide SI to UE (from your PHY SSB/PBCH/SIB1 chain or from config)
%   ue.setSystemInformation( sixgr.l3.rrc.SystemInformation(cfg) );
%
%   % UE initiates attach (generates PRACH action)
%   actUE = ue.step(0, struct());
%   % gNB receives PRACH detection and returns RAR action
%   actG  = gnb.step(0, struct('PrachDetect', actUE.PrachTx));
%   % UE receives RAR
%   ue.step(1, struct('RAR', actG.RAR));
%
%   % Exchange SRB0/SRB1 MAC SDUs via your MAC/PHY (back-to-back here)
%   ul = ue.pollTxMACSDUs(200);
%   gnb.receiveMACSDUs(ul,'RNTI',actG.RAR.TempCRNTI);
%   dl = gnb.pollTxMACSDUs(400,'RNTI',actG.RAR.TempCRNTI);
%   ue.receiveMACSDUs(dl);
%   ... continue stepping until ue.State == "CONNECTED"
%
% NOTE:
% - For multi-UE, the gNB RRC maintains per-UE contexts keyed by RNTI.
% - This file is ASCII-only.

    properties
        Cfg (1,1) struct
        Role (1,:) char = 'UE'           % 'UE' or 'GNB'
        UEId (1,1) double = 1            % UE identity (sim)
        CellID (1,1) double = 1          % serving cell ID
        Logger = []
    end

    properties(SetAccess=private)
        State (1,:) char = 'IDLE'
        CRNTI (1,1) double = -1          % valid after attach
    end

    properties
        SI (1,1) sixgr.l3.rrc.SystemInformation
    end

    properties(Access=private)
        % UE single-context
        UE_Attach (1,1) sixgr.l3.rrc.AttachProcedure
        UE_RACH (1,1) sixgr.l3.rrc.RACHProcedure

        UE_SRB0_RLC = []
        UE_SRB1_PDCP = []
        UE_SRB1_RLC = []

        UE_RxQueue cell = {}            % decoded messages (structs with fields SRB, Msg)

        % gNB multi-context: map rnti -> ctx struct
        GNB_UeCtx
    end

    methods
        function obj = RRC(cfg, role, varargin)
            if nargin < 1 || isempty(cfg)
                cfg = struct();
            end
            if nargin < 2 || isempty(role)
                role = 'UE';
            end

            obj.Cfg = cfg;
            obj.Role = upper(char(string(role)));

            % Defaults from cfg
            obj.CellID = double(sixgr.util.structGet(cfg,'phy.carrier.NCellID',obj.CellID));

            % Parse name-value
            if ~isempty(varargin)
                if mod(numel(varargin),2) ~= 0
                    error('sixgr:RRC:BadNV','Name-value inputs must come in pairs.');
                end
                for i = 1:2:numel(varargin)
                    k = varargin{i}; v = varargin{i+1};
                    if isstring(k), k = char(k); end
                    switch lower(char(k))
                        case 'ueid'
                            obj.UEId = double(v);
                        case 'cellid'
                            obj.CellID = double(v);
                        case 'logger'
                            obj.Logger = v;
                        otherwise
                            error('sixgr:RRC:BadOpt','Unknown option: %s', string(k));
                    end
                end
            end

            % System information object (default from config)
            obj.SI = sixgr.l3.rrc.SystemInformation(cfg,'CellID',obj.CellID);

            if strcmp(obj.Role,'UE')
                obj.initUE_();
            elseif strcmp(obj.Role,'GNB')
                obj.initGNB_();
            else
                error('sixgr:RRC:BadRole','Role must be UE or gNB.');
            end
        end

        function reset(obj)
            obj.State = 'IDLE';
            obj.CRNTI = -1;
            obj.SI = sixgr.l3.rrc.SystemInformation(obj.Cfg,'CellID',obj.CellID);

            if strcmp(obj.Role,'UE')
                obj.initUE_();
            else
                obj.initGNB_();
            end
        end

        function setSystemInformation(obj, siObj)
            if isempty(siObj)
                return;
            end
            obj.SI = siObj;
            if strcmp(obj.Role,'UE')
                obj.UE_Attach.onSystemInformationReady(obj.SI);
            end
        end

        function acts = step(obj, slot, inputs)
            % step Advance RRC procedures and produce "actions" for the simulator.
            %
            % inputs fields (best-effort):
            %   inputs.RAR         : struct (for UE)
            %   inputs.PrachDetect : struct (for gNB)
            %   inputs.MACSDUs     : struct array (for UE) or inputs.MACSDUsUL + inputs.RNTI (for gNB)
            %
            % Output actions:
            %   - acts.PrachTx (UE) : struct with PRACH transmit request
            %   - acts.RAR (gNB)    : struct RAR to send (MAC CE, abstracted)
            %   - acts.Notes        : text notes for debug

            if nargin < 2 || isempty(slot)
                slot = 0;
            end
            if nargin < 3 || isempty(inputs)
                inputs = struct();
            end

            acts = struct();
            acts.Notes = '';

            if strcmp(obj.Role,'UE')
                % Accept downlink MAC SDUs (SRB0/SRB1)
                if isfield(inputs,'MACSDUs') && ~isempty(inputs.MACSDUs)
                    obj.receiveMACSDUs(inputs.MACSDUs);
                end

                % Pass RAR to attach procedure if present
                rar = [];
                if isfield(inputs,'RAR')
                    rar = inputs.RAR;
                end

                a = obj.UE_Attach.step(slot, struct('RAR',rar), obj);
                acts = localMergeActions(acts, a);

                obj.State = obj.UE_Attach.State;
                obj.CRNTI = obj.UE_Attach.CRNTI;

            else
                % gNB: PRACH detection event
                if isfield(inputs,'PrachDetect') && ~isempty(inputs.PrachDetect)
                    det = inputs.PrachDetect;
                    a = obj.handlePrachDetect_(slot, det);
                    acts = localMergeActions(acts, a);
                end

                % gNB: receive uplink MAC SDUs for a specific UE
                if isfield(inputs,'MACSDUsUL') && ~isempty(inputs.MACSDUsUL)
                    rnti = double(sixgr.util.structGet(inputs,'RNTI',-1));
                    if rnti < 0
                        % Try parse from inputs
                        if isfield(inputs,'TempCRNTI')
                            rnti = double(inputs.TempCRNTI);
                        end
                    end
                    if rnti >= 0
                        obj.receiveMACSDUs(inputs.MACSDUsUL,'RNTI',rnti);
                        % Step that UE attach state machine
                        ctx = obj.getUeCtx_(rnti,false);
                        if ~isempty(ctx)
                            a2 = ctx.Attach.step(slot, struct(), obj);
                            acts = localMergeActions(acts, a2);
                            obj.GNB_UeCtx(rnti) = ctx;
                        end
                    end
                end
            end
        end

        function macSDUs = pollTxMACSDUs(obj, availBytes, varargin)
            % pollTxMACSDUs Build MAC SDUs to be multiplexed for SRB0/SRB1.
            %
            % UE: returns SRB0/1 SDUs from its internal SRB stacks.
            % gNB: pass 'RNTI', rnti to get that UE's downlink SRB SDUs.

            if nargin < 2 || isempty(availBytes)
                availBytes = inf;
            end

            if strcmp(obj.Role,'UE')
                macSDUs = obj.buildTxSDUsForUE_(double(availBytes));
            else
                rnti = [];
                if ~isempty(varargin)
                    if mod(numel(varargin),2) ~= 0
                        error('sixgr:RRC:BadNV','Name-value inputs must come in pairs.');
                    end
                    for i = 1:2:numel(varargin)
                        k = varargin{i}; v = varargin{i+1};
                        if isstring(k), k = char(k); end
                        switch lower(char(k))
                            case 'rnti'
                                rnti = double(v);
                            otherwise
                                error('sixgr:RRC:BadOpt','Unknown option: %s', string(k));
                        end
                    end
                end
                if isempty(rnti)
                    error('sixgr:RRC:NeedRNTI','gNB pollTxMACSDUs requires ''RNTI'',rnti.');
                end
                macSDUs = obj.buildTxSDUsForGNB_(rnti, double(availBytes));
            end
        end

        function receiveMACSDUs(obj, macSDUs, varargin)
            % receiveMACSDUs Deliver MAC SDUs to this RRC (from lower layers).
            %
            % UE:
            %   receiveMACSDUs(sduList)
            % gNB:
            %   receiveMACSDUs(sduList,'RNTI',rnti)

            if nargin < 2 || isempty(macSDUs)
                return;
            end

            if strcmp(obj.Role,'UE')
                obj.rxIntoStacksUE_(macSDUs);
                obj.processRxUE_();
            else
                rnti = [];
                if ~isempty(varargin)
                    if mod(numel(varargin),2) ~= 0
                        error('sixgr:RRC:BadNV','Name-value inputs must come in pairs.');
                    end
                    for i = 1:2:numel(varargin)
                        k = varargin{i}; v = varargin{i+1};
                        if isstring(k), k = char(k); end
                        switch lower(char(k))
                            case 'rnti'
                                rnti = double(v);
                            otherwise
                                error('sixgr:RRC:BadOpt','Unknown option: %s', string(k));
                        end
                    end
                end
                if isempty(rnti)
                    error('sixgr:RRC:NeedRNTI','gNB receiveMACSDUs requires ''RNTI'',rnti.');
                end
                obj.rxIntoStacksGNB_(rnti, macSDUs);
                obj.processRxGNB_(rnti);
            end
        end

        function msgs = pullRxMessages(obj)
            % pullRxMessages Return and clear decoded RX message queue (UE only).
            msgs = obj.UE_RxQueue;
            obj.UE_RxQueue = {};
        end

        % -----------------------------------------------------------------
        % Sending primitives used by procedures
        % -----------------------------------------------------------------
        function sendSRB0(obj, msgStruct, varargin)
            % sendSRB0 Enqueue a CCCH message on SRB0 (RLC TM).
            if strcmp(obj.Role,'UE')
                b = sixgr.l3.rrc.RRC.encodeMessage(msgStruct);
                obj.UE_SRB0_RLC.addSDU(b);
            else
                rnti = localParseRNTI_(varargin{:});
                ctx = obj.getUeCtx_(rnti,true);
                b = sixgr.l3.rrc.RRC.encodeMessage(msgStruct);
                ctx.SRB0_RLC.addSDU(b);
                obj.GNB_UeCtx(rnti) = ctx;
            end
        end

        function sendSRB1(obj, msgStruct, varargin)
            % sendSRB1 Enqueue a DCCH message on SRB1 (PDCP + RLC AM).
            if strcmp(obj.Role,'UE')
                b = sixgr.l3.rrc.RRC.encodeMessage(msgStruct);
                p = obj.UE_SRB1_PDCP.tx(b);
                obj.UE_SRB1_RLC.addSDU(p);
            else
                rnti = localParseRNTI_(varargin{:});
                ctx = obj.getUeCtx_(rnti,true);
                b = sixgr.l3.rrc.RRC.encodeMessage(msgStruct);
                p = ctx.SRB1_PDCP.tx(b);
                ctx.SRB1_RLC.addSDU(p);
                obj.GNB_UeCtx(rnti) = ctx;
            end
        end

        % -----------------------------------------------------------------
        % Handover hooks (stubs with coherent messages)
        % -----------------------------------------------------------------
        function requestHandover(obj, rnti, targetCellID)
            % requestHandover (gNB) Generate an RRCReconfiguration HO command.
            if ~strcmp(obj.Role,'GNB')
                error('sixgr:RRC:HandoverRole','Only gNB can initiate handover in this class.');
            end

            msg = struct();
            msg.msgType = 'RRCReconfiguration';
            msg.cRNTI = double(rnti);
            msg.mobilityControl = struct('targetCellID',double(targetCellID), ...
                                         'hoType','intraNR', ...
                                         'reconfigWithSync', true);
            msg.timestamp = char(datetime('now','Format','yyyy-MM-dd HH:mm:ss.SSS'));

            obj.sendSRB1(msg,'RNTI',double(rnti));
        end

        function onMeasurementReport(obj, rnti, meas)
            % onMeasurementReport (gNB) Placeholder hook for HO decisions.
            %#ok<INUSD>
            if ~strcmp(obj.Role,'GNB')
                return;
            end
            if ~isempty(obj.Logger) && isa(obj.Logger,'sixgr.core.Logger')
                obj.Logger.info(sprintf('RRC: MeasurementReport from RNTI=%d', double(rnti)));
            end
        end
    end

    methods(Static)
        function bytes = encodeMessage(msgStruct)
            if nargin < 1 || isempty(msgStruct)
                bytes = uint8([]);
                return;
            end
            % Ensure msgType exists for routing/debug
            if ~isfield(msgStruct,'msgType')
                msgStruct.msgType = 'Unknown';
            end
            try
                s = jsonencode(msgStruct);
            catch
                % jsonencode can fail on non-scalar/handle fields; try sanitize
                s = jsonencode(localSanitizeStruct(msgStruct));
            end
            bytes = uint8(unicode2native(s,'UTF-8'));
            bytes = bytes(:);
        end

        function msgStruct = decodeMessage(bytes)
            msgStruct = struct('msgType','DecodeFail');
            if isempty(bytes)
                msgStruct.msgType = 'Empty';
                return;
            end
            try
                s = native2unicode(uint8(bytes(:)).','UTF-8');
                tmp = jsondecode(s);
                if isstruct(tmp)
                    msgStruct = tmp;
                else
                    msgStruct = struct('msgType','DecodedNonStruct','value',tmp);
                end
            catch ME
                msgStruct = struct('msgType','DecodeFail','error',ME.message);
            end
        end
    end

    methods(Access=private)
        function initUE_(obj)
            % Create UE SRB stacks and procedures
            obj.UE_SRB0_RLC = sixgr.l2.rlc.RLC_TM(obj.Cfg,'LCID',0,'Direction','UL','Logger',obj.Logger);
            obj.UE_SRB1_PDCP = sixgr.l2.pdcp.PDCP(obj.Cfg,'Direction','UL','DRBID',0,'Logger',obj.Logger);
            obj.UE_SRB1_RLC = sixgr.l2.rlc.RLC_AM(obj.Cfg,'LCID',1,'Direction','UL','Logger',obj.Logger);

            obj.UE_RACH = sixgr.l3.rrc.RACHProcedure(obj.Cfg,'Role','UE','CellID',obj.CellID,'UEId',obj.UEId,'Logger',obj.Logger);
            obj.UE_Attach = sixgr.l3.rrc.AttachProcedure(obj.Cfg,'Role','UE','UEId',obj.UEId,'CellID',obj.CellID,'Logger',obj.Logger);
            obj.UE_Attach.bindRACH(obj.UE_RACH);

            obj.UE_RxQueue = {};
        end

        function initGNB_(obj)
            obj.GNB_UeCtx = containers.Map('KeyType','double','ValueType','any');
        end

        function acts = handlePrachDetect_(obj, slot, det)
            %#ok<INUSD>
            % PRACH detection event at gNB:
            % det fields: PreambleIndex, TimingOffset, (optional) RaRNTI
            acts = struct();
            acts.Notes = '';

            pre = double(sixgr.util.structGet(det,'PreambleIndex',0));
            ta  = double(sixgr.util.structGet(det,'TimingOffset',0));

            % Allocate a temporary C-RNTI (simple sequential strategy)
            tempCRNTI = obj.allocateTempCRNTI_();

            % Create per-UE context
            ctx = obj.getUeCtx_(tempCRNTI,true);
            ctx.Attach.onPrachDetected(pre, ta, slot);

            % Build RAR (abstract MAC CE)
            rar = ctx.Attach.buildRAR(tempCRNTI);

            acts.RAR = rar;
            obj.GNB_UeCtx(tempCRNTI) = ctx;
        end

        function ctx = getUeCtx_(obj, rnti, createIfMissing)
            if nargin < 3
                createIfMissing = false;
            end
            ctx = [];
            rnti = double(rnti);

            if isKey(obj.GNB_UeCtx, rnti)
                ctx = obj.GNB_UeCtx(rnti);
                return;
            end

            if ~createIfMissing
                return;
            end

            % Create new UE context with SRB stacks and attach procedure
            ctx = struct();
            ctx.RNTI = rnti;

            ctx.SRB0_RLC = sixgr.l2.rlc.RLC_TM(obj.Cfg,'LCID',0,'Direction','DL','Logger',obj.Logger);
            ctx.SRB1_PDCP = sixgr.l2.pdcp.PDCP(obj.Cfg,'Direction','DL','DRBID',0,'Logger',obj.Logger);
            ctx.SRB1_RLC = sixgr.l2.rlc.RLC_AM(obj.Cfg,'LCID',1,'Direction','DL','Logger',obj.Logger);

            ctx.RACH = sixgr.l3.rrc.RACHProcedure(obj.Cfg,'Role','GNB','CellID',obj.CellID,'UEId',-1,'Logger',obj.Logger);
            ctx.Attach = sixgr.l3.rrc.AttachProcedure(obj.Cfg,'Role','GNB','UEId',-1,'CellID',obj.CellID,'Logger',obj.Logger);
            ctx.Attach.bindRACH(ctx.RACH);
        end

        function macSDUs = buildTxSDUsForUE_(obj, availBytes)
            budget = double(availBytes);
            macSDUs = struct('LCID',{},'Payload',{});

            % Prioritize SRB0 (CCCH)
            s0 = obj.UE_SRB0_RLC.buildMACSDUs(budget);
            s0 = localNormalizeMacSDUs_(s0);
            budget = budget - localTotalPayload_(s0);
            if budget < 0, budget = 0; end

            s1 = obj.UE_SRB1_RLC.buildMACSDUs(budget);
            s1 = localNormalizeMacSDUs_(s1);

            % Concatenate
            macSDUs = [s0(:); s1(:)];
        end

        function macSDUs = buildTxSDUsForGNB_(obj, rnti, availBytes)
            ctx = obj.getUeCtx_(rnti,false);
            if isempty(ctx)
                macSDUs = struct('LCID',{},'Payload',{});
                return;
            end

            budget = double(availBytes);
            s0 = ctx.SRB0_RLC.buildMACSDUs(budget);
            s0 = localNormalizeMacSDUs_(s0);
            budget = budget - localTotalPayload_(s0);
            if budget < 0, budget = 0; end
            s1 = ctx.SRB1_RLC.buildMACSDUs(budget);
            s1 = localNormalizeMacSDUs_(s1);

            macSDUs = [s0(:); s1(:)];
        end

        function rxIntoStacksUE_(obj, macSDUs)
            macSDUs = localNormalizeMacSDUs_(macSDUs);
            for i = 1:numel(macSDUs)
                lcid = double(macSDUs(i).LCID);
                pdu = uint8(macSDUs(i).Payload(:));
                if lcid == 0
                    obj.UE_SRB0_RLC.receivePDU(pdu);
                elseif lcid == 1
                    obj.UE_SRB1_RLC.receivePDU(pdu);
                end
            end
        end

        function processRxUE_(obj)
            % SRB0: SDUs are RRC messages
            sdu0 = obj.UE_SRB0_RLC.pullSDUs();
            for i = 1:numel(sdu0)
                msg = sixgr.l3.rrc.RRC.decodeMessage(sdu0{i});
                obj.UE_RxQueue{end+1} = struct('SRB',0,'Msg',msg); %#ok<AGROW>
                obj.UE_Attach.onDownlinkMessage(0, msg);
            end

            % SRB1: SDUs are PDCP SDUs (RRC messages)
            pdu1 = obj.UE_SRB1_RLC.pullSDUs();
            for i = 1:numel(pdu1)
                obj.UE_SRB1_PDCP.rx(pdu1{i});
            end
            sdu1 = obj.UE_SRB1_PDCP.pullSDUs();
            for i = 1:numel(sdu1)
                msg = sixgr.l3.rrc.RRC.decodeMessage(sdu1{i});
                obj.UE_RxQueue{end+1} = struct('SRB',1,'Msg',msg); %#ok<AGROW>
                obj.UE_Attach.onDownlinkMessage(1, msg);
            end
        end

        function rxIntoStacksGNB_(obj, rnti, macSDUs)
            ctx = obj.getUeCtx_(rnti,true);
            macSDUs = localNormalizeMacSDUs_(macSDUs);
            for i = 1:numel(macSDUs)
                lcid = double(macSDUs(i).LCID);
                pdu = uint8(macSDUs(i).Payload(:));
                if lcid == 0
                    ctx.SRB0_RLC.receivePDU(pdu);
                elseif lcid == 1
                    ctx.SRB1_RLC.receivePDU(pdu);
                end
            end
            obj.GNB_UeCtx(rnti) = ctx;
        end

        function processRxGNB_(obj, rnti)
            ctx = obj.getUeCtx_(rnti,false);
            if isempty(ctx)
                return;
            end

            % SRB0 messages
            sdu0 = ctx.SRB0_RLC.pullSDUs();
            for i = 1:numel(sdu0)
                msg = sixgr.l3.rrc.RRC.decodeMessage(sdu0{i});
                ctx.Attach.onUplinkMessage(0, msg, rnti, obj);
            end

            % SRB1 messages (PDCP)
            pdu1 = ctx.SRB1_RLC.pullSDUs();
            for i = 1:numel(pdu1)
                ctx.SRB1_PDCP.rx(pdu1{i});
            end
            sdu1 = ctx.SRB1_PDCP.pullSDUs();
            for i = 1:numel(sdu1)
                msg = sixgr.l3.rrc.RRC.decodeMessage(sdu1{i});
                ctx.Attach.onUplinkMessage(1, msg, rnti, obj);
            end

            obj.GNB_UeCtx(rnti) = ctx;
        end

        function rnti = allocateTempCRNTI_(obj)
            % Simple sequential allocator: choose the smallest unused >= 1.
            used = [];
            if ~isempty(obj.GNB_UeCtx)
                used = cell2mat(obj.GNB_UeCtx.keys);
            end
            rnti = 1;
            if ~isempty(used)
                rnti = max(used) + 1;
            end
        end
    end
end

% ============================== Local helpers =============================

function acts = localMergeActions(a, b)
    acts = a;
    if isempty(b) || ~isstruct(b)
        return;
    end
    f = fieldnames(b);
    for i = 1:numel(f)
        acts.(f{i}) = b.(f{i});
    end
end

function total = localTotalPayload_(sduList)
    total = 0;
    if isempty(sduList), return; end
    for i = 1:numel(sduList)
        if isfield(sduList(i),'Payload') && ~isempty(sduList(i).Payload)
            total = total + numel(sduList(i).Payload);
        end
    end
end

function macSDUs = localNormalizeMacSDUs_(macSDUs)
    if isempty(macSDUs)
        macSDUs = struct('LCID',{},'Payload',{});
        return;
    end
    if ~isstruct(macSDUs) || ~isfield(macSDUs,'LCID') || ~isfield(macSDUs,'Payload')
        error('sixgr:RRC:BadMACSDUs','MAC SDUs must be a struct array with fields LCID and Payload.');
    end
    n = numel(macSDUs);
    out = repmat(struct('LCID',0,'Payload',uint8([])), n, 1);
    for i = 1:n
        out(i).LCID = double(macSDUs(i).LCID);
        out(i).Payload = uint8(macSDUs(i).Payload(:));
    end
    macSDUs = out;
end

function rnti = localParseRNTI_(varargin)
    rnti = [];
    if isempty(varargin)
        error('sixgr:RRC:NeedRNTI','Missing RNTI name-value argument.');
    end
    if mod(numel(varargin),2) ~= 0
        error('sixgr:RRC:BadNV','Name-value inputs must come in pairs.');
    end
    for i = 1:2:numel(varargin)
        k = varargin{i}; v = varargin{i+1};
        if isstring(k), k = char(k); end
        if strcmpi(char(k),'rnti')
            rnti = double(v);
            return;
        end
    end
    error('sixgr:RRC:NeedRNTI','Missing ''RNTI'' name-value argument.');
end

function s = localSanitizeStruct(x)
    % Remove unsupported fields for jsonencode (handles / objects)
    s = struct();
    if ~isstruct(x)
        s.value = x;
        return;
    end
    fn = fieldnames(x);
    for i = 1:numel(fn)
        v = x.(fn{i});
        if isa(v,'handle')
            s.(fn{i}) = class(v);
        elseif isstruct(v)
            s.(fn{i}) = localSanitizeStruct(v);
        elseif iscell(v)
            % best-effort for cells
            try
                s.(fn{i}) = v;
            catch
                s.(fn{i}) = sprintf('<cell:%d>', numel(v));
            end
        else
            s.(fn{i}) = v;
        end
    end
end
