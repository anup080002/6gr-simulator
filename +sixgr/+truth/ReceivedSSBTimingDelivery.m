classdef ReceivedSSBTimingDelivery
% Original per-beam BCH timing, independent of the installed SI/MIB owner.
% No receiver execution, reconstructed timing, beam choice or age expiry.
methods (Static)
    function receipt=bindCompleted(state,item,context,dl,decoderObservation,acquisitionBinding)
        if nargin<6, acquisitionBinding=[]; end
        % Reuse the original complete-capture/decoder/epoch authentication.
        % This does not install a MIB or rerun any PHY receiver.
        original=sixgr.truth.ReceivedMIBDelivery.bindCompleted( ...
            state,item,context,dl,decoderObservation);
        frozen=sixgr.util.structGet(item.Context,'AcquisitionMIBBinding',[]);
        tracking=sixgr.util.structGet(item.Context,'TrackingOnly',false);
        assert(islogical(tracking) && isscalar(tracking) && isequaln(frozen,acquisitionBinding) && ...
            (~tracking || ~isempty(frozen)), ...
            'sixgr:truth:ReceivedSSBTimingOwnerMismatch', ...
            'Use the original acquisition binding frozen in this capture, not the current mutable generation.');
        generation="";
        if ~isempty(acquisitionBinding)
            sixgr.truth.ReceivedMIBDelivery.validate(acquisitionBinding,true);
            for name=["UEIndex","ServingCell","LinkID","ReceiverID","TransmitterID", ...
                    "PhysicalConfigurationEpoch","AcquisitionConfigurationEpoch","SampleRateHz"]
                assert(isequaln(original.(name),acquisitionBinding.(name)), ...
                    'sixgr:truth:ReceivedSSBTimingOwnerMismatch', ...
                    'Tracking timing must retain the acquisition owner frozen when its capture was armed.');
            end
            assert(original.CaptureStartSample>=acquisitionBinding.DeliveredAvailableSample, ...
                'sixgr:truth:ReceivedSSBTimingOwnerMismatch', ...
                'An existing acquisition cannot own a capture that started before its delivery.');
            generation=acquisitionBinding.GenerationID;
        end
        receipt=struct('ContractVersion',"sixgr.truth.received_ssb_timing_delivery/v1", ...
            'Source',"original_shared_received_BCH_per_beam_timing", ...
            'OriginalBCHBinding',original,'SSBIndex',context.Data.SSBIndex, ...
            'ReceivedDLTimingReference',dl,'AcquisitionGenerationAtCapture',generation, ...
            'BindingSHA256',"",'Delivered',false,'DeliveredAvailableSample',NaN, ...
            'DeliverySlot',NaN,'AcquisitionGenerationID',"",'DeliverySHA256',"");
        receipt.BindingSHA256=localBindingHash(receipt);
        sixgr.truth.ReceivedSSBTimingDelivery.validate(receipt,false);
    end

    function [state,installed,status]=deliver(state,receipt,trial)
        sixgr.truth.ReceivedSSBTimingDelivery.validate(receipt,false);
        installed=false; status="stale_selected_ssb_timing";
        b=receipt.OriginalBCHBinding; owner=localOwner(state);
        now=localNow(state,owner);
        [available,~,acquisition]=sixgr.truth.ReceivedMIBDelivery.current(state,b.UEIndex);
        if ~available || ~localIdentity(state,b), return; end
        if receipt.AcquisitionGenerationAtCapture==""
            % Initial acquisition may deliver every genuinely decoded beam
            % from its original burst, not only the selected MIB candidate.
            if acquisition.ObservationID~=b.ObservationID || ...
                    acquisition.CaptureStartSample~=b.CaptureStartSample || ...
                    acquisition.CaptureEndSampleExclusive~=b.CaptureEndSampleExclusive || ...
                    acquisition.RawPostRFInputSHA256~=b.RawPostRFInputSHA256
                return;
            end
        elseif receipt.AcquisitionGenerationAtCapture~=acquisition.GenerationID
            return; % Never retag a pending tracking capture after reacquisition.
        end
        required={'SSBIndex','ObservationStartSample','ObservationEndSampleExclusive', ...
            'ObservationSampleRateHz','MeasurementClockEpoch','ResultCompletedAtSample', ...
            'ResultAvailableAtSample','DeliverySlotStartSample','ObservationDeliverySlot','ServingCell'};
        assert(istable(trial) && all(ismember(required,trial.Properties.VariableNames)), ...
            'sixgr:truth:ReceivedSSBTimingDeliveryClockRequired', ...
            'Deliver with the original candidate rows at their actual shared publication boundary.');
        % SelectedSSBIndex is the burst-wide winner repeated on every row;
        % SSBIndex is the original decoded/requested candidate identity.
        row=find(trial.SSBIndex==receipt.SSBIndex);
        assert(isscalar(row),'sixgr:truth:ReceivedSSBTimingCandidateMismatch', ...
            'Exactly one original candidate row must own this decoded SSB timing.');
        t=trial(row,:);
        assert(sixgr.truth.pbchAcquisitionAccepted(t) && ...
            t.ServingCell==b.ServingCell && t.ObservationStartSample==b.CaptureStartSample && ...
            t.ObservationEndSampleExclusive==b.CaptureEndSampleExclusive && ...
            t.ObservationSampleRateHz==b.SampleRateHz && t.MeasurementClockEpoch==b.PhysicalConfigurationEpoch && ...
            t.ResultCompletedAtSample==b.BoundAtSample && t.ResultAvailableAtSample==now && ...
            t.DeliverySlotStartSample==now && t.ObservationDeliverySlot==state.CurrentSlot && ...
            now>=b.BoundAtSample, ...
            'sixgr:truth:ReceivedSSBTimingCandidateMismatch', ...
            'The delivered row must preserve its accepted original candidate, capture, completion and delivery clocks.');
        values=sixgr.util.structGet(state,'ReceivedSSBTimingByUE',cell(state.NumUsers,1));
        history={};
        if numel(values)>=b.UEIndex && ~isempty(values{b.UEIndex}), history=values{b.UEIndex}; end
        assert(iscell(history),'sixgr:truth:InvalidReceivedSSBTiming','Retain a cell history of original timing receipts.');
        for k=1:numel(history)
            sixgr.truth.ReceivedSSBTimingDelivery.validate(history{k},true);
            if history{k}.BindingSHA256==receipt.BindingSHA256
                installed=true; status="already_delivered_original_ssb_timing"; return;
            end
        end
        receipt.Delivered=true;
        receipt.DeliveredAvailableSample=now;
        receipt.DeliverySlot=double(state.CurrentSlot);
        receipt.AcquisitionGenerationID=acquisition.GenerationID;
        receipt.DeliverySHA256=localDeliveryHash(receipt);
        history{end+1,1}=receipt;
        values{b.UEIndex,1}=history; state.ReceivedSSBTimingByUE=values;
        installed=true; status="delivered_original_ssb_timing";
    end

    function [available,status,receipt]=current(state,ue,cfg,selectedSSB)
        available=false; status="no_delivered_selected_ssb_timing"; receipt=[];
        localInteger(ue); localInteger(selectedSSB);
        assert(ue>=1 && ue<=state.NumUsers && selectedSSB<=63, ...
            'sixgr:truth:ReceivedSSBTimingOwnerMismatch','Use the original UE and decoded SSB index.');
        owner=localOwner(state); now=localNow(state,owner);
        [current,~,acquisition]=sixgr.truth.ReceivedMIBDelivery.current(state,ue);
        if ~current, status="stale_selected_ssb_timing"; return; end
        geometry=sixgr.phy.broadcast.ReceivedMIBContext.receiverGeometry(cfg);
        values=sixgr.util.structGet(state,'ReceivedSSBTimingByUE',{});
        if numel(values)<ue || isempty(values{ue}), return; end
        history=values{ue}; assert(iscell(history),'sixgr:truth:InvalidReceivedSSBTiming','Retain original timing history.');
        for k=numel(history):-1:1
            r=history{k}; sixgr.truth.ReceivedSSBTimingDelivery.validate(r,true);
            if r.SSBIndex~=selectedSSB, continue; end
            b=r.OriginalBCHBinding; status="stale_selected_ssb_timing";
            if b.UEIndex~=ue || ~localIdentity(state,b) || ...
                    r.AcquisitionGenerationID~=acquisition.GenerationID || ...
                    ~isequaln(geometry,b.Context.Data.ReceiverGeometry) || cfg.phy.carrier.NCellID~=b.Context.Data.NCellID
                continue;
            end
            if r.DeliveredAvailableSample>now
                status="selected_ssb_timing_not_yet_delivered"; continue;
            end
            if isempty(receipt) || b.CaptureEndSampleExclusive>receipt.OriginalBCHBinding.CaptureEndSampleExclusive
                receipt=r;
            end
        end
        if ~isempty(receipt)
            available=true; status="current_delivered_selected_ssb_timing";
        end
    end

    function validate(receipt,requireDelivered)
        assert(islogical(requireDelivered) && isscalar(requireDelivered) && ...
            isstruct(receipt) && isscalar(receipt) && all(isfield(receipt, ...
            {'ContractVersion','Source','OriginalBCHBinding','SSBIndex','ReceivedDLTimingReference', ...
            'AcquisitionGenerationAtCapture','BindingSHA256','Delivered','DeliveredAvailableSample', ...
            'DeliverySlot','AcquisitionGenerationID','DeliverySHA256'})), ...
            'sixgr:truth:InvalidReceivedSSBTiming','Retain the complete original per-beam timing receipt.');
        for name=["ContractVersion","Source","AcquisitionGenerationAtCapture","BindingSHA256", ...
                "AcquisitionGenerationID","DeliverySHA256"]
            assert(isstring(receipt.(name)) && isscalar(receipt.(name)) && ~ismissing(receipt.(name)), ...
                'sixgr:truth:InvalidReceivedSSBTiming','Timing receipt identifiers must be scalar strings.');
        end
        b=receipt.OriginalBCHBinding;
        sixgr.truth.ReceivedMIBDelivery.validate(b,false);
        localInteger(receipt.SSBIndex);
        assert(~b.Delivered && receipt.ContractVersion=="sixgr.truth.received_ssb_timing_delivery/v1" && ...
            receipt.Source=="original_shared_received_BCH_per_beam_timing" && ...
            receipt.SSBIndex==b.Context.Data.SSBIndex && ...
            isequaln(receipt.ReceivedDLTimingReference,b.ReceivedDLTimingReference) && ...
            receipt.BindingSHA256==localBindingHash(receipt) && ...
            islogical(receipt.Delivered) && isscalar(receipt.Delivered), ...
            'sixgr:truth:InvalidReceivedSSBTiming','Original timing/candidate binding changed.');
        if receipt.Delivered
            localInteger(receipt.DeliveredAvailableSample); localInteger(receipt.DeliverySlot);
            assert(receipt.DeliverySlot>=1 && receipt.DeliveredAvailableSample>=b.BoundAtSample && ...
                strlength(receipt.AcquisitionGenerationID)==64 && ...
                (receipt.AcquisitionGenerationAtCapture=="" || ...
                 receipt.AcquisitionGenerationAtCapture==receipt.AcquisitionGenerationID) && ...
                receipt.DeliverySHA256==localDeliveryHash(receipt), ...
                'sixgr:truth:InvalidReceivedSSBTiming','Original timing delivery/generation changed.');
        else
            assert(~requireDelivered && isequaln(receipt.DeliveredAvailableSample,NaN) && ...
                isequaln(receipt.DeliverySlot,NaN) && receipt.AcquisitionGenerationID=="" && receipt.DeliverySHA256=="", ...
                'sixgr:truth:ReceivedSSBTimingNotDelivered','Timing is unavailable before original result delivery.');
        end
    end
end
end

function owner=localOwner(state)
owner=sixgr.util.structGet(state,'SharedWaveformStream',[]);
assert(isa(owner,'sixgr.truth.CoupledWaveformStream') && isscalar(owner), ...
    'sixgr:truth:ReceivedSSBTimingOwnerRequired','Use the original shared receive owner.');
end
function now=localNow(state,owner)
carrier=sixgr.phy.grid.makeCarrier(state.CfgMobility);
now=sixgr.phy.frame.slotStartSample(carrier,state.CurrentSlot-1,owner.SampleRateHz);
localInteger(now);
assert(now==owner.Events.NextSampleIndex,'sixgr:truth:ReceivedSSBTimingDeliveryClockRequired', ...
    'Use the actual canonical boundary, not a future planning clock.');
end
function tf=localIdentity(state,b)
owner=localOwner(state); id=owner.broadcastReceiveIdentity(b.UEIndex);
tf=state.CurrentServingIdx(b.UEIndex)==b.ServingCell;
for name=string(fieldnames(id)).', tf=tf && isequaln(id.(name),b.(name)); end
end
function localInteger(value)
assert(isa(value,'double') && isreal(value) && isscalar(value) && isfinite(value) && ...
    value>=0 && value<=flintmax && value==fix(value), ...
    'sixgr:truth:InvalidReceivedSSBTiming','Timing identities/clocks must be exact nonnegative double integers.');
end
function hash=localBindingHash(r)
hash=localHash(struct('ContractVersion',r.ContractVersion,'Source',r.Source, ...
    'OriginalBCHBindingSHA256',r.OriginalBCHBinding.BindingSHA256,'SSBIndex',r.SSBIndex, ...
    'ReceivedDLTimingReference',r.ReceivedDLTimingReference, ...
    'AcquisitionGenerationAtCapture',r.AcquisitionGenerationAtCapture));
end
function hash=localDeliveryHash(r)
hash=localHash(struct('BindingSHA256',r.BindingSHA256,'Delivered',r.Delivered, ...
    'DeliveredAvailableSample',r.DeliveredAvailableSample,'DeliverySlot',r.DeliverySlot, ...
    'AcquisitionGenerationID',r.AcquisitionGenerationID));
end
function hash=localHash(value)
hash=string(sixgr.util.sha256Hex(jsonencode(sixgr.util.jsonSafeValue(value))));
end
