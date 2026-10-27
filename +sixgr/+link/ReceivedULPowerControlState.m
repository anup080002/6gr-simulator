classdef ReceivedULPowerControlState
    % UE-owned connected PUSCH adjustment state, TS 38.213 7.1.1.
    % Value semantics: only successful waveform preparation/queueing commits
    % the next owner. Receiver CRC success is NOT a power-state prerequisite.
    % Scope: one scheduled PUSCH per occasion, one configured loop (l=0),
    % received DCI 0_0/0_1/0_2. Group TPC and configured grants are separate.
    properties (SetAccess=private)
        RNTI (1,1) double
        Entries cell = {}
        % Queue admission can precede emission. Keep the effective sample
        % clock so SRS never consumes a future PUSCH adjustment.
        History cell = {}
    end
    methods
        function obj=ReceivedULPowerControlState(installed)
            c=sixgr.phy.pdcch.DCIContextFactory.fromRuntimeConfig(installed,'0_1');
            assert(string(c.Data.RNTIType)=="C-RNTI", ...
                'sixgr:power:ConnectedCRNTIRequired','Connected power state requires C-RNTI.');
            obj.RNTI=c.Data.RNTIValue;
        end

        function [wave,pc,cfgOut,state,next]=resolvePUSCH(obj,cfg,a,tx,observation)
            % Existing post-waveform interface preserves nonzero waveform guard.
            assert(isnumeric(tx.Waveform)&&~isempty(tx.Waveform)&&all(isfinite(tx.Waveform(:)))&& ...
                mean(sum(abs(double(tx.Waveform)).^2,2))>0, ...
                'sixgr:pusch:InvalidPowerControlWaveform','Original actual waveform required.');
            allocation=struct('Carrier',tx.Carrier,'PUSCH',tx.PUSCH,'NumSamples',size(tx.Waveform,1));
            [pc,cfgOut,state,next]=obj.previewPUSCHAllocation(cfg,a,allocation,observation);
            wave=tx.Waveform;
        end

        function [pc,cfgOut,state,next]=previewPUSCHAllocation(obj,cfg,a,tx,observation)
            validateattributes(tx.NumSamples,{'numeric'},{'scalar','finite','integer','positive'});
            c=sixgr.phy.pdcch.validateConnectedAssignment(cfg,a);
            assert(a.Direction=="UL" && a.RNTI==obj.RNTI, ...
                'sixgr:power:WrongEndpoint','A UE cannot consume another endpoint or DL command.');
            assert(c.Data.ControlServingCell==c.Data.ScheduledServingCell && ...
                c.Data.ControlCarrier==c.Data.ScheduledCarrier, ...
                'sixgr:power:UnsupportedCrossCarrierTPC', ...
                'This owner requires same-carrier control; cross-carrier TPC needs both numerology clocks.');
            assert(isstruct(observation) && all(isfield(observation, ...
                {'AssignmentDigest','AvailableAtSample','SampleRateHz'})) && ...
                string(observation.AssignmentDigest)==string(a.AssignmentDigest), ...
                'sixgr:power:MissingReceivedTPCObservation', ...
                'Retain the actual decoded assignment and receiver availability clock.');
            fs=double(observation.SampleRateHz); available=double(observation.AvailableAtSample);
            validateattributes(fs,{'double'},{'scalar','finite','positive'});
            validateattributes(available,{'double'},{'scalar','finite','integer','nonnegative'});
            assert(double(tx.Carrier.SubcarrierSpacing)==double(cfg.phy.carrier.SubcarrierSpacing), ...
                'sixgr:power:NumerologyMismatch','Power timing must use the executed carrier.');
            slotStart=sixgr.phy.frame.slotStartSample(tx.Carrier,a.DataAbsoluteSlot,fs);
            timing=sixgr.link.resolveConnectedULTransmissionTiming(cfg, ...
                slotStart/fs,fs,tx.NumSamples);
            slotStart=timing.TransmitStartSample;
            ofdm=nrOFDMInfo(tx.Carrier,'SampleRate',fs);
            offset=mod(double(tx.Carrier.NSlot),double(tx.Carrier.SlotsPerSubframe))* ...
                double(tx.Carrier.SymbolsPerSlot);
            firstSample=slotStart+sum(double(ofdm.SymbolLengths(offset+(1:a.SymbolAllocation(1)))));
            mu=log2(double(tx.Carrier.SubcarrierSpacing)/15);
            policy=sixgr.phy.frame.TimingPolicyCatalog.capability1(mu);
            % 38.213 7.1.1 uses Tproc,2 with d2,1=0 for TPC application.
            ticks=sixgr.phy.frame.TimingPolicyCatalog.processingSymbolTicks(policy.PUSCHN2Symbols,mu);
            requiredSamples=ceil(double(ticks)*fs/(480e3*4096));
            assert(firstSample-available>=requiredSamples, ...
                'sixgr:power:TPCNotYetApplicable', ...
                'Received TPC must meet its preparation interval before the advanced UL symbol.');
            assert(tx.PUSCH.RNTI==a.RNTI && ...
                isequal(double(tx.PUSCH.PRBSet(:).'),a.PRBStart+(0:a.NumPRB-1)) && ...
                isequal(double(tx.PUSCH.SymbolAllocation),double(a.SymbolAllocation)), ...
                'sixgr:power:TransmissionMismatch','Power must bind to the decoded actual PUSCH allocation.');
            key=struct('Cell',c.Data.ScheduledServingCell,'Carrier',c.Data.ScheduledCarrier, ...
                'BWP',c.Data.ScheduledBWP,'Loop',0);
            p=cfg.phy.pusch.powerControl;
            assert(logical(p.enabled) && isfield(p,'p0PUSCH_dBm') && ...
                isfield(p,'p0UE_dB') && isfield(p,'alpha'), ...
                'sixgr:power:MissingInstalledPowerConfiguration', ...
                'The connected owner requires explicit installed P0 and alpha.');
            params=struct('P0',double(p.p0PUSCH_dBm),'P0UE',double(p.p0UE_dB), ...
                'Alpha',double(p.alpha),'Mode',string(p.adjustmentMode));
            hit=find(cellfun(@(e)isequal(e.Key,key),obj.Entries));
            assert(numel(hit)<=1,'sixgr:power:DuplicateContext','Power contexts must be unique.');
            reset="initial_installed_p0_alpha_configuration";
            state=struct('PreviousF_dB',0,'UpdateCount',0,'AtMaximumPower',false,'AtMinimumPower',false);
            if ~isempty(hit)
                prior=obj.Entries{hit};
                assert(a.ControlAbsoluteSlot>prior.LastControlSlot && a.DataAbsoluteSlot>prior.LastDataSlot && ...
                    firstSample>prior.LastAppliedAtSample && available>prior.LastAvailableAtSample && ...
                    a.ConfigurationEpoch>=prior.Epoch, ...
                    'sixgr:power:ReplayedOrNoncausalTPC', ...
                    'Apply each received command once, in control/data order and the current epoch.');
                % An unrelated DCI/beam epoch is not a P0/alpha reset.
                % This bounded owner has no RRC same-value reconfiguration
                % event; a future reconfiguration owner must supply it.
                if isequaln(params,prior.Parameters)
                    state=prior.State; reset="none_retained_previous_transmission";
                else
                    reset="installed_power_parameters_changed";
                end
            end
            grant=struct('PRBSet',tx.PUSCH.PRBSet,'DecodedDCIFields',a.Fields);
            [pc,cfgOut,state]=sixgr.link.resolvePUSCHAllocationPowerContext( ...
                cfg,tx,grant,state);
            pc.StateOwner="received_ue_pusch_power_control";
            pc.StateResetReason=reset;
            pc.ReceivedAssignmentDigest=a.AssignmentDigest;
            pc.TPCAvailableAtSample=available; pc.TPCAppliedAtSample=firstSample;
            pc.TPCMinimumProcessingSamples=requiredSamples;
            pc.StateUpdateCount=state.UpdateCount;
            entry=struct('Key',key,'Parameters',params,'Epoch',a.ConfigurationEpoch, ...
                'State',state,'LastControlSlot',a.ControlAbsoluteSlot, ...
                'LastDataSlot',a.DataAbsoluteSlot,'LastAppliedAtSample',firstSample, ...
                'LastAvailableAtSample',available,'LastAssignmentDigest',a.AssignmentDigest, ...
                'SampleRateHz',fs,'ResetReason',reset);
            next=obj;
            if isempty(hit), next.Entries{end+1}=entry; else, next.Entries{hit}=entry; end
            next.History{end+1}=entry;
        end

        function evidence=adjustmentAt(obj,cfg,sample,fs)
            % Read-only h=f lookup for TS 38.213 V18.8.0 7.3.1.
            % This does not apply a second TPC or let a future grant change
            % an earlier SRS. Sample is on the actual advanced UE TX clock.
            validateattributes(sample,{'double'},{'scalar','finite','integer','nonnegative'});
            validateattributes(fs,{'double'},{'scalar','finite','positive'});
            c=sixgr.phy.pdcch.DCIContextFactory.fromRuntimeConfig(cfg,'0_1');
            assert(c.Data.RNTIValue==obj.RNTI,'sixgr:power:WrongEndpoint', ...
                'SRS must use its own installed UE power state.');
            p=cfg.phy.pusch.powerControl;
            assert(p.enabled && p.closedLoopEnabled, ...
                'sixgr:power:SharedSRSRequiresPUSCH','Shared SRS adjustment requires configured PUSCH power control.');
            key=struct('Cell',c.Data.ScheduledServingCell,'Carrier',c.Data.ScheduledCarrier, ...
                'BWP',c.Data.ScheduledBWP,'Loop',0);
            params=struct('P0',double(p.p0PUSCH_dBm),'P0UE',double(p.p0UE_dB), ...
                'Alpha',double(p.alpha),'Mode',string(p.adjustmentMode));
            evidence=struct('Adjustment_dB',0,'StateOwner',"received_ue_pusch_power_control", ...
                'AdjustmentState',"same_as_pusch",'StateUpdateCount',0, ...
                'StateResetReason',"initial_installed_p0_alpha_configuration", ...
                'ReceivedAssignmentDigest',"",'TPCAvailableAtSample',NaN, ...
                'TPCAppliedAtSample',NaN,'AdjustmentReadAtSample',sample,'SampleRateHz',fs);
            matches=find(cellfun(@(e)isequal(e.Key,key),obj.History));
            assert(isempty(obj.Entries) || ~isempty(obj.History), ...
                'sixgr:power:MissingAdjustmentHistory','An older checkpoint cannot invent missing effective-time history.');
            applicable=[];
            for i=reshape(matches,1,[])
                e=obj.History{i};
                assert(e.SampleRateHz==fs,'sixgr:power:AdjustmentClockMismatch', ...
                    'Power state and SRS must use the same physical sample clock.');
                if e.LastAppliedAtSample>sample, continue; end
                applicable=i;
            end
            if ~isempty(applicable)
                e=obj.History{applicable};
                assert(e.LastAvailableAtSample<=sample, ...
                    'sixgr:power:NoncausalAdjustment','A command must be received before it is applied.');
                assert(isequaln(e.Parameters,params), ...
                    'sixgr:power:SRSReconfigurationTimingRequired', ...
                    'A P0/alpha change needs an explicit installation-time event; do not reset retrospectively.');
                evidence.Adjustment_dB=e.State.PreviousF_dB;
                evidence.StateUpdateCount=e.State.UpdateCount;
                evidence.StateResetReason=e.ResetReason;
                evidence.ReceivedAssignmentDigest=string(e.LastAssignmentDigest);
                evidence.TPCAvailableAtSample=e.LastAvailableAtSample;
                evidence.TPCAppliedAtSample=e.LastAppliedAtSample;
            end
        end
    end
end
