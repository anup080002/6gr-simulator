classdef CandidateGrant
    %CANDIDATEGRANT Immutable pre-commit scheduling proposal.
    properties (SetAccess=immutable)
        CandidateID (1,1) string
        SnapshotID (1,1) string
        Policy (1,1) string
        Data (1,1) struct
    end
    methods
        function obj=CandidateGrant(snapshotID,policy,data)
            arguments
                snapshotID
                policy
                data (1,1) struct
            end
            obj.SnapshotID=string(snapshotID);
            obj.Policy=string(policy); obj.Data=data;
            obj.CandidateID=sixgr.l2.mac.MACHash.of(struct( ...
                "SnapshotID",obj.SnapshotID,"Policy",obj.Policy,"Data",data));
        end
    end
end
