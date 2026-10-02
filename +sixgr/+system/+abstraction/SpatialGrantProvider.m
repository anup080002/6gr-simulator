classdef (Abstract) SpatialGrantProvider < handle
    % Spatial producers return modeled channel/precoder/power/covariance for
    % actual scheduled grants. They must account for the active interfering
    % grants supplied by SystemLevelRunner, not an assumed fully loaded cell.
    % No returned object is a received SRS/CSI waveform measurement.
    methods (Abstract)
        observation = evaluate(obj,ctx,slotContext)
    end
    methods
        function observations=observeCSI(~,~)
            error('sixgr:abstraction:MissingCSIProducer','Enabled DL feedback requires a causal CSI provider.');
            observations=struct([]); %#ok<UNRCH>
        end
        function observations=observeSRS(~,~)
            error('sixgr:abstraction:MissingSRSProducer', ...
                'Enabled SLS spatial feedback requires a provider of causal modeled SRS observations.');
            observations=struct([]); %#ok<UNRCH>
        end
    end
end
