/**
 * The harness home page: reports what the module loaded, never the values.
 */
component {

	property name="dotenv" inject="DotEnv@appdotenv";

	/**
	 * Shows the load summary and key names.
	 */
	function index( event, rc, prc ){
		return event.renderData(
			type = "json",
			data = {
				"summary" : dotenv.describe(),
				"keys"    : dotenv.keys()
			}
		);
	}

}
