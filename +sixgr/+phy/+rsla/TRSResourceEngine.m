classdef TRSResourceEngine
    %TRSRESOURCEENGINE Selected NZP-CSI-RS tracking resource-set façade.

    methods (Static)
        function plan = planVector(row)
            periodicity = sixgr.phy.rsla.RSLAUtil.number( ...
                row,"PeriodicitySlots",NaN);
            offset = sixgr.phy.rsla.RSLAUtil.number(row,"OffsetSlots",NaN);
            qcl = lower(sixgr.phy.rsla.RSLAUtil.text(row,"QCLType",""));
            resources = sixgr.phy.rsla.RSLAUtil.number( ...
                row,"ResourceCount",NaN);
            if ~(ismember(periodicity,[10 20 40 80]) && ...
                    isfinite(offset)&&offset>=0&&offset<periodicity && ...
                    ismember(qcl,["typea","typec"]) && resources==2)
                error("RSLA:InvalidTRSConfiguration", ...
                    "Invalid selected NZP-CSI-RS tracking resource set.");
            end
            indices = [];
            symbols = [];
            for resource = 1:resources
                k = (resource-1)*4;
                l = 4+(resource-1)*4;
                prbs = (0:51).';
                indices = [indices; l*52*12+prbs*12+k]; %#ok<AGROW>
                symbols = [symbols; exp(1j*pi/2*mod(prbs+resource,4))]; %#ok<AGROW>
            end
            plan = struct("PeriodicitySlots",periodicity, ...
                "OffsetSlots",offset,"QCLType",qcl, ...
                "ResourceCount",resources,"IndicesZeroBased",indices, ...
                "Symbols",symbols,"ResourceSetID","TRS-NZP-SET-1", ...
                "IndexSHA256",sixgr.phy.rsla.RSLAUtil.hash(indices), ...
                "SequenceSHA256",sixgr.phy.rsla.RSLAUtil.hash( ...
                    [real(symbols) imag(symbols)]), ...
                "ResourceType","NZP-CSI-RS-TRACKING");
        end

        function result = runMeasuredTracking(row)
            plan = sixgr.phy.rsla.TRSResourceEngine.planVector(row);
            injectedCFO = sixgr.phy.rsla.RSLAUtil.number(row,"CFOHz",0);
            injectedTiming = sixgr.phy.rsla.RSLAUtil.number( ...
                row,"TimingOffsetSamples",0);
            sampleRate = 15.36e6;
            n = (0:numel(plan.Symbols)-1).';
            received = circshift(plan.Symbols,round(injectedTiming));
            received = received.*exp(1j*2*pi*injectedCFO*n/sampleRate);
            phase = unwrap(angle(received.*conj(plan.Symbols)));
            if numel(phase)>=2
                estimateCFO = (phase(end)-phase(1))*sampleRate/ ...
                    (2*pi*(numel(phase)-1));
            else
                estimateCFO = 0;
            end
            correlation = abs(ifft(fft(received).*conj(fft(plan.Symbols))));
            [~,peak] = max(correlation);
            estimateTiming = peak-1;
            if estimateTiming>numel(received)/2
                estimateTiming = estimateTiming-numel(received);
            end
            tracker = sixgr.phy.rsla.TimingFrequencyTracker(1);
            state = tracker.update(estimateCFO,estimateTiming,1,0);
            [corrected,lineage] = tracker.apply(received,sampleRate,1);
            residualPhase = unwrap(angle(corrected.*conj(plan.Symbols)));
            if numel(residualPhase)>=2
                residualCFO = (residualPhase(end)-residualPhase(1))*sampleRate/ ...
                    (2*pi*(numel(residualPhase)-1));
            else
                residualCFO = 0;
            end
            result = struct("Plan",plan,"MeasuredCFOHz",estimateCFO, ...
                "EstimatedCFOHz",state.CFOEstimateHz, ...
                "ResidualCFOHz",residualCFO, ...
                "MeasuredTimingSamples",estimateTiming, ...
                "EstimatedTimingSamples",state.TimingEstimateSamples, ...
                "ResidualTimingSamples",injectedTiming-estimateTiming, ...
                "CorrectionApplied",lineage.CorrectionApplied, ...
                "Lineage",lineage, ...
                "ReceiverInputs","received_samples_and_installed_resource_only");
        end
    end
end
