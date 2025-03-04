# Migrate .zsh-update file to $ZSH_CACHE_DIR
if [[ -f ~/.zsh-update && ! -f "${ZSH_CACHE_DIR}/.zsh-update" ]]; then
  mv ~/.zsh-update "${ZSH_CACHE_DIR}/.zsh-update"
fi

# Get user's update preferences
#
# Supported update modes:
# - prompt (default): the user is asked before updating when it's time to update
# - auto: the update is performed automatically when it's time
# - reminder: a reminder is shown to the user when it's time to update
# - disabled: automatic update is turned off
zstyle -s ':omz:update' mode update_mode || update_mode=prompt

# Support old-style settings
[[ "$DISABLE_UPDATE_PROMPT" != true ]] || update_mode=auto
[[ "$DISABLE_AUTO_UPDATE" != true ]] || update_mode=disabled

# Cancel update if:
# - the automatic update is disabled.
# - the current user doesn't have write permissions nor owns the $ZSH directory.
# - git is unavailable on the system.
if [[ "$update_mode" = disabled ]] \
   || [[ ! -w "$ZSH" || ! -O "$ZSH" ]] \
   || ! command -v git &>/dev/null; then
  unset update_mode
  return
fi

function current_epoch() {
  zmodload zsh/datetime
  echo $(( EPOCHSECONDS / 60 / 60 / 24 ))
}

function is_update_available() {
  local branch
  branch=${"$(git -C "$ZSH" config --local oh-my-zsh.branch)":-master}

  local remote remote_url remote_repo
  remote=${"$(git -C "$ZSH" config --local oh-my-zsh.remote)":-origin}
  remote_url=$(git -C "$ZSH" config remote.$remote.url)

  local repo
  case "$remote_url" in
  https://github.com/*) repo=${${remote_url#https://github.com/}%.git} ;;
  git@github.com:*) repo=${${remote_url#git@github.com:}%.git} ;;
  *)
    # If the remote is not using GitHub we can't check for updates
    # Let's assume there are updates
    return 0 ;;
  esac

  # If the remote repo is not the official one, let's assume there are updates available
  [[ "$repo" = ohmyzsh/ohmyzsh ]] || return 0
  local api_url="https://api.github.com/repos/${repo}/commits/${branch}"

  # Get local and remote HEADs and compare them. If we can't get either assume there are updates
  local local_head remote_head
  local_head=$(git -C "$ZSH" rev-parse $branch 2>/dev/null) || return 0

  remote_head=$(curl -fsSL -H 'Accept: application/vnd.github.v3.sha' $api_url 2>/dev/null) \
  || remote_head=$(wget -O- --header='Accept: application/vnd.github.v3.sha' $api_url 2>/dev/null) \
  || remote_head=$(HTTP_ACCEPT='Accept: application/vnd.github.v3.sha' fetch -o - $api_url 2>/dev/null) \
  || return 0

  # Compare local and remote HEADs
  [[ "$local_head" != "$remote_head" ]]
}

function update_last_updated_file() {
  echo "LAST_EPOCH=$(current_epoch)" >! "${ZSH_CACHE_DIR}/.zsh-update"
}

function update_ohmyzsh() {
  if ZSH="$ZSH" zsh -f "$ZSH/tools/upgrade.sh" --interactive; then
    update_last_updated_file
  fi
}

function has_typed_input() {
  # Created by Philippe Troin <phil@fifi.org>
  # https://zsh.org/mla/users/2022/msg00062.html
  emulate -L zsh
  zmodload zsh/zselect

  # Back up stty settings prior to disabling canonical mode
  # Consider that no input can be typed if stty fails
  # (this might happen if stdin is not a terminal)
  local termios
  termios=$(stty --save 2>/dev/null) || return 1
  {
    # Disable canonical mode so that typed input counts
    # regardless of whether Enter was pressed
    stty -icanon

    # Poll stdin (fd 0) for data ready to be read
    zselect -t 0 -r 0
    return $?
  } always {
    # Restore stty settings
    stty $termios
  }
}

() {
  emulate -L zsh

  local epoch_target mtime option LAST_EPOCH

  # Remove lock directory if older than a day
  zmodload zsh/datetime
  zmodload -F zsh/stat b:zstat
  if mtime=$(zstat +mtime "$ZSH/log/update.lock" 2>/dev/null); then
    if (( (mtime + 3600 * 24) < EPOCHSECONDS )); then
      command rm -rf "$ZSH/log/update.lock"
    fi
  fi

  # Check for lock directory
  if ! command mkdir "$ZSH/log/update.lock" 2>/dev/null; then
    return
  fi

  # Remove lock directory on exit. `return $ret` is important for when trapping a SIGINT:
  #  The return status from the function is handled specially. If it is zero, the signal is
  #  assumed to have been handled, and execution continues normally. Otherwise, the shell
  #  will behave as interrupted except that the return status of the trap is retained.
  #  This means that for a CTRL+C, the trap needs to return the same exit status so that
  #  the shell actually exits what it's running.
  trap "
    ret=\$?
    unset update_mode
    unset -f current_epoch is_update_available update_last_updated_file update_ohmyzsh 2>/dev/null
    command rm -rf '$ZSH/log/update.lock'
    return \$ret
  " EXIT INT QUIT

  # Create or update .zsh-update file if missing or malformed
  if ! source "${ZSH_CACHE_DIR}/.zsh-update" 2>/dev/null || [[ -z "$LAST_EPOCH" ]]; then
    update_last_updated_file
    return
  fi

  # Number of days before trying to update again
  zstyle -s ':omz:update' frequency epoch_target || epoch_target=${UPDATE_ZSH_DAYS:-13}
  # Test if enough time has passed until the next update
  if (( ( $(current_epoch) - $LAST_EPOCH ) < $epoch_target )); then
    return
  fi

  # Check if there are updates available before proceeding
  if ! is_update_available; then
    return
  fi

  # Ask for confirmation before updating unless in auto mode
  if [[ "$update_mode" = auto ]]; then
    update_ohmyzsh
  else
    # input sink to swallow all characters typed before the prompt
    # and add a newline if there wasn't one after characters typed
    while read -t -k 1 option; do true; done
    [[ "$option" != ($'\n'|"") ]] && echo

    echo -n "[oh-my-zsh] Would you like to update? [Y/n] "
    read -r -k 1 option
    [[ "$option" != $'\n' ]] && echo
    case "$option" in
      [yY$'\n']) update_ohmyzsh ;;
      [nN]) update_last_updated_file ;;
    esac
  fi

  # Check if there are updates available before proceeding
  if ! is_update_available; then
    return
  fi

  # If in reminder mode or user has typed input, show reminder and exit
  if [[ "$update_mode" = reminder ]] || has_typed_input; then
    printf '\r\e[0K' # move cursor to first column and clear whole line
    echo "[oh-my-zsh] It's time to update! You can do that by running \`omz update\`"
    return 0
  fi

  # Don't ask for confirmation before updating if in auto mode
  if [[ "$update_mode" = auto ]]; then
    update_ohmyzsh
    return $?
  fi

  # Ask for confirmation and only update on 'y', 'Y' or Enter
  # Otherwise just show a reminder for how to update
  echo -n "[oh-my-zsh] Would you like to update? [Y/n] "
  read -r -k 1 option
  [[ "$option" = $'\n' ]] || echo
  case "$option" in
    [yY$'\n']) update_ohmyzsh ;;
    [nN]) update_last_updated_file ;&
    *) echo "[oh-my-zsh] You can update manually by running \`omz update\`" ;;
  esac
}

unset update_mode
unset -f current_epoch is_update_available update_last_updated_file update_ohmyzsh
