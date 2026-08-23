function ok = testReceivedOccupiedREENoiseReference()
%TESTRECEIVEDOCCUPIEDRENOISEREFERENCE Guard the post-channel Es plane.

setup6GRSimToolkit('Verbose', false);
carrier = nrCarrierConfig;
carrier.NSizeGrid = 25;
carrier.SubcarrierSpacing = 15;
carrier.CyclicPrefix = 'normal';

grid = nrResourceGrid(carrier, 2);
subcarriers = (7:12:(12 * carrier.NSizeGrid - 5)).';
symbols = [3 9];
indices = zeros(numel(subcarriers) * numel(symbols) * 2, 1);
cursor = 0;
for port = 1:2
    for symbol = symbols
        n = numel(subcarriers);
        indices(cursor + (1:n)) = sub2ind(size(grid), subcarriers, ...
            repmat(symbol, n, 1), repmat(port, n, 1));
        cursor = cursor + n;
    end
end
grid(indices) = exp(1j * (0:numel(indices)-1).' * pi / 7);
waveform = nrOFDMModulate(carrier, grid);

pathGain = 10^(-83 / 20);
rxReference = [waveform(:, 1) .* pathGain, ...
    waveform(:, 2) .* pathGain .* exp(1j * pi / 5)];
[measured, evidence] = sixgr.phy.waveform.measureReceivedOccupiedREEnergy( ...
    carrier, rxReference, indices, "SignalFamily", "regression");
expected = pathGain.^2;
assert(abs(measured - expected) <= max(1e-14, expected * 1e-10), ...
    'Received occupied-RE energy did not include the applied path gain.');
assert(string(evidence.MeasurementPlane) == ...
    "noiseless_received_resource_grid_post_channel_post_large_scale_pre_noise", ...
    'Received occupied-RE measurement plane was not explicit.');
assert(double(evidence.ReceiveBranchCount) == 2 && ...
    double(evidence.UniqueTimeFrequencyRECount) == ...
    numel(subcarriers) * numel(symbols), ...
    'Occupied-RE port collapse or receive-branch accounting is incorrect.');
ok = true;
end
