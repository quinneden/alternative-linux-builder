{
  kernel ? pkgsLinux.linux,
  makeInitrdNG,
  pkgsLinux,
  writeScript,
}:

let
  busyboxStatic = pkgsLinux.pkgsStatic.busybox;

  initrd = makeInitrdNG {
    compressor = "cat";
    contents = [
      {
        source = "${busyboxStatic}/bin/busybox";
        target = "/bin/busybox";
      }
      {
        source = "${pkgsLinux.iproute2}/bin/ip";
        target = "/bin/ip";
      }
      {
        source = "${pkgsLinux.jq}/bin/jq";
        target = "/bin/jq";
      }
      {
        source = "${pkgsLinux.kmod}/bin/modprobe";
        target = "/bin/modprobe";
      }
      {
        source = setupNetworkScript;
        target = "/bin/setup-network";
      }
      {
        source = writeBuilderInit;
        target = "/bin/write-builder-init";
      }
      {
        source = initrdInit;
        target = "/init";
      }
      {
        source = "${kernel.modules}/lib/modules";
        target = "/lib/modules";
      }
    ];
  };

  initrdInit =
    let
      rosettaMagic = "\\x7fELF\\x02\\x01\\x01\\x00\\x00\\x00\\x00\\x00\\x00\\x00\\x00\\x00\\x02\\x00\\x3e\\x00";
      rosettaMask = "\\xff\\xff\\xff\\xff\\xff\\xfe\\xfe\\x00\\xff\\xff\\xff\\xff\\xff\\xff\\xff\\xff\\xfe\\xff\\xff\\xff";
    in
    writeScript "initrd-init" ''
      #!/bin/busybox sh
      set -eux

      cleanup() {
        exec busybox poweroff -f
      }

      trap cleanup EXIT

      # FIXME: the clock is wrong/weird in the VM, enough that e.g. meson fails a build because it's more than 0.001 seconds in the future
      busybox date -u -s @"$(($(busybox date +%s) + 1))"

      busybox mkdir -p /mnt/root
      busybox mount -t tmpfs tmpfs /mnt/root

      busybox mkdir -p /mnt/root/root
      busybox mkdir -p /mnt/root/var/empty
      busybox chmod 555 /mnt/root/var/empty
      busybox mkdir -p /mnt/root/etc

      busybox cat >/mnt/root/etc/passwd <<EOF
      root:!:0:0:System administrator:/root:
      nixbld:x:30000:30000:Nix build user:/var/empty:
      EOF

      busybox cat >/mnt/root/etc/group <<EOF
      root:x:0:
      nixbld:x:30000:
      EOF

      busybox mkdir -p /mnt/root/proc
      busybox mount -t proc none /mnt/root/proc

      busybox mkdir -p /mnt/root/dev
      busybox mount -t devtmpfs devtmpfs /mnt/root/dev

      busybox mkdir -p /mnt/root/tmp
      busybox mount -t tmpfs tmpfs /mnt/root/tmp

      busybox mkdir -p /mnt/root/dev/shm
      busybox mount -t tmpfs tmpfs /mnt/root/dev/shm -o rw,nosuid,nodev

      busybox mkdir -p /mnt/root/bin
      busybox cp ${busyboxStatic}/bin/busybox /mnt/root/bin
      busybox ln -sf ./busybox /mnt/root/bin/sh

      ip link set lo up

      if ip link show eth0; then
        ip link set eth0 up
        busybox udhcpc -i eth0 -s /bin/setup-network
      fi

      modprobe virtiofs

      busybox mkdir -p /mnt/root/nix/store
      busybox mount -t virtiofs nix-store /mnt/root/nix/store

      busybox mkdir -p /mnt/root/build-root
      busybox mount -t virtiofs build-root /mnt/root/build-root

      busybox cp -r /mnt/root/build-root /mnt/root/build
      busybox chmod 777 /mnt/root/build

      BUILDER_JSON="/mnt/root/build-root/builder.json"

      if [[ ! -e "$BUILDER_JSON" ]]; then
        echo "Builder json instructions did not exist! Exiting."
        exit 1
      fi

      busybox mkdir -p /proc
      busybox mount -t proc none /proc

      system="$(jq -r .system "$BUILDER_JSON")"

      # setup rosetta if needed
      if [[ "$system" == "x86_64-linux" ]]; then
        busybox mount -t binfmt_misc none /proc/sys/fs/binfmt_misc
        busybox mkdir -p /rosetta
        busybox mount -t virtiofs rosetta /rosetta
        echo ":rosetta:M::${rosettaMagic}:${rosettaMask}:/rosetta/rosetta:POCF" > /proc/sys/fs/binfmt_misc/register
      fi

      # setup the builder that will run after we switch root
      builder="$(jq -r '.builder | @sh' "$BUILDER_JSON")"
      args="$(jq -r '.args | map(. | @sh) | join(" ")' "$BUILDER_JSON")"
      jq -r '.env | to_entries[] | "\(.key)=\(.value | @sh)"' "$BUILDER_JSON" > /mnt/root/execenv
      busybox chmod 400 /mnt/root/execenv

      # FIXME: preserve args as an array
      write-builder-init "$builder" "$args" > /mnt/root/init
      busybox chmod 500 /mnt/root/init

      # shut up the kernel
      echo 0 > /proc/sys/kernel/printk

      exec busybox switch_root -c /dev/console /mnt/root /init
    '';

  setupNetworkScript = writeScript "setup-network" ''
    #!/bin/busybox sh
    case "$1" in
        bound|renew)
            ip addr add $ip/$mask dev $interface
            [ -n "$router" ] && ip route add default via $router
            if [ -n "$dns" ]; then
              echo "nameserver $dns" > /mnt/root/etc/resolv.conf
            else
              echo "Didn't get DNS from DHCP... Networking will not work."
            fi
            ;;
        deconfig)
            ip addr flush dev $interface
            ;;
    esac
  '';

  writeBuilderInit = writeScript "write-builder-init" ''
    #!/bin/busybox sh
    set -eux

    builder="$1"
    args="$2"

    busybox cat <<EOF
    #!/bin/busybox env -i /bin/sh
    set -eux

    cleanup() {
      exec /bin/busybox poweroff -f
    }
    trap cleanup EXIT

    /bin/busybox rm /init
    /bin/busybox ln -s /proc/self/fd /dev/fd
    /bin/busybox ln -s /proc/self/fd/0 /dev/stdin
    /bin/busybox ln -s /proc/self/fd/1 /dev/stdout
    /bin/busybox ln -s /proc/self/fd/2 /dev/stderr

    cd /build

    /bin/busybox stty -onlcr

    set +x
    # tell Nix that it can start printing this as build output
    /bin/busybox printf '\2\n'

    set -a
    . /execenv
    set +a

    /bin/busybox rm /execenv

    set +e
    /bin/busybox setuidgid nixbld $builder $args < /dev/null
    echo \$? > /build-root/.exitcode

    /bin/busybox cp -r /build /build-root
    EOF
  '';
in

initrd.overrideAttrs (oldAttrs: {
  passthru = (oldAttrs.passthru or { }) // {
    inherit initrdInit writeBuilderInit;
  };
})
