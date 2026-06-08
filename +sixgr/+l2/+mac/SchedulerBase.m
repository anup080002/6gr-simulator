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
        Alpha (1,1) double = 0.995   % PF averaging factor; default resolved from AvgWindowMs
        AvgWindowMs (1,1) double = 100
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
        UEStats = struct('RNTI',{},'AvgThroughput_bps',{},'LastServedSlot',{},'LastTBSBits',{}, ...
            'LastAck',{},'NumScheduledSlots',{},'NumUnscheduledSlots',{})
        TBSCache = []
        NRECache = []
        CacheScopeToken (1,:) char = ''
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
            alphaCfg = sixgr.util.structGet(cfg,"mac.scheduler.alpha",[]);
            alphaExplicit = ~isempty(alphaCfg);
            if alphaExplicit
                obj.Alpha = double(alphaCfg);
            end
            obj.AvgWindowMs = double(sixgr.util.structGet(cfg,"mac.scheduler.avgWindowMs",obj.AvgWindowMs));

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
                            alphaExplicit = true;
                        case 'avgwindowms'
                            obj.AvgWindowMs = double(val);
                            alphaExplicit = false;
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

            if ~alphaExplicit
                % PF implementations normally average over O(100ms), not a
                % handful of slots. alpha = exp(-Tslot/tau) per R1-062478
                % proportional-fair scheduler guidance.
                tauMs = max(1, double(obj.AvgWindowMs));
                obj.Alpha = exp(-double(obj.SlotDuration_s) * 1e3 / tauMs);
            end
            localWarnIfPFAlphaOutOfRange(obj.Alpha, obj.SlotDuration_s);

            % HARQ default (optional)
            try
                harqEnable = logical(sixgr.util.structGet(cfg,"mac.harq.enable",true));
                if harqEnable && isempty(obj.HARQ)
                    obj.HARQ = sixgr.l2.mac.HARQEntity(cfg,'Direction',obj.Direction,'Logger',obj.Logger);
                end
            catch
                % ignore
            end

            obj.CacheScopeToken = localSchedulerCacheScopeToken(cfg, obj.Direction, obj.Carrier, obj.SymbolsPerSlot);
            try
                obj.TBSCache = localSharedTBSCache();
            catch
                obj.TBSCache = [];
            end
            try
                obj.NRECache = localSharedNRECache();
            catch
                obj.NRECache = [];
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
            obj.UEStats = struct('RNTI',{},'AvgThroughput_bps',{},'LastServedSlot',{},'LastTBSBits',{}, ...
                'LastAck',{},'NumScheduledSlots',{},'NumUnscheduledSlots',{});
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
            %  - struct array with fields: RNTI, TBSBits, Ack (logical), and optional HarqID/HARQProcess
            %  - table with variables: RNTI, TBSBits, Ack, and optional HarqID/HARQProcess
            if isempty(rxFeedback)
                return;
            end
            if istable(rxFeedback)
                rntiList = rxFeedback.RNTI;
                tbsList  = rxFeedback.TBSBits;
                ackList  = rxFeedback.Ack;
                if ismember("HarqID", string(rxFeedback.Properties.VariableNames))
                    harqIdList = rxFeedback.HarqID;
                elseif ismember("HARQProcess", string(rxFeedback.Properties.VariableNames))
                    harqIdList = rxFeedback.HARQProcess;
                else
                    harqIdList = nan(height(rxFeedback), 1);
                end
            else
                rntiList = [rxFeedback.RNTI];
                tbsList  = [rxFeedback.TBSBits];
                ackList  = [rxFeedback.Ack];
                harqIdList = nan(numel(rntiList), 1);
                for ii = 1:numel(rntiList)
                    if isfield(rxFeedback(ii), "HarqID") && ~isempty(rxFeedback(ii).HarqID)
                        harqIdList(ii) = double(rxFeedback(ii).HarqID);
                    elseif isfield(rxFeedback(ii), "HARQProcess") && ~isempty(rxFeedback(ii).HARQProcess)
                        harqIdList(ii) = double(rxFeedback(ii).HARQProcess);
                    elseif isfield(rxFeedback(ii), "HARQ") && isstruct(rxFeedback(ii).HARQ)
                        harqIdList(ii) = double(sixgr.util.structGet(rxFeedback(ii).HARQ, "HarqID", NaN));
                    end
                end
            end

            for k = 1:numel(rntiList)
                rnti = double(rntiList(k));
                tbsBits = double(tbsList(k));
                ack = logical(ackList(k));
                obj.updateAvgThroughput(rnti, tbsBits, ack);
                if ~isempty(obj.HARQ)
                    harqId = double(harqIdList(k));
                    if isfinite(harqId)
                        obj.HARQ.onFeedback(rnti, harqId, ack);
                    end
                end
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
            obj.UEStats(i).LastAck = logical(ack);
            obj.UEStats(i).NumScheduledSlots = double(obj.UEStats(i).NumScheduledSlots) + 1;
        end

        function prewarmUEAverage(obj, ue, nActiveUE)
            if nargin < 3 || isempty(nActiveUE)
                nActiveUE = 1;
            end
            if ~isstruct(ue) || ~isfield(ue, "RNTI") || isempty(ue.RNTI)
                return;
            end
            idx = obj.ensureUE(double(ue.RNTI));
            if isfinite(double(obj.UEStats(idx).LastServedSlot))
                return;
            end
            cqi = double(sixgr.util.structGet(ue, "CQI", NaN));
            if ~(isscalar(cqi) && isfinite(cqi) && cqi > 0)
                return;
            end
            try
                [modStr, nLayers, targetCodeRate] = obj.selectAMC(ue);
                refPRB = max(1, floor(double(obj.NSizeGrid) / max(1, round(double(nActiveUE)))));
                [initTBS, ~] = obj.estimateTBS(modStr, nLayers, refPRB, [0 obj.SymbolsPerSlot], targetCodeRate, ...
                    "PlanningOnly", true);
                if isfinite(initTBS) && initTBS > 0
                    obj.UEStats(idx).AvgThroughput_bps = double(initTBS) / max(obj.SlotDuration_s, eps);
                end
            catch
                % Prewarm is only an initialization hint; scheduling remains
                % driven by runtime grants if a toolbox release cannot size it.
            end
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
                obj.UEStats(end).LastAck = false;
                obj.UEStats(end).NumScheduledSlots = 0;
                obj.UEStats(end).NumUnscheduledSlots = 0;
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

        function [modStr, nLayers, targetCodeRate, amc] = selectAMC(obj, ue)
            % Select modulation/layers/code rate using an explicit NR AMC path.
            dir = upper(obj.Direction);
            mcsTable = obj.resolveMCSTable();
            cqiTable = obj.resolveCQITable();
            cqiRaw = sixgr.l2.mac.SchedulerBase.sanitizeCQI( ...
                sixgr.util.structGet(ue, "CQI", NaN), NaN);

            if strcmp(dir,'DL')
                modStr = char(string(sixgr.util.structGet(obj.Cfg,"phy.pdsch.modulation","16QAM")));
                nLayers = double(sixgr.util.structGet(obj.Cfg,"phy.pdsch.nLayers",1));
                targetCodeRate = double(sixgr.util.structGet(obj.Cfg,"phy.pdsch.codeRate",0.5));
                cfgMCSIndex = double(sixgr.util.structGet(obj.Cfg,"phy.pdsch.mcsIndex", NaN));
                linkAdaptationPolicy = sixgr.util.structGet(obj.Cfg, "phy.linkAdaptation.dlPolicy", "");
            else
                modStr = char(string(sixgr.util.structGet(obj.Cfg,"phy.pusch.modulation","16QAM")));
                nLayers = double(sixgr.util.structGet(obj.Cfg,"phy.pusch.nLayers",1));
                targetCodeRate = double(sixgr.util.structGet(obj.Cfg,"phy.pusch.codeRate",0.5));
                cfgMCSIndex = double(sixgr.util.structGet(obj.Cfg,"phy.pusch.mcsIndex", NaN));
                linkAdaptationPolicy = sixgr.util.structGet(obj.Cfg, "phy.linkAdaptation.ulPolicy", "");
            end
            linkAdaptationMode = sixgr.util.structGet(obj.Cfg, "phy.linkAdaptation.mode", "fixed");
            fixedTokens = ["fixed","fixed_mcs","configured_fixed","disabled","off","none","false"];

            if isfield(ue,'Modulation') && ~isempty(ue.Modulation)
                modStr = char(string(ue.Modulation));
            end
            if isfield(ue,'NumLayers') && ~isempty(ue.NumLayers)
                nLayers = double(ue.NumLayers);
            elseif isfield(ue,'RI') && ~isempty(ue.RI)
                nLayers = max(1, min(8, double(ue.RI)));
            end
            if isfield(ue,'TargetCodeRate') && ~isempty(ue.TargetCodeRate)
                tcrOverride = double(ue.TargetCodeRate);
                if isfinite(tcrOverride) && tcrOverride > 0
                    targetCodeRate = tcrOverride;
                end
            end

            amc = struct( ...
                "Mode", "fixed_modulation", ...
                "MCSTable", char(mcsTable), ...
                "CQITable", char(cqiTable), ...
                "CQIUsed", double(cqiRaw), ...
                "MCSIndex", NaN, ...
                "MCSProfile", sixgr.link.resolveMCSProfile(mcsTable, -1));

            ueMCSIndex = double(sixgr.util.structGet(ue, "MCSIndex", NaN));
            ueMCSIndexAuthority = lower(strtrim(string(sixgr.util.structGet(ue, "MCSIndexAuthority", ""))));
            hasExplicitModulation = isfield(ue,'Modulation') && ~isempty(ue.Modulation) && ...
                strlength(string(ue.Modulation)) > 0;
            hasExplicitTargetCodeRate = isfield(ue,'TargetCodeRate') && ~isempty(ue.TargetCodeRate) && ...
                isfinite(double(ue.TargetCodeRate)) && double(ue.TargetCodeRate) > 0;
            hasExplicitFixedModulation = hasExplicitModulation || hasExplicitTargetCodeRate;
            useConfiguredCQIAMC = localUseConfiguredCQIAMC(linkAdaptationMode, linkAdaptationPolicy);
            useExplicitUEMCSOverride = isfinite(ueMCSIndex) && ueMCSIndex >= 0 && ...
                (ismember(ueMCSIndexAuthority, ["explicit_fixed_override","configured_fixed_default","configured_fixed_fallback","explicit","config","override","fixed"]) || ...
                ismember(lower(strtrim(string(linkAdaptationMode))), fixedTokens) || ...
                ismember(lower(strtrim(string(linkAdaptationPolicy))), fixedTokens));

            if useExplicitUEMCSOverride
                amc.Mode = "fixed_mcs";
                amc.MCSIndex = round(ueMCSIndex);
            elseif useConfiguredCQIAMC
                amc.Mode = "cqi_table";
                if ~(isfinite(double(cqiRaw)) && cqiRaw > 0)
                    cqiDecision = struct("Valid", false);
                    amc.MCSIndex = 0;
                    amc.MCSProfile = sixgr.link.resolveMCSProfile(mcsTable, 0);
                else
                    cqiDecision = sixgr.link.resolveMCSFromCQI(cqiRaw, mcsTable, cqiTable);
                end
                if isfield(cqiDecision, "Valid") && cqiDecision.Valid
                    amc.MCSIndex = double(cqiDecision.MCSIndex);
                    amc.MCSProfile = cqiDecision.MCSProfile;
                    modStr = char(string(cqiDecision.MCSProfile.Modulation));
                    targetCodeRate = double(cqiDecision.MCSProfile.TargetCodeRate);
                else
                    % In AMC mode, missing/invalid CQI must not silently
                    % promote the configured study MCS into a scheduler grant.
                    amc.MCSIndex = 0;
                    amc.MCSProfile = sixgr.link.resolveMCSProfile(mcsTable, 0);
                end
            elseif isfinite(cfgMCSIndex) && cfgMCSIndex >= 0
                amc.Mode = "fixed_mcs";
                amc.MCSIndex = round(cfgMCSIndex);
            elseif hasExplicitFixedModulation
                amc.Mode = "fixed_modulation";
            elseif isfinite(cqiRaw)
                amc.Mode = "cqi_table";
                if cqiRaw <= 0
                    cqiDecision = struct("Valid", false);
                    amc.MCSIndex = 0;
                    amc.MCSProfile = sixgr.link.resolveMCSProfile(mcsTable, 0);
                else
                    cqiDecision = sixgr.link.resolveMCSFromCQI(cqiRaw, mcsTable, cqiTable);
                end
                if isfield(cqiDecision, "Valid") && cqiDecision.Valid
                    amc.MCSIndex = double(cqiDecision.MCSIndex);
                    amc.MCSProfile = cqiDecision.MCSProfile;
                    modStr = char(string(cqiDecision.MCSProfile.Modulation));
                    targetCodeRate = double(cqiDecision.MCSProfile.TargetCodeRate);
                end
            end

            if amc.Mode == "cqi_table" && isstruct(amc.MCSProfile) && ...
                    isfield(amc.MCSProfile, "Valid") && logical(amc.MCSProfile.Valid)
                % Keep the modulation/code-rate export aligned with the
                % resolved CQI profile even when the CQI path legitimately
                % falls back to MCS 0 before any richer feedback arrives.
                modStr = char(string(amc.MCSProfile.Modulation));
                targetCodeRate = double(amc.MCSProfile.TargetCodeRate);
                if ~isfinite(amc.MCSIndex) && isfield(amc.MCSProfile, "MCSIndex")
                    amc.MCSIndex = double(amc.MCSProfile.MCSIndex);
                end
            end

            if amc.Mode == "fixed_mcs" && isfinite(amc.MCSIndex) && amc.MCSIndex >= 0
                prof = sixgr.link.resolveMCSProfile(mcsTable, amc.MCSIndex);
                if prof.Valid
                    amc.MCSProfile = prof;
                    modStr = char(string(prof.Modulation));
                    targetCodeRate = double(prof.TargetCodeRate);
                end
            elseif ~isfinite(amc.MCSIndex)
                amc.MCSIndex = sixgr.l2.mac.SchedulerBase.approxMCSIndex(modStr, targetCodeRate, cqiRaw, mcsTable);
                amc.MCSProfile = sixgr.link.resolveMCSProfile(mcsTable, amc.MCSIndex);
            end

            if localUseWaveformULSingleLayerSafety(obj.Cfg) && strcmp(dir, 'UL')
                % Preserve the validated waveform-fading UL single-layer safety
                % behavior without coupling it to CQI or AMC table selection.
                nLayers = 1;
            end

            nLayers = max(1, min(8, round(nLayers)));
            targetCodeRate = min(max(targetCodeRate, 0.05), 0.95);
            amc.Modulation = char(string(modStr));
            amc.TargetCodeRate = double(targetCodeRate);
            amc.NumLayers = double(nLayers);
        end

        function tableName = resolveMCSTable(obj)
            if strcmpi(obj.Direction, 'UL')
                token = sixgr.util.structGet(obj.Cfg, "phy.pusch.mcsTable", ...
                    localDefaultMCSTable(sixgr.util.structGet(obj.Cfg, "phy.pusch.modulation", "16QAM")));
            else
                token = sixgr.util.structGet(obj.Cfg, "phy.pdsch.mcsTable", ...
                    localDefaultMCSTable(sixgr.util.structGet(obj.Cfg, "phy.pdsch.modulation", "16QAM")));
            end
            tableName = char(lower(string(token)));
        end

        function tableName = resolveCQITable(obj)
            if strcmpi(obj.Direction, 'UL')
                token = sixgr.util.structGet(obj.Cfg, "phy.pusch.cqiTable", ...
                    sixgr.util.structGet(obj.Cfg, "phy.csi.ulCQITable", ...
                    sixgr.util.structGet(obj.Cfg, "phy.csi.cqiTable", "table1")));
            else
                token = sixgr.util.structGet(obj.Cfg, "phy.pdsch.cqiTable", ...
                    sixgr.util.structGet(obj.Cfg, "phy.csi.dlCQITable", ...
                    sixgr.util.structGet(obj.Cfg, "phy.csi.cqiTable", "table1")));
            end
            tableName = char(sixgr.link.resolveCQIProfile(token, 1).Table);
        end

        function [tbsBits, tbsBytes, nrePerPRB, info] = estimateTBS(obj, modStr, nLayers, nPRB, symAlloc, targetCodeRate, varargin)
            % Estimate TB size using nrTBS. Uses NREPerPRB from nrPDSCHInfo/nrPUSCHInfo.
            if nargin < 5 || isempty(symAlloc)
                symAlloc = [0 obj.SymbolsPerSlot];
            end
            opt = struct("PlanningOnly", false, "ForceExact", false);
            if ~isempty(varargin)
                if mod(numel(varargin), 2) ~= 0
                    error("sixgr:SchedulerBase:EstimateTBSBadNV", ...
                        "estimateTBS name-value inputs must come in pairs.");
                end
                for nvIdx = 1:2:numel(varargin)
                    key = lower(string(varargin{nvIdx}));
                    value = varargin{nvIdx + 1};
                    switch key
                        case "planningonly"
                            opt.PlanningOnly = logical(value);
                        case "forceexact"
                            opt.ForceExact = logical(value);
                        otherwise
                            error("sixgr:SchedulerBase:EstimateTBSUnknownNV", ...
                                "Unknown estimateTBS option '%s'.", char(key));
                    end
                end
            end
            nSym = double(symAlloc(2));
            xOverhead = localResolveTBSXOverhead(obj.Direction, obj.Cfg);
            info = struct("UsedFastNREApprox", false, "StrictTBSMode", false, ...
                "TBSMode", "approximate", "ViennaEquivalent", false, ...
                "PlanningOnly", logical(opt.PlanningOnly), ...
                "ForceExact", logical(opt.ForceExact), ...
                "XOverhead", double(xOverhead));

            % Memoize repeated TBS queries (same AMC + budget) since these are
            % called very frequently in per-slot scheduling loops.
            tbsCache = [];
            if isa(obj.TBSCache, 'containers.Map')
                tbsCache = true;
            end
            key = "";
            if ~isempty(tbsCache)
                symStart = round(double(symAlloc(1)));
                key = localScopedCacheKey(obj.CacheScopeToken, sprintf("%s|%s|%d|%d|%d|%d|%.4f", ...
                    upper(char(obj.Direction)), upper(char(modStr)), ...
                    round(double(nLayers)), round(double(nPRB)), symStart, round(double(nSym)), ...
                    round(double(targetCodeRate) * 1e4) / 1e4));
                [hit, v] = sixgr.l2.mac.schedulerCache('get', 'TBS', key);
                if hit
                    tbsBits = double(v(1));
                    tbsBytes = double(v(2));
                    nrePerPRB = double(v(3));
                    return;
                end
            end

            useFastNRE = logical(sixgr.util.structGet(obj.Cfg, "mac.scheduler.fastNREApprox", true));
            strictMode = logical(sixgr.util.structGet(obj.Cfg, "run.strictMode", false));
            tbsMode = lower(string(sixgr.util.structGet(obj.Cfg, "mac.scheduler.tbsMode", "approximate")));
            viennaEquivalent = logical(sixgr.util.structGet(obj.Cfg, "mac.scheduler.viennaEquivalent", false));
            allowApproxPlanningInStrict = logical(sixgr.util.structGet(obj.Cfg, ...
                "mac.scheduler.allowApproximatePlanningInStrictMode", false));
            info.StrictTBSMode = strictMode;
            info.ViennaEquivalent = viennaEquivalent;
            info.TBSMode = char(tbsMode);
            planningApproxAllowed = strictMode && logical(opt.PlanningOnly) && ...
                allowApproxPlanningInStrict && tbsMode == "approximate" && ~viennaEquivalent;
            if logical(opt.ForceExact) || tbsMode == "faithful" || tbsMode == "strict" || ...
                    viennaEquivalent || (strictMode && ~planningApproxAllowed)
                useFastNRE = false;
                info.TBSMode = "faithful";
            end
            nrePerPRB = localFastNREPerPRB(obj.Direction, obj.Cfg, nSym);
            if ~useFastNRE
                nreCache = [];
                if isa(obj.NRECache, 'containers.Map')
                    nreCache = true;
                end
                nreKey = localScopedCacheKey(obj.CacheScopeToken, ...
                    localNRECacheKey(obj.Direction, nLayers, nPRB, symAlloc));
                nreCached = false;
                if ~isempty(nreCache)
                    [nreCached, cachedValue] = sixgr.l2.mac.schedulerCache('get', 'NRE', nreKey);
                    if nreCached
                        nrePerPRB = double(cachedValue);
                    end
                end
                if ~nreCached
                    try
                        carrier = obj.Carrier;
                        if isempty(carrier) || ~isprop(carrier, "NSizeGrid") || double(carrier.NSizeGrid) < max(double(nPRB), 1)
                            [carrier, ~] = sixgr.phy.grid.makeCarrier(obj.Cfg, ...
                                "NSizeGrid", max(max(nPRB,1), double(sixgr.util.structGet(obj.Cfg, "phy.carrier.NSizeGrid", nPRB))));
                        end
                        nrePerPRB = localComputeExactNREPerPRB(obj.Direction, carrier, obj.Cfg, nPRB, symAlloc, modStr, nLayers);
                        if ~isempty(nreCache) && isfinite(double(nrePerPRB)) && double(nrePerPRB) > 0
                            sixgr.l2.mac.schedulerCache('set', 'NRE', nreKey, double(nrePerPRB));
                        end
                    catch
                        % keep fallback
                    end
                end
            end

            qm = sixgr.l2.mac.SchedulerBase.modOrder(modStr);
            if useFastNRE
                info.UsedFastNREApprox = true;
                if obj.UseMexTBS && exist("sixgr_l2_mac_estimateTBSApprox_entry_mex", "file") == 3
                    if abs(double(nrePerPRB) - 12*double(nSym)) <= 1e-9 && double(xOverhead) == 0
                        [tbsBits, tbsBytes, nrePerPRB] = sixgr_l2_mac_estimateTBSApprox_entry_mex( ...
                            double(qm), double(nLayers), double(nPRB), double(nSym), double(targetCodeRate));
                    else
                        eff = qm * targetCodeRate;
                        effectiveNRE = max(1, double(nrePerPRB) - double(xOverhead));
                        tbsBits = floor(double(nPRB) * effectiveNRE * eff);
                        tbsBits = 8 * floor(tbsBits / 8);
                        tbsBytes = floor(tbsBits / 8);
                    end
                else
                    eff = qm * targetCodeRate;
                    effectiveNRE = max(1, double(nrePerPRB) - double(xOverhead));
                    tbsBits = floor(double(nPRB) * effectiveNRE * eff);
                    tbsBits = 8 * floor(tbsBits / 8);
                    tbsBytes = floor(tbsBits / 8);
                end
            else
                if ~(isfinite(double(nrePerPRB)) && double(nrePerPRB) > 0)
                    tbsBits = 0;
                    tbsBytes = 0;
                    if ~isempty(tbsCache) && strlength(string(key)) > 0
                        sixgr.l2.mac.schedulerCache('set', 'TBS', char(key), ...
                            [double(tbsBits), double(tbsBytes), double(nrePerPRB)]);
                    end
                    return;
                end
                try
                    tbsBits = double(nrTBS(char(modStr), double(nLayers), double(nPRB), double(nrePerPRB), double(targetCodeRate), double(xOverhead)));
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

            if ~isempty(tbsCache) && strlength(string(key)) > 0
                sixgr.l2.mac.schedulerCache('set', 'TBS', char(key), ...
                    [double(tbsBits), double(tbsBytes), double(nrePerPRB)]);
            end
        end

        function plan = buildNewDataGrantPlan(obj, ue, prbSet, symAlloc, queueBytes, varargin)
            opt = struct("PlanningOnly", false);
            if ~isempty(varargin)
                if mod(numel(varargin), 2) ~= 0
                    error("sixgr:SchedulerBase:BuildGrantPlanBadNV", ...
                        "buildNewDataGrantPlan name-value inputs must come in pairs.");
                end
                for nvIdx = 1:2:numel(varargin)
                    key = lower(string(varargin{nvIdx}));
                    value = varargin{nvIdx + 1};
                    switch key
                        case "planningonly"
                            opt.PlanningOnly = logical(value);
                        otherwise
                            error("sixgr:SchedulerBase:BuildGrantPlanUnknownNV", ...
                                "Unknown buildNewDataGrantPlan option '%s'.", char(key));
                    end
                end
            end
            queueBytes = max(0, floor(double(queueBytes)));
            [modStr, nLayers, targetCodeRate, amc] = obj.selectAMC(ue);
            [rawBits, rawBytes, rawNRE] = obj.estimateTBS(modStr, nLayers, numel(prbSet), symAlloc, targetCodeRate, ...
                "PlanningOnly", logical(opt.PlanningOnly));

            plan = struct( ...
                "Valid", false, ...
                "PRBSet", double(prbSet(:).'), ...
                "Modulation", char(string(modStr)), ...
                "NumLayers", double(nLayers), ...
                "TargetCodeRate", double(targetCodeRate), ...
                "MCSIndex", double(amc.MCSIndex), ...
                "MCSTable", char(string(amc.MCSTable)), ...
                "CQITable", char(string(amc.CQITable)), ...
                "AMCMode", char(string(amc.Mode)), ...
                "NREPerPRB", double(rawNRE), ...
                "TBSBits", double(rawBits), ...
                "TBSBytes", double(rawBytes), ...
                "RawEstimatedTBSBits", double(rawBits), ...
                "RawEstimatedTBSBytes", double(rawBytes), ...
                "QueueLimited", false);

            if queueBytes <= 0 || rawBits <= 0 || rawBytes <= 0 || isempty(prbSet)
                return;
            end
            if rawBytes <= queueBytes
                plan.Valid = true;
                return;
            end

            if logical(opt.PlanningOnly)
                % PF probe passes only need an honest bounded estimate for
                % ranking. Keep the final selected-grant path exact, but do
                % not burn an exhaustive queue-limited search during
                % planning-only metric evaluation.
                plan.Valid = true;
                plan.TBSBytes = double(queueBytes);
                plan.TBSBits = double(8 * floor(double(queueBytes)));
                plan.QueueLimited = true;
                return;
            end

            best = localFindQueueLimitedPlan(obj, amc, prbSet, symAlloc, queueBytes, ...
                "PlanningOnly", logical(opt.PlanningOnly));
            if ~best.Valid
                return;
            end

            plan.Valid = true;
            plan.PRBSet = double(best.PRBSet);
            plan.Modulation = char(string(best.Modulation));
            plan.NumLayers = double(best.NumLayers);
            plan.TargetCodeRate = double(best.TargetCodeRate);
            plan.MCSIndex = double(best.MCSIndex);
            plan.NREPerPRB = double(best.NREPerPRB);
            plan.TBSBits = double(best.TBSBits);
            plan.TBSBytes = double(best.TBSBytes);
            plan.QueueLimited = true;
        end

        function metric = pfMetric(obj, ue, tbsBits)
            % PF metric = instRate / avgRate.
            i = obj.ensureUE(double(ue.RNTI));
            avg = double(obj.UEStats(i).AvgThroughput_bps);
            inst = double(tbsBits) / max(obj.SlotDuration_s, eps);
            metric = inst / max(avg, 1);
        end

        function dci = buildDCIBitfield(obj, grant)
            % buildDCIBitfield Build NR-style DCI intent fields for a grant.
            dci = struct("Format", "", "Bits", uint8([]), "Hex", "", ...
                "FieldMap", struct(), "FieldValues", struct(), ...
                "RIV", 0, "RBStart", 0, "RBLength", 0, ...
                "SLIV", NaN, "TimeDomainAssignmentIndex", NaN, ...
                "StandardProfile", "ts38212_semantic_field_layout", ...
                "BitExactPDCCHPayload", false);
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
            sliv = localTimeDomainAssignIndex(sixgr.util.structGet(grant, "SymbolAllocation", [0 14]), obj.SymbolsPerSlot);
            tdaIndex = max(0, min(15, round(double(sixgr.util.structGet(grant, "TimeDomainResourceAssignmentIndex", ...
                sixgr.util.structGet(grant, "TDRAIndex", 0))))));

            direction = upper(string(sixgr.util.structGet(grant, "Direction", obj.Direction)));
            fmt = localResolveDCIFormat(obj.Cfg, grant, direction);
            fmtBit = double(direction == "DL");

            bits = uint8([]);
            fmap = struct();
            fvals = struct();
            [bits, fmap, fvals] = localAppendDCIField(bits, fmap, fvals, "FormatIndicator", fmtBit, 1);
            [bits, fmap, fvals] = localAppendDCIField(bits, fmap, fvals, "FrequencyDomainResourceAssignment_RIV", riv, freqBits);
            [bits, fmap, fvals] = localAppendDCIField(bits, fmap, fvals, "TimeDomainResourceAssignmentIndex", tdaIndex, 4);
            [bits, fmap, fvals] = localAppendDCIField(bits, fmap, fvals, "TimeDomainResourceAssignmentSLIV", sliv, 8);
            [bits, fmap, fvals] = localAppendDCIField(bits, fmap, fvals, "MCS", mcs, 5);
            [bits, fmap, fvals] = localAppendDCIField(bits, fmap, fvals, "NDI", ndi, 1);
            [bits, fmap, fvals] = localAppendDCIField(bits, fmap, fvals, "RV", rv, 2);
            [bits, fmap, fvals] = localAppendDCIField(bits, fmap, fvals, "HARQProcessNumber", harqId, 4);

            if fmt == "DCI_1_1"
                tci = localClampDCIValue(sixgr.util.structGet(grant, "TCIState", ...
                    sixgr.util.structGet(obj.Cfg, "phy.pdsch.TCIState", 0)), 3);
                srsReq = localClampDCIValue(sixgr.util.structGet(grant, "SRSRequest", 0), 2);
                csiReq = localClampDCIValue(sixgr.util.structGet(grant, "CSIRequest", ...
                    double(isfinite(double(sixgr.util.structGet(grant, "CRI", NaN))))), 2);
                antennaPorts = localDLAntennaPortField(grant);
                [bits, fmap, fvals] = localAppendDCIField(bits, fmap, fvals, "DAI", dai, 2);
                [bits, fmap, fvals] = localAppendDCIField(bits, fmap, fvals, "PDSCHToHARQFeedbackTimingIndicator_K1", k1, 3);
                [bits, fmap, fvals] = localAppendDCIField(bits, fmap, fvals, "VRBToPRBMapping", sixgr.util.structGet(grant, "VRBToPRBMapping", 0), 1);
                [bits, fmap, fvals] = localAppendDCIField(bits, fmap, fvals, "PRBBundlingSizeIndicator", sixgr.util.structGet(grant, "PRBBundlingSizeIndicator", 0), 1);
                [bits, fmap, fvals] = localAppendDCIField(bits, fmap, fvals, "RateMatchingIndicator", sixgr.util.structGet(grant, "RateMatchingIndicator", 0), 2);
                [bits, fmap, fvals] = localAppendDCIField(bits, fmap, fvals, "ZP_CSIRS_Trigger", sixgr.util.structGet(grant, "ZPCSIRSTrigger", 0), 2);
                [bits, fmap, fvals] = localAppendDCIField(bits, fmap, fvals, "AntennaPorts", antennaPorts, 5);
                [bits, fmap, fvals] = localAppendDCIField(bits, fmap, fvals, "TransmissionConfigurationIndication", tci, 3);
                [bits, fmap, fvals] = localAppendDCIField(bits, fmap, fvals, "SRSRequest", srsReq, 2);
                [bits, fmap, fvals] = localAppendDCIField(bits, fmap, fvals, "CSIRequest", csiReq, 2);
                [bits, fmap, fvals] = localAppendDCIField(bits, fmap, fvals, "CBGTransmissionInformation", sixgr.util.structGet(grant, "CBGTI", 0), 8);
                [bits, fmap, fvals] = localAppendDCIField(bits, fmap, fvals, "CBGFlushingInformation", sixgr.util.structGet(grant, "CBGFI", 0), 1);
                [bits, fmap, fvals] = localAppendDCIField(bits, fmap, fvals, "DMRSSequenceInitialization", sixgr.util.structGet(grant, "DMRSSequenceInitialization", 0), 1);
            elseif fmt == "DCI_0_1"
                tpmi = localClampDCIValue(sixgr.util.structGet(grant, "TPMI", ...
                    sixgr.util.structGet(grant, "PMI", NaN)), 6);
                numLayers = localClampDCIValue(sixgr.util.structGet(grant, "NumLayers", 1), 2) - 1;
                sri = localClampDCIValue(sixgr.util.structGet(grant, "SRSResourceIndicator", ...
                    sixgr.util.structGet(grant, "SRSResourceID", 0)), 4);
                [bits, fmap, fvals] = localAppendDCIField(bits, fmap, fvals, "FrequencyHoppingFlag", sixgr.util.structGet(grant, "FrequencyHoppingFlag", 0), 1);
                [bits, fmap, fvals] = localAppendDCIField(bits, fmap, fvals, "FirstDAI", dai, 2);
                [bits, fmap, fvals] = localAppendDCIField(bits, fmap, fvals, "TPCCommandForPUSCH", sixgr.util.structGet(grant, "TPCCommandForPUSCH", 1), 2);
                [bits, fmap, fvals] = localAppendDCIField(bits, fmap, fvals, "SRSResourceIndicator", sri, 4);
                [bits, fmap, fvals] = localAppendDCIField(bits, fmap, fvals, "PrecodingInformationAndNumberOfLayers_TPMI", tpmi, 6);
                [bits, fmap, fvals] = localAppendDCIField(bits, fmap, fvals, "PrecodingInformationAndNumberOfLayers_RankMinus1", numLayers, 2);
                [bits, fmap, fvals] = localAppendDCIField(bits, fmap, fvals, "AntennaPorts", localULAntennaPortField(grant), 5);
                [bits, fmap, fvals] = localAppendDCIField(bits, fmap, fvals, "SRSRequest", sixgr.util.structGet(grant, "SRSRequest", 0), 2);
                [bits, fmap, fvals] = localAppendDCIField(bits, fmap, fvals, "CSIRequest", sixgr.util.structGet(grant, "CSIRequest", 0), 2);
                [bits, fmap, fvals] = localAppendDCIField(bits, fmap, fvals, "K2", k2, 3);
            else
                [bits, fmap, fvals] = localAppendDCIField(bits, fmap, fvals, "DAI", dai, 2);
                [bits, fmap, fvals] = localAppendDCIField(bits, fmap, fvals, "K1", k1, 3);
                [bits, fmap, fvals] = localAppendDCIField(bits, fmap, fvals, "K2", k2, 3);
            end

            dci.Format = fmt;
            dci.Bits = uint8(bits(:));
            dci.Hex = sixgr.l2.mac.SchedulerBase.bitsToHex(dci.Bits);
            dci.FieldMap = fmap;
            dci.FieldValues = fvals;
            dci.RIV = double(riv);
            dci.RBStart = double(rbStart);
            dci.RBLength = double(rbLen);
            dci.SLIV = double(sliv);
            dci.TimeDomainAssignmentIndex = double(tdaIndex);
            dci.BitLength = double(numel(dci.Bits));
            dci.NRFieldLayoutSource = "3gpp_ts_38_212_dci_field_semantics";
            dci.NRResourceAssignmentSource = "3gpp_ts_38_214_riv_sliv";
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
        function cqi = sanitizeCQI(cqiRaw, defaultValue)
            if nargin < 2
                defaultValue = NaN;
            end
            cqi = double(defaultValue);
            raw = double(cqiRaw);
            if isempty(raw)
                return;
            end
            raw = raw(1);
            if ~(isscalar(raw) && isfinite(raw))
                return;
            end
            cqi = max(0, min(15, round(raw)));
        end

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

        function mcs = approxMCSIndex(modStr, targetCodeRate, cqiFallback, mcsTable)
            if nargin < 3
                cqiFallback = NaN;
            end
            if nargin < 4 || isempty(mcsTable)
                mcsTable = localDefaultMCSTable(modStr);
            end

            s = upper(char(string(modStr)));
            tcr = double(targetCodeRate);
            if isfinite(tcr) && tcr > 0 && strlength(string(s)) > 0
                mcs = localMatchMCSIndex(mcsTable, s, tcr);
            else
                cqiFallback = sixgr.l2.mac.SchedulerBase.sanitizeCQI(cqiFallback, NaN);
            end
            if isfinite(double(cqiFallback))
                if double(cqiFallback) <= 0
                    mcs = 0;
                    mcs = max(0, min(31, round(double(mcs))));
                    return;
                end
                cqiTable = localDefaultCQITable(mcsTable);
                amc = sixgr.link.resolveMCSFromCQI(double(cqiFallback), mcsTable, cqiTable);
                if amc.Valid
                    mcs = double(amc.MCSIndex);
                else
                    mcs = 0;
                end
            else
                mcs = 0;
            end

            mcs = max(0, min(31, round(double(mcs))));
        end

        function profile = resolveMCSProfileForGrant(obj, grant, cqiFallback)
            if nargin < 3
                cqiFallback = NaN;
            end
            modStr = char(string(sixgr.util.structGet(grant, "Modulation", "QPSK")));
            defaultMCSTable = localDefaultMCSTable(modStr);
            mcsTable = sixgr.util.structGet(grant, "MCSTable", defaultMCSTable);
            mcsIndex = double(sixgr.util.structGet(grant, "MCSIndex", NaN));
            if isfinite(mcsIndex) && mcsIndex >= 0
                profile = sixgr.link.resolveMCSProfile(mcsTable, mcsIndex);
                if profile.Valid
                    return;
                end
            end

            tcr = double(sixgr.util.structGet(grant, "TargetCodeRate", 0.5));
            mcsIndex = sixgr.l2.mac.SchedulerBase.approxMCSIndex(modStr, tcr, cqiFallback, mcsTable);
            profile = sixgr.link.resolveMCSProfile(mcsTable, mcsIndex);
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

function localWarnIfPFAlphaOutOfRange(alpha, slotDuration_s)
alpha = double(alpha);
slotDuration_s = double(slotDuration_s);
if ~(isscalar(alpha) && isfinite(alpha) && alpha > 0 && alpha < 1)
    warning('sixgr:scheduler:AlphaOutOfRange', ...
        'PF alpha=%.4g is outside the stable EWMA interval (0,1).', alpha);
    return;
end
tauMs = -slotDuration_s * 1e3 / log(alpha);
if alpha < 0.9 || alpha > 0.9999
    warning('sixgr:scheduler:AlphaOutOfRange', ...
        'PF alpha=%.4f corresponds to averaging window tau=%.1f ms; expected approximately 50-500 ms.', ...
        alpha, tauMs);
end
end

function idx = localTimeDomainAssignIndex(symAlloc, symbolsPerSlot)
% TS 38.214 SLIV encoding for a start symbol S and length L.
if nargin < 2 || isempty(symbolsPerSlot)
    symbolsPerSlot = 14;
end
N = max(1, min(14, round(double(symbolsPerSlot))));
sa = double(symAlloc(:).');
if numel(sa) < 2
    sa = [0 N];
end
s = max(0, min(N - 1, round(sa(1))));
l = max(1, min(N - s, round(sa(2))));
if (l - 1) <= floor(N / 2)
    idx = N * (l - 1) + s;
else
    idx = N * (N - l + 1) + (N - 1 - s);
end
idx = max(0, round(double(idx)));
end

function nrePerPRB = localFastNREPerPRB(direction, cfg, nSym)
% TS 38.214 Table 5.1.3.2-1: subtract DMRS RE even in scheduler fast mode.
nSym = max(1, round(double(nSym)));
dmrsSym = localResolveDMRSSymbolCount(direction, cfg, nSym);
dmrsREPerPRB = localResolveDMRSREPerPRB(direction, cfg);
nrePerPRB = max(1, 12 * nSym - dmrsREPerPRB * dmrsSym);
end

function nSym = localResolveDMRSSymbolCount(direction, cfg, allocSymbols)
if upper(string(direction)) == "UL"
    basePath = "phy.pusch";
else
    basePath = "phy.pdsch";
end
addPos = localFirstFiniteScalar( ...
    sixgr.util.structGet(cfg, basePath + ".dmrs.additionalPositions", []), ...
    sixgr.util.structGet(cfg, basePath + ".DMRSAdditionalPosition", []), ...
    sixgr.util.structGet(cfg, "phy.dmrs.additionalPositions", []), ...
    sixgr.util.structGet(cfg, "phy.dmrs.DMRSAdditionalPosition", []), ...
    0);
maxFrontLoaded = localFirstFiniteScalar( ...
    sixgr.util.structGet(cfg, basePath + ".dmrs.maxLength", []), ...
    sixgr.util.structGet(cfg, basePath + ".DMRSLength", []), ...
    sixgr.util.structGet(cfg, "phy.dmrs.maxLength", []), ...
    sixgr.util.structGet(cfg, "phy.dmrs.DMRSLength", []), ...
    1);
nSym = max(1, min(round(double(allocSymbols)), round(double(maxFrontLoaded)) + max(0, round(double(addPos)))));
end

function rePerPRB = localResolveDMRSREPerPRB(direction, cfg)
if upper(string(direction)) == "UL"
    basePath = "phy.pusch";
else
    basePath = "phy.pdsch";
end
dmrsType = localFirstFiniteScalar( ...
    sixgr.util.structGet(cfg, basePath + ".dmrs.configurationType", []), ...
    sixgr.util.structGet(cfg, basePath + ".DMRSConfigurationType", []), ...
    sixgr.util.structGet(cfg, "phy.dmrs.configurationType", []), ...
    sixgr.util.structGet(cfg, "phy.dmrs.DMRSConfigurationType", []), ...
    1);
if round(double(dmrsType)) == 2
    rePerPRB = 8;
else
    rePerPRB = 6;
end
end

function xOverhead = localResolveTBSXOverhead(direction, cfg)
if upper(string(direction)) == "UL"
    xOverhead = localFirstFiniteScalar( ...
        sixgr.util.structGet(cfg, "phy.pusch.xOverhead", []), ...
        sixgr.util.structGet(cfg, "phy.pusch.XOverhead", []), ...
        0);
    modToken = upper(strtrim(string(sixgr.util.structGet(cfg, "phy.pusch.modulation", ""))));
    tpEnabled = logical(sixgr.util.structGet(cfg, "phy.pusch.transformPrecoding", false)) || ...
        strcmp(modToken, "PI/2-BPSK") || strcmp(modToken, "PI2-BPSK");
    if tpEnabled
        xOverhead = max(double(xOverhead), 6);
    end
else
    xOverhead = localFirstFiniteScalar( ...
        sixgr.util.structGet(cfg, "phy.pdsch.xOverhead", []), ...
        sixgr.util.structGet(cfg, "phy.pdsch.XOverhead", []), ...
        0);
end
xOverhead = max(0, round(double(xOverhead)));
end

function value = localFirstFiniteScalar(varargin)
value = NaN;
for i = 1:numel(varargin)
    raw = varargin{i};
    if isempty(raw)
        continue;
    end
    try
        v = double(raw);
    catch
        continue;
    end
    v = v(isfinite(v));
    if ~isempty(v)
        value = v(1);
        return;
    end
end
end

function [bits, fmap, fvals] = localAppendDCIField(bits, fmap, fvals, name, value, width)
width = max(1, round(double(width)));
value = localClampDCIValue(value, width);
bits = [bits; sixgr.l2.mac.SchedulerBase.uintToBits(value, width)]; %#ok<AGROW>
fieldName = char(matlab.lang.makeValidName(char(string(name))));
fmap.([fieldName '_bits']) = double(width);
fvals.(fieldName) = double(value);
end

function value = localClampDCIValue(value, width)
raw = double(value);
if isempty(raw) || ~(isscalar(raw) && isfinite(raw))
    raw = 0;
end
maxValue = 2 ^ max(1, round(double(width))) - 1;
value = max(0, min(maxValue, round(raw)));
end

function fmt = localResolveDCIFormat(cfg, grant, direction)
direction = upper(string(direction));
if direction == "UL"
    if localNeedsAdvancedULDci(cfg, grant)
        fmt = "DCI_0_1";
    else
        fmt = "DCI_0_0";
    end
else
    if localNeedsAdvancedDLDci(cfg, grant)
        fmt = "DCI_1_1";
    else
        fmt = "DCI_1_0";
    end
end
end

function tf = localNeedsAdvancedDLDci(cfg, grant)
numLayers = double(sixgr.util.structGet(grant, "NumLayers", sixgr.util.structGet(cfg, "phy.pdsch.nLayers", 1)));
pmi = double(sixgr.util.structGet(grant, "PMI", NaN));
cri = double(sixgr.util.structGet(grant, "CRI", NaN));
tciConfigured = isfinite(double(sixgr.util.structGet(grant, "TCIState", ...
    sixgr.util.structGet(cfg, "phy.pdsch.TCIState", NaN))));
forceDCI11 = logical(sixgr.util.structGet(cfg, "phy.pdcch.forceDCI11", ...
    sixgr.util.structGet(cfg, "mac.scheduler.forceDCI11", false)));
tf = (isfinite(numLayers) && numLayers > 1) || isfinite(pmi) || isfinite(cri) || ...
    tciConfigured || forceDCI11;
end

function tf = localNeedsAdvancedULDci(cfg, grant)
numLayers = double(sixgr.util.structGet(grant, "NumLayers", sixgr.util.structGet(cfg, "phy.pusch.nLayers", 1)));
tpmi = double(sixgr.util.structGet(grant, "TPMI", sixgr.util.structGet(grant, "PMI", NaN)));
sri = double(sixgr.util.structGet(grant, "SRSResourceIndicator", sixgr.util.structGet(grant, "SRSResourceID", NaN)));
forceDCI01 = logical(sixgr.util.structGet(cfg, "phy.pdcch.forceDCI01", ...
    sixgr.util.structGet(cfg, "mac.scheduler.forceDCI01", false)));
tf = (isfinite(numLayers) && numLayers > 1) || isfinite(tpmi) || isfinite(sri) || forceDCI01;
end

function field = localDLAntennaPortField(grant)
numLayers = double(sixgr.util.structGet(grant, "NumLayers", 1));
if ~(isscalar(numLayers) && isfinite(numLayers) && numLayers >= 1)
    numLayers = 1;
end
field = max(0, min(31, round(numLayers) - 1));
end

function field = localULAntennaPortField(grant)
numLayers = double(sixgr.util.structGet(grant, "NumLayers", 1));
if ~(isscalar(numLayers) && isfinite(numLayers) && numLayers >= 1)
    numLayers = 1;
end
field = max(0, min(31, round(numLayers) - 1));
end

function tf = localUseWaveformULSingleLayerSafety(cfg)
backend = lower(char(string(sixgr.util.structGet(cfg, "system.phyBackend", ""))));
awgnOnly = logical(sixgr.util.structGet(cfg, "channel.awgnOnly", false));
channelModel = upper(char(string(sixgr.util.structGet(cfg, "channel.model", "AWGN"))));
fadingModel = upper(char(string(sixgr.util.structGet(cfg, "channel.fading.model", ""))));
delayProfile = upper(char(string(sixgr.util.structGet(cfg, "channel.delayProfile", ""))));
tdlProfile = upper(char(string(sixgr.util.structGet(cfg, "channel.tdlProfile", ""))));
cdlProfile = upper(char(string(sixgr.util.structGet(cfg, "channel.cdlProfile", ""))));
fadingEnabled = logical(sixgr.util.structGet(cfg, "channel.fading.enable", false));

isConcreteFading = startsWith(channelModel, "TDL") || startsWith(channelModel, "CDL") || ...
    startsWith(delayProfile, "TDL") || startsWith(delayProfile, "CDL") || ...
    startsWith(tdlProfile, "TDL-") || startsWith(cdlProfile, "CDL-") || ...
    strcmp(fadingModel, "TDL") || strcmp(fadingModel, "CDL");

tf = strcmp(backend, "waveform") && fadingEnabled && ~awgnOnly && isConcreteFading;
end

function tf = localUseConfiguredCQIAMC(linkAdaptationMode, linkAdaptationPolicy)
mode = lower(strtrim(string(linkAdaptationMode)));
policy = lower(strtrim(string(linkAdaptationPolicy)));
fixedTokens = ["fixed","fixed_mcs","configured_fixed","disabled","off","none","false"];
tf = ~ismember(mode, fixedTokens) && ~ismember(policy, fixedTokens);
end

function mcs = localMatchMCSIndex(mcsTable, modStr, targetCodeRate)
targetQM = sixgr.l2.mac.SchedulerBase.modOrder(modStr);
targetSE = double(targetQM) * double(targetCodeRate);
bestIdx = 0;
bestScore = inf;
for idx = 0:31
    prof = sixgr.link.resolveMCSProfile(mcsTable, idx);
    if ~prof.Valid
        continue;
    end
    if prof.Qm > targetQM + 1e-9
        continue;
    end
    score = abs(double(prof.SpectralEfficiency) - targetSE);
    if score < bestScore - 1e-9 || ...
            (abs(score - bestScore) <= 1e-9 && abs(double(prof.TargetCodeRate) - double(targetCodeRate)) < 1e-9 && idx > bestIdx)
        bestScore = score;
        bestIdx = idx;
    end
end
mcs = bestIdx;
end

function tableName = localDefaultMCSTable(modulationToken)
qm = sixgr.l2.mac.SchedulerBase.modOrder(modulationToken);
if qm >= 8
    tableName = "qam256_table2";
else
    tableName = "qam64_table1";
end
end

function tableName = localDefaultCQITable(mcsTable)
token = lower(string(mcsTable));
if contains(token, "256") || contains(token, "table2")
    tableName = "table2";
else
    tableName = "table1";
end
end

function best = localFindQueueLimitedPlan(obj, amc, prbSet, symAlloc, queueBytes, varargin)
opt = struct("PlanningOnly", false);
if ~isempty(varargin)
    if mod(numel(varargin), 2) ~= 0
        error("sixgr:SchedulerBase:QueueLimitedPlanBadNV", ...
            "localFindQueueLimitedPlan name-value inputs must come in pairs.");
    end
    for nvIdx = 1:2:numel(varargin)
        key = lower(string(varargin{nvIdx}));
        value = varargin{nvIdx + 1};
        switch key
            case "planningonly"
                opt.PlanningOnly = logical(value);
            otherwise
                error("sixgr:SchedulerBase:QueueLimitedPlanUnknownNV", ...
                    "Unknown localFindQueueLimitedPlan option '%s'.", char(key));
        end
    end
end

best = struct("Valid", false);
rawPRBSet = double(prbSet(:).');
if isempty(rawPRBSet)
    return;
end

candidateProfiles = localCandidateMCSProfiles(amc);
bestBits = -inf;
bestPRBCount = inf;
for i = 1:numel(candidateProfiles)
    cand = candidateProfiles(i);
    [bestIdxForCand, bestCand] = localFindLargestQueueFit(obj, cand, rawPRBSet, symAlloc, queueBytes, opt);
    if ~bestCand.Valid
        continue;
    end
    [minIdxForCand, minCand] = localFindSmallestSubsetForBits( ...
        obj, cand, rawPRBSet, symAlloc, queueBytes, bestIdxForCand, bestCand.TBSBits, opt);
    if minCand.Valid
        chosenIdx = minIdxForCand;
        chosenCand = minCand;
    else
        chosenIdx = bestIdxForCand;
        chosenCand = bestCand;
    end
    prbSubset = rawPRBSet(1:chosenIdx);
    if chosenCand.TBSBits > bestBits + 1e-9 || ...
            (abs(chosenCand.TBSBits - bestBits) <= 1e-9 && numel(prbSubset) < bestPRBCount)
        best = struct( ...
            "Valid", true, ...
            "PRBSet", double(prbSubset), ...
            "Modulation", char(string(cand.Modulation)), ...
            "NumLayers", double(cand.NumLayers), ...
            "TargetCodeRate", double(cand.TargetCodeRate), ...
            "MCSIndex", double(cand.MCSIndex), ...
            "NREPerPRB", double(chosenCand.NREPerPRB), ...
            "TBSBits", double(chosenCand.TBSBits), ...
            "TBSBytes", double(chosenCand.TBSBytes));
        bestBits = double(chosenCand.TBSBits);
        bestPRBCount = numel(prbSubset);
    end
end
end

function [bestIdx, bestEval] = localFindLargestQueueFit(obj, cand, rawPRBSet, symAlloc, queueBytes, opt)
bestIdx = 0;
bestEval = localInvalidQueueEval();
lo = 1;
hi = numel(rawPRBSet);
while lo <= hi
    mid = floor((lo + hi) / 2);
    evalMid = localEvaluateQueueLimitedCandidate(obj, cand, mid, symAlloc, queueBytes, opt);
    if evalMid.Valid
        bestIdx = mid;
        bestEval = evalMid;
        lo = mid + 1;
    else
        hi = mid - 1;
    end
end
end

function [bestIdx, bestEval] = localFindSmallestSubsetForBits(obj, cand, rawPRBSet, symAlloc, queueBytes, hiIdx, targetBits, opt)
bestIdx = 0;
bestEval = localInvalidQueueEval();
if hiIdx <= 0 || ~(isfinite(targetBits) && targetBits > 0)
    return;
end
lo = 1;
hi = hiIdx;
while lo <= hi
    mid = floor((lo + hi) / 2);
    evalMid = localEvaluateQueueLimitedCandidate(obj, cand, mid, symAlloc, queueBytes, opt);
    if evalMid.Valid && abs(evalMid.TBSBits - targetBits) <= 1e-9
        bestIdx = mid;
        bestEval = evalMid;
        hi = mid - 1;
    else
        lo = mid + 1;
    end
end
end

function evalOut = localEvaluateQueueLimitedCandidate(obj, cand, prbCount, symAlloc, queueBytes, opt)
evalOut = localInvalidQueueEval();
[tbsBits, tbsBytes, nrePerPRB] = obj.estimateTBS( ...
    cand.Modulation, cand.NumLayers, double(prbCount), symAlloc, cand.TargetCodeRate, ...
    "PlanningOnly", logical(opt.PlanningOnly));
if ~(isfinite(tbsBits) && isfinite(tbsBytes) && tbsBits > 0 && tbsBytes > 0)
    return;
end
if tbsBytes > queueBytes
    return;
end
evalOut.Valid = true;
evalOut.NREPerPRB = double(nrePerPRB);
evalOut.TBSBits = double(tbsBits);
evalOut.TBSBytes = double(tbsBytes);
end

function evalOut = localInvalidQueueEval()
evalOut = struct( ...
    "Valid", false, ...
    "NREPerPRB", NaN, ...
    "TBSBits", NaN, ...
    "TBSBytes", NaN);
end

function candidates = localCandidateMCSProfiles(amc)
mode = lower(string(sixgr.util.structGet(amc, "Mode", "fixed_modulation")));
mcsTable = char(string(sixgr.util.structGet(amc, "MCSTable", "qam64_table1")));
numLayers = max(1, round(double(sixgr.util.structGet(amc, "NumLayers", 1))));

if mode == "cqi_table" && isfinite(double(sixgr.util.structGet(amc, "MCSIndex", NaN)))
    idxList = round(double(sixgr.util.structGet(amc, "MCSIndex", 0))):-1:0;
    candidates = repmat(struct("MCSIndex", 0, "Modulation", "QPSK", "TargetCodeRate", 0.1, "NumLayers", numLayers), 0, 1);
    for idx = idxList
        prof = sixgr.link.resolveMCSProfile(mcsTable, idx);
        if prof.Valid
            candidates(end+1) = struct( ... %#ok<AGROW>
                "MCSIndex", double(idx), ...
                "Modulation", char(string(prof.Modulation)), ...
                "TargetCodeRate", double(prof.TargetCodeRate), ...
                "NumLayers", double(numLayers));
        end
    end
else
    candidates = struct( ...
        "MCSIndex", double(sixgr.util.structGet(amc, "MCSIndex", 0)), ...
        "Modulation", char(string(sixgr.util.structGet(amc, "Modulation", "QPSK"))), ...
        "TargetCodeRate", double(sixgr.util.structGet(amc, "TargetCodeRate", 0.1)), ...
        "NumLayers", double(numLayers));
end
end

function map = localSharedTBSCache()
persistent sharedMap
if isempty(sharedMap)
    sharedMap = containers.Map('KeyType','char','ValueType','any');
end
map = sharedMap;
end

function map = localSharedNRECache()
persistent sharedMap
if isempty(sharedMap)
    sharedMap = containers.Map('KeyType','char','ValueType','double');
end
map = sharedMap;
end

function scopedKey = localScopedCacheKey(scopeToken, rawKey)
scopeToken = char(string(scopeToken));
if strlength(string(scopeToken)) == 0
    scopeToken = 'default';
end
rawKey = char(string(rawKey));
scopedKey = sprintf('%s||%s', scopeToken, rawKey);
end

function token = localSchedulerCacheScopeToken(cfg, direction, carrier, symbolsPerSlot)
scope = struct();
scope.Direction = upper(char(string(direction)));
scope.SymbolsPerSlot = double(symbolsPerSlot);
scope.Carrier = sixgr.util.structGet(cfg, "phy.carrier", struct());
scope.DMRS = sixgr.util.structGet(cfg, "phy.dmrs", struct());
if strcmpi(direction, 'UL')
    scope.ChannelConfig = sixgr.util.structGet(cfg, "phy.pusch", struct());
    scope.Sounder = sixgr.util.structGet(cfg, "phy.srs", struct());
else
    scope.ChannelConfig = sixgr.util.structGet(cfg, "phy.pdsch", struct());
    scope.Sounder = sixgr.util.structGet(cfg, "phy.csirs", struct());
end
if ~isempty(carrier) && isobject(carrier)
    try
        scope.RuntimeCarrier = struct( ...
            "NSizeGrid", double(carrier.NSizeGrid), ...
            "SymbolsPerSlot", double(carrier.SymbolsPerSlot), ...
            "SubcarrierSpacing", double(carrier.SubcarrierSpacing), ...
            "CyclicPrefix", char(string(carrier.CyclicPrefix)));
    catch
        % Keep the config-derived scope if runtime carrier fields are not readable.
    end
end
try
    token = char(jsonencode(scope));
catch
    token = sprintf('%s|NGrid=%g|Symbols=%g', upper(char(string(direction))), ...
        double(sixgr.util.structGet(cfg, "phy.carrier.NSizeGrid", NaN)), double(symbolsPerSlot));
end
end

function key = localNRECacheKey(direction, nLayers, nPRB, symAlloc)
sa = double(symAlloc(:).');
if numel(sa) < 2
    sa = [0 14];
end

dirToken = upper(char(string(direction)));
startSym = round(double(sa(1)));
nSym = round(double(sa(2)));
key = sprintf('%s|L%d|P%d|S%d|N%d', dirToken, round(double(nLayers)), round(double(nPRB)), startSym, nSym);
end

function nrePerPRB = localComputeExactNREPerPRB(direction, carrier, cfg, nPRB, symAlloc, modStr, nLayers)
if strcmpi(direction,'DL')
    [~, allocInfo] = sixgr.phy.grid.allocREsPDSCH(carrier, cfg, ...
        "PRBSet", 0:(max(nPRB,1)-1), ...
        "SymbolAllocation", symAlloc, ...
        "Modulation", char(modStr), ...
        "NumLayers", double(nLayers));
else
    [~, allocInfo] = sixgr.phy.grid.allocREsPUSCH(carrier, cfg, ...
        "PRBSet", 0:(max(nPRB,1)-1), ...
        "SymbolAllocation", symAlloc, ...
        "Modulation", char(modStr), ...
        "NumLayers", double(nLayers));
end
nrePerPRB = localExtractNREPerPRB(allocInfo, nPRB, modStr, nLayers);
end

function nrePerPRB = localExtractNREPerPRB(info, nPRB, modStr, nLayers)
[nrePerPRB, ~] = sixgr.util.resolveDataNREPerPRB(info, nPRB, modStr, nLayers);
end
