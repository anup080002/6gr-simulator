classdef ReceivedDLHARQState
    % UE-owned connected DL soft state; value semantics preserve failed calls.
    % HARQ acknowledgement decisions are not evidence of a transmitted PUCCH.
    properties (SetAccess=private)
        ContextDigest
        UEId
        Processes
    end
    methods
        function obj=ReceivedDLHARQState(installed,ueId)
            validateattributes(ueId,{'numeric'},{'scalar','integer','positive','finite'});
            c=sixgr.phy.pdcch.DCIContextFactory.fromRuntimeConfig(installed,'1_1');
            assert(isequal(installed.phy.harq.enable,true), ...
                'sixgr:link:ReceivedDLHARQDisabled','The configured DL HARQ entity must be enabled.');
            assert(c.Data.RNTIType=="C-RNTI",'sixgr:link:ReceivedDLHARQProcedure', ...
                'This entity owns connected C-RNTI DL HARQ, not random access, SPS or broadcast.');
            obj.ContextDigest=c.Digest; obj.UEId=double(ueId);
            obj.Processes=cell(c.Data.HARQProcessCount,1);
        end

        function tf=requiresDecode(obj,installed,a)
            % A decoded control assignment, not a transmitter grant, selects
            % the MAC disposition. This query never consumes a HARQ attempt.
            [prior,fresh]=obj.validateReception(installed,a);
            tf=fresh || ~prior.Decoded;
        end

        function [decision,next,protocol]=acknowledgeRetained(obj,installed,a)
            % TS 38.321 5.3.2.2: acknowledge a previously decoded C-RNTI TB
            % without another PHY decode or duplicate upper-layer delivery.
            % No IQ, current CRC, current SINR, timing estimate or gNB grant
            % is an input to this protocol-only transition.
            [prior,fresh]=obj.validateReception(installed,a);
            assert(~fresh && prior.Decoded, ...
                'sixgr:link:ReceivedDLRetainedACKUnavailable', ...
                'Repeated ACK requires this UE to have decoded the same process and NDI.');
            prior.History.allocation(installed,a,obj.UEId);
            decision=struct('IsRetransmission',true,'DecodeAttempted',false, ...
                'AcknowledgedFromPriorDecode',true,'ACK',true,'DeliverTransportBlock',false, ...
                'Source',"ue_received_control_and_actual_dl_decoder", ...
                'FeedbackTransmissionQualified',false,'ReceivedAssignmentDigest',a.AssignmentDigest, ...
                'Attempt',prior.Attempts+1);
            protocol=struct('ContractVersion',"received_dl_retained_ack/v1", ...
                'UEId',obj.UEId,'RNTI',a.RNTI,'HARQProcess',a.HARQProcess,'NDI',a.NDI, ...
                'ControlAbsoluteSlot',a.ControlAbsoluteSlot,'DataAbsoluteSlot',a.DataAbsoluteSlot, ...
                'ReceivedAssignmentDigest',a.AssignmentDigest, ...
                'PriorAcknowledgedAssignmentDigest',prior.LastAssignmentDigest, ...
                'PriorAcknowledgedDataAbsoluteSlot',prior.LastDataAbsoluteSlot, ...
                'InitialAssignmentDigest',prior.History.InitialAssignment.AssignmentDigest, ...
                'RetainedTBSBits',prior.History.TBSBits,'ACK',true, ...
                'DecodeAttempted',false,'DeliverTransportBlock',false, ...
                'FeedbackTransmissionQualified',false, ...
                'Source',"received_dci_and_ue_retained_decoded_tb");
            prior.Attempts=decision.Attempt;
            prior.LastControlAbsoluteSlot=a.ControlAbsoluteSlot;
            prior.LastDataAbsoluteSlot=a.DataAbsoluteSlot;
            prior.LastAssignmentDigest=a.AssignmentDigest;
            next=obj; next.Processes{a.HARQProcess+1}=prior;
        end

        function [rx,decision,next,protocol]=receive(obj,installed,a,waveform,varargin)
            [prior,fresh]=obj.validateReception(installed,a);
            protocol=struct();
            % Parse even for repeated ACK so legacy/oracle overrides cannot
            % enter unnoticed just because the current TB needs no decoder.
            parser=inputParser;
            parser.addParameter('TimingSearchWindowSamples',[]);
            parser.addParameter('ReceiverTrackingState',[]);
            parser.addParameter('PhysicalMeasurementWaveform',[]);
            parser.addParameter('PhysicalMeasurementReferencePlane',"");
            parser.addParameter('PhysicalMeasurementSource',"");
            parser.addParameter('ReceivedExecutionEvidence',struct());
            parser.parse(varargin{:}); opts=parser.Results;
            if ~fresh && prior.Decoded
                rx=[];
                [decision,next,protocol]=obj.acknowledgeRetained(installed,a);
                return;
            end
            assert(isnumeric(waveform) && ismatrix(waveform) && ~isempty(waveform), ...
                'sixgr:link:ReceivedDLWaveformRequired', ...
                'New or undecoded transport blocks require actual received IQ.');
            index=a.HARQProcess+1;
            tracking={}; names=fieldnames(opts);
            for k=1:numel(names), tracking=[tracking {names{k},opts.(names{k})}]; end %#ok<AGROW>
            decision=struct('IsRetransmission',~fresh,'DecodeAttempted',false, ...
                'AcknowledgedFromPriorDecode',false,'ACK',false,'DeliverTransportBlock',false, ...
                'Source',"ue_received_control_and_actual_dl_decoder", ...
                'FeedbackTransmissionQualified',false,'ReceivedAssignmentDigest',a.AssignmentDigest);
            if fresh
                history=sixgr.pdsch.ReceivedDLHARQCodingHistory(installed,a,obj.UEId);
                bundle=sixgr.pdsch.PDSCHCalibrationFacadeAdapter.materializeReceivedNewTB( ...
                    installed,a,obj.UEId,size(waveform,2));
                entry=struct('NDI',a.NDI,'History',history,'Attempts',0,'Decoded',false, ...
                    'SoftBuffer',[],'PriorPlan',[], ...
                    'HARQKey',"UE-DL-"+a.AssignmentDigest);
            else
                entry=prior;
                bundle=sixgr.pdsch.PDSCHCalibrationFacadeAdapter.materializeReceived( ...
                    installed,a,obj.UEId,size(waveform,2),prior.History);
            end
            rx=sixgr.phy.dl.PDSCH_Rx(waveform,installed, ...
                'ExecutionProfile','connected_strict','Assignment',bundle.Assignment, ...
                'ResourcePlan',bundle.ResourcePlan,'Carrier',bundle.Carrier, ...
                'ReferenceSignalConfig',bundle.ReferenceConfig,'ReceiverConfig',bundle.ReceiverConfig, ...
                'CodingPlan',bundle.CodingPlans,'IntegrationContext',bundle.IntegrationContext, ...
                'ReceiverHARQState',obj,'ReceivedAssignment',a,tracking{:});
            if ~fresh
                assert(~rx.Decode.HARQCombineInfo.ResetPrior && rx.Decode.HARQCombineInfo.Applied, ...
                    'sixgr:link:ReceivedDLHARQCombineRejected', ...
                    'A retained soft buffer must combine in the original mother-code domain, not silently reset.');
            end
            entry.SoftBuffer=rx.Decode.SoftBuffer;
            entry.PriorPlan=bundle.CodingPlans{1};
            entry.Decoded=logical(rx.CRCPass);
            decision.DecodeAttempted=true;
            decision.DeliverTransportBlock=entry.Decoded;
            decision.ACK=entry.Decoded;
            entry.Attempts=entry.Attempts+1; decision.Attempt=entry.Attempts;
            entry.LastControlAbsoluteSlot=a.ControlAbsoluteSlot;
            entry.LastDataAbsoluteSlot=a.DataAbsoluteSlot;
            entry.LastAssignmentDigest=a.AssignmentDigest;
            next=obj; next.Processes{index}=entry;
        end

        function [prior,fresh]=validateReception(obj,installed,a)
            c=sixgr.phy.pdcch.validateConnectedAssignment(installed,a);
            assert(a.Direction=="DL" && obj.ContextDigest==c.Digest && installed.phy.harq.enable, ...
                'sixgr:link:ReceivedDLHARQContextMismatch','Received control must belong to this DL entity.');
            index=a.HARQProcess+1;
            validateattributes(index,{'double'},{'scalar','integer','positive','<=',numel(obj.Processes)});
            prior=obj.Processes{index}; fresh=isempty(prior) || prior.NDI~=a.NDI;
            if ~isempty(prior)
                assert(a.ControlAbsoluteSlot>prior.LastControlAbsoluteSlot && ...
                    a.DataAbsoluteSlot>prior.LastDataAbsoluteSlot, ...
                    'sixgr:link:ReceivedDLHARQNoncausalAssignment', ...
                    'A process cannot accept replayed or out-of-order control/data assignments.');
            end
        end

        function [soft,plan,key]=priorFor(obj,assignment)
            % Read-only binding for the strict PHY boundary. Raw legacy
            % soft-buffer overrides remain forbidden by that boundary.
            assignment.validateForExecution(); d=assignment.toStruct();
            assert(assignment.Profile=="connected_strict" && ...
                d.ControlAuthority=="receiver_crc_valid_decode" && ...
                d.UEId==obj.UEId && d.ReceivedContextDigest==obj.ContextDigest, ...
                'sixgr:link:ReceivedDLHARQContextMismatch','Receiver assignment does not belong to this UE entity.');
            index=d.HARQProcessId+1;
            validateattributes(index,{'double'},{'scalar','integer','positive','<=',numel(obj.Processes)});
            prior=obj.Processes{index};
            fresh=isempty(prior) || prior.NDI~=d.NDIPerCodeword;
            soft=[]; plan=[]; key="UE-DL-"+d.ReceivedAssignmentDigest;
            if ~isempty(prior)
                assert(d.PDCCHAbsoluteSlot>prior.LastControlAbsoluteSlot && ...
                    d.PDSCHAbsoluteSlot>prior.LastDataAbsoluteSlot, ...
                    'sixgr:link:ReceivedDLHARQNoncausalAssignment','Receiver assignment is not newer than retained state.');
            end
            if fresh
                assert(~isfield(d,'ReceivedHARQCodingHistory'), ...
                    'sixgr:pdsch:ReceivedDLHARQIdentityMismatch','A new NDI must not attach prior coding history.');
            else
                assert(~prior.Decoded && isfield(d,'ReceivedHARQCodingHistory') && ...
                    d.ReceivedHARQCodingHistory.InitialAssignment.AssignmentDigest== ...
                    prior.History.InitialAssignment.AssignmentDigest, ...
                    'sixgr:pdsch:ReceivedDLHARQIdentityMismatch', ...
                    'Retained PHY soft state must match the assignment history and an undecoded TB.');
                soft=prior.SoftBuffer; plan=prior.PriorPlan; key=prior.HARQKey;
            end
        end
    end
end
