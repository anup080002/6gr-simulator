function result = runAllIA(varargin) %#ok<INUSD>
%RUNALLIA Fail closed until C0 obtains TDoc-grade acceptance.
error("sixgr:phy:ia:c0:campaign:PhaseGate", ...
    "runAllIA is gated: execute C0 in TDOC mode and obtain TDocPass before implementing C1-C15.");
result=struct(); %#ok<UNRCH>
end
