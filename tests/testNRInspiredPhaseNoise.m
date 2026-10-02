function ok=testNRInspiredPhaseNoise()
% Assumed-profile numerics, streaming invariance, and CPE + nonzero ICI.
d=sixgr.lls6g.config.readConfigFile('simulator/configs/rf/phase_noise_nr_inspired_7ghz.yaml');
fs=122880000; raw=sixgr.rf.runtime.resolveMultipolePhaseNoiseProfile(d,7e9,fs);
p=struct('ProfileID',raw.profile_id,'Version',raw.version,'SampleRate_Hz',fs, ...
    'CarrierFrequency_Hz',7e9,'MaskOffsets_Hz',raw.mask_offsets_hz, ...
    'MaskLevels_dBcHz',raw.mask_levels_dbchz,'LOCorrelation',raw.lo_correlation, ...
    'Seed',103277,'SynthesisMethod',raw.synthesis_method,'FIRLength',raw.fir_length, ...
    'Classification',raw.classification);
% Independently evaluate one analytic reference offset (linear products).
f=raw.mask_offsets_hz(1);
ref=10*log10(prod(1+(f./double(d.zero_frequencies_hz)).^double(d.zero_exponents))/ ...
    prod(1+(f./double(d.pole_frequencies_hz)).^double(d.pole_exponents))) ...
    +d.reference_psd_dbchz+20*log10(7e9/d.reference_frequency_hz);
assert(abs(ref-raw.mask_levels_dbchz(1))<1e-10);
d2=d; d2.carrier_frequency_hz=d.reference_frequency_hz;
reference=sixgr.rf.runtime.resolveMultipolePhaseNoiseProfile(d2,d.reference_frequency_hz,fs);
assert(max(abs(raw.mask_levels_dbchz-reference.mask_levels_dbchz-20*log10(7e9/d.reference_frequency_hz)))<1e-10);
fit=sixgr.rf.runtime.PhaseNoiseProcess.evaluateModelPSD(p,p.MaskOffsets_Hz);
assert(max(abs(fit-p.MaskLevels_dBcHz))<1);
n=262144; a=sixgr.rf.runtime.PhaseNoiseProcess(p,2,1);
b=sixgr.rf.runtime.PhaseNoiseProcess(p,2,1);
[whole,t]=a.apply(ones(n,2),1);
[first,~]=b.apply(ones(17013,2),1); [last,~]=b.apply(ones(n-17013,2),1);
assert(max(abs(whole-[first;last]),[],'all')<1e-11);
assert(max(abs(abs(whole)-1),[],'all')<1e-12);
assert(max(abs(whole(:,1)-whole(:,2)))<1e-12); % common LO
% A single OFDM tone makes off-tone bins an exact ICI witness. Removing
% the true mean phasor phase is diagnostic oracle CPE-only compensation,
% NOT the production PTRS estimator and not a performance claim.
N=4096; q=reshape(whole(:,1),N,[]); spectrum=fft(q,[],1)/N;
cpe=angle(spectrum(1,:)); ici=sum(abs(spectrum(2:end,:)).^2,1);
assert(std(cpe)>0 && all(ici>0));
assert(max(abs(abs(spectrum(1,:)).^2+ici-1))<1e-12);
% Independent Welch estimate, pooled frequency bands around mask offsets.
[psd,freq]=pwelch(t.Phase_rad(:,1),hann(16384),8192,16384,fs,'twosided');
targets=p.MaskOffsets_Hz(p.MaskOffsets_Hz>=1e5 & p.MaskOffsets_Hz<=1e7);
err=zeros(size(targets));
for k=1:numel(targets)
    take=freq>=targets(k)*0.85 & freq<=targets(k)*1.15;
    model=sixgr.rf.runtime.PhaseNoiseProcess.evaluateModelPSD(p,freq(take));
    err(k)=10*log10(mean(psd(take))/mean(10.^(model/10)));
end
assert(max(abs(err))<3,'Independent realized phase PSD differs by >3 dB in a pooled band.');
folder=fullfile(pwd,'logs','nr_inspired_phase_noise_20261001'); if ~isfolder(folder), mkdir(folder); end
writetable(table(p.MaskOffsets_Hz,p.MaskLevels_dBcHz,fit, ...
    'VariableNames',{'OffsetHz','AssumedMaskdBcHz','ImplementedFilterdBcHz'}),fullfile(folder,'mask.csv'));
writetable(table(targets,err,'VariableNames',{'OffsetHz','MeasuredPSDerrorDB'}),fullfile(folder,'measured_psd.csv'));
save(fullfile(folder,'cpe_ici.mat'),'cpe','ici','p');
ok=true; fprintf('NR_INSPIRED_PHASE_NOISE_PASS CPE_RMS_DEG=%g ICI_MEAN=%g HARDWARE_QUALIFIED=UNKNOWN\n', ...
    sqrt(mean(cpe.^2))*180/pi,mean(ici));
end
