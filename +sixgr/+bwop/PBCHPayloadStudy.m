classdef PBCHPayloadStudy
    %PBCHPAYLOADSTUDY Deterministic PBCH payload-cost screening.

    methods (Static)
        function out = run(cfg)
            payload=double(cfg.sib1_payload_bits(:)); rates=double(cfg.effective_code_rates(:));
            rows=cell(numel(payload)*numel(rates),1);index=0;
            for A=payload(:).'
                crc=16+(A>3824)*8;
                for rate=rates(:).'
                    index=index+1;
                    minimum=ceil((A+crc)/(2*rate*double(cfg.analytical_re_per_rb)));
                    rows{index}=table(A,crc,rate,double(cfg.analytical_re_per_rb),minimum, ...
                        "ANALYTICAL_EXACT",'VariableNames',{'PayloadBits','CRCBits', ...
                        'EffectiveCodeRate','AnalyticalREPerRB','MinimumRB','EvidenceClass'});
                end
            end
            out.MinimumRB=vertcat(rows{:});
            added=double(cfg.pbch_added_bits(:)); baseline=double(cfg.pbch_baseline_input_bits);
            delta=10*log10((baseline+added)/baseline);
            % Capacity screening is explicitly separate from the exact closed form.
            rate=(baseline+added)/double(cfg.pbch_coded_bits);
            capacityEsN0=10*log10(max(2.^rate-1,realmin));
            capacityDelta=capacityEsN0-capacityEsN0(1);
            out.PayloadCost=table(added,repmat(baseline,numel(added),1),delta, ...
                rate,capacityDelta,delta-capacityDelta, ...
                repmat("ANALYTICAL_EXACT",numel(added),1), ...
                repmat("ANALYTICAL_SCREENING",numel(added),1), ...
                'VariableNames',{'AddedBits','BaselineInputBits','ClosedFormDeltaEsN0Db', ...
                'EffectiveInputRate','CapacityScreeningDeltaDb','MethodDeltaDb', ...
                'ClosedFormEvidenceClass','CapacityEvidenceClass'});
        end
    end
end
