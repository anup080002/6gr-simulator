classdef PDCCHBlindSearchEngine
    %PDCCHBLINDSEARCHENGINE Canonical strict receiver facade.

    methods (Static)
        function result = search(rxWaveform, strictCfg, varargin)
            result = sixgr.phy.pdcch.PDCCHReceiver.receive( ...
                rxWaveform, strictCfg, varargin{:});
        end
    end
end
