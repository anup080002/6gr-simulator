classdef RLCEntityFactory
    %RLCENTITYFACTORY Create strict bounded RLC entities from bearer config.
    methods (Static)
        function entity=create(config)
            mode=upper(string(config.Mode));
            switch mode
                case "AM"
                    entity=sixgr.l2.rlc18.RLCAMEntity(config);
                case "UM"
                    entity=sixgr.l2.rlc18.RLCUMEntity(config);
                case "TM"
                    entity=sixgr.l2.rlc18.RLCTMEntity(config);
                otherwise
                    error("sixgr:protocol:UnsupportedCapability", ...
                        "Unsupported RLC mode %s.",mode);
            end
        end
    end
end
