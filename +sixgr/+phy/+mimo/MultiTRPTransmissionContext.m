classdef MultiTRPTransmissionContext
    %MULTITRPTRANSMISSIONCONTEXT Explicit NCJT/CJT timing, phase and TCI state.

    properties (SetAccess = immutable)
        Mode (1,1) string
        TRPIDs (1,:) string
        TCIStateIDs (1,:) double
        TimingMismatchFractionCP (1,1) double
        PhaseMismatchDeg (1,1) double
        PowerDBM (1,:) double
        MaxTimingMismatchFractionCP (1,1) double
        MaxPhaseMismatchDeg (1,1) double
    end

    methods
        function obj = MultiTRPTransmissionContext(options)
            arguments
                options.Mode (1,1) string
                options.TRPIDs (1,:) string
                options.TCIStateIDs (1,:) double
                options.TimingMismatchFractionCP (1,1) double {mustBeNonnegative} = 0
                options.PhaseMismatchDeg (1,1) double {mustBeNonnegative} = 0
                options.PowerDBM (1,:) double = [0 0]
                options.MaxTimingMismatchFractionCP (1,1) double {mustBeNonnegative} = 0.05
                options.MaxPhaseMismatchDeg (1,1) double {mustBeNonnegative} = 10
            end
            mode = upper(options.Mode);
            if ~ismember(mode,["NCJT","CJT"])
                error("sixgr:mimo:MissingTRPState", ...
                    "Multi-TRP mode must be NCJT or CJT.");
            end
            if numel(options.TRPIDs) ~= 2 || numel(unique(options.TRPIDs)) ~= 2 || ...
                    numel(options.TCIStateIDs) ~= 2 || any(options.TCIStateIDs <= 0)
                error("sixgr:mimo:MissingTRPState", ...
                    "Bounded multi-TRP requires two unique TRPs and two active TCI states.");
            end
            if numel(options.PowerDBM) ~= 2
                error("sixgr:mimo:MissingTRPState", ...
                    "Multi-TRP power ledger requires one entry per TRP.");
            end
            if mode == "CJT"
                if options.TimingMismatchFractionCP > options.MaxTimingMismatchFractionCP
                    error("sixgr:mimo:TRPTimingMismatch", ...
                        "CJT timing mismatch %.3g CP exceeds %.3g CP.", ...
                        options.TimingMismatchFractionCP,options.MaxTimingMismatchFractionCP);
                end
                if options.PhaseMismatchDeg > options.MaxPhaseMismatchDeg
                    error("sixgr:mimo:TRPPhaseMismatch", ...
                        "CJT phase mismatch %.3g deg exceeds %.3g deg.", ...
                        options.PhaseMismatchDeg,options.MaxPhaseMismatchDeg);
                end
            end
            obj.Mode = mode;
            obj.TRPIDs = options.TRPIDs;
            obj.TCIStateIDs = options.TCIStateIDs;
            obj.TimingMismatchFractionCP = options.TimingMismatchFractionCP;
            obj.PhaseMismatchDeg = options.PhaseMismatchDeg;
            obj.PowerDBM = options.PowerDBM;
            obj.MaxTimingMismatchFractionCP = options.MaxTimingMismatchFractionCP;
            obj.MaxPhaseMismatchDeg = options.MaxPhaseMismatchDeg;
        end

        function combined = combineSamples(obj, samples)
            if ~iscell(samples) || numel(samples) ~= 2 || ...
                    ~isequal(size(samples{1}),size(samples{2}))
                error("sixgr:mimo:MissingTRPState", ...
                    "Two aligned sample-domain TRP waveforms are required.");
            end
            x1 = 10^(obj.PowerDBM(1)/20)*samples{1};
            x2 = 10^(obj.PowerDBM(2)/20)*samples{2};
            if obj.Mode == "CJT"
                x2 = x2*exp(1i*deg2rad(obj.PhaseMismatchDeg));
                combined = x1+x2;
            else
                combined = cat(ndims(x1)+1,x1,x2);
            end
        end
    end
end
