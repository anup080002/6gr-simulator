classdef MACConfigurationEpoch
    %MACCONFIGURATIONEPOCH Immutable configuration identity.

    properties (SetAccess=immutable)
        Epoch (1,1) double
        Digest (1,1) string
    end

    methods
        function obj = MACConfigurationEpoch(epoch, resolvedConfig)
            arguments
                epoch (1,1) double {mustBeInteger,mustBeNonnegative}
                resolvedConfig (1,1) struct
            end
            obj.Epoch = epoch;
            obj.Digest = sixgr.l2.mac.MACHash.of(resolvedConfig);
        end
    end
end
