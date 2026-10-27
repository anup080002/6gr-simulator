function state=testN40ReceivedMACContinuation(state,cfg,ul,prefixSlot,folder)
% Original 20MHz SRS prefix -> actual SR/DCI/PUSCH -> received MAC demand.
% Common cell/connected/DRB/TAG are declared inputs, not decoded RA/RRC.
owner=state.SharedWaveformStream;
assert(state.ProtocolWaveformEnabled&&state.TestMACNoGrantBeforeReceivedDemand);
assert(cfg.phy.carrier.NSizeGrid==51&&cfg.phy.carrier.SubcarrierSpacing==30&&owner.SampleRateHz==30.72e6);
state.TestMACUL=table(); state.TestMACDL=table(); state.TestMACUC=table(); state.TestMACDC=table();
state.TestMACDS={struct()}; state.TestMACUS={struct()}; state.TestMACIssued={};
state.TestMACPlanning={}; state.TestMACRoot=folder;
state.SharedPendingULGrants=repmat(struct(),0,1);
expiry=ul.SharedULTimingContext.TimeAlignmentExpirySampleExclusive;
horizon=min(prefixSlot+25,floor(expiry/(owner.SampleRateHz*state.SlotDuration_s)));
assert(horizon>prefixSlot&&cfg.phy.csi.reportPeriodicitySlots==40);
for slot=prefixSlot+1:horizon
    [dl,~]=sixgr.truth.CoupledTruthRuntime.resolveSlotPartition(cfg,slot);
    direction="UL"; if dl, direction="DL"; end
    [state,pending,blocked]=sixgr.truth.CoupledTruthRuntime.startSlotWithQueuedUL( ...
        state,cfg,direction,1,1,slot,horizon,cfg.channel.snr_dB,state.SharedPendingULGrants, ...
        sixgr.truth.isPUSCHUCIAvailable(cfg));
    assert(isempty(blocked),'test:MACUnexpectedResourceCollision','Do not suppress an original resource conflict.');
    state.SharedPendingULGrants=pending;
    % Original completed receive windows become usable only at this start.
    state=sixgr.truth.SharedSRSRuntime.deliver(state);
    state=sixgr.truth.CoupledTruthRuntime.refreshControlState(state);
    [state,pending,~]=sixgr.truth.SharedSRSRuntime.prepare( ...
        state,cfg,1,cfg.channel.snr_dB,pending,@logLine);
    state.SharedPendingULGrants=pending;
    state=sixgr.truth.CoupledTruthRuntime.armSharedPUCCHFeedbackRuntime(state);
    if dl && numel(state.TestMACIssued)<2
        before=sixgr.truth.ulSchedulingQueueBits(state);
        [state,grants,planning]=sixgr.truth.planFutureULGrants(state,cfg,{cfg},pending,1,horizon);
        state.TestMACPlanning{end+1}=struct('Slot',slot,'ReceivedBudgetBits',before,'Planning',planning);
        if ~isempty(grants)
            [~,grants]=sixgr.truth.resolveJointPDCCHAdmission(state,cfg,{cfg},repmat(struct(),0,1),grants);
            [state,qualified,queued]=sixgr.truth.PDCCHControlRuntime.queueShared(state,{cfg},grants,'UL',cfg.channel.snr_dB,@logLine);
            assert(isempty(qualified),'Original queued control is not decoded authority.');
            for k=1:numel(queued), state.TestMACIssued{end+1}=queued(k); end
        end
    end
    state=owner.advanceSlot(state,sixgr.phy.grid.applyRuntimeCarrierTimeline(cfg,slot),@events);
    [state,state.TestMACDL,state.TestMACUL,state.TestMACDC,state.TestMACUC,state.TestMACDS,state.TestMACUS]= ...
        sixgr.truth.SharedDataCompletionRuntime.drain(state,state.TestMACDL,state.TestMACUL, ...
        state.TestMACDC,state.TestMACUC,state.TestMACDS,state.TestMACUS);
    srCount=height(sixgr.util.structGet(state,'SharedGNBSRReceptionTable',table()));
    macCount=numel(sixgr.util.structGet(state,'SharedReceivedMACLedger',{}));
    dci=sixgr.util.structGet(state.ControlTrials,'PDCCH',table()); dciCount=0;
    if ~isempty(dci)&&ismember('CRCPass',dci.Properties.VariableNames)
        dciCount=sum(dci.CRCPass==1);
    end
    fprintf('MAC_CHAIN_SLOT=%d/%d SR_RX=%d DCI_QUEUED=%d DCI_CRC_PASS=%d MAC_RX=%d APP_TB_RX=%d SRS_LAST=%g\n', ...
        slot,horizon,srCount,numel(state.TestMACIssued),dciCount,macCount, ...
        receivedApplicationTBCount(state),state.LastSRSSlotByUE(1));
    if receivedApplicationTBCount(state)>=2, break; end
end
sixgr.util.csvWriteTable(fullfile(folder,'mac_chain_ul_trials.csv'),state.TestMACUL,'PreserveSchema',true);
sixgr.util.csvWriteTable(fullfile(folder,'mac_chain_srs_trials.csv'),state.ControlTrials.SRS,'PreserveSchema',true);
sixgr.util.csvWriteTable(fullfile(folder,'mac_chain_pdcch_trials.csv'),state.ControlTrials.PDCCH,'PreserveSchema',true);
sixgr.util.csvWriteTable(fullfile(folder,'mac_chain_received_sr.csv'), ...
    sixgr.util.structGet(state,'SharedGNBSRReceptionTable',table()),'PreserveSchema',true);
sixgr.util.matSave(fullfile(folder,'mac_chain_receipts.mat'),struct('Issued',{state.TestMACIssued}, ...
    'Planning',{state.TestMACPlanning},'ReceivedMAC',{sixgr.util.structGet(state,'SharedReceivedMACLedger',{})}, ...
    'ReceivedPHRReports',{state.SharedGNBPHRStates{1}.Reports}, ...
    'ReceivedSR',sixgr.util.structGet(state,'SharedGNBSRReceptionTable',table()), ...
    'Scope',"declared_common_connected_DRB_TAG_actual_shared_SRS_SR_DCI_PUSCH_no_full_scenario"));
assert(height(state.TestMACUL)>=2&&all(state.TestMACUL.Crash==0)&&all(state.TestMACUL.CRCPass==1), ...
    'test:OriginalMACPhysicalOutcome','Retain original RF/CRC results; received MAC qualification requires both actual decodes.');
assert(receivedApplicationTBCount(state)>=2, ...
    'test:MACApplicationPopulation','STATUS-only UL transport cannot replace either original application-bearing TB.');
sr=state.SharedGNBSRReceptionTable;
assert(any(sr.PositiveSRDetected & sr.ReceiverUsable & ~sr.DTXFlag));
ph=state.SharedGNBPHRStates{1}; bs=state.SharedGNBBufferStates{1};
assert(~isempty(ph.Reports)&&~isempty(bs.BSR)&&numel(bs.Debits)>=2);
first=ph.Reports{1};
assert(first.AvailableSample>=first.ObservationEndSampleExclusive&&first.PHType=="Type1_PCell");
later=cellfun(@(x)x.ReceivedBudgetBits>8*cfg.phy.mac.uplinkControl.SRProbeBytes,state.TestMACPlanning);
assert(any(later),'test:ReceivedBSRLaterGrant','Actual decoded BSR must reach a later normal scheduler decision.');
phrUse=assertOriginalReceivedPHRAllocation(state,false);
sixgr.util.jsonWrite(fullfile(folder,'original_received_phr_allocation_use.json'),phrUse);
% EffectiveCapRows can honestly be zero for a nonbinding physical PHR. This
% test then proves actual receipt use, not a resource reduction/power guarantee.
% A separately labelled reducer negative consumes the original decoded bytes,
% but a false CRC must not update either fresh receiver-owned state.
record=state.SharedReceivedMACLedger{1}; record.CRCPass=false;
freshPH=sixgr.l2.mac.ReceivedPHRState(record.Scope);
freshBS=sixgr.l2.mac.ReceivedULBufferState(record.Scope);
[a,~]=freshPH.previewAdmission([],record); [b,~]=freshBS.previewAdmission([],record);
freshPH.commitAdmission(a); freshBS.commitAdmission(b);
assert(isempty(freshPH.Reports)&&isempty(freshBS.BSR)&&isempty(freshBS.Debits));
state.TestMACReceivedChainCompleted=true;

    function out=events(in,items)
        out=sixgr.truth.completeSharedReceiverBatch(in,items,@one);
    end
    function out=one(out,item)
        switch string(item.Kind)
            case {"PBCH","SSBOccasion"}
                out=receiveN40MACSSBClock(out,item);
            case "BindSRSPower"
                out=sixgr.truth.bindSharedSRSPower(out,item);
            case "SRS"
                out=sixgr.truth.SharedSRSRuntime.complete(out,item,@logLine);
            case "PreparePUCCH"
                out=sixgr.truth.CoupledTruthRuntime.prepareSharedPUCCHFeedbackRuntime(out,item);
            case "PUCCHTX"
                out=sixgr.truth.commitSharedPUCCHTransmission(out,item);
            case "PUCCH"
                out=sixgr.truth.CoupledTruthRuntime.completeSharedPUCCHFeedbackRuntime(out,item);
            case "PUCCHReceiveOnly"
                out=sixgr.truth.CoupledTruthRuntime.completeSharedPUCCHReceiveOnlyRuntime(out,item);
            case "PUCCHNotSelected"
                out=sixgr.truth.completeUnselectedPUCCHObservation(out,item);
            case "PDCCH"
                out=sixgr.truth.PDCCHControlRuntime.completeShared(out,item,@logLine);
            case "PrepareULData"
                out=sixgr.truth.prepareSharedScheduledULData(out,item);
            case "DataTX"
                out=sixgr.truth.commitSharedDataTransmission(out,item);
                out=sixgr.truth.flushDeferredSharedDataPreparations(out,item.UE,item.Context.Prepared.Direction);
            case "PUSCH"
                out=sixgr.truth.SharedDataCompletionRuntime.complete(out,item,@logLine);
            case "PUSCHReceiveOnly"
                out=sixgr.truth.completeSharedPUSCHAfterRejectedControl(out,item.Context.ObservationID);
            otherwise
                error('test:MACUnexpectedEvent','Unsupported original event %s; do not silently skip it.',item.Kind);
        end
    end
end
function logLine(level,fmt,varargin)
fprintf('[%s] %s\n',string(level),sprintf(fmt,varargin{:}));
end
function count=receivedApplicationTBCount(state)
records=sixgr.util.structGet(state,'SharedReceivedMACLedger',{}); ids=strings(0,1);
for k=1:numel(records)
    r=records{k}; if ~r.CRCPass, continue; end
    b=state.ProtocolBridge.originalTransportApplicationBinding(r.LogicalTBID);
    if ~isequal(sixgr.util.structGet(b,'ControlOnly',false),true)&&b.ApplicationPayloadBytes>0
        ids(end+1,1)=string(r.LogicalTBID); %#ok<AGROW>
    end
end
count=numel(unique(ids));
end
