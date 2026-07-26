classdef PUSCHPowerController
%PUSCHPOWERCONTROLLER Exact-channel facade over event-sourced UL state.
    methods(Static)
        function result=resolve(state,request)
            result=sixgr.rf.runtime.PUSCHPowerController.resolveFor( ...
                state,request,"PUSCH");
        end
    end
    methods(Static,Access=private)
        function result=resolveFor(state,request,channel)
            if ~isa(state,"sixgr.rf.runtime.UplinkPowerControlState") || ...
                    ~isstruct(request) || ~isfield(request,"Channel") || ...
                    upper(string(request.Channel))~=channel
                error("RF:PowerControlChannelMismatch", ...
                    "Power-control request does not match %s.",channel);
            end
            result=state.resolve(request);
        end
    end
end
