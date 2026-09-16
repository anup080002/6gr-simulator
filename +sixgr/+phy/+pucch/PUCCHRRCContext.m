classdef PUCCHRRCContext
    %PUCCHRRCContext Immutable installed RRC PUCCH configuration.

    properties (SetAccess=private)
        Data
        ResourceSets
        Resources
        ConfigurationEpoch
        Digest
    end

    methods
        function obj = PUCCHRRCContext(data)
            required = ["ConfigurationEpoch","ResourceSets","Resources", ...
                "DLDataToULACK","SRResources","CSIResources", ...
                "SPSPUCCHANResources"];
            sixgr.phy.pucch.UCIReport.requireFields(data,required);
            assert(~isfield(data,'SimultaneousHARQACKCSI'), ...
                'sixgr:phy:pucch:InvalidMultiplexingPermission', ...
                'Use format-owned permission; a global HARQ/CSI permission is ambiguous.');
            if ~isfield(data,'FormatConfigurations')
                data.FormatConfigurations=struct('Format',{},'SimultaneousHARQACKCSI',{});
            end
            policies=data.FormatConfigurations;
            assert(isstruct(policies),'sixgr:phy:pucch:InvalidMultiplexingPermission', ...
                'FormatConfigurations must contain format-owned configuration objects.');
            formats=zeros(1,numel(policies));
            for index=1:numel(policies)
                assert(isfield(policies,'Format'),'sixgr:phy:pucch:InvalidMultiplexingPermission', ...
                    'Each format configuration must identify format 2, 3 or 4.');
                format=policies(index).Format;
                assert(isnumeric(format) && isreal(format) && isscalar(format) && ...
                    ismember(format,[2 3 4]),'sixgr:phy:pucch:InvalidMultiplexingPermission', ...
                    'Each format configuration must identify format 2, 3 or 4.');
                formats(index)=format;
                if ~isfield(policies,'SimultaneousHARQACKCSI')
                    [policies.SimultaneousHARQACKCSI]=deal(false);
                end
                permission=policies(index).SimultaneousHARQACKCSI;
                assert((islogical(permission)||isnumeric(permission)) && ...
                    isreal(permission) && isscalar(permission) && ...
                    isfinite(permission) && any(permission==[0 1]), ...
                    'sixgr:phy:pucch:InvalidMultiplexingPermission', ...
                    'Format-owned SimultaneousHARQACKCSI must be a scalar binary permission.');
                policies(index).SimultaneousHARQACKCSI=logical(permission);
                if isfield(policies,'MaxCodeRate') && ~isempty(policies(index).MaxCodeRate)
                    sixgr.phy.pucch.PUCCHResource.validateMaxCodeRate(policies(index).MaxCodeRate);
                end
            end
            assert(numel(unique(formats))==numel(formats), ...
                'sixgr:phy:pucch:InvalidMultiplexingPermission', ...
                'A PUCCH format cannot have multiple configuration authorities.');
            data.FormatConfigurations=policies;
            obj.ConfigurationEpoch = double(data.ConfigurationEpoch);
            sets = data.ResourceSets;
            resources = data.Resources;
            resourceSets = sixgr.phy.pucch.PUCCHResourceSet.empty(0,1);
            for index = 1:numel(sets)
                resourceSets(end+1,1) = sixgr.phy.pucch.PUCCHResourceSet(sets(index)); %#ok<AGROW>
            end
            resourceObjects = sixgr.phy.pucch.PUCCHResource.empty(0,1);
            for index = 1:numel(resources)
                resourceObjects(end+1,1) = sixgr.phy.pucch.PUCCHResource(resources(index)); %#ok<AGROW>
            end
            obj.ResourceSets = resourceSets;
            obj.Resources = resourceObjects;
            ids = arrayfun(@(x) x.ID,obj.Resources);
            if numel(unique(ids)) ~= numel(ids)
                error("sixgr:phy:pucch:InvalidResourceIndicator", ...
                    "PUCCH resource IDs must be unique.");
            end
            for index = 1:numel(obj.ResourceSets)
                if any(~ismember(obj.ResourceSets(index).ResourceIDs,ids))
                    error("sixgr:phy:pucch:InvalidResourceIndicator", ...
                        "PUCCH resource set %d references an unknown resource.", ...
                        obj.ResourceSets(index).ID);
                end
            end
            obj.Data = data;
            obj.Digest = sixgr.phy.pucch.PUCCHUtil.hash(data);
        end

        function resource = resourceByID(obj,id)
            index = find(arrayfun(@(x) x.ID,obj.Resources) == double(id),1);
            if isempty(index)
                error("sixgr:phy:pucch:InvalidResourceIndicator", ...
                    "Unknown PUCCH resource ID %g.",id);
            end
            resource = obj.Resources(index);
        end

        function allowed=allowsHARQCSI(obj,format)
            validateattributes(format,{'numeric'},{'real','finite','scalar','integer','>=',0,'<=',4});
            policies=obj.Data.FormatConfigurations;
            allowed=false; % Absent higher-layer IE: not provided, TS 38.213 9.2.5.
            for index=1:numel(policies)
                if policies(index).Format==format
                    allowed=policies(index).SimultaneousHARQACKCSI;
                    return;
                end
            end
        end

        function assertMultiplexingAllowed(obj,format,harqBits,csiBits)
            % Counts suffice: neither TX values nor receiver decisions enter.
            if harqBits>0 && csiBits>0
                assert(obj.allowsHARQCSI(format), ...
                    'sixgr:phy:pucch:HARQCSIMultiplexingNotConfigured', ...
                    ['Combined HARQ/CSI requires simultaneousHARQ-ACK-CSI for its selected format. ' ...
                     'Resolve CSI dropping before resource planning; do not transmit or receive this combined schema.']);
            end
        end

        function value=maxCodeRate(obj,format)
            policies=obj.Data.FormatConfigurations;
            index=find([policies.Format]==format,1);
            assert(~isempty(index) && isfield(policies,'MaxCodeRate') && ...
                ~isempty(policies(index).MaxCodeRate), ...
                'sixgr:phy:pucch:MissingMaxCodeRate', ...
                'Install max_code_rate for selected PUCCH format %d.',format);
            value=policies(index).MaxCodeRate;
        end

        function [resource,budget]=allocateResource(obj,id,context,slot0,procedure)
            resource=obj.resourceByID(id);
            assert(context.Sequence2Length==0, ...
                'sixgr:phy:pucch:SeparateCSIPart2CodingRequired', ...
                'Separately coded CSI Part 2 cannot use a flattened single-sequence budget.');
            assert(isfield(obj.Data,'CarrierConfiguration'), ...
                'sixgr:phy:pucch:MissingCarrierConfiguration', ...
                'Resource allocation requires installed carrier geometry.');
            grid=obj.Data.CarrierConfiguration;
            fields=["NSizeGrid","NStartGrid","SubcarrierSpacing","CyclicPrefix"];
            sixgr.phy.pucch.UCIReport.requireFields(grid,fields);
            carrier=nrCarrierConfig;
            for field=fields, carrier.(field)=grid.(field); end
            validateattributes(slot0,{'numeric'},{'real','finite','scalar','integer','nonnegative'});
            carrier.NSlot=mod(slot0,carrier.SlotsPerFrame);
            carrier.NFrame=floor(slot0/carrier.SlotsPerFrame);
            [resource,budget]=resource.selectPRBAllocation(carrier, ...
                context.Sequence1Length,obj.maxCodeRate(resource.Format),procedure);
        end
    end
end
