function ok = testRSOverheadPhysicalGridDomain()
%TESTRSOVERHEADPHYSICALGRIDDOMAIN Keep RS overhead in one physical RE domain.

setup6GRSimToolkit("Verbose", false);

acct = struct( ...
    "LayerDataRE", 100, ...
    "ModulationSymbolCount", 200, ...
    "DMRSRE", 20, ...
    "PTRSRE", 5, ...
    "CodedBitCountG", 400);
tx = struct( ...
    "ResourceAccounting", acct, ...
    "PDSCH", struct("Modulation", "QPSK", "NumLayers", 2), ...
    "PDSCHSymbols", complex(zeros(200, 1)), ...
    "Waveform", complex(zeros(0, 1)));

[metrics, ~] = sixgr.link.deriveModulationTrackingMetrics(tx, struct(), struct(), "DL");

expected = (20 + 5) / (100 + 20 + 5);
assert(abs(double(metrics.RSOverheadFraction) - expected) < 1e-12, ...
    "RS overhead must divide unique physical RS RE by unique physical data-plus-RS RE.");
assert(abs(double(metrics.TotalDataRECount) - 200) < 1e-12, ...
    "Layer-domain modulation-symbol accounting must remain independently available.");

% Legacy retained transmitters may have actual indices but no accounting
% struct. Independently request subscript coordinates from MATLAB, rather
% than repeating the DUT's linear-index port-collapse calculation.
cases=0; sharedCDMSeen=false;
for nPRB=[25 273]
    carrier=nrCarrierConfig('NSizeGrid',nPRB,'NStartGrid',8,'SubcarrierSpacing',30);
    for direction=["DL","UL"]
        for layers=1:4
            for ptrs=[false true]
                if direction=="DL", channel=nrPDSCHConfig; else, channel=nrPUSCHConfig; end
                channel.NStartBWP=11; channel.NSizeBWP=nPRB-6;
                channel.PRBSet=0:channel.NSizeBWP-1;
                channel.Modulation='64QAM'; channel.NumLayers=layers;
                channel.DMRS.DMRSAdditionalPosition=1;
                channel.EnablePTRS=ptrs;
                [actual,recorded,expected]=localCheckIndices(carrier,channel,direction);
                assert(actual.DMRSRECount==expected(2) && actual.PTRSRECount==expected(3));
                sharedCDMSeen=sharedCDMSeen || numel(recorded.DMRSIndices)>expected(2);
                cases=cases+1;
            end
        end
    end
    % A one-layer/two-port UL map is not twice the layer-domain data count.
    channel=nrPUSCHConfig('NumLayers',1,'TransmissionScheme','codebook', ...
        'NumAntennaPorts',2,'TPMI',0,'Modulation','64QAM','PRBSet',0:23);
    [actual,recorded]=localCheckIndices(carrier,channel,"UL");
    assert(numel(recorded.PUSCHIndices)>actual.TotalDataRECount);
    cases=cases+1;
    for ptrs=[false true]
        channel=nrPUSCHConfig('NumLayers',1,'TransformPrecoding',true, ...
            'Modulation','64QAM','PRBSet',0:23,'EnablePTRS',ptrs);
        localCheckIndices(carrier,channel,"UL");
        cases=cases+1;
    end
    for hopping=["neither","intraSlot"]
        channel=nrPUSCHConfig('NumLayers',1,'TransformPrecoding',true, ...
            'TransmissionScheme','codebook','NumAntennaPorts',2,'TPMI',1, ...
            'Modulation','64QAM','NStartBWP',10,'NSizeBWP',nPRB-4, ...
            'PRBSet',2:7,'MappingType','B','SymbolAllocation',[4 8], ...
            'EnablePTRS',true,'FrequencyHopping',char(hopping),'SecondHopStartPRB',10);
        channel.DMRS.DMRSAdditionalPosition=1;
        localCheckIndices(carrier,channel,"UL");
        cases=cases+1;
    end
end
assert(sharedCDMSeen,'Exercise shared time/frequency resources on different DM-RS ports.');

missing=rmfield(recorded,'Carrier');
actual=sixgr.link.deriveModulationTrackingMetrics(missing,struct(),struct(),"UL");
assert(isnan(actual.RSOverheadFraction) && isnan(actual.DMRSRECount), ...
    'Missing grid dimensions must not be replaced with a guessed physical RE count.');
missing=rmfield(recorded,'DMRSIndices');
actual=sixgr.link.deriveModulationTrackingMetrics(missing,struct(),struct(),"UL");
assert(isnan(actual.RSOverheadFraction) && isnan(actual.DMRSRECount) && ...
    isfinite(actual.DataRECount), 'Missing pilot evidence is not zero pilot occupancy.');
broken=recorded; broken.DMRSIndices(1)=0;
caught=false;
try, sixgr.link.deriveModulationTrackingMetrics(broken,struct(),struct(),"UL");
catch ex, caught=strcmp(ex.identifier,'sixgr:link:InvalidResourceObservation'); end
assert(caught,'Malformed recorded indices must not be silently wrapped into the grid.');

fprintf('RS_OVERHEAD_PHYSICAL_GRID_PASS native_cases=%d DL_UL_ranks_1_to_4=1 codebook_ports_and_DFT_PTRS=1\n',cases);
ok = true;
end

function [metrics,tx,counts]=localCheckIndices(carrier,channel,direction)
if direction=="DL", prefix="PDSCH"; else, prefix="PUSCH"; end
indices=str2func("nr"+prefix+"Indices");
dmrs=str2func("nr"+prefix+"DMRSIndices");
ptrs=str2func("nr"+prefix+"PTRSIndices");
[data,info]=indices(carrier,channel);
tx=struct('Carrier',carrier,'DMRSIndices',dmrs(carrier,channel), ...
    'PTRSIndices',ptrs(carrier,channel));
if direction=="UL" && channel.TransformPrecoding
    % Production binds the extra nrPUSCH output to its existing transformed
    % allocation. Neither native linear nor subscript PT-RS indices are
    % carrier-grid coordinates in this mode.
    tx.PTRSIndices=sixgr.phy.resource.puschPTRSGridIndices(carrier,channel);
end
tx.(prefix)=channel; tx.(prefix+"Indices")=data;
% An obsolete bootstrap modulation must not override the actual TX object.
cfg=struct('phy',struct('pdsch',struct('modulation','QPSK')));
metrics=sixgr.link.deriveModulationTrackingMetrics(tx,struct(),cfg,direction);
dmrsSub=dmrs(carrier,channel,'IndexStyle','subscript');
ptrsSub=ptrs(carrier,channel,'IndexStyle','subscript');
if direction=="UL" && channel.TransformPrecoding && ~isempty(ptrsSub)
    % Independent grid-coordinate check: form native allocation subscript
    % rows, then select by the pre-transform sequence row positions. This
    % is dimensional overhead, not isolated post-DFT pilot energy.
    allocationSub=indices(carrier,channel,'IndexStyle','subscript');
    relative=ptrs(carrier,channel);
    ptrsSub=[]; expectedLinear=zeros(size(relative,1),size(data,2));
    for port=1:size(data,2)
        portSub=allocationSub(allocationSub(:,3)==port,:);
        selected=double(portSub(double(relative(:,1)),:));
        ptrsSub=[ptrsSub;selected]; %#ok<AGROW>
        expectedLinear(:,port)=sub2ind([12*carrier.NSizeGrid,carrier.SymbolsPerSlot,size(data,2)], ...
            selected(:,1),selected(:,2),selected(:,3));
    end
    assert(isequal(double(tx.PTRSIndices),expectedLinear));
    assert(isequal(sixgr.phy.resource.puschPTRSGridIndices(carrier,channel,'IndexBase','0based'), ...
        expectedLinear-1));
    [nativeSymbols,nativePTRS]=nrPUSCH(carrier,channel,zeros(info.G,1));
    assert(isequal(nativeSymbols(double(relative(:,1)),:),nativePTRS), ...
        'Additional native PT-RS output is a subset of the already transformed allocation.');
    csi=reshape(linspace(0.1,0.9,size(data,1)*channel.NumLayers), ...
        size(data,1),channel.NumLayers);
    [mapped,mapping]=sixgr.phy.ul.puschDemapperCSI( ...
        csi,carrier,channel,[info.Gd channel.NumLayers]);
    msc=12*numel(channel.PRBSet);
    reference=nrTransformDeprecode(csi,numel(channel.PRBSet))/sqrt(msc);
    reference=repelem(real(reference(1:msc:end,:)),msc,1);
    reference(relative)=[];
    assert(max(abs(mapped(:)-reference(:)))<1e-12 && ...
        mapping.PTRSSamplesRemoved==numel(relative) && ...
        mapping.InputCount-mapping.OutputCount==numel(relative));
    caught=false;
    try
        sixgr.phy.ul.puschDemapperCSI(csi,carrier,channel,[info.Gd+1 channel.NumLayers]);
    catch ex
        caught=strcmp(ex.identifier,'sixgr:phy:ul:PUSCHCSIDemapperShapeMismatch');
    end
    assert(caught,'CSI length mismatches must fail rather than truncate or pad weights.');
end
counts=[double(info.Gd),localCountCoordinates(dmrsSub),localCountCoordinates(ptrsSub)];
assert(metrics.ModulationOrderQm==6 && metrics.DataRECount==counts(1) && ...
    metrics.DataRECountPerLayer==counts(1) && ...
    metrics.TotalDataRECount==counts(1)*channel.NumLayers && ...
    metrics.ComputedE_TS38212==sum(double(info.G)));
assert(metrics.DMRSRECount==counts(2) && metrics.PTRSRECount==counts(3) && ...
    abs(metrics.RSOverheadFraction-sum(counts(2:3))/sum(counts))<1e-12);
end

function count=localCountCoordinates(indices)
count=0;
if ~isempty(indices), count=size(unique(double(indices(:,1:2)),'rows'),1); end
end
