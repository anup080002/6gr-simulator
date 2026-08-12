function [summary,trials]=runPDSCHProfileSweep(cfg,stress)
%RUNPDSCHPROFILESWEEP Coded production PDSCH sweep with W0-W3 reservations.
[llsCfg,provenance]=sixgr.lls.loadConfig(string(cfg.fullPHYAnchor.configPath));
llsCfg.isac.enabled=false;
llsCfg.simulation.snrDb=double(stress.pdschSNRDb(:).');
jointCarrier=cfg.carrier.profiles.(cfg.carrier.activeProfile);
llsCfg.scenario.id=char(string(cfg.study.id)+"_shared_pdsch_"+string(cfg.carrier.activeProfile));
llsCfg.scenario.description=char("10.8.3 shared-resource production PDSCH on executed joint carrier "+ ...
    string(cfg.carrier.activeProfile));
llsCfg.carrier.frequencyHz=double(jointCarrier.frequencyHz);
llsCfg.carrier.bandwidthMHz=double(jointCarrier.channelBandwidthHz)/1e6;
llsCfg.carrier.subcarrierSpacingKHz=double(jointCarrier.subcarrierSpacingKHz);
llsCfg.carrier.nSizeGrid=double(jointCarrier.nSizeGrid);
llsCfg.carrier.nStartGrid=double(jointCarrier.nStartGrid);
llsCfg.carrier.nCellId=double(jointCarrier.nCellID);
shared=cfg.fullPHYAnchor.sharedResourceAllocation;
llsCfg.allocation.startPRB=double(shared.startPRB);
llsCfg.allocation.numberPRB=double(shared.numberPRB);
llsCfg.allocation.symbols=double(shared.symbols(:).');
effectiveConfigHash=string(sixgr.util.sha256Hex(uint8(unicode2native( ...
    jsonencode(llsCfg),"UTF-8"))));
if isfield(stress,"pdschTransportBlocksPerPoint")
    minTB=double(stress.pdschTransportBlocksPerPoint); maxTB=minTB; minErrors=maxTB+1;
else
    minTB=1; maxTB=double(stress.pdschMaximumTransportBlocks);
    minErrors=double(stress.pdschMinimumBlockErrors);
end
profiles=["W0";"W1-A";"W1-B";"W2";"W3"];
ids=["W0";"W1";"W1";"W2";"W3"];
variants=["default";"per_occasion";"reset_aligned_interval";"default";"default"];
summaryParts=cell(numel(profiles)*numel(llsCfg.simulation.snrDb),1);
trialParts=cell(size(summaryParts)); index=0;
for p=1:numel(profiles)
    for s=1:numel(llsCfg.simulation.snrDb)
        phy=sixgr.lls.buildPHYConfig(llsCfg,double(llsCfg.simulation.snrDb(s)));
        [carrier,~]=sixgr.phy.grid.makeCarrier(phy);
        rows=cell(maxTB,1); errors=0; n=0;
        while n<maxTB && ~(n>=minTB&&errors>=minErrors)
            n=n+1;
            reference=sixgr.isac.buildReferenceGrid(cfg,carrier,ids(p), ...
                double(cfg.run.masterSeed)+n,4,variants(p));
            [row,~]=sixgr.lls.runPDSCHTransportBlock(llsCfg,phy, ...
                effectiveConfigHash,s,n,"CaptureDiagnostic",false, ...
                "ISACReferenceGrid",reference.Grid);
            row.WaveformProfile=profiles(p);
            row.JointISACConfigSHA256=string(cfg.provenance.SourceSHA256);
            row.FullPHYAnchorConfigSHA256=string(provenance.ConfigSHA256);
            row.ExecutedCarrierProfile=string(cfg.carrier.activeProfile);
            row.ExecutedFrequencyHz=double(jointCarrier.frequencyHz);
            row.ExecutedBandwidthHz=double(jointCarrier.channelBandwidthHz);
            row.ExecutedSubcarrierSpacingKHz=double(jointCarrier.subcarrierSpacingKHz);
            row.ExecutedNSizeGrid=double(jointCarrier.nSizeGrid);
            row.SharedResourcePolicy=string(shared.policy);
            row.SharedAllocationStartPRB=double(shared.startPRB);
            row.SharedAllocationNumberPRB=double(shared.numberPRB);
            row.SharedAllocationSymbols=string(mat2str(double(shared.symbols(:).')));
            rows{n}=struct2table(row); errors=errors+row.CRCError;
        end
        tableRows=vertcat(rows{1:n}); index=index+1; trialParts{index}=tableRows;
        bits=sum(tableRows.TransportBlockSizeBits); bitErrors=sum(tableRows.BitErrors);
        [ciLow,ciHigh]=sixgr.lls.stats.wilsonInterval(errors,n,.95);
        slotDuration=1e-3/(double(llsCfg.carrier.subcarrierSpacingKHz)/15);
        goodput=sum(tableRows.TransportBlockSizeBits(~tableRows.CRCError))/(n*slotDuration);
        meanEVM=mean(tableRows.EqualizedSymbolEVMRMS,"omitnan");
        qualified=(errors>=100||n>=10000);
        summaryParts{index}=table(profiles(p),double(llsCfg.simulation.snrDb(s)),n,errors, ...
            errors/n,ciLow,ciHigh,bits,bitErrors,bitErrors/max(bits,1),goodput, ...
            meanEVM,qualified,string(stress.evidenceClass), ...
            'VariableNames',{'WaveformProfile','SNRdB','TransportBlocks','BlockErrors', ...
            'BLER','BLERCILow','BLERCIHigh','Bits','BitErrors','BER','GoodputBps','EVMRMS', ...
            'PublicationStoppingRuleSatisfied','EvidenceClass'});
    end
end
summary=vertcat(summaryParts{1:index}); trials=vertcat(trialParts{1:index});
end
