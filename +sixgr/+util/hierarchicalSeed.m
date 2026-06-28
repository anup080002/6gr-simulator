function seed = hierarchicalSeed(baseSeed, pointIndex, dropIndex, trialIndex, linkToken)
%HIERARCHICALSEED Deterministic seed for campaign point/drop/trial/link units.
% The arithmetic is intentionally integer-only and independent of worker order.

if nargin < 5 || strlength(string(linkToken)) == 0
    linkToken = "TASK";
end

baseSeed = double(baseSeed);
if ~(isfinite(baseSeed) && baseSeed >= 0)
    baseSeed = 1;
end

pointIndex = localFiniteInteger(pointIndex, 0);
dropIndex = localFiniteInteger(dropIndex, 0);
trialIndex = localFiniteInteger(trialIndex, 0);
token = char(upper(string(linkToken)));

linkHash = 0;
modulus = 2^31 - 1;
for i = 1:numel(token)
    linkHash = mod(linkHash * 131 + double(token(i)), modulus);
end

seed = mod(round(baseSeed) + pointIndex * 1000003 + ...
    dropIndex * 9176 + trialIndex * 131071 + linkHash * 8191, modulus);
if seed <= 0
    seed = seed + 1;
end
seed = double(seed);
end

function value = localFiniteInteger(value, defaultValue)
value = double(value);
if ~(isfinite(value) && isscalar(value))
    value = double(defaultValue);
end
value = round(value);
end
