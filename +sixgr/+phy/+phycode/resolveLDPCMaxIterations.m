function maxIter = resolveLDPCMaxIterations(cfg, varargin)
%RESOLVELDPCMAXITERATIONS Resolve the runtime LDPC decoder iteration budget.
%
% NR does not specify a decoder implementation limit. Use a conformance-style
% receiver default of 50 iterations when the scenario does not configure one.
% If the scenario configures a decoder budget, keep it authoritative instead
% of silently mutating the receiver implementation.

opt = struct("Direction", "");
for i = 1:2:numel(varargin)
    if i + 1 > numel(varargin)
        break;
    end
    key = lower(strtrim(string(varargin{i})));
    switch key
        case "direction"
            opt.Direction = upper(strtrim(string(varargin{i + 1})));
    end
end

configured = localFirstFiniteScalar( ...
    sixgr.util.structGet(cfg, "phy.ldpc.maxIterations", []), ...
    sixgr.util.structGet(cfg, "phy.ldpc.maxNumIter", []), ...
    sixgr.util.structGet(cfg, "phy.ldpc.maxIter", []));
if isfinite(configured)
    maxIter = configured;
else
    maxIter = 50;
end

targetBLER = localResolveTargetBLER(cfg, opt.Direction);
if ~isfinite(configured) && isfinite(targetBLER) && targetBLER > 0 && targetBLER < 1e-4
    maxIter = max(maxIter, 200);
end

fadingFloor = localResolveFadingIterationFloor(cfg);
if ~isfinite(configured) && isfinite(fadingFloor) && fadingFloor > 0 && localIsConcreteFadingChannel(cfg)
    maxIter = max(maxIter, fadingFloor);
end

maxIter = max(1, round(double(maxIter)));
end

function target = localResolveTargetBLER(cfg, direction)
target = localFirstFiniteScalar( ...
    sixgr.util.structGet(cfg, "phy.ldpc.targetBLER", []), ...
    sixgr.util.structGet(cfg, "phy.linkAdaptation.targetBLER", []), ...
    sixgr.util.structGet(cfg, "phy.csi.targetBLER", []));
if upper(string(direction)) == "UL"
    target = localFirstFiniteScalar( ...
        sixgr.util.structGet(cfg, "phy.pusch.targetBLER", []), target);
else
    target = localFirstFiniteScalar( ...
        sixgr.util.structGet(cfg, "phy.pdsch.targetBLER", []), target);
end
end

function value = localResolveFadingIterationFloor(cfg)
value = localFirstFiniteScalar( ...
    sixgr.util.structGet(cfg, "phy.ldpc.fadingMinIterations", []), ...
    sixgr.util.structGet(cfg, "phy.ldpc.fadingMinDecoderIterations", []), ...
    sixgr.util.structGet(cfg, "coding.fading_min_decoder_iterations", []));
if ~isfinite(value)
    value = 100;
end
end

function tf = localIsConcreteFadingChannel(cfg)
model = upper(strtrim(string(sixgr.util.structGet(cfg, "channel.model", ""))));
delayProfile = upper(strtrim(string(sixgr.util.structGet(cfg, "channel.delayProfile", ""))));
tdlProfile = upper(strtrim(string(sixgr.util.structGet(cfg, "channel.tdlProfile", ""))));
cdlProfile = upper(strtrim(string(sixgr.util.structGet(cfg, "channel.cdlProfile", ""))));
fadingProfile = upper(strtrim(string(sixgr.util.structGet(cfg, "channel.fading.profile", ""))));
fadingModel = upper(strtrim(string(sixgr.util.structGet(cfg, "channel.fading.model", ""))));
tf = startsWith(model, "TDL-") || startsWith(model, "CDL-") || ...
    startsWith(delayProfile, "TDL-") || startsWith(delayProfile, "CDL-") || ...
    startsWith(tdlProfile, "TDL-") || startsWith(cdlProfile, "CDL-") || ...
    startsWith(fadingProfile, "TDL-") || startsWith(fadingProfile, "CDL-") || ...
    ((fadingModel == "TDL" || fadingModel == "CDL") && ...
    (startsWith(tdlProfile, "TDL-") || startsWith(cdlProfile, "CDL-") || ...
    startsWith(fadingProfile, "TDL-") || startsWith(fadingProfile, "CDL-")));
end

function value = localFirstFiniteScalar(varargin)
value = NaN;
for i = 1:numel(varargin)
    raw = varargin{i};
    if isempty(raw)
        continue;
    end
    try
        v = double(raw);
    catch
        continue;
    end
    v = v(isfinite(v));
    if ~isempty(v)
        value = v(1);
        return;
    end
end
end
