#!/bin/bash

userinstall=no
steamcmd_user=
showusage=no

while [ -n "$1" ]; do
  case "$1" in
    --me)
      userinstall=yes
      steamcmd_user="--me"
    ;;
    -h|--help)
      showusage=yes
      break
    ;;
    --prefix=*)
      PREFIX="${1#--prefix=}"
    ;;
    --prefix)
      PREFIX="$2"
      shift
    ;;
    --exec-prefix=*)
      EXECPREFIX="${1#--exec-prefix=}"
    ;;
    --exec-prefix)
      EXECPREFIX="$2"
      shift
    ;;
    --install-root=*)
      INSTALL_ROOT="${1#--install-root=}"
    ;;
    --install-root)
      INSTALL_ROOT="$2"
      shift
    ;;
    --bindir=*)
      BINDIR="${1#--bindir=}"
    ;;
    --bindir)
      BINDIR="$2"
      shift
    ;;
    -*)
      echo "Invalid option '$1'"
      showusage=yes
      break;
    ;;
    *)
      if [ -n "$steamcmd_user" ]; then
        echo "Multiple users specified"
        showusage=yes
        break;
      elif getent passwd "$1" >/dev/null 2>&1; then
        steamcmd_user="$1"
      else
        echo "Invalid user '$1'"
        showusage=yes
        break;
      fi
    ;;
  esac
  shift
done

if [ "$userinstall" == "yes" -a "$UID" -eq 0 ]; then
  echo "Refusing to perform user-install as root"
  showusage=yes
fi

if [ "$showusage" == "no" -a -z "$steamcmd_user" ]; then
  echo "No user specified"
  showusage=yes
fi

if [ "$userinstall" == "yes" ]; then
  PREFIX="${PREFIX:-${HOME}}"
  EXECPREFIX="${EXECPREFIX:-${PREFIX}}"
else
  PREFIX="${PREFIX:-/usr/local}"
  EXECPREFIX="${EXECPREFIX:-${PREFIX}}"
fi

BINDIR="${BINDIR:-${EXECPREFIX}/bin}"

if [ "$showusage" == "yes" ]; then
    echo "Usage: ./install.sh {<user>|--me} [OPTIONS]"
    echo "You must specify your system steam user who own steamcmd directory to install ARK Tools."
    echo "Specify the special used '--me' to perform a user-install."
    echo
    echo "<user>          The user arkmanager should be run as"
    echo
    echo "Option          Description"
    echo "--help, -h      Show this help text"
    echo "--me            Perform a user-install"
    echo "--prefix        Specify the prefix under which to install arkmanager"
    echo "                [PREFIX=${PREFIX}]"
    echo "--exec-prefix   Specify the prefix under which to install executables"
    echo "                [EXECPREFIX=${EXECPREFIX}]"
    echo "--install-root  Specify the staging directory in which to perform the install"
    echo "                [INSTALL_ROOT=${INSTALL_ROOT}]"
    echo "--bindir        Specify the directory under which to install executables"
    echo "                [BINDIR=${BINDIR}]"
    exit 1
fi

if [ "$userinstall" == "yes" ]; then
    # Copy arkmanager to ~/bin
    mkdir -p "${INSTALL_ROOT}${BINDIR}"
    cp arkmanager "${INSTALL_ROOT}${BINDIR}/arkmanager"
    chmod +x "${INSTALL_ROOT}${BINDIR}/arkmanager"

    # Create a folder in ~/logs to let Ark tools write its own log files
    mkdir -p "${INSTALL_ROOT}${PREFIX}/logs/arktools"

    # Copy arkmanager.cfg to ~/.arkmanager.cfg if it doesn't already exist
    if [ -f "${INSTALL_ROOT}${PREFIX}/.arkmanager.cfg" ]; then
      cp -n arkmanager.cfg "${INSTALL_ROOT}${PREFIX}/.arkmanager.cfg.NEW"
      sed -i "s|^steamcmd_user=\"steam\"|steamcmd_user=\"--me\"|;s|\"/home/steam|\"${PREFIX}|;s|/var/log/arktools|${PREFIX}/logs/arktools|" "${INSTALL_ROOT}${PREFIX}/.arkmanager.cfg.NEW"
      echo "A previous version of ARK Server Tools was detected in your system, your old configuration was not overwritten. You may need to manually update it."
      echo "A copy of the new configuration file was included in '${INSTALL_ROOT}${PREFIX}/.arkmanager.cfg.NEW'. Make sure to review any changes and update your config accordingly!"
      exit 2
    else
      cp -n arkmanager.cfg "${INSTALL_ROOT}${PREFIX}/.arkmanager.cfg"
      sed -i "s|^steamcmd_user=\"steam\"|steamcmd_user=\"--me\"|;s|\"/home/steam|\"${PREFIX}|;s|/var/log/arktools|${PREFIX}/logs/arktools|" "${INSTALL_ROOT}${PREFIX}/.arkmanager.cfg"
    fi
else
    # Copy arkmanager to /usr/bin and set permissions
    cp arkmanager "${INSTALL_ROOT}${BINDIR}/arkmanager"
    chmod +x "${INSTALL_ROOT}${BINDIR}/arkmanager"

    # Copy arkdaemon to /etc/init.d ,set permissions and add it to boot
    if [ -f /lib/lsb/init-functions ]; then
      # on debian 8, sysvinit and systemd are present. If systemd is available we use it instead of sysvinit
      if [ -f /etc/systemd/system.conf ]; then   # used by systemd
        mkdir -p "${INSTALL_ROOT}${EXECPREFIX}/libexec/arkmanager"
        cp lsb/arkdaemon "${INSTALL_ROOT}${EXECPREFIX}/libexec/arkmanager/arkmanager.init"
        chmod +x "${INSTALL_ROOT}${EXECPREFIX}/libexec/arkmanager/arkmanager.init"
        cp systemd/arkdeamon.service "${INSTALL_ROOT}/etc/systemd/system/arkmanager.service"
        sed -i "s|=/usr/|=${EXECPREFIX}/|" "${INSTALL_ROOT}/etc/systemd/system/arkmanager.service"
        sed -i "s@^DAEMON=\"/usr/bin/@DAEMON=\"${BINDIR}/@" "${INSTALL_ROOT}${EXECPREFIX}/libexec/arkmanager/arkmanager.init"
        if [ -z "${INSTALL_ROOT}" ]; then
          systemctl daemon-reload
          systemctl enable arkmanager.service
          echo "Ark server will now start on boot, if you want to remove this feature run the following line"
          echo "systemctl disable arkmanager.service"
	fi
      else  # systemd not present, so use sysvinit
        cp lsb/arkdaemon "${INSTALL_ROOT}/etc/init.d/arkmanager"
        chmod +x "${INSTALL_ROOT}/etc/init.d/arkmanager"
        sed -i "s|^DAEMON=\"/usr/bin/|DAEMON=\"${BINDIR}/|" "${INSTALL_ROOT}/etc/init.d/arkmanager"
        # add to startup if the system use sysinit
        if [ -x /usr/sbin/update-rc.d -a -z "${INSTALL_ROOT}" ]; then
          update-rc.d arkmanager defaults
          echo "Ark server will now start on boot, if you want to remove this feature run the following line"
          echo "update-rc.d -f arkmanager remove"
        fi
      fi
    elif [ -f /etc/rc.d/init.d/functions ]; then
      # on RHEL 7, sysvinit and systemd are present. If systemd is available we use it instead of sysvinit
      if [ -f /etc/systemd/system.conf ]; then   # used by systemd
        mkdir -p "${INSTALL_ROOT}${EXECPREFIX}/libexec/arkmanager"
        cp redhat/arkdaemon "${INSTALL_ROOT}${EXECPREFIX}/libexec/arkmanager/arkmanager.init"
        chmod +x "${INSTALL_ROOT}${EXECPREFIX}/libexec/arkmanager/arkmanager.init"
        cp systemd/arkdeamon.service "${INSTALL_ROOT}/etc/systemd/system/arkmanager.service"
        sed -i "s|=/usr/|=${EXECPREFIX}/|" "${INSTALL_ROOT}/etc/systemd/system/arkmanager.service"
        sed -i "s@^DAEMON=\"/usr/bin/@DAEMON=\"${BINDIR}/@" "${INSTALL_ROOT}${EXECPREFIX}/libexec/arkmanager/arkmanager.init"
        if [ -z "${INSTALL_ROOT}" ]; then
          systemctl daemon-reload
          systemctl enable arkmanager.service
          echo "Ark server will now start on boot, if you want to remove this feature run the following line"
          echo "systemctl disable arkmanager.service"
        fi
      else # systemd not preset, so use sysvinit
        cp redhat/arkdaemon "${INSTALL_ROOT}/etc/rc.d/init.d/arkmanager"
        chmod +x "${INSTALL_ROOT}/etc/rc.d/init.d/arkmanager"
        sed -i "s@^DAEMON=\"/usr/bin/@DAEMON=\"${BINDIR}/@" "${INSTALL_ROOT}/etc/rc.d/init.d/arkmanager"
        if [ -x /sbin/chkconfig -a -z "${INSTALL_ROOT}" ]; then
          chkconfig --add arkmanager
          echo "Ark server will now start on boot, if you want to remove this feature run the following line"
          echo "chkconfig arkmanager off"
        fi
      fi
    elif [ -f /sbin/runscript ]; then
      cp openrc/arkdaemon "${INSTALL_ROOT}/etc/init.d/arkmanager"
      chmod +x "${INSTALL_ROOT}/etc/init.d/arkmanager"
      sed -i "s@^DAEMON=\"/usr/bin/@DAEMON=\"${BINDIR}/@" "${INSTALL_ROOT}/etc/init.d/arkmanager"
      if [ -x /sbin/rc-update -a -z "${INSTALL_ROOT}" ]; then
        rc-update add arkmanager default
        echo "Ark server will now start on boot, if you want to remove this feature run the following line"
        echo "rc-update del arkmanager default"
      fi
    elif [ -f /etc/systemd/system.conf ]; then   # used by systemd
      mkdir -p "${INSTALL_ROOT}${EXECPREFIX}/libexec/arkmanager"
      cp systemd/arkdaemon.init "${INSTALL_ROOT}${EXECPREFIX}/libexec/arkmanager/arkmanager.init"
      chmod +x "${INSTALL_ROOT}${EXECPREFIX}/libexec/arkmanager/arkmanager.init"
      cp systemd/arkdeamon.service "${INSTALL_ROOT}/etc/systemd/system/arkmanager.service"
      sed -i "s|=/usr/|=${EXECPREFIX}/|" "${INSTALL_ROOT}/etc/systemd/system/arkmanager.service"
      sed -i "s@^DAEMON=\"/usr/bin/@DAEMON=\"${BINDIR}/@" "${INSTALL_ROOT}${EXECPREFIX}/libexec/arkmanager/arkmanager.init"
      if [ -z "${INSTALL_ROOT}" ]; then
        systemctl enable arkmanager.service
        echo "Ark server will now start on boot, if you want to remove this feature run the following line"
        echo "systemctl disable arkmanager.service"
      fi
    fi

    # Create a folder in /var/log to let Ark tools write its own log files
    mkdir -p "${INSTALL_ROOT}/var/log/arktools"
    chown "$1" "${INSTALL_ROOT}/var/log/arktools"

    # Copy arkmanager.cfg inside linux configuation folder if it doesn't already exists
    mkdir -p "${INSTALL_ROOT}/etc/arkmanager"
    if [ -f "${INSTALL_ROOT}/etc/arkmanager/arkmanager.cfg" ]; then
      cp -n arkmanager.cfg "${INSTALL_ROOT}/etc/arkmanager/arkmanager.cfg.NEW"
      chown "$1" "${INSTALL_ROOT}/etc/arkmanager/arkmanager.cfg.NEW"
      echo "A previous version of ARK Server Tools was detected in your system, your old configuration was not overwritten. You may need to manually update it."
      echo "A copy of the new configuration file was included in /etc/arkmanager. Make sure to review any changes and update your config accordingly!"
      exit 2
    else
      cp -n arkmanager.cfg "${INSTALL_ROOT}/etc/arkmanager/arkmanager.cfg"
      chown "$1" "${INSTALL_ROOT}/etc/arkmanager/arkmanager.cfg"
      sed -i "s|^steamcmd_user=\"steam\"|steamcmd_user=\"$1\"|;s|\"/home/steam|\"/home/$1|" "${INSTALL_ROOT}/etc/arkmanager/arkmanager.cfg"
    fi
fi

exit 0
