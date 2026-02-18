#!/usr/bin/env bash
set -euo pipefail

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Missing required command: $1" >&2
    exit 1
  fi
}

detect_target() {
  local os arch
  os="$(uname -s)"
  arch="$(uname -m)"

  case "${os}" in
    Linux)
      case "${arch}" in
        x86_64|amd64) echo "x86_64-unknown-linux-musl" ;;
        aarch64|arm64) echo "aarch64-unknown-linux-gnu" ;;
        *)
          echo "Unsupported Linux architecture: ${arch}" >&2
          exit 1
          ;;
      esac
      ;;
    Darwin)
      case "${arch}" in
        x86_64|amd64) echo "x86_64-apple-darwin" ;;
        aarch64|arm64) echo "aarch64-apple-darwin" ;;
        *)
          echo "Unsupported macOS architecture: ${arch}" >&2
          exit 1
          ;;
      esac
      ;;
    MINGW*|MSYS*|CYGWIN*)
      case "${arch}" in
        x86_64|amd64) echo "x86_64-pc-windows-msvc" ;;
        *)
          echo "Unsupported Windows architecture: ${arch}" >&2
          exit 1
          ;;
      esac
      ;;
    *)
      echo "Unsupported OS: ${os}" >&2
      exit 1
      ;;
  esac
}

fetch_release_json() {
  local repo version api_base url token json
  repo="$1"
  version="$2"
  token="$3"
  api_base="https://api.github.com/repos/${repo}/releases"

  if [ "${version}" = "latest" ]; then
    url="${api_base}/latest"
    curl_release "${url}" "${token}"
    return $?
  fi

  url="${api_base}/tags/${version}"
  if json="$(curl_release "${url}" "${token}" 2>/dev/null)"; then
    printf '%s\n' "${json}"
    return 0
  fi

  if [ "${version#v}" = "${version}" ]; then
    url="${api_base}/tags/v${version}"
    curl_release "${url}" "${token}"
    return $?
  fi

  return 1
}

curl_release() {
  local url token
  url="$1"
  token="$2"

  if [ -n "${token}" ]; then
    curl -fsSL \
      -H "Accept: application/vnd.github+json" \
      -H "X-GitHub-Api-Version: 2022-11-28" \
      -H "Authorization: Bearer ${token}" \
      "${url}"
  else
    curl -fsSL \
      -H "Accept: application/vnd.github+json" \
      -H "X-GitHub-Api-Version: 2022-11-28" \
      "${url}"
  fi
}

curl_download() {
  local url token out
  url="$1"
  token="$2"
  out="$3"

  if [ -n "${token}" ]; then
    curl -fsSL \
      -H "Authorization: Bearer ${token}" \
      "${url}" \
      -o "${out}"
  else
    curl -fsSL "${url}" -o "${out}"
  fi
}

require_cmd curl
require_cmd jq
require_cmd tar

version="${BREL_VERSION:-latest}"
repo="${BREL_RELEASE_REPO:-better-releases/brel}"
token="${BREL_GITHUB_TOKEN:-}"
requested_target="${BREL_TARGET:-auto}"

if [ "${requested_target}" = "auto" ]; then
  target="$(detect_target)"
else
  target="${requested_target}"
fi

echo "Resolving brel release '${version}' from ${repo} for target ${target}..."
if ! release_json="$(fetch_release_json "${repo}" "${version}" "${token}")"; then
  echo "Failed to resolve release metadata for '${version}' from ${repo}." >&2
  exit 1
fi

asset_json="$(
  echo "${release_json}" | jq -c --arg target "${target}" '
    [
      .assets[]
      | select(
          (.name | contains($target + "."))
          and (.name | test("\\.(tar\\.(gz|xz)|zip)$"))
        )
    ][0] // empty
  '
)"

if [ -z "${asset_json}" ]; then
  echo "Could not find release asset for target ${target} (.tar.gz, .tar.xz, or .zip)." >&2
  exit 1
fi

asset_name="$(echo "${asset_json}" | jq -r '.name // empty')"
asset_url="$(echo "${asset_json}" | jq -r '.browser_download_url // empty')"
release_tag="$(echo "${release_json}" | jq -r '.tag_name // empty')"

if [ -z "${asset_name}" ] || [ -z "${asset_url}" ]; then
  echo "Release asset metadata is incomplete." >&2
  exit 1
fi

temp_root="${RUNNER_TEMP:-/tmp}"
work_dir="$(mktemp -d "${temp_root}/setup-brel.XXXXXX")"
archive_path="${work_dir}/${asset_name}"
extract_dir="${work_dir}/extract"
mkdir -p "${extract_dir}"

cleanup() {
  rm -rf "${work_dir}"
}
trap cleanup EXIT

curl_download "${asset_url}" "${token}" "${archive_path}"

case "${asset_name}" in
  *.tar.gz|*.tgz|*.tar.xz)
    tar -xaf "${archive_path}" -C "${extract_dir}"
    ;;
  *.zip)
    require_cmd unzip
    unzip -q "${archive_path}" -d "${extract_dir}"
    ;;
  *)
    echo "Unsupported archive format: ${asset_name}" >&2
    exit 1
    ;;
esac

bin_name="brel"
if [[ "${target}" == *"-windows-"* ]]; then
  bin_name="brel.exe"
fi

brel_bin="$(find "${extract_dir}" -type f -name "${bin_name}" | head -n1)"
if [ -z "${brel_bin}" ]; then
  echo "Unable to locate ${bin_name} in extracted archive." >&2
  exit 1
fi

install_dir="${BREL_INSTALL_DIR:-}"
if [ -z "${install_dir}" ]; then
  install_dir="${RUNNER_TEMP:-/tmp}"
fi
mkdir -p "${install_dir}"

installed_bin="${install_dir}/${bin_name}"
cp "${brel_bin}" "${installed_bin}"
if [ "${bin_name}" = "brel" ]; then
  chmod +x "${installed_bin}"
fi

if [ -n "${GITHUB_PATH:-}" ]; then
  echo "${install_dir}" >> "${GITHUB_PATH}"
fi

if [ -n "${GITHUB_OUTPUT:-}" ]; then
  {
    echo "path=${install_dir}"
    echo "version=${release_tag}"
    echo "target=${target}"
    echo "binary=${installed_bin}"
  } >> "${GITHUB_OUTPUT}"
fi

echo "Installed ${bin_name} to ${installed_bin}"
