#!/bin/bash

#===========================================================================#
#                                                                           #
# Tulio Control Panel - Main Configuration Function Library                #
#                                                                           #
#===========================================================================#

# Reading and writing $TULIO/conf/tulio.conf.
#
# Every v-script sources that file, so a truncated or half-written copy of it
# takes the whole panel down. Nothing here edits it in place: the new content
# is rendered in full into a temporary file next to it, checked, renamed over
# it and read back, with a backup to fall back on at every step.
#
# None of these functions looks at DEMO_MODE. The guard lives in the commands
# that call them - check_tulio_demo_mode in v-change-sys-config-value - which
# is what lets v-change-sys-demo-mode leave demo mode from inside demo mode
# without any other command gaining the same ability.

# Keys are shell variable names in upper case. Anything outside that shape is
# either unreadable by source_conf or a way to smuggle shell into the file.
sysconfig_is_key_valid() {
	[[ "$1" =~ ^[A-Z][A-Z0-9_]*$ ]]
}

# Values are written between single quotes on a line of their own, so a value
# can hold neither a single quote nor a line break. Other control characters
# are refused with them: source_conf strips those when it reads the file, so a
# value containing one would not come back as the value that went in.
sysconfig_is_value_valid() {
	[[ "$1" != *"'"* ]] && [ "$1" = "${1//[[:cntrl:]]/}" ]
}

# Print the value a key currently holds, without the quotes around it.
#
# A later assignment overrides an earlier one when the file is sourced, so the
# last one is the one reported. Returns 1 when the key is not assigned at all,
# which is not the same as it being assigned an empty value.
sysconfig_value() {
	local key="$1" file="${2:-$TULIO/conf/tulio.conf}" line

	sysconfig_is_key_valid "$key" || return 1
	[ -r "$file" ] || return 1

	line="$(grep -E "^${key}=" "$file" | tail -n 1)"
	[ -z "$line" ] && return 1

	line="${line#*=}"
	if [[ "$line" == \'*\' ]]; then
		line="${line#\'}"
		line="${line%\'}"
	fi

	printf '%s\n' "$line"
	return 0
}

# Rewrite the configuration with one key set to one value.
#
# Reads the current file from stdin and writes the result to stdout. The key
# keeps the position of its first assignment and any repeat of it is dropped,
# so a file that ended up with two copies of a key comes back with one. A key
# that is not there yet is appended.
#
# The file the panel maintains is kept in alphabetical order and
# v-change-sys-config-value has always re-sorted it on every change. That is
# reproduced here only when the input actually was in order: re-sorting a file
# an operator has arranged by hand would be an edit nobody asked for. The
# comparison and the sort both run under the C collation, which is the order
# the installed file is in, so a file already in order comes back in exactly
# the same order.
sysconfig_render() {
	local key="$1" value="$2" line
	local -a lines=() out=()
	local seen='false'

	sysconfig_is_key_valid "$key" || return 1
	sysconfig_is_value_valid "$value" || return 1

	while IFS= read -r line || [ -n "$line" ]; do
		lines+=("$line")
	done

	for line in "${lines[@]}"; do
		if [[ "$line" == "$key="* ]]; then
			if [ "$seen" = 'false' ]; then
				out+=("$key='$value'")
				seen='true'
			fi
			continue
		fi
		out+=("$line")
	done
	[ "$seen" = 'false' ] && out+=("$key='$value'")

	if [ "${#lines[@]}" -gt 0 ] && printf '%s\n' "${lines[@]}" | LC_ALL=C sort -C; then
		printf '%s\n' "${out[@]}" | LC_ALL=C sort
		return 0
	fi

	printf '%s\n' "${out[@]}"
	return 0
}

# Sanity check a rendered configuration before it is allowed to replace the
# original: it may not be empty, it has to assign the key exactly once with the
# value that was asked for, and it has to still assign every key the reference
# copy did. That last check is what catches a render that lost lines.
sysconfig_validate() {
	local file="$1" key="$2" value="$3" reference="$4"
	local ref_key count

	if [ ! -s "$file" ]; then
		echo "Error: resulting configuration is empty" >&2
		return 1
	fi

	count="$(grep -cE "^${key}=" "$file")"
	if [ "$count" -ne 1 ]; then
		echo "Error: $key is assigned $count times in the result, expected once" >&2
		return 1
	fi

	if [ "$(sysconfig_value "$key" "$file")" != "$value" ]; then
		echo "Error: $key did not read back as the value it was set to" >&2
		return 1
	fi

	if [ -n "$reference" ] && [ -f "$reference" ]; then
		while IFS= read -r ref_key; do
			[ -z "$ref_key" ] && continue
			if ! grep -qE "^${ref_key}=" "$file"; then
				echo "Error: resulting configuration lost $ref_key" >&2
				return 1
			fi
		done < <(grep -oE '^[A-Z][A-Z0-9_]*=' "$reference" | tr -d '=' | sort -u)
	fi

	return 0
}

# Set a key in a configuration file, atomically.
#
# A failure at any stage before the rename leaves the original exactly as it
# was. After the rename the file is read back from disk and the backup put back
# if what landed is not what was asked for, because a caller that is told the
# write succeeded will go on to act on it.
sysconfig_write() {
	local key="$1" value="$2" file="${3:-$TULIO/conf/tulio.conf}"
	local target tmp backup

	if ! sysconfig_is_key_valid "$key"; then
		echo "Error: invalid configuration key :: $key" >&2
		return 1
	fi
	if ! sysconfig_is_value_valid "$value"; then
		echo "Error: invalid value for $key, it may not contain a quote or a line break" >&2
		return 1
	fi

	# Follow a symlinked configuration so the link itself is not replaced.
	target="$(readlink -f "$file" 2> /dev/null)"
	[ -n "$target" ] && file="$target"
	if [ ! -f "$file" ]; then
		echo "Error: $file does not exist" >&2
		return 1
	fi

	tmp="$(mktemp "${file}.tulio.XXXXXX")" || return 1
	backup="$(mktemp "${file}.tulio-bak.XXXXXX")" || {
		rm -f "$tmp"
		return 1
	}

	if ! cp -p "$file" "$backup"; then
		rm -f "$tmp" "$backup"
		return 1
	fi

	if ! sysconfig_render "$key" "$value" < "$file" > "$tmp"; then
		rm -f "$tmp" "$backup"
		return 1
	fi

	chmod --reference="$file" "$tmp" 2> /dev/null
	chown --reference="$file" "$tmp" 2> /dev/null

	if ! sysconfig_validate "$tmp" "$key" "$value" "$backup"; then
		rm -f "$tmp" "$backup"
		return 1
	fi

	if ! mv -f "$tmp" "$file"; then
		rm -f "$tmp" "$backup"
		return 1
	fi

	if ! sysconfig_validate "$file" "$key" "$value" "$backup"; then
		cat "$backup" > "$file"
		rm -f "$backup"
		return 1
	fi

	rm -f "$backup"
	return 0
}
