classdef PDSCHConfigMaterializer
    %PDSCHConfigMaterializer One-way immutable assignment to Toolbox adapter.

    methods (Static)
        function pdsch = fromAssignment(assignment, referenceConfig)
            arguments
                assignment (1,1) sixgr.pdsch.PDSCHSchedulingAssignment
                referenceConfig (1,1) struct
            end

            source = assignment.toStruct();
            before = source;
            requiredReference = [ ...
                "NID","DMRSConfigurationType","DMRSTypeAPosition", ...
                "DMRSAdditionalPosition","DMRSLength", ...
                "NumCDMGroupsWithoutData","NIDNSCID","NSCID","EnablePTRS"];
            if logical(sixgr.util.structGet(referenceConfig, "EnablePTRS", false))
                requiredReference = [requiredReference, ...
                    "PTRSTimeDensity","PTRSFrequencyDensity","PTRSREOffset"];
            end
            missing = requiredReference(~isfield(referenceConfig, requiredReference));
            if ~isempty(missing)
                error("sixgr:pdsch:IncompleteReferenceSignalConfiguration", ...
                    "PDSCH reference configuration is missing: %s.", ...
                    strjoin(cellstr(missing), ", "));
            end

            if isempty(source.PRBSetCarrierRelative)
                error("sixgr:pdsch:MissingPRBAllocation", ...
                    "Scheduling assignment has no carrier-relative PRB allocation.");
            end
            if numel(source.SymbolAllocation) ~= 2
                error("sixgr:pdsch:SymbolAllocationEmpty", ...
                    "Scheduling assignment must contain [start length].");
            end
            sixgr.pdsch.PDSCHConfigMaterializer. ...
                validateCodewordModulation( ...
                source.ModulationPerCodeword,source.NumCodewords);

            pdsch = nrPDSCHConfig;
            if source.NumCodewords == 1
                pdsch.Modulation = char(source.ModulationPerCodeword(1));
            else
                pdsch.Modulation = cellstr(source.ModulationPerCodeword(:));
            end
            pdsch.NumLayers = double(source.NumLayers);
            pdsch.PRBSet = double(source.PRBSetCarrierRelative(:).');
            pdsch.SymbolAllocation = double(source.SymbolAllocation(:).');
            pdsch.MappingType = char(upper(string(source.MappingType)));
            pdsch.RNTI = double(source.RNTI);
            pdsch.NID = double(referenceConfig.NID);

            pdsch.DMRS.DMRSConfigurationType = double(referenceConfig.DMRSConfigurationType);
            pdsch.DMRS.DMRSTypeAPosition = double(referenceConfig.DMRSTypeAPosition);
            pdsch.DMRS.DMRSAdditionalPosition = double(referenceConfig.DMRSAdditionalPosition);
            pdsch.DMRS.DMRSLength = double(referenceConfig.DMRSLength);
            pdsch.DMRS.NumCDMGroupsWithoutData = double(referenceConfig.NumCDMGroupsWithoutData);
            pdsch.DMRS.NIDNSCID = double(referenceConfig.NIDNSCID);
            pdsch.DMRS.NSCID = double(referenceConfig.NSCID);
            pdsch.DMRS.DMRSPortSet = double(source.DMRSPortSet(:).');
            if isfield(referenceConfig,"DMRSMultiplexing")
                multiplexing = lower(strtrim(string( ...
                    referenceConfig.DMRSMultiplexing)));
                if multiplexing == "enhanced"
                    if ~isprop(pdsch.DMRS,"DMRSEnhancedR18")
                        error("sixgr:pdsch:EnhancedDMRSUnavailable", ...
                            "Installed Toolbox lacks DMRSEnhancedR18.");
                    end
                    pdsch.DMRS.DMRSEnhancedR18 = true;
                elseif multiplexing == "basic"
                    if isprop(pdsch.DMRS,"DMRSEnhancedR18")
                        pdsch.DMRS.DMRSEnhancedR18 = false;
                    end
                else
                    error("sixgr:pdsch:InvalidDMRSMultiplexingMode", ...
                        "DMRSMultiplexing must be basic or enhanced.");
                end
            end

            pdsch.EnablePTRS = logical(referenceConfig.EnablePTRS);
            if pdsch.EnablePTRS
                if isempty(source.PTRSPortSet)
                    error("sixgr:pdsch:InvalidPTRSPortAssociation", ...
                        "Enabled PT-RS requires an explicit PTRSPortSet.");
                end
                pdsch.PTRS.TimeDensity = double(referenceConfig.PTRSTimeDensity);
                pdsch.PTRS.FrequencyDensity = double(referenceConfig.PTRSFrequencyDensity);
                pdsch.PTRS.REOffset = char(string(referenceConfig.PTRSREOffset));
                pdsch.PTRS.PTRSPortSet = double(source.PTRSPortSet(:).');
            end

            if ~isequaln(before, assignment.toStruct())
                error("sixgr:pdsch:AssignmentMutation", ...
                    "PDSCH configuration materialization mutated the scheduling assignment.");
            end
        end

        function validateCodewordModulation(modulations,numCodewords)
            %VALIDATECODEWORDMODULATION Shared pre-waveform adapter guard.
            values = string(modulations);
            count = double(numCodewords);
            if ~(isscalar(count) && isfinite(count) ...
                    && count == fix(count) && count >= 1) ...
                    || numel(values) ~= count ...
                    || any(strlength(strtrim(values)) == 0)
                error("sixgr:pdsch:MissingCodewordSpecificModulation", ...
                    "Expected one nonblank modulation value per codeword.");
            end
        end
    end
end
