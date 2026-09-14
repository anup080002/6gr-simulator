function capture=applySSBPBCHChannel(waveform,waveInfo,txContract,cfg,initialState,runtimeSlot)
% Apply the configured physical path to an already generated SS/PBCH burst.
% SSB_Tx is a transmitter, not a channel. SIB1 disablement cannot disable
% fading, receiver noise or RF impairments, nor authorize TX-aided correction.
[cfg,~]=sixgr.rf.resolveSSBPowerContract(cfg);
fs=double(txContract.SampleRate_Hz);
validateattributes(fs,{'numeric'},{'scalar','real','finite','positive'});
validateattributes(waveform,{'single','double'},{'2d','nonempty','finite'});
carrier=sixgr.phy.grid.makeCarrier(cfg);
assert(carrier.NSizeGrid==txContract.NSizeGrid && ...
    carrier.NStartGrid==txContract.NStartGrid && ...
    carrier.SubcarrierSpacing==txContract.SubcarrierSpacing_kHz, ...
    'sixgr:link:SSBPBCHCarrierMismatch','Use the actual SS/PBCH producer carrier.');
ofdm=nrOFDMInfo(carrier);
assert(double(ofdm.SampleRate)==fs,'sixgr:link:SSBPBCHSampleRateMismatch', ...
    'The physical channel must use the actual transmitter sample rate.');
% Recover the exact transmitted composite on its carrier. Do not use the
% empty ResourceGridInCarrier field of an SSB-only generator as TX energy.
txInfo=struct('OFDM',ofdm,'PortGrid',nrOFDMDemodulate(carrier,waveform), ...
    'PowerNormalizationGridSource',"exact_ssb_pbch_waveform_demodulation");
[transmit,power]=sixgr.rf.applyPowerContext(waveform,cfg,'DL',txInfo);
cfg=sixgr.util.structSet(cfg,'lls6g.runtimePowerContext',power);
cfg=sixgr.util.structSet(cfg,'lls6g.userContext.RuntimeCurrentDirection',"DL");
cfg=sixgr.util.structSet(cfg,'lls6g.userContext.RuntimeSignalFamily',"PBCH");
tx=struct('Waveform',transmit,'SampleRateHz',fs,'Carrier',carrier,'PowerContext',power);
txInfo.PowerContext=power;
state=sixgr.link.initWaveformTruthChannelState(cfg,tx,txInfo, ...
    'InitialRuntimeChannelState',initialState);
if isfinite(runtimeSlot)
    validateattributes(runtimeSlot,{'numeric'},{'scalar','real','integer','nonnegative'});
    startTime=double(runtimeSlot)*sixgr.time.slotDurationSec(cfg);
    if logical(sixgr.util.structGet(state,'RuntimeChannelState.Initialized',false))
        state.RuntimeChannelState=sixgr.channel.ChannelFactory.advanceRuntimeChannelStateToTime( ...
            state.RuntimeChannelState,startTime,size(transmit,2),transmit);
    else
        state.WaveformImpairmentNextSample=round(startTime*fs);
    end
end
snr=double(sixgr.util.structGet(cfg,'channel.snr_dB',NaN));
assert(isscalar(snr) && isreal(snr) && ~isnan(snr),'sixgr:link:MissingSSBPBCHNoiseOperatingPoint', ...
    'SS/PBCH must retain its explicitly configured noise operating point.');
[received,replay,state]=sixgr.link.applyWaveformTruthImpairments(transmit,snr,state,cfg,tx,txInfo);
capture=struct('Waveform',received,'TransmitWaveform',transmit, ...
    'ReceiverConfig',cfg,'SampleRateHz',fs,'PowerContext',power, ...
    'ChannelReplay',replay,'RuntimeDLChannelState',state.RuntimeChannelState, ...
    'SSBTx',struct('SSBBurstPlan',txContract.SSBBurstPlan, ...
        'SSBComposite',waveInfo.SSBComposite,'SSBWaveform',waveform,'SSBInfo',txContract), ...
    'Source',"SSB_Tx_power_context_configured_waveform_truth_impairments");
end
