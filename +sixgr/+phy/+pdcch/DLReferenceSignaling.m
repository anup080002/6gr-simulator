classdef DLReferenceSignaling
    % TS 38.212 V18.8.0 table 7.3.1.2.2-1 (not -1A).
    % Logical port values below mean physical DM-RS antenna ports 1000+p.
    methods (Static)
        function out=resolve(data)
            assert(isfield(data,'DLReferenceSignaling'), ...
                'sixgr:phy:pdcch:MissingDLReferenceContext','Explicit DL reference signaling is required.');
            p=data.DLReferenceSignaling;
            required={'dmrs_configuration_type','dmrs_max_length','dmrs_type_enhanced', ...
                'two_tci_states','max_codewords'};
            assert(isstruct(p) && isscalar(p) && all(isfield(p,required)), ...
                'sixgr:phy:pdcch:MissingDLReferenceContext','Incomplete DL reference signaling context.');
            assert(isequal(p.dmrs_configuration_type,1) && isequal(p.dmrs_max_length,1) && ...
                isequal(p.dmrs_type_enhanced,false) && isequal(p.two_tci_states,false) && ...
                isequal(p.max_codewords,1), ...
                'sixgr:phy:pdcch:UnsupportedDLReferenceContext', ...
                'This table implementation requires ordinary type-1/maxLength-1 DMRS, one codeword and no two-TCI-state mapping.');
            out=struct('AntennaWidth',4,'StandardClause',"38.212 7.3.1.2.2 table -1");
        end

        function [groups,ports]=antennaRows(data)
            sixgr.phy.pdcch.DLReferenceSignaling.resolve(data);
            groups=[1 1 1 2 2 2 2 2 2 2 2 2];
            ports={0,1,[0 1],0,1,2,3,[0 1],[2 3],[0 1 2],[0 1 2 3],[0 2]};
        end

        function value=encodeAntenna(data,rank,portSet,numCDM,frontLoad)
            [groups,ports]=sixgr.phy.pdcch.DLReferenceSignaling.antennaRows(data);
            assert(isnumeric(rank) && isscalar(rank) && isfinite(rank) && rank==fix(rank) && ...
                rank>=1 && rank<=4 && isnumeric(portSet) && isreal(portSet) && ...
                numel(portSet)==rank && all(isfinite(portSet(:))) && ...
                isnumeric(numCDM) && isscalar(numCDM) && isfinite(numCDM) && isequal(frontLoad,1), ...
                'sixgr:phy:pdcch:MissingDLDMRSSelection', ...
                'Exact scheduled rank, DMRS ports, CDM group count and one front-loaded symbol are required.');
            index=find(groups==numCDM & cellfun(@(x)isequal(x,double(portSet(:).')),ports));
            assert(isscalar(index),'sixgr:phy:pdcch:DLDMRSSelectionNotInTable', ...
                'Scheduled DMRS ports/CDM groups are absent from the selected 38.212 table.');
            value=index-1;
        end

        function [ports,groups,rank]=decodeAntenna(data,value)
            [allGroups,allPorts]=sixgr.phy.pdcch.DLReferenceSignaling.antennaRows(data);
            assert(isnumeric(value) && isscalar(value) && isreal(value) && isfinite(value) && ...
                value==fix(value) && value>=0 && value<numel(allGroups), ...
                'sixgr:phy:pdcch:ReservedDLDMRSCodepoint','Reserved DL antenna-port indication.');
            ports=allPorts{value+1}; groups=allGroups(value+1); rank=numel(ports);
        end

        function value=antennaFromGrant(data,cfg,grant)
            sixgr.phy.pdcch.DLReferenceSignaling.resolve(data);
            rank=double(grant.NumLayers);
            ports=sixgr.phy.grant.resolveScheduledDMRSPortSet(cfg,'DL',rank,grant);
            selected=cfg;
            % scheduledPortSet has priority over the configured available pool.
            selected.phy.pdsch.dmrs.scheduledPortSet=ports;
            carrier=sixgr.phy.grid.makeCarrier(selected);
            pdsch=sixgr.phy.grid.pdschConfigFromConfig(carrier,selected,'NumLayers',rank, ...
                'SymbolAllocation',grant.SymbolAllocation,'PRBSet',grant.PRBSet);
            p=data.DLReferenceSignaling;
            assert(pdsch.DMRS.DMRSConfigurationType==p.dmrs_configuration_type && ...
                pdsch.DMRS.DMRSLength==p.dmrs_max_length && pdsch.NumCodewords==p.max_codewords, ...
                'sixgr:phy:pdcch:DLDMRSContextMismatch', ...
                'DCI DL reference context disagrees with the scheduled PDSCH configuration.');
            value=sixgr.phy.pdcch.DLReferenceSignaling.encodeAntenna(data,rank, ...
                pdsch.DMRS.DMRSPortSet,pdsch.DMRS.NumCDMGroupsWithoutData,pdsch.DMRS.DMRSLength);
        end
    end
end
