#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 1 || $# -gt 2 ]]; then
  printf '用法: %s <版本号，如 0.3.7> [构建号]\n' "$0" >&2
  exit 2
fi

version=$1
if [[ ! $version =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  printf '无效版本号: 需要 X.Y.Z 格式\n' >&2
  exit 2
fi

project_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
if [[ $# -eq 2 ]]; then
  build_number=$2
else
  build_number=$(git -C "$project_root" rev-list --count HEAD)
fi
if [[ ! $build_number =~ ^[1-9][0-9]*$ ]]; then
  printf '无效构建号: 需要正整数\n' >&2
  exit 2
fi

build_dir="$project_root/build"
ipa_name="PiliPod ${version}+${build_number}.ipa"
mkdir -p "$build_dir"
staging_dir=$(mktemp -d "$build_dir/ipa.XXXXXX")
trap 'rm -rf "$staging_dir"' EXIT

printf '构建未签名 IPA：版本 %s，构建号 %s\n' "$version" "$build_number"
xcodebuild -quiet archive \
  -project "$project_root/PiliPod.xcodeproj" \
  -scheme PiliPod \
  -configuration Release \
  -destination 'generic/platform=iOS' \
  -archivePath "$staging_dir/PiliPod.xcarchive" \
  -derivedDataPath "$build_dir/DerivedData" \
  -clonedSourcePackagesDirPath "$build_dir/SourcePackages" \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY= \
  PROVISIONING_PROFILE_SPECIFIER= \
  "MARKETING_VERSION=$version" \
  "CURRENT_PROJECT_VERSION=$build_number"

mkdir -p "$staging_dir/Payload"
ditto "$staging_dir/PiliPod.xcarchive/Products/Applications/PiliPod.app" \
  "$staging_dir/Payload/PiliPod.app"
(
  cd "$staging_dir"
  zip -qry output.ipa Payload
)
mv -f "$staging_dir/output.ipa" "$build_dir/$ipa_name"
printf 'IPA 已生成：%s\n' "$build_dir/$ipa_name"
