function ok = testExecutedDataAntennaEvidence()
% Declared unit fixtures exercise the actual element-domain mapper and its
% completed-trial binder. These are not decoded PHY or antenna qualification.
setup6GRSimToolkit('Verbose',false);
beforeRNG = rng;
for direction=["DL","UL"]
    for layers=[1 4]
        [grant,iq] = localFixture(direction,layers);
        role="bs"; signal="pdsch";
        if direction=="UL", role="ue"; signal="pusch"; end
        [mapped,projection,evidence] = sixgr.truth.mapDataWaveformToPhysicalElements( ...
            iq,struct(),grant,role,signal);
        assert(isequal(mapped,iq),'The element-domain mapper must not apply a second projection.');
        row=table(direction,layers,NaN,grant.AntennaArchitecture.NumRFChains,0.03,1, ...
            'VariableNames',{'Direction','NumLayers','NumLogicalPorts','NumRFChains','EVM','CRCPass'});
        original=row;
        bound=sixgr.truth.bindExecutedDataAntennaEvidence(row,grant,evidence,projection);
        assert(bound.NumLogicalPorts==4 && bound.PrecodingNumLogicalPorts==4 && ...
            bound.NumPhysicalElements==size(iq,2) && bound.DataWaveformNumColumns==size(iq,2) && ...
            bound.FrozenDataLayers==layers && bound.FrozenDataDMRSPortCount==layers && ...
            bound.FrozenNumRFChains==grant.AntennaArchitecture.NumRFChains && ...
            bound.FrozenGrantContextId==string(grant.GrantContextId) && ...
            ~bound.SharedStreamAdditionalProjectionApplied);
        assert(~ismember('PHYGrantContextId',bound.Properties.VariableNames), ...
            'Do not create a second identity vocabulary beside FrozenGrantContextId.');
        assert(isequal(bound(:,{'EVM','CRCPass','NumLayers','NumRFChains'}), ...
            original(:,{'EVM','CRCPass','NumLayers','NumRFChains'})), ...
            'Mapping provenance cannot change receiver results or measured RF-chain fields.');
        assert(isequaln(bound,sixgr.truth.bindExecutedDataAntennaEvidence( ...
            bound,grant,evidence,projection)),'Binding must be exactly idempotent.');
        annotated=sixgr.truth.annotateFrozenMUMIMOTrialEvidence(bound,struct());
        assert(isequaln(annotated(:,bound.Properties.VariableNames),bound), ...
            'A non-MU grant without root architecture aliases cannot erase executed mapping evidence.');
        matching=struct('NumLogicalPorts',bound.NumLogicalPorts,'NumRFChains',bound.NumRFChains);
        annotated=sixgr.truth.annotateFrozenMUMIMOTrialEvidence(bound,matching);
        assert(isequaln(annotated(:,bound.Properties.VariableNames),bound));
        emptyAliases=struct('NumLogicalPorts',[],'NumRFChains',[]);
        annotated=sixgr.truth.annotateFrozenMUMIMOTrialEvidence(bound,emptyAliases);
        assert(isequaln(annotated(:,bound.Properties.VariableNames),bound), ...
            'Empty optional grant aliases must preserve executed architecture evidence.');
        assert(isempty(emptyAliases.NumLogicalPorts) && isempty(emptyAliases.NumRFChains));
        for name=["NumLogicalPorts","NumRFChains"]
            for badValue={0,-1,Inf,4.5,[4 5],4+1i}
                malformed=matching; malformed.(name)=badValue{1};
                rejected=false;
                try
                    sixgr.truth.annotateFrozenMUMIMOTrialEvidence(bound,malformed);
                catch cause
                    assert(strcmp(cause.identifier,'sixgr:truth:InvalidFrozenMUMIMOEvidence'), ...
                        'Unexpected architecture annotation error: %s',cause.identifier);
                    rejected=true;
                end
                assert(rejected,'Malformed architecture aliases must not be scalarized or ignored.');
            end
        end
        wrong=matching; wrong.NumLogicalPorts=wrong.NumLogicalPorts+1;
        conflict=false;
        try
            sixgr.truth.annotateFrozenMUMIMOTrialEvidence(bound,wrong);
        catch cause
            conflict=strcmp(cause.identifier,'sixgr:truth:ConflictingFrozenAntennaEvidence');
        end
        assert(conflict,'An explicit root alias must not overwrite conflicting executed architecture.');
    end
end
assert(isequal(rng,beforeRNG),'Provenance binding cannot advance the simulation RNG.');

[grant,iq]=localFixture("DL",1);
[~,projection,evidence]=sixgr.truth.mapDataWaveformToPhysicalElements(iq,struct(),grant,"bs","pdsch");
row=table("DL",1,'VariableNames',{'Direction','NumLayers'});
for name=["NumLogicalPorts","NumPhysicalElements","InputWaveformColumns", ...
        "ProjectionRows","ProjectionColumns"]
    bad=evidence; bad.(name)=bad.(name)+1;
    localReject(@() sixgr.truth.bindExecutedDataAntennaEvidence(row,grant,bad,projection));
end
bad=evidence; bad.InputWaveformDomain='logical_port';
localReject(@() sixgr.truth.bindExecutedDataAntennaEvidence(row,grant,bad,projection));
bad=evidence; bad.AdditionalProjectionApplied=true;
localReject(@() sixgr.truth.bindExecutedDataAntennaEvidence(row,grant,bad,projection));
bad=evidence; bad.ElementDomainPrecodingAppliedBeforeSharedStream=false;
localReject(@() sixgr.truth.bindExecutedDataAntennaEvidence(row,grant,bad,projection));
bad=evidence; bad.ProjectionSHA256=repmat('0',1,64);
localReject(@() sixgr.truth.bindExecutedDataAntennaEvidence(row,grant,bad,projection));
changed=projection; changed(1,1)=2;
localReject(@() sixgr.truth.bindExecutedDataAntennaEvidence(row,grant,evidence,changed));
bad=evidence; bad.ProjectionSHA256=char(sixgr.phy.mimo.MatrixContract.digest(double(changed)));
localReject(@() sixgr.truth.bindExecutedDataAntennaEvidence(row,grant,bad,changed));
badRow=row; badRow.NumLogicalPorts=64;
localReject(@() sixgr.truth.bindExecutedDataAntennaEvidence(badRow,grant,evidence,projection));
badRow=row; badRow.NumLayers=4;
localReject(@() sixgr.truth.bindExecutedDataAntennaEvidence(badRow,grant,evidence,projection));
badRow=row; badRow.Direction="UL";
localReject(@() sixgr.truth.bindExecutedDataAntennaEvidence(badRow,grant,evidence,projection));
badRow=row; badRow.PHYGrantContextId="another_transmission";
localReject(@() sixgr.truth.bindExecutedDataAntennaEvidence(badRow,grant,evidence,projection));
badRow=row; badRow.FrozenGrantContextId="another_transmission";
localReject(@() sixgr.truth.bindExecutedDataAntennaEvidence(badRow,grant,evidence,projection));
badRow=row; badRow.GrantContextId="another_transmission";
localReject(@() sixgr.truth.bindExecutedDataAntennaEvidence(badRow,grant,evidence,projection));
badRow=row; badRow.PhysicalTxAntennas=4;
localReject(@() sixgr.truth.bindExecutedDataAntennaEvidence(badRow,grant,evidence,projection));
badRow=row; badRow.PrecodingNumPorts=4;
localReject(@() sixgr.truth.bindExecutedDataAntennaEvidence(badRow,grant,evidence,projection));
badRow=row; badRow.PrecodingNumLayers=4;
localReject(@() sixgr.truth.bindExecutedDataAntennaEvidence(badRow,grant,evidence,projection));
aliasRow=row; aliasRow.GrantContextId=string(grant.GrantContextId);
aliasRow.FrozenGrantContextId=string(grant.GrantContextId);
aliasRow.PhysicalTxAntennas=64; aliasRow.PrecodingNumPorts=64; aliasRow.PrecodingNumLayers=1;
aliasBound=sixgr.truth.bindExecutedDataAntennaEvidence(aliasRow,grant,evidence,projection);
assert(isequaln(aliasBound(:,aliasRow.Properties.VariableNames),aliasRow), ...
    'Existing exact producer identities and dimension fields must remain unchanged.');
localReject(@() sixgr.truth.bindExecutedDataAntennaEvidence([row;row],grant,evidence,projection));
localReject(@() sixgr.truth.bindExecutedDataAntennaEvidence(row,grant,struct(),projection));
% Missing historical evidence must remain missing, not be reconstructed from
% configured capability, a selected rank or a physical waveform width.
assert(~ismember('NumLogicalPorts',row.Properties.VariableNames));
fprintf('EXECUTED_DATA_ANTENNA_EVIDENCE_PASS scope=unit_mapper_contract physical_qualification=0\n');
ok=true;
end

function [grant,iq]=localFixture(direction,layers)
elements=64; receive=4;
if direction=="UL", elements=4; receive=64; end
W=eye(elements,layers);
ant=struct('NumElements',elements,'NumLogicalPorts',4,'NumLayers',layers, ...
    'NumCodewords',1,'NumWaveformColumns',elements,'NumRxAntennas',receive, ...
    'NumRFChains',elements,'ElementDomainPrecoding',true,'WaveformDomain','element');
coding=struct('NumLayers',layers,'NumCodewords',1,'DMRSPortSet',0:layers-1, ...
    'PTRSEnabled',false,'PTRSPortSet',[]);
precoding=struct('Matrix',W,'MatrixLogicalPorts',eye(4,layers), ...
    'NumPorts',elements,'NumLogicalPorts',4,'NumLayers',layers);
grant=struct('IsFrozen',true,'Direction',char(direction), ...
    'GrantContextId',char("declared_unit_"+direction+"_rank"+layers), ...
    'AntennaArchitecture',ant,'CodingLayout',coding,'PrecodingState',precoding, ...
    'ResourceAllocation',struct('PRBSet',0:3,'PRBCount',4,'SymbolAllocation',[2 12]));
iq=complex(reshape(1:8*elements,8,elements),reshape(8*elements:-1:1,8,elements));
end

function localReject(callback)
caught=false;
try
    callback();
catch problem
    assert(strcmp(problem.identifier,'sixgr:truth:ExecutedDataAntennaEvidenceMismatch'), ...
        'Unexpected error: %s %s',problem.identifier,problem.message);
    caught=true;
end
assert(caught,'A contradictory or missing executed-mapping contract must fail.');
end
