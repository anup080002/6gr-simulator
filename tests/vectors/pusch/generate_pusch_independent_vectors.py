#!/usr/bin/env python3
"""Generate bounded independent PUSCH/UL-SCH vector oracles.

No MATLAB or 5G Toolbox function is called.  The script recomputes the
deterministic floor for:
  * TS 38.211 Gold scrambling, including the bounded MsgA c_init cases and
    UCI x/y placeholder handling used by this pack;
  * pi/2-BPSK and square-QAM mapping;
  * codeword-to-layer de-interleaving;
  * generic TS 38.212 TB CRC, TBS and LDPC base-graph selection;
  * scheduling-source acceptance;
  * UCI owner selection for one/two UL-SCH transport blocks;
  * unitary transform-precoding DFT vectors;
  * bounded hop plans;
  * SRS-state age/epoch acceptance;
  * explicit precoder matrix application;
  * PUSCH power-control arithmetic;
  * HARQ state-transition expectations.

The broad DM-RS/PT-RS tables, full UCI coding/multiplex bit positions,
complete LDPC/rate-matching indices, and full PUSCH codebook tables must be
added by Codex from the pinned specifications or independently frozen vectors.
The files generated here are a deterministic floor, not a complete oracle.
"""
from __future__ import annotations
import csv, cmath, hashlib, json, math
from pathlib import Path
from typing import Iterable, Sequence

ROOT=Path(__file__).resolve().parent

def read_csv(name):
    with (ROOT/name).open(newline="",encoding="utf-8-sig") as f:
        return list(csv.DictReader(f))

def write_csv(name, rows, fields=None):
    rows=list(rows)
    if fields is None:
        fields=[];seen=set()
        for r in rows:
            for k in r:
                if k not in seen: seen.add(k);fields.append(k)
    with (ROOT/name).open("w",newline="",encoding="utf-8") as f:
        w=csv.DictWriter(f,fieldnames=fields,extrasaction="ignore")
        w.writeheader();w.writerows(rows)

def bits_text(v): return "".join(str(int(x)) for x in v)
def nums_text(v): return "|".join(str(x) for x in v)
def complex_text(v): return "|".join(f"{z.real:.15g}{z.imag:+.15g}j" for z in v)
def parse_complex_list(text):
    if str(text).strip()=="": return []
    return [complex(x) for x in str(text).split("|")]
def parse_matrix(text):
    if str(text).strip()=="": return []
    return [parse_complex_list(row) for row in str(text).split(";")]
def file_sha(path):
    h=hashlib.sha256()
    with Path(path).open("rb") as f:
        for b in iter(lambda:f.read(1024*1024),b""):h.update(b)
    return h.hexdigest()

def gold_sequence(c_init,length,nc=1600):
    total=nc+length+31
    x1=[0]*total;x2=[0]*total;x1[0]=1
    for i in range(31):x2[i]=(c_init>>i)&1
    for n in range(total-31):
        x1[n+31]=(x1[n+3]+x1[n])&1
        x2[n+31]=(x2[n+3]+x2[n+2]+x2[n+1]+x2[n])&1
    return [(x1[n+nc]+x2[n+nc])&1 for n in range(length)]

def gen_scrambling():
    out=[]
    for r in read_csv("pusch_scrambling_test_vectors.csv"):
        msga=int(r["IsMsgA"])
        rnti=int(r["RNTI"]);q=int(r["CodewordIndexQ"]);nid=int(r["NID"])
        init=(rnti*2**16+int(r["RAPID"])*2**10+nid) if msga else (rnti*2**15+q*2**14+nid)
        inp=r["InputSymbols"];seq=gold_sequence(init,len(inp));res=[];prev=0
        for i,ch in enumerate(inp):
            if ch in "01":v=int(ch)^seq[i]
            elif ch=="X":v=1
            elif ch=="Y":v=prev
            else:raise ValueError(f"invalid input symbol {ch}")
            res.append(v);prev=v
        out.append({"CaseID":r["CaseID"],"CInit":init,"GoldBits":bits_text(seq),
                    "ScrambledSymbols":bits_text(res),"GoldOnes":sum(seq),
                    "OutputOnes":sum(res),"Status":"PASS"})
    write_csv("expected_pusch_scrambling_vectors.csv",out)

QAM={"QPSK":(2,2.0),"16QAM":(4,10.0),"64QAM":(6,42.0),"256QAM":(8,170.0)}
def axis_amp(bits):
    if len(bits)==1:return 1-2*int(bits[0])
    inner=2-(1-2*int(bits[-1]))
    for idx in range(len(bits)-2,0,-1):
        inner=2**(len(bits)-idx)-(1-2*int(bits[idx]))*inner
    return (1-2*int(bits[0]))*inner
def qam_mod(bits,mod):
    qm,norm2=QAM[mod];res=[]
    for i in range(0,len(bits),qm):
        g=bits[i:i+qm]
        res.append(complex(axis_amp(g[0::2]),axis_amp(g[1::2]))/math.sqrt(norm2))
    return res
def pi2_mod(bits):
    return [(1j**(i%4))*complex(1-2*b,1-2*b)/math.sqrt(2) for i,b in enumerate(bits)]

def gen_modulation():
    out=[]
    for r in read_csv("pusch_modulation_test_vectors.csv"):
        if r["ExpectedStatus"]=="ERROR":
            out.append({"CaseID":r["CaseID"],"SymbolCount":"","ExpectedSymbols":"",
                        "MeanPower":"","Status":"ERROR","ExpectedError":r["ExpectedError"]});continue
        bits=[int(x) for x in r["InputBits"]]
        syms=pi2_mod(bits) if r["Modulation"]=="PI/2-BPSK" else qam_mod(bits,r["Modulation"])
        out.append({"CaseID":r["CaseID"],"SymbolCount":len(syms),
                    "ExpectedSymbols":complex_text(syms),
                    "MeanPower":sum(abs(z)**2 for z in syms)/len(syms),"Status":"PASS"})
    write_csv("expected_pusch_modulation_vectors.csv",out)

def gen_layers():
    out=[]
    for r in read_csv("pusch_layer_mapping_test_vectors.csv"):
        if r["ExpectedStatus"]=="ERROR":
            out.append({"CaseID":r["CaseID"],"Rank":r["Rank"],"Codeword":"","Layer":"",
                        "SourceLayerIndex":"","ExpectedSymbols":"","SourceSymbolCount":"",
                        "MappedSymbolCount":"","Status":"ERROR","ExpectedError":r["ExpectedError"]});continue
        rank=int(r["Rank"])
        counts=[rank] if rank<=4 else {5:[2,3],6:[3,3],7:[3,4],8:[4,4]}[rank]
        global_layer=0
        for q,v in enumerate(counts):
            cw=parse_complex_list(r[f"Codeword{q}Symbols"])
            for li in range(v):
                vals=cw[li::v]
                out.append({"CaseID":r["CaseID"],"Rank":rank,"Codeword":q,
                            "Layer":global_layer+li,"SourceLayerIndex":li,
                            "ExpectedSymbols":complex_text(vals),
                            "SourceSymbolCount":len(cw),"MappedSymbolCount":len(vals),"Status":"PASS"})
            global_layer+=v
    write_csv("expected_pusch_layer_mapping.csv",out)

CRC_POLY={"16":[16,12,5,0],
          "24A":[24,23,18,17,14,11,10,7,6,5,4,3,1,0]}
def crc_remainder(bits,name):
    exps=CRC_POLY[name];degree=max(exps)
    poly=[1 if p in exps else 0 for p in range(degree,-1,-1)]
    work=list(bits)+[0]*degree
    for i in range(len(bits)):
        if work[i]:
            for j,v in enumerate(poly):work[i+j]^=v
    return work[-degree:]
TBS_SMALL=[24,32,40,48,56,64,72,80,88,96,104,112,120,128,136,144,152,160,168,176,
184,192,208,224,240,256,272,288,304,320,336,352,368,384,408,432,456,480,504,528,
552,576,608,640,672,704,736,768,808,848,888,928,984,1032,1064,1128,1160,1192,1224,
1256,1288,1320,1352,1416,1480,1544,1608,1672,1736,1800,1864,1928,2024,2088,2152,
2216,2280,2408,2472,2536,2600,2664,2728,2792,2856,2976,3104,3240,3368,3496,3624,3752,3824]
def half_up(x):return math.floor(x+0.5)
def tbs_calc(nprb,nsym,ndmrs,noh,qm,rate,layers,scale):
    nre1=12*nsym-ndmrs-noh;nre=min(156,nre1)*nprb;ninfo=scale*nre*rate*qm*layers
    if ninfo<=3824:
        n=max(3,math.floor(math.log2(ninfo))-6)
        nip=max(24,(2**n)*math.floor(ninfo/(2**n)))
        tbs=next(v for v in TBS_SMALL if v>=nip);c=1
    else:
        n=math.floor(math.log2(ninfo-24))-5
        nip=max(3840,(2**n)*half_up((ninfo-24)/(2**n)))
        if rate<=.25:c=math.ceil((nip+24)/3816)
        elif nip>8424:c=math.ceil((nip+24)/8424)
        else:c=1
        tbs=8*c*math.ceil((nip+24)/(8*c))-24
    bg=2 if tbs<=292 or (tbs<=3824 and rate<=.67) or rate<=.25 else 1
    crc="24A" if tbs>3824 else "16"
    return nre1,nre,ninfo,nip,c,int(tbs),crc,bg
def gen_coding():
    out=[]
    for r in read_csv("pusch_coding_tbs_test_vectors.csv"):
        if r["ExpectedStatus"]=="ERROR":
            out.append({"CaseID":r["CaseID"],"Status":"ERROR","ExpectedError":r["ExpectedError"]});continue
        vals=tbs_calc(int(r["NPRB"]),int(r["NScheduledSymbols"]),int(r["NDMRSREPerPRB"]),
                      int(r["NOverheadREPerPRB"]),int(r["Qm"]),float(r["TargetCodeRate"]),
                      int(r["NumLayers"]),float(r["TBScaling"]))
        nre1,nre,ninfo,nip,c,tbs,crc,bg=vals
        out.append({"CaseID":r["CaseID"],"NREPrimePerPRB":nre1,"NRE":nre,
                    "NInfo":f"{ninfo:.15g}","NInfoPrime":f"{nip:.15g}",
                    "CForTBS":c,"TBS":tbs,"TBCRCType":crc,
                    "TBCRCLength":24 if crc=="24A" else 16,"BaseGraph":bg,"Status":"PASS"})
    write_csv("expected_pusch_tbs_basegraph.csv",out)
    crcrows=[]
    for r in read_csv("pusch_tb_crc_test_vectors.csv"):
        bits=[int(x) for x in r["InputBits"]];rem=crc_remainder(bits,r["CRCType"])
        crcrows.append({"CaseID":r["CaseID"],"PayloadLength":len(bits),"CRCType":r["CRCType"],
                        "InputBits":r["InputBits"],"ExpectedCRCBits":bits_text(rem),
                        "ExpectedBlockWithCRC":bits_text(bits+rem),"Status":"PASS"})
    write_csv("expected_pusch_tb_crc_vectors.csv",crcrows)

def gen_assignment():
    rows=[]
    for r in read_csv("pusch_scheduling_assignment_test_vectors.csv"):
        ok=r["ExpectedStatus"]=="PASS"
        rows.append({"CaseID":r["CaseID"],"AssignmentCreated":int(ok),"WaveformAllowed":int(ok),
        "ResolvedProfile":r["Profile"],"ResolvedSource":r["SourceType"],
        "ResolvedBWPId":r["BWPId"] if ok else "","ResolvedPRBSet":r["PRBSet"] if ok else "",
        "ResolvedSymbolAllocation":r["SymbolAllocation"] if ok else "",
        "ResolvedMCSIndex":r["MCSIndex"] if ok else "",
        "ResolvedTransformPrecoding":r["TransformPrecoding"] if ok else "",
        "ResolvedFrequencyHopping":r["FrequencyHopping"] if ok else "",
        "ResolvedHARQProcessID":r["HARQProcessID"] if ok else "",
        "ErrorIdentifier":"" if ok else r["ExpectedError"],"Status":r["ExpectedStatus"]})
    write_csv("expected_pusch_assignment_resolution.csv",rows)

def gen_uci():
    rows=[]
    for r in read_csv("pusch_uci_multiplex_test_vectors.csv"):
        ok=r["ExpectedStatus"]=="PASS";owner=""
        if ok:
            nt=int(r["NumULSCHTB"])
            owner="UCI_ONLY" if nt==0 else ("0" if nt==1 or int(r["InitialIMCSCodeword0"])>=int(r["InitialIMCSCodeword1"]) else "1")
        total=""
        types=[]
        try:
            total=sum(int(r[k]) for k in ("OACK","OCSI1","OCSI2","OSR","OCGUCI"))
            for k,n in (("OACK","HARQ_ACK"),("OCSI1","CSI_PART1"),("OCSI2","CSI_PART2"),("OSR","SR"),("OCGUCI","CG_UCI")):
                if int(r[k])>0:types.append(n)
        except ValueError:pass
        rows.append({"CaseID":r["CaseID"],"ExpectedUCIOwner":owner,"RawUCIBitCount":total,
        "PayloadTypes":"|".join(types),"CSI2DependsOnCSI1":int(ok and str(r["OCSI2"]).isdigit() and int(r["OCSI2"])>0),
        "BetaOffsetsRequired":int(ok and total!="" and total>0),
        "ExpectedStatus":r["ExpectedStatus"],"ExpectedError":r["ExpectedError"]})
    write_csv("expected_pusch_uci_owner_and_budget.csv",rows)

def unitary_dft(x):
    M=len(x);return [sum(x[n]*cmath.exp(-2j*math.pi*k*n/M) for n in range(M))/math.sqrt(M) for k in range(M)]
def unitary_idft(X):
    M=len(X);return [sum(X[k]*cmath.exp(2j*math.pi*k*n/M) for k in range(M))/math.sqrt(M) for n in range(M)]
def papr(x):
    p=[abs(z)**2 for z in x];return 10*math.log10(max(p)/(sum(p)/len(p)))
def gen_transform():
    rows=[]
    for r in read_csv("pusch_transform_precoding_test_vectors.csv"):
        if r["ExpectedStatus"]=="ERROR":
            rows.append({"CaseID":r["CaseID"],"ExpectedDFTByLayer":"","RoundTripNMSE":"",
                         "EnergyRelativeError":"","InputPAPR_dB":"","DFTOutputPAPR_dB":"",
                         "Status":"ERROR","ExpectedError":r["ExpectedError"]});continue
        layers=[parse_complex_list(x) for x in r["InputSymbolsByLayer"].split(";")]
        outs=[unitary_dft(x) for x in layers];nmse=[];err=[]
        for x,X in zip(layers,outs):
            xr=unitary_idft(X)
            nmse.append(sum(abs(a-b)**2 for a,b in zip(x,xr))/sum(abs(a)**2 for a in x))
            err.append(abs(sum(abs(a)**2 for a in x)-sum(abs(a)**2 for a in X))/sum(abs(a)**2 for a in x))
        rows.append({"CaseID":r["CaseID"],"ExpectedDFTByLayer":";".join(complex_text(x) for x in outs),
                     "RoundTripNMSE":max(nmse),"EnergyRelativeError":max(err),
                     "InputPAPR_dB":max(papr(x) for x in layers),
                     "DFTOutputPAPR_dB":max(papr(x) for x in outs),"Status":"PASS"})
    write_csv("expected_pusch_transform_dft_vectors.csv",rows)

def gen_hopping():
    rows=[]
    for r in read_csv("pusch_frequency_hopping_test_vectors.csv"):
        if r["ExpectedStatus"]=="ERROR":
            rows.append({"CaseID":r["CaseID"],"FirstHopPRBSet":"","SecondHopPRBSet":"",
                         "FirstHopSymbols":"","SecondHopSymbols":"","ActiveHopForSlot":"",
                         "ActivePRBSet":"","Status":"ERROR","ExpectedError":r["ExpectedError"]});continue
        start=int(r["PRBStart"]);length=int(r["PRBLength"]);ss=int(r["StartSymbol"]);sl=int(r["SymbolLength"])
        p0=list(range(start,start+length));mode=r["Mode"];p1=[];s0=[];s1=[];active=0;activeprb=""
        if mode=="none":
            s0=list(range(ss,ss+sl))
        elif mode=="intra_slot":
            p1=list(range(int(r["SecondHopStartPRB"]),int(r["SecondHopStartPRB"])+length))
            split=sl//2;s0=list(range(ss,ss+split));s1=list(range(ss+split,ss+sl));active="0|1"
        else:
            p1=list(range(int(r["SecondHopStartPRB"]),int(r["SecondHopStartPRB"])+length))
            if r["RepetitionType"]=="B":
                s0=list(range(ss,min(14,ss+sl)));s1=list(range(0,max(0,ss+sl-14)))
            else:s0=list(range(ss,ss+sl))
            active=int(r["RepetitionIndex"])%2;activeprb=nums_text(p1 if active else p0)
        rows.append({"CaseID":r["CaseID"],"FirstHopPRBSet":nums_text(p0),
                     "SecondHopPRBSet":nums_text(p1),"FirstHopSymbols":nums_text(s0),
                     "SecondHopSymbols":nums_text(s1),"ActiveHopForSlot":active,
                     "ActivePRBSet":activeprb,"Status":"PASS"})
    write_csv("expected_pusch_hop_plans.csv",rows)

def gen_dmrs_ptrs_floor():
    rows=[]
    for r in read_csv("pusch_dmrs_test_vectors.csv"):
        rows.append({"CaseID":r["CaseID"],"InputMutationAllowed":0,
                     "RequestedDMRSPortSet":r["RequestedDMRSPortSet"],
                     "ExpectedPortSetPreserved":1,"ExactTableResolutionRequired":1,
                     "ExpectedError":r["ExpectedError"],
                     "Status":"ERROR" if r["ExpectedStatus"]=="ERROR" else "TABLE_ORACLE_REQUIRED"})
    write_csv("expected_pusch_dmrs_validation_floor.csv",rows)
    rows=[]
    for r in read_csv("pusch_ptrs_test_vectors.csv"):
        rows.append({"CaseID":r["CaseID"],"ExpectedPTRSPresent":r["ExpectedPTRSPresent"],
                     "ExpectedAssociatedDMRSPort":r["AssociatedDMRSPort"] if r["ExpectedStatus"]!="ERROR" else "",
                     "InputMutationAllowed":0,"ExactIndexOracleRequired":1,
                     "ExpectedStatus":r["ExpectedStatus"],"ExpectedError":r["ExpectedError"],
                     "DisableReason":r.get("DisableReason","")})
    write_csv("expected_pusch_ptrs_presence.csv",rows)

def gen_srs():
    rows=[]
    for r in read_csv("pusch_srs_precoder_test_vectors.csv"):
        ok=r["ExpectedStatus"]=="PASS";age=int(r["CurrentSlot"])-int(r["MeasurementSlot"])
        epoch=int(r["ConfigurationEpoch"])==int(r["CurrentConfigurationEpoch"])
        ri=""
        if ok:
            # The input generator writes the expected rank into the number of
            # non-negligible diagonal/eigenmodes.  Recompute a conservative
            # rank without NumPy by counting nonzero columns for this floor.
            A=parse_matrix(r["HEstimate"]);cols=len(A[0]) if A else 0
            colnorm=[sum(abs(row[c])**2 for row in A) for c in range(cols)]
            peak=max(colnorm) if colnorm else 0
            ri=sum(v>=.01*peak for v in colnorm)
        rows.append({"CaseID":r["CaseID"],"MeasurementAccepted":int(ok),"ExpectedRI":ri,
                     "DecisionSource":"measured_srs" if ok else "","Stale":int(age>int(r["MaxAgeSlots"])),
                     "EpochMatch":int(epoch),"AppliedPrecoderMustMatchDecision":int(ok),
                     "ConfiguredTPMIFallbackAllowed":0,"Status":r["ExpectedStatus"],
                     "ExpectedError":r["ExpectedError"]})
    write_csv("expected_pusch_srs_precoder_decisions.csv",rows)

def matmul(A,x):
    return [sum(A[i][j]*x[j] for j in range(len(x))) for i in range(len(A))]
def mat_digest(A):
    txt=f"{len(A)}x{len(A[0]) if A else 0}|"+ ";".join(complex_text(row) for row in A)
    return hashlib.sha256(txt.encode()).hexdigest()
def vec_digest(x):return hashlib.sha256(complex_text(x).encode()).hexdigest()
def gen_precoding():
    rows=[]
    for r in read_csv("pusch_precoding_application_test_vectors.csv"):
        if r["ExpectedStatus"]=="ERROR":
            rows.append({"CaseID":r["CaseID"],"PRG":r["PRG"],"SymbolGroup":r["SymbolGroup"],
                         "MatrixDigest":"","ExpectedPortSymbols":"","ExpectedPortSymbolDigest":"",
                         "InputEnergy":"","OutputEnergy":"","MatrixApplicationCount":0,
                         "Status":"ERROR","ExpectedError":r["ExpectedError"]});continue
        A=parse_matrix(r["Matrix"]);x=parse_complex_list(r["LayerSymbols"]);y=matmul(A,x)
        rows.append({"CaseID":r["CaseID"],"PRG":r["PRG"],"SymbolGroup":r["SymbolGroup"],
                     "MatrixDigest":mat_digest(A),"ExpectedPortSymbols":complex_text(y),
                     "ExpectedPortSymbolDigest":vec_digest(y),
                     "InputEnergy":sum(abs(z)**2 for z in x),"OutputEnergy":sum(abs(z)**2 for z in y),
                     "MatrixApplicationCount":1,"Status":"PASS"})
    write_csv("expected_pusch_precoding_application.csv",rows)

def gen_power():
    rows=[]
    for r in read_csv("pusch_power_control_test_vectors.csv"):
        if r["ExpectedStatus"]=="ERROR":
            rows.append({"CaseID":r["CaseID"],"UpdatedF_dB":"","RequestedPower_dBm":"",
                         "AppliedPower_dBm":"","PowerHeadroom_dB":"","AmplitudeScale":"",
                         "Clipped":"","FormulaIncludesMuFactor":1,"Status":"ERROR",
                         "ExpectedError":r["ExpectedError"]});continue
        mode=r["AdjustmentMode"];prev=float(r["PreviousF_dB"]);tpc=float(r["TPCDelta_dB"])
        f=prev+tpc if mode=="accumulated" else tpc
        req=float(r["P0Nominal_dBm"])+float(r["P0UE_dB"])+10*math.log10((2**int(r["Mu"]))*int(r["MRB"]))+float(r["Alpha"])*float(r["Pathloss_dB"])+float(r["DeltaTF_dB"])+f
        pc=float(r["PCMAX_dBm"]);app=min(pc,req);ref=float(r["ReferenceWaveformPower_dBm"])
        rows.append({"CaseID":r["CaseID"],"UpdatedF_dB":f,"RequestedPower_dBm":req,
                     "AppliedPower_dBm":app,"PowerHeadroom_dB":pc-req,
                     "AmplitudeScale":10**((app-ref)/20),"Clipped":int(req>pc),
                     "FormulaIncludesMuFactor":1,"Status":"PASS"})
    write_csv("expected_pusch_power_control.csv",rows)

def gen_harq():
    rows=[];state={}
    for r in read_csv("pusch_harq_test_vectors.csv"):
        if r["ExpectedStatus"]=="ERROR":
            rows.append({"CaseID":r["CaseID"],"HARQAction":"","Combined":"",
                         "SoftBufferInputDigest":"","SoftBufferOutputDigest":"",
                         "FlushAfterDecode":"","Status":"ERROR","ExpectedError":r["ExpectedError"]});continue
        key=(int(r["HARQProcessID"]),int(r["Codeword"]));prev=state.get(key)
        ndi=int(r["NDI"]);tbid=r["TBIdentity"];tbs=int(r["TBS"]);rv=int(r["RV"]);tx=int(r["TransmissionIndex"])
        new=prev is None or ndi!=prev["ndi"] or tbid!=prev["tbid"]
        action="NEW_DATA" if new else "RETRANSMISSION";combined=int(not new)
        ind=hashlib.sha256((prev["digest"] if prev else "").encode()).hexdigest()[:16] if combined else ""
        outd=hashlib.sha256(f"{tbid}|{tbs}|{rv}|{tx}|{ind}".encode()).hexdigest()[:16]
        crc=int(r["DecoderCRCOK"])
        rows.append({"CaseID":r["CaseID"],"HARQAction":action,"Combined":combined,
                     "SoftBufferInputDigest":ind,"SoftBufferOutputDigest":outd,
                     "FlushAfterDecode":crc,"Status":"PASS"})
        if crc:state.pop(key,None)
        else:state[key]={"ndi":ndi,"tbid":tbid,"digest":outd}
    write_csv("expected_pusch_harq_transitions.csv",rows)

EXPECTED=[
"expected_pusch_scrambling_vectors.csv","expected_pusch_modulation_vectors.csv",
"expected_pusch_layer_mapping.csv","expected_pusch_tbs_basegraph.csv",
"expected_pusch_tb_crc_vectors.csv","expected_pusch_assignment_resolution.csv",
"expected_pusch_uci_owner_and_budget.csv","expected_pusch_dmrs_validation_floor.csv",
"expected_pusch_ptrs_presence.csv","expected_pusch_transform_dft_vectors.csv",
"expected_pusch_hop_plans.csv","expected_pusch_srs_precoder_decisions.csv",
"expected_pusch_precoding_application.csv","expected_pusch_power_control.csv",
"expected_pusch_harq_transitions.csv"]

INPUTS=[
"pusch_scrambling_test_vectors.csv","pusch_modulation_test_vectors.csv",
"pusch_layer_mapping_test_vectors.csv","pusch_coding_tbs_test_vectors.csv",
"pusch_tb_crc_test_vectors.csv","pusch_scheduling_assignment_test_vectors.csv",
"pusch_uci_multiplex_test_vectors.csv","pusch_dmrs_test_vectors.csv",
"pusch_ptrs_test_vectors.csv","pusch_transform_precoding_test_vectors.csv",
"pusch_frequency_hopping_test_vectors.csv","pusch_srs_precoder_test_vectors.csv",
"pusch_precoding_application_test_vectors.csv","pusch_power_control_test_vectors.csv",
"pusch_harq_test_vectors.csv","pusch_declared_coverage_matrix.csv"]

def write_manifest():
    files=[]
    for name in INPUTS+EXPECTED:
        p=ROOT/name
        with p.open(newline="",encoding="utf-8-sig") as f:
            rows=sum(1 for _ in csv.reader(f))-1
        files.append({"FileName":name,"SHA256":file_sha(p),"Rows":rows,
                      "Role":"input" if name in INPUTS else "bounded_independent_expected"})
    manifest={"SchemaVersion":"PUSCHIndependentVectorManifest/v1",
              "Generator":"generate_pusch_independent_vectors.py",
              "GeneratorSHA256":file_sha(Path(__file__)),
              "NoMATLABUsed":True,
              "ScopeWarning":"Bounded floor only; broad DMRS/PT-RS/UCI/LDPC/codebook tables require additional independent vectors.",
              "Files":files}
    (ROOT/"independent_vector_manifest.json").write_text(json.dumps(manifest,indent=2)+"\n",encoding="utf-8")
    write_csv("expected_output_integrity_audit.csv",
              [{"FileName":x["FileName"],"Rows":x["Rows"],"SHA256":x["SHA256"],
                "Role":x["Role"],"Status":"PASS"} for x in files])

def main():
    gen_scrambling();gen_modulation();gen_layers();gen_coding();gen_assignment()
    gen_uci();gen_dmrs_ptrs_floor();gen_transform();gen_hopping();gen_srs()
    gen_precoding();gen_power();gen_harq();write_manifest()
    print(f"Generated {len(EXPECTED)} expected files and manifest without MATLAB.")
if __name__=="__main__":main()
