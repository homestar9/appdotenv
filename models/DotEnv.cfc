/**
 * Per-application dotenv loader.
 *
 * Built for servers that run many sites in one CFML engine (one JVM). There a `.env` can't go
 * into JVM system properties or the OS environment: keys such as DB_PASSWORD would collide
 * between sites, and every site could read every other site's secrets. Instead the app's
 * Application.cfc parses its own `.env` into an instance of this component and stores it in
 * `application.dotenv` before ColdBox boots, so config/ColdBox.cfc and config/modules/*.cfc can
 * read it.
 *
 * Values live in the `variables` scope on purpose. A dump of the application scope shows this
 * component's methods, not the secrets.
 *
 * File location, when built with `appRoot`: `<appRoot>/.env` if it exists (development, the
 * same file CommandBox loads), otherwise `<appRoot>/../.env` (production, one level above the
 * webroot so the web server can never serve it).
 *
 * Lookup order in get(): the `.env` file, then a Java system property, then an OS environment
 * variable, then the caller's default. The file wins so that a value from another site's
 * JVM-global configuration can never leak in. In development CommandBox loads the same file
 * into the JVM, so both sources agree.
 *
 * Parser rules: `KEY=value` and `export KEY=value`; `#` comments on their own line or after an
 * unquoted value when preceded by whitespace; one pair of matching outer quotes is stripped;
 * inside double quotes `\n`, `\r`, `\t`, `\"` and `\\` are unescaped; single quotes are literal;
 * there is no `${VAR}` interpolation.
 */
component {

	variables.path     = "";
	variables.values   = {};
	variables.loaded   = false;
	variables.loadedAt = "";

	/**
	 * Records the file to load. No I/O happens here; call load().
	 *
	 * @path    Absolute path of the dotenv file. It may not exist. Wins over appRoot.
	 * @appRoot The application root (the webroot). The file is then resolved with resolvePath().
	 */
	DotEnv function init( string path = "", string appRoot = "" ){
		if ( len( arguments.path ) || !len( arguments.appRoot ) ) {
			variables.path = arguments.path;
		} else {
			variables.path = resolvePath( arguments.appRoot );
		}
		return this;
	}

	/**
	 * Picks the `.env` for an application root: `<appRoot>/.env` when it exists, else
	 * `<appRoot>/../.env`. When neither exists the parent path is returned, so the startup log
	 * names where production expects the file.
	 *
	 * @appRoot The application root (the webroot), with or without a trailing slash.
	 */
	string function resolvePath( required string appRoot ){
		var root       = reReplace( arguments.appRoot, "[\\/]+$", "" );
		var candidates = [ canonical( root & "/.env" ), canonical( root & "/../.env" ) ];
		for ( var candidate in candidates ) {
			if ( fileExists( candidate ) ) {
				return candidate;
			}
		}
		return candidates[ 2 ];
	}

	/**
	 * Reads and parses the file. A missing file is not an error: the application then runs on
	 * defaults and JVM values, and isLoaded() reports false so the caller can log it.
	 */
	DotEnv function load(){
		var parsed = {};

		if ( len( variables.path ) && fileExists( variables.path ) ) {
			parsed           = parse( fileRead( variables.path, "utf-8" ) );
			variables.loaded = true;
		} else {
			variables.loaded = false;
		}

		variables.values   = parsed;
		variables.loadedAt = now();
		return this;
	}

	/**
	 * Re-reads the file in place so objects holding a reference to this instance see the new
	 * values.
	 */
	DotEnv function reload(){
		return load();
	}

	/**
	 * Reloads the file when the request asks for a ColdBox reinit. A reinit re-runs every config
	 * CFC but not onApplicationStart, so Application.cfc calls this from onRequestStart.
	 *
	 * `fwreinit` counts in the URL or a form field, because tools such as deploybot can POST it.
	 * The reinit password still gates the reinit itself; re-reading a small file on a refused
	 * attempt costs nothing.
	 *
	 * @params The request parameters to check. Defaults to the form and url scopes.
	 */
	DotEnv function syncWithRequest( struct params ){
		var source = isNull( arguments.params ) ? requestParams() : arguments.params;
		if ( source.keyExists( "fwreinit" ) ) {
			reload();
		}
		return this;
	}

	/**
	 * Resolves a key: file, then Java system property, then OS environment variable, then the
	 * default. Throws `SystemSettingNotFound` (the same type ColdBox uses) when nothing matches
	 * and no default was given.
	 *
	 * A key present in the file with a blank value (`CMS_SECRET=`, the state a fresh copy of
	 * .env.example is in) counts as unset, so a required secret still stops the boot and an
	 * optional one still gets its default.
	 *
	 * @key          The setting name, case-insensitive for file values.
	 * @defaultValue Returned when the key is found nowhere.
	 */
	any function get( required string key, any defaultValue ){
		if ( hasFileValue( arguments.key ) ) {
			return variables.values[ arguments.key ];
		}

		var value = getJavaSystem().getProperty( arguments.key );
		if ( !isNull( local.value ) ) {
			return value;
		}

		value = getJavaSystem().getenv( arguments.key );
		if ( !isNull( local.value ) ) {
			return value;
		}

		if ( !isNull( arguments.defaultValue ) ) {
			return arguments.defaultValue;
		}

		throw(
			type    = "SystemSettingNotFound",
			message = "Could not find [#arguments.key#] in #variables.path#, the Java system properties, or the environment."
		);
	}

	/**
	 * True when get() would succeed without a default.
	 */
	boolean function has( required string key ){
		if ( hasFileValue( arguments.key ) ) {
			return true;
		}
		var property = getJavaSystem().getProperty( arguments.key );
		if ( !isNull( local.property ) ) {
			return true;
		}
		var envValue = getJavaSystem().getenv( arguments.key );
		return !isNull( local.envValue );
	}

	/**
	 * Sorted names of the keys read from the file, blank ones included. Safe to log; values are
	 * not included.
	 */
	array function keys(){
		var names = variables.values.keyArray();
		names.sort( "textnocase" );
		return names;
	}

	/**
	 * The path this instance reads from.
	 */
	string function getPath(){
		return variables.path;
	}

	/**
	 * Whether the last load() found the file.
	 */
	boolean function isLoaded(){
		return variables.loaded;
	}

	/**
	 * When load() last ran, or an empty string before the first load.
	 */
	any function getLoadedAt(){
		return variables.loadedAt;
	}

	/**
	 * One log-safe line describing the last load: key count and path, never values.
	 */
	string function describe(){
		return variables.loaded
		 ? "DotEnv loaded #keys().len()# keys from #variables.path#"
		 : "DotEnv found no file at #variables.path#; running on defaults and JVM values";
	}

	/**
	 * Parses dotenv text into a struct. Public so the parser can be tested without a file.
	 *
	 * @content The raw file contents.
	 */
	struct function parse( required string content ){
		var result = {};
		var text   = arguments.content;

		// Strip a UTF-8 byte order mark, which Windows editors like to add.
		if ( len( text ) && asc( left( text, 1 ) ) == 65279 ) {
			text = mid( text, 2, len( text ) - 1 );
		}

		for ( var rawLine in listToArray( text, chr( 10 ) ) ) {
			var line = trim( rawLine );

			if ( !len( line ) || left( line, 1 ) == "##" ) {
				continue;
			}

			line = reReplaceNoCase( line, "^export\s+", "" );

			// Needs an "=" with at least one character before it (ACF rejects left( x, 0 )).
			var separator = find( "=", line );
			if ( separator < 2 ) {
				continue;
			}

			var key = trim( left( line, separator - 1 ) );
			if ( !reFind( "^[A-Za-z_][A-Za-z0-9_.]*$", key ) ) {
				continue;
			}

			var rawValue = separator < len( line ) ? trim( mid( line, separator + 1, len( line ) - separator ) ) : "";

			result[ key ] = unquote( rawValue );
		}

		return result;
	}

	/**
	 * True when the file defines the key with a non-blank value.
	 */
	private boolean function hasFileValue( required string key ){
		return variables.values.keyExists( arguments.key ) && len( variables.values[ arguments.key ] );
	}

	/**
	 * Normalizes a path (resolves `..`, uses the OS separator) whether or not it exists.
	 * java.io.File does this the same way on every engine; BoxLang's getCanonicalPath()
	 * leaves `..` in place for a missing file.
	 */
	private string function canonical( required string path ){
		return createObject( "java", "java.io.File" ).init( arguments.path ).getCanonicalPath();
	}

	/**
	 * The current request's form and url parameters, url winning, as ColdBox merges them.
	 */
	private struct function requestParams(){
		var merged = {};
		merged.append( form );
		merged.append( url );
		return merged;
	}

	/**
	 * Applies the quoting rules to one raw value.
	 */
	private string function unquote( required string value ){
		var raw = arguments.value;

		if ( len( raw ) >= 2 && left( raw, 1 ) == '"' ) {
			var doubleMatch = reFind( '^"((?:[^"\\]|\\.)*)"', raw, 1, true );
			if ( doubleMatch.pos[ 1 ] ) {
				return unescape( doubleMatch.len[ 2 ] ? mid( raw, doubleMatch.pos[ 2 ], doubleMatch.len[ 2 ] ) : "" );
			}
		}

		if ( len( raw ) >= 2 && left( raw, 1 ) == "'" ) {
			var singleMatch = reFind( "^'([^']*)'", raw, 1, true );
			if ( singleMatch.pos[ 1 ] ) {
				return singleMatch.len[ 2 ] ? mid( raw, singleMatch.pos[ 2 ], singleMatch.len[ 2 ] ) : "";
			}
		}

		// Unquoted: a hash preceded by whitespace starts a comment.
		var comment = reFind( "\s##", raw );
		if ( comment ) {
			raw = comment > 1 ? trim( left( raw, comment - 1 ) ) : "";
		}

		return raw;
	}

	/**
	 * Resolves backslash escapes inside a double-quoted value.
	 */
	private string function unescape( required string value ){
		var out    = "";
		var length = len( arguments.value );
		var i      = 1;

		while ( i <= length ) {
			var char = mid( arguments.value, i, 1 );

			if ( char == "\" && i < length ) {
				var next = mid( arguments.value, i + 1, 1 );
				switch ( next ) {
					case "n":
						out &= chr( 10 );
						break;
					case "r":
						out &= chr( 13 );
						break;
					case "t":
						out &= chr( 9 );
						break;
					default:
						// Covers \" and \\ and leaves unknown escapes as the literal character.
						out &= next;
				}
				i += 2;
				continue;
			}

			out &= char;
			i++;
		}

		return out;
	}

	/**
	 * Lazily created java.lang.System proxy for the JVM and OS fallbacks.
	 */
	private any function getJavaSystem(){
		if ( isNull( variables.javaSystem ) ) {
			variables.javaSystem = createObject( "java", "java.lang.System" );
		}
		return variables.javaSystem;
	}

}
