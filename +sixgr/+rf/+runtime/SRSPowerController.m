classdef SRSPowerController
%SRSPOWERCONTROLLER Exact SRS power-control facade.
    methods(Static)
        function result=resolve(state,request)
            if ~isa(state,"sixgr.rf.runtime.UplinkPowerControlState") || ...
                    ~isstruct(request)||~isfield(request,"Channel")|| ...
                    upper(string(request.Channel))~="SRS"
                error("RF:PowerControlChannelMismatch", ...
                    "Power-control request does not match SRS.");
            end
            result=state.resolve(request);
        end
    end
end
