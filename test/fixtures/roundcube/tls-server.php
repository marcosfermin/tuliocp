<?php

/**
 * Test harness: a one-shot HTTPS endpoint that stands in for the panel.
 *
 * Usage: php tls-server.php <cert> <key> <port file> <request log> [body]
 *
 * Binds to a free port on the loopback address, writes that port to <port
 * file>, serves exactly one request and writes everything it received to
 * <request log>. A client that refuses the certificate never gets that far, so
 * an empty request log is the proof that nothing was sent.
 */

error_reporting(E_ERROR | E_PARSE);

if ($argc < 5) {
	fwrite(STDERR, "usage: tls-server.php <cert> <key> <port file> <request log> [body]\n");
	exit(1);
}

[$script, $cert, $key, $port_file, $request_log] = $argv;
$body = $argc > 5 ? $argv[5] : "ok";

$context = stream_context_create([
	"ssl" => [
		"local_cert" => $cert,
		"local_pk" => $key,
		"verify_peer" => false,
		"verify_peer_name" => false,
		"allow_self_signed" => true,
	],
]);

$server = stream_socket_server(
	"tls://127.0.0.1:0",
	$errno,
	$errstr,
	STREAM_SERVER_BIND | STREAM_SERVER_LISTEN,
	$context,
);

if ($server === false) {
	fwrite(STDERR, "unable to listen: {$errstr} ({$errno})\n");
	exit(1);
}

$address = stream_socket_get_name($server, false);
$port = substr($address, strrpos($address, ":") + 1);

file_put_contents($request_log, "");
// Written last: the caller waits for this file and then connects.
file_put_contents($port_file, $port);

$client = @stream_socket_accept($server, 20);
if ($client === false) {
	// A rejected certificate ends here, with nothing received.
	fwrite(STDERR, "no client completed the handshake\n");
	exit(0);
}

stream_set_timeout($client, 10);

$request = "";
while (!feof($client)) {
	$chunk = fread($client, 4096);
	if ($chunk === false || $chunk === "") {
		break;
	}
	$request .= $chunk;

	$split = strpos($request, "\r\n\r\n");
	if ($split === false) {
		continue;
	}

	$length = 0;
	if (preg_match("/^Content-Length:[[:space:]]*([0-9]+)/mi", substr($request, 0, $split), $m)) {
		$length = (int) $m[1];
	}
	if (strlen($request) >= $split + 4 + $length) {
		break;
	}
}

file_put_contents($request_log, $request);

$response =
	"HTTP/1.1 200 OK\r\n" .
	"Content-Type: text/plain\r\n" .
	"Content-Length: " .
	strlen($body) .
	"\r\n" .
	"Connection: close\r\n" .
	"\r\n" .
	$body;

fwrite($client, $response);
fclose($client);
fclose($server);
exit(0);
