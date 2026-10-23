function [ok,evidence] = testPDSCHReferenceCoordinateAuthority()
%TESTPDSCHREFERENCECOORDINATEAUTHORITY Declared RS-only native comparison.
% TS 38.211 V18.8.0 7.4.1.1.2 and 7.4.1.2; native R2026a comparison.
% PRB0 is an explicitly declared PHY reference component here, NOT proof of
% CORESET0/Type0 CSS/SI-RNTI procedure delivery. No waveform/RX/RF executes.
setup6GRSimToolkit('Verbose',false,'RunToolboxChecks',false);
checks = table(strings(0,1),false(0,1),strings(0,1), ...
    'VariableNames',{'Case','Passed','Detail'});
observations = {};
fixture = StrictPDSCHChainFixture.create(2,'NPRB',12,'UsePTRS',true);
for configType=1:2
    for point=["CRB0","PRB0"]
        for carrierStart=[0 5]
            for bwpOffset=[0 2]
                name=sprintf('type%d_%s_carrier%d_bwp%d', ...
                    configType,point,carrierStart,bwpOffset);
                record(name,@()positive(configType,point,carrierStart,bwpOffset,false));
            end
        end
        record(sprintf('enhanced_type%d_%s_odd_origin',configType,point), ...
            @()positive(configType,point,5,2,true));
    end
end
record('legacy_default_CRB0_and_explicit_native_inheritance',@defaults);
record('reference_metadata_and_coordinate_negatives',@negatives);
record('zero_origin_old_oracle_counterexample_not_relabelled',@counterexample);
evidence=struct('Checks',checks,'Observations',{observations}, ...
    'ReceiverExecuted',false,'WaveformExecuted',false,'RFExecuted',false, ...
    'ControlProcedureQualified',false);
for k=find(~checks.Passed).'
    fprintf(2,'PDSCH_REFERENCE_COORDINATE %s FAIL %s\n',checks.Case(k),checks.Detail(k));
end
assert(all(checks.Passed),'test:PDSCHReferenceCoordinateAuthority:Failed', ...
    '%d/%d coordinate checks failed.',nnz(~checks.Passed),height(checks));
ok=true;
fprintf('PDSCH_REFERENCE_COORDINATE_PASS cases=%d waveform=0 control_procedure=0\n',height(checks));

    function record(name,fn)
        try
            fn(); passed=true; detail="";
        catch err
            passed=false; detail=string(getReport(err,'extended','hyperlinks','off'));
        end
        checks(end+1,:)={string(name),passed,detail};
    end

    function positive(configType,point,carrierStart,bwpOffset,enhanced)
        [a,c,r,p,native]=make(configType,point,carrierStart,bwpOffset,enhanced);
        beforeA=a.toStruct(); beforeR=r.toStruct();
        g=sixgr.pdsch.PDSCHReferenceSignalGenerator.generate(a,p,c,r);
        assert(isequaln(a.toStruct(),beforeA) && isequaln(r.toStruct(),beforeR));
        expectedPRBs=double(a.get('PRBSetBWPRelative'));
        if point=="CRB0", expectedPRBs=expectedPRBs+carrierStart+bwpOffset; end
        assert(isequal(g.SequenceReference.PRBSetReferenceRelative,expectedPRBs));
        assert(g.DMRSSequenceNMSE<=1e-24 && g.PTRSSequenceNMSE<=1e-24);
        dmrs=nrPDSCHDMRS(c,native); ptrs=nrPDSCHPTRS(c,native);
        assert(isequal([g.DMRSSymbolsPerPort{:}],dmrs));
        assert(isequal(g.PTRSSymbolsPerPort{1},ptrs));
        assert(~isempty(ptrs) && ~g.SequenceReference.ControlProcedureQualified);
        % Native subscripts retain the grid origin even when sequence origin
        % differs. No reference offset may leak into actual RE placement.
        subs=double(nrPDSCHDMRSIndices(c,native,'IndexStyle','subscript','IndexBase','0based'));
        ports=double(a.get('DMRSPortSet'));
        for layer=1:numel(ports)
            rows=subs(:,3)==layer-1;
            indices=subs(rows,1)+12*c.NSizeGrid*subs(rows,2);
            assert(isequal(double(g.DMRSIndicesPerPort{layer}(:)),indices(:)));
        end
        observations{end+1}=struct('SequenceReference',g.SequenceReference, ...
            'Type',configType,'Enhanced',enhanced, ...
            'DMRSCount',numel(dmrs),'PTRSCount',numel(ptrs));
    end

    function defaults()
        [a,c,r,~,native]=make(1,"CRB0",5,0,false);
        d=r.toStruct(); d=rmfield(d,{'NStartBWP','NSizeBWP','DMRSReferencePoint'});
        r0=sixgr.pdsch.PDSCHReferenceSignalConfig(d);
        x=sixgr.pdsch.PDSCHReferenceSignalGenerator.resolveIndices(a,c,r0);
        assert(x.SequenceReference.ReferenceRBOffset==5);
        assert(string(x.MaterializedPDSCH.DMRS.DMRSReferencePoint)=="CRB0");
        d.NStartBWP=[]; d.NSizeBWP=[];
        r1=sixgr.pdsch.PDSCHReferenceSignalConfig(d);
        y=sixgr.pdsch.PDSCHReferenceSignalGenerator.resolveIndices(a,c,r1);
        assert(isequal(x.DMRSIndicesPerPort,y.DMRSIndicesPerPort));
        assert(isequal(nrPDSCHDMRS(c,x.MaterializedPDSCH),nrPDSCHDMRS(c,native)));
    end

    function negatives()
        [a,c,r,~,~]=make(1,"PRB0",5,2,false);
        d=r.toStruct(); d.DMRSReferencePoint="bad";
        reject(@()sixgr.pdsch.PDSCHReferenceSignalConfig(d), ...
            "sixgr:pdsch:InvalidDMRSReferencePoint");
        d=r.toStruct(); d=rmfield(d,'NSizeBWP');
        reject(@()sixgr.pdsch.PDSCHReferenceSignalConfig(d), ...
            "sixgr:pdsch:IncompleteReferenceBWP");
        for value={NaN,-1,.5,[1 2]}
            d=r.toStruct(); d.NStartBWP=value{1};
            reject(@()sixgr.pdsch.PDSCHReferenceSignalConfig(d), ...
                "sixgr:pdsch:InvalidReferenceBWP");
        end
        d=r.toStruct(); d.NStartBWP=d.NStartBWP+1;
        bad=sixgr.pdsch.PDSCHReferenceSignalConfig(d);
        reject(@()sixgr.pdsch.PDSCHReferenceSignalGenerator.resolveIndices(a,c,bad), ...
            "sixgr:pdsch:ReferencePRBCoordinateMismatch");
        d=r.toStruct(); d=rmfield(d,{'NStartBWP','NSizeBWP'});
        bad=sixgr.pdsch.PDSCHReferenceSignalConfig(d);
        reject(@()sixgr.pdsch.PDSCHReferenceSignalGenerator.resolveIndices(a,c,bad), ...
            "sixgr:pdsch:ReferencePRBCoordinateMismatch");
        q=oracleRequest(a,c,r);
        for value={NaN,Inf,.5,[1 2],-100}
            q.ReferenceRBOffset=value{1};
            reject(@()sixgr.pdsch.oracle.DMRSSequenceSpec.generate(q), ...
                "sixgr:pdsch:oracle:InvalidDMRSSequenceField");
        end
        ri=sixgr.pdsch.PDSCHReferenceSignalGenerator.resolveIndices(a,c,r);
        ptrs=struct('Indices0Based',ri.PTRSIndicesPerPort{1}, ...
            'GridNumPRB',c.NSizeGrid,'PRBSet',a.get('PRBSetCarrierRelative'), ...
            'DMRSConfigurationType',1,'AssociatedDMRSPort',0, ...
            'NIDNSCID',r.get('NIDNSCID'),'NSCID',r.get('NSCID'), ...
            'ReferenceDMRSSymbol',ri.DMRSSymbolPositions(1), ...
            'SlotNumber',c.NSlot,'SymbolsPerSlot',c.SymbolsPerSlot);
        for value={NaN,Inf,.5,[1 2],-100}
            ptrs.ReferenceRBOffset=value{1};
            reject(@()sixgr.pdsch.oracle.PTRSSequenceSpec.generate(ptrs), ...
                "sixgr:pdsch:oracle:InvalidPTRSSequenceField");
        end
    end

    function counterexample()
        [a,c,r,~,native]=make(1,"CRB0",5,0,false);
        q=oracleRequest(a,c,r); old=sixgr.pdsch.oracle.DMRSSequenceSpec.generate(q);
        actual=nrPDSCHDMRS(c,native);
        assert(sum(abs(actual-old.Sequence).^2,'all')>0, ...
            'Old carrier-relative sequence must reproduce a real mismatch.');
        q.ReferenceRBOffset=5;
        fixed=sixgr.pdsch.oracle.DMRSSequenceSpec.generate(q);
        assert(isequal(actual,fixed.Sequence));
    end

    function [a,c,r,p,native]=make(configType,point,carrierStart,bwpOffset,enhanced)
        c=fixture.Carrier; c.NStartGrid=carrierStart;
        d=fixture.Assignment.toStruct();
        d.PRBSetBWPRelative=[0 2 3]; d.PRBSetCarrierRelative=[0 2 3]+bwpOffset;
        d.AssignmentId=d.AssignmentId+"_declared_RS_reference_component";
        if enhanced, d.DMRSPortSet=[0 8+4*(configType==2)]; end
        a=sixgr.pdsch.PDSCHSchedulingAssignment(d);
        rd=fixture.ReferenceConfig.toStruct(); rd.DMRSConfigurationType=configType;
        rd.DMRSAdditionalPosition=1; rd.DMRSReferencePoint=point;
        rd.NStartBWP=carrierStart+bwpOffset; rd.NSizeBWP=6;
        if enhanced, rd.DMRSMultiplexing="enhanced"; end
        r=sixgr.pdsch.PDSCHReferenceSignalConfig(rd);
        ri=sixgr.pdsch.PDSCHReferenceSignalGenerator.resolveIndices(a,c,r);
        % Independent native object uses the original BWP-relative request;
        % it is not copied back from the production materializer.
        native=nrPDSCHConfig; native.NSizeBWP=6; native.NStartBWP=rd.NStartBWP;
        native.PRBSet=d.PRBSetBWPRelative; native.SymbolAllocation=d.SymbolAllocation;
        native.NumLayers=2; native.NID=rd.NID; native.RNTI=d.RNTI;
        native.DMRS.DMRSConfigurationType=configType;
        native.DMRS.DMRSAdditionalPosition=1; native.DMRS.DMRSLength=1;
        native.DMRS.DMRSTypeAPosition=2; native.DMRS.NumCDMGroupsWithoutData=1;
        native.DMRS.DMRSPortSet=d.DMRSPortSet; native.DMRS.NIDNSCID=rd.NIDNSCID;
        native.DMRS.NSCID=rd.NSCID; native.DMRS.DMRSReferencePoint=char(point);
        native.DMRS.DMRSEnhancedR18=enhanced;
        native.EnablePTRS=true; native.PTRS.TimeDensity=rd.PTRSTimeDensity;
        native.PTRS.FrequencyDensity=rd.PTRSFrequencyDensity;
        native.PTRS.REOffset=char(rd.PTRSREOffset); native.PTRS.PTRSPortSet=0;
        [k,l]=ndgrid(reshape(12*d.PRBSetCarrierRelative+(0:11).',1,[]),0:13);
        ownership=sixgr.pdsch.PDSCHResourceOwnershipMap(sort(k(:)+144*l(:)).',struct());
        context=struct('PRBSet',d.PRBSetCarrierRelative,'SymbolAllocation',[0 14], ...
            'GridNumPRB',12,'GridSymbolsPerSlot',14,'BWPStartPRB',bwpOffset, ...
            'AbsoluteSlot',0,'UnavailableIndices',zeros(1,0), ...
            'DMRSIndicesPerPort',{ri.DMRSIndicesPerPort}, ...
            'PTRSIndicesPerPort',{ri.PTRSIndicesPerPort}, ...
            'DMRSLogicalPortSet',ri.DMRSLogicalPortSet,'PTRSLogicalPortSet',ri.PTRSLogicalPortSet, ...
            'LayerCountPerCodeword',2,'QmPerCodeword',2,'CodeBlockCountPerCodeword',1, ...
            'ReferenceConfigurationDigest',r.ConfigurationDigest);
        p=sixgr.pdsch.PDSCHResourcePlan(ownership,context);
    end
end

function q=oracleRequest(a,c,r)
d=r.toStruct();
symbols=sixgr.pdsch.PDSCHDMRSValidator.resolveSymbolPositions( ...
    a.get('MappingType'),d.DMRSLength,0,14,d.DMRSTypeAPosition,d.DMRSAdditionalPosition);
q=struct('DMRSConfigurationType',d.DMRSConfigurationType,'DMRSLength',d.DMRSLength, ...
    'DMRSPortSet',a.get('DMRSPortSet'),'DMRSSymbols',symbols, ...
    'PRBSet',a.get('PRBSetCarrierRelative'),'NIDNSCID',d.NIDNSCID, ...
    'NSCID',d.NSCID,'SlotNumber',c.NSlot,'SymbolsPerSlot',c.SymbolsPerSlot);
end

function reject(fn,id)
try
    fn();
catch err
    assert(string(err.identifier)==id,'test:PDSCHReferenceCoordinateAuthority:WrongError', ...
        'Expected %s, observed %s: %s',id,string(err.identifier),err.message);
    return;
end
error('test:PDSCHReferenceCoordinateAuthority:MissingRejection','Expected %s.',id);
end
