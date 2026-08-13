classdef PowerNormalizer
    %POWERNORMALIZER Exact allocation-energy accounting for BWOP studies.

    methods (Static)
        function T = sourceArithmetic(nSmall,nLarge,sourceDelta,distributedDelta)
            nSmall=double(nSmall); nLarge=double(nLarge);
            if any([nSmall nLarge]<=0)
                error("sixgr:bwop:InvalidAllocationSize", ...
                    "Allocation sizes must be positive.");
            end
            ratioDb=10*log10(nLarge/nSmall);
            fixedTotalDelta=double(sourceDelta)-ratioDb;
            T=table(nSmall,nLarge,ratioDb,double(sourceDelta), ...
                fixedTotalDelta,double(distributedDelta),"ANALYTICAL_EXACT", ...
                'VariableNames',{'SmallAllocationRB','LargeAllocationRB', ...
                'OccupiedEnergyRatioDb','SourceReportedFixedPSDDeltaDb', ...
                'ArithmeticFixedTotalDeltaDb','SourceReportedDistributedDeltaDb', ...
                'EvidenceClass'});
        end

        function T = accounting(prbCounts,dataREPerRB,dmrsREPerRB,mode)
            counts=double(prbCounts(:)); dataPer=double(dataREPerRB);
            dmrsPer=double(dmrsREPerRB); mode=lower(string(mode));
            if any(counts<=0)||dataPer<0||dmrsPer<0||~ismember(mode,["fixed_psd","fixed_total_power"])
                error("sixgr:bwop:InvalidPowerAccountingInput", ...
                    "Power accounting requires positive RB counts, nonnegative RE counts and a supported mode.");
            end
            dataRE=counts*dataPer; dmrsRE=counts*dmrsPer; occupied=dataRE+dmrsRE;
            if mode=="fixed_psd"
                dataPower=ones(size(counts)); dmrsPower=ones(size(counts));
            else
                dataPower=1./occupied; dmrsPower=dataPower;
            end
            total=dataRE.*dataPower+dmrsRE.*dmrsPower;
            T=table(counts,dataRE,dmrsRE,occupied,dataPower,dmrsPower,total, ...
                repmat(mode,numel(counts),1),repmat("ANALYTICAL_EXACT",numel(counts),1), ...
                'VariableNames',{'ActualAllocationRB','DataRE','DMRSRE','OccupiedRE', ...
                'DataPowerPerRE','DMRSPowerPerRE','TotalCodewordEnergy', ...
                'NormalizationMode','EvidenceClass'});
        end

        function assertClosure(T,tolerance)
            if nargin<2,tolerance=1e-12;end
            modes=unique(string(T.NormalizationMode));
            for mode=modes(:).'
                rows=T(string(T.NormalizationMode)==mode,:);
                if mode=="fixed_total_power"
                    if max(abs(rows.TotalCodewordEnergy-rows.TotalCodewordEnergy(1)))>tolerance
                        error("sixgr:bwop:FixedTotalPowerClosure", ...
                            "Fixed-total-power energy does not close within %.3g.",tolerance);
                    end
                elseif mode=="fixed_psd"
                    measured=rows.TotalCodewordEnergy/rows.TotalCodewordEnergy(1);
                    expected=rows.OccupiedRE/rows.OccupiedRE(1);
                    if max(abs(measured-expected))>tolerance
                        error("sixgr:bwop:FixedPSDClosure", ...
                            "Fixed-PSD total energy ratio does not match occupied-RE ratio.");
                    end
                end
            end
        end
    end
end
