classdef HARQTBKey
    %HARQTBKEY Immutable TB identity across every retransmission.

    properties (SetAccess=immutable)
        Direction (1,1) string
        ServingCell (1,1) double
        UEID (1,1) double
        HARQProcess (1,1) double
        Codeword (1,1) double
        NDIEpoch (1,1) double
        TBID (1,1) string
        BWPID (1,1) double
        ConfigurationEpoch (1,1) double
        Digest (1,1) string
    end

    methods
        function obj=HARQTBKey(direction,cellID,ueID,processID,codeword, ...
                ndiEpoch,tbID,bwpID,configurationEpoch)
            arguments
                direction
                cellID (1,1) double {mustBeInteger,mustBeNonnegative}
                ueID (1,1) double {mustBeInteger,mustBeNonnegative}
                processID (1,1) double {mustBeInteger,mustBeNonnegative}
                codeword (1,1) double {mustBeInteger,mustBeNonnegative}
                ndiEpoch (1,1) double {mustBeInteger,mustBeNonnegative}
                tbID
                bwpID (1,1) double {mustBeInteger,mustBeNonnegative}
                configurationEpoch (1,1) double {mustBeInteger,mustBeNonnegative}
            end
            d=upper(string(direction));
            if ~ismember(d,["DL","UL"])
                error("sixgr:mac:InvalidDirection","Direction must be DL or UL.");
            end
            if strlength(string(tbID))==0
                error("sixgr:mac:HARQIdentityMissing","TBID is mandatory.");
            end
            obj.Direction=d; obj.ServingCell=cellID; obj.UEID=ueID;
            obj.HARQProcess=processID; obj.Codeword=codeword;
            obj.NDIEpoch=ndiEpoch; obj.TBID=string(tbID);
            obj.BWPID=bwpID; obj.ConfigurationEpoch=configurationEpoch;
            obj.Digest=sixgr.l2.mac.MACHash.of(obj.asStruct());
        end

        function value=asStruct(obj)
            value=struct("Direction",obj.Direction, ...
                "ServingCell",obj.ServingCell,"UEID",obj.UEID, ...
                "HARQProcess",obj.HARQProcess,"Codeword",obj.Codeword, ...
                "NDIEpoch",obj.NDIEpoch,"TBID",obj.TBID, ...
                "BWPID",obj.BWPID,"ConfigurationEpoch",obj.ConfigurationEpoch);
        end

        function assertSame(obj,other)
            if ~isa(other,"sixgr.l2.mac.HARQTBKey") || obj.Digest~=other.Digest
                error("sixgr:mac:HARQIdentityMismatch", ...
                    "HARQ TB identity changed across attempts.");
            end
        end
    end
end
