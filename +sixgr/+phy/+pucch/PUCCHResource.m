classdef PUCCHResource
    %PUCCHRESOURCE Immutable exact format-specific PUCCH resource.

    properties (SetAccess=private)
        Data
        Digest
    end

    properties (Dependent)
        ID
        Format
    end

    methods
        function obj = PUCCHResource(data)
            required = ["ID","Format","StartPRB","NumPRBs","StartSymbol", ...
                "NumSymbols","IntraSlotHopping","SecondHopStartPRB", ...
                "InitialCyclicShift","OCCLength","OCCIndex", ...
                "AdditionalDMRS","Pi2BPSK","RNTI","NID","HoppingID"];
            sixgr.phy.pucch.UCIReport.requireFields(data,required);
            obj.Data = data;
            obj.Digest = sixgr.phy.pucch.PUCCHUtil.hash(data);
        end

        function value = get.ID(obj), value = double(obj.Data.ID); end
        function value = get.Format(obj), value = double(obj.Data.Format); end

        function [selected,budget] = selectPRBAllocation(obj,carrier,informationBits,maxCodeRate,procedure)
            % Single-sequence TS 38.213 9.2.3 / 9.2.5 allocation primitive.
            % Caller owns procedure selection and whole-report CSI omission.
            % Never concatenate separately coded CSI Part 2 into this count.
            assert(isa(carrier,'nrCarrierConfig') && isscalar(carrier), ...
                'sixgr:phy:pucch:MissingCarrierConfiguration', ...
                'Use the installed carrier, not a synthetic capacity grid.');
            validateattributes(informationBits,{'numeric'}, ...
                {'real','finite','scalar','integer','>=',3,'<=',1706});
            procedure=string(procedure);
            assert(isscalar(procedure) && any(procedure== ...
                ["dynamic_harq","dynamic_harq_csi","dynamic_harq_csi_omission","configured_csi"]), ...
                'sixgr:phy:pucch:InvalidAllocationProcedure', ...
                'Declare the HARQ, HARQ/CSI, CSI-omission or configured-CSI allocation procedure.');
            sixgr.phy.pucch.PUCCHResource.validateMaxCodeRate(maxCodeRate);
            assert(ismember(obj.Format,[2 3 4]), ...
                'sixgr:phy:pucch:InvalidAllocationProcedure', ...
                'Short PUCCH uses HARQ/SR modulation, not this coding budget.');
            sixgr.phy.pucch.PUCCHFormatValidator.validateResource(obj.Data,informationBits);
            maximum=double(obj.Data.NumPRBs);
            assert(maximum<=16 && (obj.Format~=3 || localTransformWidth(maximum)), ...
                'sixgr:phy:pucch:InvalidPRBAllocation', ...
                'Non-interlaced formats 2/3 allow at most 16 PRBs; format 3 requires a 2/3/5-smooth width.');
            assert(obj.Data.StartPRB+maximum<=carrier.NSizeGrid && ...
                (~obj.Data.IntraSlotHopping || obj.Data.SecondHopStartPRB+maximum<=carrier.NSizeGrid), ...
                'sixgr:phy:pucch:InvalidPRBAllocation', ...
                'The complete configured PUCCH resource must fit its carrier grid.');
            widths=1:maximum;
            if obj.Format==3, widths=widths(arrayfun(@localTransformWidth,widths)); end
            if any(procedure==["configured_csi","dynamic_harq_csi_omission"]) || obj.Format==4
                widths=maximum;
            end
            selected=[];
            for width=widths
                data=obj.Data; data.NumPRBs=width;
                candidate=sixgr.phy.pucch.PUCCHResource(data);
                [~,info]=nrPUCCHIndices(carrier,candidate.toolboxConfig());
                coding=sixgr.phy.pucch.UCIEncodingPlan(informationBits,double(info.G));
                % TS 38.213 9.2 explicitly assumes 11 CRC bits for A>=360
                % in resource selection. Keep actual segmented CRC separate.
                selectionCRC=coding.TotalCRCBits;
                if informationBits>=360, selectionCRC=11; end
                selectionInput=informationBits+selectionCRC;
                meetsRate=selectionInput<=maxCodeRate*double(info.G);
                budget=struct('Procedure',procedure,'ConfiguredResourceDigest',obj.Digest, ...
                    'ConfiguredNumPRBs',maximum,'SelectedNumPRBs',width, ...
                    'InformationBits',informationBits,'TotalCRCBits',coding.TotalCRCBits, ...
                    'AllocationCRCBits',selectionCRC,'AllocationInputBits',selectionInput, ...
                    'CodeBlockPaddingBits',coding.CodeBlockPaddingBits, ...
                    'CodeBlockInputBits',coding.CodeBlockInputBits, ...
                    'CapacityBits',double(info.G),'MaxCodeRate',double(maxCodeRate), ...
                    'InformationAndCRCRate',selectionInput/double(info.G), ...
                    'ActualInformationAndCRCRate',coding.InformationAndCRCBits/double(info.G), ...
                    'RateConstraintSatisfied',meetsRate,'RequiresCSISelection',false, ...
                    'Disposition',"selected_minimum_legal_width");
                budget.CarrierConfiguration=struct('NSizeGrid',carrier.NSizeGrid, ...
                    'NStartGrid',carrier.NStartGrid,'SubcarrierSpacing',carrier.SubcarrierSpacing, ...
                    'CyclicPrefix',carrier.CyclicPrefix);
                if meetsRate
                    selected=candidate;
                    if procedure=="configured_csi", budget.Disposition="configured_csi_resource"; end
                    if procedure=="dynamic_harq_csi_omission"
                        budget.Disposition="whole_csi_reports_selected_on_configured_resource";
                    end
                    return;
                end
            end
            if procedure=="dynamic_harq"
                % 9.2.3/9.2.5.1 retain the maximum-resource branch. This
                % does not claim that an arbitrary A/E can be encoded.
                selected=candidate;
                budget.Disposition="maximum_harq_resource_above_nominal_rate";
            else
                budget.SelectedNumPRBs=NaN;
                budget.RequiresCSISelection=procedure=="dynamic_harq_csi";
                budget.Disposition="configured_csi_capacity_exceeded";
                if budget.RequiresCSISelection, budget.Disposition="whole_csi_report_selection_required"; end
                if procedure=="dynamic_harq_csi_omission"
                    budget.Disposition="csi_omission_subset_exceeds_capacity";
                end
                % Empty allocation prevents an over-capacity CSI hypothesis
                % being mistaken for an accepted physical transmission.
            end
        end

        function value = toolboxConfig(obj)
            d = obj.Data;
            switch d.Format
                case 0, value = nrPUCCH0Config;
                case 1, value = nrPUCCH1Config;
                case 2, value = nrPUCCH2Config;
                case 3, value = nrPUCCH3Config;
                case 4, value = nrPUCCH4Config;
                otherwise
                    error("sixgr:phy:pucch:InvalidFormatPayload", ...
                        "Unsupported PUCCH format %g.",d.Format);
            end
            value.PRBSet = d.StartPRB + (0:d.NumPRBs-1);
            value.SymbolAllocation = [d.StartSymbol d.NumSymbols];
            value = localSet(value,"RNTI",d.RNTI);
            value = localSet(value,"NID",d.NID);
            value = localSet(value,"NID0",d.NID);
            value = localSet(value,"HoppingID",d.HoppingID);
            value = localSet(value,"FrequencyHopping",localHopping(d.IntraSlotHopping));
            if d.IntraSlotHopping
                value = localSet(value,"SecondHopStartPRB",d.SecondHopStartPRB);
            end
            % These names are not interchangeable across PUCCH formats.
            % In the repository schema OCCLength is the configured
            % orthogonal-cover/spreading factor.  MATLAB R2026 exposes it
            % as SpreadingFactor for formats 2/3/4 and rejects the legacy
            % value one for formats 2/4.  Do not copy it blindly to every
            % Toolbox object.
            if ismember(d.Format,[0 1])
                value = localSet(value,"InitialCyclicShift",d.InitialCyclicShift);
            end
            if ismember(d.Format,[1 2 3 4])
                value = localSet(value,"OCCI",d.OCCIndex);
            end
            if ismember(d.Format,[2 3 4])
                value = localSet(value,"SpreadingFactor",d.OCCLength);
            end
            if ismember(d.Format,[3 4])
                value = localSet(value,"AdditionalDMRS",logical(d.AdditionalDMRS));
                value = localSet(value,"Pi2BPSK",logical(d.Pi2BPSK));
            end
            if isprop(value,"Modulation")
                if logical(d.Pi2BPSK)
                    value.Modulation = "pi/2-BPSK";
                else
                    value.Modulation = "QPSK";
                end
            end
        end
    end
    methods (Static)
        function validateAllocationCarrier(budget,carrier)
            assert(isstruct(budget) && isscalar(budget) && isfield(budget,'CarrierConfiguration'), ...
                'sixgr:phy:pucch:MissingCarrierConfiguration','Allocation must retain its installed carrier geometry.');
            for field=["NSizeGrid","NStartGrid","SubcarrierSpacing","CyclicPrefix"]
                assert(isequal(budget.CarrierConfiguration.(field),carrier.(field)), ...
                    'sixgr:phy:pucch:AllocationCarrierMismatch', ...
                    'PUCCH allocation/runtime carrier field %s differs.',field);
            end
        end
        function validateMaxCodeRate(value)
            catalog=sixgr.lls6g.config.loadParameterCatalog('scenario');
            allowed=double(catalog.nested_sections.pucch_format_configuration_object. ...
                parameters.max_code_rate.allowed_numeric_values);
            assert(isnumeric(value) && isreal(value) && isscalar(value) && ...
                isfinite(value) && any(value==allowed), ...
                'sixgr:phy:pucch:InvalidMaxCodeRate', ...
                'max_code_rate must be one of the catalogued TS 38.213 values.');
        end
    end
end

function object = localSet(object,name,value)
if isprop(object,name) && ~isempty(value) && ...
        ~(isnumeric(value) && isscalar(value) && isnan(value))
    object.(name) = value;
end
end

function value = localHopping(input)
if logical(input), value = "intraSlot"; else, value = "neither"; end
end

function valid=localTransformWidth(width)
for prime=[2 3 5]
    while mod(width,prime)==0, width=width/prime; end
end
valid=width==1;
end
