classdef MACVectorValidator
    %MACVECTORVALIDATOR Compare production logic with independent vectors.

    methods (Static)
        function result=validate(vectorRoot)
            vectorRoot=string(vectorRoot);
            if ~isfolder(vectorRoot)
                error("sixgr:mac:MissingVectorPack", ...
                    "VectorRoot does not exist: %s.",vectorRoot);
            end
            families=["bsr5","bsr8","bsr_refined","phr","pcmax", ...
                "harq_state","harq_feedback","timing","tdd","soft_buffer", ...
                "lcp","pdu","ta","scheduler","lineage"];
            files=["expected_bsr_5bit_table.csv","expected_bsr_8bit_table.csv", ...
                "expected_refined_bsr_8bit_table.csv","expected_phr_mapping.csv", ...
                "expected_pcmax_mapping.csv","mac_harq_state_transition_vectors.csv", ...
                "mac_harq_feedback_codebook_vectors.csv", ...
                "mac_timing_k0_k1_k2_vectors.csv", ...
                "mac_tdd_eligibility_vectors.csv", ...
                "mac_soft_buffer_provenance_vectors.csv", ...
                "mac_lcp_test_vectors.csv","mac_pdu_subheader_test_vectors.csv", ...
                "mac_timing_advance_test_vectors.csv", ...
                "mac_scheduler_policy_test_vectors.csv", ...
                "mac_packet_lineage_test_vectors.csv"];
            mismatch=zeros(numel(families),1);
            cases=zeros(numel(families),1);
            maxError=zeros(numel(families),1);
            for ii=1:numel(families)
                tableValue=localRead(fullfile(vectorRoot,files(ii)));
                cases(ii)=height(tableValue);
                [mismatch(ii),maxError(ii)]=localValidateFamily( ...
                    families(ii),tableValue);
            end
            % Related state vectors are folded into their procedure family.
            extras={ ...
                "bsr5","mac_bsr_trigger_timer_vectors.csv"; ...
                "phr","mac_phr_trigger_timer_vectors.csv"; ...
                "lcp","mac_sr_state_vectors.csv"; ...
                "pdu","mac_ce_priority_test_vectors.csv"};
            for ii=1:size(extras,1)
                family=extras{ii,1}; extra=localRead(fullfile(vectorRoot,extras{ii,2}));
                [m,e]=localValidateExtra(extras{ii,2},extra);
                index=find(families==family,1);
                mismatch(index)=mismatch(index)+m;
                cases(index)=cases(index)+height(extra);
                maxError(index)=max(maxError(index),e);
            end
            result=struct("Passed",all(mismatch==0), ...
                "MismatchCount",sum(mismatch),"Cases",sum(cases), ...
                "Table",table(families.',cases,mismatch,maxError, ...
                'VariableNames',{'VectorFamily','Cases','MismatchCount', ...
                'MaxAbsoluteError'}));
        end
    end
end

function [mismatch,maxError]=localValidateFamily(family,value)
mismatch=0; maxError=0;
switch family
    case {"bsr5","bsr8","bsr_refined"}
        ids=struct("bsr5","5bit","bsr8","8bit","bsr_refined","refined8bit");
        bounds=sixgr.l2.mac.BSRTableR18.upperBounds(ids.(char(family)));
        for ii=1:height(value)
            expected=localNumber(value.UpperInclusive(ii));
            actual=bounds(ii);
            if isnan(expected)
                reserved=localTruth(value.Reserved(ii));
                ok=(reserved&&isnan(actual))||(~reserved&&isinf(actual));
                errorValue=double(~ok);
            else
                errorValue=abs(actual-expected);
            end
            mismatch=mismatch+(errorValue~=0);
            maxError=max(maxError,errorValue);
        end
    case {"phr","pcmax"}
        for ii=1:height(value)
            index=str2double(value.Index(ii));
            if family=="phr"
                [lower,upper]=sixgr.l2.mac.PHRMappingR18.phRange(index);
            else
                [lower,upper]=sixgr.l2.mac.PHRMappingR18.pcmaxRange(index);
            end
            expectedLower=localNumber(value.LowerInclusive(ii));
            expectedUpper=localNumber(value.UpperExclusive(ii));
            errors=[localBoundError(lower,expectedLower), ...
                localBoundError(upper,expectedUpper)];
            mismatch=mismatch+any(errors~=0); maxError=max([maxError errors]);
        end
    case "harq_state"
        for ii=1:height(value)
            valid=localTruth(value.ExpectedValid(ii)); actualValid=true; actualState="";
            errorID="";
            try
                actualState=sixgr.l2.mac.HARQProcess.nextState( ...
                    value.Direction(ii),value.FromState(ii),value.Event(ii));
            catch ME
                actualValid=false; errorID=string(ME.identifier);
            end
            ok=actualValid==valid;
            if valid, ok=ok&&actualState==value.ToState(ii);
            else, ok=ok&&errorID==value.ExpectedError(ii); end
            mismatch=mismatch+~ok;
        end
    case "harq_feedback"
        for ii=1:height(value)
            data=struct("Outcome",value.Outcome(ii), ...
                "CodebookType",value.CodebookType(ii), ...
                "DAI",str2double(value.DAI(ii)), ...
                "BitPosition",str2double(value.BitPosition(ii)), ...
                "ServingCell",str2double(value.ServingCell(ii)), ...
                "HARQProcess",0,"Codeword",0,"SourceAttemptID","A", ...
                "DueSlot",1,"ReceivedSlot",1);
            actualValid=true; actualState=""; errorID="";
            try
                feedback=sixgr.l2.mac.HARQFeedbackEvent(data);
                actualState=feedback.apply();
            catch ME
                actualValid=false; errorID=string(ME.identifier);
            end
            valid=localTruth(value.ExpectedValid(ii));
            ok=actualValid==valid;
            if valid, ok=ok&&actualState==value.ExpectedNextState(ii);
            else, ok=ok&&errorID==value.ExpectedError(ii); end
            mismatch=mismatch+~ok;
        end
    case "timing"
        for ii=1:height(value)
            pdcch=str2double(value.PDCCHSlot(ii));
            actual=[pdcch+str2double(value.K0(ii)), ...
                pdcch+str2double(value.K0(ii))+str2double(value.K1(ii)), ...
                pdcch+str2double(value.K2(ii))];
            expected=str2double([value.PDSCHSlot(ii),value.PUCCHSlot(ii), ...
                value.PUSCHSlot(ii)]);
            errorValue=max(abs(actual-expected));
            mismatch=mismatch+(errorValue~=0); maxError=max(maxError,errorValue);
        end
    case "tdd"
        for ii=1:height(value)
            actual=sixgr.l2.mac.CentralMACTimingService.isSegmentLegal( ...
                value.CommonPattern(ii),value.RequestedDirection(ii), ...
                str2double(value.StartSymbol(ii)), ...
                str2double(value.LengthSymbols(ii)), ...
                value.FlexibleResolution(ii));
            mismatch=mismatch+(actual~=localTruth(value.ExpectedLegal(ii)));
        end
    case "soft_buffer"
        actual=localTruth(value.SameTB)&localTruth(value.SameCodeword)& ...
            localTruth(value.SameCodingLayout)& ...
            localTruth(value.SameMotherCodePositions)& ...
            localTruth(value.SameServingCell)&localTruth(value.SameNDIEpoch);
        mismatch=sum(actual~=localTruth(value.ExpectedCombine));
    case "lcp"
        for ii=1:height(value)
            actual=sixgr.l2.mac.LogicalChannelState.nextBj( ...
                str2double(value.PreviousBj_Bytes(ii)), ...
                str2double(value.PrioritizedBitRate_kBps(ii)), ...
                str2double(value.BucketSizeDuration_ms(ii)), ...
                str2double(value.Elapsed_ms(ii)));
            expected=str2double(value.ExpectedBj_Bytes(ii));
            errorValue=abs(actual-expected);
            mismatch=mismatch+(errorValue>1e-9); maxError=max(maxError,errorValue);
        end
    case "pdu"
        for ii=1:height(value)
            actualValid=true; headerLength=NaN; errorID="";
            try
                header=sixgr.l2.mac.MACSubheaderCodec.encode( ...
                    value.Direction(ii),str2double(value.LCID(ii)), ...
                    str2double(value.PayloadLength(ii)));
                headerLength=numel(header);
            catch ME
                actualValid=false; errorID=string(ME.identifier);
            end
            valid=localTruth(value.ExpectedValid(ii));
            ok=actualValid==valid;
            if valid
                ok=ok&&headerLength==str2double(value.ExpectedHeaderBytes(ii));
            else
                ok=ok&&errorID==value.ExpectedError(ii);
            end
            mismatch=mismatch+~ok;
        end
    case "ta"
        for ii=1:height(value)
            if ismissing(value.TACommand(ii)) || strlength(value.TACommand(ii))==0
                continue;
            end
            [delta,nta]=sixgr.l2.mac.TimingAdvanceGroupState.resolveCommand( ...
                str2double(value.Mu(ii)),str2double(value.CurrentNTA(ii)), ...
                str2double(value.TACommand(ii)));
            expected=[str2double(value.ExpectedDeltaUnits(ii)), ...
                str2double(value.ExpectedNTA(ii))];
            errorValue=max(abs([delta nta]-expected));
            mismatch=mismatch+(errorValue>1e-9); maxError=max(maxError,errorValue);
        end
    case "scheduler"
        for ii=1:height(value)
            row=table(str2double(value.UEID(ii)),1,string("DL"),1, ...
                str2double(value.HoLDelay_ms(ii)),str2double(value.PDB_ms(ii)), ...
                str2double(value.Priority(ii)),str2double(value.InstantRate(ii)), ...
                str2double(value.AverageRate(ii)),localTruth(value.Eligible(ii)), ...
                str2double(value.NumUE(ii)),str2double(value.Seed(ii)), ...
                'VariableNames',{'UEID','ServingCell','Direction','QueueBytes', ...
                'HoLDelay_ms','PDB_ms','Priority','InstantRate', ...
                'AverageRate','Eligible','NumUE','Seed'});
            snapshot=sixgr.l2.mac.SchedulerSnapshot(row);
            actual=sixgr.l2.mac.SchedulerPolicy.create(value.Policy(ii)).score(snapshot);
            expected=str2double(value.ExpectedMetric(ii));
            errorValue=abs(actual-expected);
            mismatch=mismatch+(errorValue>5e-6); maxError=max(maxError,errorValue);
        end
    case "lineage"
        for ii=1:height(value)
            packetBytes=str2double(value.PacketBytes(ii));
            offset=str2double(value.SegmentOffset(ii));
            bytes=str2double(value.SegmentBytes(ii));
            actual=offset>=0&&bytes>=0&&offset+bytes<=packetBytes;
            mismatch=mismatch+(actual~=localTruth(value.ExpectedByteConservation(ii)));
        end
end
end

function [mismatch,maxError]=localValidateExtra(fileName,value)
mismatch=0; maxError=0;
switch fileName
    case "mac_bsr_trigger_timer_vectors.csv"
        for ii=1:height(value)
            trigger=lower(value.Trigger(ii)); active=str2double(value.ActiveLCGs(ii));
            grant=str2double(value.GrantBytes(ii)); valid=true; transmit=false; format="none";
            if active>0
                if trigger=="padding"&&grant==0
                    valid=false;
                    if active==1, format="short"; end
                elseif active==1
                    format="short"; transmit=true;
                elseif grant>=3
                    format="long"; transmit=true;
                elseif grant==2
                    format="shortTruncated"; transmit=true;
                end
            end
            ok=valid==localTruth(value.ExpectedValid(ii))&& ...
                transmit==localTruth(value.ExpectedTransmit(ii))&& ...
                format==value.ExpectedFormat(ii);
            mismatch=mismatch+~ok;
        end
    case "mac_phr_trigger_timer_vectors.csv"
        for ii=1:height(value)
            ph=sixgr.l2.mac.PHRMappingR18.phIndex(str2double(value.PH_dB(ii)));
            pc=sixgr.l2.mac.PHRMappingR18.pcmaxIndex(str2double(value.PCMAX_dBm(ii)));
            errorValue=max(abs([ph pc]-[str2double(value.ExpectedPHIndex(ii)), ...
                str2double(value.ExpectedPCMAXIndex(ii))]));
            report=~localTruth(value.ProhibitTimerRunning(ii));
            ok=errorValue==0&&report==localTruth(value.ExpectedReport(ii));
            mismatch=mismatch+~ok; maxError=max(maxError,errorValue);
        end
    case "mac_sr_state_vectors.csv"
        for ii=1:height(value)
            valid=true; next=""; transmit=false; errorID="";
            try
                next=sixgr.l2.mac.SchedulingRequestState.nextState( ...
                    value.FromState(ii),value.Event(ii));
                transmit=upper(value.Event(ii))=="SR_TX";
            catch ME, valid=false; errorID=string(ME.identifier); end
            expectedValid=localTruth(value.ExpectedValid(ii));
            ok=valid==expectedValid;
            if expectedValid
                ok=ok&&next==value.ToState(ii)&& ...
                    transmit==localTruth(value.SRTransmission(ii));
            else
                ok=ok&&errorID==value.ExpectedError(ii);
            end
            mismatch=mismatch+~ok;
        end
    case "mac_ce_priority_test_vectors.csv"
        for ii=1:height(value)
            items=struct("Name",{char(value.TriggeredCE1(ii)), ...
                char(value.TriggeredCE2(ii))},"RequiredBytes",{1,1});
            decision=sixgr.l2.mac.MACCEPriorityResolver.select(items, ...
                max(1,str2double(value.GrantBytes(ii))));
            ok=~isempty(decision.Selected)&& ...
                decision.Selected(1)==value.SelectedFirst(ii);
            mismatch=mismatch+~ok;
        end
end
end

function value=localRead(path)
value=readtable(path,"TextType","string","VariableNamingRule","preserve");
for name=string(value.Properties.VariableNames)
    value.(name)=string(value.(name));
end
end

function value=localTruth(input)
value=ismember(upper(string(input)),["1","TRUE","YES","PASS"]);
end

function value=localNumber(input)
if strlength(string(input))==0
    value=NaN;
else
    value=str2double(input);
end
end

function value=localBoundError(actual,expected)
if isnan(expected)
    value=double(~isinf(actual));
else
    value=abs(actual-expected);
end
end
