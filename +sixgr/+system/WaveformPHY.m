classdef WaveformPHY < handle
% sixgr.system.WaveformPHY
% Experimental system PHY backend using grant-level waveform replay.

    properties
        Cfg struct
        StrictMode (1,1) logical = false
        CompactPHYIO (1,1) logical = true
        FastAWGNPath (1,1) logical = false
        AdaptiveLDPC (1,1) logical = true
        LDPCMaxIterations (1,1) double = 0
        UseGPU (1,1) logical = false
        LongRunAuditEnabled (1,1) logical = false
        LongRunAuditPeriodSlots (1,1) double = Inf
        LongRunAuditMaxGrantsPerSlot (1,1) double = Inf
        Stream
        ExecutionBackend (1,1) string = "WAVEFORM_SYSTEM_PHY"
        PHYMode (1,1) string = "GRANT_CRC_WAVEFORM_REPLAY_EXPERIMENTAL"
        LastReplay struct = struct()
    end

    methods
        function obj = WaveformPHY(cfg, params, varargin)
            if nargin < 1 || isempty(cfg)
                cfg = sixgr.config.defaultConfig();
            end
            if nargin < 2 || isempty(params)
                params = struct();
            end

            obj.Cfg = cfg;
            obj.StrictMode = logical(sixgr.util.structGet(params, "StrictMode", ...
                sixgr.util.structGet(cfg, "run.strictMode", false)));
            obj.CompactPHYIO = logical(sixgr.util.structGet(params, "WaveformCompactPHYIO", ...
                sixgr.util.structGet(params, "CompactPHYIO", true)));
            obj.FastAWGNPath = logical(sixgr.util.structGet(params, "WaveformFastAWGNPath", ...
                sixgr.util.structGet(params, "FastAWGNPath", false)));
            obj.AdaptiveLDPC = logical(sixgr.util.structGet(params, "WaveformAdaptiveLDPC", ...
                sixgr.util.structGet(params, "AdaptiveLDPC", true)));
            obj.LDPCMaxIterations = double(sixgr.util.structGet(params, "WaveformLDPCMaxIterations", ...
                sixgr.util.structGet(params, "LDPCMaxIterations", 0)));
            obj.UseGPU = logical(sixgr.util.structGet(params, "WaveformUseGPU", ...
                sixgr.util.structGet(params, "UseGPU", false)));
            obj.LongRunAuditEnabled = logical(sixgr.util.structGet(params, "WaveformLongRunAuditEnabled", ...
                sixgr.util.structGet(cfg, "system.waveform.longRunAudit.enabled", false)));
            obj.LongRunAuditPeriodSlots = double(sixgr.util.structGet(params, "WaveformLongRunAuditPeriodSlots", ...
                sixgr.util.structGet(cfg, "system.waveform.longRunAudit.periodSlots", Inf)));
            obj.LongRunAuditMaxGrantsPerSlot = double(sixgr.util.structGet(params, "WaveformLongRunAuditMaxGrantsPerSlot", ...
                sixgr.util.structGet(cfg, "system.waveform.longRunAudit.maxGrantsPerAuditSlot", Inf)));
            if obj.LongRunAuditEnabled
                obj.PHYMode = "GRANT_CRC_WAVEFORM_REPLAY_AUDITED_LONG_RUN";
            end

            seed = double(sixgr.util.structGet(cfg, "run.seed", 1)) + 31;
            if ~isempty(varargin)
                for i = 1:2:numel(varargin)
                    key = lower(char(string(varargin{i})));
                    val = varargin{i+1};
                    if strcmp(key, "seed")
                        seed = double(val);
                    elseif strcmp(key, "strictmode")
                        obj.StrictMode = logical(val);
                    end
                end
            end
            obj.Stream = RandStream("mt19937ar", "Seed", seed);
        end

        function bler = mapBLER(obj, in)
            replay = obj.localReplay(in);
            bler = double(replay.BLER);
        end

        function [ok, bler] = decode(obj, in)
            replay = obj.localReplay(in);
            ok = logical(replay.Ok);
            bler = double(replay.BLER);
        end
    end

    methods(Access = private)
        function replay = localReplay(obj, ctx)
            if ~isstruct(ctx) || ~isfield(ctx, "Grant") || isempty(ctx.Grant)
                error("sixgr:system:WaveformPHY:MissingGrant", ...
                    "WaveformPHY requires ctx.Grant to replay real system grants.");
            end

            if obj.localShouldDeferReplay(ctx)
                replay = obj.localDeferredReplay(ctx);
                obj.LastReplay = replay;
                return;
            end

            grantReplay = ctx.Grant;
            if isfield(grantReplay, "TBSBits")
                grantReplay = rmfield(grantReplay, "TBSBits");
            end
            if isfield(grantReplay, "TBSBytes")
                grantReplay = rmfield(grantReplay, "TBSBytes");
            end

            replay = sixgr.system.waveform.replayGrant(obj.Cfg, ...
                sixgr.util.structGet(ctx, "Direction", "DL"), ...
                grantReplay, [], ...
                double(sixgr.util.structGet(ctx, "SINR_dB", NaN)), ...
                "InputFormat", "bits", ...
                "StrictMode", obj.StrictMode, ...
                "CompactPHYIO", obj.CompactPHYIO, ...
                "FastAWGNPath", obj.FastAWGNPath, ...
                "AdaptiveLDPC", obj.AdaptiveLDPC, ...
                "LDPCMaxIterations", obj.LDPCMaxIterations, ...
                "UseGPU", obj.UseGPU);

            if strlength(strtrim(string(sixgr.util.structGet(replay, "PHYDecisionRole", "")))) == 0
                replay.PHYDecisionRole = "measured";
            end
            if strlength(strtrim(string(sixgr.util.structGet(replay, "PHYDecisionStatus", "")))) == 0
                replay.PHYDecisionStatus = "OK";
            end
            if strlength(strtrim(string(sixgr.util.structGet(replay, "PHYDecisionSource", "")))) == 0
                replay.PHYDecisionSource = "sixgr.system.waveform.replayGrant";
            end
            if strlength(strtrim(string(sixgr.util.structGet(replay, "PHYDecisionReason", "")))) == 0
                replay.PHYDecisionReason = "waveform_replay_executed";
            end
            replay.WaveformReplayExecuted = logical(sixgr.util.structGet(replay, "WaveformReplayExecuted", true));
            replay.WaveformReplayReused = logical(sixgr.util.structGet(replay, "WaveformReplayReused", false));
            replay.WaveformReplayKey = obj.localReplayKey(ctx);
            obj.LastReplay = replay;
        end

        function tf = localShouldDeferReplay(obj, ctx)
            tf = false;
            if ~obj.LongRunAuditEnabled
                return;
            end
            periodSlots = max(1, round(double(obj.LongRunAuditPeriodSlots)));
            maxGrant = max(0, round(double(obj.LongRunAuditMaxGrantsPerSlot)));
            tti = max(1, round(double(sixgr.util.structGet(ctx, "TTI", 1))));
            grantIndex = max(1, round(double(sixgr.util.structGet(ctx, "GrantIndex", 1))));
            auditSlot = mod(tti - 1, periodSlots) == 0;
            tf = ~(auditSlot && grantIndex <= maxGrant);
        end

        function replay = localDeferredReplay(obj, ctx)
            reason = "not_executed_long_run_waveform_audit_budget";
            replay = struct( ...
                "Ok", false, ...
                "BLER", NaN, ...
                "Notes", reason, ...
                "UsedFading", false, ...
                "FastAWGNPath", false, ...
                "ChannelModel", string(sixgr.util.structGet(obj.Cfg, "channel.delayProfile", ...
                    sixgr.util.structGet(obj.Cfg, "channel.model", ""))), ...
                "ExecutionBackend", obj.ExecutionBackend, ...
                "PHYMode", obj.PHYMode, ...
                "TransportBlockSize", double(sixgr.util.structGet(ctx, "TBSBits", NaN)), ...
                "DecoderIterations", NaN, ...
                "EffectiveTxAntennas", NaN, ...
                "EffectiveRxAntennas", NaN, ...
                "PHYDecisionRole", "unavailable", ...
                "PHYDecisionStatus", "NOT_AVAILABLE", ...
                "PHYDecisionSource", "sixgr.system.WaveformPHY.longRunAudit", ...
                "PHYDecisionReason", reason, ...
                "WaveformReplayExecuted", false, ...
                "WaveformReplayReused", false, ...
                "WaveformReplayKey", obj.localReplayKey(ctx));
        end

        function key = localReplayKey(obj, ctx)
            grant = sixgr.util.structGet(ctx, "Grant", struct());
            prbCount = double(sixgr.util.structGet(ctx, "PRBCount", NaN));
            sinr = double(sixgr.util.structGet(ctx, "SINR_dB", NaN));
            if isfinite(sinr)
                sinr = round(sinr, 1);
            end
            key = sprintf("%s|tti=%g|grant=%g|cell=%g|ue=%g|prb=%g|mcs=%g|rv=%g|sinr=%.1f", ...
                upper(char(string(sixgr.util.structGet(ctx, "Direction", "")))), ...
                double(sixgr.util.structGet(ctx, "TTI", NaN)), ...
                double(sixgr.util.structGet(ctx, "GrantIndex", NaN)), ...
                double(sixgr.util.structGet(ctx, "ServingCellID", NaN)), ...
                double(sixgr.util.structGet(grant, "RNTI", NaN)), ...
                prbCount, ...
                double(sixgr.util.structGet(ctx, "MCSIndex", NaN)), ...
                double(sixgr.util.structGet(sixgr.util.structGet(grant, "HARQ", struct()), "RV", NaN)), ...
                sinr);
            key = string(key);
        end
    end
end
