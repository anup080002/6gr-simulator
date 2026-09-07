function ok=testULTimingOffsetAuthority()
% Real UPER receiver boundary and normative offset values, not a claim that
% the main shared-stream UL transmit-origin migration is complete.
cfg=sixgr.config.defaultConfig();
cfg.initial_access=struct();
cfg.frequency.band_name='n77'; cfg.phy.carrier.NSizeGrid=25;
cfg.phy.carrier.SubcarrierSpacing=15;
cfg.phy.prach.configurationIndex=157; cfg.phy.prach.preambleFormat='B4';
cfg.phy.prach.subcarrierSpacing_kHz=30;
expected=[25600 0 25600 39936]; enums=["","n0","n25600","n39936"];
for duplex=["TDD","FDD"]
    cfg.phy.duplex.mode=char(duplex);
    for k=1:numel(enums)
        if k==1
            if isfield(cfg.initial_access,'n_timing_advance_offset')
                cfg.initial_access=rmfield(cfg.initial_access,'n_timing_advance_offset');
            end
        else
            cfg.initial_access.n_timing_advance_offset=enums(k);
        end
        tree=sixgr.rrc.asn1.buildBCCHDLSCHMessage(cfg);
        encoded=sixgr.rrc.asn1.encodeSIB1UPER(tree);
        received=sixgr.rrc.asn1.decodeSIB1UPER(encoded);
        assert(sixgr.rrc.asn1.compareSIB1Trees(tree,received));
        assert(isequal(encoded,sixgr.rrc.asn1.encodeSIB1UPER(received)));
        % Install against a deliberately stale transmitter value. Only the
        % received tree may own either the value or absence.
        stale=struct('random_access',struct('n_timing_advance_offset','n39936'));
        [installed,evidence]=sixgr.mac.ra.installDecodedSIB1RACHConfig(stale,received);
        common=installed.UECommonCellConfiguration;
        assert(common.TimingAdvanceOffsetPresent==(k~=1));
        assert(common.TimingAdvanceOffset==enums(k));
        assert(installed.random_access.n_timing_advance_offset==enums(k));
        offset=sixgr.phy.frame.resolveULTimingAdvanceOffset(common,'FR1');
        assert(offset.NTAOffset_Tc==expected(k) && ~offset.WaveformTimingApplied);
        assert(abs(offset.Seconds*7.68e6-double(expected(k))/256)<1e-12);
        e=evidence(evidence.Parameter=="n_timing_advance_offset",:);
        assert(height(e)==1 && e.DecodedValue==enums(k));
        if k==1
            assert(contains(offset.Source,'absent_IE_default') && contains(e.ValidationStatus,'absent_IE'));
        else
            assert(offset.Source=="received_SIB1_n_TimingAdvanceOffset");
        end
    end
end
common=struct('Source',"decoded_sib1",'TimingAdvanceOffsetPresent',false,'TimingAdvanceOffset',"");
for fr=["FR2-1","FR2-2"]
    offset=sixgr.phy.frame.resolveULTimingAdvanceOffset(common,fr);
    assert(offset.NTAOffset_Tc==13792);
end
bad=common; bad.TimingAdvanceOffset="n0";
localMustFail(@()sixgr.phy.frame.resolveULTimingAdvanceOffset(bad,'FR1'), ...
    'sixgr:phy:frame:InconsistentTimingOffsetPresence');
bad=common; bad.Source="transmitter_config";
localMustFail(@()sixgr.phy.frame.resolveULTimingAdvanceOffset(bad,'FR1'), ...
    'sixgr:phy:frame:MissingReceivedULTimingAuthority');
bad=common; bad.TimingAdvanceOffsetPresent=true; bad.TimingAdvanceOffset="n123";
localMustFail(@()sixgr.phy.frame.resolveULTimingAdvanceOffset(bad,'FR1'), ...
    'sixgr:phy:frame:InvalidReceivedTimingOffset');
% Authoring schema rejects invalid enums before waveform preparation.
for token=["n0","n25600","n39936"]
    sixgr.lls6g.config.validateScenarioConfig(struct('initial_access', ...
        struct('n_timing_advance_offset',token)),'AllowPartial',true);
end
try
    sixgr.lls6g.config.validateScenarioConfig(struct('initial_access', ...
        struct('n_timing_advance_offset','n1')),'AllowPartial',true);
    error('test:ExpectedValidationFailure','Invalid timing enum was accepted.');
catch cause
    assert(~strcmp(cause.identifier,'test:ExpectedValidationFailure'));
end
ok=true; disp('UL_TIMING_OFFSET_AUTHORITY_PASS: real SIB1 IE/absence, FR1 TDD/FDD defaults, stale-value rejection; waveform application remains separate.');
end

function localMustFail(call,id)
try, call(); catch cause, assert(strcmp(cause.identifier,id),cause.message); return; end
error('test:ExpectedFailure','Expected %s.',id);
end
