function identity=noiseTrialIdentity(seeds,point,trial,maximumTrials,preamblePresent)
%NOISETRIALIDENTITY Disjoint H0/H1 episode substreams, independent of batches.
% The frozen seed list, point order and cap are part of the campaign identity.
% RandStream substreams, not sums of seeds, separate noise realizations:
% https://www.mathworks.com/help/matlab/ref/randstream.html
validateattributes(seeds,{'numeric'},{'real','finite','integer','vector','nonempty','>=',0,'<=',2^32-1});
validateattributes(point,{'numeric'},{'real','finite','integer','scalar','positive'});
validateattributes(maximumTrials,{'numeric'},{'real','finite','integer','scalar','positive'});
validateattributes(trial,{'numeric'},{'real','finite','integer','scalar','>=',1,'<=',maximumTrials});
validateattributes(preamblePresent,{'logical','numeric'},{'scalar','binary'});
assert(numel(unique(seeds))==numel(seeds),'sixgr:phy:prach:DuplicateNoiseSeeds', ...
    'Declare distinct deterministic seed families.');
assert(point<=floor(flintmax/2),'sixgr:phy:prach:NoiseSubstreamOverflow', ...
    'Point identity must be exactly representable.');
populationPoint=2*(double(point)-1)+double(preamblePresent)+1;
assert(populationPoint-1<=floor((flintmax-double(trial))/double(maximumTrials)), ...
    'sixgr:phy:prach:NoiseSubstreamOverflow','Episode identity must be exactly representable.');
episode=(populationPoint-1)*double(maximumTrials)+double(trial);
family=double(seeds(mod(trial-1,numel(seeds))+1));
stride=max(double(seeds))+1;
assert(episode-1<=floor((flintmax-family-1)/stride), ...
    'sixgr:phy:prach:NoiseSubstreamOverflow','Substream identity must be exactly representable.');
identity=struct('Seed',double(seeds(1)),'Substream',(episode-1)*stride+family+1, ...
    'Generator',"Threefry",'NormalTransform',"Inversion",'Episode',episode, ...
    'Point',double(point),'Trial',double(trial),'MaximumTrials',double(maximumTrials), ...
    'PreamblePresent',logical(preamblePresent));
end
