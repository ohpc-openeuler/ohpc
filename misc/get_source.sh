#!/bin/bash

if [ $# -ne 1 ]; then
	echo "${0} requires the name of the spec file as parameter."
	exit 1
fi

PATTERN=${1}

IFS=$'\n'

find . -name "${PATTERN}" -print0 | while IFS= read -r -d '' file
do
	if [ ! -f "${file}" ]; then
		echo "${file} is not a file. Skipping."
		continue
	fi

	echo "${file}"

	DIR=$(dirname "${file}")
	pushd "${DIR}" > /dev/null || exit 1
	BASE=$(basename "${file}")

	SOURCES=$(rpmspec --parse --define '_sourcedir ../../..' --define 'rhel 8' "${BASE}" | grep Source)
	for u in ${SOURCES}; do
		echo "${u}"
		if [[ "${u}" != *"http"* ]]; then
			continue
		fi
		u=$(awk '{ print $2 }' <<< "${u}")
		echo "Trying to get ${u}"
		# Try to download only if newer
		WGET=$(wget -N -nv -P ../SOURCES "${u}" 2>&1)
		# Handling for github URLs with #/ or #$/
		if grep -E "#[$]?/" <<< "${u}"; then
			MV_SOURCE=$(echo "${WGET}" | tail -1 | cut -d\  -f6 | sed -e 's/^"//' -e 's/"$//')
			MV_DEST=../SOURCES/$(basename "${u}")
			mv "${MV_SOURCE}" "${MV_DEST}"
		fi
	done

	popd > /dev/null || exit 1
done
