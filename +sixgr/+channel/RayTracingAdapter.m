classdef RayTracingAdapter < handle
% sixgr.channel.RayTracingAdapter
%
% Adapter for RF Propagation / Site Viewer ray tracing workflows.
% Intended for large-scale effects (pathloss, rays) in System/Hybrid modes.
%
% This adapter intentionally avoids hard dependency on a GUI viewer. It can:
%   - compute ray-tracing based pathloss if RF Propagation functions exist
%   - optionally return rays for visualization
%
% Important:
%   - Ray tracing functions are NOT MATLAB Coder compatible.
%   - Use this only for offline analysis / calibration.
%
% Example:
%   rt = sixgr.channel.RayTracingAdapter(cfg,"Fc_Hz",3.5e9);
%   [pldB,det] = rt.pathloss([0;0;25],[200;0;1.5]);

    properties
        Scenario (1,1) string = "UMa"
        Fc_Hz (1,1) double = 3.5e9
        CoordinateSystem (1,1) string = "cartesian" % "cartesian" or "geographic"
        Viewer = []
        PropModel = []
    end

    methods
        function obj = RayTracingAdapter(cfg, varargin)
            if nargin < 1
                cfg = struct();
            end

            obj.Scenario = string(localCanonicalScenario(cfg, obj.Scenario));
            obj.Fc_Hz = double(localCanonicalStructGet(cfg, "phy.fc_Hz", "channel.fc_Hz", obj.Fc_Hz));
            obj.CoordinateSystem = string(sixgr.util.structGet(cfg, "scenario.siteviewer.coordinateSystem", obj.CoordinateSystem));

            if mod(numel(varargin),2) ~= 0
                error("RayTracingAdapter:BadNV","Name-value inputs must come in pairs.");
            end
            for i = 1:2:numel(varargin)
                name = string(varargin{i});
                val  = varargin{i+1};
                switch lower(name)
                    case "scenario"
                        obj.Scenario = string(val);
                    case {"fc_hz","fc","frequency"}
                        obj.Fc_Hz = double(val);
                    case {"coordinatesystem","cs"}
                        obj.CoordinateSystem = string(val);
                    case "viewer"
                        obj.Viewer = val;
                    otherwise
                        error("RayTracingAdapter:UnknownOpt","Unknown option: %s", name);
                end
            end

            % Create propagation model (ray tracing) if available
            if exist("propagationModel","file") == 2
                method = sixgr.util.structGet(cfg,"channel.raytracing.method",[]);
                maxRef = sixgr.util.structGet(cfg,"channel.raytracing.maxReflections",[]);
                if isempty(method) || isempty(maxRef)
                    error("CHANNEL:InvalidRayTracingContract", ...
                        "Ray tracing requires explicit method and maxReflections.");
                end
                obj.PropModel = propagationModel("raytracing", ...
                    "Method", char(string(method)), ...
                    "MaxNumReflections", double(maxRef));
            else
                obj.PropModel = [];
            end
        end

        function [pl_dB, det] = pathloss(obj, txPos_m, rxPos_m, varargin)
            % Compute ray tracing pathloss (dB).
            %
            % Inputs:
            %   txPos_m: [3x1] meters (x;y;z) OR pass TxSite in options
            %   rxPos_m: [3x1] meters (x;y;z) OR pass RxSite in options
            %
            % Name-value:
            %   "TxSite"      : txsite object
            %   "RxSite"      : rxsite object
            %   "ReturnRays"  : true/false (default false)
            %
            opt.TxSite = [];
            opt.RxSite = [];
            opt.ReturnRays = false;

            if mod(numel(varargin),2) ~= 0
                error("RayTracingAdapter:pathloss:BadNV","Name-value inputs must come in pairs.");
            end
            for i = 1:2:numel(varargin)
                name = string(varargin{i});
                val  = varargin{i+1};
                switch lower(name)
                    case "txsite"
                        opt.TxSite = val;
                    case "rxsite"
                        opt.RxSite = val;
                    case "returnrays"
                        opt.ReturnRays = logical(val);
                    otherwise
                        error("RayTracingAdapter:pathloss:UnknownOpt","Unknown option: %s", name);
                end
            end

            % Create sites
            if isempty(opt.TxSite) || isempty(opt.RxSite)
                [tx, rx] = obj.localMakeSites(txPos_m, rxPos_m);
            else
                tx = opt.TxSite;
                rx = opt.RxSite;
            end

            % Pathloss evaluation
            pl_dB = NaN;
            det = struct();
            det.method = "";

            % Prefer pathloss() if available
            if exist("pathloss","file") == 2 && ~isempty(obj.PropModel)
                try
                    pl_dB = pathloss(rx, tx, obj.PropModel);
                    det.method = "pathloss(rx,tx,propModel)";
                catch
                    % Fall back
                end
            end

            % Fallback: use sigstrength (tx power set to 0 dBm -> pathloss = -ss)
            if isnan(pl_dB)
                if exist("sigstrength","file") == 2 && ~isempty(obj.PropModel)
                    try
                        ss_dBm = sigstrength(rx, tx, obj.PropModel);
                        pl_dB = -ss_dBm; % tx power 0 dBm, no gains
                        det.method = "sigstrength(rx,tx,propModel) with txPower=0 dBm";
                    catch ME
                        error("CHANNEL:RayTracingFailed", ...
                            "Ray tracing pathloss failed. Underlying error: %s", ME.message);
                    end
                else
                    error("CHANNEL:RayTracingUnavailable", ...
                        "RF propagation functions are missing (propagationModel/pathloss/sigstrength).");
                end
            end

            det.pl_dB = pl_dB;

            % Rays (optional)
            det.rays = [];
            if opt.ReturnRays && exist("raytrace","file") == 2 && ~isempty(obj.PropModel)
                det.rays = raytrace(tx, rx, obj.PropModel);
            end
        end
    end

    methods(Access=private)
        function [tx, rx] = localMakeSites(obj, txPos_m, rxPos_m)
            % Create txsite/rxsite with cartesian antenna positions.
            % If creation fails due to API differences, throw a helpful error.
            try
                txPos_m = double(txPos_m(:));
                rxPos_m = double(rxPos_m(:));
                if numel(txPos_m) ~= 3 || numel(rxPos_m) ~= 3
                    error("BadPos");
                end

                % For deterministic pathloss, set tx power ~= 0 dBm (1 mW).
                % R2025b enforces strictly positive TransmitterPower.
                if exist("txsite","file") ~= 2 || exist("rxsite","file") ~= 2
                    error("MissingSiteObjs");
                end

                if lower(strtrim(obj.CoordinateSystem)) == "cartesian"
                    tx = txsite("CoordinateSystem","cartesian", ...
                        "AntennaPosition", txPos_m, ...
                        "TransmitterFrequency", obj.Fc_Hz, ...
                        "TransmitterPower", 1e-3);
                    rx = rxsite("CoordinateSystem","cartesian", ...
                        "AntennaPosition", rxPos_m);
                else
                    error("GeographicNotImplemented");
                end
            catch
                error("CHANNEL:InvalidRayTracingContract", ...
                    "Failed to create txsite/rxsite from positions. " + ...
                    "Pass explicit TxSite/RxSite objects to RayTracingAdapter.pathloss().");
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
