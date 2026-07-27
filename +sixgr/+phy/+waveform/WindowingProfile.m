classdef WindowingProfile
    %WINDOWINGPROFILE Immutable rectangular or complementary WOLA profile.
    methods (Static)
        function profile=resolve(profileID,overlapSamples,explicit)
            if nargin<3,explicit=false;end
            profileID=string(profileID); overlapSamples=double(overlapSamples);
            strict=startsWith(profileID,"nr_rel19_");
            if strict && overlapSamples>0
                error("WAVEFORM:WindowingMustBeExplicit", ...
                    "Strict NR profiles use rectangular windowing.");
            end
            if overlapSamples>0 && ~logical(explicit)
                error("WAVEFORM:WindowingMustBeExplicit", ...
                    "Nonzero WOLA requires an explicit research profile.");
            end
            if overlapSamples<0||overlapSamples~=fix(overlapSamples)
                error("WAVEFORM:InvalidOFDMParameters","WOLA overlap is invalid.");
            end
            [rise,fall]=sixgr.phy.waveform.WindowingProfile.coefficients(overlapSamples);
            profile=struct("ProfileID",profileID,"OverlapSamples",overlapSamples, ...
                "Rise",rise,"Fall",fall,"WindowType", ...
                "sqrt_raised_cosine_complementary", ...
                "CoefficientSHA256",sixgr.phy.waveform.WaveformHash.numeric([rise;fall]), ...
                "GroupDelaySamples",overlapSamples/2, ...
                "NormativeClaimAllowed",strict&&overlapSamples==0);
        end
        function [rise,fall]=coefficients(overlap)
            overlap=double(overlap);
            if overlap==0,rise=1;fall=0;return;end
            index=(0:overlap-1).';
            angle=pi*(index+0.5)/(2*overlap);
            rise=sin(angle);fall=cos(angle);
        end
    end
end
