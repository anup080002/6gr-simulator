classdef SystemInformation < handle
% sixgr.l3.rrc.SystemInformation
% Stores and serves MIB/SIB1 information for the simulator.
%
% This class provides:
%  - A single place to store serving cell MIB and SIB1 data
%  - Accessors for PRACH-related parameters used by RACHProcedure
%  - Encoder/decoder for the repository's constrained SIB1 ASN.1 profile.
%
% This file is ASCII-only.

    properties
        CellID (1,1) double = 1
        MIB (1,1) struct = struct()
        SIB1 (1,1) struct = struct()
        Logger = []
    end

    properties(SetAccess=private)
        HasMIB (1,1) logical = false
        HasSIB1 (1,1) logical = false
        Cfg_ (1,1) struct = struct()
    end

    methods
        function obj = SystemInformation(cfg, varargin)
            if nargin < 1 || isempty(cfg)
                cfg = struct();
            end

            obj.CellID = double(sixgr.util.structGet(cfg,'phy.carrier.NCellID',obj.CellID));

            % Parse name-value
            if ~isempty(varargin)
                if mod(numel(varargin),2) ~= 0
                    error('sixgr:SystemInformation:BadNV','Name-value inputs must come in pairs.');
                end
                for i = 1:2:numel(varargin)
                    k = varargin{i}; v = varargin{i+1};
                    if isstring(k), k = char(k); end
                    switch lower(char(k))
                        case 'cellid'
                            obj.CellID = double(v);
                        case 'logger'
                            obj.Logger = v;
                        otherwise
                            error('sixgr:SystemInformation:BadOpt','Unknown option: %s', string(k));
                    end
                end
            end

            % Populate default SI from cfg if present
            obj.loadDefaultsFromConfig_(cfg);
            obj.Cfg_ = cfg;
        end

        function updateFromPBCH(obj, pb)
            % updateFromPBCH Best-effort extract MIB-like info from PBCH recovery output.
            if isempty(pb) || ~isstruct(pb)
                return;
            end

            mib = struct();
            mib.CellID = double(sixgr.util.structGet(pb,'NCellID',obj.CellID));
            mib.SSBIndex = double(sixgr.util.structGet(pb,'SSBIndex',0));
            mib.HalfFrame = double(sixgr.util.structGet(pb,'HalfFrame',0));
            mib.SFN4LSB = sixgr.util.structGet(pb,'SFN4LSB',[]);
            mib.TimeStamp = char(datetime('now','Format','yyyy-MM-dd HH:mm:ss.SSS'));

            obj.MIB = mib;
            obj.CellID = mib.CellID;
            obj.HasMIB = true;
        end

        function setSIB1(obj, sib1Struct)
            if nargin < 2 || isempty(sib1Struct) || ~isstruct(sib1Struct)
                return;
            end
            obj.SIB1 = sib1Struct;
            obj.HasSIB1 = true;
        end

        function sib1Struct = getSIB1(obj)
            sib1Struct = obj.SIB1;
        end

        function prach = getPRACHConfig(obj, cfg)
            % getPRACHConfig Return PRACH config struct for PHY/RACH layers.
            %
            % Priority: SIB1 overrides cfg defaults if present.
            if nargin < 2 || isempty(cfg)
                cfg = struct();
            end

            prach = struct();
            prach.enable = logical(sixgr.util.structGet(cfg,'phy.prach.enable',false));
            prach.configurationIndex = double(sixgr.util.structGet(cfg,'phy.prach.configurationIndex',16));
            prach.subcarrierSpacing_kHz = double(sixgr.util.structGet(cfg,'phy.prach.subcarrierSpacing_kHz',1.25));
            prach.preambleFormat = char(string(sixgr.util.structGet(cfg,'phy.prach.preambleFormat','A1')));
            prach.rootSeqIndex = double(sixgr.util.structGet(cfg,'phy.prach.rootSeqIndex',1));
            prach.zeroCorrelationZone = double(sixgr.util.structGet(cfg,'phy.prach.zeroCorrelationZone',8));

            if obj.HasSIB1
                if isfield(obj.SIB1,'prach') && isstruct(obj.SIB1.prach)
                    s = obj.SIB1.prach;
                    prach = localStructMerge_(prach, s);
                end
            end
        end

        function bytes = encodeSIB1(obj)
            if ~obj.HasSIB1
                bytes = uint8([]);
                return;
            end
            sib1Tree = obj.SIB1;
            if ~(isstruct(sib1Tree) && isfield(sib1Tree, "message"))
                sib1Tree = sixgr.rrc.asn1.buildBCCHDLSCHMessage(obj.Cfg_, "CellID", obj.CellID);
            end
            [bits, ~] = sixgr.rrc.asn1.encodeSIB1UPER(sib1Tree);
            bytes = localBitsToBytes_(bits);
        end

        function ok = decodeSIB1(obj, bytes)
            ok = false;
            try
                [s, ~] = sixgr.rrc.asn1.decodeSIB1UPER(uint8(bytes(:)));
            catch
                s = struct();
            end
            if isstruct(s) && ~isempty(fieldnames(s))
                obj.SIB1 = s;
                obj.HasSIB1 = true;
                ok = true;
            end
        end

        function decodeAndSetSIB1(obj, bytes)
            obj.decodeSIB1(bytes);
        end

        function ok = validateSIB1RoundTrip(obj)
            ok = false;
            if ~obj.HasSIB1
                return;
            end
            bytes = obj.encodeSIB1();
            objCopy = sixgr.l3.rrc.SystemInformation(obj.Cfg_);
            if ~objCopy.decodeSIB1(bytes)
                return;
            end
            ok = isequaln(obj.SIB1, objCopy.SIB1);
        end

        function bytes = encodeMIB(obj)
            if ~obj.HasMIB
                bytes = uint8([]);
                return;
            end
            bytes = localEncode_(obj.MIB);
        end

        function decodeAndSetMIB(obj, bytes)
            s = localDecode_(bytes);
            if isstruct(s)
                obj.MIB = s;
                if isfield(s,'CellID')
                    obj.CellID = double(s.CellID);
                end
                obj.HasMIB = true;
            end
        end
    end

    methods(Access=private)
        function loadDefaultsFromConfig_(obj, cfg)
            % Provide an abstract SI object for the attach state machine. Strict
            % SIB1 conformance evidence must come from the PHY broadcast path,
            % not from this holder.
            sib1 = struct();
            sib1.cellID = double(sixgr.util.structGet(cfg,'phy.carrier.NCellID',obj.CellID));
            sib1.plmn = sixgr.util.structGet(cfg,'rrc.sib1.plmn','00101');
            sib1.tac = double(sixgr.util.structGet(cfg,'rrc.sib1.tac',1));
            sib1.cellBarred = false;
            sib1.intraFreqReselection = true;

            % Embed PRACH config (links to cfg.phy.prach)
            sib1.prach = struct();
            sib1.prach.configurationIndex = double(sixgr.util.structGet(cfg,'phy.prach.configurationIndex',16));
            sib1.prach.subcarrierSpacing_kHz = double(sixgr.util.structGet(cfg,'phy.prach.subcarrierSpacing_kHz',1.25));
            sib1.prach.preambleFormat = char(string(sixgr.util.structGet(cfg,'phy.prach.preambleFormat','A1')));
            sib1.prach.rootSeqIndex = double(sixgr.util.structGet(cfg,'phy.prach.rootSeqIndex',1));
            sib1.prach.zeroCorrelationZone = double(sixgr.util.structGet(cfg,'phy.prach.zeroCorrelationZone',8));
            sib1.prach.nPreambles = double(sixgr.util.structGet(cfg,'phy.prach.nPreambles',64));

            obj.SIB1 = sib1;
            obj.HasSIB1 = true;
        end
    end
end

% ============================== Local helpers =============================

function out = localStructMerge_(a, b)
    out = a;
    if isempty(b) || ~isstruct(b), return; end
    fn = fieldnames(b);
    for i = 1:numel(fn)
        out.(fn{i}) = b.(fn{i});
    end
end

function bytes = localEncode_(s)
    try
        js = jsonencode(s);
    catch
        js = jsonencode(struct('encodeFail',true));
    end
    payload = uint8(unicode2native(js,'UTF-8'));
    L = uint32(numel(payload));
    hdr = typecast(swapbytes(L), 'uint8');
    bytes = [hdr(:); payload(:)];
end

function s = localDecode_(bytes)
    s = struct();
    if isempty(bytes)
        return;
    end
    try
        raw = uint8(bytes(:)).';
        if numel(raw) >= 4
            L = double(swapbytes(typecast(raw(1:4), 'uint32')));
            if isfinite(L) && L >= 0 && numel(raw) >= 4 + L
                raw = raw(5:(4+L));
            end
        end
        js = native2unicode(raw,'UTF-8');
        s = jsondecode(js);
    catch
        s = struct();
    end
end

function bytes = localBitsToBytes_(bits)
bits = int8(bits(:));
pad = mod(8 - mod(numel(bits), 8), 8);
if pad > 0
    bits = [bits; zeros(pad, 1, "int8")];
end
bytes = zeros(numel(bits)/8, 1, "uint8");
for i = 1:numel(bytes)
    v = uint8(0);
    for b = 1:8
        v = bitor(bitshift(v, 1), uint8(bits((i-1)*8+b) ~= 0));
    end
    bytes(i) = v;
end
end
