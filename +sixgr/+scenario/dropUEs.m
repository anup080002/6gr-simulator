function ue = dropUEs(cfg, layout, scenarioName)
%SIXGR.SCENARIO.DROPUES Drop UEs in the scenario and assign indoor/speed profiles.
%
%   ue = sixgr.scenario.dropUEs(cfg, layout)
%   ue = sixgr.scenario.dropUEs(cfg, layout, scenarioName)
%
% Returns ue struct:
%   ue.K
%   ue.id
%   ue.pos_m         [K x 3]
%   ue.indoor        [K x 1] logical
%   ue.speed_kmh     [K x 1]
%   ue.heading_deg   [K x 1]
%
% This function is deterministic under cfg.run.seed (via rngInit).
%
% Fixes earlier config mismatches by supporting both:
%   cfg.scenario.ue.distribution.indoorFraction
%   cfg.scenario.ue.distribution.speeds_kmh
%
% See also: sixgr.scenario.generateLayout

arguments
    cfg struct
    layout struct
    scenarioName {mustBeTextScalar} = ""
end

prof = sixgr.scenario.ScenarioFactory.getProfile(cfg, scenarioName);

K = prof.ue.count;
W = prof.area_m(1);
H = prof.area_m(2);

% Uniform drop in centered rectangle ([-W/2,W/2] x [-H/2,H/2])
xy = [ (rand(K,1)-0.5)*W, (rand(K,1)-0.5)*H ];

% Heights
z = prof.ue.height_m * ones(K,1);

% Indoor/outdoor
indoorFrac = double(sixgr.util.structGet(prof, "ue.distribution.indoorFraction", 0.2));
indoor = rand(K,1) < indoorFrac;

% Speed distribution (km/h)
speeds = double(sixgr.util.structGet(prof, "ue.distribution.speeds_kmh", [3 30 120]));
p = double(sixgr.util.structGet(prof, "ue.distribution.speedProb", ones(1,numel(speeds))/numel(speeds)));
p = p(:).';
if numel(p) ~= numel(speeds)
    p = ones(1,numel(speeds))/numel(speeds);
end
p = p / sum(p);

speedIdx = localDiscreteSample(p, K);
speedKmh = speeds(speedIdx).';

% Heading (deg)
headingDeg = rand(K,1) * 360;

ue = struct();
ue.profileName = prof.name;
ue.K = K;
ue.id = (1:K).';
ue.pos_m = [xy z];
ue.indoor = indoor;
ue.speed_kmh = speedKmh;
ue.heading_deg = headingDeg;

end

% ---------------- Local helpers ----------------

function idx = localDiscreteSample(p, N)
% Sample N iid indices from categorical distribution p (row vector).
cdf = cumsum(p(:));
r = rand(N,1);
idx = zeros(N,1);
for i = 1:N
    idx(i) = find(r(i) <= cdf, 1, "first");
end
end
