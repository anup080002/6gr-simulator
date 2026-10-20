function ok=testPDCCHBoundedReceiveWindow()
% Deterministic truncated native-PDCCH timing stimulus, not a BLER sample.
% Exercise the out-of-window correlation peak explicitly instead of relying
% on an incidental peak of one historical noise realization.
setup6GRSimToolkit('Verbose',false);
s=sixgr.lls6g.config.loadScenarioConfig( ...
    'simulator/configs/scenarios/lls_rejected_ul_control_fixture.yaml');
cfg=sixgr.lls6g.buildInternalConfig(s,tempname);
cfg=sixgr.phy.grid.applyRuntimeCarrierTimeline(cfg,1);
context=sixgr.phy.pdcch.DCIContextFactory.fromRuntimeConfig(cfg,'0_1');
schema=sixgr.phy.pdcch.DCISchemaEngine.resolve(context);
fields=struct();
for def=schema.Definitions(:).', fields.(def.Name)=def.ValueMin; end
authored=sixgr.phy.pdcch.DCIPacker.pack(fields,context);
bits=authored.Bits;
p=sixgr.link.preparePDCCHTransmission(cfg,'DCIBits',bits,'RNTI',context.Data.RNTIValue);
upper=16; delay=64; count=double(p.MinimumReceiveSamples)+upper;
assert(count>delay && size(p.TransmitSamples,1)>=count-delay);
% A delayed waveform whose last monitored symbols lie outside the observed
% capture. Initial silence is authored TX timing, never RX zero-padding.
samples=complex(zeros(count,size(p.TransmitSamples,2),'like',p.TransmitSamples));
samples(delay+1:end,:)=p.TransmitSamples(1:count-delay,:);
[~,info]=sixgr.phy.dl.PDCCH_Rx(samples,p.ReceiverConfig, ...
    'Carrier',p.Tx.Carrier,'PDCCH',p.Tx.PDCCH,'K',numel(bits), ...
    'RNTI',p.TxInfo.RNTI,'PDCCHScramblingRNTI',p.TxInfo.PDCCHScramblingRNTI, ...
    'SampleRate_Hz',p.SampleRateHz,'TimingSearchWindowSamples',[0 upper]);
timing=info.TimingEstimate;
[~,peak]=max(timing.SearchMetric);
assert(timing.UnboundedEstimate_samples>upper, ...
    'test:TimingRegressionNotExercised','The explicit truncated waveform must exercise an out-of-window peak.');
assert(timing.AppliedCorrection_samples==peak-1 && ...
    timing.AppliedCorrection_samples<=upper && ~info.ReceivePaddingApplied && ...
    isequal(timing.SearchWindowSamples,[0 upper]), ...
    'test:BoundedTimingSelection','Only complete-symbol timing hypotheses may enter demodulation.');
fprintf('PDCCH_BOUNDED_WINDOW_PASS authored_delay=%d unbounded=%g bounded=%g upper=%d scope=deterministic_timing_not_BLER\n', ...
    delay,timing.UnboundedEstimate_samples,timing.AppliedCorrection_samples,upper);
ok=true;
end
