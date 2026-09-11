function ok=testUCIBinaryInputValidation()
% Reject malformed payloads before any narrowing conversion can alter them.
for value={0.2,-0.2,0.8,1.2,NaN,Inf,-Inf,1+1i,[0 0.25 1],{0,1}}
    observed="";
    try
        sixgr.phy.pucch.PUCCHUtil.bits(value{1});
    catch exception
        observed=string(exception.identifier);
    end
    assert(observed=="sixgr:phy:pucch:InvalidUCIBit", ...
        'Malformed UCI must not be rounded or coerced into a transmitted bit.');
end
for value={logical([0 1 0]),double([0 1 0]),single([0 1 0]), ...
        uint8([0 1 0]),int8([0 1 0]),'010',"010"}
    actual=sixgr.phy.pucch.PUCCHUtil.bits(value{1});
    assert(isequal(actual,int8([0;1;0])));
end
assert(isempty(sixgr.phy.pucch.PUCCHUtil.bits([])));
assert(isempty(sixgr.phy.pucch.PUCCHUtil.bits("")));
row=struct('HARQACKBits',[0 0.2 1],'SRBits',"", ...
    'CSIPart1Bits',"",'CSIPart2Bits',"",'CaseID',"invalid");
% The production typed report path must not coerce numeric report bits.
state=struct('ReportID',"invalid",'RNTI',1,'ServingCell',0, ...
    'ComponentCarrier',0,'ULBWP',0,'ConfigurationEpoch',1,'TargetSlot',0, ...
    'PriorityIndex',0,'HARQACKReport',struct('Bits',row.HARQACKBits), ...
    'SchedulingRequestReports',struct([]),'CSIReports',struct([]), ...
    'ReportSource',"test_invalid_input",'TriggeringEventIDs',"test");
observed="";
try
    sixgr.phy.pucch.UCIReportSerializer.serialize(sixgr.phy.pucch.UCIReport(state));
catch exception
    observed=string(exception.identifier);
end
assert(observed=="sixgr:phy:pucch:InvalidUCIBit");
ok=true;
end
