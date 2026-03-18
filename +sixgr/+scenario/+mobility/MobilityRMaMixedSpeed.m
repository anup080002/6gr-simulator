classdef MobilityRMaMixedSpeed < sixgr.scenario.mobility.MobilityModelBase
%SIXGR.SCENARIO.MOBILITY.MOBILITYRMAMIXEDSPEED Rural macro mixed-speed mobility.
%
% A simple mixed-speed model often used for RMa stress:
%   - Indoor/slow UEs (typically ~3 km/h) move slowly with random headings.
%   - Outdoor/vehicular UEs (typically ~120 km/h) move with constant heading.
%
% This class assumes ue.indoor and ue.speed_kmh are already assigned by
% sixgr.scenario.dropUEs().
%
% UE fields updated:
%   ue.pos_m(:,1:2)
%   ue.heading_deg
%
% See also: sixgr.scenario.mobility.updatePositions

    methods
        function obj = MobilityRMaMixedSpeed(area_m, wrapEnabled)
            obj@sixgr.scenario.mobility.MobilityModelBase(area_m, wrapEnabled);
        end

        function ue = reset(~, ue)
            % Randomize initial headings (deg) if not present
            if ~isfield(ue, "heading_deg") || numel(ue.heading_deg) ~= ue.K
                ue.heading_deg = rand(ue.K,1) * 360;
            end
        end

        function ue = step(obj, ue, dt_s)
            if ~isfield(ue, "heading_deg") || numel(ue.heading_deg) ~= ue.K
                ue = reset(obj, ue);
            end

            xy = ue.pos_m(:,1:2);

            v_mps = (ue.speed_kmh(:) ./ 3.6);
            hd = ue.heading_deg(:);
            dx = v_mps .* cosd(hd) * dt_s;
            dy = v_mps .* sind(hd) * dt_s;

            % Indoor UEs: add small random heading jitter to avoid perfectly straight lines
            if isfield(ue, "indoor")
                ind = logical(ue.indoor(:));
                jitter = zeros(ue.K,1);
                jitter(ind) = (rand(nnz(ind),1)-0.5) * 10; % +/-5 deg per step
                hd = mod(hd + jitter, 360);
                ue.heading_deg = hd;
                dx = v_mps .* cosd(hd) * dt_s;
                dy = v_mps .* sind(hd) * dt_s;
            end

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
