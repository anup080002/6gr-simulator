function [bits,noise,channel]=resolveExplicitSeeds(plan,bits,noise,channel)
% Explicit disjoint stream IDs for a population campaign; legacy unchanged.
if isempty(fieldnames(plan)), return; end
assert(isequal(sort(string(fieldnames(plan))),sort(["Bits";"Noise";"Channel"])), ...
    'sixgr:calibration:Seeds','Supply exactly Bits, Noise and Channel stream seeds.');
v=[plan.Bits plan.Noise plan.Channel];
validateattributes(v,{'numeric'},{'integer','nonnegative','finite','<',2^32,'numel',3});
assert(numel(unique(v))==3,'sixgr:calibration:Seeds','Bit, noise and channel streams must differ.');
bits=double(plan.Bits); noise=double(plan.Noise); channel=double(plan.Channel);
end
