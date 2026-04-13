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
                opt.Model = string(sixgr.util.structGet(cfg, "channel.model", ...
                    sixgr.util.structGet(cfg, "channel.type", "nrTDL")));
            end
            [cfg, model] = sixgr.channel.ChannelFactory.localResolveModel(cfg, opt.Model);

            % Resolve carrier frequency if possible (used by some models)
            if isempty(opt.Fc_Hz)
                opt.Fc_Hz = sixgr.util.structGet(cfg, "phy.fc_Hz", 3.5e9);
            end
            if strlength(opt.Scenario) == 0
                opt.Scenario = string(sixgr.util.structGet(cfg, "channel.propagationScenario", ...
                    sixgr.util.structGet(cfg, "run.scenario", ...
                    sixgr.util.structGet(cfg, "scenario.profileName", ...
                    sixgr.util.structGet(cfg, "scenario.name", "UMa")))));
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
                args = {"Fc_Hz", opt.Fc_Hz, "Seed", opt.Seed};
                if strlength(opt.Scenario) > 0
                    args = [{"Scenario", opt.Scenario}, args];
                end
                chObj = sixgr.channel.TR38901Plus(cfg, args{:});
                ch = struct("Type","TR38901Plus","Object",chObj,"IsFading",false,"IsLargeScaleOnly",true,"Meta",meta);
            elseif any(model == ["raytracing","ray","rt"])
                args = {"Fc_Hz", opt.Fc_Hz, "Viewer", opt.Viewer};
                if strlength(opt.Scenario) > 0
                    args = [{"Scenario", opt.Scenario}, args];
                end
                chObj = sixgr.channel.RayTracingAdapter(cfg, args{:});
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
            delayProfile = sixgr.channel.ChannelFactory.localResolveConcreteDelayProfile(cfg, "TDL");
            if exist("nrTDLChannel","class") ~= 8
                error("ChannelFactory:TDL:Missing5G", "nrTDLChannel not found. Install/enable 5G Toolbox.");
            end

            tdl = nrTDLChannel;

            % Basic profile parameters
            tdl.DelayProfile = delayProfile;
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
            delayProfile = sixgr.channel.ChannelFactory.localResolveConcreteDelayProfile(cfg, "CDL");
            if exist("nrCDLChannel","class") ~= 8
                error("ChannelFactory:CDL:Missing5G", "nrCDLChannel not found. Install/enable 5G Toolbox.");
            end

            cdl = nrCDLChannel;
            cdl.DelayProfile = delayProfile;
            cdl.DelaySpread = sixgr.util.structGet(cfg, "channel.delaySpread_s", 300e-9);
            cdl.MaximumDopplerShift = sixgr.util.structGet(cfg, "channel.doppler_Hz", 30);
            cdl.TransmitAntennaArray = sixgr.channel.ChannelFactory.localConfigureCDLAntennaArray( ...
                cdl.TransmitAntennaArray, opt.NumTxAnt, ...
                sixgr.util.structGet(cfg, "antenna_and_array.bs_array_geometry", "ura"), ...
                sixgr.util.structGet(cfg, "antenna_and_array.polarization", ""));
            cdl.ReceiveAntennaArray = sixgr.channel.ChannelFactory.localConfigureCDLAntennaArray( ...
                cdl.ReceiveAntennaArray, opt.NumRxAnt, ...
                sixgr.util.structGet(cfg, "antenna_and_array.ue_array_geometry", "ula"), ...
                sixgr.util.structGet(cfg, "antenna_and_array.polarization", ""));

            if ~isempty(opt.SampleRate)
                cdl.SampleRate = opt.SampleRate;
            end
            if ~isempty(opt.Fc_Hz)
                cdl.CarrierFrequency = double(opt.Fc_Hz);
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

        function arr = localConfigureCDLAntennaArray(arr, numAnt, geometry, polarization)
            numAnt = max(1, round(double(numAnt)));
            polCount = sixgr.channel.ChannelFactory.localResolveCDLPolarizationCount(numAnt, polarization);
            spatialCount = max(1, round(numAnt / polCount));
            arr.Size = sixgr.channel.ChannelFactory.localResolveCDLArraySize(spatialCount, polCount, geometry);
            arr.PolarizationAngles = sixgr.channel.ChannelFactory.localResolveCDLPolarizationAngles( ...
                arr.PolarizationAngles, polCount);
        end

        function polCount = localResolveCDLPolarizationCount(numAnt, polarization)
            polToken = lower(strtrim(char(string(polarization))));
            wantsDual = any(strcmp(polToken, {"dual", "dual_pol", "dualpolarized", "dual-polarized", ...
                "cross", "cross_pol", "cross-polarized", "cross_polarized"}));
            polCount = 1;
            if wantsDual && mod(numAnt, 2) == 0
                polCount = 2;
            end
        end

        function sizeVec = localResolveCDLArraySize(spatialCount, polCount, geometry)
            geom = lower(strtrim(char(string(geometry))));
            switch geom
                case {"ura", "upa", "planar", "rectangular"}
                    nRow = floor(sqrt(double(spatialCount)));
                    nRow = max(1, nRow);
                    while mod(spatialCount, nRow) ~= 0
                        nRow = nRow - 1;
                    end
                    nCol = max(1, round(spatialCount / nRow));
                    sizeVec = [nRow nCol polCount 1 1];
                otherwise
                    sizeVec = [spatialCount 1 polCount 1 1];
            end
        end

        function angles = localResolveCDLPolarizationAngles(currentAngles, polCount)
            currentAngles = reshape(double(currentAngles), 1, []);
            if polCount == 1
                if isempty(currentAngles)
                    angles = 0;
                else
                    angles = currentAngles(1);
                end
                return;
            end

            if numel(currentAngles) >= 2
                angles = currentAngles(1:2);
            elseif numel(currentAngles) == 1
                angles = [currentAngles(1), -currentAngles(1)];
            else
                angles = [45, -45];
            end
        end

        function [cfgOut, model] = localResolveModel(cfg, rawModel)
            cfgOut = cfg;
            modelToken = sixgr.channel.ChannelFactory.localNormalizeToken(rawModel);
            if sixgr.channel.ChannelFactory.localIsConcreteTDLProfile(modelToken)
                cfgOut = sixgr.channel.ChannelFactory.localAssignConcreteProfile(cfgOut, "TDL", modelToken);
                model = "tdl";
            elseif sixgr.channel.ChannelFactory.localIsConcreteCDLProfile(modelToken)
                cfgOut = sixgr.channel.ChannelFactory.localAssignConcreteProfile(cfgOut, "CDL", modelToken);
                model = "cdl";
            elseif any(strcmp(modelToken, {'NRTDL', 'TDL'}))
                model = "tdl";
            elseif any(strcmp(modelToken, {'NRCDL', 'CDL'}))
                model = "cdl";
            else
                model = lower(string(modelToken));
            end
        end

        function profile = localResolveConcreteDelayProfile(cfg, family)
            family = char(upper(string(family)));
            if strcmp(family, 'TDL')
                ownProfilePath = "channel.tdlProfile";
                otherProfilePath = "channel.cdlProfile";
                exampleProfile = 'TDL-C';
            elseif strcmp(family, 'CDL')
                ownProfilePath = "channel.cdlProfile";
                otherProfilePath = "channel.tdlProfile";
                exampleProfile = 'CDL-D';
            else
                error("ChannelFactory:BadDelayProfile", "Unsupported channel family '%s'.", family);
            end

            fields = { ...
                "channel.model", ...
                char(ownProfilePath), ...
                char(otherProfilePath), ...
                "channel.delayProfile", ...
                "channel.fading.profile", ...
                "channel.fading.model" ...
                };

            ownProfiles = strings(0, 1);
            ownFields = strings(0, 1);
            otherProfiles = strings(0, 1);
            otherFields = strings(0, 1);
            for i = 1:numel(fields)
                path = char(fields{i});
                value = sixgr.channel.ChannelFactory.localNormalizeToken( ...
                    sixgr.util.structGet(cfg, path, ""));
                if strcmp(family, 'TDL')
                    if sixgr.channel.ChannelFactory.localIsConcreteTDLProfile(value)
                        ownProfiles(end+1, 1) = string(value); %#ok<AGROW>
                        ownFields(end+1, 1) = string(path); %#ok<AGROW>
                    elseif sixgr.channel.ChannelFactory.localIsConcreteCDLProfile(value)
                        otherProfiles(end+1, 1) = string(value); %#ok<AGROW>
                        otherFields(end+1, 1) = string(path); %#ok<AGROW>
                    end
                else
                    if sixgr.channel.ChannelFactory.localIsConcreteCDLProfile(value)
                        ownProfiles(end+1, 1) = string(value); %#ok<AGROW>
                        ownFields(end+1, 1) = string(path); %#ok<AGROW>
                    elseif sixgr.channel.ChannelFactory.localIsConcreteTDLProfile(value)
                        otherProfiles(end+1, 1) = string(value); %#ok<AGROW>
                        otherFields(end+1, 1) = string(path); %#ok<AGROW>
                    end
                end
            end

            sixgr.channel.ChannelFactory.localRejectBareDelayProfile( ...
                sixgr.util.structGet(cfg, char(ownProfilePath), ""), char(ownProfilePath), family, exampleProfile);
            sixgr.channel.ChannelFactory.localRejectBareDelayProfile( ...
                sixgr.util.structGet(cfg, char(otherProfilePath), ""), char(otherProfilePath), family, exampleProfile);
            sixgr.channel.ChannelFactory.localRejectBareDelayProfile( ...
                sixgr.util.structGet(cfg, "channel.delayProfile", ""), "channel.delayProfile", family, exampleProfile);
            sixgr.channel.ChannelFactory.localRejectBareDelayProfile( ...
                sixgr.util.structGet(cfg, "channel.fading.profile", ""), "channel.fading.profile", family, exampleProfile);

            ownProfiles = unique(ownProfiles, "stable");
            otherProfiles = unique(otherProfiles, "stable");
            if ~isempty(otherProfiles)
                error("ChannelFactory:BadDelayProfile", ...
                    "%s channel construction conflicts with opposite-family concrete profile(s) %s across %s.", ...
                    family, strjoin(cellstr(otherProfiles), ", "), strjoin(cellstr(unique(otherFields, "stable")), ", "));
            end
            if numel(ownProfiles) > 1
                error("ChannelFactory:BadDelayProfile", ...
                    "%s channel construction has conflicting concrete delay profiles %s across %s.", ...
                    family, strjoin(cellstr(ownProfiles), ", "), strjoin(cellstr(unique(ownFields, "stable")), ", "));
            end
            if isempty(ownProfiles)
                error("ChannelFactory:BadDelayProfile", ...
                    "%s channel construction requires a concrete delay profile such as %s. Bare family names are not allowed.", ...
                    family, exampleProfile);
            end
            profile = char(ownProfiles(1));
        end

        function localRejectBareDelayProfile(rawValue, fieldName, family, exampleProfile)
            value = sixgr.channel.ChannelFactory.localNormalizeToken(rawValue);
            if strcmp(value, 'TDL') || strcmp(value, 'CDL')
                error("ChannelFactory:BadDelayProfile", ...
                    "%s='%s' is ambiguous for %s channel construction. Use a concrete profile such as %s.", ...
                    fieldName, value, family, exampleProfile);
            end
        end

        function cfgOut = localAssignConcreteProfile(cfg, family, profile)
            cfgOut = cfg;
            if ~isfield(cfgOut, "channel") || ~isstruct(cfgOut.channel)
                cfgOut.channel = struct();
            end
            profile = sixgr.channel.ChannelFactory.localNormalizeToken(profile);
            if strcmp(char(family), 'TDL')
                cfgOut.channel.tdlProfile = char(profile);
            else
                cfgOut.channel.cdlProfile = char(profile);
            end
        end

        function token = localNormalizeToken(rawValue)
            token = upper(strtrim(char(string(rawValue))));
        end

        function tf = localIsConcreteTDLProfile(profile)
            profile = sixgr.channel.ChannelFactory.localNormalizeToken(profile);
            tf = startsWith(profile, 'TDL') && ~strcmp(profile, 'TDL');
        end

        function tf = localIsConcreteCDLProfile(profile)
            profile = sixgr.channel.ChannelFactory.localNormalizeToken(profile);
            tf = startsWith(profile, 'CDL') && ~strcmp(profile, 'CDL');
        end
    end
end
