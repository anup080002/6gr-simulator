function ok=testSharedPUSCHPartialHARQCompletion()
% Actual public-codec partial reception and the production completion reducer.
% Declared LLRs/receiver identities, NOT waveform or shared-owner qualification.
setup6GRSimToolkit('Verbose',false);
[uci,partial,context,pusch,capacity]=localPartialReception();
assert(~partial.DecodeAttempted && ~partial.CRCAvailable && ...
    isnan(partial.CRCPass) && isnan(partial.CRCError) && ...
    isempty(partial.TransportBlocks{1}) && ...
    isempty(fieldnames(partial.CodewordEvidence{1}.CodingLayout)));
flags=struct('NoiseVarStrictFailure',false,'DecodeAttempted',true, ...
    'ULSCHDecodeAttempted',logical(partial.DecodeAttempted),'ReceiverUsable',true);
rx=flags;
rx.DecodedHARQACKBits=uci.DecodedHARQACK;
rx.UCIReceiverEvidence=uci.UCIReceiverEvidence;
observed=sixgr.truth.normalizeReceivedPUSCHHARQ(rx,context);
assert(observed.DecodeAttempted && observed.DecodeOk && ~observed.DTXFlag && ...
    isequal(observed.DecodedBits,zeros(4,1,'int8')));

% Retain real mother-code soft evidence from an earlier attempted CRC failure.
% Corrupt a TB CRC before LDPC encoding, so data bits can decode correctly
% while the independently executed CRC check actually fails.
first=localAttempt(1);
[~,~,firstToken]=sixgr.truth.resolveULHARQReceiverState({},first);
[failed,soft]=localFailedDecode(pusch,capacity.G,first.ReceiverKey);
assert(failed.DecodeAttempted && failed.CRCAvailable && failed.CRCPass==0);
priorOut=struct('IndependentUCICompletionFlags',struct('ULSCHDecodeAttempted',true), ...
    'ReceiverHARQAttempt',firstToken,'CombinedDecodeOK',failed.AllTransportBlocksPassed, ...
    'SoftBuffer',soft);
priorDecision=sixgr.truth.preparePUSCHULHARQReceiverDecision(priorOut);
records=sixgr.truth.resolveULHARQReceiverState({},first,priorDecision);
assert(isequaln(records{1}.SoftBuffer,soft));

second=localAttempt(2);
[~,prior,token]=sixgr.truth.resolveULHARQReceiverState(records,second);
% This is the missing-field schema returned by the production link runner
% when data decode is unavailable. The old completion dereferenced SoftBuffer
% unconditionally before inspecting ULSCHDecodeAttempted.
out=struct('IndependentUCICompletionFlags',flags,'ReceiverHARQAttempt',token, ...
    'CombinedDecodeOK',partial.AllTransportBlocksPassed,'CombinedLLR',prior, ...
    'DecodedTransportBlockBits',partial.TransportBlocks{1}, ...
    'DecodedHARQACKBits',rx.DecodedHARQACKBits,'UCIReceiverEvidence',rx.UCIReceiverEvidence, ...
    'IndependentHARQObservation',observed);
before=out;
assert(~isfield(out,'SoftBuffer') && ~isfield(out,'HARQSoftBuffer'));
decision=sixgr.truth.preparePUSCHULHARQReceiverDecision(out);
assert(~decision.DecodeAttempted && ~decision.CRCPass && isempty(decision.SoftBuffer));
after=sixgr.truth.resolveULHARQReceiverState(records,second,decision);
assert(isequaln(after{1}.SoftBuffer,prior) && ...
    ~after{1}.DecodeAttempted && ~after{1}.CRCPass && ...
    after{1}.Attempt.ObservationID==second.ObservationID);
assert(isequaln(before,out) && isequaln(observed,sixgr.truth.normalizeReceivedPUSCHHARQ(rx,context)));
assert(isnan(partial.CRCPass) && ~partial.CRCAvailable && observed.DecodeOk, ...
    'Unavailable UL-SCH CRC and independently usable HARQ UCI remain distinct.');

% Explicitly empty evidence is also legal; neither form can erase prior data.
emptyOut=out; emptyOut.SoftBuffer=[]; emptyOut.HARQSoftBuffer=[];
assert(isequaln(decision,sixgr.truth.preparePUSCHULHARQReceiverDecision(emptyOut)));
% With no prior attempt, unattempted data creates no invented soft evidence.
fresh=out; fresh.ReceiverHARQAttempt=firstToken;
freshDecision=sixgr.truth.preparePUSCHULHARQReceiverDecision(fresh);
freshRecords=sixgr.truth.resolveULHARQReceiverState({},first,freshDecision);
assert(isempty(freshRecords{1}.SoftBuffer));

% Unavailable data must not loosen token/clock guards or accept unsolicited
% soft state. A measured CRC failure above remains an attempted decode.
localReject(@()sixgr.truth.resolveULHARQReceiverState(after,second,decision), ...
    'sixgr:truth:StaleULHARQReceiveAttempt');
bad=decision; bad.ReceiverAttempt=firstToken;
localReject(@()sixgr.truth.resolveULHARQReceiverState(records,second,bad), ...
    'sixgr:truth:ChangedULHARQReceiverState');
assert(isequaln(records{1}.SoftBuffer,soft) && isequaln(after{1}.SoftBuffer,soft));
bad=out; bad.IndependentUCICompletionFlags.ULSCHDecodeAttempted=true;
localReject(@()sixgr.truth.preparePUSCHULHARQReceiverDecision(bad), ...
    'sixgr:truth:ULHARQReceiverSoftEvidenceRequired');
bad.SoftBuffer=struct();
localReject(@()sixgr.truth.preparePUSCHULHARQReceiverDecision(bad), ...
    'sixgr:truth:ULHARQReceiverSoftEvidenceRequired');
for name=["SoftBuffer","HARQSoftBuffer"]
    bad=out; bad.(name)=soft;
    localReject(@()sixgr.truth.preparePUSCHULHARQReceiverDecision(bad), ...
        'sixgr:truth:UnattemptedULHARQSoftEvidence');
end
bad=out; bad.CombinedDecodeOK=true;
localReject(@()sixgr.truth.preparePUSCHULHARQReceiverDecision(bad), ...
    'sixgr:truth:InvalidULHARQReceiverDecision');
bad=out; bad.CombinedDecodeOK=NaN;
localReject(@()sixgr.truth.preparePUSCHULHARQReceiverDecision(bad), ...
    'sixgr:truth:InvalidULHARQReceiverDecision');
bad=out; bad.IndependentUCICompletionFlags.ULSCHDecodeAttempted=0;
localReject(@()sixgr.truth.preparePUSCHULHARQReceiverDecision(bad), ...
    'sixgr:truth:InvalidULHARQReceiverDecision');
% TX reference/coding metadata cannot resolve an unknown receive mapping.
poison=out; poison.TransportBlockBits=ones(999,1,'int8');
poison.CodingLayout=struct('RateMatchedBitCount',123456,'BaseGraph',99);
poison.CombinedLLR=ones(7,1);
assert(isequaln(decision,sixgr.truth.preparePUSCHULHARQReceiverDecision(poison)));
fprintf(['SHARED_PUSCH_PARTIAL_HARQ_COMPLETION_PASS actual_codec_partial=1 ' ...
    'prior_soft_preserved=1 independent_UCI=1 public_CRC_unavailable=1 waveform=0\n']);
ok=true;
end

function [uci,partial,context,pusch,capacity]=localPartialReception()
cfg=sixgr.config.defaultConfig();
pusch=nrPUSCHConfig('PRBSet',0:5,'SymbolAllocation',[0 14], ...
    'NumLayers',1,'Modulation','QPSK','BetaOffsetACK',20, ...
    'BetaOffsetCSI1',6.25,'BetaOffsetCSI2',6.25);
[~,capacity]=nrPUSCHIndices(nrCarrierConfig('NSizeGrid',12),pusch);
request=struct('ReportConfigID',"partial_completion_declared_schema",'Epoch',0, ...
    'CodebookType',"typeI-SinglePanel",'Ports',2,'Rank',1,'MaxRank',2, ...
    'ReportQuantity',"cri-RI-PMI-CQI",'NumCSIResources',1, ...
    'FrequencyGranularity',"wideband",'UCIChannel',"PUSCH");
report=sixgr.phy.mimo.CSIReportConfiguration(request,0);
context=sixgr.phy.ul.pusch.PUSCHUCIReceiveContext(struct( ...
    'ObservationID',"declared_codec_partial_capture",'ConfigurationEpoch',0, ...
    'AssignmentDigest',"declared_ul_assignment",'HARQMappingDigest',"declared_four_HARQ_bits", ...
    'HARQACKBitCount',4,'ConfiguredGrantUCIBitCount',0, ...
    'CSIReportConfigID',report.ReportConfigID,'CSIConfigurationEpoch',report.Epoch));
coding=struct('RV',0,'MaxIterations',25,'Algorithm','Normalized min-sum', ...
    'Nref',{{[]}},'PresenceDecisionAlgorithm',cfg.phy.pusch.csiPresenceDecisionAlgorithm);
% Both receive hypotheses admit the zero linear codeword. Their actual CRC
% passes cannot select one layout; only invariant HARQ UCI is deliverable.
uci=sixgr.phy.ul.pusch.receiveWithCSIPresence(pusch,.3,512, ...
    100*ones(capacity.G,1),context,4,report,cfg.phy.pusch.shortUCIDecision,coding);
assert(isequal(uci.CSIPresenceEvidence.CandidateTBCRCPass,[1;1]) && ...
    ~uci.CSIPresenceResolved && uci.PartialReception && ...
    ~uci.ULSCHMappingResolved && isempty(uci.ULSCHLLR{1}));
partial=sixgr.phy.ul.pusch.decodeResolvedULSCH(uci.ULSCHLLR,uci.ULSCHMappingResolved, ...
    pusch,512,.3,0,[],25,'Normalized min-sum',[],[]);
end

function [decoded,soft]=localFailedDecode(pusch,G,key)
tbs=512; rate=.3; rv=0;
bits=int8(mod((1:tbs).'+floor((1:tbs).'/7),2));
info=nrULSCHInfo(tbs,rate);
withCRC=nrCRCEncode(bits,info.CRC);
withCRC(end)=1-withCRC(end);
segmented=nrCodeBlockSegmentLDPC(withCRC,info.BGN);
coded=nrLDPCEncode(segmented,info.BGN);
matched=nrRateMatchLDPC(coded,G,rv,pusch.Modulation,pusch.NumLayers);
llr=100*(1-2*double(matched));
decoded=sixgr.phy.ul.pusch.decodeResolvedULSCH({llr},true,pusch,tbs,rate,rv, ...
    [],25,'Normalized min-sum',[],[]);
assert(isequal(decoded.TransportBlocks{1},bits) && decoded.CRCError==1);
layout=decoded.CodewordEvidence{1}.CodingLayout;
recovered=sixgr.phy.phycode.rateRecoverLDPC(llr,tbs,rate,rv,pusch.Modulation, ...
    pusch.NumLayers,double(layout.NumCodeBlocks),layout.Nref,'CodingLayout',layout);
[~,combining]=sixgr.phy.harq.combineSoftLLR(recovered,[], ...
    'CurrentLayout',layout,'HARQKey',key);
soft=combining.SoftBuffer;
assert(isequaln(soft.LLRSum,decoded.CodewordEvidence{1}.HARQCombining.SoftBuffer.LLRSum));
end

function a=localAttempt(n)
a=struct('ScopeKey',"declared_UL_process",'ReceiverKey',"gNB-UL-TB-declared-partial-completion", ...
    'NDIEpoch',1,'DataAbsoluteSlot',4+5*(n-1),'ObservationID',"declared_rx_"+n, ...
    'GrantContextID',"declared_grant_"+n,'CommandObservationID',"declared_command_"+n, ...
    'StartSample',400+500*(n-1),'EndSampleExclusive',500+500*(n-1), ...
    'SampleRateHz',1000,'AvailableAtSample',500+500*(n-1));
end

function localReject(action,identifier)
try, action(); catch cause
    assert(strcmp(cause.identifier,identifier),'Expected %s, got %s: %s', ...
        identifier,cause.identifier,cause.message); return;
end
error('test:MissingRejection','Expected %s.',identifier);
end
