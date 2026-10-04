function ok=testGrantCalibrationAllocation()
% Public SLS carrier -> exact production sizing, never a BLER fixture.
path=fullfile(pwd,'simulator','configs','scenarios','sls_nr_tdd_21cell_connected.yaml');
request=sixgr.config.loadSimulationRequest(path); cfg=request.Config;
frame=sixgr.phy.FrameStructureEngine(cfg,'FrameCoreOnly',true);
assert(frame.NRB==273 && cfg.system.linkAbstraction.allowDevelopmentFixtures==false);
for direction=["DL","UL"]
    symbols=[2 10];
    legal=[];
    for slot=1:19
        good=frame.IsDLAllocation(slot,symbols);
        if direction=="UL", good=frame.IsULAllocation(slot,symbols); end
        if good, legal(end+1)=slot; end %#ok<AGROW>
    end
    assert(~isempty(legal));
    for layers=[1 2 4]
        W=eye(4,layers)/sqrt(layers);
        a=struct('direction',direction,'rnti',73,'ue_index',1,'serving_cell',1, ...
            'prb_set',0:272,'symbol_allocation',symbols,'mcs_table',"qam64_table1", ...
            'mcs_index',1,'rank',layers,'precoder_real',real(W),'precoder_imag',imag(W), ...
            'rv_sequence',[0 2 3],'absolute_slots',legal(1)+[0 20 40], ...
            'control_assumption',"ideal_issued_grant");
        g=sixgr.calibration.buildGrantCalibrationAllocation(cfg,a);
        for j=1:numel(g)
            t=g{j};
            assert(t.ExactPHYFeasible && t.NumLayers==layers && numel(t.PRBSet)==273 && ...
                t.TBSBits==g{1}.TBSBits && t.PHYGrant.CodingLayout.TBSBits==t.TBSBits && ...
                t.ScheduledAbsoluteSlot==a.absolute_slots(j));
            independentTBS=nrTBS(t.Modulation,layers,numel(t.PRBSet), ...
                t.TBSInputNREPerPRB,t.TargetCodeRate,t.TBSInputXOverhead);
            assert(t.TBSBits==independentTBS && t.ExactAllocationCodedBitsG>0);
            if direction=="UL"
                assert(isequal(double(t.PHYGrant.CodingLayout.DMRSPortSet(:).'),0:layers-1), ...
                    'UL grant must retain exactly the logical DM-RS ports for its scheduled rank.');
            end
        end
    end
end
bad=a; bad.precoder_real=bad.precoder_real*2;
localReject(@()sixgr.calibration.buildGrantCalibrationAllocation(cfg,bad),'sixgr:calibration:AllocationPrecoder');
bad=a; bad.control_assumption="physical_received_dci";
localReject(@()sixgr.calibration.buildGrantCalibrationAllocation(cfg,bad),'sixgr:calibration:AllocationControl');
bad=a; bad.absolute_slots=[1 1 2];
localReject(@()sixgr.calibration.buildGrantCalibrationAllocation(cfg,bad),'sixgr:calibration:AllocationHistory');
bad=a; bad.prb_set=[0 0];
localReject(@()sixgr.calibration.buildGrantCalibrationAllocation(cfg,bad),'sixgr:calibration:AllocationHistory');
bad=a; bad.direction="DL"; % Retain UL-only clocks: do not silently move them.
localReject(@()sixgr.calibration.buildGrantCalibrationAllocation(cfg,bad),'sixgr:calibration:AllocationDuplex');
folder=tempname(fullfile(pwd,'logs')); mkdir(folder);
a.prb_set="all_carrier";
collection=struct('id',"ul_fullband",'scenario_config',string(path),'allocation',a, ...
    'snr_histories_db',[40 40 40],'fit_starts_per_history',1,'validation_starts_per_history',1);
p=struct('schema',"sixgr.grant_calibration_campaign/v1",'campaign_id',"public_allocation_check", ...
    'research_class',"baseline_benchmark",'seed_base',901000,'episodes_per_invocation',1, ...
    'channel_evolution',"persistent_link_absolute_slot",'collections',collection);
file=fullfile(folder,'campaign.yaml'); sixgr.util.jsonWrite(file,p);
[~,collections,identity]=sixgr.calibration.loadGrantCampaign(file);
assert(numel(collections.Plan)==2 && ~isempty(collections.SourceInputs) && ...
    contains(collections.TemplateUsage,"no_outcomes") && strlength(identity)==64);
assert(collections.Plan(1).Grants{1}.TBSBits==g{1}.TBSBits && ...
    collections.Plan(1).Seeds.Bits~=collections.Plan(2).Seeds.Bits);
[~,again,againIdentity]=sixgr.calibration.loadGrantCampaign(file);
assert(againIdentity==identity && isequaln(again.Config,collections.Config) && ...
    isequaln(again.Plan,collections.Plan), ...
    'Reloading unchanged YAML must not alter immutable campaign/config/seed identity.');
fprintf('GRANT_CONFIGURED_ALLOCATION_PASS PRBs=273 directions=2 ranks=1,2,4 waveform_executed=0 qualified=0\n');
ok=true;
end

function localReject(fn,id)
try, fn(); catch cause, assert(strcmp(cause.identifier,id),'Expected %s, got %s: %s',id,cause.identifier,cause.message); return; end
error('test:MissingAllocationRejection','Expected %s',id);
end
