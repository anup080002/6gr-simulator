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
            localSet(value,"RNTI",d.RNTI);
            localSet(value,"NID",d.NID);
            localSet(value,"NID0",d.NID);
            localSet(value,"HoppingID",d.HoppingID);
            localSet(value,"FrequencyHopping",localHopping(d.IntraSlotHopping));
            if d.IntraSlotHopping
                localSet(value,"SecondHopStartPRB",d.SecondHopStartPRB);
            end
            localSet(value,"InitialCyclicShift",d.InitialCyclicShift);
            localSet(value,"OCCI",d.OCCIndex);
            localSet(value,"SpreadingFactor",d.OCCLength);
            localSet(value,"AdditionalDMRS",logical(d.AdditionalDMRS));
            localSet(value,"Pi2BPSK",logical(d.Pi2BPSK));
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

function localSet(object,name,value)
if isprop(object,name) && ~isempty(value) && ...
        ~(isnumeric(value) && isscalar(value) && isnan(value))
    object.(name) = value;
end
end

function value = localHopping(input)
if logical(input), value = "intraSlot"; else, value = "neither"; end
end
