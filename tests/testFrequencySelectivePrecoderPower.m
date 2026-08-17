function ok = testFrequencySelectivePrecoderPower()
%TESTFREQUENCYSELECTIVEPRECODERPOWER Guard rank>1 PMI scoring semantics.

H = complex(zeros(2, 2, 2));
H(:,:,1) = [1 2; 3 4];
H(:,:,2) = [2 0; 0 1];
W = eye(2) ./ sqrt(2);

observed = sixgr.phy.dl.frequencySelectivePrecoderPower(H, W);
expected = 0;
for snapshot = 1:size(H, 3)
    projected = H(:,:,snapshot) * W;
    expected = expected + sum(abs(projected(:)).^2);
end
expected = expected / (size(H, 3) * size(W, 2));
assert(isscalar(observed) && abs(observed - expected) < 1e-12, ...
    "Rank-2 PMI scoring must return one total-power-per-layer scalar per candidate.");

assertThrows(@() sixgr.phy.dl.frequencySelectivePrecoderPower(H, ones(3, 1)), ...
    "sixgr:phy:dl:FrequencySelectivePrecoderDimensionMismatch");

ok = true;
end

function assertThrows(fn, expectedIdentifier)
threw = false;
try
    fn();
catch ME
    threw = true;
    assert(strcmp(ME.identifier, expectedIdentifier), ...
        "Expected error %s, observed %s.", expectedIdentifier, ME.identifier);
end
assert(threw, "Expected error %s was not thrown.", expectedIdentifier);
end
