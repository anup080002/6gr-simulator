function [grid,info] = ofdmDemodulate(carrier,waveform,varargin)
%OFDMDEMODULATE Compatibility facade for the canonical waveform engine.
[grid,info] = sixgr.phy.waveform.CanonicalOFDMDemodulator.toolbox( ...
    carrier,waveform,varargin{:});
end
