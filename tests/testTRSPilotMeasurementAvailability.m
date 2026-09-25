function ok=testTRSPilotMeasurementAvailability(capturePath)
% Retained acquired TRS receiver regression, not a new PHY execution.
% The capture is explicit so this test cannot silently pick another run.
setup6GRSimToolkit('Verbose',false);
assert(nargin==1 && isfile(capturePath),'Provide the retained shared TRS capture.');
before=sixgr.phy.waveform.WaveformHash.file(capturePath);
saved=load(capturePath,'p','replay','det');
cfg=saved.p.StrictConfig;
cfg.RuntimeChannelEstimator="flat_static_awgn_ls";
rx=struct('ReceivedExecutionEvidence',saved.replay);
ch=sixgr.phy.trs.estimateTRSChannel(rx,cfg,saved.p.Tx,saved.det);
assert(ch.EstimateAvailable,'The acquired capture must retain its practical channel estimate.');
assert(isfield(ch,'PilotPowerEvidence') && ...
    numel(ch.PilotPowerEvidence)==numel(saved.det.SlotDetections), ...
    'test:MissingTRSPilotPowerEvidence', ...
    'The production TRS estimator drops the received-pilot power/noise evidence.');
for k=1:numel(saved.det.SlotDetections)
    d=saved.det.SlotDetections(k);
    assert(d.Detected);
    samples=reshape(d.RxGrid,[],size(d.RxGrid,3));
    samples=samples(double(d.ReferenceIndices(:)),:);
    reference=d.ReferenceSymbols(:);
    % Independent scalar LS reference, not the multiport production helper.
    N=numel(reference); energy=sum(abs(reference).^2);
    gain=(reference'*samples)/energy;
    residual=samples-reference*gain;
    noise=sum(abs(residual).^2,1)/(N-1);
    raw=abs(gain).^2*energy/N;
    desired=raw-noise/N;
    signed=(N-2)/(N-1)*raw./noise-1/N;
    e=ch.PilotPowerEvidence{k};
    assert(max(abs(e.SignedSignalPowerPerReceiveBranch-desired))<1e-12);
    assert(max(abs(e.NoisePowerPerReceiveBranch-noise))<1e-12);
    assert(max(abs(e.SignedReferenceSNRLinearPerReceiveBranch-signed))<1e-12);
    assert(~e.ClippedToNonnegative && ~e.ConfiguredSNROrChannelTruthUsed);
    assert(abs(ch.Table.SignedPilotSINRLinear(k)-mean(signed))<1e-12);
    assert(abs(ch.Table.DesiredPilotPower(k)-mean(desired))<1e-12);
    decoded=jsondecode(ch.Table.PilotPowerEvidenceJSON(k));
    assert(max(abs(decoded.SignedSignalPowerPerReceiveBranch(:)-desired(:)))<1e-12);
end
assert(abs(ch.MeanPilotSINR_dB-10*log10(mean(ch.Table.SignedPilotSINRLinear)))<1e-12);
% An orthogonal received residual has negative debiased signal power. This
% numerical negative fixture must not be clipped or assigned a finite dB.
negative=saved.det;
for k=1:numel(negative.SlotDetections)
    d=negative.SlotDetections(k); reference=d.ReferenceSymbols(:);
    N=numel(reference); v=complex((1:N)',mod((1:N)',7));
    v=v-reference*((reference'*v)/(reference'*reference));
    grid=reshape(d.RxGrid,[],size(d.RxGrid,3));
    grid(double(d.ReferenceIndices(:)),:)=repmat(v,1,size(grid,2));
    negative.SlotDetections(k).RxGrid=reshape(grid,size(d.RxGrid));
end
neg=sixgr.phy.trs.estimateTRSChannel(rx,cfg,saved.p.Tx,negative);
assert(neg.EstimateAvailable && neg.DesiredPilotPower<0 && ...
    neg.SignedPilotSINRLinear<0 && isnan(neg.MeanPilotSINR_dB));
% Generic channel estimates do not acquire an AWGN power interpretation.
generic=cfg; generic.RuntimeChannelEstimator="nr_channel_estimate";
other=sixgr.phy.trs.estimateTRSChannel(rx,generic,saved.p.Tx,saved.det);
assert(isnan(other.MeanPilotSINR_dB) && all(cellfun(@isempty,other.PilotPowerEvidence)));
% Injected truth remains irrelevant to received-grid estimation.
poison=rx; poison.ReceivedExecutionEvidence.InjectedNoiseVariance=1e12;
poison.ReceivedExecutionEvidence.AppliedAWGNSNR_dB=120;
again=sixgr.phy.trs.estimateTRSChannel(poison,cfg,saved.p.Tx,saved.det);
assert(isequaln(ch.PilotPowerEvidence,again.PilotPowerEvidence));
assert(sixgr.phy.waveform.WaveformHash.file(capturePath)==before);
fprintf('TRS_PILOT_MEASUREMENT_AVAILABILITY_PASS resources=%d source_unchanged=1\n',numel(ch.PilotPowerEvidence));
ok=true;
end
