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
        function [ch, metaOut] = create(cfg, varargin)
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
            opt.TransmitAntennaRuntime = struct();
            opt.ReceiveAntennaRuntime = struct();
            opt.TransmitAntennaMeta = struct();
            opt.ReceiveAntennaMeta = struct();

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
                    case {"transmitantennaruntime","txantennaruntime","runtime transmitantenna","runtime txantenna"}
                        opt.TransmitAntennaRuntime = val;
                    case {"receiveantennaruntime","rxantennaruntime","runtime receiveantenna","runtime rxantenna"}
                        opt.ReceiveAntennaRuntime = val;
                    case {"transmitantennameta","txantennameta","runtime transmitantennameta","runtime txantennameta"}
                        opt.TransmitAntennaMeta = val;
                    case {"receiveantennameta","rxantennameta","runtime receiveantennameta","runtime rxantennameta"}
                        opt.ReceiveAntennaMeta = val;
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
                opt.Fc_Hz = sixgr.channel.ChannelFactory.resolveCarrierFrequency(cfg);
            else
                validateattributes(opt.Fc_Hz, {'numeric'}, ...
                    {'real','scalar','finite','positive'}, ...
                    'ChannelFactory.create', 'Fc_Hz');
                opt.Fc_Hz = double(opt.Fc_Hz);
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
            meta.ChannelArrayModel = "";
            meta.ChannelObjectSource = "";
            meta.ChannelObjectClass = "";
            meta.ChannelArrayHandlingStatus = "";
            meta.ChannelArrayHandlingBlocker = "";
            meta.ChannelUsesCountOnlyAntennaModel = false;
            meta.ChannelUsesSameRuntimeAntennaAssumptions = false;
            meta.ChannelGeometryCouplingLevel = "";
            meta.GeometryAdapterType = "";
            meta.GeometryAdapterSource = "";
            meta.GeometryAdapterLimitation = "";
            meta.GeometryAdapterPortMapping = "";
            meta.RuntimeArrayGeometryCoupled = false;
            meta.PathlossExecutionBackend = "";
            meta.PathlossTruthClassification = "";
            meta.PathlossApproximationReason = "";
            meta.ChannelComplianceMode = "";
            meta.PathlossModelSource = "";
            meta.PathlossComplianceStatus = "";
            meta.FallbackUsedForPathloss = false;
            meta.O2IModelSource = "";
            meta.O2IComplianceStatus = "";
            meta.O2IComplianceReason = "";
            meta.LOSProbabilitySource = "";
            meta.LOSComplianceStatus = "";
            meta.LOSComplianceReason = "";
            meta.SpatialNonStationarityTruthClassification = "";
            meta.SpatialNonStationarityApproximationMode = "";
            meta.SpatialNonStationarityApproximationReason = "";
            meta.SpatialNonStationarityMode = "";
            meta.VisibilityMaskSource = "";
            meta.GeometryInputsUsed = "";
            meta.PlaceholderUsed = false;
            meta.SpatialNonStationarityComplianceStatus = "";
            meta.ChannelNormalizePathGains = false;
            meta.ChannelNormalizationMode = "";
            meta.ChannelNormalizationSource = "";
            meta.ChannelNormalizeOutputs = false;
            meta.ChannelOutputNormalizationMode = "";
            meta.ChannelOutputNormalizationSource = "";

            % Create channel
            if any(model == ["awgn","none","off",""])
                meta = sixgr.channel.ChannelFactory.localApplyChannelHandlingMeta( ...
                    meta, "awgn", "none", "sixgr.channel.ChannelFactory.create:awgn_shortcut");
                ch = struct("Type","AWGN","Object",[],"IsFading",false,"IsLargeScaleOnly",false,"Meta",meta);
                metaOut = ch.Meta;
                return;
            end


            [txRuntimeContract] = sixgr.channel.ChannelFactory.localValidateRuntimeAntennaPortContract( ...
                opt.TransmitAntennaRuntime, opt.TransmitAntennaMeta, opt.NumTxAnt, "tx");
            [rxRuntimeContract] = sixgr.channel.ChannelFactory.localValidateRuntimeAntennaPortContract( ...
                opt.ReceiveAntennaRuntime, opt.ReceiveAntennaMeta, opt.NumRxAnt, "rx");
            meta.TransmitAntennaNumElements = double(txRuntimeContract.NumElements);
            meta.TransmitAntennaNumPorts = double(txRuntimeContract.NumPorts);
            meta.TransmitAntennaNumWaveformColumns = double(txRuntimeContract.NumWaveformColumns);
            meta.TransmitAntennaWaveformDomain = string(txRuntimeContract.WaveformDomain);
            meta.TransmitAntennaNumRFChains = double(txRuntimeContract.NumRFChains);
            meta.TransmitAntennaPortCountSource = string(txRuntimeContract.PortCountSource);
            meta.ReceiveAntennaNumElements = double(rxRuntimeContract.NumElements);
            meta.ReceiveAntennaNumPorts = double(rxRuntimeContract.NumPorts);
            meta.ReceiveAntennaNumWaveformColumns = double(rxRuntimeContract.NumWaveformColumns);
            meta.ReceiveAntennaWaveformDomain = string(rxRuntimeContract.WaveformDomain);
            meta.ReceiveAntennaNumRFChains = double(rxRuntimeContract.NumRFChains);
            meta.ReceiveAntennaPortCountSource = string(rxRuntimeContract.PortCountSource);
            if any(model == ["nrtdl","tdl"])
                [chObj, arrayRuntimeMeta] = sixgr.channel.ChannelFactory.localCreateTDL(cfg, opt);
                meta = sixgr.channel.ChannelFactory.localApplyChannelHandlingMeta( ...
                    meta, "tdl", class(chObj), "sixgr.channel.ChannelFactory.localCreateTDL");
                meta.ChannelNormalizePathGains = logical(sixgr.util.structGet(arrayRuntimeMeta, "NormalizePathGains", false));
                meta.ChannelNormalizationMode = string(sixgr.util.structGet(arrayRuntimeMeta, "ChannelNormalizationMode", ""));
                meta.ChannelNormalizationSource = string(sixgr.util.structGet(arrayRuntimeMeta, "ChannelNormalizationSource", ""));
                meta.ChannelNormalizeOutputs = logical(sixgr.util.structGet(arrayRuntimeMeta, "NormalizeChannelOutputs", false));
                meta.ChannelOutputNormalizationMode = string(sixgr.util.structGet(arrayRuntimeMeta, "ChannelOutputNormalizationMode", ""));
                meta.ChannelOutputNormalizationSource = string(sixgr.util.structGet(arrayRuntimeMeta, "ChannelOutputNormalizationSource", ""));
                if logical(sixgr.util.structGet(arrayRuntimeMeta, "RuntimeGeometryCorrelationApplied", false))
                    meta.ChannelArrayModel = "nrtdl_runtime_geometry_correlation_channel";
                    meta.ChannelArrayHandlingStatus = "adapted_geometry_backed_reduced_representation";
                    meta.ChannelArrayHandlingBlocker = "nrtdlchannel_consumes_custom_spatial_correlation_matrices_not_runtime_array_objects";
                    meta.ChannelUsesCountOnlyAntennaModel = false;
                    meta.ChannelUsesSameRuntimeAntennaAssumptions = false;
                    meta.ChannelGeometryCouplingLevel = "runtime_geometry_reduced_spatial_correlation";
                    meta.GeometryAdapterType = string(sixgr.util.structGet(arrayRuntimeMeta, "GeometryAdapterType", ""));
                    meta.GeometryAdapterSource = string(sixgr.util.structGet(arrayRuntimeMeta, "GeometryAdapterSource", ""));
                    meta.GeometryAdapterLimitation = string(sixgr.util.structGet(arrayRuntimeMeta, "GeometryAdapterLimitation", ""));
                    meta.GeometryAdapterPortMapping = string(sixgr.util.structGet(arrayRuntimeMeta, "GeometryAdapterPortMapping", ""));
                    meta.TDLTransmitCorrelationMatrixSource = string(sixgr.util.structGet(arrayRuntimeMeta, "TransmitCorrelationMatrixSource", ""));
                    meta.TDLReceiveCorrelationMatrixSource = string(sixgr.util.structGet(arrayRuntimeMeta, "ReceiveCorrelationMatrixSource", ""));
                    meta.TDLTransmitCorrelationMatrixSize = string(sixgr.util.structGet(arrayRuntimeMeta, "TransmitCorrelationMatrixSize", ""));
                    meta.TDLReceiveCorrelationMatrixSize = string(sixgr.util.structGet(arrayRuntimeMeta, "ReceiveCorrelationMatrixSize", ""));
                    meta.TDLGeometryCorrelationDistance_lambda = double(sixgr.util.structGet(arrayRuntimeMeta, "GeometryCorrelationDistance_lambda", NaN));
                end
                ch = struct("Type","nrTDLChannel","Object",chObj,"IsFading",true,"IsLargeScaleOnly",false,"Meta",meta);
            elseif any(model == ["nrcdl","cdl"])
                [chObj, arrayRuntimeMeta] = sixgr.channel.ChannelFactory.localCreateCDL(cfg, opt);
                meta = sixgr.channel.ChannelFactory.localApplyChannelHandlingMeta( ...
                    meta, "cdl", class(chObj), "sixgr.channel.ChannelFactory.localCreateCDL");
                meta.ChannelNormalizePathGains = logical(sixgr.util.structGet(arrayRuntimeMeta, "NormalizePathGains", false));
                meta.ChannelNormalizationMode = string(sixgr.util.structGet(arrayRuntimeMeta, "ChannelNormalizationMode", ""));
                meta.ChannelNormalizationSource = string(sixgr.util.structGet(arrayRuntimeMeta, "ChannelNormalizationSource", ""));
                meta.ChannelNormalizeOutputs = logical(sixgr.util.structGet(arrayRuntimeMeta, "NormalizeChannelOutputs", false));
                meta.ChannelOutputNormalizationMode = string(sixgr.util.structGet(arrayRuntimeMeta, "ChannelOutputNormalizationMode", ""));
                meta.ChannelOutputNormalizationSource = string(sixgr.util.structGet(arrayRuntimeMeta, "ChannelOutputNormalizationSource", ""));
                meta.LOSProbabilitySource = string(sixgr.util.structGet(arrayRuntimeMeta, "LOSProbabilitySource", ""));
                meta.LOSComplianceStatus = string(sixgr.util.structGet(arrayRuntimeMeta, "LOSComplianceStatus", ""));
                meta.LOSComplianceReason = string(sixgr.util.structGet(arrayRuntimeMeta, "LOSComplianceReason", ""));
                meta.CDLDelayProfileBeforeLOSGating = string(sixgr.util.structGet(arrayRuntimeMeta, "CDLDelayProfileBeforeLOSGating", ""));
                meta.CDLDelayProfileAfterLOSGating = string(sixgr.util.structGet(arrayRuntimeMeta, "CDLDelayProfileAfterLOSGating", ""));
                meta.CDLLOSDraw = double(sixgr.util.structGet(arrayRuntimeMeta, "CDLLOSDraw", NaN));
                meta.RuntimeArrayGeometryCoupled = logical(sixgr.util.structGet(arrayRuntimeMeta, "RuntimeArrayGeometryCoupled", false));
                meta.TransmitElementPatternApplied = logical(sixgr.util.structGet(arrayRuntimeMeta, "TransmitElementPatternApplied", false));
                meta.ReceiveElementPatternApplied = logical(sixgr.util.structGet(arrayRuntimeMeta, "ReceiveElementPatternApplied", false));
                meta.TransmitElementPatternSource = string(sixgr.util.structGet(arrayRuntimeMeta, "TransmitElementPatternSource", ""));
                meta.ReceiveElementPatternSource = string(sixgr.util.structGet(arrayRuntimeMeta, "ReceiveElementPatternSource", ""));
                if logical(sixgr.util.structGet(arrayRuntimeMeta, "RuntimeArrayGeometryCoupled", false))
                    meta.ChannelArrayModel = "nrcdl_runtime_array_geometry_channel";
                    meta.ChannelArrayHandlingStatus = string(sixgr.util.structGet(arrayRuntimeMeta, "ChannelArrayHandlingStatus", "runtime_array_shape_spacing_orientation_coupled"));
                    meta.ChannelArrayHandlingBlocker = "";
                    meta.ChannelUsesCountOnlyAntennaModel = false;
                    meta.ChannelUsesSameRuntimeAntennaAssumptions = logical(sixgr.util.structGet(arrayRuntimeMeta, "ChannelUsesSameRuntimeAntennaAssumptions", true));
                    meta.ChannelGeometryCouplingLevel = string(sixgr.util.structGet(arrayRuntimeMeta, "ChannelGeometryCouplingLevel", "runtime_array_shape_spacing_orientation"));
                    meta.GeometryAdapterType = string(sixgr.util.structGet(arrayRuntimeMeta, "GeometryAdapterType", "backend_native_nrCDLChannel_antenna_array"));
                    meta.GeometryAdapterSource = string(sixgr.util.structGet(arrayRuntimeMeta, "RuntimeArrayGeometrySource", ""));
                    meta.GeometryAdapterLimitation = string(sixgr.util.structGet(arrayRuntimeMeta, "GeometryAdapterLimitation", ""));
                    meta.GeometryAdapterPortMapping = string(sixgr.util.structGet(arrayRuntimeMeta, "GeometryAdapterPortMapping", "runtime_array_shape_matches_channel_ports"));
                    meta.ChannelRuntimeGeometrySource = string(sixgr.util.structGet(arrayRuntimeMeta, "RuntimeArrayGeometrySource", ""));
                    meta.TransmitArrayOrientation_deg = sixgr.util.structGet(arrayRuntimeMeta, "TransmitArrayOrientation_deg", [NaN; NaN; NaN]);
                    meta.ReceiveArrayOrientation_deg = sixgr.util.structGet(arrayRuntimeMeta, "ReceiveArrayOrientation_deg", [NaN; NaN; NaN]);
                    meta.TransmitAntennaArraySize = string(sixgr.util.structGet(arrayRuntimeMeta, "TransmitAntennaArraySize", ""));
                    meta.ReceiveAntennaArraySize = string(sixgr.util.structGet(arrayRuntimeMeta, "ReceiveAntennaArraySize", ""));
                    meta.TransmitAntennaElementSpacing_lambda = string(sixgr.util.structGet(arrayRuntimeMeta, "TransmitAntennaElementSpacing_lambda", ""));
                    meta.ReceiveAntennaElementSpacing_lambda = string(sixgr.util.structGet(arrayRuntimeMeta, "ReceiveAntennaElementSpacing_lambda", ""));
                end
                ch = struct("Type","nrCDLChannel","Object",chObj,"IsFading",true,"IsLargeScaleOnly",false,"Meta",meta);
            elseif any(model == ["tr38901","tr38.901","tr38_901","abg","large","abstract"])
                args = {"Fc_Hz", opt.Fc_Hz, "Seed", opt.Seed};
                if strlength(opt.Scenario) > 0
                    args = [{"Scenario", opt.Scenario}, args];
                end
                chObj = sixgr.channel.TR38901Plus(cfg, args{:});
                meta = sixgr.channel.ChannelFactory.localApplyChannelHandlingMeta( ...
                    meta, "tr38901", class(chObj), "sixgr.channel.ChannelFactory.create:TR38901Plus");
                meta.PathlossExecutionBackend = string(chObj.PathlossExecutionBackend);
                meta.PathlossTruthClassification = string(chObj.PathlossTruthClassification);
                meta.PathlossApproximationReason = string(chObj.PathlossApproximationReason);
                meta.ChannelComplianceMode = string(chObj.ChannelComplianceMode);
                meta.PathlossModelSource = string(chObj.PathlossModelSource);
                meta.PathlossComplianceStatus = string(chObj.PathlossComplianceStatus);
                meta.FallbackUsedForPathloss = logical(chObj.FallbackUsedForPathloss);
                meta.O2IModelSource = string(chObj.O2IModelSource);
                meta.O2IComplianceStatus = string(chObj.O2IComplianceStatus);
                meta.O2IComplianceReason = string(chObj.O2IComplianceReason);
                meta.LOSProbabilitySource = string(chObj.LOSProbabilitySource);
                meta.LOSComplianceStatus = string(chObj.LOSComplianceStatus);
                meta.LOSComplianceReason = string(chObj.LOSComplianceReason);
                ch = struct("Type","TR38901Plus","Object",chObj,"IsFading",false,"IsLargeScaleOnly",true,"Meta",meta);
            elseif any(model == ["raytracing","ray","rt"])
                args = {"Fc_Hz", opt.Fc_Hz, "Viewer", opt.Viewer};
                if strlength(opt.Scenario) > 0
                    args = [{"Scenario", opt.Scenario}, args];
                end
                chObj = sixgr.channel.RayTracingAdapter(cfg, args{:});
                meta = sixgr.channel.ChannelFactory.localApplyChannelHandlingMeta( ...
                    meta, "raytracing", class(chObj), "sixgr.channel.ChannelFactory.create:RayTracingAdapter");
                ch = struct("Type","RayTracing","Object",chObj,"IsFading",false,"IsLargeScaleOnly",true,"Meta",meta);
            else
                error("ChannelFactory:create:UnknownModel", "Unsupported cfg.channel.model='%s'.", model);
            end

            % Spatial non-stationarity hook (optional metadata only)
            if opt.EnableSpatialNonStationarity
                try
                    vis = sixgr.channel.SpatialNonStationarity(cfg, ...
                        "NumTxAnt", opt.NumTxAnt, "NumRxAnt", opt.NumRxAnt, "Seed", opt.Seed, ...
                        "TransmitAntennaMeta", opt.TransmitAntennaMeta, ...
                        "ReceiveAntennaMeta", opt.ReceiveAntennaMeta);
                    ch.Meta.SpatialNonStationarity = vis;
                    ch.Meta.SpatialNonStationarityTruthClassification = string(sixgr.util.structGet(vis, "truthClassification", ""));
                    ch.Meta.SpatialNonStationarityApproximationMode = string(sixgr.util.structGet(vis, "approximationMode", ""));
                    ch.Meta.SpatialNonStationarityApproximationReason = string(sixgr.util.structGet(vis, "approximationReason", ""));
                    ch.Meta.SpatialNonStationarityMode = string(sixgr.util.structGet(vis, "mode", ""));
                    ch.Meta.VisibilityMaskSource = string(sixgr.util.structGet(vis, "visibilityMaskSource", ""));
                    ch.Meta.GeometryInputsUsed = string(sixgr.util.structGet(vis, "geometryInputsUsed", ""));
                    ch.Meta.PlaceholderUsed = logical(sixgr.util.structGet(vis, "placeholderUsed", false));
                    ch.Meta.SpatialNonStationarityComplianceStatus = string(sixgr.util.structGet(vis, "complianceStatus", ""));
                catch ME
                    % Non-fatal: keep channel but warn in metadata
                    ch.Meta.SpatialNonStationarity = struct("enable",true,"error",string(ME.message));
                    ch.Meta.SpatialNonStationarityTruthClassification = "unavailable_due_to_runtime_error";
                    ch.Meta.SpatialNonStationarityApproximationMode = "runtime_error";
                    ch.Meta.SpatialNonStationarityApproximationReason = string(ME.message);
                    ch.Meta.SpatialNonStationarityMode = "runtime_error";
                    ch.Meta.VisibilityMaskSource = "runtime_error";
                    ch.Meta.GeometryInputsUsed = "";
                    ch.Meta.PlaceholderUsed = false;
                    ch.Meta.SpatialNonStationarityComplianceStatus = "runtime_error";
                end
            end
            metaOut = ch.Meta;
        end

        function tf = requiresRuntimeChannelState(cfg)
            modelRaw = upper(strtrim(string(sixgr.util.structGet(cfg, "channel.model", ...
                sixgr.util.structGet(cfg, "channel.type", "AWGN")))));
            awgnOnly = logical(sixgr.util.structGet(cfg, "channel.awgnOnly", false));
            tf = ~awgnOnly && (startsWith(modelRaw, "TDL") || startsWith(modelRaw, "CDL") || ...
                any(modelRaw == ["NRTDL","NRCDL"]));
        end

        function fc = resolveCarrierFrequency(cfg)
            % Match normalizeConfig authority: resolved PHY, then catalog
            % channel frequency. The historical carrier alias is last and
            % may only supply a value when canonical fields are absent.
            % Do not skip invalid explicit values or invent an RF carrier.
            paths = ["phy.fc_Hz", "channel.fc_Hz", "carrier.fc_Hz"];
            sections = ["phy", "channel", "carrier"];
            for k = 1:numel(paths)
                section = sixgr.util.structGet(cfg, sections(k), struct());
                if ~(isstruct(section) && isscalar(section) && isfield(section,'fc_Hz'))
                    continue;
                end
                raw = section.fc_Hz;
                if ~(isnumeric(raw) && isreal(raw) && isscalar(raw) && ...
                        isfinite(raw) && raw > 0)
                    error('ChannelFactory:InvalidCarrierFrequency', ...
                        '%s must be a finite positive numeric scalar in Hz.', paths(k));
                end
                fc = double(raw);
                return;
            end
            error('ChannelFactory:MissingCarrierFrequency', ...
                ['Provide resolved phy.fc_Hz or catalog channel.fc_Hz ' ...
                 '(legacy carrier.fc_Hz is accepted when both are absent).']);
        end

        function key = runtimeChannelKey(cfg, direction, varargin)
            ip = inputParser;
            ip.addParameter("UEIndex", NaN, @(x) isnumeric(x) && isscalar(x));
            ip.addParameter("ServingCell", NaN, @(x) isnumeric(x) && isscalar(x));
            ip.addParameter("CarrierKey", "", @(x) ischar(x) || isstring(x));
            ip.parse(varargin{:});
            opt = ip.Results;

            direction = upper(strtrim(string(direction)));
            if direction ~= "UL"
                direction = "DL";
            end
            ueIdx = double(opt.UEIndex);
            if ~(isfinite(ueIdx) && ueIdx >= 1)
                ueIdx = double(sixgr.util.structGet(cfg, "lls6g.userContext.RuntimeUEIndex", ...
                    sixgr.util.structGet(cfg, "lls6g.userContext.UEIndex", 1)));
            end
            servingCell = double(opt.ServingCell);
            if ~(isfinite(servingCell) && servingCell >= 1)
                servingCell = double(sixgr.util.structGet(cfg, "lls6g.userContext.RuntimeServingCell", ...
                    sixgr.util.structGet(cfg, "cell.id", 1)));
            end
            carrierKey = string(opt.CarrierKey);
            if strlength(strtrim(carrierKey)) == 0
                nSize = double(sixgr.util.structGet(cfg, "phy.carrier.NSizeGrid", NaN));
                scs = double(sixgr.util.structGet(cfg, "phy.carrier.SubcarrierSpacing", NaN));
                fc = sixgr.channel.ChannelFactory.resolveCarrierFrequency(cfg);
                carrierKey = "nrb=" + string(nSize) + ":scs=" + string(scs) + ":fc=" + string(fc);
            end
            if direction == "UL"
                txEntity = "UE" + string(round(ueIdx));
                rxEntity = "gNB" + string(round(servingCell));
            else
                txEntity = "gNB" + string(round(servingCell));
                rxEntity = "UE" + string(round(ueIdx));
            end
            key = char("dir=" + direction + ";tx=" + txEntity + ";rx=" + rxEntity + ";carrier=" + carrierKey);
        end

        function seed = runtimeChannelSeed(cfg, linkKey)
            baseSeed = double(sixgr.util.structGet(cfg, "channel.seed", ...
                sixgr.util.structGet(cfg, "run.seed", 1)));
            if ~(isfinite(baseSeed) && baseSeed >= 0)
                baseSeed = 1;
            end
            seedKey = sixgr.channel.ChannelFactory.localRuntimeSeedKey(cfg, linkKey);
            seed = mod(round(baseSeed) * 1664525 + sixgr.channel.ChannelFactory.localStringHash(seedKey) + 1013904223, 2^31 - 1);
            if ~(isfinite(seed) && seed >= 1)
                seed = 1;
            end
        end

        function key = runtimeChannelStateKey(cfg, linkKey)
            % A moving TDD link is one physical reciprocal channel whose
            % direction changes with the slot.  Store it once so DL and UL
            % cannot advance independent fading clocks.  FDD and static
            % reciprocal adapters retain per-direction state because their
            % endpoint implementations are intentionally independent.
            key = char(string(linkKey));
            if sixgr.channel.ChannelFactory.supportsDynamicRuntimeTDDReciprocity(cfg)
                key = sixgr.channel.ChannelFactory.localRuntimeSeedKey(cfg, linkKey);
            end
        end

        function state = emptyRuntimeChannelState()
            state = struct( ...
                "ContractVersion", "sixgr.channel.RuntimeChannelState/v1", ...
                "LinkKey", "", ...
                "StateKey", "", ...
                "Direction", "", ...
                "Seed", NaN, ...
                "Initialized", false, ...
                "Materialized", false, ...
                "UseFading", false, ...
                "Obj", [], ...
                "Meta", struct(), ...
                "SampleRate_Hz", NaN, ...
                "NumTxAnt", NaN, ...
                "NumRxAnt", NaN, ...
                "ExternalLogicalTxPorts", NaN, ...
                "PhysicalChannelTxElements", NaN, ...
                "PortToElementMatrix", [], ...
                "ElementExpansionApplied", false, ...
                "ElementExpansionMatrixSHA256", "", ...
                "ElementExpansionChunkSamples", 4096, ...
                "ChannelPadSamples", 0, ...
                "ChannelTrimSamples", 0, ...
                "WarmupSamples", 0, ...
                "ResetCount", 0, ...
                "ResetPolicy", "drop_seed_boundary_only", ...
                "CreatedBy", "sixgr.channel.ChannelFactory.createRuntimeChannelState", ...
                "CurrentSampleIndex", 0, ...
                "CurrentTime_s", 0, ...
                "PendingIdleSamples", 0, ...
                "TotalAppliedSamples", 0, ...
                "TotalIdleAdvancedSamples", 0, ...
                "TotalObjectInputSamples", 0, ...
                "LastApplyStartSample", NaN, ...
                "LastApplyEndSample", NaN, ...
                "LastIdleAdvancedSamples", 0, ...
                "TargetSlotStartTime_s", NaN, ...
                "TargetSlot", NaN, ...
                "TargetFrame", NaN, ...
                "TargetUEIndex", NaN, ...
                "TargetServingCell", NaN, ...
                "LastPathGainsAvailable", false, ...
                "RuntimeDiagnosticPathGainCaptureCompleted", false, ...
                "RuntimeDiagnosticPathGainMaxElements", 1024);
        end

        function state = createRuntimeChannelState(cfg, direction, varargin)
            ip = inputParser;
            ip.addParameter("LinkKey", "", @(x) ischar(x) || isstring(x));
            ip.addParameter("Seed", NaN, @(x) isnumeric(x) && isscalar(x));
            ip.addParameter("UEIndex", NaN, @(x) isnumeric(x) && isscalar(x));
            ip.addParameter("ServingCell", NaN, @(x) isnumeric(x) && isscalar(x));
            ip.addParameter("CarrierKey", "", @(x) ischar(x) || isstring(x));
            ip.addParameter("AbsoluteSampleIndex", 0, @(x) isnumeric(x) && isscalar(x));
            ip.parse(varargin{:});
            opt = ip.Results;

            key = string(opt.LinkKey);
            if strlength(strtrim(key)) == 0
                key = string(sixgr.channel.ChannelFactory.runtimeChannelKey(cfg, direction, ...
                    "UEIndex", opt.UEIndex, "ServingCell", opt.ServingCell, "CarrierKey", opt.CarrierKey));
            end
            seed = double(opt.Seed);
            if ~(isfinite(seed) && seed >= 0)
                seed = sixgr.channel.ChannelFactory.runtimeChannelSeed(cfg, key);
            end
            state = sixgr.channel.ChannelFactory.emptyRuntimeChannelState();
            state.LinkKey = char(key);
            state.StateKey = sixgr.channel.ChannelFactory.runtimeChannelStateKey(cfg, key);
            state.Direction = char(upper(string(direction)));
            state.Seed = double(seed);
            state.Initialized = true;
            state.CurrentSampleIndex = max(0, round(double(opt.AbsoluteSampleIndex)));
            state.CurrentTime_s = 0;
            % A nonzero initial clock is elapsed input time, not merely a
            % reporting offset. Consume that idle interval when the object
            % is materialized, without moving the logical clock again.
            state.PendingIdleSamples = state.CurrentSampleIndex;
            state.TotalIdleAdvancedSamples = state.CurrentSampleIndex;
            if state.CurrentSampleIndex > 0
                state.CurrentTime_s = NaN; % Sample rate is not known yet.
            end
            diagnosticLimit = double(sixgr.util.structGet(cfg, ...
                "outputs.phySignalDiagnosticChannelPoints", 1024));
            if ~(isscalar(diagnosticLimit) && isfinite(diagnosticLimit) && diagnosticLimit >= 1)
                diagnosticLimit = 1024;
            end
            state.RuntimeDiagnosticPathGainMaxElements = ...
                min(4096, max(1, round(diagnosticLimit)));
        end

        function forkedState = forkRuntimeChannelState(state)
            %FORKRUNTIMECHANNELSTATE Deep-copy a channel at one time origin.
            %
            % Shared-slot MU signals are concurrent, not consecutive calls
            % through one mutable System object.  A contribution therefore
            % receives a deep copy of the exact slot-start channel state.
            % Executing the copy must not advance the canonical per-link
            % state later consumed by the desired waveform.
            forkedState = state;
            if ~(isstruct(state) && isfield(state, "ContractVersion"))
                return;
            end
            if ~logical(sixgr.util.structGet(state, "Materialized", false))
                error("ChannelFactory:RuntimeChannelForkBeforeMaterialization", ...
                    ['Runtime channel ''%s'' must be materialized once in the canonical ' ...
                     'per-link state before a shared-slot fork is created.  Forking ' ...
                     'an unmaterialized state lets concurrent sources instantiate ' ...
                     'different channel realizations.'], ...
                    char(string(sixgr.util.structGet(state, "LinkKey", ""))));
            end
            if logical(sixgr.util.structGet(state, "UseFading", false)) && ...
                    isfield(state, "Obj") && ~isempty(state.Obj)
                if ~ismethod(state.Obj, "clone")
                    error("ChannelFactory:RuntimeChannelNotForkable", ...
                        ["Runtime channel '%s' uses %s, which cannot be deep-cloned " ...
                         "for coherent shared-slot waveform superposition."], ...
                        char(string(sixgr.util.structGet(state, "LinkKey", ""))), ...
                        class(state.Obj));
                end
                forkedState.Obj = clone(state.Obj);
            end
        end

        function state = materializeRuntimeChannelState(state, cfg, waveform, txInfo, varargin)
            if nargin < 2 || ~isstruct(cfg)
                cfg = struct();
            end
            if nargin < 3
                waveform = [];
            end
            if nargin < 4 || ~isstruct(txInfo)
                txInfo = struct();
            end
            if ~(isstruct(state) && isfield(state, "ContractVersion"))
                state = sixgr.channel.ChannelFactory.createRuntimeChannelState(cfg, "DL");
            end
            ip = inputParser;
            ip.addParameter("NumTxAnt", NaN, @(x) isnumeric(x) && isscalar(x));
            ip.addParameter("NumRxAnt", NaN, @(x) isnumeric(x) && isscalar(x));
            ip.addParameter("TransmitAntennaRuntime", struct(), @(x) isempty(x) || isstruct(x));
            ip.addParameter("ReceiveAntennaRuntime", struct(), @(x) isempty(x) || isstruct(x));
            ip.addParameter("TransmitAntennaMeta", struct(), @(x) isempty(x) || isstruct(x));
            ip.addParameter("ReceiveAntennaMeta", struct(), @(x) isempty(x) || isstruct(x));
            ip.parse(varargin{:});
            opt = ip.Results;

            if logical(sixgr.util.structGet(state, "Materialized", false))
                state = sixgr.channel.ChannelFactory.localRetargetDynamicTDDChannelState( ...
                    state, cfg);
                expectedPhysicalTx = double(sixgr.util.structGet( ...
                    state, "NumTxAnt", NaN));
                observedTx = size(waveform, 2);
                [nextMap, nextExpansion] = ...
                    sixgr.channel.ChannelFactory.localResolvePortToElementExpansion( ...
                    opt.TransmitAntennaRuntime, opt.TransmitAntennaMeta, ...
                    max(1, observedTx));
                if nextExpansion && size(nextMap, 1) == round(expectedPhysicalTx)
                    state.ExternalLogicalTxPorts = double(observedTx);
                    state.PhysicalChannelTxElements = double(expectedPhysicalTx);
                    state.PortToElementMatrix = nextMap;
                    state.ElementExpansionApplied = true;
                    state.ElementExpansionMatrixSHA256 = char( ...
                        sixgr.phy.mimo.MatrixContract.digest(nextMap));
                    return;
                elseif isfinite(expectedPhysicalTx) && ...
                        observedTx == round(expectedPhysicalTx)
                    state.ExternalLogicalTxPorts = double(observedTx);
                    state.PhysicalChannelTxElements = double(expectedPhysicalTx);
                    state.PortToElementMatrix = [];
                    state.ElementExpansionApplied = false;
                    state.ElementExpansionMatrixSHA256 = "";
                    return;
                end
                requestedTx = double(opt.NumTxAnt);
                if ~(isfinite(requestedTx) && requestedTx >= 1)
                    requestedTx = observedTx;
                end
                expectedExternalTx = double(sixgr.util.structGet(state, ...
                    "ExternalLogicalTxPorts", expectedPhysicalTx));
                if isfinite(expectedExternalTx) && expectedExternalTx >= 1 ...
                        && observedTx > round(expectedExternalTx)
                    error("ChannelFactory:RuntimeChannelDimensionChange", ...
                        ['Runtime channel ''%s'' was materialized for %d active logical ' ...
                         'Tx port(s) over %d physical element(s), but this execution ' ...
                         'has %d active waveform column(s), declared a pre-projection ' ...
                         'capacity of %d, and supplied no compatible logical-port-to-' ...
                         'element projection.'], ...
                        char(string(sixgr.util.structGet(state, "LinkKey", ""))), ...
                        round(expectedExternalTx), round(expectedPhysicalTx), ...
                        round(observedTx), round(requestedTx));
                end
                return;
            end

            modelRaw = upper(string(sixgr.util.structGet(cfg, "channel.model", "AWGN")));
            awgnOnly = logical(sixgr.util.structGet(cfg, "channel.awgnOnly", false));
            if awgnOnly || modelRaw == "AWGN" || modelRaw == "NONE" || modelRaw == "OFF"
                state.Materialized = true;
                state.UseFading = false;
                fsObserved = sixgr.util.structGet(txInfo, "OFDM.SampleRate", NaN);
                if isnumeric(fsObserved) && isscalar(fsObserved) && isfinite(fsObserved) && fsObserved > 0
                    state.SampleRate_Hz = double(fsObserved);
                    state.CurrentTime_s = double(state.CurrentSampleIndex) / double(fsObserved);
                end
                state.PendingIdleSamples = 0; % There is no fading object to warm.
                return;
            end

            cfgCh = cfg;
            dopp = double(sixgr.util.structGet(cfgCh, "channel.doppler_Hz", ...
                sixgr.util.structGet(cfgCh, "channel.dopplerHz", ...
                sixgr.util.structGet(cfgCh, "channel.fading.maxDoppler_Hz", 0))));
            cfgCh.channel.doppler_Hz = max(0, dopp);
            if startsWith(modelRaw, "TDL")
                cfgCh.channel.model = "TDL";
                if modelRaw ~= "TDL"
                    cfgCh.channel.tdlProfile = char(modelRaw);
                end
            elseif startsWith(modelRaw, "CDL")
                cfgCh.channel.model = "CDL";
                if modelRaw ~= "CDL"
                    cfgCh.channel.cdlProfile = char(modelRaw);
                end
            else
                cfgCh.channel.model = char(modelRaw);
            end

            fs = sixgr.channel.ChannelFactory.localRuntimeSampleRate(waveform, txInfo);
            numTx = double(opt.NumTxAnt);
            if ~(isfinite(numTx) && numTx >= 1)
                numTx = max(1, size(waveform, 2));
            end
            numRx = double(opt.NumRxAnt);
            if ~(isfinite(numRx) && numRx >= 1)
                numRx = max(1, double(sixgr.util.structGet(cfg, "phy.nRxAnt", numTx)));
            end
            externalTx = max(1, size(waveform, 2));
            [portToElement, expandToElements] = ...
                sixgr.channel.ChannelFactory.localResolvePortToElementExpansion( ...
                opt.TransmitAntennaRuntime, opt.TransmitAntennaMeta, externalTx);
            txRuntimeForChannel = opt.TransmitAntennaRuntime;
            txMetaForChannel = opt.TransmitAntennaMeta;
            if expandToElements
                numTx = size(portToElement, 1);
                [txRuntimeForChannel, txMetaForChannel] = ...
                    sixgr.channel.ChannelFactory.localElementDomainRuntimeAntenna( ...
                    txRuntimeForChannel, txMetaForChannel, externalTx, numTx);
                state.ExternalLogicalTxPorts = double(externalTx);
                state.PhysicalChannelTxElements = double(numTx);
                state.PortToElementMatrix = portToElement;
                state.ElementExpansionApplied = true;
                state.ElementExpansionMatrixSHA256 = char( ...
                    sixgr.phy.mimo.MatrixContract.digest(portToElement));
                chunkSamples = double(sixgr.util.structGet(cfg, ...
                    "channel.runtimeElementExpansionChunkSamples", 4096));
                if ~(isscalar(chunkSamples) && isfinite(chunkSamples) ...
                        && chunkSamples >= 1 && chunkSamples == fix(chunkSamples))
                    error("ChannelFactory:InvalidElementExpansionChunkSamples", ...
                        "channel.runtimeElementExpansionChunkSamples must be a positive integer.");
                end
                state.ElementExpansionChunkSamples = double(chunkSamples);
            else
                state.ExternalLogicalTxPorts = double(numTx);
                state.PhysicalChannelTxElements = double(numTx);
            end
            opt.TransmitAntennaRuntime = txRuntimeForChannel;
            opt.TransmitAntennaMeta = txMetaForChannel;

            if sixgr.channel.ChannelFactory.supportsDynamicRuntimeTDDReciprocity(cfgCh)
                ch = sixgr.channel.ChannelFactory.localCreateDynamicTDDReciprocalChannel( ...
                    cfgCh,state,fs,max(1,round(numTx)),max(1,round(numRx)),opt);
            elseif sixgr.channel.ChannelFactory.supportsRuntimeTDDReciprocity(cfgCh)
                ch = sixgr.channel.ChannelFactory.localCreateStaticTDDReciprocalChannel( ...
                    cfgCh,state,fs,max(1,round(numTx)),max(1,round(numRx)),opt);
            else
                ch = sixgr.channel.ChannelFactory.create(cfgCh, ...
                    "Model", cfgCh.channel.model, ...
                    "SampleRate", fs, ...
                    "NumTxAnt", max(1, round(numTx)), ...
                    "NumRxAnt", max(1, round(numRx)), ...
                    "Seed", double(state.Seed), ...
                    "TransmitAntennaRuntime", opt.TransmitAntennaRuntime, ...
                    "ReceiveAntennaRuntime", opt.ReceiveAntennaRuntime, ...
                    "TransmitAntennaMeta", opt.TransmitAntennaMeta, ...
                    "ReceiveAntennaMeta", opt.ReceiveAntennaMeta);
            end
            state.Meta = sixgr.util.structGet(ch, "Meta", struct());
            state.Meta.ElementExpansionApplied = logical(expandToElements);
            state.Meta.ExternalLogicalTxPorts = double(state.ExternalLogicalTxPorts);
            state.Meta.PhysicalChannelTxElements = double(state.PhysicalChannelTxElements);
            state.Meta.ElementExpansionMatrixSHA256 = ...
                string(state.ElementExpansionMatrixSHA256);
            state.Meta = sixgr.channel.ChannelFactory.localAttachRuntimeGeometryMeta(state.Meta, cfgCh);
            state.SampleRate_Hz = double(fs);
            state.NumTxAnt = max(1, round(numTx));
            state.NumRxAnt = max(1, round(numRx));
            state.Materialized = true;
            if logical(sixgr.util.structGet(ch, "IsFading", false)) && isfield(ch, "Object") && ~isempty(ch.Object)
                state.UseFading = true;
                state.Obj = ch.Object;
                [padSamples, trimSamples] = sixgr.channel.ChannelFactory.resolveChannelDelaySamples(ch.Object, fs);
                state.ChannelPadSamples = padSamples;
                state.ChannelTrimSamples = trimSamples;
                state.WarmupSamples = max(256, padSamples);
                reset(state.Obj);
                state.ResetCount = double(state.ResetCount) + 1;
                if state.WarmupSamples > 0
                    if isempty(waveform)
                        warmup = zeros(state.WarmupSamples, max(1, round(numTx)));
                    else
                        warmup = zeros(state.WarmupSamples, max(1, round(numTx)), 'like', waveform);
                    end
                    try
                        state.Obj(warmup);
                    catch
                        [~, ~] = state.Obj(warmup);
                    end
                    state.TotalObjectInputSamples = double(state.TotalObjectInputSamples) + double(state.WarmupSamples);
                end
                pendingIdle = max(0, round(double(sixgr.util.structGet(state, "PendingIdleSamples", 0))));
                if pendingIdle > 0
                    % The logical clock already includes these samples.
                    % Advance only the newly created physical object.
                    state = sixgr.channel.ChannelFactory.localConsumeRuntimeIdleSamples( ...
                        state, pendingIdle, max(1, round(numTx)), waveform);
                    state.PendingIdleSamples = 0;
                end
            end
            state.CurrentTime_s = double(state.CurrentSampleIndex) / double(fs);
        end

        function state = advanceRuntimeChannelStateToTime(state, targetTime_s, numTx, prototype)
            if nargin < 4
                prototype = [];
            end
            if ~(isstruct(state) && isfield(state, "ContractVersion"))
                return;
            end
            fs = double(sixgr.util.structGet(state, "SampleRate_Hz", NaN));
            if ~(isnumeric(targetTime_s) && isscalar(targetTime_s) && ...
                    isreal(targetTime_s) && isfinite(targetTime_s) && targetTime_s >= 0)
                error("sixgr:channel:InvalidRuntimeTargetTime", ...
                    "A runtime channel target time must be a finite nonnegative scalar in seconds.");
            end
            if ~(isscalar(fs) && isfinite(fs) && fs > 0)
                error("sixgr:channel:UnresolvedRuntimeSampleClock", ...
                    "Absolute-time channel advancement requires a resolved positive sample rate.");
            end
            targetSample = round(double(targetTime_s) * fs);
            currentSample = double(sixgr.util.structGet(state, "CurrentSampleIndex", NaN));
            if ~(isscalar(currentSample) && isfinite(currentSample) && currentSample >= 0 && currentSample == round(currentSample))
                error("sixgr:channel:InvalidRuntimeSampleClock", ...
                    "CurrentSampleIndex must be an actual nonnegative integer sample count.");
            end
            if targetSample < currentSample
                error("sixgr:channel:RuntimeChannelTimeReversal", ...
                    "Channel '%s' is already at sample %.0f (%.12g s); requested sample %.0f (%.12g s). " + ...
                    "Execute or compose waveforms on the causal timeline; do not reset, clamp, or replay the channel clock.", ...
                    string(sixgr.util.structGet(state, "StateKey", "")), ...
                    currentSample, currentSample/fs, targetSample, double(targetTime_s));
            end
            state = sixgr.channel.ChannelFactory.advanceRuntimeChannelState(state, targetSample - currentSample, numTx, prototype);
        end

        function state = advanceRuntimeChannelState(state, numSamples, numTx, prototype)
            if nargin < 4
                prototype = [];
            end
            if ~(isstruct(state) && isfield(state, "ContractVersion"))
                return;
            end
            if ~(isnumeric(numSamples) && isscalar(numSamples) && isreal(numSamples) && ...
                    isfinite(numSamples) && numSamples >= 0 && numSamples == round(numSamples))
                error("sixgr:channel:InvalidRuntimeAdvanceSamples", ...
                    "Runtime channel idle advancement requires a nonnegative integer sample count.");
            end
            n = double(numSamples);
            if n <= 0
                state.LastIdleAdvancedSamples = 0;
                return;
            end
            if ~(logical(sixgr.util.structGet(state, "Materialized", false)) && ...
                    logical(sixgr.util.structGet(state, "UseFading", false)) && isfield(state, "Obj") && ~isempty(state.Obj))
                if ~logical(sixgr.util.structGet(state, "Materialized", false))
                    state.PendingIdleSamples = max(0, round(double(sixgr.util.structGet(state, "PendingIdleSamples", 0)))) + n;
                end
                state.CurrentSampleIndex = max(0, round(double(sixgr.util.structGet(state, "CurrentSampleIndex", 0)))) + n;
                state.TotalIdleAdvancedSamples = double(sixgr.util.structGet(state, "TotalIdleAdvancedSamples", 0)) + n;
                fs = double(sixgr.util.structGet(state, "SampleRate_Hz", NaN));
                state.CurrentTime_s = NaN;
                if isfinite(fs) && fs > 0
                    state.CurrentTime_s = double(state.CurrentSampleIndex) / fs;
                end
                state.LastIdleAdvancedSamples = n;
                return;
            end
            state = sixgr.channel.ChannelFactory.localConsumeRuntimeIdleSamples(state, n, numTx, prototype);
            state.CurrentSampleIndex = max(0, round(double(sixgr.util.structGet(state, "CurrentSampleIndex", 0)))) + n;
            fs = double(sixgr.util.structGet(state, "SampleRate_Hz", NaN));
            if isfinite(fs) && fs > 0
                state.CurrentTime_s = double(state.CurrentSampleIndex) / fs;
            end
            state.TotalIdleAdvancedSamples = double(sixgr.util.structGet(state, "TotalIdleAdvancedSamples", 0)) + n;
            state.LastIdleAdvancedSamples = n;
        end

        function [y, replay, state, reference] = applyRuntimeChannelState(state, x, varargin)
            ip = inputParser;
            ip.addParameter("CapturePathGains", [], @(v) isempty(v) || ...
                (isscalar(v) && (islogical(v) || isnumeric(v))));
            % A separate bounded output for independent channel scoring.
            % Never substitute the truncated diagnostic preview for this.
            ip.addParameter("CaptureChannelReference", false, @(v) ...
                (islogical(v)||isnumeric(v)) && isscalar(v) && any(v==[0 1]));
            % This selects the API's sample reference plane, not a fading
            % approximation. Continuous consumers retain channel/filter
            % delay and must perform timing recovery on their RX buffer.
            ip.addParameter("OutputSampleAlignment", "grant_delay_aligned", ...
                @(v) ischar(v) || isstring(v));
            ip.addParameter("InputSampleDomain", "logical_ports", ...
                @(v) ischar(v) || isstring(v));
            ip.parse(varargin{:});
            explicitPathGainCapture = ip.Results.CapturePathGains;
            captureReference = logical(ip.Results.CaptureChannelReference);
            reference = struct([]);
            inputDomain = string(ip.Results.InputSampleDomain);
            if ~isscalar(inputDomain) || ismissing(inputDomain) || ...
                    ~any(inputDomain == ["logical_ports", "materialized_channel_ports"])
                error("ChannelFactory:InvalidInputSampleDomain", ...
                    "InputSampleDomain must be logical_ports or materialized_channel_ports.");
            end
            projectedInput = inputDomain == "materialized_channel_ports";
            outputAlignment = string(ip.Results.OutputSampleAlignment);
            if ~isscalar(outputAlignment) || ismissing(outputAlignment) || ...
                    ~any(outputAlignment == ["grant_delay_aligned", "continuous_raw_samples"])
                error("ChannelFactory:InvalidOutputSampleAlignment", ...
                    "OutputSampleAlignment must be grant_delay_aligned or continuous_raw_samples.");
            end
            continuousOutput = outputAlignment == "continuous_raw_samples";
            if captureReference && (~continuousOutput || ~projectedInput || nargout<4)
                error("ChannelFactory:InvalidChannelReferenceRequest", ...
                    "Retain the fourth output and request actual continuous materialized-port samples for channel scoring.");
            end
            if (continuousOutput || projectedInput) && (~isstruct(state) || ~isscalar(state) || ...
                    ~isfield(state, "ContractVersion") || ...
                    ~logical(sixgr.util.structGet(state, "Initialized", false)) || ...
                    ~logical(sixgr.util.structGet(state, "Materialized", false)))
                error("ChannelFactory:UninitializedContinuousChannel", ...
                    "Continuous samples require an initialized and materialized authoritative runtime channel.");
            end
            if (continuousOutput || projectedInput) && logical(sixgr.util.structGet(state, "UseFading", false)) && ...
                    isempty(sixgr.util.structGet(state, "Obj", []))
                error("ChannelFactory:MissingContinuousFadingObject", ...
                    "A continuous fading stream cannot pass samples through without its channel object.");
            end
            if continuousOutput && isa(sixgr.util.structGet(state, "Obj", []), "nrCDLChannel") && ...
                    ~isinf(state.Obj.SampleDensity)
                error("ChannelFactory:ContinuousCDLRequiresPerSampleFading", ...
                    "Continuous CDL reception requires channels.per_sample_fading_enabled=true; finite snapshot sampling depends on chunk boundaries.");
            end
            if continuousOutput && (~isnumeric(x) || ~ismatrix(x) || ...
                    isempty(x) || any(~isfinite(x(:))))
                error("ChannelFactory:InvalidContinuousSamples", ...
                    "Continuous channel input must be a finite, nonempty sample matrix.");
            end
            if projectedInput && (~isfloat(x) || ~ismatrix(x) || isempty(x) || ...
                    any(~isfinite(x(:))) || ...
                    size(x,2) ~= double(sixgr.util.structGet(state,"NumTxAnt",NaN)))
                error("ChannelFactory:ProjectedInputDimensionMismatch", ...
                    "Preprojected samples must be finite floating-point samples on every materialized channel transmit port; implicit projection/padding is forbidden.");
            end
            if captureReference
                object = state.Obj;
                if ~(logical(state.UseFading) && ...
                        (isa(object,'nrCDLChannel') || isa(object,'nrTDLChannel')) && ...
                        object.ChannelFiltering && string(object.ChannelResponseOutput)=="path-gains")
                    error("ChannelFactory:ChannelReferenceBackendUnavailable", ...
                        "An applied NR fading object with filtered samples and path-gain output is required; no synthetic channel reference.");
                end
                if isa(object,'nrTDLChannel') && string(object.PathGainSampleRate)~="signal"
                    error("ChannelFactory:ChannelReferenceSnapshotCoverage", ...
                        "Independent continuous scoring requires one applied fading snapshot per actual sample.");
                end
                referenceFilters = getPathFilters(object);
            end
            y = x;
            replay = struct( ...
                "ChannelRealizationId", "", ...
                "ChannelFadingApplied", false, ...
                "ChannelFadingExecutionStatus", "not_requested", ...
                "ChannelFadingObjectClass", "", ...
                "ChannelModelApplied", "", ...
                "ChannelPathGainsAvailable", false, ...
                "RuntimeChannelStateUsed", false, ...
                "RuntimeChannelLinkKey", "", ...
                "RuntimeChannelStateKey", "", ...
                "RuntimeChannelSeed", NaN, ...
                "RuntimeChannelReciprocityExact", false, ...
                "RuntimeChannelReciprocityDirection", "", ...
                "RuntimeChannelReciprocitySource", "", ...
                "RuntimeChannelReciprocityApproximationMode", "", ...
                "RuntimeChannelTransmitAndReceiveSwapped", false, ...
                "RuntimeChannelResetCount", NaN, ...
                "RuntimeChannelStartSample", NaN, ...
                "RuntimeChannelEndSample", NaN, ...
                "RuntimeChannelIdleAdvancedSamples", NaN, ...
                "RuntimeChannelMaterializedTxPorts", NaN, ...
                "RuntimeChannelActiveTxPorts", NaN, ...
                "RuntimeChannelInputPaddedToMaterializedPorts", false, ...
                "RuntimeChannelInputPaddingColumns", 0, ...
                "RuntimeChannelElementExpansionApplied", false, ...
                "RuntimeChannelExternalLogicalTxPorts", NaN, ...
                "RuntimeChannelPhysicalTxElements", NaN, ...
                "RuntimeChannelElementExpansionMatrixSHA256", "", ...
                "RuntimeChannelElementExpansionChunkSamples", NaN, ...
                "RuntimeChannelInputWaveformSHA256", "", ...
                "RuntimeChannelInputSampleDomain", inputDomain, ...
                "RuntimeChannelInputAlreadyProjected", projectedInput, ...
                "RuntimeChannelOutputWaveformSHA256", "", ...
                "RuntimeChannelPathGainsSHA256", "", ...
                "RuntimeChannelPathGainElementCount", 0, ...
                "RuntimeChannelPathGainDimensions", "", ...
                "RuntimeChannelPathGainsPreview", complex([]), ...
                "RuntimeChannelPathGainSampleTimes_s", [], ...
                "RuntimeChannelPathDelays_s", [], ...
                "RuntimeChannelFilterDelay_samples", NaN, ...
                "RuntimeChannelMinimumPathDelay_samples", NaN, ...
                "RuntimeChannelExpectedEarliestArrivalDelay_samples", NaN, ...
                "RuntimeChannelTimingTruthSource", "", ...
                "RuntimeChannelAngleEvidenceAvailable", false, ...
                "RuntimeChannelAnglesAoD_deg", [], ...
                "RuntimeChannelAnglesAoA_deg", [], ...
                "RuntimeChannelAnglesZoD_deg", [], ...
                "RuntimeChannelAnglesZoA_deg", [], ...
                "RuntimeChannelAngleCoordinateFrame", "", ...
                "RuntimeChannelAngleEvidenceSource", "", ...
                "RuntimeChannelCanonicalInputSamples", NaN, ...
                "RuntimeChannelAlignmentLookaheadSamples", 0, ...
                "RuntimeChannelAlignmentLookaheadExecutedOnFork", false, ...
                "RuntimeChannelOutputSampleAlignment", outputAlignment, ...
                "RuntimeChannelAppliedAlignmentTrimSamples", 0, ...
                "RuntimeChannelObjectClockExact", false, ...
                "RuntimeChannelPathGainPreviewElementCount", 0, ...
                "RuntimeChannelPathGainPreviewTruncated", false, ...
                "RuntimeChannelPathGainCaptureRequested", false, ...
                "RuntimeChannelPathGainCapturePolicy", "not_requested", ...
                "RuntimeChannelPathGainCaptureSatisfied", false);
            if ~(isstruct(state) && isfield(state, "ContractVersion"))
                return;
            end
            replay.RuntimeChannelStateUsed = true;
            replay.RuntimeChannelLinkKey = char(string(sixgr.util.structGet(state, "LinkKey", "")));
            replay.RuntimeChannelStateKey = char(string(sixgr.util.structGet(state, ...
                "StateKey", replay.RuntimeChannelLinkKey)));
            replay.RuntimeChannelSeed = double(sixgr.util.structGet(state, "Seed", NaN));
            replay.RuntimeChannelReciprocityExact = logical(sixgr.util.structGet( ...
                state, "Meta.RuntimeTDDReciprocityExact", false));
            replay.RuntimeChannelReciprocityDirection = char(string(sixgr.util.structGet( ...
                state, "Meta.RuntimeTDDReciprocityDirection", "")));
            replay.RuntimeChannelReciprocitySource = char(string(sixgr.util.structGet( ...
                state, "Meta.RuntimeTDDReciprocitySource", "")));
            replay.RuntimeChannelReciprocityApproximationMode = char(string( ...
                sixgr.util.structGet(state, ...
                "Meta.RuntimeTDDReciprocityApproximationMode", "")));
            replay.RuntimeChannelTransmitAndReceiveSwapped = logical( ...
                sixgr.channel.ChannelFactory.localObjectLogicalProperty( ...
                sixgr.util.structGet(state, "Obj", []), ...
                "TransmitAndReceiveSwapped", false));
            replay.RuntimeChannelResetCount = double(sixgr.util.structGet(state, "ResetCount", NaN));
            replay.RuntimeChannelStartSample = double(sixgr.util.structGet(state, "CurrentSampleIndex", 0));
            replay.RuntimeChannelIdleAdvancedSamples = double(sixgr.util.structGet(state, "LastIdleAdvancedSamples", 0));
            filterDelay = double(sixgr.util.structGet(state, "ChannelTrimSamples", NaN));
            pathDelays = sixgr.channel.ChannelFactory.localRuntimePathDelays( ...
                sixgr.util.structGet(state, "Obj", []));
            minimumPathDelay = NaN;
            if ~isempty(pathDelays) && isfinite(double(sixgr.util.structGet(state, "SampleRate_Hz", NaN)))
                minimumPathDelay = min(double(pathDelays(:))) * double(state.SampleRate_Hz);
            elseif ~logical(sixgr.util.structGet(state, "UseFading", false))
                minimumPathDelay = 0;
            end
            replay.RuntimeChannelFilterDelay_samples = filterDelay;
            replay.RuntimeChannelMinimumPathDelay_samples = minimumPathDelay;
            if isfinite(filterDelay) && isfinite(minimumPathDelay)
                replay.RuntimeChannelExpectedEarliestArrivalDelay_samples = ...
                    filterDelay + minimumPathDelay;
                replay.RuntimeChannelTimingTruthSource = ...
                    "executed_channel_object_filter_delay_plus_minimum_physical_path_delay";
            end
            replay.RuntimeChannelInputWaveformSHA256 = ...
                sixgr.channel.ChannelFactory.runtimeNumericArraySHA256(x);
            materializedTx = max(1, round(double(sixgr.util.structGet(state, "NumTxAnt", max(1, size(x, 2))))));
            activeTx = max(1, size(x, 2));
            externalTx = max(1, round(double(sixgr.util.structGet( ...
                state, "ExternalLogicalTxPorts", materializedTx))));
            elementExpansion = logical(sixgr.util.structGet( ...
                state, "ElementExpansionApplied", false)) && ~projectedInput;
            replay.RuntimeChannelMaterializedTxPorts = double(materializedTx);
            replay.RuntimeChannelActiveTxPorts = double(activeTx);
            replay.RuntimeChannelElementExpansionApplied = elementExpansion;
            replay.RuntimeChannelExternalLogicalTxPorts = double(externalTx);
            replay.RuntimeChannelPhysicalTxElements = double(sixgr.util.structGet( ...
                state, "PhysicalChannelTxElements", materializedTx));
            replay.RuntimeChannelElementExpansionMatrixSHA256 = char(string( ...
                sixgr.util.structGet(state, "ElementExpansionMatrixSHA256", "")));
            replay.RuntimeChannelElementExpansionChunkSamples = double( ...
                sixgr.util.structGet(state, "ElementExpansionChunkSamples", NaN));
            if projectedInput
                % A composite can contain several distinct precoders. Its
                % contributor records own those maps, not this last logical
                % map stored in the materialized channel state.
                replay.RuntimeChannelElementExpansionMatrixSHA256 = "";
                replay.RuntimeChannelElementExpansionChunkSamples = NaN;
                replay.RuntimeChannelExternalLogicalTxPorts = NaN;
            end
            if ~(logical(sixgr.util.structGet(state, "UseFading", false)) && isfield(state, "Obj") && ~isempty(state.Obj))
                replay.ChannelFadingExecutionStatus = "runtime_channel_state_awgn_or_not_materialized";
                replay.RuntimeChannelEndSample = replay.RuntimeChannelStartSample + size(x, 1);
                state.CurrentSampleIndex = replay.RuntimeChannelEndSample;
                state.TotalAppliedSamples = double(sixgr.util.structGet(state, "TotalAppliedSamples", 0)) + size(x, 1);
                fs = double(sixgr.util.structGet(state, "SampleRate_Hz", NaN));
                state.CurrentTime_s = NaN;
                if isfinite(fs) && fs > 0
                    state.CurrentTime_s = double(state.CurrentSampleIndex) / fs;
                end
                replay.RuntimeChannelOutputWaveformSHA256 = ...
                    replay.RuntimeChannelInputWaveformSHA256;
                replay.ChannelRealizationId = ...
                    sixgr.channel.ChannelFactory.runtimeChannelRealizationId(state, replay);
                return;
            end
            replay.ChannelFadingExecutionStatus = "attempted";
            replay.ChannelFadingObjectClass = class(state.Obj);
            if isprop(state.Obj,'DelayProfile')
                replay.ChannelModelApplied = string(state.Obj.DelayProfile);
            end
            expectedActiveTx = materializedTx;
            if elementExpansion
                expectedActiveTx = externalTx;
            end
            if activeTx > expectedActiveTx
                error("ChannelFactory:RuntimeChannelDimensionChange", ...
                    "Runtime channel '%s' was materialized for %d external Tx port(s), but this grant has %d waveform column(s).", ...
                    char(string(sixgr.util.structGet(state, "LinkKey", ""))), expectedActiveTx, activeTx);
            end
            xChannel = x;
            if activeTx < expectedActiveTx
                xChannel = [x zeros(size(x, 1), expectedActiveTx - activeTx, 'like', x)];
                replay.RuntimeChannelInputPaddedToMaterializedPorts = true;
                replay.RuntimeChannelInputPaddingColumns = double(expectedActiveTx - activeTx);
            end
            padSamples = max(0, round(double(sixgr.util.structGet(state, "ChannelPadSamples", 0))));
            trimSamples = max(0, round(double(sixgr.util.structGet(state, "ChannelTrimSamples", 0))));
            if continuousOutput
                % No fabricated future silence at each chunk boundary:
                % delayed energy must emerge when the NEXT real samples
                % traverse this same persistent object.
                padSamples = 0;
                trimSamples = 0;
            end
            replay.RuntimeChannelCanonicalInputSamples = double(size(xChannel, 1));
            replay.RuntimeChannelAlignmentLookaheadSamples = double(padSamples);
            pathGainCaptureEnabled = double(sixgr.util.structGet(state, ...
                "RuntimeDiagnosticPathGainMaxElements", 0)) > 0;
            if isempty(explicitPathGainCapture)
                capturePathGains = pathGainCaptureEnabled && ...
                    ~logical(sixgr.util.structGet(state, ...
                    "RuntimeDiagnosticPathGainCaptureCompleted", false));
                if capturePathGains
                    replay.RuntimeChannelPathGainCapturePolicy = ...
                        "automatic_first_executed_waveform";
                else
                    replay.RuntimeChannelPathGainCapturePolicy = ...
                        "automatic_capture_already_completed_or_disabled";
                end
            else
                capturePathGains = pathGainCaptureEnabled && ...
                    logical(explicitPathGainCapture);
                if capturePathGains
                    replay.RuntimeChannelPathGainCapturePolicy = ...
                        "explicit_same_trial_runtime_request";
                elseif logical(explicitPathGainCapture)
                    replay.RuntimeChannelPathGainCapturePolicy = ...
                        "explicit_request_disabled_by_zero_capture_budget";
                else
                    replay.RuntimeChannelPathGainCapturePolicy = ...
                        "explicitly_not_requested";
                end
            end
            replay.RuntimeChannelPathGainCaptureRequested = logical(capturePathGains);
            if captureReference
                capturePathGains = true;
                replay.RuntimeChannelPathGainCaptureRequested = true;
                replay.RuntimeChannelPathGainCapturePolicy = "explicit_same_execution_full_channel_reference";
            end
            % Advance the authoritative channel object by exactly the real
            % waveform samples.  Alignment needs a bounded causal tail after
            % the grant, but feeding those zeros into the canonical object
            % corrupts the fading clock and inserts an artificial idle gap
            % before the next slot.  Clone the post-grant object and execute
            % the zero lookahead only on that disposable branch.
            if captureReference
                % Exactly one state advance. Do not catch and call this
                % persistent channel again if an output contract fails.
                [yHead, pathGains, sampleTimes] = state.Obj(xChannel);
                if size(pathGains,1)~=size(xChannel,1) || ...
                        size(pathGains,3)~=state.NumTxAnt || size(pathGains,4)~=state.NumRxAnt || ...
                        size(referenceFilters,2)~=size(pathGains,2) || ...
                        ~isequal(size(sampleTimes),[size(xChannel,1) 1]) || ...
                        any(~isfinite(pathGains(:))) || any(~isfinite(referenceFilters(:))) || ...
                        any(~isfinite(sampleTimes)) || ...
                        any(abs(diff(sampleTimes)*state.SampleRate_Hz-1)>1e-6)
                    error("ChannelFactory:IncompleteAppliedChannelReference", ...
                        "Applied path gains, filters, antenna dimensions and snapshot times must cover the complete physical interval.");
                end
                reference = struct('Source',"same_executed_NR_channel_path_gains_and_filters", ...
                    'StartSample',state.CurrentSampleIndex, ...
                    'EndSampleExclusive',state.CurrentSampleIndex+size(xChannel,1), ...
                    'SampleRateHz',state.SampleRate_Hz,'PathGains',pathGains, ...
                    'PathFilters',referenceFilters,'SampleTimes_s',sampleTimes, ...
                    'NormalizeChannelOutputs',logical(state.Obj.NormalizeChannelOutputs), ...
                    'NormalizePathGains',logical(state.Obj.NormalizePathGains), ...
                    'NumTransmitAntennas',state.NumTxAnt,'NumReceiveAntennas',state.NumRxAnt, ...
                    'StateKey',string(state.StateKey),'AdditionalChannelExecutions',0, ...
                    'ReceiverEstimatorInput',false,'LargeScaleLossApplied',false, ...
                    'PhysicalPortMappingApplied',false,'RFIncluded',false);
            elseif elementExpansion
                [yHead, pathGains, sampleTimes] = ...
                    sixgr.channel.ChannelFactory.localApplyElementExpandedChannel( ...
                    state, xChannel, capturePathGains);
            elseif capturePathGains && continuousOutput
                % The shared clock cannot retry a stateful channel call.
                [yHead, pathGains, sampleTimes] = state.Obj(xChannel);
            elseif capturePathGains
                try
                    [yHead, pathGains, sampleTimes] = state.Obj(xChannel);
                catch
                    try
                        [yHead, pathGains] = state.Obj(xChannel);
                        sampleTimes = [];
                    catch
                        yHead = state.Obj(xChannel);
                        pathGains = [];
                        sampleTimes = [];
                    end
                end
            else
                yHead = state.Obj(xChannel);
                pathGains = [];
                sampleTimes = [];
            end
            if capturePathGains
                % Request the potentially large Ns-by-Npath-by-Nt-by-Nr
                % tensor once per persistent link/drop. Evidence collection
                % must not add this allocation to every subsequent grant.
                state.RuntimeDiagnosticPathGainCaptureCompleted = true;
            end
            yRaw = yHead;
            if padSamples > 0
                tailState = sixgr.channel.ChannelFactory.forkRuntimeChannelState(state);
                tailInput = zeros(padSamples, size(xChannel, 2), 'like', xChannel);
                if elementExpansion
                    [yTail, ~, ~] = ...
                        sixgr.channel.ChannelFactory.localApplyElementExpandedChannel( ...
                        tailState, tailInput, false);
                else
                    yTail = tailState.Obj(tailInput);
                end
                yRaw = [yHead; yTail];
                replay.RuntimeChannelAlignmentLookaheadExecutedOnFork = true;
            end
            if continuousOutput
                if size(yRaw, 1) ~= size(x, 1)
                    error("ChannelFactory:ContinuousSampleCountMismatch", ...
                        "Continuous channel produced %d samples for %d real inputs; padding/trimming is forbidden.", ...
                        size(yRaw, 1), size(x, 1));
                end
                y = yRaw;
            elseif trimSamples > 0 && size(yRaw, 1) >= (trimSamples + size(x, 1))
                y = yRaw(1+trimSamples:trimSamples+size(x, 1), :);
                replay.RuntimeChannelAppliedAlignmentTrimSamples = trimSamples;
            else
                y = yRaw;
                if size(y, 1) > size(x, 1)
                    y = y(1:size(x, 1), :);
                elseif size(y, 1) < size(x, 1)
                    y(end+1:size(x, 1), :) = cast(0, 'like', y); %#ok<AGROW>
                end
            end
            replay.ChannelFadingApplied = true;
            replay.ChannelFadingExecutionStatus = "applied_persistent_runtime_channel_object";
            replay.ChannelPathGainsAvailable = ~isempty(pathGains);
            replay.RuntimeChannelPathGainCaptureSatisfied = ...
                logical(capturePathGains) && ~isempty(pathGains);
            replay.RuntimeChannelOutputWaveformSHA256 = ...
                sixgr.channel.ChannelFactory.runtimeNumericArraySHA256(y);
            if ~isempty(pathGains)
                replay.RuntimeChannelPathGainsSHA256 = ...
                    sixgr.channel.ChannelFactory.runtimeNumericArraySHA256(pathGains);
                replay.RuntimeChannelPathGainElementCount = double(numel(pathGains));
                replay.RuntimeChannelPathGainDimensions = char(join(string(size(pathGains)), "x"));
                maxPreviewElements = max(1, round(double(sixgr.util.structGet( ...
                    state, "RuntimeDiagnosticPathGainMaxElements", 1024))));
                [preview, previewTimes, wasTruncated] = ...
                    sixgr.channel.ChannelFactory.localBoundPathGainPreview( ...
                    pathGains, sampleTimes, maxPreviewElements);
                replay.RuntimeChannelPathGainsPreview = preview;
                replay.RuntimeChannelPathGainSampleTimes_s = previewTimes;
                replay.RuntimeChannelPathDelays_s = pathDelays;
                angleEvidence = sixgr.channel.ChannelFactory.localRuntimeAngleEvidence( ...
                    state.Obj, size(pathGains, 2));
                replay.RuntimeChannelAngleEvidenceAvailable = angleEvidence.Available;
                replay.RuntimeChannelAnglesAoD_deg = angleEvidence.AnglesAoD_deg;
                replay.RuntimeChannelAnglesAoA_deg = angleEvidence.AnglesAoA_deg;
                replay.RuntimeChannelAnglesZoD_deg = angleEvidence.AnglesZoD_deg;
                replay.RuntimeChannelAnglesZoA_deg = angleEvidence.AnglesZoA_deg;
                replay.RuntimeChannelAngleCoordinateFrame = ...
                    angleEvidence.CoordinateFrame;
                replay.RuntimeChannelAngleEvidenceSource = angleEvidence.Source;
                replay.RuntimeChannelPathGainPreviewElementCount = double(numel(preview));
                replay.RuntimeChannelPathGainPreviewTruncated = logical(wasTruncated);
            end
            state.LastPathGainsAvailable = replay.ChannelPathGainsAvailable;
            state.LastApplyStartSample = replay.RuntimeChannelStartSample;
            state.LastApplyEndSample = replay.RuntimeChannelStartSample + size(x, 1);
            state.CurrentSampleIndex = state.LastApplyEndSample;
            fs = double(sixgr.util.structGet(state, "SampleRate_Hz", NaN));
            if isfinite(fs) && fs > 0
                state.CurrentTime_s = double(state.CurrentSampleIndex) / fs;
            end
            state.TotalAppliedSamples = double(sixgr.util.structGet(state, "TotalAppliedSamples", 0)) + size(x, 1);
            state.TotalObjectInputSamples = double(sixgr.util.structGet(state, "TotalObjectInputSamples", 0)) + size(xChannel, 1);
            expectedObjectSamples = double(sixgr.util.structGet(state, "WarmupSamples", 0)) + ...
                double(state.CurrentSampleIndex);
            replay.RuntimeChannelObjectClockExact = ...
                double(state.TotalObjectInputSamples) == expectedObjectSamples;
            if ~replay.RuntimeChannelObjectClockExact
                error("ChannelFactory:RuntimeChannelObjectClockMismatch", ...
                    ['Runtime channel canonical object consumed %d samples, but its ' ...
                     'warmup plus logical clock requires %d samples.'], ...
                    round(double(state.TotalObjectInputSamples)), ...
                    round(double(expectedObjectSamples)));
            end
            replay.RuntimeChannelEndSample = double(state.CurrentSampleIndex);
            replay.ChannelRealizationId = ...
                sixgr.channel.ChannelFactory.runtimeChannelRealizationId(state, replay);
        end

        function realizationId = runtimeChannelRealizationId(state, replay)
            % Identify the exact persistent-channel sample slice that was
            % applied.  This digest is derived from executed state, never
            % from the configured profile alone, and intentionally avoids
            % serializing the mutable System object or hidden path gains.
            payload = struct( ...
                "ContractVersion", string(sixgr.util.structGet(state, "ContractVersion", "")), ...
                "LinkKey", string(sixgr.util.structGet(replay, "RuntimeChannelLinkKey", "")), ...
                "Seed", double(sixgr.util.structGet(replay, "RuntimeChannelSeed", NaN)), ...
                "ResetCount", double(sixgr.util.structGet(replay, "RuntimeChannelResetCount", NaN)), ...
                "StartSample", double(sixgr.util.structGet(replay, "RuntimeChannelStartSample", NaN)), ...
                "EndSample", double(sixgr.util.structGet(replay, "RuntimeChannelEndSample", NaN)), ...
                "ChannelObjectClass", string(sixgr.util.structGet(replay, "ChannelFadingObjectClass", "")), ...
                "FadingApplied", logical(sixgr.util.structGet(replay, "ChannelFadingApplied", false)), ...
                "MaterializedTxPorts", double(sixgr.util.structGet(replay, "RuntimeChannelMaterializedTxPorts", NaN)), ...
                "ActiveTxPorts", double(sixgr.util.structGet(replay, "RuntimeChannelActiveTxPorts", NaN)), ...
                "PhysicalTxElements", double(sixgr.util.structGet(replay, "RuntimeChannelPhysicalTxElements", NaN)), ...
                "ElementExpansionMatrixSHA256", string(sixgr.util.structGet(replay, "RuntimeChannelElementExpansionMatrixSHA256", "")));
            digest = lower(string(sixgr.channel.hashChannelRFConfig(payload)));
            realizationId = char("ch_" + extractBefore(digest, 17));
        end

        function hash = runtimeNumericArraySHA256(value)
            % Byte-exact digest used for executed waveform/path-gain
            % lineage.  Size and class are included to avoid equal byte
            % streams from different array interpretations colliding.
            header = uint8(char("runtime_array:" + string(class(value)) + ":"));
            dims = reshape(typecast(uint64(size(value)), "uint8"), [], 1);
            if isempty(value)
                payload = uint8([]);
            elseif isnumeric(value) || islogical(value)
                realBytes = reshape(typecast(double(real(value(:))), "uint8"), [], 1);
                imagBytes = reshape(typecast(double(imag(value(:))), "uint8"), [], 1);
                payload = [realBytes; imagBytes];
            else
                payload = uint8(unicode2native(char(string(class(value))), "UTF-8"));
            end
            hash = char(lower(string(sixgr.util.sha256Hex([header(:); dims; payload(:)]))));
        end

        function [padSamples, trimSamples] = resolveChannelDelaySamples(chObj, fs)
            padSamples = 0;
            trimSamples = 0;
            if isempty(chObj) || ~isfinite(double(fs)) || double(fs) <= 0
                return;
            end
            filterDelay = 0;
            pathDelays = [];
            try
                chInfo = info(chObj);
                filterDelay = double(sixgr.util.structGet(chInfo, "ChannelFilterDelay", 0));
                pathDelays = sixgr.util.structGet(chInfo, "PathDelays", []);
            catch
            end
            if isempty(pathDelays)
                try
                    pathDelays = double(chObj.PathDelays);
                catch
                    pathDelays = [];
                end
            end
            maxPathDelay = 0;
            if ~isempty(pathDelays)
                maxPathDelay = ceil(max(double(pathDelays(:))) * double(fs));
            end
            padSamples = max(0, round(filterDelay + maxPathDelay));
            trimSamples = max(0, round(filterDelay));
        end

        function tf = supportsRuntimeTDDReciprocity(cfg)
            % Duplex is a single validated authority shared by every PHY
            % consumer.  A channel must not select one alias and silently
            % ignore a contradictory value held by another subsystem.
            duplexMode = lower(sixgr.phy.frame.resolveDuplexMode(cfg));
            model = upper(strtrim(string(sixgr.util.structGet(cfg, ...
                "channel.model", "AWGN"))));
            doppler = double(sixgr.util.structGet(cfg, "channel.doppler_Hz", ...
                sixgr.util.structGet(cfg, "channel.dopplerHz", ...
                sixgr.util.structGet(cfg, "channel.fading.maxDoppler_Hz", NaN))));
            % Duplex mode is the governing authority.  A stale TDD token
            % must never make an FDD channel share state or seeds.
            tddRequested = duplexMode == "tdd";
            validDoppler = ~isempty(doppler) && all(isfinite(doppler(:))) && ...
                all(doppler(:) >= 0);
            % Physical propagation reciprocity follows the resolved duplex
            % carrier, not a CSI-use policy.  A scenario may disable SRS-
            % based CSI transfer or calibration assumptions, but that must
            % not create two unrelated over-the-air fading realizations on
            % one TDD carrier. RF-chain non-reciprocity is applied by the
            % explicit Tx/Rx impairment stages outside this channel object.
            tf = logical(tddRequested && ...
                (startsWith(model,"TDL") || startsWith(model,"CDL") || ...
                any(model == ["NRTDL","NRCDL"])) && validDoppler);
        end

        function tf = supportsDynamicRuntimeTDDReciprocity(cfg)
            doppler = double(sixgr.util.structGet(cfg, "channel.doppler_Hz", ...
                sixgr.util.structGet(cfg, "channel.dopplerHz", ...
                sixgr.util.structGet(cfg, "channel.fading.maxDoppler_Hz", NaN))));
            tf = sixgr.channel.ChannelFactory.supportsRuntimeTDDReciprocity(cfg) && ...
                any(abs(doppler(:)) > eps);
        end
    end

    methods(Static, Access=private)
        function state = localConsumeRuntimeIdleSamples(state, n, numTx, prototype)
            % Physical input consumption only. Callers own the logical clock
            % so deferred materialization cannot count the interval twice.
            if ~(isfinite(double(numTx)) && double(numTx) >= 1)
                numTx = double(sixgr.util.structGet(state, "NumTxAnt", 1));
            end
            materializedTx = double(sixgr.util.structGet(state, "NumTxAnt", NaN));
            if isfinite(materializedTx) && materializedTx >= 1
                numTx = max(double(numTx), round(materializedTx));
            end
            if isempty(prototype)
                z = zeros(n, max(1, round(double(numTx))));
            else
                z = zeros(n, max(1, round(double(numTx))), 'like', prototype);
            end
            try
                state.Obj(z);
            catch
                [~, ~] = state.Obj(z);
            end
            state.TotalObjectInputSamples = double(sixgr.util.structGet(state, "TotalObjectInputSamples", 0)) + n;
        end

        function [matrix, enabled] = ...
                localResolvePortToElementExpansion( ...
                runtimeAntenna, runtimeMeta, waveformColumns)
            matrix = sixgr.util.structGet( ...
                runtimeAntenna, "PortToElementMatrix", []);
            enabled = false;
            hybridEnabled = logical(sixgr.util.structGet( ...
                runtimeAntenna, "HybridBeamformingEnabled", false)) || ...
                logical(sixgr.util.structGet( ...
                runtimeMeta, "HybridBeamformingEnabled", false));
            projectionEnabled = logical(sixgr.util.structGet( ...
                runtimeAntenna, "PortToElementExpansionEnabled", false)) || ...
                logical(sixgr.util.structGet( ...
                runtimeMeta, "PortToElementExpansionEnabled", false));
            if ~(hybridEnabled || projectionEnabled)
                return;
            end
            if isempty(matrix)
                return;
            end
            if ~(isnumeric(matrix) && ismatrix(matrix) ...
                    && all(isfinite(real(matrix(:)))) ...
                    && all(isfinite(imag(matrix(:)))))
                error("ChannelFactory:InvalidPortToElementMatrix", ...
                    "Runtime PortToElementMatrix must be a finite numeric matrix.");
            end
            if size(matrix, 2) ~= waveformColumns
                return;
            end
            if size(matrix, 1) <= size(matrix, 2)
                return;
            end
            gram = matrix' * matrix;
            residual = norm(gram - eye(size(gram), "like", gram), "fro");
            if residual > 1e-9 * max(1, size(matrix, 2))
                error("ChannelFactory:NonPowerPreservingPortToElementMatrix", ...
                    "PortToElementMatrix must have orthonormal logical-port columns (residual %.3g).", ...
                    residual);
            end
            enabled = true;
        end

        function [runtimeAntenna, runtimeMeta] = ...
                localElementDomainRuntimeAntenna( ...
                runtimeAntenna, runtimeMeta, logicalPorts, physicalElements)
            if ~isstruct(runtimeAntenna)
                runtimeAntenna = struct();
            end
            if ~isstruct(runtimeMeta)
                runtimeMeta = struct();
            end
            runtimeAntenna.SourceLogicalWaveformColumns = double(logicalPorts);
            runtimeAntenna.NumWaveformColumns = double(physicalElements);
            runtimeAntenna.WaveformDomain = "element";
            runtimeAntenna.PortToElementExpansionEnabled = true;
            runtimeMeta.SourceLogicalWaveformColumns = double(logicalPorts);
            runtimeMeta.NumWaveformColumns = double(physicalElements);
            runtimeMeta.WaveformDomain = "element";
            runtimeMeta.PortToElementExpansionEnabled = true;
        end

        function [yRaw, pathGains, sampleTimes] = ...
                localApplyElementExpandedChannel(state, xLogical, capturePathGains)
            if nargin < 3
                capturePathGains = false;
            end
            matrix = sixgr.util.structGet(state, "PortToElementMatrix", []);
            if isempty(matrix) || size(matrix, 2) ~= size(xLogical, 2)
                error("ChannelFactory:ElementExpansionDimensionMismatch", ...
                    "Runtime element expansion matrix does not match logical waveform columns.");
            end
            chunkSamples = max(1, round(double(sixgr.util.structGet( ...
                state, "ElementExpansionChunkSamples", 4096))));
            nRows = size(xLogical, 1);
            nChunks = ceil(nRows / chunkSamples);
            parts = cell(nChunks, 1);
            matrixLike = cast(matrix, "like", xLogical);
            pathGains = [];
            sampleTimes = [];
            for chunkIndex = 1:nChunks
                firstRow = (chunkIndex - 1) * chunkSamples + 1;
                lastRow = min(nRows, chunkIndex * chunkSamples);
                xPhysical = xLogical(firstRow:lastRow, :) * matrixLike.';
                if logical(capturePathGains) && chunkIndex == 1
                    try
                        [parts{chunkIndex}, pathGains, sampleTimes] = ...
                            state.Obj(xPhysical);
                    catch
                        try
                            [parts{chunkIndex}, pathGains] = state.Obj(xPhysical);
                            sampleTimes = [];
                        catch
                            parts{chunkIndex} = state.Obj(xPhysical);
                            pathGains = [];
                            sampleTimes = [];
                        end
                    end
                else
                    parts{chunkIndex} = state.Obj(xPhysical);
                end
            end
            yRaw = vertcat(parts{:});
            % Capture only the first executed chunk once per persistent
            % link/drop.  This is the exact tensor produced while filtering
            % the same element-domain samples consumed by the receiver; it
            % is subsequently bounded by localBoundPathGainPreview.  Never
            % reconstruct this evidence from the configured PDP.
        end

        function [preview, previewTimes, truncated] = ...
                localBoundPathGainPreview(pathGains, sampleTimes, maxElements)
            % Preserve a bounded, exact subset of the executed channel
            % tensor for evidence generation.  This never enters a receiver
            % and therefore cannot become a perfect-CSI oracle.
            sz = size(pathGains);
            sz(end+1:4) = 1;
            nTime = max(1, sz(1));
            perTime = prod(sz(2:end));
            keepTime = max(1, min(nTime, floor(double(maxElements) / max(1, perTime))));
            if perTime > maxElements
                % Preserve the first exact path/antenna elements if a single
                % complete temporal slice exceeds the configured evidence cap.
                flat = pathGains(:);
                preview = reshape(flat(1:min(numel(flat), maxElements)), [], 1);
                previewTimes = [];
                truncated = numel(preview) < numel(pathGains);
                return;
            end
            subs = repmat({':'}, 1, max(2, ndims(pathGains)));
            subs{1} = 1:keepTime;
            preview = pathGains(subs{:});
            previewTimes = double(sampleTimes(:));
            if ~isempty(previewTimes)
                previewTimes = previewTimes(1:min(numel(previewTimes), keepTime));
            end
            truncated = numel(preview) < numel(pathGains);
        end

        function delays = localRuntimePathDelays(channelObject)
            delays = [];
            try
                channelInfo = info(channelObject);
                delays = double(sixgr.util.structGet(channelInfo, "PathDelays", []));
            catch
            end
            if isempty(delays)
                try
                    delays = double(channelObject.PathDelays);
                catch
                    delays = [];
                end
            end
            delays = reshape(delays, 1, []);
        end

        function evidence = localRuntimeAngleEvidence(channelObject, expectedPathCount)
            evidence = struct( ...
                "Available", false, ...
                "AnglesAoD_deg", [], ...
                "AnglesAoA_deg", [], ...
                "AnglesZoD_deg", [], ...
                "AnglesZoA_deg", [], ...
                "CoordinateFrame", "", ...
                "Source", "");
            if nargin < 2 || ~(isscalar(expectedPathCount) && ...
                    isfinite(expectedPathCount) && expectedPathCount >= 1)
                expectedPathCount = NaN;
            end
            try
                channelInfo = info(channelObject);
            catch
                return;
            end
            names = ["AnglesAoD","AnglesAoA","AnglesZoD","AnglesZoA"];
            values = cell(1, numel(names));
            for i = 1:numel(names)
                raw = double(sixgr.util.structGet(channelInfo, names(i), []));
                raw = reshape(raw, 1, []);
                if isempty(raw) || any(~isfinite(raw))
                    return;
                end
                values{i} = raw;
            end
            lengths = cellfun(@numel, values);
            if any(lengths ~= lengths(1)) || ...
                    (isfinite(expectedPathCount) && lengths(1) ~= round(expectedPathCount))
                return;
            end
            evidence.Available = true;
            evidence.AnglesAoD_deg = values{1};
            evidence.AnglesAoA_deg = values{2};
            evidence.AnglesZoD_deg = values{3};
            evidence.AnglesZoA_deg = values{4};
            evidence.CoordinateFrame = "3gpp_tr38901_global_coordinate_system";
            evidence.Source = "info_on_same_executed_runtime_channel_object";
        end

        function key = localRuntimeSeedKey(cfg, linkKey)
            key = char(string(linkKey));
            if ~sixgr.channel.ChannelFactory.supportsRuntimeTDDReciprocity(cfg)
                return;
            end
            token = string(key);
            tx = regexp(token,"(?:^|;)tx=([^;]+)","tokens","once");
            rx = regexp(token,"(?:^|;)rx=([^;]+)","tokens","once");
            carrier = regexp(token,"(?:^|;)carrier=(.*)$","tokens","once");
            if isempty(tx) || isempty(rx)
                return;
            end
            endpoints = sort([string(tx{1}),string(rx{1})]);
            carrierToken = "";
            if ~isempty(carrier)
                carrierToken = string(carrier{1});
            end
            key = char("tdd_reciprocal;endpoint_a=" + endpoints(1) + ...
                ";endpoint_b=" + endpoints(2) + ";carrier=" + carrierToken);
        end

        function token = localFirstConfigToken(cfg, paths)
            token = "";
            for path = string(paths(:)).'
                value = lower(strtrim(string(sixgr.util.structGet(cfg,path,""))));
                value = value(strlength(value) > 0);
                if ~isempty(value)
                    token = value(1);
                    return;
                end
            end
        end

        function state = localRetargetDynamicTDDChannelState(state, cfg)
            if ~sixgr.channel.ChannelFactory.supportsDynamicRuntimeTDDReciprocity(cfg) || ...
                    ~logical(sixgr.util.structGet(state, ...
                    "Meta.RuntimeTDDReciprocityExact", false))
                return;
            end
            if ~(isfield(state, "Obj") && ~isempty(state.Obj) && ...
                    ismethod(state.Obj, "swapTransmitAndReceive"))
                error("ChannelFactory:DynamicTDDReciprocitySwapUnavailable", ...
                    ['Dynamic TDD reciprocity requires a channel object with ' ...
                     'swapTransmitAndReceive support; runtime object is %s.'], ...
                    class(sixgr.util.structGet(state, "Obj", [])));
            end
            desiredDirection = upper(strtrim(string(sixgr.util.structGet( ...
                state, "Direction", "DL"))));
            if desiredDirection ~= "UL"
                desiredDirection = "DL";
            end
            currentDirection = upper(strtrim(string(sixgr.util.structGet( ...
                state, "Meta.RuntimeTDDReciprocityDirection", ""))));
            if ~any(currentDirection == ["DL","UL"])
                error("ChannelFactory:DynamicTDDReciprocityDirectionUnavailable", ...
                    "Materialized dynamic reciprocal channel has no current direction authority.");
            end
            objectSwapped = logical(state.Obj.TransmitAndReceiveSwapped);
            if objectSwapped ~= (desiredDirection == "UL")
                swapTransmitAndReceive(state.Obj);
            end
            if desiredDirection ~= currentDirection
                state.Meta = sixgr.channel.ChannelFactory.localSwapDirectionalChannelMeta( ...
                    state.Meta);
            end

            % A direction swap changes the physical channel endpoints, not
            % their sizes to match the next waveform's logical port count.
            % In particular one-port PRACH still excites the configured UE
            % array through its explicit port-to-element projection. Read
            % the actual swapped object's dimensions before resolving that
            % projection in materializeRuntimeChannelState.
            channelInfo = info(state.Obj);
            physicalTx = double(sixgr.util.structGet(channelInfo, ...
                "NumInputSignals", sixgr.util.structGet(channelInfo, ...
                "NumTransmitAntennas", NaN)));
            physicalRx = double(sixgr.util.structGet(channelInfo, ...
                "NumOutputSignals", sixgr.util.structGet(channelInfo, ...
                "NumReceiveAntennas", NaN)));
            counts = [physicalTx physicalRx];
            if numel(counts) ~= 2 || any(~isfinite(counts)) || ...
                    any(counts < 1 | counts ~= fix(counts))
                error("ChannelFactory:DynamicTDDPhysicalDimensionsUnavailable", ...
                    "The reciprocal channel object must expose exact input/output antenna dimensions.");
            end
            state.NumTxAnt = physicalTx;
            state.NumRxAnt = physicalRx;
            state.Meta.NumTxAnt = double(state.NumTxAnt);
            state.Meta.NumRxAnt = double(state.NumRxAnt);
            state.Meta.RuntimeTDDReciprocityDirection = char(desiredDirection);
            state.Meta.LinkDirection = lower(char(desiredDirection));
            state.Meta.RuntimeTDDChannelObjectSwapped = ...
                logical(sixgr.channel.ChannelFactory.localObjectLogicalProperty( ...
                state.Obj, "TransmitAndReceiveSwapped", desiredDirection == "UL"));
            [state.ChannelPadSamples, state.ChannelTrimSamples] = ...
                sixgr.channel.ChannelFactory.resolveChannelDelaySamples( ...
                state.Obj, double(state.SampleRate_Hz));
        end

        function ch = localCreateDynamicTDDReciprocalChannel(cfg,state,fs,numTx,numRx,opt)
            direction = upper(strtrim(string(sixgr.util.structGet(state,"Direction","DL"))));
            if direction ~= "UL"
                direction = "DL";
            end
            if direction == "DL"
                canonicalTx = numTx;
                canonicalRx = numRx;
                txRuntime = opt.TransmitAntennaRuntime;
                rxRuntime = opt.ReceiveAntennaRuntime;
                txMeta = opt.TransmitAntennaMeta;
                rxMeta = opt.ReceiveAntennaMeta;
            else
                canonicalTx = numRx;
                canonicalRx = numTx;
                txRuntime = opt.ReceiveAntennaRuntime;
                rxRuntime = opt.TransmitAntennaRuntime;
                txMeta = opt.ReceiveAntennaMeta;
                rxMeta = opt.TransmitAntennaMeta;
            end
            ch = sixgr.channel.ChannelFactory.create(cfg, ...
                "Model", cfg.channel.model, "SampleRate", fs, ...
                "NumTxAnt", canonicalTx, "NumRxAnt", canonicalRx, ...
                "Seed", double(state.Seed), "LinkDirection", "DL", ...
                "TransmitAntennaRuntime", txRuntime, ...
                "ReceiveAntennaRuntime", rxRuntime, ...
                "TransmitAntennaMeta", txMeta, ...
                "ReceiveAntennaMeta", rxMeta);
            if ~(isfield(ch, "Object") && ~isempty(ch.Object) && ...
                    ismethod(ch.Object, "swapTransmitAndReceive"))
                error("ChannelFactory:DynamicTDDReciprocitySwapUnavailable", ...
                    ['Exact moving TDD reciprocity requires the selected %s backend ' ...
                     'to implement swapTransmitAndReceive.'], ...
                    class(sixgr.util.structGet(ch, "Object", [])));
            end
            if sixgr.channel.ChannelFactory.localObjectLogicalProperty( ...
                    ch.Object, "NormalizeChannelOutputs", true)
                error("ChannelFactory:DynamicTDDOutputNormalizationForbidden", ...
                    ['Exact moving TDD reciprocity requires ' ...
                     'channels.normalize_channel_outputs=false. Toolbox output ' ...
                     'normalization scales by the receive-array size and therefore ' ...
                     'breaks reciprocal amplitude for unequal endpoint arrays.']);
            end
            if direction == "UL"
                swapTransmitAndReceive(ch.Object);
                ch.Meta = sixgr.channel.ChannelFactory.localSwapDirectionalChannelMeta( ...
                    ch.Meta);
            end
            ch.Type = char(string(ch.Type) + "_DynamicTDDReciprocal");
            ch.Meta.NumTxAnt = double(numTx);
            ch.Meta.NumRxAnt = double(numRx);
            ch.Meta.LinkDirection = lower(char(direction));
            ch.Meta.RuntimeTDDReciprocityExact = true;
            ch.Meta.RuntimeTDDReciprocityDirection = char(direction);
            ch.Meta.RuntimeTDDReciprocitySource = ...
                "matlab_nr_channel_swapTransmitAndReceive_shared_fading_timeline";
            ch.Meta.RuntimeTDDReciprocityApproximationMode = "none_dynamic_exact";
            ch.Meta.RuntimeTDDCanonicalSeed = double(state.Seed);
            ch.Meta.RuntimeTDDStateKey = string(sixgr.util.structGet( ...
                state, "StateKey", ""));
            ch.Meta.RuntimeTDDChannelObjectSwapped = ...
                logical(sixgr.channel.ChannelFactory.localObjectLogicalProperty( ...
                ch.Object, "TransmitAndReceiveSwapped", direction == "UL"));
        end

        function meta = localSwapDirectionalChannelMeta(meta)
            if ~(isstruct(meta) && isscalar(meta))
                meta = struct();
                return;
            end
            pairs = [ ...
                "NumTxAnt", "NumRxAnt"; ...
                "TransmitAntennaNumElements", "ReceiveAntennaNumElements"; ...
                "TransmitAntennaNumPorts", "ReceiveAntennaNumPorts"; ...
                "TransmitAntennaNumWaveformColumns", "ReceiveAntennaNumWaveformColumns"; ...
                "TransmitAntennaWaveformDomain", "ReceiveAntennaWaveformDomain"; ...
                "TransmitAntennaNumRFChains", "ReceiveAntennaNumRFChains"; ...
                "TransmitAntennaPortCountSource", "ReceiveAntennaPortCountSource"; ...
                "TransmitElementPatternApplied", "ReceiveElementPatternApplied"; ...
                "TransmitElementPatternSource", "ReceiveElementPatternSource"; ...
                "TransmitArrayOrientation_deg", "ReceiveArrayOrientation_deg"; ...
                "TransmitAntennaArraySize", "ReceiveAntennaArraySize"; ...
                "TransmitAntennaElementSpacing_lambda", "ReceiveAntennaElementSpacing_lambda"; ...
                "TransmitAntennaElementClass", "ReceiveAntennaElementClass"; ...
                "TDLTransmitCorrelationMatrixSource", "TDLReceiveCorrelationMatrixSource"; ...
                "TDLTransmitCorrelationMatrixSize", "TDLReceiveCorrelationMatrixSize" ...
                ];
            for i = 1:size(pairs, 1)
                left = char(pairs(i, 1));
                right = char(pairs(i, 2));
                hasLeft = isfield(meta, left);
                hasRight = isfield(meta, right);
                if ~(hasLeft || hasRight)
                    continue;
                end
                leftValue = [];
                rightValue = [];
                if hasLeft
                    leftValue = meta.(left);
                end
                if hasRight
                    rightValue = meta.(right);
                end
                meta.(left) = rightValue;
                meta.(right) = leftValue;
            end
        end

        function value = localObjectLogicalProperty(obj, propertyName, fallback)
            value = logical(fallback);
            try
                if isprop(obj, char(propertyName))
                    value = logical(obj.(char(propertyName)));
                end
            catch
                value = logical(fallback);
            end
        end

        function ch = localCreateStaticTDDReciprocalChannel(cfg,state,fs,numTx,numRx,opt)
            direction = upper(strtrim(string(sixgr.util.structGet(state,"Direction","DL"))));
            if direction ~= "UL"
                direction = "DL";
            end
            if direction == "DL"
                canonicalTx = numTx;
                canonicalRx = numRx;
                txRuntime = opt.TransmitAntennaRuntime;
                rxRuntime = opt.ReceiveAntennaRuntime;
                txMeta = opt.TransmitAntennaMeta;
                rxMeta = opt.ReceiveAntennaMeta;
            else
                canonicalTx = numRx;
                canonicalRx = numTx;
                txRuntime = opt.ReceiveAntennaRuntime;
                rxRuntime = opt.TransmitAntennaRuntime;
                txMeta = opt.ReceiveAntennaMeta;
                rxMeta = opt.TransmitAntennaMeta;
            end
            source = sixgr.channel.ChannelFactory.create(cfg, ...
                "Model", cfg.channel.model, "SampleRate", fs, ...
                "NumTxAnt", canonicalTx, "NumRxAnt", canonicalRx, ...
                "Seed", double(state.Seed), ...
                "TransmitAntennaRuntime", txRuntime, ...
                "ReceiveAntennaRuntime", rxRuntime, ...
                "TransmitAntennaMeta", txMeta, ...
                "ReceiveAntennaMeta", rxMeta);
            [canonicalImpulse,evidence] = ...
                sixgr.channel.measureStaticMIMOImpulseResponse( ...
                source.Object,canonicalTx,canonicalRx,fs);
            if direction == "UL"
                endpointImpulse = permute(canonicalImpulse,[1 3 2]);
            else
                endpointImpulse = canonicalImpulse;
            end
            endpoint = sixgr.channel.StaticReciprocalMIMOChannel( ...
                endpointImpulse,fs, ...
                "SourceChannelClass",class(source.Object), ...
                "SourceChannelSeed",double(state.Seed), ...
                "Direction",direction);
            ch = source;
            ch.Object = endpoint;
            ch.Type = char(string(source.Type) + "_StaticTDDReciprocal");
            ch.Meta.RuntimeTDDReciprocityExact = true;
            ch.Meta.RuntimeTDDReciprocityDirection = char(direction);
            ch.Meta.RuntimeTDDReciprocitySource = ...
                "exact_static_toolbox_channel_impulse_and_nonconjugate_spatial_transpose";
            ch.Meta.RuntimeTDDReciprocityApproximationMode = "none_static_lti_exact";
            ch.Meta.RuntimeTDDReciprocityEvidence = evidence;
            ch.Meta.RuntimeTDDCanonicalImpulseSHA256 = char( ...
                sixgr.phy.mimo.MatrixContract.digest(canonicalImpulse));
        end

        function fs = localRuntimeSampleRate(tx, txInfo)
            fs = [];
            if nargin >= 2 && isstruct(txInfo)
                fs = sixgr.util.structGet(txInfo, "OFDM.SampleRate", []);
            end
            if isempty(fs) && isstruct(tx)
                carrier = sixgr.util.structGet(tx, "Carrier", []);
                if ~isempty(carrier)
                    try
                        ofdmInfo = nrOFDMInfo(carrier);
                        fs = double(sixgr.util.structGet(ofdmInfo, "SampleRate", []));
                    catch
                        fs = [];
                    end
                end
            end
            if isempty(fs) || ~isfinite(double(fs)) || double(fs) <= 0
                fs = 30.72e6;
            else
                fs = double(fs);
            end
        end

        function hash = localStringHash(value)
            bytes = uint8(char(string(value)));
            hash = uint32(2166136261);
            for ii = 1:numel(bytes)
                hash = bitxor(hash, uint32(bytes(ii)));
                hash = uint32(mod(uint64(hash) * uint64(16777619), uint64(2^32)));
            end
            hash = double(hash);
        end

        function contract = localValidateRuntimeAntennaPortContract(runtimeAntenna, runtimeMeta, signalPortCount, sideLabel)
            signalPortCount = max(1, round(double(signalPortCount)));
            [numPorts, portSource] = sixgr.channel.ChannelFactory.localRuntimeLogicalPortCount(runtimeAntenna, runtimeMeta);
            [numElements, elementSource] = sixgr.channel.ChannelFactory.localRuntimeElementCount(runtimeAntenna, runtimeMeta);
            [numRFChains, rfSource] = sixgr.channel.ChannelFactory.localRuntimeRFChainCount(runtimeAntenna, runtimeMeta);
            [numWaveformColumns, waveformSource, waveformDomain] = sixgr.channel.ChannelFactory.localRuntimeWaveformColumnCount(runtimeAntenna, runtimeMeta);
            if ~isfinite(numRFChains) && isfinite(numPorts)
                numRFChains = numPorts;
                rfSource = "default_equal_logical_ports";
            end
            if ~isfinite(numWaveformColumns) && isfinite(numPorts)
                numWaveformColumns = numPorts;
                waveformSource = "default_logical_port_waveform_columns";
                waveformDomain = "logical_port";
            end

            runtimeSupplied = (isstruct(runtimeAntenna) && ~isempty(fieldnames(runtimeAntenna))) || ...
                (isstruct(runtimeMeta) && ~isempty(fieldnames(runtimeMeta)));
            if ~isfinite(numPorts) && isfinite(numElements) && runtimeSupplied
                if round(double(numElements)) == signalPortCount
                    numPorts = numElements;
                    portSource = "legacy_runtime_element_count_matches_signal_ports";
                else
                    error("ChannelFactory:RuntimeAntennaPortMismatch", ...
                        "%s runtime antenna evidence has %d element(s) but no logical-port mapping for %d waveform/channel port(s).", ...
                        upper(char(string(sideLabel))), round(double(numElements)), signalPortCount);
                end
            end
            if ~isfinite(numWaveformColumns) && isfinite(numPorts)
                numWaveformColumns = numPorts;
                waveformSource = "default_logical_port_waveform_columns";
                waveformDomain = "logical_port";
            end

            elementDomainDeclared = strcmpi(char(string(waveformDomain)), "element") || ...
                logical(sixgr.util.structGet(runtimeAntenna, "HybridBeamformingEnabled", false)) || ...
                logical(sixgr.util.structGet(runtimeMeta, "HybridBeamformingEnabled", false));
            if isfinite(numWaveformColumns) && round(double(numWaveformColumns)) ~= signalPortCount
                error("ChannelFactory:RuntimeAntennaPortMismatch", ...
                    "%s runtime waveform column count %d from %s does not match channel port count %d.", ...
                    upper(char(string(sideLabel))), round(double(numWaveformColumns)), char(string(waveformSource)), signalPortCount);
            end
            if isfinite(numPorts) && round(double(numPorts)) ~= signalPortCount
                if ~(elementDomainDeclared && isfinite(numElements) && round(double(numElements)) == signalPortCount)
                    error("ChannelFactory:RuntimeAntennaPortMismatch", ...
                        "%s runtime logical port count %d does not match waveform/channel port count %d. Geometry is not discarded to hide this mismatch.", ...
                        upper(char(string(sideLabel))), round(double(numPorts)), signalPortCount);
                end
            end

            contract = struct( ...
                "NumPorts", double(numPorts), ...
                "NumElements", double(numElements), ...
                "NumWaveformColumns", double(numWaveformColumns), ...
                "WaveformDomain", char(string(waveformDomain)), ...
                "NumRFChains", double(numRFChains), ...
                "PortCountSource", char(string(portSource)), ...
                "WaveformColumnCountSource", char(string(waveformSource)), ...
                "ElementCountSource", char(string(elementSource)), ...
                "RFChainCountSource", char(string(rfSource)));
        end

        function [count, source] = localRuntimeLogicalPortCount(runtimeAntenna, runtimeMeta)
            count = NaN;
            source = "";
            candidates = {runtimeMeta, runtimeAntenna};
            labels = ["runtime_meta", "runtime_antenna"];
            fields = ["NumPorts", "NumLogicalPorts", "LogicalPortCount"];
            for c = 1:numel(candidates)
                obj = candidates{c};
                if ~(isstruct(obj) && ~isempty(fieldnames(obj)))
                    continue;
                end
                for f = 1:numel(fields)
                    raw = sixgr.util.structGet(obj, fields(f), NaN);
                    value = sixgr.channel.ChannelFactory.localPositiveIntegerOrNaN(raw);
                    if isfinite(value)
                        count = value;
                        source = labels(c) + "." + fields(f);
                        return;
                    end
                end
            end
            map = sixgr.util.structGet(runtimeAntenna, "PortToElementMatrix", []);
            if isnumeric(map) && ismatrix(map) && size(map, 2) >= 1
                count = size(map, 2);
                source = "runtime_antenna.PortToElementMatrix_columns";
                return;
            end
            map = sixgr.util.structGet(runtimeAntenna, "ElementToPortMatrix", []);
            if isnumeric(map) && ismatrix(map) && size(map, 1) >= 1
                count = size(map, 1);
                source = "runtime_antenna.ElementToPortMatrix_rows";
                return;
            end
        end

        function [count, source] = localRuntimeElementCount(runtimeAntenna, runtimeMeta)
            count = NaN;
            source = "";
            fields = ["NumElements", "Nant"];
            objs = {runtimeMeta, runtimeAntenna};
            labels = ["runtime_meta", "runtime_antenna"];
            for c = 1:numel(objs)
                obj = objs{c};
                if ~(isstruct(obj) && ~isempty(fieldnames(obj)))
                    continue;
                end
                for f = 1:numel(fields)
                    raw = sixgr.util.structGet(obj, fields(f), NaN);
                    value = sixgr.channel.ChannelFactory.localPositiveIntegerOrNaN(raw);
                    if isfinite(value)
                        count = value;
                        source = labels(c) + "." + fields(f);
                        return;
                    end
                end
            end
            map = sixgr.util.structGet(runtimeAntenna, "PortToElementMatrix", []);
            if isnumeric(map) && ismatrix(map) && size(map, 1) >= 1
                count = size(map, 1);
                source = "runtime_antenna.PortToElementMatrix_rows";
                return;
            end
            map = sixgr.util.structGet(runtimeAntenna, "ElementToPortMatrix", []);
            if isnumeric(map) && ismatrix(map) && size(map, 2) >= 1
                count = size(map, 2);
                source = "runtime_antenna.ElementToPortMatrix_columns";
                return;
            end
            sizeVec = double(sixgr.util.structGet(runtimeAntenna, "Size", []));
            if ~isempty(sizeVec)
                sizeVec = sizeVec(:).';
                sizeVec = sizeVec(isfinite(sizeVec) & sizeVec >= 1);
                if ~isempty(sizeVec)
                    if numel(sizeVec) >= 3
                        sizeVec = sizeVec(1:3);
                    end
                    count = prod(max(1, round(sizeVec)));
                    source = "runtime_antenna.Size_product";
                end
            end
        end

        function [count, source] = localRuntimeRFChainCount(runtimeAntenna, runtimeMeta)
            count = NaN;
            source = "";
            fields = ["NumRFChains", "RFChainCount"];
            objs = {runtimeMeta, runtimeAntenna};
            labels = ["runtime_meta", "runtime_antenna"];
            for c = 1:numel(objs)
                obj = objs{c};
                if ~(isstruct(obj) && ~isempty(fieldnames(obj)))
                    continue;
                end
                for f = 1:numel(fields)
                    raw = sixgr.util.structGet(obj, fields(f), NaN);
                    value = sixgr.channel.ChannelFactory.localPositiveIntegerOrNaN(raw);
                    if isfinite(value)
                        count = value;
                        source = labels(c) + "." + fields(f);
                        return;
                    end
                end
            end
        end

        function [count, source, domain] = localRuntimeWaveformColumnCount(runtimeAntenna, runtimeMeta)
            count = NaN;
            source = "";
            domain = "";
            fields = ["NumWaveformColumns", "WaveformColumnCount", "NumTxAntennas"];
            objs = {runtimeMeta, runtimeAntenna};
            labels = ["runtime_meta", "runtime_antenna"];
            for c = 1:numel(objs)
                obj = objs{c};
                if ~(isstruct(obj) && ~isempty(fieldnames(obj)))
                    continue;
                end
                for f = 1:numel(fields)
                    raw = sixgr.util.structGet(obj, fields(f), NaN);
                    value = sixgr.channel.ChannelFactory.localPositiveIntegerOrNaN(raw);
                    if isfinite(value)
                        count = value;
                        source = labels(c) + "." + fields(f);
                        break;
                    end
                end
                if isfinite(count)
                    break;
                end
            end
            for c = 1:numel(objs)
                obj = objs{c};
                if ~(isstruct(obj) && ~isempty(fieldnames(obj)))
                    continue;
                end
                rawDomain = string(sixgr.util.structGet(obj, "WaveformDomain", ""));
                if strlength(strtrim(rawDomain)) > 0
                    domain = lower(strtrim(rawDomain));
                    return;
                end
            end
            if strlength(string(domain)) == 0 && isfinite(count)
                domain = "logical_port";
            end
        end


        function count = localPositiveIntegerOrNaN(raw)
            count = NaN;
            if isempty(raw) || ~isnumeric(raw)
                return;
            end
            raw = double(raw(1));
            if isfinite(raw) && raw >= 1
                count = max(1, round(raw));
            end
        end
        function meta = localApplyChannelHandlingMeta(meta, modelToken, objectClass, objectSource)
            token = lower(strtrim(char(string(modelToken))));
            objClass = char(string(objectClass));
            objSource = char(string(objectSource));
            meta.ChannelObjectSource = string(objSource);
            meta.ChannelObjectClass = string(objClass);
            switch token
                case "tdl"
                    meta.ChannelArrayModel = "nrtdl_count_only_fading_channel";
                    meta.ChannelArrayHandlingStatus = "count_only_spatial_dims_no_runtime_geometry";
                    meta.ChannelArrayHandlingBlocker = "runtime_geometry_not_supplied_or_not_mappable_to_tdl_custom_correlation";
                    meta.ChannelUsesCountOnlyAntennaModel = true;
                    meta.ChannelUsesSameRuntimeAntennaAssumptions = false;
                    meta.ChannelGeometryCouplingLevel = "none_count_only_antenna_dimensions";
                    meta.GeometryAdapterType = "";
                    meta.GeometryAdapterSource = "";
                    meta.GeometryAdapterLimitation = "nrTDLChannel does not consume runtime antenna array objects; adapter requires runtime geometry for custom correlation matrices.";
                    meta.GeometryAdapterPortMapping = "";
                case "cdl"
                    meta.ChannelArrayModel = "nrcdl_config_array_shape_channel";
                    meta.ChannelArrayHandlingStatus = "config_array_shape_no_runtime_object_pose";
                    meta.ChannelArrayHandlingBlocker = "nrcdlchannel_uses_configured_array_shape_but_not_runtime_antenna_object_pose";
                    meta.ChannelUsesCountOnlyAntennaModel = false;
                    meta.ChannelUsesSameRuntimeAntennaAssumptions = false;
                    meta.ChannelGeometryCouplingLevel = "config_array_shape_only";
                    meta.GeometryAdapterType = "backend_native_nrCDLChannel_config_array_shape";
                    meta.GeometryAdapterSource = "config";
                    meta.GeometryAdapterLimitation = "no runtime antenna metadata supplied";
                    meta.GeometryAdapterPortMapping = "";
                case "awgn"
                    meta.ChannelArrayModel = "awgn_no_array_channel";
                    meta.ChannelArrayHandlingStatus = "no_fading_channel_object";
                    meta.ChannelArrayHandlingBlocker = "";
                    meta.ChannelUsesCountOnlyAntennaModel = true;
                    meta.ChannelUsesSameRuntimeAntennaAssumptions = false;
                    meta.ChannelGeometryCouplingLevel = "not_applicable_no_fading_channel_object";
                    meta.GeometryAdapterType = "";
                    meta.GeometryAdapterSource = "";
                    meta.GeometryAdapterLimitation = "";
                    meta.GeometryAdapterPortMapping = "";
                case "tr38901"
                    meta.ChannelArrayModel = "tr38901_large_scale_no_waveform_array_channel";
                    meta.ChannelArrayHandlingStatus = "large_scale_only_no_waveform_array_kernel";
                    meta.ChannelArrayHandlingBlocker = "large_scale_channel_not_used_as_waveform_array_fading_kernel";
                    meta.ChannelUsesCountOnlyAntennaModel = false;
                    meta.ChannelUsesSameRuntimeAntennaAssumptions = false;
                    meta.ChannelGeometryCouplingLevel = "large_scale_only_no_waveform_array_kernel";
                    meta.GeometryAdapterType = "";
                    meta.GeometryAdapterSource = "";
                    meta.GeometryAdapterLimitation = meta.ChannelArrayHandlingBlocker;
                    meta.GeometryAdapterPortMapping = "";
                case "raytracing"
                    meta.ChannelArrayModel = "raytracing_large_scale_no_waveform_array_channel";
                    meta.ChannelArrayHandlingStatus = "large_scale_only_no_waveform_array_kernel";
                    meta.ChannelArrayHandlingBlocker = "large_scale_channel_not_used_as_waveform_array_fading_kernel";
                    meta.ChannelUsesCountOnlyAntennaModel = false;
                    meta.ChannelUsesSameRuntimeAntennaAssumptions = false;
                    meta.ChannelGeometryCouplingLevel = "large_scale_only_no_waveform_array_kernel";
                    meta.GeometryAdapterType = "";
                    meta.GeometryAdapterSource = "";
                    meta.GeometryAdapterLimitation = meta.ChannelArrayHandlingBlocker;
                    meta.GeometryAdapterPortMapping = "";
                otherwise
                    meta.ChannelArrayModel = "other_channel_model";
                    meta.ChannelArrayHandlingStatus = "unknown_channel_array_handling";
                    meta.ChannelArrayHandlingBlocker = "";
                    meta.ChannelUsesCountOnlyAntennaModel = false;
                    meta.ChannelUsesSameRuntimeAntennaAssumptions = false;
                    meta.ChannelGeometryCouplingLevel = "unknown";
                    meta.GeometryAdapterType = "";
                    meta.GeometryAdapterSource = "";
                    meta.GeometryAdapterLimitation = "";
                    meta.GeometryAdapterPortMapping = "";
            end
        end

        function meta = localAttachRuntimeGeometryMeta(meta, cfg)
            if ~(isstruct(meta) && isscalar(meta))
                meta = struct();
            end
            meta.RuntimeGeometrySource = string(sixgr.util.structGet(cfg, "lls6g.userContext.RuntimeGeometrySource", ""));
            meta.RuntimeGeometryDelaySource = string(sixgr.util.structGet(cfg, "lls6g.userContext.RuntimeGeometryDelaySource", ""));
            meta.RuntimeGeometryDopplerSource = string(sixgr.util.structGet(cfg, "lls6g.userContext.RuntimeGeometryDopplerSource", ""));
            meta.RuntimeDistance2D_m = double(sixgr.util.structGet(cfg, "channel.distance2D_m", NaN));
            meta.RuntimeDistance3D_m = double(sixgr.util.structGet(cfg, "channel.distance3D_m", NaN));
            meta.RuntimePropagationDelay_s = double(sixgr.util.structGet(cfg, "channel.propagationDelay_s", NaN));
            meta.RuntimeDoppler_Hz = double(sixgr.util.structGet(cfg, "channel.doppler_Hz", NaN));
            meta.RuntimeSignedDoppler_Hz = double(sixgr.util.structGet(cfg, "channel.runtimeSignedDoppler_Hz", NaN));
            meta.RuntimeLOSProbability = double(sixgr.util.structGet(cfg, "channel.losProbability", NaN));
            meta.RuntimeLOS = logical(sixgr.util.structGet(cfg, "channel.runtimeLOS", false));
            meta.RuntimePathloss_dB = double(sixgr.util.structGet(cfg, "lls6g.userContext.RuntimeServingPathloss_dB", NaN));
            meta.RuntimeShadowFading_dB = double(sixgr.util.structGet(cfg, "lls6g.userContext.RuntimeServingShadowFading_dB", NaN));
            meta.RuntimeO2I_dB = double(sixgr.util.structGet(cfg, "lls6g.userContext.RuntimeServingO2I_dB", NaN));
        end
        function [tdl, arrayRuntimeMeta] = localCreateTDL(cfg, opt)
            delayProfile = sixgr.channel.ChannelFactory.localResolveConcreteDelayProfile(cfg, "TDL");
            if exist("nrTDLChannel","class") ~= 8
                error("ChannelFactory:TDL:Missing5G", "nrTDLChannel not found. Install/enable 5G Toolbox.");
            end

            arrayRuntimeMeta = sixgr.channel.ChannelFactory.localEmptyTDLGeometryAdapterMeta();
            tdl = nrTDLChannel;

            % R2026a exposes path gains through ChannelResponseOutput;
            % older 5G Toolbox releases use PathGainsOutputPort.  Keep the
            % executed response available to the evidence path without ever
            % feeding it into a receiver or relabelling it as estimated CSI.
            if isprop(tdl, "ChannelResponseOutput")
                tdl.ChannelResponseOutput = "path-gains";
            elseif isprop(tdl, "PathGainsOutputPort")
                tdl.PathGainsOutputPort = true;
            end

            % Basic profile parameters
            tdl.DelayProfile = delayProfile;
            tdl.DelaySpread = sixgr.util.structGet(cfg, "channel.delaySpread_s", 300e-9);
            tdl.MaximumDopplerShift = sixgr.util.structGet(cfg, "channel.doppler_Hz", 30);
            tdl.NumTransmitAntennas = opt.NumTxAnt;
            tdl.NumReceiveAntennas  = opt.NumRxAnt;
            [normalizePathGains, normalizationMode, normalizationSource] = ...
                sixgr.channel.ChannelFactory.localResolveNormalizePathGains(cfg, "TDL");
            if isprop(tdl, "NormalizePathGains")
                tdl.NormalizePathGains = normalizePathGains;
            end
            [normalizeOutputs, outputNormalizationMode, outputNormalizationSource] = ...
                sixgr.channel.ChannelFactory.localResolveNormalizeChannelOutputs(cfg, "TDL");
            if isprop(tdl, "NormalizeChannelOutputs")
                tdl.NormalizeChannelOutputs = normalizeOutputs;
            end
            arrayRuntimeMeta.NormalizePathGains = normalizePathGains;
            arrayRuntimeMeta.ChannelNormalizationMode = normalizationMode;
            arrayRuntimeMeta.ChannelNormalizationSource = normalizationSource;
            arrayRuntimeMeta.NormalizeChannelOutputs = normalizeOutputs;
            arrayRuntimeMeta.ChannelOutputNormalizationMode = outputNormalizationMode;
            arrayRuntimeMeta.ChannelOutputNormalizationSource = outputNormalizationSource;

            if ~isempty(opt.SampleRate)
                tdl.SampleRate = opt.SampleRate;
            end
            % nrTDLChannel already returns per-input-sample path gains and
            % has no CDL-style SampleDensity property to override.

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

            [tdl, arrayRuntimeMeta] = sixgr.channel.ChannelFactory.localConfigureTDLGeometryAdapter(tdl, cfg, opt, arrayRuntimeMeta);
        end

        function meta = localEmptyTDLGeometryAdapterMeta()
            meta = struct( ...
                "RuntimeGeometryCorrelationApplied", false, ...
                "GeometryAdapterType", "", ...
                "GeometryAdapterSource", "", ...
                "GeometryAdapterLimitation", "", ...
                "GeometryAdapterPortMapping", "", ...
                "TransmitCorrelationMatrixSource", "", ...
                "ReceiveCorrelationMatrixSource", "", ...
                "TransmitCorrelationMatrixSize", "", ...
                "ReceiveCorrelationMatrixSize", "", ...
                "GeometryCorrelationDistance_lambda", NaN, ...
                "NormalizePathGains", false, ...
                "ChannelNormalizationMode", "", ...
                "ChannelNormalizationSource", "", ...
                "NormalizeChannelOutputs", false, ...
                "ChannelOutputNormalizationMode", "", ...
                "ChannelOutputNormalizationSource", "");
        end

        function [tdl, meta] = localConfigureTDLGeometryAdapter(tdl, cfg, opt, meta)
            if ~(isobject(tdl) && isprop(tdl, "MIMOCorrelation") && ...
                    isprop(tdl, "TransmitCorrelationMatrix") && isprop(tdl, "ReceiveCorrelationMatrix"))
                return;
            end

            numTx = max(1, round(double(opt.NumTxAnt)));
            numRx = max(1, round(double(opt.NumRxAnt)));
            if numTx <= 1 && numRx <= 1
                return;
            end

            corrDistance = double(sixgr.util.structGet(cfg, ...
                "channel.tdlGeometryCorrelationDistance_lambda", ...
                sixgr.util.structGet(cfg, "channel.geometryCorrelationDistance_lambda", 0.7)));
            if ~(isfinite(corrDistance) && corrDistance > 0)
                corrDistance = 0.7;
            end

            [txCorr, txSource, txMapping, txValid] = sixgr.channel.ChannelFactory.localRuntimeTDLCorrelationMatrix( ...
                opt.TransmitAntennaRuntime, opt.TransmitAntennaMeta, numTx, corrDistance, "tx");
            [rxCorr, rxSource, rxMapping, rxValid] = sixgr.channel.ChannelFactory.localRuntimeTDLCorrelationMatrix( ...
                opt.ReceiveAntennaRuntime, opt.ReceiveAntennaMeta, numRx, corrDistance, "rx");
            if ~(txValid || rxValid)
                return;
            end
            if ~txValid
                txCorr = eye(numTx);
                txSource = "identity_no_runtime_tx_geometry";
                txMapping = "identity_tx_side_not_geometry_backed";
            end
            if ~rxValid
                rxCorr = eye(numRx);
                rxSource = "identity_no_runtime_rx_geometry";
                rxMapping = "identity_rx_side_not_geometry_backed";
            end

            try
                tdl.MIMOCorrelation = "Custom";
                tdl.TransmitCorrelationMatrix = txCorr;
                tdl.ReceiveCorrelationMatrix = rxCorr;
            catch ME
                error("ChannelFactory:TDL:GeometryAdapterFailed", ...
                    "Runtime TDL geometry adapter could not apply custom correlation matrices to nrTDLChannel: %s", ME.message);
            end

            meta.RuntimeGeometryCorrelationApplied = true;
            meta.GeometryAdapterType = "tdl_custom_tx_rx_correlation_from_runtime_element_positions";
            meta.GeometryAdapterSource = "ChannelFactory.localConfigureTDLGeometryAdapter";
            meta.GeometryAdapterLimitation = "nrTDLChannel consumes reduced custom correlation matrices; it does not consume runtime array object pose or element pattern or polarization angles or per-path angles.";
            meta.GeometryAdapterPortMapping = string(txMapping) + ";" + string(rxMapping);
            meta.TransmitCorrelationMatrixSource = string(txSource);
            meta.ReceiveCorrelationMatrixSource = string(rxSource);
            meta.TransmitCorrelationMatrixSize = sprintf("%dx%d", size(txCorr, 1), size(txCorr, 2));
            meta.ReceiveCorrelationMatrixSize = sprintf("%dx%d", size(rxCorr, 1), size(rxCorr, 2));
            meta.GeometryCorrelationDistance_lambda = corrDistance;
        end

        function [corr, source, mapping, valid] = localRuntimeTDLCorrelationMatrix(runtimeAntenna, runtimeMeta, numAnt, corrDistance, role)
            corr = [];
            source = "";
            mapping = "";
            valid = false;
            [positionsLambda, posSource, posMapping, posValid] = sixgr.channel.ChannelFactory.localRuntimeTDLPositionsLambda( ...
                runtimeAntenna, runtimeMeta, numAnt, role);
            if ~posValid
                return;
            end
            corr = sixgr.channel.ChannelFactory.localSpatialCorrelationFromPositions(positionsLambda, corrDistance);
            if isempty(corr) || any(size(corr) ~= [numAnt numAnt])
                corr = [];
                return;
            end
            source = posSource;
            mapping = posMapping;
            valid = true;
        end

        function [positionsLambda, source, mapping, valid] = localRuntimeTDLPositionsLambda(runtimeAntenna, runtimeMeta, numAnt, role)
            positionsLambda = [];
            source = "";
            mapping = "";
            valid = false;
            numAnt = max(1, round(double(numAnt)));
            if ~(isstruct(runtimeMeta) && ~isempty(fieldnames(runtimeMeta)))
                runtimeMeta = struct();
            end
            if ~(isstruct(runtimeAntenna) && ~isempty(fieldnames(runtimeAntenna)))
                runtimeAntenna = struct();
            end

            pos = double(sixgr.util.structGet(runtimeAntenna, "ElementPositions_m", []));
            lambda = double(sixgr.util.structGet(runtimeAntenna, "Lambda_m", NaN));
            portToElement = double(sixgr.util.structGet(runtimeAntenna, "PortToElementMatrix", []));
            if ismatrix(pos) && size(pos, 2) >= 3 && ismatrix(portToElement) && ...
                    size(portToElement, 2) == numAnt && size(pos, 1) >= size(portToElement, 1) && ...
                    isfinite(lambda) && lambda > 0
                weights = abs(portToElement);
                colSum = sum(weights, 1);
                if all(isfinite(colSum)) && all(colSum > 0)
                    weights = weights ./ colSum;
                    positionsLambda = (weights.' * pos(1:size(weights, 1), 1:3)) ./ lambda;
                    source = string(role) + "_runtime_port_centroids_from_element_port_mapping";
                    mapping = string(role) + "_logical_ports_projected_from_runtime_element_positions";
                    valid = all(isfinite(positionsLambda(:)));
                    return;
                end
            end
            if ismatrix(pos) && size(pos, 2) >= 3 && size(pos, 1) >= numAnt && isfinite(lambda) && lambda > 0
                positionsLambda = pos(1:numAnt, 1:3) ./ lambda;
                source = string(role) + "_runtime_element_positions_m";
                if size(pos, 1) == numAnt
                    mapping = string(role) + "_runtime_positions_match_waveform_ports";
                else
                    mapping = string(role) + "_runtime_positions_reduced_to_waveform_ports";
                end
                valid = all(isfinite(positionsLambda(:)));
                return;
            end

            nRow = double(sixgr.util.structGet(runtimeMeta, "NumRows", NaN));
            nCol = double(sixgr.util.structGet(runtimeMeta, "NumCols", NaN));
            nPol = double(sixgr.util.structGet(runtimeMeta, "NumPolarizations", NaN));
            spacingH = double(sixgr.util.structGet(runtimeMeta, "SpacingH_lambda", NaN));
            spacingV = double(sixgr.util.structGet(runtimeMeta, "SpacingV_lambda", NaN));
            if ~(isfinite(nRow) && isfinite(nCol))
                sizeVec = double(sixgr.util.structGet(runtimeAntenna, "Size", [NaN NaN]));
                if numel(sizeVec) >= 2
                    nRow = double(sizeVec(1));
                    nCol = double(sizeVec(2));
                end
            end
            if ~(isfinite(nPol) && nPol >= 1)
                nPol = double(sixgr.util.structGet(runtimeAntenna, "NPol", 1));
            end
            if ~(isfinite(spacingH) && isfinite(spacingV) && spacingH > 0 && spacingV > 0)
                spacing = double(sixgr.util.structGet(runtimeAntenna, "ElementSpacing_m", [NaN NaN]));
                lambda = double(sixgr.util.structGet(runtimeAntenna, "Lambda_m", NaN));
                if isfinite(lambda) && lambda > 0 && numel(spacing) >= 2
                    spacingH = spacing(1) ./ lambda;
                    spacingV = spacing(2) ./ lambda;
                end
            end
            if ~(isfinite(nRow) && nRow >= 1 && isfinite(nCol) && nCol >= 1 && ...
                    isfinite(nPol) && nPol >= 1 && isfinite(spacingH) && spacingH > 0 && ...
                    isfinite(spacingV) && spacingV > 0)
                return;
            end

            allPositions = sixgr.channel.ChannelFactory.localGridPositionsLambda( ...
                max(1, round(nRow)), max(1, round(nCol)), max(1, round(nPol)), spacingH, spacingV);
            if size(allPositions, 1) < numAnt
                return;
            end
            positionsLambda = allPositions(1:numAnt, :);
            source = string(role) + "_runtime_metadata_shape_spacing_lambda";
            if size(allPositions, 1) == numAnt
                mapping = string(role) + "_runtime_metadata_ports_match_waveform_ports";
            else
                mapping = string(role) + "_runtime_metadata_ports_reduced_to_waveform_ports";
            end
            valid = all(isfinite(positionsLambda(:)));
        end

        function positions = localGridPositionsLambda(nRow, nCol, nPol, spacingH, spacingV)
            y = ((0:nRow-1) - (nRow-1)/2) .* double(spacingH);
            z = ((0:nCol-1) - (nCol-1)/2) .* double(spacingV);
            [Y, Z] = ndgrid(y, z);
            base = [zeros(numel(Y), 1), Y(:), Z(:)];
            if nPol > 1
                positions = repmat(base, max(1, round(double(nPol))), 1);
            else
                positions = base;
            end
        end

        function corr = localSpatialCorrelationFromPositions(positionsLambda, corrDistance)
            positionsLambda = double(positionsLambda);
            n = size(positionsLambda, 1);
            corr = eye(n);
            for ii = 1:n
                for jj = (ii+1):n
                    d = norm(positionsLambda(ii, :) - positionsLambda(jj, :));
                    rho = exp(-d ./ double(corrDistance));
                    corr(ii, jj) = rho;
                    corr(jj, ii) = rho;
                end
            end
            corr = (corr + corr') ./ 2;
            corr = corr + eye(n) .* 1e-10;
            d = sqrt(max(real(diag(corr)), eps));
            corr = corr ./ (d * d.');
            corr = (corr + corr') ./ 2;
        end

        function [cdl, arrayRuntimeMeta] = localCreateCDL(cfg, opt)
            delayProfile = sixgr.channel.ChannelFactory.localResolveConcreteDelayProfile(cfg, "CDL");
            if exist("nrCDLChannel","class") ~= 8
                error("ChannelFactory:CDL:Missing5G", "nrCDLChannel not found. Install/enable 5G Toolbox.");
            end

            arrayRuntimeMeta = struct( ...
                "RuntimeArrayGeometryCoupled", false, ...
                "RuntimeArrayGeometrySource", "", ...
                "TransmitArrayOrientation_deg", [NaN; NaN; NaN], ...
                "ReceiveArrayOrientation_deg", [NaN; NaN; NaN], ...
                "TransmitAntennaArraySize", "", ...
                "ReceiveAntennaArraySize", "", ...
                "TransmitAntennaElementSpacing_lambda", "", ...
                "ReceiveAntennaElementSpacing_lambda", "", ...
                "LOSProbabilitySource", "", ...
                "LOSComplianceStatus", "", ...
                "LOSComplianceReason", "", ...
                "CDLDelayProfileBeforeLOSGating", string(delayProfile), ...
                "CDLDelayProfileAfterLOSGating", string(delayProfile), ...
                "CDLLOSDraw", NaN, ...
                "ChannelArrayHandlingStatus", "runtime_array_shape_spacing_orientation_coupled", ...
                "ChannelGeometryCouplingLevel", "runtime_array_shape_spacing_orientation", ...
                "GeometryAdapterType", "backend_native_nrCDLChannel_antenna_array", ...
                "GeometryAdapterLimitation", "", ...
                "GeometryAdapterPortMapping", "runtime_array_shape_matches_channel_ports", ...
                "ChannelUsesSameRuntimeAntennaAssumptions", true);
            [delayProfile, losMeta] = sixgr.channel.ChannelFactory.localApplyCDLLOSProbabilityGating(delayProfile, cfg, opt);
            losFields = fieldnames(losMeta);
            for losIdx = 1:numel(losFields)
                arrayRuntimeMeta.(losFields{losIdx}) = losMeta.(losFields{losIdx});
            end
            cdl = nrCDLChannel;
            if isprop(cdl, "ChannelResponseOutput")
                cdl.ChannelResponseOutput = "path-gains";
            elseif isprop(cdl, "PathGainsOutputPort")
                cdl.PathGainsOutputPort = true;
            end
            cdl.DelayProfile = delayProfile;
            cdl.DelaySpread = sixgr.util.structGet(cfg, "channel.delaySpread_s", 300e-9);
            cdl.MaximumDopplerShift = sixgr.util.structGet(cfg, "channel.doppler_Hz", 30);
            [normalizePathGains, normalizationMode, normalizationSource] = ...
                sixgr.channel.ChannelFactory.localResolveNormalizePathGains(cfg, "CDL");
            if isprop(cdl, "NormalizePathGains")
                cdl.NormalizePathGains = normalizePathGains;
            end
            [normalizeOutputs, outputNormalizationMode, outputNormalizationSource] = ...
                sixgr.channel.ChannelFactory.localResolveNormalizeChannelOutputs(cfg, "CDL");
            if isprop(cdl, "NormalizeChannelOutputs")
                cdl.NormalizeChannelOutputs = normalizeOutputs;
            end
            arrayRuntimeMeta.NormalizePathGains = normalizePathGains;
            arrayRuntimeMeta.ChannelNormalizationMode = normalizationMode;
            arrayRuntimeMeta.ChannelNormalizationSource = normalizationSource;
            arrayRuntimeMeta.NormalizeChannelOutputs = normalizeOutputs;
            arrayRuntimeMeta.ChannelOutputNormalizationMode = outputNormalizationMode;
            arrayRuntimeMeta.ChannelOutputNormalizationSource = outputNormalizationSource;
            [cdl.TransmitAntennaArray, txRuntimeCoupled, txArrayAdapterMeta] = sixgr.channel.ChannelFactory.localConfigureCDLAntennaArray( ...
                cdl.TransmitAntennaArray, opt.NumTxAnt, ...
                sixgr.util.structGet(cfg, "antenna_and_array.bs_array_geometry", "ura"), ...
                sixgr.util.structGet(cfg, "antenna_and_array.polarization", ""), ...
                opt.TransmitAntennaRuntime, opt.TransmitAntennaMeta);
            [cdl.ReceiveAntennaArray, rxRuntimeCoupled, rxArrayAdapterMeta] = sixgr.channel.ChannelFactory.localConfigureCDLAntennaArray( ...
                cdl.ReceiveAntennaArray, opt.NumRxAnt, ...
                sixgr.util.structGet(cfg, "antenna_and_array.ue_array_geometry", "ula"), ...
                sixgr.util.structGet(cfg, "antenna_and_array.polarization", ""), ...
                opt.ReceiveAntennaRuntime, opt.ReceiveAntennaMeta);
            arrayRuntimeMeta.TransmitElementPatternApplied = logical( ...
                sixgr.util.structGet(txArrayAdapterMeta, "ElementPatternApplied", false));
            arrayRuntimeMeta.ReceiveElementPatternApplied = logical( ...
                sixgr.util.structGet(rxArrayAdapterMeta, "ElementPatternApplied", false));
            arrayRuntimeMeta.TransmitElementPatternSource = string( ...
                sixgr.util.structGet(txArrayAdapterMeta, "ElementPatternSource", ""));
            arrayRuntimeMeta.ReceiveElementPatternSource = string( ...
                sixgr.util.structGet(rxArrayAdapterMeta, "ElementPatternSource", ""));
            [txSize, txSpacing, txElementClass] = ...
                sixgr.channel.ChannelFactory.localCDLArrayEvidence(cdl.TransmitAntennaArray, opt.Fc_Hz);
            [rxSize, rxSpacing, rxElementClass] = ...
                sixgr.channel.ChannelFactory.localCDLArrayEvidence(cdl.ReceiveAntennaArray, opt.Fc_Hz);
            arrayRuntimeMeta.TransmitAntennaArraySize = mat2str(txSize);
            arrayRuntimeMeta.ReceiveAntennaArraySize = mat2str(rxSize);
            arrayRuntimeMeta.TransmitAntennaElementSpacing_lambda = mat2str(txSpacing);
            arrayRuntimeMeta.ReceiveAntennaElementSpacing_lambda = mat2str(rxSpacing);
            arrayRuntimeMeta.TransmitAntennaElementClass = txElementClass;
            arrayRuntimeMeta.ReceiveAntennaElementClass = rxElementClass;
            if ~(txRuntimeCoupled && rxRuntimeCoupled)
                arrayRuntimeMeta.RuntimeArrayGeometryCoupled = false;
                arrayRuntimeMeta.RuntimeArrayGeometrySource = "ChannelFactory.configured_antenna_array_shape_to_nrCDLChannel";
                arrayRuntimeMeta.TransmitArrayOrientation_deg = [NaN; NaN; NaN];
                arrayRuntimeMeta.ReceiveArrayOrientation_deg = [NaN; NaN; NaN];
            end
            if txRuntimeCoupled && rxRuntimeCoupled
                txOrientation = sixgr.channel.ChannelFactory.localResolveRuntimeAntennaOrientation( ...
                    opt.TransmitAntennaMeta, "Azimuth_deg");
                rxOrientation = sixgr.channel.ChannelFactory.localResolveRuntimeAntennaOrientation( ...
                    opt.ReceiveAntennaMeta, "Heading_deg");
                cdl = sixgr.channel.ChannelFactory.localSetCDLArrayOrientation(cdl, "Transmit", txOrientation);
                cdl = sixgr.channel.ChannelFactory.localSetCDLArrayOrientation(cdl, "Receive", rxOrientation);
                arrayRuntimeMeta.RuntimeArrayGeometryCoupled = true;
                arrayRuntimeMeta.RuntimeArrayGeometrySource = "CoupledTruthRuntime.runtime_antenna_metadata_to_nrCDLChannel";
                arrayRuntimeMeta.TransmitArrayOrientation_deg = txOrientation;
                arrayRuntimeMeta.ReceiveArrayOrientation_deg = rxOrientation;
                projectionApplied = logical(sixgr.util.structGet(txArrayAdapterMeta, "LogicalPortProjectionApplied", false)) || ...
                    logical(sixgr.util.structGet(rxArrayAdapterMeta, "LogicalPortProjectionApplied", false));
                arrayRuntimeMeta.GeometryAdapterPortMapping = string(sixgr.util.structGet(txArrayAdapterMeta, "PortMapping", "")) + ";" + ...
                    string(sixgr.util.structGet(rxArrayAdapterMeta, "PortMapping", ""));
                if projectionApplied
                    arrayRuntimeMeta.ChannelArrayHandlingStatus = "runtime_array_logical_port_projection_coupled";
                    arrayRuntimeMeta.ChannelGeometryCouplingLevel = "runtime_logical_port_projection_from_element_geometry";
                    arrayRuntimeMeta.GeometryAdapterType = "port_domain_channel_array_from_element_to_port_mapping";
                    arrayRuntimeMeta.GeometryAdapterLimitation = "nrCDLChannel consumes waveform columns as channel ports; physical element geometry is projected to logical ports before channel filtering.";
                    arrayRuntimeMeta.ChannelUsesSameRuntimeAntennaAssumptions = false;
                end
            end

            if ~isempty(opt.SampleRate)
                cdl.SampleRate = opt.SampleRate;
            end
            if logical(sixgr.util.structGet(cfg, "channel.perSampleFadingEnabled", false))
                cdl.SampleDensity = Inf;
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

        function [profile, meta] = localApplyCDLLOSProbabilityGating(profile, cfg, opt)
            profile = char(string(profile));
            meta = struct( ...
                "LOSProbabilitySource", "not_evaluated_distance_unavailable", ...
                "LOSComplianceStatus", "not_evaluated", ...
                "LOSComplianceReason", "", ...
                "CDLDelayProfileBeforeLOSGating", string(profile), ...
                "CDLDelayProfileAfterLOSGating", string(profile), ...
                "CDLLOSDraw", NaN);
            runtimeLOS = sixgr.util.structGet(cfg, "channel.runtimeLOS", []);
            if ~isempty(runtimeLOS)
                isLOS = logical(runtimeLOS);
                if ~isLOS && any(upper(string(profile)) == ["CDL-D", "CDL-E"])
                    profile = "CDL-C";
                end
                meta.LOSProbabilitySource = "runtime_geometry_los_state";
                meta.LOSComplianceStatus = "runtime_geometry_state_reused";
                meta.LOSComplianceReason = "";
                meta.CDLDelayProfileAfterLOSGating = string(profile);
                meta.CDLLOSDraw = double(isLOS);
                return;
            end
            pLOS = double(sixgr.util.structGet(cfg, "channel.losProbability", NaN));
            status = struct("Source", "configured_channel_los_probability", ...
                "ComplianceStatus", "configured_probability", "Reason", "", "StrictSupported", true);
            if ~isfinite(pLOS)
                d2d_m = double(sixgr.util.structGet(cfg, "channel.propagationDistance2D_m", ...
                    sixgr.util.structGet(cfg, "channel.distance2D_m", ...
                    sixgr.util.structGet(cfg, "channel.distance_m", NaN))));
                if ~isfinite(d2d_m)
                    d3d_m = double(sixgr.util.structGet(cfg, "channel.propagationDistance_m", NaN));
                    hBS_m = double(sixgr.util.structGet(cfg, "scenario.bs.height_m", ...
                        sixgr.util.structGet(cfg, "deployment_topology.bs_height_m", 25)));
                    hUE_m = double(sixgr.util.structGet(cfg, "ue.heightAboveGround_m", ...
                        sixgr.util.structGet(cfg, "scenario.ue.height_m", 1.5)));
                    if isfinite(d3d_m) && isfinite(hBS_m) && isfinite(hUE_m)
                        d2d_m = sqrt(max(double(d3d_m).^2 - (double(hBS_m) - double(hUE_m)).^2, 0));
                    end
                end
                if isfinite(d2d_m) && d2d_m > 0
                    scenarioName = string(sixgr.util.structGet(cfg, "channel.scenario", ""));
                    if strlength(strtrim(scenarioName)) == 0
                        scenarioName = string(sixgr.util.structGet(cfg, "channels.pathloss_scenario", ""));
                    end
                    if strlength(strtrim(scenarioName)) == 0
                        scenarioName = string(sixgr.util.structGet(cfg, "deployment_topology.cell_type", ""));
                    end
                    if strlength(strtrim(scenarioName)) == 0
                        scenarioName = "UMa";
                    end
                    hUE_m = double(sixgr.util.structGet(cfg, "ue.heightAboveGround_m", ...
                        sixgr.util.structGet(cfg, "scenario.ue.height_m", 1.5)));
                    [pLOS, status] = sixgr.channel.LOSProbability(scenarioName, d2d_m, "HUT_m", hUE_m);
                    pLOS = double(pLOS(1));
                end
            end
            if ~isfinite(pLOS)
                return;
            end
            pLOS = max(0, min(1, double(pLOS)));
            seed = double(sixgr.util.structGet(cfg, "channel.losSeed", ...
                sixgr.util.structGet(cfg, "run.seed", sixgr.util.structGet(cfg, "channel.seed", 1))));
            if ~(isfinite(seed) && isscalar(seed))
                seed = 1;
            end
            stream = RandStream("mt19937ar", "Seed", max(0, mod(round(seed), 2^32 - 1)));
            draw = rand(stream);
            isLOS = draw < pLOS;
            if ~isLOS && any(upper(string(profile)) == ["CDL-D", "CDL-E"])
                profile = "CDL-C";
            end
            meta.LOSProbabilitySource = string(sixgr.util.structGet(status, "Source", "tr38901_los_probability"));
            meta.LOSComplianceStatus = string(sixgr.util.structGet(status, "ComplianceStatus", "evaluated"));
            meta.LOSComplianceReason = sprintf("losProbability=%.6f losDraw=%.6f isLOS=%d", pLOS, draw, isLOS);
            extraReason = string(sixgr.util.structGet(status, "Reason", ""));
            if strlength(strtrim(extraReason)) > 0
                meta.LOSComplianceReason = meta.LOSComplianceReason + "; " + extraReason;
            end
            meta.CDLDelayProfileAfterLOSGating = string(profile);
            meta.CDLLOSDraw = double(draw);
        end

        function [arr, usedRuntimeGeometry, adapterMeta] = localConfigureCDLAntennaArray(arr, numAnt, geometry, polarization, runtimeAntenna, runtimeMeta)
            if nargin < 5
                runtimeAntenna = struct();
            end
            if nargin < 6
                runtimeMeta = struct();
            end
            adapterMeta = struct("LogicalPortProjectionApplied", false, ...
                "PortMapping", "runtime_array_shape_matches_channel_ports", ...
                "ElementPatternApplied", false, ...
                "ElementPatternSource", "");
            requiredPattern = logical(sixgr.util.structGet(runtimeAntenna, ...
                "RequireElementPatternInChannel", false));
            runtimeArrayObject = sixgr.util.structGet(runtimeAntenna, "ArrayObj", []);
            if ~isempty(runtimeArrayObject)
                try
                    runtimeElementCount = double(getNumElements(runtimeArrayObject));
                catch ME
                    if requiredPattern
                        error("ChannelFactory:RequiredAntennaPatternInspectionFailed", ...
                            "Required runtime phased-array element count cannot be inspected: %s", ME.message);
                    end
                    runtimeElementCount = NaN;
                end
                if isfinite(runtimeElementCount) && runtimeElementCount == round(double(numAnt))
                    arr = runtimeArrayObject;
                    usedRuntimeGeometry = true;
                    adapterMeta.ElementPatternApplied = true;
                    adapterMeta.ElementPatternSource = "AntennaArrayFactory.phased.NRRectangularPanelArray";
                    adapterMeta.PortMapping = "runtime_phased_array_elements_match_channel_ports";
                    return;
                end
                if requiredPattern
                    error("ChannelFactory:RequiredAntennaPatternPortMismatch", ...
                        "Required runtime phased array has %g elements but the CDL endpoint consumes %g physical ports.", ...
                        runtimeElementCount, double(numAnt));
                end
            elseif requiredPattern
                error("ChannelFactory:RequiredAntennaPatternObjectMissing", ...
                    "The scenario requires an element pattern in the channel, but no phased array object reached ChannelFactory.");
            end
            [runtimeSpec, usedRuntimeGeometry] = sixgr.channel.ChannelFactory.localResolveRuntimeCDLArraySpec(runtimeAntenna, runtimeMeta, numAnt);
            if usedRuntimeGeometry
                arr.Size = runtimeSpec.Size;
                arr.ElementSpacing = runtimeSpec.ElementSpacing;
                arr.PolarizationAngles = sixgr.channel.ChannelFactory.localResolveCDLPolarizationAngles( ...
                    arr.PolarizationAngles, runtimeSpec.PolarizationCount);
                adapterMeta = runtimeSpec.AdapterMeta;
                adapterMeta.ElementPatternApplied = false;
                adapterMeta.ElementPatternSource = "nrCDLChannel_struct_element_pattern";
                return;
            end
            numAnt = max(1, round(double(numAnt)));
            polCount = sixgr.channel.ChannelFactory.localResolveCDLPolarizationCount(numAnt, polarization);
            spatialCount = max(1, round(numAnt / polCount));
            arr.Size = sixgr.channel.ChannelFactory.localResolveCDLArraySize(spatialCount, polCount, geometry);
            arr.ElementSpacing = sixgr.channel.ChannelFactory.localNonoverlappingCDLSpacing( ...
                double(arr.Size), 0.5, 0.5);
            arr.PolarizationAngles = sixgr.channel.ChannelFactory.localResolveCDLPolarizationAngles( ...
                arr.PolarizationAngles, polCount);
        end

        function [sizeVec, spacingLambda, elementClass] = localCDLArrayEvidence(arr, fcHz)
            sizeVec = NaN;
            spacingLambda = NaN;
            elementClass = "";
            if isstruct(arr)
                sizeVec = double(sixgr.util.structGet(arr, "Size", NaN));
                spacingLambda = double(sixgr.util.structGet(arr, "ElementSpacing", NaN));
                elementClass = string(sixgr.util.structGet(arr, "Element", ""));
                return;
            end
            elementClass = string(class(arr));
            try
                sizeVec = double(arr.Size);
            catch
                try
                    sizeVec = [double(getNumElements(arr)) 1 1 1 1];
                catch
                    sizeVec = NaN;
                end
            end
            try
                lambda = physconst("LightSpeed") ./ double(fcHz);
                spacingLambda = double(arr.Spacing) ./ lambda;
            catch
                spacingLambda = NaN;
            end
            try
                elementSet = arr.ElementSet;
                if iscell(elementSet) && ~isempty(elementSet)
                    elementClass = string(class(elementSet{1}));
                end
            catch
            end
        end

        function [spec, valid] = localResolveRuntimeCDLArraySpec(runtimeAntenna, runtimeMeta, numAnt)
            spec = struct("Size", [NaN NaN NaN 1 1], "ElementSpacing", [NaN NaN 1 1], "PolarizationCount", NaN, ...
                "AdapterMeta", struct("LogicalPortProjectionApplied", false, "PortMapping", "runtime_array_shape_matches_channel_ports"));
            numAnt = max(1, round(double(numAnt)));
            valid = false;
            if ~(isstruct(runtimeMeta) && ~isempty(fieldnames(runtimeMeta)))
                runtimeMeta = struct();
            end
            if ~(isstruct(runtimeAntenna) && ~isempty(fieldnames(runtimeAntenna)))
                runtimeAntenna = struct();
            end
            nRow = double(sixgr.util.structGet(runtimeMeta, "NumRows", NaN));
            nCol = double(sixgr.util.structGet(runtimeMeta, "NumCols", NaN));
            nPol = double(sixgr.util.structGet(runtimeMeta, "NumPolarizations", NaN));
            if ~isfinite(nPol)
                nPol = double(sixgr.util.structGet(runtimeAntenna, "NPol", NaN));
            end
            panelRows = double(sixgr.util.structGet(runtimeMeta, "PanelRows", ...
                sixgr.util.structGet(runtimeAntenna, "PanelRows", NaN)));
            panelCols = double(sixgr.util.structGet(runtimeMeta, "PanelCols", ...
                sixgr.util.structGet(runtimeAntenna, "PanelCols", NaN)));
            if ~(isfinite(nRow) && isfinite(nCol))
                sizeVec = double(sixgr.util.structGet(runtimeAntenna, "ArraySize5D", ...
                    sixgr.util.structGet(runtimeAntenna, "Size", [NaN NaN])));
                if numel(sizeVec) >= 2
                    nRow = double(sizeVec(1));
                    nCol = double(sizeVec(2));
                end
                if numel(sizeVec) >= 4 && ~isfinite(panelRows)
                    panelRows = double(sizeVec(4));
                end
                if numel(sizeVec) >= 5 && ~isfinite(panelCols)
                    panelCols = double(sizeVec(5));
                end
            end
            if ~(isfinite(nRow) && nRow >= 1 && isfinite(nCol) && nCol >= 1)
                return;
            end
            if ~(isfinite(nPol) && nPol >= 1)
                nPol = 1;
            end
            if ~(isfinite(panelRows) && panelRows >= 1)
                panelRows = 1;
            end
            if ~(isfinite(panelCols) && panelCols >= 1)
                panelCols = 1;
            end
            nRow = max(1, round(nRow));
            nCol = max(1, round(nCol));
            nPol = max(1, round(nPol));
            panelRows = max(1, round(panelRows));
            panelCols = max(1, round(panelCols));
            spacingH = double(sixgr.util.structGet(runtimeMeta, "SpacingH_lambda", NaN));
            spacingV = double(sixgr.util.structGet(runtimeMeta, "SpacingV_lambda", NaN));
            if ~(isfinite(spacingH) && isfinite(spacingV) && spacingH > 0 && spacingV > 0)
                spacing = double(sixgr.util.structGet(runtimeAntenna, "ElementSpacing_m", [NaN NaN]));
                lambda = double(sixgr.util.structGet(runtimeAntenna, "Lambda_m", NaN));
                if isfinite(lambda) && lambda > 0 && numel(spacing) >= 2
                    spacingH = spacing(1) ./ lambda;
                    spacingV = spacing(2) ./ lambda;
                end
            end
            if ~(isfinite(spacingH) && isfinite(spacingV) && spacingH > 0 && spacingV > 0)
                spacingH = 0.5;
                spacingV = 0.5;
            end
            [logicalPorts, portSource] = sixgr.channel.ChannelFactory.localRuntimeLogicalPortCount(runtimeAntenna, runtimeMeta);
            [numElements, ~] = sixgr.channel.ChannelFactory.localRuntimeElementCount(runtimeAntenna, runtimeMeta);
            physicalArrayCount = nRow * nCol * nPol * panelRows * panelCols;
            if isfinite(logicalPorts) && round(double(logicalPorts)) == numAnt && physicalArrayCount ~= numAnt
                spec.Size = [numAnt 1 1 1 1];
                spec.ElementSpacing = sixgr.channel.ChannelFactory.localNonoverlappingCDLSpacing( ...
                    spec.Size, spacingV, spacingH);
                spec.PolarizationCount = 1;
                spec.AdapterMeta = struct("LogicalPortProjectionApplied", true, ...
                    "PortMapping", sprintf("logical_%d_ports_projected_from_%d_runtime_elements_via_%s", ...
                    numAnt, round(double(numElements)), char(string(portSource))));
                valid = true;
                return;
            end
            spec.Size = [nRow nCol nPol panelRows panelCols];
            spec.ElementSpacing = sixgr.channel.ChannelFactory.localNonoverlappingCDLSpacing( ...
                spec.Size, spacingV, spacingH);
            spec.PolarizationCount = nPol;
            spec.AdapterMeta = struct("LogicalPortProjectionApplied", false, "PortMapping", "runtime_array_shape_matches_channel_ports");
            valid = true;
        end

        function orientation = localResolveRuntimeAntennaOrientation(runtimeMeta, primaryField)
            orientation = [0; 0; 0];
            if ~(isstruct(runtimeMeta) && ~isempty(fieldnames(runtimeMeta)))
                return;
            end
            az = double(sixgr.util.structGet(runtimeMeta, primaryField, NaN));
            if ~isfinite(az)
                az = double(sixgr.util.structGet(runtimeMeta, "Azimuth_deg", ...
                    sixgr.util.structGet(runtimeMeta, "Heading_deg", NaN)));
            end
            tilt = double(sixgr.util.structGet(runtimeMeta, "Tilt_deg", 0));
            boresightAz = double(sixgr.util.structGet(runtimeMeta, "BoresightAzimuth_deg", 0));
            boresightEl = double(sixgr.util.structGet(runtimeMeta, "BoresightElevation_deg", 0));
            boresightSlant = double(sixgr.util.structGet(runtimeMeta, "BoresightSlant_deg", 0));
            if isfinite(az)
                orientation(1) = az;
            end
            if isfinite(tilt)
                orientation(2) = tilt;
            end
            if isfinite(boresightAz)
                orientation(1) = orientation(1) + boresightAz;
            end
            % nrCDLChannel beta is positive mechanical downtilt, whereas
            % boresight elevation is positive above the local horizon.
            if isfinite(boresightEl)
                orientation(2) = orientation(2) - boresightEl;
            end
            if isfinite(boresightSlant)
                orientation(3) = boresightSlant;
            end
        end

        function cdl = localSetCDLArrayOrientation(cdl, side, orientation)
            propName = string(side) + "ArrayOrientation";
            if isprop(cdl, char(propName))
                cdl.(char(propName)) = double(orientation(:));
                return;
            end
            arrayProp = string(side) + "AntennaArray";
            if isprop(cdl, char(arrayProp))
                arr = cdl.(char(arrayProp));
                if isstruct(arr) && isfield(arr, "Orientation")
                    arr.Orientation = double(orientation(:));
                    cdl.(char(arrayProp)) = arr;
                end
            end
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

        function spacing = localNonoverlappingCDLSpacing(sizeVec, verticalElementSpacing, horizontalElementSpacing)
            sizeVec = double(sizeVec(:).');
            if numel(sizeVec) < 2
                sizeVec = [sizeVec ones(1, 2 - numel(sizeVec))];
            end
            nRows = max(1, round(sizeVec(1)));
            nCols = max(1, round(sizeVec(2)));
            verticalElementSpacing = max(eps, double(verticalElementSpacing));
            horizontalElementSpacing = max(eps, double(horizontalElementSpacing));
            % nrCDLChannel defines the last two values as panel-center
            % spacings.  The old fixed [1 1] values overlapped any panel
            % wider/taller than two half-wavelength-spaced elements.
            verticalPanelSpacing = (nRows + 1) * verticalElementSpacing;
            horizontalPanelSpacing = (nCols + 1) * horizontalElementSpacing;
            spacing = [verticalElementSpacing horizontalElementSpacing ...
                verticalPanelSpacing horizontalPanelSpacing];
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

        function [normalizePathGains, mode, source] = localResolveNormalizePathGains(cfg, family)
            familyToken = lower(strtrim(char(string(family))));
            explicitPaths = { ...
                "channel.normalizePathGains", ...
                "channel.NormalizePathGains", ...
                "channel.normalize_path_gains", ...
                "channel.fading.normalizePathGains", ...
                "channel.fading.normalize_path_gains", ...
                sprintf("channel.%s.normalizePathGains", familyToken), ...
                sprintf("channel.%s.normalize_path_gains", familyToken) ...
                };
            for i = 1:numel(explicitPaths)
                path = char(explicitPaths{i});
                raw = sixgr.util.structGet(cfg, path, []);
                if isempty(raw)
                    continue;
                end
                [normalizePathGains, ok] = sixgr.channel.ChannelFactory.localParseLogical(raw);
                if ~ok
                    error("ChannelFactory:BadNormalizePathGains", ...
                        "%s must be a boolean-like value; got '%s'.", path, char(string(raw)));
                end
                if normalizePathGains
                    mode = "normalized_path_gains_config_explicit";
                else
                    mode = "absolute_power_tracking_config_explicit";
                end
                source = string(path);
                return;
            end

            noiseMode = lower(strtrim(string(sixgr.util.structGet(cfg, "run.noiseOperatingMode", ""))));
            if strlength(noiseMode) == 0
                noiseMode = lower(strtrim(string(sixgr.util.structGet(cfg, "simulation.noise_operating_mode", ""))));
            end
            if strlength(noiseMode) == 0
                noiseMode = lower(strtrim(string(sixgr.util.structGet( ...
                    cfg, "lls6g.resolvedConfig.simulation.noise_operating_mode", ""))));
            end

            if noiseMode == "receiver_noise_figure_thermal_noise"
                normalizePathGains = false;
                mode = "absolute_power_tracking_receiver_noise_figure";
                source = "default_for_receiver_noise_figure_thermal_noise";
            else
                normalizePathGains = true;
                mode = "normalized_path_gains_operating_point";
                if strlength(noiseMode) == 0
                    source = "default_without_noise_operating_mode";
                else
                    source = "default_for_" + noiseMode;
                end
            end
        end

        function [normalizeOutputs, mode, source] = localResolveNormalizeChannelOutputs(cfg, family)
            familyToken = lower(strtrim(char(string(family))));
            explicitPaths = { ...
                "channel.normalizeChannelOutputs", ...
                "channel.NormalizeChannelOutputs", ...
                "channel.normalize_channel_outputs", ...
                "channel.fading.normalizeChannelOutputs", ...
                "channel.fading.normalize_channel_outputs", ...
                sprintf("channel.%s.normalizeChannelOutputs", familyToken), ...
                sprintf("channel.%s.normalize_channel_outputs", familyToken) ...
                };
            for i = 1:numel(explicitPaths)
                path = char(explicitPaths{i});
                raw = sixgr.util.structGet(cfg, path, []);
                if isempty(raw)
                    continue;
                end
                [normalizeOutputs, ok] = sixgr.channel.ChannelFactory.localParseLogical(raw);
                if ~ok
                    error("ChannelFactory:BadNormalizeChannelOutputs", ...
                        "%s must be a boolean-like value; got '%s'.", path, char(string(raw)));
                end
                if normalizeOutputs
                    mode = "receive_antenna_count_normalized_config_explicit";
                else
                    mode = "physical_per_connector_power_config_explicit";
                end
                source = string(path);
                return;
            end

            % Per-connector voltage and power must remain unchanged by a
            % reporting convenience normalization.  This is also required
            % for exact TDD reciprocity when the two endpoints have unequal
            % array sizes.  Scenarios may explicitly request normalized
            % outputs, but such a setting is rejected by the exact dynamic
            % TDD reciprocal adapter below.
            normalizeOutputs = false;
            mode = "physical_per_connector_power_default";
            source = "ChannelFactory_physical_channel_default";
        end

        function [tf, ok] = localParseLogical(value)
            ok = true;
            if islogical(value)
                tf = logical(value(1));
                return;
            end
            if isnumeric(value)
                tf = double(value(1)) ~= 0;
                return;
            end
            token = lower(strtrim(char(string(value))));
            if any(strcmp(token, {'true','t','yes','y','on','1','enable','enabled'}))
                tf = true;
            elseif any(strcmp(token, {'false','f','no','n','off','0','disable','disabled'}))
                tf = false;
            else
                tf = false;
                ok = false;
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
                tdlProfile = sixgr.channel.ChannelFactory.localNormalizeToken( ...
                    sixgr.util.structGet(cfgOut, "channel.tdlProfile", ""));
                if sixgr.channel.ChannelFactory.localIsConcreteTDLProfile(tdlProfile)
                    cfgOut = sixgr.channel.ChannelFactory.localAssignConcreteProfile(cfgOut, "TDL", tdlProfile);
                end
                model = "tdl";
            elseif any(strcmp(modelToken, {'NRCDL', 'CDL'}))
                cdlProfile = sixgr.channel.ChannelFactory.localNormalizeToken( ...
                    sixgr.util.structGet(cfgOut, "channel.cdlProfile", ""));
                if sixgr.channel.ChannelFactory.localIsConcreteCDLProfile(cdlProfile)
                    cfgOut = sixgr.channel.ChannelFactory.localAssignConcreteProfile(cfgOut, "CDL", cdlProfile);
                end
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

            ownProfileValue = sixgr.channel.ChannelFactory.localNormalizeToken( ...
                sixgr.util.structGet(cfg, char(ownProfilePath), ""));
            if strcmp(family, 'TDL')
                hasExplicitOwnProfile = sixgr.channel.ChannelFactory.localIsConcreteTDLProfile(ownProfileValue);
            else
                hasExplicitOwnProfile = sixgr.channel.ChannelFactory.localIsConcreteCDLProfile(ownProfileValue);
            end
            modelToken = sixgr.channel.ChannelFactory.localNormalizeToken( ...
                sixgr.util.structGet(cfg, "channel.model", ""));
            fadingModelToken = sixgr.channel.ChannelFactory.localNormalizeToken( ...
                sixgr.util.structGet(cfg, "channel.fading.model", ""));

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
                        if sixgr.channel.ChannelFactory.localIsStaleGenericFadingProfile( ...
                                path, hasExplicitOwnProfile, modelToken, fadingModelToken, family)
                            continue;
                        end
                        otherProfiles(end+1, 1) = string(value); %#ok<AGROW>
                        otherFields(end+1, 1) = string(path); %#ok<AGROW>
                    end
                else
                    if sixgr.channel.ChannelFactory.localIsConcreteCDLProfile(value)
                        ownProfiles(end+1, 1) = string(value); %#ok<AGROW>
                        ownFields(end+1, 1) = string(path); %#ok<AGROW>
                    elseif sixgr.channel.ChannelFactory.localIsConcreteTDLProfile(value)
                        if sixgr.channel.ChannelFactory.localIsStaleGenericFadingProfile( ...
                                path, hasExplicitOwnProfile, modelToken, fadingModelToken, family)
                            continue;
                        end
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

        function tf = localIsStaleGenericFadingProfile(path, hasExplicitOwnProfile, modelToken, fadingModelToken, family)
            tf = false;
            if ~hasExplicitOwnProfile || ~strcmp(char(path), "channel.fading.profile")
                return;
            end
            family = upper(string(family));
            modelToken = upper(string(modelToken));
            fadingModelToken = upper(string(fadingModelToken));
            tf = modelToken == family || ...
                (strlength(modelToken) == 0 && ...
                (fadingModelToken == family || strlength(fadingModelToken) == 0));
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
            if ~isfield(cfgOut.channel, "fading") || ~isstruct(cfgOut.channel.fading)
                cfgOut.channel.fading = struct();
            end
            cfgOut.channel.fading.model = char(upper(string(family)));
            cfgOut.channel.fading.profile = char(profile);
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
