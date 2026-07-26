classdef CalibrationProfileKey
    %CALIBRATIONPROFILEKEY Complete CQI/MCS/effective-SINR profile identity.

    methods (Static)
        function [key,digest] = create(value)
            required = ["Direction","Waveform","MCSTable","Receiver", ...
                "Channel","Rank","SCSkHz","NRB","DMRSProfile", ...
                "PTRSProfile","TargetBLER","ImplementationVersion"];
            for field = required
                if ~isfield(value,char(field))
                    error("RSLA:InvalidCalibrationProvenance", ...
                        "Calibration key is missing %s.",field);
                end
            end
            key = orderfields(value);
            digest = sixgr.phy.rsla.RSLAUtil.hash(key);
        end
    end
end
