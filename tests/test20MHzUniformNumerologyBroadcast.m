function ok=test20MHzUniformNumerologyBroadcast()
% Real broadcast decode at the selected uniform SCS; no fading/RF acceptance claim.
setup6GRSimToolkit('Verbose',false);
s=sixgr.lls6g.config.loadScenarioConfig( ...
    'simulator/configs/scenarios/lls_tdd_n40_20mhz_64txru_4rx_cdlc100_impaired.yaml');
cfg=sixgr.lls6g.buildInternalConfig(s,tempname);
[cfg,power]=sixgr.rf.resolveSSBPowerContract(cfg);
assert(power.OFDMUnitReference.Nfft==1024 && cfg.phy.ssb.scs_kHz==30);
p=sixgr.link.prepareCellSearchBroadcast(cfg,true);
assert(p.SampleRateHz==30.72e6 && p.Tx.Carrier.NSizeGrid==51 && ...
    p.Tx.Carrier.SubcarrierSpacing==30 && p.Tx.SSBInfo.SSB.SCS_kHz==30);
assert(isequal(p.TransmitSamples,p.Tx.Waveform) && size(p.TransmitSamples,2)==64);
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
