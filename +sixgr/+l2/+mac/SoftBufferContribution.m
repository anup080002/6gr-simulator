classdef SoftBufferContribution
    %SOFTBUFFERCONTRIBUTION One position-aware LLR observation.
    properties (SetAccess=immutable)
        AttemptKey
        MotherCodePositions (:,1) double
        LLR (:,1) double
        ChannelRealizationID (1,1) string
        NoiseRealizationID (1,1) string
        ReceiverSHA256 (1,1) string
    end
    methods
        function obj=SoftBufferContribution(key,positions,llr,channelID,noiseID,receiverHash)
            arguments
                key (1,1) sixgr.l2.mac.HARQAttemptKey
                positions (:,1) double {mustBeInteger,mustBeNonnegative}
                llr (:,1) double
                channelID
                noiseID
                receiverHash
            end
            if numel(positions)~=numel(llr) || numel(unique(positions))~=numel(positions)
                error("sixgr:mac:SoftBufferProvenanceMismatch", ...
                    "LLRs require unique, equally-sized mother-code positions.");
            end
            if strlength(string(receiverHash))~=64
                error("sixgr:mac:SoftBufferProvenanceMismatch", ...
                    "Receiver hash must have 64 characters.");
            end
            obj.AttemptKey=key; obj.MotherCodePositions=positions;
            obj.LLR=llr; obj.ChannelRealizationID=string(channelID);
            obj.NoiseRealizationID=string(noiseID);
            obj.ReceiverSHA256=string(receiverHash);
        end
    end
end
