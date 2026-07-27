function [waveform,info] = ofdmModulate(carrier,grid,varargin)
%OFDMODULATE Compatibility facade for the canonical waveform engine.
[waveform,info] = sixgr.phy.waveform.CanonicalOFDMModulator.toolbox( ...
    carrier,grid,varargin{:});
end
