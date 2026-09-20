function [data,ack,csi1,csi2]=demultiplexUCIStreams(pusch,tcr,tbs,oack,ocsi1,ocsi2,llr)
% Preserve the native path; the research adapter never masquerades as nrPUSCHConfig.
if isa(pusch,'nrPUSCHConfig')
    [data,ack,csi1,csi2]=nrULSCHDemultiplex(pusch,tcr,tbs,oack,ocsi1,ocsi2,llr);
else
    assert(isa(pusch,'sixgr.phy.research.PUSCHUCIResourceAdapter') && isscalar(pusch), ...
        'sixgr:pusch:InvalidPUSCHConfiguration','Use a native configuration or the explicit research adapter.');
    if iscell(llr)
        assert(isscalar(llr),'sixgr:research:UnsupportedUCIGeometry','Research adapter supports one codeword.');
        llr=llr{1};
    end
    plan=pusch.resourcePlan(tcr,tbs,[oack ocsi1 ocsi2]);
    [data,ack,csi1,csi2]=sixgr.phy.research.PUSCHUCIResourceAdapter.demultiplex(plan,llr);
end
end
