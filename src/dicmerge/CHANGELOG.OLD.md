# Changelog
All notable changes to this project will be documented in this file. See [conventional commits](https://www.conventionalcommits.org/) for commit guidelines.

- - -
## [v0.6.4](https://github.com/dcog989/dicmerge/compare/877a81f29e5684daff1eecbf2abd11d318ce2ce5..v0.6.4) - 2026-10-14
#### Bug Fixes
- (**discovery**) deduplicate identical dictionary files within a source - ([3cd1dc4](https://github.com/dcog989/dicmerge/commit/3cd1dc461853d94c53f3d2afffeb079174b5d416)) - dcog989
#### Build system
- (**deps**) bump astral-sh/setup-uv from 10.1.0 to 10.3.0 - ([877a81f](https://github.com/dcog989/dicmerge/commit/877a81f29e5684daff1eecbf2abd11d318ce2ce5)) - dependabot[bot]

- - -

## [v0.6.3](https://github.com/dcog989/dicmerge/compare/3e9a2b26692d1eabb577abee1ca4365bfcf971f6..v0.6.3) - 2026-10-14
#### Bug Fixes
- (**cli**) handle missing config file as ConfigError - ([29378a5](https://github.com/dcog989/dicmerge/commit/29378a56949043676057a54843b4679232407a70)) - dcog989
- (**config**) report malformed or unreadable config as exit 2 - ([73280e7](https://github.com/dcog989/dicmerge/commit/73280e799332573bfc4953b3def19b52ed2e0a6a)) - dcog989
- (**core**) always write utf-8 - ([f05480c](https://github.com/dcog989/dicmerge/commit/f05480c1f97954125f445fd5e983a31e820d468d)) - dcog989
- (**core**) skip write-back for sources that failed to scan - ([3d51e39](https://github.com/dcog989/dicmerge/commit/3d51e39131e5ccef8f096aa1ea4bb844ac8fd363)) - dcog989
- (**discovery**) match only real Firefox backup dir names in _is_backup - ([b043502](https://github.com/dcog989/dicmerge/commit/b0435022c04f0ccf73446ee32c3cc94131cb44ac)) - dcog989
- (**discovery**) skip non-file glob matches - ([63e3848](https://github.com/dcog989/dicmerge/commit/63e38480e2b071a5d8f7d723527ad27cdc0f8d6a)) - dcog989
- (**log**) rotate debug.log and fall back to stderr when unwritable - ([80e8063](https://github.com/dcog989/dicmerge/commit/80e806367ad0bd37fa313c0c8588ac1b2fb4d244)) - dcog989
- (**output**) keep destination mode instead of leaving files 0600 - ([b05df92](https://github.com/dcog989/dicmerge/commit/b05df92ba9befc259e985b1065bbedb042f2d8f7)) - dcog989
- (**util**) reject NUL-containing files instead of latin1-decoding them - ([cc98203](https://github.com/dcog989/dicmerge/commit/cc98203d95ff8f5ab7582729bbbed2d9fb2388d4)) - dcog989
- guard dicmerge.__main__ against running at import time - ([ab8641c](https://github.com/dcog989/dicmerge/commit/ab8641cf0390d68d6e45225e9024832fd7b92e06)) - dcog989
#### Performance Improvements
- (**libreoffice**) read only the header line when matching .dic files - ([14a6af4](https://github.com/dcog989/dicmerge/commit/14a6af44ba4d15dcb90c767a9c95564325458a04)) - dcog989
#### Documentation
- readme refined - ([b5f5ac5](https://github.com/dcog989/dicmerge/commit/b5f5ac5cdf162b9901c5d408cee90044dab2ef1f)) - dcog989
- readme refined - ([3714425](https://github.com/dcog989/dicmerge/commit/3714425b64d9e309b210c4fa18bc091698340b9f)) - dcog989
- agents.md refined - ([1656a7b](https://github.com/dcog989/dicmerge/commit/1656a7b8ed29fe088e5c4eefe1e88046948cc672)) - dcog989
#### Tests
- cover rws skip, output failure, and latin1 fallback paths - ([89bc0dd](https://github.com/dcog989/dicmerge/commit/89bc0dd073fe07eba1080b3edbb8fef7d6f86beb)) - dcog989
#### Build system
- (**deps**) bump astral-sh/setup-uv from 10.0.0 to 10.1.0 - ([d69dbfd](https://github.com/dcog989/dicmerge/commit/d69dbfd4b32ff90fd5bcd5571978c82d42cde088)) - dependabot[bot]
#### Continuous Integration
- add dependabot configuration - ([e0a8273](https://github.com/dcog989/dicmerge/commit/e0a827320c97c6afa5f32cd5980b5a3405242d9c)) - dcog989
#### Refactoring
- (**cli**) drop rich for plain print output - ([b6472ed](https://github.com/dcog989/dicmerge/commit/b6472edd15a1b941e8dc6bfa1fb632c14a399b69)) - dcog989
- (**output**) extract write_text_atomic and use it for write-back - ([b099465](https://github.com/dcog989/dicmerge/commit/b099465d861f16df95628e36c4a0a86a90af598c)) - dcog989
#### Miscellaneous Chores
- (**editorconfig**) generalize indentation rules for multi-language use - ([337ec82](https://github.com/dcog989/dicmerge/commit/337ec82b2ee19345b65770f9d348875f60bf5758)) - dcog989
- (**release**) run full checks in pre-bump hooks - ([22895f8](https://github.com/dcog989/dicmerge/commit/22895f8841e86addf555daba2fdba363e1e460d7)) - dcog989
- (**release**) publish cocogitto changelog as GitHub release body - ([3e9a2b2](https://github.com/dcog989/dicmerge/commit/3e9a2b26692d1eabb577abee1ca4365bfcf971f6)) - dcog989
- drop dead helpers, unused scanner extension attrs, and empty test files - ([e4c93e2](https://github.com/dcog989/dicmerge/commit/e4c93e2a1287e66a92c837363b9478b986dc70cc)) - dcog989
- updates - ([aea7a13](https://github.com/dcog989/dicmerge/commit/aea7a13f93f910f660ba5cd4a9bb809d1efa8e00)) - dcog989
- updates - ([a3e2b95](https://github.com/dcog989/dicmerge/commit/a3e2b9573f96cb5b6a4c2ac5297825006ed48c45)) - dcog989

- - -

## [v0.6.2](https://github.com/dcog989/dicmerge/compare/bcd6c25f548899076f77a8e2f8b1c02f2785a229..v0.6.2) - 2026-09-01
#### Continuous Integration
- pin setup-uv to v10.0.0 immutable tag - ([bcd6c25](https://github.com/dcog989/dicmerge/commit/bcd6c25f548899076f77a8e2f8b1c02f2785a229)) - dcog989

- - -

## [v0.6.1](https://github.com/dcog989/dicmerge/compare/eaa744adca8843bf22c212f972a84186469ac41a..v0.6.1) - 2026-09-01
#### Bug Fixes
- push correct tag ref in cog post-bump hooks - ([eaa744a](https://github.com/dcog989/dicmerge/commit/eaa744adca8843bf22c212f972a84186469ac41a)) - dcog989
#### Build system
- regenerate uv.lock in cog pre-bump hooks - ([624eadb](https://github.com/dcog989/dicmerge/commit/624eadbc85b7597a3944f18106db798cb514f3ca)) - dcog989

- - -

## [v0.6.0](https://github.com/dcog989/dicmerge/compare/c078cbce5fb91e3494273bfbfe9060313576650e..v0.6.0) - 2026-09-01
#### Build system
- push commits and tag after cog bump - ([c078cbc](https://github.com/dcog989/dicmerge/commit/c078cbce5fb91e3494273bfbfe9060313576650e)) - dcog989
#### Miscellaneous Chores
- update - ([df55411](https://github.com/dcog989/dicmerge/commit/df5541137caf065cea369c5f59caa69f39a0b9ea)) - dcog989

- - -

## [v0.5.1](https://github.com/dcog989/dicmerge/compare/e2835378adaee1a29fef1726995af29f7b372e40..v0.5.1) - 2026-09-01
#### Bug Fixes
- wrap backup creation in write-back error handling - ([b48a66e](https://github.com/dcog989/dicmerge/commit/b48a66ed70fea89139163d483356393bd93cd7c1)) - dcog989
- clarify output line under dry-run - ([4be38ba](https://github.com/dcog989/dicmerge/commit/4be38ba1f46041645fa1bae92210907bb3a12cd0)) - dcog989
- show write-back targets in dry-run - ([f0d042b](https://github.com/dcog989/dicmerge/commit/f0d042b8c5c755e6491850286eb856a7399db3ea)) - dcog989
- make --write-back flag work regardless of config - ([994b420](https://github.com/dcog989/dicmerge/commit/994b420cc1dfc18299a16e56458f93e70a835fc4)) - dcog989
- exclude Firefox crashrecovery backup dirs from discovery - ([4543124](https://github.com/dcog989/dicmerge/commit/4543124adfa48e7af30c28a1d6ad9a183d75f12d)) - dcog989
- stop dropping digit first line in plaintext scanner - ([f2da662](https://github.com/dcog989/dicmerge/commit/f2da6624a6a13f07f208c9dc74071449d90a381d)) - dcog989
- honor output encoding from config - ([f6980ba](https://github.com/dcog989/dicmerge/commit/f6980baa9f1c4933e38ff6b342a8f371579aecf8)) - dcog989
- refresh write-back backup on every run - ([9953ccf](https://github.com/dcog989/dicmerge/commit/9953ccf8f13f56dae1547d3684c7d3b3c8c4a6fb)) - dcog989
- honor write_back.enabled config and dry-run for write-back - ([b961b78](https://github.com/dcog989/dicmerge/commit/b961b781323d482576b64dec1b008da0f4afc2b7)) - dcog989
#### Documentation
- fix usage instructions - ([c62b76d](https://github.com/dcog989/dicmerge/commit/c62b76d20f1cc4dd3c6ac7981c69990d67de8876)) - dcog989
- readme ruff format - ([d2b5a5a](https://github.com/dcog989/dicmerge/commit/d2b5a5a35ec7ca15bf1e4c819e14c394d877634f)) - dcog989
- document write_back.enabled config toggle - ([e944839](https://github.com/dcog989/dicmerge/commit/e944839423cfd6d12c79b3cb85a76d1dfc3774ad)) - dcog989
- correct write-back behavior and document cocogitto + CI stack - ([c165d40](https://github.com/dcog989/dicmerge/commit/c165d400d53ee4c9ad446654cf62040d56ff03dd)) - dcog989
#### Build system
- migrate version bumping from version-bump script to cocogitto - ([e283537](https://github.com/dcog989/dicmerge/commit/e2835378adaee1a29fef1726995af29f7b372e40)) - dcog989
#### Continuous Integration
- add CI pipeline with lint, typecheck, and coverage gates - ([623ebec](https://github.com/dcog989/dicmerge/commit/623ebecd423a5cbce514090a15106fd80f0615e1)) - dcog989
#### Refactoring
- route --list-sources through core orchestration - ([433f93f](https://github.com/dcog989/dicmerge/commit/433f93f81178d60dff470cb44d4d00db98296af5)) - dcog989
- separate source discovery from config handling - ([26e8f65](https://github.com/dcog989/dicmerge/commit/26e8f65498e3ac1b4127648c74a01c9cbc8fc068)) - dcog989
- depend on Scanner abstraction in write-back - ([12aebd1](https://github.com/dcog989/dicmerge/commit/12aebd11900c8b7839c86f78f71c94d210cd9f86)) - dcog989
- close scanner dispatch via registry and matches() - ([9d984ce](https://github.com/dcog989/dicmerge/commit/9d984ce6b6e4beec3f5260dc6b08dfab7b0347ee)) - dcog989
- split run() into focused single-responsibility helpers - ([1d6342b](https://github.com/dcog989/dicmerge/commit/1d6342b5afa99a9ffe82284a7d8d493739cf184b)) - dcog989
- drop speculative multi-format output files - ([96f3163](https://github.com/dcog989/dicmerge/commit/96f3163ea02df63de4f456189bb68655ce443e18)) - dcog989
- remove unused missing_words helper - ([8f68879](https://github.com/dcog989/dicmerge/commit/8f68879485bddd4f55c47d737e3812e85ab48862)) - dcog989
- dedupe source discovery globbing in config - ([6b0ce2c](https://github.com/dcog989/dicmerge/commit/6b0ce2cb14393304608b5d87a94c51978eec8146)) - dcog989
- extract shared .rws skip check in core - ([9e2af66](https://github.com/dcog989/dicmerge/commit/9e2af66a27cdf504de78d7cedd8567f265013ac3)) - dcog989
- collapse duplicate scanner line-reading into base - ([bc2abe1](https://github.com/dcog989/dicmerge/commit/bc2abe1cd2537ec60908b7a561c9728cda53e022)) - dcog989

- - -

Changelog generated by [cocogitto](https://github.com/cocogitto/cocogitto).