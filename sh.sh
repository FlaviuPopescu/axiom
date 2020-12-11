#!/bin/bash
INFO=$(
	cat <<-'EOF'
		Uses shellcheck to fix any issues in a repo which shellcheck knows how to
		fix automatically and then commits the changes.
	EOF
)

set -o errexit
set -o nounset

shopt -s globstar

declare -a DEPS
DEPS=(
	'git'
	'sponge'
	'shellcheck'
)

declare -a AUTOFIX
AUTOFIX=(
	'2006'
	'2086'
	'2251'
)

declare -A AUTOFIX_MSGS
# shellcheck disable=SC2016
AUTOFIX_MSGS=(
	['2006']='Use $(...) notation instead of legacy backticked `...`'
	['2086']='Double quote to prevent globbing and word splitting.'
	['2251']='This ! is not on a condition and skips errexit. Use && exit 1 instead, or make sure $? is checked.'
)

function autofix() {
	local code
	local msg

	code=$1
	msg=$2

	printf 'Checking files for SC%s\n' "${code}"
	for src_file in **/*; do
		# skip non-regular files
		if ! [[ -f "${src_file}" ]]; then
			continue
		fi

		# grab mimetype
		if ! mime_type=$(file --mime-type -b "${src_file}"); then
			printf 'Unable to get mimetype of %s\n' "${src_file}"
			exit 1
		fi

		# skip anything that is not a shellscript
		if [[ "${mime_type}" != 'text/x-shellscript' ]]; then
			continue
		fi

		# if there is nothing to fix, skip
		if shellcheck -i "${code}" -f quiet "${src_file}"; then
			continue
		fi

		printf 'Auto fixing SC%s in %s\n' "${code}" "${src_file}"
		shellcheck -i "${code}" -f diff "${src_file}" | sponge | git apply
	done
	if [[ -n "$(git status --porcelain)" ]]; then
		printf 'Committing fixes for SC%s\n' "${code}"
		git add -A
		git commit -m "SC${code}: ${msg}"
	fi
}

usage() {
	printf '%s\n' "${INFO}"
	printf 'usage: %s\n' "${0##*/}"
	printf '  -d <DIR>      Repo directory to autofix\n'
	printf '  -h            This message\n'
}

main() {
	while getopts ':d:h' opt; do
		case "${opt}" in
		d)
			repo=$OPTARG
			;;
		h)
			usage
			exit
			;;
		\?)
			usage 1>&2
			exit 1
			;;
		:)
			echo "Option -$OPTARG requires an argument" >&2
			exit 1
			;;
		esac
	done
	shift $((OPTIND - 1))

	for dep in "${DEPS[@]}"; do
		if ! command -v "${dep}" >/dev/null 2>&1; then
			printf 'Command %s required!\n' "${dep}"
			exit 1
		fi
	done

	if [[ ! -v 'repo' || -z "${repo}" ]]; then
		usage 1>&2
		exit 1
	fi

	pushd "${repo}" >/dev/null
	for fix_num in "${AUTOFIX[@]}"; do
		autofix "${fix_num}" "${AUTOFIX_MSGS["$fix_num"]}"
	done
	popd >/dev/null
	printf 'Auto fixing complete, git log:\n'
	git log --oneline origin..
}

main "${@}"
