function ok=testPUCCHNormalizedTransmitReference()
% Check the TX-side Es reference independently of received noise or fading.
setup6GRSimToolkit('Verbose',false);
f=sixgr.phy.pucch.PUCCHFixtureFactory.connected(0,int8([1;0]));
tx=sixgr.phy.pucch.PUCCHTransmitter.transmit(f.Carrier,f.Assignment,f.Report);
reference=sixgr.phy.waveform.ofdmModulate(f.Carrier,tx.Grid);
cfg=struct('integration',struct('run_mode','FIXED_SNR_SWEEP', ...
    'configured_snr_is_link_authority',true));
[actual,~,e]=sixgr.link.preparePUCCHTransmitWaveform(tx,cfg,'ApplyNodeRF',false);
assert(norm(actual-reference,'fro')/norm(reference,'fro')<1e-12);
assert(e.NormalizedPowerReference && ~e.PhysicalPowerApplicable && isnan(e.AppliedPower_dBm));
assert(e.RemovedAbsoluteTransmitScale==tx.Power.WaveformScale);
assert(e.PowerContext.FixedSNRReferenceEnergyPerOccupiedRE==1);
physical=cfg; physical.integration.configured_snr_is_link_authority=false;
[actual,~,e]=sixgr.link.preparePUCCHTransmitWaveform(tx,physical,'ApplyNodeRF',false);
assert(e.PhysicalPowerApplicable && ~e.NormalizedPowerReference);
[power,~,~]=sixgr.rf.measureActiveOFDMTotalPower(actual,struct('OFDM',tx.OFDMInfo));
assert(abs(10*log10(power)-tx.Power.AppliedPowerdBm)<1e-10);
bad=tx; bad.Power.WaveformScale=NaN; rejected=false;
try
    sixgr.link.preparePUCCHTransmitWaveform(bad,cfg,'ApplyNodeRF',false);
catch
    rejected=true;
end
assert(rejected,'Missing TX normalization evidence must not be inferred from received IQ.');
disp('PUCCH_NORMALIZED_REFERENCE_PASS: original IFFT restored; absolute mode preserved; missing scale rejected.');
ok=true;
end
