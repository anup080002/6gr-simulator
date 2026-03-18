function info = rngInit(seed, useParallel)
%RNGINIT Reproducible RNG initialization (supports serial and parallel pools).
%
%   info = sixgr.util.rngInit(1,true)
%
% Notes:
% - Sets global RNG for the client.
% - If a parallel pool exists (gcp), sets a different substream per worker.
% - Does NOT auto-start a pool (keeps selftests lightweight).

if nargin < 1 || isempty(seed)
    seed = 1;
end
if nargin < 2 || isempty(useParallel)
    useParallel = false;
end

seed = double(seed);

rng(seed, "twister");
info = struct();
info.seed = seed;
info.parallelConfigured = false;

if ~useParallel
    return;
end

if exist("gcp","file") ~= 2
    return;
end

pool = gcp("nocreate");
if isempty(pool)
    return;
end

try
    spmd
        s = RandStream("Threefry","Seed",seed);
        s.Substream = labindex;
        RandStream.setGlobalStream(s);
    end
    info.parallelConfigured = true;
catch
    % Best-effort: don't fail runs if RNG can't be configured on workers
    info.parallelConfigured = false;
end

end
