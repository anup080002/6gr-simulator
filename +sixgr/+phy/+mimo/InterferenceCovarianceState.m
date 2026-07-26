classdef InterferenceCovarianceState
    %INTERFERENCECOVARIANCESTATE Qualified strict IRC covariance evidence.

    properties (SetAccess = immutable)
        CovarianceID (1,1) string
        Matrix
        SampleCount (1,1) double
        MinSamples (1,1) double
        Slot (1,1) double
        MaxAgeSlots (1,1) double
        PRGID (1,1) double
        SourceResource (1,1) string
        ConditionNumber (1,1) double
        MinEigenvalue (1,1) double
        HermitianError (1,1) double
        ShrinkageFactor (1,1) double
        IncludesNoise (1,1) logical
    end

    methods
        function obj = InterferenceCovarianceState(R, options)
            arguments
                R
                options.CovarianceID (1,1) string = "cov-0"
                options.SampleCount (1,1) double {mustBeInteger,mustBeNonnegative} = 0
                options.MinSamples (1,1) double {mustBeInteger,mustBePositive} = 8
                options.Slot (1,1) double {mustBeInteger,mustBeNonnegative} = 0
                options.MaxAgeSlots (1,1) double {mustBeInteger,mustBeNonnegative} = 8
                options.PRGID (1,1) double {mustBeInteger,mustBeNonnegative} = 0
                options.SourceResource (1,1) string = "measured_interference_reference"
                options.ShrinkageFactor (1,1) double {mustBeInRange(options.ShrinkageFactor,0,1)} = 0.05
                options.ApplyShrinkage (1,1) logical = true
                options.IncludesNoise (1,1) logical = false
            end
            if isempty(R)
                error("sixgr:mimo:MissingInterferenceCovariance", ...
                    "Strict IRC requires measured interference covariance.");
            end
            if ~isnumeric(R) || ~ismatrix(R) || size(R,1) ~= size(R,2) || ...
                    any(~isfinite(real(R(:))) | ~isfinite(imag(R(:))))
                error("sixgr:mimo:InvalidInterferenceCovariance", ...
                    "Covariance must be a finite square numeric matrix.");
            end
            hermitianError = norm(R-R',"fro") / max(norm(R,"fro"),realmin);
            Rh = (R+R')/2;
            alpha = options.ShrinkageFactor;
            if alpha > 0 && options.ApplyShrinkage
                target = trace(Rh)/size(Rh,1)*eye(size(Rh,1));
                Rh = (1-alpha)*Rh+alpha*target;
            end
            eigValues = real(eig(Rh));
            traceScale = max(abs(trace(Rh)),1);
            if hermitianError > 1e-12 || min(eigValues) < -1e-10*traceScale
                error("sixgr:mimo:InvalidInterferenceCovariance", ...
                    "Covariance is not Hermitian positive semidefinite.");
            end
            if options.SampleCount < options.MinSamples
                error("sixgr:mimo:InsufficientCovarianceSamples", ...
                    "Covariance has %d samples; at least %d are required.", ...
                    options.SampleCount, options.MinSamples);
            end
            condition = cond(Rh);
            if ~isfinite(condition) || condition > 1e12
                error("sixgr:mimo:IllConditionedCovariance", ...
                    "Covariance condition number %.6g is not qualified.", condition);
            end
            obj.CovarianceID = options.CovarianceID;
            obj.Matrix = Rh;
            obj.SampleCount = options.SampleCount;
            obj.MinSamples = options.MinSamples;
            obj.Slot = options.Slot;
            obj.MaxAgeSlots = options.MaxAgeSlots;
            obj.PRGID = options.PRGID;
            obj.SourceResource = options.SourceResource;
            obj.ConditionNumber = condition;
            obj.MinEigenvalue = min(eigValues);
            obj.HermitianError = hermitianError;
            obj.ShrinkageFactor = options.ShrinkageFactor;
            obj.IncludesNoise = options.IncludesNoise;
        end

        function validateAt(obj, slotValue, prgID)
            age = double(slotValue)-obj.Slot;
            if age < 0 || age > obj.MaxAgeSlots
                error("sixgr:mimo:StaleInterferenceCovariance", ...
                    "Covariance %s is stale.", obj.CovarianceID);
            end
            if nargin >= 3 && double(prgID) ~= obj.PRGID
                error("sixgr:mimo:InvalidInterferenceCovariance", ...
                    "Covariance PRG identity does not match the scheduled PRG.");
            end
        end
    end

    methods (Static)
        function obj = estimate(samples, options)
            arguments
                samples
                options.CovarianceID (1,1) string = "cov-estimated"
                options.MinSamples (1,1) double {mustBeInteger,mustBePositive} = 8
                options.Slot (1,1) double {mustBeInteger,mustBeNonnegative} = 0
                options.MaxAgeSlots (1,1) double {mustBeInteger,mustBeNonnegative} = 8
                options.PRGID (1,1) double {mustBeInteger,mustBeNonnegative} = 0
                options.SourceResource (1,1) string = "measured_interference_reference"
                options.ShrinkageFactor (1,1) double {mustBeInRange(options.ShrinkageFactor,0,1)} = 0.05
            end
            if ~isnumeric(samples) || ndims(samples) ~= 2
                error("sixgr:mimo:InvalidInterferenceCovariance", ...
                    "Covariance samples must be Nsample-by-Nrx.");
            end
            nSamples = size(samples,1);
            if nSamples < options.MinSamples
                error("sixgr:mimo:InsufficientCovarianceSamples", ...
                    "Covariance has %d samples; at least %d are required.", ...
                    nSamples, options.MinSamples);
            end
            centered = samples - mean(samples,1);
            R = (centered' * centered) / max(1,nSamples-1);
            target = trace(R)/size(R,1) * eye(size(R,1));
            alpha = options.ShrinkageFactor;
            R = (1-alpha)*R + alpha*target;
            obj = sixgr.phy.mimo.InterferenceCovarianceState(R, ...
                CovarianceID=options.CovarianceID, SampleCount=nSamples, ...
                MinSamples=options.MinSamples, Slot=options.Slot, ...
                MaxAgeSlots=options.MaxAgeSlots, PRGID=options.PRGID, ...
                SourceResource=options.SourceResource, ShrinkageFactor=alpha, ...
                ApplyShrinkage=false,IncludesNoise=false);
        end
    end
end
