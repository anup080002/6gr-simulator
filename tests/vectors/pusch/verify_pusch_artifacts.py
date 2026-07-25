#!/usr/bin/env python3
"""Fail-closed verifier for PUSCH/UL-SCH phase CSV and PNG artifacts.

The MATLAB phase runner must generate production-derived artifacts.  This
verifier checks presence, schemas, primary-key uniqueness, technical
cross-field invariants, mandatory-test completion, receiver-derived SINR,
statistical campaign status, PNG integrity, and MATLAB-recorded figure
semantics.  It does not infer plot meaning from pixels.
"""
from __future__ import annotations
import argparse, csv, hashlib, math, sys, tempfile
from dataclasses import dataclass
from pathlib import Path
from typing import Iterable, Sequence
try:
    from PIL import Image, ImageDraw, ImageStat
except ImportError as exc:
    raise SystemExit("Pillow is required: python -m pip install Pillow") from exc

HERE=Path(__file__).resolve().parent
CSV_CONTRACT_FILE=HERE/"desired_pusch_csv_contract.csv"
IMAGE_CONTRACT_FILE=HERE/"desired_pusch_image_contract.csv"

@dataclass(frozen=True)
class CsvContract:
    name:str; columns:tuple[str,...]; key:tuple[str,...]
@dataclass(frozen=True)
class ImageContract:
    name:str; sources:tuple[str,...]; xlabel:str; ylabel:str; title_token:str
    min_axes:int; min_series:int; min_points:int; min_width:int; min_height:int

def digest(path:Path)->str:
    h=hashlib.sha256()
    with path.open("rb") as f:
        for b in iter(lambda:f.read(1024*1024),b""):h.update(b)
    return h.hexdigest()

def finite(v):
    try:x=float(str(v).strip())
    except (ValueError,TypeError):return None
    return x if math.isfinite(x) else None
def integer(v):
    x=finite(v)
    return int(round(x)) if x is not None and abs(x-round(x))<=1e-9 else None
def truth(v):
    t=str(v).strip().upper()
    if t in {"1","TRUE","YES","Y","PASS"}:return True
    if t in {"0","FALSE","NO","N","FAIL"}:return False
    return None
def norm(v):return " ".join(str(v).strip().split())
def split_tokens(v):return [x for x in str(v).replace(",","|").split("|") if x!=""]

def read_contracts():
    cc={}
    with CSV_CONTRACT_FILE.open(newline="",encoding="utf-8-sig") as f:
        for r in csv.DictReader(f):
            if truth(r.get("Required","1")) is False:continue
            name=r["FileName"].strip()
            cc[name]=CsvContract(name,tuple(x.strip() for x in r["RequiredColumns"].split("|") if x.strip()),
                                  tuple(x.strip() for x in r["PrimaryKey"].split("|") if x.strip()))
    ic={}
    with IMAGE_CONTRACT_FILE.open(newline="",encoding="utf-8-sig") as f:
        for r in csv.DictReader(f):
            name=r["ImageFile"].strip()
            ic[name]=ImageContract(name,tuple(x.strip() for x in r["SourceCSV"].split("|") if x.strip()),
                r["ExpectedXLabel"].strip(),r["ExpectedYLabel"].strip(),r["ExpectedTitleToken"].strip(),
                int(r["MinAxesCount"]),int(r["MinSeriesCount"]),int(r["MinFinitePointCount"]),
                int(r["MinWidth"]),int(r["MinHeight"]))
    return cc,ic

def read_rect(path):
    with path.open(newline="",encoding="utf-8-sig") as f:raw=list(csv.reader(f))
    if not raw:return [],[],["empty_file"]
    head=raw[0];err=[]
    if any(not x.strip() for x in head):err.append("empty_header")
    if len(set(head))!=len(head):err.append("duplicate_header")
    for i,row in enumerate(raw[1:],2):
        if len(row)!=len(head):err.append(f"nonrectangular_line:{i}")
    rows=[dict(zip(head,r,strict=True)) for r in raw[1:] if len(r)==len(head)]
    if not rows:err.append("no_data_rows")
    return head,rows,err

def dup_keys(rows,fields):
    seen=set();dup=[]
    for line,r in enumerate(rows,2):
        key=tuple(r.get(f,"") for f in fields)
        if key in seen:dup.append(f"line={line}:key={key}")
        seen.add(key)
    return dup

def result(name,kind,reasons,**extra):
    d={"Artifact":name,"Type":kind,"Status":"PASS" if not reasons else "FAIL","Reason":";".join(reasons)}
    d.update(extra);return d

def require_nonneg(r,f,line,reasons):
    x=finite(r.get(f,""))
    if x is None or x<0:reasons.append(f"invalid_nonnegative:{f}:line={line}")
    return x
def require_prob(r,f,line,reasons):
    x=finite(r.get(f,""))
    if x is None or not 0<=x<=1:reasons.append(f"invalid_probability:{f}:line={line}")
    return x

REQUIRED_VECTOR_FAMILIES={
"scrambling","modulation","layer_mapping","tbs_basegraph","tb_crc",
"ldpc_segmentation","ldpc_encoding","rate_matching","uci_coding_multiplexing",
"dmrs_positions_ports_sequence","ptrs_indices_sequence","transform_precoding",
"frequency_hopping","pusch_codebook","srs_precoder_selection","power_control",
"harq_combining","receiver_chain"}

def validate_specific(name,rows,reasons):
    if name=="pusch_assignment_resolution.csv":
        for line,r in enumerate(rows,2):
            created=truth(r.get("AssignmentCreated"));allowed=truth(r.get("WaveformAllowed"))
            if created is None or allowed is None:reasons.append(f"invalid_assignment_flags:line={line}");continue
            if allowed and not created:reasons.append(f"waveform_without_assignment:line={line}")
            err=str(r.get("ErrorIdentifier","")).strip()
            if not created:
                if allowed:reasons.append(f"rejected_assignment_waveform:line={line}")
                if not err:reasons.append(f"rejected_assignment_missing_error:line={line}")
                continue
            if err:reasons.append(f"created_assignment_has_error:line={line}")
            p=str(r.get("Profile","")).lower();src=str(r.get("AssignmentSource","")).lower()
            if p=="connected_dynamic_strict":
                if "decoded" not in src:reasons.append(f"dynamic_source_not_decoded:line={line}")
                if not str(r.get("DecodedDCIId","")).strip():reasons.append(f"missing_dci_id:line={line}")
                if not str(r.get("DCIFormat","")).startswith("0_"):reasons.append(f"invalid_dci_format:line={line}")
                if truth(r.get("DCICRCPass")) is not True:reasons.append(f"dci_crc_not_pass:line={line}")
                if truth(r.get("DCIRNTIMatch")) is not True:reasons.append(f"dci_rnti_not_match:line={line}")
            elif p=="configured_grant_type1_strict":
                if truth(r.get("CGInstalled")) is not True or truth(r.get("CGReleased")) is not False or truth(r.get("CGOccasionMatch")) is not True:
                    reasons.append(f"invalid_type1_cg_state:line={line}")
            elif p=="configured_grant_type2_strict":
                if not all(truth(r.get(x)) is True for x in ("CGInstalled","CGActivated","CGOccasionMatch","DCICRCPass","DCIRNTIMatch")):
                    reasons.append(f"invalid_type2_cg_activation:line={line}")
                if truth(r.get("CGReleased")) is not False:reasons.append(f"type2_cg_released:line={line}")
                if "CS-RNTI" not in str(r.get("RNTIType","")).upper():reasons.append(f"type2_wrong_rnti:line={line}")
            elif p=="random_access_ul_strict":
                if not str(r.get("RARGrantID","")).strip():reasons.append(f"missing_ra_grant_id:line={line}")
                if not any(x in src for x in ("rar","msga")):reasons.append(f"wrong_ra_source:line={line}")
            elif p=="phy_calibration":
                if "calibration" not in src:reasons.append(f"wrong_calibration_source:line={line}")
            else:reasons.append(f"unknown_profile:line={line}:{p}")
            for f in ("MCSIndex","NumLayers","NumCodewords","NDI","RV","HARQProcessID"):
                if integer(r.get(f)) is None:reasons.append(f"invalid_integer:{f}:line={line}")
            if not str(r.get("PRBSet","")).strip() or not str(r.get("SymbolAllocation","")).strip():
                reasons.append(f"missing_resolved_resources:line={line}")
    elif name=="pusch_resource_ownership.csv":
        for line,r in enumerate(rows,2):
            if integer(r.get("CollisionCount"))!=0:reasons.append(f"resource_collision:line={line}")
    elif name=="pusch_dmrs_matrix.csv":
        for line,r in enumerate(rows,2):
            if norm(r.get("RequestedDMRSPortSet"))!=norm(r.get("AppliedDMRSPortSet")):
                reasons.append(f"dmrs_port_mutation:line={line}")
            if integer(r.get("InputMutationCount"))!=0:reasons.append(f"dmrs_input_mutation:line={line}")
            if integer(r.get("IndexMismatchCount"))!=0:reasons.append(f"dmrs_index_mismatch:line={line}")
            nmse=finite(r.get("SequenceNMSE"))
            if nmse is None or nmse>1e-10:reasons.append(f"dmrs_sequence_nmse:line={line}:{nmse}")
    elif name=="pusch_ptrs_matrix.csv":
        for line,r in enumerate(rows,2):
            if integer(r.get("InputMutationCount"))!=0:reasons.append(f"ptrs_input_mutation:line={line}")
            if integer(r.get("IndexMismatchCount"))!=0:reasons.append(f"ptrs_index_mismatch:line={line}")
            present=truth(r.get("ExpectedPresent"))
            if present:
                if (integer(r.get("PTRSRECount")) or 0)<=0:reasons.append(f"ptrs_missing_re:line={line}")
                if str(r.get("AssociatedDMRSPort","")).strip()=="":reasons.append(f"ptrs_missing_dmrs_association:line={line}")
                before=finite(r.get("EVMBeforePercent"));after=finite(r.get("EVMAfterPercent"))
                if before is not None and after is not None and after>before+1e-9:reasons.append(f"ptrs_evm_not_improved:line={line}")
    elif name=="pusch_uci_multiplexing.csv":
        owner_by_case={}
        for line,r in enumerate(rows,2):
            counts=[]
            for f in ("OACK","OCSI1","OCSI2","OCGUCI","ULSCHBitCount","ACKCodedBitCount","CSI1CodedBitCount","CSI2CodedBitCount","CGUCICodedBitCount","PlaceholderXCount","PlaceholderYCount"):
                x=require_nonneg(r,f,line,reasons);counts.append(x)
            g=integer(r.get("G"));mux=integer(r.get("MuxedBitCount"))
            if g is None or mux!=g:reasons.append(f"uci_mux_count_not_G:line={line}")
            if truth(r.get("PayloadMatch")) is not True:reasons.append(f"uci_payload_mismatch:line={line}")
            owner=str(r.get("UCIOwnerCodeword","")).strip()
            raw=sum(integer(r.get(f)) or 0 for f in ("OACK","OCSI1","OCSI2","OCGUCI"))
            if raw>0 and owner=="":reasons.append(f"uci_owner_missing:line={line}")
            if raw>0:owner_by_case.setdefault(r["CaseID"],set()).add(owner)
            for bits,crcfield in (("OACK","ACKCRCOK"),("OCSI1","CSI1CRCOK"),("OCSI2","CSI2CRCOK")):
                if (integer(r.get(bits)) or 0)>0 and truth(r.get(crcfield)) is not True:
                    reasons.append(f"uci_crc_not_ok:{crcfield}:line={line}")
        for case,owners in owner_by_case.items():
            if len(owners)!=1:reasons.append(f"uci_multiple_owner_codewords:{case}:{owners}")
    elif name=="pusch_coding_chain.csv":
        for line,r in enumerate(rows,2):
            g=integer(r.get("G"));rm=integer(r.get("RateMatchedBits"))
            if g is None or rm!=g:reasons.append(f"rate_match_count_not_G:line={line}")
            if truth(r.get("CRCOK")) is not True:reasons.append(f"coding_crc_fail:line={line}")
    elif name=="pusch_independent_vector_results.csv":
        fam=set()
        for line,r in enumerate(rows,2):
            fam.add(str(r.get("VectorFamily","")).strip())
            if integer(r.get("MismatchCount"))!=0:reasons.append(f"oracle_mismatch:line={line}")
            e=finite(r.get("MaxAbsError"));t=finite(r.get("Tolerance"))
            if e is None or t is None or e>t:reasons.append(f"oracle_error_over_tolerance:line={line}")
            cls=str(r.get("IndependenceClass","")).lower()
            if any(x in cls for x in ("same_toolbox","self_consistency","same_implementation")):
                reasons.append(f"nonindependent_oracle:line={line}")
            h=str(r.get("OracleArtifactSHA256","")).strip()
            if len(h)!=64 or any(c not in "0123456789abcdefABCDEF" for c in h):
                reasons.append(f"invalid_oracle_hash:line={line}")
        missing=sorted(REQUIRED_VECTOR_FAMILIES-fam)
        if missing:reasons.append("missing_vector_families:"+",".join(missing))
    elif name=="pusch_codeword_layer_map.csv":
        groups={}
        for line,r in enumerate(rows,2):
            if integer(r.get("MismatchCount"))!=0:reasons.append(f"layer_mapping_mismatch:line={line}")
            key=(r["CaseID"],r["Codeword"]);groups.setdefault(key,[integer(r.get("SourceSymbolCount")),0])
            groups[key][1]+=(integer(r.get("MappedSymbolCount")) or 0)
        for key,(source,total) in groups.items():
            if source is None or source!=total:reasons.append(f"layer_symbol_conservation:{key}:{source}!={total}")
    elif name=="pusch_transform_precoding.csv":
        for line,r in enumerate(rows,2):
            if integer(r.get("InputSymbolCount"))!=integer(r.get("OutputSymbolCount")):reasons.append(f"dft_count_mismatch:line={line}")
            v=finite(r.get("EnergyRelativeError"))
            if v is None or v>1e-10:reasons.append(f"dft_energy_error:line={line}")
            v=finite(r.get("RoundTripNMSE"))
            if v is None or v>1e-10:reasons.append(f"dft_roundtrip_nmse:line={line}")
    elif name=="pusch_frequency_hopping.csv":
        for line,r in enumerate(rows,2):
            if integer(r.get("PRBMismatchCount"))!=0:reasons.append(f"hop_prb_mismatch:line={line}")
            if norm(r.get("PRBSet"))!=norm(r.get("ExpectedPRBSet")):reasons.append(f"hop_set_not_expected:line={line}")
            if integer(r.get("ResourceAllocationType"))==2 and str(r.get("Mode","")).lower()!="none":
                reasons.append(f"type2_hopping_not_rejected:line={line}")
    elif name=="pusch_srs_precoder_selection.csv":
        for line,r in enumerate(rows,2):
            if truth(r.get("DecisionValid")) is not True:reasons.append(f"srs_decision_invalid:line={line}")
            if "measured" not in str(r.get("DecisionSource","")).lower():reasons.append(f"srs_not_measurement_driven:line={line}")
            age=integer(r.get("AgeSlots"));maxage=integer(r.get("MaxAgeSlots"))
            if age is None or maxage is None or age>maxage:reasons.append(f"stale_srs_used:line={line}")
            if integer(r.get("MeasurementConfigurationEpoch"))!=integer(r.get("CurrentConfigurationEpoch")):
                reasons.append(f"srs_epoch_mismatch:line={line}")
            if norm(r.get("DecisionID"))!=norm(r.get("AppliedDecisionID")):reasons.append(f"srs_decision_not_applied:line={line}")
            if norm(r.get("SelectedTPMI"))!=norm(r.get("AppliedTPMI")):reasons.append(f"tpmi_decision_not_applied:line={line}")
            if truth(r.get("ConfiguredTPMIFallbackUsed")) is not False:reasons.append(f"configured_tpmi_fallback:line={line}")
    elif name=="pusch_precoding_application.csv":
        for line,r in enumerate(rows,2):
            if norm(r.get("MatrixDigest"))!=norm(r.get("AppliedMatrixDigest")):reasons.append(f"precoder_digest_mismatch:line={line}")
            if (integer(r.get("MatrixApplicationCount")) or 0)<1:reasons.append(f"precoder_not_applied:line={line}")
            v=finite(r.get("PowerRelativeError"))
            if v is None or v>1e-10:reasons.append(f"precoder_power_error:line={line}")
    elif name=="pusch_power_control.csv":
        for line,r in enumerate(rows,2):
            mu=integer(r.get("Mu"));mrb=integer(r.get("MRB"))
            vals=[finite(r.get(x)) for x in ("P0Nominal_dBm","P0UE_dB","Alpha","MeasuredPathloss_dB","DeltaTF_dB","UpdatedF_dB","RequestedPower_dBm","PCMAX_dBm","AppliedPower_dBm")]
            if mu is None or mrb is None or mrb<=0 or any(x is None for x in vals):reasons.append(f"invalid_power_fields:line={line}");continue
            p0n,p0u,a,pl,dtf,fadj,req,pcmax,applied=vals
            expected=p0n+p0u+10*math.log10((2**mu)*mrb)+a*pl+dtf+fadj
            if abs(req-expected)>1e-6:reasons.append(f"power_formula_mismatch:line={line}:{req}!={expected}")
            if abs(applied-min(pcmax,expected))>1e-6:reasons.append(f"pcmax_application_mismatch:line={line}")
            v=finite(r.get("PowerError_dB"))
            if v is None or v>0.1:reasons.append(f"waveform_power_error:line={line}")
            src=str(r.get("PathlossReferenceRS","")).lower()
            if "configured_snr" in src:reasons.append(f"configured_snr_pathloss:line={line}")
    elif name=="pusch_harq_trials.csv":
        for line,r in enumerate(rows,2):
            if integer(r.get("RV")) not in {0,1,2,3}:reasons.append(f"invalid_rv:line={line}")
            action=str(r.get("HARQAction","")).upper()
            if action not in {"NEW_DATA","RETRANSMISSION"}:reasons.append(f"invalid_harq_action:line={line}")
            if action=="NEW_DATA" and truth(r.get("Combined")) is not False:reasons.append(f"new_data_combined:line={line}")
            if action=="RETRANSMISSION" and truth(r.get("Combined")) is not True:reasons.append(f"retx_not_combined:line={line}")
    elif name=="pusch_receiver_metrics.csv":
        for line,r in enumerate(rows,2):
            if finite(r.get("MeasuredSINRdB")) is None:reasons.append(f"missing_measured_sinr:line={line}")
            if truth(r.get("ReceiverDerived")) is not True:reasons.append(f"sinr_not_receiver_derived:line={line}")
            src=str(r.get("MeasuredSINRSource","")).lower()
            if not src or any(x in src for x in ("configured","requested","expected","oracle")):
                reasons.append(f"invalid_sinr_source:line={line}:{src}")
            require_prob(r,"BER",line,reasons);require_prob(r,"BLER",line,reasons)
    elif name=="pusch_bler_curve.csv":
        for line,r in enumerate(rows,2):
            trials=integer(r.get("Trials"));errors=integer(r.get("TBErrors"));bler=require_prob(r,"BLER",line,reasons)
            lo=require_prob(r,"CILower",line,reasons);hi=require_prob(r,"CIUpper",line,reasons)
            conf=require_prob(r,"ConfidenceLevel",line,reasons)
            if trials is None or trials<=0 or errors is None or not 0<=errors<=trials:reasons.append(f"invalid_trial_counts:line={line}")
            elif bler is not None and abs(bler-errors/trials)>1e-12:reasons.append(f"bler_count_mismatch:line={line}")
            if lo is not None and hi is not None and lo>hi:reasons.append(f"invalid_ci_order:line={line}")
            if conf in (0,1):reasons.append(f"invalid_confidence_level:line={line}")
            if truth(r.get("Incomplete")) is not False:reasons.append(f"incomplete_point:line={line}")
            stop=str(r.get("StopReason","")).lower()
            if any(x in stop for x in ("max_tb","max_trial","incomplete","unknown")):reasons.append(f"invalid_stop_reason:line={line}:{stop}")
    elif name=="pusch_negative_tests.csv":
        for line,r in enumerate(rows,2):
            if norm(r.get("ExpectedErrorIdentifier"))!=norm(r.get("ActualErrorIdentifier")):reasons.append(f"negative_wrong_error:line={line}")
            if truth(r.get("AssignmentCreated")) is not False:reasons.append(f"negative_assignment_created:line={line}")
            if truth(r.get("WaveformGenerated")) is not False:reasons.append(f"negative_waveform_generated:line={line}")
            if truth(r.get("ConfigurationMutated")) is not False:reasons.append(f"negative_configuration_mutated:line={line}")
    elif name=="pusch_test_summary.csv":
        for line,r in enumerate(rows,2):
            total=integer(r.get("Total"));passed=integer(r.get("Passed"))
            if truth(r.get("Mandatory")) is True:
                if any((integer(r.get(x)) or 0)>0 for x in ("Failed","Skipped","Blocked")):reasons.append(f"mandatory_not_fully_executed:line={line}")
                if total is None or passed!=total:reasons.append(f"mandatory_total_not_passed:line={line}")

def verify_csvs(root,contracts):
    results=[];parsed={}
    for name,c in contracts.items():
        path=root/name;reasons=[]
        if not path.is_file():
            results.append(result(name,"CSV",["missing_file"]));continue
        head,rows,err=read_rect(path);reasons.extend(err)
        missing=[x for x in c.columns if x not in head]
        if missing:reasons.append("missing_columns:"+",".join(missing))
        if rows and c.key:
            d=dup_keys(rows,c.key)
            if d:reasons.append("duplicate_primary_keys:"+",".join(d[:10]))
        if rows and not missing:
            # Status represents the test/artifact row outcome, not assignment acceptance.
            for line,r in enumerate(rows,2):
                if str(r.get("Status","")).strip().upper()!="PASS":reasons.append(f"row_status_not_pass:line={line}")
            validate_specific(name,rows,reasons)
        parsed[name]=rows
        results.append(result(name,"CSV",reasons,Rows=len(rows),Columns=len(head),SHA256=digest(path)))
    return results,parsed

def verify_pngs(root,contracts):
    results=[];meta={}
    for name,c in contracts.items():
        path=root/name;reasons=[]
        if not path.is_file():
            results.append(result(name,"PNG",["missing_file"]));continue
        try:
            with Image.open(path) as im:
                im.load();width,height=im.size;mode=im.mode
                gray=im.convert("L");stat=ImageStat.Stat(gray)
                std=float(stat.stddev[0]);ext=gray.getextrema();fraction=0 if ext[0]==ext[1] else 1
            size=path.stat().st_size;sha=digest(path)
            if width<c.min_width or height<c.min_height:reasons.append(f"dimensions:{width}x{height}")
            if size<1000:reasons.append(f"file_too_small:{size}")
            if std<=1:reasons.append(f"pixel_stddev_low:{std}")
            meta[name]={"Width":width,"Height":height,"Mode":mode,"Bytes":size,"SHA256":sha}
            results.append(result(name,"PNG",reasons,**meta[name]))
        except Exception as exc:results.append(result(name,"PNG",[f"decode:{type(exc).__name__}:{exc}"]))
    return results,meta

def source_hash(root,sources):
    if not all((root/s).is_file() for s in sources):return None
    if len(sources)==1:return digest(root/sources[0])
    return "|".join(f"{s}={digest(root/s)}" for s in sources)

def verify_semantics(root,contracts,parsed,pngmeta):
    rows=parsed.get("pusch_image_semantic_audit.csv",[]);by={}
    for r in rows:by.setdefault(r.get("ImageFile","").strip(),[]).append(r)
    out=[]
    for name,c in contracts.items():
        reasons=[];matches=by.get(name,[])
        if len(matches)!=1:
            out.append(result(name,"SEMANTIC",[f"semantic_row_count:{len(matches)}"]));continue
        r=matches[0];m=pngmeta.get(name)
        if r.get("SourceCSV","").strip()!="|".join(c.sources):reasons.append("source_contract_mismatch")
        sh=source_hash(root,c.sources)
        if sh is None or r.get("SourceCSV_SHA256","").strip()!=sh:reasons.append("source_hash_mismatch")
        if m is None:reasons.append("png_metadata_unavailable")
        else:
            if r.get("PNG_SHA256","").strip()!=m["SHA256"]:reasons.append("png_hash_mismatch")
            if integer(r.get("Width"))!=m["Width"] or integer(r.get("Height"))!=m["Height"]:reasons.append("dimension_record_mismatch")
        if (integer(r.get("AxesCount")) or 0)<c.min_axes:reasons.append("axes_below_contract")
        if (integer(r.get("SeriesCount")) or 0)<c.min_series:reasons.append("series_below_contract")
        if (integer(r.get("FinitePointCount")) or 0)<c.min_points:reasons.append("points_below_contract")
        if norm(r.get("ActualXLabel"))!=norm(c.xlabel):reasons.append("xlabel_mismatch")
        if norm(r.get("ActualYLabel"))!=norm(c.ylabel):reasons.append("ylabel_mismatch")
        if norm(c.title_token).lower() not in norm(r.get("ActualTitle")).lower():reasons.append("title_token_missing")
        out.append(result(name,"SEMANTIC",reasons))
    unknown=sorted(set(by)-set(contracts))
    if unknown:out.append(result("pusch_image_semantic_audit.csv","SEMANTIC",["unknown_images:"+",".join(unknown)]))
    return out

def write_results(path,rows):
    fields=["Artifact","Type","Status","Reason","Rows","Columns","Width","Height","Mode","Bytes","SHA256"]
    with path.open("w",newline="",encoding="utf-8") as f:
        w=csv.DictWriter(f,fieldnames=fields,extrasaction="ignore");w.writeheader();w.writerows(rows)

def verify(root,write_output=True):
    cc,ic=read_contracts();a,parsed=verify_csvs(root,cc);b,meta=verify_pngs(root,ic);c=verify_semantics(root,ic,parsed,meta)
    rows=a+b+c;fails=sum(r["Status"]!="PASS" for r in rows)
    if write_output:write_results(root/"pusch_artifact_verification.csv",rows)
    print(f"PUSCH artifact verification: {len(rows)-fails} passed, {fails} failed")
    for r in rows:
        if r["Status"]!="PASS":print(f"FAIL {r['Type']} {r['Artifact']}: {r['Reason']}")
    return (0 if fails==0 else 2),rows

# ---------------------------- verifier self-test ----------------------------
def write_csv(path,columns,rows):
    with path.open("w",newline="",encoding="utf-8") as f:
        w=csv.DictWriter(f,fieldnames=list(columns),extrasaction="ignore");w.writeheader();w.writerows(rows)
def base(columns):
    r={c:"1" for c in columns};r["Status"]="PASS";return r

def synthetic_csvs(root,contracts):
    for name,c in contracts.items():
        if name=="pusch_image_semantic_audit.csv":continue
        r=base(c.columns);r[c.key[0]]="SYN-001";rows=[]
        if name=="pusch_assignment_resolution.csv":
            r.update(Profile="connected_dynamic_strict",AssignmentSource="decoded_dci_plus_rrc",DecodedDCIId="D1",DCIFormat="0_1",
            DCICRCPass=1,DCIRNTIMatch=1,RNTIType="C-RNTI",PRBSet="0|1",SymbolAllocation="2|10",MCSIndex=10,
            NumLayers=1,NumCodewords=1,NDI=1,RV=0,HARQProcessID=2,AssignmentCreated=1,WaveformAllowed=1,ErrorIdentifier="",
            CGInstalled="",CGActivated="",CGReleased="",CGOccasionMatch="")
        elif name=="pusch_resource_ownership.csv":r.update(CaseID="SYN",Slot=0,Hop=0,PRB=0,Symbol=2,Subcarrier=0,Owner="DATA",UEID="UE1",CollisionCount=0)
        elif name=="pusch_re_mapping.csv":r.update(CaseID="SYN",Domain="DATA",Hop=0,Codeword=0,Layer=0,Port=0,PRB=0,Symbol=2,Subcarrier=0,LinearIndex0Based=0)
        elif name=="pusch_dmrs_matrix.csv":r.update(RequestedDMRSPortSet="0",AppliedDMRSPortSet="0",InputMutationCount=0,IndexMismatchCount=0,SequenceNMSE=0,DMRSRECount=12)
        elif name=="pusch_ptrs_matrix.csv":r.update(CaseID="SYN",Hop=0,ExpectedPresent=1,PTRSRECount=12,AssociatedDMRSPort=0,InputMutationCount=0,IndexMismatchCount=0,EVMBeforePercent=8,EVMAfterPercent=2)
        elif name=="pusch_uci_multiplexing.csv":
            r.update(CaseID="SYN",Codeword=0,NumULSCHTB=1,UCIOnly=0,OACK=2,OCSI1=0,OCSI2=0,OCGUCI=0,
            G=100,ULSCHBitCount=80,ACKCodedBitCount=20,CSI1CodedBitCount=0,CSI2CodedBitCount=0,
            CGUCICodedBitCount=0,PlaceholderXCount=0,PlaceholderYCount=0,MuxedBitCount=100,UCIOwnerCodeword=0,
            PayloadMatch=1,ACKCRCOK=1,CSI1CRCOK=1,CSI2CRCOK=1)
        elif name=="pusch_coding_chain.csv":r.update(CaseID="SYN",Codeword=0,TBS=1024,G=2048,RateMatchedBits=2048,RateRecoveredBits=2048,CRCOK=1)
        elif name=="pusch_independent_vector_results.csv":
            rows=[]
            for i,fam in enumerate(sorted(REQUIRED_VECTOR_FAMILIES)):
                q=base(c.columns);q.update(VectorFamily=fam,CaseID=f"S{i}",ComparedField="all",OracleImplementation="pure_spec",
                    OracleVersion="1",OracleArtifactSHA256="a"*64,ExpectedDigest="b",ActualDigest="b",
                    MismatchCount=0,MaxAbsError=0,Tolerance=0,IndependenceClass="independent_pure_python")
                rows.append(q)
        elif name=="pusch_codeword_layer_map.csv":r.update(CaseID="SYN",Rank=1,NumCodewords=1,Codeword=0,Layer=0,SourceSymbolCount=10,MappedSymbolCount=10,MismatchCount=0)
        elif name=="pusch_transform_precoding.csv":r.update(CaseID="SYN",Hop=0,Layer=0,DFTSize=12,MRB=1,InputSymbolCount=12,OutputSymbolCount=12,EnergyRelativeError=0,RoundTripNMSE=0,InputPAPR_dB=1,OutputPAPR_dB=2)
        elif name=="pusch_frequency_hopping.csv":r.update(CaseID="SYN",AbsoluteSlot=0,RepetitionIndex=0,Hop=0,Mode="none",ResourceAllocationType=1,PRBSet="0|1",ExpectedPRBSet="0|1",PRBMismatchCount=0)
        elif name=="pusch_srs_precoder_selection.csv":r.update(CaseID="SYN",MeasurementSlot=10,CurrentSlot=12,AgeSlots=2,MaxAgeSlots=8,MeasurementConfigurationEpoch=4,CurrentConfigurationEpoch=4,SelectedTPMI=2,AppliedTPMI=2,DecisionID="D",AppliedDecisionID="D",DecisionSource="measured_srs",DecisionValid=1,ConfiguredTPMIFallbackUsed=0)
        elif name=="pusch_precoding_application.csv":r.update(CaseID="SYN",Hop=0,PRG=0,SymbolGroup=0,MatrixDigest="d",AppliedMatrixDigest="d",PowerRelativeError=0,MatrixApplicationCount=1)
        elif name=="pusch_power_control.csv":
            mu=1;mrb=12;p0n=-96;p0u=2;a=.8;pl=100;dtf=1.5;fadj=1
            req=p0n+p0u+10*math.log10((2**mu)*mrb)+a*pl+dtf+fadj;pc=23;app=min(pc,req)
            r.update(CaseID="SYN",Mu=mu,MRB=mrb,P0Nominal_dBm=p0n,P0UE_dB=p0u,Alpha=a,MeasuredPathloss_dB=pl,
            DeltaTF_dB=dtf,UpdatedF_dB=fadj,RequestedPower_dBm=req,PCMAX_dBm=pc,AppliedPower_dBm=app,
            PowerError_dB=0,PathlossReferenceRS="SRS-RS-1")
        elif name=="pusch_harq_trials.csv":r.update(CaseID="SYN",Codeword=0,TransmissionIndex=0,RV=0,HARQAction="NEW_DATA",Combined=0)
        elif name=="pusch_receiver_metrics.csv":r.update(CaseID="SYN",Codeword=0,Layer=0,Hop=0,MeasuredSINRdB=10,MeasuredSINRSource="receiver_equalizer_channel_estimate",ReceiverDerived=1,BER=0,BLER=0)
        elif name=="pusch_bler_curve.csv":
            r.update(CampaignID="C",OperatingPointID="O",Trials=1000,TBErrors=100,BLER=.1,ConfidenceLevel=.95,CILower=.08,CIUpper=.12,Incomplete=0,StopReason="ci_and_min_errors_met")
        elif name=="pusch_negative_tests.csv":r.update(CaseID="NEG",ExpectedErrorIdentifier="sixgr:pusch:E",ActualErrorIdentifier="sixgr:pusch:E",AssignmentCreated=0,WaveformGenerated=0,ConfigurationMutated=0)
        elif name=="pusch_test_summary.csv":r.update(TestSuite="self",Mandatory=1,Total=10,Passed=10,Failed=0,Skipped=0,Blocked=0)
        if not rows:rows=[r]
        write_csv(root/name,c.columns,rows)

def synthetic_images(root,contracts):
    for i,c in enumerate(contracts.values()):
        w=max(1000,c.min_width);h=max(650,c.min_height)
        im=Image.new("RGB",(w,h),"white");d=ImageDraw.Draw(im)
        d.rectangle((60,40,w-40,h-60),outline="black",width=3)
        last=None
        for k in range(30):
            p=(70+k*(w-130)//30,70+((k*43+i*29)%(h-170)))
            d.ellipse((p[0]-4,p[1]-4,p[0]+4,p[1]+4),fill="black")
            if last:d.line((last[0],last[1],p[0],p[1]),fill="black",width=2)
            last=p
        im.save(root/c.name)

def synthetic_semantics(root,ic,c):
    rows=[]
    for x in ic.values():
        with Image.open(root/x.name) as im:w,h=im.size
        rows.append({"ImageFile":x.name,"SourceCSV":"|".join(x.sources),"Width":w,"Height":h,
        "AxesCount":x.min_axes,"SeriesCount":x.min_series,"FinitePointCount":x.min_points,
        "ExpectedXLabel":x.xlabel,"ActualXLabel":x.xlabel,"ExpectedYLabel":x.ylabel,"ActualYLabel":x.ylabel,
        "ExpectedTitleToken":x.title_token,"ActualTitle":"Synthetic "+x.title_token,
        "SourceCSV_SHA256":source_hash(root,x.sources),"PNG_SHA256":digest(root/x.name),"Status":"PASS"})
    write_csv(root/c.name,c.columns,rows)

def self_test():
    cc,ic=read_contracts()
    with tempfile.TemporaryDirectory(prefix="pusch-verifier-") as t:
        root=Path(t);synthetic_csvs(root,cc);synthetic_images(root,ic);synthetic_semantics(root,ic,cc["pusch_image_semantic_audit.csv"])
        good,gr=verify(root,False)
        h,rows,e=read_rect(root/"pusch_image_semantic_audit.csv");rows[0]["PNG_SHA256"]="0"*64;write_csv(root/"pusch_image_semantic_audit.csv",h,rows)
        bad,br=verify(root,False);det=any("png_hash_mismatch" in r["Reason"] for r in br if r["Status"]=="FAIL")
        print(f"self-test valid exit={good} checks={len(gr)} failures={sum(x['Status']!='PASS' for x in gr)}")
        print(f"self-test corrupt exit={bad} failures={sum(x['Status']!='PASS' for x in br)} detected={det}")
        return 0 if good==0 and bad==2 and det else 3

def main():
    ap=argparse.ArgumentParser();ap.add_argument("output_dir",nargs="?",type=Path);ap.add_argument("--self-test",action="store_true");a=ap.parse_args()
    if a.self_test:return self_test()
    if a.output_dir is None:raise SystemExit("output_dir required")
    if not a.output_dir.is_dir():print(f"not found:{a.output_dir}",file=sys.stderr);return 2
    return verify(a.output_dir.resolve())[0]
if __name__=="__main__":raise SystemExit(main())
