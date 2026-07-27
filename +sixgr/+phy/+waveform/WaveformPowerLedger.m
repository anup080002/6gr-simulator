classdef WaveformPowerLedger < handle
    %WAVEFORMPOWERLEDGER Explicit per-stage energy and power records.
    properties (SetAccess=private)
        Rows table
    end
    methods
        function obj=WaveformPowerLedger()
            obj.Rows=table('Size',[0 8], ...
                'VariableTypes',{'string','string','string','double','double','double','double','string'}, ...
                'VariableNames',{'CaseID','Stage','ReferenceDomain','Energy', ...
                'AveragePower','ExpectedPower','Error_dB','Status'});
        end
        function add(obj,caseID,stage,domain,samples,expectedPower)
            energy=sum(abs(double(samples(:))).^2);
            power=energy/max(1,numel(samples));
            errorDB=10*log10(max(power,realmin)/max(double(expectedPower),realmin));
            status="PASS";
            if abs(errorDB)>0.01,status="FAIL";end
            obj.Rows(end+1,:)={string(caseID),string(stage),string(domain), ...
                energy,power,double(expectedPower),errorDB,status};
        end
        function requireClosed(obj)
            if any(abs(obj.Rows.Error_dB)>0.01)
                error("WAVEFORM:PowerLedgerMismatch", ...
                    "At least one waveform power stage exceeds 0.01 dB.");
            end
        end
    end
end
