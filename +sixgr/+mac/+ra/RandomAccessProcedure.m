function result = RandomAccessProcedure(cfg, varargin)
%RANDOMACCESSPROCEDURE Execute strict contention-based four-step RA.
result = sixgr.phy.ra.runFourStepRA(cfg, varargin{:});
end
