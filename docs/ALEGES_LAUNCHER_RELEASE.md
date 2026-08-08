# Aleges Launcher Release Guide

This is the launcher-repository source of truth for updating launcher code, preserving Aleges branding, building the cross-platform packages, and handing one validated bundle to the Aleges Website repository. The Website repository's `docs/LAUNCHER_CLIENT_RELEASE_RUNBOOK.md` remains authoritative for Git LFS, bootstrap integration, VM publication, CDN purge, public verification, containment, and rollback.

## Launcher And Game Client Are Separate

Do not treat every client update as a launcher release.

- This repository builds the Aleges **launcher** and its installers.
- `aleges-client.jar` is the portable Java 17 **launcher**, despite its historical filename.
- A file such as `aleges-client-1.12.35-rev240-1.jar` is the actual Aleges **game client**. It is built and versioned outside this repository and belongs in the Website bootstrap `artifacts[]` array.
- A launcher-only release replaces launcher downloads and bootstrap `updates[]`; it preserves the game-client version, `artifacts[]`, native runtime artifacts, and JVM argument arrays.
- A client-only release publishes a new immutable game-client filename and updates the matching bootstrap client metadata; it does not rebuild this launcher unless launcher code also changed.

The hosted production manifest is always:

```text
https://aleges.com/integration/bootstrap.json
```

`bootstrap.json.example` is historical reference data. Never deploy it as the live Aleges bootstrap and never replace the Website bootstrap with an upstream RuneLite bootstrap.

## Branding Contract

Every upstream merge and every release must preserve all of these Aleges invariants:

- product, executable, application, installer, shortcut, and install-directory names use `Aleges`;
- the launcher bootstrap URL is `https://aleges.com/integration/bootstrap.json`;
- the launcher website/download link uses `https://aleges.com/`;
- Windows, Linux, macOS, portable-JAR, icon, and splash assets are the Aleges assets;
- the splash progress color is Aleges orange `#DC8A00` (`RGB 220, 138, 0`), enforced by `SplashScreenTest.testAlegesProgressColor`;
- canonical Website names and immutable updater names follow the inventory below.

The principal branding sources are:

```text
src/main/resources/net/runelite/launcher/launcher.properties
src/main/resources/net/runelite/launcher/runelite_128.png
src/main/resources/net/runelite/launcher/runelite_splash.png
src/main/java/net/runelite/launcher/Constants.java
src/main/java/net/runelite/launcher/SplashScreen.java
innosetup/runelite.ico
innosetup/runelite_small.bmp
appimage/runelite.png
osx/runelite.icns
gradle.properties
build.gradle.kts
```

Do not accept an upstream conflict resolution that silently restores RuneLite names, URLs, paths, icons, or the old green progress color.

## Version Rule

The launcher version is assigned in `build.gradle.kts`. Every set of launcher bytes published to players must use a version strictly newer than every previously published or quarantined build.

- Version `2.8.3` is already assigned to the validated Aleges release from launcher commit `9631a5002a5f9cdef818a42b724dc1bf7c0fed74`.
- The production 2.8.3 bytes are exactly the validated `website-release` from successful workflow run `31243423957`, published through Website release-content commit `9ef5b0fd41d1bf05208cdc1fb823747a57ff6127` and publicly verified on 2026-08-08. Do not replace them with a second rebuild of the same version.
- The next different launcher build published to the Website must therefore be `2.8.4` or newer.
- Never rebuild changed bytes and publish them under an existing immutable filename such as `aleges-launcher-2.8.3-windows-x64.exe`.
- A CI-only packaging or documentation run may retain the source version, but its rebuilt installers must not replace already-published immutable files. Bump the version before using a fresh build as a new launcher release.

The one-time CI packaging/documentation cleanup that removes the public macOS tar archive is not a new launcher release. Commit that maintenance change with `[skip ci]` in the commit subject so the push does not create a second, potentially byte-different 2.8.3 bundle. Do not manually dispatch the workflow at 2.8.3 merely to test that maintenance commit. Its PowerShell assembly contract and YAML must be validated locally; the complete workflow change will receive CI exercise with the next intentionally built release, after its version is first bumped to 2.8.4 or newer.

## Updating From Upstream

1. Fetch the official `runelite` remote and review the incoming commits.
2. Merge the selected official launcher commits on a release branch.
3. Resolve conflicts while preserving the complete branding contract above.
4. Review changes to bootstrap parsing, updater selection, platform/architecture names, JVM requirements, packaging scripts, and CI actions.
5. Bump `build.gradle.kts` to a never-used version when the resulting launcher binaries will be published.
6. Run the launcher tests with JDK 17:

```powershell
./gradlew.bat clean test build -P RUNELITE_BUILD=runelite --no-daemon
```

7. Inspect the diff and confirm that no unrelated upstream branding or URL was introduced.
8. Commit and push the exact reviewed launcher commit. Deploy only artifacts produced from an all-green `main` workflow run for that commit.

## CI Artifact Contract

The GitHub Actions workflow builds three platform staging artifacts:

- `website-windows`: three Windows installers;
- `website-linux`: two AppImages and the portable launcher JAR;
- `website-macos`: two player-facing DMGs.

The macOS job also uploads `macos-app`, containing `app.tar`. That internal archive preserves application-bundle permissions for CI or downstream packaging. It is not a Website player download and is deliberately excluded by the `website-*` merge pattern.

The Linux container fixes `GRADLE_USER_HOME` at `/github/home/.gradle` and creates its `caches` and `wrapper` directories before `actions/setup-java`. Preserve that ordering during upstream workflow merges; it prevents the setup-java cache action from warning that its Gradle cache paths do not exist.

The `website-release` job downloads only `website-*`, runs `ci/prepare-website-release.ps1` to assemble the release, reruns the same script with `-ValidateOnly`, and uploads one final artifact named `website-release`. Integrate only this final artifact.

The final artifact root contains exactly:

```text
website-release/
  aleges-launcher-updates.json
  downloads/
    8 canonical player downloads
    7 immutable updater copies
```

There are exactly 15 files under `downloads/`. The validator rejects missing files, extra files, empty files, mismatched canonical/immutable pairs, incorrect embedded launcher version/URL properties, missing or empty expected icon/splash resources, duplicate or incorrectly cased selectors, invalid URLs, and incorrect sizes or SHA-256 hashes.

Resource filenames alone do not prove the pixels are the approved Aleges artwork, and this assembly validator does not inspect every native package's displayed metadata or CPU architecture. Before release, compare the icon/splash source hashes with the approved Aleges assets, inspect the resulting packages, and verify each native package's branding and architecture. These manual gates are required in addition to the automated validator.

### Eight Canonical Player Downloads

| Platform | Canonical Website filename |
|---|---|
| Windows x64 | `aleges-windows-x64.exe` |
| Windows x86 | `aleges-windows-x86.exe` |
| Windows ARM64 | `aleges-windows-arm64.exe` |
| Linux x64 | `aleges-linux-x64.AppImage` |
| Linux ARM64 | `aleges-linux-aarch64.AppImage` |
| macOS Intel | `aleges-macos-intel.dmg` |
| macOS Apple Silicon | `aleges-macos-apple-silicon.dmg` |
| Portable Java 17 launcher | `aleges-client.jar` |

These stable canonical names are the only launcher binaries that belong on the Website player download page. They are mutable aliases replaced by a newer verified launcher release.

### Seven Immutable Self-Update Copies

For launcher version `<version>`, CI makes byte-identical immutable copies for the seven native platform targets:

| Selector | Immutable filename |
|---|---|
| Windows `amd64` | `aleges-launcher-<version>-windows-x64.exe` |
| Windows `x86` | `aleges-launcher-<version>-windows-x86.exe` |
| Windows `aarch64` | `aleges-launcher-<version>-windows-arm64.exe` |
| Linux `amd64` | `aleges-launcher-<version>-linux-x64.AppImage` |
| Linux `aarch64` | `aleges-launcher-<version>-linux-aarch64.AppImage` |
| macOS `x86_64` | `aleges-launcher-<version>-macos-intel.dmg` |
| macOS `aarch64` | `aleges-launcher-<version>-macos-apple-silicon.dmg` |

These files are consumed automatically through bootstrap `updates[]`. Do not add duplicate player-download cards for them. The portable JAR has no immutable updater copy because it is not a native self-update target.

## Validate The Downloaded Artifact

Download `website-release` from the successful workflow run for the exact trusted commit and record the run URL and GitHub artifact digest. Before extraction, hash the downloaded ZIP and require an exact digest match:

```powershell
$releaseZip = 'C:\path\to\website-release.zip'
$expectedDigest = '<64-character lowercase digest shown by GitHub Actions>'
$actualDigest = (Get-FileHash -LiteralPath $releaseZip -Algorithm SHA256).Hash.ToLowerInvariant()

if ($actualDigest -cne $expectedDigest) {
    throw "Artifact digest mismatch: expected $expectedDigest, got $actualDigest"
}
```

Extract the verified ZIP into a new directory. From the same launcher commit, validate it again:

```powershell
$release = 'C:\path\to\extracted\website-release'

powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File .\ci\prepare-website-release.ps1 `
  -OutputDirectory $release `
  -ValidateOnly
```

The command must report the expected launcher version and succeed. Also confirm the extracted root has only `downloads` and `aleges-launcher-updates.json`, and that `downloads` has exactly 15 files.

Before Website integration, scan all six Windows EXEs: the three canonical installers and their three byte-identical immutable copies. Keep Defender and real-time protection enabled, add no exclusions, and stop the release on any detection, missing file, or zero-byte file. Record Authenticode status honestly; signing/reputation warnings and malware detections are different gates.

## Website Handoff

1. Copy all 15 files from the validated artifact's `downloads` directory into the Website repository's `public/downloads` directory.
2. Do **not** publish `aleges-launcher-updates.json` as a public download. Replace only the Website bootstrap `updates[]` array with that file's seven exact entries.
3. For a launcher-only release, preserve the Website bootstrap client `version`, all `artifacts[]`, every JVM argument array, and any other client/runtime fields.
4. Set the Website download page's displayed launcher version to the new launcher version. Its cards must reference only the eight canonical filenames above.
5. Validate every bootstrap URL, filename, size, and SHA-256 against the Website copy. Verify all binaries are real Git LFS content, not pointer text.
6. Follow the Website repository's `docs/LAUNCHER_CLIENT_RELEASE_RUNBOOK.md` for explicit staging, the second-machine Defender gate, commit/LFS push, guarded VM publisher, Cloudflare purge, and public byte verification.
7. Publish every referenced download first and activate `bootstrap.json` last. Never run Git checkout or LFS materialization in the live web root.

Do not copy the platform staging artifacts or `macos-app` into the Website. Do not restore the retired `/downloads/client.jar` alias. Do not substitute portable launcher `aleges-client.jar` for the immutable game-client JAR.

## Release Checklist

- [ ] Official upstream changes reviewed.
- [ ] A never-used launcher version selected for new published bytes.
- [ ] Aleges names, URLs, paths, icons, splash, and `#DC8A00` progress color preserved.
- [ ] JDK 17 tests passed.
- [ ] Exact source commit and successful `main` workflow run recorded.
- [ ] Only the final `website-release` artifact selected.
- [ ] Artifact digest recorded and extracted release validated.
- [ ] Exactly 8 canonical plus 7 immutable download files present.
- [ ] All six Windows EXEs passed current-signature Defender scanning.
- [ ] Website bootstrap received only the exact seven generated `updates[]` entries.
- [ ] Game-client artifacts and JVM configuration were preserved for a launcher-only release.
- [ ] Website release runbook completed through public verification.
