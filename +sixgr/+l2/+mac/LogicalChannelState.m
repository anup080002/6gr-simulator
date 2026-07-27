classdef LogicalChannelState < handle
    %LOGICALCHANNELSTATE Exact PBR/BSD/Bj token-bucket state.
    properties (SetAccess=private)
        LCID (1,1) double
        LCGID (1,1) double
        Priority (1,1) double
        PBR_kBps (1,1) double
        BSD_ms (1,1) double
        Bj_Bytes (1,1) double
        QueueBytes (1,1) double = 0
        AllowedServingCells (1,:) double
        AllowedSCS_kHz (1,:) double
    end
    methods
        function obj=LogicalChannelState(data)
            arguments
                data (1,1) struct
            end
            required=["LCID","LCGID","Priority","PBR_kBps","BSD_ms", ...
                "AllowedServingCells","AllowedSCS_kHz"];
            for field=required
                if ~isfield(data,field)
                    error("sixgr:mac:MissingLogicalChannelConfig", ...
                        "Logical channel requires %s.",field);
                end
            end
            obj.LCID=data.LCID; obj.LCGID=data.LCGID;
            obj.Priority=data.Priority; obj.PBR_kBps=data.PBR_kBps;
            obj.BSD_ms=data.BSD_ms; obj.Bj_Bytes=0;
            obj.AllowedServingCells=double(data.AllowedServingCells);
            obj.AllowedSCS_kHz=double(data.AllowedSCS_kHz);
        end
        function update(obj,elapsedMS)
            capacity=obj.PBR_kBps*obj.BSD_ms;
            obj.Bj_Bytes=min(capacity,obj.Bj_Bytes+obj.PBR_kBps*elapsedMS);
        end
        function enqueue(obj,bytes)
            validateattributes(bytes,{'numeric'},{'scalar','integer','nonnegative'});
            obj.QueueBytes=obj.QueueBytes+bytes;
        end
        function selected=serve(obj,maxBytes,cellID,scsKHz)
            if ~ismember(cellID,obj.AllowedServingCells) || ...
                    ~ismember(scsKHz,obj.AllowedSCS_kHz)
                error("sixgr:mac:LogicalChannelRestriction", ...
                    "Logical channel is not legal on this cell/SCS.");
            end
            selected=min([maxBytes,obj.QueueBytes,obj.Bj_Bytes]);
            obj.QueueBytes=obj.QueueBytes-selected;
            obj.Bj_Bytes=obj.Bj_Bytes-selected;
        end
    end
    methods (Static)
        function value=nextBj(previousBj,pbrKBps,bsdMS,elapsedMS)
            if double(pbrKBps)<0
                value=Inf;
                return;
            end
            capacity=double(pbrKBps)*double(bsdMS);
            value=min(capacity,double(previousBj)+double(pbrKBps)*double(elapsedMS));
        end
    end
end
