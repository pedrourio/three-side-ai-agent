import importlib
import sys

WEB_MODULES = ("fastapi", "uvicorn", "starlette")


def _forget(prefixes: tuple[str, ...]) -> None:
    for name in list(sys.modules):
        if name in prefixes or name.startswith(tuple(p + "." for p in prefixes)):
            del sys.modules[name]


def test_importing_core_does_not_load_a_web_framework():
    """core roda em script de terminal e em teste; não pode arrastar servidor."""
    _forget(("core",) + WEB_MODULES)
    importlib.import_module("core")
    assert not [m for m in WEB_MODULES if m in sys.modules]
