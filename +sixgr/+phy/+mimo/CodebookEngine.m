classdef CodebookEngine
    %CODEBOOKENGINE Bounded, profile-aware precoder candidate authority.

    methods (Static)
        function result = enumerate(request)
            arguments
                request (1,1) struct
            end
            ports = localInteger(request, "Ports");
            rankValue = localInteger(request, "Rank");
            codebookType = lower(string(localField(request, "CodebookType", "")));
            profileID = string(localField(request, "ProfileID", ""));
            if strlength(profileID) == 0
                error("sixgr:mimo:UnsupportedProfile", ...
                    "Strict codebook enumeration requires ProfileID.");
            end
            sixgr.phy.mimo.MIMOCapabilityProfile().resolve(request);
            if ports == 2 && contains(codebookType, "typei") && ...
                    contains(codebookType, "single")
                matrices = sixgr.phy.mimo.TypeI2PortCodebook.enumerate(rankValue);
                indices = (0:size(matrices,3)-1).';
                result = localResult(matrices, indices, request, ...
                    "TS38.214-V18.9.0-Table5.2.2.2.1-1");
                return;
            end

            % The public R2026a 5G Toolbox CSI report implementation is the
            % release-pinned production authority for the enabled larger
            % Type-I/Type-II tuples. Candidate enumeration is intentionally
            % fail-closed until a frozen independent matrix pack exists.
            error("sixgr:mimo:UnsupportedProfile", ...
                "Strict candidate enumeration for profile %s (%s, %d ports, " + ...
                "rank %d) requires its frozen independent matrix pack; the " + ...
                "two-port Type-I floor is the currently enabled enumerated subset.", ...
                profileID, codebookType, ports, rankValue);
        end

        function [W, decision] = select(H, candidates, options)
            arguments
                H
                candidates
                options.NoiseVariance (1,1) double {mustBeNonnegative} = 1
                options.InterferenceCovariance = []
                options.Receiver (1,1) string = "MMSE"
                options.Objective (1,1) string = "posteq_mutual_information"
            end
            if isempty(H) || ~isnumeric(H)
                error("sixgr:mimo:MissingMeasurementState", ...
                    "Codebook selection requires a measured channel.");
            end
            if ndims(candidates) < 3
                candidates = reshape(candidates, size(candidates,1), ...
                    size(candidates,2), 1);
            end
            if size(H,2) ~= size(candidates,1)
                error("sixgr:mimo:PrecoderDimensionMismatch", ...
                    "Measured channel ports do not match codebook ports.");
            end
            nRx = size(H,1);
            if isempty(options.InterferenceCovariance)
                if upper(options.Receiver) == "IRC"
                    error("sixgr:mimo:MissingInterferenceCovariance", ...
                        "Strict IRC selection requires qualified covariance state.");
                end
                R = options.NoiseVariance * eye(nRx);
            elseif isa(options.InterferenceCovariance, ...
                    "sixgr.phy.mimo.InterferenceCovarianceState")
                R = double(options.InterferenceCovariance.Matrix);
                if ~options.InterferenceCovariance.IncludesNoise
                    R = R + options.NoiseVariance*eye(nRx);
                end
            else
                if upper(options.Receiver) == "IRC"
                    error("sixgr:mimo:InvalidInterferenceCovariance", ...
                        "Strict IRC requires covariance metadata, not a bare matrix.");
                end
                R = double(options.InterferenceCovariance);
                if ~isequal(size(R),[nRx nRx]) || ...
                        norm(R-R',"fro") > 1e-12 || min(real(eig((R+R')/2))) < -1e-10
                    error("sixgr:mimo:InvalidInterferenceCovariance", ...
                        "Interference covariance is invalid.");
                end
                R = R + options.NoiseVariance*eye(nRx);
            end
            metric = zeros(size(candidates,3),1);
            for index = 1:size(candidates,3)
                Wi = candidates(:,:,index);
                G = double(H) * double(Wi);
                gram = G' * (R \ G);
                metric(index) = real(log2(det(eye(size(gram)) + gram)));
            end
            [bestMetric, bestIndex] = max(metric);
            W = candidates(:,:,bestIndex);
            decision = struct( ...
                "CandidateMetric", metric, ...
                "SelectedIndex", bestIndex-1, ...
                "SelectedMetric", bestMetric, ...
                "Objective", options.Objective, ...
                "Receiver", options.Receiver, ...
                "ConfiguredSNRUsed", false, ...
                "SVDThresholdUsed", false, ...
                "MatrixSHA256", sixgr.phy.mimo.MatrixContract.digest(W));
        end
    end
end

function value = localField(s, name, defaultValue)
if isfield(s,name) && ~isempty(s.(name))
    value = s.(name);
else
    value = defaultValue;
end
end

function value = localInteger(s, name)
value = double(localField(s,name,NaN));
if ~(isscalar(value) && isfinite(value) && value >= 1 && value == round(value))
    error("sixgr:mimo:UnsupportedAntennaTuple", ...
        "%s must be a positive integer.", name);
end
end

function result = localResult(matrices, indices, request, specification)
nCandidates = size(matrices,3);
digests = strings(nCandidates,1);
power = zeros(nCandidates,1);
orthogonality = zeros(nCandidates,1);
for index = 1:nCandidates
    info = sixgr.phy.mimo.MatrixContract.validate( ...
        matrices(:,:,index), size(matrices,1), size(matrices,2));
    digests(index) = info.MatrixSHA256;
    power(index) = info.FrobeniusPower;
    orthogonality(index) = info.OrthogonalityError;
end
result = struct( ...
    "ProfileID", string(request.ProfileID), ...
    "CodebookType", string(request.CodebookType), ...
    "Ports", size(matrices,1), ...
    "Rank", size(matrices,2), ...
    "Matrices", matrices, ...
    "CandidateIndices", indices, ...
    "MatrixSHA256", digests, ...
    "FrobeniusPower", power, ...
    "OrthogonalityError", orthogonality, ...
    "GenericDFTApproximationUsed", false, ...
    "Specification", string(specification));
end
