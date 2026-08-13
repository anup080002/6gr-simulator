classdef JointSIB1Study
    %JOINTSIB1STUDY Joint-success arithmetic over separately qualified links.

    methods (Static)
        function T=combine(pdcchTable,pdschTable)
            required=["SNRdB","Trials","Errors"];
            if ~all(ismember(required,string(pdcchTable.Properties.VariableNames)))|| ...
                    ~all(ismember(required,string(pdschTable.Properties.VariableNames)))
                error("sixgr:bwop:MissingCalibratedJointInput", ...
                    "Joint SIB1 evidence requires measured PDCCH/PDSCH trials and errors at common SNR points.");
            end
            [snr,ia,ib]=intersect(double(pdcchTable.SNRdB),double(pdschTable.SNRdB));
            if isempty(snr)
                error("sixgr:bwop:NoCommonSNRPoints", ...
                    "PDCCH and PDSCH evidence has no common measured SNR point.");
            end
            pControl=1-double(pdcchTable.Errors(ia))./double(pdcchTable.Trials(ia));
            pData=1-double(pdschTable.Errors(ib))./double(pdschTable.Trials(ib));
            jointBLER=1-pControl.*pData;
            T=table(snr,pControl,pData,jointBLER, ...
                repmat("CALIBRATED_LLS",numel(snr),1), ...
                'VariableNames',{'SNRdB','PDCCHSuccessProbability', ...
                'ConditionalPDSCHSuccessProbability','JointAcquisitionBLER','EvidenceClass'});
        end
    end
end
