classdef PAModel < handle
%PAMODEL Power amplifier model for baseband simulation.
%
% The memoryless method uses comm.MemorylessNonlinearity (COMM Toolbox).
% Soft limiter and memory polynomial are explicit model selections, never
% substitutions for a missing or failed requested implementation.
%
% Configuration fields (cfg.rf.pa.*):
%   enable       : true/false
%   method       : "memoryless" (default), "softlimiter", or "memorypolynomial"
%   gain_dB      : linear gain applied after nonlinearity
%   backoff_dB   : input backoff applied before nonlinearity
%   iip3_dBm     : input IP3 for comm.MemorylessNonlinearity (default 45)
%   ampm_deg     : AM/PM conversion (deg/dB), default 0
%   memory.*     : memory polynomial taps/orders/weights
%
% Keep ASCII only.

    properties
        Enable (1,1) logical = false
        Method (1,:) char = "memoryless"
        Gain_dB (1,1) double = 0
        Backoff_dB (1,1) double = 0
        IIP3_dBm (1,1) double = 45
        AMPMConversion (1,1) double = 0
        MemoryEnabled (1,1) logical = false
        MemoryTaps double = [1 0.15 0.05]
        MemoryOrders double = [1 3 5]
        MemoryOrderWeights double = [1 -0.12 0.02]
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
            obj.MemoryEnabled = logical(sixgr.util.structGet(cfg, "rf.pa.memory.enable", ...
                strcmpi(string(obj.Method), "memorypolynomial")));
            if obj.Enable
                if ~any(strcmpi(string(obj.Method),["memoryless","softlimiter","memorypolynomial"]))
                    error("PAModel:UnsupportedMethod","Unsupported PA method '%s'.",obj.Method);
                end
                if obj.MemoryEnabled ~= strcmpi(string(obj.Method),"memorypolynomial")
                    error("PAModel:ConflictingMemoryAuthority", ...
                        "rf.pa.memory.enable must agree with the selected rf.pa.method '%s'.",obj.Method);
                end
            end
            obj.MemoryTaps = obj.localFiniteVector(sixgr.util.structGet(cfg, "rf.pa.memory.taps", obj.MemoryTaps), obj.MemoryTaps);
            obj.MemoryOrders = obj.localFiniteVector(sixgr.util.structGet(cfg, "rf.pa.memory.orders", obj.MemoryOrders), obj.MemoryOrders);
            obj.MemoryOrders = obj.MemoryOrders(mod(round(obj.MemoryOrders), 2) == 1 & obj.MemoryOrders >= 1);
            if isempty(obj.MemoryOrders)
                obj.MemoryOrders = [1 3 5];
            end
            obj.MemoryOrderWeights = obj.localFiniteVector(sixgr.util.structGet(cfg, "rf.pa.memory.orderWeights", obj.MemoryOrderWeights), obj.MemoryOrderWeights);
            if numel(obj.MemoryOrderWeights) < numel(obj.MemoryOrders)
                obj.MemoryOrderWeights(end+1:numel(obj.MemoryOrders)) = 0;
            end
            obj.MemoryOrderWeights = obj.MemoryOrderWeights(1:numel(obj.MemoryOrders));

            obj = obj.reset();
        end

        function obj = reset(obj)
            obj.UseCommObj = false;
            obj.Obj = [];
            if obj.Enable && strcmpi(string(obj.Method),"memoryless") && ~obj.MemoryEnabled
                if exist("comm.MemorylessNonlinearity","class") ~= 8
                    error("PAModel:BackendUnavailable", ...
                        "The requested memoryless PA requires comm.MemorylessNonlinearity; no substitute model is allowed.");
                end
                try
                    obj.Obj = comm.MemorylessNonlinearity( ...
                        "Method", "Cubic polynomial", ...
                        "IIP3", obj.IIP3_dBm, ...
                        "AMPMConversion", obj.AMPMConversion);
                    obj.UseCommObj = true;
                catch ME
                    failure = MException("PAModel:BackendInitializationFailed", ...
                        "The requested memoryless PA could not initialize: %s",ME.message);
                    throwAsCaller(addCause(failure,ME));
                end
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

            if obj.MemoryEnabled
                ypa = obj.memoryPolynomial(xin);
            elseif obj.UseCommObj && ~isempty(obj.Obj)
                ypa = obj.Obj(xin);
            else
                ypa = obj.softLimiter(xin);
            end

            % The native memoryless object already owns AM/PM conversion.
            % Applying the separate envelope law again double-counts it.
            if ~obj.UseCommObj
                ypa = obj.applyAMPM(ypa, xin);
            end
            y = ypa .* 10.^(obj.Gain_dB/20);
        end

    end

    methods(Access=private)

        function y = softLimiter(~, x)
            %SOFTLIMITER Explicit normalized p=2 Rapp AM/AM limiter.
            %
            A = 1.0; % saturation level in normalized units
            r = abs(x);
            % Normalized Rapp smoothness p=2: the denominator exponent is
            % 1/(2*p), not 1/2. A square root makes large inputs fold back
            % toward zero instead of approaching the saturation amplitude.
            % Evaluate reciprocal ratios above saturation to avoid r.^4
            % overflowing while preserving the same transfer function.
            g = zeros(size(r),"like",r);
            below = r <= A;
            g(below) = (1 + (r(below)./A).^4).^(-1/4);
            inverseRatio = A ./ r(~below);
            g(~below) = inverseRatio .* (1 + inverseRatio.^4).^(-1/4);
            y = x .* g;
        end

        function y = memoryPolynomial(obj, x)
            y = complex(zeros(size(x), "like", x));
            taps = double(obj.MemoryTaps(:).');
            orders = max(1, round(double(obj.MemoryOrders(:).')));
            weights = double(obj.MemoryOrderWeights(:).');
            n = size(x, 1);
            for mi = 1:numel(taps)
                delay = mi - 1;
                xd = complex(zeros(size(x), "like", x));
                if delay == 0
                    xd = x;
                elseif n > delay
                    xd(1+delay:end, :) = x(1:end-delay, :);
                end
                for oi = 1:numel(orders)
                    p = orders(oi);
                    coeff = taps(mi) .* weights(oi);
                    y = y + coeff .* xd .* abs(xd).^(p - 1);
                end
            end
        end

        function y = applyAMPM(obj, x, ref)
            y = x;
            if ~(isfinite(obj.AMPMConversion) && abs(obj.AMPMConversion) > 0)
                return;
            end
            envelopeDb = 20 .* log10(max(abs(ref), eps));
            phaseRad = obj.AMPMConversion .* envelopeDb .* pi ./ 180;
            y = x .* exp(1j .* phaseRad);
        end

        function value = localFiniteVector(~, raw, fallback)
            value = double(fallback(:).');
            if isempty(raw) || ~isnumeric(raw)
                return;
            end
            raw = double(raw(:).');
            raw = raw(isfinite(raw));
            if ~isempty(raw)
                value = raw;
            end
        end

    end
end
