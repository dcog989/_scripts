# flac-conversion

Caps a FLAC library at 16-bit / 48 kHz, keeping each file in its rate family. Sources are never modified — output goes to a separate target tree.

Built for the `/mnt/data/Music` library (19,040 FLACs, ~609 GiB), where 206 files sit above 48 kHz and the rest is 44.1 kHz.

## Rules

A file is converted only when it is above 16 bit **or** above 48 kHz.

| Input | Output | Note |
| --- | --- | --- |
| 96 / 192 / 384 kHz, any depth above 16 bit | 48 kHz, 16 bit | dithered |
| 88.2 / 176.4 / 352.8 kHz, above 16 bit | 44.1 kHz, 16 bit | dithered |
| 24 bit at 44.1 / 48 kHz | same rate, 16 bit | dithered |
| 16 bit at 88.2 / 96 kHz and above | family rate, 16 bit | no depth change, so no dither |
| 16 bit at 44.1 / 48 kHz | untouched | not in the job list |

Rate is only ever lowered, by 2:1 where the family allows it. Bit depth is only
ever lowered, to 16.

## Usage

```sh
# 1. Report the mix and write the job list to /tmp/opencode/flac-conversion-jobs.tsv
./src/flac-conversion/flac-conversion.py scan

# 2. Review the list, then convert into the target tree (4 parallel ffmpeg jobs)
./src/flac-conversion/flac-conversion.py convert
./src/flac-conversion/flac-conversion.py convert --dry-run    # print commands only

# 3. Check every output against its source before touching the originals
./src/flac-conversion/flac-conversion.py verify
```

Defaults: `--source /mnt/data/Music`, `--target /mnt/data/Music-48k`,
`--job-list /tmp/opencode/flac-conversion-jobs.tsv`, `--jobs 4`.

`scan` reads only the file header (STREAMINFO, skipping a non-standard ID3v2 tag placed in front of the FLAC stream — those files are read, and listed per folder with how many of them are in the job list, since the tag is only dropped for files that actually get converted) and reports anything unreadable or not actually FLAC, grouped by folder with the container it did find — MP3, Ogg, MP4/ALAC, WAV, truncated header, empty file — instead of a generic parse error. `convert` skips outputs that already exist with the right rate and bit depth, writes to `<name>.flac.part`
and renames on success, and keeps going when one file fails — the exit code is non-zero if any did.

`verify` compares rate, bit depth, channel count, `PICTURE` block count and every `VORBIS_COMMENT` tag against the source (an output may add tags such as `encoder`, but must not drop one), and exits non-zero on any mismatch. Run it before deleting or replacing originals; that step is deliberately not automated.

## Dependencies

`ffmpeg` (with `libsoxr`), `metaflac`. Both are installed.

## Caveats

- Transcoding is one-way. Keep the originals until `verify` is clean.
- 88.2 → 48 kHz, if ever forced by a device, is a non-integer resample. The
  default family-preserving mapping avoids it.
- 24 → 16 bit is dithered (`triangular_hp`) because undithered truncation turns
  quantization error into distortion rather than noise.
- Tags and cover art are carried over with `-map_metadata 0` and `-map 0`. If a
  source has no embedded art, nothing is added.
