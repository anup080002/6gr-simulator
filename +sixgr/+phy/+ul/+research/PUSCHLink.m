classdef PUSCHLink
    %PUSCHLINK Explicit research UL entry point; standard PUSCH is unchanged.
    methods (Static)
        function a=allocation(scfg,slot)
            a=sixgr.phy.research.SharedChannelLink.allocation(scfg,slot,"UL");
        end
        function tx=transmit(scfg,slot,tb)
            tx=sixgr.phy.research.SharedChannelLink.transmit(scfg,slot,tb,"UL");
        end
        function rx=receive(scfg,slot,waveform)
            rx=sixgr.phy.research.SharedChannelLink.receive(scfg,slot,waveform,"UL");
        end
    end
end
