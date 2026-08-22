function result = runULTDocStudySuite(mode, varargin)
%RUNTDOCSUITE Public RAN1 10.5.2.3 uplink study entry point.
result = sixgr.tdoc.ul10523.runULTDocStudySuiteInternal(mode, varargin{:});
end
