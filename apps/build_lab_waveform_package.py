"""Package and independently measure an actual completed lab PHY campaign.

Never generates PHY samples. Input .iq64/.symbols64 files are MATLAB-produced
little-endian complex128 streams. Instrument copies preserve the native clock.
"""
from __future__ import annotations
import argparse
import csv
import hashlib
import json
import math
import shutil
from pathlib import Path

import numpy as np
import pandas as pd
from scipy import signal
from scipy.io import loadmat, savemat
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt


def require(condition, message):
    if not condition:
        raise ValueError(message)


def digest(path):
    h = hashlib.sha256()
    with Path(path).open("rb") as f:
        for block in iter(lambda: f.read(8 * 1024 * 1024), b""):
            h.update(block)
    return h.hexdigest()


def write_json(path, data):
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(data, indent=2, allow_nan=False), encoding="utf-8")


def write_csv(path, data):
    pd.DataFrame(data).to_csv(path, index=False, float_format="%.17g")


def read_iq(path):
    require(Path(path).stat().st_size % 16 == 0, f"Truncated complex128 stream: {path}")
    return np.memmap(path, dtype="<c16", mode="r")


def truth(series):
    return series.astype(str).str.lower().isin(("true", "1"))


def iq_stats(x, active=None):
    power = np.abs(x) ** 2
    average = float(power.mean())
    require(average > 0 and np.isfinite(x).all(), "Silent or nonfinite endpoint")
    result = dict(Samples=len(x), RMS=math.sqrt(average), MeanI=float(x.real.mean()),
                  MeanQ=float(x.imag.mean()), PeakI=float(np.abs(x.real).max()),
                  PeakQ=float(np.abs(x.imag).max()), PeakMagnitude=float(np.abs(x).max()),
                  AveragePower=average, PeakPower=float(power.max()),
                  PAPRFullFrame_dB=float(10 * np.log10(power.max() / average)))
    if active is not None:
        require(active.any(), "No scheduled active samples")
        result["PAPRActiveSlots_dB"] = float(10 * np.log10(power[active].max() / power[active].mean()))
    return result


def verify_native_cp(wave,nfft,symbols):
    """Identify exact copied CP blocks in executed, nonwindowed active-slot IQ."""
    equal=wave[:-nfft]==wave[nfft:]
    edges=np.diff(np.r_[False,equal,False].astype(np.int8))
    starts=np.flatnonzero(edges==1); ends=np.flatnonzero(edges==-1)
    require(len(starts)==symbols and starts[0]==0 and ends[-1]+nfft==len(wave),"Native CP block count/extent differs")
    require(np.array_equal(starts[1:],ends[:-1]+nfft),"Native CP/useful-symbol boundaries differ")
    require(np.all(ends>starts),"Empty CP")
    return starts,ends-starts


def native_grid(wave,starts,lengths,nfft,subcarriers):
    useful=np.column_stack([wave[int(a+b):int(a+b+nfft)] for a,b in zip(starts,lengths)])
    transformed=np.fft.fftshift(np.fft.fft(useful,axis=0),axes=0)
    first=(nfft-subcarriers)//2
    return transformed[first:first+subcarriers]


def verify_native_replay(root,profile,direction,rows,cfg):
    """Independent NumPy FFT audit against saved MATLAB modulation symbols.

    RX noise is measured on a full-CP-removal window; it is not mislabeled as
    the receiver's possibly different fractional-CP analysis window.
    """
    directory=root/f"{direction.lower()}_tx"/profile
    saved=loadmat(directory/"first_slot_grid.mat")
    nfft=int(cfg["waveform"]["explicit_fft_size"]); sc=int(cfg["frequency"]["n_size_grid"])*12
    snrs=cfg["lab_waveform"]["rx_snr_db"]; layers=int(cfg["mimo"]["n_layers"])
    output=[]
    for port in range(1,layers+1):
        wave=read_iq(directory/f"port{port}.iq64")
        ref=read_iq(directory/f"reference_layer{port}.symbols64")
        indices=saved["DataIndices"][:,port-1].astype(np.int64)-1-(port-1)*sc*14
        rxs={snr:read_iq(root/f"{direction.lower()}_rx_awgn"/profile/f"snr{snr:g}"/f"port{port}.iq64") for snr in snrs}
        for row in rows[rows.SNRdB==snrs[0]].itertuples():
            start=int(row.StartSample); stop=start+int(row.SampleCount)
            cpstart,cplen=verify_native_cp(wave[start:stop],nfft,14)
            grid=native_grid(wave[start:stop],cpstart,cplen,nfft,sc)
            actual=grid.ravel(order="F")[indices]
            symbol_start=int(row.SymbolStart)
            expected=ref[symbol_start:symbol_start+int(row.LayerDataRE)]/np.sqrt(layers)
            error=float(np.max(np.abs(actual-expected)))
            bound=64*np.finfo(float).eps*max(1.,float(np.abs(expected).max()))
            require(error<=bound,"Native IQ does not reconstruct its exact retained reference data REs")
            if row.AbsoluteSlot==int(saved["AbsoluteSlot"].item()):
                require(np.max(np.abs(grid-saved["Grid"][:,:,port-1]))<=bound,"Independent FFT disagrees with full saved grid/DMRS")
            for snr in snrs:
                noisy=native_grid(rxs[snr][start:stop],cpstart,cplen,nfft,sc).ravel(order="F")[indices]
                measured=10*np.log10(np.vdot(actual,actual).real/np.vdot(noisy-actual,noisy-actual).real)
                require(abs(measured-snr)<.2,"Independent physical SNR differs from configured AWGN point")
                output.append(dict(Profile=profile,Direction=direction,Port=port,AbsoluteSlot=row.AbsoluteSlot,SNRdB=snr,
                    IndependentFullCPWindowSNRdB=float(measured),ReferenceGridMaxError=error,
                    ReferenceGridErrorBound=bound,CPExact=True,Source="NumPy_FFT_of_actual_IQ_not_PHY_regeneration"))
    return output


def export_port(x, directory, stem, scale, fs, fc, span, description="Digital research waveform", standards_status="research_extension"):
    """Exact CSV/MAT + commonly scaled WIQ/VSA. No resampling or padding."""
    directory.mkdir(parents=True, exist_ok=True)
    receipt = []
    path = directory / f"{stem}.csv"
    with path.open("w", newline="", encoding="ascii") as f:
        f.write("I,Q\n")
        for start in range(0, len(x), 65536):
            y = x[start:start + 65536]
            np.savetxt(f, np.column_stack((y.real, y.imag)), fmt="%.17g", delimiter=",")
    # Python's float parser guarantees a 17-significant-digit binary64 round trip.
    with path.open(newline="", encoding="ascii") as f:
        reader = csv.reader(f); require(next(reader) == ["I", "Q"], "CSV header")
        offset = 0
        for row in reader:
            require(offset < len(x), "CSV has excess samples")
            require(float(row[0]) == x[offset].real and float(row[1]) == x[offset].imag,
                    f"CSV sample differs at {offset}")
            offset += 1
    require(offset == len(x), "CSV is incomplete")
    receipt.append(dict(Path=str(path), Kind="raw_csv", ExactReadback=True))
    path = directory / f"{stem}.mat"
    savemat(path, dict(Waveform=np.asarray(x)[:, None], SampleRateHz=fs,
                      CenterFrequencyHz=fc, CommonPlaybackScale=scale, Description=description,
                      StandardsStatus=standards_status, PhysicalRFMeasurement=False), do_compression=False)
    back = loadmat(path)
    require(np.array_equal(back["Waveform"].ravel(), x) and back["SampleRateHz"].item() == fs, "MAT differs")
    del back
    receipt.append(dict(Path=str(path), Kind="raw_mat", ExactReadback=True))
    normalized = x / scale
    pair = np.column_stack((normalized.real, normalized.imag))
    require(np.max(np.abs(pair)) <= 1, "Playback clipping")
    codes = np.rint(pair * 32767).astype("<i2")
    path = directory / f"{stem}.wiq"; codes.tofile(path)
    back = np.fromfile(path, dtype="<i2").reshape(-1, 2)
    require(np.array_equal(back, codes), "WIQ differs")
    error = float(np.max(np.abs(back.astype(float) / 32767 - pair)))
    require(error <= .5 / 32767 + np.finfo(float).eps, "WIQ exceeds quantization bound")
    receipt.append(dict(Path=str(path), Kind="wiq", ExactReadback=True, QuantizationMaxError=error))
    del back, pair, codes
    path = directory / f"{stem}_vsa.mat"
    payload = dict(Y=normalized.astype(np.complex64)[:, None], XDelta=1/fs,
                   XStart=0., InputCenter=fc, InputZoom=1., XDomain=2., InputSpan=span)
    savemat(path, payload, do_compression=False)
    back = loadmat(path)
    for key, value in payload.items():
        require(np.array_equal(back[key], np.asarray(value).reshape(back[key].shape)), f"VSA differs: {key}")
    receipt.append(dict(Path=str(path), Kind="vsa_mat", ExactReadback=True))
    for r in receipt:
        r.update(Bytes=Path(r["Path"]).stat().st_size, SHA256=digest(r["Path"]),
                 Samples=len(x), SampleRateHz=fs, CommonScale=scale, Resampled=False,
                 ClippedComponents=0, InstrumentImportVerified=False, Description=description,
                 StandardsStatus=standards_status, QuantizationRule="nearest_ties_to_even_component_times_32767")
    return receipt


def save_plot(path, x, y, xlabel, ylabel, title, scatter=False):
    fig, ax = plt.subplots(figsize=(10, 5.5), constrained_layout=True)
    fig.suptitle("SixGR digital reference · 6G research waveform · not a physical RF measurement",fontsize=10)
    if scatter:
        ax.scatter(x, y, s=1, alpha=.45); ax.set_aspect("equal")
    else:
        ax.plot(x, y, linewidth=.8)
    ax.set(xlabel=xlabel, ylabel=ylabel, title=title); ax.grid(alpha=.2)
    fig.savefig(path, dpi=160); plt.close(fig)


def analyze_iq(root, profile, direction, port, x, cfg, active, plot_alias):
    fs = cfg["waveform"]["explicit_sample_rate_hz"]
    p = cfg["lab_waveform"]; nfft = int(p["psd_fft_size"])
    count = min(len(x), int(p["visualization_points"]))
    indices = np.unique(np.linspace(0, len(x)-1, count).astype(int))
    # Welch integrates power across the full TDD recording, including silence.
    f, psd = signal.welch(x, fs=fs, window="hann", nperseg=nfft,
                          noverlap=int(nfft*p["psd_overlap_fraction"]), nfft=nfft,
                          detrend=False, return_onesided=False, scaling="density")
    order = np.argsort(f); f, psd = f[order], psd[order]
    require(np.isfinite(psd).all() and (psd >= 0).all(), "Invalid PSD")
    spectrum = psd * (fs/nfft)
    cdf = np.cumsum(psd) / psd.sum(); tail = (1-p["occupied_power_fraction"])/2
    lower = f[min(np.searchsorted(cdf, tail), len(f)-1)]
    upper = f[min(np.searchsorted(cdf, 1-tail), len(f)-1)]
    statistics = iq_stats(x, active)
    statistics.update(Profile=profile, Direction=direction, Port=port,
                      OccupiedBandwidthHz=float(upper-lower), IntegratedPSDPower=float(psd.sum()*fs/nfft),
                      PSDWindow=p["psd_window"], PSDNFFT=nfft, PSDOverlapFraction=p["psd_overlap_fraction"],
                      ResolutionHz=fs/nfft, OccupiedPowerFraction=p["occupied_power_fraction"])
    prefix = f"{profile}_{direction.lower()}_port{port}"
    csvroot=root/"reports/csv"; image=root/"reports/image"
    waveform = pd.DataFrame(dict(Sample=indices, Time_s=indices/fs, I=x[indices].real, Q=x[indices].imag))
    write_csv(csvroot/f"{prefix}_time_iq.csv", waveform)
    write_csv(csvroot/f"{prefix}_psd.csv", dict(FrequencyHz=f, PSD_per_Hz=psd, PowerPerBin=spectrum))
    power = np.abs(x)**2
    ordered = np.sort(power/power.mean())
    thresholds = np.linspace(0, max(1., statistics["PAPRFullFrame_dB"]), 200)
    exceed = (len(x)-np.searchsorted(ordered, 10**(thresholds/10), side="right"))/len(x)
    write_csv(csvroot/f"{prefix}_ccdf.csv", dict(Threshold_dB=thresholds, Exceedance=exceed))
    # Actual STFT bins, deterministically subsampled only for display/export.
    sf, st, spec = signal.spectrogram(x, fs=fs, window="hann", nperseg=nfft,
                                    noverlap=nfft//2, detrend=False, return_onesided=False, scaling="density")
    so=np.argsort(sf); fi=np.linspace(0,len(sf)-1,256).astype(int); ti=np.linspace(0,len(st)-1,min(128,len(st))).astype(int)
    small=spec[so[fi]][:,ti]
    ff, tt=np.meshgrid(sf[so[fi]],st[ti],indexing="ij")
    write_csv(csvroot/f"{prefix}_spectrogram.csv", dict(FrequencyHz=ff.ravel(),Time_s=tt.ravel(),PSD_per_Hz=small.ravel()))
    fig,ax=plt.subplots(figsize=(10,5),constrained_layout=True)
    ax.pcolormesh(st[ti]*1e3,sf[so[fi]]/1e6,10*np.log10(np.maximum(small,np.finfo(float).tiny)),shading="auto")
    ax.set(xlabel="Time (ms)",ylabel="Baseband frequency (MHz)",title=f"{prefix}: measured spectrogram")
    fig.savefig(image/f"{prefix}_spectrogram.png",dpi=150); plt.close(fig)
    save_plot(image/f"{prefix}_time_iq.png",indices/fs*1e3,np.column_stack((x[indices].real,x[indices].imag)),"Time (ms)","I / Q (raw digital)",prefix)
    save_plot(image/f"{prefix}_psd.png",f/1e6,10*np.log10(np.maximum(psd,np.finfo(float).tiny)),"Baseband frequency (MHz)","Digital PSD (dB/Hz)",prefix)
    save_plot(image/f"{prefix}_spectrum.png",f/1e6,10*np.log10(np.maximum(spectrum,np.finfo(float).tiny)),"Baseband frequency (MHz)","Power per analysis bin (dB)",prefix)
    save_plot(image/f"{prefix}_papr_ccdf.png",thresholds,exceed,"Power / frame mean (dB)","Exceedance probability",prefix)
    if plot_alias:
        for suffix in ("time_iq","psd","spectrum","papr_ccdf"):
            shutil.copy2(image/f"{prefix}_{suffix}.png",image/f"{direction.lower()}_{suffix}.png")
    display=np.linspace(0,len(f)-1,1024).astype(int)
    return statistics, dict(frequencyMHz=(f[display]/1e6).tolist(),
        psdDB=(10*np.log10(np.maximum(psd[display],np.finfo(float).tiny))).tolist(),
        ccdfDB=thresholds.tolist(),ccdf=exceed.tolist(),
        waveformTimeMs=(indices/fs*1e3).tolist(),waveformI=x[indices].real.tolist(),waveformQ=x[indices].imag.tolist(),
        csv=f"reports/csv/{prefix}_psd.csv",stats=statistics)


def package(root):
    root=Path(root).resolve()
    source_names=("build_lab_waveform_package.py","vxg_vsa_demo_dashboard.py","vxg_vsa_demo.html","seal_lab_waveform_package.py")
    frozen_sources={name:digest(Path(__file__).with_name(name)) for name in source_names}
    meta=json.loads((root/"meta/manifest.json").read_text(encoding="utf-8-sig"))
    cfg=json.loads((root/"config/resolved_config.json").read_text(encoding="utf-8-sig"))
    require(meta["Status"]=="phy_completed", "Only a completely executed PHY campaign can be packaged")
    p=cfg["lab_waveform"]; fs=float(meta["SampleRateHz"]); fc=float(cfg["frequency"]["center_frequency_hz"])
    samples=int(meta["SamplesPerPort"]); layers=int(cfg["mimo"]["n_layers"])
    require(layers==2,"Joint VSA exporter currently requires exactly two ports")
    require(samples==round(fs*p["expected_duration_s"]) and samples>=p["min_playback_samples"] and
            samples%p["playback_sample_multiple"]==0,"Sample duration or playback constraints")
    trials=pd.read_csv(root/"reports/csv/trials.csv"); timeline=pd.read_csv(root/"reports/csv/timeline.csv")
    bins=pd.read_csv(root/"reports/csv/evm_bins.csv")
    profiles=[f"mcs{int(v)}" for v in p["dl_mcs_indices"]]
    require(set(trials.Profile)==set(profiles) and set(trials.SNRdB)==set(p["rx_snr_db"]),"Incomplete case matrix")
    for profile in profiles:
        tick=timeline[timeline.Profile==profile].sort_values("AbsoluteSlot")
        require(len(tick)==cfg["simulation"]["n_slots"] and tick.StartSample.iloc[0]==0 and
                tick.StopSampleExclusive.iloc[-1]==samples and
                np.array_equal(tick.StartSample.to_numpy()[1:],tick.StopSampleExclusive.to_numpy()[:-1]),"Frame clock gaps")
        for direction in ("DL","UL"):
            slots=tick.loc[truth(tick[direction+"Active"]),"AbsoluteSlot"].tolist()
            for snr in p["rx_snr_db"]:
                actual=trials[(trials.Profile==profile)&(trials.Direction==direction)&(trials.SNRdB==snr)]
                require(actual.AbsoluteSlot.tolist()==slots,"Missing/duplicate executed trials")
    receipts=[]; statistics=[]; summary=[]; evm=[]; cp_rows=[]; replay_rows=[]; replay={"profiles":{},"meta":meta,"config":cfg}
    for pi,profile in enumerate(profiles):
        replay["profiles"][profile]={}
        for direction in ("DL","UL"):
            print(f"LAB_PACKAGE {profile} {direction}",flush=True)
            folder=root/f"{direction.lower()}_tx"/profile
            direction_rows=trials[(trials.Profile==profile)&(trials.Direction==direction)]
            replay_rows.extend(verify_native_replay(root,profile,direction,direction_rows,cfg))
            raw=[read_iq(folder/f"port{i}.iq64") for i in range(1,layers+1)]
            require(all(len(x)==samples for x in raw),"Unequal or truncated TX ports")
            source_hash=[digest(folder/f"port{i}.iq64") for i in range(1,layers+1)]
            scale=max(max(float(np.abs(x.real).max()),float(np.abs(x.imag).max())) for x in raw)
            require(scale>0,"Silent TX")
            active=np.zeros(samples,dtype=bool)
            for row in timeline[(timeline.Profile==profile)&truth(timeline[direction+"Active"])].itertuples():
                active[int(row.StartSample):int(row.StopSampleExclusive)]=True
            require(all(np.all(x[~active]==0) for x in raw),"TX contains unscheduled waveform samples")
            item={"ports":[],"cases":{},"scale":scale}
            for port,x in enumerate(raw,1):
                for tick in timeline[(timeline.Profile==profile)&truth(timeline[direction+"Active"])].itertuples():
                    offset=int(tick.StartSample); stop=int(tick.StopSampleExclusive)
                    cp_starts,cp_lengths=verify_native_cp(x[offset:stop],int(meta["FFTSize"]),14)
                    for symbol,(start,length) in enumerate(zip(cp_starts,cp_lengths)):
                        cp_rows.append(dict(Profile=profile,Direction=direction,Port=port,AbsoluteSlot=tick.AbsoluteSlot,
                                            Symbol=symbol,StartSample=offset+int(start),CPCount=int(length),UsefulSamples=meta["FFTSize"],ExactCopyPass=True))
                receipts.extend(export_port(x,folder,f"{direction.lower()}_tx_port{port}",scale,fs,fc,
                                            fs/p["vsa_sample_rate_to_span_ratio"],meta["Description"],
                                            "3gpp_derived_pdsch_on_research_carrier" if direction=="DL" else "research_extension"))
                stat,view=analyze_iq(root,profile,direction,port,x,cfg,active,pi==0 and port==1)
                statistics.append(stat); item["ports"].append(view)
            # Documented dual-channel Y1/Y2, matching existing verified packager.
            joint=root/"vsa"/profile; joint.mkdir(parents=True,exist_ok=True)
            vsa=dict(Y1=(raw[0]/scale).astype(np.complex64)[:,None],Y2=(raw[1]/scale).astype(np.complex64)[:,None],
                     XDelta=1/fs,XStart=0.,InputCenter=fc,InputZoom=1.,XDomain=2.,InputSpan=fs/p["vsa_sample_rate_to_span_ratio"])
            path=joint/f"{direction.lower()}_tx_2ch_vsa.mat"; savemat(path,vsa,do_compression=False)
            back=loadmat(path)
            for key,value in vsa.items():
                require(np.array_equal(back[key],np.asarray(value).reshape(back[key].shape)),f"Joint VSA differs: {key}")
            receipts.append(dict(Path=str(path),Kind="joint_vsa",SHA256=digest(path),Bytes=path.stat().st_size,ExactReadback=True,
                                 Samples=samples,SampleRateHz=fs,CommonScale=scale,Resampled=False,ClippedComponents=0,InstrumentImportVerified=False))
            del back,vsa
            require(source_hash==[digest(folder/f"port{i}.iq64") for i in range(1,layers+1)],"Source IQ changed while packaging")
            symbol_trials=trials[(trials.Profile==profile)&(trials.Direction==direction)&(trials.SNRdB==p["rx_snr_db"][0])]
            expected_symbols=int(symbol_trials.LayerDataRE.sum())
            refs=[read_iq(folder/f"reference_layer{i}.symbols64") for i in range(1,layers+1)]
            require(all(len(x)==expected_symbols for x in refs),"Reference symbol stream incomplete")
            display=np.unique(np.linspace(0,expected_symbols-1,min(p["visualization_points"],expected_symbols)).astype(int))
            item["symbolCountPerLayer"]=expected_symbols; item["reference"]=[]; item["observedIdealPoints"]=[]
            for li,ref in enumerate(refs,1):
                points=np.column_stack((ref[display].real,ref[display].imag))
                name=f"{profile}_{direction.lower()}_reference_layer{li}"
                write_csv(root/"reports/csv"/f"{name}.csv",dict(SymbolIndex=display,I=points[:,0],Q=points[:,1]))
                save_plot(root/"reports/image"/f"{name}.png",points[:,0],points[:,1],"I","Q",name,True)
                if pi==0 and li==1: shutil.copy2(root/"reports/image"/f"{name}.png",root/"reports/image"/f"{direction.lower()}_constellation_reference.png")
                item["reference"].append(points.tolist())
                observed=np.unique(ref)
                require(len(observed)<=2**int(symbol_trials.Qm.iloc[0]),"Reference contains more points than configured QAM alphabet")
                item["observedIdealPoints"].append(np.column_stack((observed.real,observed.imag)).tolist())
            for snr in p["rx_snr_db"]:
                rxdir=root/f"{direction.lower()}_rx_awgn"/profile/f"snr{snr:g}"
                rows=trials[(trials.Profile==profile)&(trials.Direction==direction)&(trials.SNRdB==snr)]
                points=[]; totalerr=0.; totalref=0.; layer_evm=[]
                for li,ref in enumerate(refs,1):
                    eq=read_iq(rxdir/f"equalized_layer{li}.symbols64"); errors=read_iq(rxdir/f"error_layer{li}.symbols64")
                    require(len(eq)==len(ref)==len(errors),"Missing received symbols")
                    require(np.array_equal(eq-ref,errors),"Retained error vector differs from actual equalized-reference symbols")
                    ee=float(np.vdot(errors,errors).real); re=float(np.vdot(ref,ref).real)
                    totalerr+=ee; totalref+=re; layer_evm.append(100*math.sqrt(ee/re))
                    value=np.column_stack((eq[display].real,eq[display].imag)); points.append(value.tolist())
                    name=f"{profile}_{direction.lower()}_snr{snr:g}_layer{li}"
                    write_csv(root/"reports/csv"/f"{name}.csv",dict(SymbolIndex=display,I=value[:,0],Q=value[:,1],
                              ReferenceI=ref[display].real,ReferenceQ=ref[display].imag,ErrorI=errors[display].real,ErrorQ=errors[display].imag))
                    save_plot(root/"reports/image"/f"{name}.png",value[:,0],value[:,1],"I","Q",name,True)
                    if pi==0 and li==1 and snr==p["rx_snr_db"][0]:
                        shutil.copy2(root/"reports/image"/f"{name}.png",root/"reports/image"/f"{direction.lower()}_constellation_awgn_{snr:g}db.png")
                    rxwave=read_iq(rxdir/f"port{li}.iq64"); require(len(rxwave)==samples,"RX frame truncated")
                    rxmat=rxdir/f"{direction.lower()}_rx_port{li}.mat"
                    savemat(rxmat,dict(Waveform=np.asarray(rxwave)[:,None],SampleRateHz=fs,CenterFrequencyHz=fc,SNRdB=snr),do_compression=False)
                    require(np.array_equal(loadmat(rxmat)["Waveform"].ravel(),rxwave),"RX MAT differs")
                require(np.isclose(totalerr,rows.ErrorEnergy.sum(),rtol=1e-12) and
                        np.isclose(totalref,rows.ReferenceEnergy.sum(),rtol=1e-12),"Exported EVM energies disagree")
                passed=truth(rows.CRCPass)&truth(rows.TBExact)
                dt=samples/fs; active_seconds=float(rows.SampleCount.sum()/fs)
                summary_row=dict(Description=meta["Description"],EvidenceMode="digital_reference_simulated_AWGN",
                    Profile=profile,Direction=direction,SNRdB=snr,DL_MCS=int(profile[3:]) if direction=="DL" else "not_applicable",
                    ULStandardsStatus=p["ul_standards_status"] if direction=="UL" else "3gpp_derived_pdsch",
                    TargetCodeRate=float(rows.TargetCodeRate.iloc[0]),TBCount=len(rows),CRCPasses=int(truth(rows.CRCPass).sum()),
                    PayloadPasses=int(passed.sum()),BLER=float(1-passed.mean()),TBSBits=int(rows.TBSBits.iloc[0]),
                    CodedBitsPerTB=int(rows.CodedBits.iloc[0]),InformationBits=int(rows.TBSBits.sum()),
                    DeliveredUniqueBits=int(rows.loc[passed,"TBSBits"].sum()),FrameDuration_s=dt,
                    GoodputGbps=float(rows.loc[passed,"TBSBits"].sum()/dt/1e9),
                    ScheduledCodedFrameGbps=float(rows.CodedBits.sum()/dt/1e9),
                    ActiveSlotCodedGbps=float(rows.CodedBits.sum()/active_seconds/1e9),
                    ActiveSlotInformationGbps=float(rows.TBSBits.sum()/active_seconds/1e9),
                    RawModulationLayerGbps=cfg["frequency"]["n_size_grid"]*12*cfg["frame"]["scs_khz"]*1000*layers*int(rows.Qm.iloc[0])/1e9,
                    GoodputSpectralEfficiency_bpsHz=float(rows.loc[passed,"TBSBits"].sum()/dt/cfg["frequency"]["bandwidth_hz"]),
                    EVMRMSPercent=100*math.sqrt(totalerr/totalref),ReferenceErrorSINRdB=10*math.log10(totalref/totalerr),
                    MeasuredDataREChannelSNRdB=float(rows.MeasuredDataREChannelSNRdB.mean()))
                summary.append(summary_row); evm.append(summary_row.copy())
                selection=bins[(bins.Profile==profile)&(bins.Direction==direction)&(bins.SNRdB==snr)]
                curves={}
                for kind in ("symbol","prb"):
                    grouped=selection[selection.Kind==kind].groupby("Index")[["ErrorEnergy","ReferenceEnergy","Count"]].sum()
                    grouped["EVMRMSPercent"]=100*np.sqrt(grouped.ErrorEnergy/grouped.ReferenceEnergy)
                    name=f"{profile}_{direction.lower()}_snr{snr:g}_evm_per_{kind}"
                    grouped.to_csv(root/"reports/csv"/f"{name}.csv",float_format="%.17g")
                    save_plot(root/"reports/image"/f"{name}.png",grouped.index,grouped.EVMRMSPercent,kind,"RMS EVM (%)",name)
                    curves[kind]=dict(index=grouped.index.tolist(),evm=grouped.EVMRMSPercent.tolist())
                    if pi==0 and direction=="DL" and snr==p["rx_snr_db"][0]:
                        shutil.copy2(root/"reports/image"/f"{name}.png",root/"reports/image"/f"evm_per_{kind}.png")
                item["cases"][str(snr)]=dict(summary=summary_row,constellations=points,layerEVM=layer_evm,evmCurves=curves)
            grid=pd.read_csv(folder/"resource_grid.csv")
            grid1=grid[grid.Port==1].pivot(index="Subcarrier",columns="Symbol",values="Kind").to_numpy()
            item["grid"]=grid1.tolist(); item["gridSlot"]=int(grid.AbsoluteSlot.iloc[0])
            fig,ax=plt.subplots(figsize=(10,5),constrained_layout=True)
            ax.imshow(grid1,origin="lower",aspect="auto",vmin=0,vmax=2,cmap=matplotlib.colors.ListedColormap(["#152538","#31dec0","#eebf60"]))
            ax.set(xlabel="OFDM symbol",ylabel="Active subcarrier",title=f"{profile} {direction} actual slot {item['gridSlot']}: 0 unused, 1 data, 2 DMRS")
            fig.savefig(root/"reports/image"/f"{profile}_resource_grid_{direction.lower()}.png",dpi=150); plt.close(fig)
            if pi==0: shutil.copy2(root/"reports/image"/f"{profile}_resource_grid_{direction.lower()}.png",root/"reports/image"/f"resource_grid_{direction.lower()}.png")
            replay["profiles"][profile][direction]=item
    write_csv(root/"reports/csv/iq_statistics.csv",statistics)
    write_csv(root/"reports/csv/cp_samples.csv",cp_rows)
    write_csv(root/"reports/csv/native_grid_replay.csv",replay_rows)
    write_csv(root/"reports/csv/papr.csv",statistics)
    write_csv(root/"reports/csv/throughput.csv",summary)
    write_csv(root/"reports/csv/evm.csv",evm)
    write_csv(root/"reports/csv/scenario_summary.csv",summary)
    # One shared PSD table across profiles, directions and ports.
    psds=[]
    for profile in profiles:
        for direction in ("DL","UL"):
            for port in range(1,layers+1):
                t=pd.read_csv(root/"reports/csv"/f"{profile}_{direction.lower()}_port{port}_psd.csv")
                t.insert(0,"Port",port); t.insert(0,"Direction",direction); t.insert(0,"Profile",profile); psds.append(t)
    write_csv(root/"reports/csv/psd.csv",pd.concat(psds,ignore_index=True))
    for row in receipts: row["Path"]=Path(row["Path"]).relative_to(root).as_posix()
    write_json(root/"validation/export_receipts.json",receipts)
    write_csv(root/"reports/csv/instrument_handoff.csv",receipts)
    timeline_view=timeline[timeline.Profile==profiles[0]].copy()
    replay["timeline"]=timeline_view.to_dict("records")
    for tick in replay["timeline"]:
        tick["SymbolStartSamples"]=[r["StartSample"] for r in cp_rows if r["Profile"]==profiles[0] and
            r["AbsoluteSlot"]==tick["AbsoluteSlot"] and r["Port"]==1]
    fig,ax=plt.subplots(figsize=(12,3),constrained_layout=True)
    for row in timeline_view.itertuples():
        color="#31dec0" if str(row.DLActive).lower() in ("1","true") else "#749aff" if str(row.ULActive).lower() in ("1","true") else "#eebf60"
        ax.barh(0,(row.StopSampleExclusive-row.StartSample)/fs*1e3,left=row.StartSample/fs*1e3,color=color)
    ax.set(xlabel="Time (ms)",yticks=[],title="Executed TDD frame: DL / mixed idle / UL")
    fig.savefig(root/"reports/image/tdd_timeline.png",dpi=150); plt.close(fig)
    handoff=dict(Description=meta["Description"],WaveformExportReady=True,InstrumentCapability="UNKNOWN",
        InstrumentImportVerified=False,PhysicalMeasurement="Awaiting instrument capture",
        CarrierHz=fc,NominalBandwidthHz=cfg["frequency"]["bandwidth_hz"],ActiveSpanHz=meta["ActiveSpanHz"],
        SampleRateHz=fs,SamplesPerPort=samples,CoherentTxChannelsRequired=layers,CoherentRxChannelsRequired=layers,
        VSAInputSpanHz=fs/p["vsa_sample_rate_to_span_ratio"],
        VSAInputSpanNote="384 MHz complex analysis span preserves native 491.52 MSa/s ratio; not the nominal 400 MHz RF bandwidth",
        Format="WIQ signed int16 little-endian IQ; CSV/MAT raw float64; VSA commonly normalized complex64",
        Normalization="one common scale across both ports, separately per endpoint/profile",
        DigitalRelativePortAmplitudePhasePreserved=True,
        NoResampling=True,NoPadding=True,NoTruncation=True,NoRepeatedFrame=True,
        ModelCandidates=["M9484C VXG B5X + >=508 + coherent two-channel capability", "N5186A MXG B5X + 508 + coherent two-channel capability",
                         "N9030B PXA B5X + suitable frequency option", "N9032B PXA", "N9042B UXA", "89600 VSA with suitable analysis licenses"],
        HardwarePreflightRequired=["*IDN?", "*OPT?", "frequency range", "bandwidth per channel", "native sample-rate playback",
                                   "memory per channel", "coherent simultaneous two-channel TX and RX", "analysis software/1024-QAM/custom OFDM support"],
        References=["https://helpfiles.keysight.com/csg/89600B/Webhelp/Subsystems/sharing/content/data_header.htm",
                    "https://helpfiles.keysight.com/csg/89600B/Webhelp/Subsystems/sharing/content/inputspan.htm"],Files=receipts)
    write_json(root/"keysight/instrument_handoff.json",handoff)
    shutil.copy2(Path(__file__).resolve().parents[1]/"docs/lls/vxg_vsa_rank2_runbook.md",root/"keysight/hardware_checklist_and_runbook.md")
    shutil.copy2(Path(__file__).with_name("physical_measurement.schema.json"),root/"keysight/physical_measurement.schema.json")
    demod=dict(CarrierHz=fc,SCSHz=cfg["frame"]["scs_khz"]*1000,FFT=meta["FFTSize"],PRBs=cfg["frequency"]["n_size_grid"],
               Rank=layers,Modulation="1024QAM",Timing="configured native slot boundary; physical acquisition not verified",
               DL=cfg["research_dl"],UL=cfg["research_ul"],ULStandardsStatus=p["ul_standards_status"],
               TDD=cfg["frame"]["tdd_common"],AnalysisLicenseVerified=False,InputSpanHz=handoff["VSAInputSpanHz"])
    write_json(root/"vsa/vsa_demod_config.json",demod)
    replay["handoff"]=handoff; replay["files"]=receipts; replay["summary"]=summary
    write_json(root/"webgui/replay_data.json",replay)
    receipt=dict(WaveformExportReady=True,WebDemoReady=False,SoftwareHandoffReady=True,InstrumentCapability="UNKNOWN",
                 PayloadPass=bool(meta["PayloadPass"]),SourceCommit=meta["GitCommit"],StatisticallyQualified=False,
                 DigitalOnly=True,PackageScriptSHA256=digest(Path(__file__)))
    write_json(root/"validation/package_receipt.json",receipt)
    from vxg_vsa_demo_dashboard import build_dashboard
    build_dashboard(root,replay)
    source_folder=root/"meta/packaging_sources"; source_folder.mkdir(exist_ok=True)
    for name in source_names:
        require(digest(Path(__file__).with_name(name))==frozen_sources[name],"Packaging source changed during execution; re-run packaging on frozen source")
        shutil.copy2(Path(__file__).with_name(name),source_folder/name)
    repo=Path(__file__).resolve().parents[1]
    for name in ("+sixgr/+lls6g/+runners/runSingle.m", "simulator/configs/schema/scenario_parameter_catalog.yaml",
                 "scripts/run_vxg_vsa_demo.ps1", "tests/testLabWaveformCampaign.m", "tests/check_lab_waveform_browser.py",
                 "tests/test_lab_waveform_package.py"):
        target=source_folder/name; target.parent.mkdir(parents=True,exist_ok=True)
        shutil.copy2(repo/name,target)
    return root


if __name__=="__main__":
    parser=argparse.ArgumentParser(description=__doc__); parser.add_argument("run_folder",type=Path)
    print(package(parser.parse_args().run_folder))
