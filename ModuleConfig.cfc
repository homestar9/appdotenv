/**
 * AppDotEnv: a per-application `.env` for ColdBox apps that share one CFML engine with other sites.
 *
 * The module itself does not load the file. ColdBox runs config/ColdBox.cfc and every
 * config/modules/*.cfc before any module loads, and those files need the values, so the host
 * app's Application.cfc builds `application.dotenv` before the ColdBox bootstrap (see README).
 * This module then registers that same instance with WireBox as `DotEnv@appdotenv` and logs
 * where it was read from.
 */
component {

	// Module details
	this.title       = "AppDotEnv";
	this.author      = "Angry Sam Productions, Inc.";
	this.webURL      = "https://github.com/homestar9/appdotenv";
	this.description = "Loads each ColdBox app's own .env into the application scope, so sites that share one CFML engine never share secrets.";
	// Keep the version in box.json instead of copying it here.
	this.version     = readPackageVersion();

	// WireBox model namespace
	this.modelNamespace = "appdotenv";
	// The one model is mapped by hand to the instance Application.cfc built, so a second,
	// unloaded DotEnv must never be auto-mapped under the same name.
	this.autoMapModels  = false;

	// CFML mapping
	this.cfmapping = "appdotenv";

	// This module has no runtime dependencies.
	this.dependencies = [];

	/**
	 * Maps `DotEnv@appdotenv` to `application.dotenv`. Throws AppDotEnv.NotBooted when
	 * Application.cfc has not created it, because every config CFC that reads it has already
	 * run by now and a later lookup would only fail somewhere less obvious.
	 */
	function configure(){
		variables.settings = {};

		if ( !application.keyExists( "dotenv" ) ) {
			throw(
				type    = "AppDotEnv.NotBooted",
				message = "application.dotenv does not exist. AppDotEnv needs Application.cfc to create it before ColdBox boots.",
				detail  = "In onApplicationStart, before the ColdBox bootstrap: application.dotenv = new modules.appdotenv.models.DotEnv( appRoot = COLDBOX_APP_ROOT_PATH ).load(); See the appdotenv README."
			);
		}

		binder.map( "DotEnv@appdotenv" ).toValue( application.dotenv );
	}

	/**
	 * Logs which file was read and how many keys it held. Never logs values. A missing file is
	 * a warning, because production normally has one.
	 */
	function onLoad(){
		var message = application.dotenv.describe();
		if ( application.dotenv.isLoaded() ) {
			log.info( message );
		} else {
			log.warn( message );
		}
	}

	/**
	 * Run after ColdBox stops and unregisters the module.
	 */
	function onUnload(){
	}

	/**
	 * Reads the module version from box.json.
	 * ColdBox reads this.version before configure(), so this method runs early.
	 * Returns an empty string when box.json cannot be read.
	 */
	private string function readPackageVersion(){
		try {
			var boxJsonPath = getDirectoryFromPath( getCurrentTemplatePath() ) & "box.json";

			if ( !fileExists( boxJsonPath ) ) {
				return "";
			}

			var boxJson = deserializeJSON( fileRead( boxJsonPath ) );

			return boxJson.keyExists( "version" ) ? boxJson.version : "";
		} catch ( any e ) {
			return "";
		}
	}

}
