function ok=test20MHzUniformNumerologyBroadcast()
% Real broadcast decode at the selected uniform SCS; no fading/RF acceptance claim.
setup6GRSimToolkit('Verbose',false);
s=sixgr.lls6g.config.loadScenarioConfig( ...
    'simulator/configs/scenarios/lls_tdd_n40_20mhz_64txru_4rx_cdlc100_impaired.yaml');
cfg=sixgr.lls6g.buildInternalConfig(s,tempname);
[cfg,power]=sixgr.rf.resolveSSBPowerContract(cfg);
% The absolute-power branch does not run the normalized single-RE probe.
% Check the executed carrier/OFDM definition, not that inapplicable receipt.
carrier=sixgr.phy.grid.makeCarrier(cfg);
ofdm=nrOFDMInfo(carrier);
assert(ofdm.Nfft==1024 && ofdm.SampleRate==30.72e6 && cfg.phy.ssb.scs_kHz==30);
assert(power.Available && ~power.FixedSNRNormalizedReference && ...
    power.PowerReferenceDomain=="configured_device_full_bwp_budget" && ...
    power.TxPowerBudget_dBm==30 && power.NumSubcarriers==612 && ...
    abs(power.FullBWPUnitEPRE_dBm-(30-10*log10(612)))<1e-12);
p=sixgr.link.prepareCellSearchBroadcast(cfg,true);
assert(p.SampleRateHz==30.72e6 && p.Tx.Carrier.NSizeGrid==51 && ...
    p.Tx.Carrier.SubcarrierSpacing==30 && p.Tx.SSBInfo.SSB.SCS_kHz==30);
% Tx is the original generator grid/waveform; RuntimeTx contains the
% absolute-power-scaled samples actually enqueued. Equality with unscaled
% Tx is only valid for the normalized branch and must not be imposed here.
assert(isequal(p.TransmitSamples,p.RuntimeTx.Waveform) && size(p.TransmitSamples,2)==64);
assert(p.PowerContext.ScaleApplied && ~p.PowerContext.FixedSNRNormalizedReference && ...
    ~p.PowerContext.PAApplied && isfinite(p.PowerContext.AmplitudeScale) && ...
    p.PowerContext.AmplitudeScale>0 && abs(p.PowerContext.PowerClosureError_dB)<1e-10);
% Check every sample, in bounded chunks to avoid a duplicate 64-chain capture.
for first=1:4096:size(p.TransmitSamples,1)
    last=min(first+4095,size(p.TransmitSamples,1));
    expected=p.Tx.Waveform(first:last,:).*cast(p.PowerContext.AmplitudeScale,'like',p.Tx.Waveform);
    assert(isequal(p.TransmitSamples(first:last,:),expected), ...
        'Absolute broadcast samples must preserve the exact declared scale.');
end
r=sixgr.phy.broadcast.recoverSIB1FromWaveform(p.TransmitSamples(:,1), ...
    p.ReceiverConfig,'CandidateSSBIndex',0);
assert(r.DLSCHCrcPass && r.SIB1ASN1DecodeOk && r.DCIBlindDecodeSuccess && ...
    isempty(r.UsedOracleFields),'Actual PBCH/Type-0/SIB1 decoding must succeed without TX oracle.');
[grid,sync]=sixgr.phy.dl.SSB_Rx(p.TransmitSamples(:,1),cfg,'SampleRate_Hz',p.SampleRateHz);
[pb,info]=sixgr.phy.dl.PBCH_Recovery(grid,sync,cfg);
assert(pb.Ok);
mib=sixgr.phy.broadcast.decodeMIBTransportBlock(info.Selected.trblk);
assert(mib.SubCarrierSpacingCommonBit==1,'MIB must advertise common SCS 30 kHz.');
assert(isfield(p.TxInfo,'PortGrid') && ~isempty(p.TxInfo.PortGrid), ...
    'Equal-SCS broadcast must retain its actual composite port grid.');
fprintf('UNIFORM_SSB30_COMMON30_BROADCAST_PASS: real PBCH, SI-RNTI DCI and SIB1 decoding.\n');
ok=true;
end
