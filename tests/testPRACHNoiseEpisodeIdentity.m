function ok=testPRACHNoiseEpisodeIdentity()
% Identity checks plus actual bounded detector execution; not qualification.
setup6GRSimToolkit('Verbose',false);
seeds=[240616 240631 240641 240659];
% Reproduce the prior arithmetic collision before checking its replacement.
old=seeds(mod((1:12000)-1,numel(seeds))+1)+100000+(1:12000)+1;
assert(old(2)==old(17) && numel(unique(old))<12000);
substreams=zeros(12000,4);
for point=1:2
    for present=[false true]
        for trial=1:12000
            id=sixgr.phy.prach.noiseTrialIdentity(seeds,point,trial,12000,present);
            substreams(trial,2*(point-1)+double(present)+1)=id.Substream;
        end
    end
end
assert(numel(unique(substreams(:)))==numel(substreams));
for trial=[17 2 11999 1]
    a=sixgr.phy.prach.noiseTrialIdentity(seeds,1,trial,12000,false);
    assert(a.Substream==substreams(trial,1));
    first=localNoise(a,[64 2],1);
    replay=localNoise(a,[64 2],1);
    assert(isequal(first,replay));
end
assert(~isequal(localNoise(sixgr.phy.prach.noiseTrialIdentity(seeds,1,2,12000,false),[64 2],1), ...
    localNoise(sixgr.phy.prach.noiseTrialIdentity(seeds,1,17,12000,false),[64 2],1)));
for testCase=1:2
    try
        if testCase==1
            sixgr.phy.prach.noiseTrialIdentity([1 1],1,1,10,false);
        else
            sixgr.phy.prach.noiseTrialIdentity(seeds,flintmax,1,10,false);
        end
        error('test:InvalidNoiseIdentityAccepted','Invalid identity was accepted.');
    catch ex
        assert(startsWith(string(ex.identifier),"sixgr:phy:prach:"));
    end
end
before=rng;
b=prachStrictAnchorResult('Refresh',true);
assert(isequal(before,rng),'PRACH campaign must not reseed the caller global RNG.');
allRows=b.Result.ArtifactTables.prach_trials;
rows=allRows(ismember(allRows.TrialType,["false_alarm_sweep","missed_detection_sweep"]),:);
assert(height(unique(rows(:,{'NoiseSeed','NoiseSubstream'})))==height(rows) && ...
    all(rows.NoiseNormalTransform=="Inversion") && ...
    all(strlength(rows.ReceivedWaveformSHA256)==64));
maximumTrials=max([b.Config.StatisticalQualification.MaximumTrials, ...
    b.Config.StatisticalQualification.DetectionMaximumTrials,b.Config.NumTrials]);
for k=1:height(rows)
    id=sixgr.phy.prach.noiseTrialIdentity(seeds,rows.NoisePointIndex(k), ...
        rows.NoiseTrialIndex(k),maximumTrials,rows.TrialType(k)=="missed_detection_sweep");
    assert(rows.NoiseSeed(k)==id.Seed && rows.NoiseSubstream(k)==id.Substream && ...
        rows.NoiseMaximumTrials(k)==maximumTrials);
end
h0=rows(find(rows.TrialType=="false_alarm_sweep",1),:);
id=struct('Generator',h0.NoiseGenerator,'Seed',h0.NoiseSeed, ...
    'NormalTransform',h0.NoiseNormalTransform,'Substream',h0.NoiseSubstream);
replayed=localNoise(id,size(b.Result.NoiseOnlyWaveform),h0.AppliedSampleNoiseVariance);
assert(isequal(replayed,b.Result.NoiseOnlyWaveform) && ...
    string(sixgr.rrc.asn1.asn1SHA256Hex(typecast([real(replayed(:));imag(replayed(:))],'uint8')))== ...
    h0.ReceivedWaveformSHA256,'Exported RNG identity must reproduce the actual detector input.');
assert(~b.Result.StatisticallyQualified,'This bounded anchor is not a statistical qualification.');
fprintf('PRACH_NOISE_IDENTITY_PASS identities=%d physical_episodes=%d H0_exact_replay=1\n', ...
    numel(substreams),height(rows));
ok=true;
end

function values=localNoise(identity,sz,variance)
stream=RandStream(char(identity.Generator),'Seed',identity.Seed, ...
    'NormalTransform',char(identity.NormalTransform));
stream.Substream=identity.Substream;
values=sqrt(variance/2).*(randn(stream,sz)+1i*randn(stream,sz));
end
