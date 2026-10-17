# flac-conversion

Caps a FLAC library at 16-bit / 48 kHz, keeping each file in its rate family, and rewrites any file that carries a non-standard ID3v2 tag in front of its FLAC stream. Sources are never modified — output goes to a separate target tree.

Built for the `/mnt/data/Music` library (19,040 FLACs, ~609 GiB), where 206 files sit above 48 kHz, 59 carry a stray ID3v2 tag, and the rest is 44.1 kHz.

## Rules

A file is converted when it is above 16 bit, above 48 kHz, **or** carries a non-standard ID3v2 tag.

| Input | Output | Note |
| --- | --- | --- |
| 96 / 192 / 384 kHz, any depth above 16 bit | 48 kHz, 16 bit | dithered |
| 88.2 / 176.4 / 352.8 kHz, above 16 bit | 44.1 kHz, 16 bit | dithered |
| 24 bit at 44.1 / 48 kHz | same rate, 16 bit | dithered |
| 16 bit at 88.2 / 96 kHz and above | family rate, 16 bit | no depth change, so no dither |
| any FLAC with a leading ID3v2 tag | same rate and depth | rewritten to drop the tag, tags and art carried over |
| 16 bit at 44.1 / 48 kHz, no ID3v2 tag | untouched | not in the job list |

Rate is only ever lowered, by 2:1 where the family allows it. Bit depth is only ever lowered, to 16.

## Usage

```sh
./src/flac-conversion/flac-conversion.py scan    # Report the mix and write the job list to /tmp/opencode/flac-conversion-jobs.tsv

./src/flac-conversion/flac-conversion.py convert --dry-run    # print commands only
./src/flac-conversion/flac-conversion.py convert   # Review the list, then convert into the target tree (4 parallel ffmpeg jobs)

./src/flac-conversion/flac-conversion.py verify    # Check every output against its source before touching the originals
``` 

Defaults: `--source /mnt/data/Music`, `--target /mnt/data/Music-48k`, `--job-list /tmp/opencode/flac-conversion-jobs.tsv`, `--jobs 4`.

`scan` reads only the file header (STREAMINFO, skipping a non-standard ID3v2 tag placed in front of the FLAC stream — those files are read and listed per folder with the tag's size, since they are all rewritten) and reports anything unreadable or not actually FLAC, grouped by folder with the container it did find — MP3, Ogg, MP4/ALAC, WAV, truncated header, empty file — instead of a generic parse error. `convert` skips outputs that already exist with the right rate and bit depth, writes to `<name>.flac.part`, copies the tags across, confirms the new file decodes with `flac -t` (ffmpeg exits 0 even when it logs FLAC decode errors, so its status is not trusted), and renames on success — it keeps going when one file fails, and the exit code is non-zero if any did.

`verify` decodes every output end to end with `flac -t` (so a truncated or corrupt file is caught before its tags are even looked at), then compares rate, bit depth, channel count, sample count (scaled by the rate change) and `PICTURE` block count against the source, and requires the tag set to match exactly — missing and extra tags both fail (the source's tags come from the ffprobe view, so a stray ID3v2 tag counts as a source of tags). It exits non-zero on any mismatch. When an output's rate or bit depth changed, it also measures the peak level and warns without failing about samples at full scale, which is where a resample that overshot would have clipped. Run it before deleting or replacing originals; that step is deliberately not automated.

Tags survive by not trusting the encoder with them. ffmpeg is given no `-map_metadata`, and after each rewrite the source's tags are read with `ffprobe` and written onto the output with `metaflac`, replacing whatever the encoder left behind. That is why a file whose metadata lives only in its ID3v2 tag keeps it: the tag is gone, the values are not. If a source has no tags, the output has none — the encoder's own `encoder=Lavf…` tag is removed too.

## Dependencies

`ffmpeg` (with `libsoxr`; `verify` also uses it for the peak measurement), `ffprobe`, `metaflac`, `flac` (the end-to-end decode test in `convert` and `verify`). All are installed.

## Caveats

- Transcoding is one-way. Keep the originals until `verify` is clean.
- 88.2 → 48 kHz, if ever forced by a device, is a non-integer resample. The default family-preserving mapping avoids it.
- 24 → 16 bit is dithered (`triangular_hp`) because undithered truncation turns quantization error into distortion rather than noise.
- A file rewritten only to drop its ID3v2 tag is still re-encoded: the audio is the same, the file bytes are not.
- Tag values are compared exactly, keys case-insensitively. A converter that rewrites a value instead of dropping it would pass.
- Sample counts are compared by scaling the source count by the rate change (the family mappings are exact integer ratios). A source whose STREAMINFO stores no total (`0`, meaning unknown) is not length-checked.
- Cover art comes from ffmpeg (`-map 0`), which keeps the `PICTURE` blocks as they are. If a source has no embedded art, nothing is added.
