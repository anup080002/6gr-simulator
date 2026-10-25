function T=readSRSPhysicalMeasurementTrials(path)
% Read original SRS text/vector operands without cardinality inference.
T=table(); if ~isfile(path), return; end
options=detectImportOptions(path,'FileType','text','Delimiter',',','VariableNamingRule','preserve');
names=["SRSRSRPSource","SRSRSRPStatus","SRSRSRPPerReceiveAntenna_dBm", ...
    "SRSRSRPPerReceiveAntenna_dB_re_UnitOccupiedRE_Es","SRSAbsolutePowerSource", ...
    "SRSAbsolutePowerStatus","SRSAbsolutePowerReferencePlane","SRSAbsolutePowerAggregation", ...
    "SRSAbsolutePowerEvidenceJSON","SRSAbsolutePowerEvidenceSHA256","SRSResourceIDsJSON", ...
    "SRSConfigurationContextID","SRSConfigurationContextVersion"];
types=struct();
for name=names
    if ismember(name,string(options.VariableNames)), types.(name)='string'; end
end
T=sixgr.util.csvReadTable(path,'ColumnTypes',types);
end
