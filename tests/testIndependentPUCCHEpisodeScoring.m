function ok=testIndependentPUCCHEpisodeScoring()
% Negative accounting contracts, not physical observations or populations.
setup6GRSimToolkit('Verbose',false);
c=localContext(2,3); rx=localRX(c,int8([1;1]),int8([1;0;1]));
e=localExecution(c,false); emptyTX=struct([]);
row=sixgr.link.scoreIndependentPUCCHReceiverEpisode(c,rx,emptyTX,e);
assert(row.FalseACKEpisode==1 && row.FalseACKBitCount==2 && row.FalseAcceptanceEpisode==1 && ...
    row.IndependentWaveformCount==1 && ~row.HARQBitsAreIndependentTrials && ...
    isnan(row.CompleteUCIErrorEpisode) && ~row.StatisticallyQualified);
rx.CRCPassed=false;
row=sixgr.link.scoreIndependentPUCCHReceiverEpisode(c,rx,emptyTX,e);
assert(row.FalseACKEpisode==0 && row.FalseAcceptanceEpisode==0 && ...
    row.FalseDetectionEpisode==1 && ~row.CRCPassed);
rx.CRCPassed=true; rx.DTX=true;
row=sixgr.link.scoreIndependentPUCCHReceiverEpisode(c,rx,emptyTX,e);
assert(row.CRCPassed && row.DTX && row.FalseAcceptanceEpisode==0 && row.FalseACKEpisode==0);
csi=localContext(0,3); onlyCSI=localRX(csi,int8([]),int8([1;0;1]));
row=sixgr.link.scoreIndependentPUCCHReceiverEpisode(csi,onlyCSI,emptyTX,localExecution(csi,false));
assert(isnan(row.FalseACKEpisode) && row.FalseAcceptanceEpisode==1);

tx=localTX(int8([0;1]),int8([1;0;1])); e=localExecution(c,true);
rx=localRX(c,int8([1;0]),int8([1;0;1]));
row=sixgr.link.scoreIndependentPUCCHReceiverEpisode(c,rx,tx,e);
assert(row.UCIReceptionAccepted && row.CompleteUCIErrorEpisode==1 && ...
    row.FalseACKBitCount==1 && row.FalseNACKBitCount==1 && row.FalseACKEpisode==1 && ...
    row.IndependentWaveformCount==1);
rx.DecodedFields.HARQACK=int8([0;1]);
row=sixgr.link.scoreIndependentPUCCHReceiverEpisode(c,rx,tx,e);
assert(row.CompleteUCIErrorEpisode==0 && row.ExactDecodedFields==1 && ...
    row.FalseACKEpisode==0 && row.MissedHARQEpisode==0 && row.TXRXFieldLengthsMatch==1);
rx.CRCPassed=false;
row=sixgr.link.scoreIndependentPUCCHReceiverEpisode(c,rx,tx,e);
assert(row.CompleteUCIErrorEpisode==1 && row.ExactDecodedFields==1 && ...
    ~row.UCIReceptionAccepted && row.MissedHARQEpisode==1 && row.FalseACKEpisode==0);
rx.CRCPassed=true; rx.DTX=true; rx.ReceiverUsable=false;
rx.DecodedFields.HARQACK=int8([]); rx.DecodedFields.CSIPart1=int8([]);
row=sixgr.link.scoreIndependentPUCCHReceiverEpisode(c,rx,tx,e);
assert(row.CompleteUCIErrorEpisode==1 && row.MissedHARQEpisode==1 && ...
    row.FalseACKEpisode==0 && isnan(row.FalseACKBitCount) && row.CRCPassed);

% The flat bits agree, but HARQ/CSI field ownership differs. Do not fix
% this valid hypothesis mismatch by matching a prefix or borrowing TX layout.
different=localContext(1,4);
rx=localRX(different,int8(0),int8([1;1;0;1]));
row=sixgr.link.scoreIndependentPUCCHReceiverEpisode(different,rx,tx,localExecution(different,true));
assert(row.TXRXFieldLengthsMatch==0 && row.ExactDecodedFields==0 && ...
    row.CompleteUCIErrorEpisode==1 && isnan(row.FalseACKBitCount) && ...
    isnan(row.MissedHARQEpisode));
bad=localExecution(c,false); bad.ReceiverContextDigest="wrong";
try
    sixgr.link.scoreIndependentPUCCHReceiverEpisode(c,localRX(c,int8([0;1]),int8([1;0;1])),emptyTX,bad);
    error('test:ExpectedScoringContextRejection');
catch err
    assert(strcmp(err.identifier,'sixgr:link:InvalidPUCCHEpisodeScoring'));
end
fprintf('INDEPENDENT_PUCCH_SCORING_PASS contract_only_not_waveform_population\n');
ok=true;
end

function c=localContext(h,csi)
c=sixgr.phy.pucch.UCIReportContext(struct('ReportID',"independent_receiver_contract", ...
    'ConfigurationEpoch',1,'Sequence1Length',h+csi,'Sequence2Length',0, ...
    'HARQACKBits',h,'SRBits',0,'CSIPart1Bits',csi,'CSIPart2Bits',0,'PriorityIndex',0));
end
function rx=localRX(c,h,b)
rx=struct('ReceiverUsable',true,'DTX',false,'CRCApplicable',true,'CRCPassed',true, ...
    'DetectionMetric',.7,'DetectionThreshold',.2, ...
    'ReportContextDigest',c.Digest,'AssignmentDigest',"receiver_assignment_contract", ...
    'DecodedFields',struct('HARQACK',h,'SR',int8([]),'CSIPart1',b,'CSIPart2',int8([])));
end
function e=localExecution(c,present)
e=struct('EpisodeID',"accounting_contract_not_physical", ...
    'Scope',"installed_single_occasion_independent_reset_not_continuous_runtime", ...
    'SignalPresent',present,'TransmitterExecuted',present,'DesiredChannelExecuted',present, ...
    'ReceiverContextDigest',c.Digest,'ReceiverAssignmentDigest',"receiver_assignment_contract");
end
function tx=localTX(h,csi)
report=sixgr.phy.pucch.UCIReport(struct('ReportID',"tx_accounting_contract",'RNTI',1, ...
    'ServingCell',1,'ComponentCarrier',0,'ULBWP',0,'ConfigurationEpoch',1, ...
    'TargetSlot',1,'PriorityIndex',0,'HARQACKReport',struct('Bits',h), ...
    'SchedulingRequestReports',struct([]), ...
    'CSIReports',struct('Part1Bits',csi,'Part2Bits',int8([]),'Priority',0,'ReportID',1), ...
    'ReportSource',"accounting_contract_not_physical",'TriggeringEventIDs',"contract"));
tx=struct('Report',report,'Serialization',sixgr.phy.pucch.UCIReportSerializer.serialize(report));
end
