# appdotenv - AI Agent Instructions

A ColdBox module (ForgeBox slug `appdotenv`) that gives each ColdBox app its own `.env` on a server
where many sites share one CFML engine. User-facing docs are in `README.md`; this file is for
working on the module itself.

## Layout

- `models/DotEnv.cfc` - the whole feature: file resolution, parser, lookup order, reload.
- `ModuleConfig.cfc` - maps `DotEnv@appdotenv` to `application.dotenv` and logs the load. It never
  creates the instance.
- `test-harness/` - a ColdBox app that boots exactly the way the README tells host apps to.
  Specs are in `test-harness/tests/specs/{unit,integration}`; fixtures in
  `test-harness/tests/resources/dotenv/` (CRLF line endings and a BOM on purpose; copy them
  byte for byte).

## Rules

- **The host app's Application.cfc owns the instance.** ColdBox runs `config/ColdBox.cfc` and
  `config/modules/*.cfc` before any module loads, so the module can't be the thing that loads
  the file. Don't add a fallback that builds one in `configure()`; that would hide a missing
  Application.cfc step until a config value silently took its default.
- **Never log or render values.** `keys()` and `describe()` are the only log-safe outputs.
- **No JVM or OS writes.** The point of the module is that nothing reaches `System.setProperty`
  or the environment, where every site on the server could read it.
- **Lookup order is file, JVM property, OS env, default.** The file wins so another site's
  JVM-global value can't leak in.
- Engines: Adobe 2023/2025, BoxLang (CFML compat), Lucee 6. Keep to functions all four have.
- Use member functions and `keyExists()`; in specs, use `for` loops, not closures, for clearer
  stack traces. Every method gets a short docblock.

## Testing

```bash
box run-script install:dependencies
box run-script start:2023
box testbox run runner="http://127.0.0.1:60330/tests/runner.cfm"
```

Releases use commandbox-release (`release.json`): `box release test` runs every engine.
