function ok=testPUSCHAllocationPowerPreview()
% Analytic pre-encoding boundary, no generated waveform or RF execution.
for mu=[0 1 2]
    for prbs=[1 24 51]
        for previous=[-3 4]
            a={'LoopId',0,'AdjustmentMode','accumulated','Mu',mu,'MRB',prbs, ...
                'P0Nominal_dBm',-80,'P0UE_dB',0,'Alpha',1, ...
                'MeasuredPathloss_dB',90,'DeltaTF_dB',0,'PreviousF_dB',previous, ...
                'TPCDelta_dB',1,'PCMAX_dBm',23,'PathlossReferenceRS','received-SSB-1'};
            p=sixgr.phy.ul.pusch.PUSCHPowerController.resolveAllocation(a{:});
            q=sixgr.phy.ul.pusch.PUSCHPowerController.resolve(a{:},'ReferenceWaveformPower_dBm',-7);
            for f=string(fieldnames(p)).'
                if ismember(f,["ReferenceWaveformPower_dBm","AmplitudeScale"]), continue; end
                assert(isequaln(p.(f),q.(f)));
            end
            expected=-80+10*log10(2^mu*prbs)+90+previous+1;
            assert(abs(p.RequestedPower_dBm-expected)<1e-12 && ...
                abs(p.PowerHeadroom_dB-(23-expected))<1e-12);
            assert(isnan(p.AmplitudeScale) && isnan(p.ReferenceWaveformPower_dBm));
            bad=false; try
                sixgr.phy.ul.pusch.PUSCHPowerController.apply(ones(4,1),p);
            catch e, bad=strcmp(e.identifier,'sixgr:pusch:UnboundWaveformPower'); end
            assert(bad,'An allocation-only target must not scale samples.');
        end
    end
end
assert(p.PowerHeadroom_dB<0 && p.AppliedPower_dBm==23);
ok=true;
end
