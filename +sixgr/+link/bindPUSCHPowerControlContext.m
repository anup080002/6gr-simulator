function [waveOut,pc,cfgOut,stateOut]=bindPUSCHPowerControlContext(waveIn,cfg,tx,grant,stateIn)
%BINDPUSCHPOWERCONTROLCONTEXT Bind original allocation target to actual waveform.
% No scaling here; applyPowerContext owns scaling. Allocation resolution is
% shared with pre-encoding MAC PHR generation, without a second TPC update.
if nargin<5, stateIn=struct(); end
[pc,cfgOut,stateOut]=sixgr.link.resolvePUSCHAllocationPowerContext(cfg,tx,grant,stateIn);
if pc.Enabled
    inputMeanPower=mean(sum(abs(double(waveIn)).^2,2),"omitnan");
    assert(isscalar(inputMeanPower)&&isfinite(inputMeanPower)&&inputMeanPower>0, ...
        'sixgr:pusch:InvalidWaveformPower', ...
        'PUSCH power control requires a finite nonzero production waveform.');
end
waveOut=waveIn;
end
