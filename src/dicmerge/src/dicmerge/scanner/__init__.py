from pathlib import Path

from dicmerge.scanner.base import Scanner
from dicmerge.scanner.codebook import CodebookScanner
from dicmerge.scanner.libreoffice import LibreOfficeScanner
from dicmerge.scanner.plaintext import PlainTextScanner

_SCANNERS: tuple[type[Scanner], ...] = (CodebookScanner, LibreOfficeScanner)


def get_scanner(path: Path) -> Scanner:
    for scanner_cls in _SCANNERS:
        if scanner_cls.matches(path):
            return scanner_cls()
    return PlainTextScanner()
