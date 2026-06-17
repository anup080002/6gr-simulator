classdef MobilityTrace < sixgr.scenario.mobility.MobilityModelBase
%SIXGR.SCENARIO.MOBILITY.MOBILITYTRACE Follow configured per-UE waypoint traces.

    properties
        UserPaths struct = struct([])
        NextWaypointIdx double = zeros(0,1)
        HoldRemaining_s double = zeros(0,1)
        DirectionSign double = zeros(0,1)
    end

    methods
        function obj = MobilityTrace(area_m, wrapEnabled, userPaths)
            obj@sixgr.scenario.mobility.MobilityModelBase(area_m, wrapEnabled);
            if nargin >= 3 && ~isempty(userPaths)
                obj.UserPaths = userPaths;
            end
        end

        function ue = reset(obj, ue)
            K = ue.K;
            if ~isfield(ue, "heading_deg") || numel(ue.heading_deg) ~= K
                ue.heading_deg = rand(K,1) * 360;
            end
            obj.NextWaypointIdx = zeros(K,1);
            obj.HoldRemaining_s = zeros(K,1);
            obj.DirectionSign = ones(K,1);

            for i = 1:numel(obj.UserPaths)
                spec = obj.UserPaths(i);
                ueId = round(double(spec.ue_id));
                if ueId < 1 || ueId > K
                    continue;
                end
                initialPos = double(spec.initial_position_m);
                ue.pos_m(ueId, 1:2) = initialPos(1:2);
                if numel(initialPos) >= 3 && isfinite(initialPos(3))
                    ue.pos_m(ueId, 3) = initialPos(3);
                end
                if isfinite(double(spec.speed_kmh))
                    ue.speed_kmh(ueId) = double(spec.speed_kmh);
                end
                if isfinite(double(spec.initial_heading_deg))
                    ue.heading_deg(ueId) = double(spec.initial_heading_deg);
                elseif ~isempty(spec.waypoints)
                    targetPos = double(spec.waypoints(1).position_m);
                    delta = targetPos(1:2) - initialPos(1:2);
                    if norm(delta) > 0
                        ue.heading_deg(ueId) = mod(atan2d(delta(2), delta(1)), 360);
                    end
                    obj.NextWaypointIdx(ueId) = 1;
                end
            end
        end

        function ue = step(obj, ue, dt_s)
            if ~isfield(ue, "heading_deg") || numel(ue.heading_deg) ~= ue.K || ...
                    numel(obj.NextWaypointIdx) ~= ue.K
                ue = obj.reset(ue);
            end

            for i = 1:numel(obj.UserPaths)
                spec = obj.UserPaths(i);
                ueId = round(double(spec.ue_id));
                if ueId < 1 || ueId > ue.K
                    continue;
                end
                remaining_s = double(dt_s);
                while remaining_s > 0
                    if obj.HoldRemaining_s(ueId) > 0
                        spent_s = min(remaining_s, obj.HoldRemaining_s(ueId));
                        obj.HoldRemaining_s(ueId) = obj.HoldRemaining_s(ueId) - spent_s;
                        remaining_s = remaining_s - spent_s;
                        if remaining_s <= 0
                            break;
                        end
                    end

                    waypointIdx = round(double(obj.NextWaypointIdx(ueId)));
                    if waypointIdx < 1 || waypointIdx > numel(spec.waypoints)
                        break;
                    end

                    currentPos = double(ue.pos_m(ueId, 1:2));
                    targetPos = double(spec.waypoints(waypointIdx).position_m);
                    delta = targetPos(1:2) - currentPos;
                    distance_m = norm(delta);
                    speed_mps = max(0, double(ue.speed_kmh(ueId)) / 3.6);

                    if distance_m <= 1e-9 || speed_mps <= 0
                        ue.pos_m(ueId, 1:2) = targetPos(1:2);
                        if numel(targetPos) >= 3 && isfinite(targetPos(3))
                            ue.pos_m(ueId, 3) = targetPos(3);
                        end
                        obj.HoldRemaining_s(ueId) = max(0, double(spec.waypoints(waypointIdx).hold_time_s));
                        obj.advanceWaypoint(ueId, spec);
                        continue;
                    end

                    direction = delta / distance_m;
                    ue.heading_deg(ueId) = mod(atan2d(direction(2), direction(1)), 360);
                    travel_m = speed_mps * remaining_s;
                    if travel_m + 1e-9 >= distance_m
                        ue.pos_m(ueId, 1:2) = targetPos(1:2);
                        if numel(targetPos) >= 3 && isfinite(targetPos(3))
                            ue.pos_m(ueId, 3) = targetPos(3);
                        end
                        remaining_s = max(0, remaining_s - (distance_m / max(speed_mps, eps)));
                        obj.HoldRemaining_s(ueId) = max(0, double(spec.waypoints(waypointIdx).hold_time_s));
                        obj.advanceWaypoint(ueId, spec);
                    else
                        ue.pos_m(ueId, 1:2) = currentPos + direction * travel_m;
                        remaining_s = 0;
                    end
                end
            end
        end

        function advanceWaypoint(obj, ueId, spec)
            nWaypoints = numel(spec.waypoints);
            if nWaypoints < 1
                obj.NextWaypointIdx(ueId) = 0;
                return;
            end

            currentIdx = round(double(obj.NextWaypointIdx(ueId)));
            if currentIdx < 1
                currentIdx = 1;
            end

            loopMode = lower(strtrim(string(spec.loop_mode)));
            switch loopMode
                case "hold"
                    if currentIdx >= nWaypoints
                        obj.NextWaypointIdx(ueId) = 0;
                    else
                        obj.NextWaypointIdx(ueId) = currentIdx + 1;
                    end
                case "wrap"
                    obj.NextWaypointIdx(ueId) = mod(currentIdx, nWaypoints) + 1;
                otherwise
                    if nWaypoints == 1
                        obj.NextWaypointIdx(ueId) = 1;
                        obj.DirectionSign(ueId) = 1;
                        return;
                    end
                    direction = double(obj.DirectionSign(ueId));
                    if direction == 0
                        direction = 1;
                    end
                    nextIdx = currentIdx + direction;
                    if nextIdx > nWaypoints
                        direction = -1;
                        nextIdx = nWaypoints - 1;
                    elseif nextIdx < 1
                        direction = 1;
                        nextIdx = 2;
                    end
                    obj.DirectionSign(ueId) = direction;
                    obj.NextWaypointIdx(ueId) = nextIdx;
            end
        end
    end
end
