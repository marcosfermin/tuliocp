<?php

/**
 * Test harness: run the shipped phpMyAdmin sign-on client's API request
 * against a fixture endpoint, without phpMyAdmin and without a browser.
 *
 * Usage: php sso-endpoint.php <rendered tulio-sso.php>
 *
 * The client only defines its class under the CLI, so requiring it here does
 * not start a session or handle a sign-on. Prints one "log=<message>" line for
 * every warning the client raised and a final "result=<OK|FAILED>" line. It
 * always exits 0, so the caller asserts on the output rather than the status.
 */

set_error_handler(function ($errno, $message) {
	echo "log={$message}\n";
	return true;
});

if ($argc < 2) {
	fwrite(STDERR, "usage: sso-endpoint.php <rendered tulio-sso.php>\n");
	exit(1);
}

require $argv[1];

$api = new Tulio_API();
$data = $api->create_temp_user("fixture_db", "fixture_user", "localhost");

if ($data === false) {
	echo "result=FAILED\n";
	exit(0);
}

echo "result=OK\n";
// The credentials the panel returned are deliberately not printed: the tests
// assert that nothing secret reaches the output, and this is the only place
// that could have put a real one there.
echo "credentials=" . (isset($data->login->user) ? "received" : "missing") . "\n";
exit(0);
