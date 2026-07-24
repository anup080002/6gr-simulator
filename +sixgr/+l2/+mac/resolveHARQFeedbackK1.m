function [k1, timingDecision] = resolveHARQFeedbackK1(cfg, grant, varargin)
%RESOLVEHARQFEEDBACKK1 Resolve K1 from attached canonical frame state.
%
% The legacy (pdschSlot,tddPattern,mu) signature is intentionally rejected:
% a compact pattern cannot represent symbol-level availability, CC/BWP
% identity, or processing-time capability.

if nargin ~= 2 || ~isstruct(cfg) || ~isscalar(cfg) || ...
        ~isstruct(grant) || ~isscalar(grant) || ~isempty(varargin)
    error("sixgr:l2:mac:LegacyHARQTimingSignatureRejected", ...
        "resolveHARQFeedbackK1 requires (resolvedCfg, grant). " + ...
        "Compact TDD pattern and default-mu callers are unsupported.");
end
grant.Direction = "DL";
timingDecision = ...
    sixgr.phy.frame.TimingRelationEngine.resolveProductionGrant(cfg, grant);
if ~timingDecision.Valid
    error("sixgr:l2:mac:HARQTimingRejected", ...
        "Canonical HARQ-ACK timing rejected the grant: %s", ...
        char(string(timingDecision.ReasonCode)));
end
k1 = double(timingDecision.K1);
end
