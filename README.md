Aleges launcher, kept current with the RuneLite launcher and built by CI.

Can be used for any client revision (317, OSRS, 500+, etc.), as well as any Java application.

## Aleges configuration

- The launcher name, icons, install paths, and generated artifacts are configured for `Aleges`.
- The launcher fetches its client manifest from
  `https://aleges.com/integration/bootstrap.json`.
- Update that hosted manifest only when publishing matching Aleges client artifacts. The included
  `bootstrap.json.example` is a generic historical example and is not the live Aleges manifest.
- Follow the [Aleges launcher release guide](docs/ALEGES_LAUNCHER_RELEASE.md) for versioning,
  branding checks, CI validation, the exact `website-release` inventory, and the Website handoff.
- Integrate only the final `website-release` artifact. The platform artifacts and `macos-app`
  archive are CI intermediates and are not the deployable Website bundle.

## Support

If there's a problem with the launcher,
please open an issue in this repository.
