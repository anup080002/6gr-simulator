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

            obj.LastReplay = replay;
        end
    end
end
