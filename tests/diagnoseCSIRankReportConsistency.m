function T=diagnoseCSIRankReportConsistency()
% Analytical diagnostic, not waveform or scenario qualification. Compare
% rank-selection and reporting engines on IDENTICAL declared H/noise inputs.
% Known matrices below are validation fixtures, never receiver observations.
setup6GRSimToolkit('Verbose',false);
carrier=nrCarrierConfig('NSizeGrid',25,'SubcarrierSpacing',15,'NCellID',17);
rs=nrCSIRSConfig('CSIRSType','nzp','RowNumber',4,'Density','one', ...
    'SymbolLocations',6,'SubcarrierLocations',0,'NumRB',25);
physical=[.8 0 .6 0;0 .6 0 .8];
H=repmat(reshape(physical,1,1,2,4),300,14,1,1);
cqiTables=nrCQITables;
efficiencies=cqiTables.CQITable1.SpectralEfficiency;
rows=struct([]);
for cdmGroups=[1 2]
    dmrs=nrPDSCHDMRSConfig('NumCDMGroupsWithoutData',cdmGroups);
    for snr=[-10 0 10 20 30 40]
        nVar=10^(-snr/10);
        report=nrCSIReportConfig('NSizeBWP',25,'PanelDimensions',[1 2 1], ...
            'CQIFormatIndicator','wideband','PMIFormatIndicator','wideband', ...
            'CodebookType','type1SinglePanel','CodebookMode',1, ...
            'RIRestriction',[1 1 0 0 0 0 0 0]);
        nativeRI=nr5g.internal.nrRISelect(carrier,rs,report,H,nVar,'MaxSE');
        for rank=1:2
            [oldCQI,~,oldInfo]=nr5g.internal.nrCQISelect(carrier,rs,report,rank,H,nVar);
            [newCQI,pmi,newInfo,pinfo]=nr5g.internal.nrCQIReport(carrier,rs,report,dmrs,rank,H,nVar);
            W=pinfo.W(:,:,1); G=physical*W;
            F=(G'*G+nVar*eye(rank))\G'; combined=F*G;
            desired=abs(diag(combined)).^2;
            interlayer=sum(abs(combined-diag(diag(combined))).^2,2);
            noise=nVar*sum(abs(F).^2,2);
            layerSINR=desired./(interlayer+noise);
            direct=10*log10(expm1(mean(log1p(layerSINR))));
            reported=10*log10(expm1(mean(log1p(pinfo.SINRPerREPMI),'all')));
            assert(abs(direct-reported)<1e-8, ...
                'The reporting engine SINR disagrees with explicit receiver powers.');
            row=struct('FixtureSNR_dB',snr,'DMRSCDMGroups',cdmGroups, ...
                'CandidateRank',rank,'NativeSelectedRI',nativeRI, ...
                'RankSelectorCQI',oldCQI(1),'ReportCQI',newCQI(1), ...
                'RankSelectorPredictedBLER',oldInfo.TransportBLER(1), ...
                'ReportPredictedBLER',newInfo.TransportBLER(1), ...
                'RankSelectorEfficiency',score(rank,oldCQI(1),oldInfo.TransportBLER(1),efficiencies), ...
                'ReportEfficiency',score(rank,newCQI(1),newInfo.TransportBLER(1),efficiencies), ...
                'ReportPMI',string(jsonencode(pmi)),'ExplicitMMSESINR_dB',direct, ...
                'ReportSINR_dB',reported,'EvidenceScope',"analytical_fixture_not_PHY_run");
            if isempty(rows), rows=row; else, rows(end+1)=row; end %#ok<AGROW>
        end
    end
end
T=struct2table(rows);
folder=fullfile(pwd,'results','lls','csi_rank_report_consistency', ...
    char(datetime('now','Format','yyyyMMdd_HHmmss_SSS')));
mkdir(folder); writetable(T,fullfile(folder,'diagnostic.csv'));
disp(T(:,{'FixtureSNR_dB','DMRSCDMGroups','CandidateRank','NativeSelectedRI', ...
    'RankSelectorCQI','ReportCQI','RankSelectorEfficiency','ReportEfficiency'}));
fprintf('CSI_RANK_REPORT_DIAGNOSTIC output=%s\n',folder);
end

function value=score(rank,cqi,bler,efficiencies)
if cqi==0, value=0; else, value=rank*efficiencies(cqi+1)*(1-bler); end
end
