classdef PagingBandwidthStudy
    %PAGINGBANDWIDTHSTUDY Idle paging location/energy procedure model.

    methods (Static)
        function T=run(cfg,analyticalCfg,masterSeed)
            locations=string(cfg.locations(:));rows=cell(numel(locations),1);
            for i=1:numel(locations)
                stream=RandStream("Threefry","Seed",mod(double(masterSeed)+i*7919,2^31-2)+1);
                switch locations(i)
                    case "common_coreset", inside=true;retune=false;
                    case "sib1_pdsch", inside=true;retune=false;
                    case "same_span_additional", inside=true;retune=false;
                    case "retune_additional", inside=true;retune=true;
                    otherwise, inside=false;retune=true;
                end
                n=double(cfg.paging_occasions);
                p=double(cfg.pdcch_success_probability)*double(cfg.pdsch_success_probability)*inside;
                success=rand(stream,n,1)<p;
                retuneSlots=double(retune)*double(cfg.retune_time_slots);
                activeSlots=1+retuneSlots;
                energy=activeSlots*double(cfg.active_energy_per_slot)+ ...
                    max(0,double(cfg.drx_cycle_slots)-activeSlots)*double(cfg.deep_sleep_energy_per_slot);
                rows{i}=table(locations(i),inside,retune,n,1-mean(success), ...
                    energy,activeSlots,retuneSlots, ...
                    inside,"PROCEDURE_SLS", ...
                    'VariableNames',{'Location','MandatoryRFSpanFeasible','RetuneRequired', ...
                    'PagingOccasions','PagingMissProbability','EnergyPerCycle', ...
                    'RFActiveSlots','RetuneSlots','CanProceedToRACH','EvidenceClass'});
            end
            T=vertcat(rows{:});
            %#ok<NASGU> analyticalCfg documents the shared RF-span authority.
        end
    end
end
