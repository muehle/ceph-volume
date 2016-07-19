#!/bin/bash
set -e

: ${CLUSTER:=ceph}
: ${CEPH_CLUSTER_NETWORK:=${CEPH_PUBLIC_NETWORK}}
: ${CEPH_DAEMON:=${1}} # default daemon to first argument
: ${CEPH_GET_ADMIN_KEY:=0}
: ${HOSTNAME:=$(hostname -s)}
: ${MON_NAME:=${HOSTNAME}}
: ${NETWORK_AUTO_DETECT:=0}
: ${MDS_NAME:=mds-${HOSTNAME}}
: ${OSD_FORCE_ZAP:=0}
: ${OSD_JOURNAL_SIZE:=100}
: ${CRUSH_LOCATION:=root=default host=${HOSTNAME}}
: ${CEPHFS_CREATE:=0}
: ${CEPHFS_NAME:=cephfs}
: ${CEPHFS_DATA_POOL:=${CEPHFS_NAME}_data}
: ${CEPHFS_DATA_POOL_PG:=8}
: ${CEPHFS_METADATA_POOL:=${CEPHFS_NAME}_metadata}
: ${CEPHFS_METADATA_POOL_PG:=8}
: ${RGW_NAME:=${HOSTNAME}}
: ${RGW_ZONEGROUP:=}
: ${RGW_ZONE:=}
: ${RGW_CIVETWEB_PORT:=8080}
: ${RGW_REMOTE_CGI:=0}
: ${RGW_REMOTE_CGI_PORT:=9000}
: ${RGW_REMOTE_CGI_HOST:=0.0.0.0}
: ${RESTAPI_IP:=0.0.0.0}
: ${RESTAPI_PORT:=5000}
: ${RESTAPI_BASE_URL:=/api/v0.1}
: ${RESTAPI_LOG_LEVEL:=warning}
: ${RESTAPI_LOG_FILE:=/var/log/ceph/ceph-restapi.log}
: ${KV_TYPE:=none} # valid options: consul, etcd or none
: ${KV_IP:=127.0.0.1}
: ${KV_PORT:=4001} # PORT 8500 for Consul


: ${RBD_IMAGE:=image0}
: ${RBD_POOL:=rbd}
: ${RBD_OPTS:=rw}
: ${RBD_FS:=xfs}
: ${RBD_TARGET:=/mnt/rbd}

case "$KV_TYPE" in
   etcd|consul)
      source /config.kv.sh
      ;;
   *)
      source /config.static.sh
      ;;
esac

function check_config {
if [[ ! -e /etc/ceph/${CLUSTER}.conf ]]; then
  echo "ERROR- /etc/ceph/${CLUSTER}.conf must exist; get it from your existing mon"
  exit 1
fi
}

function get_admin_key {
   kviator --kvstore=${KV_TYPE} --client=${KV_IP}:${KV_PORT} ${KV_TLS} get ${CLUSTER_PATH}/adminKeyring > /etc/ceph/${CLUSTER}.client.admin.keyring
}

# ceph admin key exists or die
function check_admin_key {
if [[ ! -e /etc/ceph/${CLUSTER}.client.admin.keyring ]]; then
    echo "ERROR- /etc/ceph/${CLUSTER}.client.admin.keyring must exist; get it from your existing mon"
    exit 1
fi
}

# Map the rbd volume
function map {
	/usr/bin/rbd map ${RBD_IMAGE} --pool ${RBD_POOL} -o ${RBD_OPTS}
}

# Mount and wait for exit signal (after which, unmount and exit)
function mount {
	RBD_DEV=$1

	if [ -z $1 ]; then
		read RBD_DEV
	fi

	/mountWait -rbddev ${RBD_DEV} -fstype ${RBD_FS} -target ${RBD_TARGET} -o ${RBD_OPTS}
}

# Unmap rbd device
function unmap {
	/usr/bin/rbd unmap $( /usr/bin/rbd showmapped | grep -m 1 -E "^[0-9]{1,3}\s+${RBD_POOL}\s+${RBD_IMAGE}" | awk '{print $5}' )
}

get_admin_key
check_admin_key
get_config
check_config

case "$@" in
	"map" ) map;;
	"mount" ) mount;;
	"unmap" ) unmap;;
	* ) 
	RBD_DEV=$(map)
	mount $RBD_DEV
	;;
esac

