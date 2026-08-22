function result=runRAN1AI10522PDSCHDMRS(mode,varargin)
%RUNRAN1AI10522PDSCHDMRS Stable repository-root campaign entry point.
if nargin<1,mode="smoke";end
result=sixgr.studies.ran1ai10522.runRAN1AITDocStudySuite(string(mode),varargin{:});
end
