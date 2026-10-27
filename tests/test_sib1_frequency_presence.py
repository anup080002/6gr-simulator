"""Exact optional frequency IEs; syntax preservation is not installation."""
import csv
import json
from pathlib import Path
import pytest
from tools.initial_access import nr_sib1_codec as codec

def source():
    with (Path(__file__).parent/'vectors/initial_access/sib1_release18_uper_vectors.csv').open() as h:
        return json.loads(next(csv.DictReader(h))['SemanticJSON'])

@pytest.mark.parametrize('point,band',[(False,False),(True,True),(True,False),(False,True)])
def test_optional_frequency_fields_are_independently_lossless(point,band):
    s=source();s.pop('absolute_frequency_point_a',None);s['band']=40
    s['uplink_frequency_band_present']=band
    if point:s['absolute_frequency_point_a']=468164
    if band:s['uplink_frequency_band']=40
    s['dl_offset_to_carrier']=3;s['ul_offset_to_carrier']=7
    s['ul_carrier_subcarrier_spacing_khz']=15;s['ul_carrier_bandwidth_rb']=106
    value=codec.bounded_object(s)
    wire=codec.CODEC.to_uper(value);codec.CODEC.from_uper(wire)
    decoded=codec.semantic_from_object(codec.CODEC.get_val())
    assert ('absolute_frequency_point_a' in decoded)==point
    assert ('uplink_frequency_band' in decoded)==band
    assert decoded['dl_offset_to_carrier']==3 and decoded['ul_offset_to_carrier']==7
    assert decoded['ul_carrier_subcarrier_spacing_khz']==15 and decoded['ul_carrier_bandwidth_rb']==106
    assert codec.CODEC.to_uper(codec.bounded_object(decoded))==wire

def test_original_independent_vectors_remain_exact():
    with (Path(__file__).parent/'vectors/initial_access/sib1_release18_uper_vectors.csv').open() as h:
        for row in csv.DictReader(h):
            if row['ExpectedBehavior']!='ACCEPT':
                continue
            s=json.loads(row['SemanticJSON'])
            wire=codec.CODEC.to_uper(codec.bounded_object(s))
            assert wire.hex().upper()==row['UPERHex']
            codec.CODEC.from_uper(wire)
            decoded=codec.semantic_from_object(codec.CODEC.get_val())
            assert codec.CODEC.to_uper(codec.bounded_object(decoded))==wire
