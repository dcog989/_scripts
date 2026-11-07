from dicmerge.dedup import deduplicate


def test_deduplicate_removes_duplicates():
    words = ["foo", "bar", "foo", "baz", "bar"]
    assert deduplicate(words) == ["foo", "bar", "baz"]


def test_deduplicate_case_insensitive():
    words = ["Foo", "foo", "FOO"]
    assert deduplicate(words) == ["Foo"]


def test_deduplicate_preserves_first_occurrence():
    words = ["Foo", "bar", "foo"]
    assert deduplicate(words) == ["Foo", "bar"]


def test_deduplicate_empty():
    assert deduplicate([]) == []


def test_deduplicate_no_duplicates():
    words = ["alpha", "beta", "gamma"]
    assert deduplicate(words) == ["alpha", "beta", "gamma"]
