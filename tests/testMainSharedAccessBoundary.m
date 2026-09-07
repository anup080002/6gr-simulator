function ok=testMainSharedAccessBoundary()
% Execute the actual main entry point through its migrated access boundary.
% This is deliberately NOT a full-run pass: unmigrated eager RA must fail
% before touching the retained channel. Preserve its diagnostic checkpoint.
setup6GRSimToolkit('Verbose',false);
s=sixgr.lls6g.config.loadScenarioConfig(fullfile('simulator','configs','scenarios', ...
    'lls_causal_access_to_data_wiring_tdd.yaml'));
folder=fullfile(tempdir,['main_shared_access_' char(datetime('now','Format','yyyyMMdd_HHmmss'))]);
cfg=sixgr.lls6g.buildInternalConfig(s,folder);
horizon=2*double(cfg.phy.numerology.slotsPerFrame);
options=struct('LinkSNR_dB',12,'LinkDuration_s',horizon*sixgr.time.slotDurationSec(cfg),'LinkMaxSimFrames',horizon, ...
    'SaveFigures',false,'PersistenceEnabled',true);
fprintf('MAIN_SHARED_ACCESS_DIAGNOSTIC=%s\n',folder);
try
    sixgr.truth.runWaveformLinkBundle(cfg,fullfile(folder,'air_interface'),options);
    error('TEST:ExpectedUnmigratedAccessBoundary','Main entry must not silently bypass unmigrated RA.');
catch e
    assert(strcmp(e.identifier,'sixgr:truth:LegacyExecutionOnSharedStream'), ...
        'Unexpected main boundary: %s\n%s',e.identifier,getReport(e,'extended','hyperlinks','off'));
end
files=dir(fullfile(folder,'**','runtime_failure_checkpoint.csv'));
assert(numel(files)==1,'The main failure must retain its measured checkpoint.');
t=readtable(fullfile(files.folder,files.name),'TextType','string');
assert(t.Slot>=6 && t.DLTrialRows==0 && t.ULTrialRows==0);
files=dir(fullfile(folder,'**','*pbch*trials*.csv'));
found=false;
for f=files(:).'
    t=readtable(fullfile(f.folder,f.name),'TextType','string');
    if ~isempty(t) && all(ismember({'ObservationEndSampleExclusive','ReceiverGainCompensationApplied'},t.Properties.VariableNames))
        assert(all(t.BCHCrcPass==1) && all(t.SIB1DCICrcPass==1) && all(t.SIB1DLSCHCrcPass==1));
        assert(all(t.ReceiverGainCompensationApplied) && all(t.ObservationDeliverySlot>=6));
        for row=1:height(t)
            rss=jsondecode(t.SSBWindowPowerMeasurementJSON(row));
            assert(rss.Available && all(isfinite(rss.RSSIPerAntenna_dBm)));
        end
        assert(height(t)==4); found=true;
    end
end
assert(found,'The main scheduler must publish its actual four-candidate burst, not only component-test results.');
disp('MAIN_SHARED_ACCESS_BOUNDARY_PASS: completed SSB/SIB1 evidence; unmigrated RA remains blocked, not qualified.');
ok=true;
end
