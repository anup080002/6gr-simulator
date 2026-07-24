function ok = testFRCFadingSNRNormalization()
%TESTFRCFADINGSNRNORMALIZATION Guard summed-connector FRC SNR semantics.

setup6GRSimToolkit("AddSubfolders", false, "Verbose", false, ...
    "RunToolboxChecks", false);
if exist("nrTDLChannel", "class") ~= 8
    warning("testFRCFadingSNRNormalization:Missing5G", ...
        "Skipping because nrTDLChannel is unavailable.");
    ok = true;
    return;
end

probe = nrTDLChannel;
if ~isprop(probe, "NormalizePathGains") || ...
        ~isprop(probe, "NormalizeChannelOutputs")
    warning("testFRCFadingSNRNormalization:UnsupportedRelease", ...
        "Skipping because this nrTDLChannel lacks the required normalization properties.");
    ok = true;
    return;
end
release(probe);

runnerPath = which("sixgr.conformance.runFRCPoint");
assert(strlength(string(runnerPath)) > 0, ...
    "The FRC runner must be discoverable on the MATLAB path.");
runnerSource = fileread(runnerPath);
assert(~isempty(regexp(runnerSource, ...
    "NormalizePathGains\s*=\s*true", "once")), ...
    "The FRC fading path must retain normalized TDL path gains.");
assert(~isempty(regexp(runnerSource, ...
    "NormalizeChannelOutputs\s*=\s*false", "once")), ...
    ["The FRC fading path must disable nrTDLChannel output normalization " ...
    "to preserve summed receive-connector SNR."]);

numRx = 2;
numSeeds = 20;
burnIn = 512;
numMeasured = 16384;
rng(381041, "twister");
x = complex(randn(burnIn + numMeasured, 1), ...
    randn(burnIn + numMeasured, 1)) ./ sqrt(2);
inputPower = mean(abs(x(burnIn + 1:end)).^2, "all");
preserved = zeros(numSeeds, 1);
legacyNormalized = zeros(numSeeds, 1);

for seedIndex = 1:numSeeds
    channelSeed = 38000 + seedIndex;
    yPreserved = localRunTDL(x, numRx, channelSeed, false);
    yLegacy = localRunTDL(x, numRx, channelSeed, true);
    preserved(seedIndex) = sum(mean( ...
        abs(yPreserved(burnIn + 1:end, :)).^2, 1), "all") ./ inputPower;
    legacyNormalized(seedIndex) = sum(mean( ...
        abs(yLegacy(burnIn + 1:end, :)).^2, 1), "all") ./ inputPower;
end

meanPreserved = mean(preserved);
meanLegacy = mean(legacyNormalized);
legacyLoss_dB = 10 * log10(meanPreserved / meanLegacy);

assert(abs(meanPreserved - numRx) <= 0.35 * numRx, ...
    ["With NormalizePathGains=true and NormalizeChannelOutputs=false, " ...
    "summed receive power must average to NRx=%d; measured %.6g."], ...
    numRx, meanPreserved);
assert(abs(meanLegacy - 1) <= 0.35, ...
    ["The legacy normalized-output control should average to unit summed " ...
    "power; measured %.6g."], meanLegacy);
assert(abs(legacyLoss_dB - 10 * log10(numRx)) <= 0.10, ...
    ["The regression must expose the old -10*log10(NRx) SNR shift; " ...
    "measured %.6g dB for NRx=%d."], legacyLoss_dB, numRx);

fprintf( ...
    "FRCFadingSNRNormalization: sum-Rx power %.4f (preserved) vs %.4f " + ...
    "(legacy normalized), old loss %.4f dB across %d seeds.\n", ...
    meanPreserved, meanLegacy, legacyLoss_dB, numSeeds);
ok = true;
end

function y = localRunTDL(x, numRx, seed, normalizeOutputs)
channel = nrTDLChannel;
channel.DelayProfile = "TDL-A";
channel.DelaySpread = 30e-9;
channel.MaximumDopplerShift = 0;
channel.SampleRate = 7.68e6;
channel.NumTransmitAntennas = 1;
channel.NumReceiveAntennas = numRx;
channel.MIMOCorrelation = "Low";
channel.NormalizePathGains = true;
channel.NormalizeChannelOutputs = logical(normalizeOutputs);
channel.RandomStream = "mt19937ar with seed";
channel.Seed = seed;
y = channel(x);
release(channel);
end
