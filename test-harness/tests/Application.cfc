/**
 * Maps the test and module paths, loads a known .env fixture, and starts a ColdBox virtual
 * application.
 */
component {

	// Name the module used in CFML mappings.
	request.MODULE_NAME = "appdotenv";
	// Name the module's repository directory.
	request.MODULE_PATH = "appdotenv";

	this.name               = "#request.MODULE_NAME#-testing-suite";
	this.sessionManagement  = true;
	this.sessionTimeout     = createTimespan( 0, 0, 15, 0 );
	this.applicationTimeout = createTimespan( 0, 0, 15, 0 );
	this.setClientCookies   = true;

	// Map the test directory.
	this.mappings[ "/tests" ] = getDirectoryFromPath( getCurrentTemplatePath() );

	// Map the harness application root.
	rootPath                 = reReplaceNoCase( this.mappings[ "/tests" ], "tests(\\|/)", "" );
	this.mappings[ "/root" ] = rootPath;

	// Find and map the module repository.
	moduleRootPath = reReplaceNoCase(
		rootPath,
		"#request.MODULE_PATH#(\\|/)test-harness(\\|/)",
		""
	);
	this.mappings[ "/moduleroot" ]            = moduleRootPath;
	this.mappings[ "/#request.MODULE_NAME#" ] = moduleRootPath & "#request.MODULE_PATH#";

	/**
	 * Loads the basic.env fixture into application.dotenv, as a host Application.cfc would
	 * before ColdBox boots, then starts a ColdBox virtual application for runner and spec
	 * requests.
	 *
	 * @targetPage The requested test template.
	 */
	public boolean function onRequestStart( required targetPage ){
		setting requestTimeout="9999";

		// Created once, like a host app. Replacing it per request would leave a virtual app that
		// outlived a crashed run holding the previous instance.
		if ( !application.keyExists( "dotenv" ) ) {
			application.dotenv = new appdotenv.models.DotEnv(
				path = expandPath( "/tests/resources/dotenv/basic.env" )
			).load();
		}

		request.coldBoxVirtualApp = new coldbox.system.testing.VirtualApp( appMapping = "/root" );

		if ( getBaseTemplatePath().replace( expandPath( "/tests" ), "" ).reFindNoCase( "(runner|specs)" ) ) {
			request.coldBoxVirtualApp.startup();
		}

		if ( url.keyExists( "fwreinit" ) ) {
			if ( server.keyExists( "lucee" ) ) {
				pagePoolClear();
			}
			request.coldBoxVirtualApp.restart();
		}

		return true;
	}

	/**
	 * Shuts down the ColdBox virtual application after a test request.
	 *
	 * @targetPage The requested test template.
	 */
	public void function onRequestEnd( required targetPage ){
		request.coldBoxVirtualApp.shutdown();
	}

}
