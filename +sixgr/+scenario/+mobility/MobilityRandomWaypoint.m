classdef MobilityRandomWaypoint < sixgr.scenario.mobility.MobilityModelBase
%SIXGR.SCENARIO.MOBILITY.MOBILITYRANDOMWAYPOINT Random waypoint mobility.
%
% The UE moves toward a random target waypoint. When the waypoint is reached,
% a new waypoint is drawn uniformly in the area.
%
% UE fields used/updated:
%   ue.pos_m(:,1:2)
%   ue.speed_kmh
%   ue.heading_deg
%
% See also: sixgr.scenario.mobility.updatePositions

    properties
        TargetXY_m double = zeros(0,2);  % [K x 2]
        Stream
    end

    methods
        function obj = MobilityRandomWaypoint(area_m, wrapEnabled, varargin)
            obj@sixgr.scenario.mobility.MobilityModelBase(area_m, wrapEnabled);
            parser = inputParser;
            addParameter(parser, "Seed", 0, @(x) isnumeric(x) && isscalar(x) && isfinite(x));
            parse(parser, varargin{:});
            obj.Stream = RandStream("mt19937ar", "Seed", double(parser.Results.Seed));
        end

        function ue = reset(obj, ue)
            K = ue.K;
            obj.TargetXY_m = localRandomXY(K, obj.Area_m, obj.Stream);
            ue.heading_deg = localHeadingToTarget(ue.pos_m(:,1:2), obj.TargetXY_m);
        end

        function ue = step(obj, ue, dt_s)
            if isempty(obj.TargetXY_m) || size(obj.TargetXY_m,1) ~= ue.K
                ue = reset(obj, ue);
            end

            xy = ue.pos_m(:,1:2);
            tgt = obj.TargetXY_m;
            toTgt = tgt - xy;
            d = sqrt(sum(toTgt.^2, 2));
            arrived = d < 1.0; % meters

            if any(arrived)
                obj.TargetXY_m(arrived,:) = localRandomXY(nnz(arrived), obj.Area_m, obj.Stream);
                tgt = obj.TargetXY_m;
                toTgt = tgt - xy;
                d = sqrt(sum(toTgt.^2, 2));
            end

            dir = toTgt ./ max(d, 1e-9);
            step_m = (ue.speed_kmh(:) ./ 3.6) * dt_s;
            xyNew = xy + dir .* step_m;

            % Update heading from direction
            ue.heading_deg = mod(atan2d(dir(:,2), dir(:,1)), 360);

            if obj.WraparoundEnabled
                xyNew = obj.applyWraparound(xyNew);
            else
                [xyNew, ue.heading_deg] = obj.applyReflect(xyNew, ue.heading_deg);
            end

            ue.pos_m(:,1:2) = xyNew;
        end
    end
end

% ---------------- Local helpers ----------------

function xy = localRandomXY(K, area_m, stream)
W = area_m(1); H = area_m(2);
xy = [ (rand(stream,K,1)-0.5)*W, (rand(stream,K,1)-0.5)*H ];
end

function hd = localHeadingToTarget(xy, tgt)
v = tgt - xy;
hd = mod(atan2d(v(:,2), v(:,1)), 360);
end
