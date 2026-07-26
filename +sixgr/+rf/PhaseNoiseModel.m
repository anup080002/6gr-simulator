classdef PhaseNoiseModel < handle
%PHASENOISEMODEL Apply oscillator phase noise in the waveform path.
%
% Primary implementation uses comm.PhaseNoise System object.
% When that backend is unavailable, use a deterministic colored PSD process
% derived from a carrier-frequency phase-noise mask instead of a white
% Gaussian or unconstrained Wiener shortcut.
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
        PreferCommBackend (1,1) logical = false
        UseCommObj (1,1) logical = false
        Backend (1,1) string = ""
        TruthClassification (1,1) string = ""
        ApproximationReason (1,1) string = ""
    end

    properties(Access=private)
        Obj
        RuntimeProcess
        RuntimeProfile struct = struct()
        StateEpoch (1,1) double = 1
        UseCanonicalRuntime (1,1) logical = false
    end

    methods

        function obj = PhaseNoiseModel(cfg, sampleRateHz, seed)
            arguments
                cfg (1,1) struct
                sampleRateHz (1,1) double = NaN
                seed (1,1) double = 1
            end

            obj.Enable = obj.localResolvePhaseNoiseEnabled(cfg);
            [obj.Level_dBcHz, obj.FrequencyOffset_Hz] = obj.localResolvePhaseNoiseMask(cfg);
            obj.PreferCommBackend = logical(sixgr.util.structGet(cfg, "rf.phaseNoise.useCommBackend", false));
            obj.Seed = seed;

            if ~isnan(sampleRateHz) && sampleRateHz > 0
                obj.SampleRate_Hz = sampleRateHz;
            else
                obj.SampleRate_Hz = double(sixgr.util.structGet(cfg, "rf.sampleRate_Hz", 1e6));
            end

            [obj.UseCanonicalRuntime,obj.RuntimeProfile,obj.StateEpoch] = ...
                obj.localResolveCanonicalProfile(cfg);

            obj = obj.reset();
        end

        function obj = reset(obj, seed)
            if nargin >= 2
                obj.Seed = seed;
            end

            obj.UseCommObj = obj.PreferCommBackend && (exist("comm.PhaseNoise","class") == 8);
            obj.Backend = "disabled";
            obj.TruthClassification = "disabled";
            obj.ApproximationReason = "";

            if ~obj.Enable
                obj.Obj = [];
                obj.RuntimeProcess = [];
                return;
            end

            if obj.UseCanonicalRuntime
                obj.RuntimeProfile.SampleRate_Hz = obj.SampleRate_Hz;
                obj.RuntimeProfile.Seed = obj.Seed;
                obj.RuntimeProfile = sixgr.rf.runtime.PhaseNoiseProfile. ...
                    validate(obj.RuntimeProfile);
                obj.RuntimeProcess = [];
                obj.UseCommObj = false;
                obj.Obj = [];
                obj.Backend = "sixgr_rf_runtime_phase_noise_process";
                obj.TruthClassification = "runtime_calibrated_mask_model";
                obj.ApproximationReason = "";
                return;
            end

            if obj.UseCommObj
                try
                    obj.Obj = comm.PhaseNoise( ...
                        "Level", obj.Level_dBcHz, ...
                        "FrequencyOffset", obj.FrequencyOffset_Hz, ...
                        "SampleRate", obj.SampleRate_Hz);
                    obj.Backend = "comm_phase_noise_runtime_backend";
                    obj.TruthClassification = "toolbox_runtime_phase_noise_backend";
                    obj.ApproximationReason = "";
                catch ME
                    obj.UseCommObj = false;
                    obj.Obj = [];
                    obj.Backend = "colored_psd_phase_noise_runtime_model";
                    obj.TruthClassification = "runtime_colored_phase_noise_model";
                    obj.ApproximationReason = "comm_phasenoise_initialization_failed_" + string(ME.identifier);
                    warning("PhaseNoiseModel:CommFailed","comm.PhaseNoise init failed: %s", ME.message);
                end
            else
                obj.Obj = [];
                obj.Backend = "colored_psd_phase_noise_runtime_model";
                obj.TruthClassification = "runtime_colored_phase_noise_model";
                obj.ApproximationReason = "";
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

            if obj.UseCanonicalRuntime
                if isempty(obj.RuntimeProcess) || ...
                        numel(obj.RuntimeProcess.Phase_rad) ~= size(x,2)
                    obj.RuntimeProcess = sixgr.rf.runtime.PhaseNoiseProcess( ...
                        obj.RuntimeProfile,size(x,2),obj.StateEpoch);
                end
                [y,~] = obj.RuntimeProcess.apply(x,obj.StateEpoch);
                return;
            end

            if obj.UseCommObj && ~isempty(obj.Obj)
                y = obj.Obj(x);
                return;
            end

            phi = obj.coloredPhaseProcess(size(x, 1));
            rot = exp(1j * phi);

            y = x .* rot;
        end

    end

    methods(Access=private)

        function enabled = localResolvePhaseNoiseEnabled(~, cfg)
            enabled = logical(sixgr.util.structGet(cfg, "rf.phaseNoise.enable", ...
                sixgr.util.structGet(cfg, "phy.impairments.phaseNoiseEnabled", ...
                sixgr.util.structGet(cfg, "impairments.phase_noise_enabled", ...
                sixgr.util.structGet(cfg, "lls6g.resolvedConfig.impairments.phase_noise_enabled", false)))));
        end

        function [levels, offsets] = localResolvePhaseNoiseMask(obj, cfg)
            levels = double(sixgr.util.structGet(cfg, "rf.phaseNoise.maskLevels_dBcHz", ...
                sixgr.util.structGet(cfg, "rf.phaseNoise.level_dBcHz", [])));
            offsets = double(sixgr.util.structGet(cfg, "rf.phaseNoise.maskOffsets_Hz", ...
                sixgr.util.structGet(cfg, "rf.phaseNoise.freqOffsetHz", [])));
            if ~isempty(levels) && ~isempty(offsets) && numel(levels) == numel(offsets)
                levels = levels(:).';
                offsets = offsets(:).';
                return;
            end

            resolved = sixgr.util.structGet(cfg, "lls6g.resolvedConfig", struct());
            model = lower(strtrim(string(sixgr.util.structGet(cfg, "rf.phaseNoise.model", ...
                sixgr.util.structGet(resolved, "impairments.phase_noise_model", ...
                sixgr.util.structGet(resolved, "impairments.phase_noise.model", ""))))));
            l0 = obj.localFirstFiniteScalar( ...
                sixgr.util.structGet(cfg, "rf.phaseNoise.L0_dBcHz", NaN), ...
                sixgr.util.structGet(cfg, "rf.phaseNoise.l0_dBcHz", NaN), ...
                sixgr.util.structGet(resolved, "impairments.phase_noise_L0_dBcHz", NaN), ...
                sixgr.util.structGet(resolved, "impairments.phase_noise.L0_dBcHz", NaN));
            f3dB = obj.localFirstFiniteScalar( ...
                sixgr.util.structGet(cfg, "rf.phaseNoise.f3dB_Hz", NaN), ...
                sixgr.util.structGet(cfg, "rf.phaseNoise.cornerFrequency_Hz", NaN), ...
                sixgr.util.structGet(resolved, "impairments.phase_noise_f3dB_Hz", NaN), ...
                sixgr.util.structGet(resolved, "impairments.phase_noise.f3dB_Hz", NaN));
            floorLevel = obj.localFirstFiniteScalar( ...
                sixgr.util.structGet(cfg, "rf.phaseNoise.floor_dBcHz", NaN), ...
                sixgr.util.structGet(resolved, "impairments.phase_noise_floor_dBcHz", NaN), ...
                sixgr.util.structGet(resolved, "impairments.phase_noise.floor_dBcHz", NaN));
            if isfinite(l0) && isfinite(f3dB) && f3dB > 0 && ...
                    (contains(model, "lorentzian") || strlength(model) == 0 || isfinite(floorLevel))
                if isempty(offsets)
                    offsets = [1e3 1e4 1e5 1e6 1e7];
                end
                [levels, offsets] = sixgr.rf.PhaseNoiseModel.lorentzianMaskFromParameters( ...
                    l0, f3dB, floorLevel, offsets);
                return;
            end

            carrierHz = double(sixgr.util.structGet(cfg, "phy.fc_Hz", ...
                sixgr.util.structGet(cfg, "channel.fc_Hz", ...
                sixgr.util.structGet(cfg, "carrierFrequencyHz", 4e9))));
            [levels, offsets] = sixgr.rf.PhaseNoiseModel.defaultMaskFromCarrier(carrierHz);
        end

        function [canonical,profile,stateEpoch] = ...
                localResolveCanonicalProfile(obj,cfg)
            canonical = false;
            profile = struct();
            stateEpoch = double(sixgr.util.structGet(cfg, ...
                "rf.configurationEpoch",1));
            profileId = string(sixgr.util.structGet(cfg, ...
                "rf.specification.profile_id",""));
            if strlength(strtrim(profileId)) == 0 || ~obj.Enable
                return;
            end
            sixgr.rf.runtime.RFSpecificationProfile.resolve(profileId);
            raw = sixgr.util.structGet(cfg,"rf.frontend.phase_noise",struct());
            if ~isstruct(raw) || isempty(fieldnames(raw))
                error("RF:PhaseNoiseMaskMissing", ...
                    "Canonical RF phase noise requires rf_frontend.phase_noise.");
            end
            profile = struct( ...
                "ProfileID",string(sixgr.util.structGet(raw,"profile_id","")), ...
                "Version",string(sixgr.util.structGet(raw,"version","")), ...
                "SampleRate_Hz",obj.SampleRate_Hz, ...
                "CarrierFrequency_Hz",double(sixgr.util.structGet(cfg, ...
                "phy.fc_Hz",sixgr.util.structGet(cfg,"channel.fc_Hz",NaN))), ...
                "MaskOffsets_Hz",double(sixgr.util.structGet( ...
                raw,"mask_offsets_hz",[])), ...
                "MaskLevels_dBcHz",double(sixgr.util.structGet( ...
                raw,"mask_levels_dbchz",[])), ...
                "LOCorrelation",double(sixgr.util.structGet( ...
                raw,"lo_correlation",NaN)), ...
                "Seed",double(sixgr.util.structGet(raw,"seed",NaN)));
            profile = sixgr.rf.runtime.PhaseNoiseProfile.validate(profile);
            canonical = true;
        end

        function value = localFirstFiniteScalar(~, varargin)
            value = NaN;
            for i = 1:nargin-1
                raw = varargin{i};
                if isempty(raw) || ~isnumeric(raw)
                    continue;
                end
                raw = double(raw(:));
                raw = raw(isfinite(raw));
                if ~isempty(raw)
                    value = raw(1);
                    return;
                end
            end
        end

        function phi = coloredPhaseProcess(obj, nSamples)
            nSamples = max(1, round(double(nSamples)));
            rs = RandStream("mt19937ar", "Seed", max(0, mod(round(double(obj.Seed)), 2^32)));
            white = randn(rs, nSamples, 1);

            freqAxis = (0:nSamples-1).' .* double(obj.SampleRate_Hz) ./ double(nSamples);
            freqAxis(freqAxis > double(obj.SampleRate_Hz) / 2) = ...
                freqAxis(freqAxis > double(obj.SampleRate_Hz) / 2) - double(obj.SampleRate_Hz);
            freqAbs = max(abs(freqAxis), 1);
            psd = obj.interpolatePSD(freqAbs);
            shape = sqrt(psd ./ max(mean(psd, "omitnan"), realmin));
            phi = real(ifft(fft(white) .* shape));
            phi = phi - mean(phi, "omitnan");

            posFreq = unique(freqAbs(freqAbs > 0 & freqAbs <= double(obj.SampleRate_Hz) / 2));
            posPSD = obj.interpolatePSD(posFreq);
            if numel(posFreq) >= 2
                phaseVar = 2 * trapz(posFreq, posPSD);
            else
                phaseVar = 0;
            end
            targetRMS = sqrt(max(phaseVar, 0));
            currentRMS = sqrt(mean(double(phi).^2, "omitnan"));
            if isfinite(targetRMS) && targetRMS > 0 && isfinite(currentRMS) && currentRMS > 0
                phi = phi .* (targetRMS / currentRMS);
            end
        end

        function psd = interpolatePSD(obj, freqAbs)
            offsets = max(double(obj.FrequencyOffset_Hz(:)), 1);
            levels = double(obj.Level_dBcHz(:));
            [offsets, order] = sort(offsets, "ascend");
            levels = levels(order);
            if numel(offsets) == 1
                levelInterp = repmat(levels(1), size(freqAbs));
            else
                levelInterp = interp1(log10(offsets), levels, log10(max(freqAbs, min(offsets))), ...
                    "linear", "extrap");
            end
            psd = max(10 .^ (levelInterp ./ 10), realmin);
        end

    end

    methods(Static)

        function [levels, offsets] = defaultMaskFromCarrier(carrierHz)
            carrierHz = double(carrierHz);
            if ~(isfinite(carrierHz) && carrierHz > 0)
                carrierHz = 4e9;
            end
            if carrierHz < 6e9
                l0 = -94; f3dB = 1e4; floorLevel = -140;
            elseif carrierHz < 15e9
                l0 = -87; f3dB = 1e4; floorLevel = -130;
            elseif carrierHz < 30e9
                l0 = -80; f3dB = 1e5; floorLevel = -120;
            else
                l0 = -73; f3dB = 1e5; floorLevel = -110;
            end
            offsets = [1e3 1e4 1e5 1e6 1e7];
            [levels, offsets] = sixgr.rf.PhaseNoiseModel.lorentzianMaskFromParameters( ...
                l0, f3dB, floorLevel, offsets);
        end

        function [levels, offsets] = lorentzianMaskFromParameters(l0_dBcHz, f3dB_Hz, floor_dBcHz, offsets)
            offsets = max(double(offsets(:)).', 1);
            l0Lin = 10.^(double(l0_dBcHz) ./ 10);
            f3dB_Hz = max(double(f3dB_Hz), eps);
            shaped = l0Lin ./ (1 + (offsets ./ f3dB_Hz).^2);
            if isfinite(double(floor_dBcHz))
                psd = shaped + 10.^(double(floor_dBcHz) ./ 10);
            else
                psd = shaped;
            end
            levels = 10 .* log10(max(psd, realmin));
        end

    end
end
