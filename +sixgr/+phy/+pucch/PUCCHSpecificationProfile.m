classdef PUCCHSpecificationProfile
    %PUCCHSPECIFICATIONPROFILE Release-pinned strict PUCCH specification.

    properties (SetAccess=private)
        Data
        Digest
    end

    methods
        function obj = PUCCHSpecificationProfile(data)
            if nargin == 0
                data = sixgr.phy.pucch.PUCCHSpecificationProfile.release18Data();
            end
            obj.Data = data;
            obj.Digest = sixgr.phy.pucch.PUCCHUtil.hash(data);
        end
    end

    methods (Static)
        function obj = release18()
            obj = sixgr.phy.pucch.PUCCHSpecificationProfile();
        end

        function data = release18Data()
            data = struct( ...
                "ProfileID", "nr_rel18_pucch_strict", ...
                "ResearchClass", "baseline_benchmark", ...
                "TS38211", "V18.8.0", ...
                "TS38212", "V18.8.0", ...
                "TS38213", "V18.8.0", ...
                "TS38214", "V18.8.0", ...
                "TS38331", "V18.8.0", ...
                "MaximumUCIBits", 1706, ...
                "SupportedFormats", [0 1 2 3 4], ...
                "TruthProxyPolicy", "waveform_truth_only_for_physical_trials");
        end
    end
end
