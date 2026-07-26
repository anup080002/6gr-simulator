classdef MUMIMOTransmissionContext
    %MUMIMOTRANSMISSIONCONTEXT Shared-resource MU-MIMO identity authority.

    properties (SetAccess = immutable)
        UEIDs (1,:) string
        SharedPRBs (1,:) double
        SharedSymbols (1,:) double
        DMRSIdentities (1,:) double
        Precoders
        PowerDBM (1,:) double
        Receiver (1,1) string
    end

    methods
        function obj = MUMIMOTransmissionContext(options)
            arguments
                options.UEIDs (1,:) string
                options.SharedPRBs (1,:) double
                options.SharedSymbols (1,:) double
                options.DMRSIdentities (1,:) double
                options.Precoders
                options.PowerDBM (1,:) double
                options.Receiver (1,1) string = "IRC"
            end
            nUE = numel(options.UEIDs);
            if ~ismember(nUE,[2 4]) || isempty(options.SharedPRBs) || isempty(options.SharedSymbols)
                error("sixgr:mimo:InvalidMUResourceSharing", ...
                    "The bounded MU profile requires 2 or 4 UEs on one explicit shared resource.");
            end
            if numel(unique(options.UEIDs)) ~= nUE || ...
                    numel(options.DMRSIdentities) ~= nUE || ...
                    numel(unique(options.DMRSIdentities)) ~= nUE
                error("sixgr:mimo:MUIdentityCollision", ...
                    "MU UE and DM-RS identities must be unique.");
            end
            if numel(options.PowerDBM) ~= nUE
                error("sixgr:mimo:InvalidMUResourceSharing", ...
                    "MU power ledger requires one value per UE.");
            end
            if ~iscell(options.Precoders) || numel(options.Precoders) ~= nUE
                error("sixgr:mimo:InvalidMUResourceSharing", ...
                    "MU context requires one immutable precoder per UE.");
            end
            for index = 1:nUE
                W = options.Precoders{index};
                sixgr.phy.mimo.MatrixContract.validate(W,size(W,1),size(W,2));
            end
            if upper(options.Receiver) == "IRC"
                % Covariance is supplied and qualified at receive time; the
                % context deliberately does not invent it from geometry.
            elseif ~ismember(upper(options.Receiver),["MMSE","ZF"])
                error("sixgr:mimo:InvalidMUResourceSharing", ...
                    "Unsupported MU receiver %s.",options.Receiver);
            end
            obj.UEIDs = options.UEIDs;
            obj.SharedPRBs = options.SharedPRBs;
            obj.SharedSymbols = options.SharedSymbols;
            obj.DMRSIdentities = options.DMRSIdentities;
            obj.Precoders = options.Precoders;
            obj.PowerDBM = options.PowerDBM;
            obj.Receiver = upper(options.Receiver);
        end

        function composite = combine(obj, waveforms)
            if ~iscell(waveforms) || numel(waveforms) ~= numel(obj.UEIDs)
                error("sixgr:mimo:InvalidMUResourceSharing", ...
                    "One sample-domain waveform per scheduled UE is required.");
            end
            sizes = cellfun(@(x)size(x),waveforms,'UniformOutput',false);
            if any(~cellfun(@(x)isequal(x,sizes{1}),sizes))
                error("sixgr:mimo:InvalidMUResourceSharing", ...
                    "MU waveforms must occupy the same samples and ports.");
            end
            composite = zeros(sizes{1},'like',waveforms{1});
            for index = 1:numel(waveforms)
                scale = 10^(obj.PowerDBM(index)/20);
                composite = composite + scale*waveforms{index};
            end
        end
    end
end
