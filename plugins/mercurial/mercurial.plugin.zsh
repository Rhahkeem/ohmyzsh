# aliases
alias hga='hg add'
alias hgc='hg commit'
alias hgca='hg commit --amend'
alias hgci='hg commit --interactive'
alias hgb='hg branch'
alias hgba='hg branches'
alias hgbk='hg bookmarks'
alias hgco='hg checkout'
alias hgd='hg diff'
alias hged='hg diffmerge'
alias hgp='hg push'
alias hgs='hg status'
alias hgsl='hg log --limit 20 --template "{node|short} | {date|isodatesec} | {author|person}: {desc|strip|firstline}\n" '
alias hgun='hg resolve --list'
# pull and update
alias hgi='hg incoming'
alias hgl='hg pull -u'
alias hglr='hg pull --rebase'
alias hgo='hg outgoing'
alias hglg='hg log --stat -v'
alias hglgp='hg log --stat  -p -v'

function in_hg() {
  if $(hg branch > /dev/null 2>&1); then
    echo 1
  fi
}

function hg_get_branch_name() {
  branch=`hg branch 2>/dev/null`
  if [ $? -eq 0 ]; then
    echo $branch
  fi
  unset branch
}

function hg_prompt_info {
  _DISPLAY=`hg branch 2>/dev/null`
  if [ $? -eq 0 ]; then
    echo "$ZSH_PROMPT_BASE_COLOR$ZSH_THEME_HG_PROMPT_PREFIX\
$ZSH_THEME_REPO_NAME_COLOR$_DISPLAY$ZSH_PROMPT_BASE_COLOR$ZSH_PROMPT_BASE_COLOR$(hg_dirty)$ZSH_THEME_HG_PROMPT_SUFFIX$ZSH_PROMPT_BASE_COLOR"
  fi
  unset _DISPLAY
}

function hg_dirty_choose {
  hg status -mar 2> /dev/null | command grep -Eq '^\s*[ACDIM!?L]'
  if [ $? -eq 0 ]; then
    if [ $pipestatus[-1] -eq 0 ]; then
      # Grep exits with 0 when "One or more lines were selected", return "dirty".
      echo $1
      return
    fi
  fi
  echo $2
}

function hg_dirty {
  hg_dirty_choose $ZSH_THEME_HG_PROMPT_DIRTY $ZSH_THEME_HG_PROMPT_CLEAN
}

function hgic() {
  hg incoming "$@" | grep "changeset" | wc -l
}

function hgoc() {
  hg outgoing "$@" | grep "changeset" | wc -l
}

# functions
function hg_root() {
  local dir="$PWD"
  while [[ "$dir" != "/" ]]; do
    if [[ -d "$dir/.hg" ]]; then
      echo "$dir"
      return 0
    fi
    dir="${dir:h}"
  done
  return 1
}

function in_hg() {
  hg_root >/dev/null
}

function hg_get_branch_name() {
  local dir
  if ! dir=$(hg_root); then
    return
  fi

  if [[ ! -f "$dir/.hg/branch" ]]; then
    echo default
    return
  fi

  echo "$(<"$dir/.hg/branch")"
}

function hg_get_bookmark_name() {
  local dir
  if ! dir=$(hg_root); then
    return
  fi

  if [[ ! -f "$dir/.hg/bookmarks.current" ]]; then
    return
  fi

  echo "$(<"$dir/.hg/bookmarks.current")"
}

function hg_prompt_info {
  local dir branch dirty
  if ! dir=$(hg_root); then
    return
  fi

  if [[ ! -f "$dir/.hg/branch" ]]; then
    branch=default
  else
    branch="$(<"$dir/.hg/branch")"
  fi

  dirty="$(hg_dirty)"

  echo "${ZSH_THEME_HG_PROMPT_PREFIX}${branch:gs/%/%%}${dirty}${ZSH_THEME_HG_PROMPT_SUFFIX}"
}

function hg_dirty {
  # Do nothing if clean / dirty settings aren't defined
  if [[ -z "$ZSH_THEME_HG_PROMPT_DIRTY" && -z "$ZSH_THEME_HG_PROMPT_CLEAN" ]]; then
    return
  fi

  # Check if there are modifications
  local hg_status
  if [[ "$DISABLE_UNTRACKED_FILES_DIRTY" = true ]]; then
    if ! hg_status="$(hg status -q 2>/dev/null)"; then
      return
    fi
  else
    if ! hg_status="$(hg status 2>/dev/null)"; then
      return
    fi
  fi

  # grep exits with 0 when dirty
  if command grep -Eq '^\s*[ACDIMR!?L].*$' <<< "$hg_status"; then
    echo $ZSH_THEME_HG_PROMPT_DIRTY
    return
  fi

  echo $ZSH_THEME_HG_PROMPT_CLEAN
}
