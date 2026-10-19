function ok = testPDCCHFalseAlarmSweep()
setup6GRSimToolkit("Verbose", false);
seeds=[240617 240629 240643 240647];
identities=zeros(3000,2); draws=zeros(3000,4);
for point=1:3
    for episode=1:1000
        id=sixgr.phy.pdcch.noiseTrialIdentity(seeds,point,episode,1000);
        k=(point-1)*1000+episode;
        identities(k,:)=[id.Seed id.Substream];
        stream=RandStream(char(id.Generator),'Seed',id.Seed); stream.Substream=id.Substream;
        draws(k,:)=randn(stream,1,4);
    end
end
assert(size(unique(identities,'rows'),1)==3000 && size(unique(draws,'rows'),1)==3000, ...
    'Noise-only episodes must never reuse a seed/substream realization.');
assert(all(identities(:,1)==seeds(1)) && numel(unique(identities(:,2)))==3000, ...
    'Nonoverlap must use disjoint substreams of one seeded generator, not different seeds.');
repeat=sixgr.phy.pdcch.noiseTrialIdentity(seeds,1,22,1000);
stream=RandStream(char(repeat.Generator),'Seed',repeat.Seed); stream.Substream=repeat.Substream;
assert(isequal(randn(stream,1,4),draws(22,:)),'Episode replay must be deterministic.');
edge=sixgr.phy.pdcch.noiseTrialIdentity([0 2^32-1],1,2,1000);
assert(edge.Seed==0 && edge.Substream==2^33);
try
    sixgr.phy.pdcch.noiseTrialIdentity(seeds,flintmax,2,1000);
    error('test:ExpectedOverflow','A rounded episode identity must not be accepted.');
catch cause
    assert(string(cause.identifier)=="sixgr:phy:pdcch:NoiseSubstreamOverflow");
end
b = pdcchStrictAnchorResult();
T = b.Result.ArtifactTables.pdcch_false_alarm_sweep;
assert(height(T) >= 3, "Strict PDCCH false-alarm sweep must cover multiple SNR points.");
assert(all(double(T.NumTrials) >= 2), "False-alarm sweep must use repeated noise-only trials.");
assert(all(double(T.FalseAlarmProbability) >= 0 & double(T.FalseAlarmProbability) <= 1), ...
    "False-alarm probabilities must be bounded.");
required = ["CandidateDecisionCount","CILower","CIUpper","CIWidth", ...
    "ConfidenceLevel","StatisticalQualification","StatisticallyQualified", ...
    "StoppingReason","DeterministicSeedSet","EvidenceUnit"];
assert(all(ismember(required,string(T.Properties.VariableNames))), ...
    "False-alarm evidence must export counts, exact intervals, stopping and seed provenance.");
assert(all(string(T.StatisticalQualification) == "NOT_EVALUATED") && ...
    all(~logical(T.StatisticallyQualified)), ...
    "The three-waveform mini anchor must remain explicitly statistically unqualified.");
assert(all(double(T.CIUpper) > double(T.TargetFalseAlarmProbability)), ...
    "The exact upper bound must expose the uncertainty hidden by a zero-event point estimate.");
assert(~logical(b.Result.StatisticallyQualified), ...
    "Functional PDCCH health must not be promoted to statistical qualification.");
[decisive,qualification]=sixgr.stats.summarizeBinomialQualifications(T);
assert(b.Result.StatisticallyQualified==decisive && ...
    b.Result.StatisticalQualification==qualification && qualification=="NOT_EVALUATED", ...
    'Actual producer summary must retain the exact population qualification outcome.');
assert(all(string(T.EvidenceUnit)=="independent_noise_only_waveform"));
assert(all(abs(T.FalseAlarmProbability - T.FalseAlarmWaveformCount./T.WaveformTrialCount)<eps));
assert(all(T.FalseAlarmWaveformCount<=T.WaveformTrialCount));
trials=b.Result.ArtifactTables.pdcch_trials;
trials=trials(string(trials.TrialType)=="false_alarm_sweep",:);
assert(height(unique(trials(:,{'NoiseSeed','NoiseSubstream'}),'rows'))==height(trials) && ...
    all(string(trials.NoiseGenerator)=="Threefry") && numel(unique(trials.NoiseSeed))==1);
ok = true;
end
