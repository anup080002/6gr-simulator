classdef AntennaPanel
    %ANTENNAPANEL Canonical panel, polarization, port, pose and calibration.

    properties (SetAccess = immutable)
        PanelID (1,1) string
        N1 (1,1) double
        N2 (1,1) double
        HorizontalSpacingLambda (1,1) double
        VerticalSpacingLambda (1,1) double
        Polarizations (1,:) string
        XPRdB (1,1) double
        LogicalPorts (1,:) double
        PhysicalElements (1,:) double
        PoseRotation (3,3) double
        Calibration
    end

    methods
        function obj = AntennaPanel(options)
            arguments
                options.PanelID (1,1) string = "panel-0"
                options.N1 (1,1) double {mustBeInteger,mustBePositive} = 2
                options.N2 (1,1) double {mustBeInteger,mustBePositive} = 1
                options.HorizontalSpacingLambda (1,1) double {mustBePositive} = 0.5
                options.VerticalSpacingLambda (1,1) double {mustBePositive} = 0.5
                options.Polarizations (1,:) string = "P0"
                options.XPRdB (1,1) double = 99
                options.LogicalPorts (1,:) double = []
                options.PhysicalElements (1,:) double = []
                options.PoseRotation (3,3) double = eye(3)
                options.Calibration = []
            end
            if options.N1 * options.N2 < 1 || ...
                    options.HorizontalSpacingLambda > 10 || ...
                    options.VerticalSpacingLambda > 10
                error("sixgr:mimo:InvalidPanelGeometry", ...
                    "Panel dimensions and spacing must be explicit and physical.");
            end
            pol = upper(string(options.Polarizations));
            if isempty(pol) || any(~ismember(pol, ["P0","P1","+45","-45","V","H"]))
                error("sixgr:mimo:InvalidPolarization", ...
                    "Polarization labels must be explicit P0/P1, +/-45, V, or H.");
            end
            if numel(pol) > 1 && ~(isfinite(options.XPRdB) && options.XPRdB >= 0)
                error("sixgr:mimo:InvalidPolarization", ...
                    "Dual-polarized panels require finite nonnegative XPRdB.");
            end
            nPorts = options.N1 * options.N2 * numel(pol);
            logicalPorts = options.LogicalPorts;
            if isempty(logicalPorts)
                logicalPorts = 3000 + (0:nPorts-1);
            end
            physical = options.PhysicalElements;
            if isempty(physical)
                physical = 0:nPorts-1;
            end
            localValidateMapping(logicalPorts, physical, nPorts);
            if norm(options.PoseRotation' * options.PoseRotation - eye(3), "fro") > 1e-10 || ...
                    det(options.PoseRotation) < 0
                error("sixgr:mimo:InvalidPanelGeometry", ...
                    "PoseRotation must be a proper orthonormal rotation.");
            end
            calibration = options.Calibration;
            if isempty(calibration)
                calibration = ones(nPorts, 1);
            end
            if ~isnumeric(calibration) || numel(calibration) ~= nPorts || ...
                    any(~isfinite(real(calibration(:))) | ~isfinite(imag(calibration(:))))
                error("sixgr:mimo:InvalidPortMapping", ...
                    "Calibration must contain one finite coefficient per port.");
            end

            obj.PanelID = options.PanelID;
            obj.N1 = options.N1;
            obj.N2 = options.N2;
            obj.HorizontalSpacingLambda = options.HorizontalSpacingLambda;
            obj.VerticalSpacingLambda = options.VerticalSpacingLambda;
            obj.Polarizations = pol;
            obj.XPRdB = options.XPRdB;
            obj.LogicalPorts = logicalPorts(:).';
            obj.PhysicalElements = physical(:).';
            obj.PoseRotation = options.PoseRotation;
            obj.Calibration = calibration(:);
        end

        function xyz = elementPositionsLambda(obj)
            [horizontal, vertical] = ndgrid(0:obj.N1-1, 0:obj.N2-1);
            base = [horizontal(:) .* obj.HorizontalSpacingLambda, ...
                    zeros(numel(horizontal),1), ...
                    vertical(:) .* obj.VerticalSpacingLambda];
            base = repmat(base, numel(obj.Polarizations), 1);
            xyz = (obj.PoseRotation * base.').';
        end

        function response = steeringResponse(obj, azimuthDeg, elevationDeg, polarization)
            arguments
                obj
                azimuthDeg (1,1) double
                elevationDeg (1,1) double
                polarization (1,1) string = "P0"
            end
            pol = upper(polarization);
            polIdx = find(obj.Polarizations == pol, 1);
            if isempty(polIdx)
                error("sixgr:mimo:InvalidPolarization", ...
                    "Polarization %s is not part of panel %s.", pol, obj.PanelID);
            end
            baseCount = obj.N1 * obj.N2;
            positions = obj.elementPositionsLambda();
            indices = (polIdx-1)*baseCount + (1:baseCount);
            positions = positions(indices,:);
            direction = [cosd(elevationDeg)*sind(azimuthDeg); ...
                         cosd(elevationDeg)*cosd(azimuthDeg); ...
                         sind(elevationDeg)];
            phase = 2*pi*(positions*direction);
            response = exp(1i*phase) ./ sqrt(baseCount);
            response = response .* obj.Calibration(indices);
            response = response ./ norm(response);
        end

        function mapping = portMapping(obj)
            n = numel(obj.LogicalPorts);
            pol = repmat(obj.Polarizations, obj.N1*obj.N2, 1);
            pol = pol(:);
            mapping = table(obj.LogicalPorts(:), obj.PhysicalElements(:), pol(1:n), ...
                repmat(obj.PanelID,n,1), ...
                'VariableNames', {'LogicalPort','PhysicalElement','Polarization','PanelID'});
        end
    end
end

function localValidateMapping(logicalPorts, physical, nPorts)
if numel(logicalPorts) ~= nPorts || numel(physical) ~= nPorts || ...
        numel(unique(double(logicalPorts))) ~= nPorts || ...
        numel(unique(double(physical))) ~= nPorts || ...
        any(~isfinite(double(logicalPorts))) || any(~isfinite(double(physical)))
    error("sixgr:mimo:InvalidPortMapping", ...
        "Logical-to-physical port mapping must be finite, complete and bijective.");
end
end
