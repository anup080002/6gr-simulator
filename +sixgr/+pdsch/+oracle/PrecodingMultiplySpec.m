function [output, info] = PrecodingMultiplySpec(W, input, varargin)
%PRECODINGMULTIPLYSPEC Independent explicit precoding multiply oracle.
%
%   PORTS = PrecodingMultiplySpec(W,LAYERS)
%   LAYERS = PrecodingMultiplySpec(W,PORTS,"Operation","deapply")
%
% This oracle intentionally calls neither production code nor nr* helpers.

operation = "apply";
if mod(numel(varargin), 2) ~= 0
    error("sixgr:pdsch:oracle:PrecodingMultiplySpec:BadNameValue", ...
        "Precoding oracle options must be name-value pairs.");
end
for idx = 1:2:numel(varargin)
    if lower(strtrim(string(varargin{idx}))) ~= "operation"
        error("sixgr:pdsch:oracle:PrecodingMultiplySpec:UnknownOption", ...
            "Unknown precoding oracle option '%s'.", string(varargin{idx}));
    end
    operation = lower(strtrim(string(varargin{idx + 1})));
end

if ~(isnumeric(W) && ismatrix(W) && all(isfinite(real(W(:)))) ...
        && all(isfinite(imag(W(:)))))
    error("sixgr:pdsch:oracle:PrecodingMultiplySpec:InvalidMatrix", ...
        "W must be a finite numeric two-dimensional matrix.");
end
W = complex(double(W));
if rank(W, max(size(W)) * eps(norm(W))) < size(W, 2)
    error("sixgr:pdsch:oracle:PrecodingMultiplySpec:RankDeficientMatrix", ...
        "W must have full column rank.");
end
if ~(isnumeric(input) && ismatrix(input) ...
        && all(isfinite(real(input(:)))) && all(isfinite(imag(input(:)))))
    error("sixgr:pdsch:oracle:PrecodingMultiplySpec:InvalidInput", ...
        "Precoding oracle input must be a finite numeric matrix.");
end
input = complex(double(input));

switch operation
    case "apply"
        if size(input, 1) ~= size(W, 2)
            error("sixgr:pdsch:oracle:PrecodingMultiplySpec:LayerDimensionMismatch", ...
                "Apply input must have %d layer rows.", size(W, 2));
        end
        output = W * input;
    case "deapply"
        if size(input, 1) ~= size(W, 1)
            error("sixgr:pdsch:oracle:PrecodingMultiplySpec:PortDimensionMismatch", ...
                "Deapply input must have %d port rows.", size(W, 1));
        end
        output = W \ input;
    otherwise
        error("sixgr:pdsch:oracle:PrecodingMultiplySpec:UnsupportedOperation", ...
            "Unsupported precoding oracle operation '%s'.", operation);
end

info = struct("Operation", operation, "NPorts", size(W,1), ...
    "NLayers", size(W,2), "InputColumns", size(input,2), ...
    "Implementation", "independent_explicit_matrix_algebra");
end
