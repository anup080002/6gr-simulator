classdef SDAP < handle
% sixgr.l2.sdap.SDAP
% Service Data Adaptation Protocol (SDAP) - simplified but coherent.
%
% SDAP maps QoS Flows (QFI) to DRBs (bearers / LCIDs) and can optionally
% carry an SDAP header with QFI + reflective QoS indication.
%
% This implementation provides:
%   - QFI <-> LCID mapping table (configurable)
%   - SDAP header encode/decode (1 byte, simulation-friendly)
%   - simple TX/RX APIs suitable for end-to-end simulator message flow
%
% SDAP header (simplified, 1 byte):
%   bit7: RQI (Reflective QoS Indication)
%   bit6: RDI (Reflective QoS "downlink" indicator - used in some flows)
%   bits5..0: QFI (0..63)
%
% Note:
%   This is not a bit-exact TS 37.324 implementation; it is designed to
%   keep the layering and state flow correct while remaining lightweight.
%
% API:
%   setMapping(qfi, lcid)
%   lcid = mapQFIToLCID(qfi)
%   pdu = tx(payloadBytes, qfi, 'RQI',0/1, 'RDI',0/1)   -> returns struct
%   [payload,qfi,rqi,rdi] = rx(pduBytes)
%
% Output of tx() is designed to be passed directly into PDCP as an SDU:
%   out = sdap.tx(ipPkt,qfi);
%   pdcpPdu = pdcp.tx(out.SDUPayload);
% and the lcid is used to pick the right RLC/MAC logical channel.

    properties
        Cfg (1,1) struct
        HeaderPresent (1,1) logical = true
        DefaultQFI (1,1) double = 9
        DefaultLCID (1,1) double = 4
        Logger = []
    end

    properties(SetAccess=private)
        Stats (1,1) struct = struct('TxSDU',0,'RxSDU',0,'Drop',0)
    end

    properties(Access=private)
        QFI2LCID containers.Map
    end

    methods
        function obj = SDAP(cfg, varargin)
            if nargin < 1 || isempty(cfg)
                cfg = struct();
            end
            obj.Cfg = cfg;

            obj.HeaderPresent = logical(sixgr.util.structGet(cfg,"l2.sdap.headerPresent",obj.HeaderPresent));
            obj.DefaultQFI = double(sixgr.util.structGet(cfg,"l2.sdap.defaultQfi",obj.DefaultQFI));
            obj.DefaultLCID = double(sixgr.util.structGet(cfg,"l2.sdap.defaultLcid",obj.DefaultLCID));

            obj.QFI2LCID = containers.Map('KeyType','double','ValueType','double');

            % Optional mapping table from cfg: cfg.l2.sdap.qfiToLcid as Nx2
            tbl = sixgr.util.structGet(cfg,"l2.sdap.qfiToLcid",[]);
            if ~isempty(tbl)
                try
                    tbl = double(tbl);
                    for i = 1:size(tbl,1)
                        obj.QFI2LCID(tbl(i,1)) = tbl(i,2);
                    end
                catch
                    % ignore malformed mapping
                end
            end

            if ~isempty(varargin)
                if mod(numel(varargin),2) ~= 0
                    error("sixgr:SDAP:BadNV","Name-value inputs must come in pairs.");
                end
                for i = 1:2:numel(varargin)
                    k = varargin{i}; v = varargin{i+1};
                    if isstring(k), k = char(k); end
                    switch lower(char(k))
                        case 'headerpresent'
                            obj.HeaderPresent = logical(v);
                        case 'defaultqfi'
                            obj.DefaultQFI = double(v);
                        case 'defaultlcid'
                            obj.DefaultLCID = double(v);
                        case 'logger'
                            obj.Logger = v;
                        otherwise
                            error("sixgr:SDAP:BadOpt","Unknown option: %s", string(k));
                    end
                end
            end
        end

        function reset(obj)
            obj.QFI2LCID = containers.Map('KeyType','double','ValueType','double');
            obj.Stats = struct('TxSDU',0,'RxSDU',0,'Drop',0);
        end

        function setMapping(obj, qfi, lcid)
            obj.QFI2LCID(double(qfi)) = double(lcid);
        end

        function lcid = mapQFIToLCID(obj, qfi)
            qfi = double(qfi);
            if isKey(obj.QFI2LCID, qfi)
                lcid = obj.QFI2LCID(qfi);
            else
                lcid = obj.DefaultLCID;
            end
        end

        function out = tx(obj, payloadBytes, qfi, varargin)
            % tx Build SDAP SDU (payload to PDCP) and return mapping metadata.
            if nargin < 3 || isempty(qfi)
                qfi = obj.DefaultQFI;
            end
            qfi = double(qfi);

            rqi = 0;
            rdi = 0;
            if ~isempty(varargin)
                if mod(numel(varargin),2) ~= 0
                    error("sixgr:SDAP:BadNV","Name-value inputs must come in pairs.");
                end
                for i = 1:2:numel(varargin)
                    k = varargin{i}; v = varargin{i+1};
                    if isstring(k), k = char(k); end
                    switch lower(char(k))
                        case 'rqi'
                            rqi = double(v) ~= 0;
                        case 'rdi'
                            rdi = double(v) ~= 0;
                        otherwise
                            error("sixgr:SDAP:BadOpt","Unknown option: %s", string(k));
                    end
                end
            end

            payloadBytes = localToU8(payloadBytes);
            lcid = obj.mapQFIToLCID(qfi);

            if obj.HeaderPresent
                hdr = obj.encodeHeader(qfi, rqi, rdi);
                sdu = [hdr; payloadBytes];
            else
                hdr = uint8([]);
                sdu = payloadBytes;
            end

            out = struct();
            out.LCID = double(lcid);
            out.QFI = qfi;
            out.RQI = logical(rqi);
            out.RDI = logical(rdi);
            out.HeaderPresent = obj.HeaderPresent;
            out.SDUPayload = sdu(:);
            out.Header = hdr;

            obj.Stats.TxSDU = obj.Stats.TxSDU + 1;
        end

        function [payload, qfi, rqi, rdi] = rx(obj, sduBytes, varargin)
            %#ok<INUSD>
            % rx Parse one SDAP SDU from PDCP and return payload + flow metadata.
            if isempty(sduBytes)
                payload = uint8([]);
                qfi = obj.DefaultQFI;
                rqi = false;
                rdi = false;
                return;
            end
            sduBytes = localToU8(sduBytes);

            if obj.HeaderPresent
                if numel(sduBytes) < 1
                    obj.Stats.Drop = obj.Stats.Drop + 1;
                    payload = uint8([]);
                    qfi = obj.DefaultQFI;
                    rqi = false;
                    rdi = false;
                    return;
                end
                [qfi, rqi, rdi] = obj.decodeHeader(sduBytes(1));
                payload = sduBytes(2:end);
            else
                payload = sduBytes;
                qfi = obj.DefaultQFI;
                rqi = false;
                rdi = false;
            end

            payload = payload(:);
            obj.Stats.RxSDU = obj.Stats.RxSDU + 1;
        end
    end

    methods(Static)
        function b = encodeHeader(qfi, rqi, rdi)
            qfi = double(qfi);
            qfi = max(0, min(63, floor(qfi)));
            rqi = double(rqi) ~= 0;
            rdi = double(rdi) ~= 0;
            b = uint8(qfi);
            if rdi
                b = bitor(b, uint8(64));
            end
            if rqi
                b = bitor(b, uint8(128));
            end
            b = b(:);
        end

        function [qfi, rqi, rdi] = decodeHeader(b)
            b = uint8(b);
            rqi = bitand(b, uint8(128)) ~= 0;
            rdi = bitand(b, uint8(64)) ~= 0;
            qfi = double(bitand(b, uint8(63)));
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
