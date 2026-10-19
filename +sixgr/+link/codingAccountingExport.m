function evidence=codingAccountingExport(metrics)
% Compact measured coding evidence. No maps/payloads duplicated into CSV.
names=["CBCRCBits","CodeBlockInputBits","SegmentationOverheadBits", ...
    "InherentLDPCPuncturedBits","RateMatchEligibleBits", ...
    "RateMatchUniqueSelectedBits","CodingAccountingVersion","RateMatchAccountingJSON"];
if nargin==0, metrics=sixgr.link.deriveCodingTrialMetrics(struct(),struct(),struct(),struct()); end
evidence=struct();
for name=names, evidence.(name)=metrics.(name); end
end
