<?php

/**
 * Test harness: run the shipped Tulio password driver against a fixture
 * configuration, without a Roundcube installation.
 *
 * Usage: php driver-endpoint.php <config file> <driver file>
 *
 * Prints one "log=<message>" line for every message the driver logged and a
 * final "result=<constant>" line. It always exits 0, so the caller asserts on
 * the output rather than on the exit status.
 */

define("PASSWORD_SUCCESS", 0);
define("PASSWORD_CRYPT_ERROR", 1);
define("PASSWORD_ERROR", 2);
define("PASSWORD_CONNECT_ERROR", 3);

class rcube {
	public static function write_log($area, $message) {
		echo "log={$message}\n";
	}
}

class tulio_fixture_config {
	private $values;

	public function __construct(array $values) {
		$this->values = $values;
	}

	public function get($key, $default = null) {
		return array_key_exists($key, $this->values) ? $this->values[$key] : $default;
	}
}

class rcmail {
	public $config;
	private static $instance;

	public static function get_instance() {
		return self::$instance;
	}

	public static function load_config(array $values) {
		self::$instance = new self();
		self::$instance->config = new tulio_fixture_config($values);
	}
}

if ($argc < 3) {
	fwrite(STDERR, "usage: driver-endpoint.php <config file> <driver file>\n");
	exit(1);
}

// Load the plugin configuration the way Roundcube does.
$config = [];
require $argv[1];
rcmail::load_config($config);

require $argv[2];

$_SESSION["username"] = "fixture@example.org";

$driver = new rcube_tulio_password();
$result = $driver->save("current-password", "new-password");

$names = [
	PASSWORD_SUCCESS => "PASSWORD_SUCCESS",
	PASSWORD_CRYPT_ERROR => "PASSWORD_CRYPT_ERROR",
	PASSWORD_ERROR => "PASSWORD_ERROR",
	PASSWORD_CONNECT_ERROR => "PASSWORD_CONNECT_ERROR",
];

echo "result=" . (isset($names[$result]) ? $names[$result] : $result) . "\n";
exit(0);
