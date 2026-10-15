/**
 * Integration tests: the module registers the instance Application.cfc created, config CFCs can
 * read it, and the module refuses to load without it.
 *
 * tests/Application.cfc loads tests/resources/dotenv/basic.env into application.dotenv before
 * the virtual app starts.
 */
component extends="coldbox.system.testing.BaseTestCase" appMapping="/root" {

	this.loadColdBox   = true;
	this.unloadColdBox = false;

	function run(){

		describe( "AppDotEnv module", function(){

			it( "registers DotEnv@appdotenv as the same instance as application.dotenv", function(){
				var system = createObject( "java", "java.lang.System" );
				expect( system.identityHashCode( getInstance( "DotEnv@appdotenv" ) ) ).toBe(
					system.identityHashCode( application.dotenv )
				);
			} );

			it( "makes .env values available to config/ColdBox.cfc", function(){
				expect( getController().getSetting( "dotenvPlain" ) ).toBe( "plain value" );
			} );

			it( "injects into handlers", function(){
				var event = execute( event = "main.index", renderResults = true );
				var body  = deserializeJSON( event.getRenderedContent() );
				expect( body.summary ).toInclude( "12 keys" );
				expect( body.keys.findNoCase( "PLAIN" ) ).toBeGT( 0 );
				expect( event.getRenderedContent() ).notToInclude( "plain value" );
			} );

			it( "throws AppDotEnv.NotBooted when Application.cfc did not create application.dotenv", function(){
				var saved = application.dotenv;
				try {
					structDelete( application, "dotenv" );
					expect( function(){
						new appdotenv.ModuleConfig().configure();
					} ).toThrow( "AppDotEnv.NotBooted" );
				} finally {
					application.dotenv = saved;
				}
			} );

		} );

	}

}
