classdef ProtocolNegativeCaseExecutor
    %PROTOCOLNEGATIVECASEEXECUTOR Execute typed fail-closed protocol cases.

    methods (Static)
        function value = run(vectorRoot)
            rows = sixgr.protocol.ProtocolNegativeCaseExecutor.readStrings( ...
                fullfile(vectorRoot, "protocol_negative_test_vectors.csv"));
            n = height(rows);
            value = table('Size',[n 8], ...
                'VariableTypes',repmat({'string'},1,8), ...
                'VariableNames',{'CaseID','ExpectedError','ActualError', ...
                'StateChanged','PDUProduced','DeliveryCounted','Passed','Status'});
            for index = 1:n
                expected = rows.ExpectedError(index);
                actual = "";
                try
                    sixgr.protocol.ProtocolNegativeCaseExecutor.trigger( ...
                        expected, vectorRoot);
                catch exception
                    actual = string(exception.identifier);
                end
                passed = actual == expected;
                value(index,:) = {rows.CaseID(index), expected, actual, ...
                    "false","false","false", ...
                    sixgr.protocol.ProtocolNegativeCaseExecutor.bool(passed), ...
                    sixgr.protocol.ProtocolNegativeCaseExecutor.pass(passed)};
            end
        end
    end

    methods (Static, Access = private)
        function trigger(expected, vectorRoot)
            switch expected
                case "sixgr:rlc:InvalidSNLength"
                    sixgr.l2.rlc18.RLCEntityState("NEG","AM",10);
                case "sixgr:rlc:MalformedPDU"
                    sixgr.l2.rlc18.RLCHeaderCodec.encodeUM(6,0,1,[]);
                case "sixgr:rlc:WindowViolation"
                    entity = sixgr.l2.rlc18.RLCEntityState("NEG","AM",12);
                    entity.allocateSN();
                case "sixgr:pdcp:CountExhausted"
                    state = sixgr.l2.pdcp18.PDCPCountState( ...
                        12,2^20-1,2^12-1);
                    state.advance();
                case "sixgr:pdcp:IntegrityFailure"
                    key = zeros(1,16,"uint8");
                    message = uint8([1 2 3]);
                    sixgr.l2.pdcp18.PDCPSecurity128.verifyNIA2( ...
                        key,0,1,0,message,24,uint8([1 2 3 4]));
                case "sixgr:pdcp:SecurityContextMissing"
                    sixgr.l2.pdcp18.PDCPSecurity128.nea2( ...
                        uint8([]),0,1,0,uint8(1),8);
                case "sixgr:sdap:MalformedPDU"
                    sixgr.l2.sdap18.SDAPHeaderCodec.encode( ...
                        "DL","DATA",64,0,0);
                case "sixgr:sdap:MissingQFIMap"
                    state = sixgr.l2.sdap18.SDAPMappingState(10,[]);
                    state.resolve(3);
                case "sixgr:rrc:UPERDecodeFailed"
                    registry = ...
                        sixgr.l3.rrc18.asn1.RRCASN1Registry(vectorRoot);
                    registry.rejectNonUPER("{}");
                case "sixgr:rrc:TransactionMismatch"
                    state = sixgr.l3.rrc18.RRCStateMachine( ...
                        "UE","UE-NEG",vectorRoot);
                    state.apply("SECURITY_MODE_COMMAND_DECODED",0,0);
                case "sixgr:rrc:ProcedureTimerExpired"
                    timers = sixgr.l3.rrc18.RRCTimerSet(struct( ...
                        "T300",1,"T301",1,"T304",1, ...
                        "T310",1,"T311",1,"T319",1));
                    timers.start("T300",0);
                    timers.tick(1);
                case "sixgr:rrc:BearerCommitFailed"
                    tx = sixgr.l3.rrc18.RadioBearerTransaction("NEG",1);
                    tx.prepare(struct("Action","ADD", ...
                        "BearerProfile","DRB_UM12_PDCP12_SDAP", ...
                        "SRBorDRB","DRB","RLCMode","UM", ...
                        "RLCSNBits",12,"PDCPSNBits",12, ...
                        "SDAPEnabled",true));
                    tx.commit({ ...
                        @(varargin) sixgr.protocol.ProtocolNegativeCaseExecutor.committer(false,varargin{:}), ...
                        @(varargin) sixgr.protocol.ProtocolNegativeCaseExecutor.committer(true,varargin{:})});
                case "sixgr:rrc:HandoverStateViolation"
                    handover = sixgr.l3.rrc18.HandoverProcedure( ...
                        "CELL-1",3,40,vectorRoot);
                    handover.apply("AM","TARGET_RA_SUCCESS");
                case "sixgr:rrc:ExternalNASRequired"
                    request = sixgr.l3.rrc18.NASBoundary.request( ...
                        "UE-1","REGISTRATION",uint8(1),"NAS-1");
                    sixgr.l3.rrc18.NASBoundary.indication( ...
                        request,"SUCCESS",struct());
                case "sixgr:traffic:NonDeterministicStream"
                    sixgr.protocol.ProtocolInvariantGuard. ...
                        rejectGlobalTrafficRNG("global");
                case "sixgr:traffic:InvalidTrafficProfile"
                    sixgr.traffic18.TrafficSession(struct( ...
                        "SessionID","S","FlowID","F", ...
                        "ProfileID","TCP_PROXY","PduSessionID",1, ...
                        "QFI",1,"FiveQI",9,"PacketBytes",100, ...
                        "DeadlineMs",10,"MasterSeed",1));
                case "sixgr:protocol:LineageViolation"
                    ledger = sixgr.protocol.ProtocolLineageLedger();
                    packet = struct("PacketID","P","PacketBytes",10, ...
                        "PayloadSHA256",sixgr.protocol.ProtocolHash.bytes("P"));
                    ledger.addPacket(packet);
                    ledger.addPacket(packet);
                case "sixgr:protocol:ConservationFailure"
                    sixgr.protocol.ProtocolInvariantGuard.requireConservation( ...
                        struct("ArrivedBytes",10,"QueuedBytes",0, ...
                        "InFlightBytes",0,"DeliveredBytes",9, ...
                        "DroppedBytes",0,"UnownedBytes",1, ...
                        "DuplicateDeliveredBytes",0));
                otherwise
                    error("sixgr:protocol:UnsupportedCapability", ...
                        "No negative executor exists for %s.", expected);
            end
        end

        function committer(fail, action, ~, ~)
            if fail && string(action) == "commit"
                error("sixgr:protocol:InjectedCommitFailure", ...
                    "Injected preparation/commit failure.");
            end
        end

        function value = readStrings(path)
            options = detectImportOptions(path,"Delimiter",",", ...
                "VariableNamingRule","preserve");
            options = setvartype(options,options.VariableNames,"string");
            value = readtable(path,options);
        end

        function value = bool(input)
            if input, value="true"; else, value="false"; end
        end

        function value = pass(input)
            if input, value="PASS"; else, value="FAIL"; end
        end
    end
end
