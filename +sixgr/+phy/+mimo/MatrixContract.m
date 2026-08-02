classdef MatrixContract
    %MATRIXCONTRACT Immutable Nport-by-Nlayer precoder validation.

    methods (Static)
        function info = validate(W, nPorts, nLayers, options)
            arguments
                W
                nPorts (1,1) double {mustBeInteger,mustBePositive}
                nLayers (1,1) double {mustBeInteger,mustBePositive}
                options.PowerTolerance (1,1) double {mustBeNonnegative} = 1e-10
                options.ExpectedDigest (1,1) string = ""
            end
            if ~isnumeric(W) || ~isequal(size(W), [nPorts nLayers])
                error("sixgr:mimo:PrecoderDimensionMismatch", ...
                    "Precoder must be exactly Nport-by-Nlayer (%d-by-%d); received %s.", ...
                    nPorts, nLayers, mat2str(size(W)));
            end
            if any(~isfinite(real(W(:))) | ~isfinite(imag(W(:))))
                error("sixgr:mimo:PrecoderNormalizationMismatch", ...
                    "Precoder contains nonfinite coefficients.");
            end
            froPower = sum(abs(W(:)).^2);
            if abs(froPower - 1) > options.PowerTolerance
                error("sixgr:mimo:PrecoderNormalizationMismatch", ...
                    "Precoder Frobenius power %.16g differs from one.", froPower);
            end
            digest = sixgr.phy.mimo.MatrixContract.digest(W);
            if strlength(options.ExpectedDigest) > 0 && digest ~= options.ExpectedDigest
                error("sixgr:mimo:PrecoderDigestMismatch", ...
                    "Selected precoder digest %s differs from applied digest %s.", ...
                    options.ExpectedDigest, digest);
            end
            gram = W' * W;
            info = struct( ...
                "Orientation", "Nport_by_Nlayer", ...
                "Rows", nPorts, ...
                "Columns", nLayers, ...
                "FrobeniusPower", double(froPower), ...
                "OrthogonalityError", double(norm(gram - trace(gram)/nLayers*eye(nLayers), "fro")), ...
                "MatrixSHA256", digest);
        end

        function digest = digest(W)
            if ~isnumeric(W)
                error("sixgr:mimo:PrecoderDimensionMismatch", ...
                    "Only numeric matrices have a precoder digest.");
            end
            header = uint8(unicode2native(sprintf( ...
                "sixgr-mimo-matrix-v1|%s|%s|", class(W), mat2str(size(W))), "UTF-8"));
            re = typecast(double(real(W(:))), "uint8");
            im = typecast(double(imag(W(:))), "uint8");
            digest = string(sixgr.util.sha256Hex([header(:); re(:); im(:)]));
        end

        function assertApplied(selectedW, appliedW)
            selectedDigest = sixgr.phy.mimo.MatrixContract.digest(selectedW);
            appliedDigest = sixgr.phy.mimo.MatrixContract.digest(appliedW);
            if selectedDigest ~= appliedDigest
                error("sixgr:mimo:PrecoderDigestMismatch", ...
                    "Selected precoder digest %s differs from applied digest %s.", ...
                    selectedDigest, appliedDigest);
            end
        end

        function token = serialize(W)
            %SERIALIZE Persist an exact finite complex matrix with a digest.
            if ~isnumeric(W) || isempty(W) || ...
                    any(~isfinite(real(W(:))) | ~isfinite(imag(W(:))))
                error("sixgr:mimo:InvalidSerializedMatrix", ...
                    "Only nonempty finite numeric matrices can be serialized.");
            end
            W = double(W);
            payload = struct( ...
                "ContractVersion", "sixgr_complex_matrix/v1", ...
                "Rows", double(size(W, 1)), ...
                "Columns", double(size(W, 2)), ...
                "RealColumnMajor", double(real(W(:)).'), ...
                "ImagColumnMajor", double(imag(W(:)).'), ...
                "MatrixSHA256", char(sixgr.phy.mimo.MatrixContract.digest(W)));
            token = string(jsonencode(payload));
        end

        function W = deserialize(token, options)
            %DESERIALIZE Reconstruct and verify a serialized complex matrix.
            arguments
                token (1,1) string
                options.ExpectedDigest (1,1) string = ""
            end
            if strlength(strtrim(token)) == 0
                error("sixgr:mimo:InvalidSerializedMatrix", ...
                    "Serialized matrix token is empty.");
            end
            try
                payload = jsondecode(char(token));
            catch ME
                error("sixgr:mimo:InvalidSerializedMatrix", ...
                    "Serialized matrix JSON is invalid: %s", ME.message);
            end
            required = ["ContractVersion","Rows","Columns", ...
                "RealColumnMajor","ImagColumnMajor","MatrixSHA256"];
            if ~isstruct(payload) || ~all(isfield(payload, cellstr(required))) || ...
                    string(payload.ContractVersion) ~= "sixgr_complex_matrix/v1"
                error("sixgr:mimo:InvalidSerializedMatrix", ...
                    "Serialized matrix does not satisfy sixgr_complex_matrix/v1.");
            end
            nRows = double(payload.Rows);
            nCols = double(payload.Columns);
            re = double(payload.RealColumnMajor(:));
            im = double(payload.ImagColumnMajor(:));
            if ~(isscalar(nRows) && isfinite(nRows) && nRows >= 1 && nRows == fix(nRows) && ...
                    isscalar(nCols) && isfinite(nCols) && nCols >= 1 && nCols == fix(nCols) && ...
                    numel(re) == nRows * nCols && numel(im) == nRows * nCols && ...
                    all(isfinite(re)) && all(isfinite(im)))
                error("sixgr:mimo:InvalidSerializedMatrix", ...
                    "Serialized matrix dimensions or coefficients are invalid.");
            end
            W = reshape(complex(re, im), nRows, nCols);
            actualDigest = sixgr.phy.mimo.MatrixContract.digest(W);
            storedDigest = string(payload.MatrixSHA256);
            if actualDigest ~= storedDigest || ...
                    (strlength(options.ExpectedDigest) > 0 && actualDigest ~= options.ExpectedDigest)
                error("sixgr:mimo:PrecoderDigestMismatch", ...
                    "Serialized matrix digest verification failed.");
            end
        end
    end
end
