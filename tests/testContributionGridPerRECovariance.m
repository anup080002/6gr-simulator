function ok = testContributionGridPerRECovariance()
%TESTCONTRIBUTIONGRIDPERRCOVARIANCE Prove local spatial covariance authority.

setup6GRSimToolkit('Verbose', false);
if exist("nrCarrierConfig", "file") ~= 2 || exist("nrOFDMModulate", "file") ~= 2
    fprintf("testContributionGridPerRECovariance skipped (5G Toolbox unavailable).\n");
    ok = true;
    return;
end

carrier = nrCarrierConfig;
carrier.NCellID = 17;
carrier.SubcarrierSpacing = 30;
carrier.NSizeGrid = 4;
carrier.NSlot = 0;
nSC = 12 * carrier.NSizeGrid;
nSym = carrier.SymbolsPerSlot;
nRx = 2;

% Use eight REs in each of two PRBs in one OFDM symbol. The two PRBs have
% orthogonal interference directions. A single wideband covariance would
% mix them; the configured per-PRB estimator must preserve the distinction.
symbolOneBased = 4;
scPRB0 = (1:8).';
scPRB1 = (13:20).';
dataInd = [sub2ind([nSC nSym], scPRB0, repmat(symbolOneBased, 8, 1)); ...
           sub2ind([nSC nSym], scPRB1, repmat(symbolOneBased, 8, 1))];

grid = complex(zeros(nSC, nSym, nRx));
rs = RandStream("mt19937ar", "Seed", 8675309);
qpsk0 = (2 * (rand(rs, 8, 1) > 0.5) - 1 + ...
    1i * (2 * (rand(rs, 8, 1) > 0.5) - 1)) ./ sqrt(2);
qpsk1 = (2 * (rand(rs, 8, 1) > 0.5) - 1 + ...
    1i * (2 * (rand(rs, 8, 1) > 0.5) - 1)) ./ sqrt(2);
page1 = grid(:, :, 1);
page2 = grid(:, :, 2);
page1(dataInd(1:8)) = qpsk0;
page2(dataInd(9:16)) = qpsk1;
grid(:, :, 1) = page1;
grid(:, :, 2) = page2;

waveform = nrOFDMModulate(carrier, grid);
contributionTensor = reshape(waveform, size(waveform, 1), nRx, 1);
[Rint, info] = sixgr.phy.rx.estimateContributionGridCovariance( ...
    contributionTensor, carrier, dataInd, 0, ...
    "unit_test_oracle_separated_peer", "receiver_sample_waveform_pre_noise", ...
    "pusch", "FrequencyWindowPRBs", 1, "TimeWindowSymbols", 1, ...
    "ShrinkageFactor", 0, "MinimumSamples", 4);

assert(logical(info.Available) && logical(info.PerRECovariance), ...
    "Per-RE contribution covariance was not materialized: %s", string(info.NAReason));
assert(isequal(size(Rint), [16 2 2]), ...
    "Expected a 16-by-2-by-2 covariance tensor, got %s.", mat2str(size(Rint)));
assert(string(info.Source) == ...
    "oracle_separated_shared_slot_per_prb_symbol_contribution_grid_covariance", ...
    "Oracle-separated covariance must remain explicitly labeled.");

R0 = squeeze(mean(Rint(1:8, :, :), 1));
R1 = squeeze(mean(Rint(9:16, :, :), 1));
assert(real(R0(1,1)) > 0.9 && abs(R0(2,2)) < 1e-10, ...
    "PRB 0 covariance leaked into the orthogonal receive branch: %s", mat2str(R0));
assert(real(R1(2,2)) > 0.9 && abs(R1(1,1)) < 1e-10, ...
    "PRB 1 covariance leaked into the orthogonal receive branch: %s", mat2str(R1));

try
    sixgr.phy.rx.estimateContributionGridCovariance(contributionTensor, carrier, ...
        dataInd, 0, "unit_test", "receiver_sample_waveform_pre_noise", "pusch", ...
        "EstimatorMode", "wideband_shortcut");
    error("testContributionGridPerRECovariance:MissingEstimatorGuard", ...
        "Unsupported wideband estimator did not fail closed.");
catch ME
    assert(strcmp(ME.identifier, ...
        "sixgr:phy:rx:UnsupportedContributionCovarianceEstimator"), ...
        "Unexpected estimator guard failure: %s", ME.identifier);
end

fprintf("testContributionGridPerRECovariance passed: PRB-local orthogonal covariances preserved.\n");
ok = true;
end
