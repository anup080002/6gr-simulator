function topology = buildTopology(scenario)
%BUILDTOPOLOGY Build an exact spherical-Earth circular LEO service pass.
%
% The service terminal is the local reference point.  The circular orbit is
% propagated in its pass plane with closest approach at the YAML-selected
% time.  Range, range rate, elevation, one-way latency and Doppler all come
% from the same position/velocity samples; none are independently invented.

arguments
    scenario (1,1) struct
end

cfg = scenario.ntn_topology;
R = double(scenario.geometry.earth_radius_km)*1e3;
h = double(cfg.satellite.altitude_m);
mu = double(scenario.geometry.gravitational_parameter_m3_s2);
c = double(scenario.geometry.speed_of_light_m_s);
earthRate = double(scenario.geometry.earth_rotation_rate_rad_s);
fc = double(cfg.link_budget.carrier_frequency_hz);
sampleTime = double(cfg.sample_time_s);
duration = double(cfg.duration_s);
times = (0:sampleTime:duration).';
if times(end) < duration
    times(end+1,1) = duration;
end
tca = double(cfg.closest_approach_time_s);
if tca < 0 || tca > duration
    error("sixgr:ntn:resilientsync:InvalidClosestApproachTime", ...
        "Closest approach must lie inside the configured topology interval.");
end

ueRadius = R+double(cfg.service_ue.altitude_m);
latitude=deg2rad(double(cfg.service_ue.latitude_deg));
longitude=deg2rad(double(cfg.service_ue.longitude_deg));
up=[cos(latitude)*cos(longitude) cos(latitude)*sin(longitude) sin(latitude)];
east=[-sin(longitude) cos(longitude) 0];
north=cross(up,east); north=north./norm(north);
elevationAtTCA=deg2rad(double(cfg.closest_approach_elevation_deg));
orbitRadius=R+h;
rangeAtTCA=-ueRadius*sin(elevationAtTCA)+sqrt( ...
    orbitRadius^2-ueRadius^2*cos(elevationAtTCA)^2);
ueAtTCA=ueRadius*up;
satelliteAtTCA=ueAtTCA+rangeAtTCA*(sin(elevationAtTCA)*up+ ...
    cos(elevationAtTCA)*north);
% The along-track direction is east at closest approach, orthogonal to the
% cross-track range vector.  Earth rotation is included independently for
% each Earth-fixed endpoint below.
satelliteVelocityAtTCA=sqrt(mu/orbitRadius)*east;
omega = sqrt(mu/orbitRadius^3);
propagated = sixgr.ntn.resilientsync.geometry.propagateCircularOrbit( ...
    satelliteAtTCA,satelliteVelocityAtTCA, ...
    times-tca,mu);
satellitePosition = propagated.PositionECEF_m;
satelliteVelocity = propagated.VelocityECEF_m_s;
[uePosition,ueVelocity]=localGroundState(cfg.service_ue,R,earthRate,times-tca);
slant = sixgr.ntn.resilientsync.geometry.slantRangeAndRate( ...
    satellitePosition,satelliteVelocity,uePosition,ueVelocity);
up = uePosition./sqrt(sum(uePosition.^2,2));
elevation = asind(sum(slant.LOSUnitVector.*up,2));
delay = slant.Range_m/c;
% Positive Doppler denotes an approaching satellite (decreasing range).
doppler = -slant.RangeRate_m_s*fc/c;
dopplerRate = gradient(doppler,times);
access = elevation >= double(cfg.access.minimum_elevation_deg);
[gatewayPosition,gatewayVelocity]=localGroundState(cfg.gateway,R,earthRate,times-tca);
gatewaySlant=sixgr.ntn.resilientsync.geometry.slantRangeAndRate( ...
    satellitePosition,satelliteVelocity,gatewayPosition,gatewayVelocity);
gatewayUp=gatewayPosition./sqrt(sum(gatewayPosition.^2,2));
gatewayElevation=asind(sum(gatewaySlant.LOSUnitVector.*gatewayUp,2));
gatewayAccess=gatewayElevation>=double(cfg.gateway.minimum_elevation_deg);

state = table;
state.Time_s = times;
state.SatelliteX_m = satellitePosition(:,1);
state.SatelliteY_m = satellitePosition(:,2);
state.SatelliteZ_m = satellitePosition(:,3);
state.SatelliteVx_m_s = satelliteVelocity(:,1);
state.SatelliteVy_m_s = satelliteVelocity(:,2);
state.SatelliteVz_m_s = satelliteVelocity(:,3);
state.ServiceUEX_m = uePosition(:,1);
state.ServiceUEY_m = uePosition(:,2);
state.ServiceUEZ_m = uePosition(:,3);
state.ElevationDeg = elevation;
state.SlantRange_m = slant.Range_m;
state.RangeRate_m_s = slant.RangeRate_m_s;
state.OneWayLatency_s = delay;
state.DopplerShiftHz = doppler;
state.DopplerRateHz_s = dopplerRate;
state.Access = access;
state.GatewayElevationDeg = gatewayElevation;
state.GatewaySlantRange_m = gatewaySlant.Range_m;
state.GatewayOneWayLatency_s = gatewaySlant.Range_m/c;
state.GatewayDopplerShiftHz = -gatewaySlant.RangeRate_m_s*fc/c;
state.GatewayAccess = gatewayAccess;
state.GeometryModel = repmat(string(cfg.geometry_model),height(state),1);
state.EvidenceClass = repmat("ANALYTICAL",height(state),1);

endpoints = table( ...
    [string(cfg.satellite.id);string(cfg.gateway.id);string(cfg.service_ue.id)], ...
    ["satellite";"gateway_ground_station";"service_ue_ground_terminal"], ...
    [NaN;double(cfg.gateway.latitude_deg);double(cfg.service_ue.latitude_deg)], ...
    [NaN;double(cfg.gateway.longitude_deg);double(cfg.service_ue.longitude_deg)], ...
    [h;double(cfg.gateway.altitude_m);double(cfg.service_ue.altitude_m)], ...
    [string(cfg.satellite.antenna_binding);string(cfg.gateway.feeder_antenna_model);string(cfg.service_ue.antenna_binding)], ...
    'VariableNames',{'EndpointId','EndpointType','LatitudeDeg','LongitudeDeg', ...
    'AltitudeM','AntennaBinding'});

topology = struct( ...
    "StateTable",state, ...
    "AccessIntervals",[ ...
        localAccessIntervals(times,access,elevation,string(cfg.service_ue.id)); ...
        localAccessIntervals(times,gatewayAccess,gatewayElevation,string(cfg.gateway.id))], ...
    "EndpointTable",endpoints, ...
    "AngularRateRad_s",omega, ...
    "OrbitalSpeedM_s",orbitRadius*omega, ...
    "Source","same_state_position_velocity_geometry", ...
    "EvidenceClass","ANALYTICAL");
end

function intervals = localAccessIntervals(times,mask,elevation,endpointId)
starts = find(mask & [true;~mask(1:end-1)]);
stops = find(mask & [~mask(2:end);true]);
if isempty(starts)
    intervals = table('Size',[0 7], ...
        'VariableTypes',{'string','double','double','double','double','double','string'}, ...
        'VariableNames',{'EndpointId','IntervalNumber','StartTime_s','EndTime_s','Duration_s', ...
        'PeakElevationDeg','EvidenceClass'});
    return;
end
n = numel(starts);
peak = zeros(n,1);
for index=1:n
    peak(index)=max(elevation(starts(index):stops(index)));
end
intervals = table(repmat(endpointId,n,1),(1:n).',times(starts),times(stops), ...
    times(stops)-times(starts),peak,repmat("ANALYTICAL",n,1), ...
    'VariableNames',{'EndpointId','IntervalNumber','StartTime_s','EndTime_s','Duration_s', ...
    'PeakElevationDeg','EvidenceClass'});
end

function [position,velocity]=localGroundState(endpoint,R,earthRate,relativeTime)
radius=R+double(endpoint.altitude_m);
latitude=deg2rad(double(endpoint.latitude_deg));
longitude0=deg2rad(double(endpoint.longitude_deg));
longitude=longitude0+earthRate*relativeTime(:);
position=[radius*cos(latitude).*cos(longitude), ...
    radius*cos(latitude).*sin(longitude),repmat(radius*sin(latitude),numel(longitude),1)];
velocity=[-earthRate*position(:,2),earthRate*position(:,1),zeros(numel(longitude),1)];
end
