<?php

/* Tulio way to enable support for SSO to PHPmyAdmin */
/* To install please run v-add-sys-pma-sso */

/* Following keys will get replaced when calling v-add-sys-pma-sso */
define("PHPMYADMIN_KEY", "%PHPMYADMIN_KEY%");
define("API_HOST_NAME", "%API_HOST_NAME%");
define("API_TULIO_PORT", "%API_TULIO_PORT%");
define("API_KEY", "%API_KEY%");
/* Optional trust anchor for the panel certificate. Empty means the system
   trust store, which is what a panel with a publicly issued certificate needs.
   Point it at a CA bundle or at the panel certificate itself when that store
   does not chain to it. It only ever adds trust: there is no value that turns
   verification off. */
define("API_CA_FILE", "%API_CA_FILE%");

class Tulio_API {
	/** @var string */
	public $hostname;
	/** @var string */
	public $key;
	/** @var string */
	public $pma_key;
	/** @var string */
	private $api_url;
	/** @var string */
	private $endpoint;
	public function __construct() {
		$this->hostname = API_HOST_NAME;
		$this->endpoint = API_HOST_NAME . ":" . API_TULIO_PORT;
		$this->api_url = "https://" . $this->endpoint . "/api/";
		$this->key = API_KEY;
		$this->pma_key = PHPMYADMIN_KEY;
	}

	/* Creates curl request */
	public function request($postvars) {
		$postdata = http_build_query($postvars);

		$curl = curl_init();
		if ($curl === false) {
			$this->fail("curl_init() failed");
			return false;
		}

		/* This request carries the panel API key and asks the panel to create
		   a database account, so the panel certificate is always verified
		   against a trust store: a certificate that cannot be verified, or one
		   issued for a different name, must fail the sign-on rather than hand
		   the key to whoever answered on that address. Redirects are refused
		   for the same reason - the API only ever answers in place, and
		   following a redirect would repost the key somewhere else. */
		$options = [
			CURLOPT_URL => $this->api_url,
			CURLOPT_RETURNTRANSFER => true,
			CURLOPT_POST => true,
			CURLOPT_POSTFIELDS => $postdata,
			CURLOPT_USERAGENT => "Tulio Control Panel phpMyAdmin SSO",
			CURLOPT_SSL_VERIFYPEER => true,
			CURLOPT_SSL_VERIFYHOST => 2,
			CURLOPT_FOLLOWLOCATION => false,
			CURLOPT_CONNECTTIMEOUT => 10,
			CURLOPT_TIMEOUT => 30,
		];

		/* A trust anchor is always an absolute path. Anything else - an
		   unsubstituted placeholder above all - means none was configured,
		   which leaves the system trust store in charge. Nothing here can
		   disable verification, only add to what is trusted. */
		$ca_file = API_CA_FILE;
		if (substr($ca_file, 0, 1) === "/") {
			if (!is_readable($ca_file)) {
				curl_close($curl);
				$this->fail("configured CA file is not readable: {$ca_file}");
				return false;
			}
			$options[CURLOPT_CAINFO] = $ca_file;
		}

		if (curl_setopt_array($curl, $options) === false) {
			$error = curl_error($curl);
			curl_close($curl);
			$this->fail("curl_setopt_array() failed: {$error}");
			return false;
		}

		$answer = curl_exec($curl);
		if ($answer === false) {
			/* Certificate and hostname verification failures arrive here.
			 Nothing below may retry the request with weaker options. */
			$errno = curl_errno($curl);
			$error = curl_error($curl);
			curl_close($curl);
			$this->fail("request to {$this->endpoint} failed: {$error} (curl error {$errno})");
			return false;
		}

		$status = curl_getinfo($curl, CURLINFO_RESPONSE_CODE);
		curl_close($curl);

		if ($status != 200) {
			$this->fail("request to {$this->endpoint} returned HTTP {$status}");
			return false;
		}

		return $answer;
	}

	/* Report a failed request.
	   The message describes the connection only. The API key, the phpMyAdmin
	   key and the generated database credentials are never part of it, so a
	   failed sign-on cannot leak them into the web server error log. */
	private function fail($message) {
		trigger_error("phpMyAdmin SSO: " . $message, E_USER_WARNING);
	}

	/* Creates an new temp user in mysql */
	public function create_temp_user($database, $user, $host) {
		$post_request = [
			"hash" => $this->key,
			"returncode" => "no",
			"cmd" => "v-add-database-temp-user",
			"arg1" => $user,
			"arg2" => $database,
			"arg3" => "mysql",
			"arg4" => $host,
		];
		$request = $this->request($post_request);
		$json = json_decode($request);
		if (json_last_error() == JSON_ERROR_NONE) {
			return $json;
		} else {
			trigger_error("Unable to connect over API please check api connection", E_USER_WARNING);
			return false;
		}
	}

	/* Delete an new temp user in mysql */
	public function delete_temp_user($database, $user, $dbuser, $host) {
		$post_request = [
			"hash" => $this->key,
			"returncode" => "yes",
			"cmd" => "v-delete-database-temp-user",
			"arg1" => $user,
			"arg2" => $database,
			"arg3" => $dbuser,
			"arg4" => "mysql",
			"arg5" => $host,
		];
		$request = $this->request($post_request);
		if (is_numeric($request) && $request == 0) {
			return true;
		} else {
			return false;
		}
	}

	public function get_user_ip() {
		// Saving user IPs to the session for preventing session hijacking
		$user_combined_ip = [];
		if ($_SERVER["REMOTE_ADDR"] != $_SERVER["SERVER_ADDR"]) {
			$user_combined_ip[] = $_SERVER["REMOTE_ADDR"];
		}
		if (isset($_SERVER["HTTP_CLIENT_IP"])) {
			$user_combined_ip .= "|" . $_SERVER["HTTP_CLIENT_IP"];
		}
		if (isset($_SERVER["HTTP_X_FORWARDED_FOR"])) {
			if ($_SERVER["REMOTE_ADDR"] != $_SERVER["HTTP_X_FORWARDED_FOR"]) {
				$user_combined_ip[] = $_SERVER["HTTP_X_FORWARDED_FOR"];
			}
		}
		if (isset($_SERVER["HTTP_FORWARDED_FOR"])) {
			if ($_SERVER["REMOTE_ADDR"] != $_SERVER["HTTP_FORWARDED_FOR"]) {
				$user_combined_ip[] = $_SERVER["HTTP_FORWARDED_FOR"];
			}
		}
		if (isset($_SERVER["HTTP_X_FORWARDED"])) {
			if ($_SERVER["REMOTE_ADDR"] != $_SERVER["HTTP_X_FORWARDED"]) {
				$user_combined_ip[] = $_SERVER["HTTP_X_FORWARDED"];
			}
		}
		if (isset($_SERVER["HTTP_FORWARDED"])) {
			if ($_SERVER["REMOTE_ADDR"] != $_SERVER["HTTP_FORWARDED"]) {
				$user_combined_ip[] = "|" . $_SERVER["HTTP_FORWARDED"];
			}
		}
		if (isset($_SERVER["HTTP_CF_CONNECTING_IP"])) {
			if (!empty($_SERVER["HTTP_CF_CONNECTING_IP"])) {
				$user_combined_ip[] = $_SERVER["HTTP_CF_CONNECTING_IP"];
			}
		}
		return implode("|", $user_combined_ip);
	}
}

function verify_token($database, $user, $ip, $time, $token) {
	if (!password_verify($database . $user . $ip . $time . PHPMYADMIN_KEY, $token)) {
		if (
			!password_verify(
				$database . $user . $_SERVER["SERVER_ADDR"] . "|" . $ip . $time . PHPMYADMIN_KEY,
				$token,
			)
		) {
			trigger_error(
				"Access denied: There is a security token mismatch " . $time,
				E_USER_WARNING,
			);
			session_invalid();
		}
	}
	return;
}

function session_invalid() {
	global $session_name;
	//delete all current sessions
	session_destroy();
	setcookie($session_name, null, -1, "/");
	header("Location: " . dirname($_SERVER["PHP_SELF"]) . "/index.php");
	die();
}

/* Handle one sign-on request. Everything above only declares things, so the
   file can be loaded to exercise the API client on its own - see the call at
   the bottom. */
function tulio_sso_main() {
	global $session_name;

	/* Need to have cookie visible from parent directory */
	session_set_cookie_params(0, "/", "", true, true);
	/* Create signon session */
	$session_name = "SignonSession";
	session_name($session_name);
	@session_start();

	$api = new Tulio_API();
	if (!empty($_GET)) {
		if (isset($_GET["logout"])) {
			$api->delete_temp_user(
				$_SESSION["TULIO_sso_database"],
				$_SESSION["TULIO_sso_user"],
				$_SESSION["PMA_single_signon_user"],
				$_SESSION["TULIO_sso_host"],
			);
			//remove session
			session_invalid();
		} else {
			if (isset($_GET["user"]) && isset($_GET["tulio_token"])) {
				$database = $_GET["database"];
				$user = $_GET["user"];
				$host = "localhost";
				$token = $_GET["tulio_token"];
				if (is_numeric($_GET["exp"])) {
					$time = $_GET["exp"];
				} else {
					$time = 0;
				}

				if ($time + 60 > time()) {
					//note: Possible issues with cloudflare due to ip obfuscation
					$ip = $api->get_user_ip();
					verify_token($database, $user, $ip, $time, $token);
					$id = session_id();
					//create a new temp user
					$data = $api->create_temp_user($database, $user, $host);
					if ($data) {
						$_SESSION["PMA_single_signon_user"] = $data->login->user;
						$_SESSION["PMA_single_signon_password"] = $data->login->password;
						$_SESSION["PMA_single_signon_host"] = $host;
						//save database / username to be used for sending logout notification.
						$_SESSION["TULIO_sso_user"] = $user;
						$_SESSION["TULIO_sso_database"] = $database;
						$_SESSION["TULIO_sso_host"] = $host;

						@session_write_close();
						setcookie($session_name, $id, 0, "/");
						header("Location: " . dirname($_SERVER["PHP_SELF"]) . "/index.php");
						die();
					} else {
						session_invalid();
					}
				} else {
					trigger_error(
						"Link has been expired: System time: " .
							time() .
							" / Time provided in link: " .
							$time,
						E_USER_WARNING,
					);
					session_invalid();
				}
			}
		}
	} else {
		session_invalid();
	}
}

/* phpMyAdmin redirects the browser to this file, so it is always reached
   through the web server. Under the CLI it only defines its class, which is
   how the test harness exercises the API client without a sign-on request. */
if (PHP_SAPI !== "cli") {
	tulio_sso_main();
}
