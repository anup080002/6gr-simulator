function ok=testCSIYAMLQuantityAndSubset()
% YAML -> installed typed request -> native selection / received-bit codec.
% Declared matrices only: no RF, scheduler delivery or accuracy qualification.
setup6GRSimToolkit('Verbose',false,'RunToolboxChecks',false);
checks={@singleton,@subset,@guards};
names=["one_port_authored_quantity","native_subset_and_codec","invalid_subset_guards"];
passed=false(size(checks));
for k=1:numel(checks)
    try
        checks{k}(); passed(k)=true;
        fprintf('CSI_YAML_QUANTITY_SUBSET_PASS %s\n',names(k));
    catch cause
        fprintf(2,'CSI_YAML_QUANTITY_SUBSET_FAIL %s %s: %s\n', ...
            names(k),cause.identifier,cause.message);
    end
end
assert(all(passed),'test:CSIYAMLQuantityAndSubset','Passed %d/%d groups.',nnz(passed),numel(passed));
ok=true;
end

function singleton()
s=loadScenario('dl_4ghz_baseline.yaml');
if isfield(s.mimo,'phase07_strict'), s.mimo=rmfield(s.mimo,'phase07_strict'); end
s.reference_signals.csi_reporting_enabled=true;
s.reference_signals.pmi_reporting_enabled=false;
s.reference_signals.csi_rs_enabled=true;
s.reference_signals.csi_rs_ports=1;
s.reference_signals.csi_rs_num_resources=1;
s.pdsch.layer_count=1; s.pdsch.rank=1; s.mimo.n_layers=1;
s.mimo.codebook_type='type1';
s.csi_acquisition_and_reporting.report_configuration.report_quantity='cri-ri-cqi';
cfg=sixgr.lls6g.buildInternalConfig(s,tempname);
r=cfg.phy.csi.reportConfiguration;
assert(string(r.ReportQuantity)=="cri-ri-cqi"&&r.Ports==1);
wire=sixgr.phy.mimo.CSIReportConfiguration(r,r.Epoch);
p=wire.reportingPolicy();
assert(p.ReportRI&&p.ReportCRI&&p.ReportCQI&&~p.ReportPMI);
assert(~any([wire.Part1Fields wire.Part2Fields]=="RI")&&wire.part2BitCount()==0);
payload=wire.build(struct('RI',1,'CRI',0,'CQI_CW0',11));
received=wire.encodeDecodeNoNoise(payload);
decoded=wire.decode(received.Part1.Bits,received.Part2.Bits);
assert(received.CRCPassed&&decoded.RI==1&&decoded.CQI_CW0==11);
% An enabled runtime report must reject an inspection-only legacy alias
% before any waveform. The typed inspection API remains covered separately.
s.csi_acquisition_and_reporting.report_configuration.report_quantity='cqi';
reject(@()sixgr.lls6g.buildInternalConfig(s,tempname),'sixgr:mimo:UnqualifiedCSIWireLayout');
s.reference_signals.csi_reporting_enabled=false;
for field=["cqi_reporting_enabled","pmi_reporting_enabled", ...
        "ri_reporting_enabled","cri_reporting_enabled"]
    s.reference_signals.(field)=false;
end
cfg=sixgr.lls6g.buildInternalConfig(s,tempname);
assert(~cfg.phy.csi.reportCSI&&string(cfg.phy.csi.reportConfiguration.ReportQuantity)=="cqi");
wire=sixgr.phy.mimo.CSIReportConfiguration(cfg.phy.csi.reportConfiguration,r.Epoch);
assert(wire.part1BitCount()==4); % Disabled inspection is not a wire qualification.
end

function subset()
s=loadScenario('lls_tdd_four_port_received_rank_transition_fixture.yaml');
s.mimo.codebook_subset_restriction='10000000'; % a0, not a7, is enabled.
cfg=sixgr.lls6g.buildInternalConfig(s,tempname);
r=cfg.phy.csi.reportConfiguration;
assert(isequal(r.CodebookSubsetRestriction,[1 zeros(1,7)])&&r.Ports==4&&r.CodebookMode==1);
carrier=nrCarrierConfig('NSizeGrid',24,'SubcarrierSpacing',30);
csirs=nrCSIRSConfig('CSIRSType','nzp','RowNumber',4,'Density','one', ...
    'SymbolLocations',3,'SubcarrierLocations',0,'NumRB',24);
H=repmat(reshape(eye(4),1,1,4,4),288,14,1,1);
for rank=[1 2 4]
    r.Rank=rank;
    [W,indices,components]=sixgr.phy.mimo.TypeISinglePanelCodebook.enumerate(r);
    native=nrCSIReportConfig('NSizeBWP',24,'CodebookType','type1SinglePanel', ...
        'PanelDimensions',[1 2 1],'CodebookMode',1,'PMIFormatIndicator','wideband', ...
        'CodebookSubsetRestriction',r.CodebookSubsetRestriction);
    [selected,info]=nr5g.internal.nrPMIReport(carrier,csirs,native,rank,H,.1);
    allNative=reshape(info.Codebook,4,rank,[]);
    nativeAllowed=find(reshape(any(any(abs(allNative)>0,1),2),[],1))-1;
    assert(isequal(indices,nativeAllowed));
    retained=allNative(:,:,indices+1);
    assert(max(abs(W(:)-retained(:)))<1e-12);
    % Native PMISet uses one-based indices, including implicit i12/i13.
    % The normative tuple/codec API uses zero-based component values.
    c=struct('PMI_I11',double(selected.i1(1))-1,'PMI_I12',double(selected.i1(2))-1, ...
        'PMI_I13',0,'PMI_I2',double(selected.i2)-1);
    if numel(selected.i1)>2, c.PMI_I13=double(selected.i1(3))-1; end
    selectedIndex=sixgr.phy.mimo.TypeISinglePanelCodebook.linearIndex(r,c);
    assert(ismember(selectedIndex,indices));
    % Original noncontiguous PMI indices survive the actual typed codec.
    wire=sixgr.phy.mimo.CSIReportConfiguration(r,r.Epoch);
    for k=1:numel(indices)
        values=components(k); values.RI=rank; values.LI=0; values.CRI=0; values.CQI_CW0=9;
        payload=wire.build(values); received=wire.encodeDecodeNoNoise(payload);
        decoded=wire.decode(received.Part1.Bits,received.Part2.Bits);
        assert(received.CRCPassed&&decoded.PMI==indices(k)&&decoded.RI==rank);
    end
    unrestricted=rmfield(r,'CodebookSubsetRestriction');
    [~,full]=sixgr.phy.mimo.TypeISinglePanelCodebook.enumerate(unrestricted);
    excluded=setdiff(full,indices); assert(~isempty(excluded));
    reject(@()sixgr.phy.mimo.TypeISinglePanelCodebook.matrix(r,excluded(1)), ...
        'sixgr:mimo:RestrictedPMI');
    % A CRC-valid encoded report from an unrestricted configuration must
    % still be rejected by the independently installed restricted decoder.
    % Keep rank domain, transport and all non-subset configuration unchanged.
    [~,excludedValues]=sixgr.phy.mimo.TypeISinglePanelCodebook.matrix(unrestricted,excluded(1));
    excludedValues.RI=rank; excludedValues.LI=0; excludedValues.CRI=0; excludedValues.CQI_CW0=9;
    unrestrictedWire=sixgr.phy.mimo.CSIReportConfiguration(unrestricted,r.Epoch);
    excludedPayload=unrestrictedWire.build(excludedValues);
    excludedReceived=unrestrictedWire.encodeDecodeNoNoise(excludedPayload);
    assert(excludedReceived.CRCPassed);
    unrestrictedDecoded=unrestrictedWire.decode(excludedReceived.Part1.Bits,excludedReceived.Part2.Bits);
    assert(unrestrictedDecoded.PMI==excluded(1)&&unrestrictedDecoded.RI==rank);
    reject(@()wire.decode(excludedReceived.Part1.Bits,excludedReceived.Part2.Bits), ...
        'sixgr:mimo:RestrictedPMI');
    % Same installed request reaches actual scheduler-side enumeration.
    cfg.phy.csi.reportConfiguration=r;
    scheduled=sixgr.phy.dl.pmiCodebookCandidates(cfg,rank,4,'Mode','type1_su_mimo');
    assert(isequal(cat(3,scheduled.W),W));
    if rank==2
        % Analytic H is a numerical test operand, not measured CSI. Keep
        % the immutable operational measurement-state guard exercised.
        reject(@()sixgr.phy.mimo.CSIMeasurementState( ...
            MeasurementID="declared_YAML_subset_matrix",UEID="UE1", ...
            ResourceType="NZP-CSI-RS",ResourceID="CSI-RS-0",ResourceOrdinal=0, ...
            Slot=0,MaxAgeSlots=0,ChannelEstimate=eye(4),NoiseVariance=.1, ...
            Provenance="declared_analytic_matrix_not_received_waveform"), ...
            'sixgr:mimo:BeamMeasurementOracleForbidden');
        % The numerical rank helper and native CQI/PMI implementation accept
        % supplied matrices without creating receiver/feedback authority.
        % This does NOT exercise NRCSIReportEngine's measured-state path.
        native.RIRestriction=[0 1 zeros(1,6)];
        [selectedRank,decision]=sixgr.phy.mimo.selectNRMaxSEWithEvidence( ...
            carrier,csirs,native,H,.1,2);
        assert(selectedRank==2&&isequal(decision.Configuration.CodebookSubsetRestriction, ...
            r.CodebookSubsetRestriction)&&~decision.IndependentSelectionQualityVerified);
        [cqi,pmi,~,nativePMI]=nr5g.internal.nrCQIReport( ...
            carrier,csirs,native,nrPDSCHDMRSConfig,selectedRank,H,.1);
        values=struct('PMI_I11',double(pmi.i1(1))-1,'PMI_I12',double(pmi.i1(2))-1, ...
            'PMI_I13',double(pmi.i1(3))-1,'PMI_I2',double(pmi.i2)-1, ...
            'RI',selectedRank,'LI',0,'CRI',0,'CQI_CW0',double(cqi(1)));
        selectedIndex=sixgr.phy.mimo.TypeISinglePanelCodebook.linearIndex(r,values);
        selectedW=sixgr.phy.mimo.TypeISinglePanelCodebook.matrix(r,selectedIndex);
        assert(ismember(selectedIndex,indices)&&max(abs(selectedW(:)-nativePMI.W(:)))<1e-12);
        payload=wire.build(values); received=wire.encodeDecodeNoNoise(payload);
        decoded=wire.decode(received.Part1.Bits,received.Part2.Bits);
        assert(received.CRCPassed&&decoded.PMI==selectedIndex&&decoded.RI==selectedRank);
    end
end
end

function guards()
s=loadScenario('lls_tdd_four_port_received_rank_transition_fixture.yaml');
for value={"0101", "00000000", "10002000", [1 zeros(1,7)], ["1","0"]}
    bad=s; bad.mimo.codebook_subset_restriction=value{1};
    reject(@()sixgr.lls6g.buildInternalConfig(bad,tempname), ...
        'sixgr:mimo:InvalidCodebookSubsetRestriction');
end
s.mimo.codebook_subset_restriction='unrestricted';
cfg=sixgr.lls6g.buildInternalConfig(s,tempname);
assert(~isfield(cfg.phy.csi.reportConfiguration,'CodebookSubsetRestriction'));
s.mimo.codebook_subset_restriction='';
cfg=sixgr.lls6g.buildInternalConfig(s,tempname);
assert(~isfield(cfg.phy.csi.reportConfiguration,'CodebookSubsetRestriction'));
% Existing two-port consumers do not consume this bitmap; no ignored knob.
s=loadScenario('dl_4ghz_baseline.yaml');
if isfield(s.mimo,'phase07_strict'), s.mimo=rmfield(s.mimo,'phase07_strict'); end
s.reference_signals.csi_rs_ports=2; s.pdsch.layer_count=1; s.pdsch.rank=1; s.mimo.n_layers=1;
s.mimo.codebook_subset_restriction='111111';
reject(@()sixgr.lls6g.buildInternalConfig(s,tempname), ...
    'sixgr:mimo:UnsupportedCodebookSubsetRestriction');
end

function s=loadScenario(name)
loaded=sixgr.lls6g.config.loadScenarioConfig(fullfile(pwd,'simulator','configs','scenarios',name));
s=loaded.toStruct();
end
function reject(action,id)
try, action(); catch cause
    assert(strcmp(cause.identifier,id),'Expected %s, got %s: %s',id,cause.identifier,cause.message); return;
end
error('test:MissingCSIYAMLGuard','Expected %s.',id);
end
