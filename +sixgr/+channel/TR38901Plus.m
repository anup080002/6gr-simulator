classdef TR38901Plus < handle
% sixgr.channel.TR38901Plus
%
% A large-scale channel abstraction inspired by 3GPP TR 38.901:
%   - LOS probability (scenario specific)
%   - Pathloss via nrPathLoss (if available) OR ABG fallback
%   - Optional O2I penetration loss (low/high/custom)
%   - Optional log-normal shadow fading
%
% This class is intended for System-Level Simulation (SLS) and Hybrid
% abstraction paths (LLS -> BLER LUT -> abstract PHY).
%
% It does NOT generate small-scale fading taps. Use nrTDLChannel/nrCDLChannel
% for link-level fading.
%
% Notes:
%   - The formulas here are configurable; exact 3GPP compliance can be
%     enforced by selecting PathlossModel="nrPathLoss" and setting the
%     scenario parameters consistently.
%   - All text is ASCII to avoid "Invalid text character" errors.
%
% Example:
%   pl = sixgr.channel.TR38901Plus(cfg,"Scenario","UMa","Fc_Hz",3.5e9);
%   [pldB,los,ex] = pl.pathloss([0;0;25],[200;0;1.5],"IndoorRx",false);

    properties
        Scenario (1,1) string = "UMa"
        Fc_Hz (1,1) double = 3.5e9

        % "nrPathLoss" or "ABG"
        PathlossModel (1,1) string = "nrPathLoss"
        PathlossExecutionBackend (1,1) string = ""
        PathlossTruthClassification (1,1) string = ""
        PathlossApproximationReason (1,1) string = ""

        % ABG coefficients (used if PathlossModel="ABG")
        ABG struct

        % Shadow fading sigma (dB). Set 0 to disable.
        ShadowSigma_dB (1,1) double = 0

        % Propagation feature flags.
        PathlossEnabled (1,1) logical = true
        ShadowFadingEnabled (1,1) logical = true
        LOSEnabled (1,1) logical = true

        % O2I model: "none" | "low" | "high" | "custom"
        O2IModel (1,1) string = "none"
        O2ICustom_dB (1,1) double = 0

        % Random stream (for LOS draw and shadowing)
        Stream
    end

    methods
        function obj = TR38901Plus(cfg, varargin)
            % Construct from cfg + overrides
            if nargin < 1
                cfg = struct();
            end

            % Defaults from cfg
            obj.Scenario = string(localCanonicalScenario(cfg, obj.Scenario));
            obj.Fc_Hz = double(localCanonicalStructGet(cfg, "phy.fc_Hz", "channel.fc_Hz", obj.Fc_Hz));
            obj.PathlossModel = string(localCanonicalStructGet(cfg, "channel.pathlossModel", "channel.pathloss.model", obj.PathlossModel));
            obj.ShadowSigma_dB = double(localCanonicalStructGet(cfg, "channel.shadowSigma_dB", "channel.shadowFadingStd_dB", obj.ShadowSigma_dB));
            obj.PathlossEnabled = logical(sixgr.util.structGet(cfg, "channel.pathlossEnabled", obj.PathlossEnabled));
            obj.ShadowFadingEnabled = logical(sixgr.util.structGet(cfg, "channel.shadowFadingEnabled", obj.ShadowFadingEnabled));
            obj.LOSEnabled = logical(sixgr.util.structGet(cfg, "channel.losEnabled", obj.LOSEnabled));
            obj.O2IModel = string(sixgr.util.structGet(cfg, "channel.o2i.model", obj.O2IModel));
            obj.O2ICustom_dB = double(sixgr.util.structGet(cfg, "channel.o2i.custom_dB", obj.O2ICustom_dB));

            % ABG defaults (safe generic)
            obj.ABG = struct();
            obj.ABG.alpha = double(sixgr.util.structGet(cfg, "channel.abg.alpha", 3.5));
            obj.ABG.beta  = double(sixgr.util.structGet(cfg, "channel.abg.beta", 20));
            obj.ABG.gamma = double(sixgr.util.structGet(cfg, "channel.abg.gamma", 2.0));
            obj.ABG.shadowSigma_dB = double(sixgr.util.structGet(cfg, "channel.abg.shadowSigma_dB", 4.0));
            obj.ABG.d0_m = double(sixgr.util.structGet(cfg, "channel.abg.d0_m", 1.0));

            % Parse overrides
            if mod(numel(varargin),2) ~= 0
                error("TR38901Plus:BadNV","Name-value inputs must come in pairs.");
            end
            seed = [];
            for i = 1:2:numel(varargin)
                name = string(varargin{i});
                val  = varargin{i+1};
                switch lower(name)
                    case "scenario"
                        obj.Scenario = string(val);
                    case {"fc_hz","fc","frequency"}
                        obj.Fc_Hz = double(val);
                    case "pathlossmodel"
                        obj.PathlossModel = string(val);
                    case "shadowsigma_db"
                        obj.ShadowSigma_dB = double(val);
                    case "pathlossenabled"
                        obj.PathlossEnabled = logical(val);
                    case "shadowfadingenabled"
                        obj.ShadowFadingEnabled = logical(val);
                    case "losenabled"
                        obj.LOSEnabled = logical(val);
                    case "o2imodel"
                        obj.O2IModel = string(val);
                    case "o2icustom_db"
                        obj.O2ICustom_dB = double(val);
                    case "abg"
                        obj.ABG = val;
                    case "seed"
                        seed = val;
                    otherwise
                        error("TR38901Plus:UnknownOpt","Unknown option: %s", name);
                end
            end

            % Stream
            if isempty(seed)
                seed = sixgr.util.structGet(cfg, "run.seed", []);
            end
            if isempty(seed)
                obj.Stream = RandStream("mt19937ar","Seed",0);
            else
                obj.Stream = RandStream("mt19937ar","Seed",double(seed));
            end

            obj = obj.refreshPathlossTruthBoundary();

            localLogResolvedConfigOnce(cfg, obj);
        end

        function p = losProbability(obj, d2d_m, scenarioName)
            if nargin < 3 || strlength(string(scenarioName))==0
                scenarioName = obj.Scenario;
            end
            p = sixgr.channel.LOSProbability(scenarioName, d2d_m);
        end

        function los = drawLOS(obj, d2d_m, scenarioName)
            % Draw LOS/NLOS booleans using LOS probability
            p = obj.losProbability(d2d_m, scenarioName);
            u = rand(obj.Stream, size(p));
            los = (u <= p);
        end

        function [pl_dB, los, ex] = pathloss(obj, txPos_m, rxPos_m, varargin)
            % Compute pathloss with LOS draw and O2I additions.
            %
            % Inputs:
            %   txPos_m: [3 x N] or [3 x 1] (x;y;z) in meters
            %   rxPos_m: [3 x N] or [3 x 1] (x;y;z) in meters
            %
            % Name-value:
            %   "Scenario"    : override scenario name
            %   "LOS"         : provide LOS flags directly (logical)
            %   "Shadow_dB"   : provide shadow-fading values directly
            %   "O2ILoss_dB"  : provide O2I loss directly
            %   "IndoorRx"    : logical (scalar or Nx1)
            %   "IndoorDistance_m": scalar or Nx1 (for O2I)
            %   "PathlossEnabled"     : override pathloss flag
            %   "ShadowFadingEnabled" : override shadow-fading flag
            %   "LOSEnabled"          : override LOS-logic flag
            %
            opt = struct();
            opt.Scenario = obj.Scenario;
            opt.LOS = [];
            opt.Shadow_dB = [];
            opt.O2ILoss_dB = [];
            opt.IndoorRx = false;
            opt.IndoorDistance_m = [];
            opt.PathlossEnabled = obj.PathlossEnabled;
            opt.ShadowFadingEnabled = obj.ShadowFadingEnabled;
            opt.LOSEnabled = obj.LOSEnabled;

            if mod(numel(varargin),2) ~= 0
                error("TR38901Plus:pathloss:BadNV","Name-value inputs must come in pairs.");
            end
            for i = 1:2:numel(varargin)
                name = string(varargin{i});
                val  = varargin{i+1};
                switch lower(name)
                    case "scenario"
                        opt.Scenario = string(val);
                    case "los"
                        opt.LOS = logical(val);
                    case {"shadow_db","shadowfading_db"}
                        opt.Shadow_dB = double(val);
                    case {"o2iloss_db","o2i_db"}
                        opt.O2ILoss_dB = double(val);
                    case {"indoor","indoorrx"}
                        opt.IndoorRx = logical(val);
                    case {"indoordistance_m","dindoor_m","dindoor"}
                        opt.IndoorDistance_m = double(val);
                    case "pathlossenabled"
                        opt.PathlossEnabled = logical(val);
                    case "shadowfadingenabled"
                        opt.ShadowFadingEnabled = logical(val);
                    case "losenabled"
                        opt.LOSEnabled = logical(val);
                    otherwise
                        error("TR38901Plus:pathloss:UnknownOpt","Unknown option: %s", name);
                end
            end

            % Normalize dimensions
            txPos_m = double(txPos_m);
            rxPos_m = double(rxPos_m);
            if size(txPos_m,1) ~= 3 || size(rxPos_m,1) ~= 3
                error("TR38901Plus:pathloss:BadPos","txPos_m and rxPos_m must be 3xN in meters.");
            end
            N = max(size(txPos_m,2), size(rxPos_m,2));
            if size(txPos_m,2) == 1 && N > 1, txPos_m = repmat(txPos_m,1,N); end
            if size(rxPos_m,2) == 1 && N > 1, rxPos_m = repmat(rxPos_m,1,N); end

            d2d = hypot(txPos_m(1,:)-rxPos_m(1,:), txPos_m(2,:)-rxPos_m(2,:));
            d3d = sqrt(sum((txPos_m - rxPos_m).^2,1));

            % LOS
            if isempty(opt.LOS)
                if opt.LOSEnabled
                    los = obj.drawLOS(d2d, opt.Scenario);
                else
                    los = false(1,N);
                end
            else
                los = opt.LOS;
                if isscalar(los) && N > 1
                    los = repmat(los,1,N);
                end
            end
            los = logical(double(los(:)).');

            % Base pathloss
            plBase = zeros(1,N);
            if opt.PathlossEnabled
                model = lower(strtrim(obj.PathlossModel));
                if any(model == ["nrpathloss","nr"])
                    plBase = obj.pathlossViaNrPathLoss(txPos_m, rxPos_m, los, opt.Scenario);
                elseif any(model == ["abg","tr38901abg","fr3abg"])
                    plBase = sixgr.channel.PathlossABG(d3d, obj.Fc_Hz, obj.ABG, "Stream", obj.Stream);
                else
                    % Fallback: free-space path loss
                    c = 299792458;
                    lambda = c / obj.Fc_Hz;
                    plBase = 20*log10(4*pi*max(d3d,1e-3)/lambda);
                end
            end
            plBase = double(plBase(:)).';

            % Shadow fading
            sf = zeros(1,N);
            if ~isempty(opt.Shadow_dB)
                sf = double(opt.Shadow_dB);
                if isscalar(sf) && N > 1
                    sf = repmat(sf, 1, N);
                end
            elseif opt.ShadowFadingEnabled && obj.ShadowSigma_dB > 0
                sf = obj.ShadowSigma_dB .* randn(obj.Stream, 1, N);
            end
            sf = double(sf(:)).';
            if ~opt.ShadowFadingEnabled
                sf(:) = 0;
            end

            % O2I
            indoor = opt.IndoorRx;
            if isscalar(indoor) && N > 1
                indoor = repmat(indoor,1,N);
            end
            indoor = logical(double(indoor(:)).');
            o2i = zeros(1,N);
            if ~isempty(opt.O2ILoss_dB)
                o2i = double(opt.O2ILoss_dB);
                if isscalar(o2i) && N > 1
                    o2i = repmat(o2i, 1, N);
                end
            elseif opt.PathlossEnabled && any(indoor)
                if isempty(opt.IndoorDistance_m)
                    dIn = 10; % m
                else
                    dIn = opt.IndoorDistance_m;
                end
                if isscalar(dIn) && N > 1
                    dIn = repmat(dIn,1,N);
                end
                for k = 1:N
                    if indoor(k)
                        if lower(strtrim(obj.O2IModel)) == "custom"
                            o2i(k) = obj.O2ICustom_dB;
                        else
                            o2i(k) = sixgr.channel.O2ILoss(obj.Fc_Hz, obj.O2IModel, ...
                                "IndoorDistance_m", dIn(k), "Stream", obj.Stream);
                        end
                    end
                end
            end
            o2i = double(o2i(:)).';
            if ~opt.PathlossEnabled
                o2i(:) = 0;
            end

            pl_dB = plBase + sf + o2i;

            ex = struct();
            ex.d2d_m = d2d(:);
            ex.d3d_m = d3d(:);
            ex.los = los(:);
            ex.o2i_dB = o2i(:);
            ex.shadow_dB = sf(:);
            ex.base_dB = plBase(:);
            ex.scenario = opt.Scenario;
            ex.fc_Hz = obj.Fc_Hz;
            ex.model = obj.PathlossModel;
            ex.pathlossEnabled = opt.PathlossEnabled;
            ex.shadowFadingEnabled = opt.ShadowFadingEnabled;
            ex.losEnabled = opt.LOSEnabled;
        end
    end

    methods(Access=private)
        function obj = refreshPathlossTruthBoundary(obj)
            model = lower(strtrim(obj.PathlossModel));
            obj.PathlossExecutionBackend = "";
            obj.PathlossTruthClassification = "";
            obj.PathlossApproximationReason = "";

            if any(model == ["nrpathloss","nr"])
                if exist("nrPathLossConfig","class") == 8 && exist("nrPathLoss","file") == 2
                    obj.PathlossExecutionBackend = "nrpathloss_runtime_backend";
                    obj.PathlossTruthClassification = "standards_backed_3gpp_large_scale_pathloss";
                else
                    obj.PathlossExecutionBackend = "free_space_path_loss_fallback";
                    obj.PathlossTruthClassification = "approximate_fallback_not_tr38901_pathloss";
                    obj.PathlossApproximationReason = "nrpathloss_runtime_backend_unavailable_in_current_matlab_environment";
                end
            elseif any(model == ["abg","tr38901abg","fr3abg"])
                obj.PathlossExecutionBackend = "abg_large_scale_model";
                obj.PathlossTruthClassification = "approximate_abg_large_scale_pathloss_model";
                obj.PathlossApproximationReason = "abg_pathloss_is_a_configured_large_scale_abstraction_not_nrpathloss_runtime";
            else
                obj.PathlossExecutionBackend = "free_space_path_loss_shortcut";
                obj.PathlossTruthClassification = "approximate_non_tr38901_pathloss_shortcut";
                obj.PathlossApproximationReason = "configured_pathloss_model_is_not_nrpathloss_or_abg";
            end
        end

        function pl = pathlossViaNrPathLoss(obj, txPos_m, rxPos_m, los, scenarioName)
            % Use nrPathLoss if available. Otherwise, fallback to FSPL.
            N = size(txPos_m,2);
            pl = zeros(1,N);

            if exist("nrPathLossConfig","class") ~= 8 || exist("nrPathLoss","file") ~= 2
                % Fallback: FSPL
                obj.PathlossExecutionBackend = "free_space_path_loss_fallback";
                obj.PathlossTruthClassification = "approximate_fallback_not_tr38901_pathloss";
                obj.PathlossApproximationReason = "nrpathloss_runtime_backend_unavailable_in_current_matlab_environment";
                c = 299792458;
                lambda = c / obj.Fc_Hz;
                d3d = sqrt(sum((txPos_m - rxPos_m).^2,1));
                pl = 20*log10(4*pi*max(d3d,1e-3)/lambda);
                return;
            end

            obj.PathlossExecutionBackend = "nrpathloss_runtime_backend";
            obj.PathlossTruthClassification = "standards_backed_3gpp_large_scale_pathloss";
            obj.PathlossApproximationReason = "";

            % Try to configure nrPathLossConfig; keep minimal to avoid version issues.
            try
                plc = nrPathLossConfig;
                if ~isempty(scenarioName)
                    try
                        plc.Scenario = char(scenarioName);
                    catch
                        % Ignore if property differs by release
                    end
                end
            catch
                plc = nrPathLossConfig;
            end

            % nrPathLoss expects LOS as logical. Ensure correct shape.
            los = logical(los);
            if isrow(los), losRow = los; else, losRow = los.'; end

            for k = 1:N
                pl(k) = nrPathLoss(plc, obj.Fc_Hz, losRow(k), txPos_m(:,k), rxPos_m(:,k));
            end
        end
    end
end

function value = localCanonicalStructGet(cfg, canonicalPath, aliasPath, defaultValue)
value = sixgr.util.structGet(cfg, canonicalPath, []);
if isempty(value)
    value = sixgr.util.structGet(cfg, aliasPath, defaultValue);
end
end

function value = localCanonicalScenario(cfg, defaultValue)
value = sixgr.util.structGet(cfg, "channel.propagationScenario", []);
if isempty(value)
    value = sixgr.util.structGet(cfg, "run.scenario", []);
end
if isempty(value)
    value = sixgr.util.structGet(cfg, "scenario.profileName", []);
end
if isempty(value)
    value = sixgr.util.structGet(cfg, "scenario.name", defaultValue);
end
end

function localLogResolvedConfigOnce(cfg, obj)
persistent didLogResolvedConfig
if ~isempty(didLogResolvedConfig) && didLogResolvedConfig
    return;
end

verbose = logical(sixgr.util.structGet(cfg, "run.verbose", false)) || ...
    logical(sixgr.util.structGet(cfg, "logging.echo_to_console", false));
if ~verbose
    return;
end

fprintf("[TR38901Plus] Resolved config: Scenario=%s Fc_Hz=%.15g PathlossModel=%s ShadowSigma_dB=%.15g PathlossEnabled=%d ShadowEnabled=%d LOSEnabled=%d\n", ...
    char(obj.Scenario), double(obj.Fc_Hz), char(obj.PathlossModel), double(obj.ShadowSigma_dB), ...
    double(obj.PathlossEnabled), double(obj.ShadowFadingEnabled), double(obj.LOSEnabled));
didLogResolvedConfig = true;
end
