classdef ULReferenceSignaling
    % TS 38.212 7.3.1.1.2: codebook SRI and tables -8/-9/-10/-11.
    % Explicitly excludes enhanced DMRS, transform precoding and multi-panel.
    methods (Static)
        function out=resolve(data)
            p=data.ULReferenceSignaling;
            fields={'srs_resource_count','dmrs_configuration_type','dmrs_max_length', ...
                'dmrs_type_enhanced','multipanel_sdm'};
            assert(isstruct(p) && isscalar(p) && all(isfield(p,fields)) && ...
                isfield(data,'ULPrecoding'),'sixgr:phy:pdcch:MissingULReferenceContext', ...
                'Explicit UL reference signaling and codebook context are required.');
            n=double(p.srs_resource_count);
            assert(isscalar(n) && isfinite(n) && n==fix(n) && n>=1 && n<=4, ...
                'sixgr:phy:pdcch:InvalidSRSResourceCount','Codebook SRS resource count must be in 1..4.');
            assert(string(data.ULPrecoding.transmission_scheme)=="codebook" && ...
                ~logical(data.TransformPrecodingEnabled) && ...
                isequal(double(p.dmrs_configuration_type),1) && isequal(double(p.dmrs_max_length),1) && ...
                isequal(logical(p.dmrs_type_enhanced),false) && isequal(logical(p.multipanel_sdm),false), ...
                'sixgr:phy:pdcch:UnsupportedULReferenceContext', ...
                'This table set requires ordinary type-1, maxLength-1 CP-OFDM DMRS and codebook SRS.');
            out=struct('SRIWidth',ceil(log2(n)),'SRIMaxValue',n-1,'AntennaWidth',3);
        end

        function [groups,ports]=antennaRows(data,rank)
            sixgr.phy.pdcch.ULReferenceSignaling.resolve(data);
            switch rank
                case 1, groups=[1 1 2 2 2 2]; ports={0,1,0,1,2,3};
                case 2, groups=[1 2 2 2]; ports={[0 1],[0 1],[2 3],[0 2]};
                case 3, groups=2; ports={[0 1 2]};
                case 4, groups=2; ports={[0 1 2 3]};
                otherwise
                    error('sixgr:phy:pdcch:InvalidULDMRSRank','DMRS table rank must be 1..4.');
            end
        end

        function value=encodeAntenna(data,rank,portSet,numCDM,frontLoad)
            assert(isscalar(numCDM) && isfinite(numCDM) && numCDM==fix(numCDM) && ...
                numel(portSet)==rank && all(isfinite(portSet(:))), ...
                'sixgr:phy:pdcch:MissingULDMRSSelection','Exact scheduled DMRS ports and CDM group count are required.');
            [groups,ports]=sixgr.phy.pdcch.ULReferenceSignaling.antennaRows(data,rank);
            assert(isequal(double(frontLoad),1),'sixgr:phy:pdcch:ULDMRSContextMismatch', ...
                'Configured maxLength=1 cannot signal double-symbol DMRS.');
            index=find(groups==numCDM & cellfun(@(x)isequal(x,double(portSet(:).')),ports));
            assert(isscalar(index),'sixgr:phy:pdcch:ULDMRSSelectionNotInTable', ...
                'Actual scheduled DMRS ports/CDM groups are absent from the selected 38.212 table.');
            value=index-1;
        end

        function [ports,groups]=decodeAntenna(data,rank,value)
            [allGroups,allPorts]=sixgr.phy.pdcch.ULReferenceSignaling.antennaRows(data,rank);
            assert(isscalar(value) && isfinite(value) && value==fix(value) && value>=0 && ...
                value<numel(allGroups),'sixgr:phy:pdcch:ReservedULDMRSCodepoint', ...
                'Reserved antenna-port indication for the decoded UL rank.');
            ports=allPorts{value+1}; groups=allGroups(value+1);
        end

        function fields=bindSRI(fields,data,indicator)
            out=sixgr.phy.pdcch.ULReferenceSignaling.resolve(data);
            assert(isscalar(indicator) && isfinite(indicator) && indicator==fix(indicator) && ...
                indicator>=0 && indicator<=out.SRIMaxValue, ...
                'sixgr:phy:pdcch:InvalidSRSResourceIndicator','SRI must index the configured codebook SRS resource set.');
            if out.SRIWidth==0
                if isfield(fields,'srs_resource_indicator'), fields=rmfield(fields,'srs_resource_indicator'); end
            else
                fields.srs_resource_indicator=indicator;
            end
        end

        function value=antennaFromGrant(data,cfg,grant)
            rank=double(grant.NumLayers);
            [ports,~]=sixgr.phy.grant.resolveScheduledDMRSPortSet(cfg,'UL',rank,grant);
            selected=cfg; selected.phy.pusch.dmrs.scheduledPortSet=ports;
            carrier=sixgr.phy.grid.makeCarrier(selected);
            [~,~,pusch]=sixgr.phy.grid.allocREsPUSCH(carrier,selected,'NumLayers',rank, ...
                'SymbolAllocation',grant.SymbolAllocation,'PRBSet',grant.PRBSet);
            assert(pusch.DMRS.DMRSConfigurationType==data.ULReferenceSignaling.dmrs_configuration_type && ...
                pusch.DMRS.DMRSLength==data.ULReferenceSignaling.dmrs_max_length, ...
                'sixgr:phy:pdcch:ULDMRSContextMismatch','DCI DMRS context disagrees with the actual PUSCH allocation.');
            value=sixgr.phy.pdcch.ULReferenceSignaling.encodeAntenna(data,rank, ...
                pusch.DMRS.DMRSPortSet,pusch.DMRS.NumCDMGroupsWithoutData,pusch.DMRS.DMRSLength);
        end
    end
end
