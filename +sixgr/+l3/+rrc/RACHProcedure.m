classdef RACHProcedure < handle
% sixgr.l3.rrc.RACHProcedure
% Random Access (RACH) context helper for UE and gNB.
%
% This class models the essential information and timers around the 4-step
% contention-based random access procedure:
%   Msg1: PRACH preamble
%   Msg2: RAR (Random Access Response) - MAC CE (abstracted here)
%   Msg3: UE message on UL-CCCH (RRCSetupRequest in this simulator)
%   Msg4: Contention resolution (RRCSetup / RRCReject in this simulator)
%
% In your current build, Msg1 uses your PHY PRACH_Tx/PRACH_Rx blocks. Msg2 is
% produced/consumed as a struct (RAR) because you may not yet carry RAR as a
% MAC CE through PDSCH/PUSCH. Msg3/Msg4 are carried on SRB0 using RLC TM.
%
% This file is ASCII-only.

    properties
        Cfg (1,1) struct
        Role (1,:) char = 'UE'              % 'UE' or 'GNB'
        UEId (1,1) double = 1
        CellID (1,1) double = 1
        Logger = []
    end

    properties(SetAccess=private)
        State (1,:) char = 'IDLE'
        PreambleIndex (1,1) double = -1
        TempCRNTI (1,1) double = -1
        TimingAdvance (1,1) double = 0
        ULGrantBytes (1,1) double = 0
        StartSlot (1,1) double = -1
        LastSlot (1,1) double = -1
        Msg1Attempts (1,1) double = 0
        Msg3SentSlot (1,1) double = -1
        FailureCause (1,:) char = ''
    end

    properties
        % Timers configured in milliseconds per TS 38.321/38.331 and
        % materialized into slots using the active UL numerology.
        RAResponseWindow_ms (1,1) double = 10
        ContentionResolutionTimer_ms (1,1) double = 64
        SlotDuration_ms (1,1) double = 1
        RAResponseWindow_slots (1,1) double = 10
        ContentionResolutionTimer_slots (1,1) double = 64
        PreambleTransMax (1,1) double = 4
    end

    methods
        function obj = RACHProcedure(cfg, varargin)
            if nargin < 1 || isempty(cfg)
                cfg = struct();
            end
            obj.Cfg = cfg;

            obj.CellID = double(sixgr.util.structGet(cfg,'phy.carrier.NCellID',obj.CellID));
            [slotsPerMs, slotDurationMs] = localResolveSlotsPerMs(cfg);
            obj.SlotDuration_ms = double(slotDurationMs);
            obj.RAResponseWindow_ms = double(sixgr.util.structGet(cfg,'rrc.rach.raResponseWindow_ms',obj.RAResponseWindow_ms));
            obj.ContentionResolutionTimer_ms = double(sixgr.util.structGet(cfg,'rrc.rach.contentionResolutionTimer_ms',obj.ContentionResolutionTimer_ms));
            legacyRASlots = sixgr.util.structGet(cfg,'rrc.rach.raResponseWindow_slots',[]);
            legacyCRSlots = sixgr.util.structGet(cfg,'rrc.rach.contentionResolutionTimer_slots',[]);
            raSlotsExplicit = ~isempty(legacyRASlots) && isempty(sixgr.util.structGet(cfg,'rrc.rach.raResponseWindow_ms',[]));
            crSlotsExplicit = ~isempty(legacyCRSlots) && isempty(sixgr.util.structGet(cfg,'rrc.rach.contentionResolutionTimer_ms',[]));
            if raSlotsExplicit
                obj.RAResponseWindow_slots = double(legacyRASlots);
            end
            if crSlotsExplicit
                obj.ContentionResolutionTimer_slots = double(legacyCRSlots);
            end

            % Parse name-value
            if ~isempty(varargin)
                if mod(numel(varargin),2) ~= 0
                    error('sixgr:RACHProcedure:BadNV','Name-value inputs must come in pairs.');
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
                        case 'raresponsewindow_slots'
                            obj.RAResponseWindow_slots = double(v);
                            raSlotsExplicit = true;
                        case 'raresponsewindow_ms'
                            obj.RAResponseWindow_ms = double(v);
                            raSlotsExplicit = false;
                        case 'contentionresolutiontimer_slots'
                            obj.ContentionResolutionTimer_slots = double(v);
                            crSlotsExplicit = true;
                        case 'contentionresolutiontimer_ms'
                            obj.ContentionResolutionTimer_ms = double(v);
                            crSlotsExplicit = false;
                        case 'preambletransmax'
                            obj.PreambleTransMax = max(1, round(double(v)));
                        otherwise
                            error('sixgr:RACHProcedure:BadOpt','Unknown option: %s', string(k));
                    end
                end
            end

            localValidateRAResponseWindow(obj.RAResponseWindow_ms);
            if ~raSlotsExplicit
                obj.RAResponseWindow_slots = max(1, round(double(obj.RAResponseWindow_ms) * double(slotsPerMs)));
            end
            if ~crSlotsExplicit
                obj.ContentionResolutionTimer_slots = max(1, round(double(obj.ContentionResolutionTimer_ms) * double(slotsPerMs)));
            end
            obj.PreambleTransMax = max(1, round(double(sixgr.util.structGet(cfg,'rrc.rach.preambleTransMax',obj.PreambleTransMax))));
        end

        function reset(obj)
            obj.State = 'IDLE';
            obj.PreambleIndex = -1;
            obj.TempCRNTI = -1;
            obj.TimingAdvance = 0;
            obj.ULGrantBytes = 0;
            obj.StartSlot = -1;
            obj.LastSlot = -1;
            obj.Msg1Attempts = 0;
            obj.Msg3SentSlot = -1;
            obj.FailureCause = '';
        end

        function act = startUE(obj, slot, varargin)
            % startUE Start contention-based RA at UE; returns PRACH Tx action.
            if ~strcmp(obj.Role,'UE')
                error('sixgr:RACHProcedure:Role','startUE is for UE role.');
            end
            if nargin < 2 || isempty(slot)
                slot = 0;
            end

            act = struct();
            if obj.Msg1Attempts >= obj.PreambleTransMax
                obj.State = 'FAILED';
                obj.FailureCause = 'PREAMBLE_MAX_TX_REACHED';
                return;
            end

            preamble = [];
            if ~isempty(varargin)
                if mod(numel(varargin),2) ~= 0
                    error('sixgr:RACHProcedure:BadNV','Name-value inputs must come in pairs.');
                end
                for i = 1:2:numel(varargin)
                    k = varargin{i}; v = varargin{i+1};
                    if isstring(k), k = char(k); end
                    switch lower(char(k))
                        case 'preambleindex'
                            preamble = double(v);
                        otherwise
                            error('sixgr:RACHProcedure:BadOpt','Unknown option: %s', string(k));
                    end
                end
            end

            if isempty(preamble)
                % Choose a random preamble index (0..63 typical); allow cfg override
                nPre = double(sixgr.util.structGet(obj.Cfg,'phy.prach.nPreambles',64));
                preamble = randi([0 max(0,nPre-1)],1,1);
            end

            obj.PreambleIndex = preamble;
            obj.State = 'MSG1_SENT';
            obj.StartSlot = double(slot);
            obj.LastSlot = double(slot);
            obj.Msg1Attempts = obj.Msg1Attempts + 1;
            obj.Msg3SentSlot = -1;
            obj.FailureCause = '';

            act.Type = 'PRACH_TX';
            act.Slot = double(slot);
            act.CellID = obj.CellID;
            act.UEId = obj.UEId;
            act.PreambleIndex = obj.PreambleIndex;
            act.Attempt = obj.Msg1Attempts;
        end

        function onRAR(obj, rar, slot)
            % onRAR UE consumes RAR (Msg2) and stores Temp C-RNTI and UL grant.
            if ~strcmp(obj.Role,'UE')
                error('sixgr:RACHProcedure:Role','onRAR is for UE role.');
            end
            if nargin < 3 || isempty(slot)
                slot = obj.LastSlot + 1;
            end
            obj.LastSlot = double(slot);

            if isempty(rar) || ~isstruct(rar)
                return;
            end

            if isfield(rar, 'PreambleIndex')
                pre = double(sixgr.util.structGet(rar, 'PreambleIndex', -1));
                if pre >= 0 && pre ~= obj.PreambleIndex
                    return;
                end
            end

            obj.TempCRNTI = double(sixgr.util.structGet(rar,'TempCRNTI',-1));
            obj.TimingAdvance = double(sixgr.util.structGet(rar,'TimingAdvance',0));
            obj.ULGrantBytes = double(sixgr.util.structGet(rar,'ULGrantBytes',0));

            if obj.TempCRNTI >= 0
                obj.State = 'RAR_RECEIVED';
                obj.FailureCause = '';
            end
        end

        function tf = hasRAR(obj)
            tf = strcmp(obj.State,'RAR_RECEIVED') || strcmp(obj.State,'MSG3_SENT') || strcmp(obj.State,'WAIT_MSG4') || strcmp(obj.State,'SUCCESS');
        end

        function act = buildRAR_gNB(obj, tempCRNTI, varargin)
            % buildRAR_gNB (gNB) Build an abstract RAR struct.
            if ~strcmp(obj.Role,'GNB')
                error('sixgr:RACHProcedure:Role','buildRAR_gNB is for gNB role.');
            end

            ta = 0;
            ulGrant = double(sixgr.util.structGet(obj.Cfg,'rrc.rach.defaultULGrantBytes', 64));
            preamble = -1;
            backoffSlots = 0;

            if ~isempty(varargin)
                if mod(numel(varargin),2) ~= 0
                    error('sixgr:RACHProcedure:BadNV','Name-value inputs must come in pairs.');
                end
                for i = 1:2:numel(varargin)
                    k = varargin{i}; v = varargin{i+1};
                    if isstring(k), k = char(k); end
                    switch lower(char(k))
                        case 'timingadvance'
                            ta = double(v);
                        case 'ulgrantbytes'
                            ulGrant = double(v);
                        case 'preambleindex'
                            preamble = double(v);
                        case 'backoffslots'
                            backoffSlots = max(0, round(double(v)));
                        otherwise
                            error('sixgr:RACHProcedure:BadOpt','Unknown option: %s', string(k));
                    end
                end
            end

            act = struct();
            act.msgType = 'RAR';
            act.CellID = obj.CellID;
            act.TempCRNTI = double(tempCRNTI);
            act.TimingAdvance = double(ta);
            act.ULGrantBytes = double(ulGrant);
            act.PreambleIndex = double(preamble);
            act.BackoffSlots = double(backoffSlots);
        end

        function tick(obj, slot)
            % tick Update timers and fail if windows expired (UE only).
            if nargin < 2 || isempty(slot)
                slot = obj.LastSlot + 1;
            end
            slot = double(slot);
            obj.LastSlot = slot;

            if strcmp(obj.Role,'UE')
                if strcmp(obj.State,'MSG1_SENT')
                    if (slot - obj.StartSlot) >= obj.RAResponseWindow_slots
                        if obj.Msg1Attempts < obj.PreambleTransMax
                            obj.State = 'RETRY_PENDING';
                            obj.FailureCause = 'RAR_TIMEOUT_RETRY';
                        else
                            obj.State = 'FAILED';
                            obj.FailureCause = 'RAR_TIMEOUT_MAX_TX';
                        end
                    end
                elseif strcmp(obj.State,'WAIT_MSG4')
                    refSlot = obj.Msg3SentSlot;
                    if refSlot < 0
                        refSlot = obj.StartSlot;
                    end
                    if (slot - refSlot) >= obj.ContentionResolutionTimer_slots
                        obj.State = 'FAILED';
                        obj.FailureCause = 'CONTENTION_RESOLUTION_TIMEOUT';
                    end
                end
            end
        end

        function markMsg3Sent(obj)
            if strcmp(obj.Role,'UE') && strcmp(obj.State,'RAR_RECEIVED')
                obj.State = 'MSG3_SENT';
                obj.Msg3SentSlot = obj.LastSlot;
            end
        end

        function markWaitMsg4(obj)
            if strcmp(obj.Role,'UE')
                obj.State = 'WAIT_MSG4';
                if obj.Msg3SentSlot < 0
                    obj.Msg3SentSlot = obj.LastSlot;
                end
            end
        end

        function markSuccess(obj)
            obj.State = 'SUCCESS';
            obj.FailureCause = '';
        end

        function tf = shouldRetry(obj)
            tf = strcmp(obj.State,'RETRY_PENDING');
        end

        function consumeRetry(obj)
            if strcmp(obj.State,'RETRY_PENDING')
                obj.State = 'IDLE';
            end
        end
    end
end

function [slotsPerMs, slotDurationMs] = localResolveSlotsPerMs(cfg)
scs_kHz = double(sixgr.util.structGet(cfg,'phy.carrier.SubcarrierSpacing', ...
    sixgr.util.structGet(cfg,'phy.pusch.subcarrierSpacing', 15)));
if ~(isscalar(scs_kHz) && isfinite(scs_kHz) && scs_kHz > 0)
    scs_kHz = 15;
end
mu = round(log2(max(scs_kHz, 15) / 15));
mu = max(0, mu);
slotsPerMs = 2 ^ mu;
slotDurationMs = 1.0 / slotsPerMs;
end

function localValidateRAResponseWindow(valueMs)
validRaWindow_ms = [1 2 4 8 10 20 40 80];
valueMs = double(valueMs);
if ~(isscalar(valueMs) && isfinite(valueMs)) || ~any(abs(valueMs - validRaWindow_ms) < 0.5)
    warning('sixgr:rrc:RACHProcedure:InvalidRAWindow', ...
        'ra-ResponseWindow_ms=%.1f is not a standard NR value. Valid: %s ms.', ...
        valueMs, mat2str(validRaWindow_ms));
end
end
