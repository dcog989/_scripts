from pathlib import Path

import pytest

from dicmerge.scanner.codebook import CodebookScanner
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


CODEBOOK = 'dictionaries = [\n    "en_us",\n    "en_gb",\n]\nwords = [\n    "foo",\n    "bar",\n]\n'


def test_codebook_matches_filename(tmp_path: Path):
    assert CodebookScanner.matches(tmp_path / "codebook.toml") is True
    assert CodebookScanner.matches(tmp_path / "other.toml") is False


def test_codebook_read_returns_words_only(tmp_path: Path):
    f = tmp_path / "codebook.toml"
    f.write_text(CODEBOOK, encoding="utf-8")
    assert CodebookScanner().read(f) == ["foo", "bar"]


def test_codebook_read_missing_words_key(tmp_path: Path):
    f = tmp_path / "codebook.toml"
    f.write_text('dictionaries = ["en_us"]\n', encoding="utf-8")
    assert CodebookScanner().read(f) == []


def test_codebook_read_rejects_non_string_words(tmp_path: Path):
    f = tmp_path / "codebook.toml"
    f.write_text("words = [1, 2]\n", encoding="utf-8")
    with pytest.raises(ValueError, match="list of strings"):
        CodebookScanner().read(f)


def test_codebook_format_output_preserves_dictionaries(tmp_path: Path):
    f = tmp_path / "codebook.toml"
    f.write_text(CODEBOOK, encoding="utf-8")
    rendered = CodebookScanner().format_output(f, ["bar", "foo"])
    assert rendered == 'dictionaries = [\n    "en_us",\n    "en_gb",\n]\nwords = [\n    "bar",\n    "foo",\n]\n'


def test_codebook_format_output_preserves_unknown_keys_and_comments(tmp_path: Path):
    f = tmp_path / "codebook.toml"
    original = "# keep me\n[settings]\ncase_sensitive = true\n\n" + CODEBOOK
    f.write_text(original, encoding="utf-8")

    rendered = CodebookScanner().format_output(f, ["baz"])

    assert "# keep me" in rendered
    assert "[settings]\ncase_sensitive = true" in rendered
    assert 'words = [\n    "baz",\n]' in rendered


def test_codebook_format_output_replaces_inline_words_array(tmp_path: Path):
    f = tmp_path / "codebook.toml"
    f.write_text('words = []\ndictionaries = ["en_us"]\n', encoding="utf-8")

    rendered = CodebookScanner().format_output(f, ["baz"])

    assert rendered == 'words = [\n    "baz",\n]\ndictionaries = ["en_us"]\n'


def test_libreoffice_format_output_preserves_header(tmp_path: Path):
    f = tmp_path / "custom.dic"
    f.write_text("OOoUserDict1\nlang: de-DE\ntype: positive\nreplacement: \nHaus\n", encoding="utf-8")

    rendered = LibreOfficeScanner().format_output(f, ["Haus", "Baum"])

    assert rendered == "OOoUserDict1\nlang: de-DE\ntype: positive\nreplacement: \nHaus\nBaum\n"
