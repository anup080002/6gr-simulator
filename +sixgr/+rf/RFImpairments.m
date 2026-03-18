classdef RFImpairments < handle
%RFIMPAIRMENTS Collection of baseband RF impairments (Tx/Rx) with toolbox reuse.
%
% Supported impairments:
%   - PA nonlinearity (PAModel)
%   - Phase noise (PhaseNoiseModel)
%   - I/Q amplitude + phase imbalance (uses iqimbal if available)
%   - CFO (carrier frequency offset)
%   - DC offset
%
% Configuration fields (cfg.rf.*):
%   enable
%   iqImbalance.enable, gainImbalance_dB, phaseImbalance_deg
%   cfo_Hz
%   dcOffset (complex scalar) or dcOffset_IQ (2-element)
%   sampleRate_Hz
%   phaseNoise.* (see PhaseNoiseModel)
%   pa.* (see PAModel)
%
% Notes:
% - CFO is applied as a complex exponential rotation.
% - I/Q imbalance uses Communications Toolbox iqimbal if present; else uses a
%   standard widely-linear model.
% - For code generation, provide a separate coder-friendly path in later work.

    properties
        Enable (1,1) logical = false

        SampleRate_Hz (1,1) double = 1e6

        CFO_Hz (1,1) double = 0
        % DC offset (complex is allowed, but the validation class must be numeric).
        DCOffset (1,1) double = 0

        IQEnable (1,1) logical = false
        IQGainImbalance_dB (1,1) double = 0
        IQPhaseImbalance_deg (1,1) double = 0

        PhaseNoise sixgr.rf.PhaseNoiseModel
        PA sixgr.rf.PAModel
    end

    methods

        function obj = RFImpairments(cfg, sampleRateHz, seed)
            arguments
                cfg (1,1) struct
                sampleRateHz (1,1) double = NaN
                seed (1,1) double = 1
            end

            obj.Enable = logical(sixgr.util.structGet(cfg, "rf.enable", false));

            if ~isnan(sampleRateHz) && sampleRateHz > 0
                obj.SampleRate_Hz = sampleRateHz;
            else
                obj.SampleRate_Hz = double(sixgr.util.structGet(cfg, "rf.sampleRate_Hz", 1e6));
            end

            obj.CFO_Hz = double(sixgr.util.structGet(cfg, "rf.cfo_Hz", 0));

            % DC offset can be configured either as complex or [I Q]
            if isfield(cfg, "rf") && isfield(cfg.rf, "dcOffset")
                obj.DCOffset = complex(cfg.rf.dcOffset);
            elseif isfield(cfg, "rf") && isfield(cfg.rf, "dcOffset_IQ")
                v = double(cfg.rf.dcOffset_IQ(:));
                if numel(v) >= 2
                    obj.DCOffset = complex(v(1), v(2));
                end
            end

            obj.IQEnable = logical(sixgr.util.structGet(cfg, "rf.iqImbalance.enable", false));
            obj.IQGainImbalance_dB = double(sixgr.util.structGet(cfg, "rf.iqImbalance.gainImbalance_dB", 0));
            obj.IQPhaseImbalance_deg = double(sixgr.util.structGet(cfg, "rf.iqImbalance.phaseImbalance_deg", 0));

            obj.PhaseNoise = sixgr.rf.PhaseNoiseModel(cfg, obj.SampleRate_Hz, seed);
            obj.PA = sixgr.rf.PAModel(cfg);
        end

        function y = applyTx(obj, x)
            %APPLYTX Apply transmitter-side impairments.
            y = x;
            if ~obj.Enable
                return;
            end

            % PA first (memoryless baseband model)
            y = obj.PA.apply(y);

            % IQ imbalance
            if obj.IQEnable
                y = obj.applyIQImbalance(y, obj.IQGainImbalance_dB, obj.IQPhaseImbalance_deg);
            end

            % Phase noise
            y = obj.PhaseNoise.apply(y, obj.SampleRate_Hz);

            % CFO
            if obj.CFO_Hz ~= 0
                y = obj.applyCFO(y, obj.CFO_Hz, obj.SampleRate_Hz);
            end

            % DC offset
            if obj.DCOffset ~= 0
                y = y + obj.DCOffset;
            end
        end

        function y = applyRx(obj, x)
            %APPLYRX Apply receiver-side impairments (optional).
            %
            % For now, we mirror Tx options. Later, separate Rx-specific knobs
            % can be added (LNA NF, AGC, ADC quantization, etc.).
            y = x;
            if ~obj.Enable
                return;
            end

            if obj.IQEnable
                y = obj.applyIQImbalance(y, obj.IQGainImbalance_dB, obj.IQPhaseImbalance_deg);
            end

            y = obj.PhaseNoise.apply(y, obj.SampleRate_Hz);

            if obj.CFO_Hz ~= 0
                y = obj.applyCFO(y, obj.CFO_Hz, obj.SampleRate_Hz);
            end

            if obj.DCOffset ~= 0
                y = y + obj.DCOffset;
            end
        end

    end

    methods(Access=private)

        function y = applyCFO(~, x, cfoHz, fs)
            Ns = size(x,1);
            n = (0:Ns-1).';
            rot = exp(1j*2*pi*(cfoHz/fs)*n);
            y = x .* rot;
        end

        function y = applyIQImbalance(~, x, gainImb_dB, phaseImb_deg)
            % Try Communications Toolbox iqimbal first
            if exist("iqimbal","file") == 2 || exist("iqimbal","file") == 6
                try
                    y = iqimbal(x, gainImb_dB, phaseImb_deg);
                    return;
                catch
                    % Fall back to manual
                end
            end

            g = 10.^(gainImb_dB/20);
            phi = phaseImb_deg*pi/180;

            alpha = 0.5*(1 + g*exp(-1j*phi));
            beta  = 0.5*(1 - g*exp( 1j*phi));

            y = alpha*x + beta*conj(x);
        end

    end
end
