function ok=testPUCCHDetectorPilotAccounting()
% Declared unit inputs only: no RF trials or detector qualification.
v=sixgr.lls6g.config.readConfigFile('simulator/configs/validation/pucch_tdd_detector_pilot.yaml');
validatePUCCHDetectorPilotPolicy(v);
% IDs are labels, not proof of the hypothesis. Changing a payload while
% retaining eight distinct IDs must fail before creating any output folder.
bad=v; bad.cases(8).payload=[1 0];
localReject(@()validatePUCCHDetectorPilotPolicy(bad),'test:PilotCaseCoverage');
bad=v; bad.cases(1).id='../noise';
localReject(@()validatePUCCHDetectorPilotPolicy(bad),'test:PilotCaseIdentity');
bad=v; bad.cases(8).id=bad.cases(7).id;
localReject(@()validatePUCCHDetectorPilotPolicy(bad),'test:PilotCaseIdentity');
bad=v; bad.cases(1).signal_present='false';
localReject(@()validatePUCCHDetectorPilotPolicy(bad),'test:PilotCaseCoverage');
bad=v; bad.seed_base=2^32-1; bad.episodes=2;
localReject(@()validatePUCCHDetectorPilotPolicy(bad),'test:PilotSeedRange');
edge=v; edge.seed_base=2^32-1; edge.episodes=1;
validatePUCCHDetectorPilotPolicy(edge);
edge.seed_base=2^32-1-edge.seed_stride; edge.episodes=2;
validatePUCCHDetectorPilotPolicy(edge);
% Policy identity is independent of case order and arbitrary safe labels.
reordered=v; reordered.cases=reordered.cases(end:-1:1);
validatePUCCHDetectorPilotPolicy(reordered);

noise=struct('harq_bits',2,'signal_present',false,'payload',[]);
r=countPUCCHDetectorPilotErrors(noise,int8([1 1]),true,false);
assert(r.EventError && r.FalseACKBits==2 && r.FalseACKBitOpportunities==2);
r=countPUCCHDetectorPilotErrors(noise,int8([]),false,true);
assert(~r.EventError && r.FalseACKBits==0 && r.FalseACKBitOpportunities==2);
% Do not relax the retained raw-payload noise assertion when output is
% unusable; distinguish its conservative event gate from actionable ACKs.
r=countPUCCHDetectorPilotErrors(noise,int8([1 1]),false,false);
assert(r.EventError && r.RawNoiseACKBits==2 && r.FalseACKBits==0);
signal=struct('harq_bits',2,'signal_present',true,'payload',[0 1]);
r=countPUCCHDetectorPilotErrors(signal,int8([1 0]),true,false);
assert(r.EventError && r.MissedACKBits==1 && r.NACKToACKBits==1 && ...
    r.SignalBitErrors==2 && r.SignalBits==2 && r.TransmittedACKBits==1 && r.TransmittedNACKBits==1);
r=countPUCCHDetectorPilotErrors(signal,int8([0 1]),true,false);
assert(~r.EventError && r.SignalBitErrors==0 && r.MissedACKBits==0);
r=countPUCCHDetectorPilotErrors(signal,int8([]),false,true);
assert(r.EventError && r.MissedACKBits==1 && r.SignalBitErrors==2 && r.NACKToACKBits==0);
signal.payload=[0 0];
r=countPUCCHDetectorPilotErrors(signal,int8([]),false,true);
assert(r.EventError && r.MissedACKBits==0 && r.SignalBitErrors==2);
localReject(@()countPUCCHDetectorPilotErrors(noise,int8(1),true,false),'test:PilotReceiverAccounting');
localReject(@()countPUCCHDetectorPilotErrors(noise,[0.1 1],true,false),'test:PilotReceiverAccounting');
localReject(@()countPUCCHDetectorPilotErrors(noise,int8([1 1]),true,true),'test:PilotReceiverAccounting');
localReject(@()countPUCCHDetectorPilotErrors(noise,int8([1 1]),1,false),'test:PilotReceiverAccounting');
% CSV serialization must retain actual counts, including explicit zeros.
folder=tempname; mkdir(folder);
file=fullfile(folder,'declared_unit_counts.csv');
sixgr.util.csvWriteTable(file,struct2table(r,'AsArray',true),'PreserveSchema',true);
restored=readtable(file);
for name=string(fieldnames(r)).'
    assert(isequal(double(restored.(name)),double(r.(name))));
end
% Recompute existing physical receipts against the independent retained-MAT
% audit. This adds no RF episodes and does not replace the raw evidence audit.
receiptRoot='docs/lls/evidence_20260914/tdd_detector_pilot_5084694c';
physical=readtable(fullfile(receiptRoot,'physical_trials.csv'),'TextType','string');
audited=readtable(fullfile(receiptRoot,'recomputed_existing_trials.csv'),'TextType','string');
assert(height(physical)==8 && height(audited)==8);
for k=1:height(physical)
    match=find(audited.CaseID==physical.CaseID(k) & audited.Episode==physical.Episode(k));
    assert(isscalar(match) && audited.EvidenceSHA256(match)==physical.EvidenceSHA256(k));
    c=struct('harq_bits',physical.HARQBits(k),'signal_present',logical(physical.SignalPresent(k)), ...
        'payload',jsondecode(physical.DeclaredPayloadJSON(k)));
    % Python audit CSV writes literal True/False, not numeric status flags.
    flag=lower(string(audited.ReceiverUsable(match)));
    assert(ismember(flag,["true","false"]));
    result=countPUCCHDetectorPilotErrors(c,jsondecode(physical.DecodedPayloadJSON(k)), ...
        flag=="true",logical(physical.DTX(k)));
    assert(result.EventError==logical(physical.EventError(k)));
    fields=["FalseACKBits","FalseACKBitOpportunities","MissedACKBits","TransmittedACKBits", ...
        "NACKToACKBits","TransmittedNACKBits","SignalBitErrors","SignalBits"];
    for name=fields
        assert(result.(name)==audited.(name)(match),'Stored physical accounting mismatch for %s.',name);
    end
end
ok=true;
disp('PUCCH_PILOT_ACCOUNTING_PASS: exact hypotheses, seed bounds, erased/rejected bits; declared unit inputs only.');
end
function localReject(f,id)
try
    f();
catch e
    assert(string(e.identifier)==id,e.message);
    return;
end
error('testPUCCHDetectorPilotAccounting:MissingRejection','Expected %s.',id);
end
