#!/usr/bin/env bash
set -euo pipefail

CUR_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOP_DIR="$(cd "${CUR_DIR}/.." && pwd)"

# In CI, Bazel is typically installed by jwlawson/actions-setup-bazel.
# We keep Bazel version in a single place: the repo-root `.bazelversion`.
# Strategy:
# - Prefer system `bazel` if it matches the desired version.
# - Otherwise, fall back to `bazelisk` (multi-arch), which honors `.bazelversion`.

DESIRED_BAZEL_VERSION=""
if [[ -f "${TOP_DIR}/.bazelversion" ]]; then
  DESIRED_BAZEL_VERSION="$(tr -d ' \t\r\n' < "${TOP_DIR}/.bazelversion")"
fi
if [[ -z "${DESIRED_BAZEL_VERSION}" ]]; then
  DESIRED_BAZEL_VERSION="${USE_BAZEL_VERSION:-${BAZEL_VERSION:-}}"
fi
if [[ -n "${DESIRED_BAZEL_VERSION}" ]]; then
  export USE_BAZEL_VERSION="${DESIRED_BAZEL_VERSION}"
fi

BAZEL_BIN=""
if command -v bazel > /dev/null 2>&1; then
  if [[ -z "${DESIRED_BAZEL_VERSION}" ]]; then
    BAZEL_BIN="bazel"
  else
    SYS_VER_RAW="$(bazel --version 2> /dev/null || true)"
    SYS_VER="${SYS_VER_RAW##* }"
    if [[ -n "${SYS_VER}" && "${SYS_VER}" == "${DESIRED_BAZEL_VERSION}" ]]; then
      BAZEL_BIN="bazel"
    fi
  fi
fi

if [[ -z "${BAZEL_BIN}" ]] && command -v bazelisk > /dev/null 2>&1; then
  BAZEL_BIN="bazelisk"
fi

if [[ -z "${BAZEL_BIN}" ]]; then
  OS="$(uname -s | tr '[:upper:]' '[:lower:]')"
  ARCH="$(uname -m)"
  case "${OS}" in
    linux)
      case "${ARCH}" in
        x86_64 | amd64) ASSET="bazelisk-linux-amd64" ;;
        aarch64 | arm64) ASSET="bazelisk-linux-arm64" ;;
        *)
          echo "Unsupported arch for bazelisk: ${ARCH}" >&2
          exit 1
          ;;
      esac
      ;;
    darwin)
      case "${ARCH}" in
        x86_64 | amd64) ASSET="bazelisk-darwin-amd64" ;;
        arm64) ASSET="bazelisk-darwin-arm64" ;;
        *)
          echo "Unsupported arch for bazelisk: ${ARCH}" >&2
          exit 1
          ;;
      esac
      ;;
    *)
      echo "Unsupported OS for bazelisk: ${OS}" >&2
      exit 1
      ;;
  esac

  TMP_DIR="$(mktemp -d)"
  trap 'rm -rf "${TMP_DIR}"' EXIT
  BAZELISK_PATH="${TMP_DIR}/bazelisk"
  URL="https://github.com/bazelbuild/bazelisk/releases/latest/download/${ASSET}"

  if command -v curl > /dev/null 2>&1; then
    curl -fsSL "${URL}" -o "${BAZELISK_PATH}"
  elif command -v wget > /dev/null 2>&1; then
    wget -qO "${BAZELISK_PATH}" "${URL}"
  else
    echo "Neither curl nor wget is available to download bazelisk" >&2
    exit 1
  fi
  chmod +x "${BAZELISK_PATH}"
  BAZEL_BIN="${BAZELISK_PATH}"
fi
#
# Pass through user-provided Bazel flags (e.g. --config=xxx / --copt=xxx).
# Note: Bazel options must appear before the target.
"${BAZEL_BIN}" coverage --combined_report=lcov "$@" unittest-gcc-coverage

OUTPUT_PATH="$("${BAZEL_BIN}" info output_path)"
COV_DAT="${OUTPUT_PATH}/_coverage/_coverage_report.dat"
if [[ ! -f "${COV_DAT}" ]]; then
  echo "Coverage report not found: ${COV_DAT}" >&2
  exit 1
fi

mv -f "${COV_DAT}" "${TOP_DIR}/coverage.dat"
