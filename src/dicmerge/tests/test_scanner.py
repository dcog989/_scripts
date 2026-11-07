from pathlib import Path

from dicmerge.scanner.firefox import FirefoxScanner
from dicmerge.scanner.libreoffice import LibreOfficeScanner
from dicmerge.scanner.plaintext import PlainTextScanner


def test_plaintext_read(tmp_path: Path):
    f = tmp_path / "dict.txt"
    f.write_text("foo\nbar\nbaz\n", encoding="utf-8")
    scanner = PlainTextScanner()
    assert scanner.read(f) == ["foo", "bar", "baz"]


def test_plaintext_read_strips_whitespace(tmp_path: Path):
    f = tmp_path / "dict.txt"
    f.write_text("  foo  \n\tbar\t\n", encoding="utf-8")
    scanner = PlainTextScanner()
    assert scanner.read(f) == ["foo", "bar"]


def test_plaintext_read_skips_empty_lines(tmp_path: Path):
    f = tmp_path / "dict.txt"
    f.write_text("foo\n\n\nbar\n", encoding="utf-8")
    scanner = PlainTextScanner()
    assert scanner.read(f) == ["foo", "bar"]


def test_plaintext_read_keeps_digit_first_line(tmp_path: Path):
    f = tmp_path / "dict.txt"
    f.write_text("12345\nfoo\nbar\n", encoding="utf-8")
    scanner = PlainTextScanner()
    assert scanner.read(f) == ["12345", "foo", "bar"]


def test_plaintext_read_keeps_non_digit_first_line(tmp_path: Path):
    f = tmp_path / "dict.txt"
    f.write_text("foo\nbar\nbaz\n", encoding="utf-8")
    scanner = PlainTextScanner()
    assert scanner.read(f) == ["foo", "bar", "baz"]


def test_plaintext_read_latin1_fallback(tmp_path: Path):
    f = tmp_path / "dict.txt"
    f.write_bytes("café\n".encode("latin1"))
    scanner = PlainTextScanner()
    assert scanner.read(f) == ["café"]


def test_firefox_read(tmp_path: Path):
    f = tmp_path / "persdict.dat"
    f.write_text("foo\nbar\nbaz\n", encoding="utf-8")
    scanner = FirefoxScanner()
    assert scanner.read(f) == ["foo", "bar", "baz"]


def test_firefox_does_not_skip_digit_line(tmp_path: Path):
    f = tmp_path / "persdict.dat"
    f.write_text("12345\nfoo\n", encoding="utf-8")
    scanner = FirefoxScanner()
    assert scanner.read(f) == ["12345", "foo"]


HEADER = "OOoUserDict1\nlang: en-US\ntype: positive\nreplacement: \n"


def test_libreoffice_read_basic(tmp_path: Path):
    f = tmp_path / "custom.dic"
    f.write_text(HEADER + "foo\nbar\nbaz\n", encoding="utf-8")
    scanner = LibreOfficeScanner()
    assert scanner.read(f) == ["foo", "bar", "baz"]


def test_libreoffice_read_skips_header(tmp_path: Path):
    f = tmp_path / "custom.dic"
    lines = "OOoUserDict1\nsome_header_word\ntype: positive\nreplacement: \nactual_word\n"
    f.write_text(lines, encoding="utf-8")
    scanner = LibreOfficeScanner()
    assert scanner.read(f) == ["actual_word"]


def test_libreoffice_read_less_than_4_lines(tmp_path: Path):
    f = tmp_path / "custom.dic"
    f.write_text("line1\nline2\n", encoding="utf-8")
    scanner = LibreOfficeScanner()
    assert scanner.read(f) == []


def test_libreoffice_read_exactly_4_lines(tmp_path: Path):
    f = tmp_path / "custom.dic"
    f.write_text(HEADER, encoding="utf-8")
    scanner = LibreOfficeScanner()
    assert scanner.read(f) == []


def test_libreoffice_read_empty_file(tmp_path: Path):
    f = tmp_path / "custom.dic"
    f.write_text("", encoding="utf-8")
    scanner = LibreOfficeScanner()
    assert scanner.read(f) == []


def test_libreoffice_read_skips_empty_lines_after_header(tmp_path: Path):
    f = tmp_path / "custom.dic"
    f.write_text(HEADER + "foo\n\n\nbar\n", encoding="utf-8")
    scanner = LibreOfficeScanner()
    assert scanner.read(f) == ["foo", "bar"]


def test_libreoffice_read_strips_whitespace(tmp_path: Path):
    f = tmp_path / "custom.dic"
    f.write_text(HEADER + "  foo  \n\tbar\t\n", encoding="utf-8")
    scanner = LibreOfficeScanner()
    assert scanner.read(f) == ["foo", "bar"]


def test_libreoffice_matches_header_line(tmp_path: Path):
    f = tmp_path / "custom.dic"
    f.write_text(HEADER + "foo\n", encoding="utf-8")
    assert LibreOfficeScanner.matches(f) is True


def test_libreoffice_does_not_match_plain_word_list(tmp_path: Path):
    f = tmp_path / "words.dic"
    f.write_text("foo\nbar\n", encoding="utf-8")
    assert LibreOfficeScanner.matches(f) is False


def test_libreoffice_does_not_match_undecodable_file(tmp_path: Path):
    f = tmp_path / "custom.dic"
    f.write_bytes("foo\n".encode("utf-16-le"))
    assert LibreOfficeScanner.matches(f) is False
