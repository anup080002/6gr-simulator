function ref=resolveDACAmplitudeReference(cfg,raw,fs,direction)
% Fixed DAC range in the waveform's units. Never observe payload samples.
% Quantization uses this range directly: no pre/post signal gain, power
% restoration, allocation normalization, rank normalization or SNR tuning.
mode=string(sixgr.util.structGet(raw,'reference_domain','waveform_samples'));
if ~isscalar(mode) || ~any(mode==["waveform_samples","normalized_nr_ofdm_full_carrier","absolute_endpoint_rms"])
    error('RF:DACReferenceDomain','Unsupported rf_frontend.dac.reference_domain.');
end
ref=struct('Domain',mode,'WaveformUnitsPerReferenceUnit',1, ...
    'ReferenceRMS',NaN,'Headroom_dB',NaN,'ReferenceREEnergy',NaN, ...
    'Nfft',NaN,'NumSubcarriers',NaN,'NumTransmitPorts',NaN, ...
    'Source',"explicit_waveform_sample_units",'PayloadDependent',false);
if mode=="waveform_samples", return; end
if mode=="absolute_endpoint_rms"
    absolute=sixgr.rf.resolveAbsoluteEndpointReference(cfg,raw,direction);
    for name=string(fieldnames(absolute)).', ref.(name)=absolute.(name); end
    return;
end
if ~sixgr.rf.isNormalizedFixedSNRPowerReference(cfg)
    error('RF:DACReferencePowerDomain', ...
        'Normalized OFDM DAC reference requires normalized fixed-Es samples, not absolute-power samples.');
end
energy=double(sixgr.util.structGet(raw,'reference_re_energy',NaN));
headroom=double(sixgr.util.structGet(raw,'reference_headroom_db',NaN));
if ~(isscalar(energy)&&isreal(energy)&&isfinite(energy)&&energy>0 && ...
        isscalar(headroom)&&isreal(headroom)&&isfinite(headroom)&&headroom>=0)
    error('RF:DACReferenceProfile', ...
        'Declare positive reference_re_energy and nonnegative reference_headroom_db.');
end
direction=upper(string(direction));
if any(direction==["DL","DOWNLINK"])
    ports=double(sixgr.util.structGet(cfg,'scenario.bs.nTxAnt',NaN));
elseif any(direction==["UL","UPLINK"])
    ports=double(sixgr.util.structGet(cfg,'scenario.ue.nTxAnt',NaN));
else
    error('RF:DACReferenceDirection','Declare DL or UL DAC endpoint ownership.');
end
if ~(isscalar(ports)&&isreal(ports)&&isfinite(ports)&&ports>=1&&ports==fix(ports))
    error('RF:DACReferencePorts','A fixed DAC reference requires the configured physical TX port count.');
end
assert(isfield(cfg,'phy')&&isfield(cfg.phy,'carrier'), ...
    'RF:DACReferenceCarrier','The OFDM DAC reference requires an installed carrier.');
carrier=sixgr.phy.grid.makeCarrier(cfg);
options={'SampleRate',fs};
explicit=sixgr.util.structGet(cfg,'phy.ofdm.explicitNfft',[]);
if ~isempty(explicit), options=[options {'Nfft',explicit}]; end
sampling=sixgr.phy.frame.OFDMSamplingResolver.resolve(carrier,options{:});
nfft=double(sampling.Nfft);
nsc=12*double(carrier.NSizeGrid);
% Parseval for native 1/Nfft IFFT; total configured reference RE energy is
% shared over TX ports, NOT over current layers or active resource elements.
rms=sqrt(nsc*energy/ports)/nfft;
scale=rms*10^(headroom/20);
if ~(isfinite(scale)&&scale>0)
    error('RF:DACReferenceProfile','DAC reference range must be finite and positive.');
end
ref.WaveformUnitsPerReferenceUnit=scale;
ref.ReferenceRMS=rms; ref.Headroom_dB=headroom;
ref.ReferenceREEnergy=energy; ref.Nfft=nfft;
ref.NumSubcarriers=nsc; ref.NumTransmitPorts=ports;
ref.Source="configured_full_carrier_unit_RE_native_IFFT_equal_total_power_over_TX_ports";
end
