classdef (Abstract) MobilityModelBase < handle
%SIXGR.SCENARIO.MOBILITY.MOBILITYMODELBASE Base class for UE mobility models.
%
%   Mobility models update UE positions per TTI/slot. This base class defines
%   common properties (area, wrap-around) and the step() API.
%
%   NOTE: Handle classes are not intended for MATLAB Coder. For code
%   generation, export mobility to fixed-field structs and use function-only
%   updates (a separate "coder" path can be added later).
%
% See also:
%   sixgr.scenario.mobility.MobilityRandomWaypoint
%   sixgr.scenario.mobility.MobilityRMaMixedSpeed
%   sixgr.scenario.mobility.updatePositions

    properties
        Area_m (1,2) double = [2000 2000];   % [W H]
        WraparoundEnabled (1,1) logical = true;
    end

    methods
        function obj = MobilityModelBase(area_m, wrapEnabled)
            if nargin >= 1 && ~isempty(area_m)
                obj.Area_m = double(area_m(:).');
            end
            if nargin >= 2 && ~isempty(wrapEnabled)
                obj.WraparoundEnabled = logical(wrapEnabled);
            end
        end

        function ue = reset(obj, ue) %#ok<INUSD>
            %RESET Optional reset hook. Default is no-op.
            % Subclasses may override to initialize internal state.
        end

        function xy = applyWraparound(obj, xy)
            %APPLYWRAPAROUND Wrap positions into centered rectangle if enabled.
            if ~obj.WraparoundEnabled
                return;
            end
            W = obj.Area_m(1);
            H = obj.Area_m(2);
            xy(:,1) = localWrapCentered(xy(:,1), W);
            xy(:,2) = localWrapCentered(xy(:,2), H);
        end

        function [xy, heading_deg] = applyReflect(obj, xy, heading_deg)
            %APPLYREFLECT Reflect positions off boundaries if wrap-around disabled.
            W = obj.Area_m(1);
            H = obj.Area_m(2);
            xMin = -W/2; xMax = W/2;
            yMin = -H/2; yMax = H/2;

            % Reflect X
            hitL = xy(:,1) < xMin;
            hitR = xy(:,1) > xMax;
            xy(hitL,1) = xMin + (xMin - xy(hitL,1));
            xy(hitR,1) = xMax - (xy(hitR,1) - xMax);
            heading_deg(hitL | hitR) = mod(180 - heading_deg(hitL | hitR), 360);

            % Reflect Y
            hitB = xy(:,2) < yMin;
            hitT = xy(:,2) > yMax;
            xy(hitB,2) = yMin + (yMin - xy(hitB,2));
            xy(hitT,2) = yMax - (xy(hitT,2) - yMax);
            heading_deg(hitB | hitT) = mod(-heading_deg(hitB | hitT), 360);
        end
    end

    methods (Abstract)
        ue = step(obj, ue, dt_s)
    end
end

function x = localWrapCentered(x, L)
% Wrap into [-L/2, L/2)
x = x + L/2;
x = x - L*floor(x./L);
x = x - L/2;
end
