function [ok,checks] = testPDSCHCodewordDecodeLineage()
% Actual one-PRB, two-codeword calibration TX/RX plus declared codec controls.
% No received DCI, scheduler, RF, natural HARQ retry or BLER qualification.
% The private projection is tested from its exact current production source;
% the generated entrypoint is test-only and removed on exit. Decoder results
% are actual primitives, not altered mocks, except explicitly rejected copies.
setup6GRSimToolkit('Verbose',false);
savedRNG = rng; restoreRNG = onCleanup(@()rng(savedRNG)); %#ok<NASGU>
[project,cleanup,sourceHash] = localProjection(); %#ok<ASGLU>
rows = repmat(struct('Case',"",'Passed',false,'FailureID',"",'Detail',""),0,1);
record("actual_one_PRB_rank6_facade",@()localWaveform(project));
record("actual_single_codeword_decoder",@()localSingle(project));
record("actual_mixed_TB_CRC_codewords",@()localMixedCRC(project));
record("actual_same_TB_RV0_RV2_boundary",@()localCombined(project));
record("original_decoder_projection_corruption_guards",@()localGuards(project));
checks = struct2table(rows);
for k = find(~checks.Passed).'
    fprintf(2,'PDSCH_CW_LINEAGE %s FAIL %s %s\n', ...
        checks.Case(k),checks.FailureID(k),checks.Detail(k));
end
fprintf('PDSCH_CW_LINEAGE cases=%d failures=%d native_RX_fixture_cases=1 reference_BLER_qualified=0 source_SHA256=%s\n', ...
    height(checks),nnz(~checks.Passed),sourceHash);
assert(all(checks.Passed),'test:PDSCHCodewordDecodeLineage:Failed', ...
    '%d/%d bounded codeword receipt checks failed.',nnz(~checks.Passed),height(checks));
ok = true;

    function record(name,fn)
        row=struct('Case',name,'Passed',false,'FailureID',"",'Detail',"");
        try
            fn(); row.Passed=true;
        catch cause
            row.FailureID=string(cause.identifier);
            row.Detail=string(getReport(cause,'extended','hyperlinks','off'));
        end
        rows(end+1,1)=row; %#ok<AGROW>
    end
end

function localWaveform(project)
f = StrictPDSCHChainFixture.create(6,'NPRB',1);
assert(f.Carrier.NSizeGrid<=12 && f.Assignment.Profile=="phy_calibration");
tx = sixgr.pdsch.PDSCHTransmitter(f.TransportBlocks,f.Assignment, ...
    f.ResourcePlan,f.Carrier,f.ReferenceConfig,'PrecoderBundle',f.PrecoderBundle);
cfg = struct('run',struct('pdschExecutionProfile','phy_calibration', ...
    'strictMode',true),'phy',struct('ldpc',struct('useMexBatchDecode',false)));
[rx,info] = sixgr.phy.dl.PDSCH_Rx(tx.Waveform,cfg, ...
    'Carrier',f.Carrier,'Assignment',f.Assignment,'ResourcePlan',f.ResourcePlan, ...
    'ReferenceSignalConfig',f.ReferenceConfig,'ReceiverConfig',f.ReceiverConfig, ...
    'CodingPlan',tx.CodingPlans,'PrecoderBundle',f.PrecoderBundle, ...
    'IntegrationContext',f.IntegrationContext,'ExecutionProfile','phy_calibration');
assert(rx.CRCPass && all(rx.CRCPassPerCodeword) && ...
    isequal(rx.TransportBlocks,f.TransportBlocks));
assert(isequaln(rx.DecodedBitLineagePerCodeword,info.DecodedBitLineagePerCodeword) && ...
    isequaln(rx.DecodedBitLineage,rx.DecodedBitLineagePerCodeword{1}) && ...
    rx.DecodedBitLineageAliasScope=="codeword_zero_only_not_aggregate");
before = rng;
again = project(rx.Decode,2);
assert(isequal(before,rng) && isequaln(again,rx.DecodedBitLineagePerCodeword));
localCheck(again,rx.Decode);
assert(~any(cellfun(@(x)x.FinalThroughputOutcomeBound,again)), ...
    'A facade result is not a later throughput-combined decoder receipt.');
end

function localSingle(project)
[plans,llr,bits] = localCodec(0,false);
out = sixgr.pdsch.DLSCHDecoder(llr{1},'CodingPlan',plans{1},'MaxIterations',25);
assert(out.CRCPass && isequal(out.TransportBlock,bits{1}));
r = project(out,1); localCheck(r,out);
assert(r{1}.CodewordIndex==0 && r{1}.NumCodewords==1 && ...
    ~r{1}.CodeBlockCRCApplicable && isempty(r{1}.CodeBlockCRCError) && ...
    isempty(r{1}.CodeBlockCRCPass) && r{1}.CurrentAttemptStandaloneCRCMeasured);
end

function localMixedCRC(project)
[plans,llr,bits] = localCodec(0,true);
out = sixgr.pdsch.DLSCHDecoder(llr,'CodingPlan',plans,'MaxIterations',25);
% CW1 contains an intentionally invalid TB CRC before genuine LDPC encoding.
% Its payload is unchanged; this is not a noisy-waveform performance sample.
assert(isequal(out.CRCPassPerCodeword,[true false]) && ~out.CRCPass && ...
    isequal(out.TransportBlocks,bits));
before = out; state = rng;
r = project(out,2); localCheck(r,out);
assert(isequaln(before,out) && isequal(state,rng));
assert(r{1}.CRCPass && ~r{2}.CRCPass && ~r{1}.CRCError && r{2}.CRCError && ...
    r{1}.CodingPlanID~=r{2}.CodingPlanID && ...
    r{1}.CodingLayoutHash==r{2}.CodingLayoutHash, ...
    'Equal-shaped codewords must retain their own identity and CRC, not aggregate CRC copies.');
end

function localCombined(project)
[p0,l0,bits] = localCodec(0,false);
[p2,l2,bits2] = localCodec(2,false);
assert(isequal(bits,bits2));
initial = sixgr.pdsch.DLSCHDecoder(l0,'CodingPlan',p0,'MaxIterations',25);
current = sixgr.pdsch.DLSCHDecoder(l2,'CodingPlan',p2,'MaxIterations',25);
combined = sixgr.pdsch.DLSCHDecoder(l2,'CodingPlan',p2, ...
    'PriorRecoveredLLR',initial,'PriorCodingPlan',p0,'MaxIterations',25);
% Explicit same-TB boundary invocation, not a retransmission ordered after ACK.
r0=project(initial,2); rc=project(current,2); rh=project(combined,2);
localCheck(r0,initial); localCheck(rc,current); localCheck(rh,combined);
assert(combined.CRCPass && isequal(combined.TransportBlocks,bits));
for cw=1:2
    assert(~rc{cw}.HARQSoftCombiningApplied && rc{cw}.CurrentAttemptStandaloneCRCMeasured && ...
        rh{cw}.HARQSoftCombiningApplied && ~rh{cw}.CurrentAttemptStandaloneCRCMeasured && ...
        rh{cw}.RV==2 && r0{cw}.RV==0 && ...
        rh{cw}.HARQCombineInfo.PriorNumel>0 && ...
        rh{cw}.HARQCombineInfo.PositionAware && ...
        rh{cw}.HARQCombineInfo.CodewordIndex==cw && rh{cw}.HARQCodewordIndexBase==1 && ...
        ~rh{cw}.FinalThroughputOutcomeBound && ~rh{cw}.UniqueTransportBlockIdentityAvailable);
end
end

function localGuards(project)
[plans,llr] = localCodec(0,false);
out=sixgr.pdsch.DLSCHDecoder(llr,'CodingPlan',plans,'MaxIterations',25);
id='sixgr:phy:dl:DecodedCodewordEvidenceMismatch';
bad=out; bad.Codewords=bad.Codewords([2 1]); localReject(@()project(bad,2),id);
bad=out; bad.Codewords=bad.Codewords(1); localReject(@()project(bad,2),id);
bad=out; bad.NumCodewords=1; localReject(@()project(bad,2),id);
bad=out; bad.Codewords{2}.CodingPlanID="unrelated_plan"; localReject(@()project(bad,2),id);
bad=out; bad.Codewords{2}.CodingLayout.CodingLayoutHash="unrelated_layout"; localReject(@()project(bad,2),id);
bad=out; bad.Codewords{2}.HARQCombineInfo.CodewordIndex=1; localReject(@()project(bad,2),id);
bad=out; bad.Codewords{2}.TransportBlock=bad.Codewords{2}.TransportBlock(2:end); localReject(@()project(bad,2),id);
bad=out; bad.Codewords{2}.RateRecoveredLLR=bad.Codewords{2}.RateRecoveredLLR(2:end,:); localReject(@()project(bad,2),id);
bad=out; bad.Codewords{2}.CRCPass=false; localReject(@()project(bad,2),id);
end

function [plans,llr,bits] = localCodec(rv,poisonSecondTBCRC)
A=512; rate=.3; layers=3; modulation='QPSK'; G=3600;
bits={int8(mod((1:A).',2)),int8(mod(floor((1:A).'/3),2))};
plans=cell(1,2); llr=cell(1,2); sch=nrDLSCHInfo(A,rate);
for cw=1:2
    plans{cw}=sixgr.pdsch.DLSCHCodingPlan.resolve('TransportBlockSize',A, ...
        'TargetCodeRate',rate,'RV',rv,'Modulation',modulation, ...
        'NumLayers',layers,'RateMatchedBitCount',G,'CodewordIndex',cw-1);
    tbCRC=nrCRCEncode(bits{cw},sch.CRC);
    if poisonSecondTBCRC && cw==2, tbCRC(end)=1-tbCRC(end); end
    cb=nrCodeBlockSegmentLDPC(tbCRC,sch.BGN);
    coded=nrLDPCEncode(cb,sch.BGN);
    matched=nrRateMatchLDPC(coded,G,rv,modulation,layers);
    llr{cw}=20*(1-2*double(matched));
end
end

function localCheck(receipts,decode)
if numel(receipts)==1, words={decode}; else, words=decode.Codewords; end
assert(numel(receipts)==numel(words));
for cw=1:numel(receipts)
    r=receipts{cw}; d=words{cw}; p=d.CodingPlan; h=d.HARQCombineInfo;
    assert(r.ContractVersion=="PDSCHDecodedBitLineage/v2" && ...
        r.CodewordIndex==cw-1 && r.CodewordIndexBase==0 && r.NumCodewords==numel(words) && ...
        r.Source=="canonical_dlsch_decoder_immutable_coding_plan" && ...
        r.DecoderSource==string(d.Source) && ...
        r.ReceiptStage=="PDSCH_Rx_returned_DLSCH_codeword_decode" && ...
        r.PopulationScope=="one_codeword_in_this_receiver_decoder_call");
    assert(r.CodingPlanID==string(d.CodingPlanID) && ...
        r.CodingLayoutHash==string(d.CodingLayout.CodingLayoutHash) && ...
        r.RateMatchSignature==string(p.RateMatchSignature) && ...
        r.CombineSignature==string(p.CombineSignature) && ...
        r.TransportBlockSize==double(p.TransportBlockSize) && ...
        r.DecodedTransportBlockLength==numel(d.TransportBlock) && ...
        r.TransportBlockLengthWithCRC==numel(d.DesegmentedTransportBlockWithCRC));
    assert(isequaln(r.CRCPass,d.CRCPass) && isequaln(r.CRCError,d.CRCError) && ...
        isequaln(r.TransportBlockCRCPass,d.TransportBlockCRCPass) && ...
        isequaln(r.TransportBlockCRCError,d.TransportBlockCRCError) && ...
        isequaln(r.CodeBlockCRCError,d.CodeBlockCRCError) && ...
        isequaln(r.CodeBlockCRCPass,d.CodeBlockCRCPass) && ...
        isequaln(r.HARQCombineInfo,rmfield(h,'SoftBuffer')));
    assert(r.DemapperLLRCount==numel(d.InputRateMatchedLLR) && ...
        r.RateMatchedBitCount==double(p.RateMatchedBitCount) && ...
        r.RateRecoveredRows==size(d.RateRecoveredLLR,1) && ...
        r.RateRecoveredCodeBlocks==size(d.RateRecoveredLLR,2) && ...
        r.DecoderCRCInputDomain=="harq_combined_mother_code");
    forbidden=["InputRateMatchedLLR","RateRecoveredLLR","HARQCombinedLLR", ...
        "TransportBlock","DecodedCodeBlocks","SoftBuffer","LogicalTBID","TBId"];
    assert(~any(isfield(r,forbidden)) && ~isfield(r.HARQCombineInfo,'SoftBuffer') && ...
        ~r.FinalThroughputOutcomeBound && ~r.UniqueTransportBlockIdentityAvailable);
end
end

function [project,cleanup,sourceHash] = localProjection()
path=which('sixgr.phy.dl.PDSCH_Rx'); source=fileread(path);
signature='function lineage = localBuildPDSCHDecodedBitLineage(decode,nCodewords)';
start=strfind(source,signature); assert(isscalar(start));
tail=source(start:end); functions=regexp(tail,'(?m)^function ','start');
assert(numel(functions)>=2 && functions(1)==1);
body=tail(1:functions(2)-1);
generated=strrep(body,signature, ...
    'function lineage = pdschCodewordLineageProjection(decode,nCodewords)');
assert(strcmp(strrep(generated,'pdschCodewordLineageProjection(', ...
    'localBuildPDSCHDecodedBitLineage('),body), ...
    'The test projection must preserve the exact production body.');
folder=tempname; mkdir(folder);
file=fullfile(folder,'pdschCodewordLineageProjection.m');
cleanup=onCleanup(@()localCleanup(folder,file));
fid=fopen(file,'w','n','UTF-8'); assert(fid>=0);
closeFile=onCleanup(@()fclose(fid));
fwrite(fid,generated,'char'); clear closeFile
assert(strcmp(fileread(file),generated));
addpath(folder); project=@pdschCodewordLineageProjection;
sourceHash=string(sixgr.util.sha256File(path));
end

function localCleanup(folder,file)
if any(strcmp(strsplit(path,pathsep),folder)), rmpath(folder); end
if isfile(file), delete(file); end
if isfolder(folder), rmdir(folder); end % Only the new empty test directory.
end

function localReject(fn,id)
try, fn(); catch cause
    assert(strcmp(cause.identifier,id),'Expected %s, received %s: %s', ...
        id,cause.identifier,cause.message); return;
end
error('test:PDSCHCodewordDecodeLineage:MissingGuard','Expected %s.',id);
end
