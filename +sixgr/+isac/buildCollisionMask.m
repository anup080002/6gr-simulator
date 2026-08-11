function mask = buildCollisionMask(configuredMask,profile,ratioPercent,seed)
%BUILDCOLLISIONMASK Build an exact-count, YAML-selected collision mask.

arguments
    configuredMask logical
    profile (1,1) string
    ratioPercent (1,1) double {mustBeFinite,mustBeGreaterThanOrEqual(ratioPercent,0),mustBeLessThanOrEqual(ratioPercent,100)}
    seed (1,1) double {mustBeFinite}
end
profile=lower(strtrim(profile));
active=find(configuredMask);
nSelect=round(numel(active)*ratioPercent/100);
mask=false(size(configuredMask));
if nSelect==0, return; end

prior=rng; cleanup=onCleanup(@() rng(prior)); %#ok<NASGU>
rng(round(seed),"twister");
[activeRows,activeCols]=find(configuredMask);
switch profile
    case "random_isolated"
        order=randperm(numel(active));
    case "contiguous_time"
        center=activeCols(randi(numel(activeCols)));
        score=abs(activeCols-center)+1e-6*rand(size(activeCols));
        [~,order]=sort(score,"ascend");
    case "contiguous_frequency"
        center=activeRows(randi(numel(activeRows)));
        score=abs(activeRows-center)+1e-6*rand(size(activeRows));
        [~,order]=sort(score,"ascend");
    case "rectangular_tf"
        rowCenter=activeRows(randi(numel(activeRows)));
        colCenter=activeCols(randi(numel(activeCols)));
        rowScale=max(1,max(activeRows)-min(activeRows));
        colScale=max(1,max(activeCols)-min(activeCols));
        score=((activeRows-rowCenter)/rowScale).^2+ ...
            ((activeCols-colCenter)/colScale).^2+1e-6*rand(size(activeRows));
        [~,order]=sort(score,"ascend");
    case "periodic_rs"
        stride=max(1,round(numel(active)/nSelect));
        start=randi(stride);
        periodic=start:stride:numel(active);
        remainder=setdiff(1:numel(active),periodic,"stable");
        order=[periodic,remainder];
    otherwise
        error("sixgr:isac:UnsupportedCollisionMaskProfile", ...
            "Unsupported collision mask profile %s.",profile);
end
mask(active(order(1:nSelect)))=true;
end
