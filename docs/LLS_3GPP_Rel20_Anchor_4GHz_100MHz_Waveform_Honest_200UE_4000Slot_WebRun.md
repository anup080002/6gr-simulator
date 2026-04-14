# LLS 3GPP Rel20 Anchor 4 GHz 100 MHz Waveform Honest 200 UE 4000 Slot Web Run

- Scenario: `lls_3gpp_rel20_anchor_4ghz_100mhz_waveform_honest_200ue_4000slot`
- Active scenario file: `simulator/configs/scenarios/lls_3gpp_rel20_anchor_4ghz_100mhz_waveform_honest_200ue_4000slot.yaml`
- Compatibility alias: `configs/scenarios/lls_3gpp_rel20_anchor_4ghz_100mhz_waveform_honest_200ue_4000slot.yaml`
- Browser default: `apps/lls_web_dashboard.py` `DEFAULT_SCENARIO`

This browser-owned run stays on the current NR PHY/MAC baseline while using Rel-20 only as the study anchor. The active execution path is `/run` -> `run_6g_phy_lls_single` -> `system_level_lls`, with waveform-backed grant replay where the repo supports it and explicit abstraction/unavailable labeling elsewhere.

Key locked values:
- `200` UEs
- `4000` total slots
- `500` warmup slots
- `3500` measurement slots
- `4 GHz`
- `100 MHz`
- `TDD`
- `30 kHz` SCS
- `273` RB
- `7` sites / `21` cells
- `full_buffer` traffic

Launch helper:
```powershell
.\scripts\run_lls_from_web_gui_equivalent.ps1
```
