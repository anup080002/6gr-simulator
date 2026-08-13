classdef EnergyModel
    %ENERGYMODEL Source arithmetic and explicitly assumed BWOP energy model.

    methods (Static)
        function T = sourceReproduction(cfg)
            m=cfg.mediatek;
            bandwidth=[100;200;100;200];
            sleepCase=["baseline";"baseline";"enhanced";"enhanced"];
            pusch=[double(m.pusch_energy_100mhz);double(m.pusch_energy_200mhz); ...
                double(m.pusch_energy_100mhz);double(m.pusch_energy_200mhz)];
            sleep=[double(m.sleep_energy_baseline);double(m.sleep_energy_baseline); ...
                double(m.sleep_energy_enhanced);double(m.sleep_energy_enhanced)];
            total=pusch+sleep;
            increase=[0;100*(total(2)/total(1)-1);0;100*(total(4)/total(3)-1)];
            T=table(bandwidth,sleepCase,pusch,sleep,total,increase, ...
                repmat("SOURCE_REPRODUCTION",4,1), ...
                'VariableNames',{'ConfiguredBandwidthMHz','SleepCase','PUSCHEnergy', ...
                'SleepEnergy','TotalNormalizedEnergy','IncreaseVs100MHzPercent','EvidenceClass'});
        end

        function T = configuredRangeStudy(configuredRangeRB,actualRB,txPowerDbm,model)
            configuredRangeRB=double(configuredRangeRB(:)); actualRB=double(actualRB(:));
            txPowerDbm=double(txPowerDbm(:)); rows=cell(numel(configuredRangeRB)*numel(actualRB)*numel(txPowerDbm),1);r=0;
            for width=configuredRangeRB(:).'
                for allocation=actualRB(:).'
                    for power=txPowerDbm(:).'
                        if allocation>width,continue;end
                        r=r+1;
                        paEnergy=10^(power/10)*double(model.pa_slot_duration_s);
                        rfEnergy=double(model.rf_sqrt_bandwidth_coefficient)*sqrt(width);
                        bbEnergy=double(model.bb_configured_rb_coefficient)*width+ ...
                            double(model.bb_allocated_rb_coefficient)*allocation;
                        sleepEnergy=max(0,double(model.sleep_baseline)- ...
                            double(model.sleep_per_configured_rb)*width);
                        total=paEnergy+rfEnergy+bbEnergy+sleepEnergy;
                        rows{r}=table(width,allocation,power,paEnergy,rfEnergy,bbEnergy, ...
                            sleepEnergy,total,"ASSUMPTION_ONLY", ...
                            'VariableNames',{'ConfiguredRangeRB','ActualAllocationRB', ...
                            'UETxPowerDbm','PAEnergy','RFEnergy','BBEnergy','SleepEnergy', ...
                            'TotalEnergy','EvidenceClass'});
                    end
                end
            end
            T=vertcat(rows{1:r});
        end
    end
end
