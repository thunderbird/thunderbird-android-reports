#!/usr/bin/env bash
#
# merged-prs-report
#
# Generates monthly reports of pull requests merged into the main, beta,
# and release branches of a GitHub repository.
#
# Usage:
#   ./merged-prs-report YEAR MONTH [TARGET_DIR]
#
# Example:
#   ./merged-prs-report 2026 02
#   ./merged-prs-report 2026 02 ./reports
#
# Arguments:
#   YEAR           Four-digit year (e.g. 2026)
#   MONTH          Two-digit month (01-12)
#   TARGET_DIR     (Optional) Target directory for reports (default: current directory)
#
# Output:
#   - Markdown report: TARGET_DIR/merged-prs-YEAR-MONTH.md
#   - CSV report: TARGET_DIR/csv/merged-prs-YEAR-MONTH.csv
#   - Report index: TARGET_DIR/README.md
#
# For each PR, the reports include:
#   - branch       Target branch (main, beta, release)
#   - PR           PR number and link
#   - merged       Merge date (YYYY-MM-DD)
#   - title        PR title
#   - report       Status from labels (Highlight, Include, Exclude, Review)
#   - beta         First beta tag containing the merge commit (if any)
#   - release      First release tag containing the merge commit (if any)
#
# The CSV report also includes:
#   - author       PR author
#   - sha          Merge commit SHA
#   - url          Link to the PR
#   - comment      Empty column for manual notes
#
# Requirements:
#   - git: Installed and run from within the repository
#   - gh: GitHub CLI authenticated with access to the repository
#   - jq: JSON processor installed
#   - macOS/BSD or GNU date command
#
# Configuration:
#   REPORT_OWNER      GitHub repository owner (default: thunderbird)
#   REPORT_REPO       GitHub repository name (default: thunderbird-android)
#   REPORT_BRANCHES   Space-separated target branches (default: main beta release)
#
set -Eeuo pipefail

if [[ $# -lt 2 || $# -gt 3 ]]; then
  echo "Usage: $0 YEAR MONTH [TARGET_DIR]"
  echo "Example: $0 2026 02"
  echo "Example: $0 2026 02 ./reports"
  exit 1
fi

YEAR="$1"
MONTH="$2"
TARGET_DIR="."

if [[ $# -ge 3 ]]; then
  TARGET_DIR="$3"
fi

OWNER="${REPORT_OWNER:-thunderbird}"
REPO="${REPORT_REPO:-thunderbird-android}"
read -r -a BRANCHES <<< "${REPORT_BRANCHES:-main beta release}"
DEFAULT_STATUS="Review"

# Validate input format
if [[ ! "$YEAR" =~ ^[0-9]{4}$ ]]; then
  echo "Error: YEAR must be a four-digit number (e.g. 2026)"
  exit 1
fi
if [[ ! "$MONTH" =~ ^(0[1-9]|1[0-2])$ ]]; then
  echo "Error: MONTH must be two digits (01-12)"
  exit 1
fi

START="${YEAR}-${MONTH}-01"

calculate_month_end() {
  local start="$1"

  if date -j -v+1m -v-1d -f "%Y-%m-%d" "$start" +%Y-%m-%d >/dev/null 2>&1; then
    date -j -v+1m -v-1d -f "%Y-%m-%d" "$start" +%Y-%m-%d
  elif date -d "$start +1 month -1 day" +%Y-%m-%d >/dev/null 2>&1; then
    date -d "$start +1 month -1 day" +%Y-%m-%d
  else
    echo "Error: Failed to calculate date range. Install macOS/BSD date or GNU date." >&2
    return 1
  fi
}

END="$(calculate_month_end "$START")"

# Create target directories if they don't exist
MD_DIR="$TARGET_DIR"
CSV_DIR="${TARGET_DIR}/csv"
mkdir -p "$MD_DIR" "$CSV_DIR"

MD_OUT="${MD_DIR}/merged-prs-${YEAR}-${MONTH}.md"
CSV_OUT="${CSV_DIR}/merged-prs-${YEAR}-${MONTH}.csv"
INDEX_OUT="${TARGET_DIR}/README.md"
CSV_LINK="csv/merged-prs-${YEAR}-${MONTH}.csv"

# Temporary setup for git operations
TMP_REPO="$(mktemp -d)"
CACHE_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_REPO" "$CACHE_DIR"' EXIT

BETA_CACHE_FILE="$CACHE_DIR/beta_cache.txt"
RELEASE_CACHE_FILE="$CACHE_DIR/release_cache.txt"
touch "$BETA_CACHE_FILE" "$RELEASE_CACHE_FILE"

echo "Preparing temporary repo for tag analysis in $TMP_REPO..."
git init -q "$TMP_REPO"
git -C "$TMP_REPO" remote add origin "https://github.com/$OWNER/$REPO.git"

echo "Fetching tags and branch heads from origin..."
git -C "$TMP_REPO" fetch origin "${BRANCHES[@]}" --tags --quiet

map_report_status() {
  local labels_json="$1"

  if jq -e '.[] | select(.name == "report: highlight")' >/dev/null <<< "$labels_json"; then
    echo "Highlight"
  elif jq -e '.[] | select(.name == "report: include")' >/dev/null <<< "$labels_json"; then
    echo "Include"
  elif jq -e '.[] | select(.name == "report: exclude")' >/dev/null <<< "$labels_json"; then
    echo "Exclude"
  else
    echo "$DEFAULT_STATUS"
  fi
}

map_version() {
  local sha="$1"
  local mode="$2"

  if [[ -z "$sha" ]]; then
    echo "-"
    return
  fi

  local target_branch
  if [[ "$mode" == "release" ]]; then
    target_branch="release"
  elif [[ "$mode" == "beta" ]]; then
    target_branch="beta"
  else
    echo "Error: Invalid mode '$mode' in map_version" >&2
    return 1
  fi

  # If commit is not in the target branch history, it's not applicable
  if ! git -C "$TMP_REPO" merge-base --is-ancestor "$sha" "origin/$target_branch" 2>/dev/null; then
    echo "-"
    return
  fi

  # Find the first tag (by version sorting) that contains this commit
  local first_tag
  if [[ "$mode" == "release" ]]; then
    # Exclude tags containing 'b' (betas)
    first_tag="$(git -C "$TMP_REPO" tag --list "THUNDERBIRD_*" --contains "$sha" --sort=version:refname | grep -v "b" | head -n 1)"
  else
    # Only tags containing 'b' (betas)
    first_tag="$(git -C "$TMP_REPO" tag --list "THUNDERBIRD_*b*" --contains "$sha" --sort=version:refname | head -n 1)"
  fi

  if [[ -n "$first_tag" ]]; then
    echo "$first_tag"
  else
    echo "Not released yet"
  fi
}

get_cached_value() {
  local cache_file="$1"
  local sha="$2"

  local result
  result="$(awk -F '\t' -v key="$sha" '$1 == key { print $2; exit }' "$cache_file")"

  if [[ -n "$result" ]]; then
    echo "$result"
    return 0
  fi

  return 1
}

set_cached_value() {
  local cache_file="$1"
  local sha="$2"
  local value="$3"

  printf '%s\t%s\n' "$sha" "$value" >> "$cache_file"
}

escape_md() {
  printf '%s' "$1" | sed 's/|/\\|/g'
}

escape_csv() {
  local value="$1"
  value="${value//\"/\"\"}"
  printf '"%s"' "$value"
}

format_release_tag_md() {
  local value="$1"

  if [[ "$value" == THUNDERBIRD_* ]]; then
    printf '[%s](https://github.com/%s/%s/releases/tag/%s)' "$value" "$OWNER" "$REPO" "$value"
  else
    printf '%s' "$value"
  fi
}

update_report_index() {
  {
    echo "# Merged PR Reports"
    echo
    echo "Monthly reports of pull requests merged into $OWNER/$REPO."
    echo
    echo "| Month | Markdown | CSV |"
    echo "|---|---|---|"

    local report_file
    while IFS= read -r report_file; do
      local report_name
      local report_month
      local csv_name

      report_name="$(basename "$report_file")"
      report_month="${report_name#merged-prs-}"
      report_month="${report_month%.md}"
      csv_name="merged-prs-${report_month}.csv"

      if [[ -f "$CSV_DIR/$csv_name" ]]; then
        echo "| $report_month | [$report_name]($report_name) | [$csv_name](csv/$csv_name) |"
      else
        echo "| $report_month | [$report_name]($report_name) | - |"
      fi
    done < <(find "$TARGET_DIR" -maxdepth 1 -type f -name 'merged-prs-*.md' | sort -r)
  } > "$INDEX_OUT"
}

append_report_table() {
  local rows_file="$1"

  echo "| PR | Merged | SHA | Title | Feature Flag | Beta | Release |" >> "$MD_OUT"
  echo "|---|---|---|---|---|---|---|" >> "$MD_OUT"
  cat "$rows_file" >> "$MD_OUT"
  echo >> "$MD_OUT"
}

append_status_section() {
  local title="$1"
  local rows_file="$2"

  if [[ ! -s "$rows_file" ]]; then
    return
  fi

  echo "### $title" >> "$MD_OUT"
  echo >> "$MD_OUT"
  append_report_table "$rows_file"
}

append_excluded_section() {
  local rows_file="$1"

  if [[ ! -s "$rows_file" ]]; then
    return
  fi

  echo "<details>" >> "$MD_OUT"
  echo "<summary>Excluded</summary>" >> "$MD_OUT"
  echo >> "$MD_OUT"
  append_report_table "$rows_file"
  echo "</details>" >> "$MD_OUT"
  echo >> "$MD_OUT"
}

{
  echo "# Merged PR Report (${YEAR}-${MONTH})"
  echo
  echo "**Repository:** $OWNER/$REPO  "
  echo "**Range:** $START -> $END  "
  echo "**CSV:** [$CSV_LINK]($CSV_LINK)"
  echo
} > "$MD_OUT"

echo "Branch,Number,Merged,Author,Title,Report,Beta,Release,SHA,URL,Comment" > "$CSV_OUT"

for BRANCH in "${BRANCHES[@]}"; do
  echo "Processing $BRANCH..."

  echo "## Branch: $BRANCH" >> "$MD_OUT"
  echo >> "$MD_OUT"

  prs_json="$(gh pr list \
    --repo "$OWNER/$REPO" \
    --state merged \
    --base "$BRANCH" \
    --search "merged:$START..$END" \
    --json number,title,body,url,mergedAt,mergeCommit,labels,author \
    --limit 1000)"

  sorted_prs_json="$(jq 'sort_by(.mergedAt)' <<< "$prs_json")"

  if [[ "$(jq 'length' <<< "$sorted_prs_json")" -eq 0 ]]; then
    echo "_No merged PRs in this range._" >> "$MD_OUT"
    echo >> "$MD_OUT"
    continue
  fi

  branch_key="${BRANCH//[^[:alnum:]_-]/_}"
  highlight_rows="$(mktemp "$CACHE_DIR/highlight-${branch_key}.XXXXXX")"
  include_rows="$(mktemp "$CACHE_DIR/include-${branch_key}.XXXXXX")"
  review_rows="$(mktemp "$CACHE_DIR/review-${branch_key}.XXXXXX")"
  exclude_rows="$(mktemp "$CACHE_DIR/exclude-${branch_key}.XXXXXX")"

  while IFS= read -r pr; do
    number="$(jq -r '.number' <<< "$pr")"
    title="$(jq -r '.title' <<< "$pr")"
    title_md="$(escape_md "$title")"
    url="$(jq -r '.url' <<< "$pr")"
    merged_at="$(jq -r '.mergedAt | split("T")[0]' <<< "$pr")"
    sha="$(jq -r '.mergeCommit.oid // empty' <<< "$pr")"
    author="$(jq -r '.author.login // "ghost"' <<< "$pr")"
    labels_json="$(jq -c '.labels // []' <<< "$pr")"
    status="$(map_report_status "$labels_json")"
    feature_flag="$(jq -r \
      'try (.body // "" | gsub("\r"; "") | capture("(?m)^feature-flag:\\s*`(?<flag>[^`]+)`$").flag) catch "" // "-"' \
      <<< "$pr")"

    if [[ -n "$sha" ]]; then
      # Beta tag analysis
      if ! beta_version="$(get_cached_value "$BETA_CACHE_FILE" "$sha" 2>/dev/null)"; then
        beta_version="$(map_version "$sha" "beta")"
        set_cached_value "$BETA_CACHE_FILE" "$sha" "$beta_version"
      fi

      # Release tag analysis
      if ! release_version="$(get_cached_value "$RELEASE_CACHE_FILE" "$sha" 2>/dev/null)"; then
        release_version="$(map_version "$sha" "release")"
        set_cached_value "$RELEASE_CACHE_FILE" "$sha" "$release_version"
      fi
    else
      beta_version="-"
      release_version="-"
    fi

    if [[ -n "$sha" ]]; then
      short_sha="${sha:0:7}"
      sha_md="[$short_sha](https://github.com/$OWNER/$REPO/commit/$sha)"
    else
      sha_md="-"
    fi

    beta_version_md="$(format_release_tag_md "$beta_version")"
    release_version_md="$(format_release_tag_md "$release_version")"
    markdown_row="| [#$number]($url) | $merged_at | $sha_md | $title_md | $feature_flag | $beta_version_md | $release_version_md |"

    case "$status" in
      Highlight)
        echo "$markdown_row" >> "$highlight_rows"
        ;;
      Include)
        echo "$markdown_row" >> "$include_rows"
        ;;
      Exclude)
        echo "$markdown_row" >> "$exclude_rows"
        ;;
      *)
        echo "$markdown_row" >> "$review_rows"
        ;;
    esac

    printf '%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s\n' \
      "$(escape_csv "$BRANCH")" \
      "$(escape_csv "$number")" \
      "$(escape_csv "$merged_at")" \
      "$(escape_csv "$author")" \
      "$(escape_csv "$title")" \
      "$(escape_csv "$status")" \
      "$(escape_csv "$feature_flag")" \
      "$(escape_csv "$beta_version")" \
      "$(escape_csv "$release_version")" \
      "$(escape_csv "$sha")" \
      "$(escape_csv "$url")" \
      "$(escape_csv "")" \
      >> "$CSV_OUT"
  done < <(jq -c '.[]' <<< "$sorted_prs_json")

  if [[ ! -s "$highlight_rows" && ! -s "$include_rows" && ! -s "$review_rows" && ! -s "$exclude_rows" ]]; then
    echo "_No reportable merged PRs in this range._" >> "$MD_OUT"
    echo >> "$MD_OUT"
  else
    append_status_section "Highlight" "$highlight_rows"
    append_status_section "Include" "$include_rows"
    append_status_section "Review" "$review_rows"
    append_excluded_section "$exclude_rows"
  fi
done

update_report_index

echo "Wrote Markdown report to $MD_OUT"
echo "Wrote CSV report to $CSV_OUT"
echo "Updated report index at $INDEX_OUT"
