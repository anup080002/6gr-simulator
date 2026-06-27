classdef GeometryEngine
%GEOMETRYENGINE Canonical per-slot link geometry for physical runtime paths.
% Keep this file ASCII-only.

methods(Static)
    function state = buildLargeScaleState(cfg, layout, ue, plModel, varargin)
        opt = struct("PreviousState", struct(), "ReusePropagation", false, "IndoorDistance_m", []);
        if mod(numel(varargin), 2) ~= 0
            error("sixgr:system:GeometryEngine:BadNV", "Name-value inputs must come in pairs.");
        end
        for i = 1:2:numel(varargin)
            name = lower(string(varargin{i})); val = varargin{i+1};
            switch name
                case "previousstate", opt.PreviousState = val;
                case "reusepropagation", opt.ReusePropagation = logical(val);
                case {"indoordistance_m","dindoor_m","dindoor"}, opt.IndoorDistance_m = double(val);
                otherwise, error("sixgr:system:GeometryEngine:UnknownOpt", "Unknown option: %s", char(name));
            end
        end

        uePos = sixgr.system.GeometryEngine.positionMatrix(sixgr.util.structGet(ue, "pos_m", zeros(0,3)), "ue.pos_m");
        bsPos = sixgr.system.GeometryEngine.positionMatrix(sixgr.util.structGet(layout, "bs.pos_m", zeros(0,3)), "layout.bs.pos_m");
        K = size(uePos,1); nCells = size(bsPos,1);
        state = struct();
        state.ContractVersion = "sixgr.system.GeometryEngine/v1";
        state.GeometrySource = "sixgr.system.GeometryEngine.buildLargeScaleState";
        state.PositionSource = "scenario_layout_and_mobility_state";
        state.DelaySource = "distance_over_c";
        state.DopplerSource = "relative_velocity_projection";
        state.PathlossSource = "TR38901Plus.pathlossFromGeometryState";
        state.UEPosition_m = uePos; state.BSPosition_m = bsPos;
        state.UEVelocity_mps = sixgr.system.GeometryEngine.resolveUEVelocity(ue, K);
        state.BSVelocity_mps = sixgr.system.GeometryEngine.resolveBSVelocity(layout, nCells);
        state.CarrierFrequency_Hz = sixgr.system.GeometryEngine.resolveCarrierFrequency(cfg, plModel);
        state.SpeedOfLight_mps = sixgr.system.GeometryEngine.lightSpeed();
        state.PropagationScenario = string(sixgr.util.structGet(cfg, "channel.propagationScenario", sixgr.util.structGet(cfg, "run.scenario", "UMa")));
        state.PathlossEnabled = logical(sixgr.util.structGet(cfg, "channel.pathlossEnabled", true));
        state.ShadowFadingEnabled = logical(sixgr.util.structGet(cfg, "channel.shadowFadingEnabled", true));
        state.LOSEnabled = logical(sixgr.util.structGet(cfg, "channel.losEnabled", true));

        [d2d, dxy] = sixgr.system.GeometryEngine.distanceAndDelta(uePos, layout);
        dz = uePos(:,3) - bsPos(:,3).';
        d3d = sqrt(max(d2d.^2 + dz.^2, 0));
        state.d2d_m = double(d2d); state.d3d_m = double(d3d); state.dxy_m = double(dxy);
        state.UnitVectorTxToRx = sixgr.system.GeometryEngine.unitVectors(dxy, dz, d3d);
        state.PropagationDelay_s = double(d3d) ./ state.SpeedOfLight_mps;
        [vr, fd] = sixgr.system.GeometryEngine.radialDoppler(state.UnitVectorTxToRx, state.UEVelocity_mps, state.BSVelocity_mps, state.CarrierFrequency_Hz);
        state.RadialVelocity_mps = double(vr); state.SignedDoppler_Hz = double(fd); state.Doppler_Hz = abs(double(fd));

        indoorUE = sixgr.system.GeometryEngine.columnLogical(sixgr.util.structGet(ue, "indoor", false(K,1)), K, "ue.indoor");
        state.IndoorRx = repmat(indoorUE, 1, nCells);
        state.IndoorDistance_m = sixgr.system.GeometryEngine.resolveIndoorDistance(cfg, opt.IndoorDistance_m, indoorUE, K, nCells);
        state.LOSProbability = sixgr.system.GeometryEngine.resolveLOSProbability(cfg, state);

        if logical(opt.ReusePropagation)
            prev = opt.PreviousState;
            state.LOS = logical(sixgr.system.GeometryEngine.requirePrevious(prev, "LOS", K, nCells));
            state.Shadow_dB = double(sixgr.system.GeometryEngine.requirePrevious(prev, "Shadow_dB", K, nCells));
            state.O2I_dB = double(sixgr.system.GeometryEngine.requirePrevious(prev, "O2I_dB", K, nCells));
            state.BasePathloss_dB = double(sixgr.system.GeometryEngine.requirePrevious(prev, "BasePathloss_dB", K, nCells));
            state.Pathloss_dB = double(sixgr.system.GeometryEngine.requirePrevious(prev, "Pathloss_dB", K, nCells));
            state.PathlossModelSource = string(sixgr.util.structGet(prev, "PathlossModelSource", ""));
            state.PathlossComplianceStatus = string(sixgr.util.structGet(prev, "PathlossComplianceStatus", ""));
            state.FallbackUsedForPathloss = logical(sixgr.util.structGet(prev, "FallbackUsedForPathloss", false));
            state.O2IModelSource = string(sixgr.util.structGet(prev, "O2IModelSource", ""));
            state.O2IComplianceStatus = string(sixgr.util.structGet(prev, "O2IComplianceStatus", ""));
            state.O2IComplianceReason = string(sixgr.util.structGet(prev, "O2IComplianceReason", ""));
            state.LOSProbabilitySource = string(sixgr.util.structGet(prev, "LOSProbabilitySource", ""));
            state.LOSComplianceStatus = string(sixgr.util.structGet(prev, "LOSComplianceStatus", ""));
            state.LOSComplianceReason = string(sixgr.util.structGet(prev, "LOSComplianceReason", ""));
            return;
        end

        state.LOS = false(K, nCells);
        state.Shadow_dB = zeros(K, nCells);
        state.O2I_dB = zeros(K, nCells);
        state.BasePathloss_dB = zeros(K, nCells);
        state.Pathloss_dB = zeros(K, nCells);
        if isempty(plModel)
            error("sixgr:system:GeometryEngine:MissingPathlossModel", "A TR38901Plus pathloss model is required for physical geometry evaluation.");
        end
        for c = 1:nCells
            [pl_dB, los, ex] = plModel.pathlossFromGeometryState(state, c);
            state.Pathloss_dB(:,c) = double(pl_dB(:));
            state.LOS(:,c) = logical(los(:));
            state.Shadow_dB(:,c) = double(ex.shadow_dB(:));
            state.O2I_dB(:,c) = double(ex.o2i_dB(:));
            state.BasePathloss_dB(:,c) = double(ex.base_dB(:));
        end
        state.PathlossModelSource = sixgr.system.GeometryEngine.objectStringProp(plModel, "PathlossModelSource", "");
        state.PathlossComplianceStatus = sixgr.system.GeometryEngine.objectStringProp(plModel, "PathlossComplianceStatus", "");
        state.FallbackUsedForPathloss = sixgr.system.GeometryEngine.objectLogicalProp(plModel, "FallbackUsedForPathloss", false);
        state.O2IModelSource = sixgr.system.GeometryEngine.objectStringProp(plModel, "O2IModelSource", "");
        state.O2IComplianceStatus = sixgr.system.GeometryEngine.objectStringProp(plModel, "O2IComplianceStatus", "");
        state.O2IComplianceReason = sixgr.system.GeometryEngine.objectStringProp(plModel, "O2IComplianceReason", "");
        state.LOSProbabilitySource = sixgr.system.GeometryEngine.objectStringProp(plModel, "LOSProbabilitySource", "");
        state.LOSComplianceStatus = sixgr.system.GeometryEngine.objectStringProp(plModel, "LOSComplianceStatus", "");
        state.LOSComplianceReason = sixgr.system.GeometryEngine.objectStringProp(plModel, "LOSComplianceReason", "");
    end

    function [d2d, dxy] = distanceAndDelta(uePos, layout)
        bsPos = double(sixgr.util.structGet(layout, "bs.pos_m", zeros(0,3)));
        uePos = double(uePos);
        wrapEn = logical(sixgr.util.structGet(layout, "wraparoundEnabled", false));
        area_m = double(sixgr.util.structGet(layout, "area_m", [0 0]));
        wrapMode = string(sixgr.util.structGet(layout, "wraparoundMode", ""));
        if strlength(strtrim(wrapMode)) == 0
            if contains(lower(string(sixgr.util.structGet(layout, "layoutType", ""))), "hex")
                wrapMode = "hex_lattice_min_image";
            else
                wrapMode = "rectangular_torus";
            end
        end
        if wrapEn && wrapMode ~= "disabled"
            [d2d, dxy] = sixgr.scenario.wraparoundDistance(uePos, bsPos, area_m, "Mode", wrapMode, "ISD_m", double(sixgr.util.structGet(layout, "isd_m", NaN)));
            return;
        end
        dx = uePos(:,1) - bsPos(:,1).'; dy = uePos(:,2) - bsPos(:,2).';
        d2d = sqrt(dx.^2 + dy.^2);
        dxy = zeros(size(dx,1), size(dx,2), 2);
        dxy(:,:,1) = dx; dxy(:,:,2) = dy;
    end

    function velocity = resolveUEVelocity(ue, K)
        explicit = double(sixgr.util.structGet(ue, "velocity_mps", []));
        if ~isempty(explicit)
            velocity = sixgr.system.GeometryEngine.velocityMatrix(explicit, K, "ue.velocity_mps");
            return;
        end
        speed = double(sixgr.util.structGet(ue, "speed_kmh", zeros(K,1)));
        if isscalar(speed), speed = repmat(speed, K, 1); end
        speed = reshape(speed, [], 1);
        if numel(speed) ~= K, error("sixgr:system:GeometryEngine:BadUESpeed", "ue.speed_kmh must be scalar or Kx1."); end
        heading = double(sixgr.util.structGet(ue, "heading_deg", zeros(K,1)));
        if isscalar(heading), heading = repmat(heading, K, 1); end
        heading = reshape(heading, [], 1);
        if numel(heading) ~= K, error("sixgr:system:GeometryEngine:BadUEHeading", "ue.heading_deg must be scalar or Kx1."); end
        speed = speed ./ 3.6;
        velocity = [speed .* cosd(heading), speed .* sind(heading), zeros(K,1)];
    end

    function velocity = resolveBSVelocity(layout, nCells)
        explicit = double(sixgr.util.structGet(layout, "bs.velocity_mps", []));
        if isempty(explicit), velocity = zeros(nCells, 3); return; end
        velocity = sixgr.system.GeometryEngine.velocityMatrix(explicit, nCells, "layout.bs.velocity_mps");
    end

    function fc = resolveCarrierFrequency(cfg, plModel)
        fc = double(sixgr.util.structGet(cfg, "phy.fc_Hz", sixgr.util.structGet(cfg, "carrier.fc_Hz", sixgr.util.structGet(cfg, "channel.fc_Hz", NaN))));
        if ~(isfinite(fc) && fc > 0) && ~isempty(plModel) && isobject(plModel) && isprop(plModel, "Fc_Hz"), fc = double(plModel.Fc_Hz); end
        if ~(isfinite(fc) && fc > 0), fc = 3.5e9; end
    end

    function c = lightSpeed(), c = 299792458; end

    function u = unitVectors(dxy, dz, d3d)
        K = size(dxy,1); nCells = size(dxy,2); u = zeros(K, nCells, 3); denom = max(double(d3d), eps);
        u(:,:,1) = double(dxy(:,:,1)) ./ denom; u(:,:,2) = double(dxy(:,:,2)) ./ denom; u(:,:,3) = double(dz) ./ denom;
    end

    function [vr, fd] = radialDoppler(unitTxToRx, ueVelocity, bsVelocity, fc)
        K = size(unitTxToRx,1); nCells = size(unitTxToRx,2); vr = zeros(K, nCells);
        for c = 1:nCells
            rel = double(ueVelocity) - double(bsVelocity(c,:));
            u = reshape(double(unitTxToRx(:,c,:)), K, 3);
            vr(:,c) = sum(rel .* u, 2);
        end
        fd = vr ./ sixgr.system.GeometryEngine.lightSpeed() .* double(fc);
    end

    function p = resolveLOSProbability(cfg, geometryState)
        K = size(geometryState.d2d_m,1); nCells = size(geometryState.d2d_m,2); p = zeros(K, nCells);
        if ~logical(sixgr.util.structGet(geometryState, "LOSEnabled", true)), return; end
        hUT = geometryState.UEPosition_m(:,3);
        scenarioName = string(sixgr.util.structGet(geometryState, "PropagationScenario", sixgr.util.structGet(cfg, "channel.propagationScenario", "UMa")));
        for c = 1:nCells
            [pc, ~] = sixgr.channel.LOSProbability(scenarioName, geometryState.d2d_m(:,c), "HUT_m", hUT);
            p(:,c) = double(pc(:));
        end
        p = max(0, min(1, p));
    end

    function d = resolveIndoorDistance(cfg, override, indoorUE, K, nCells)
        if isempty(override)
            d = double(sixgr.util.structGet(cfg, "channel.o2i.indoorDistance_m", 10));
        else
            d = double(override);
        end
        if isscalar(d)
            d = repmat(d, K, 1);
        else
            d = reshape(d, [], 1);
            if numel(d) ~= K, error("sixgr:system:GeometryEngine:BadIndoorDistance", "IndoorDistance_m must be scalar or Kx1."); end
        end
        d = repmat(max(0, d) .* double(indoorUE(:)), 1, nCells);
    end

    function value = requirePrevious(s, fieldName, varargin)
        if ~isstruct(s) || ~isfield(s, fieldName)
            error("sixgr:system:GeometryEngine:MissingPreviousState", "PreviousState.%s is required when ReusePropagation=true.", fieldName);
        end
        value = s.(fieldName); expected = cell2mat(varargin);
        if ~isequal(size(value), expected)
            error("sixgr:system:GeometryEngine:BadPreviousStateShape", "PreviousState.%s must have size %s.", fieldName, mat2str(expected));
        end
    end

    function pos = positionMatrix(pos, label)
        pos = double(pos);
        if isempty(pos), pos = zeros(0,3); return; end
        if size(pos,2) < 3, error("sixgr:system:GeometryEngine:BadPositionMatrix", "%s must have at least three columns [x y z].", label); end
        pos = pos(:,1:3);
        if any(~isfinite(pos(:))), error("sixgr:system:GeometryEngine:NonfinitePosition", "%s must contain finite positions.", label); end
    end

    function velocity = velocityMatrix(value, nRows, label)
        value = double(value);
        if isvector(value) && numel(value) == 3, velocity = repmat(reshape(value, 1, 3), nRows, 1); return; end
        if size(value,1) ~= nRows || size(value,2) < 3, error("sixgr:system:GeometryEngine:BadVelocityMatrix", "%s must be 1x3 or Nx3.", label); end
        velocity = value(:,1:3);
        if any(~isfinite(velocity(:))), error("sixgr:system:GeometryEngine:NonfiniteVelocity", "%s must contain finite velocities.", label); end
    end

    function out = columnLogical(value, K, label)
        if isscalar(value), out = repmat(logical(value), K, 1); return; end
        out = reshape(logical(value), [], 1);
        if numel(out) ~= K, error("sixgr:system:GeometryEngine:BadLogicalVector", "%s must be scalar or Kx1.", label); end
    end

    function value = objectStringProp(obj, propName, fallback)
        value = string(fallback);
        if ~isempty(obj) && isobject(obj) && isprop(obj, propName), value = string(obj.(propName)); end
    end

    function value = objectLogicalProp(obj, propName, fallback)
        value = logical(fallback);
        if ~isempty(obj) && isobject(obj) && isprop(obj, propName), value = logical(obj.(propName)); end
    end
end
end
