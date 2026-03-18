classdef (Abstract) SchedulerBase < handle
% sixgr.l2.mac.SchedulerBase
% Base class for MAC schedulers (DL/UL).
%
% This is an "abstract but coherent" scheduler intended for the unified
% simulator. It produces grant structs per slot that can be consumed by the
% PHY Tx/Rx chains (PDSCH/PUSCH) and by higher-layer state machines.
%
% Design goals
%  - Keep the API stable while the simulator grows from LLS -> SLS -> Hybrid.
%  - Make retransmissions (HARQ) a first-class scheduling concern.
%  - Avoid hard dependence on Wireless Network Simulation Library (WNS),
%    since it may be absent. This code can be used standalone or as a
%    backend under WNS when installed.
%
% Expected UE state (per element in ueStates array)
%   ue.RNTI              : scalar numeric (unique UE id)
%   ue.DLBufferBytes     : bytes queued at gNB for DL (optional)
%   ue.ULBufferBytes     : bytes reported by UE for UL (optional)
%   ue.CQI               : 1..15 (optional, for PF metric / AMC)
%   ue.RI                : 1..4  (optional)
%   ue.Modulation        : e.g., '64QAM' (optional override)
%   ue.TargetCodeRate    : 0..1  (optional override)
%
% Grant struct (per scheduled UE)
%   g.Direction          : 'DL' or 'UL'
%   g.Slot               : slot index (caller-defined)
%   g.RNTI               : UE RNTI
%   g.PRBSet             : 0-based PRB indices (vector)
%   g.SymbolAllocation   : [startSym nSym]
%   g.Modulation         : modulation string
%   g.NumLayers          : number of layers
%   g.TargetCodeRate     : target code rate
%   g.TBSBits            : transport block size (bits)
%   g.TBSBytes           : transport block size (bytes)
%   g.HARQ               : struct with HarqID, NDI, RV, IsRetransmission
%
% Notes
%  - This scheduler generates a compact DCI bitfield payload per grant
%    (field-packed simulator representation) alongside DCI-ready intent
%    fields used by PHY/control modules.
%  - PRBSet uses 0-based indexing to match 5G Toolbox config objects.
%  - TBS is estimated via nrTBS with NREPerPRB from nrPDSCHInfo/nrPUSCHInfo.
%
% Keep this file ASCII-only.

    properties
        Cfg (1,1) struct
        Direction (1,:) char = 'DL'  % 'DL' or 'UL'
        Alpha (1,1) double = 0.9     % PF averaging factor (exp)
        MetricAveraging (1,:) char = 'exp' % 'exp'|'simple'
        Logger = []                  % optional sixgr.core.Logger
        HARQ = []                    % optional sixgr.l2.mac.HARQEntity
    end

    properties(SetAccess=protected)
        Carrier = []                 % nrCarrierConfig (optional helper)
        SlotDuration_s (1,1) double = 1e-3
        NSizeGrid (1,1) double = 0
        SymbolsPerSlot (1,1) double = 14
    end

    properties(Access=protected)
        UEStats = struct('RNTI',{},'AvgThroughput_bps',{},'LastServedSlot',{},'LastTBSBits',{})
        TBSCache = []
        UseMexTBS (1,1) logical = false
        UEIndexMap = []
    end

    methods
        function obj = SchedulerBase(cfg, varargin)
            if nargin < 1 || isempty(cfg)
                error('sixgr:SchedulerBase:NoCfg','SchedulerBase requires cfg struct.');
            end
            obj.Cfg = cfg;

            % Defaults from cfg
            obj.Direction = char(string(sixgr.util.structGet(cfg,"mac.scheduler.direction",obj.Direction)));
            obj.MetricAveraging = char(string(sixgr.util.structGet(cfg,"mac.scheduler.metricAveraging",obj.MetricAveraging)));
            obj.Alpha = double(sixgr.util.structGet(cfg,"mac.scheduler.alpha",obj.Alpha));

            % Parse name-value overrides
            if ~isempty(varargin)
                if mod(numel(varargin),2) ~= 0
                    error('sixgr:SchedulerBase:BadNV','Name-value inputs must come in pairs.');
                end
                for i = 1:2:numel(varargin)
                    key = varargin{i};
                    val = varargin{i+1};
                    if isstring(key), key = char(key); end
                    switch lower(char(key))
                        case 'direction'
                            obj.Direction = upper(char(string(val)));
                        case 'alpha'
                            obj.Alpha = double(val);
                        case 'metricaveraging'
                            obj.MetricAveraging = char(string(val));
                        case 'logger'
                            obj.Logger = val;
                        case 'harq'
                            obj.HARQ = val;
                    end
                end
            end

            % Build a carrier helper if 5G Toolbox is available
            try
                [carrier, ~] = sixgr.phy.grid.makeCarrier(cfg);
                obj.Carrier = carrier;
                obj.NSizeGrid = double(carrier.NSizeGrid);
                obj.SymbolsPerSlot = double(carrier.SymbolsPerSlot);

                % Slot duration: 1ms / 2^mu where mu = log2(SCS/15k)
                scs = double(carrier.SubcarrierSpacing);
                mu = log2(max(scs,15)/15);
                if isfinite(mu) && mu >= 0
                    obj.SlotDuration_s = 1e-3 / (2^mu);
                else
                    obj.SlotDuration_s = 1e-3;
                end
            catch
                % Leave defaults; scheduler can still run with budgets passed in.
                obj.Carrier = [];
                obj.NSizeGrid = double(sixgr.util.structGet(cfg,"phy.carrier.NSizeGrid",66));
                obj.SymbolsPerSlot = 14;
                obj.SlotDuration_s = 1e-3;
            end

            % HARQ default (optional)
            try
                harqEnable = logical(sixgr.util.structGet(cfg,"mac.harq.enable",true));
                if harqEnable && isempty(obj.HARQ)
                    obj.HARQ = sixgr.l2.mac.HARQEntity(cfg,'Direction',obj.Direction,'Logger',obj.Logger);
                end
            catch
                % ignore
            end

            try
                obj.TBSCache = containers.Map('KeyType','char','ValueType','any');
            catch
                obj.TBSCache = [];
            end
            try
                obj.UEIndexMap = containers.Map('KeyType','double','ValueType','double');
            catch
                obj.UEIndexMap = [];
            end
            obj.UseMexTBS = logical(sixgr.util.structGet(cfg, "run.useMex", false)) || ...
                logical(sixgr.util.structGet(cfg, "mac.scheduler.useMexTBS", false));
        end

        function ueStats = getUEStats(obj)
            ueStats = obj.UEStats;
        end

        function resetStats(obj)
            obj.UEStats = struct('RNTI',{},'AvgThroughput_bps',{},'LastServedSlot',{},'LastTBSBits',{});
            try
                obj.UEIndexMap = containers.Map('KeyType','double','ValueType','double');
            catch
                obj.UEIndexMap = [];
            end
        end

        function updateAfterRx(obj, rxFeedback)
            % updateAfterRx Update scheduler statistics after RX feedback.
            %
            % rxFeedback can be:
            %  - struct array with fields: RNTI, TBSBits, Ack (logical)
            %  - table with variables: RNTI, TBSBits, Ack
            if isempty(rxFeedback)
                return;
            end
            if istable(rxFeedback)
                rntiList = rxFeedback.RNTI;
                tbsList  = rxFeedback.TBSBits;
                ackList  = rxFeedback.Ack;
            else
                rntiList = [rxFeedback.RNTI];
                tbsList  = [rxFeedback.TBSBits];
                ackList  = [rxFeedback.Ack];
            end

            for k = 1:numel(rntiList)
                rnti = double(rntiList(k));
                tbsBits = double(tbsList(k));
                ack = logical(ackList(k));
                obj.updateAvgThroughput(rnti, tbsBits, ack);
            end
        end

        function updateAvgThroughput(obj, rnti, tbsBits, ack)
            % Exponential moving average throughput per UE for PF.
            i = obj.ensureUE(rnti);
            inst_bps = 0;
            if ack
                inst_bps = double(tbsBits) / max(obj.SlotDuration_s, eps);
            end
            old = double(obj.UEStats(i).AvgThroughput_bps);

            switch lower(char(obj.MetricAveraging))
                case 'exp'
                    a = min(max(obj.Alpha,0),1);
                    obj.UEStats(i).AvgThroughput_bps = a*old + (1-a)*inst_bps;
                otherwise
                    % simple moving average (very rough)
                    obj.UEStats(i).AvgThroughput_bps = 0.5*old + 0.5*inst_bps;
            end
            obj.UEStats(i).LastTBSBits = double(tbsBits);
        end

        function idx = ensureUE(obj, rnti)
            % Ensure UEStats entry exists.
            if ~isempty(obj.UEIndexMap)
                if isKey(obj.UEIndexMap, double(rnti))
                    idx = double(obj.UEIndexMap(double(rnti)));
                    if idx >= 1 && idx <= numel(obj.UEStats)
                        return;
                    end
                end
            end
            idx = find([obj.UEStats.RNTI] == rnti, 1, 'first');
            if isempty(idx)
                obj.UEStats(end+1).RNTI = rnti; %#ok<AGROW>
                obj.UEStats(end).AvgThroughput_bps = 1; % avoid div-by-zero
                obj.UEStats(end).LastServedSlot = -inf;
                obj.UEStats(end).LastTBSBits = 0;
                idx = numel(obj.UEStats);
            end
            if ~isempty(obj.UEIndexMap)
                obj.UEIndexMap(double(rnti)) = double(idx);
            end
        end

        function [prbAvail, symAlloc] = defaultBudget(obj, budget)
            % budget can be empty or a struct.
            if nargin < 2 || isempty(budget)
                budget = struct();
            end

            if isfield(budget,'PRBSet') && ~isempty(budget.PRBSet)
                prbAvail = double(budget.PRBSet(:).');
            else
                nrb = double(obj.NSizeGrid);
                if isfield(budget,'NPRB') && ~isempty(budget.NPRB)
                    nrb = double(budget.NPRB);
                end
                prbAvail = 0:(nrb-1);
            end

            if isfield(budget,'SymbolAllocation') && ~isempty(budget.SymbolAllocation)
                symAlloc = double(budget.SymbolAllocation(:).');
            else
                symAlloc = [0 double(obj.SymbolsPerSlot)];
            end
        end

        function [modStr, nLayers, targetCodeRate] = selectAMC(obj, ue)
            % Select modulation/layers/code rate.
            %
            % If UE provides overrides, use them; otherwise fall back to cfg.
            dir = upper(obj.Direction);
            if strcmp(dir,'DL')
                modStr = char(string(sixgr.util.structGet(obj.Cfg,"phy.pdsch.modulation","16QAM")));
                nLayers = double(sixgr.util.structGet(obj.Cfg,"phy.pdsch.nLayers",1));
                targetCodeRate = double(sixgr.util.structGet(obj.Cfg,"phy.pdsch.codeRate",0.5));
            else
                modStr = char(string(sixgr.util.structGet(obj.Cfg,"phy.pusch.modulation","16QAM")));
                nLayers = double(sixgr.util.structGet(obj.Cfg,"phy.pusch.nLayers",1));
                targetCodeRate = double(sixgr.util.structGet(obj.Cfg,"phy.pusch.codeRate",0.5));
            end

            if isfield(ue,'Modulation') && ~isempty(ue.Modulation)
                modStr = char(string(ue.Modulation));
            end
            if isfield(ue,'NumLayers') && ~isempty(ue.NumLayers)
                nLayers = double(ue.NumLayers);
            elseif isfield(ue,'RI') && ~isempty(ue.RI)
                % If RI present, use it as layers (clamped)
                nLayers = max(1, min(8, double(ue.RI)));
            end
            if isfield(ue,'TargetCodeRate') && ~isempty(ue.TargetCodeRate)
                targetCodeRate = double(ue.TargetCodeRate);
            end

            % Clamp
            nLayers = max(1, min(8, round(nLayers)));
            targetCodeRate = min(max(targetCodeRate, 0.05), 0.95);
        end

        function [tbsBits, tbsBytes, nrePerPRB] = estimateTBS(obj, modStr, nLayers, nPRB, symAlloc, targetCodeRate)
            % Estimate TB size using nrTBS. Uses NREPerPRB from nrPDSCHInfo/nrPUSCHInfo.
            if nargin < 5 || isempty(symAlloc)
                symAlloc = [0 obj.SymbolsPerSlot];
            end
            nSym = double(symAlloc(2));

            % Memoize repeated TBS queries (same AMC + budget) since these are
            % called very frequently in per-slot scheduling loops.
            key = "";
            if ~isempty(obj.TBSCache)
                key = sprintf("%s|%s|%d|%d|%d|%.4f", upper(char(obj.Direction)), upper(char(modStr)), ...
                    round(double(nLayers)), round(double(nPRB)), round(double(nSym)), ...
                    round(double(targetCodeRate) * 1e4) / 1e4);
                if isKey(obj.TBSCache, key)
                    v = obj.TBSCache(key);
                    tbsBits = double(v(1));
                    tbsBytes = double(v(2));
                    nrePerPRB = double(v(3));
                    return;
                end
            end

            useFastNRE = logical(sixgr.util.structGet(obj.Cfg, "mac.scheduler.fastNREApprox", true));
            strictMode = logical(sixgr.util.structGet(obj.Cfg, "run.strictMode", false));
            if strictMode
                useFastNRE = false;
            end
            nrePerPRB = 12*nSym; % fast approximation
            if ~useFastNRE
                try
                    if strcmpi(obj.Direction,'DL')
                        pdsch = nrPDSCHConfig;
                        pdsch.Modulation = char(modStr);
                        pdsch.NumLayers = double(nLayers);
                        pdsch.PRBSet = 0:(max(nPRB,1)-1);
                        pdsch.SymbolAllocation = [0 nSym];
                        info = nrPDSCHInfo(pdsch);
                        nrePerPRB = double(info.NREPerPRB);
                    else
                        pusch = nrPUSCHConfig;
                        pusch.Modulation = char(modStr);
                        pusch.NumLayers = double(nLayers);
                        pusch.PRBSet = 0:(max(nPRB,1)-1);
                        pusch.SymbolAllocation = [0 nSym];
                        info = nrPUSCHInfo(pusch);
                        nrePerPRB = double(info.NREPerPRB);
                    end
                catch
                    % keep fallback
                end
            end

            qm = sixgr.l2.mac.SchedulerBase.modOrder(modStr);
            if useFastNRE
                if obj.UseMexTBS && exist("sixgr_l2_mac_estimateTBSApprox_entry_mex", "file") == 3
                    [tbsBits, tbsBytes, nrePerPRB] = sixgr_l2_mac_estimateTBSApprox_entry_mex( ...
                        double(qm), double(nLayers), double(nPRB), double(nSym), double(targetCodeRate));
                else
                    eff = qm * targetCodeRate;
                    tbsBits = floor(double(nPRB) * double(nrePerPRB) * eff);
                    tbsBits = 8 * floor(tbsBits / 8);
                    tbsBytes = floor(tbsBits / 8);
                end
            else
                try
                    tbsBits = double(nrTBS(char(modStr), double(nLayers), double(nPRB), double(nrePerPRB), double(targetCodeRate), 0));
                catch
                    if strictMode
                        error("sixgr:SchedulerBase:TBSFallback", ...
                            "Strict mode forbids rough TBS fallback when nrTBS evaluation fails.");
                    end
                    obj.log('warn', "nrTBS evaluation failed; setting TBS=0 for this grant.");
                    tbsBits = 0;
                end
                tbsBytes = floor(tbsBits/8);
            end

            if ~isempty(obj.TBSCache) && strlength(string(key)) > 0
                obj.TBSCache(char(key)) = [double(tbsBits), double(tbsBytes), double(nrePerPRB)];
            end
        end

        function metric = pfMetric(obj, ue, tbsBits)
            % PF metric = instRate / avgRate.
            i = obj.ensureUE(double(ue.RNTI));
            avg = double(obj.UEStats(i).AvgThroughput_bps);
            inst = double(tbsBits) / max(obj.SlotDuration_s, eps);
            metric = inst / max(avg, 1);
        end

        function dci = buildDCIBitfield(obj, grant)
            % buildDCIBitfield Build compact simulator DCI bitfield payload.
            dci = struct("Format", "", "Bits", uint8([]), "Hex", "", ...
                "FieldMap", struct(), "RIV", 0, "RBStart", 0, "RBLength", 0);
            if nargin < 2 || isempty(grant) || ~isstruct(grant)
                return;
            end

            prbSet = double(sixgr.util.structGet(grant, "PRBSet", []));
            if isempty(prbSet)
                return;
            end
            prbSet = sort(unique(prbSet(:).'));
            rbStart = max(0, round(min(prbSet)));
            rbLen = max(1, round(numel(prbSet)));
            nRB = max(1, round(double(obj.NSizeGrid)));
            rbStart = min(rbStart, max(0, nRB - 1));
            rbLen = min(rbLen, nRB);

            % 38.214-style RIV mapping.
            if rbLen - 1 <= floor(nRB / 2)
                riv = nRB * (rbLen - 1) + rbStart;
            else
                riv = nRB * (nRB - rbLen + 1) + (nRB - 1 - rbStart);
            end
            freqBits = max(1, ceil(log2(double(nRB * (nRB + 1) / 2))));

            harq = sixgr.util.structGet(grant, "HARQ", struct());
            mcs = max(0, min(31, round(double(sixgr.util.structGet(grant, "MCSIndex", 0)))));
            ndi = double(logical(sixgr.util.structGet(harq, "NDI", 1)));
            rv = max(0, min(3, round(double(sixgr.util.structGet(harq, "RV", 0)))));
            harqId = max(0, min(15, round(double(sixgr.util.structGet(harq, "HarqID", 0)))));
            dai = max(0, min(3, round(double(sixgr.util.structGet(grant, "DAI", 1)))));
            k1 = max(0, min(7, round(double(sixgr.util.structGet(grant, "K1", 4)))));
            k2 = max(0, min(7, round(double(sixgr.util.structGet(grant, "K2", 1)))));
            tda = localTimeDomainAssignIndex(sixgr.util.structGet(grant, "SymbolAllocation", [0 14]));
            tda = max(0, min(15, round(double(tda))));

            if strcmpi(char(string(sixgr.util.structGet(grant, "Direction", obj.Direction))), "DL")
                fmt = "DCI_1_0";
                fmtBit = 1;
            else
                fmt = "DCI_0_0";
                fmtBit = 0;
            end

            bits = [ ...
                sixgr.l2.mac.SchedulerBase.uintToBits(fmtBit, 1); ...
                sixgr.l2.mac.SchedulerBase.uintToBits(riv, freqBits); ...
                sixgr.l2.mac.SchedulerBase.uintToBits(tda, 4); ...
                sixgr.l2.mac.SchedulerBase.uintToBits(mcs, 5); ...
                sixgr.l2.mac.SchedulerBase.uintToBits(ndi, 1); ...
                sixgr.l2.mac.SchedulerBase.uintToBits(rv, 2); ...
                sixgr.l2.mac.SchedulerBase.uintToBits(harqId, 4); ...
                sixgr.l2.mac.SchedulerBase.uintToBits(dai, 2); ...
                sixgr.l2.mac.SchedulerBase.uintToBits(k1, 3); ...
                sixgr.l2.mac.SchedulerBase.uintToBits(k2, 3)];

            fmap = struct();
            fmap.FormatIndicator_bits = 1;
            fmap.FrequencyDomainResource_bits = freqBits;
            fmap.TimeDomainAssignment_bits = 4;
            fmap.MCS_bits = 5;
            fmap.NDI_bits = 1;
            fmap.RV_bits = 2;
            fmap.HARQProcess_bits = 4;
            fmap.DAI_bits = 2;
            fmap.K1_bits = 3;
            fmap.K2_bits = 3;

            dci.Format = fmt;
            dci.Bits = uint8(bits(:));
            dci.Hex = sixgr.l2.mac.SchedulerBase.bitsToHex(dci.Bits);
            dci.FieldMap = fmap;
            dci.RIV = double(riv);
            dci.RBStart = double(rbStart);
            dci.RBLength = double(rbLen);
        end

        function log(obj, level, msg, varargin)
            if isempty(obj.Logger)
                return;
            end
            try
                switch lower(level)
                    case 'info'
                        obj.Logger.info(msg, varargin{:});
                    case 'warn'
                        obj.Logger.warn(msg, varargin{:});
                    case 'error'
                        obj.Logger.error(msg, varargin{:});
                    otherwise
                        obj.Logger.debug(msg, varargin{:});
                end
            catch
                % ignore logger errors
            end
        end
    end

    methods(Static)
        function qm = modOrder(modStr)
            % Modulation order Qm from modulation string
            s = upper(char(string(modStr)));
            switch s
                case 'QPSK'
                    qm = 2;
                case '16QAM'
                    qm = 4;
                case '64QAM'
                    qm = 6;
                case '256QAM'
                    qm = 8;
                case '1024QAM'
                    qm = 10;
                case '4096QAM'
                    qm = 12;
                otherwise
                    qm = 2;
            end
        end

        function bits = uintToBits(val, width)
            width = max(1, round(double(width)));
            v = max(0, floor(double(val)));
            bits = zeros(width, 1, 'uint8');
            for i = 1:width
                sh = width - i;
                bits(i) = uint8(bitget(uint64(v), sh + 1));
            end
        end

        function hx = bitsToHex(bits)
            bits = uint8(bits(:) ~= 0);
            if isempty(bits)
                hx = "";
                return;
            end
            pad = mod(8 - mod(numel(bits), 8), 8);
            if pad > 0
                bits = [bits; zeros(pad,1,'uint8')];
            end
            nB = numel(bits) / 8;
            u8 = zeros(nB,1,'uint8');
            for b = 1:nB
                chunk = bits((b-1)*8 + (1:8));
                v = uint8(0);
                for k = 1:8
                    v = bitor(bitshift(v,1), uint8(chunk(k) ~= 0));
                end
                u8(b) = v;
            end
            hx = upper(reshape(dec2hex(u8,2).',1,[]));
        end
    end

    methods(Abstract)
        % schedule Run one-slot scheduling.
        %
        % Inputs:
        %   slot     : scalar slot index (caller-defined)
        %   ueStates : struct array of UE states (see header)
        %   budget   : struct with fields:
        %               PRBSet (0-based vector) or NPRB (scalar)
        %               SymbolAllocation [start nSym]
        %
        % Outputs:
        %   grants : struct array as described in header
        %   info   : optional debug struct
        [grants, info] = schedule(obj, slot, ueStates, budget);
    end
end

function idx = localTimeDomainAssignIndex(symAlloc)
sa = double(symAlloc(:).');
if numel(sa) < 2
    sa = [0 14];
end
s = max(0, min(13, round(sa(1))));
l = max(1, min(14, round(sa(2))));
idx = s*14 + (l-1);
end
