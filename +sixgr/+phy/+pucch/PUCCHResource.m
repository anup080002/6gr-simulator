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
