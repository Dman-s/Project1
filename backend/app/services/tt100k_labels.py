"""Canonical TT100K class IDs used by the local detector API."""

from collections.abc import Mapping, Sequence


TT100K_COMMON_45_CLASSES = (
    "i2",
    "i4",
    "i5",
    "il100",
    "il60",
    "il80",
    "io",
    "ip",
    "p10",
    "p11",
    "p12",
    "p19",
    "p23",
    "p26",
    "p27",
    "p3",
    "p5",
    "p6",
    "pg",
    "ph4",
    "ph4.5",
    "ph5",
    "pl100",
    "pl120",
    "pl20",
    "pl30",
    "pl40",
    "pl5",
    "pl50",
    "pl60",
    "pl70",
    "pl80",
    "pm20",
    "pm30",
    "pm55",
    "pn",
    "pne",
    "po",
    "pr40",
    "w13",
    "w32",
    "w55",
    "w57",
    "w59",
    "wo",
)

TT100K_CLASS_ALIASES = {
    "i160": "il60",
    "p\u00f3": "p6",
    "pL80": "pl80",
}


def _ordered_names(names: Mapping[int, str] | Sequence[str]) -> list[tuple[int, str]]:
    if isinstance(names, Mapping):
        return sorted((int(class_id), str(name)) for class_id, name in names.items())
    return [(class_id, str(name)) for class_id, name in enumerate(names)]


def build_tt100k_class_id_map(
    names: Mapping[int, str] | Sequence[str],
) -> dict[int, int]:
    canonical_ids = {
        name: class_id for class_id, name in enumerate(TT100K_COMMON_45_CLASSES)
    }
    mapping = {}
    used_ids = set()
    for native_id, raw_name in _ordered_names(names):
        normalized_name = TT100K_CLASS_ALIASES.get(raw_name.strip(), raw_name.strip())
        if normalized_name not in canonical_ids:
            raise ValueError(f"Unknown TT100K class name: {raw_name}")
        canonical_id = canonical_ids[normalized_name]
        if canonical_id in used_ids:
            raise ValueError(f"Duplicate TT100K class name: {normalized_name}")
        mapping[native_id] = canonical_id
        used_ids.add(canonical_id)
    return mapping
