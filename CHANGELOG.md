# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- First release, extracted from angrysam-web. `DotEnv` parses an app's own `.env` into
  `application.dotenv` before ColdBox boots, so config CFCs can read it without the JVM or the
  OS environment. It reads the webroot `.env` in development and the one above the webroot in
  production.
- `syncWithRequest()` reloads the file on a ColdBox reinit, including a reinit sent as a POST
  field.
- The module registers that instance as `DotEnv@appdotenv` and logs where it was loaded from,
  key names and counts only.
