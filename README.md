Latest version RuneLite launcher, with CI.

Can be used for any client revision (317, OSRS, 500+, etc.), as well as any Java application.

## Aleges configuration

- The launcher name, icons, install paths, and generated artifacts are configured for `Aleges`.
- The launcher fetches its client manifest from
  `https://aleges.com/integration/bootstrap.json`.
- Update that hosted manifest only when publishing matching Aleges client artifacts. The included
  `bootstrap.json.example` is a generic historical example and is not the live Aleges manifest.
- Push your changes to GitHub, then run the workflow from the Actions tab. Download the
  `website-windows`, `website-linux`, and `website-macos` artifacts and copy their contents directly into the
  Aleges website's `public/downloads` directory; their names already match the website links.

## Support

If there's a problem with the launcher,
please open an issue in this repository.
