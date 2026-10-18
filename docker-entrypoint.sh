#!/bin/bash

# Set TZ if not provided with enviromental variable.
if [ -z "${TZ}" ]; then
  export TZ="$(cat /etc/timezone)"
else
  if [ ! -f "/usr/share/zoneinfo/${TZ}" ]; then
      echo "The timezone '${TZ}' is unavailable!"
      exit 1
  fi

  echo "${TZ}" > /etc/timezone
  ln -fs "/usr/share/zoneinfo/${TZ}" /etc/localtime
fi

# Set UID/GID if not provided with enviromental variable(s).
if [ -z "${DROPBOX_UID}" ]; then
  export DROPBOX_UID=$(/usr/bin/id -u dropbox)
  echo "DROPBOX_UID not specified, defaulting to dropbox user id (${DROPBOX_UID})"
fi

if [ -z "${DROPBOX_GID}" ]; then
  export DROPBOX_GID=$(/usr/bin/id -g dropbox)
  echo "DROPBOX_GID not specified, defaulting to dropbox user group id (${DROPBOX_GID})"
fi

# Look for existing group, if not found create dropbox with specified GID.
if [ -z "$(grep ":${DROPBOX_GID}:" /etc/group)" ]; then
  usermod -g users dropbox
  groupdel dropbox
  groupadd -g $DROPBOX_GID dropbox
fi

if [[ ! "${POLLING_INTERVAL}" =~ ^[0-9]+$ ]]; then
  echo "POLLING_INTERVAL not set to a valid number, defaulting to 5!"
  export POLLING_INTERVAL=5
fi

# Set dropbox account's UID/GID.
usermod -u ${DROPBOX_UID} -g ${DROPBOX_GID} --non-unique dropbox > /dev/null 2>&1

# Change ownership to dropbox account on all working folders.
if [[ $(echo "${SKIP_SET_PERMISSIONS:-false}" | tr '[:upper:]' '[:lower:]' | tr -d " ") == "true" ]]; then
  echo "Skipping permissions check, ensure the dropbox user owns all files!"
  chown ${DROPBOX_UID}:${DROPBOX_GID} /opt/dropbox
else
  chown -R ${DROPBOX_UID}:${DROPBOX_GID} /opt/dropbox
fi

# Change permissions on Dropbox folder
[[ -d /opt/dropbox/Dropbox ]] && chmod 755 /opt/dropbox/Dropbox

#  Dropbox did not shutdown properly? Remove files.
[ ! -e "/opt/dropbox/.dropbox/command_socket" ] || rm /opt/dropbox/.dropbox/command_socket
[ ! -e "/opt/dropbox/.dropbox/iface_socket" ]   || rm /opt/dropbox/.dropbox/iface_socket
[ ! -e "/opt/dropbox/.dropbox/unlink.db" ]      || rm /opt/dropbox/.dropbox/unlink.db
[ ! -e "/opt/dropbox/.dropbox/dropbox.pid" ]    || rm /opt/dropbox/.dropbox/dropbox.pid

# Dropbox has the nasty tendency to update itself without asking. A mode-0 ~/.dropbox-dist
# stops the daemon from updating itself; this lives in the /opt/dropbox volume, so it has
# to be (re-)created here rather than at build time.
if [[ ! -d /opt/dropbox/.dropbox-dist ]]; then
  install -dm0 /opt/dropbox/.dropbox-dist
fi

# Empty line
echo ""

# Set umask
umask 002

# Print timezone
echo "Using $(cat /etc/timezone) timezone ($(date +%H:%M:%S) local time)"

# Start Dropbox
echo "Starting dropboxd ($(cat /opt/dropbox-client/VERSION))..."
gosu dropbox "$@" & export DROPBOX_PID="$!"
trap "/bin/kill -SIGQUIT ${DROPBOX_PID}" INT

# Optionally start monitoring script
if [[ $(echo "${ENABLE_MONITORING:-false}" | tr '[:upper:]' '[:lower:]' | tr -d " ") == "true" ]]; then
  echo "Starting monitoring script..."
  gosu dropbox python3 /monitoring.py -i "${POLLING_INTERVAL}" -a "${MONITORING_ADDRESS}" -p "${MONITORING_PORT}" &
fi

# Wait a few seconds for the Dropbox daemon to start
sleep 5

# Dropbox likes to restart itself. In that case, the container will exit!
while kill -0 ${DROPBOX_PID} 2> /dev/null; do
  [ -d "/proc/${DROPBOX_PID}" ] && [ -f "/opt/dropbox/.dropbox/info.json" ] && gosu dropbox dropbox status
  /usr/bin/find /tmp/ -maxdepth 1 -type d -mtime +1 ! -path /tmp/ -exec rm -rf {} \;
  /bin/sleep ${POLLING_INTERVAL}
done
