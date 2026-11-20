#!/usr/bin/env bash
# so-rec — record the current shell: commands as typed, their output, timestamps.
# Source it; do not execute it.
#
#   source ~/scripts/lib/so-rec.sh
#   rec                      # start; log -> ./rec-<timestamp>.log
#   rec start [file]         # start; log -> file
#   rec start -t [file]      # also trace inside functions (set -T)
#   rec stop
#   rec status

if [[ ${BASH_SOURCE[0]} == "$0" ]]; then
  printf 'so-rec: source this file: source %s\n' "${BASH_SOURCE[0]}" >&2
  return 2 2>/dev/null || exit 2
fi

(( BASH_VERSINFO[0] > 4 || (BASH_VERSINFO[0] == 4 && BASH_VERSINFO[1] >= 2) )) || {
  echo 'so-rec: bash >= 4.2 required' >&2
  return 1 2>/dev/null || exit 1
}

rec() {
  case ${1:-start} in
    start)  shift; _so_rec_start "$@" ;;
    stop)   _so_rec_stop ;;
    status) if [[ -n ${_so_rec_log:-} ]]; then
              printf 'rec: recording to %s (trace=%s)\n' "$_so_rec_log" "${_so_rec_trace:-0}"
            else
              echo 'rec: not recording'
            fi ;;
    *)      echo 'usage: rec [start [-t] [file]] | rec stop | rec status' >&2; return 2 ;;
  esac
}

_so_rec_start() {
  local trace=0 log=''
  while (($#)); do
    case $1 in
      -t|--trace) trace=1 ;;
      *) if [[ -n $log ]]; then echo 'rec: too many arguments' >&2; return 2; fi
         log=$1 ;;
    esac
    shift
  done

  if [[ -n ${_so_rec_log:-} ]]; then
    printf 'rec: already recording to %s\n' "$_so_rec_log" >&2
    return 1
  fi

  [[ -n $log ]] || { printf -v log 'rec-%(%Y%m%d-%H%M%S)T.log' -1; log=$PWD/$log; }
  : >>"$log" || { printf 'rec: cannot write %s\n' "$log" >&2; return 1; }

  # Keep the real streams so `rec stop` can put them back.
  exec {_so_rec_out}>&1 {_so_rec_err}>&2

  # Markers get their own fd, straight into the file. They must never travel
  # through the stdout pipe: that would leak them into $(...) and pipelines.
  exec {_so_rec_mark}>>"$log"

  # One merged pipe for the output, so stdout and stderr keep their relative
  # order. The tee child is created before 2>&1, so its errors reach the real
  # stderr.
  exec 1> >(tee -a "$log") 2>&1

  _so_rec_log=$log
  _so_rec_trace=$trace
  _so_rec_prev_functrace=$([[ -o functrace ]] && echo 1 || echo 0)

  trap '_so_rec_debug' DEBUG
  (( trace )) && set -T

  printf '=== rec started %(%Y-%m-%d %H:%M:%S)T%s\n' -1 \
    "$([[ $trace == 1 ]] && echo ' (trace)')" >&"$_so_rec_mark"
}

_so_rec_debug() {
  [[ -z ${_so_rec_log:-} ]] && return 0

  # Skip the recorder's own plumbing.
  case ${FUNCNAME[1]:-} in rec|_so_rec_*) return 0 ;; esac
  case $BASH_COMMAND in rec\ *|_so_rec_*|exec\ *) return 0 ;; esac
  # With functrace on, entering a function logs the call twice.
  [[ ${FUNCNAME[1]:-} == "$BASH_COMMAND" ]] && return 0

  local note=''
  (( BASH_SUBSHELL > 0 )) && note='   # (subshell)'
  printf '%(%H:%M:%S)T $ %*s%s%s\n' -1 \
    "$(( (${#FUNCNAME[@]} - 1) * 2 ))" '' "$BASH_COMMAND" "$note" >&"$_so_rec_mark"
}

_so_rec_stop() {
  if [[ -z ${_so_rec_log:-} ]]; then
    echo 'rec: not recording' >&2
    return 1
  fi
  local log=$_so_rec_log

  # Clearing the state makes the still-installed trap a no-op: bash restores
  # trap state when a function returns, so it can't be removed from here.
  unset _so_rec_log _so_rec_trace
  [[ ${_so_rec_prev_functrace:-0} == 1 ]] || set +T

  exec 1>&"$_so_rec_out" 2>&"$_so_rec_err"
  exec {_so_rec_out}>&- {_so_rec_err}>&- {_so_rec_mark}>&-
  unset _so_rec_prev_functrace _so_rec_out _so_rec_err _so_rec_mark

  printf 'rec: wrote %s\n' "$log"
}
