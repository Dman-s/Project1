from app.services.tt100k_labels import (
    TT100K_COMMON_45_CLASSES,
    TT100K_COMMON_45_LABELS_ZH,
    tt100k_label_zh,
)


def test_tt100k_common_45_chinese_labels_are_complete():
    assert len(TT100K_COMMON_45_CLASSES) == 45
    assert len(TT100K_COMMON_45_LABELS_ZH) == 45
    assert all(label.strip() for label in TT100K_COMMON_45_LABELS_ZH)


def test_tt100k_label_zh_returns_representative_meanings():
    assert tt100k_label_zh("p10") == "禁止小型客车驶入"
    assert tt100k_label_zh("p23") == "禁止向左转弯"
    assert tt100k_label_zh("pl5") == "最高限速 5 km/h"
    assert tt100k_label_zh("pl60") == "最高限速 60 km/h"
    assert tt100k_label_zh("unknown") is None


def test_tt100k_label_zh_normalizes_whitespace_and_aliases():
    assert tt100k_label_zh("  pL80  ") == "最高限速 80 km/h"
