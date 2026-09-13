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
        SlotDuration_s (1,1) double = NaN
        NSizeGrid (1,1) double = 0
        SymbolsPerSlot (1,1) double = NaN
    end

    properties(Access=protected)
        UEStats = struct('RNTI',{},'AvgThroughput_bps',{},'LastServedSlot',{},'LastTBSBits',{}, ...
            'LastAck',{},'NumScheduledSlots',{},'NumUnscheduledSlots',{}, ...
            'OLLADeltaDb',{},'OLLADeltaMCS',{},'OLLAUpdateCount',{},'LastOLLAAck',{})
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
            % Scheduler construction is the last normal production boundary
            % before grants are materialized.  Attach the serializable
            % canonical frame/CC/BWP context here when buildInternalConfig
            % has not already done so.  The builder performs physical
            % resolution once and never supplies legacy K/default rows.
            cfg = sixgr.phy.frame.FrameRuntimeStateBuilder. ...
                attachTimingContext(cfg);
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

            % The scheduler consumes the already attached canonical frame
            % state. A carrier construction error is a configuration or
            % Toolbox dependency failure and must not become a mu-0
            % scheduler with invented 14-symbol timing.
            [carrier, ~] = sixgr.phy.grid.makeCarrier(cfg);
            obj.Carrier = carrier;
            obj.NSizeGrid = double(carrier.NSizeGrid);
            numerology = sixgr.util.structGet( ...
                cfg, "phy.frameStructure.Numerology", []);
            if ~(isstruct(numerology) && isscalar(numerology) && ...
                    isfield(numerology, "SymbolsPerSlot") && ...
                    isfield(numerology, "SlotDurationSeconds"))
                error("sixgr:SchedulerBase:MissingCanonicalNumerology", ...
                    "Scheduler construction requires the attached canonical numerology.");
            end
            obj.SymbolsPerSlot = double(numerology.SymbolsPerSlot);
            obj.SlotDuration_s = double(numerology.SlotDurationSeconds);

            if ~alphaExplicit
                % PF implementations normally average over O(100ms), not a
                % handful of slots. alpha = exp(-Tslot/tau) per R1-062478
                % proportional-fair scheduler guidance.
                tauMs = max(1, double(obj.AvgWindowMs));
                obj.Alpha = exp(-double(obj.SlotDuration_s) * 1e3 / tauMs);
            end
            localWarnIfPFAlphaOutOfRange(obj.Alpha, obj.SlotDuration_s);

            % HARQ execution is owned by the resolved YAML feature flag.
            % Do not swallow configuration/constructor failures: that would
            % silently turn an enabled HARQ scenario into non-HARQ execution.
            harqEnable = logical(sixgr.util.structGet(cfg,"mac.harq.enable",false));
            sixgr.config.assertRuntimeFeatureUse(cfg, "harq", harqEnable, ...
                "SchedulerBase.HARQ");
            if harqEnable && isempty(obj.HARQ)
                if strcmpi(obj.Direction, "DL")
                    obj.HARQ = sixgr.l2.mac.HARQEntityDL(cfg,'Logger',obj.Logger);
                else
                    obj.HARQ = sixgr.l2.mac.HARQEntityUL(cfg,'Logger',obj.Logger);
                end
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
                'LastAck',{},'NumScheduledSlots',{},'NumUnscheduledSlots',{}, ...
                'OLLADeltaDb',{},'OLLADeltaMCS',{},'OLLAUpdateCount',{},'LastOLLAAck',{});
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
            % Optional RV/IsRetransmission marks HARQ-combined feedback that
            % must not raise/lower first-transmission OLLA.
            if isempty(rxFeedback)
                return;
            end
            if istable(rxFeedback)
                rntiList = rxFeedback.RNTI;
                tbsList  = rxFeedback.TBSBits;
                if ismember("Outcome", string(rxFeedback.Properties.VariableNames))
                    outcomeList = upper(string(rxFeedback.Outcome));
                    ackList = outcomeList == "ACK";
                else
                    ackList  = rxFeedback.Ack;
                    outcomeList = strings(height(rxFeedback),1);
                    outcomeList(logical(ackList)) = "ACK";
                    outcomeList(~logical(ackList)) = "NACK";
                end
                rvList = nan(height(rxFeedback), 1);
                isRetxList = false(height(rxFeedback), 1);
                isRetxKnownList = false(height(rxFeedback), 1);
                ollaAuthorityList = repmat("scheduler_local_state", height(rxFeedback), 1);
                sourceSlotList = nan(height(rxFeedback), 1);
                if ismember("HarqID", string(rxFeedback.Properties.VariableNames))
                    harqIdList = rxFeedback.HarqID;
                elseif ismember("HARQProcess", string(rxFeedback.Properties.VariableNames))
                    harqIdList = rxFeedback.HARQProcess;
                else
                    harqIdList = nan(height(rxFeedback), 1);
                end
                if ismember("RV", string(rxFeedback.Properties.VariableNames))
                    rvList = double(rxFeedback.RV);
                end
                if ismember("IsRetransmission", string(rxFeedback.Properties.VariableNames))
                    isRetxList = logical(rxFeedback.IsRetransmission);
                    isRetxKnownList = true(height(rxFeedback), 1);
                end
                if ismember("OLLAStateAuthority", string(rxFeedback.Properties.VariableNames))
                    ollaAuthorityList = string(rxFeedback.OLLAStateAuthority);
                end
                if ismember("SourceSlot", string(rxFeedback.Properties.VariableNames))
                    sourceSlotList = double(rxFeedback.SourceSlot);
                elseif ismember("Slot", string(rxFeedback.Properties.VariableNames))
                    sourceSlotList = double(rxFeedback.Slot);
                end
            else
                rntiList = [rxFeedback.RNTI];
                tbsList  = [rxFeedback.TBSBits];
                if isfield(rxFeedback, "Outcome")
                    outcomeList = upper(string({rxFeedback.Outcome}));
                    ackList = outcomeList == "ACK";
                else
                    ackList  = [rxFeedback.Ack];
                    outcomeList = strings(numel(ackList),1);
                    outcomeList(logical(ackList)) = "ACK";
                    outcomeList(~logical(ackList)) = "NACK";
                end
                harqIdList = nan(numel(rntiList), 1);
                rvList = nan(numel(rntiList), 1);
                isRetxList = false(numel(rntiList), 1);
                isRetxKnownList = false(numel(rntiList), 1);
                ollaAuthorityList = repmat("scheduler_local_state", numel(rntiList), 1);
                sourceSlotList = nan(numel(rntiList), 1);
                for ii = 1:numel(rntiList)
                    if isfield(rxFeedback(ii), "HarqID") && ~isempty(rxFeedback(ii).HarqID)
                        harqIdList(ii) = double(rxFeedback(ii).HarqID);
                    elseif isfield(rxFeedback(ii), "HARQProcess") && ~isempty(rxFeedback(ii).HARQProcess)
                        harqIdList(ii) = double(rxFeedback(ii).HARQProcess);
                    elseif isfield(rxFeedback(ii), "HARQ") && isstruct(rxFeedback(ii).HARQ)
                        harqIdList(ii) = double(sixgr.util.structGet(rxFeedback(ii).HARQ, "HarqID", NaN));
                    end
                    if isfield(rxFeedback(ii), "RV") && ~isempty(rxFeedback(ii).RV)
                        rvList(ii) = double(rxFeedback(ii).RV);
                    elseif isfield(rxFeedback(ii), "HARQ") && isstruct(rxFeedback(ii).HARQ)
                        rvList(ii) = double(sixgr.util.structGet(rxFeedback(ii).HARQ, "RV", NaN));
                    end
                    if isfield(rxFeedback(ii), "IsRetransmission") && ~isempty(rxFeedback(ii).IsRetransmission)
                        isRetxList(ii) = logical(rxFeedback(ii).IsRetransmission);
                        isRetxKnownList(ii) = true;
                    elseif isfield(rxFeedback(ii), "HARQ") && isstruct(rxFeedback(ii).HARQ) && ...
                            isfield(rxFeedback(ii).HARQ, "IsRetransmission")
                        isRetxList(ii) = logical(rxFeedback(ii).HARQ.IsRetransmission);
                        isRetxKnownList(ii) = true;
                    end
                    if isfield(rxFeedback(ii), "OLLAStateAuthority") && ...
                            ~isempty(rxFeedback(ii).OLLAStateAuthority)
                        ollaAuthorityList(ii) = string(rxFeedback(ii).OLLAStateAuthority);
                    end
                    if isfield(rxFeedback(ii), "SourceSlot") && ~isempty(rxFeedback(ii).SourceSlot)
                        sourceSlotList(ii) = double(rxFeedback(ii).SourceSlot);
                    elseif isfield(rxFeedback(ii), "Slot") && ~isempty(rxFeedback(ii).Slot)
                        sourceSlotList(ii) = double(rxFeedback(ii).Slot);
                    end
                end
            end

            for k = 1:numel(rntiList)
                rnti = double(rntiList(k));
                tbsBits = double(tbsList(k));
                ack = logical(ackList(k));
                obj.updateAvgThroughput(rnti, tbsBits, ack);
                if any(outcomeList(k)==["ACK","NACK"]) && ...
                        ~localOLLAIsExternallyManaged(ollaAuthorityList(k)) && ...
                        localFeedbackEligibleForOLLA(isRetxKnownList(k), isRetxList(k), rvList(k))
                    obj.updateOLLADelta(rnti, ack);
                end
                if ~isempty(obj.HARQ)
                    harqId = double(harqIdList(k));
                    if isfinite(harqId)
                        if isfinite(double(sourceSlotList(k)))
                            obj.HARQ.onFeedback(rnti, harqId, outcomeList(k), "SourceSlot", double(sourceSlotList(k)));
                        else
                            obj.HARQ.onFeedback(rnti, harqId, outcomeList(k));
                        end
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

        function markUnscheduled(obj, rnti)
            % Decay PF history for active UEs that were considered but not served.
            i = obj.ensureUE(double(rnti));
            old = double(obj.UEStats(i).AvgThroughput_bps);
            switch lower(char(obj.MetricAveraging))
                case 'exp'
                    a = min(max(obj.Alpha,0),1);
                    obj.UEStats(i).AvgThroughput_bps = a * old;
                otherwise
                    obj.UEStats(i).AvgThroughput_bps = 0.5 * old;
            end
            obj.UEStats(i).LastTBSBits = 0;
            obj.UEStats(i).LastAck = false;
            obj.UEStats(i).NumUnscheduledSlots = double(obj.UEStats(i).NumUnscheduledSlots) + 1;
        end

        function updateOLLADelta(obj, rnti, ack)
            if ~localSchedulerOLLAEnabled(obj.Cfg)
                return;
            end
            i = obj.ensureUE(double(rnti));
            delta = double(sixgr.util.structGet(obj.UEStats(i), "OLLADeltaDb", ...
                sixgr.util.structGet(obj.UEStats(i), "OLLADeltaMCS", 0)));
            if logical(ack)
                delta = delta + localSchedulerOLLAStep(obj.Cfg, "up");
            else
                delta = delta - localSchedulerOLLAStep(obj.Cfg, "down");
            end
            delta = min(localSchedulerOLLADeltaMax(obj.Cfg), max(localSchedulerOLLADeltaMin(obj.Cfg), delta));
            obj.UEStats(i).OLLADeltaDb = double(delta);
            obj.UEStats(i).OLLADeltaMCS = double(delta); % Legacy export alias; units are dB.
            obj.UEStats(i).OLLAUpdateCount = double(sixgr.util.structGet(obj.UEStats(i), "OLLAUpdateCount", 0)) + 1;
            obj.UEStats(i).LastOLLAAck = logical(ack);
        end

        function [delta, updateCount, enabled] = getOLLAMCSDelta(obj, rnti)
            enabled = localSchedulerOLLAEnabled(obj.Cfg);
            delta = 0;
            updateCount = 0;
            if ~(enabled && isfinite(double(rnti)))
                return;
            end
            i = obj.ensureUE(double(rnti));
            delta = double(sixgr.util.structGet(obj.UEStats(i), "OLLADeltaDb", ...
                sixgr.util.structGet(obj.UEStats(i), "OLLADeltaMCS", 0)));
            updateCount = double(sixgr.util.structGet(obj.UEStats(i), "OLLAUpdateCount", 0));
            if ~isfinite(delta)
                delta = 0;
            end
            if ~isfinite(updateCount)
                updateCount = 0;
            end
        end

        function prewarmUEAverage(obj, ue, nActiveUE)
            if nargin < 3 || isempty(nActiveUE)
                nActiveUE = 1;
            end
            if ~isstruct(ue) || ~isfield(ue, "RNTI") || isempty(ue.RNTI)
                return;
            end
            idx = obj.ensureUE(double(ue.RNTI));
            if isfinite(double(obj.UEStats(idx).LastServedSlot)) || ...
                    double(obj.UEStats(idx).NumScheduledSlots) > 0 || ...
                    double(obj.UEStats(idx).NumUnscheduledSlots) > 0
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
                obj.UEStats(end).OLLADeltaDb = 0;
                obj.UEStats(end).OLLADeltaMCS = 0;
                obj.UEStats(end).OLLAUpdateCount = 0;
                obj.UEStats(end).LastOLLAAck = false;
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
                symAlloc = localDefaultSymbolAllocation(obj.Cfg, obj.Direction, obj.SymbolsPerSlot);
            end
        end

        function [modStr, nLayers, targetCodeRate, amc] = selectAMC(obj, ue)
            % Select modulation/layers/code rate using an explicit NR AMC path.
            dir = upper(obj.Direction);
            mcsTable = obj.resolveMCSTable();
            cqiTable = obj.resolveCQITable();
            cqiRaw = sixgr.l2.mac.SchedulerBase.sanitizeCQI( ...
                sixgr.util.structGet(ue, "CQI", NaN), NaN);
            feedbackValid = logical(sixgr.util.structGet(ue, "FeedbackValid", true));
            bootstrapCQIUsable = logical(sixgr.util.structGet(ue, ...
                "BootstrapCQIUsableForScheduling", false));
            bootstrapCQISource = strtrim(string(sixgr.util.structGet(ue, ...
                "BootstrapCQISource", "")));
            isBootstrapCQI = ~feedbackValid && bootstrapCQIUsable && ...
                strlength(bootstrapCQISource) > 0;
            [causalFeedbackUsable, causalFeedbackStatus, feedbackAgeSlots, feedbackAgeSeconds] = ...
                localResolveUECausalFeedback(ue, obj.Cfg, dir);

            if strcmp(dir,'DL')
                modStr = char(string(sixgr.util.structGet(obj.Cfg,"runtime.phy.dl.Modulation", ...
                    sixgr.util.structGet(obj.Cfg,"phy.pdsch.modulation","16QAM"))));
                nLayers = double(sixgr.util.structGet(obj.Cfg,"runtime.phy.dl.NumLayers", ...
                    sixgr.util.structGet(obj.Cfg,"phy.pdsch.nLayers",1)));
                targetCodeRate = double(sixgr.util.structGet(obj.Cfg,"runtime.phy.dl.TargetCodeRate", ...
                    sixgr.util.structGet(obj.Cfg,"phy.pdsch.codeRate",0.5)));
                cfgMCSIndex = double(sixgr.util.structGet(obj.Cfg,"runtime.phy.dl.MCSIndex", ...
                    sixgr.util.structGet(obj.Cfg,"phy.pdsch.mcsIndex", NaN)));
                linkAdaptationPolicy = sixgr.util.structGet(obj.Cfg, ...
                    "runtime.link_adaptation.DLPolicy", ...
                    sixgr.util.structGet(obj.Cfg, "phy.linkAdaptation.dlPolicy", ""));
            else
                modStr = char(string(sixgr.util.structGet(obj.Cfg,"runtime.phy.ul.Modulation", ...
                    sixgr.util.structGet(obj.Cfg,"phy.pusch.modulation","16QAM"))));
                nLayers = double(sixgr.util.structGet(obj.Cfg,"runtime.phy.ul.NumLayers", ...
                    sixgr.util.structGet(obj.Cfg,"phy.pusch.nLayers",1)));
                targetCodeRate = double(sixgr.util.structGet(obj.Cfg,"runtime.phy.ul.TargetCodeRate", ...
                    sixgr.util.structGet(obj.Cfg,"phy.pusch.codeRate",0.5)));
                cfgMCSIndex = double(sixgr.util.structGet(obj.Cfg,"runtime.phy.ul.MCSIndex", ...
                    sixgr.util.structGet(obj.Cfg,"phy.pusch.mcsIndex", NaN)));
                linkAdaptationPolicy = sixgr.util.structGet(obj.Cfg, ...
                    "runtime.link_adaptation.ULPolicy", ...
                    sixgr.util.structGet(obj.Cfg, "phy.linkAdaptation.ulPolicy", ""));
            end
            linkAdaptationMode = sixgr.util.structGet(obj.Cfg, ...
                "runtime.link_adaptation.Mode", ...
                sixgr.util.structGet(obj.Cfg, "phy.linkAdaptation.mode", "fixed"));
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
                "MCSProfile", sixgr.link.resolveMCSProfile(mcsTable, -1), ...
                "InnerLoopEnabled", logical(localSchedulerInnerLoopEnabled(obj.Cfg, dir)), ...
                "InnerLoopApplied", false, ...
                "OuterLoopEnabled", logical(localSchedulerOLLAEnabled(obj.Cfg)), ...
                "OuterLoopApplied", false, ...
                "OLLADeltaDb", 0, ...
                "OLLADeltaMCS", 0, ...
                "OLLAMarginMinDb", double(localSchedulerOLLADeltaMin(obj.Cfg)), ...
                "OLLAMarginMaxDb", double(localSchedulerOLLADeltaMax(obj.Cfg)), ...
                "OLLAAdjustedMCSBeforeCQICeiling", NaN, ...
                "OLLABaseRequiredSINR_dB", NaN, ...
                "OLLATargetRequiredSINR_dB", NaN, ...
                "OLLAThresholdSource", "", ...
                "OLLAUpdateCount", 0, ...
                "OLLAStateAuthority", "scheduler_local_state", ...
                "OLLAState", "not_applicable", ...
                "MCSSelectionSource", "configured_profile", ...
                "CQIProvenance", "unavailable", ...
                "MCSValueStatus", "unresolved", ...
                "ConfiguredInitialMCSIndex", double(sixgr.util.structGet(obj.Cfg, ...
                    "runtime.link_adaptation.InitialMCSIndex", ...
                    sixgr.util.structGet(obj.Cfg, "phy.linkAdaptation.initialMCSIndex", NaN))), ...
                "ConfiguredMaximumMCSIndex", double(sixgr.util.structGet(obj.Cfg, ...
                    "runtime.link_adaptation.MaximumMCSIndex", ...
                    sixgr.util.structGet(obj.Cfg, "phy.linkAdaptation.maximumMCSIndex", NaN))), ...
                "MaximumMCSBoundApplied", false, ...
                "RawCQIDerivedMCS", NaN, ...
                "CausalFeedbackUsable", logical(causalFeedbackUsable), ...
                "CausalFeedbackStatus", char(causalFeedbackStatus), ...
                "FeedbackAgeSlots", double(feedbackAgeSlots), ...
                "FeedbackAgeSeconds", double(feedbackAgeSeconds), ...
                "SubbandSINRVector_dB", char(string(sixgr.util.structGet(ue, "SubbandSINRVector_dB", ""))), ...
                "AgedSubbandSINRVector_dB", char(string(sixgr.util.structGet(ue, "AgedSubbandSINRVector_dB", ""))), ...
                "PostEqSINRPerLayer_dB", char(string(sixgr.util.structGet(ue, "PostEqSINRPerLayer_dB", ""))), ...
                "AgedPostEqSINRPerLayer_dB", char(string(sixgr.util.structGet(ue, "AgedPostEqSINRPerLayer_dB", ""))), ...
                "SchedulerCQIRawCQI", double(sixgr.util.structGet(ue, "SchedulerCQIRawCQI", NaN)), ...
                "SchedulerAdjustedSINR_dB", double(sixgr.util.structGet(ue, "SchedulerAdjustedSINR_dB", NaN)), ...
                "SchedulerSINRBackoff_dB", double(sixgr.util.structGet(ue, "SchedulerSINRBackoff_dB", NaN)), ...
                "SchedulerCQISource", char(string(sixgr.util.structGet(ue, "SchedulerCQISource", ""))), ...
                "AutoQueueAwareWidebandCQIGuard", false, ...
                "CalibrationProfile", char(localSchedulerCalibrationProfile(obj.Cfg, dir)), ...
                "InitialNumLayers", double(nLayers), ...
                "RankSelectionPolicy", "", ...
                "RankSelectionSource", "", ...
                "RankDecisionReason", "", ...
                "RankDowngradeApplied", false, ...
                "MaxSupportedLayers", NaN);

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
                ueMCSIndexAuthority == "ul_shared_reuse_probe_conservative_mcs" || ...
                ismember(lower(strtrim(string(linkAdaptationMode))), fixedTokens) || ...
                ismember(lower(strtrim(string(linkAdaptationPolicy))), fixedTokens));

            if useExplicitUEMCSOverride
                amc.Mode = "fixed_mcs";
                amc.MCSIndex = round(ueMCSIndex);
                if ueMCSIndexAuthority == "ul_shared_reuse_probe_conservative_mcs"
                    amc.MCSSelectionSource = "ul_shared_reuse_probe_conservative_mcs";
                    amc.MCSValueStatus = "shared_reuse_probe_pending";
                else
                    amc.MCSSelectionSource = "explicit_ue_or_configured_fixed_mcs";
                    amc.MCSValueStatus = "configured";
                end
                amc.CQIProvenance = "not_used_fixed_mcs";
            elseif useConfiguredCQIAMC
                amc.Mode = "cqi_table";
                if ~logical(causalFeedbackUsable)
                    cqiDecision = struct("Valid", false);
                    amc = localMarkMissingRuntimeCQI(amc, obj.Cfg, causalFeedbackStatus);
                elseif isfinite(double(cqiRaw)) && double(cqiRaw) == 0
                    % TS 38.214 CQI index 0 is an explicit out-of-range
                    % report.  It is receiver feedback, not missing CSI,
                    % and therefore must never reopen the conservative
                    % first-transmission bootstrap path.
                    cqiDecision = struct("Valid", false);
                    amc = localMarkMissingRuntimeCQI(amc, obj.Cfg, ...
                        "measured_cqi_zero_out_of_range");
                    amc.InnerLoopApplied = true;
                elseif ~(isfinite(double(cqiRaw)) && cqiRaw > 0)
                    cqiDecision = struct("Valid", false);
                    amc = localMarkMissingRuntimeCQI(amc, obj.Cfg, "missing_runtime_cqi");
                else
                    cqiDecision = sixgr.link.resolveMCSFromCQI(cqiRaw, mcsTable, cqiTable);
                end
                if isfield(cqiDecision, "Valid") && cqiDecision.Valid
                    amc.Mode = "cqi_table";
                    amc.MCSIndex = double(cqiDecision.MCSIndex);
                    amc.MCSProfile = cqiDecision.MCSProfile;
                    if isBootstrapCQI
                        amc.MCSSelectionSource = char(bootstrapCQISource);
                        amc.CQIProvenance = char(bootstrapCQISource);
                        amc.MCSValueStatus = "bootstrap_not_measured_cqi";
                    else
                        amc.MCSSelectionSource = "runtime_cqi_table";
                        amc.CQIProvenance = localSchedulerCQIProvenance(ue, "runtime_reported_cqi");
                        amc.MCSValueStatus = "measured_cqi_mapped";
                    end
                    amc.RawCQIDerivedMCS = double(cqiDecision.MCSIndex);
                    % CausalFeedbackUsable is the authoritative admission
                    % result after feedback age/source validation.  The
                    % legacy FeedbackValid bit alone is too narrow for
                    % measured SRS/CSI feedback installed by the coupled
                    % runtime and caused executed CQI decisions to be
                    % mislabeled as unapplied.
                    amc.InnerLoopApplied = logical(causalFeedbackUsable && ~isBootstrapCQI);
                    modStr = char(string(cqiDecision.MCSProfile.Modulation));
                    targetCodeRate = double(cqiDecision.MCSProfile.TargetCodeRate);
                else
                    % In AMC mode, missing/invalid CQI must not silently
                    % promote the configured study MCS into a scheduler grant.
                    % Conservative scenarios can still request a labeled
                    % bootstrap MCS. Measured-only scenarios fail closed and
                    % block the grant until runtime CQI evidence arrives.
                    if localAMCBlocksGrant(amc)
                        % Preserve an explicit measured-CQI-0 outage (or
                        % another typed block) selected above.
                    elseif logical(causalFeedbackUsable)
                        amc = localMarkMissingRuntimeCQI(amc, obj.Cfg, "missing_or_invalid_runtime_cqi");
                    else
                        amc = localMarkMissingRuntimeCQI(amc, obj.Cfg, causalFeedbackStatus);
                    end
                end
            elseif isfinite(cfgMCSIndex) && cfgMCSIndex >= 0
                amc.Mode = "fixed_mcs";
                amc.MCSIndex = round(cfgMCSIndex);
                amc.MCSSelectionSource = "configured_fixed_mcs";
                amc.CQIProvenance = "not_used_fixed_mcs";
                amc.MCSValueStatus = "configured";
            elseif hasExplicitFixedModulation
                amc.Mode = "fixed_modulation";
                amc.MCSSelectionSource = "configured_modulation_code_rate";
                amc.CQIProvenance = "not_used_fixed_modulation";
                amc.MCSValueStatus = "configured";
            elseif isfinite(cqiRaw)
                amc.Mode = "cqi_table";
                if ~logical(causalFeedbackUsable)
                    cqiDecision = struct("Valid", false);
                    amc = localMarkMissingRuntimeCQI(amc, obj.Cfg, causalFeedbackStatus);
                elseif double(cqiRaw) == 0
                    cqiDecision = struct("Valid", false);
                    amc = localMarkMissingRuntimeCQI(amc, obj.Cfg, ...
                        "measured_cqi_zero_out_of_range");
                    amc.InnerLoopApplied = true;
                elseif cqiRaw <= 0
                    cqiDecision = struct("Valid", false);
                    amc = localMarkMissingRuntimeCQI(amc, obj.Cfg, "invalid_runtime_cqi");
                else
                    cqiDecision = sixgr.link.resolveMCSFromCQI(cqiRaw, mcsTable, cqiTable);
                end
                if isfield(cqiDecision, "Valid") && cqiDecision.Valid
                    amc.Mode = "cqi_table";
                    amc.MCSIndex = double(cqiDecision.MCSIndex);
                    amc.MCSProfile = cqiDecision.MCSProfile;
                    if isBootstrapCQI
                        amc.MCSSelectionSource = char(bootstrapCQISource);
                        amc.CQIProvenance = char(bootstrapCQISource);
                        amc.MCSValueStatus = "bootstrap_not_measured_cqi";
                    else
                        amc.MCSSelectionSource = "runtime_cqi_table";
                        amc.CQIProvenance = localSchedulerCQIProvenance(ue, "runtime_reported_cqi");
                        amc.MCSValueStatus = "measured_cqi_mapped";
                    end
                    amc.RawCQIDerivedMCS = double(cqiDecision.MCSIndex);
                    amc.InnerLoopApplied = logical(causalFeedbackUsable && ~isBootstrapCQI);
                    modStr = char(string(cqiDecision.MCSProfile.Modulation));
                    targetCodeRate = double(cqiDecision.MCSProfile.TargetCodeRate);
                elseif localAMCBlocksGrant(amc)
                    % Preserve explicit outage/missing-feedback blockers.
                end
            end

            if ismember(string(amc.Mode), ["cqi_table","bootstrap_cqi_conservative"]) && isstruct(amc.MCSProfile) && ...
                    isfield(amc.MCSProfile, "Valid") && logical(amc.MCSProfile.Valid)
                % Keep the modulation/code-rate export aligned with the
                % resolved CQI or explicitly labeled bootstrap profile.
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
            elseif ~isfinite(amc.MCSIndex) && ~localAMCBlocksGrant(amc)
                mcsDecision = sixgr.link.resolveMCSIndexFromProfile(modStr, targetCodeRate, ...
                    "MCSTable", mcsTable, ...
                    "CQI", cqiRaw, ...
                    "CQITable", cqiTable);
                if mcsDecision.Valid
                    amc.MCSIndex = double(mcsDecision.MCSIndex);
                    amc.MCSProfile = mcsDecision.MCSProfile;
                    modStr = char(string(mcsDecision.MCSProfile.Modulation));
                    targetCodeRate = double(mcsDecision.MCSProfile.TargetCodeRate);
                end
            end

            if amc.Mode == "cqi_table" && localSchedulerOLLAEnabled(obj.Cfg)
                rntiForOLLA = double(sixgr.util.structGet(ue, "RNTI", NaN));
                [ollaDeltaDb, ollaCount, ollaEnabled] = obj.getOLLAMCSDelta(rntiForOLLA);
                amc.OuterLoopEnabled = logical(ollaEnabled);
                amc.OLLADeltaDb = double(ollaDeltaDb);
                amc.OLLADeltaMCS = double(ollaDeltaDb); % Legacy export alias; units are dB.
                amc.OLLAUpdateCount = double(ollaCount);
                amc.OLLAState = "configured_waiting_for_ack_feedback";
                if isfinite(amc.MCSIndex) && isfinite(ollaDeltaDb) && ollaCount > 0
                    cqiCeilingMCS = double(sixgr.util.structGet(amc, "RawCQIDerivedMCS", amc.MCSIndex));
                    if ~(isfinite(cqiCeilingMCS) && cqiCeilingMCS >= 0)
                        cqiCeilingMCS = double(amc.MCSIndex);
                    end
                    [unclampedMCS, ollaDetail] = sixgr.link.applyOLLADeltaDbToMCSIndex( ...
                        double(amc.MCSIndex), double(ollaDeltaDb), mcsTable, cqiTable, dir, ...
                        "Config", obj.Cfg);
                    adjustedMCS = max(0, min(31, min(unclampedMCS, floor(double(cqiCeilingMCS)))));
                    prof = sixgr.link.resolveMCSProfile(mcsTable, adjustedMCS);
                    if prof.Valid
                        amc.MCSIndex = double(adjustedMCS);
                        amc.MCSProfile = prof;
                        modStr = char(string(prof.Modulation));
                        targetCodeRate = double(prof.TargetCodeRate);
                        amc.OuterLoopApplied = true;
                        amc.OLLAState = "applied_scheduler_ack_nack_delta";
                        amc.OLLAAdjustedMCSBeforeCQICeiling = double(unclampedMCS);
                        amc.OLLABaseRequiredSINR_dB = double(ollaDetail.BaseRequiredSINR_dB);
                        amc.OLLATargetRequiredSINR_dB = double(ollaDetail.TargetRequiredSINR_dB);
                        amc.OLLAThresholdSource = char(string(ollaDetail.ThresholdSource));
                        if double(unclampedMCS) > double(cqiCeilingMCS)
                            amc.MCSValueStatus = "clamped_to_cqi_max";
                        else
                            amc.MCSValueStatus = "measured_cqi_mapped_olla_db_margin_adjusted";
                        end
                    end
                end
            end

            [amc, modStr, targetCodeRate] = localApplyAdaptiveMCSBounds( ...
                obj.Cfg, amc, modStr, targetCodeRate, mcsTable, ...
                linkAdaptationMode, linkAdaptationPolicy);

            requestedLayers = max(1, min(8, round(nLayers)));
            rankDecision = sixgr.mimo.resolveRankExecutionPolicy(obj.Cfg, dir, requestedLayers, ...
                "WaveformFadingULSafetyRequested", localUseWaveformULSingleLayerSafety(obj.Cfg), ...
                "TransmissionScheme", sixgr.util.structGet(obj.Cfg, "phy.pusch.transmissionScheme", ""), ...
                "TPMI", sixgr.util.structGet(obj.Cfg, "phy.pusch.TPMI", NaN));
            nLayers = double(rankDecision.EffectiveRank);
            nLayers = max(1, min(8, round(nLayers)));
            targetCodeRate = min(max(targetCodeRate, 0.05), 0.95);
            amc.Modulation = char(string(modStr));
            amc.TargetCodeRate = double(targetCodeRate);
            amc.NumLayers = double(nLayers);
            amc.InitialNumLayers = double(requestedLayers);
            amc.RankSelectionPolicy = char(string(rankDecision.Policy));
            amc.RankSelectionSource = char(string(rankDecision.DecisionReason));
            amc.RankDecisionReason = char(string(rankDecision.DecisionReason));
            amc.RankDowngradeApplied = logical(rankDecision.DowngradeApplied);
            amc.MaxSupportedLayers = double(rankDecision.MaxSupportedLayers);
        end

        function tableName = resolveMCSTable(obj)
            if strcmpi(obj.Direction, 'UL')
                token = sixgr.util.structGet(obj.Cfg, "runtime.phy.ul.MCSTable", ...
                    sixgr.util.structGet(obj.Cfg, "phy.pusch.mcsTable", ...
                    localDefaultMCSTable(sixgr.util.structGet(obj.Cfg, "phy.pusch.modulation", "16QAM"))));
            else
                token = sixgr.util.structGet(obj.Cfg, "runtime.phy.dl.MCSTable", ...
                    sixgr.util.structGet(obj.Cfg, "phy.pdsch.mcsTable", ...
                    localDefaultMCSTable(sixgr.util.structGet(obj.Cfg, "phy.pdsch.modulation", "16QAM"))));
            end
            tableName = char(lower(string(token)));
        end

        function tableName = resolveCQITable(obj)
            token = sixgr.link.resolveConfiguredCQITable(obj.Cfg, obj.Direction);
            tableName = char(sixgr.link.resolveCQIProfile(token, 1).Table);
        end

        function [tbsBits, tbsBytes, nrePerPRB, info] = estimateTBS(obj, modStr, nLayers, nPRB, symAlloc, targetCodeRate, varargin)
            % Estimate TB size using nrTBS. Uses NREPerPRB from nrPDSCHInfo/nrPUSCHInfo.
            if nargin < 5 || isempty(symAlloc)
                symAlloc = [0 obj.SymbolsPerSlot];
            end
            opt = struct("PlanningOnly", false, "ForceExact", false, "ConfigOverride", []);
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
                        case "configoverride"
                            opt.ConfigOverride = value;
                        otherwise
                            error("sixgr:SchedulerBase:EstimateTBSUnknownNV", ...
                                "Unknown estimateTBS option '%s'.", char(key));
                    end
                end
            end
            cfgTBS = obj.Cfg;
            cfgOverrideActive = false;
            if isstruct(opt.ConfigOverride) && ~isempty(fieldnames(opt.ConfigOverride))
                cfgTBS = opt.ConfigOverride;
                cfgOverrideActive = true;
            end
            nSym = double(symAlloc(2));
            xOverhead = localResolveTBSXOverhead(obj.Direction, cfgTBS, symAlloc);
            info = struct("UsedFastNREApprox", false, "StrictTBSMode", false, ...
                "TBSMode", "approximate", "ViennaEquivalent", false, ...
                "PlanningOnly", logical(opt.PlanningOnly), ...
                "ForceExact", logical(opt.ForceExact), ...
                "XOverhead", double(xOverhead));

            % Memoize repeated TBS queries (same AMC + budget). The cache key
            % is formed after exact-vs-fast policy resolution so planning
            % probes cannot contaminate executable grant sizing.
            tbsCache = [];
            if isa(obj.TBSCache, 'containers.Map')
                tbsCache = true;
            end
            key = "";

            useFastNRE = logical(sixgr.util.structGet(cfgTBS, "mac.scheduler.fastNREApprox", false));
            strictMode = logical(sixgr.util.structGet(cfgTBS, "run.strictMode", false));
            tbsMode = lower(string(sixgr.util.structGet(cfgTBS, "mac.scheduler.tbsMode", "faithful")));
            viennaEquivalent = logical(sixgr.util.structGet(cfgTBS, "mac.scheduler.viennaEquivalent", false));
            allowApproxPlanningInStrict = logical(sixgr.util.structGet(cfgTBS, ...
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
            if ~localIsTBSModulationSupported(modStr) && ...
                    (strictMode || logical(opt.ForceExact) || tbsMode == "faithful" || tbsMode == "strict" || viennaEquivalent)
                error("sixgr:SchedulerBase:TBSFallback", ...
                    "Strict TBS sizing forbids rough fallback for unsupported modulation '%s'.", char(string(modStr)));
            end
            requiresExactGrantNRE = localRequiresExactGrantNRE(obj.Direction, symAlloc);
            if requiresExactGrantNRE
                useFastNRE = false;
            end
            if ~isempty(tbsCache)
                symStart = round(double(symAlloc(1)));
                cacheScopeToken = obj.CacheScopeToken;
                if cfgOverrideActive
                    cacheScopeToken = localSchedulerCacheScopeToken(cfgTBS, obj.Direction, obj.Carrier, obj.SymbolsPerSlot);
                end
                key = localScopedCacheKey(cacheScopeToken, sprintf("%s|%s|%d|%d|%d|%d|%d|%.4f|planning=%d|force=%d|fast=%d|mode=%s|strict=%d|vienna=%d", ...
                    upper(char(obj.Direction)), upper(char(modStr)), ...
                    round(double(nLayers)), round(double(nPRB)), symStart, round(double(nSym)), ...
                    round(double(xOverhead)), ...
                    round(double(targetCodeRate) * 1e4) / 1e4, ...
                    logical(opt.PlanningOnly), logical(opt.ForceExact), logical(useFastNRE), ...
                    char(tbsMode), logical(strictMode), logical(viennaEquivalent)));
                [hit, v] = sixgr.l2.mac.schedulerCache('get', 'TBS', key);
                if hit
                    tbsBits = double(v(1));
                    tbsBytes = double(v(2));
                    nrePerPRB = double(v(3));
                    if numel(v) >= 4
                        info.UsedFastNREApprox = logical(v(4));
                    end
                    return;
                end
            end
            nrePerPRB = localFastNREPerPRB(obj.Direction, cfgTBS, nSym);
            if ~useFastNRE
                nreCache = [];
                if isa(obj.NRECache, 'containers.Map')
                    nreCache = true;
                end
                cacheScopeToken = obj.CacheScopeToken;
                if cfgOverrideActive
                    cacheScopeToken = localSchedulerCacheScopeToken(cfgTBS, obj.Direction, obj.Carrier, obj.SymbolsPerSlot);
                end
                nreKey = localScopedCacheKey(cacheScopeToken, ...
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
                            [carrier, ~] = sixgr.phy.grid.makeCarrier(cfgTBS, ...
                                "NSizeGrid", max(max(nPRB,1), double(sixgr.util.structGet(cfgTBS, "phy.carrier.NSizeGrid", nPRB))));
                        end
                        nrePerPRB = localComputeExactNREPerPRB(obj.Direction, carrier, cfgTBS, nPRB, symAlloc, modStr, nLayers);
                        if ~isempty(nreCache) && isfinite(double(nrePerPRB)) && double(nrePerPRB) > 0
                            sixgr.l2.mac.schedulerCache('set', 'NRE', nreKey, double(nrePerPRB));
                        end
                    catch ME
                        error("sixgr:SchedulerBase:ExactResourceAccountingFailed", ...
                            "Exact %s resource accounting failed for TBS sizing: %s", ...
                            upper(char(obj.Direction)), ME.message);
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
                            [double(tbsBits), double(tbsBytes), double(nrePerPRB), double(logical(info.UsedFastNREApprox))]);
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
                    [double(tbsBits), double(tbsBytes), double(nrePerPRB), double(logical(info.UsedFastNREApprox))]);
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
            xOverhead = localResolveTBSXOverhead(obj.Direction, obj.Cfg, symAlloc);
            if localAMCBlocksGrant(amc)
                rawBits = 0;
                rawBytes = 0;
                rawNRE = NaN;
            else
                [rawBits, rawBytes, rawNRE] = obj.estimateTBS(modStr, nLayers, numel(prbSet), symAlloc, targetCodeRate, ...
                    "PlanningOnly", logical(opt.PlanningOnly), ...
                    "ForceExact", ~logical(opt.PlanningOnly));
            end

            plan = struct( ...
                "Valid", false, ...
                "PRBSet", double(prbSet(:).'), ...
                "Modulation", char(string(modStr)), ...
                "NumLayers", double(nLayers), ...
                "Layers", double(nLayers), ...
                "RI", double(nLayers), ...
                "RIUsed", double(nLayers), ...
                "Rank", double(nLayers), ...
                "RankIndicator", double(nLayers), ...
                "TargetCodeRate", double(targetCodeRate), ...
                "MCSIndex", double(amc.MCSIndex), ...
                "MCSTable", char(string(amc.MCSTable)), ...
                "CQITable", char(string(amc.CQITable)), ...
                "CQIUsed", double(sixgr.util.structGet(amc, "CQIUsed", NaN)), ...
                "RawCQIDerivedMCS", double(sixgr.util.structGet(amc, "RawCQIDerivedMCS", NaN)), ...
                "CQIBasedMCS", double(sixgr.util.structGet(amc, "CQIBasedMCS", NaN)), ...
                "SmoothedCQI", double(sixgr.util.structGet(amc, "SmoothedCQI", NaN)), ...
                "InstantaneousCQIMCS", double(sixgr.util.structGet(amc, "InstantaneousCQIMCS", NaN)), ...
                "DeltaMCS", double(sixgr.util.structGet(amc, "DeltaMCS", NaN)), ...
                "StaticDeltaMCS", double(sixgr.util.structGet(amc, "StaticDeltaMCS", 0)), ...
                "AMCMode", char(string(amc.Mode)), ...
                "InnerLoopEnabled", logical(sixgr.util.structGet(amc, "InnerLoopEnabled", false)), ...
                "InnerLoopApplied", logical(sixgr.util.structGet(amc, "InnerLoopApplied", false)), ...
                "OuterLoopEnabled", logical(sixgr.util.structGet(amc, "OuterLoopEnabled", false)), ...
                "OuterLoopApplied", logical(sixgr.util.structGet(amc, "OuterLoopApplied", false)), ...
                "OLLADeltaDb", double(sixgr.util.structGet(amc, "OLLADeltaDb", sixgr.util.structGet(amc, "OLLADeltaMCS", 0))), ...
                "OLLADeltaMCS", double(sixgr.util.structGet(amc, "OLLADeltaMCS", 0)), ...
                "OLLAMarginMinDb", double(sixgr.util.structGet(amc, "OLLAMarginMinDb", NaN)), ...
                "OLLAMarginMaxDb", double(sixgr.util.structGet(amc, "OLLAMarginMaxDb", NaN)), ...
                "OLLAAdjustedMCSBeforeCQICeiling", double(sixgr.util.structGet(amc, "OLLAAdjustedMCSBeforeCQICeiling", NaN)), ...
                "OLLABaseRequiredSINR_dB", double(sixgr.util.structGet(amc, "OLLABaseRequiredSINR_dB", NaN)), ...
                "OLLATargetRequiredSINR_dB", double(sixgr.util.structGet(amc, "OLLATargetRequiredSINR_dB", NaN)), ...
                "OLLAThresholdSource", char(string(sixgr.util.structGet(amc, "OLLAThresholdSource", ""))), ...
                "OLLAUpdateCount", double(sixgr.util.structGet(amc, "OLLAUpdateCount", 0)), ...
                "OLLAStateAuthority", char(string(sixgr.util.structGet(amc, ...
                    "OLLAStateAuthority", "scheduler_local_state"))), ...
                "OLLAState", char(string(sixgr.util.structGet(amc, "OLLAState", ""))), ...
                "MCSSelectionSource", char(string(sixgr.util.structGet(amc, "MCSSelectionSource", ""))), ...
                "CQIProvenance", char(string(sixgr.util.structGet(amc, "CQIProvenance", ""))), ...
                "MCSValueStatus", char(string(sixgr.util.structGet(amc, "MCSValueStatus", ""))), ...
                "ConfiguredInitialMCSIndex", double(sixgr.util.structGet(amc, "ConfiguredInitialMCSIndex", NaN)), ...
                "ConfiguredMaximumMCSIndex", double(sixgr.util.structGet(amc, "ConfiguredMaximumMCSIndex", NaN)), ...
                "MaximumMCSBoundApplied", logical(sixgr.util.structGet(amc, "MaximumMCSBoundApplied", false)), ...
                "CausalFeedbackUsable", logical(sixgr.util.structGet(amc, "CausalFeedbackUsable", true)), ...
                "CausalFeedbackStatus", char(string(sixgr.util.structGet(amc, "CausalFeedbackStatus", ""))), ...
                "FeedbackAgeSlots", double(sixgr.util.structGet(amc, "FeedbackAgeSlots", NaN)), ...
                "FeedbackAgeSeconds", double(sixgr.util.structGet(amc, "FeedbackAgeSeconds", NaN)), ...
                "CalibrationProfile", char(string(sixgr.util.structGet(amc, "CalibrationProfile", ""))), ...
                "SchedulerCQIRawCQI", double(sixgr.util.structGet(amc, "SchedulerCQIRawCQI", NaN)), ...
                "SchedulerAdjustedSINR_dB", double(sixgr.util.structGet(amc, "SchedulerAdjustedSINR_dB", NaN)), ...
                "SchedulerSINRBackoff_dB", double(sixgr.util.structGet(amc, "SchedulerSINRBackoff_dB", NaN)), ...
                "SchedulerCQISource", char(string(sixgr.util.structGet(amc, "SchedulerCQISource", ""))), ...
                "RankSelectionPolicy", char(string(sixgr.util.structGet(amc, "RankSelectionPolicy", ""))), ...
                "RankSelectionSource", char(string(sixgr.util.structGet(amc, "RankSelectionSource", ""))), ...
                "RankDecisionReason", char(string(sixgr.util.structGet(amc, "RankDecisionReason", ""))), ...
                "RankDowngradeApplied", logical(sixgr.util.structGet(amc, "RankDowngradeApplied", false)), ...
                "MaxSupportedLayers", double(sixgr.util.structGet(amc, "MaxSupportedLayers", NaN)), ...
                "GrantBlocker", char(localAMCBlockerReason(amc)), ...
                "NREPerPRB", double(rawNRE), ...
                "XOverhead", double(xOverhead), ...
                "TBSInputModulation", char(string(modStr)), ...
                "TBSInputNumLayers", double(nLayers), ...
                "TBSInputNPRB", double(numel(prbSet)), ...
                "TBSInputNREPerPRB", double(rawNRE), ...
                "TBSInputTargetCodeRate", double(targetCodeRate), ...
                "TBSInputXOverhead", double(xOverhead), ...
                "TBSInputSource", "scheduler_exact_allocation_resource_accounting", ...
                "TBSBits", double(rawBits), ...
                "TBSBytes", double(rawBytes), ...
                "RawEstimatedTBSBits", double(rawBits), ...
                "RawEstimatedTBSBytes", double(rawBytes), ...
                "QueueLimited", false, ...
                "QueuePaddingBits", 0, ...
                "QueuePaddingBytes", 0, ...
                "InitialMCSIndex", double(amc.MCSIndex), ...
                "InitialNumLayers", double(nLayers), ...
                "PlanningOnlyApproximation", logical(opt.PlanningOnly), ...
                "QueueAwareReductionEnabled", logical(localQueueAwareRankMCSReductionEnabled(obj.Cfg)), ...
                "QueueAwareReductionApplied", false, ...
                "QueueAwareReductionSource", "", ...
                "MCSReductionSteps", 0, ...
                "LayerReductionSteps", 0);

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
                plan.PlanningOnlyApproximation = true;
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
            plan.Layers = double(best.NumLayers);
            plan.RI = double(best.NumLayers);
            plan.RIUsed = double(best.NumLayers);
            plan.Rank = double(best.NumLayers);
            plan.RankIndicator = double(best.NumLayers);
            plan.TargetCodeRate = double(best.TargetCodeRate);
            plan.MCSIndex = double(best.MCSIndex);
            plan.CQIUsed = double(sixgr.util.structGet(amc, "CQIUsed", plan.CQIUsed));
            plan.RawCQIDerivedMCS = double(sixgr.util.structGet(amc, "RawCQIDerivedMCS", plan.RawCQIDerivedMCS));
            plan.CQIBasedMCS = double(sixgr.util.structGet(amc, "CQIBasedMCS", plan.CQIBasedMCS));
            plan.SmoothedCQI = double(sixgr.util.structGet(amc, "SmoothedCQI", plan.SmoothedCQI));
            plan.InstantaneousCQIMCS = double(sixgr.util.structGet(amc, "InstantaneousCQIMCS", plan.InstantaneousCQIMCS));
            plan.DeltaMCS = double(sixgr.util.structGet(amc, "DeltaMCS", plan.DeltaMCS));
            plan.StaticDeltaMCS = double(sixgr.util.structGet(amc, "StaticDeltaMCS", plan.StaticDeltaMCS));
            plan.NREPerPRB = double(best.NREPerPRB);
            plan.XOverhead = double(sixgr.util.structGet(best, "XOverhead", xOverhead));
            plan.TBSInputModulation = char(string(best.Modulation));
            plan.TBSInputNumLayers = double(best.NumLayers);
            plan.TBSInputNPRB = double(numel(plan.PRBSet));
            plan.TBSInputNREPerPRB = double(best.NREPerPRB);
            plan.TBSInputTargetCodeRate = double(best.TargetCodeRate);
            plan.TBSInputXOverhead = double(plan.XOverhead);
            plan.TBSBits = double(best.TBSBits);
            plan.TBSBytes = double(best.TBSBytes);
            plan.QueueLimited = true;
            plan.QueuePaddingBits = double(sixgr.util.structGet(best, "QueuePaddingBits", 0));
            plan.QueuePaddingBytes = double(sixgr.util.structGet(best, "QueuePaddingBytes", 0));
            plan.InitialMCSIndex = double(sixgr.util.structGet(best, "InitialMCSIndex", plan.InitialMCSIndex));
            plan.InitialNumLayers = double(sixgr.util.structGet(best, "InitialNumLayers", plan.InitialNumLayers));
            plan.QueueAwareReductionEnabled = logical(sixgr.util.structGet(best, "QueueAwareReductionEnabled", plan.QueueAwareReductionEnabled));
            plan.QueueAwareReductionApplied = logical(sixgr.util.structGet(best, "QueueAwareReductionApplied", false));
            plan.QueueAwareReductionSource = char(string(sixgr.util.structGet(best, "QueueAwareReductionSource", "")));
            plan.MCSReductionSteps = double(sixgr.util.structGet(best, "MCSReductionSteps", 0));
            plan.LayerReductionSteps = double(sixgr.util.structGet(best, "LayerReductionSteps", 0));
        end

        function metric = pfMetric(obj, ue, tbsBits)
            % PF metric = instRate / avgRate.
            i = obj.ensureUE(double(ue.RNTI));
            avg = double(obj.UEStats(i).AvgThroughput_bps);
            inst = double(tbsBits) / max(obj.SlotDuration_s, eps);
            metric = inst / max(avg, 1);
        end

        function [available,evidence] = ssbSafePRBSet(obj,slot,budget,available,symAlloc,grant)
            % Derive common-DL exclusions for this actual data occasion.
            % Connected-mode PDSCH is emitted as a separate waveform on the
            % shared stream, so overlapping SSB, Type-0/SIB1 or TRS REs must
            % be excluded before DCI/TBS freezing.  Treating that overlap as
            % harmless rate matching would be incorrect: no rate-matching
            % pattern is signalled to either independently coded PDSCH.
            evidence = table();
            commonEnabled = logical(sixgr.util.structGet(obj.Cfg,"phy.ssb.enable",false)) || ...
                logical(sixgr.util.structGet(obj.Cfg,"phy.sib1.enable",false)) || ...
                logical(sixgr.util.structGet(obj.Cfg,"phy.trs.enable",false));
            if upper(string(obj.Direction))~="DL" || ~commonEnabled
                return;
            end
            if nargin<6, grant=struct(); end
            probe=grant;
            probe.Direction='DL'; probe.Slot=slot;
            probe.SymbolAllocation=symAlloc;
            probe=sixgr.l2.mac.rebindHARQRetransmissionTiming(probe);
            probe.ControlAbsoluteSlot=slot;
            if isfield(budget,'ControlAbsoluteSlot')
                probe.ControlAbsoluteSlot=budget.ControlAbsoluteSlot;
            end
            if isfield(budget,'ControlSymbolAllocation')
                probe.ControlSymbolAllocation=budget.ControlSymbolAllocation;
            end
            timing=sixgr.phy.frame.TimingRelationEngine.resolveProductionGrant(obj.Cfg,probe);
            assert(timing.Valid,'sixgr:SchedulerBase:TimingDecisionRejected', ...
                'SSB resource selection requires legal canonical timing: %s',timing.Diagnostic);
            actual=sixgr.phy.grid.applyRuntimeCarrierTimeline(obj.Cfg,double(timing.DataAbsoluteSlot)+1);
            before=double(available(:).');
            if isempty(before), return; end
            plan=sixgr.phy.frame.CommonDLResourcePlan(actual);
            excluded=zeros(1,0); owners=strings(0,1);
            for prb=before
                allocation=struct('PRBStart',double(prb),'NumPRB',1, ...
                    'SymbolStart',double(symAlloc(1)),'NumSymbols',double(symAlloc(2)));
                [free,conflict]=plan.checkPDSCH(allocation,double(timing.DataAbsoluteSlot));
                if ~free
                    excluded(end+1)=prb; %#ok<AGROW>
                    owners=[owners;string(conflict.ConflictingOwners(:))]; %#ok<AGROW>
                end
            end
            if isempty(excluded), return; end
            available=setdiff(before,unique(excluded,'stable'),'stable');
            owners=unique(owners,'stable');
            reason="common_dl_resource_frequency_exclusion:" + strjoin(owners,"|");
            evidence=table(double(slot),double(timing.ControlAbsoluteSlot), ...
                double(timing.DataAbsoluteSlot),string(obj.Direction), ...
                string(jsonencode(before)),string(jsonencode(excluded)), ...
                string(jsonencode(available)),reason, ...
                'VariableNames',{'Slot','ControlAbsoluteSlot0','DataAbsoluteSlot0', ...
                'Direction','InputPRBSetJSON','ExcludedPRBSetJSON','AvailablePRBSetJSON','Reason'});
        end

        function grantOut = freezePHYGrantForGrant(obj, grantIn)
            % Freeze the final scheduler grant dimensional contract once.
            grantOut = grantIn;
            if nargin < 2 || ~(isstruct(grantOut) && ~isempty(fieldnames(grantOut)))
                return;
            end
            if ~isfield(grantOut, "Direction") || strlength(string(grantOut.Direction)) == 0
                grantOut.Direction = obj.Direction;
            end
            % A DL DCI owns the PUCCH resource indicator used by the UE for
            % HARQ-ACK.  Resolve it before DCI packing and before the grant
            % is frozen so the exact value survives the complete
            % scheduler -> PDCCH -> PDSCH -> HARQ -> PUCCH causal chain.
            grantOut = obj.attachPUCCHResourceAuthorityToGrant(grantOut);
            % A retransmission preserves the TB, coding, allocation shape,
            % and HARQ process, but it is a new transmission occasion.  K0,
            % K1/K2 and their absolute-slot results belong to the previous
            % control occasion and must be selected again from the attached
            % YAML timing catalog.  Retaining an old explicit K1 can point a
            % later retransmission at a fixed DL slot in TDD even when another
            % configured K1 candidate is valid.
            grantOut = sixgr.l2.mac.rebindHARQRetransmissionTiming(grantOut);
            grantOut = obj.attachCanonicalTimingDecision(grantOut);
            grantOut = obj.finalizeExactPHYFeasibility(grantOut);
            if ~logical(sixgr.util.structGet(grantOut,"ExactPHYFeasible",false))
                % A rejected allocation must not acquire a frozen PHY contract.
                grantOut.PHYGrant = struct();
                grantOut.PHYGrantContextId = "";
                return;
            end
            cfgForFreeze = obj.Cfg;
            priorPHYGrant = sixgr.util.structGet(grantOut, "PHYGrant", struct());
            isRetransmission = logical(sixgr.util.structGet(grantOut, ...
                "IsRetransmission", sixgr.util.structGet(grantOut, ...
                "HARQ.IsRetransmission", false)));
            currentSharedMU = logical(sixgr.util.structGet(grantOut, ...
                "MUMIMOEnabled", false)) && ...
                double(sixgr.util.structGet(grantOut, "MUMIMOGroupSize", 0)) >= 2;
            if upper(string(grantOut.Direction)) == "DL" && ...
                    isRetransmission && ~currentSharedMU && ...
                    isstruct(priorPHYGrant) && ~isempty(fieldnames(priorPHYGrant)) && ...
                    logical(sixgr.util.structGet(priorPHYGrant, "IsFrozen", false))
                % The scheduler refreezes current-slot control/timing, but
                % an orthogonal HARQ replay retains the first transmission's
                % immutable spatial architecture. Project that frozen grant
                % into a replay-only config before removing the recursive
                % PHYGrant field. This is the same authority boundary used
                % by CoupledTruthRuntime at execution time.
                sixgr.phy.grant.assertPHYGrantDimensions( ...
                    priorPHYGrant, "scheduler_harq_replay_refreeze");
                cfgForFreeze = sixgr.phy.grant.applyPHYGrantToConfig( ...
                    cfgForFreeze, priorPHYGrant);
            end
            grantSeed = grantOut;
            if isfield(grantSeed, "PHYGrant")
                grantSeed = rmfield(grantSeed, "PHYGrant");
            end
            if upper(string(grantOut.Direction)) == "DL" && ...
                    isfield(grantOut, "PMI") && ...
                    ~(isnumeric(grantOut.PMI) && isscalar(grantOut.PMI) && ...
                    isfinite(grantOut.PMI))
                % The finalized scheduler grant owns whether PMI was
                % actually selected.  In an adaptive bootstrap interval a
                % configured study default must not leak back in after the
                % causal feedback path explicitly reports PMI unavailable.
                cfgForFreeze = sixgr.util.structSet( ...
                    cfgForFreeze, "phy.pdsch.PMI", NaN);
                cfgForFreeze = sixgr.util.structSet( ...
                    cfgForFreeze, "phy.pdsch.pmi", NaN);
            end
            phyGrant = sixgr.phy.grant.freezePHYGrant(cfgForFreeze, grantOut.Direction, grantSeed, ...
                "Slot", double(sixgr.util.structGet(grantOut, "Slot", NaN)), ...
                "Frame", double(sixgr.util.structGet(grantOut, "Frame", sixgr.util.structGet(grantOut, "Slot", NaN))), ...
                "HARQContext", sixgr.util.structGet(grantOut, "HARQ", struct()));
            if upper(string(grantOut.Direction)) == "DL" && ...
                    logical(sixgr.util.structGet(grantOut, "MUMIMOEnabled", false))
                frozenW = double(sixgr.util.structGet(phyGrant, ...
                    "PrecodingState.MatrixPhysicalPorts", []));
                nLayers = double(sixgr.util.structGet(phyGrant, ...
                    "AntennaArchitecture.NumLayers", NaN));
                sixgr.phy.mimo.MatrixContract.validate( ...
                    frozenW, size(frozenW,1), nLayers);
            end
            grantOut.PHYGrant = phyGrant;
            grantOut.PHYGrantContextId = char(string(phyGrant.GrantContextId));
            grantOut.DMRSPortSet = double(phyGrant.CodingLayout.DMRSPortSet(:).');
            grantOut.DMRSPortSetSource = char(string( ...
                phyGrant.CodingLayout.DMRSPortSetSource));
            grantOut.PTRSEnabled = logical(phyGrant.CodingLayout.PTRSEnabled);
            grantOut.PTRSPortSet = double(phyGrant.CodingLayout.PTRSPortSet(:).');
            grantOut.PTRSPortSetSource = char(string( ...
                phyGrant.CodingLayout.PTRSPortSetSource));
        end

        function grantOut = attachULSRSAuthorityToGrant(obj, grantIn, ueState)
            % Bind the causal measured-SRS identity before a strict UL grant
            % is frozen.  This method copies runtime evidence only; it never
            % manufactures a measurement identity or upgrades unusable SRS.
            grantOut = grantIn;
            if upper(string(obj.Direction)) ~= "UL"
                return;
            end
            if nargin < 3 || ~(isstruct(ueState) && isscalar(ueState))
                error("sixgr:l2:mac:MissingULSchedulerUEState", ...
                    "UL grant freezing requires the scheduler UE state that owns the causal SRS evidence.");
            end
            grantOut.SRSValid = logical(sixgr.util.structGet( ...
                ueState, "SRSValid", false));
            grantOut.SRSCausalUsable = logical(sixgr.util.structGet( ...
                ueState, "SRSCausalUsable", false));
            grantOut.SRSCausalMeasurementId = char(string(sixgr.util.structGet( ...
                ueState, "SRSCausalMeasurementId", "")));
            grantOut.LastSuccessfulSRSSlot = double(sixgr.util.structGet( ...
                ueState, "LastSuccessfulSRSSlot", NaN));
            grantOut.SRSAgeSlots = double(sixgr.util.structGet( ...
                ueState, "SRSAgeSlots", NaN));
            grantOut.SRSCausalAgeSlots = double(sixgr.util.structGet( ...
                ueState, "SRSCausalAgeSlots", NaN));
            grantOut.SRSCausalStatus = char(string(sixgr.util.structGet( ...
                ueState, "SRSCausalStatus", "")));
            grantOut.SRSMeasurementAuthoritySource = ...
                "scheduler_ue_state_causal_srs";
            tpmi = double(sixgr.util.structGet(ueState, "TPMI", ...
                sixgr.util.structGet(ueState, "PMI", NaN)));
            if isscalar(tpmi) && isfinite(tpmi)
                grantOut.TPMI = double(round(tpmi));
                grantOut.PMI = double(round(tpmi));
            end
            sri = double(sixgr.util.structGet(ueState, "SRI", NaN));
            if isscalar(sri) && isfinite(sri)
                grantOut.SRI = double(round(sri));
                grantOut.SRSResourceIndicator = double(round(sri));
            end
        end

        function grantOut = attachPUCCHResourceAuthorityToGrant(obj, grantIn)
            % Bind a YAML-authorized PUCCH PRI to every DL scheduling grant.
            % The mapping policy is a scheduler policy (not a PHY proxy):
            % 38.212/38.213 define how the DCI PRI selects a configured
            % resource, while the gNB is responsible for choosing that PRI.
            grantOut = grantIn;
            if upper(string(sixgr.util.structGet(grantOut, "Direction", obj.Direction))) ~= "DL"
                return;
            end
            section = sixgr.util.structGet(obj.Cfg, "validation.pucch_resources", struct());
            if ~(isstruct(section) && logical(sixgr.util.structGet(section, "enabled", false)))
                return;
            end
            explicitPRI = double(sixgr.util.structGet(grantOut, "PUCCHResourceIndicator", NaN));
            authority = sixgr.phy.pucch.resolveConfiguredPRI(obj.Cfg, ...
                double(sixgr.util.structGet(grantOut, "UEIndex", NaN)), ...
                double(sixgr.util.structGet(grantOut, "RNTI", NaN)), ...
                explicitPRI);
            grantOut.PUCCHResourceIndicator = authority.PRIValue;
            grantOut.PUCCHResourceSetId = authority.ResourceSetId;
            grantOut.PUCCHResourceId = authority.ResourceId;
            grantOut.PUCCHResourceIndicatorSource = authority.Source;
            grantOut.PUCCHResourceAuthority = authority.Authority;
        end

        function grantOut = attachCanonicalTimingDecision(obj, grantIn)
            % Attach the authoritative CC/BWP-aware K0/K1/K2 decision.
            grantOut = grantIn;
            timingGrant=grantOut;
            if upper(string(sixgr.util.structGet(grantOut,'Direction',obj.Direction)))=="UL"
                % Timing now depends on the first-symbol DM-RS/data mapping.
                % Resolve the same scheduler mapping policy before N2, not
                % only afterwards during exact TBS/resource finalization.
                mapping=localFinalizeGrantMappingType(obj.Cfg,'UL',grantOut, ...
                    sixgr.util.structGet(grantOut,'SymbolAllocation',[]));
                timingGrant.MappingType=char(mapping.MappingType);
            end
            timing = sixgr.phy.frame.TimingRelationEngine. ...
                resolveProductionGrant(obj.Cfg, timingGrant);
            grantOut.TimingDecision = timing;
            grantOut.SchedulingCCID = timing.SchedulingCCID;
            grantOut.ScheduledCCID = timing.ScheduledCCID;
            grantOut.CarrierIndicator = timing.CarrierIndicator;
            grantOut.SourceBWPID = timing.SourceBWPID;
            grantOut.TargetBWPID = timing.TargetBWPID;
            grantOut.BWPId = localNumericIdentifierOrNaN( ...
                timing.TargetBWPID);
            grantOut.K0 = timing.K0;
            grantOut.K1 = timing.K1;
            grantOut.K2 = timing.K2;
            grantOut.ControlAbsoluteSlot = ...
                double(timing.ControlAbsoluteSlot);
            grantOut.ScheduledAbsoluteSlot = ...
                double(timing.DataAbsoluteSlot);
            grantOut.HARQFeedbackAbsoluteSlot = ...
                double(timing.FeedbackAbsoluteSlot);
            if ~timing.Valid
                grantOut.Valid = false;
                grantOut.GrantBlocker = char(timing.ReasonCode);
                error("sixgr:SchedulerBase:TimingDecisionRejected", ...
                    "Canonical production timing rejected the grant: %s (%s)", ...
                    char(string(timing.ReasonCode)), ...
                        char(string(timing.Diagnostic)));
            end
            if isfield(grantOut,'SharedULTimingContext') && ...
                    ~isempty(fieldnames(grantOut.SharedULTimingContext))
                grantOut.ReceivedULTimingValidation=sixgr.l2.mac.validateGrantReceivedULTiming( ...
                    obj.Cfg,grantOut,timing);
            end
        end

        function grantOut = finalizeExactPHYFeasibility(obj, grantIn)
            %finalizeExactPHYFeasibility Stamp executable grant sizing before DCI/TX.
            grantOut = grantIn;
            if nargin < 2 || ~(isstruct(grantOut) && ~isempty(fieldnames(grantOut)))
                return;
            end
            if ~isfield(grantOut, "Direction") || strlength(string(grantOut.Direction)) == 0
                grantOut.Direction = obj.Direction;
            end

            [ok, reason] = localValidateGrantResourceIntent(obj, grantOut);
            if ok
                try
                    sixgr.phy.grant.assertGrantTimingIdentity(grantOut,obj.Direction);
                catch cause
                    if ~strcmp(cause.identifier,'sixgr:phy:grant:TimingIdentityMismatch')
                        rethrow(cause);
                    end
                    ok=false;
                    reason=string(cause.message);
                end
            end
            grantOut.ExactPHYFeasibilityChecked = true;
            grantOut.ExactPHYFeasible = logical(ok);
            grantOut.ExactPHYFeasibilitySource = "SchedulerBase.finalizeExactPHYFeasibility";
            grantOut.ExecutableTBSMode = "faithful_exact_resource_accounting";
            grantOut.ExactPHYInfeasibilityReason = char(reason);
            if ~ok
                grantOut.Valid = false;
                grantOut.GrantBlocker = char(reason);
                return;
            end

            prbSet = double(sixgr.util.structGet(grantOut, "PRBSet", []));
            if isempty(prbSet)
                prbStart = double(sixgr.util.structGet(grantOut, "PRBStart", NaN));
                prbCount = double(sixgr.util.structGet(grantOut, "AllocatedPRBCount", ...
                    sixgr.util.structGet(grantOut, "PRBCount", NaN)));
                if isfinite(prbStart) && isfinite(prbCount) && prbCount >= 1
                    prbSet = round(prbStart):(round(prbStart) + round(prbCount) - 1);
                end
            end
            prbSet = double(prbSet(:).');
            symAlloc = double(sixgr.util.structGet( ...
                grantOut, "SymbolAllocation", []));
            symAlloc = double(symAlloc(:).');
            if numel(symAlloc) < 2
                error("sixgr:SchedulerBase:MissingSymbolAllocation", ...
                    "Final PHY grant requires an explicit SymbolAllocation.");
            end
            symAlloc = round(symAlloc(1:2));

            modStr = char(string(sixgr.util.structGet(grantOut, "Modulation", ...
                sixgr.util.structGet(obj.Cfg, localPHYRoot(grantOut.Direction) + ".modulation", "QPSK"))));
            nLayers = double(sixgr.util.structGet(grantOut, "NumLayers", ...
                sixgr.util.structGet(grantOut, "Layers", 1)));
            nLayers = max(1, round(nLayers));
            targetCodeRate = double(sixgr.util.structGet(grantOut, "TargetCodeRate", ...
                sixgr.util.structGet(obj.Cfg, localPHYRoot(grantOut.Direction) + ".codeRate", NaN)));
            if ~(isscalar(targetCodeRate) && isfinite(targetCodeRate) && targetCodeRate > 0)
                mcsTable = char(string(sixgr.util.structGet(grantOut, "MCSTable", obj.resolveMCSTable())));
                mcsIndex = double(sixgr.util.structGet(grantOut, "MCSIndex", sixgr.util.structGet(grantOut, "MCS", NaN)));
                if isfinite(mcsIndex)
                    profile = sixgr.link.resolveMCSProfile(mcsTable, mcsIndex);
                    if logical(sixgr.util.structGet(profile, "Valid", false))
                        modStr = char(string(profile.Modulation));
                        targetCodeRate = double(profile.TargetCodeRate);
                    end
                end
            end
            cqiUsed = double(sixgr.util.structGet(grantOut, "CQIUsed", NaN));
            amcMode = lower(strtrim(string(sixgr.util.structGet(grantOut, "AMCMode", ""))));
            mcsSource = lower(strtrim(string(sixgr.util.structGet(grantOut, "MCSSelectionSource", ...
                sixgr.util.structGet(grantOut, "MCSIndexAuthority", "")))));
            cqiDrivenGrant = isfinite(cqiUsed) && cqiUsed > 0 && ...
                (amcMode == "cqi_table" || contains(mcsSource, "cqi") || contains(mcsSource, "measured"));
            if cqiDrivenGrant
                [cqiModStr, cqiTargetCodeRate, cqiMCSIndex] = sixgr.link.amcFromCQI(cqiUsed, "", NaN, obj.Cfg, grantOut.Direction);
                if isfinite(cqiMCSIndex) && cqiMCSIndex >= 0 && ...
                        isfinite(cqiTargetCodeRate) && cqiTargetCodeRate > 0 && strlength(string(cqiModStr)) > 0
                    grantOut.RawCQIDerivedMCS = double(cqiMCSIndex);
                    if ~isfinite(double(sixgr.util.structGet(grantOut, "InstantaneousCQIMCS", NaN)))
                        grantOut.InstantaneousCQIMCS = double(cqiMCSIndex);
                    end
                    mcsIndex = double(sixgr.util.structGet(grantOut, "MCSIndex", sixgr.util.structGet(grantOut, "MCS", NaN)));
                    if isfinite(mcsIndex) && round(double(mcsIndex)) > round(double(cqiMCSIndex))
                        grantOut.MCSIndex = double(round(cqiMCSIndex));
                        grantOut.MCS = double(round(cqiMCSIndex));
                        grantOut.Modulation = char(string(cqiModStr));
                        grantOut.TargetCodeRate = double(cqiTargetCodeRate);
                        grantOut.MCSValueStatus = "clamped_to_cqi_max";
                        modStr = char(string(cqiModStr));
                        targetCodeRate = double(cqiTargetCodeRate);
                    end
                end
            end

            mappingDecision = localFinalizeGrantMappingType(obj.Cfg, grantOut.Direction, grantOut, symAlloc);
            grantOut.MappingType = char(mappingDecision.MappingType);
            grantOut.MappingTypeSelectionSource = char(mappingDecision.Source);
            grantOut.MappingTypeSelectionReason = char(mappingDecision.Reason);
            cfgExact = localApplyGrantMappingTypeToCfg(obj.Cfg, grantOut.Direction, mappingDecision.MappingType);
            % Exact TBS/NRE accounting must use the same scheduled DM-RS and
            % PT-RS port association that will be frozen into the PHY grant.
            % Reading only the cell-wide config here loses disjoint MU-MIMO
            % ports and makes a YAML-enabled PT-RS grant appear infeasible
            % before freezePHYGrant can bind its configured association
            % policy.  Resolve once from YAML + the actual scheduler grant,
            % then project that exact resource contract into the accounting
            % config used by allocREsPDSCH/allocREsPUSCH.
            [scheduledDMRSPorts, scheduledDMRSSource] = ...
                sixgr.phy.grant.resolveScheduledDMRSPortSet( ...
                obj.Cfg, grantOut.Direction, nLayers, grantOut);
            [scheduledPTRSEnabled, scheduledPTRSPorts, scheduledPTRSSource] = ...
                sixgr.phy.grant.resolveScheduledPTRSPortSet( ...
                obj.Cfg, grantOut.Direction, scheduledDMRSPorts, grantOut);
            resourceRoot = localPHYRoot(grantOut.Direction);
            cfgExact = sixgr.util.structSet(cfgExact, ...
                resourceRoot + ".dmrs.portSet", double(scheduledDMRSPorts(:).'));
            cfgExact = sixgr.util.structSet(cfgExact, ...
                resourceRoot + ".dmrs.DMRSPortSet", double(scheduledDMRSPorts(:).'));
            cfgExact = sixgr.util.structSet(cfgExact, ...
                resourceRoot + ".enablePTRS", logical(scheduledPTRSEnabled));
            cfgExact = sixgr.util.structSet(cfgExact, ...
                resourceRoot + ".ptrs.portSet", double(scheduledPTRSPorts(:).'));
            grantOut.DMRSPortSet = double(scheduledDMRSPorts(:).');
            grantOut.DMRSPortSetSource = char(string(scheduledDMRSSource));
            grantOut.PTRSEnabled = logical(scheduledPTRSEnabled);
            grantOut.PTRSPortSet = double(scheduledPTRSPorts(:).');
            grantOut.PTRSPortSetSource = char(string(scheduledPTRSSource));
            try
                [exactBits, exactBytes, exactNRE, exactInfo] = obj.estimateTBS(modStr, nLayers, numel(prbSet), symAlloc, targetCodeRate, ...
                    "PlanningOnly", false, "ForceExact", true, "ConfigOverride", cfgExact);
                % Nominal TBS sizing cannot validate current-slot ownership:
                % its cache uses a PRB count, not the actual frequency/time
                % allocation. Bind the canonical DATA clock (not the DCI
                % slot) and separately resolve the actual rate-matched G.
                dataSlot0 = double(sixgr.util.structGet( ...
                    grantOut,"ScheduledAbsoluteSlot",NaN));
                validateattributes(dataSlot0,{'numeric'}, ...
                    {'scalar','finite','integer','nonnegative'});
                cfgActual = sixgr.phy.grid.applyRuntimeCarrierTimeline( ...
                    cfgExact,dataSlot0+1);
                actualCarrier = sixgr.phy.grid.makeCarrier(cfgActual);
                actualArgs = {"PRBSet",prbSet,"SymbolAllocation",symAlloc, ...
                    "Modulation",modStr,"NumLayers",nLayers, ...
                    "RNTI",double(grantOut.RNTI)};
                if upper(string(grantOut.Direction)) == "DL"
                    [~,actualInfo] = sixgr.phy.grid.allocREsPDSCH( ...
                        actualCarrier,cfgActual,actualArgs{:});
                else
                    [~,actualInfo,actualPUSCH] = sixgr.phy.grid.allocREsPUSCH( ...
                        actualCarrier,cfgActual,actualArgs{:});
                    timing=sixgr.util.structGet(grantOut,'TimingDecision.DataDecision',struct());
                    if isfield(timing,'ProcessingBudget')
                        finalBudget=sixgr.phy.frame.puschPreparationProcessingTime( ...
                            actualCarrier,actualPUSCH,[timing.SourceMu,timing.TargetMu]);
                        assert(finalBudget.Ticks==timing.MinimumProcessingTicks && ...
                            finalBudget.D21Symbols==timing.ProcessingBudget.D21Symbols, ...
                            'sixgr:SchedulerBase:PUSCHProcessingAllocationChanged', ...
                            'Final PUSCH allocation changed the preparation budget after canonical timing selection.');
                    end
                end
                assert(actualInfo.NREPerPRB == exactNRE, ...
                    'sixgr:SchedulerBase:NominalNREMismatch', ...
                    'Actual allocation and nominal TBS must agree on 38.214 N_RE.');
                assert(actualInfo.G > 0, ...
                    'sixgr:SchedulerBase:EmptyRateMatchedAllocation', ...
                    'The actual scheduled allocation has no coded data capacity.');
                grantOut.ExactAllocationCodedBitsG = double(actualInfo.G);
                grantOut.ExactAllocationDataRE = double(actualInfo.NRE);
                grantOut.ExactAllocationReservedRE = double(actualInfo.ReservedRE);
                grantOut.ExactAllocationAbsoluteSlot0 = dataSlot0;
                grantOut.ExactAllocationSource = "scheduled_prb_symbol_reference_ownership";
            catch ME
                grantOut.Valid = false;
                grantOut.ExactPHYFeasible = false;
                grantOut.ExactPHYInfeasibilityReason = char("exact_resource_accounting_failed:" + string(ME.message));
                grantOut.GrantBlocker = grantOut.ExactPHYInfeasibilityReason;
                return;
            end
            if ~(isfinite(double(exactBits)) && double(exactBits) > 0 && isfinite(double(exactBytes)) && double(exactBytes) > 0)
                grantOut.Valid = false;
                grantOut.ExactPHYFeasible = false;
                grantOut.ExactPHYInfeasibilityReason = "zero_exact_tbs";
                grantOut.GrantBlocker = "zero_exact_tbs";
                return;
            end

            harq = sixgr.util.structGet(grantOut, "HARQ", struct());
            isRetx = sixgr.phy.grant.isExplicitHARQRetransmission( ...
                grantOut, sixgr.util.structGet(grantOut, "PHYGrant", struct()), harq);
            scheduledBits = double(exactBits);
            scheduledBytes = double(exactBytes);
            existingTBSBits = double(sixgr.util.structGet(grantOut, "TBSBits", ...
                sixgr.util.structGet(grantOut, "TransportBlockSize", NaN)));
            if isRetx && isfinite(existingTBSBits) && existingTBSBits > 0
                scheduledBits = double(existingTBSBits);
                scheduledBytes = floor(scheduledBits / 8);
            end

            grantOut.PRBSet = prbSet;
            grantOut.PRBStart = double(min(prbSet));
            grantOut.AllocatedPRBCount = double(numel(prbSet));
            grantOut.PRBCount = double(numel(prbSet));
            grantOut.SymbolAllocation = symAlloc;
            grantOut.Modulation = char(string(modStr));
            grantOut.NumLayers = double(nLayers);
            grantOut.Layers = double(nLayers);
            grantOut.RI = double(nLayers);
            grantOut.RIUsed = double(nLayers);
            grantOut.Rank = double(nLayers);
            grantOut.RankIndicator = double(nLayers);
            grantOut.TargetCodeRate = double(targetCodeRate);
            grantOut.NREPerPRB = double(exactNRE);
            grantOut.TBSInputModulation = char(string(modStr));
            grantOut.TBSInputNumLayers = double(nLayers);
            grantOut.TBSInputNPRB = double(numel(prbSet));
            grantOut.TBSInputNREPerPRB = double(exactNRE);
            grantOut.TBSInputTargetCodeRate = double(targetCodeRate);
            grantOut.TBSInputXOverhead = double(sixgr.util.structGet(exactInfo, "XOverhead", ...
                sixgr.util.structGet(grantOut, "XOverhead", 0)));
            grantOut.TBSInputSource = "scheduler_exact_allocation_resource_accounting";
            grantOut.XOverhead = double(grantOut.TBSInputXOverhead);
            grantOut.ExactAllocationCapacityBits = double(exactBits);
            grantOut.ExactAllocationCapacityBytes = double(exactBytes);
            grantOut.RetxOriginalTBSBits = NaN;
            grantOut.RetxCurrentGrantNewDataTBSBits = NaN;
            grantOut.RetxTBSPreservationMode = "";
            if isRetx
                grantOut.RetxOriginalTBSBits = double(scheduledBits);
                grantOut.RetxCurrentGrantNewDataTBSBits = double(exactBits);
                grantOut.RetxTBSPreservationMode = "harq_original_tb_size_preserved";
            end
            grantOut.ExactTBSBits = double(scheduledBits);
            grantOut.ExactTBSBytes = double(scheduledBytes);
            grantOut.ExactNREPerPRB = double(exactNRE);
            grantOut.ExactTBSUsedFastNREApprox = logical(sixgr.util.structGet(exactInfo, "UsedFastNREApprox", false));
            grantOut.ExactTBSInfo = exactInfo;
            grantOut.PlanningOnlyApproximation = false;
            grantOut.TBSBits = double(scheduledBits);
            grantOut.TBSBytes = double(scheduledBytes);
            grantOut.TransportBlockSize = double(scheduledBits);
            grantOut.Valid = logical(sixgr.util.structGet(grantOut, "Valid", true));
        end

        function dci = buildDCIBitfield(obj, grant)
            % buildDCIBitfield Build NR-style DCI intent fields for a grant.
            dci = struct("Format", "", "Bits", uint8([]), "Hex", "", ...
                "FieldMap", struct(), "FieldValues", struct(), ...
                "RIV", 0, "RBStart", 0, "RBLength", 0, ...
                "SLIV", NaN, "TimeDomainAssignmentIndex", NaN, ...
                "StandardProfile", "ts38212_semantic_field_layout", ...
                "BitExactPDCCHPayload", false, ...
                "PHYGrant", struct(), ...
                "PHYGrantContextId", "", ...
                "PHYGrantEvidenceSource", "", ...
                "FinalizedGrant", false, ...
                "ExactPHYFeasibilityChecked", false, ...
                "ExactPHYFeasible", false, ...
                "SourceGrantTBSBits", NaN, ...
                "DCIGrantContract", "");
            if nargin < 2 || isempty(grant) || ~isstruct(grant)
                return;
            end
            timingDecision = sixgr.util.structGet( ...
                grant, "TimingDecision", struct());
            if ~(isstruct(timingDecision) && isscalar(timingDecision) && ...
                    logical(sixgr.util.structGet( ...
                    timingDecision, "Valid", false)))
                error("sixgr:SchedulerBase:MissingTimingDecision", ...
                    "DCI packing requires a valid canonical TimingDecision.");
            end
            if logical(sixgr.util.structGet(grant, "ExactPHYFeasibilityChecked", false)) && ...
                    ~logical(sixgr.util.structGet(grant, "ExactPHYFeasible", false))
                error("sixgr:SchedulerBase:InfeasibleGrantDCI", ...
                    "Cannot pack DCI for an infeasible finalized PHY grant: %s", ...
                    char(string(sixgr.util.structGet(grant, "ExactPHYInfeasibilityReason", "unknown"))));
            end
            phyGrant = sixgr.util.structGet(grant, "PHYGrant", struct());
            if isstruct(phyGrant) && ~isempty(fieldnames(phyGrant))
                sixgr.phy.grant.assertPHYGrantDimensions(phyGrant, "scheduler_dci_build");
                dci.PHYGrant = phyGrant;
                dci.PHYGrantContextId = char(string(phyGrant.GrantContextId));
                dci.PHYGrantEvidenceSource = "SchedulerBase.freezePHYGrantForGrant";
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
            mcs = max(0, min(31, round(localFirstFiniteScalar( ...
                sixgr.util.structGet(grant, "MCSIndex", []), 0))));
            ndi = double(logical(localFirstFiniteScalar( ...
                sixgr.util.structGet(harq, "NDI", []), 1)));
            rv = max(0, min(3, round(localFirstFiniteScalar( ...
                sixgr.util.structGet(harq, "RV", []), 0))));
            harqId = max(0, min(15, round(localFirstFiniteScalar( ...
                sixgr.util.structGet(harq, "HarqID", []), 0))));
            dai = max(0, min(3, round(localFirstFiniteScalar( ...
                sixgr.util.structGet(grant, "DAI", []), 1))));
            direction = upper(string(sixgr.util.structGet( ...
                grant, "Direction", obj.Direction)));
            if direction == "DL"
                k1 = localRequiredDCITimingInteger(grant, "K1");
                k2 = NaN;
            else
                k1 = NaN;
                k2 = localRequiredDCITimingInteger(grant, "K2");
            end
            symbolAllocation = sixgr.util.structGet( ...
                grant, "SymbolAllocation", []);
            if ~(isnumeric(symbolAllocation) && ...
                    numel(symbolAllocation) == 2 && ...
                    all(isfinite(double(symbolAllocation(:)))))
                error("sixgr:SchedulerBase:MissingSymbolAllocation", ...
                    "DCI packing requires an explicit two-value SymbolAllocation.");
            end
            fmt = localResolveDCIFormat(obj.Cfg, grant, direction);
            sliv = localTimeDomainAssignIndex( ...
                symbolAllocation, obj.SymbolsPerSlot);
            sixgr.phy.grant.assertGrantTimingIdentity(grant,obj.Direction);
            [dciContext, tdaIndex, dciContextSource] = ...
                sixgr.phy.pdcch.DCIContextFactory.fromScheduledGrant( ...
                obj.Cfg, grant, fmt);
            dciFields = localBuildSupportedDCIFields(obj.Cfg, grant, direction, fmt, riv, tdaIndex, ...
                rbStart, rbLen, mcs, ndi, rv, harqId, dai, k1, k2, dciContext);
            dciPayload = sixgr.phy.pdcch.encodeDCIPayload(dciFields, fmt, dciContext);
            fmap = localDCIFieldMapFromTable(dciPayload.FieldTable);
            fvals = localDCILegacyFieldValues(dciPayload.Fields, riv, tdaIndex, sliv, mcs, ndi, rv, harqId, dai, k1, k2);

            dci.Format = fmt;
            dci.Bits = uint8(dciPayload.Bits(:));
            dci.Hex = char(string(dciPayload.PayloadHex));
            dci.PayloadHash = char(string(dciPayload.PayloadHash));
            dci.PayloadHex = char(string(dciPayload.PayloadHex));
            dci.FieldMap = fmap;
            dci.FieldValues = fvals;
            dci.RIV = double(riv);
            dci.RBStart = double(rbStart);
            dci.RBLength = double(rbLen);
            dci.SLIV = double(sliv);
            dci.TimeDomainAssignmentIndex = double(tdaIndex);
            dci.ContextData = dciContext.Data;
            dci.ContextDigest = char(string(dciContext.Digest));
            dci.ContextSource = char(string(dciContextSource));
            dci.BitLength = double(numel(dci.Bits));
            dci.StandardProfile = "ts38212_supported_dci_payload";
            dci.BitExactPDCCHPayload = true;
            dci.FieldTable = dciPayload.FieldTable;
            dci.SizeDetails = dciPayload.SizeDetails;
            dci.NRFieldLayoutSource = "sixgr.phy.pdcch.encodeDCIPayload_ts_38212_supported_layout";
            dci.NRResourceAssignmentSource = "3gpp_ts_38_214_riv_sliv";
            dci.FinalizedGrant = logical(sixgr.util.structGet(grant, "ExactPHYFeasibilityChecked", false));
            dci.ExactPHYFeasibilityChecked = logical(sixgr.util.structGet(grant, "ExactPHYFeasibilityChecked", false));
            dci.ExactPHYFeasible = logical(sixgr.util.structGet(grant, "ExactPHYFeasible", false));
            dci.SourceGrantTBSBits = double(sixgr.util.structGet(grant, "TBSBits", NaN));
            dci.DCIGrantContract = "packed_from_finalized_scheduler_phy_grant";
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
            % Deprecated compatibility shim. The implementation is now
            % table-driven and returns NaN instead of fabricating MCS 0 when
            % neither CQI nor an explicit modulation/code-rate profile maps
            % to a valid standards-table row.
            if nargin < 3
                cqiFallback = NaN;
            end
            if nargin < 4 || isempty(mcsTable)
                mcsTable = localDefaultMCSTable(modStr);
            end
            decision = sixgr.link.resolveMCSIndexFromProfile(modStr, targetCodeRate, ...
                "MCSTable", mcsTable, ...
                "CQI", cqiFallback, ...
                "CQITable", localDefaultCQITable(mcsTable));
            mcs = double(decision.MCSIndex);
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
            decision = sixgr.link.resolveMCSIndexFromProfile(modStr, tcr, ...
                "MCSTable", mcsTable, ...
                "CQI", cqiFallback, ...
                "CQITable", localDefaultCQITable(mcsTable));
            profile = decision.MCSProfile;
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
    error("sixgr:SchedulerBase:MissingSymbolsPerSlot", ...
        "DCI time-domain assignment requires canonical SymbolsPerSlot.");
end
if ~(isnumeric(symbolsPerSlot) && isreal(symbolsPerSlot) && ...
        isscalar(symbolsPerSlot) && isfinite(symbolsPerSlot) && ...
        symbolsPerSlot == fix(symbolsPerSlot) && ...
        any(double(symbolsPerSlot) == [12 14]))
    error("sixgr:SchedulerBase:InvalidSymbolsPerSlot", ...
        "Canonical NR SymbolsPerSlot must be 12 or 14.");
end
N = double(symbolsPerSlot);
if ~(isnumeric(symAlloc) && isreal(symAlloc) && numel(symAlloc) == 2)
    error("sixgr:SchedulerBase:MissingSymbolAllocation", ...
        "DCI time-domain assignment requires explicit [start,count] symbols.");
end
sa = reshape(double(symAlloc), 1, 2);
if any(~isfinite(sa)) || any(sa ~= fix(sa)) || ...
        sa(1) < 0 || sa(2) < 1 || sum(sa) > N
    error("sixgr:SchedulerBase:InvalidSymbolAllocation", ...
        "DCI SymbolAllocation must be integer [start,count] within " + ...
        "the canonical %d-symbol slot.", N);
end
s = sa(1);
l = sa(2);
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

function tf = localRequiresExactGrantNRE(direction, symAlloc)
tf = false;
if upper(string(direction)) ~= "UL"
    return;
end
if nargin < 2 || isempty(symAlloc)
    tf = true;
    return;
end
sa = double(symAlloc(:).');
if numel(sa) < 2 || any(~isfinite(sa(1:2)))
    tf = true;
    return;
end
startSym = max(0, round(double(sa(1))));
nSym = max(0, round(double(sa(2))));

% Late-start or tiny UL allocations depend on exact PUSCH mapping. Fast
% RE estimates can overstate schedulable data RE in special-slot UL tails.
tf = startSym > 3 || nSym <= 2;
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

function xOverhead = localResolveTBSXOverhead(direction, cfg, symAlloc)
if nargin < 3 || isempty(symAlloc)
    error("sixgr:SchedulerBase:MissingSymbolAllocation", ...
        "Exact TBS overhead resolution requires explicit [start,count] symbols.");
end
if upper(string(direction)) == "UL"
    [xOverhead, explicit] = localFirstFiniteScalarWithPresence( ...
        sixgr.util.structGet(cfg, "phy.pusch.xOverhead", []), ...
        sixgr.util.structGet(cfg, "phy.pusch.XOverhead", []));
    if ~explicit
        xOverhead = 0;
    end
    modToken = upper(strtrim(string(sixgr.util.structGet(cfg, "phy.pusch.modulation", ""))));
    tpEnabled = logical(sixgr.util.structGet(cfg, "phy.pusch.transformPrecoding", false)) || ...
        strcmp(modToken, "PI/2-BPSK") || strcmp(modToken, "PI2-BPSK");
    if tpEnabled
        xOverhead = max(double(xOverhead), 6);
    end
else
    [xOverhead, explicit] = localFirstFiniteScalarWithPresence( ...
        sixgr.util.structGet(cfg, "phy.pdsch.xOverhead", []), ...
        sixgr.util.structGet(cfg, "phy.pdsch.XOverhead", []));
    if ~explicit
        xOverhead = localResolveDLReferenceSignalXOverhead(cfg, symAlloc);
    end
end
xOverhead = max(0, round(double(xOverhead)));
end

function xOverhead = localResolveDLReferenceSignalXOverhead(cfg, symAlloc)
xOverhead = sixgr.phy.dl.resolvePDSCHXOverhead(cfg, symAlloc);
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

function [value, found] = localFirstFiniteScalarWithPresence(varargin)
value = NaN;
found = false;
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
        found = true;
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
    needsAdvanced = localNeedsAdvancedULDci(cfg, grant);
    advancedFormat = "0_1";
    basicFormat = "0_0";
else
    needsAdvanced = localNeedsAdvancedDLDci(cfg, grant);
    advancedFormat = "1_1";
    basicFormat = "1_0";
end
if needsAdvanced
    selected = advancedFormat;
else
    selected = basicFormat;
end

% Search-space monitoring is RRC/YAML authority.  A scheduler must never
% silently manufacture an unmonitored DCI format merely because a finite
% PMI/CRI/SRI is present in its internal state.  Conversely, when dynamic
% spatial fields are required, silently falling back to the basic format
% would omit causal grant information.  Fail closed on that conflict.
configured = localConfiguredDCIFormats(cfg);
if ~isempty(configured)
    compatible = configured(startsWith(configured, extractBefore(selected, "_") + "_"));
    if ismember(selected, compatible)
        % Exact intended format is monitored.
    elseif ~needsAdvanced && ismember(advancedFormat, compatible)
        selected = advancedFormat;
    else
        error("sixgr:SchedulerBase:RequiredDCIFormatNotMonitored", ...
            'The %s scheduler requires DCI %s, but the configured search space monitors only [%s] for that direction.', ...
            char(direction), char(selected), char(strjoin(compatible, ",")));
    end
end
fmt = "DCI_" + selected;
end

function formats = localConfiguredDCIFormats(cfg)
raw = sixgr.util.structGet(cfg, "phy.pdcch.dciFormats", ...
    sixgr.util.structGet(cfg, "phy.pdcch.dciFormat", []));
formats = string(raw);
formats = formats(:).';
formats = formats(strlength(strtrim(formats)) > 0);
for ii = 1:numel(formats)
    formats(ii) = sixgr.phy.pdcch.normalizeDCIFormat(formats(ii));
end
formats = unique(formats, "stable");
end

function fields = localBuildSupportedDCIFields(cfg, grant, direction, fmt, riv, tdaIndex, ...
        rbStart, rbLen, mcs, ndi, rv, harqId, dai, k1, k2, dciContext)
direction = upper(string(direction));
fmt = sixgr.phy.pdcch.normalizeDCIFormat(fmt);
fields = struct();
fields.format_identifier = double(direction == "DL");
fields.frequency_resource_assignment = double(riv);
fields.time_resource_assignment = double(tdaIndex);
fields.mcs = double(mcs);
fields.ndi = double(ndi);
fields.rv = double(rv);
fields.harq_process = double(harqId);
if isfield(dciContext.Data,'ConnectedPolicy')
    fields=sixgr.phy.pdcch.ConnectedDCIProfile.scheduledFields(fields,dciContext,cfg,grant,k1);
    return;
end
symAlloc = double(sixgr.util.structGet(grant, "SymbolAllocation", []));
if numel(symAlloc) ~= 2 || any(~isfinite(symAlloc))
    error("sixgr:SchedulerBase:MissingSymbolAllocation", ...
        "Supported DCI fields require an explicit SymbolAllocation.");
end

switch fmt
    case "1_0"
        fields.vrb_to_prb_mapping = localClampDCIValue(sixgr.util.structGet(grant, "VRBToPRBMapping", 0), 1);
        fields.dai = double(dai);
        fields.tpc_command_for_pucch = localClampDCIValue(sixgr.util.structGet(grant, "TPC", 1), 2);
        fields.pucch_resource_indicator = localClampDCIValue(sixgr.util.structGet(grant, "PUCCHResourceIndicator", 0), 3);
        fields.pdsch_to_harq_feedback_timing = double(k1);
    case "0_0"
        fields.frequency_hopping = localClampDCIValue(sixgr.util.structGet(grant, "FrequencyHoppingFlag", 0), 1);
        fields.tpc_command_for_pusch = localClampDCIValue(sixgr.util.structGet(grant, "TPCCommandForPUSCH", ...
            sixgr.util.structGet(grant, "TPC", 1)), 2);
    case "1_1"
        fields.vrb_to_prb_mapping = localClampDCIValue(sixgr.util.structGet(grant, "VRBToPRBMapping", 0), 1);
        fields.prb_bundling_size_indicator = localClampDCIValue(sixgr.util.structGet(grant, "PRBBundlingSizeIndicator", 0), 1);
        fields.rate_matching_indicator = localClampDCIValue(sixgr.util.structGet(grant, "RateMatchingIndicator", 0), 2);
        fields.zp_csirs_trigger = localClampDCIValue(sixgr.util.structGet(grant, "ZPCSIRSTrigger", 0), 2);
        fields.dai = double(dai);
        fields.tpc_command_for_pucch = localClampDCIValue(sixgr.util.structGet(grant, "TPC", 1), 2);
        fields.pucch_resource_indicator = localClampDCIValue(sixgr.util.structGet(grant, "PUCCHResourceIndicator", 0), 3);
        fields.pdsch_to_harq_feedback_timing = double(k1);
        fields.antenna_ports = localDLAntennaPortField(grant);
        if isfield(dciContext.Data,'DLReferenceSignaling')
            fields.antenna_ports=sixgr.phy.pdcch.DLReferenceSignaling.antennaFromGrant(dciContext.Data,cfg,grant);
        end
        if logical(dciContext.Data.TCIPresent)
            policy=sixgr.util.structGet(cfg,'phy.pdsch.qclTCI',struct());
            if logical(sixgr.util.structGet(policy,'enabled',false))
                assert(grant.Slot-1>=policy.activation_absolute_slot0 && ...
                    dciContext.Data.ConfigurationEpoch==policy.configuration_epoch, ...
                    'sixgr:qcl:InactiveTCI','Scheduled DCI must use the active TCI mapping epoch.');
                fields.transmission_configuration_indication=double(policy.codepoint);
            else
                fields.transmission_configuration_indication = localClampDCIValue(sixgr.util.structGet(grant, "TCIState", ...
                    sixgr.util.structGet(cfg, "phy.pdsch.TCIState", 0)), dciContext.Data.TCIWidth);
            end
        end
        fields.srs_request = localClampDCIValue(sixgr.util.structGet(grant, "SRSRequest", 0), 2);
        fields.csi_request = localClampDCIValue(sixgr.util.structGet(grant, "CSIRequest", ...
            double(isfinite(double(sixgr.util.structGet(grant, "CRI", NaN))))), 2);
        if logical(dciContext.Data.CBGFieldsPresent)
            fields.cbg_transmission_information = localClampDCIValue( ...
                sixgr.util.structGet(grant, "CBGTI", 0), ...
                dciContext.Data.CBGTransmissionWidth);
            fields.cbg_flushing_information = localClampDCIValue( ...
                sixgr.util.structGet(grant, "CBGFI", 0), ...
                dciContext.Data.CBGFlushWidth);
        end
        if logical(dciContext.Data.DMRSSequenceInitializationPresent)
            fields.dmrs_sequence_initialization = localClampDCIValue( ...
                sixgr.util.structGet(grant, "DMRSSequenceInitialization", 0), 1);
        end
    case "0_1"
        fields.frequency_hopping = localClampDCIValue(sixgr.util.structGet(grant, "FrequencyHoppingFlag", 0), 1);
        fields.first_dai = double(dai);
        fields.tpc_command_for_pusch = localClampDCIValue(sixgr.util.structGet(grant, "TPCCommandForPUSCH", 1), 2);
        fields.srs_resource_indicator = localClampDCIValue(sixgr.util.structGet(grant, "SRSResourceIndicator", ...
            sixgr.util.structGet(grant, "SRSResourceID", 0)), 4);
        tpmi = localClampDCIValue(sixgr.util.structGet(grant, "TPMI", ...
            sixgr.util.structGet(grant, "PMI", 0)), 4);
        rankMinusOne = max(0, localClampDCIValue( ...
            sixgr.util.structGet(grant, "NumLayers", 1), 2) - 1);
        fields.precoding_information_and_number_of_layers = ...
            double(tpmi + 16 * rankMinusOne);
        if isfield(dciContext.Data,'ULPrecoding')
            fields.precoding_information_and_number_of_layers= ...
                sixgr.phy.pdcch.ULPrecodingField.encode(dciContext.Data, ...
                double(sixgr.util.structGet(grant,"NumLayers",NaN)), ...
                double(sixgr.util.structGet(grant,"TPMI",NaN)));
        end
        fields.antenna_ports = localULAntennaPortField(grant);
        if isfield(dciContext.Data,'ULReferenceSignaling')
            fields=sixgr.phy.pdcch.ULReferenceSignaling.bindSRI(fields,dciContext.Data, ...
                double(sixgr.util.structGet(grant,"SRSResourceIndicator",0)));
            fields.antenna_ports=sixgr.phy.pdcch.ULReferenceSignaling.antennaFromGrant(dciContext.Data,cfg,grant);
        end
        fields.srs_request = localClampDCIValue(sixgr.util.structGet(grant, "SRSRequest", 0), 2);
        fields.csi_request = localClampDCIValue(sixgr.util.structGet(grant, "CSIRequest", 0), 2);
        if logical(dciContext.Data.CBGFieldsPresent)
            fields.cbg_transmission_information = localClampDCIValue( ...
                sixgr.util.structGet(grant, "CBGTI", 0), ...
                dciContext.Data.CBGTransmissionWidth);
            fields.ptrs_dmrs_association = localClampDCIValue( ...
                sixgr.util.structGet(grant, "PTRSDMRSAssociation", 0), 2);
        end
end
fields = sixgr.phy.pdcch.completeDCIFields(fields, dciContext);
end

function fmap = localDCIFieldMapFromTable(fieldTable)
fmap = struct();
if ~istable(fieldTable) || height(fieldTable) < 1
    return;
end
for ii = 1:height(fieldTable)
    name = char(matlab.lang.makeValidName(char(string(fieldTable.FieldName(ii)))));
    fmap.([name '_bits']) = double(fieldTable.BitOffsetEnd(ii) - fieldTable.BitOffsetStart(ii) + 1);
    fmap.([name '_start']) = double(fieldTable.BitOffsetStart(ii));
    fmap.([name '_end']) = double(fieldTable.BitOffsetEnd(ii));
end
end

function fvals = localDCILegacyFieldValues(fields, riv, tdaIndex, sliv, mcs, ndi, rv, harqId, dai, k1, k2)
fvals = struct();
fvals.FormatIndicator = double(sixgr.util.structGet(fields, "format_identifier", NaN));
fvals.FrequencyDomainResourceAssignment_RIV = double(riv);
fvals.TimeDomainResourceAssignmentIndex = double(tdaIndex);
fvals.TimeDomainResourceAssignmentSLIV = double(sliv);
fvals.MCS = double(mcs);
fvals.NDI = double(ndi);
fvals.RV = double(rv);
fvals.HARQProcessNumber = double(harqId);
fvals.DAI = double(dai);
fvals.K1 = double(k1);
fvals.K2 = double(k2);
fieldNames = string(fieldnames(fields));
for ii = 1:numel(fieldNames)
    raw = fields.(char(fieldNames(ii)));
    if isnumeric(raw) && isscalar(raw)
        legacyName = char(matlab.lang.makeValidName(char(fieldNames(ii))));
        fvals.(legacyName) = double(raw);
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

function [usable, status, ageSlots, ageSeconds] = localResolveUECausalFeedback(ue, cfg, direction)
usable = true;
status = "OK";
ageSlots = double(sixgr.util.structGet(ue, "FeedbackAgeSlots", ...
    sixgr.util.structGet(ue, "CSIAgeSlots", NaN)));
ageSeconds = double(sixgr.util.structGet(ue, "FeedbackAgeSeconds", ...
    sixgr.util.structGet(ue, "CSIAgeSeconds", NaN)));

direction = upper(string(direction));
if direction == "UL"
    signalUsable = sixgr.util.structGet(ue, "SRSCausalUsable", []);
else
    signalUsable = sixgr.util.structGet(ue, "CSIRSCausalUsable", []);
end
rawUsable = sixgr.util.structGet(ue, "CausalFeedbackUsable", ...
    sixgr.util.structGet(ue, "FeedbackUsable", signalUsable));
if ~isempty(rawUsable) && (islogical(rawUsable) || isnumeric(rawUsable)) && isscalar(rawUsable)
    usable = logical(rawUsable);
end
rawStatus = strtrim(string(sixgr.util.structGet(ue, "CausalFeedbackStatus", ...
    sixgr.util.structGet(ue, "FeedbackStatus", ""))));
if strlength(rawStatus) > 0
    status = rawStatus;
end

maxAgeSlots = localSchedulerMaxCSIAgeSlots(cfg, direction);
if isfinite(maxAgeSlots) && isfinite(ageSlots) && ageSlots > maxAgeSlots
    usable = false;
    status = "stale_csi_age_exceeds_configured_limit";
elseif ~usable && status == "OK"
    status = "csi_marked_unusable_by_runtime";
end
end

function maxAgeSlots = localSchedulerMaxCSIAgeSlots(cfg, direction)
direction = upper(string(direction));
if direction == "UL"
    maxAgeSlots = localFirstFiniteScalar( ...
        sixgr.util.structGet(cfg, "phy.linkAdaptation.ulMaxCSIAgeSlots", []), ...
        sixgr.util.structGet(cfg, "phy.linkAdaptation.maxCSIAgeSlots", []), ...
        sixgr.util.structGet(cfg, "run.controlGating.srsMaxAgeSlots", []), ...
        inf);
else
    maxAgeSlots = localFirstFiniteScalar( ...
        sixgr.util.structGet(cfg, "phy.linkAdaptation.dlMaxCSIAgeSlots", []), ...
        sixgr.util.structGet(cfg, "phy.linkAdaptation.maxCSIAgeSlots", []), ...
        sixgr.util.structGet(cfg, "run.controlGating.csirsMaxAgeSlots", []), ...
        inf);
end
if ~(isfinite(maxAgeSlots) && maxAgeSlots >= 0)
    maxAgeSlots = inf;
end
end

function profile = localSchedulerCalibrationProfile(cfg, direction)
direction = upper(string(direction));
if direction == "UL"
    version = string(sixgr.util.structGet(cfg, "phy.linkAdaptation.ulCalibrationVersion", ...
        sixgr.util.structGet(cfg, "phy.linkAdaptation.calibrationVersion", "nr_cqi_mcs_table_v1")));
    targetBLER = double(sixgr.util.structGet(cfg, "phy.pusch.targetBLER", ...
        sixgr.util.structGet(cfg, "phy.linkAdaptation.targetBLER", 0.1)));
else
    version = string(sixgr.util.structGet(cfg, "phy.linkAdaptation.dlCalibrationVersion", ...
        sixgr.util.structGet(cfg, "phy.linkAdaptation.calibrationVersion", "nr_cqi_mcs_table_v1")));
    targetBLER = double(sixgr.util.structGet(cfg, "phy.pdsch.targetBLER", ...
        sixgr.util.structGet(cfg, "phy.linkAdaptation.targetBLER", 0.1)));
end
if strlength(strtrim(version)) == 0
    version = "nr_cqi_mcs_table_v1";
end
if ~(isfinite(targetBLER) && targetBLER > 0 && targetBLER < 1)
    targetBLER = 0.1;
end
profile = "nr_cqi_table_amc:target_bler_" + regexprep(string(sprintf("%.3g", targetBLER)), "[^0-9A-Za-z]+", "p") + ":" + strtrim(version);
end

function provenance = localSchedulerCQIProvenance(ue, fallback)
provenance = strtrim(string(sixgr.util.structGet(ue, "SchedulerCQISource", "")));
if strlength(provenance) == 0
    provenance = strtrim(string(fallback));
end
if strlength(provenance) == 0
    provenance = "runtime_reported_cqi";
end
provenance = char(provenance);
end

function mcs = localResolveBootstrapMCSIndex(cfg)
mcs = double(sixgr.util.structGet(cfg, "phy.linkAdaptation.bootstrapMCSIndex", ...
    sixgr.util.structGet(cfg, "mac.scheduler.bootstrapMCSIndex", 1)));
if ~(isscalar(mcs) && isfinite(mcs))
    mcs = 1;
end
mcs = max(0, min(31, round(mcs)));
end

function amc = localMarkMissingRuntimeCQI(amc, cfg, provenance)
amc.CausalFeedbackUsable = false;
amc.CausalFeedbackStatus = char(string(provenance));
if localSchedulerRequiresMeasuredCQI(cfg) || localBootstrapAdmissionRejected(provenance) || ...
        localMeasuredCQIOutOfRange(provenance)
    amc.Mode = "cqi_required_no_runtime_feedback";
    amc.MCSIndex = NaN;
    amc.MCSProfile = sixgr.link.resolveMCSProfile(char(string(amc.MCSTable)), -1);
    if localMeasuredCQIOutOfRange(provenance)
        amc.MCSSelectionSource = "blocked_measured_cqi_zero_out_of_range";
        amc.MCSValueStatus = "unavailable_measured_cqi_zero_out_of_range";
    elseif localBootstrapAdmissionRejected(provenance)
        amc.MCSSelectionSource = "blocked_bootstrap_cqi_below_configured_floor";
        amc.MCSValueStatus = "unavailable_missing_runtime_cqi";
    else
        amc.MCSSelectionSource = "blocked_missing_runtime_cqi";
        amc.MCSValueStatus = "unavailable_missing_runtime_cqi";
    end
    amc.CQIProvenance = char(string(provenance));
else
    amc.Mode = "bootstrap_cqi_conservative";
    amc.MCSIndex = localResolveBootstrapMCSIndex(cfg);
    amc.MCSProfile = sixgr.link.resolveMCSProfile(char(string(amc.MCSTable)), amc.MCSIndex);
    amc.MCSSelectionSource = "bootstrap_cqi_conservative_lab_default";
    amc.CQIProvenance = char(string(provenance));
    amc.MCSValueStatus = "bootstrap_not_measured_cqi";
end
end

function tf = localMeasuredCQIOutOfRange(provenance)
token = lower(strtrim(string(provenance)));
tf = token == "measured_cqi_zero_out_of_range" || ...
    contains(token, "measured_cqi_zero_out_of_range");
end

function tf = localBootstrapAdmissionRejected(provenance)
token = lower(strtrim(string(provenance)));
tf = any(token == ["rejected_below_min_cqi_for_scheduling", ...
    "bootstrap_cqi_rejected_below_min_cqi_for_scheduling"]) || ...
    contains(token, "rejected_below_min_cqi_for_scheduling");
end

function tf = localSchedulerRequiresMeasuredCQI(cfg)
mode = lower(strtrim(string(sixgr.util.structGet(cfg, "phy.linkAdaptation.bootstrapCQIMode", ...
    sixgr.util.structGet(cfg, "mac.scheduler.bootstrapCQIMode", "conservative")))));
tf = ismember(mode, ["require_measured_cqi","measured_only","strict_measured_cqi","none","disabled","off"]);
end

function tf = localAMCBlocksGrant(amc)
tf = strcmpi(char(string(sixgr.util.structGet(amc, "Mode", ""))), "cqi_required_no_runtime_feedback") || ...
    ismember(lower(strtrim(string(sixgr.util.structGet(amc, "MCSValueStatus", "")))), ...
        ["unavailable_missing_runtime_cqi","unavailable_measured_cqi_zero_out_of_range"]);
end

function reason = localAMCBlockerReason(amc)
if localAMCBlocksGrant(amc)
    if localMeasuredCQIOutOfRange(sixgr.util.structGet(amc, "CausalFeedbackStatus", ""))
        reason = "blocked_measured_cqi_zero_out_of_range";
    else
        reason = "blocked_until_runtime_cqi_feedback";
    end
else
    reason = "";
end
end

function tf = localSchedulerOLLAEnabled(cfg)
policy = sixgr.link.resolveOLLAConfig(cfg);
tf = logical(policy.Enabled);
end

function tf = localFeedbackEligibleForOLLA(isRetxKnown, isRetx, rv)
% OLLA should track the selected first-transmission operating point. HARQ
% retransmission ACKs prove IR/soft combining recovered the TB, not that the
% original CQI-to-MCS choice met the target first-transmission BLER.
tf = true;
if logical(isRetxKnown) && logical(isRetx)
    tf = false;
    return;
end
rv = double(rv);
if isfinite(rv) && round(rv) ~= 0
    tf = false;
end
end

function tf = localOLLAIsExternallyManaged(authority)
authority = lower(strtrim(string(authority)));
tf = any(authority == ["receiver_harq_feedback_state", ...
    "external_receiver_feedback_state"]);
end

function step = localSchedulerOLLAStep(cfg, direction)
policy = sixgr.link.resolveOLLAConfig(cfg);
direction = lower(strtrim(string(direction)));
if direction == "up"
    step = double(policy.StepUpDb);
else
    step = double(policy.StepDownDb);
end
end

function tf = localSchedulerInnerLoopEnabled(cfg, direction)
mode = lower(strtrim(string(sixgr.util.structGet(cfg, "phy.linkAdaptation.mode", "fixed"))));
if upper(string(direction)) == "UL"
    policy = lower(strtrim(string(sixgr.util.structGet(cfg, ...
        "phy.linkAdaptation.ulPolicy", ""))));
else
    policy = lower(strtrim(string(sixgr.util.structGet(cfg, ...
        "phy.linkAdaptation.dlPolicy", ""))));
end
flag = logical(sixgr.util.structGet(cfg, "phy.linkAdaptation.innerLoopFlag", true));
fixedTokens = ["fixed","fixed_mcs","configured_fixed","disabled","off","none","false",""];
tf = flag && ~ismember(mode, fixedTokens) && ~ismember(policy, fixedTokens);
end

function value = localSchedulerOLLADeltaMin(cfg)
policy = sixgr.link.resolveOLLAConfig(cfg);
value = double(policy.MinimumOffsetDb);
end

function value = localSchedulerOLLADeltaMax(cfg)
policy = sixgr.link.resolveOLLAConfig(cfg);
value = double(policy.MaximumOffsetDb);
end

function symAlloc = localDefaultSymbolAllocation(cfg, direction, symbolsPerSlot)
direction = upper(string(direction));
if direction == "DL"
    base = "phy.pdsch";
else
    base = "phy.pusch";
end
symAlloc = sixgr.util.structGet(cfg, base + ".symbolAllocation", []);
if isempty(symAlloc)
    symAlloc = sixgr.util.structGet(cfg, base + ".SymbolAllocation", []);
end
if isempty(symAlloc)
    startSymbol = sixgr.util.structGet(cfg, base + ".startSymbol", []);
    numSymbols = sixgr.util.structGet(cfg, base + ".numSymbols", []);
    if ~isempty(startSymbol) && ~isempty(numSymbols)
        symAlloc = [startSymbol, numSymbols];
    end
end
if ~(isnumeric(symAlloc) && isreal(symAlloc) && numel(symAlloc) == 2 && ...
        all(isfinite(double(symAlloc(:)))) && ...
        all(double(symAlloc(:)) == fix(double(symAlloc(:)))))
    error("sixgr:SchedulerBase:MissingSymbolAllocation", ...
        "%s scheduling requires an explicit configured SymbolAllocation.", ...
        direction);
end
symAlloc = reshape(double(symAlloc), 1, 2);
if symAlloc(1) < 0 || symAlloc(2) < 1 || ...
        sum(symAlloc) > double(symbolsPerSlot)
    error("sixgr:SchedulerBase:InvalidSymbolAllocation", ...
        "%s SymbolAllocation is outside the configured slot.", direction);
end
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

autoSmallPRBGuard = localAutoQueueAwareWidebandCQIGuard(obj, amc, rawPRBSet, symAlloc, queueBytes, opt);
if autoSmallPRBGuard
    amc.AutoQueueAwareWidebandCQIGuard = true;
end
queueAwareReduction = (localQueueAwareRankMCSReductionEnabled(obj.Cfg) && ...
    localQueueAwarePRBDeltaTriggered(obj, amc, rawPRBSet, symAlloc, queueBytes, opt)) || ...
    autoSmallPRBGuard;
candidateProfiles = localCandidateMCSProfiles(amc, obj.Cfg, queueAwareReduction);
if localPreserveAMCMCSForQueueLimit(amc) && ~queueAwareReduction && ~isempty(candidateProfiles)
    cand = candidateProfiles(1);
    [chosenIdx, chosenCand] = localFindSmallestPositiveTB(obj, cand, rawPRBSet, symAlloc, opt);
    if chosenCand.Valid
        prbSubset = rawPRBSet(1:chosenIdx);
        best = localBuildQueueLimitedBest(cand, prbSubset, chosenCand, queueBytes);
        return;
    end
end
bestBits = -inf;
bestPRBCount = inf;
robustBest = struct("Valid", false);
robustBestBits = -inf;
robustBestPRBCount = inf;
minGuardPRB = localSmallPRBWidebandCQIGuardMinPRB(obj.Cfg, rawPRBSet);
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
    candidateBest = localBuildQueueLimitedBest(cand, prbSubset, chosenCand, queueBytes);
    if localQueueLimitedPlanBetter(chosenCand.TBSBits, numel(prbSubset), bestBits, bestPRBCount)
        best = candidateBest;
        bestBits = double(chosenCand.TBSBits);
        bestPRBCount = numel(prbSubset);
    end
    robustCandidate = ~autoSmallPRBGuard || ...
        localSmallPRBWidebandCQIRobustCandidate(cand, prbSubset, minGuardPRB, obj.Cfg);
    if robustCandidate && localQueueLimitedPlanBetter(chosenCand.TBSBits, numel(prbSubset), robustBestBits, robustBestPRBCount)
        robustBest = candidateBest;
        robustBestBits = double(chosenCand.TBSBits);
        robustBestPRBCount = numel(prbSubset);
    end
end
if autoSmallPRBGuard && logical(sixgr.util.structGet(robustBest, "Valid", false))
    best = robustBest;
end
if autoSmallPRBGuard && logical(sixgr.util.structGet(best, "Valid", false))
    best.QueueAwareReductionEnabled = true;
    best.QueueAwareReductionApplied = true;
    best.QueueAwareReductionSource = char(localAppendQueueAwareSource( ...
        sixgr.util.structGet(best, "QueueAwareReductionSource", ""), ...
        "wideband_cqi_small_prb_guard"));
    best.SmallPRBWidebandCQIGuardApplied = true;
    best.SmallPRBWidebandCQIGuardMinPRB = double(minGuardPRB);
end
end

function tf = localQueueLimitedPlanBetter(bits, prbCount, bestBits, bestPRBCount)
tf = double(bits) > double(bestBits) + 1e-9 || ...
    (abs(double(bits) - double(bestBits)) <= 1e-9 && double(prbCount) < double(bestPRBCount));
end

function tf = localPreserveAMCMCSForQueueLimit(amc)
mode = lower(string(sixgr.util.structGet(amc, "Mode", "fixed_modulation")));
mcsIndex = double(sixgr.util.structGet(amc, "MCSIndex", NaN));
tf = isfinite(mcsIndex) && mcsIndex >= 0 && (mode == "cqi_table" || mode == "fixed_mcs");
end

function best = localBuildQueueLimitedBest(cand, prbSubset, evalOut, queueBytes)
tbsBits = double(evalOut.TBSBits);
tbsBytes = double(evalOut.TBSBytes);
payloadBytes = max(0, floor(double(queueBytes)));
initialMCS = double(sixgr.util.structGet(cand, "InitialMCSIndex", sixgr.util.structGet(cand, "MCSIndex", NaN)));
initialLayers = double(sixgr.util.structGet(cand, "InitialNumLayers", sixgr.util.structGet(cand, "NumLayers", 1)));
mcsSteps = double(sixgr.util.structGet(cand, "MCSReductionSteps", 0));
layerSteps = double(sixgr.util.structGet(cand, "LayerReductionSteps", 0));
queueAwareEnabled = logical(sixgr.util.structGet(cand, "QueueAwareReductionEnabled", false));
queueAwareApplied = queueAwareEnabled && (mcsSteps > 0 || layerSteps > 0);
source = "";
if queueAwareApplied
    source = "buffer_occupancy_prb_share_rank_mcs_reduction";
end
best = struct( ...
    "Valid", true, ...
    "PRBSet", double(prbSubset(:).'), ...
    "Modulation", char(string(cand.Modulation)), ...
    "NumLayers", double(cand.NumLayers), ...
    "Layers", double(cand.NumLayers), ...
    "RI", double(cand.NumLayers), ...
    "RIUsed", double(cand.NumLayers), ...
    "Rank", double(cand.NumLayers), ...
    "RankIndicator", double(cand.NumLayers), ...
    "TargetCodeRate", double(cand.TargetCodeRate), ...
    "MCSIndex", double(cand.MCSIndex), ...
    "NREPerPRB", double(evalOut.NREPerPRB), ...
    "XOverhead", double(sixgr.util.structGet(evalOut, "XOverhead", NaN)), ...
    "TBSInputModulation", char(string(cand.Modulation)), ...
    "TBSInputNumLayers", double(cand.NumLayers), ...
    "TBSInputNPRB", double(numel(prbSubset)), ...
    "TBSInputNREPerPRB", double(evalOut.NREPerPRB), ...
    "TBSInputTargetCodeRate", double(cand.TargetCodeRate), ...
    "TBSInputXOverhead", double(sixgr.util.structGet(evalOut, "XOverhead", NaN)), ...
    "TBSInputSource", "scheduler_exact_allocation_resource_accounting", ...
    "TBSBits", tbsBits, ...
    "TBSBytes", tbsBytes, ...
    "QueuePaddingBits", max(0, tbsBits - 8 * payloadBytes), ...
    "QueuePaddingBytes", max(0, tbsBytes - payloadBytes), ...
    "InitialMCSIndex", initialMCS, ...
    "InitialNumLayers", initialLayers, ...
    "QueueAwareReductionEnabled", queueAwareEnabled, ...
    "QueueAwareReductionApplied", queueAwareApplied, ...
    "QueueAwareReductionSource", source, ...
    "MCSReductionSteps", mcsSteps, ...
    "LayerReductionSteps", layerSteps);
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

function [bestIdx, bestEval] = localFindSmallestPositiveTB(obj, cand, rawPRBSet, symAlloc, opt)
bestIdx = 0;
bestEval = localInvalidQueueEval();
lo = 1;
hi = numel(rawPRBSet);
while lo <= hi
    mid = floor((lo + hi) / 2);
    evalMid = localEvaluatePositiveCandidate(obj, cand, mid, symAlloc, opt);
    if evalMid.Valid
        bestIdx = mid;
        bestEval = evalMid;
        hi = mid - 1;
    else
        lo = mid + 1;
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
[tbsBits, tbsBytes, nrePerPRB, tbsInfo] = obj.estimateTBS( ...
    cand.Modulation, cand.NumLayers, double(prbCount), symAlloc, cand.TargetCodeRate, ...
    "PlanningOnly", logical(opt.PlanningOnly), ...
    "ForceExact", ~logical(opt.PlanningOnly));
if ~(isfinite(tbsBits) && isfinite(tbsBytes) && tbsBits > 0 && tbsBytes > 0)
    return;
end
if tbsBytes > queueBytes
    return;
end
evalOut.Valid = true;
evalOut.NREPerPRB = double(nrePerPRB);
evalOut.XOverhead = double(sixgr.util.structGet(tbsInfo, "XOverhead", localResolveTBSXOverhead(obj.Direction, obj.Cfg, symAlloc)));
evalOut.TBSBits = double(tbsBits);
evalOut.TBSBytes = double(tbsBytes);
end

function evalOut = localEvaluatePositiveCandidate(obj, cand, prbCount, symAlloc, opt)
evalOut = localInvalidQueueEval();
[tbsBits, tbsBytes, nrePerPRB, tbsInfo] = obj.estimateTBS( ...
    cand.Modulation, cand.NumLayers, double(prbCount), symAlloc, cand.TargetCodeRate, ...
    "PlanningOnly", logical(opt.PlanningOnly), ...
    "ForceExact", ~logical(opt.PlanningOnly));
if ~(isfinite(tbsBits) && isfinite(tbsBytes) && tbsBits > 0 && tbsBytes > 0)
    return;
end
evalOut.Valid = true;
evalOut.NREPerPRB = double(nrePerPRB);
evalOut.XOverhead = double(sixgr.util.structGet(tbsInfo, "XOverhead", localResolveTBSXOverhead(obj.Direction, obj.Cfg, symAlloc)));
evalOut.TBSBits = double(tbsBits);
evalOut.TBSBytes = double(tbsBytes);
end

function evalOut = localInvalidQueueEval()
evalOut = struct( ...
    "Valid", false, ...
    "NREPerPRB", NaN, ...
    "XOverhead", NaN, ...
    "TBSBits", NaN, ...
    "TBSBytes", NaN);
end

function candidates = localCandidateMCSProfiles(amc, cfg, queueAwareReduction)
if nargin < 2 || isempty(cfg)
    cfg = struct();
end
if nargin < 3 || isempty(queueAwareReduction)
    queueAwareReduction = localQueueAwareRankMCSReductionEnabled(cfg);
end
mode = lower(string(sixgr.util.structGet(amc, "Mode", "fixed_modulation")));
mcsTable = char(string(sixgr.util.structGet(amc, "MCSTable", "qam64_table1")));
numLayers = max(1, round(double(sixgr.util.structGet(amc, "NumLayers", 1))));
queueAwareReduction = logical(queueAwareReduction);

layerList = numLayers;
if queueAwareReduction
    layerDecMax = localNonnegativeIntegerConfig(cfg, "phy.linkAdaptation.queueAwareLayerDecrementMax", 1);
    minLayers = max(1, numLayers - layerDecMax);
    layerList = numLayers:-1:minLayers;
end

hasMCSIndex = isfinite(double(sixgr.util.structGet(amc, "MCSIndex", NaN)));
if (mode == "cqi_table" || mode == "fixed_mcs") && hasMCSIndex
    initialMCS = max(0, min(31, round(double(sixgr.util.structGet(amc, "MCSIndex", 0)))));
    if queueAwareReduction
        autoGuard = logical(sixgr.util.structGet(amc, "AutoQueueAwareWidebandCQIGuard", false));
        defaultMCSDecMax = 2;
        if autoGuard
            defaultMCSDecMax = max(2, initialMCS);
        end
        mcsDecMax = localNonnegativeIntegerConfig(cfg, "phy.linkAdaptation.queueAwareMCSDecrementMax", defaultMCSDecMax);
        step1 = localNonnegativeIntegerConfig(cfg, "phy.linkAdaptation.queueAwareMCSDecrementStep1", 1);
        step2 = localNonnegativeIntegerConfig(cfg, "phy.linkAdaptation.queueAwareMCSDecrementStep2", 2);
        decSet = unique([0, 1:mcsDecMax, step1, step2], "stable");
        decSet = decSet(decSet >= 0 & decSet <= max(mcsDecMax, 0));
        idxList = max(0, initialMCS - decSet);
    elseif mode == "cqi_table"
        idxList = initialMCS:-1:0;
    else
        idxList = initialMCS;
    end
    idxList = unique(idxList, "stable");
    prototype = localQueueAwareCandidateStruct(NaN, "QPSK", 0.1, numLayers, initialMCS, numLayers, queueAwareReduction);
    candidates = repmat(prototype, 0, 1);
    for layerIdx = 1:numel(layerList)
        layerCount = double(layerList(layerIdx));
        for idx = idxList
            prof = sixgr.link.resolveMCSProfile(mcsTable, idx);
            if prof.Valid
                candidates(end+1) = localQueueAwareCandidateStruct( ... %#ok<AGROW>
                    idx, prof.Modulation, prof.TargetCodeRate, layerCount, ...
                    initialMCS, numLayers, queueAwareReduction);
            end
        end
    end
else
    initialMCS = double(sixgr.util.structGet(amc, "MCSIndex", NaN));
    prototype = localQueueAwareCandidateStruct(initialMCS, "QPSK", 0.1, numLayers, initialMCS, numLayers, queueAwareReduction);
    candidates = repmat(prototype, 0, 1);
    for layerIdx = 1:numel(layerList)
        candidates(end+1) = localQueueAwareCandidateStruct( ... %#ok<AGROW>
            initialMCS, sixgr.util.structGet(amc, "Modulation", "QPSK"), ...
            sixgr.util.structGet(amc, "TargetCodeRate", 0.1), double(layerList(layerIdx)), ...
            initialMCS, numLayers, queueAwareReduction);
    end
end
end

function cand = localQueueAwareCandidateStruct(mcsIndex, modulation, targetCodeRate, numLayers, initialMCS, initialLayers, queueAwareReduction)
if ~(isfinite(double(mcsIndex)) && isfinite(double(initialMCS)))
    mcsSteps = 0;
else
    mcsSteps = max(0, round(double(initialMCS)) - round(double(mcsIndex)));
end
layerSteps = max(0, round(double(initialLayers)) - round(double(numLayers)));
cand = struct( ...
    "MCSIndex", double(mcsIndex), ...
    "Modulation", char(string(modulation)), ...
    "TargetCodeRate", double(targetCodeRate), ...
    "NumLayers", double(numLayers), ...
    "InitialMCSIndex", double(initialMCS), ...
    "InitialNumLayers", double(initialLayers), ...
    "QueueAwareReductionEnabled", logical(queueAwareReduction), ...
    "MCSReductionSteps", double(mcsSteps), ...
    "LayerReductionSteps", double(layerSteps));
end

function tf = localQueueAwareRankMCSReductionEnabled(cfg)
tf = logical(sixgr.util.structGet(cfg, "phy.linkAdaptation.queueAwareRankMCSReductionEnable", false));
if ~tf
    token = lower(strtrim(string(sixgr.util.structGet(cfg, "phy.linkAdaptation.rankPolicy", ""))));
    tf = contains(token, "queue") || contains(token, "buffer");
end
end

function tf = localAutoQueueAwareWidebandCQIGuard(obj, amc, rawPRBSet, symAlloc, queueBytes, opt)
tf = false;
mode = lower(strtrim(string(sixgr.util.structGet(amc, "Mode", ""))));
if mode ~= "cqi_table"
    return;
end
source = lower(strjoin([ ...
    string(sixgr.util.structGet(amc, "MCSSelectionSource", "")), ...
    string(sixgr.util.structGet(amc, "CQIProvenance", ""))], " "));
if ~(contains(source, "runtime") || contains(source, "measured"))
    return;
end
if contains(source, "bootstrap") || contains(source, "fixed")
    return;
end
if localHasUsableSubbandSchedulerCSI(amc, rawPRBSet)
    return;
end
minGuardPRB = localSmallPRBWidebandCQIGuardMinPRB(obj.Cfg, rawPRBSet);
if ~(isfinite(minGuardPRB) && minGuardPRB > 1)
    return;
end
baseCandidates = localCandidateMCSProfiles(amc, obj.Cfg, false);
if isempty(baseCandidates)
    return;
end
requiredPRB = localFindSmallestQueueCoveringPRB(obj, baseCandidates(1), rawPRBSet, symAlloc, queueBytes, opt);
mcsIndex = double(sixgr.util.structGet(amc, "MCSIndex", NaN));
nLayers = double(sixgr.util.structGet(amc, "NumLayers", 1));
smallSelectedRegion = numel(rawPRBSet) < minGuardPRB || ...
    (isfinite(requiredPRB) && requiredPRB < minGuardPRB);
tf = smallSelectedRegion && ...
    (double(nLayers) > 1 || (isfinite(mcsIndex) && mcsIndex >= localSmallPRBWidebandCQIMCSFloor(obj.Cfg)));
end

function tf = localSmallPRBWidebandCQIRobustCandidate(cand, prbSubset, minGuardPRB, cfg)
tf = numel(prbSubset) >= minGuardPRB;
if tf
    return;
end
floorMCS = localSmallPRBWidebandCQIMCSFloor(cfg);
mcsIndex = double(sixgr.util.structGet(cand, "MCSIndex", NaN));
nLayers = double(sixgr.util.structGet(cand, "NumLayers", 1));
tf = round(max(1, nLayers)) == 1 && ...
    isfinite(mcsIndex) && round(mcsIndex) < floorMCS;
end

function tf = localHasUsableSubbandSchedulerCSI(amc, rawPRBSet)
tf = false;
requiredBins = max(1, numel(rawPRBSet));
for fieldName = ["AgedSubbandSINRVector_dB","SubbandSINRVector_dB"]
    values = localParseNumericVectorToken(sixgr.util.structGet(amc, fieldName, ""));
    values = values(isfinite(values));
    if numel(values) >= requiredBins
        tf = true;
        return;
    end
end
end

function values = localParseNumericVectorToken(token)
if isnumeric(token)
    values = double(token(:));
    return;
end
txt = strtrim(string(token));
if strlength(txt) == 0
    values = [];
    return;
end
txt = replace(txt, ["[", "]", ";", ","], " ");
parts = regexp(char(txt), "[|\\s]+", "split");
parts = parts(~cellfun("isempty", parts));
values = str2double(string(parts));
values = double(values(:));
end

function minPRB = localSmallPRBWidebandCQIGuardMinPRB(cfg, rawPRBSet)
minPRB = double(sixgr.util.structGet(cfg, "phy.linkAdaptation.minPRBForWidebandCQIGrant", ...
    sixgr.util.structGet(cfg, "mac.scheduler.minPRBPerUE", NaN)));
if ~(isfinite(minPRB) && minPRB >= 1)
    minPRB = max(4, ceil(0.02 * max(1, numel(rawPRBSet))));
end
minPRB = max(1, round(minPRB));
end

function floorMCS = localSmallPRBWidebandCQIMCSFloor(cfg)
floorMCS = double(sixgr.util.structGet(cfg, "phy.linkAdaptation.smallPRBWidebandCQIMCSFloor", 10));
if ~(isfinite(floorMCS) && floorMCS >= 0)
    floorMCS = 10;
end
floorMCS = round(floorMCS);
end

function source = localAppendQueueAwareSource(source, token)
source = string(source);
token = string(token);
if strlength(strtrim(source)) == 0
    source = token;
elseif ~contains(source, token)
    source = source + "+" + token;
end
end

function tf = localQueueAwarePRBDeltaTriggered(obj, amc, rawPRBSet, symAlloc, queueBytes, opt)
tf = false;
rawPRBSet = double(rawPRBSet(:).');
nShare = numel(rawPRBSet);
if nShare < 1 || ~(isfinite(double(queueBytes)) && double(queueBytes) > 0)
    return;
end

baseCandidates = localCandidateMCSProfiles(amc, obj.Cfg, false);
if isempty(baseCandidates)
    return;
end
baseCand = baseCandidates(1);
requiredPRB = localFindSmallestQueueCoveringPRB(obj, baseCand, rawPRBSet, symAlloc, queueBytes, opt);
if ~(isfinite(requiredPRB) && requiredPRB >= 1)
    return;
end

spareFraction = max(0, (double(nShare) - double(requiredPRB)) / max(double(nShare), 1));
delta1 = localNonnegativeScalarConfig(obj.Cfg, "phy.linkAdaptation.queueAwarePRBDelta1Fraction", 0.5);
delta2 = localNonnegativeScalarConfig(obj.Cfg, "phy.linkAdaptation.queueAwarePRBDelta2Fraction", 0.8);
triggerFraction = min(max(delta1, 0), max(delta2, 0));
tf = spareFraction >= triggerFraction;
end

function requiredPRB = localFindSmallestQueueCoveringPRB(obj, cand, rawPRBSet, symAlloc, queueBytes, opt)
requiredPRB = NaN;
lo = 1;
hi = numel(rawPRBSet);
payloadBytes = max(0, floor(double(queueBytes)));
while lo <= hi
    mid = floor((lo + hi) / 2);
    evalMid = localEvaluatePositiveCandidate(obj, cand, mid, symAlloc, opt);
    if evalMid.Valid && double(evalMid.TBSBytes) >= payloadBytes
        requiredPRB = mid;
        hi = mid - 1;
    else
        lo = mid + 1;
    end
end
if ~isfinite(requiredPRB)
    requiredPRB = numel(rawPRBSet);
end
end

function value = localNonnegativeIntegerConfig(cfg, path, defaultValue)
value = double(sixgr.util.structGet(cfg, path, defaultValue));
if ~(isfinite(value) && value >= 0)
    value = double(defaultValue);
end
value = max(0, round(value));
end

function value = localNonnegativeScalarConfig(cfg, path, defaultValue)
value = double(sixgr.util.structGet(cfg, path, defaultValue));
if ~(isfinite(value) && value >= 0)
    value = double(defaultValue);
end
value = max(0, double(value));
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
    error("sixgr:SchedulerBase:MissingSymbolAllocation", ...
        "Exact NRE cache keys require explicit [start,count] symbols.");
end

dirToken = upper(char(string(direction)));
startSym = round(double(sa(1)));
nSym = round(double(sa(2)));
key = sprintf('%s|L%d|P%d|S%d|N%d', dirToken, round(double(nLayers)), round(double(nPRB)), startSym, nSym);
end

function tf = localIsTBSModulationSupported(modStr)
token = upper(strtrim(string(modStr)));
tf = any(token == ["QPSK", "16QAM", "64QAM", "256QAM", "1024QAM"]);
end

function nrePerPRB = localComputeExactNREPerPRB(direction, carrier, cfg, nPRB, symAlloc, modStr, nLayers)
cfg = localApplyGrantLayerCountToCfg(cfg, direction, nLayers);
if strcmpi(direction,'DL')
    % This cache is keyed by count/TDRA, not the scheduled slot or PRB set.
    % It owns nominal TBS N_RE only, never occasion-specific feasibility/G.
    nrePerPRB = sixgr.phy.resource.nominalPDSCHNREPerPRB(carrier, cfg, ...
        "PRBSet", 0:(max(nPRB,1)-1), ...
        "SymbolAllocation", symAlloc, ...
        "Modulation", char(modStr), ...
        "NumLayers", double(nLayers));
    return;
else
    [~, allocInfo] = sixgr.phy.grid.allocREsPUSCH(carrier, cfg, ...
        "PRBSet", 0:(max(nPRB,1)-1), ...
        "SymbolAllocation", symAlloc, ...
        "Modulation", char(modStr), ...
        "NumLayers", double(nLayers));
end
nrePerPRB = localExtractNREPerPRB(allocInfo, nPRB, modStr, nLayers);
end

function cfg = localApplyGrantLayerCountToCfg(cfg, direction, nLayers)
direction = upper(string(direction));
nLayers = max(1, round(double(nLayers)));
root = localPHYRoot(direction);
cfg = sixgr.util.structSet(cfg, root + ".nLayers", nLayers);
cfg = sixgr.util.structSet(cfg, root + ".numLayers", nLayers);

ports = sixgr.util.structGet(cfg, root + ".dmrs.availablePortSet", ...
    sixgr.util.structGet(cfg, root + ".dmrs.portSet", ...
    sixgr.util.structGet(cfg, root + ".dmrs.DMRSPortSet", [])));
if isempty(ports) && direction == "DL"
    ports = sixgr.util.structGet(cfg, "pdsch6gr.DMRSPortSet", []);
end
if isempty(ports)
    return;
end
ports = double(ports(:).');
if numel(ports) < nLayers
    error("sixgr:SchedulerBase:InsufficientDMRSPorts", ...
        "Configured %s DM-RS port set has %d ports for a %d-layer grant.", ...
        char(direction), numel(ports), nLayers);
end
grantPorts = ports(1:nLayers);
cfg = sixgr.util.structSet(cfg, root + ".dmrs.portSet", grantPorts);
cfg = sixgr.util.structSet(cfg, root + ".dmrs.DMRSPortSet", grantPorts);
end

function nrePerPRB = localExtractNREPerPRB(info, nPRB, modStr, nLayers)
[nrePerPRB, ~] = sixgr.util.resolveDataNREPerPRB(info, nPRB, modStr, nLayers);
end

function root = localPHYRoot(direction)
if upper(string(direction)) == "UL"
    root = "phy.pusch";
else
    root = "phy.pdsch";
end
end

function decision = localFinalizeGrantMappingType(cfg, direction, grant, symAlloc)
direction = upper(string(direction));
root = localPHYRoot(direction);
grantMap = strtrim(string(sixgr.util.structGet(grant, "MappingType", ...
    sixgr.util.structGet(grant, "mappingType", ""))));
cfgMap = strtrim(string(sixgr.util.structGet(cfg, root + ".mappingType", ...
    sixgr.util.structGet(cfg, root + ".MappingType", ""))));
if strlength(grantMap) > 0
    mapType = localNormalizeGrantMappingTypeToken(grantMap);
    source = "grant_explicit_mapping_type";
elseif strlength(cfgMap) > 0
    mapType = localNormalizeGrantMappingTypeToken(cfgMap);
    source = "configured_mapping_type";
else
    mapType = "A";
    source = "implicit_default_mapping_type";
end

sa = double(symAlloc(:).');
if numel(sa) < 2
    error("sixgr:SchedulerBase:MissingSymbolAllocation", ...
        "Grant mapping finalization requires explicit [start,count] symbols.");
end
startSym = max(0, round(double(sa(1))));
typeAPos = localResolveTypeAPosition(cfg, root);
reason = source;
if mapType == "A" && startSym > typeAPos
    if source == "implicit_default_mapping_type"
        mapType = "B";
        source = "scheduler_special_slot_legalization";
        reason = sprintf("implicit MappingType A is invalid for startSymbol=%d after DMRSTypeAPosition=%d; finalized legal MappingType B before exact PUSCH/PDSCH accounting", ...
            startSym, round(double(typeAPos)));
    else
        reason = sprintf("explicit MappingType A retained; exact resource accounting will reject startSymbol=%d after DMRSTypeAPosition=%d", ...
            startSym, round(double(typeAPos)));
    end
end
decision = struct("MappingType", string(mapType), "Source", string(source), "Reason", string(reason));
end

function mapType = localNormalizeGrantMappingTypeToken(value)
token = upper(strtrim(string(value)));
switch token
    case {"A","TYPEA","TYPE_A","MAPPINGTYPEA","MAPPING_TYPE_A"}
        mapType = "A";
    case {"B","TYPEB","TYPE_B","MAPPINGTYPEB","MAPPING_TYPE_B"}
        mapType = "B";
    otherwise
        mapType = token;
end
end

function typeAPos = localResolveTypeAPosition(cfg, root)
typeAPos = localFirstFiniteScalar( ...
    sixgr.util.structGet(cfg, root + ".dmrs.DMRSTypeAPosition", []), ...
    sixgr.util.structGet(cfg, root + ".DMRSTypeAPosition", []), ...
    sixgr.util.structGet(cfg, root + ".dmrs.typeApos", []), ...
    sixgr.util.structGet(cfg, root + ".dmrs.typeAPosition", []), ...
    sixgr.util.structGet(cfg, "phy.dmrs.DMRSTypeAPosition", []), ...
    sixgr.util.structGet(cfg, "phy.dmrs.typeApos", []), ...
    2);
typeAPos = max(2, min(3, round(double(typeAPos))));
end

function cfgOut = localApplyGrantMappingTypeToCfg(cfg, direction, mapType)
cfgOut = cfg;
root = localPHYRoot(direction);
cfgOut = sixgr.util.structSet(cfgOut, root + ".mappingType", char(string(mapType)));
cfgOut = sixgr.util.structSet(cfgOut, root + ".MappingType", char(string(mapType)));
end

function [ok, reason] = localValidateGrantResourceIntent(obj, grant)
ok = false;
reason = "unknown_resource_validation_failure";

prbSet = double(sixgr.util.structGet(grant, "PRBSet", []));
if isempty(prbSet)
    prbStart = double(sixgr.util.structGet(grant, "PRBStart", NaN));
    prbCount = double(sixgr.util.structGet(grant, "AllocatedPRBCount", ...
        sixgr.util.structGet(grant, "PRBCount", NaN)));
    if isfinite(prbStart) && isfinite(prbCount) && prbCount >= 1
        prbSet = round(prbStart):(round(prbStart) + round(prbCount) - 1);
    end
end
prbSet = double(prbSet(:).');
if isempty(prbSet) || any(~isfinite(prbSet)) || any(prbSet < 0)
    reason = "empty_or_invalid_prb_set";
    return;
end
if numel(unique(round(prbSet), "stable")) ~= numel(prbSet)
    reason = "duplicate_prb_allocation";
    return;
end
if any(abs(prbSet - round(prbSet)) > 1e-9)
    reason = "non_integer_prb_allocation";
    return;
end
nGrid = max(1, round(double(obj.NSizeGrid)));
if any(round(prbSet) >= nGrid)
    reason = "prb_out_of_carrier_grid";
    return;
end

symAlloc = double(sixgr.util.structGet(grant, "SymbolAllocation", []));
symAlloc = double(symAlloc(:).');
if numel(symAlloc) ~= 2 || ~isreal(symAlloc) || any(~isfinite(symAlloc)) || ...
        any(symAlloc~=fix(symAlloc))
    reason = "invalid_symbol_allocation";
    return;
end
if symAlloc(1) < 0 || symAlloc(2) < 1 || (symAlloc(1) + symAlloc(2)) > round(double(obj.SymbolsPerSlot))
    reason = "symbol_allocation_out_of_slot";
    return;
end

reserved = localGrantReservedRegions(obj.Cfg, grant);
if ~isempty(reserved)
    dataSymbols = symAlloc(1):(symAlloc(1) + symAlloc(2) - 1);
    for k = 1:numel(reserved)
        r = reserved(k);
        if isempty(r.PRBSet) || isempty(r.Symbols)
            continue;
        end
        if any(ismember(round(prbSet), round(double(r.PRBSet(:).')))) && ...
                any(ismember(double(dataSymbols), round(double(r.Symbols(:).'))))
            reason = "data_control_reference_resource_collision";
            return;
        end
    end
end

ok = true;
reason = "";
end

function reserved = localGrantReservedRegions(cfg, grant)
reserved = repmat(struct("PRBSet", [], "Symbols", []), 0, 1);

raw = sixgr.util.structGet(grant, "ReservedResourceRegions", struct([]));
if isstruct(raw) && ~isempty(raw)
    for i = 1:numel(raw)
        prb = double(sixgr.util.structGet(raw(i), "PRBSet", []));
        symbols = localSymbolsFromAllocation(sixgr.util.structGet(raw(i), "SymbolAllocation", []));
        if isempty(symbols)
            symbols = double(sixgr.util.structGet(raw(i), "Symbols", []));
        end
        reserved(end+1, 1) = struct("PRBSet", prb(:).', "Symbols", symbols(:).'); %#ok<AGROW>
    end
end

if upper(string(sixgr.util.structGet(grant, "Direction", "DL"))) == "DL" && ...
        logical(sixgr.util.structGet(cfg, "mac.scheduler.enforceControlReferenceCollisions", false))
    duration = double(sixgr.util.structGet(cfg, "phy.pdcch.coreset.duration", ...
        sixgr.util.structGet(cfg, "phy.pdcch.numSymbols", ...
        sixgr.util.structGet(cfg, "ctrl6gr.CORESET.DurationSymbols", 0))));
    if isscalar(duration) && isfinite(duration) && duration > 0
        nGrid = double(sixgr.util.structGet(cfg, "phy.carrier.NSizeGrid", NaN));
        if ~(isscalar(nGrid) && isfinite(nGrid) && nGrid >= 1)
            nGrid = double(sixgr.util.structGet(grant, "AllocatedPRBCount", numel(sixgr.util.structGet(grant, "PRBSet", []))));
        end
        reserved(end+1, 1) = struct("PRBSet", 0:(max(1, round(nGrid)) - 1), ...
            "Symbols", 0:(ceil(duration) - 1)); %#ok<AGROW>
    end
end
end

function symbols = localSymbolsFromAllocation(symAlloc)
symbols = [];
symAlloc = double(symAlloc(:).');
if numel(symAlloc) < 2 || any(~isfinite(symAlloc(1:2)))
    return;
end
startSym = round(symAlloc(1));
nSym = round(symAlloc(2));
if nSym < 1
    return;
end
symbols = startSym:(startSym + nSym - 1);
end

function value = localNumericIdentifierOrNaN(input)
value = str2double(string(input));
if ~(isscalar(value) && isfinite(value) && value >= 0 && ...
        value == fix(value))
    value = NaN;
end
end

function value = localRequiredDCITimingInteger(grant, field)
raw = sixgr.util.structGet(grant, field, []);
if ~(isnumeric(raw) && isreal(raw) && isscalar(raw) && ...
        isfinite(double(raw)) && double(raw) >= 0 && ...
        double(raw) == fix(double(raw)))
    error("sixgr:SchedulerBase:MissingTimingDecisionValue", ...
        "Canonical TimingDecision did not provide required %s.", field);
end
value = double(raw);
end

function [amc, modulation, targetCodeRate] = localApplyAdaptiveMCSBounds( ...
        cfg, amc, modulation, targetCodeRate, mcsTable, mode, policy)
adaptiveTokens = ["amc","adaptive","cqi","cqi_driven", ...
    "effective_sinr","effective_sinr_driven","olla","actual_bler_based"];
tokens = lower(strtrim([string(mode), string(policy)]));
if ~any(ismember(tokens, adaptiveTokens)) || ...
        ~(isfinite(double(amc.MCSIndex)) && double(amc.MCSIndex) >= 0)
    return;
end
maximumMCS = double(sixgr.util.structGet(cfg, ...
    "runtime.link_adaptation.MaximumMCSIndex", ...
    sixgr.util.structGet(cfg, "phy.linkAdaptation.maximumMCSIndex", 31)));
if ~(isscalar(maximumMCS) && isfinite(maximumMCS) && ...
        maximumMCS >= 0 && maximumMCS <= 31)
    error("sixgr:SchedulerBase:InvalidAdaptiveMaximumMCS", ...
        "Adaptive maximum MCS must be a finite integer in [0,31].");
end
maximumMCS = round(maximumMCS);
if double(amc.MCSIndex) <= maximumMCS
    return;
end
boundedMCS = maximumMCS;
profile = sixgr.link.resolveMCSProfile(mcsTable, boundedMCS);
if ~logical(sixgr.util.structGet(profile, "Valid", false))
    error("sixgr:SchedulerBase:UnsupportedAdaptiveMaximumMCS", ...
        "Configured adaptive maximum MCS %d is unavailable in table '%s'.", ...
        boundedMCS, char(string(mcsTable)));
end
amc.MCSIndex = double(boundedMCS);
amc.MCSProfile = profile;
amc.MaximumMCSBoundApplied = true;
amc.MCSValueStatus = char(localAppendStatusToken( ...
    sixgr.util.structGet(amc, "MCSValueStatus", ""), ...
    "clamped_to_yaml_maximum_mcs"));
modulation = char(string(profile.Modulation));
targetCodeRate = double(profile.TargetCodeRate);
end

function value = localAppendStatusToken(existing, suffix)
existing = strtrim(string(existing));
suffix = strtrim(string(suffix));
if strlength(existing) == 0
    value = suffix;
elseif contains(existing, suffix)
    value = existing;
else
    value = existing + "_" + suffix;
end
end
