classdef MobilityZigZag < sixgr.scenario.mobility.MobilityModelBase
%SIXGR.SCENARIO.MOBILITY.MOBILITYZIGZAG Piecewise-linear zig-zag mobility.
%
% This model keeps UEs moving along straight segments, then alternates the
% heading offset to create a repeatable zig-zag trajectory. It is useful for
% link-level mobility studies where geometry-driven reselection and beam
% changes need to be visible without invoking the full system scheduler path.

    properties
        SegmentDuration_s (1,1) double = 0.75
        TurnAngle_deg (1,1) double = 35
        SegmentTimeRemaining_s double = zeros(0,1)
        TurnSign double = zeros(0,1)
    end

    methods
        function obj = MobilityZigZag(area_m, wrapEnabled, varargin)
            obj@sixgr.scenario.mobility.MobilityModelBase(area_m, wrapEnabled);
            if nargin >= 3 && ~isempty(varargin)
                if mod(numel(varargin), 2) ~= 0
                    error("sixgr:scenario:mobility:MobilityZigZag:BadNV", ...
                        "Name-value inputs must come in pairs.");
                end
                for i = 1:2:numel(varargin)
                    name = lower(string(varargin{i}));
                    value = varargin{i+1};
                    switch name
                        case "segmentduration_s"
                            obj.SegmentDuration_s = max(0.05, double(value));
                        case "turnangle_deg"
                            obj.TurnAngle_deg = min(max(double(value), 0), 170);
                        otherwise
                            error("sixgr:scenario:mobility:MobilityZigZag:UnknownOpt", ...
                                "Unknown option '%s'.", name);
                    end
                end
            end
        end

        function ue = reset(obj, ue)
            K = ue.K;
            if ~isfield(ue, "heading_deg") || numel(ue.heading_deg) ~= K
                ue.heading_deg = rand(K,1) * 360;
            end
            obj.SegmentTimeRemaining_s = obj.SegmentDuration_s * ones(K,1);
            obj.TurnSign = ones(K,1);
            obj.TurnSign(2:2:end) = -1;
        end

        function ue = step(obj, ue, dt_s)
            if ~isfield(ue, "heading_deg") || numel(ue.heading_deg) ~= ue.K || ...
                    isempty(obj.SegmentTimeRemaining_s) || numel(obj.SegmentTimeRemaining_s) ~= ue.K
                ue = obj.reset(ue);
            end

            obj.SegmentTimeRemaining_s = obj.SegmentTimeRemaining_s - dt_s;
            turnMask = obj.SegmentTimeRemaining_s <= 0;
            if any(turnMask)
                ue.heading_deg(turnMask) = mod( ...
                    ue.heading_deg(turnMask) + obj.TurnSign(turnMask) .* obj.TurnAngle_deg, 360);
                obj.TurnSign(turnMask) = -obj.TurnSign(turnMask);
                obj.SegmentTimeRemaining_s(turnMask) = obj.SegmentDuration_s;
            end

            xy = ue.pos_m(:,1:2);
            v_mps = ue.speed_kmh(:) ./ 3.6;
            dx = v_mps .* cosd(ue.heading_deg(:)) * dt_s;
            dy = v_mps .* sind(ue.heading_deg(:)) * dt_s;
            xyNew = xy + [dx dy];

            if obj.WraparoundEnabled
                xyNew = obj.applyWraparound(xyNew);
            else
                [xyNew, ue.heading_deg] = obj.applyReflect(xyNew, ue.heading_deg);
            end

            ue.pos_m(:,1:2) = xyNew;
        end
    end
end
