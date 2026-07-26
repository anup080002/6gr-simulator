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
    end
end
