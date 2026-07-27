classdef TransformPrecodingPlan
    %TRANSFORMPRECODINGPLAN Decoded-assignment-owned DFT-s-OFDM plan.
    properties (SetAccess=immutable)
        ProfileID string
        LayerCount double
        M double
        PRBCount double
        Contiguous logical
        ConfigurationEpoch double
        Modulation string
        Strict logical
    end
    methods
        function obj=TransformPrecodingPlan(assignment,profileID)
            if ~isstruct(assignment) || ...
                    ~logical(sixgr.util.structGet(assignment,"Decoded",false))
                error("WAVEFORM:TransformPrecodingOwnership", ...
                    "Transform precoding requires a decoded scheduling assignment.");
            end
            obj.ProfileID=string(profileID);
            obj.Strict=obj.ProfileID=="nr_rel19_ul_dfts_ofdm_strict";
            obj.LayerCount=double(sixgr.util.structGet(assignment,"LayerCount",NaN));
            obj.PRBCount=double(sixgr.util.structGet(assignment,"PRBCount",NaN));
            obj.M=12*obj.PRBCount;
            obj.Contiguous=logical(sixgr.util.structGet(assignment,"Contiguous",false));
            obj.ConfigurationEpoch=double(sixgr.util.structGet(assignment,"ConfigurationEpoch",NaN));
            current=double(sixgr.util.structGet(assignment,"CurrentConfigurationEpoch",NaN));
            obj.Modulation=upper(string(sixgr.util.structGet(assignment,"Modulation","")));
            if obj.Strict && obj.LayerCount~=1
                error("WAVEFORM:TransformPrecodingLayerCount", ...
                    "Strict Release-19 transform precoding requires one layer.");
            end
            if obj.Strict && ~obj.Contiguous
                error("WAVEFORM:NoncontiguousTransformAllocation", ...
                    "Strict transform precoding requires a contiguous allocation.");
            end
            if ~isfinite(obj.ConfigurationEpoch) || obj.ConfigurationEpoch~=current || ...
                    ~logical(sixgr.util.structGet(assignment,"PTRSSymbolPartitionExact",false))
                error("WAVEFORM:TransformPrecodingOwnership", ...
                    "Assignment epoch or PT-RS symbol partition is stale.");
            end
            supported=["PI/2-BPSK","PI2-BPSK","QPSK","16QAM","64QAM","256QAM"];
            if ~ismember(obj.Modulation,supported)
                error("WAVEFORM:UnsupportedModulation", ...
                    "Modulation '%s' is outside the selected profile.",obj.Modulation);
            end
            if obj.Strict && ~sixgr.phy.waveform.TransformPrecodingPlan.isValidDFTSize(obj.M)
                error("WAVEFORM:InvalidDFTSize", ...
                    "Strict DFT size M=%d has a prime factor outside 2, 3 and 5.",obj.M);
            end
        end
    end
    methods (Static)
        function tf=isValidDFTSize(m)
            m=double(m);
            if ~isscalar(m)||~isfinite(m)||m<1||m~=fix(m),tf=false;return;end
            q=m;
            for p=[2 3 5]
                while mod(q,p)==0,q=q/p;end
            end
            tf=q==1;
        end
    end
end
