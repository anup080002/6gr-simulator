classdef TCMsg4DCIContext
    % TC-RNTI DCI 1_0, TS 38.212 V18.8.0 7.3.1.2.1.
    % Licensed FR1/FR2-1, default-A common TDRA, no Msg4 ACK repetition.
    methods (Static)
        function context = create(reference,rnti,repetitionsConfigured)
            data = reference;
            data.SpecRelease = "Release18"; data.SpecVersion = "18.8.0";
            data.DCIFormat = "1_0"; data.RNTIType = "TC-RNTI";
            data.RNTIValue = rnti; data.SearchSpaceType = "TYPE1";
            data.MonitoredFormats = "1_0"; data.LegacyCompatibility = false;
            data.Msg4HARQACKRepetitionsConfigured = repetitionsConfigured;
            context = sixgr.phy.pdcch.DCIContext(data);
        end
        function validate(data)
            % The common reference shares CP/default-A validation, but TC
            % frequency sizing specifically requires CORESET0, not an
            % arbitrary active BWP or the RA-RNTI no-CORESET0 alternative.
            sixgr.phy.pdcch.RARDCIContext.validate(data);
            if ~ismember(string(data.FrequencyReferenceSource), ...
                    ["decoded_mib_coreset0","scenario_coreset0"]) || ...
                    ~isfield(data,'Msg4HARQACKRepetitionsConfigured')
                error('sixgr:phy:pdcch:invalid_tc_msg4_context', ...
                    'TC-RNTI Msg4 requires CORESET0 sizing and explicit HARQ-ACK repetition authority.');
            end
            repeat = data.Msg4HARQACKRepetitionsConfigured;
            if ~islogical(repeat) || ~isscalar(repeat) || repeat
                error('sixgr:phy:pdcch:unsupported_tc_msg4_repetitions', ...
                    'Configured Msg4 HARQ-ACK repetitions require the applicable DAI repetition semantics.');
            end
        end
        function grant = resolveSemantics(fields,context)
            d = context.Data;
            [first,count] = sixgr.bwop.RIVFDRA.decode(d.FrequencyReferenceSize,fields.frequency_resource_assignment);
            if sixgr.bwop.RIVFDRA.encode(d.FrequencyReferenceSize,first,count)~=fields.frequency_resource_assignment
                error('sixgr:phy:pdcch:field_out_of_range','Noncanonical Msg4 FDRA RIV.');
            end
            [rows,mapping] = sixgr.phy.pdcch.RARDCIContext.defaultA(d.CyclicPrefix,d.DMRSTypeAPosition);
            row = rows(fields.time_resource_assignment+1,:);
            grant = struct('prb_start',first,'num_prb',count, ...
                'reference_start',d.FrequencyReferenceStart,'symbol_start',row(2), ...
                'num_symbols',row(3),'timing_offset_slots',row(4), ...
                'mapping_type',mapping(fields.time_resource_assignment+1), ...
                'direction',"DL",'grant_type',"PDSCH",'configuration_epoch',d.ConfigurationEpoch);
        end
    end
end
