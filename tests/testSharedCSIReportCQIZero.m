function ok=testSharedCSIReportCQIZero()
% Declared CQI-0 measurement -> actual shared PUCCH -> gNB new-data gate.
% This qualifies transport/publication, not low-SNR channel estimation.
ok=testSharedCSIReportClock("TDD",false,false,[],"",0);
end
