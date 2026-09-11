function T=annotatePRACHNativeAllocation(T,tx,grid,portDomain)
% Exact native-bin/time coordinates, not carrier REs or spectral containment.
info=tx.OFDMInfo; fs=double(info.SampleRate); nfft=double(info.Nfft);
cp=double(info.CyclicPrefixLengths(:)); guards=double(info.GuardLengths(:));
lengths=double(info.SymbolLengths(:)); offset=double(info.OffsetLength);
k=size(grid,1); l=size(grid,2); scs=1000*double(tx.PRACH.SubcarrierSpacing);
values=[fs;nfft;cp;guards;lengths;offset];
assert(all(isfinite(values)) && all(values>=0 & values==fix(values)) && fs>0 && nfft>0 && ...
    numel(cp)==l && numel(guards)==l && numel(lengths)==l && ...
    all(lengths==cp+nfft+guards) && fs/nfft==scs && ...
    k==12*double(tx.Carrier.NSizeGrid)*double(tx.Carrier.SubcarrierSpacing)/double(tx.PRACH.SubcarrierSpacing) && ...
    info.Windowing==0 && offset+sum(lengths)==size(tx.Waveform,1), ...
    'sixgr:truth:PRACHNativeTimingMismatch','Native PRACH grid, OFDM timing and transmitted sample count must agree.');
symbol=double(T.symbol_index)+1;
assert(all(symbol>=1 & symbol<=l & symbol==fix(symbol)), ...
    'sixgr:truth:PRACHNativeSymbolMismatch','Native symbol index exceeds the executed PRACH period.');
starts=offset+[0;cumsum(lengths(1:end-1))];
T.grid_domain(:)="prach_native_ofdm";
T.coordinate_precision(:)="exact_native_prach_grid_run";
T.layer_count(:)=NaN;
T.port_domain=repmat(string(portDomain),height(T),1);
T.grid_subcarrier_spacing_hz=repmat(scs,height(T),1);
T.grid_subcarrier_count=repmat(k,height(T),1);
T.grid_symbol_count=repmat(l,height(T),1);
T.grid_port_count=repmat(size(grid,3),height(T),1);
T.native_grid_complete=true(height(T),1);
T.native_grid_sha256=repmat(string(sixgr.phy.waveform.WaveformHash.numeric(grid)),height(T),1);
T.native_grid_power_plane=repmat("normalized_grid_before_preamble_power_control_and_rf",height(T),1);
T.sample_rate_hz=repmat(fs,height(T),1);
T.cp_start_sample_relative=starts(symbol);
T.useful_start_sample_relative=starts(symbol)+cp(symbol);
T.useful_end_sample_exclusive_relative=T.useful_start_sample_relative+nfft;
% TS38.211 5.3.2 native-bin centering; odd K has half-bin centering.
T.frequency_first_hz=(double(T.subcarrier_start)-k/2)*scs;
T.frequency_last_hz=(double(T.subcarrier_start)+double(T.subcarrier_count)-1-k/2)*scs;
T.frequency_axis_source=repmat("native_bin_centers_relative_to_carrier_center_not_measured_spectrum",height(T),1);
T.waveform_sha256=repmat(string(sixgr.phy.waveform.WaveformHash.numeric(tx.Waveform)),height(T),1);
assert(isfield(tx,'WaveformHashPlane') && isscalar(string(tx.WaveformHashPlane)) && ...
    any(string(tx.WaveformHashPlane)==[ ...
    "prach_generator_before_preamble_power_control_spatial_mapping_and_rf", ...
    "prach_after_preamble_power_control_before_spatial_mapping_and_rf"]), ...
    'sixgr:truth:MissingPRACHWaveformHashPlane','PRACH waveform hash needs an explicit producer-owned power plane.');
T.waveform_hash_plane=repmat(string(tx.WaveformHashPlane),height(T),1);
T.waveform_start_sample=repmat(NaN,height(T),1);
if isfield(tx,'WaveformStartSample')
    origin=tx.WaveformStartSample;
    assert(isnumeric(origin) && isscalar(origin) && isfinite(origin) && origin>=0 && origin==fix(origin), ...
        'sixgr:truth:PRACHNativeOriginMismatch','Actual PRACH waveform origin must be an integer sample.');
    T.waveform_start_sample(:)=double(origin);
end
end
