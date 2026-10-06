"""Small fake installations; never execute their launchers."""
from pathlib import Path


def installation(base, name):
    path = Path(base) / name
    path.mkdir()
    (path / "proton").write_text("#!/bin/sh\nexit 0\n")
    (path / "proton").chmod(0o755)
    (path / "compatibilitytool.vdf").write_text(
        '"compatibilitytools" { "compat_tools" { "' + name + '" { "install_path" "." } } }\n'
    )
    (path / "toolmanifest.vdf").write_text('"manifest" { "commandline" "/proton run" }\n')
    return path


def configuration(root):
    root = Path(root)
    base = root / "compatibilitytools.d"
    base.mkdir()
    config = root / "umu.toml"
    config.write_text('[umu]\nproton = "/sandbox/GE-Proton11-7"\nexe = "game.exe"\n')
    return {"compatibilityToolsDir": str(base), "umuConfigPath": str(config),
            "sandboxCompatibilityToolsDir": "/sandbox"}
