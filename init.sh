#!/usr/bin/env bash

debian_packages=(
  'sudo'
  'git'
  'tmux'
  'vim'
  'ranger'
  'htop'
  'nmap'
  'ncdu'
  'iotop'
  'dnsutils'
  'rsync'
  'curl'
  'traceroute'
  'trippy'
)

fedora_packages=(
  'sudo'
  'git'
  'tmux'
  'vim'
  'ranger'
  'htop'
  'nmap'
  'ncdu'
  'iotop'
  'bind-utils'
  'rsync'
  'curl'
  'traceroute'
)

init_debian(){
  if ! command -v apt-get >/dev/null 2>&1
  then
      return 0
  fi

  sudo apt-get update --yes --ignore-missing

  sudo apt-get install "${debian_packages[@]}"
}

init_fedora(){
  if ! command -v dnf >/dev/null 2>&1
  then
      return 0
  fi

  sudo dnf install "${fedora_packages[@]}"
}

init_dotfiles() {

  if [[ -d "${HOME}/dotfiles" ]]; then
    echo "✔ dotfiles init-ed"
    return 0
  fi

  if ! command -v git >/dev/null 2>&1
  then
      echo "err: git could not be found" >&2
      return 1
  fi

  git clone https://github.com/Sarsoo/dotfiles.git "${HOME}/dotfiles"

  if [[ $? == 0 ]]; then
    "${HOME}/dotfiles/init.sh"
  else
    echo "err: failed to checkout dotfiles" >&2
    return 1
  fi
}

init_scripts() {

  if [[ -d "${HOME}/scripts" ]]; then
    echo "✔ scripts init-ed"
    return 0
  fi

  if ! command -v git >/dev/null 2>&1
  then
      echo "err: git could not be found" >&2
      return 1
  fi

  git clone https://github.com/Sarsoo/scripts.git "${HOME}/scripts"

  if [[ $? != 0 ]]; then
    echo "err: failed to checkout scripts" >&2
    return 1
  fi
}

# if (( $EUID == 0 )); then
#    echo "Don't run this as root..."
#    exit 1
# fi

if [[ -n "${SAR_PACKAGE_INSTALL}" ]]; then
  init_debian
  init_fedora
fi

init_dotfiles
init_scripts
