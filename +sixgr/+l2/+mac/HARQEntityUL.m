classdef HARQEntityUL < sixgr.l2.mac.HARQEntity
    %HARQENTITYUL Direction-specific live UL HARQ compatibility façade.
    methods
        function obj=HARQEntityUL(cfg,varargin)
            obj@sixgr.l2.mac.HARQEntity(cfg,"Direction","UL",varargin{:});
        end
    end
end
