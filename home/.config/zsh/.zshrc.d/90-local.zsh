if [[ "${OOODNAKOV_LOCAL_ENV_LOADED:-0}" != 1 && -f "$OOODNAKOV_CONFIG_HOME/local/env.zsh" ]]; then
  source "$OOODNAKOV_CONFIG_HOME/local/env.zsh"
fi
