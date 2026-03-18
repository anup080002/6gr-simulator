classdef PAModel < handle
%PAMODEL Power amplifier model (memoryless baseline) for baseband simulation.
%
% Primary implementation uses comm.MemorylessNonlinearity (COMM Toolbox).
% Fallback implementation uses a smooth soft limiter.
%
% Configuration fields (cfg.rf.pa.*):
%   enable       : true/false
%   method       : "memoryless" (default) or "softlimiter"
%   gain_dB      : linear gain applied after nonlinearity
%   backoff_dB   : input backoff applied before nonlinearity
%   iip3_dBm     : input IP3 for comm.MemorylessNonlinearity (default 45)
%   ampm_deg     : AM/PM conversion (deg/dB), default 0
%
% Keep ASCII only.

    properties
        Enable (1,1) logical = false
        Method (1,:) char = "memoryless"
        Gain_dB (1,1) double = 0
        Backoff_dB (1,1) double = 0
        IIP3_dBm (1,1) double = 45
        AMPMConversion (1,1) double = 0
        UseCommObj (1,1) logical = false
    end

    properties(Access=private)
        Obj
    end

    methods

        function obj = PAModel(cfg)
            arguments
                cfg (1,1) struct
            end

            obj.Enable = logical(sixgr.util.structGet(cfg, "rf.pa.enable", false));
            obj.Method = char(sixgr.util.structGet(cfg, "rf.pa.method", "memoryless"));
            obj.Gain_dB = double(sixgr.util.structGet(cfg, "rf.pa.gain_dB", 0));
            obj.Backoff_dB = double(sixgr.util.structGet(cfg, "rf.pa.backoff_dB", 0));
            obj.IIP3_dBm = double(sixgr.util.structGet(cfg, "rf.pa.iip3_dBm", 45));
            obj.AMPMConversion = double(sixgr.util.structGet(cfg, "rf.pa.ampm_deg", 0));

            obj = obj.reset();
        end

        function obj = reset(obj)
            obj.UseCommObj = (exist("comm.MemorylessNonlinearity","class") == 8);

            if obj.UseCommObj && obj.Enable && strcmpi(string(obj.Method),"memoryless")
                try
                    obj.Obj = comm.MemorylessNonlinearity( ...
                        "IIP3", obj.IIP3_dBm, ...
                        "AMPMConversion", obj.AMPMConversion);
                catch ME
                    obj.UseCommObj = false;
                    obj.Obj = [];
                    warning("PAModel:CommFailed","comm.MemorylessNonlinearity init failed: %s", ME.message);
                end
            else
                obj.Obj = [];
            end
        end

        function y = apply(obj, x)
            %APPLY Apply PA nonlinearity + gain/backoff to baseband samples.
            arguments
                obj
                x
            end

            if ~obj.Enable
                y = x;
                return;
            end

            xin = x .* 10.^(-obj.Backoff_dB/20);

            if obj.UseCommObj && ~isempty(obj.Obj)
                ypa = obj.Obj(xin);
            else
                ypa = obj.softLimiter(xin);
            end

            y = ypa .* 10.^(obj.Gain_dB/20);
        end

    end

    methods(Access=private)

        function y = softLimiter(~, x)
            %SOFTLIMITER Smooth AM/AM (and mild AM/PM) limiter.
            %
            % This is a fallback when COMM Toolbox PA object is not available.
            A = 1.0; % saturation level in normalized units
            r = abs(x);
            g = 1 ./ sqrt(1 + (r./A).^4);
            y = x .* g;
        end

    end
end
