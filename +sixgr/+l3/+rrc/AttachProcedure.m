classdef AttachProcedure < handle
% sixgr.l3.rrc.AttachProcedure
% NR attach (RRC Setup) with slot-driven Msg1-4 flow and retry-aware RA timers.
%
% This class implements an attach state machine that is compatible with
% both link-level and system-level execution:
%   UE side:
%     - Requires SystemInformation (SIB1) ready (abstracted)
%     - Starts RACH (Msg1) and waits RAR (Msg2)
%     - Sends RRCSetupRequest on SRB0 (Msg3)
%     - Waits RRCSetup on SRB0 (Msg4)
%     - Sends RRCSetupComplete on SRB1, transitions to CONNECTED
%
%   gNB side (per UE context):
%     - On PRACH detection, build and output RAR (Msg2)
%     - On RRCSetupRequest, send RRCSetup (Msg4)
%     - On RRCSetupComplete, mark UE CONNECTED
%
% Message encoding/decoding uses sixgr.l3.rrc.RRC.encodeMessage/decodeMessage.
% This file is ASCII-only.

    properties
        Cfg (1,1) struct
        Role (1,:) char = 'UE'            % 'UE' or 'GNB'
        UEId (1,1) double = 1
        CellID (1,1) double = 1
        Logger = []
    end

    properties(SetAccess=private)
        State (1,:) char = 'IDLE'
        TempCRNTI (1,1) double = -1
        CRNTI (1,1) double = -1
        LastError (1,:) char = ''
    end

    properties(Access=private)
        RACH (1,1) sixgr.l3.rrc.RACHProcedure
        SIReady (1,1) logical = false
        StartSlot (1,1) double = -1
        LastSlot (1,1) double = -1
        LastDetectedPreamble (1,1) double = -1
        LastTimingOffset (1,1) double = 0
    end

    methods
        function obj = AttachProcedure(cfg, varargin)
            if nargin < 1 || isempty(cfg)
                cfg = struct();
            end
            obj.Cfg = cfg;
            obj.CellID = double(sixgr.util.structGet(cfg,'phy.carrier.NCellID',obj.CellID));

            % Parse name-value
            if ~isempty(varargin)
                if mod(numel(varargin),2) ~= 0
                    error('sixgr:AttachProcedure:BadNV','Name-value inputs must come in pairs.');
                end
                for i = 1:2:numel(varargin)
                    k = varargin{i}; v = varargin{i+1};
                    if isstring(k), k = char(k); end
                    switch lower(char(k))
                        case 'role'
                            obj.Role = upper(char(string(v)));
                        case 'ueid'
                            obj.UEId = double(v);
                        case 'cellid'
                            obj.CellID = double(v);
                        case 'logger'
                            obj.Logger = v;
                        otherwise
                            error('sixgr:AttachProcedure:BadOpt','Unknown option: %s', string(k));
                    end
                end
            end

            % Default RACH object (can be replaced by bindRACH)
            obj.RACH = sixgr.l3.rrc.RACHProcedure(cfg,'Role',obj.Role,'UEId',obj.UEId,'CellID',obj.CellID,'Logger',obj.Logger);
        end

        function bindRACH(obj, rachObj)
            if isempty(rachObj)
                return;
            end
            obj.RACH = rachObj;
        end

        function reset(obj)
            obj.State = 'IDLE';
            obj.TempCRNTI = -1;
            obj.CRNTI = -1;
            obj.LastError = '';
            obj.SIReady = false;
            obj.StartSlot = -1;
            obj.LastSlot = -1;
            obj.LastDetectedPreamble = -1;
            obj.LastTimingOffset = 0;
            if ~isempty(obj.RACH)
                obj.RACH.reset();
            end
        end

        function onSystemInformationReady(obj, siObj) %#ok<INUSD>
            % UE: mark SI ready (SIB1 acquired)
            if strcmp(obj.Role,'UE')
                obj.SIReady = true;
                if strcmp(obj.State,'IDLE')
                    obj.State = 'READY';
                end
            end
        end

        function onPrachDetected(obj, preambleIndex, timingOffset, slot)
            % gNB: handle Msg1 detection. Stores preamble and timing.
            %#ok<INUSD>
            if ~strcmp(obj.Role,'GNB')
                return;
            end
            if nargin < 4 || isempty(slot)
                slot = 0;
            end
            obj.LastSlot = double(slot);
            obj.StartSlot = double(slot);
            obj.LastDetectedPreamble = double(preambleIndex);
            obj.LastTimingOffset = double(timingOffset);

            obj.State = 'RAR_PENDING';
        end

        function rar = buildRAR(obj, tempCRNTI)
            % gNB: build Msg2 RAR (abstract)
            if ~strcmp(obj.Role,'GNB')
                rar = [];
                return;
            end
            backoffSlots = max(0, round(double(sixgr.util.structGet(obj.Cfg, 'rrc.rach.backoffSlots', 0))));
            rar = obj.RACH.buildRAR_gNB(tempCRNTI, ...
                'TimingAdvance', double(obj.LastTimingOffset), ...
                'ULGrantBytes', 128, ...
                'PreambleIndex', double(obj.LastDetectedPreamble), ...
                'BackoffSlots', backoffSlots);
            obj.TempCRNTI = double(tempCRNTI);
            obj.State = 'WAIT_MSG3';
        end

        function acts = step(obj, slot, inputs, rrc)
            % step Advance attach procedure; may enqueue SRB messages via rrc.
            %
            % inputs (UE):
            %   inputs.RAR : rar struct or []
            %
            % For gNB, SRB messages are triggered by callbacks from rrc when
            % uplink messages arrive (onUplinkMessage). step() is still
            % callable to progress timers if you add them later.

            if nargin < 2 || isempty(slot), slot = 0; end
            if nargin < 3 || isempty(inputs), inputs = struct(); end
            if nargin < 4, rrc = []; end

            slot = double(slot);
            obj.LastSlot = slot;

            acts = struct();

            if strcmp(obj.Role,'UE')
                acts = obj.stepUE_(slot, inputs, rrc);
            else
                % For gNB, most actions come from onUplinkMessage().
                acts.Notes = '';
            end
        end

        function onDownlinkMessage(obj, srb, msg)
            % UE: receive and process downlink RRC message structs.
            if ~strcmp(obj.Role,'UE')
                return;
            end
            srb = double(srb);
            if ~isstruct(msg) || ~isfield(msg,'msgType')
                return;
            end

            if srb == 0 && strcmpi(msg.msgType,'RRCSetup')
                % Msg4 received
                obj.CRNTI = double(sixgr.util.structGet(msg,'cRNTI',obj.TempCRNTI));
                obj.State = 'WAIT_SETUP_COMPLETE_TX';
            elseif srb == 1 && strcmpi(msg.msgType,'RRCReconfiguration')
                % Handover command hook
                obj.State = 'HO_IN_PROGRESS';
            end
        end

        function onUplinkMessage(obj, srb, msg, rnti, rrcObj)
            % gNB: handle uplink RRC message structs and respond via rrcObj.
            if ~strcmp(obj.Role,'GNB')
                return;
            end
            if nargin < 5, rrcObj = []; end
            srb = double(srb);
            rnti = double(rnti);

            if ~isstruct(msg) || ~isfield(msg,'msgType')
                return;
            end

            if srb == 0 && strcmpi(msg.msgType,'RRCSetupRequest')
                % Msg3 received -> send Msg4 RRCSetup
                obj.TempCRNTI = double(sixgr.util.structGet(msg,'tempCRNTI',rnti));
                obj.CRNTI = obj.TempCRNTI;

                setup = struct();
                setup.msgType = 'RRCSetup';
                setup.cRNTI = obj.CRNTI;
                setup.cellID = obj.CellID;
                setup.srb1 = struct('lcid',1,'mode','AM');
                setup.timestamp = char(datetime('now','Format','yyyy-MM-dd HH:mm:ss.SSS'));

                if ~isempty(rrcObj)
                    rrcObj.sendSRB0(setup,'RNTI',rnti);
                end

                obj.State = 'WAIT_SETUP_COMPLETE';

            elseif srb == 1 && strcmpi(msg.msgType,'RRCSetupComplete')
                % Attach complete
                obj.CRNTI = double(sixgr.util.structGet(msg,'cRNTI',rnti));
                obj.State = 'CONNECTED';
            elseif srb == 1 && strcmpi(msg.msgType,'MeasurementReport')
                if ~isempty(rrcObj)
                    rrcObj.onMeasurementReport(rnti, msg);
                end
            end
        end
    end

    methods(Access=private)
        function acts = stepUE_(obj, slot, inputs, rrc)
            acts = struct();
            if nargin < 4, rrc = []; end

            % Ensure SI readiness (if user didn't call onSystemInformationReady, treat as ready if cfg says so)
            if ~obj.SIReady
                autoSI = logical(sixgr.util.structGet(obj.Cfg,'rrc.autoSIReady',true));
                if autoSI
                    obj.SIReady = true;
                end
            end

            if strcmp(obj.State,'IDLE')
                if obj.SIReady
                    obj.State = 'READY';
                else
                    obj.State = 'WAIT_SI';
                end
            end

            if strcmp(obj.State,'WAIT_SI')
                if obj.SIReady
                    obj.State = 'READY';
                end
            end

            if strcmp(obj.State,'READY')
                % Start RACH Msg1
                act = obj.RACH.startUE(slot);
                if isempty(fieldnames(act))
                    if strcmp(obj.RACH.State,'FAILED')
                        obj.State = 'FAILED';
                        failCause = string(obj.RACH.FailureCause);
                        if strlength(failCause) == 0
                            failCause = "RACH start failed";
                        end
                        obj.LastError = char(failCause);
                    end
                    return;
                end
                obj.State = 'WAIT_RAR';
                obj.StartSlot = slot;
                acts.PrachTx = act;
                return;
            end

            if strcmp(obj.State,'WAIT_RAR')
                if isfield(inputs,'RAR') && ~isempty(inputs.RAR)
                    obj.RACH.onRAR(inputs.RAR, slot);
                    if obj.RACH.hasRAR()
                        obj.TempCRNTI = obj.RACH.TempCRNTI;
                        obj.State = 'MSG3_PENDING';
                    end
                else
                    obj.RACH.tick(slot);
                    if obj.RACH.shouldRetry()
                        obj.RACH.consumeRetry();
                        obj.State = 'READY';
                        acts.Notes = 'RAR timeout, retrying Msg1.';
                        return;
                    end
                    if strcmp(obj.RACH.State,'FAILED')
                        obj.State = 'FAILED';
                        failCause = string(obj.RACH.FailureCause);
                        if strlength(failCause) == 0
                            failCause = "RAR timeout";
                        end
                        obj.LastError = char(failCause);
                    end
                end
            end

            if strcmp(obj.State,'MSG3_PENDING')
                % Build and send RRCSetupRequest over SRB0 (Msg3)
                req = struct();
                req.msgType = 'RRCSetupRequest';
                req.ueId = obj.UEId;
                req.cellID = obj.CellID;
                req.tempCRNTI = obj.TempCRNTI;
                req.establishmentCause = 'mo-Signalling';
                req.timestamp = char(datetime('now','Format','yyyy-MM-dd HH:mm:ss.SSS'));

                if ~isempty(rrc)
                    rrc.sendSRB0(req);
                end
                obj.RACH.markMsg3Sent();
                obj.RACH.markWaitMsg4();
                obj.State = 'WAIT_RRC_SETUP';
                return;
            end

            if strcmp(obj.State,'WAIT_RRC_SETUP')
                % Wait until onDownlinkMessage receives RRCSetup (Msg4)
                obj.RACH.tick(slot);
                if strcmp(obj.RACH.State,'FAILED')
                    obj.State = 'FAILED';
                    failCause = string(obj.RACH.FailureCause);
                    if strlength(failCause) == 0
                        failCause = "Contention resolution timer expired";
                    end
                    obj.LastError = char(failCause);
                end
            end

            if strcmp(obj.State,'WAIT_SETUP_COMPLETE_TX')
                % Send RRCSetupComplete over SRB1
                comp = struct();
                comp.msgType = 'RRCSetupComplete';
                comp.ueId = obj.UEId;
                comp.cellID = obj.CellID;
                comp.cRNTI = obj.CRNTI;
                comp.selectedPLMN = 1;
                comp.dedicatedNAS = struct('type','RegistrationRequest','payload','');
                comp.timestamp = char(datetime('now','Format','yyyy-MM-dd HH:mm:ss.SSS'));

                if ~isempty(rrc)
                    rrc.sendSRB1(comp);
                end

                obj.RACH.markSuccess();
                obj.State = 'CONNECTED';
                return;
            end
        end
    end
end
