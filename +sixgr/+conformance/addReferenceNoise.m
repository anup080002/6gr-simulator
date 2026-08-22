function [rxWaveform, provenance] = addReferenceNoise(txWaveform, carrier, snr_dB, varargin)
%ADDREFERENCENOISE Compatibility adapter to the shared production primitive.
%
%   [Y, INFO] = sixgr.conformance.addReferenceNoise(X, CARRIER, SNR_DB)
%   adds independent circular complex time-domain AWGN to every receive
%   column in X. SNR_DB is Es/N0 for unit-energy QAM symbols on occupied
%   resource-grid REs. The waveform power, cyclic prefix, and unused FFT
%   bins are deliberately excluded from the SNR definition.
%
%   [...] = sixgr.conformance.addReferenceNoise(..., "Seed", SEED) uses a
%   deterministic local Twister stream without changing the caller's RNG
%   state.
%
%   [...] = sixgr.conformance.addReferenceNoise(...,
%   "SignalEnergyPerOccupiedRE", ES) applies the same Es/N0 definition to a
%   waveform whose occupied data REs have been scaled to energy ES (for
%   example by a physical transmit-power context). The default remains one.
%
%   The variance contract is
%
%       gridNoiseVariance   = 10^(-SNR_DB/10)
%       sampleNoiseVariance = gridNoiseVariance / G
%
%   where G is the calibrated OFDM sample-to-grid noise-variance gain.

% Keep this public name for older callers, but make the shared PHY package
% the only numerical implementation.  All new production code calls the
% shared function directly.
[rxWaveform, provenance] = ...
    sixgr.phy.waveform.addOccupiedREAWGN( ...
    txWaveform, carrier, snr_dB, varargin{:});
provenance.ConformanceAdapterVersion = ...
    "sixgr.conformance.addReferenceNoise/v2";
provenance.ConformanceAdapterSource = ...
    "sixgr.conformance.addReferenceNoise";
provenance.FRCCompatibilityAdapterUsed = true;
end
