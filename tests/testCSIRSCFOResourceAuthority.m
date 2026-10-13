function ok=testCSIRSCFOResourceAuthority()
% A full-band CSI beam sweep is not a repeated observation of one channel.
% Native CSI-RS/OFDM component with no CFO and independently phased beams.
setup6GRSimToolkit('Verbose',false);
carrier=nrCarrierConfig('NSizeGrid',273,'SubcarrierSpacing',30,'NCellID',17,'NSlot',1);
cfg=struct();
cfg.run.strictMode=true;
cfg.channel.model='AWGN';
cfg.phy.csirs=struct('enable',true,'period_slots',5,'offset_slots',1, ...
    'numResources',2,'nPorts',4,'density','one','resourceIDs',[11 29], ...
    'rowNumbers',[4 4],'symbolLocationsByResource',[3 10], ...
    'subcarrierLocationsByResource',[0 0],'rbOffsetsByResource',[0 0], ...
    'numRBsByResource',[273 273],'runtimeChannelEstimator','nr_channel_estimate');
cfg.phy.mimo=struct('strict',true,'measurementMaxAgeSlots',8);
cfg.phy.csi.reportConfiguration=struct('Ports',4);
cfg.phy.rx.cfoCorrectionEnabled=true;
cfg.phy.impairments.cfoEstimationMethod='reference_symbol_phase_slope';
cfg.lls6g.userContext=struct('RuntimeUEIndex',1,'RuntimeCurrentSlot',2);
cfg.lls6g.runtimePowerContext.WaveformAmplitudeUnit='sqrt_mW';
cfg.integration=struct('run_mode','FIXED_SNR_SWEEP','configured_snr_is_link_authority',true);
[~,~,info]=sixgr.phy.refsig.csirs(carrier,cfg);
H=[.8 0 .6 0;0 .6 0 .8];
grid=complex(zeros(12*carrier.NSizeGrid,carrier.SymbolsPerSlot,2));
for n=1:numel(info.Resources)
    reference=info.Resources(n);
    ports=nrResourceGrid(carrier,4);
    ports(reference.Indices)=reference.Symbols;
    received=reshape(reshape(ports,[],4)*H.',size(grid));
    grid=grid+received*exp(1i*.9*(n-1));
end
waveform=nrOFDMModulate(carrier,grid);
searchEnd=37; unknownDelay=13;
capture=[zeros(unknownDelay,2);waveform;zeros(searchEnd-unknownDelay,2)];
rx=sixgr.phy.refsig.receiveCSIRSWaveform( ...
    carrier,cfg,capture,capture,[0 searchEnd],struct());
assert(rx.ReceiveTiming.TimingOffsetSamples==unknownDelay);
assert(~rx.ReceiverTrackingCorrection.CFOEstimateAvailable && ...
    ~rx.ReceiverTrackingCorrection.CFOCorrectionApplied && ...
    isnan(rx.ReceiverTrackingCorrection.EstimatedCFO_Hz), ...
    'sixgr:test:CSIRSBeamPhaseUsedAsCFO', ...
    'Single-symbol resources on different beams do not provide a repeated-channel frequency estimate.');
assert(rx.CSIRSObservation.Observed && rx.CSIRSObservation.ChannelEstimateAvailable && ...
    ~rx.PDSCHDecodeAttempted, ...
    'The missing repeated-frequency observation must not erase actual CSI-RS channel measurements.');
fprintf('CSIRS_CFO_RESOURCE_AUTHORITY_PASS PRB=273 ports=4 resources=2 no_cross_beam_CFO=1\n');
ok=true;
end
