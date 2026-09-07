function ok = testRARDCI10Canonical()
% Independent field arithmetic plus actual polar/LDPC Msg2 round trips.
reference = struct("FrequencyReferenceSize",24,"FrequencyReferenceStart",0, ...
    "FrequencyReferenceSource","scenario_initial_dl_bwp", ...
    "DMRSTypeAPosition",2,"CyclicPrefix","normal","SharedSpectrum",false, ...
    "FrequencyRange","FR1","TimeAllocationSource","38.214_default_A","ConfigurationEpoch",1);
for n = [1 6 24 25 51 275]
    reference.FrequencyReferenceSize = n;
    c = sixgr.phy.pdcch.RARDCIContext.create(reference,127);
    % Full-band allocation uses the second RIV branch except N=1.
    riv = 2*n-1; if n==1, riv=0; end
    f = struct("frequency_resource_assignment",riv,"time_resource_assignment",0, ...
        "vrb_to_prb_mapping",0,"mcs",0,"tb_scaling",0,"reserved",0);
    d = sixgr.phy.pdcch.DCIPacker.pack(f,c);
    width = ceil(log2(n*(n+1)/2));
    expected = zeros(28,1,'int8');
    if width>0, expected=[int8(dec2bin(riv,width).'-'0');expected]; end
    assert(isequal(d.Bits,expected),"RA-RNTI fields must match independent MSB-first bit arithmetic.");
    decoded = sixgr.phy.pdcch.DCIParser.parse(d.Bits,c);
    nonbinary=double(d.Bits); nonbinary(1)=0.1;
    localError(@() sixgr.phy.pdcch.DCIParser.parse(nonbinary,c),"sixgr:phy:pdcch:payload_length_mismatch");
    assert(decoded.Fields.prb_start==0 && decoded.Fields.num_prb==n);
    assert(isempty(d.Alignment.UniqueCRNTISizes));
    assert(d.SizeDetails.PaddingBits==0 && numel(d.Bits)==width+28);
    assert(~any(ismember(string(d.FieldTable.FieldName),["format_identifier","ndi","rv","harq_process"])));
    bad=d.Bits; bad(end)=1;
    localError(@() sixgr.phy.pdcch.DCIParser.parse(bad,c),"sixgr:phy:pdcch:field_out_of_range");
    f.tb_scaling=3;
    localError(@() sixgr.phy.pdcch.DCIPacker.pack(f,c),"sixgr:phy:pdcch:field_out_of_range");
end
% Independent normal-CP DMRS-pos3 and extended-CP table landmarks.
[a,m] = sixgr.phy.pdcch.RARDCIContext.defaultA("normal",3);
assert(isequal(a(1,:),[0 3 11 0]) && isequal(a(6,:),[5 10 4 0]) && m(6)=="B");
[a,~] = sixgr.phy.pdcch.RARDCIContext.defaultA("extended",2);
assert(isequal(a(1,:),[0 2 6 0]) && isequal(a(12,:),[11 1 11 0]));

cfg=raStrictAnchorConfig(); ra=sixgr.mac.ra.RAConfig(cfg);
ul=sixgr.mac.ra.buildRARULGrant(ra);
rar=sixgr.mac.ra.encodeMACRAR("RAPID",ra.PreambleIndex,"TimingAdvanceCommand",0, ...
    "TemporaryCRNTI",ra.TempCRNTI,"ULGrant",ul);
sizes=zeros(1,3);
for scaling=0:2
    ra.Msg2PDSCH.TBScaling=scaling;
    % Real common-control decoding at AL2/4/8 must retain its own AL.
    candidates=zeros(1,5); candidates(scaling+2)=1;
    cfg.initial_access.sib1.pdcch_config_common.commonSearchSpaceList.nrofCandidates=candidates;
    [tx,sched]=sixgr.phy.ra.generateMsg2RARWaveform(cfg,ra,rar);
    assert(sched.PDSCH.DMRS.DMRSAdditionalPosition==2);
    assert(sched.PDSCH.DMRS.NumCDMGroupsWithoutData==2);
    assert(tx.PDCCHInfo.PDCCHScramblingRNTI==0);
    % Inspect generated samples, not just two matching TX/RX assumptions.
    plan=tx.PDSCHResourcePlan;
    assert(plan.IndexBase=="zero_based");
    dataPower=mean(abs(tx.Grid(plan.DataIndices+1)).^2);
    dmrsPower=mean(abs(tx.Grid(plan.DMRSIndicesPerPort{1}+1)).^2);
    assert(abs(10*log10(dmrsPower/dataPower)-3)<1e-10, ...
        "Actual Msg2 DM-RS/data EPRE must follow TS38.214 Table4.1-1.");
    assert(abs(tx.PDSCHReferenceSignalConfig.Data.DMRSAmplitudeScale-10^(3/20))<1e-12);
    % Remove every TX-side receiver oracle, including the scheduled MCS.
    poisonedRa=ra; poisonedRa.Msg2PDSCH=struct("MCS",28);
    [rx,recovered]=sixgr.phy.ra.recoverMsg2RAR(tx.Waveform,cfg,poisonedRa,struct(),struct());
    assert(rx.Ok && recovered.PayloadHash==rar.PayloadHash);
    assert(rx.PDCCHControlEvent.ControlAuthority=="receiver_crc_valid_decode");
    identity=struct('RunId','unit_rar','CellId',1,'UEId',1,'AttemptId',1);
    candidateEvidence=sixgr.phy.ra.rarPDCCHCandidateEvidence(identity,ra,rx.PDCCHInfo);
    assert(height(candidateEvidence)==1 && candidateEvidence.AggregationLevel==2^(scaling+1));
    assert(candidateEvidence.CrcPass && candidateEvidence.IsSelectedCandidate);
    assert(isnan(candidateEvidence.CCEIndex) && strlength(candidateEvidence.CCEIndexNAReason)>0);
    assert(height(sixgr.phy.ra.rarPDCCHCandidateEvidence(struct(),ra,struct()))==0);
    evidence=sixgr.phy.ra.rarDCIFieldEvidence(struct('RunId','unit_rar','UEId',1),ra,tx,rx);
    assert(height(evidence)==12 && all(isfinite(evidence.Value)));
    assert(isequal(evidence.Value(1:6),evidence.Value(7:12)));
    assert(height(sixgr.phy.ra.rarDCIFieldEvidence(struct(),ra,struct(),struct()))==0);
    sizes(scaling+1)=tx.TransportBlockSize;
    expectedTBS=nrTBS("QPSK",1,24,108,120/1024,0,2^-scaling);
    assert(tx.TransportBlockSize==expectedTBS,"TBS must use 3 full DMRS symbols and the decoded TB scaling.");
end
assert(all(diff(sizes)<0));
disp('RAR_DCI_CANONICAL_PASS: independent fields, scaled TBS, actual common PDCCH/PDSCH and no TX receiver oracle.');
ok=true;
end

function localError(fn,id)
try, fn(); catch ME, assert(string(ME.identifier)==id,ME.message); return; end
error("testRARDCI10Canonical:ExpectedFailure","Expected %s",id);
end
