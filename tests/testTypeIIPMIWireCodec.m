function ok=testTypeIIPMIWireCodec()
% PMI field codec, not complete CSI-report or physical-PUSCH qualification.
setup6GRSimToolkit('Verbose',false,'RunToolboxChecks',false);
saved=rng; cleanup=onCleanup(@()rng(saved)); %#ok<NASGU>
rng(3821263212,'twister');
request=localRequest(2,1,1,2,4);
c=struct('Q1',2,'Q2',0,'BeamGroupIndex',0, ...
    'StrongestCoefficientIndices',2,'WidebandAmplitudeIndices',[1;0;7;5], ...
    'PhaseIndices',[3;0;0;1]);
% Independently hand-packed X1=(q1,strongest,k0,k1,k3), X2=(c0,c3).
expected=int8(('10100010001011101'-'0').');
report=sixgr.phy.mimo.TypeIICodebook.serializePMI(request,c);
% 2+2+9+4 = 17 bits. The literal is deliberately independent of bit helpers.
assert(numel(report.Bits)==17);
assert(isequal(report.Bits,expected),'Hand-packed Type-II vector differs.');
[decoded,W]=sixgr.phy.mimo.TypeIICodebook.deserializePMI(request,expected,3);
assert(isequal(decoded,c));
assert(norm(W-sixgr.phy.mimo.TypeIICodebook.matrix(request,c),'fro')<1e-14);
assert(~report.CompleteCSIReport);

cases=0; channelCases=0;
for tuple=[2 1 2;2 2 2;2 2 3;4 1 4].'
    L=tuple(3);
    for rank=1:2
        for alphabet=[4 8]
            request=localRequest(tuple(1),tuple(2),rank,L,alphabet);
            for count=1:2*L
                amplitudes=zeros(2*L,rank); phases=zeros(2*L,rank);
                anchors=zeros(1,rank);
                for layer=1:rank
                    active=randperm(2*L,count); anchors(layer)=active(1)-1;
                    amplitudes(active,layer)=randi([1 7],count,1);
                    amplitudes(active(1),layer)=7;
                    phases(active(2:end),layer)=randi([0 alphabet-1],count-1,1);
                end
                c=struct('Q1',randi(4)-1,'Q2',randi(request.O2)-1, ...
                    'BeamGroupIndex',randi(nchoosek(tuple(1)*tuple(2),L))-1, ...
                    'StrongestCoefficientIndices',anchors, ...
                    'WidebandAmplitudeIndices',amplitudes,'PhaseIndices',phases);
                tx=sixgr.phy.mimo.TypeIICodebook.serializePMI(request,c);
                rxCounts=repmat(count,1,rank);
                assert(numel(tx.Bits)==sixgr.phy.mimo.TypeIICodebook.pmiBitCount(request,rxCounts));
                assert(isequal(tx.Bits,localIndependentBits(request,c)));
                [rx,W]=sixgr.phy.mimo.TypeIICodebook.deserializePMI(request,tx.Bits,rxCounts);
                assert(isequal(rx,c));
                assert(norm(W-sixgr.phy.mimo.TypeIICodebook.matrix(request,c),'fro')<1e-14);
                assert(numel(tx.Owners)==numel(tx.Bits));
                if count==2*L
                    % Actual UCI channel coding/decoding; noiseless coded LLRs
                    % are a codec test, not an RF false-ACK qualification.
                    sequence=sixgr.phy.pucch.UCISequence(2,tx.Bits,tx.Owners,tx.Owners);
                    coded=sixgr.phy.pucch.UCIEncoder.encode(sequence,512,"QPSK");
                    decoded=sixgr.phy.pucch.UCIDecoder.decode(100*(1-2*double(coded.CodedBits)),numel(tx.Bits));
                    assert(decoded.CRCPassed && isequal(int8(decoded.Bits(:)),tx.Bits));
                    channelCases=channelCases+1;
                end
                cases=cases+1;
            end
        end
    end
end
% Unequal per-layer counts must retain the X1/X2 ordering and each layer's
% independently sized phase field. Extraneous TX state is not RX authority.
request=localRequest(2,2,2,3,8);
c=struct('Q1',1,'Q2',3,'BeamGroupIndex',2, ...
    'StrongestCoefficientIndices',[5 1], ...
    'WidebandAmplitudeIndices',[0 2;0 7;0 3;0 4;0 5;7 6], ...
    'PhaseIndices',[0 7;0 0;0 5;0 4;0 3;0 2]);
tx=sixgr.phy.mimo.TypeIICodebook.serializePMI(request,c);
assert(isequal(tx.Bits,localIndependentBits(request,c)));
poisoned=request; poisoned.TransmittedComponents=struct('invalid',NaN);
poisoned.PendingCSITable="unavailable";
[decoded,W]=sixgr.phy.mimo.TypeIICodebook.deserializePMI(poisoned,tx.Bits,[1 6]);
assert(isequal(decoded,c));
assert(norm(W-sixgr.phy.mimo.TypeIICodebook.matrix(request,c),'fro')<1e-14);
localReject(@()sixgr.phy.mimo.TypeIICodebook.deserializePMI(request,tx.Bits,[6 1]), ...
    'sixgr:mimo:TypeIICoefficientCountMismatch'); % Same total size, wrong ownership.
request=localRequest(2,1,1,2,4);
bits=expected;
localReject(@()sixgr.phy.mimo.TypeIICodebook.deserializePMI(request,bits(1:end-1),3), ...
    'sixgr:mimo:InvalidTypeIIPMILength');
bad=double(bits); bad(1)=NaN;
localReject(@()sixgr.phy.mimo.TypeIICodebook.deserializePMI(request,bad,3), ...
    'sixgr:mimo:InvalidTypeIIPMIBits');
bad=bits; bad(10)=1; % Zero amplitude k1 becomes one, without changing length.
localReject(@()sixgr.phy.mimo.TypeIICodebook.deserializePMI(request,bad,3), ...
    'sixgr:mimo:TypeIICoefficientCountMismatch');
for count=[0 5 NaN 1.5]
    localReject(@()sixgr.phy.mimo.TypeIICodebook.pmiBitCount(request,count), ...
        'sixgr:mimo:InvalidTypeIINonzeroCounts');
end
request=localRequest(2,2,1,3,4);
count=sixgr.phy.mimo.TypeIICodebook.pmiBitCount(request,1);
bad=int8(zeros(count,1)); bad(7:9)=1; % q1/q2 4 bits, group 2, strongest 3.
localReject(@()sixgr.phy.mimo.TypeIICodebook.deserializePMI(request,bad,1), ...
    'sixgr:mimo:InvalidPMI');
request=localRequest(2,2,1,2,4);
count=sixgr.phy.mimo.TypeIICodebook.pmiBitCount(request,1);
bad=int8(zeros(count,1)); bad(5:7)=1; % Six groups; binary 111 is not a beam group.
localReject(@()sixgr.phy.mimo.TypeIICodebook.deserializePMI(request,bad,1), ...
    'sixgr:mimo:InvalidPMI');
fprintf('TYPEII_PMI_WIRE_CODEC_PASS component_cases=%d asymmetric_counts=1 channel_codecs=%d complete_csi_report=0\n',cases,channelCases);
ok=true;
end

function bits=localIndependentBits(request,c)
% Concatenate numeric fields via decimal-to-binary text, separate from DUT.
L=request.NumberOfBeams; r=request.Rank;
values=[c.Q1 c.Q2 c.BeamGroupIndex];
widths=[log2(request.O1) log2(request.O2) ceil(log2(nchoosek(request.N1*request.N2,L)))];
for layer=1:r
    indices=setdiff(0:2*L-1,c.StrongestCoefficientIndices(layer));
    values=[values c.StrongestCoefficientIndices(layer) c.WidebandAmplitudeIndices(indices+1,layer).']; %#ok<AGROW>
    widths=[widths ceil(log2(2*L)) repmat(3,1,2*L-1)]; %#ok<AGROW>
end
for layer=1:r
    indices=find(c.WidebandAmplitudeIndices(:,layer)>0).';
    indices=setdiff(indices,c.StrongestCoefficientIndices(layer)+1);
    values=[values c.PhaseIndices(indices,layer).']; %#ok<AGROW>
    widths=[widths repmat(log2(request.PhaseAlphabetSize),1,numel(indices))]; %#ok<AGROW>
end
word='';
for k=1:numel(values)
    if widths(k)>0, word=[word dec2bin(values(k),widths(k))]; end %#ok<AGROW>
end
bits=int8((word-'0').');
end

function request=localRequest(n1,n2,rank,L,alphabet)
request=struct('CodebookType',"typeII",'FrequencyGranularity',"wideband", ...
    'Ports',2*n1*n2,'N1',n1,'N2',n2,'O1',4,'O2',1+3*(n2>1), ...
    'Rank',rank,'NumberOfBeams',L,'PhaseAlphabetSize',alphabet);
end

function localReject(action,identifier)
try
    action();
catch ex
    assert(string(ex.identifier)==identifier,'Expected %s, got %s: %s',identifier,ex.identifier,ex.message);
    return;
end
error('test:ExpectedFailure','Malformed Type-II wire evidence was accepted.');
end
