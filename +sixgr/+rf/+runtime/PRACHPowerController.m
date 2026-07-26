classdef PRACHPowerController
%PRACHPOWERCONTROLLER Exact PRACH power-control facade.
    methods(Static)
        function result=resolve(state,request)
            if ~isa(state,"sixgr.rf.runtime.UplinkPowerControlState") || ...
                    ~isstruct(request)||~isfield(request,"Channel")|| ...
                    upper(string(request.Channel))~="PRACH"
                error("RF:PowerControlChannelMismatch", ...
                    "Power-control request does not match PRACH.");
            end
            result=state.resolve(request);
        end
    end
end
