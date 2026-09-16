function ok=testPUSCHCSIPresenceDecision()
% Declared public-codec ambiguity fixture, not RF/detector qualification.
setup6GRSimToolkit('Verbose',false);
cfg=sixgr.config.defaultConfig();
assert(string(cfg.phy.pusch.csiPresenceDecisionAlgorithm)=="unique_current_tb_crc");
p=nrPUSCHConfig('PRBSet',0:5,'SymbolAllocation',[0 14], ...
    'NumLayers',1,'Modulation','QPSK','BetaOffsetACK',20, ...
    'BetaOffsetCSI1',6.25,'BetaOffsetCSI2',6.25);
[~,capacity]=nrPUSCHIndices(nrCarrierConfig('NSizeGrid',12),p);
request=struct('ReportConfigID',"presence_ambiguity_fixture",'Epoch',0, ...
    'CodebookType',"typeI-SinglePanel",'Ports',2,'Rank',1,'MaxRank',2, ...
    'ReportQuantity',"cri-RI-PMI-CQI",'NumCSIResources',1, ...
    'FrequencyGranularity',"wideband",'UCIChannel',"PUSCH");
report=sixgr.phy.mimo.CSIReportConfiguration(request,0);
context=sixgr.phy.ul.pusch.PUSCHUCIReceiveContext(struct( ...
    'ObservationID',"declared_codec_capture",'ConfigurationEpoch',0, ...
    'AssignmentDigest',"declared_ul_grant",'HARQMappingDigest',"declared_four_assignments", ...
    'HARQACKBitCount',4,'ConfiguredGrantUCIBitCount',0, ...
    'CSIReportConfigID',report.ReportConfigID,'CSIConfigurationEpoch',report.Epoch));
coding=struct('RV',0,'MaxIterations',25,'Algorithm','Normalized min-sum', ...
    'Nref',{{[]}},'PresenceDecisionAlgorithm',cfg.phy.pusch.csiPresenceDecisionAlgorithm);
policy=cfg.phy.pusch.shortUCIDecision;
llr=100*ones(capacity.G,1);
% The zero linear codeword has valid TB CRC under both lengths. Decode
% confidence / a TB pass alone must not arbitrarily pick the CSI-present one.
rx=sixgr.phy.ul.pusch.receiveWithCSIPresence(p,.3,512,llr,context,4,report,policy,coding);
assert(isequal(rx.CSIPresenceEvidence.CandidateTBCRCPass,[1;1]));
assert(~rx.CSIPresenceResolved && ~rx.CSIReportDetected && rx.PartialReception && ...
    isnan(rx.CSIPresenceEvidence.SelectedCandidate));
assert(rx.UCIReceiverEvidence.HARQACK.DecodeUsable && ...
    isequal(rx.DecodedHARQACK,zeros(4,1,'int8')));
assert(~rx.ULSCHMappingResolved && isempty(rx.ULSCHLLR{1}) && ...
    ~rx.CSIPart1Usable && isempty(rx.DecodedCSIPart1));
% No TB means no CRC exists to resolve presence. Do not manufacture a pass
% from an invariant empty UL-SCH map or the short-UCI posterior.
noTB=sixgr.phy.ul.pusch.receiveWithCSIPresence(p,.3,0,llr,context,4,report,policy,coding);
assert(~noTB.CSIPresenceResolved && all(isnan(noTB.CSIPresenceEvidence.CandidateTBCRCPass),'all') && ...
    ~any(noTB.CSIPresenceEvidence.CandidateTBDecodeAttempted,'all'));
assert(noTB.ULSCHMappingResolved && isempty(noTB.ULSCHLLR{1}) && ...
    noTB.UCIReceiverEvidence.HARQACK.DecodeUsable);
bad=coding; bad.PresenceDecisionAlgorithm="force_present";
reject(@()sixgr.phy.ul.pusch.receiveWithCSIPresence(p,.3,512,llr,context,4,report,policy,bad), ...
    'sixgr:pusch:InvalidCSIPresenceDecisionPolicy');
for name=["ExpectedBits","RateMatchedBitCount","PriorHARQSoftBuffer"]
    bad=coding; bad.(name)=1;
    reject(@()sixgr.phy.ul.pusch.receiveWithCSIPresence(p,.3,512,llr,context,4,report,policy,bad), ...
        'sixgr:pusch:InvalidCSIPresenceCodingAuthority');
end
fprintf('PUSCH_CSI_PRESENCE_DECISION_PASS ambiguous_TB_CRC=1 no_TB_no_decision=1 no_prior_or_TX_authority=1\n');
ok=true;
end
function reject(fn,id)
try, fn(); catch err
    assert(strcmp(err.identifier,id),'Expected %s, got %s: %s',id,err.identifier,err.message); return;
end
error('test:MissingRejection','Expected %s.',id);
end
