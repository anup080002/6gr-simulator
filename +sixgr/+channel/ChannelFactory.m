classdef ChannelFactory
% sixgr.channel.ChannelFactory
%
% Factory to create channel models used by Link/System/Hybrid simulations.
% This layer is intentionally robust:
%   - If a requested toolbox/class is unavailable, it throws a clear error.
%   - If WNS is unavailable, it does not matter (this is independent).
%
% Supported cfg.channel.model values (case-insensitive):
%   "nrTDL" | "TDL"         -> nrTDLChannel
%   "nrCDL" | "CDL"         -> nrCDLChannel
%   "TR38901" | "ABG"       -> TR38901Plus (large-scale abstraction)
%   "RayTracing" | "RT"     -> RayTracingAdapter (requires RF Propagation)
%   "AWGN" | "None"         -> no fading channel (placeholder)
%
% Typical usage:
%   ch = sixgr.channel.ChannelFactory.create(cfg, "SampleRate",fs, ...
%        "NumTxAnt",Nt, "NumRxAnt",Nr, "Scenario",cfg.run.scenario);
%
% The returned struct has fields:
%   .Type        - string identifier
%   .Object      - channel object/adapter (or [])
%   .IsFading    - logical
%   .IsLargeScaleOnly - logical
%   .Meta        - struct with derived parameters
%
% Note: This file uses only ASCII characters to avoid "Invalid text character"
% errors caused by copied rich-text punctuation.
%
% See also: sixgr.channel.TR38901Plus, sixgr.channel.RayTracingAdapter

    methods(Static)
        function ch = create(cfg, varargin)
            % Parse options (lightweight name-value parsing)
            opt = struct();
            opt.Model = "";
            % Optional call-site convenience (not used by channel objects)
            % but useful for higher-layer orchestration.
            opt.LinkDirection = ""; % "downlink"|"uplink"|"dl"|"ul"
            opt.SampleRate = [];
            opt.NumTxAnt = [];
            opt.NumRxAnt = [];
            opt.Scenario = "";
            opt.Fc_Hz = [];
            opt.Viewer = [];
            opt.EnableSpatialNonStationarity = [];
            opt.Seed = [];

            % Backward compatibility:
            %   create(cfg,'downlink')   % legacy smoke-test call
            %   create(cfg,'tdl')        % shorthand for model
            if mod(numel(varargin),2) ~= 0
                if numel(varargin) == 1 && (ischar(varargin{1}) || isstring(varargin{1}))
                    tok = lower(string(varargin{1}));
                    if any(tok == ["downlink","dl","uplink","ul"])
                        varargin = {"LinkDirection", char(tok)};
                    else
                        varargin = {"Model", char(tok)};
                    end
                else
                    error("ChannelFactory:create:BadNV", "Name-value inputs must come in pairs.");
                end
            end
            for i = 1:2:numel(varargin)
                name = string(varargin{i});
                val  = varargin{i+1};
                switch lower(name)
                    case "model"
                        opt.Model = string(val);
                    case {"linkdirection","direction","link"}
                        opt.LinkDirection = string(val);
                    case "samplerate"
                        opt.SampleRate = val;
                    case {"numtxant","ntx","numtx"}
                        opt.NumTxAnt = val;
                    case {"numrxant","nrx","numrx"}
                        opt.NumRxAnt = val;
                    case "scenario"
                        opt.Scenario = string(val);
                    case {"fc_hz","fc","frequency"}
                        opt.Fc_Hz = val;
                    case "viewer"
                        opt.Viewer = val;
                    case {"enablespatialnonstationarity","spatialnonstationarity"}
                        opt.EnableSpatialNonStationarity = logical(val);
                    case "seed"
                        opt.Seed = val;
                    otherwise
                        error("ChannelFactory:create:UnknownOpt", "Unknown option: %s", name);
                end
            end

            % Resolve model from cfg if not provided
            if strlength(opt.Model) == 0
                opt.Model = string(sixgr.util.structGet(cfg, "channel.model", "nrTDL"));
            end
            model = lower(strtrim(opt.Model));

            % Resolve carrier frequency if possible (used by some models)
            if isempty(opt.Fc_Hz)
                opt.Fc_Hz = sixgr.util.structGet(cfg, "phy.fc_Hz", 3.5e9);
            end

            % Resolve antenna counts
            if isempty(opt.NumTxAnt)
                opt.NumTxAnt = sixgr.util.structGet(cfg, "channel.nTxAnt", 1);
            end
            if isempty(opt.NumRxAnt)
                opt.NumRxAnt = sixgr.util.structGet(cfg, "channel.nRxAnt", 1);
            end

            % Spatial non-stationarity enable flag
            if isempty(opt.EnableSpatialNonStationarity)
                opt.EnableSpatialNonStationarity = logical(sixgr.util.structGet(cfg, "channel.spatialNonStationary.enable", false));
            end

            meta = struct();
            meta.Model = model;
            meta.Fc_Hz = opt.Fc_Hz;
            meta.SampleRate = opt.SampleRate;
            meta.NumTxAnt = opt.NumTxAnt;
            meta.NumRxAnt = opt.NumRxAnt;
            meta.Scenario = opt.Scenario;
            meta.LinkDirection = opt.LinkDirection;

            % Create channel
            if any(model == ["awgn","none","off",""])
                ch = struct("Type","AWGN","Object",[],"IsFading",false,"IsLargeScaleOnly",false,"Meta",meta);
                return;
            end

            if any(model == ["nrtdl","tdl"])
                chObj = sixgr.channel.ChannelFactory.localCreateTDL(cfg, opt);
                ch = struct("Type","nrTDLChannel","Object",chObj,"IsFading",true,"IsLargeScaleOnly",false,"Meta",meta);
            elseif any(model == ["nrcdl","cdl"])
                chObj = sixgr.channel.ChannelFactory.localCreateCDL(cfg, opt);
                ch = struct("Type","nrCDLChannel","Object",chObj,"IsFading",true,"IsLargeScaleOnly",false,"Meta",meta);
            elseif any(model == ["tr38901","tr38.901","tr38_901","abg","large","abstract"])
                chObj = sixgr.channel.TR38901Plus(cfg, "Scenario", opt.Scenario, "Fc_Hz", opt.Fc_Hz, "Seed", opt.Seed);
                ch = struct("Type","TR38901Plus","Object",chObj,"IsFading",false,"IsLargeScaleOnly",true,"Meta",meta);
            elseif any(model == ["raytracing","ray","rt"])
                chObj = sixgr.channel.RayTracingAdapter(cfg, "Scenario", opt.Scenario, "Fc_Hz", opt.Fc_Hz, "Viewer", opt.Viewer);
                ch = struct("Type","RayTracing","Object",chObj,"IsFading",false,"IsLargeScaleOnly",true,"Meta",meta);
            else
                error("ChannelFactory:create:UnknownModel", "Unsupported cfg.channel.model='%s'.", model);
            end

            % Spatial non-stationarity hook (optional metadata only)
            if opt.EnableSpatialNonStationarity
                try
                    vis = sixgr.channel.SpatialNonStationarity(cfg, ...
                        "NumTxAnt", opt.NumTxAnt, "NumRxAnt", opt.NumRxAnt, "Seed", opt.Seed);
                    ch.Meta.SpatialNonStationarity = vis;
                catch ME
                    % Non-fatal: keep channel but warn in metadata
                    ch.Meta.SpatialNonStationarity = struct("enable",true,"error",string(ME.message));
                end
            end
        end
    end

    methods(Static, Access=private)
        function tdl = localCreateTDL(cfg, opt)
            if exist("nrTDLChannel","class") ~= 8
                error("ChannelFactory:TDL:Missing5G", "nrTDLChannel not found. Install/enable 5G Toolbox.");
            end

            tdl = nrTDLChannel;

            % Basic profile parameters
            tdl.DelayProfile = char(sixgr.util.structGet(cfg, "channel.tdlProfile", "TDL-C"));
            tdl.DelaySpread = sixgr.util.structGet(cfg, "channel.delaySpread_s", 300e-9);
            tdl.MaximumDopplerShift = sixgr.util.structGet(cfg, "channel.doppler_Hz", 30);
            tdl.NumTransmitAntennas = opt.NumTxAnt;
            tdl.NumReceiveAntennas  = opt.NumRxAnt;

            if ~isempty(opt.SampleRate)
                tdl.SampleRate = opt.SampleRate;
            end

            % Disable channel filtering if caller wants raw path gains (optional)
            tdl.ChannelFiltering = logical(sixgr.util.structGet(cfg, "channel.channelFiltering", true));

            % Deterministic RNG (optional)
            seed = [];
            if ~isempty(opt.Seed)
                seed = opt.Seed;
            else
                seed = sixgr.util.structGet(cfg, "channel.seed", []);
            end
            if ~isempty(seed)
                tdl.RandomStream = "mt19937ar with seed";
                tdl.Seed = double(seed);
            end
        end

        function cdl = localCreateCDL(cfg, opt)
            if exist("nrCDLChannel","class") ~= 8
                error("ChannelFactory:CDL:Missing5G", "nrCDLChannel not found. Install/enable 5G Toolbox.");
            end

            cdl = nrCDLChannel;
            cdl.DelayProfile = char(sixgr.util.structGet(cfg, "channel.cdlProfile", "CDL-D"));
            cdl.DelaySpread = sixgr.util.structGet(cfg, "channel.delaySpread_s", 300e-9);
            cdl.MaximumDopplerShift = sixgr.util.structGet(cfg, "channel.doppler_Hz", 30);
            cdl.NumTransmitAntennas = opt.NumTxAnt;
            cdl.NumReceiveAntennas  = opt.NumRxAnt;

            if ~isempty(opt.SampleRate)
                cdl.SampleRate = opt.SampleRate;
            end
            cdl.ChannelFiltering = logical(sixgr.util.structGet(cfg, "channel.channelFiltering", true));

            seed = [];
            if ~isempty(opt.Seed)
                seed = opt.Seed;
            else
                seed = sixgr.util.structGet(cfg, "channel.seed", []);
            end
            if ~isempty(seed)
                cdl.RandomStream = "mt19937ar with seed";
                cdl.Seed = double(seed);
            end
        end
    end
end
