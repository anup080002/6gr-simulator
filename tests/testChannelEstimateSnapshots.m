function testChannelEstimateSnapshots()
%TESTCHANNELESTIMATESNAPSHOTS Guard against coherent-grid cancellation.

% Two subcarriers carry equal-power channels with opposite phase.  A
% coherent average would return zero even though both REs contain a valid
% unit-power channel.
H = complex(zeros(2, 2, 1, 2));
H(1, 1, 1, :) = reshape([1 1], 1, 1, 1, 2);
H(2, 1, 1, :) = reshape([-1 1], 1, 1, 1, 2);
H(1, 2, 1, :) = reshape([2 2], 1, 1, 1, 2);
H(2, 2, 1, :) = reshape([-2 2], 1, 1, 1, 2);

snap = sixgr.mimo.channelEstimateSnapshots(H);
assert(isequal(size(snap), [1 2 4]), ...
    "Expected one Rx, two Tx ports, and four RE snapshots.");
assert(abs(mean(abs(snap(:)).^2) - 2.5) < 1e-12, ...
    "Snapshot conversion must preserve channel power.");

wSum = [1; 1] / sqrt(2);
wDiff = [1; -1] / sqrt(2);
pSum = sixgr.phy.dl.frequencySelectivePrecoderPower(snap, wSum);
pDiff = sixgr.phy.dl.frequencySelectivePrecoderPower(snap, wDiff);
assert(abs(pSum - 2.5) < 1e-12 && abs(pDiff - 2.5) < 1e-12, ...
    "Frequency-selective scoring must retain both nonzero beam powers.");

mask = logical([0 1; 0 0]);
masked = sixgr.mimo.channelEstimateSnapshots(H, "PilotMask", mask);
assert(isequal(size(masked), [1 2 2]), ...
    "Pilot-mask selection must retain only reference-bearing symbols.");
assert(norm(reshape(masked(1, :, 1), 1, []) - [2 2]) < 1e-12, ...
    "Pilot-mask symbol selection returned the wrong channel snapshots.");

fprintf('[PASS] Channel-estimate snapshot conversion preserves RE energy.\n');
end
