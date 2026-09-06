function grant = buildRARULGrant(raCfg, varargin)
%BUILDRARULGRANT Encode licensed NR Msg3 using standard RAR fields.
p = inputParser;
p.addParameter("MCS", [], @(x)isempty(x) || (isnumeric(x) && isscalar(x)));
p.parse(varargin{:});
index = raCfg.Msg3PUSCH.MCS;
if ~isempty(p.Results.MCS), index = p.Results.MCS; end
grant = sixgr.mac.ra.RARULGrantCodec.encode(raCfg, index);
sched = raCfg.Msg3PUSCH;
if isempty(p.Results.MCS) && (string(sched.Modulation) ~= string(grant.Modulation) || ...
        abs(double(sched.TargetCodeRate)-double(grant.TargetCodeRate)) > 1e-12)
    error("sixgr:mac:ra:RARMCSAssignmentMismatch", ...
        "Configured Msg3 modulation/rate contradict the RAR MCS index and applicable PUSCH table.");
end
end
