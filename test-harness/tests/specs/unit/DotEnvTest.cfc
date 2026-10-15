/**
 * Unit tests for models/DotEnv.cfc: the parser, the lookup order, file resolution from an app
 * root, and reload.
 *
 * Fixture files live in tests/resources/dotenv/. The precedence tests set a Java system
 * property on the test JVM and clear it again in afterEach. The app-root tests build throwaway
 * folders under the engine's temp directory.
 */
component extends="testbox.system.BaseSpec" {

	function beforeAll(){
		variables.fixtures = expandPath( "/tests/resources/dotenv/" );
		variables.system   = createObject( "java", "java.lang.System" );
	}

	/**
	 * Creates a loader for one fixture file.
	 */
	private any function loader( required string fileName ){
		return new appdotenv.models.DotEnv( variables.fixtures & arguments.fileName ).load();
	}

	/**
	 * The normalized form of a path, computed the same way DotEnv does on every engine.
	 */
	private string function canonical( required string path ){
		return createObject( "java", "java.io.File" ).init( arguments.path ).getCanonicalPath();
	}

	/**
	 * Creates `<temp>/<site>/wwwroot/` and returns the site folder, with a trailing slash.
	 */
	private string function newSite(){
		var site = getTempDirectory() & "appdotenv-#createUUID()#/";
		directoryCreate( site & "wwwroot" );
		return site;
	}

	function run(){

		describe( "DotEnv parsing", function(){

			beforeEach( function(){
				variables.env = loader( "basic.env" );
			} );

			it( "reports the file as loaded and exposes only valid keys", function(){
				expect( variables.env.isLoaded() ).toBeTrue();
				for ( var expected in [
					"DOUBLE",
					"EMPTY",
					"EQUALS",
					"ESCAPED",
					"EXPORTED",
					"HASH_INSIDE",
					"lowercase",
					"PLAIN",
					"SINGLE",
					"SPACED",
					"TRAILING",
					"URL"
				] ) {
					expect( variables.env.keys().findNoCase( expected ) ).toBeGT( 0, "missing #expected#" );
				}
				expect( variables.env.keys().len() ).toBe( 12 );
			} );

			it( "reads plain, exported and padded values", function(){
				expect( variables.env.get( "PLAIN" ) ).toBe( "plain value" );
				expect( variables.env.get( "EXPORTED" ) ).toBe( "yes" );
				expect( variables.env.get( "SPACED" ) ).toBe( "padded" );
				expect( variables.env.get( "EQUALS" ) ).toBe( "a=b=c" );
				expect( variables.env.get( "URL" ) ).toBe( "https://example.com/path?a=1&b=2" );
			} );

			it( "treats a blank value as unset", function(){
				expect( variables.env.has( "EMPTY" ) ).toBeFalse();
				expect( variables.env.get( "EMPTY", "default" ) ).toBe( "default" );
				expect( function(){
					variables.env.get( "EMPTY" );
				} ).toThrow( "SystemSettingNotFound" );
			} );

			it( "strips double quotes and resolves escapes inside them", function(){
				expect( variables.env.get( "DOUBLE" ) ).toBe( "double quoted ## not a comment" );
				expect( variables.env.get( "ESCAPED" ) ).toBe(
					"line1" & chr( 10 ) & "line2" & chr( 9 ) & """quoted"" back\slash"
				);
			} );

			it( "keeps single-quoted values literal", function(){
				expect( variables.env.get( "SINGLE" ) ).toBe( "single $literal \n kept" );
			} );

			it( "drops a trailing comment only when whitespace precedes the hash", function(){
				expect( variables.env.get( "TRAILING" ) ).toBe( "value" );
				expect( variables.env.get( "HASH_INSIDE" ) ).toBe( "abc##def" );
			} );

			it( "looks keys up case-insensitively", function(){
				expect( variables.env.get( "LOWERCASE" ) ).toBe( "lower" );
				expect( variables.env.has( "plain" ) ).toBeTrue();
			} );

			it( "handles CRLF line endings", function(){
				var crlf = loader( "crlf.env" );
				expect( crlf.get( "FIRST" ) ).toBe( "one" );
				expect( crlf.get( "SECOND" ) ).toBe( "two" );
				expect( crlf.get( "THIRD" ) ).toBe( "three" );
				expect( crlf.keys().len() ).toBe( 3 );
			} );

			it( "strips a UTF-8 byte order mark", function(){
				var bom = loader( "bom.env" );
				expect( bom.get( "BOMMED" ) ).toBe( "yes" );
				expect( bom.get( "AFTER" ) ).toBe( "ok" );
			} );

			it( "parses raw text without a file", function(){
				var parsed = new appdotenv.models.DotEnv( "" ).parse( "A=1" & chr( 10 ) & "B='two'" );
				expect( parsed ).toBe( { "A" : "1", "B" : "two" } );
			} );

		} );

		describe( "DotEnv lookup order", function(){

			afterEach( function(){
				variables.system.clearProperty( "DOTENV_TEST_PRECEDENCE" );
				variables.system.clearProperty( "DOTENV_TEST_JVM_ONLY" );
			} );

			it( "prefers the file over a Java system property", function(){
				variables.system.setProperty( "DOTENV_TEST_PRECEDENCE", "jvm" );
				expect( loader( "precedence.env" ).get( "DOTENV_TEST_PRECEDENCE" ) ).toBe( "file" );
			} );

			it( "falls back to a Java system property when the file lacks the key", function(){
				variables.system.setProperty( "DOTENV_TEST_JVM_ONLY", "jvm" );
				var env = loader( "precedence.env" );
				expect( env.get( "DOTENV_TEST_JVM_ONLY" ) ).toBe( "jvm" );
				expect( env.has( "DOTENV_TEST_JVM_ONLY" ) ).toBeTrue();
				expect( env.keys() ).toBe( [ "DOTENV_TEST_PRECEDENCE" ] );
			} );

			it( "returns the default when nothing matches", function(){
				expect( loader( "precedence.env" ).get( "DOTENV_TEST_MISSING", "fallback" ) ).toBe( "fallback" );
			} );

			it( "throws SystemSettingNotFound without a default", function(){
				expect( function(){
					loader( "precedence.env" ).get( "DOTENV_TEST_MISSING" );
				} ).toThrow( "SystemSettingNotFound" );
			} );

		} );

		describe( "DotEnv file resolution from an app root", function(){

			beforeEach( function(){
				variables.site = newSite();
			} );

			afterEach( function(){
				if ( directoryExists( variables.site ) ) {
					directoryDelete( variables.site, true );
				}
			} );

			it( "prefers a .env inside the webroot (development)", function(){
				fileWrite( variables.site & "wwwroot/.env", "WHERE=webroot" );
				fileWrite( variables.site & ".env", "WHERE=parent" );
				var env = new appdotenv.models.DotEnv( appRoot = variables.site & "wwwroot/" ).load();
				expect( env.get( "WHERE" ) ).toBe( "webroot" );
			} );

			it( "falls back to the .env one level above the webroot (production)", function(){
				fileWrite( variables.site & ".env", "WHERE=parent" );
				var env = new appdotenv.models.DotEnv( appRoot = variables.site & "wwwroot" ).load();
				expect( env.isLoaded() ).toBeTrue();
				expect( env.get( "WHERE" ) ).toBe( "parent" );
				expect( env.getPath() ).toBe( canonical( variables.site & ".env" ) );
			} );

			it( "names the production path when neither file exists", function(){
				var env = new appdotenv.models.DotEnv( appRoot = variables.site & "wwwroot/" ).load();
				expect( env.isLoaded() ).toBeFalse();
				expect( env.getPath() ).toBe( canonical( variables.site & ".env" ) );
				expect( env.describe() ).toInclude( "no file at" );
			} );

			it( "lets an explicit path win over appRoot", function(){
				fileWrite( variables.site & "wwwroot/.env", "WHERE=webroot" );
				var env = new appdotenv.models.DotEnv(
					path    = variables.fixtures & "precedence.env",
					appRoot = variables.site & "wwwroot/"
				).load();
				expect( env.keys() ).toBe( [ "DOTENV_TEST_PRECEDENCE" ] );
			} );

		} );

		describe( "DotEnv files that are missing or change", function(){

			it( "boots on an absent file", function(){
				var env = loader( "does-not-exist.env" );
				expect( env.isLoaded() ).toBeFalse();
				expect( env.keys() ).toBeEmpty();
				expect( env.get( "ANYTHING", "default" ) ).toBe( "default" );
				expect( env.getPath() ).toInclude( "does-not-exist.env" );
			} );

			it( "describes a load with the key count and path but no values", function(){
				var summary = loader( "basic.env" ).describe();
				expect( summary ).toInclude( "12 keys" );
				expect( summary ).toInclude( "basic.env" );
				expect( summary ).notToInclude( "plain value" );
			} );

			it( "picks up edits on reload", function(){
				var path = getTempDirectory() & "appdotenv-reload-#createUUID()#.env";
				try {
					fileWrite( path, "VALUE=before" );
					var env = new appdotenv.models.DotEnv( path ).load();
					expect( env.get( "VALUE" ) ).toBe( "before" );

					fileWrite( path, "VALUE=after" );
					env.reload();
					expect( env.get( "VALUE" ) ).toBe( "after" );
				} finally {
					if ( fileExists( path ) ) {
						fileDelete( path );
					}
				}
			} );

			it( "reloads on syncWithRequest only when fwreinit is present", function(){
				var path = getTempDirectory() & "appdotenv-sync-#createUUID()#.env";
				try {
					fileWrite( path, "VALUE=before" );
					var env = new appdotenv.models.DotEnv( path ).load();

					fileWrite( path, "VALUE=after" );
					env.syncWithRequest( { "event" : "main.index" } );
					expect( env.get( "VALUE" ) ).toBe( "before" );

					env.syncWithRequest( { "fwreinit" : "secret" } );
					expect( env.get( "VALUE" ) ).toBe( "after" );
				} finally {
					if ( fileExists( path ) ) {
						fileDelete( path );
					}
				}
			} );

		} );

	}

}
