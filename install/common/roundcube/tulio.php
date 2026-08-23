<?php

/**
 * Tulio Control Panel Password Driver
 *
 * @version 1.1
 * @author TulioCP <info@tuliocp.com>
 */
class rcube_tulio_password {
	public function save($curpass, $passwd) {
		$rcmail = rcmail::get_instance();
		$tulio_host = $rcmail->config->get("password_tulio_host");

		if (empty($tulio_host)) {
			$tulio_host = "localhost";
		}

		$tulio_port = $rcmail->config->get("password_tulio_port");
		if (empty($tulio_port)) {
			$tulio_port = "8083";
		}

		$postvars = [
			"email" => $_SESSION["username"],
			"password" => $curpass,
			"new" => $passwd,
		];
		$url = "https://{$tulio_host}:{$tulio_port}/reset/mail/";

		// This request carries the mailbox password in clear text inside the
		// TLS session, so the certificate is always verified against a trust
		// store: an unverifiable panel certificate must fail the password
		// change rather than hand the credentials to whoever answered.
		// password_tulio_ca_file is optional and only ever adds trust - leave
		// it unset to use the system trust store, or point it at a CA bundle
		// when the panel serves a certificate that store does not chain to.
		// There is deliberately no option to turn verification off.
		$options = [
			CURLOPT_URL => $url,
			CURLOPT_RETURNTRANSFER => true,
			CURLOPT_HEADER => true,
			CURLOPT_POST => true,
			CURLOPT_POSTFIELDS => http_build_query($postvars),
			CURLOPT_USERAGENT => "Tulio Control Panel Password Driver",
			CURLOPT_SSL_VERIFYPEER => true,
			CURLOPT_SSL_VERIFYHOST => 2,
			CURLOPT_FOLLOWLOCATION => false,
			CURLOPT_CONNECTTIMEOUT => 10,
			CURLOPT_TIMEOUT => 30,
		];

		$ca_file = $rcmail->config->get("password_tulio_ca_file");
		if (!empty($ca_file)) {
			if (!is_readable($ca_file)) {
				return $this->fail("configured CA file is not readable: {$ca_file}");
			}
			$options[CURLOPT_CAINFO] = $ca_file;
		}

		$ch = curl_init();
		if ($ch === false) {
			return $this->fail("curl_init() failed");
		}

		if (curl_setopt_array($ch, $options) === false) {
			$error = curl_error($ch);
			curl_close($ch);
			return $this->fail("curl_setopt_array() failed: {$error}");
		}

		$result = curl_exec($ch);
		if ($result === false) {
			// Certificate and hostname verification failures arrive here.
			// Nothing below may retry the request with weaker options.
			$errno = curl_errno($ch);
			$error = curl_error($ch);
			curl_close($ch);
			return $this->fail(
				"request to {$tulio_host}:{$tulio_port} failed: {$error} (curl error {$errno})",
			);
		}
		curl_close($ch);

		if (strpos($result, "ok") !== false && strpos($result, "error") === false) {
			return PASSWORD_SUCCESS;
		}

		return PASSWORD_ERROR;
	}

	/**
	 * Report a failed attempt.
	 *
	 * The message describes the connection only: the submitted passwords are
	 * never logged, and the caller is told the panel could not be reached so a
	 * password is never treated as changed when the request did not complete
	 * over a verified connection.
	 */
	private function fail($message) {
		if (class_exists("rcube")) {
			rcube::write_log("errors", "Tulio password driver: {$message}");
		}

		if (defined("PASSWORD_CONNECT_ERROR")) {
			return PASSWORD_CONNECT_ERROR;
		}

		return PASSWORD_ERROR;
	}
}
