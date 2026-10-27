function [state,evidence]=testSharedClockRLCReverseSTATUS(state,cfg,horizon,folder)
% Input is the same live original received-reference prefix; no clock reset.
% One complete logical TB has its receive callback deliberately withheld;
% all physical samples still execute. No fake CRC/NACK/STATUS is supplied.
% Current configured common/DRB/TAG boundaries retain their original labels.
assert(state.ProtocolWaveformEnabled&&cfg.protocol.rlc.arq_enabled);
assert(isfield(state,'TestReceivedDLClock') && state.TestContinuationCompleted && ...
    state.TestSRSContinuationCompleted && ~state.TestContinuationRejected && ~state.TestSRSContinuationRejected);
hooks=state.TestN40Hooks;
assert(horizon<=cfg.run.totalSlots&&horizon>state.CurrentSlot);
assert(~exist(folder,'dir'));mkdir(folder);
owner=state.SharedWaveformStream;
state.TestRLCMissedTB="";state.TestRLCMissedPacket="";
state.TestRLCMisses=cell(0,1);state.TestRLCIssuedDL=cell(0,1);state.TestRLCIssuedUL=cell(0,1);
state.TestRLCDL=table();state.TestRLCUL=table();state.TestRLCDC=table();state.TestRLCUC=table();
state.TestRLCDS={struct()};state.TestRLCUS={struct()};
for slot=state.CurrentSlot+1:horizon
    [isDL,~]=sixgr.truth.CoupledTruthRuntime.resolveSlotPartition(cfg,slot);
    direction="UL";if isDL,direction="DL";end
    [state,pending,blocked]=sixgr.truth.CoupledTruthRuntime.startSlotWithQueuedUL( ...
        state,cfg,direction,1,1,slot,horizon,cfg.channel.snr_dB,state.SharedPendingULGrants, ...
        sixgr.truth.isPUSCHUCIAvailable(cfg));
    assert(isempty(blocked),'test:RLCSharedCollision','Retain real control/resource conflicts.');
    state.SharedPendingULGrants=pending;
    state=sixgr.truth.CoupledTruthRuntime.enqueueTrafficForFrameRuntime(state,slot);
    state=hooks.DeliverReferences(state);
    state=sixgr.truth.SharedSRSRuntime.deliver(state);
    state=sixgr.truth.CoupledTruthRuntime.refreshControlState(state);
    [state,pending,~]=sixgr.truth.SharedSRSRuntime.prepare(state,cfg,1,cfg.channel.snr_dB,pending,@logLine);
    state.SharedPendingULGrants=pending;
    if isDL
        [active,state]=sixgr.truth.CoupledTruthRuntime.applyUserContext(cfg,state,1,'DL');
        active=sixgr.phy.grid.applyRuntimeCarrierTimeline(active,slot);
        [state,~,~]=sixgr.truth.queueSharedPeriodicCSIRS(state,active,1,slot,state.CurrentFrame, ...
            sixgr.truth.CoupledRadioIdentity.dataRNTI(active,1,'DL'),state.CurrentServingIdx(1),cfg.channel.snr_dB);
        window=sixgr.truth.resolveTRSObservationWindow(cfg,slot);
        if window.ObservationStarts && all(window.AbsoluteSlotNumbers<cfg.run.totalSlots)
            prepared=sixgr.link.prepareTRSTransmission(active,cfg.channel.snr_dB,'RuntimeSlot',slot);
            owner.queueDownlink('TRS',1,prepared,struct('Config',active,'Slot',slot, ...
                'Frame',state.CurrentFrame,'ServingCell',state.CurrentServingIdx(1)));
        end
    end
    state=sixgr.truth.CoupledTruthRuntime.armSharedPUCCHFeedbackRuntime(state);
    if isDL
        [state,dl,info]=sixgr.truth.CoupledTruthRuntime.scheduleDirection(state,cfg,'DL'); %#ok<ASGLU>
        [state,ul,planning]=sixgr.truth.planFutureULGrants(state,cfg,{cfg},pending,1,horizon); %#ok<ASGLU>
        [state,dl,ul]=sixgr.truth.planJointHARQPUSCHTiming(state,{cfg},dl,ul);
        [dl,ul]=sixgr.truth.resolveJointPDCCHAdmission(state,cfg,{cfg},dl,ul);
        [state,qualified,qd]=sixgr.truth.PDCCHControlRuntime.queueShared(state,{cfg},dl,'DL',cfg.channel.snr_dB,@logLine);
        assert(isempty(qualified));
        [state,qualified,qu]=sixgr.truth.PDCCHControlRuntime.queueShared(state,{cfg},ul,'UL',cfg.channel.snr_dB,@logLine);
        assert(isempty(qualified));
        for k=1:numel(qd),state.TestRLCIssuedDL{end+1,1}=qd(k);end
        for k=1:numel(qu),state.TestRLCIssuedUL{end+1,1}=qu(k);end
        if ~isempty(qd)
            state=sixgr.truth.queueSharedDataPlans(state,cfg,state.MultiUser,{cfg},qd, ...
                'DL',cfg.channel.snr_dB,qd(1).Frame,state.TestRLCDS);
        end
    end
    state=owner.advanceSlot(state,sixgr.phy.grid.applyRuntimeCarrierTimeline(cfg,slot),@batch);
    [state,state.TestRLCDL,state.TestRLCUL,state.TestRLCDC,state.TestRLCUC,state.TestRLCDS,state.TestRLCUS]= ...
        sixgr.truth.SharedDataCompletionRuntime.drain(state,state.TestRLCDL,state.TestRLCUL, ...
        state.TestRLCDC,state.TestRLCUC,state.TestRLCDS,state.TestRLCUS);
    state=sixgr.truth.refreshApplicationPacketDeliveries(state);
    fprintf('SHARED_RLC_SLOT=%d MISSED_ATTEMPTS=%d STATUS_PENDING=%d RETX_BYTES=%d\n', ...
        slot,numel(state.TestRLCMisses),state.ProtocolBridge.pendingReverseStatusBytes(1,'UL'), ...
        state.ProtocolBridge.pendingTransmitBytes(1,'DL').AMRetransmissionBytes);
    P=state.PacketDeliveryLedgerTable;
    p=string(P.ApplicationPacketId)==state.TestRLCMissedPacket&string(P.Direction)=="DL";
    if any(p)&&all(P.DeliverySuccess(p)),break;end
end
% Persist actual failures/populations before requiring successful integration.
sixgr.util.matSave(fullfile(folder,'shared_reverse_status_receipts.mat'),struct( ...
    'MissedReceiveEvents',{state.TestRLCMisses},'IssuedDL',{state.TestRLCIssuedDL}, ...
    'IssuedUL',{state.TestRLCIssuedUL},'Control',sixgr.util.structGet(state,'MACControlTransportLedgerTable',table()), ...
    'Recovery',sixgr.util.structGet(state,'RLCRecoveryTransportLedgerTable',table()), ...
    'Applications',state.PacketDeliveryLedgerTable));
sixgr.util.csvWriteTable(fullfile(folder,'actual_dl_trials.csv'),state.TestRLCDL,'PreserveSchema',true);
sixgr.util.csvWriteTable(fullfile(folder,'actual_ul_trials.csv'),state.TestRLCUL,'PreserveSchema',true);
C=state.MACControlTransportLedgerTable;
statusRX=C.TransportKind=="RLC_STATUS"&C.Direction=="UL"&C.Stage=="RX"&C.CRCPass==1;
assert(any(statusRX),'test:NoPhysicalReverseSTATUS','Require actual CRC-decoded PUSCH STATUS, not a codec-boundary substitute.');
assert(all(C.ApplicationCreditedBits(C.TransportKind=="RLC_STATUS")==0));
R=state.RLCRecoveryTransportLedgerTable;
assert(~isempty(R)&&any(R.DeliverySuccess),'test:NoPhysicalRLCRecovery','Original resegmented data must decode after actual reverse STATUS.');
P=state.PacketDeliveryLedgerTable;
p=string(P.ApplicationPacketId)==state.TestRLCMissedPacket&string(P.Direction)=="DL";
assert(nnz(p)==1&&P.DeliverySuccess(p)&&P.CompletedApplicationBits(p)==P.OfferedBits(p)&&P.BitConservationErrorBits(p)==0);
assert(P.DecodedApplicationPayloadSHA256(p)==P.OriginalApplicationPayloadSHA256(p));
receipt=jsondecode(P.RLCApplicationRecoveryEvidenceJSON(p));
assert(~any(string(receipt.ContributorTransportBlockIDs)==state.TestRLCMissedTB));
again=sixgr.truth.refreshApplicationPacketDeliveries(state);assert(isequaln(again,state));
evidence=struct('Scope',"shared_original_RX_STATUS_and_resegmented_application_with_declared_missing_receive_event", ...
    'OriginalMissingLogicalTB',state.TestRLCMissedTB,'ActualReverseSTATUSCRCCount',nnz(statusRX), ...
    'ApplicationExactlyOnce',true,'FullAccessQualified',false);
    function out=batch(in,items)
        out=sixgr.truth.completeSharedReceiverBatch(in,items,@one);
    end
    function out=one(out,item)
        switch string(item.Kind)
            case {"PBCH","SSBOccasion","TRS"},out=hooks.CompleteEvents(out,item);
            case "CSIRS",[out,~,~,~]=sixgr.truth.completeSharedCSIRSReception(out,item);
            case "BindSRSPower",out=sixgr.truth.bindSharedSRSPower(out,item);
            case "SRS",out=sixgr.truth.SharedSRSRuntime.complete(out,item,@logLine);
            case "PreparePUCCH",out=sixgr.truth.CoupledTruthRuntime.prepareSharedPUCCHFeedbackRuntime(out,item);
            case "PUCCHTX",out=sixgr.truth.commitSharedPUCCHTransmission(out,item);
            case "PUCCH",out=sixgr.truth.CoupledTruthRuntime.completeSharedPUCCHFeedbackRuntime(out,item);
            case "PUCCHReceiveOnly",out=sixgr.truth.CoupledTruthRuntime.completeSharedPUCCHReceiveOnlyRuntime(out,item);
            case "PUCCHNotSelected",out=sixgr.truth.completeUnselectedPUCCHObservation(out,item);
            case "PDCCH",out=sixgr.truth.PDCCHControlRuntime.completeShared(out,item,@logLine);
            case "PrepareULData",out=sixgr.truth.prepareSharedScheduledULData(out,item);
            case "DataTX"
                out=sixgr.truth.commitSharedDataTransmission(out,item);
                out=sixgr.truth.flushDeferredSharedDataPreparations(out,item.UE,item.Context.Prepared.Direction);
            case {"PDSCH","PUSCH"}
                if item.Kind=="PDSCH"
                    g=item.Context.Prepared.RequestBinding.Grant;
                    b=out.ProtocolBridge.originalTransportApplicationBinding(g.TransportBlockId);
                    assert(islogical(b.ControlOnly)&&isscalar(b.ControlOnly), ...
                        'test:RLCBindingType','Private binding must expose its explicit control/data kind.');
                    if out.TestRLCMissedTB==""&&~b.ControlOnly&&~b.IsRLCRetransmission
                        out.TestRLCMissedTB=string(g.TransportBlockId);out.TestRLCMissedPacket=string(b.PacketID);
                    end
                    if string(g.TransportBlockId)==out.TestRLCMissedTB
                        % Receiver event suppression is explicit. Do not call
                        % PHY/MAC RX or write a made-up failed CRC/NACK.
                        ix=numel(out.TestRLCMisses)+1;
                        path=fullfile(folder,sprintf('original_withheld_receiver_%03d.mat',ix));
                        save(path,'item','-v7.3');
                        out.TestRLCMisses{end+1,1}=struct('LogicalTBID',string(g.TransportBlockId), ...
                            'TransmissionID',item.Context.TransmissionIdentity.TransmissionID, ...
                            'ObservationID',string(item.ID),'OriginalCapturePath',string(path), ...
                            'ReceiverInvoked',false,'CRCAvailable',false,'Boundary',"declared_missing_receiver_event");
                        return;
                    end
                end
                out=sixgr.truth.SharedDataCompletionRuntime.complete(out,item,@logLine);
            case "PUSCHReceiveOnly",out=sixgr.truth.completeSharedPUSCHAfterRejectedControl(out,item.Context.ObservationID);
            otherwise,error('test:RLCUnhandledOriginalEvent','Unhandled original event %s.',item.Kind);
        end
    end
end
function logLine(level,fmt,varargin)
fprintf('[%s] %s\n',string(level),sprintf(fmt,varargin{:}));
end
