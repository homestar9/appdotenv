/**
 * Configures the test harness. It reads one value from application.dotenv at config time, the
 * way a host app's config CFCs do, so the integration specs can prove the value is there
 * before any module loads.
 */
component {

	/**
	 * Configures the test harness.
	 */
	function configure(){
		variables.coldbox = {
			appName                 : "appdotenv Harness",
			reinitPassword          : "",
			handlersIndexAutoReload : true,
			modulesExternalLocation : [],
			defaultEvent            : "Main.index",
			customErrorTemplate     : "/coldbox/system/exceptions/Whoops.cfm",
			handlerCaching          : false,
			eventCaching            : false
		};

		// Read at config time. The integration specs load tests/resources/dotenv/basic.env.
		variables.settings = { dotenvPlain : application.dotenv.get( "PLAIN", "" ) };

		variables.environments = { development : "localhost,127\.0\.0\.1" };

		variables.logBox = {
			appenders : { console : { class : "ConsoleAppender" } },
			root      : { levelmax : "INFO", appenders : "*" }
		};
	}

	/**
	 * Loads the module from the repository after the application starts.
	 *
	 * @event         The current request context.
	 * @interceptData Data passed to this interception point.
	 * @rc            The request collection.
	 * @prc           The private request collection.
	 */
	function afterAspectsLoad( event, interceptData, rc, prc ){
		controller
			.getModuleService()
			.registerAndActivateModule( moduleName = request.MODULE_NAME, invocationPath = "moduleroot" );
	}

}
