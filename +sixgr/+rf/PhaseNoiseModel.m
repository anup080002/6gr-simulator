classdef PhaseNoiseModel < handle
%PHASENOISEMODEL Apply phase noise using COMM Toolbox when available.
%
% Primary implementation uses comm.PhaseNoise System object.
% Fallback implementation uses a simple Wiener phase process (approximation).
%
% This model is used by sixgr.rf.RFImpairments and can also be called directly.
%
% Configuration fields (cfg.rf.phaseNoise.*):
%   enable         : true/false
%   level_dBcHz    : vector (dBc/Hz), default -120
%   freqOffsetHz   : vector (Hz), default 1e3
%
% Sample rate is provided at construction time or via apply().
%
% Keep ASCII only.

    properties
        Enable (1,1) logical = false
        Level_dBcHz double = -120
        FrequencyOffset_Hz double = 1e3
        SampleRate_Hz (1,1) double = 1e6
        Seed (1,1) double = 1
        UseCommObj (1,1) logical = false
    end

    properties(Access=private)
        Obj
    end

    methods

        function obj = PhaseNoiseModel(cfg, sampleRateHz, seed)
            arguments
                cfg (1,1) struct
                sampleRateHz (1,1) double = NaN
                seed (1,1) double = 1
            end

            obj.Enable = logical(sixgr.util.structGet(cfg, "rf.phaseNoise.enable", false));
            obj.Level_dBcHz = double(sixgr.util.structGet(cfg, "rf.phaseNoise.level_dBcHz", -120));
            obj.FrequencyOffset_Hz = double(sixgr.util.structGet(cfg, "rf.phaseNoise.freqOffsetHz", 1e3));
            obj.Seed = seed;

            if ~isnan(sampleRateHz) && sampleRateHz > 0
                obj.SampleRate_Hz = sampleRateHz;
            else
                obj.SampleRate_Hz = double(sixgr.util.structGet(cfg, "rf.sampleRate_Hz", 1e6));
            end

            obj = obj.reset();
        end

        function obj = reset(obj, seed)
            if nargin >= 2
                obj.Seed = seed;
            end

            obj.UseCommObj = (exist("comm.PhaseNoise","class") == 8);

            if obj.UseCommObj && obj.Enable
                try
                    obj.Obj = comm.PhaseNoise( ...
                        "Level", obj.Level_dBcHz, ...
                        "FrequencyOffset", obj.FrequencyOffset_Hz, ...
                        "SampleRate", obj.SampleRate_Hz);
                catch ME
                    obj.UseCommObj = false;
                    obj.Obj = [];
                    warning("PhaseNoiseModel:CommFailed","comm.PhaseNoise init failed: %s", ME.message);
                end
            else
                obj.Obj = [];
            end
        end

        function y = apply(obj, x, sampleRateHz)
            %APPLY Apply phase noise to baseband samples.
            %
            % x: [Nsamp x Nchan] complex
            arguments
                obj
                x
                sampleRateHz (1,1) double = NaN
            end

            if ~obj.Enable
                y = x;
                return;
            end

            if ~isnan(sampleRateHz) && sampleRateHz > 0 && sampleRateHz ~= obj.SampleRate_Hz
                obj.SampleRate_Hz = sampleRateHz;
                obj = obj.reset(obj.Seed);
            end

            if obj.UseCommObj && ~isempty(obj.Obj)
                y = obj.Obj(x);
                return;
            end

            % Fallback: simple Wiener phase noise (not a mask-accurate model)
            rng(obj.Seed, "twister");
            Ns = size(x,1);

            % Choose a small linewidth proxy from the mask (very rough)
            % Higher (less negative) level -> larger sigma
            lev = obj.Level_dBcHz;
            if numel(lev) > 1
                lev = mean(lev);
            end
            sigma = 1e-3 * 10.^((lev + 120)/20); % heuristic

            dphi = sigma * randn(Ns,1);
            phi = cumsum(dphi);
            rot = exp(1j*phi);

            y = x .* rot;
        end

    end
end
