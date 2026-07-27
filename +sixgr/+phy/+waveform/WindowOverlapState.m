classdef WindowOverlapState < handle
    %WINDOWOVERLAPSTATE Persistent WOLA overlap tail.
    properties (SetAccess=private)
        Tail
        OverlapSamples double
    end
    methods
        function obj=WindowOverlapState(overlap,ports)
            if nargin<2,ports=1;end
            obj.OverlapSamples=double(overlap);
            obj.Tail=complex(zeros(overlap,ports));
        end
        function tail=take(obj),tail=obj.Tail;end
        function set(obj,tail)
            if size(tail,1)~=obj.OverlapSamples
                error("WAVEFORM:WindowOverlapStateMissing","WOLA tail size changed.");
            end
            obj.Tail=tail;
        end
    end
end
