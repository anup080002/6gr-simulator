function [waveform,meta] = applyOscillatorCFO(waveform,cfg,seed)
%APPLYOSCILLATORCFO Apply production TRP/UE oscillator errors.
old = rng;
cleanup = onCleanup(@()rng(old)); %#ok<NASGU>
rng(double(seed),"twister");
ueRange = double(cfg.oscillator.ue_ppm_range(:).');
trpRange = double(cfg.oscillator.trp_ppm_range(:).');
uePPM = ueRange(1)+(ueRange(2)-ueRange(1))*rand;
trpPPM = trpRange(1)+(trpRange(2)-trpRange(1))*rand;
netPPM = trpPPM-uePPM;
cfoHz = netPPM*1e-6*double(cfg.carrier.frequency_hz);
n = (0:size(waveform,1)-1).';
sampleRate = double(sixgr.util.structGet(cfg,"runtime.sample_rate_hz", ...
    cfg.carrier.scs_khz*1000*256));
waveform = waveform.*exp(1j*2*pi*cfoHz*n/sampleRate);
meta = struct("UEPPM",uePPM,"TRPPPM",trpPPM,"NetPPM",netPPM, ...
    "UEOscillatorHz",uePPM*1e-6*double(cfg.carrier.frequency_hz), ...
    "TRPOscillatorHz",trpPPM*1e-6*double(cfg.carrier.frequency_hz), ...
    "AppliedCFOHz",cfoHz,"SignConvention","TRP_minus_UE", ...
    "Seed",double(seed));
end
