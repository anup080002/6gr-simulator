function maxIter = resolveLDPCMaxIterations(cfg, varargin)
%RESOLVELDPCMAXITERATIONS Resolve the runtime LDPC decoder iteration budget.
%
% NR does not specify a decoder implementation limit. Use a conformance-style
% receiver default of 50 iterations unless the resolved config explicitly asks
% for a higher value. Ultra-reliable study points automatically lift the floor.

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
    maxIter = max(configured, 50);
else
    maxIter = 50;
end

targetBLER = localResolveTargetBLER(cfg, opt.Direction);
if isfinite(targetBLER) && targetBLER > 0 && targetBLER < 1e-4
    maxIter = max(maxIter, 200);
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
