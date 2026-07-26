classdef RFReferencePlane
%RFREFERENCEPLANE Validated RF/baseband reference-plane catalog.

    properties(Constant)
        DIGITAL_LAYER_PORT = "DIGITAL_LAYER_PORT"
        POST_PRECODER_DIGITAL = "POST_PRECODER_DIGITAL"
        DAC_INPUT = "DAC_INPUT"
        DAC_OUTPUT = "DAC_OUTPUT"
        POST_RECONSTRUCTION_FILTER = "POST_RECONSTRUCTION_FILTER"
        PA_INPUT = "PA_INPUT"
        PA_OUTPUT = "PA_OUTPUT"
        TX_ANTENNA_CONNECTOR_OR_DECLARED_TAB = "TX_ANTENNA_CONNECTOR_OR_DECLARED_TAB"
        RX_ANTENNA_CONNECTOR_OR_DECLARED_TAB = "RX_ANTENNA_CONNECTOR_OR_DECLARED_TAB"
        LNA_INPUT = "LNA_INPUT"
        LNA_OUTPUT = "LNA_OUTPUT"
        MIXER_OUTPUT = "MIXER_OUTPUT"
        POST_SELECTIVITY_FILTER = "POST_SELECTIVITY_FILTER"
        AGC_INPUT = "AGC_INPUT"
        ADC_INPUT = "ADC_INPUT"
        ADC_OUTPUT = "ADC_OUTPUT"
        SYNCHRONIZED_BASEBAND = "SYNCHRONIZED_BASEBAND"
        EQUALIZED_RE = "EQUALIZED_RE"
    end

    methods(Static)
        function token = validate(value)
            token = upper(strtrim(string(value)));
            if strlength(token) == 0
                error("RF:MissingReferencePlane", ...
                    "An explicit RF reference plane is required.");
            end
            if ~any(token == sixgr.rf.runtime.RFReferencePlane.values())
                error("RF:MissingReferencePlane", ...
                    "Unsupported RF reference plane '%s'.", token);
            end
        end

        function values = values()
            values = [ ...
                "DIGITAL_LAYER_PORT","POST_PRECODER_DIGITAL","DAC_INPUT", ...
                "DAC_OUTPUT","POST_RECONSTRUCTION_FILTER","PA_INPUT", ...
                "PA_OUTPUT","TX_ANTENNA_CONNECTOR_OR_DECLARED_TAB", ...
                "RX_ANTENNA_CONNECTOR_OR_DECLARED_TAB","LNA_INPUT", ...
                "LNA_OUTPUT","MIXER_OUTPUT","POST_SELECTIVITY_FILTER", ...
                "AGC_INPUT","ADC_INPUT","ADC_OUTPUT", ...
                "SYNCHRONIZED_BASEBAND","EQUALIZED_RE"];
        end
    end
end
