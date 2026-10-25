classdef SIB1ResultDelivery
% Actual later SI reception and causal installation using a received MIB.
% No transmitter tree, new BCH observation or inferred radio measurement.
methods(Static)
    function [state,recovery]=complete(state,item)
        assert(isstruct(item) && isscalar(item) && string(item.Kind)=="SIB1", ...
            'sixgr:truth:InvalidSIB1Completion','Require the original SI receiver completion.');
        owner=state.SharedWaveformStream;
        owner.validateCompletedBroadcastObservation(item);
        ids=string({item.Planes.ReceiverID});
        postIndex=find(endsWith(ids,':post_rf'));
        preIndex=find(endsWith(ids,':pre_rf'));
        assert(numel(item.Planes)==2 && isscalar(postIndex) && isscalar(preIndex), ...
            'sixgr:truth:InvalidSIB1Completion','SI reception has two received planes, not a prepared transmitter.');
        c=item.Context; binding=c.ReceivedMIBBinding;
        sixgr.truth.ReceivedMIBDelivery.validate(binding,true);
        assert(item.UE==binding.UEIndex && c.ServingCell==binding.ServingCell, ...
            'sixgr:truth:InvalidSIB1Completion','Retain the armed receiver identity.');
        raw=item.Planes(postIndex).Observation;
        pre=item.Planes(preIndex).Observation;
        assert(raw.isComplete() && pre.isComplete() && raw.StartSample==pre.StartSample && ...
            raw.EndSampleExclusive==pre.EndSampleExclusive && raw.SampleRateHz==pre.SampleRateHz && ...
            raw.NumReceiveAntennas==pre.NumReceiveAntennas && ...
            owner.Events.NextSampleIndex>=raw.EndSampleExclusive, ...
            'sixgr:truth:InvalidSIB1Completion','SI input planes must cover the same completed original interval.');
        completed=string(sixgr.util.structGet(state,'CompletedSIB1ObservationIDs',strings(0,1)));
        assert(~any(completed==string(item.ID)), ...
            'sixgr:truth:DuplicateSIB1Completion','Do not decode the same SI observation twice.');
        [decoded,gain]=sixgr.phy.rx.compensateReceivedAGC(raw, ...
            item.Planes(postIndex).Segments,extractBefore(ids(postIndex),':post_rf'));
        recovery=sixgr.phy.broadcast.recoverSIB1UsingReceivedMIB(decoded,c.ReceiverConfig, ...
            binding.Context,'AbsoluteMonitoringSlot',c.AbsoluteMonitoringSlot);
        % Checks actual slot-crop operands; completion authentication above
        % supplies execution identity. A measured miss is retained as-is.
        sixgr.truth.ReceivedMIBDelivery.validateSICaptureProjection(binding.Context.Data,recovery,decoded);
        pending=localPending(state);
        receipt=struct('Item',item,'Recovery',recovery,'GainCompensation',gain, ...
            'RawInputSHA256',string(raw.sampleHash()),'DecoderInputSHA256',string(decoded.sampleHash()), ...
            'EndSampleExclusive',raw.EndSampleExclusive,'SampleRateHz',raw.SampleRateHz);
        receipt.RecoverySHA256=localHash(recovery);
        state.PendingSIB1Results=[pending;receipt];
        state.CompletedSIB1ObservationIDs=[completed(:);string(item.ID)];
    end

    function state=deliver(state)
        pending=localPending(state);
        if isempty(pending), return; end
        validateattributes(state.CurrentSlot,{'double'},{'scalar','real','finite','integer','positive'});
        owner=state.SharedWaveformStream;
        carrier=sixgr.phy.grid.makeCarrier(state.CfgMobility);
        now=sixgr.phy.frame.slotStartSample(carrier,state.CurrentSlot-1,owner.SampleRateHz);
        assert(now<=owner.Events.NextSampleIndex && ...
            all([pending.SampleRateHz]==owner.SampleRateHz), ...
            'sixgr:truth:SIB1DeliveryClockMismatch', ...
            'SI delivery must use the original physical sample clock at the current canonical boundary.');
        due=[pending.EndSampleExclusive]<=now;
        ready=pending(due);
        [~,order]=sort([ready.EndSampleExclusive]);
        ready=ready(order);
        for k=1:numel(ready)
            q=ready(k); item=q.Item; r=q.Recovery; b=item.Context.ReceivedMIBBinding;
            assert(localHash(r)==q.RecoverySHA256, ...
                'sixgr:truth:SIB1PendingResultChanged','Preserve original received SI before delivery.');
            [current,reason]=sixgr.truth.ReceivedMIBDelivery.acceptedSI(state,item.UE,b,r,item);
            accepted=current && isequal(r.StrictOk,true) && isequal(r.DCICrcPass,true) && ...
                isequal(r.DLSCHCrcPass,true) && isequal(r.SIB1ASN1DecodeOk,true) && ...
                isequal(r.SIB1SemanticValid,true);
            if accepted
                state=sixgr.truth.installReceivedSIB1Recovery(state,item.UE,r,state.CurrentSlot,b);
                reason="installed_original_received_SIB1";
            elseif current
                reason="received_SI_not_accepted";
            end
            row=table(string(item.ID),double(item.UE),double(b.ServingCell), ...
                double(item.Context.AbsoluteMonitoringSlot),double(state.CurrentSlot), ...
                double(r.SIB1CaptureStartSample),double(q.EndSampleExclusive),double(q.SampleRateHz), ...
                string(b.GenerationID),q.RawInputSHA256,q.DecoderInputSHA256,q.RecoverySHA256, ...
                logical(accepted),string(reason), ...
                'VariableNames',{'ObservationID','UEId','ServingCell','ResourceAbsoluteSlot0Based', ...
                'DeliverySlot1Based','ObservationStartSample','ObservationEndSampleExclusive', ...
                'ObservationSampleRateHz','ReceivedMIBGenerationID','RawPostRFInputSHA256', ...
                'DecoderInputSHA256','RecoverySHA256','Installed','DeliveryStatus'});
            % One stable schema covers genuine misses, decoder exceptions
            % and success. Absent later-stage evidence is not a false CRC.
            for name=["Status","FailureReason","FailureIdentifier", ...
                    "SIB1InputSampleSHA256","SIB1PayloadHashRx","SIB1RxTreeHash", ...
                    "PriorBCHContextSHA256"]
                row.(name)=string(sixgr.util.structGet(r,name,""));
            end
            for name=["Crash","SIB1ReceptionAttempted","SIB1ObservationComplete", ...
                    "DCICrcPass","DLSCHCrcPass","SIB1ASN1DecodeOk", ...
                    "SIB1SemanticValid","StrictOk","NewBCHReceptionAttempted"]
                row.(name)=double(sixgr.util.structGet(r,name,NaN));
            end
            old=sixgr.util.structGet(state,'SharedSIB1ReceptionTable',table());
            if isempty(old), state.SharedSIB1ReceptionTable=row;
            else, state.SharedSIB1ReceptionTable=[old;row]; end
        end
        state.PendingSIB1Results=pending(~due);
    end
end
end

function pending=localPending(state)
pending=sixgr.util.structGet(state,'PendingSIB1Results', ...
    repmat(struct('Item',struct(),'Recovery',struct(),'GainCompensation',struct(), ...
    'RawInputSHA256',"",'DecoderInputSHA256',"",'EndSampleExclusive',NaN, ...
    'SampleRateHz',NaN,'RecoverySHA256',""),0,1));
end

function hash=localHash(value)
hash=string(sixgr.util.sha256Hex(jsonencode(sixgr.util.jsonSafeValue(value))));
end
