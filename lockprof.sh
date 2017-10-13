#! /bin/sh
# 
# Copyright (c) 2017 Bryan Drewery <bdrewery@FreeBSD.org>
# All rights reserved.
# 
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions
# are met:
# 1. Redistributions of source code must retain the above copyright
#    notice, this list of conditions and the following disclaimer.
# 2. Redistributions in binary form must reproduce the above copyright
#    notice, this list of conditions and the following disclaimer in the
#    documentation and/or other materials provided with the distribution.
# 
# THIS SOFTWARE IS PROVIDED BY THE AUTHOR AND CONTRIBUTORS ``AS IS'' AND
# ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
# IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
# ARE DISCLAIMED.  IN NO EVENT SHALL THE AUTHOR OR CONTRIBUTORS BE LIABLE
# FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
# DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS
# OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
# HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT
# LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY
# OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF
# SUCH DAMAGE.

msg() {
	echo "lockprof: $@"
}

stats_start() {
	local phase="${1}"

	msg "Resetting stats for phase '${phase}'"
	sysctl debug.lock.prof.reset=1 >/dev/null
	sysctl -a > "${DST}/${phase}.sysctl.start"
}

stats_stop() {
	local phase="${1}"

	msg "Recording stats for phase '${phase}'"
	sysctl debug.lock.prof.stats > "${DST}/${phase}.stats"
	sysctl -a > "${DST}/${phase}.sysctl.stop"
}

THIS=${0##*/}
THIS=${THIS%.sh}
DST="/tmp/poudriere-lockprof/${BUILDNAME}"
mkdir -p "${DST}"

case "${THIS}" in
# Ensure pkgbuild hack removed at the end
jail)
	case "${1}" in
	start)
		# Symlink the logdir in
		ln -fs "${LOG}" "${DST}/logs"
		msg "Enabling lock profiling to ${DST}"
		sysctl debug.lock.prof.enable=1 >/dev/null
		;;
	stop)
		msg "Disabling lock profiling"
		sysctl debug.lock.prof.enable=0 >/dev/null
		# Remove pkgbuild hack
		rm -f "${0%/*}/pkgbuild.sh" 2>/dev/null || :
		;;
	esac
	exit 0
	;;
esac

# Reset/Record stats for all other hooks
case "${1}" in
start)
	case "${THIS}" in
	# Special case, if pkg is in the queue then we need to record stats for
	# pkg and then start build_queue stats after it.  This is done by
	# installing a temporary pkgbuild hook to avoid it being called
	# for every package after pkg.
	build_queue)
		if grep -wq "^ports-mgmt/pkg" \
		    "${LOG}/.poudriere.ports.queued"; then
			ln -fs "lockprof.sh" "${0%/*}/pkgbuild.sh"
			# There is no pkgbuild start hook currently so
			# record stats now as pkgbuild for pkg.
			stats_start "pkgbuild"
			exit 0
		fi
		;;
	esac
	stats_start "${THIS}"
	;;
stop)
	stats_stop "${THIS}"
	;;
esac

# Special case, when pkg is done building remove the hook and
# reset the stats for build_queue.  It's unclear but pkgbuild
# is only called at the end of a build.
case "${THIS}" in
pkgbuild)
	rm -f "${0%/*}/pkgbuild.sh" 2>/dev/null || :
	stats_stop "${THIS}"
	stats_start "build_queue"
	;;
esac
