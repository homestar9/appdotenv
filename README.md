# AppDotEnv

![Appdotenv Logo](https://github.com/homestar9/appdotenv/blob/master/appdotenv-logo.avif?raw=true)

A per-application `.env` for ColdBox apps that share one CFML engine with other sites.

On a typical shared Windows/IIS server, every site runs in the same Adobe ColdFusion (or Lucee)
JVM. Loading `.env` the usual way puts each value into JVM system properties or the OS
environment. Then `DB_PASSWORD` from one site overwrites another's, and every site can read
every other site's secrets. ColdBox's `getSystemSetting()` only looks there, so it can't help.

AppDotEnv keeps each app's values in that app's own `application` scope:

- Your `Application.cfc` parses the app's `.env` into `application.dotenv` before ColdBox boots.
- `config/ColdBox.cfc` and `config/modules/*.cfc` call `application.dotenv.get( "KEY", default )`.
- Handlers, models and interceptors inject `DotEnv@appdotenv`.
- `?fwreinit=<password>` re-reads the file, so changing a value needs no restart.

## Where the file lives

| Environment | File | Why |
| --- | --- | --- |
| Development | `<webroot>/.env` | The same file CommandBox loads for the dev server. |
| Production | `<webroot>/../.env` | One level above the webroot, so the web server can never serve it. |

The webroot file wins when both exist. When neither exists the app still boots on defaults, and
the startup log names the production path it expected:

```text
C:\websites\example.com\
    .env        <- production secrets
    wwwroot\    <- IIS physical path and the app root
```

## Install

```bash
box install appdotenv
```

ColdBox loads modules after it reads your config, so the module can't load the file itself. Two
small steps in `Application.cfc` do that.

### 1. Application.cfc

```cfml
public boolean function onApplicationStart(){
    // Before the ColdBox bootstrap: config CFCs read application.dotenv.
    application.dotenv = new modules.appdotenv.models.DotEnv( appRoot = COLDBOX_APP_ROOT_PATH ).load();

    application.cbBootstrap = new coldbox.system.Bootstrap( COLDBOX_CONFIG_FILE, COLDBOX_APP_ROOT_PATH, COLDBOX_APP_KEY, COLDBOX_APP_MAPPING );
    application.cbBootstrap.loadColdbox();
    return true;
}

public boolean function onRequestStart( string targetPage ){
    // Re-read .env on ?fwreinit (URL or POST). The first branch covers an app that
    // started before these lines were deployed.
    if ( !application.keyExists( "dotenv" ) ) {
        application.dotenv = new modules.appdotenv.models.DotEnv( appRoot = COLDBOX_APP_ROOT_PATH ).load();
    } else {
        application.dotenv.syncWithRequest();
    }

    application.cbBootstrap.onRequestStart( arguments.targetPage );
    return true;
}
```

The dotted path assumes the default install location, `modules/appdotenv/`. If the module loads
without `application.dotenv`, it throws `AppDotEnv.NotBooted` with the line to add.

**TestBox:** integration tests boot ColdBox through `BaseTestCase`, not your root
`Application.cfc`. Add the same line to `tests/Application.cfc` (`onApplicationStart`, plus the
`keyExists` guard in `onRequestStart`), using your root mapping:
`new root.modules.appdotenv.models.DotEnv( appRoot = rootPath ).load()`.

### 2. Read values

```cfml
// config/ColdBox.cfc, config/modules/*.cfc
reinitPassword : application.dotenv.get( "COLDBOX_REINIT_PASSWORD", "" ),
defaultSecret  : application.dotenv.get( "CMS_SECRET" ), // no default: a missing value stops the boot

// handlers, models, interceptors
property name="dotenv" inject="DotEnv@appdotenv";
var to = dotenv.get( "CONTACT_TO", "me@example.com" );
```

## API

| Method | Does |
| --- | --- |
| `init( path = "", appRoot = "" )` | `path` names the file exactly; `appRoot` resolves it as described above. |
| `load()` / `reload()` | Read the file. A missing file isn't an error. |
| `syncWithRequest( [params] )` | `reload()` when the request has `fwreinit` (URL or form). |
| `get( key, [default] )` | File, then Java system property, then OS env, then `default`. Without a default, throws `SystemSettingNotFound`. A blank value counts as unset. |
| `has( key )` | Whether `get()` would succeed without a default. |
| `keys()` | Sorted key names from the file. Safe to log. |
| `describe()` | One log-safe line: key count and path. The module logs it on load. |
| `getPath()`, `isLoaded()`, `getLoadedAt()` | What was read, and when. |

The file wins over JVM and OS values so another site's JVM-global setting can never leak in.
Values live in the component's `variables` scope, so dumping the application scope doesn't
print them.

### File format

`KEY=value` and `export KEY=value`. `#` starts a comment on its own line, or after an unquoted
value when whitespace comes before it. One pair of outer quotes is stripped. Inside double
quotes `\n`, `\r`, `\t`, `\"` and `\\` are unescaped; single quotes are literal. There is no
`${VAR}` interpolation. CRLF line endings and a UTF-8 BOM are fine.

## Adopting it in an app: checklist

1. `box install appdotenv`.
2. Add the `Application.cfc` lines above (and to `tests/Application.cfc`).
3. Replace `getSystemSetting( "X", d )` in `config/` with `application.dotenv.get( "X", d )`.
   Inject `DotEnv@appdotenv` wherever code read `getSystemSetting()` at runtime.
4. Keep secrets out of git and off the server's webroot:
   - `.gitignore`: `.env`, `.env.*`, `!.env.example`
   - Commit `.env.example` with every key and only harmless values.
   - Deploy excludes (for example DeployBot's `.deployignore`): `/.*`
   - IIS `web.config`: add `.env` to `<hiddenSegments>` under `requestFiltering`.
5. Keep the production copy on your dev machine as `.env.production` at the repo root. The
   `.env.*` pattern already ignores it. This module never reads that name; it's only the copy
   you edit and deploy from.
6. On the server, put the file at `<webroot>\..\.env`. Remove inherited permissions and grant
   Read only to the CFML engine's service account and Administrators.
7. After changing the server file, run `?fwreinit=<your reinit password>`.

### What the ACL does and doesn't protect

The file is outside the webroot and IIS has no permission to read it, so it can't be served.
But every site in a shared engine runs as the same service account, so CFML code in *another*
site on that server could still `fileRead()` it. Use a separate engine instance or a sandbox
when that matters.

## Engines

Adobe ColdFusion 2023 and 2025, BoxLang 1 (CFML compatibility), Lucee 6. Tested on ColdBox 8.

## License

Apache 2.0.
