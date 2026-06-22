classdef TR38901Plus < handle
% sixgr.channel.TR38901Plus
%
% A large-scale channel abstraction inspired by 3GPP TR 38.901:
%   - LOS probability (scenario specific)
%   - Pathloss via nrPathLoss where available, or standards-backed
%     TR 38.901 closed-form analytical equations for supported scenarios
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
        PathlossModelSource (1,1) string = ""
        PathlossComplianceStatus (1,1) string = ""
        FallbackUsedForPathloss (1,1) logical = false

        % ABG coefficients (used if PathlossModel="ABG")
        ABG struct

        % Shadow fading sigma (dB). Set 0 to disable.
        ShadowSigma_dB (1,1) double = 0

        % Propagation feature flags.
        PathlossEnabled (1,1) logical = true
        ShadowFadingEnabled (1,1) logical = true
        LOSEnabled (1,1) logical = true
        AtmosphericAbsorptionEnabled (1,1) logical = false

        % O2I model: "none" | "low" | "high" | "custom"
        O2IModel (1,1) string = "none"
        O2ICustom_dB (1,1) double = 0
        O2IModelSource (1,1) string = ""
        O2IComplianceStatus (1,1) string = ""
        O2IComplianceReason (1,1) string = ""

        LOSProbabilitySource (1,1) string = ""
        LOSComplianceStatus (1,1) string = ""
        LOSComplianceReason (1,1) string = ""

        ChannelComplianceMode (1,1) string = "approximate_38901_plus"

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
            obj.AtmosphericAbsorptionEnabled = logical(localFirstStructGet(cfg, ...
                ["channel.atmosphericAbsorptionEnabled", "channel.oxygenAbsorptionEnabled", ...
                 "channel.atmospheric_absorption.enabled", "channel.oxygen_absorption.enabled"], ...
                obj.AtmosphericAbsorptionEnabled));
            obj.ChannelComplianceMode = string(localCanonicalStructGet(cfg, "channel.complianceMode", "channel.compliance.mode", ...
                localDefaultChannelComplianceMode(cfg)));
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
                    case {"atmosphericabsorptionenabled","oxygenabsorptionenabled"}
                        obj.AtmosphericAbsorptionEnabled = logical(val);
                    case {"channelcompliancemode","compliancemode"}
                        obj.ChannelComplianceMode = string(val);
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

            obj.ChannelComplianceMode = localNormalizeChannelComplianceMode(obj.ChannelComplianceMode);
            obj = obj.refreshPathlossTruthBoundary();

            localLogResolvedConfigOnce(cfg, obj);
        end

        function [p, status] = losProbability(obj, d2d_m, scenarioName, varargin)
            if nargin < 3 || strlength(string(scenarioName))==0
                scenarioName = obj.Scenario;
            end
            [p, status] = sixgr.channel.LOSProbability(scenarioName, d2d_m, varargin{:});
            obj.LOSProbabilitySource = string(status.Source);
            obj.LOSComplianceStatus = string(status.ComplianceStatus);
            obj.LOSComplianceReason = string(status.Reason);
            if obj.ChannelComplianceMode == "strict_38901" && ~logical(status.StrictSupported)
                error("TR38901Plus:StrictLOSUnsupported", ...
                    "Strict 38.901 mode does not allow LOS probability fallback for scenario '%s'.", ...
                    char(string(scenarioName)));
            end
        end

        function los = drawLOS(obj, d2d_m, scenarioName, varargin)
            % Draw LOS/NLOS booleans using LOS probability
            [p, ~] = obj.losProbability(d2d_m, scenarioName, varargin{:});
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
            %   "AtmosphericAbsorptionEnabled": add configured gaseous loss
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
            opt.AtmosphericAbsorptionEnabled = obj.AtmosphericAbsorptionEnabled;

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
                    case {"atmosphericabsorptionenabled","oxygenabsorptionenabled"}
                        opt.AtmosphericAbsorptionEnabled = logical(val);
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
                    los = obj.drawLOS(d2d, opt.Scenario, "HUT_m", rxPos_m(3, :));
                else
                    los = false(1,N);
                    obj.LOSProbabilitySource = "los_disabled_by_config";
                    obj.LOSComplianceStatus = "not_applicable_los_disabled";
                    obj.LOSComplianceReason = "";
                end
            else
                los = opt.LOS;
                if isscalar(los) && N > 1
                    los = repmat(los,1,N);
                end
                obj.LOSProbabilitySource = "runtime_metadata_override";
                obj.LOSComplianceStatus = "runtime_provided_los_flags";
                obj.LOSComplianceReason = "";
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
                    error("TR38901Plus:UnsupportedPathlossModel", ...
                        "Unsupported pathloss model '%s'. Use 'nrPathLoss' for TR 38.901 runtime/closed-form pathloss or 'ABG' for explicitly approximate ABG studies.", ...
                        char(obj.PathlossModel));
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
                obj.O2IModelSource = "runtime_metadata_override";
                obj.O2IComplianceStatus = "runtime_provided_o2i_loss";
                obj.O2IComplianceReason = "";
            elseif opt.PathlossEnabled && any(indoor)
                if isempty(opt.IndoorDistance_m)
                    dIn = 10; % m
                else
                    dIn = opt.IndoorDistance_m;
                end
                if isscalar(dIn) && N > 1
                    dIn = repmat(dIn,1,N);
                end
                o2iStatus = struct();
                for k = 1:N
                    if indoor(k)
                        if lower(strtrim(obj.O2IModel)) == "custom"
                            if obj.ChannelComplianceMode == "strict_38901"
                                error("TR38901Plus:StrictO2IBlocked", ...
                                    "Strict 38.901 mode does not allow custom O2I loss for indoor receivers without explicit runtime O2I metadata.");
                            end
                            o2i(k) = obj.O2ICustom_dB;
                            o2iStatus = struct( ...
                                "ModelSource", "configured_custom_o2i_loss", ...
                                "ComplianceStatus", "configured_custom_o2i_loss_not_strict_38901", ...
                                "Reason", "custom configured o2i loss is caller supplied and not a strict tr38901 building penetration model");
                        else
                            [o2i(k), o2iStatus] = sixgr.channel.O2ILoss(obj.Fc_Hz, obj.O2IModel, ...
                                "IndoorDistance_m", dIn(k), "Stream", obj.Stream);
                            if obj.ChannelComplianceMode == "strict_38901" && ...
                                    ~logical(sixgr.util.structGet(o2iStatus, "StrictSupported", false))
                                error("TR38901Plus:StrictO2IBlocked", ...
                                    "Strict 38.901 mode requires O2I model 'low' or 'high'; got '%s'.", ...
                                    char(obj.O2IModel));
                            end
                        end
                    end
                end
                if ~isempty(fieldnames(o2iStatus))
                    obj.O2IModelSource = string(sixgr.util.structGet(o2iStatus, "ModelSource", ""));
                    obj.O2IComplianceStatus = string(sixgr.util.structGet(o2iStatus, "ComplianceStatus", ""));
                    obj.O2IComplianceReason = string(sixgr.util.structGet(o2iStatus, "Reason", ""));
                end
            else
                if any(indoor)
                    obj.O2IModelSource = "o2i_disabled_for_indoor_links";
                    obj.O2IComplianceStatus = "o2i_disabled_for_indoor_links";
                    obj.O2IComplianceReason = "indoor receivers were present but no o2i model or explicit o2i loss was active";
                else
                    obj.O2IModelSource = "not_applicable_outdoor_only";
                    obj.O2IComplianceStatus = "not_applicable_outdoor_only";
                    obj.O2IComplianceReason = "";
                end
            end
            o2i = double(o2i(:)).';
            if ~opt.PathlossEnabled
                o2i(:) = 0;
                obj.O2IModelSource = "pathloss_disabled";
                obj.O2IComplianceStatus = "not_applicable_pathloss_disabled";
                obj.O2IComplianceReason = "";
            end

            oxygenAbsorption_dB = zeros(1, N);
            if opt.PathlossEnabled && opt.AtmosphericAbsorptionEnabled
                oxygenAbsorption_dB = sixgr.channel.OxygenAbsorption.pathLoss_dB(obj.Fc_Hz, d3d);
            end
            oxygenAbsorption_dB = double(oxygenAbsorption_dB(:)).';

            pl_dB = plBase + sf + o2i + oxygenAbsorption_dB;

            ex = struct();
            ex.d2d_m = d2d(:);
            ex.d3d_m = d3d(:);
            ex.los = los(:);
            ex.o2i_dB = o2i(:);
            ex.oxygenAbsorption_dB = oxygenAbsorption_dB(:);
            ex.shadow_dB = sf(:);
            ex.base_dB = plBase(:);
            ex.scenario = opt.Scenario;
            ex.fc_Hz = obj.Fc_Hz;
            ex.model = obj.PathlossModel;
            ex.channelComplianceMode = obj.ChannelComplianceMode;
            ex.pathlossExecutionBackend = obj.PathlossExecutionBackend;
            ex.pathlossTruthClassification = obj.PathlossTruthClassification;
            ex.pathlossApproximationReason = obj.PathlossApproximationReason;
            ex.pathlossModelSource = obj.PathlossModelSource;
            ex.pathlossComplianceStatus = obj.PathlossComplianceStatus;
            ex.fallbackUsedForPathloss = obj.FallbackUsedForPathloss;
            ex.o2iModelSource = obj.O2IModelSource;
            ex.o2iComplianceStatus = obj.O2IComplianceStatus;
            ex.o2iComplianceReason = obj.O2IComplianceReason;
            ex.losProbabilitySource = obj.LOSProbabilitySource;
            ex.losComplianceStatus = obj.LOSComplianceStatus;
            ex.losComplianceReason = obj.LOSComplianceReason;
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
            obj.PathlossModelSource = "";
            obj.PathlossComplianceStatus = "";
            obj.FallbackUsedForPathloss = false;

            if any(model == ["nrpathloss","nr"])
                if localNrPathLossRuntimeAvailable() && localNrPathLossBandSupported(obj.Fc_Hz)
                    obj.PathlossExecutionBackend = "nrpathloss_runtime_backend";
                    obj.PathlossTruthClassification = "standards_backed_3gpp_large_scale_pathloss";
                    obj.PathlossModelSource = "nrpathloss_runtime_backend";
                    obj.PathlossComplianceStatus = "strict_38901_runtime";
                elseif localAnalytical38901Supported(obj.Scenario, obj.Fc_Hz)
                    obj.PathlossExecutionBackend = "tr38901_closed_form_runtime_backend";
                    obj.PathlossTruthClassification = "standards_backed_3gpp_closed_form_large_scale_pathloss";
                    obj.PathlossModelSource = "tr38901_closed_form_equations";
                    obj.PathlossComplianceStatus = localAnalytical38901ComplianceStatus(obj.Fc_Hz);
                else
                    obj.PathlossExecutionBackend = "unsupported_pathloss_model";
                    obj.PathlossTruthClassification = "unavailable";
                    obj.PathlossApproximationReason = "no_supported_nrpathloss_or_tr38901_closed_form_pathloss_for_requested_scenario_or_frequency";
                    obj.PathlossModelSource = "unavailable";
                    obj.PathlossComplianceStatus = "unsupported_pathloss_configuration";
                end
            elseif any(model == ["abg","tr38901abg","fr3abg"])
                obj.PathlossExecutionBackend = "abg_large_scale_model";
                obj.PathlossTruthClassification = "approximate_abg_large_scale_pathloss_model";
                obj.PathlossApproximationReason = "abg_pathloss_is_a_configured_large_scale_abstraction_not_nrpathloss_runtime";
                obj.PathlossModelSource = "configured_abg_large_scale_model";
                obj.PathlossComplianceStatus = "configured_abg_not_strict_38901";
            else
                obj.PathlossExecutionBackend = "unsupported_pathloss_model";
                obj.PathlossTruthClassification = "unavailable";
                obj.PathlossApproximationReason = "configured_pathloss_model_is_not_nrpathloss_or_abg";
                obj.PathlossModelSource = "unavailable";
                obj.PathlossComplianceStatus = "unsupported_pathloss_configuration";
            end

            if obj.ChannelComplianceMode == "strict_38901"
                if ~any(model == ["nrpathloss","nr"])
                    error("TR38901Plus:StrictPathlossModel", ...
                        "Strict 38.901 mode requires PathlossModel='nrPathLoss'; got '%s'.", ...
                        char(obj.PathlossModel));
                end
                if strcmpi(char(obj.PathlossComplianceStatus), "unsupported_pathloss_configuration")
                    error("TR38901Plus:StrictNrPathLossUnavailable", ...
                        "Strict 38.901 mode requires nrPathLoss runtime support or supported TR 38.901 closed-form equations; no fallback pathloss is allowed.");
                end
            end
        end

        function pl = pathlossViaNrPathLoss(obj, txPos_m, rxPos_m, los, scenarioName)
            % Use nrPathLoss where available. Otherwise use supported
            % TR 38.901 closed-form equations rather than a generic FSPL
            % shortcut.
            N = size(txPos_m,2);
            pl = zeros(1,N);

            scenarioToken = localCanonicalScenarioToken(scenarioName);
            useToolbox = localNrPathLossRuntimeAvailable() && localNrPathLossBandSupported(obj.Fc_Hz);
            if ~useToolbox
                if ~localAnalytical38901Supported(scenarioToken, obj.Fc_Hz)
                    obj.PathlossExecutionBackend = "unsupported_pathloss_model";
                    obj.PathlossTruthClassification = "unavailable";
                    obj.PathlossApproximationReason = "no_supported_nrpathloss_or_tr38901_closed_form_pathloss_for_requested_scenario_or_frequency";
                    obj.PathlossModelSource = "unavailable";
                    obj.PathlossComplianceStatus = "unsupported_pathloss_configuration";
                    obj.FallbackUsedForPathloss = false;
                    error("TR38901Plus:UnsupportedPathlossConfiguration", ...
                        "No standards-backed pathloss implementation is available for scenario '%s' at %.3f GHz.", ...
                        char(string(scenarioName)), double(obj.Fc_Hz)/1e9);
                end
                pl = obj.pathlossViaTR38901ClosedForm(txPos_m, rxPos_m, los, scenarioToken);
                return;
            end

            try
                % Try to configure nrPathLossConfig; keep minimal to avoid version issues.
                plc = nrPathLossConfig;
                if ~isempty(scenarioName)
                    try
                        plc.Scenario = char(scenarioName);
                    catch
                        % Ignore if property differs by release
                    end
                end

                % nrPathLoss expects LOS as logical. Ensure correct shape.
                los = logical(los);
                if isrow(los), losRow = los; else, losRow = los.'; end

                for k = 1:N
                    pl(k) = nrPathLoss(plc, obj.Fc_Hz, losRow(k), txPos_m(:,k), rxPos_m(:,k));
                end
                obj.PathlossExecutionBackend = "nrpathloss_runtime_backend";
                obj.PathlossTruthClassification = "standards_backed_3gpp_large_scale_pathloss";
                obj.PathlossApproximationReason = "";
                obj.PathlossModelSource = "nrpathloss_runtime_backend";
                obj.PathlossComplianceStatus = "strict_38901_runtime";
                obj.FallbackUsedForPathloss = false;
            catch ME
                if localAnalytical38901Supported(scenarioToken, obj.Fc_Hz)
                    pl = obj.pathlossViaTR38901ClosedForm(txPos_m, rxPos_m, los, scenarioToken);
                    return;
                end
                rethrow(ME);
            end
        end

        function pl = pathlossViaTR38901ClosedForm(obj, txPos_m, rxPos_m, los, scenarioToken)
            d2d = sqrt(sum((txPos_m(1:2,:) - rxPos_m(1:2,:)).^2, 1));
            d3d = sqrt(sum((txPos_m - rxPos_m).^2, 1));
            hUT = double(rxPos_m(3, :));
            fcGHz = double(obj.Fc_Hz) / 1e9;
            scenarioToken = localCanonicalScenarioToken(scenarioToken);
            los = logical(los);
            if isrow(los)
                losRow = los;
            else
                losRow = los.';
            end
            if isscalar(losRow) && numel(d3d) > 1
                losRow = repmat(losRow, 1, numel(d3d));
            end

            switch scenarioToken
                case "uma"
                    hBS = double(txPos_m(3, :));
                    hBS = max(hBS, 1.0);
                    hUT = max(hUT, 1.0);
                    dBP = max(1.0, 4 .* hBS .* hUT .* double(obj.Fc_Hz) ./ 3e8);
                    d3dSafe = max(d3d, 1.0);
                    pl1 = 28.0 + 22.0 .* log10(d3dSafe) + 20.0 .* log10(fcGHz);
                    plAtBP = 28.0 + 22.0 .* log10(max(dBP, 1.0)) + 20.0 .* log10(fcGHz);
                    pl2 = plAtBP + 40.0 .* log10(max(d3dSafe ./ max(dBP, 1.0), 1.0));
                    plLOS = pl1;
                    beyondBP = d2d > dBP;
                    plLOS(beyondBP) = pl2(beyondBP);
                    plNLOS = max(plLOS, 13.54 + 39.08 .* log10(max(d3d, 1.0)) + ...
                        20.0 .* log10(fcGHz) - 0.6 .* (hUT - 1.5));
                case "umi"
                    plLOS = 32.4 + 21.0 .* log10(max(d3d, 1.0)) + 20.0 .* log10(fcGHz);
                    plNLOS = max(plLOS, 22.4 + 35.3 .* log10(max(d3d, 1.0)) + ...
                        21.3 .* log10(fcGHz) - 0.3 .* (hUT - 1.5));
                otherwise
                    error("TR38901Plus:UnsupportedClosedFormScenario", ...
                        "TR 38.901 closed-form pathloss is currently implemented for UMa and UMi only; got '%s'.", ...
                        char(scenarioToken));
            end

            pl = plLOS;
            pl(~losRow) = plNLOS(~losRow);
            pl = double(pl(:)).';
            obj.PathlossExecutionBackend = "tr38901_closed_form_runtime_backend";
            obj.PathlossTruthClassification = "standards_backed_3gpp_closed_form_large_scale_pathloss";
            obj.PathlossApproximationReason = "";
            obj.PathlossModelSource = "tr38901_closed_form_equations";
            obj.PathlossComplianceStatus = localAnalytical38901ComplianceStatus(obj.Fc_Hz);
            obj.FallbackUsedForPathloss = false;
        end
    end
end

function value = localCanonicalStructGet(cfg, canonicalPath, aliasPath, defaultValue)
value = sixgr.util.structGet(cfg, canonicalPath, []);
if isempty(value)
    value = sixgr.util.structGet(cfg, aliasPath, defaultValue);
end
end

function value = localFirstStructGet(cfg, paths, defaultValue)
value = [];
for i = 1:numel(paths)
    value = sixgr.util.structGet(cfg, char(paths(i)), []);
    if ~isempty(value)
        return;
    end
end
value = defaultValue;
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

function mode = localDefaultChannelComplianceMode(cfg)
if logical(sixgr.util.structGet(cfg, "run.strictMode", false))
    mode = "strict_38901";
else
    mode = "approximate_38901_plus";
end
end

function mode = localNormalizeChannelComplianceMode(value)
token = lower(strtrim(char(string(value))));
switch token
    case {"", "approximate", "approximate_38901", "approximate_38901_plus", "tr38901_plus"}
        mode = "approximate_38901_plus";
    case {"strict", "strict_38901", "tr38901_strict"}
        mode = "strict_38901";
    case {"legacy", "legacy_fallback", "fallback"}
        mode = "legacy_fallback";
    otherwise
        mode = string(value);
end
end

function tf = localNrPathLossRuntimeAvailable()
tf = false;
if ~(exist("nrPathLossConfig", "class") == 8 && exist("nrPathLoss", "file") == 2)
    return;
end
try
    plc = nrPathLossConfig; %#ok<NASGU>
    tf = true;
catch
    tf = false;
end
end

function tf = localNrPathLossBandSupported(fcHz)
fcHz = double(fcHz);
tf = (fcHz >= 410e6 && fcHz <= 7.125e9) || (fcHz >= 24.25e9 && fcHz <= 52.6e9);
end

function tf = localAnalytical38901Supported(scenarioName, fcHz)
scenarioToken = localCanonicalScenarioToken(scenarioName);
fcGHz = double(fcHz) / 1e9;
tf = any(scenarioToken == ["uma", "umi"]) && fcGHz >= 0.5 && fcGHz <= 100.0;
end

function status = localAnalytical38901ComplianceStatus(fcHz)
fcHz = double(fcHz);
if fcHz > 52.6e9 && fcHz <= 100e9
    status = "tr38901_closed_form_52p6_to_100ghz";
elseif fcHz > 7.125e9 && fcHz < 24.25e9
    status = "tr38901_closed_form_7p125_to_24p25ghz_gap";
else
    status = "tr38901_closed_form_runtime";
end
end

function token = localCanonicalScenarioToken(value)
token = lower(strtrim(string(value)));
token = replace(token, ["-", "_", " "], "");
switch token
    case {"uma", "urbanmacro", "urbanmacrocell", "3gppuma"}
        token = "uma";
    case {"umi", "urbanmicro", "urbanmicrocell", "umistreetcanyon", "3gppumi"}
        token = "umi";
    case {"rma", "ruralmacro", "ruralmacrocell", "3gpprma"}
        token = "rma";
    otherwise
        token = lower(strtrim(string(value)));
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
