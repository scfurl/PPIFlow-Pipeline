"""
Minimal local fallback for dm-tree used by this codebase.

Only `map_structure` is implemented because that's all current callers use.
"""

from __future__ import annotations

from typing import Any, Callable


def map_structure(func: Callable[..., Any], *structures: Any) -> Any:
    if not structures:
        raise TypeError("map_structure requires at least one structure")

    first = structures[0]

    if isinstance(first, dict):
        keys = list(first.keys())
        return {
            k: map_structure(func, *(s[k] for s in structures))
            for k in keys
        }

    if isinstance(first, list):
        return [
            map_structure(func, *(s[i] for s in structures))
            for i in range(len(first))
        ]

    if isinstance(first, tuple):
        values = [
            map_structure(func, *(s[i] for s in structures))
            for i in range(len(first))
        ]
        if hasattr(first, "_fields"):
            return type(first)(*values)
        return tuple(values)

    return func(*structures)
