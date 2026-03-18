classdef RLC_TM < handle
% sixgr.l2.rlc.RLC_TM
% RLC Transparent Mode (TM)
%
% NR/LTE RLC TM is used for channels where segmentation/reassembly is not
% performed by RLC (e.g., BCCH/PCCH in typical stacks). This implementation
% is "abstract but coherent":
%  - No RLC header
%  - No segmentation (caller must ensure MAC grant can carry an SDU)
%  - RX delivers bytes exactly as received
%
% Interface (common across RLC modes in this simulator):
%   addSDU(bytes)                 : enqueue upper-layer SDU (typically PDCP PDU)
%   buildPDUs(availBytes)         : produce as many RLC PDUs as fit in availBytes
%   receivePDU(pduBytes)          : consume one received RLC PDU
%   pullSDUs()                    : dequeue all reassembled SDUs for upper layer
%
% Notes:
%  - PDUs returned are uint8 column vectors.
%  - In real stacks, TM relies on MAC for segmentation; here we enforce
%    "no segmentation" to keep behavior unambiguous.

    properties
        Cfg (1,1) struct
        Direction (1,:) char = 'DL'     % 'DL' or 'UL'
        LCID (1,1) double = 0          % logical channel id (for MAC mux)
        Logger = []                    % optional sixgr.core.Logger
    end

    properties(SetAccess=private)
        Stats (1,1) struct = struct( ...
            'TxSDU',0,'TxPDU',0,'RxPDU',0,'RxSDU',0,'Drop',0 )
    end

    properties(Access=private)
        TxQueue cell = {}              % cell of uint8 column vectors
        RxQueue cell = {}
    end

    methods
        function obj = RLC_TM(cfg, varargin)
            if nargin < 1 || isempty(cfg)
                cfg = struct();
            end
            obj.Cfg = cfg;

            % Defaults from cfg if present
            obj.Direction = upper(char(string(sixgr.util.structGet(cfg,"l2.rlc.tm.direction",obj.Direction))));
            obj.LCID = double(sixgr.util.structGet(cfg,"l2.rlc.tm.lcid",obj.LCID));

            % Parse name-value overrides
            if ~isempty(varargin)
                if mod(numel(varargin),2) ~= 0
                    error("sixgr:RLC_TM:BadNV","Name-value inputs must come in pairs.");
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
                        otherwise
                            error("sixgr:RLC_TM:BadOpt","Unknown option: %s", string(k));
                    end
                end
            end
        end

        function reset(obj)
            obj.TxQueue = {};
            obj.RxQueue = {};
            obj.Stats = struct('TxSDU',0,'TxPDU',0,'RxPDU',0,'RxSDU',0,'Drop',0);
        end

        function addSDU(obj, sduBytes)
            if isempty(sduBytes)
                return;
            end
            sduBytes = localToU8(sduBytes);
            obj.TxQueue{end+1} = sduBytes; %#ok<AGROW>
            obj.Stats.TxSDU = obj.Stats.TxSDU + 1;
        end

        function tf = hasData(obj)
            tf = ~isempty(obj.TxQueue);
        end

        function [pdu, meta] = buildPDU(obj, maxBytes)
            % buildPDU Produce one PDU not exceeding maxBytes, or [].
            if nargin < 2 || isempty(maxBytes)
                maxBytes = inf;
            end
            meta = struct('LCID',obj.LCID,'Length',0);
            pdu = uint8([]);

            if isempty(obj.TxQueue)
                return;
            end
            cand = obj.TxQueue{1};
            if numel(cand) > double(maxBytes)
                % TM cannot segment; leave in queue.
                obj.Stats.Drop = obj.Stats.Drop + 1;
                return;
            end
            % Pop
            obj.TxQueue(1) = [];
            pdu = cand(:);
            meta.Length = numel(pdu);
            obj.Stats.TxPDU = obj.Stats.TxPDU + 1;
        end

        function [pdus, metas] = buildPDUs(obj, availBytes)
            % buildPDUs Build as many PDUs as fit within availBytes total.
            if nargin < 2 || isempty(availBytes)
                availBytes = inf;
            end
            pdus = {};
            metas = struct('LCID',{},'Length',{});
            budget = double(availBytes);

            while budget > 0 && ~isempty(obj.TxQueue)
                [pdu, meta] = obj.buildPDU(budget);
                if isempty(pdu)
                    break;
                end
                pdus{end+1} = pdu; %#ok<AGROW>
                metas(end+1) = meta; %#ok<AGROW>
                budget = budget - numel(pdu);
            end
        end


        function macSDUs = buildMACSDUs(obj, availBytes)
            % buildMACSDUs Convenience wrapper for MAC mux.
            % Returns struct array with fields: LCID, Payload
            [pdus, ~] = obj.buildPDUs(availBytes);
            macSDUs = struct('LCID',{},'Payload',{});
            for i = 1:numel(pdus)
                macSDUs(end+1) = struct('LCID',obj.LCID,'Payload',pdus{i}); %#ok<AGROW>
            end
        end

        function receivePDU(obj, pduBytes)
            if isempty(pduBytes)
                return;
            end
            pduBytes = localToU8(pduBytes);
            obj.RxQueue{end+1} = pduBytes; %#ok<AGROW>
            obj.Stats.RxPDU = obj.Stats.RxPDU + 1;
            obj.Stats.RxSDU = obj.Stats.RxSDU + 1;
        end

        function sdus = pullSDUs(obj)
            % pullSDUs Return all pending SDUs and clear queue.
            sdus = obj.RxQueue;
            obj.RxQueue = {};
        end
    end
end

% -------------------------------------------------------------------------
function b = localToU8(x)
    if isa(x,'uint8')
        b = x(:);
    elseif islogical(x)
        b = uint8(x(:));
    else
        b = uint8(x(:));
    end
end
