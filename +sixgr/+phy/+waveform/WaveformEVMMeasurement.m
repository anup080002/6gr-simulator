classdef WaveformEVMMeasurement
    %WAVEFORMEVMMEASUREMENT Reference-normalized waveform/grid EVM.

    methods (Static)
        function result = measure(reference,actual,varargin)
            ip = inputParser;
            ip.addParameter("ReferenceDomain","resource_grid", ...
                @(x)ischar(x)||isstring(x));
            ip.parse(varargin{:});
            if ~isequal(size(reference),size(actual))
                error("WAVEFORM:InvalidOFDMParameters", ...
                    "EVM reference and measured arrays must have equal size.");
            end
            if any(~isfinite(reference),"all") || any(~isfinite(actual),"all")
                error("WAVEFORM:NonFiniteSamples", ...
                    "EVM inputs must contain only finite samples.");
            end
            referencePower = mean(abs(double(reference(:))).^2);
            errorPower = mean(abs(double(actual(:)-reference(:))).^2);
            normalized = errorPower/max(referencePower,eps);
            result = struct( ...
                "ReferenceDomain",string(ip.Results.ReferenceDomain), ...
                "ReferencePower",referencePower, ...
                "ErrorPower",errorPower, ...
                "NMSE",normalized, ...
                "EVM_pct",100*sqrt(normalized), ...
                "Status",localStatus(isfinite(normalized)));
        end
    end
end

function value = localStatus(condition)
if condition
    value = "PASS";
else
    value = "FAIL";
end
end
