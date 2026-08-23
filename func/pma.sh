#!/bin/bash

#===========================================================================#
#                                                                           #
# Tulio Control Panel - phpMyAdmin Single Sign-On Function Library          #
#                                                                           #
#===========================================================================#

# The sign-on client posts the panel API key to the panel over HTTPS and gets
# database credentials back, so it verifies the panel certificate and fails the
# sign-on when it cannot. These helpers render it from its template and pick the
# trust anchor it should use, and are shared by v-add-sys-pma-sso and by the
# upgrade step that refreshes an already installed copy.

# Read one define() value out of a rendered sign-on client.
#
# Prints the value and returns 0 only when the define is present and was
# substituted; an absent or still unsubstituted placeholder returns 1, so a
# caller can tell "no value" from "empty value".
pma_sso_read_define() {
	local file="$1" name="$2" value

	[ -f "$file" ] || return 1

	value="$(sed -n "s/^define(\"${name}\", \"\(.*\)\");\$/\1/p" "$file" | head -n 1)"
	[ -z "$value" ] && return 1
	[ "$value" = "%${name}%" ] && return 1

	echo "$value"
	return 0
}

# Decide which trust anchor the sign-on client should use for the panel.
#
# Prints nothing when the system trust store already verifies the panel
# certificate, which is the case for a publicly issued one. When it does not -
# a self-signed panel certificate, most commonly - the panel's own certificate
# is pinned instead, so the sign-on keeps working without the client ever
# accepting a certificate it could not verify. Anything other than a
# certificate problem leaves the system trust store in charge.
pma_sso_ca_file() {
	local host="$1" port="$2" cert="${3:-$TULIO/ssl/certificate.crt}"
	local rc=0

	[ -f "$cert" ] || return 0
	command -v curl > /dev/null 2>&1 || return 0

	curl -s -S -o /dev/null --max-time 10 "https://${host}:${port}/" > /dev/null 2>&1 || rc=$?

	# 60 is curl's "peer certificate cannot be authenticated", which covers an
	# unknown issuer and a name mismatch alike.
	if [ "$rc" -eq 60 ]; then
		echo "$cert"
	fi

	return 0
}

# Replace every occurrence of a placeholder with a value, literally.
#
# The obvious spellings all reinterpret the value: sed reads it as part of a
# script, and bash's own ${text//from/to} treats a bare & as the matched text
# from 5.2 onwards. Splitting the text on the placeholder instead gives the
# value no meaning at all, so a generated key containing / & \ or $ comes out
# exactly as it went in.
pma_sso_substitute() {
	local text="$1" needle="$2" value="$3" out=""

	while [ "$text" != "${text#*"$needle"}" ]; do
		out+="${text%%"$needle"*}${value}"
		text="${text#*"$needle"}"
	done

	printf '%s' "${out}${text}"
}

# Render the sign-on client from its template into a destination file.
#
# The rendered file is written to a temporary file first and only moved into
# place once every placeholder is gone and PHP can parse it, so a half-rendered
# client - one that would still send a literal %API_KEY% - is never installed.
pma_sso_render() {
	local template="$1" dest="$2"
	local pma_key="$3" api_host="$4" api_port="$5" api_key="$6" ca_file="${7:-}"
	local content tmp leftover value

	if [ ! -f "$template" ]; then
		echo "Error: phpMyAdmin SSO template $template is missing" >&2
		return 1
	fi

	# Each value lands inside a PHP double-quoted string, where a backslash
	# escapes, a double quote ends the string and a $ starts a variable. Every
	# value the panel puts here is plain text - generated keys are
	# alphanumeric, the rest is a hostname, a port and a file path - so refuse
	# the ones that would need escaping instead of writing a file whose
	# meaning depends on getting that escaping right.
	for value in "$pma_key" "$api_host" "$api_port" "$api_key" "$ca_file"; do
		case "$value" in
			*[\"\\$]*)
				echo "Error: phpMyAdmin SSO value contains \" \\ or \$, refusing to render" >&2
				return 1
				;;
		esac
	done

	content="$(cat "$template")" || return 1
	content="$(pma_sso_substitute "$content" '%PHPMYADMIN_KEY%' "$pma_key")"
	content="$(pma_sso_substitute "$content" '%API_HOST_NAME%' "$api_host")"
	content="$(pma_sso_substitute "$content" '%API_TULIO_PORT%' "$api_port")"
	content="$(pma_sso_substitute "$content" '%API_KEY%' "$api_key")"
	content="$(pma_sso_substitute "$content" '%API_CA_FILE%' "$ca_file")"

	tmp="$(mktemp "${dest}.tulio.XXXXXX")" || return 1
	printf '%s\n' "$content" > "$tmp" || {
		rm -f "$tmp"
		return 1
	}

	leftover="$(grep -o '%[A-Z_]\+%' "$tmp" | head -n 1)"
	if [ -n "$leftover" ]; then
		rm -f "$tmp"
		echo "Error: phpMyAdmin SSO client still contains $leftover" >&2
		return 1
	fi

	if command -v php > /dev/null 2>&1 && ! php -l "$tmp" > /dev/null 2>&1; then
		rm -f "$tmp"
		echo "Error: rendered phpMyAdmin SSO client does not parse" >&2
		return 1
	fi

	# The client holds the API key, so it is never readable by the world, not
	# even for the moment between writing it and setting its final mode.
	chmod 640 "$tmp"
	chown root:tuliomail "$tmp" 2> /dev/null

	if ! mv -f "$tmp" "$dest"; then
		rm -f "$tmp"
		return 1
	fi

	return 0
}
