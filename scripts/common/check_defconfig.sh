#!/bin/bash
# Helper shared by the scripts in scripts/defconfigs/.

# check_defconfig <defconfig> <resolved .config>
#
# Kconfig silently drops an option of a defconfig when the symbol does not exist
# in the tree or its dependencies are not met (e.g. CONFIG_PREEMPT_RT=y without
# the preempt_rt patch, which provides ARCH_SUPPORTS_RT). Print every option
# requested by <defconfig> that did not end up in <resolved .config> as asked.
# Returns 1 if at least one option was dropped or changed.
check_defconfig() {
  local defconfig="$1"
  local config="$2"
  local dropped=0
  local line sym actual

  while IFS= read -r line; do
    case "${line}" in
    CONFIG_*=* | BR2_*=*)
      sym="${line%%=*}"
      grep -qxF -- "${line}" "${config}" && continue
      ;;
    "# CONFIG_"*" is not set" | "# BR2_"*" is not set")
      sym="${line#\# }"
      sym="${sym% is not set}"
      # A symbol hidden by its dependencies is not set either.
      grep -qE "^${sym}=" "${config}" || continue
      ;;
    *)
      continue
      ;;
    esac
    actual=$(grep -E "^${sym}=|^# ${sym} is not set$" "${config}" | head -1)
    echo "  ${line}  ->  ${actual:-<not present>}"
    dropped=1
  done <"${defconfig}"

  return ${dropped}
}
