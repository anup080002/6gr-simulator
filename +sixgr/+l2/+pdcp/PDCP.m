classdef PDCP < handle
% sixgr.l2.pdcp.PDCP
% Packet Data Convergence Protocol (PDCP) - simplified, message-flow correct.
%
% This PDCP implementation is intended for an end-to-end MATLAB simulator.
% It focuses on the *stateful message flow* rather than bit-exact TS 38.323
% compliance. The design goals are:
%   - coherent interfaces between SDAP <-> PDCP <-> RLC
%   - correct sequencing / reordering behavior (in-order delivery)
%   - optional ciphering and integrity hooks (simulation-friendly)
%
% PDCP Data PDU format (simplified):
%   Header carries only PDCP SN (12 or 18 bits).
%   Optional Integrity tag appended (4 bytes).
%
% Header encoding (data PDU):
%   SNBits=12: 2 bytes
%     byte1: bits3..0 = SN[11:8], bits7..4 reserved 0
%     byte2: SN[7:0]
%   SNBits=18: 3 bytes
%     byte1: bits1..0 = SN[17:16], bits7..2 reserved 0
%     byte2: SN[15:8]
%     byte3: SN[7:0]
%
% Ciphering/Integrity:
%   Built-in algorithms:
%     Cipher:
%       - NEA0 (3GPP null cipher, exact no-encryption behavior)
%       - SIM_XOR_SHA256 (simulation-friendly deterministic stream XOR)
%     Integrity:
%       - NIA0 (3GPP null integrity, exact zero-tag behavior)
%       - SIM_SHA256_4B (simulation-friendly deterministic 4-byte tag)
%   - You can replace with your own functions via name-value:
%       'CipherFcn', @(payload,sn,dir)->payload
%       'IntegrityFcn', @(hdr,payload,sn,dir)->uint8(4)
%
% API:
%   pduBytes = tx(sduBytes)
%   rx(pduBytes)              % feed one received PDCP PDU
%   sdus = pullSDUs()         % get delivered SDUs (to SDAP)
%
% Typical flow:
%   sdapPdu -> pdcp.tx -> rlc.addSDU -> ...
%   ... -> rlc.pullSDUs -> pdcp.rx -> sdap.rx
%
% Defaults from cfg (best effort):
%   cfg.l2.pdcp.snBits                 (12)
%   cfg.l2.pdcp.ciphering.enable       (false)
%   cfg.l2.pdcp.ciphering.algorithm    ("SIM_XOR_SHA256")
%   cfg.l2.pdcp.integrity.enable       (false)
%   cfg.l2.pdcp.integrity.algorithm    ("SIM_SHA256_4B")
%   cfg.l2.pdcp.ciphering.key          (uint8)
%   cfg.l2.pdcp.integrity.key          (uint8)

    properties
        Cfg (1,1) struct
        Direction (1,:) char = 'DL'       % 'DL' or 'UL'
        DRBID (1,1) double = 1
        Logger = []
    end

    properties
        SNBits (1,1) double = 12          % 12 or 18
        CipheringEnabled (1,1) logical = false
        IntegrityEnabled (1,1) logical = false
        StrictMode (1,1) logical = false
        CipherAlgorithm (1,:) char = 'SIM_XOR_SHA256'
        IntegrityAlgorithm (1,:) char = 'SIM_SHA256_4B'

        CipherKey uint8 = uint8([1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16])
        IntegrityKey uint8 = uint8([21 22 23 24 25 26 27 28 29 30 31 32 33 34 35 36])

        CipherFcn = []        % function handle or []
        IntegrityFcn = []     % function handle or []
    end

    properties(SetAccess=private)
        Stats (1,1) struct = struct( ...
            'TxSDU',0,'TxPDU',0,'TxBytes',0, ...
            'RxPDU',0,'RxSDU',0,'RxBytes',0, ...
            'DropDup',0,'IntegrityFail',0 )
    end

    properties(Access=private)
        Modulus (1,1) double = 4096
        TxNextSN (1,1) double = 0
        RxExpectedSN (1,1) double = 0

        RxBufValid logical = false(0,1) % [Modulus x 1] valid flags
        RxBufPayload cell = {}          % [Modulus x 1] payload bytes
        RxBufMeta cell = {}             % [Modulus x 1] trace meta
        RxSeen logical = false(0,1)     % [Modulus x 1] duplicate detection flags
        RxSDUQueue cell = {}
        RxMetaQueue cell = {}
        RxDropMetaQueue cell = {}
        RxSDUCount (1,1) double = 0
        RxDropCount (1,1) double = 0
    end

    methods
        function obj = PDCP(cfg, varargin)
            if nargin < 1 || isempty(cfg)
                cfg = struct();
            end
            obj.Cfg = cfg;

            obj.Direction = upper(char(string(sixgr.util.structGet(cfg,"l2.pdcp.direction",obj.Direction))));
            obj.DRBID = double(sixgr.util.structGet(cfg,"l2.pdcp.drbid",obj.DRBID));
            obj.SNBits = double(sixgr.util.structGet(cfg,"l2.pdcp.snBits",obj.SNBits));

            obj.CipheringEnabled = logical(sixgr.util.structGet(cfg,"l2.pdcp.ciphering.enable",obj.CipheringEnabled));
            obj.IntegrityEnabled = logical(sixgr.util.structGet(cfg,"l2.pdcp.integrity.enable",obj.IntegrityEnabled));
            obj.StrictMode = logical(sixgr.util.structGet(cfg,"run.strictMode",obj.StrictMode));
            obj.CipherAlgorithm = upper(char(string(sixgr.util.structGet(cfg,"l2.pdcp.ciphering.algorithm",obj.CipherAlgorithm))));
            obj.IntegrityAlgorithm = upper(char(string(sixgr.util.structGet(cfg,"l2.pdcp.integrity.algorithm",obj.IntegrityAlgorithm))));

            k1 = sixgr.util.structGet(cfg,"l2.pdcp.ciphering.key",[]);
            if ~isempty(k1)
                obj.CipherKey = uint8(k1(:).');
            end
            k2 = sixgr.util.structGet(cfg,"l2.pdcp.integrity.key",[]);
            if ~isempty(k2)
                obj.IntegrityKey = uint8(k2(:).');
            end

            if ~ismember(obj.SNBits, [12 18])
                error("sixgr:PDCP:BadSNBits","PDCP SNBits must be 12 or 18 (got %g).", obj.SNBits);
            end
            obj.Modulus = 2^obj.SNBits;

            % Overrides
            if ~isempty(varargin)
                if mod(numel(varargin),2) ~= 0
                    error("sixgr:PDCP:BadNV","Name-value inputs must come in pairs.");
                end
                for i = 1:2:numel(varargin)
                    k = varargin{i}; v = varargin{i+1};
                    if isstring(k), k = char(k); end
                    switch lower(char(k))
                        case 'direction'
                            obj.Direction = upper(char(string(v)));
                        case 'drbid'
                            obj.DRBID = double(v);
                        case 'logger'
                            obj.Logger = v;
                        case 'snbits'
                            obj.SNBits = double(v);
                            obj.Modulus = 2^obj.SNBits;
                        case 'cipheringenabled'
                            obj.CipheringEnabled = logical(v);
                        case 'integrityenabled'
                            obj.IntegrityEnabled = logical(v);
                        case 'strictmode'
                            obj.StrictMode = logical(v);
                        case 'cipheralgorithm'
                            obj.CipherAlgorithm = upper(char(string(v)));
                        case 'integrityalgorithm'
                            obj.IntegrityAlgorithm = upper(char(string(v)));
                        case 'cipherkey'
                            obj.CipherKey = uint8(v(:).');
                        case 'integritykey'
                            obj.IntegrityKey = uint8(v(:).');
                        case 'cipherfcn'
                            obj.CipherFcn = v;
                        case 'integrityfcn'
                            obj.IntegrityFcn = v;
                        otherwise
                            error("sixgr:PDCP:BadOpt","Unknown option: %s", string(k));
                    end
                end
            end

            obj.validateSecurityConfig_();

            obj.initRxArrays_();
            obj.initOutputQueues_();
        end

        function reset(obj)
            obj.TxNextSN = 0;
            obj.RxExpectedSN = 0;
            obj.initRxArrays_();
            obj.initOutputQueues_();
            obj.Stats = struct('TxSDU',0,'TxPDU',0,'TxBytes',0,'RxPDU',0,'RxSDU',0,'RxBytes',0,'DropDup',0,'IntegrityFail',0);
        end

        function [pdu, meta] = tx(obj, sduBytes, varargin)
            % tx Build one PDCP Data PDU from an SDU.
            metaIn = localTraceMetaFromArgs(varargin{:});
            if isempty(sduBytes)
                pdu = uint8([]);
                meta = localStampPDCPMeta(metaIn, NaN);
                return;
            end
            sduBytes = localToU8(sduBytes);

            sn = obj.TxNextSN;
            hdr = localEncodePDCPHeader(obj.SNBits, sn);
            meta = localStampPDCPMeta(metaIn, sn);

            payload = sduBytes;

            if obj.CipheringEnabled
                payload = obj.applyCipher(payload, sn);
            end

            if obj.IntegrityEnabled
                tag = obj.applyIntegrity(hdr, payload, sn);
                pdu = [hdr; payload; tag];
            else
                pdu = [hdr; payload];
            end

            obj.TxNextSN = mod(obj.TxNextSN + 1, obj.Modulus);

            obj.Stats.TxSDU = obj.Stats.TxSDU + 1;
            obj.Stats.TxPDU = obj.Stats.TxPDU + 1;
            obj.Stats.TxBytes = obj.Stats.TxBytes + numel(pdu);
        end

        function rx(obj, pduBytes, varargin)
            % rx Consume one received PDCP PDU.
            metaIn = localTraceMetaFromArgs(varargin{:});
            if isempty(pduBytes)
                return;
            end
            pduBytes = localToU8(pduBytes);

            [sn, hdrLen] = localDecodePDCPHeader(obj.SNBits, pduBytes);
            sn = mod(double(sn), obj.Modulus);
            metaBase = localStampPDCPMeta(metaIn, sn);

            obj.Stats.RxPDU = obj.Stats.RxPDU + 1;

            % Duplicate detection
            idxSN = sn + 1;
            if idxSN < 1 || idxSN > numel(obj.RxSeen)
                return;
            end
            if obj.RxSeen(idxSN)
                obj.Stats.DropDup = obj.Stats.DropDup + 1;
                d = metaBase;
                d.DropCause = "PDCP_DUPLICATE_SN";
                obj.enqueueDrop_(d);
                return;
            end
            obj.RxSeen(idxSN) = true;

            payloadWithTag = pduBytes((hdrLen+1):end);

            % Integrity verify
            if obj.IntegrityEnabled
                if numel(payloadWithTag) < 4
                    obj.Stats.IntegrityFail = obj.Stats.IntegrityFail + 1;
                    d = metaBase;
                    d.DropCause = "PDCP_INTEGRITY_PDU_TOO_SHORT";
                    obj.enqueueDrop_(d);
                    return;
                end
                payload = payloadWithTag(1:end-4);
                tagRx = payloadWithTag(end-3:end);
                tagEx = obj.applyIntegrity(pduBytes(1:hdrLen), payload, sn);
                if ~isequal(tagRx(:), tagEx(:))
                    obj.Stats.IntegrityFail = obj.Stats.IntegrityFail + 1;
                    d = metaBase;
                    d.DropCause = "PDCP_INTEGRITY_TAG_MISMATCH";
                    obj.enqueueDrop_(d);
                    return;
                end
            else
                payload = payloadWithTag;
            end

            if obj.CipheringEnabled
                payload = obj.applyCipher(payload, sn);
            end

            % Reordering buffer
            obj.RxBufValid(idxSN) = true;
            obj.RxBufPayload{idxSN} = payload;
            obj.RxBufMeta{idxSN} = metaBase;

            % In-order delivery
            advanced = true;
            while advanced
                advanced = false;
                idxExp = obj.RxExpectedSN + 1;
                if idxExp >= 1 && idxExp <= numel(obj.RxBufValid) && obj.RxBufValid(idxExp)
                    pl = obj.RxBufPayload{idxExp};
                    tr = localTraceMetaFromArgs(obj.RxBufMeta{idxExp});
                    obj.RxBufValid(idxExp) = false;
                    obj.RxBufPayload{idxExp} = [];
                    obj.RxBufMeta{idxExp} = [];
                    if ~isfinite(double(tr.DeliverySlot))
                        tr.DeliverySlot = double(tr.GrantSlot);
                    end
                    obj.enqueueSDU_(pl, tr);
                    obj.Stats.RxSDU = obj.Stats.RxSDU + 1;
                    obj.Stats.RxBytes = obj.Stats.RxBytes + numel(pl);
                    obj.RxExpectedSN = mod(obj.RxExpectedSN + 1, obj.Modulus);
                    advanced = true;
                end
            end
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
                % already assigned
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
    end

    methods(Access=private)
        function validateSecurityConfig_(obj)
            cAlg = upper(strtrim(char(obj.CipherAlgorithm)));
            iAlg = upper(strtrim(char(obj.IntegrityAlgorithm)));
            cOk = ismember(cAlg, ["SIM_XOR_SHA256","NEA0"]);
            iOk = ismember(iAlg, ["SIM_SHA256_4B","NIA0"]);

            if obj.CipheringEnabled && isempty(obj.CipherFcn) && ~cOk
                error("sixgr:PDCP:CipherAlgorithm", ...
                    "Unsupported built-in cipher algorithm: %s (use CipherFcn override for custom).", cAlg);
            end
            if obj.IntegrityEnabled && isempty(obj.IntegrityFcn) && ~iOk
                error("sixgr:PDCP:IntegrityAlgorithm", ...
                    "Unsupported built-in integrity algorithm: %s (use IntegrityFcn override for custom).", iAlg);
            end

            if obj.StrictMode
                if obj.CipheringEnabled && isempty(obj.CipherFcn) && startsWith(cAlg, "SIM")
                    error("sixgr:PDCP:StrictCipher", ...
                        "Strict mode forbids simulation cipher algorithm '%s'. Use NEA0 or provide exact CipherFcn.", cAlg);
                end
                if obj.IntegrityEnabled && isempty(obj.IntegrityFcn) && startsWith(iAlg, "SIM")
                    error("sixgr:PDCP:StrictIntegrity", ...
                        "Strict mode forbids simulation integrity algorithm '%s'. Use NIA0 or provide exact IntegrityFcn.", iAlg);
                end
            end
        end

        function initRxArrays_(obj)
            m = max(1, round(double(obj.Modulus)));
            obj.RxBufValid = false(m,1);
            obj.RxBufPayload = cell(m,1);
            obj.RxBufMeta = cell(m,1);
            obj.RxSeen = false(m,1);
        end

        function initOutputQueues_(obj)
            cap = 256;
            obj.RxSDUQueue = cell(cap,1);
            obj.RxMetaQueue = cell(cap,1);
            obj.RxDropMetaQueue = cell(cap,1);
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
            if idx > numel(obj.RxDropMetaQueue)
                newCap = max(numel(obj.RxDropMetaQueue) * 2, idx);
                obj.RxDropMetaQueue{newCap,1} = [];
            end
            obj.RxDropMetaQueue{idx,1} = meta;
            obj.RxDropCount = idx;
        end

        function out = applyCipher(obj, payload, sn)
            payload = payload(:);
            if ~isempty(obj.CipherFcn)
                out = obj.CipherFcn(payload, sn, obj.Direction);
                out = localToU8(out);
                return;
            end

            switch upper(strtrim(char(obj.CipherAlgorithm)))
                case 'NEA0'
                    % 3GPP null ciphering behavior.
                    out = payload;
                case 'SIM_XOR_SHA256'
                    ks = localKeystreamSHA256(obj.CipherKey, sn, obj.Direction, numel(payload));
                    out = bitxor(payload, ks);
                otherwise
                    error("sixgr:PDCP:CipherAlgorithm", ...
                        "Unsupported cipher algorithm: %s", string(obj.CipherAlgorithm));
            end
        end

        function tag = applyIntegrity(obj, hdr, payload, sn)
            if ~isempty(obj.IntegrityFcn)
                tag = obj.IntegrityFcn(hdr(:), payload(:), sn, obj.Direction);
                tag = localToU8(tag);
                if numel(tag) ~= 4
                    error("sixgr:PDCP:IntegrityFcn","IntegrityFcn must return 4 bytes.");
                end
                return;
            end

            switch upper(strtrim(char(obj.IntegrityAlgorithm)))
                case 'NIA0'
                    % 3GPP null integrity behavior.
                    tag = zeros(4,1,'uint8');
                case 'SIM_SHA256_4B'
                    tag = localMAC4_SHA256(obj.IntegrityKey, hdr(:), payload(:), sn, obj.Direction);
                otherwise
                    error("sixgr:PDCP:IntegrityAlgorithm", ...
                        "Unsupported integrity algorithm: %s", string(obj.IntegrityAlgorithm));
            end
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

function hdr = localEncodePDCPHeader(snBits, sn)
    sn = double(sn);
    if snBits == 12
        sn = mod(sn, 4096);
        b1 = uint8(bitand(bitshift(uint16(sn), -8), uint16(15))); % SN[11:8]
        b2 = uint8(bitand(uint16(sn), uint16(255)));
        hdr = [b1; b2];
    else
        sn = mod(sn, 2^18);
        b1 = uint8(bitand(bitshift(uint32(sn), -16), uint32(3))); % SN[17:16]
        b2 = uint8(bitand(bitshift(uint32(sn), -8), uint32(255)));
        b3 = uint8(bitand(uint32(sn), uint32(255)));
        hdr = [b1; b2; b3];
    end
end

function [sn, hdrLen] = localDecodePDCPHeader(snBits, pdu)
    if snBits == 12
        if numel(pdu) < 2
            error("sixgr:PDCP:BadPDU","PDCP PDU too short.");
        end
        b1 = uint16(pdu(1));
        b2 = uint16(pdu(2));
        sn = double(bitshift(bitand(b1, 15), 8) + b2);
        hdrLen = 2;
    else
        if numel(pdu) < 3
            error("sixgr:PDCP:BadPDU","PDCP PDU too short.");
        end
        b1 = uint32(pdu(1));
        b2 = uint32(pdu(2));
        b3 = uint32(pdu(3));
        sn = double(bitshift(bitand(b1, 3), 16) + bitshift(b2, 8) + b3);
        hdrLen = 3;
    end
end

function ks = localKeystreamSHA256(key, sn, dir, n)
    % Derive keystream bytes using SHA-256 blocks (simulation-only).
    key = uint8(key(:));
    snu = uint32(sn);
    dirb = uint8(double(upper(char(dir)) == 'U')); % UL=1, DL=0
    seed = [key; typecast(snu,'uint8').'; dirb];
    seed = seed(:);

    ks = zeros(n,1,'uint8');
    filled = 0;
    ctr = uint32(0);

    while filled < n
        blockIn = [seed; typecast(ctr,'uint8').'];
        h = localSHA256(blockIn);
        take = min(numel(h), n-filled);
        ks((filled+1):(filled+take)) = h(1:take);
        filled = filled + take;
        ctr = ctr + 1;
    end
end

function tag = localMAC4_SHA256(key, hdr, payload, sn, dir)
    key = uint8(key(:));
    snu = uint32(sn);
    dirb = uint8(double(upper(char(dir)) == 'U'));
    in = [key; typecast(snu,'uint8').'; dirb; hdr(:); payload(:)];
    h = localSHA256(in);
    tag = h(1:4);
end

function h = localSHA256(bytes)
    % Compute SHA-256 digest using Java (available in MATLAB desktop).
    bytes = uint8(bytes(:));
    try
        md = java.security.MessageDigest.getInstance('SHA-256');
        md.update(bytes);
        d = typecast(md.digest,'uint8');
        h = uint8(d(:));
    catch
        % Fallback: very weak hash (should not happen in typical MATLAB)
        s = uint32(sum(uint32(bytes)) + 2654435761);
        h = typecast([s s+1 s+2 s+3 s+4 s+5 s+6 s+7],'uint8');
        h = h(:);
    end
    if numel(h) < 32
        % pad if needed
        hp = zeros(32,1,'uint8');
        hp(1:numel(h)) = h;
        h = hp;
    end
    h = h(1:32);
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
end

function meta = localStampPDCPMeta(metaIn, sn)
meta = localTraceMetaFromArgs(metaIn);
if isfinite(double(sn))
    meta.PDCP_SN = double(sn);
end
if ~isfield(meta, "DropCause") || strlength(string(meta.DropCause)) == 0
    meta.DropCause = "";
end
end
