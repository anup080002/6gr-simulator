classdef HybridBeamformer
    %HYBRIDBEAMFORMER RF-chain constrained analog/digital beamformer.

    properties (SetAccess = immutable)
        Nant (1,1) double
        NRFChains (1,1) double
        NStreams (1,1) double
        PhaseQuantizationBits (1,1) double
        AnalogWeights
        DigitalWeights
        CenterFrequencyHz (1,1) double
        BandwidthHz (1,1) double
    end

    methods
        function obj = HybridBeamformer(options)
            arguments
                options.Nant (1,1) double {mustBeInteger,mustBePositive}
                options.NRFChains (1,1) double {mustBeInteger,mustBePositive}
                options.NStreams (1,1) double {mustBeInteger,mustBePositive}
                options.PhaseQuantizationBits (1,1) double {mustBeInteger,mustBePositive}
                options.CenterFrequencyHz (1,1) double {mustBePositive}
                options.BandwidthHz (1,1) double {mustBePositive}
                options.AnalogWeights = []
                options.DigitalWeights = []
            end
            if options.NStreams > options.NRFChains
                error("sixgr:mimo:RFChainLimitExceeded", ...
                    "%d streams exceed %d RF chains.", ...
                    options.NStreams,options.NRFChains);
            end
            if options.NRFChains > options.Nant
                error("sixgr:mimo:RFChainLimitExceeded", ...
                    "RF-chain count cannot exceed antenna count.");
            end
            A = options.AnalogWeights;
            if isempty(A)
                element = (0:options.Nant-1).';
                beam = 0:options.NRFChains-1;
                phase = 2*pi*element*beam/max(1,options.Nant);
                levels = 2^options.PhaseQuantizationBits;
                phase = round(mod(phase,2*pi)/(2*pi)*levels)/levels*2*pi;
                A = exp(1i*phase)/sqrt(options.Nant);
            end
            if ~isequal(size(A),[options.Nant options.NRFChains])
                error("sixgr:mimo:MissingHybridBeamState", ...
                    "Analog matrix must be Nant-by-NRFChains.");
            end
            modulusError = max(abs(abs(A(:))-1/sqrt(options.Nant)));
            if modulusError > 1e-10
                error("sixgr:mimo:AnalogWeightConstraintViolation", ...
                    "Analog weights violate the constant-modulus constraint.");
            end
            phaseStep = 2*pi/(2^options.PhaseQuantizationBits);
            phaseError = abs(angle(exp(1i*(angle(A(:))/phaseStep-round(angle(A(:))/phaseStep)))));
            if any(phaseError > 1e-9)
                error("sixgr:mimo:AnalogWeightConstraintViolation", ...
                    "Analog weights violate phase quantization.");
            end
            D = options.DigitalWeights;
            if isempty(D)
                D = eye(options.NRFChains,options.NStreams);
            end
            if ~isequal(size(D),[options.NRFChains options.NStreams])
                error("sixgr:mimo:MissingHybridBeamState", ...
                    "Digital matrix must be NRFChains-by-NStreams.");
            end
            composite = A*D;
            D = D/sqrt(sum(abs(composite(:)).^2));
            obj.Nant = options.Nant;
            obj.NRFChains = options.NRFChains;
            obj.NStreams = options.NStreams;
            obj.PhaseQuantizationBits = options.PhaseQuantizationBits;
            obj.AnalogWeights = A;
            obj.DigitalWeights = D;
            obj.CenterFrequencyHz = options.CenterFrequencyHz;
            obj.BandwidthHz = options.BandwidthHz;
        end

        function W = compositeWeights(obj)
            W = obj.AnalogWeights*obj.DigitalWeights;
        end

        function lossDB = beamSquintLoss(obj, frequencyHz, steeringAzimuthDeg)
            arguments
                obj
                frequencyHz
                steeringAzimuthDeg (1,1) double = 30
            end
            ratio = double(frequencyHz(:))/obj.CenterFrequencyHz;
            element = (0:obj.Nant-1).';
            reference = exp(1i*pi*element*sind(steeringAzimuthDeg))/sqrt(obj.Nant);
            lossDB = zeros(numel(ratio),1);
            for index = 1:numel(ratio)
                actual = exp(1i*pi*element*sind(steeringAzimuthDeg)*ratio(index))/sqrt(obj.Nant);
                gain = abs(reference'*actual)^2;
                lossDB(index) = -10*log10(max(gain,realmin));
            end
        end
    end
end
