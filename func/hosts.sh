#!/bin/bash

#===========================================================================#
#                                                                           #
# Tulio Control Panel - /etc/hosts Function Library                        #
#                                                                           #
#===========================================================================#

# Names that belong to the loopback boilerplate every distribution ships. They
# describe the local machine rather than the panel hostname, so they are never
# renamed, reordered or removed when the hostname changes.
HOSTS_RESERVED_NAMES="localhost localhost.localdomain localhost4 localhost4.localdomain4
	localhost6 localhost6.localdomain6 ip6-localhost ip6-loopback ip6-localnet
	ip6-mcastprefix ip6-allnodes ip6-allrouters ip6-allhosts"

# Check whether a name is part of the loopback boilerplate.
hosts_is_reserved_name() {
	local name="$1" reserved
	for reserved in $HOSTS_RESERVED_NAMES; do
		[ "$name" = "$reserved" ] && return 0
	done
	return 1
}

# Check whether a name appears in the remaining arguments.
hosts_contains() {
	local needle="$1" item
	shift
	for item in "$@"; do
		[ "$item" = "$needle" ] && return 0
	done
	return 1
}

# Rank an address by how well it suits the machine's own hostname mapping.
# A routable address beats the Debian 127.0.1.1 slot, which in turn beats plain
# loopback. The ranking only picks between mappings that already exist, so the
# fully qualified name is never moved onto 127.0.0.1 on its own.
hosts_address_rank() {
	case "$1" in
		127.0.0.1 | ::1) echo 1 ;;
		127.* | ::*) echo 2 ;;
		*) echo 3 ;;
	esac
}

# Split a single line of a hosts file into its parts.
#
# Populates _hosts_indent, _hosts_addr, _hosts_names and _hosts_comment and
# returns 0 when the line is a host mapping. Blank lines, comment-only lines
# and anything that does not begin with an address return 1 and must be passed
# through untouched.
hosts_parse_line() {
	local raw="$1" body trimmed

	_hosts_indent=""
	_hosts_addr=""
	_hosts_names=""
	_hosts_comment=""

	body="$raw"
	if [[ "$body" == *'#'* ]]; then
		_hosts_comment="#${body#*#}"
		body="${body%%#*}"
	fi

	trimmed="${body#"${body%%[![:space:]]*}"}"
	trimmed="${trimmed%"${trimmed##*[![:space:]]}"}"
	[ -z "$trimmed" ] && return 1
	_hosts_indent="${body%%[![:space:]]*}"

	_hosts_addr="${trimmed%%[[:space:]]*}"
	# A mapping needs an address that looks like one, plus at least one name.
	[ "$_hosts_addr" = "$trimmed" ] && return 1
	[[ "$_hosts_addr" =~ ^[0-9a-fA-F:.]+(%[0-9a-zA-Z]+)?$ ]] || return 1
	[[ "$_hosts_addr" == *.* || "$_hosts_addr" == *:* ]] || return 1

	_hosts_names="${trimmed#*[[:space:]]}"
	_hosts_names="${_hosts_names#"${_hosts_names%%[![:space:]]*}"}"
	[ -z "$_hosts_names" ] && return 1

	return 0
}

# Check whether a mapping carries the hostname being renamed. An unqualified
# hostname is matched on its bare token; a fully qualified one is not matched on
# its short form alone, so an unrelated "demo" alias elsewhere in the file does
# not claim ownership of "demo.example.com".
hosts_line_owns() {
	local names="$1" fqdn="$2" token
	for token in $names; do
		[ "$token" = "$fqdn" ] && return 0
	done
	return 1
}

# Rewrite a hosts file so that the new hostname replaces the old one.
#
# Reads the current file from stdin and writes the result to stdout:
#   - the mapping that already carries the old (or new) hostname keeps its
#     address and its unrelated aliases, and has the hostname tokens renamed
#   - the short form is only rewritten on the mapping that carries the fully
#     qualified name, so unrelated aliases that happen to share the short name
#     are left alone
#   - stale copies of either hostname on other mappings are dropped, and a
#     mapping that held nothing else is dropped with them
#   - loopback boilerplate is preserved in place
#   - when no mapping carries the hostname at all, a 127.0.1.1 entry is added,
#     which is the Debian slot for a machine's own fully qualified name
# Lines that come out unchanged are emitted byte for byte, so re-running this
# against its own output is a no-op.
hosts_render() {
	local old_fqdn="$1" new_fqdn="$2"
	local old_short="${old_fqdn%%.*}" new_short="${new_fqdn%%.*}"
	local line token i rank
	local primary=-1 primary_rank=0
	local -a lines=() out=()

	while IFS= read -r line || [ -n "$line" ]; do
		lines+=("$line")
	done

	# Pass one: pick the mapping that owns the hostname. Ties keep the first
	# match, so the file's own ordering decides between equally suitable lines.
	for i in "${!lines[@]}"; do
		hosts_parse_line "${lines[i]}" || continue
		if ! hosts_line_owns "$_hosts_names" "$old_fqdn" \
			&& ! hosts_line_owns "$_hosts_names" "$new_fqdn"; then
			continue
		fi
		rank="$(hosts_address_rank "$_hosts_addr")"
		if [ "$rank" -gt "$primary_rank" ]; then
			primary="$i"
			primary_rank="$rank"
		fi
	done

	# Pass two: rename on the owning mapping, clean up everywhere else.
	for i in "${!lines[@]}"; do
		if ! hosts_parse_line "${lines[i]}"; then
			out+=("${lines[i]}")
			continue
		fi

		local -a names=() reserved=() canonical=() kept=() final=()
		local owns_old='false' owns_new='false' is_primary='false'

		read -r -a names <<< "$_hosts_names"
		hosts_line_owns "$_hosts_names" "$old_fqdn" && owns_old='true'
		hosts_line_owns "$_hosts_names" "$new_fqdn" && owns_new='true'
		[ "$i" = "$primary" ] && is_primary='true'

		for token in "${names[@]}"; do
			if hosts_is_reserved_name "$token"; then
				hosts_contains "$token" "${reserved[@]}" || reserved+=("$token")
				continue
			fi
			# Hostname tokens are dropped here and re-added below on the
			# owning mapping only, which both renames and deduplicates them.
			if [ "$token" = "$old_fqdn" ] || [ "$token" = "$new_fqdn" ]; then
				continue
			fi
			if [ "$token" = "$old_short" ] && [ "$owns_old" = 'true' ]; then
				continue
			fi
			if [ "$token" = "$new_short" ] && [ "$owns_new" = 'true' ]; then
				continue
			fi
			hosts_contains "$token" "${kept[@]}" || kept+=("$token")
		done

		if [ "$is_primary" = 'true' ]; then
			canonical=("$new_fqdn")
			[ "$new_short" != "$new_fqdn" ] && canonical+=("$new_short")
		fi

		final=("${reserved[@]}" "${canonical[@]}" "${kept[@]}")

		# The mapping existed only for the old hostname: drop it.
		[ "${#final[@]}" -eq 0 ] && continue

		if [ "${final[*]}" = "${names[*]}" ]; then
			out+=("${lines[i]}")
		else
			out+=("${_hosts_indent}${_hosts_addr} ${final[*]}${_hosts_comment:+ $_hosts_comment}")
		fi
	done

	if [ "$primary" -lt 0 ]; then
		if [ "$new_short" != "$new_fqdn" ]; then
			out+=("127.0.1.1 $new_fqdn $new_short")
		else
			out+=("127.0.1.1 $new_fqdn")
		fi
	fi

	[ "${#out[@]}" -eq 0 ] && return 0
	printf '%s\n' "${out[@]}"
	return 0
}

# Sanity check a rendered hosts file before it is allowed to replace the
# original. Refuses an empty file, a file without host mappings, a hostname that
# is mapped more than once or not at all, a leftover mapping of the old
# hostname, and the loss of the localhost mapping.
hosts_validate() {
	local candidate="$1" new_fqdn="$2" old_fqdn="$3" reference="$4"
	local line token
	local mappings=0 new_count=0 localhost_found='false'

	if [ ! -s "$candidate" ]; then
		echo "Error: resulting hosts file is empty" >&2
		return 1
	fi

	while IFS= read -r line || [ -n "$line" ]; do
		hosts_parse_line "$line" || continue
		mappings=$((mappings + 1))
		for token in $_hosts_names; do
			[ "$token" = "$new_fqdn" ] && new_count=$((new_count + 1))
			[ "$token" = "localhost" ] && localhost_found='true'
			if [ "$token" = "$old_fqdn" ] && [ "$old_fqdn" != "$new_fqdn" ]; then
				echo "Error: old hostname $old_fqdn is still mapped" >&2
				return 1
			fi
		done
	done < "$candidate"

	if [ "$mappings" -lt 1 ]; then
		echo "Error: resulting hosts file has no host mappings" >&2
		return 1
	fi
	if [ "$new_count" -ne 1 ]; then
		echo "Error: hostname $new_fqdn is mapped $new_count times, expected once" >&2
		return 1
	fi
	if [ -n "$reference" ] && [ -f "$reference" ] && [ "$localhost_found" != 'true' ]; then
		if grep -qE '(^|[[:space:]])localhost([[:space:]]|$)' "$reference"; then
			echo "Error: resulting hosts file lost its localhost mapping" >&2
			return 1
		fi
	fi

	return 0
}

# Point a hosts file at a new hostname.
#
# The new content is rendered and validated in a temporary file next to the
# original and only then renamed into place, so a failure at any stage leaves
# the original untouched. If the file on disk somehow fails validation after the
# rename, the backup taken beforehand is restored.
update_etc_hosts() {
	local old_fqdn="$1" new_fqdn="$2" hosts_file="${3:-/etc/hosts}"
	local target tmp backup

	[ -e "$hosts_file" ] || return 0

	# Follow a symlinked hosts file so the link itself is not replaced.
	target="$(readlink -f "$hosts_file" 2> /dev/null)"
	[ -n "$target" ] && hosts_file="$target"
	[ -f "$hosts_file" ] || return 0

	tmp="$(mktemp "${hosts_file}.tulio.XXXXXX")" || return 1
	backup="$(mktemp "${hosts_file}.tulio-bak.XXXXXX")" || {
		rm -f "$tmp"
		return 1
	}

	if ! cp -p "$hosts_file" "$backup"; then
		rm -f "$tmp" "$backup"
		return 1
	fi

	if ! hosts_render "$old_fqdn" "$new_fqdn" < "$hosts_file" > "$tmp"; then
		rm -f "$tmp" "$backup"
		return 1
	fi

	chmod --reference="$hosts_file" "$tmp" 2> /dev/null
	chown --reference="$hosts_file" "$tmp" 2> /dev/null

	if ! hosts_validate "$tmp" "$new_fqdn" "$old_fqdn" "$backup"; then
		rm -f "$tmp" "$backup"
		return 1
	fi

	if ! mv -f "$tmp" "$hosts_file"; then
		rm -f "$tmp" "$backup"
		return 1
	fi

	if ! hosts_validate "$hosts_file" "$new_fqdn" "$old_fqdn" "$backup"; then
		cat "$backup" > "$hosts_file"
		rm -f "$backup"
		return 1
	fi

	rm -f "$backup"
	return 0
}
