classdef ResourceGridToFFTMap
    %RESOURCEGRIDTOFFTMAP Compatibility name for the canonical mapper.
    methods (Static)
        function map = build(varargin)
            map = sixgr.phy.waveform.SubcarrierMapper.build(varargin{:});
        end
    end
end
