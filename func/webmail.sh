#!/bin/bash

#===========================================================================#
#                                                                           #
# Tulio Control Panel - Webmail Function Library                           #
#                                                                           #
#===========================================================================#

# Regular expression matching a complete assignment to one Roundcube setting.
# Both the $config array current releases read and the $rcmail_config array
# older releases used are matched, so a stale assignment to the dead array is
# replaced rather than left behind next to the live one.
roundcube_option_pattern() {
	printf '^[[:space:]]*\\$(config|rcmail_config)\\[[[:space:]]*[\047"]%s[\047"][[:space:]]*\\][[:space:]]*=' "$1"
}

# Check that a file still parses as PHP. Without a PHP interpreter the check is
# skipped rather than treated as a failure.
roundcube_php_lint() {
	local file="$1" php_bin="${TULIO_PHP:-}"

	if [ ! -x "$php_bin" ]; then
		php_bin="$(command -v php 2> /dev/null)"
	fi
	[ -n "$php_bin" ] && [ -x "$php_bin" ] || return 0

	"$php_bin" -l "$file" > /dev/null 2>&1
}

# Print the value a Roundcube configuration file assigns to one setting.
#
# The last assignment wins, and an assignment to the live $config array always
# beats one to the dead $rcmail_config array, which is what PHP itself ends up
# using.
get_roundcube_option() {
	local file="$1" key="$2"

	[ -f "$file" ] || return 1

	TULIO_RC_PATTERN="$(roundcube_option_pattern "$key")" awk '
		function unquote(text) {
			sub(/^[^=]*=[[:space:]]*/, "", text)
			sub(/[[:space:]]*;[[:space:]]*$/, "", text)
			sub(/^[\047"]/, "", text)
			sub(/[\047"]$/, "", text)
			return text
		}
		BEGIN {
			pattern = ENVIRON["TULIO_RC_PATTERN"]
			have_config = 0
			have_legacy = 0
		}
		$0 ~ pattern {
			if ($0 ~ /^[[:space:]]*\$config\[/) {
				config_value = unquote($0)
				have_config = 1
			} else {
				legacy_value = unquote($0)
				have_legacy = 1
			}
		}
		END {
			if (have_config) print config_value
			else if (have_legacy) print legacy_value
		}
	' "$file"
}

# Set one option in a Roundcube configuration file.
#
# Only a complete assignment to that exact setting is rewritten, so unrelated
# settings that merely mention the key keep their values, and a setting whose
# value happens to appear elsewhere in the file is not rewritten by accident.
# Duplicate and legacy assignments collapse into the single $config form.
# The result replaces the original only after it has been confirmed to still
# parse as PHP, so a failed rewrite leaves the working configuration in place.
set_roundcube_option() {
	local file="$1" key="$2" value="$3"
	local tmp escaped

	[ -f "$file" ] || return 1

	# Single quoted PHP strings treat only the backslash and the quote itself
	# as special.
	escaped="${value//\\/\\\\}"
	escaped="${escaped//\'/\\\'}"

	tmp="$(mktemp "${file}.tulio.XXXXXX")" || return 1

	if ! TULIO_RC_PATTERN="$(roundcube_option_pattern "$key")" \
	TULIO_RC_LINE="\$config['${key}'] = '${escaped}';" \
		awk '
			BEGIN {
				pattern = ENVIRON["TULIO_RC_PATTERN"]
				replaced = 0
			}
			$0 ~ pattern {
				if (replaced == 0) {
					print ENVIRON["TULIO_RC_LINE"]
					replaced = 1
				}
				next
			}
			{ print }
			END { if (replaced == 0) print ENVIRON["TULIO_RC_LINE"] }
		' "$file" > "$tmp"; then
		rm -f "$tmp"
		return 1
	fi

	if ! roundcube_php_lint "$tmp"; then
		rm -f "$tmp"
		return 1
	fi

	chmod --reference="$file" "$tmp" 2> /dev/null
	chown --reference="$file" "$tmp" 2> /dev/null

	if ! mv -f "$tmp" "$file"; then
		rm -f "$tmp"
		return 1
	fi

	return 0
}
