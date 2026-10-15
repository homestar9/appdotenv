/**
 * Starts the ColdBox test harness and maps the module from the working tree.
 *
 * The dotenv lines below are the ones the README tells host apps to add, so the harness boots
 * the same way a real site does. A host app writes `modules.appdotenv.models.DotEnv`; here the
 * module is reached through the /appdotenv mapping instead.
 */
component {

	// Store the module name for mappings and ColdBox configuration.
	request.MODULE_NAME = "appdotenv";

	this.name              = hash( getCurrentTemplatePath() );
	this.sessionManagement = true;
	this.sessionTimeout    = createTimespan( 0, 0, 15, 0 );
	this.setClientCookies  = true;

	// Point ColdBox at the test harness.
	COLDBOX_APP_ROOT_PATH = getDirectoryFromPath( getCurrentTemplatePath() );
	// Use the web root as the application mapping.
	COLDBOX_APP_MAPPING   = "";
	// Use the default ColdBox configuration file.
	COLDBOX_CONFIG_FILE   = "";
	// Use ColdBox's default application key.
	COLDBOX_APP_KEY       = "";

	// Map the test harness as /root.
	this.mappings[ "/root" ] = COLDBOX_APP_ROOT_PATH;

	// Find the repository and module paths from the harness path.
	moduleRootPath = reReplaceNoCase(
		this.mappings[ "/root" ],
		"#request.MODULE_NAME#(\\|/)test-harness(\\|/)",
		""
	);
	modulePath = reReplaceNoCase( this.mappings[ "/root" ], "test-harness(\\|/)", "" );

	// Map the repository and module working tree.
	this.mappings[ "/moduleroot" ]            = moduleRootPath;
	this.mappings[ "/#request.MODULE_NAME#" ] = modulePath;

	/**
	 * Loads this application's .env, then starts ColdBox, whose config CFCs read it.
	 */
	public boolean function onApplicationStart(){
		application.dotenv = new appdotenv.models.DotEnv( appRoot = COLDBOX_APP_ROOT_PATH ).load();

		application.cbBootstrap = new coldbox.system.Bootstrap(
			COLDBOX_CONFIG_FILE,
			COLDBOX_APP_ROOT_PATH,
			COLDBOX_APP_KEY,
			COLDBOX_APP_MAPPING
		);
		application.cbBootstrap.loadColdbox();
		return true;
	}

	/**
	 * Re-reads .env on a reinit, then passes the request to ColdBox.
	 *
	 * @targetPage The requested CFML template.
	 */
	public boolean function onRequestStart( string targetPage ){
		if ( !application.keyExists( "dotenv" ) ) {
			application.dotenv = new appdotenv.models.DotEnv( appRoot = COLDBOX_APP_ROOT_PATH ).load();
		} else {
			application.dotenv.syncWithRequest();
		}

		if ( url.keyExists( "fwreinit" ) && server.keyExists( "lucee" ) ) {
			pagePoolClear();
		}

		application.cbBootstrap.onRequestStart( arguments.targetPage );

		return true;
	}

	/**
	 * Passes new sessions to ColdBox.
	 */
	public void function onSessionStart(){
		application.cbBootStrap.onSessionStart();
	}

	/**
	 * Passes completed sessions to ColdBox.
	 *
	 * @sessionScope The session that ended.
	 * @appScope     The current application scope.
	 */
	public void function onSessionEnd( struct sessionScope, struct appScope ){
		arguments.appScope.cbBootStrap.onSessionEnd( argumentCollection = arguments );
	}

	/**
	 * Lets ColdBox handle a missing template.
	 *
	 * @template The requested template path.
	 */
	public boolean function onMissingTemplate( template ){
		return application.cbBootstrap.onMissingTemplate( argumentCollection = arguments );
	}

}
