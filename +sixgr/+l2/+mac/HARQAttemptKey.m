classdef HARQAttemptKey
    %HARQATTEMPTKEY Immutable transmission-attempt identity.

    properties (SetAccess=immutable)
        TBKey
        GrantID (1,1) string
        RV (1,1) double
        AttemptIndex (1,1) double
        CodingLayoutSHA256 (1,1) string
        RateMatchSHA256 (1,1) string
        Digest (1,1) string
    end

    methods
        function obj=HARQAttemptKey(tbKey,grantID,rv,index,codingHash,rateHash)
            arguments
                tbKey (1,1) sixgr.l2.mac.HARQTBKey
                grantID
                rv (1,1) double {mustBeInteger,mustBeNonnegative}
                index (1,1) double {mustBeInteger,mustBeNonnegative}
                codingHash
                rateHash
            end
            if strlength(string(grantID))==0 || ...
                    strlength(string(codingHash))~=64 || ...
                    strlength(string(rateHash))~=64
                error("sixgr:mac:HARQIdentityMissing", ...
                    "Grant and 64-character coding/rate hashes are mandatory.");
            end
            obj.TBKey=tbKey; obj.GrantID=string(grantID); obj.RV=rv;
            obj.AttemptIndex=index; obj.CodingLayoutSHA256=string(codingHash);
            obj.RateMatchSHA256=string(rateHash);
            obj.Digest=sixgr.l2.mac.MACHash.of(struct( ...
                "TBKey",tbKey.Digest,"GrantID",obj.GrantID,"RV",rv, ...
                "AttemptIndex",index,"CodingLayoutSHA256",obj.CodingLayoutSHA256, ...
                "RateMatchSHA256",obj.RateMatchSHA256));
        end
    end
end
