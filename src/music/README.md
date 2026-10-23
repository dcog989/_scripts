# flac-conversion

Caps a FLAC library at 16-bit / 48 kHz, keeping each file's rate family, and rewrites files with a non-standard ID3v2 tag in front of the FLAC stream. Sources are never modified; output goes to a separate tree. Built for `/mnt/data/Music`.

```sh
/home/bubba/Projects/_scripts/src/music/flac-conversion.py scan                 # report mix, write job list
/home/bubba/Projects/_scripts/src/music/flac-conversion.py convert              # transcode into the target tree
/home/bubba/Projects/_scripts/src/music/flac-conversion.py verify               # decode and compare outputs against sources
/home/bubba/Projects/_scripts/src/music/flac-conversion.py move                 # replace sources with verified outputs
```

Add `--dry-run` to `convert` and `move` to print only. Defaults: `--source /mnt/data/Music`, `--target /mnt/data/Music-48k`, `--job-list /tmp/opencode/flac-conversion-jobs.tsv`, `--jobs 8`.

`verify` decodes each output end to end and compares rate, bit depth, channels, sample count, art blocks and the exact tag set against its source, plus the peak level for resampled files; `move` refuses anything that fails.

A file is converted when it is above 16 bit, above 48 kHz, or has an ID3v2 tag. Rate drops 2:1 to the family cap (88.2→44.1, 96→48 kHz); depth drops to 16 (dithered). `convert` skips outputs already in the right format, so re-running it is safe.

Tags are copied from the source's own Vorbis comments with `metaflac`, keys and duplicates intact; `ffprobe` fills in only what a stray ID3v2 tag holds. Cover art passes through (`-map 0`).

Requires `ffmpeg` (with `libsoxr`), `ffprobe`, `metaflac`, `flac`.

Caveats: transcoding is one-way, so run `verify` before `move`; a tag-only rewrite keeps its audio but the file bytes change; a source with no total sample count is not length-checked.
