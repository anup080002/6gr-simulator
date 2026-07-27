classdef ProtocolSelfTest
    %PROTOCOLSELFTEST Focused Phase-12 production assertions.

    methods (Static)
        function summary = run(vectorRoot)
            plan = sixgr.protocol.ProtocolSelfTest.readStrings(fullfile( ...
                vectorRoot,"protocol_matlab_test_plan.csv"));
            n = height(plan);
            passed = false(n,1);
            duration = zeros(n,1);
            details = strings(n,1);
            for index = 1:n
                started = tic;
                try
                    sixgr.protocol.ProtocolSelfTest.runOne( ...
                        plan.TestClass(index),vectorRoot);
                    passed(index) = true;
                    details(index) = "executed production assertion";
                catch exception
                    details(index) = string(exception.identifier) + ": " + ...
                        string(exception.message);
                end
                duration(index) = toc(started);
            end
            summary = table(plan.TestID,plan.TestClass, ...
                repmat(true,n,1),passed,~passed,duration,details, ...
                'VariableNames',{'TestID','TestClass','Executed','Passed', ...
                'Failed','DurationSeconds','Details'});
        end

        function runOne(name, vectorRoot)
            arguments
                name (1,1) string
                vectorRoot (1,1) string
            end
            vectors = sixgr.protocol.ProtocolSelfTest.vectors(vectorRoot);
            if startsWith(name,"testRLC")
                sixgr.protocol.ProtocolSelfTest.requireFamilies(vectors, ...
                    ["rlc_um_header","rlc_am_header","rlc_status","rlc_state"]);
                sixgr.protocol.ProtocolSelfTest.rlcEntities();
            elseif startsWith(name,"testPDCP")
                sixgr.protocol.ProtocolSelfTest.requireFamilies(vectors, ...
                    ["pdcp_header","pdcp_count","pdcp_security", ...
                    "pdcp_reordering"]);
                sixgr.protocol.ProtocolSelfTest.pdcpEntity();
            elseif startsWith(name,"testSDAP")
                sixgr.protocol.ProtocolSelfTest.requireFamilies(vectors, ...
                    ["sdap_header","sdap_mapping"]);
                sixgr.protocol.ProtocolSelfTest.sdapEntity();
            elseif startsWith(name,"testRRCASN1")
                sixgr.protocol.ProtocolSelfTest.requireFamilies(vectors, ...
                    ["rrc_semantics","rrc_uper"]);
                sixgr.protocol.ProtocolSelfTest.rrcRoundTrip(vectorRoot);
                sixgr.protocol.ProtocolSelfTest.rrcConnection(vectorRoot);
            elseif ismember(name,["testRRCTransactionIDs","testRRCTimers", ...
                    "testRRCStateMachine"])
                sixgr.protocol.ProtocolSelfTest.rrcState(vectorRoot);
            elseif startsWith(name,"testRadioBearer")
                sixgr.protocol.ProtocolSelfTest.bearer(vectorRoot);
            elseif name == "testSecurityModeProcedure"
                sixgr.protocol.ProtocolSelfTest.security(vectorRoot);
            elseif startsWith(name,"testHandover")
                sixgr.protocol.ProtocolSelfTest.handover(vectorRoot);
            elseif name == "testNASBoundary"
                sixgr.protocol.ProtocolSelfTest.nas();
            elseif startsWith(name,"testTraffic") || name == "testProtocolReproducibility"
                sixgr.protocol.ProtocolSelfTest.traffic();
            elseif ismember(name,["testProtocolLineage", ...
                    "testProtocolConservation","testFirstDeliveryDeduplication", ...
                    "testMultiBearerIsolation","testEndToEndConnectedModeNoLoss", ...
                    "testEndToEndConnectedModeLoss"])
                sixgr.protocol.ProtocolSelfTest.lineage();
            elseif name == "testProtocolArtifactGeneration"
                assert(~isempty(which( ...
                    "sixgr.protocol.runProtocolStackPhaseValidation")));
            elseif name == "testProtocolImpactAnalysis"
                assert(~isempty(which( ...
                    "sixgr.protocol.runProtocolStackImpactAnalysis")));
            else
                error("sixgr:protocol:MissingFocusedTest", ...
                    "No Phase-12 production assertion is mapped to %s.",name);
            end
        end
    end

    methods (Static, Access = private)
        function value = vectors(vectorRoot)
            persistent cacheRoot cacheValue
            if isempty(cacheValue) || string(cacheRoot) ~= vectorRoot
                cacheRoot = vectorRoot;
                cacheValue = ...
                    sixgr.protocol.ProtocolVectorValidator.validate(vectorRoot);
            end
            value = cacheValue;
        end

        function requireFamilies(vectors,names)
            for name = names
                row = vectors.Details.VectorFamily == name;
                assert(sum(row)==1);
                assert(str2double(vectors.Details.MismatchCount(row))==0);
            end
        end

        function rrcRoundTrip(vectorRoot)
            rows = sixgr.protocol.ProtocolSelfTest.readStrings(fullfile( ...
                vectorRoot,"protocol_rrc_release18_uper_vectors.csv"));
            for index = 1:height(rows)
                bytes = sixgr.protocol.ProtocolSelfTest.fromHex( ...
                    rows.UPERHex(index));
                decoded = ...
                    sixgr.l3.rrc18.asn1.RRCBoundedUPERCodec.decode( ...
                    bytes,rows.Channel(index));
                assert(decoded.MessageType == rows.MessageType(index));
                assert(decoded.TransactionID == ...
                    str2double(rows.TransactionID(index)));
            end
        end

        function rrcState(vectorRoot)
            state = sixgr.l3.rrc18.RRCStateMachine( ...
                "UE","UE-1",vectorRoot);
            state.apply("RRC_SETUP_REQUEST_SENT",0);
            state.apply("RRC_SETUP_DECODED",1,0);
            state.apply("RRC_SETUP_COMPLETE_DECODED",2,0);
            assert(state.State=="RRC_CONNECTED");
            timers = sixgr.l3.rrc18.RRCTimerSet(struct( ...
                "T300",1000,"T301",1000,"T304",1000, ...
                "T310",1000,"T311",1000,"T319",1000));
            timers.start("T300",0);
            timers.stop("T300");
        end

        function rlcEntities()
            persistent passed
            if ~isempty(passed),return;end
            base=struct("UEID","UE-T","BearerID","DRB-T", ...
                "Direction","UL","ConfigurationEpoch",1,"SNBits",18, ...
                "PollPDU",4,"PollByte",1000,"MaxRetxThreshold",4);
            base.Mode="AM";
            entity=sixgr.l2.rlc18.RLCEntityFactory.create(base);
            payload=uint8(1:100);entity.addSDU(payload);pdus={};
            while true
                part=entity.buildPDUs(21);
                if isempty(part),break;end
                pdus=[pdus part]; %#ok<AGROW>
            end
            for index=1:numel(pdus),entity.receivePDU(pdus{index});end
            delivered=entity.pullSDUs();
            assert(numel(delivered)==1 && isequal(delivered{1},payload));
            um=base;um.Mode="UM";um.SNBits=12;
            umEntity=sixgr.l2.rlc18.RLCEntityFactory.create(um);
            umEntity.addSDU(uint8(1:8));
            one=umEntity.buildPDUs(32);umEntity.receivePDU(one{1});
            umDelivered=umEntity.pullSDUs();
            assert(isequal(umDelivered{1},uint8(1:8)));
            passed=true;
        end

        function pdcpEntity()
            persistent passed
            if ~isempty(passed),return;end
            key=uint8(0:15);
            entity=sixgr.l2.pdcp18.PDCPBearerEntity(struct( ...
                "UEID","UE-T","BearerID","DRB-T","Bearer",1, ...
                "Direction",0,"BearerType","DRB","SNBits",18, ...
                "ConfigurationEpoch",1,"CipherAlgorithm","128-NEA2", ...
                "IntegrityAlgorithm","128-NIA2", ...
                "CipherKey",key,"IntegrityKey",key));
            entity.activateSecurity();
            payload=uint8(1:48);pdu=entity.transmit(payload);
            delivered=entity.receive(pdu);
            assert(numel(delivered)==1 && isequal(delivered{1},payload));
            assert(isempty(entity.receive(pdu)));
            passed=true;
        end

        function sdapEntity()
            persistent passed
            if ~isempty(passed),return;end
            mapping=struct("QFI",9,"DRBID",1);
            entity=sixgr.l2.sdap18.SDAPEntity(struct( ...
                "UEID","UE-T","Direction","UL","PduSessionID",1, ...
                "DefaultDRBID",1,"ConfigurationEpoch",1, ...
                "Mappings",mapping));
            [pdu,drb]=entity.transmit(9,uint8(1:16));
            assert(drb==1 && isequal(entity.receive(pdu),uint8(1:16)));
            passed=true;
        end

        function rrcConnection(vectorRoot)
            persistent passed
            if ~isempty(passed),return;end
            timers=struct("T300",1000,"T301",1000,"T304",1000, ...
                "T310",1000,"T311",3000,"T319",1000);
            ue=sixgr.l3.rrc18.RRCUE("UE-T",vectorRoot,timers);
            gnb=sixgr.l3.rrc18.RRCGNB("UE-T",vectorRoot,timers);
            result=sixgr.l3.rrc18.RRCConnectionEstablishment.run(ue,gnb,0);
            assert(result.Converged);
            campaign=sixgr.l3.rrc18.RRCProcedureCampaign.run(vectorRoot,0);
            assert(campaign.Converged && campaign.SecurityActive && ...
                campaign.UEState=="RRC_IDLE");
            passed=true;
        end

        function bearer(vectorRoot)
            rows = sixgr.protocol.ProtocolSelfTest.readStrings(fullfile( ...
                vectorRoot,"protocol_radio_bearer_vectors.csv"));
            valid = rows(lower(rows.ExpectedValid)=="true",:);
            for index = 1:height(valid)
                cfg = table2struct(valid(index,:));
                cfg.RLCSNBits = str2double(string(cfg.RLCSNBits));
                cfg.PDCPSNBits = str2double(string(cfg.PDCPSNBits));
                cfg.SDAPEnabled = lower(string(cfg.SDAPEnabled))=="true";
                tx = sixgr.l3.rrc18.RadioBearerTransaction( ...
                    "RB-"+index,index);
                tx.prepare(cfg);
                result = tx.commit({@(varargin) []});
                assert(result.Atomic);
            end
        end

        function security(vectorRoot)
            rows = sixgr.protocol.ProtocolSelfTest.readStrings(fullfile( ...
                vectorRoot,"protocol_pdcp_security_vectors.csv"));
            row = rows(rows.Algorithm=="128-NIA2",:);
            row = row(1,:);
            key = sixgr.protocol.ProtocolSelfTest.fromHex(row.KeyHex);
            message = sixgr.protocol.ProtocolSelfTest.fromHex(row.MessageHex);
            expected = sixgr.protocol.ProtocolSelfTest.fromHex( ...
                row.ExpectedMACIHex);
            sixgr.l2.pdcp18.PDCPSecurity128.verifyNIA2( ...
                key,str2double(row.COUNT),str2double(row.Bearer), ...
                str2double(row.Direction),message, ...
                str2double(row.BitLength),expected);
        end

        function handover(vectorRoot)
            procedure = sixgr.l3.rrc18.HandoverProcedure( ...
                "CELL-A",1,10,vectorRoot);
            procedure.measurement(0,-90,"CELL-B",-80,1);
            assert(procedure.measurement(10,-90,"CELL-B",-80,1));
            events = ["A3_ENTRY","MEASUREMENT_REPORT_DECODED", ...
                "TARGET_CONTEXT_READY","RECONFIG_WITH_SYNC_DECODED", ...
                "TARGET_RA_SUCCESS","RRC_RECONFIG_COMPLETE_DECODED", ...
                "SOURCE_RELEASE"];
            for event = events
                procedure.apply("AM",event);
            end
            assert(procedure.State=="SERVING_TARGET");
        end

        function nas()
            request = sixgr.l3.rrc18.NASBoundary.request( ...
                "UE-1","REGISTRATION",uint8([1 2]),"NAS-1");
            assert(request.ExternalResult=="PENDING");
            result = sixgr.l3.rrc18.NASBoundary.indication( ...
                request,"SUCCESS",struct("Decoded",true));
            assert(result.RRCStateChangeAllowed);
        end

        function traffic()
            persistent passed
            if ~isempty(passed),return;end
            cfg = struct("SessionID","S1","FlowID","F1", ...
                "ProfileID","POISSON","PduSessionID",1,"QFI",2, ...
                "FiveQI",9,"PacketBytes",64,"DeadlineMs",100, ...
                "MasterSeed",77);
            a = sixgr.traffic18.TrafficSession(cfg);
            b = sixgr.traffic18.TrafficSession(cfg);
            pa = a.generate(0,100,"LambdaPPS",100);
            pb = b.generate(0,100,"LambdaPPS",100);
            assert(isequal({pa.PayloadSHA256},{pb.PayloadSHA256}));
            assert(isequal([pa.ArrivalTime_ms],[pb.ArrivalTime_ms]));
            runtimeCfg=struct("run",struct("seed",77), ...
                "protocol",struct("enabled",true,"traffic",struct( ...
                "enabled",true,"sessions",struct("flow_id","F1", ...
                "profile_id","CBR","pdu_session_id",1,"qfi",2, ...
                "five_qi",9,"packet_bytes",64,"rate_mbps",1, ...
                "deadline_ms",100,"direction","BIDIR"))));
            generated=sixgr.system.TrafficFactory.generate( ...
                runtimeCfg,2,20,1e-3);
            assert(generated.Deterministic && ...
                height(generated.PacketTable)>0);
            passed=true;
        end

        function lineage()
            ledger = sixgr.protocol.ProtocolLineageLedger();
            packet = struct("PacketID","P1","PacketBytes",100, ...
                "PayloadSHA256",sixgr.protocol.ProtocolHash.bytes("P1"));
            ledger.addPacket(packet);
            ledger.addNode("S1","P1","SDAP",100);
            assert(ledger.deliver("P1"));
            assert(~ledger.deliver("P1"));
            result = ledger.conservation();
            assert(result.EquationErrorBytes==0);
            runtime = sixgr.protocol.ProtocolRuntime(struct( ...
                "UEID","UE-TEST","BearerID","DRB-TEST","QFI",9, ...
                "PDCPSNBits",18,"RLCSNBits",18, ...
                "ConfigurationEpoch",1));
            pdu = runtime.transmit("P-RUNTIME",uint8(1:32),0);
            assert(runtime.receive(pdu,0.1));
            assert(~runtime.receive(pdu,0.2));
            result = runtime.conservation();
            assert(result.EquationErrorBytes==0);
            assert(runtime.PacketsDelivered==1);
            assert(runtime.DuplicateDiscards==1);
        end

        function value = readStrings(path)
            options=detectImportOptions(path,"Delimiter",",", ...
                "VariableNamingRule","preserve");
            options=setvartype(options,options.VariableNames,"string");
            value=readtable(path,options);
        end

        function bytes = fromHex(text)
            bytes=uint8(sscanf(char(text),"%2x").');
        end
    end
end
