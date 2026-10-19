function identity=noiseTrialIdentity(seeds,point,trial,maximumTrials)
%NOISETRIALIDENTITY Injective waveform-episode identity, not additive seeds.
validateattributes(seeds,{'numeric'},{'real','finite','integer','vector','nonempty','>=',0,'<=',2^32-1});
validateattributes(point,{'numeric'},{'real','finite','integer','scalar','positive'});
validateattributes(maximumTrials,{'numeric'},{'real','finite','integer','scalar','positive'});
validateattributes(trial,{'numeric'},{'real','finite','integer','scalar','>=',1,'<=',maximumTrials});
assert(numel(unique(seeds))==numel(seeds), ...
    'sixgr:phy:pdcch:DuplicateNoiseSeeds','Declare distinct seed families.');
assert(double(point)-1<=floor((flintmax-double(trial))/double(maximumTrials)), ...
    'sixgr:phy:pdcch:NoiseSubstreamOverflow','Episode substream identity must be exactly representable.');
episode=(double(point)-1)*double(maximumTrials)+double(trial);
family=double(seeds(mod(trial-1,numel(seeds))+1));
stride=max(double(seeds))+1;
assert(episode-1<=floor((flintmax-family-1)/stride), ...
    'sixgr:phy:pdcch:NoiseSubstreamOverflow','Episode substream identity must be exactly representable.');
% Use disjoint substreams of ONE seeded generator. Different seeds alone
% do not establish nonoverlapping streams. Each episode owns a disjoint
% block of stride substreams; the configured family selects within it.
substream=(episode-1)*stride+family+1;
identity=struct('Seed',double(seeds(1)), ...
    'Substream',substream,'Generator',"Threefry");
end
