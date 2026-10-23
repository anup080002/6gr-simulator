function [ok,checks]=testDLSCHFinalOutcomeBinding()
% Real one-PRB calibration TX/RX and native mixed-CRC codec outcomes bind to
% explicitly declared rows. The outer buffer-summary entrypoint is an exact
% test-only source extraction: no received DCI or scheduled retry is claimed.
% This does not qualify the strict final owner, public legacy loop or writer.
setup6GRSimToolkit('Verbose',false);
saved=rng; restore=onCleanup(@()rng(saved)); %#ok<NASGU>
[owner,cleanup,sourcePath,sourceHash]=localOwner(); %#ok<ASGLU>
rows=repmat(struct('Case',"",'Passed',false,'FailureID',"",'Detail',""),0,1);
record("actual_rank1_decoder_declared_row_binding",@()waveform(1));
record("actual_rank6_decoder_declared_row_binding",@()waveform(6));
record("mixed_CRC_counts_and_lossless_raw_CSV",@mixed);
record("original_scalar_outer_failure_reproducer",@counterexample);
record("unavailable_decode_preserves_scalar_prior_container",@unavailable);
record("final_binding_contradiction_guards",@guards);
assert(string(sixgr.util.sha256File(sourcePath))==sourceHash);
checks=struct2table(rows);
for k=find(~checks.Passed).'
    fprintf(2,'DLSCH_FINAL_BIND %s FAIL %s %s\n',checks.Case(k),checks.FailureID(k),checks.Detail(k));
end
fprintf('DLSCH_FINAL_BIND cases=%d failures=%d private_buffer_summary=1 strict_final_owner=0 public_main_loop=0 received_DCI=0 source_SHA256=%s\n', ...
    height(checks),nnz(~checks.Passed),sourceHash);
assert(all(checks.Passed),'test:DLSCHFinalOutcomeBinding:Failed','%d/%d final binding cases failed.',nnz(~checks.Passed),height(checks));
ok=true;

    function record(name,fn)
        row=struct('Case',name,'Passed',false,'FailureID',"",'Detail',"");
        try, fn(); row.Passed=true;
        catch cause
            row.FailureID=string(cause.identifier); row.Detail=string(getReport(cause,'extended','hyperlinks','off'));
        end
        rows(end+1,1)=row; %#ok<AGROW>
    end
    function waveform(rankValue)
        f=StrictPDSCHChainFixture.create(rankValue,'NPRB',1);
        cfg=sixgr.config.defaultConfig();
        cfg.run.pdschExecutionProfile='phy_calibration'; cfg.run.strictMode=false;
        cfg.phy.pdsch.executionProfile='phy_calibration'; cfg.phy.pdsch.enable=true;
        cfg.phy.carrier.NSizeGrid=1; cfg.phy.carrier.SubcarrierSpacing=30;
        cfg.channel.model='AWGN'; cfg.channel.awgnOnly=true;
        cfg.phy.ldpc.useMexBatchDecode=false;
        args={'Carrier',f.Carrier,'Assignment',f.Assignment,'ResourcePlan',f.ResourcePlan, ...
            'ReferenceSignalConfig',f.ReferenceConfig,'PrecoderBundle',f.PrecoderBundle, ...
            'IntegrationContext',f.IntegrationContext,'ExecutionProfile','phy_calibration'};
        tx=sixgr.phy.dl.PDSCH_Tx(cfg,args{:},'TransportBlockBits',f.TransportBlocks);
        rx=sixgr.phy.dl.PDSCH_Rx(tx.Waveform,cfg,args{:}, ...
            'ReceiverConfig',f.ReceiverConfig,'CodingPlan',tx.CodingPlans);
        assert(rx.CRCPass&&isequal(rx.TransportBlocks,f.TransportBlocks)&& ...
            rx.IntegrationBinding.Status=="NOT_REQUIRED_PHY_CALIBRATION");
        [selection,state]=sixgr.link.finalizeDLSCHCodewordOutcomes(rx.Decode,cfg);
        t=table("DL",double(f.Carrier.NFrame),double(f.Carrier.NSlot),rx.CRCPass, ...
            sum(cellfun(@numel,f.TransportBlocks)), ...
            "actual_calibration_facade_decoder_declared_row_binding", ...
            'VariableNames',{'Direction','Frame','Slot','CRCPass','OfferedBits','Source'});
        t.AssignmentId=f.Assignment.AssignmentId;
        t.AssignmentValidationDigest=string(f.Assignment.validateForExecution());
        selection.Assignment=f.Assignment.toStruct();
        [t,final]=sixgr.link.bindDLSCHFinalOutcome(t,selection);
        assert(final.FinalThroughputOutcomeBound&&final.NumCodewords==numel(f.TransportBlocks)&& ...
            final.AdditionalDecoderInvocationCount==0&&~final.MACDeliveryQualified&& ...
            isequaln(final.Assignment,f.Assignment.toStruct())&&isequal(state.TransportBlocks,f.TransportBlocks));
        assert(t.DLSCHFinalOutcomeAvailable&&t.DLSCHFinalOutcomeStage==final.Stage&& ...
            t.DLSCHFinalOutcomeJSON==string(jsonencode(final))&& ...
            t.DLSCHFinalOutcomeSHA256==string(sixgr.util.sha256Hex(char(t.DLSCHFinalOutcomeJSON)))&& ...
            t.DLSCHSuccessfulDecodedBits==sum(cellfun(@numel,f.TransportBlocks)));
        if final.NumCodewords==1, words={rx.Decode}; else, words=rx.Decode.Codewords; end
        for cw=1:final.NumCodewords
            r=final.Codewords{cw}; d=words{cw};
            assert(r.CodewordIndex==cw-1&&r.CodingPlanID==string(d.CodingPlanID)&& ...
                r.CRCPass==d.CRCPass&&r.TransportBlockSize==numel(d.TransportBlock)&& ...
                r.DecodedTransportBlockSHA256==string(sixgr.channel.ChannelFactory.runtimeNumericArraySHA256(d.TransportBlock)));
        end
    end
    function mixed()
        [d,~]=localCodec(); cfg=localConfig(); before=d;
        [f,s]=sixgr.link.finalizeDLSCHCodewordOutcomes(d,cfg);
        t=localRow(false); original=t;
        [t,b]=sixgr.link.bindDLSCHFinalOutcome(t,f);
        assert(isequaln(d,before)&&isequaln(t(:,original.Properties.VariableNames),original));
        assert(~b.CRCPass&&isequal(b.CRCPassPerCodeword,[true false])&& ...
            b.SuccessfulDecodedBits==512&&t.GoodBits==0&&t.DLSCHSuccessfulDecodedBits==512&& ...
            ~b.MACDeliveryQualified&&~b.UniqueTransportBlockIdentityAvailable&& ...
            b.Codewords{1}.DecodedTransportBlockSHA256==string(sixgr.channel.ChannelFactory.runtimeNumericArraySHA256(s.TransportBlocks{1})));
        assert(t.DLSCHAggregateGoodBitsPolicy=="all_codewords_CRC_pass_required_existing_throughput_policy"&& ...
            t.DLSCHSuccessfulDecodedBitsScope=="this_decoder_attempt_not_unique_MAC_delivery");
        retryRow=original; retryRow.OfferedBits=0;
        retry=sixgr.link.bindDLSCHFinalOutcome(retryRow,f);
        assert(retry.OfferedBits==0&&retry.DLSCHSuccessfulDecodedBits==512, ...
            'No newly offered traffic does not erase the retransmission decoder population.');
        folder=tempname; mkdir(folder); file=fullfile(folder,'original_final_row.csv');
        remove=onCleanup(@()localRemove(folder,file)); %#ok<NASGU>
        sixgr.util.csvWriteTable(file,t,'RoundTripNumericText',true);
        read=sixgr.util.csvReadTable(file);
        assert(string(read.DLSCHFinalOutcomeJSON)==t.DLSCHFinalOutcomeJSON&& ...
            string(read.DLSCHFinalOutcomeSHA256)==t.DLSCHFinalOutcomeSHA256&& ...
            double(read.DLSCHSuccessfulDecodedBits)==512&&double(read.GoodBits)==0&& ...
            logical(read.DLSCHFinalOutcomeAvailable));
        saved=jsondecode(char(string(read.DLSCHFinalOutcomeJSON)));
        assert(isequal(logical(saved.CRCPassPerCodeword(:).'),[true false])&&saved.SourceRow.Frame==3&&saved.SourceRow.Slot==7);
    end
    function counterexample()
        % Exact old failure operands: a real passing CW0 combined decoder
        % result cannot be scored against both concatenated transport blocks.
        [d,bits]=localCodec();
        [pass,~,cw0]=sixgr.phy.harq.decodeCombinedDLSCH(d.Codewords{1}.CodingLayout, ...
            d.Codewords{1}.HARQCombinedLLR,localConfig());
        assert(pass&&numel(cw0)==512);
        reject(@()sixgr.link.scoreReceivedDLTransportBlock( ...
            struct('CRCPass',pass,'TransportBlock',cw0),vertcat(bits{:})), ...
            'sixgr:link:DLDecodedTBSMismatch');
        [f,s]=sixgr.link.finalizeDLSCHCodewordOutcomes(d,localConfig(),'Mode','legacy_outer_harq');
        [combined,e]=owner("combining",[],d,s);
        assert(iscell(combined)&&numel(combined)==2&&iscell(e.SoftBuffer)&&numel(e.SoftBuffer)==2&& ...
            e.CurrentLLRCount==sum(cellfun(@numel,s.CombinedLLRPerCodeword))&&isnan(e.LLRCombiningGain_dB));
        for cw=1:2, assert(e.SoftBuffer{cw}.CodewordIndex==cw); end
        assert(~f.CRCPass&&isequal(f.CRCPassPerCodeword,[true false]));
        % A declared invalid connected wrapper cannot bypass the existing
        % scheduler singleton limitation by providing CW0 aggregate aliases.
        invalid=struct('ExecutionProfile',"connected_strict", ...
            'SchedulingOwnership',"received_control_and_ue_owned_harq", ...
            'DecoderCRCInputDomain',"harq_combined_mother_code",'Decode',d);
        reject(@()sixgr.link.receivedDLHARQCombiningEvidence(invalid),'sixgr:link:ReceivedDLHARQCodewordScope');
    end
    function guards()
        [d,~]=localCodec(); [f,~]=sixgr.link.finalizeDLSCHCodewordOutcomes(d,localConfig());
        t=localRow(false); id='sixgr:link:DLSCHFinalOutcomeBinding';
        bad=t; bad.CRCPass=true; reject(@()sixgr.link.bindDLSCHFinalOutcome(bad,f),id);
        bad=t; bad.Frame=NaN; reject(@()sixgr.link.bindDLSCHFinalOutcome(bad,f),id);
        bad=t; bad.BitsCompared=512; reject(@()sixgr.link.bindDLSCHFinalOutcome(bad,f),id);
        bad=t; bad.DecodeAttempted=false; reject(@()sixgr.link.bindDLSCHFinalOutcome(bad,f),id);
        bad=t; bad.Crash=true; reject(@()sixgr.link.bindDLSCHFinalOutcome(bad,f),id);
        bad=t; bad.Direction="UL"; reject(@()sixgr.link.bindDLSCHFinalOutcome(bad,f),id);
        bad=f; bad.CRCPassPerCodeword=[false false]; reject(@()sixgr.link.bindDLSCHFinalOutcome(t,bad),id);
        bad=f; bad.Codewords=bad.Codewords([2 1]); reject(@()sixgr.link.bindDLSCHFinalOutcome(t,bad),id);
        bad=f; bad.SuccessfulDecodedBits=0; reject(@()sixgr.link.bindDLSCHFinalOutcome(t,bad),id);
        [bound,b]=sixgr.link.bindDLSCHFinalOutcome(t,f);
        reject(@()sixgr.link.bindDLSCHFinalOutcome(t,b),id);
        bad=bound; bad.DLSCHFinalOutcomeJSON="replaced"; reject(@()sixgr.link.bindDLSCHFinalOutcome(bad,f),id);
    end
    function unavailable()
        % Constructor-only declared metadata. No receiver or combining call
        % is made: these tokens test original prior-container preservation.
        buffer0=struct('DeclaredTestToken',"CW0");
        buffer1=struct('DeclaredTestToken',"CW1");
        priors={[],single([1;2]),buffer0,{buffer0},{buffer0,buffer1}};
        tx=struct('TransportBlock',int8([0;1]));
        grant=struct('DeclaredGrantToken',"no_decoded_authority_claim");
        context=struct('TransportBlockContext',struct('DeclaredContextToken',"unchanged"), ...
            'HARQContextStatus',"declared_constructor_only");
        for k=1:numel(priors)
            prior=priors{k}; result=owner("unavailable",tx,prior,grant,context);
            assert(isscalar(result)&&isequaln(result.CombinedLLR,prior)&& ...
                isequal(result.TransportBlockBits,tx.TransportBlock)&& ...
                isempty(result.DecodedTransportBlockBits)&&~result.CurrentDecodeOK&& ...
                ~result.CombinedDecodeOK&&isnan(result.DecoderIterations)&& ...
                isequaln(result.GrantSnapshot,grant)&&isequaln(result.Context,context)&& ...
                isequaln(result.TransportBlockContext,context.TransportBlockContext)&& ...
                isequaln(result.HARQTBContext,context.TransportBlockContext)&& ...
                ~any(isfield(result,{'FinalCodewordOutcome','DLSCHFinalOutcomeAvailable','FinalDecodedTransportBlocks'})), ...
                'No-decode retention must keep one result, exact prior type/identity and no new decoder receipt.');
        end
    end
end

function t=localRow(pass)
t=table("DL",3,7,logical(pass),false,true,true,1024,1024,0, ...
    "declared_native_codec_no_waveform", ...
    'VariableNames',{'Direction','Frame','Slot','CRCPass','Crash','DecodeAttempted','DLSCHDecodeAttempted','BitsCompared','OfferedBits','GoodBits','Source'});
end
function cfg=localConfig()
cfg=struct('phy',struct('ldpc',struct('maxIterations',25,'algorithm','Normalized min-sum')));
end
function [d,bits]=localCodec()
A=512; rate=.3; layers=3; G=3600; sch=nrDLSCHInfo(A,rate);
bits={int8(mod((1:A).',2)),int8(mod(floor((1:A).'/3),2))};
plans=cell(1,2); llr=cell(1,2);
for cw=1:2
    plans{cw}=sixgr.pdsch.DLSCHCodingPlan.resolve('TransportBlockSize',A,'TargetCodeRate',rate, ...
        'RV',0,'Modulation','QPSK','NumLayers',layers,'RateMatchedBitCount',G,'CodewordIndex',cw-1);
    crc=nrCRCEncode(bits{cw},sch.CRC); if cw==2, crc(end)=1-crc(end); end
    coded=nrLDPCEncode(nrCodeBlockSegmentLDPC(crc,sch.BGN),sch.BGN);
    matched=nrRateMatchLDPC(coded,G,0,'QPSK',layers);
    llr{cw}=20*(1-2*double(matched));
end
d=sixgr.pdsch.DLSCHDecoder(llr,'CodingPlan',plans,'MaxIterations',25,'Algorithm','Normalized min-sum');
assert(isequal(d.CRCPassPerCodeword,[true false])&&isequal(d.TransportBlocks,bits));
end

function [owner,cleanup,sourcePath,sourceHash]=localOwner()
sourcePath=which('sixgr.link.runDLPDSCHThroughput'); source=fileread(sourcePath);
first=strfind(source,'function T = localCombineObservedREChunks(chunks)'); assert(isscalar(first));
suffix=source(first:end);
assert(isscalar(strfind(suffix,'function [combined,diag]=localFinalCodewordCombiningEvidence(')));
marker=strfind(source,'"DecodedTransportBlockBits", int8([]),'); assert(isscalar(marker));
constructors=regexp(source(1:marker),'(?m)^[ \t]*lastHARQ = struct\( \.\.\.','start');
assert(~isempty(constructors)); unavailableTail=source(constructors(end):end);
stopToken='"Context", harqContext);'; stops=strfind(unavailableTail,stopToken); assert(~isempty(stops));
unavailableBody=unavailableTail(1:stops(1)+numel(stopToken)-1);
assert(isscalar(strfind(unavailableBody,'"DecodedTransportBlockBits", int8([]),')));
unavailableFunction=[sprintf('function lastHARQ=localUnavailableProjection(tx,previousCombinedLLR,grantSnapshot,harqContext)\n') ...
    unavailableBody sprintf('\nend\n')];
header=sprintf(['function varargout=dlFinalOwnerBoundary(operation,varargin)\n' ...
    'switch operation\n' ...
    'case "combining"\n[varargout{1:nargout}]=localFinalCodewordCombiningEvidence(varargin{:});\n' ...
    'case "unavailable"\n[varargout{1:nargout}]=localUnavailableProjection(varargin{:});\n' ...
    'otherwise\nerror("test:DLSCHFinalOutcomeBinding:Operation","Unknown test operation.");\nend\nend\n']);
generated=[header unavailableFunction suffix];
assert(isequal(generated(numel(header)+numel(unavailableFunction)+1:end),suffix)&& ...
    isscalar(strfind(generated,unavailableBody)));
folder=tempname; mkdir(folder); file=fullfile(folder,'dlFinalOwnerBoundary.m');
cleanup=onCleanup(@()localRemove(folder,file));
fid=fopen(file,'w','n','UTF-8'); assert(fid>=0); close=onCleanup(@()fclose(fid));
fwrite(fid,generated,'char'); clear close
assert(strcmp(fileread(file),generated)); addpath(folder); owner=@dlFinalOwnerBoundary;
sourceHash=string(sixgr.util.sha256File(sourcePath));
end
function localRemove(folder,file)
if any(strcmp(strsplit(path,pathsep),folder)), rmpath(folder); end
if isfile(file), delete(file); end
if isfolder(folder), rmdir(folder); end
end
function reject(fn,id)
try, fn(); catch cause
    assert(strcmp(cause.identifier,id),'test:DLSCHFinalOutcomeBinding:WrongGuard', ...
        'Expected %s, got %s: %s',id,cause.identifier,cause.message); return;
end
error('test:DLSCHFinalOutcomeBinding:MissingGuard','Expected %s.',id);
end
