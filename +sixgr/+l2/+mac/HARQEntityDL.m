classdef HARQEntityDL < sixgr.l2.mac.HARQEntity
    %HARQENTITYDL Direction-specific live DL HARQ compatibility façade.
    methods
        function obj=HARQEntityDL(cfg,varargin)
            obj@sixgr.l2.mac.HARQEntity(cfg,"Direction","DL",varargin{:});
        end
    end
end
