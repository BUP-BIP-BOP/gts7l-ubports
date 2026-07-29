# Vendor binary overrides

These replace files of the same path inside the Android container; the halium
overlay bind-mounts `/opt/halium-overlay/vendor/...` over the vendor partition
at boot.

## vndservicemanager

Samsung's own binary refuses every service registration on this port:

    E SELinux : Unknown class service_manager
    I vndservicemanager: display.qservice : getService has failed, permission denied.

No SELinux policy is loaded in the container (`androidboot.selinux=permissive`
only silences enforcement, it does not provide a policy), so the permission
check cannot resolve the `service_manager` class and the stock binary denies by
default. The Qualcomm composer then cannot publish `display.qservice`:

    E SDM : HWCSession::Init: Failed to acquire display.qservice
    E SDM : Cannot initialize composer

which restarts the composer service every five seconds, so Mir waits forever
for a hwcomposer and the screen never leaves the Samsung splash.

The binary here comes from the samsung-q2q port (Halium 11, same API level) and
skips that check.

## vaultkeeperd

Samsung's VaultKeeper daemon, shipped for the same reason the q2q port carries
it: the stock one interferes with services under an unlocked bootloader.
