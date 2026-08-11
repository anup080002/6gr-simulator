function state = propagateCircularOrbit(initialPositionM, initialVelocityMps, timesS, mu)
%PROPAGATECIRCULARORBIT Analytic two-body circular-orbit propagation.

arguments
    initialPositionM (1,3) double
    initialVelocityMps (1,3) double
    timesS (:,1) double
    mu (1,1) double {mustBePositive,mustBeFinite} = 3.986004418e14
end
r = norm(initialPositionM);
if abs(dot(initialPositionM, initialVelocityMps)) > 1e-6 * r * norm(initialVelocityMps)
    error("sixgr:ntn:resilientsync:NonCircularInitialState", ...
        "Circular propagation requires position and velocity to be orthogonal.");
end
omega = sqrt(mu / r^3);
e1 = initialPositionM ./ r;
e2 = initialVelocityMps ./ norm(initialVelocityMps);
phase = omega .* timesS(:);
position = r .* (cos(phase) .* e1 + sin(phase) .* e2);
velocity = r .* omega .* (-sin(phase) .* e1 + cos(phase) .* e2);
state = struct("Time_s", timesS(:), "PositionECEF_m", position, ...
    "VelocityECEF_m_s", velocity, "AngularRate_rad_s", omega, ...
    "Model", "analytical_circular_two_body");
end
