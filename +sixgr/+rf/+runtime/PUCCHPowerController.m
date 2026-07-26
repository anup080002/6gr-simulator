classdef PUCCHPowerController
%PUCCHPOWERCONTROLLER Exact PUCCH power-control facade.
    methods(Static)
        function result=resolve(state,request)
            if ~isa(state,"sixgr.rf.runtime.UplinkPowerControlState") || ...
                    ~isstruct(request)||~isfield(request,"Channel")|| ...
                    upper(string(request.Channel))~="PUCCH"
                error("RF:PowerControlChannelMismatch", ...
                    "Power-control request does not match PUCCH.");
            end
            result=state.resolve(request);
        end
    end
end
