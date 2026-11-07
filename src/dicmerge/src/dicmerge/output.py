import os
import shutil
import stat
from pathlib import Path
from tempfile import NamedTemporaryFile

_DEFAULT_MODE = 0o644


def write_words(path: Path, words: list[str]) -> None:
    write_text_atomic(path, "".join(f"{word}\n" for word in words))


def write_text_atomic(path: Path, content: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    mode = stat.S_IMODE(path.stat().st_mode) if path.exists() else _DEFAULT_MODE
    tmp_path: Path | None = None
    try:
        with NamedTemporaryFile(
            mode="w",
            encoding="utf-8",
            dir=path.parent,
            prefix=".dicmerge_",
            delete=False,
        ) as tmp:
            tmp_path = Path(tmp.name)
            tmp.write(content)
            tmp.flush()
        if tmp_path is None:
            raise RuntimeError("temporary file was not created")
        os.chmod(tmp_path, mode)
        shutil.move(tmp_path, path)
    except Exception:
        if tmp_path is not None:
            tmp_path.unlink(missing_ok=True)
        raise
