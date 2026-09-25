classdef ReceivedULHARQState
    % UE-owned C-RNTI HARQ buffers. No scheduler grants or RX LLRs are stored.
    % Value semantics make a failed preparation leave the caller unchanged.
    properties (SetAccess=private)
        ContextDigest
        Processes
    end
    methods
        function obj=ReceivedULHARQState(installed)
            c=sixgr.phy.pdcch.DCIContextFactory.fromRuntimeConfig(installed,'0_1');
            assert(string(c.Data.RNTIType)=="C-RNTI", ...
                'sixgr:link:ReceivedULHARQProcedure', ...
                'This entity owns connected C-RNTI HARQ, not Msg3 or configured-grant procedures.');
            obj.ContextDigest=c.Digest;
            obj.Processes=cell(c.Data.HARQProcessCount,1);
        end

        function [tx,info,next]=transmit(obj,installed,a,newBits,uci)
            c=sixgr.phy.pdcch.validateConnectedAssignment(installed,a);
            assert(a.Direction=="UL" && a.ULSCHIndicator==1 && ...
                obj.ContextDigest==c.Digest, ...
                'sixgr:link:ReceivedULHARQContextMismatch', ...
                'HARQ buffers must belong to this installed connected UL context.');
            index=a.HARQProcess+1;
            validateattributes(index,{'double'},{'scalar','integer','positive','<=',numel(obj.Processes)});
            prior=obj.Processes{index};
            fresh=isempty(prior) || prior.NDI~=a.NDI;
            if ~isempty(prior)
                assert(a.ControlAbsoluteSlot>prior.LastControlAbsoluteSlot && ...
                    a.DataAbsoluteSlot>prior.LastDataAbsoluteSlot, ...
                    'sixgr:link:ReceivedULHARQNoncausalAssignment', ...
                    'A process cannot accept replayed or noncausal control/data assignments.');
            end
            if fresh
                [tx,info]=sixgr.link.transmitReceivedPUSCH(installed,a,newBits,uci);
                entry=struct('NDI',a.NDI,'TransportBlockBits',int8(tx.TransportBlock(:)), ...
                    'TBSBits',double(tx.TransportBlockSize), ...
                    'InitialMCS',a.MCS,'InitialTargetCodeRate',a.TargetCodeRate, ...
                    'InitialAssignmentDigest',a.AssignmentDigest,'Attempts',1, ...
                    'BaseGraph',tx.CodingLayout.BaseGraph, ...
                    'CombineSignature',tx.CodingLayout.CombineSignature);
            else
                assert(isempty(newBits),'sixgr:link:ReceivedULHARQPayloadReplacement', ...
                    'An unchanged received NDI reuses the UE buffer; replacement payload is forbidden.');
                if logical(sixgr.util.structGet(a,'RequiresHARQHistory',false))
                    allocation=sixgr.phy.pdcch.connectedDataAllocation(installed,a,prior.InitialTargetCodeRate);
                else
                    allocation=sixgr.phy.pdcch.connectedDataAllocation(installed,a);
                    assert(allocation.NominalTBSBits==prior.TBSBits, ...
                        'sixgr:link:ReceivedULHARQTBSChanged', ...
                        'A defined-MCS retransmission must derive the same TB size as the retained buffer.');
                end
                cfg=allocation.Config;
                if isfield(cfg.phy,'canonicalGrant'), cfg.phy=rmfield(cfg.phy,'canonicalGrant'); end
                if isfield(cfg.phy.pusch,'srsDecision'), cfg.phy.pusch=rmfield(cfg.phy.pusch,'srsDecision'); end
                % Retain original TB coding/segmentation while rate matching
                % uses the newly received RV, modulation, layers and resources.
                args={'TransportBlockBits',prior.TransportBlockBits, ...
                    'TransportBlockSizeOverride',prior.TBSBits, ...
                    'TargetCodeRate',prior.InitialTargetCodeRate, ...
                    'InitialIMCSPerCodeword',prior.InitialMCS};
                % Retain an empty report's current received-DAI identity,
                % not the previous attempt's report or an untyped absence.
                if ~isempty(uci), args=[args {'UCIPayload',uci}]; end
                if isfield(allocation,'ResearchTransport')
                    args=[args {'ResearchTransport',allocation.ResearchTransport}];
                end
                [tx,info]=sixgr.phy.ul.PUSCH_Tx(cfg,args{:});
                assert(tx.TransportBlockSize==prior.TBSBits && ...
                    isequal(tx.TransportBlock,prior.TransportBlockBits) && ...
                    tx.CodingLayout.BaseGraph==prior.BaseGraph && ...
                    string(tx.CodingLayout.CombineSignature)==string(prior.CombineSignature) && ...
                    tx.PrecodeInfo.AuthoritativeDCIDecisionUsed && ...
                    ~tx.PrecodeInfo.AuthoritativeSRSDecisionUsed, ...
                    'sixgr:link:ReceivedULHARQBufferMismatch', ...
                    'Retransmission must preserve the original UE TB and LDPC combining domain.');
                entry=prior;
                entry.Attempts=prior.Attempts+1;
                tx.TransmissionAuthority="received_dci_and_ue_harq_buffer";
                tx.ReceivedDCIAssignmentDigest=a.AssignmentDigest;
                info.TransmissionAuthority=tx.TransmissionAuthority;
                info.ReceivedDCIAssignmentDigest=a.AssignmentDigest;
            end
            entry.LastControlAbsoluteSlot=a.ControlAbsoluteSlot;
            entry.LastDataAbsoluteSlot=a.DataAbsoluteSlot;
            entry.LastAssignmentDigest=a.AssignmentDigest;
            next=obj;
            next.Processes{index}=entry;
            tx.UEHARQIsRetransmission=~fresh;
            tx.UEHARQAttempt=entry.Attempts;
            tx.UEHARQInitialAssignmentDigest=entry.InitialAssignmentDigest;
            info.UEHARQIsRetransmission=~fresh;
            info.UEHARQAttempt=entry.Attempts;
            info.UEHARQInitialAssignmentDigest=entry.InitialAssignmentDigest;
        end
    end
end
