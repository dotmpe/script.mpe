! "${VERBOSE:-false}" || ! "${DEBUG:-false}" ||
  $LOG info :env "Env (dir) loading..."

# XXX: .env to sh?

. ~/.local/etc/profile.d/_local.sh

#true "${ENV:="dev"}"
APP=us-bin.mpe/0.0.4-dev
PACK_ID=us-bin
